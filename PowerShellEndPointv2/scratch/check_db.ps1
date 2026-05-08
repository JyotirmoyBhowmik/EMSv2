
$PSScriptRoot = "c:\Users\jyotu\Desktop\EndpointManagement\EMS\PowerShellEndPointv2\Modules\Database"
Import-Module "$PSScriptRoot\PSPGSql.psm1" -Force
Import-Module "c:\Users\jyotu\Desktop\EndpointManagement\EMS\PowerShellEndPointv2\Modules\Logging.psm1" -Force

$Config = Get-Content "c:\Users\jyotu\Desktop\EndpointManagement\EMS\PowerShellEndPointv2\Config\EMSConfig.json" | ConvertFrom-Json
# Override password if we think it's different
# $Config.Database.Password = "ThinkPad@2026" 

try {
    Initialize-PostgreSQLConnection -Config $Config
    $tables = Invoke-PGQuery -Query "SELECT table_name FROM information_schema.tables WHERE table_schema = 'public';"
    $tables | ForEach-Object { $_.table_name }
} catch {
    $_.Exception.Message
}
