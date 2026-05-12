<#
  PSPGSql.psm1
  Production-grade PostgreSQL helper for EMS
#>

# -------------------------
# Assembly Loading
# -------------------------
$LibRoot = Join-Path $PSScriptRoot "..\..\LibFixed"

$assemblies = @(
    "Npgsql.dll",
    "System.Buffers.dll",
    "System.Memory.dll",
    "System.Runtime.CompilerServices.Unsafe.dll",
    "System.Threading.Tasks.Extensions.dll",
    "Microsoft.Bcl.AsyncInterfaces.dll"
)

foreach ($asm in $assemblies) {
    $path = Join-Path $LibRoot $asm
    if (Test-Path $path) {
        try {
            [Reflection.Assembly]::LoadFrom($path) | Out-Null
        } catch {
            # Only warn if it's not already loaded
            if (-not ([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.Location -eq $path })) {
                Write-Warning "Failed to load assembly ${asm}: $($_.Exception.Message)"
            }
        }
    }
}

# -------------------------
# Module-scope connection
# -------------------------
$script:ConnString = $null

# -------------------------
# Connection Initialization
# -------------------------
function Initialize-PostgreSQLConnection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Config
    )

    $db = $Config.Database

    if (-not $db) {
        throw "Database configuration missing"
    }

    Import-Module "$PSScriptRoot\..\Security\EMS.Environment.psm1" -Force
    $dbPassword = Get-EMSEnvironmentVar -Key 'DB_PASSWORD'
    if (-not $dbPassword) { throw "DB_PASSWORD not set in DPAPI store. Run Setup-EMS.ps1." }

    $csb = [Npgsql.NpgsqlConnectionStringBuilder]::new()
    $csb.Host                   = $db.Host
    $csb.Port                   = [int]$db.Port
    $csb.Database               = $db.DatabaseName
    $csb.Username               = $db.Username
    $csb.Password               = $dbPassword
    $csb.SslMode                = [Npgsql.SslMode]::Require
    $csb.TrustServerCertificate = $false
    $csb.IncludeErrorDetail     = $false
    $csb.ApplicationName        = 'EMSv2'
    $script:ConnString          = $csb.ConnectionString

    Write-EMSLog -Message "PostgreSQL initialized ($($db.DatabaseName))" -Category Database
}

# -------------------------
# Connection Guard
# -------------------------
function Get-PGConnection {
    if (-not $script:ConnString) {
        throw "PostgreSQL connection not initialized"
    }

    $conn = New-Object Npgsql.NpgsqlConnection($script:ConnString)
    $conn.Open()
    return $conn
}

# -------------------------
# Connection Tester
# -------------------------
function Test-PostgreSQLConnection {
    [CmdletBinding()]
    param()

    try {
        $conn = Get-PGConnection
        $cmd  = $conn.CreateCommand()
        $cmd.CommandText = "SELECT 1"
        $cmd.ExecuteScalar() | Out-Null
        $conn.Close()
        return $true
    }
    catch {
        return $false
    }
}

# -------------------------
# Core Query Executor
# -------------------------
function Invoke-PGQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Query,

        [hashtable]$Parameters = @{},
        [switch]$NonQuery
    )

    $conn   = $null
    $cmd    = $null
    $reader = $null

    try {
        $conn = Get-PGConnection
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $Query
        $cmd.CommandTimeout = 90

        foreach ($key in $Parameters.Keys) {
            $value = $Parameters[$key]
            $param = $cmd.Parameters.AddWithValue($key, $value)
            if ($null -eq $value) {
                $param.Value = [DBNull]::Value
            }
        }

        if ($NonQuery) {
            return $cmd.ExecuteNonQuery()
        }

        $reader = $cmd.ExecuteReader()
        $results = @()

        while ($reader.Read()) {
            $row = @{}
            for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                $val = $reader.GetValue($i)
                $row[$reader.GetName($i)] = if ($val -is [DBNull]) { $null } else { $val }
            }
            $results += [pscustomobject]$row
        }

        return $results
    }
    catch {
        Write-EMSLog -Message "PG query error: $($_.Exception.Message)" -Severity Error -Category Database
        Write-EMSLog -Message "Query: $Query" -Severity Error -Category Database
        throw
    }
    finally {
        if ($reader) { $reader.Dispose() }
        if ($cmd)    { $cmd.Dispose() }
        if ($conn)   { $conn.Dispose() }
    }
}

Export-ModuleMember -Function Initialize-PostgreSQLConnection, Test-PostgreSQLConnection, Get-PGConnection, Invoke-PGQuery