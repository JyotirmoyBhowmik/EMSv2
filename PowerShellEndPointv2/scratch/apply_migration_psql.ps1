# Apply migration using psql directly to avoid assembly issues
$root = "c:\Users\jyotu\Desktop\EndpointManagement\EMS\PowerShellEndPointv2"
$config = Get-Content "$root\Config\EMSConfig.json" | ConvertFrom-Json
$pass = $config.Database.Password

$env:PGPASSWORD = $pass
$cmd = "psql -h $($config.Database.Host) -U $($config.Database.Username) -d $($config.Database.DatabaseName) -f `"$root\Database\add_scan_trace_table.sql`""
Invoke-Expression $cmd
$env:PGPASSWORD = $null
