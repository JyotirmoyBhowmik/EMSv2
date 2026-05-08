# Modules\Database\EMS.DB.Users.psm1

function Get-EMSUser {
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

function Save-ScanResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$ScanData,
        
        [int]$InitiatedBy
    )
    
    try {
        # Insert main scan result
        $query = @"
INSERT INTO scans 
    (target, ip_address, health_score, status, execution_time_sec, 
     critical_alerts, warning_alerts, info_alerts, scan_timestamp)
VALUES 
    (@target, @ip, @health, @status, @exectime,
     @critical, @warning, @info, @timestamp)
RETURNING scan_id
"@
        
        $params = @{
            target      = $ScanData.Hostname
            ip          = $ScanData.IPAddress
            health      = $ScanData.HealthScore
            status      = 'completed'
            exectime    = $ScanData.ExecutionTimeSeconds
            critical    = ($ScanData.Diagnostics | Where-Object { $_.Severity -eq 'Critical' }).Count
            warning     = ($ScanData.Diagnostics | Where-Object { $_.Severity -eq 'Warning' }).Count
            info        = ($ScanData.Diagnostics | Where-Object { $_.Severity -eq 'Info' }).Count
            timestamp   = if ($ScanData.ScanTimestamp) { $ScanData.ScanTimestamp } else { Get-Date }
        }
        
        $result = Invoke-PGQuery -Query $query -Parameters $params
        return $result.scan_id
    }
    catch {
        Write-EMSLog -Message "Error saving scan result: $_" -Severity 'Error'
        throw
    }
}

Export-ModuleMember -Function Get-EMSUser, New-EMSUser, Update-EMSUserLogin, Save-ScanResult
