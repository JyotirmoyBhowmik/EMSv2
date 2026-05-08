$root = "c:\Users\jyotu\Desktop\EndpointManagement\EMS\PowerShellEndPointv2"
Import-Module "$root\Modules\Logging.psm1" -Force
Import-Module "$root\Modules\Database\PSPGSql.psm1" -Force
$Config = Get-Content "$root\Config\EMSConfig.json" | ConvertFrom-Json
$Config.Database.Password = 'ThinkPad@2026'
Initialize-PostgreSQLConnection -Config $Config

function Measure-Query {
    param($Name, $Query)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $res = Invoke-PGQuery -Query $Query
        $sw.Stop()
        Write-Host "[$Name] Took $($sw.ElapsedMilliseconds)ms (Count: $($res.Count))" -ForegroundColor Cyan
    } catch {
        $sw.Stop()
        Write-Host "[$Name] FAILED after $($sw.ElapsedMilliseconds)ms: $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "Measuring Dashboard Queries..." -ForegroundColor Yellow

Measure-Query "Total Computers" "SELECT COUNT(*)::int AS total FROM computers;"
Measure-Query "Active Computers" "SELECT COUNT(*)::int AS total FROM computers WHERE is_active = true;"

$scanQuery = @"
SELECT
    COUNT(*)::int AS total_scans,
    COUNT(DISTINCT target)::int AS unique_endpoints,
    COUNT(*) FILTER (WHERE status = 'completed')::int AS completed_scans,
    COUNT(*) FILTER (WHERE status = 'failed')::int AS failed_scans,
    COUNT(*) FILTER (WHERE status IN ('queued', 'running'))::int AS in_progress_scans,
    COUNT(*) FILTER (WHERE status = 'completed' AND health_score >= 90)::int AS healthy_endpoints,
    COALESCE(SUM(critical_alerts) FILTER (WHERE status = 'completed'), 0)::int AS critical_alerts,
    ROUND(COALESCE(AVG(execution_time_sec) FILTER (WHERE status = 'completed' AND execution_time_sec IS NOT NULL),0)::numeric,2) AS average_scan_time,
    MAX(completed_at) AS last_scan
FROM scans
WHERE COALESCE(is_deleted, false) = false;
"@
Measure-Query "Scan Stats (All Time)" $scanQuery

Measure-Query "Compliance Buckets" @"
SELECT
    compliance_bucket,
    COUNT(*)::int AS endpoint_count
FROM v_ems_latest_compliance_classified
GROUP BY compliance_bucket;
"@

Measure-Query "Collection Failed" "SELECT COUNT(*)::int AS count FROM v_ems_latest_compliance_classified WHERE compliance_issues ILIKE '%Inventory collection failed%';"

Measure-Query "BIOS Issues" @"
SELECT COUNT(*)::int AS count
FROM v_ems_latest_compliance_classified
WHERE COALESCE(manufacturer,'') NOT IN ('', 'Unknown')
  AND COALESCE(model,'') NOT IN ('', 'Unknown')
  AND COALESCE(compliance_issues,'') NOT ILIKE '%Inventory collection failed%'
  AND (COALESCE(poweron_password,'') <> 'Configured' OR COALESCE(admin_password,'') <> 'Configured');
"@
