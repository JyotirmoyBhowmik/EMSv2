<#
.SYNOPSIS
    PostgreSQL database connection and data access module for EMS

.DESCRIPTION
    Provides functions for connecting to PostgreSQL and executing queries
    Uses Npgsql .NET driver for efficient connection pooling
    
.NOTES
    Author: Enterprise IT Team
    Version: 1.0
    Requires: Npgsql NuGet package
#>

# Import required assemblies
$NpgsqlPath = Join-Path $PSScriptRoot "..\..\Lib\Npgsql.dll"

if (Test-Path $NpgsqlPath) {
    Add-Type -Path $NpgsqlPath
}
else {
    Write-Warning "Npgsql.dll not found. Please install: Install-Package Npgsql -Destination .\Lib\"
}

# Module-level connection string cache
$script:ConnectionString = $null

#region Connection Management

function Initialize-PostgreSQLConnection {
    <#
    .SYNOPSIS
        Initializes PostgreSQL connection string from configuration
    
    .PARAMETER Config
        Configuration object containing database settings
    
    .EXAMPLE
        Initialize-PostgreSQLConnection -Config $Global:Config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )
    
    try {
        $dbConfig = $Config.Database
        
        # Build connection string
        $connString = New-Object System.Text.StringBuilder
        [void]$connString.Append("Host=$($dbConfig.Host);")
        [void]$connString.Append("Port=$($dbConfig.Port);")
        [void]$connString.Append("Database=$($dbConfig.DatabaseName);")
        [void]$connString.Append("Username=$($dbConfig.Username);")
        
        # Handle password (from config or secure store)
        if ($dbConfig.Password) {
            [void]$connString.Append("Password=$($dbConfig.Password);")
        }
        elseif ($dbConfig.PasswordSecure) {
            $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($dbConfig.PasswordSecure)
            )
            [void]$connString.Append("Password=$plainPassword;")
        }
        
        # Additional settings
        [void]$connString.Append("Pooling=true;")
        [void]$connString.Append("Minimum Pool Size=1;")
        if ($dbConfig.ConnectionPoolSize) {
            [void]$connString.Append("Maximum Pool Size=$($dbConfig.ConnectionPoolSize);")
        }
        else {
            [void]$connString.Append("Maximum Pool Size=20;")
        }
        [void]$connString.Append("Timeout=30;")
        
        if ($dbConfig.UseSSL) {
            [void]$connString.Append("SSL Mode=Require;")
        }
        
        $script:ConnectionString = $connString.ToString()
        
        Write-EMSLog -Message "PostgreSQL connection initialized: $($dbConfig.Host):$($dbConfig.Port)/$($dbConfig.DatabaseName)" -Severity 'Info'
        return $true
    }
    catch {
        Write-EMSLog -Message "Failed to initialize PostgreSQL connection: $_" -Severity 'Error'
        return $false
    }
}

function Test-PostgreSQLConnection {
    <#
    .SYNOPSIS
        Tests PostgreSQL database connectivity
    
    .EXAMPLE
        Test-PostgreSQLConnection
    #>
    [CmdletBinding()]
    param()
    
    if (!$script:ConnectionString) {
        Write-Warning "Connection string not initialized. Call Initialize-PostgreSQLConnection first."
        return $false
    }
    
    try {
        $conn = New-Object Npgsql.NpgsqlConnection($script:ConnectionString)
        $conn.Open()
        
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "SELECT version()"
        $version = $cmd.ExecuteScalar()
        
        $conn.Close()
        $conn.Dispose()
        
        Write-EMSLog -Message "PostgreSQL connection successful: $version" -Severity 'Success'
        return $true
    }
    catch {
        Write-EMSLog -Message "PostgreSQL connection test failed: $_" -Severity 'Error'
        return $false
    }
}

#endregion

#region Query Execution

function Invoke-PGQuery {
    <#
    .SYNOPSIS
        Executes a PostgreSQL query and returns results
    
    .PARAMETER Query
        SQL query to execute
    
    .PARAMETER Parameters
        Hashtable of parameters for parameterized queries
    
    .PARAMETER NonQuery
        Switch to execute non-query commands (INSERT, UPDATE, DELETE)
    
    .EXAMPLE
        $results = Invoke-PGQuery -Query "SELECT * FROM users WHERE is_active = @active" -Parameters @{active = $true}
    
    .EXAMPLE
        $rowsAffected = Invoke-PGQuery -Query "UPDATE users SET last_login = NOW() WHERE user_id = @id" -Parameters @{id = 1} -NonQuery
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Query,
        
        [hashtable]$Parameters = @{},
        
        [switch]$NonQuery
    )
    
    if (!$script:ConnectionString) {
        throw "Connection string not initialized. Call Initialize-PostgreSQLConnection first."
    }
    
    $conn = $null
    $cmd = $null
    $reader = $null
    
    try {
        # Create connection
        $conn = New-Object Npgsql.NpgsqlConnection($script:ConnectionString)
        $conn.Open()
        
        # Create command
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = 60
        
        # Add parameters
        foreach ($key in $Parameters.Keys) {
            $param = $cmd.Parameters.AddWithValue($key, $Parameters[$key])
            if ($null -eq $Parameters[$key]) {
                $param.Value = [DBNull]::Value
            }
        }
        
        if ($NonQuery) {
            # Execute non-query (INSERT, UPDATE, DELETE)
            $rowsAffected = $cmd.ExecuteNonQuery()
            return $rowsAffected
        }
        else {
            # Execute query and read results
            $reader = $cmd.ExecuteReader()
            $results = @()
            
            while ($reader.Read()) {
                $row = @{}
                for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                    $columnName = $reader.GetName($i)
                    $value = $reader.GetValue($i)
                    
                    # Handle DBNull
                    if ($value -is [DBNull]) {
                        $value = $null
                    }
                    
                    $row[$columnName] = $value
                }
                $results += [PSCustomObject]$row
            }
            
            return $results
        }
    }
    catch {
        Write-EMSLog -Message "PostgreSQL query error: $_" -Severity 'Error'
        Write-EMSLog -Message "Query: $Query" -Severity 'Error'
        throw
    }
    finally {
        if ($reader) { $reader.Close(); $reader.Dispose() }
        if ($cmd) { $cmd.Dispose() }
        if ($conn) { $conn.Close(); $conn.Dispose() }
    }
}

function Invoke-PGTransaction {
    <#
    .SYNOPSIS
        Executes multiple queries in a transaction
    
    .PARAMETER ScriptBlock
        Script block containing queries to execute
    
    .EXAMPLE
        Invoke-PGTransaction {
            Invoke-PGQuery -Query "INSERT INTO users (username) VALUES (@name)" -Parameters @{name = "jsmith"} -NonQuery
            Invoke-PGQuery -Query "INSERT INTO audit_logs (username, action) VALUES (@name, 'UserCreated')" -Parameters @{name = "jsmith"} -NonQuery
        }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )
    
    $conn = $null
    $transaction = $null
    
    try {
        $conn = New-Object Npgsql.NpgsqlConnection($script:ConnectionString)
        $conn.Open()
        $transaction = $conn.BeginTransaction()
        
        # Execute script block
        & $ScriptBlock
        
        $transaction.Commit()
        Write-EMSLog -Message "Transaction committed successfully" -Severity 'Info'
    }
    catch {
        if ($transaction) {
            $transaction.Rollback()
            Write-EMSLog -Message "Transaction rolled back due to error: $_" -Severity 'Error'
        }
        throw
    }
    finally {
        if ($transaction) { $transaction.Dispose() }
        if ($conn) { $conn.Close(); $conn.Dispose() }
    }
}

#endregion

#region User Management

function Get-EMSUser {
    <#
    .SYNOPSIS
        Retrieves user from database
    
    .PARAMETER Username
        Username to retrieve
    
    .PARAMETER UserId
        User ID to retrieve
    
    .EXAMPLE
        $user = Get-EMSUser -Username "CORP\jsmith"
    #>
    [CmdletBinding()]
    param(
        [Parameter(ParameterSetName = 'ByUsername')]
        [string]$Username,
        
        [Parameter(ParameterSetName = 'ById')]
        [int]$UserId
    )
    
    try {
        if ($Username) {
            $query = "SELECT * FROM users WHERE username = @username"
            $params = @{ username = $Username }
        }
        else {
            $query = "SELECT * FROM users WHERE user_id = @userid"
            $params = @{ userid = $UserId }
        }
        
        $result = Invoke-PGQuery -Query $query -Parameters $params
        return $result | Select-Object -First 1
    }
    catch {
        Write-EMSLog -Message "Error retrieving user: $_" -Severity 'Error'
        return $null
    }
}

function New-EMSUser {
    <#
    .SYNOPSIS
        Creates new user in database
    
    .EXAMPLE
        New-EMSUser -Username "CORP\jsmith" -DisplayName "John Smith" -Role "operator"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [string]$Domain,
        [string]$DisplayName,
        [string]$Email,
        [ValidateSet('admin', 'operator', 'viewer')]
        [string]$Role = 'viewer'
    )
    
    try {
        $query = @"
INSERT INTO users (username, domain, display_name, email, role)
VALUES (@username, @domain, @displayname, @email, @role)
RETURNING user_id
"@
        
        $params = @{
            username    = $Username
            domain      = $Domain
            displayname = $DisplayName
            email       = $Email
            role        = $Role
        }
        
        $result = Invoke-PGQuery -Query $query -Parameters $params
        
        Write-EMSLog -Message "Created user: $Username (ID: $($result.user_id))" -Severity 'Success'
        return $result.user_id
    }
    catch {
        Write-EMSLog -Message "Error creating user: $_" -Severity 'Error'
        throw
    }
}

function Update-EMSUserLogin {
    <#
    .SYNOPSIS
        Updates user's last login timestamp
    
    .EXAMPLE
        Update-EMSUserLogin -UserId 1
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$UserId
    )
    
    try {
        $query = "UPDATE users SET last_login = NOW(), failed_login_attempts = 0 WHERE user_id = @userid"
        $rowsAffected = Invoke-PGQuery -Query $query -Parameters @{ userid = $UserId } -NonQuery
        
        return $rowsAffected -gt 0
    }
    catch {
        Write-EMSLog -Message "Error updating user login: $_" -Severity 'Error'
        return $false
    }
}

#endregion

#region Scan Results

function Save-ScanResult {
    <#
    .SYNOPSIS
        Saves scan result to database
    
    .PARAMETER ScanData
        Scan result object from DataFetcher
    
    .EXAMPLE
        Save-ScanResult -ScanData $scanResult
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ScanData,
        
        [int]$InitiatedBy
    )
    
    try {
        # Insert main scan result
        $query = @"
INSERT INTO scan_results 
    (hostname, ip_address, user_id_resolved, initiated_by, scan_timestamp, 
     health_score, topology, status, execution_time_seconds, 
     critical_count, warning_count, info_count, scan_type)
VALUES 
    (@hostname, @ip, @userid, @initiatedby, @timestamp, 
     @health, @topology, @status, @exectime,
     @critical, @warning, @info, @scantype)
RETURNING scan_id
"@
        
        $params = @{
            hostname    = $ScanData.Hostname
            ip          = $ScanData.IPAddress
            userid      = $ScanData.UserID
            initiatedby = $InitiatedBy
            timestamp   = if ($ScanData.ScanTimestamp) { $ScanData.ScanTimestamp } else { Get-Date }
            health      = $ScanData.HealthScore
            topology    = $ScanData.Topology
            status      = 'completed'
            exectime    = $ScanData.ExecutionTimeSeconds
            critical    = ($ScanData.Diagnostics | Where-Object { $_.Severity -eq 'Critical' }).Count
            warning     = ($ScanData.Diagnostics | Where-Object { $_.Severity -eq 'Warning' }).Count
            info        = ($ScanData.Diagnostics | Where-Object { $_.Severity -eq 'Info' }).Count
            scantype    = 'full'
        }
        
        $result = Invoke-PGQuery -Query $query -Parameters $params
        $scanId = $result.scan_id
        
        # Insert diagnostic details
        if ($ScanData.Diagnostics) {
            foreach ($diagnostic in $ScanData.Diagnostics) {
                Save-DiagnosticDetail -ScanId $scanId -ScanTimestamp $params.timestamp -Diagnostic $diagnostic
            }
        }
        
        Write-EMSLog -Message "Saved scan result for $($ScanData.Hostname) (Scan ID: $scanId)" -Severity 'Success'
        return $scanId
    }
    catch {
        Write-EMSLog -Message "Error saving scan result: $_" -Severity 'Error'
        throw
    }
}

function Save-DiagnosticDetail {
    <#
    .SYNOPSIS
        Saves individual diagnostic detail
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [long]$ScanId,
        
        [Parameter(Mandatory)]
        [datetime]$ScanTimestamp,
        
        [Parameter(Mandatory)]
        [object]$Diagnostic
    )
    
    try {
        $query = @"
INSERT INTO diagnostic_details 
    (scan_id, scan_timestamp, category, subcategory, severity, 
     check_name, status, message, details, remediation_available)
VALUES 
    (@scanid, @timestamp, @category, @subcategory, @severity,
     @checkname, @status, @message, @details::jsonb, @remediation)
"@
        
        # Convert details to JSON
        $detailsJson = $null
        if ($Diagnostic.Details) {
            $detailsJson = $Diagnostic.Details | ConvertTo-Json -Compress -Depth 5
        }
        
        $params = @{
            scanid      = $ScanId
            timestamp   = $ScanTimestamp
            category    = $Diagnostic.Category
            subcategory = $Diagnostic.SubCategory
            severity    = $Diagnostic.Severity
            checkname   = $Diagnostic.CheckName
            status      = $Diagnostic.Status
            message     = $Diagnostic.Message
            details     = $detailsJson
            remediation = if ($Diagnostic.RemediationAvailable) { $Diagnostic.RemediationAvailable } else { $false }
        }
        
        Invoke-PGQuery -Query $query -Parameters $params -NonQuery | Out-Null
    }
    catch {
        Write-EMSLog -Message "Error saving diagnostic detail: $_" -Severity 'Error'
    }
}

function Get-ScanResults {
    <#
    .SYNOPSIS
        Retrieves scan results with filtering and pagination
    
    .PARAMETER Limit
        Maximum number of results to return
    
    .PARAMETER Offset
        Number of results to skip (for pagination)
    
    .PARAMETER Hostname
        Filter by hostname
    
    .PARAMETER HealthScoreMin
        Minimum health score filter
    
    .EXAMPLE
        $results = Get-ScanResults -Limit 50 -Offset 0
    #>
    [CmdletBinding()]
    param(
        [int]$Limit = 100,
        [int]$Offset = 0,
        [string]$Hostname,
        [int]$HealthScoreMin,
        [int]$DaysBack = 30
    )
    
    try {
        $query = @"
SELECT scan_id, hostname, ip_address, user_id_resolved, scan_timestamp,
       health_score, topology, status, execution_time_seconds,
       critical_count, warning_count, info_count
FROM scan_results
WHERE scan_timestamp > NOW() - INTERVAL '$DaysBack days'
"@
        
        $params = @{}
        
        if ($Hostname) {
            $query += " AND hostname ILIKE @hostname"
            $params['hostname'] = "%$Hostname%"
        }
        
        if ($HealthScoreMin) {
            $query += " AND health_score >= @minscore"
            $params['minscore'] = $HealthScoreMin
        }
        
        $query += " ORDER BY scan_timestamp DESC LIMIT @limit OFFSET @offset"
        $params['limit'] = $Limit
        $params['offset'] = $Offset
        
        $results = Invoke-PGQuery -Query $query -Parameters $params
        return $results
    }
    catch {
        Write-EMSLog -Message "Error retrieving scan results: $_" -Severity 'Error'
        return @()
    }
}

#endregion

#region Dashboard Statistics

function Get-DashboardStats {
    <#
    .SYNOPSIS
        Retrieves dashboard statistics from materialized view
    
    .EXAMPLE
        $stats = Get-DashboardStats
    #>
    [CmdletBinding()]
    param()
    
    try {
        # Refresh materialized view first
        Invoke-PGQuery -Query "REFRESH MATERIALIZED VIEW dashboard_statistics" -NonQuery | Out-Null
        
        # Retrieve stats
        $stats = Invoke-PGQuery -Query "SELECT * FROM dashboard_statistics"
        return $stats | Select-Object -First 1
    }
    catch {
        Write-EMSLog -Message "Error retrieving dashboard stats: $_" -Severity 'Error'
        return $null
    }
}

#endregion

#region Audit Logging

function Write-AuditLog {
    <#
    .SYNOPSIS
        Writes audit log entry to database
    
    .PARAMETER Action
        Action performed (Login, Logout, ScanInitiated, etc.)
    
    .PARAMETER User
        Username who performed action
    
    .PARAMETER Target
        Target of the action (hostname, etc.)
    
    .PARAMETER Result
        Result of action (Success, Failed, Unauthorized)
    
    .EXAMPLE
        Write-AuditLog -Action 'Login' -User 'CORP\jsmith' -Result 'Success'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Action,
        
        [Parameter(Mandatory)]
        [string]$User,
        
        [string]$Target,
        
        [ValidateSet('Success', 'Failed', 'Unauthorized')]
        [string]$Result = 'Success',
        
        [string]$IPAddress,
        [hashtable]$Details,
        [ValidateSet('Low', 'Medium', 'High', 'Critical')]
        [string]$RiskLevel = 'Low'
    )
    
    try {
        # Get user ID
        $dbUser = Get-EMSUser -Username $User
        $userId = $dbUser.user_id
        
        # Convert details to JSON
        $detailsJson = $null
        if ($Details) {
            $detailsJson = $Details | ConvertTo-Json -Compress
        }
        
        $query = @"
INSERT INTO audit_logs 
    (user_id, username, action, target, result, ip_address, details, risk_level)
VALUES 
    (@userid, @username, @action, @target, @result, @ip, @details::jsonb, @risk)
"@
        
        $params = @{
            userid   = $userId
            username = $User
            action   = $Action
            target   = $Target
            result   = $Result
            ip       = $IPAddress
            details  = $detailsJson
            risk     = $RiskLevel
        }
        
        Invoke-PGQuery -Query $query -Parameters $params -NonQuery | Out-Null
    }
    catch {
        # Don't throw on audit log errors to avoid breaking main workflow
        Write-EMSLog -Message "Error writing audit log: $_" -Severity 'Error'
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Initialize-PostgreSQLConnection',
    'Test-PostgreSQLConnection',
    'Invoke-PGQuery',
    'Invoke-PGTransaction',
    'Get-EMSUser',
    'New-EMSUser',
    'Update-EMSUserLogin',
    'Save-ScanResult',
    'Get-ScanResults',
    'Get-DashboardStats',
    'Write-AuditLog'
)
