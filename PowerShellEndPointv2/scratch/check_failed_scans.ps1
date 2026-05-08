$root = "c:\Users\jyotu\Desktop\EndpointManagement\EMS\PowerShellEndPointv2"
Import-Module "$root\Modules\Logging.psm1" -Force
Import-Module "$root\Modules\Database\PSPGSql.psm1" -Force
$Config = Get-Content "$root\Config\EMSConfig.json" | ConvertFrom-Json
$Config.Database.Password = 'ThinkPad@2026' # From user summary
Initialize-PostgreSQLConnection -Config $Config

$failedScans = Invoke-PGQuery -Query "SELECT target, status, error_message, completed_at FROM scans WHERE status = 'failed' ORDER BY completed_at DESC LIMIT 10;"
$failedScans | Format-Table -AutoSize
