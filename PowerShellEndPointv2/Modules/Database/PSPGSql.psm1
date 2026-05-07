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
        Add-Type -Path $path -ErrorAction Stop
    }
}

# -------------------------
# Module-scope connection
# -------------------------
$script:ConnectionString = $null

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

    $sb = New-Object System.Text.StringBuilder
    $sb.Append("Host=$($db.Host);")             | Out-Null
    $sb.Append("Port=$($db.Port);")             | Out-Null
    $sb.Append("Database=$($db.DatabaseName);") | Out-Null
    $sb.Append("Username=$($db.Username);")     | Out-Null

    if ($db.Password) {
        $sb.Append("Password=$($db.Password);") | Out-Null
    }
    elseif ($db.PasswordSecure) {
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($db.PasswordSecure)
        )
        $sb.Append("Password=$plain;") | Out-Null
    }
    else {
        throw "Database password not provided"
    }

    $sb.Append("Pooling=true;Minimum Pool Size=1;Maximum Pool Size=30;Timeout=30;") | Out-Null

    if ($db.EnableSSL) {
        $sb.Append("SSL Mode=Require;") | Out-Null
    }

    $script:ConnectionString = $sb.ToString()

    Write-EMSLog -Message "PostgreSQL initialized ($($db.DatabaseName))" -Category Database
}

# -------------------------
# Connection Guard
# -------------------------
function Get-PGConnection {
    if (-not $script:ConnectionString) {
        throw "PostgreSQL connection not initialized"
    }

    $conn = New-Object Npgsql.NpgsqlConnection($script:ConnectionString)
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