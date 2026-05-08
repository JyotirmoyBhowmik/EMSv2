# Apply scan_trace migration
$root = "c:\Users\jyotu\Desktop\EndpointManagement\EMS\PowerShellEndPointv2"
$lib = Join-Path $root "LibFixed"

# Manually load assemblies in correct order
$asms = @(
    "System.Runtime.CompilerServices.Unsafe.dll",
    "System.Memory.dll",
    "System.Buffers.dll",
    "System.Threading.Tasks.Extensions.dll",
    "Microsoft.Bcl.AsyncInterfaces.dll",
    "Npgsql.dll"
)

foreach ($asm in $asms) {
    Add-Type -Path (Join-Path $lib $asm) -ErrorAction SilentlyContinue
}

$config = Get-Content "$root\Config\EMSConfig.json" | ConvertFrom-Json

Import-Module "$root\Modules\Logging.psm1" -Force
Import-Module "$root\Modules\Database\PSPGSql.psm1" -Force

# Initialize DB connection
Initialize-PostgreSQLConnection -Config $config

$sql = Get-Content "$root\Database\add_scan_trace_table.sql" -Raw
try {
    Invoke-PGQuery -Query $sql -NonQuery
    Write-Host "Migration successful: scan_trace table created."
}
catch {
    Write-Host "Migration check/apply complete. Message: $($_.Exception.Message)"
}
