<#
    EMS.API.Inventory.psm1
    Handles computer inventory, dashboard stats, and compliance data.
#>

function Invoke-InventoryRoutes {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [string]$Method,
        [string]$Path,
        [pscustomobject]$Config
    )

    # Regex matches
    if ($Method -eq 'GET' -and $Path -match '^/computers/(.+)$') {
        if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
        $computerName = [System.Uri]::UnescapeDataString($Matches[1])
        $computer = Invoke-PGQuery -Query @"
SELECT computer_name, ip_address::text AS ip_address, mac_address, operating_system, os_version, os_build, domain, is_domain_joined, computer_type, manufacturer, model, serial_number, location, department, asset_tag, first_seen, last_seen, is_active, notes
FROM computers WHERE computer_name = @computerName LIMIT 1;
"@ -Parameters @{ computerName = $computerName } | Select-Object -First 1
        
        if (-not $computer) { 
            Write-JsonResponse $Request $Response 404 @{ success = $false; message = 'Computer not found' }
            return $true 
        }
        
        $users = @()
        try { 
            $users = Invoke-PGQuery -Query @"
SELECT computer_name, ad_username, display_name, email, department, title, last_logon
FROM computer_ad_users WHERE computer_name = @computerName ORDER BY ad_username;
"@ -Parameters @{ computerName = $computerName } 
        } catch { $users = @() }
        
        Write-JsonResponse $Request $Response 200 @{ success = $true; computer = $computer; users = $users }
        return $true
    }

    if ($Method -eq 'GET' -and $Path -match '^/results/(.+)$') {
        if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
        $resultIdRaw = [System.Uri]::UnescapeDataString($Matches[1])
        try { $resultId = [Guid]::Parse($resultIdRaw) } catch { 
            Write-JsonResponse $Request $Response 400 @{ success = $false; message = 'Invalid result ID format' }
            return $true 
        }
        
        $row = Invoke-PGQuery -Query @"
SELECT scan_id, target, status, health_score, critical_alerts, warning_alerts, info_alerts, execution_time_sec, result_json, error_message, started_at, completed_at
FROM scans WHERE scan_id = @scanId LIMIT 1;
"@ -Parameters @{ scanId = $resultId } | Select-Object -First 1
        
        if (-not $row) { 
            Write-JsonResponse $Request $Response 404 @{ success = $false; message = 'Result not found' }
            return $true 
        }
        
        $resultJson = $null
        if ($row.result_json) { try { $resultJson = $row.result_json | ConvertFrom-Json } catch { $resultJson = $null } }
        Write-JsonResponse $Request $Response 200 @{ success=$true; id=$row.scan_id; scanId=$row.scan_id; target=$row.target; status=$row.status; healthScore=$row.health_score; criticalAlerts=$row.critical_alerts; warningAlerts=$row.warning_alerts; infoAlerts=$row.info_alerts; executionTimeSeconds=$row.execution_time_sec; errorMessage=$row.error_message; startedAt=$row.started_at; completedAt=$row.completed_at; result=$resultJson }
        return $true
    }

    # Static Routes
    switch ("$Method $Path") {
        'GET /dashboard/stats' {
            if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            $range = $Request.QueryString['range'] # today, 24h, 7d, 30d, all
            if (-not $range) { $range = 'all' }

            $totalComputers=0; $activeComputers=0; $totalScans=0; $healthyEndpoints=0; $criticalAlerts=0; $uniqueEndpoints=0; $completedScans=0; $failedScans=0; $inProgressScans=0; $averageScanTime=$null; $lastScan=$null; $excellentCount=0; $goodCount=0; $fairCount=0; $poorCount=0; $compliantEndpoints=0; $partialCompliantEndpoints=0; $collectionFailedEndpoints=0; $dellBiosUnknownEndpoints=0; $biosPasswordUnknownEndpoints=0; $metricWarningEndpoints=0
            
            try { 
                $row = Invoke-PGQuery -Query 'SELECT COUNT(*)::int AS total, COUNT(*) FILTER (WHERE is_active = true)::int AS active FROM computers;' | Select-Object -First 1
                if ($row) { 
                    $totalComputers = [int]$row.total 
                    $activeComputers = [int]$row.active
                } 
            } catch {}
            
            $dbParams = @{
                applyToday = $applyToday;
                applyInterval = $applyInterval;
                intervalStr = $intervalStr
            }

            try {
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
    MAX(completed_at) AS last_scan,
    COUNT(*) FILTER (WHERE status = 'completed' AND health_score >= 90)::int AS excellent_count,
    COUNT(*) FILTER (WHERE status = 'completed' AND health_score >= 70 AND health_score < 90)::int AS good_count,
    COUNT(*) FILTER (WHERE status = 'completed' AND health_score >= 50 AND health_score < 70)::int AS fair_count,
    COUNT(*) FILTER (WHERE status = 'completed' AND health_score < 50)::int AS poor_count
FROM scans
WHERE COALESCE(is_deleted, false) = false
  AND (
      @range = 'all' OR
      (@range = 'today' AND completed_at >= CURRENT_DATE) OR
      (@range = '24h' AND completed_at >= NOW() - INTERVAL '24 hours') OR
      (@range = '7d' AND completed_at >= NOW() - INTERVAL '7 days') OR
      (@range = '30d' AND completed_at >= NOW() - INTERVAL '30 days')
  );
"@
                $row = Invoke-PGQuery -Query $scanQuery -Parameters @{ range = $range } | Select-Object -First 1
                if ($row) {
                    $totalScans=[int]$row.total_scans; $healthyEndpoints=[int]$row.healthy_endpoints; $criticalAlerts=[int]$row.critical_alerts; $uniqueEndpoints=[int]$row.unique_endpoints; $completedScans=[int]$row.completed_scans; $failedScans=[int]$row.failed_scans; $inProgressScans=[int]$row.in_progress_scans; $averageScanTime = if ($row.average_scan_time -ne $null) { [double]$row.average_scan_time } else { $null }; $lastScan=$row.last_scan; $excellentCount=[int]$row.excellent_count; $goodCount=[int]$row.good_count; $fairCount=[int]$row.fair_count; $poorCount=[int]$row.poor_count
                }
            } catch { Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }; return $true }
            
            try {
                $complianceQuery = @"
SELECT
    COUNT(*) FILTER (WHERE compliance_bucket = 'Compliant')::int AS compliant_count,
    COUNT(*) FILTER (WHERE compliance_bucket = 'Partial Compliant')::int AS partial_count,
    COUNT(*) FILTER (WHERE compliance_issues ILIKE '%Inventory collection failed%')::int AS collection_failed_count,
    COUNT(*) FILTER (WHERE COALESCE(compliance_warnings,'') <> '')::int AS metric_warning_count,
    COUNT(*) FILTER (
        WHERE COALESCE(manufacturer,'') NOT IN ('', 'Unknown')
          AND COALESCE(model,'') NOT IN ('', 'Unknown')
          AND COALESCE(compliance_issues,'') NOT ILIKE '%Inventory collection failed%'
          AND (COALESCE(poweron_password,'') <> 'Configured' OR COALESCE(admin_password,'') <> 'Configured')
    )::int AS bios_password_unknown_count
FROM v_ems_latest_compliance_classified
WHERE (
    @range = 'all' OR
    (@range = 'today' AND lastchecked >= CURRENT_DATE) OR
    (@range = '24h' AND lastchecked >= NOW() - INTERVAL '24 hours') OR
    (@range = '7d' AND lastchecked >= NOW() - INTERVAL '7 days') OR
    (@range = '30d' AND lastchecked >= NOW() - INTERVAL '30 days')
);
"@
                $compRow = Invoke-PGQuery -Query $complianceQuery -Parameters @{ range = $range } | Select-Object -First 1
                if ($compRow) {
                    $compliantEndpoints = [int]$compRow.compliant_count
                    $partialCompliantEndpoints = [int]$compRow.partial_count
                    $collectionFailedEndpoints = [int]$compRow.collection_failed_count
                    $metricWarningEndpoints = [int]$compRow.metric_warning_count
                    $biosPasswordUnknownEndpoints = [int]$compRow.bios_password_unknown_count
                    $dellBiosUnknownEndpoints = $biosPasswordUnknownEndpoints
                }
            } catch {
                # Silent catch for missing view/data
            }
            Write-JsonResponse $Request $Response 200 @{ success=$true; stats=@{ totalScans=$totalScans; healthyEndpoints=$healthyEndpoints; criticalAlerts=$criticalAlerts; uniqueEndpoints=$uniqueEndpoints; completedScans=$completedScans; failedScans=$failedScans; inProgressScans=$inProgressScans; averageScanTime=$averageScanTime; lastScan=$lastScan; excellentCount=$excellentCount; goodCount=$goodCount; fairCount=$fairCount; poorCount=$poorCount; totalComputers=$totalComputers; activeComputers=$activeComputers; compliantEndpoints=$compliantEndpoints; partialCompliantEndpoints=$partialCompliantEndpoints; collectionFailedEndpoints=$collectionFailedEndpoints; dellBiosUnknownEndpoints=$dellBiosUnknownEndpoints; biosPasswordUnknownEndpoints=$biosPasswordUnknownEndpoints; metricWarningEndpoints=$metricWarningEndpoints }; scanStatus=@{ completed=$completedScans; failed=$failedScans; inProgress=$inProgressScans }; performance=@{ averageScanTime=$averageScanTime; lastScan=$lastScan }; healthOverview=@{ excellent=$excellentCount; good=$goodCount; fair=$fairCount; poor=$poorCount } }
            return $true
        }

        'GET /compliance/compliant' {
            if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            $rows = Invoke-PGQuery -Query "SELECT * FROM v_ems_latest_compliance_classified WHERE compliance_bucket = 'Compliant' ORDER BY target;"
            Write-JsonResponse $Request $Response 200 @{ success=$true; count=@($rows).Count; results=@($rows) }
            return $true
        }

        'GET /compliance/partial' {
            if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            $rows = Invoke-PGQuery -Query "SELECT * FROM v_ems_latest_compliance_classified WHERE compliance_bucket = 'Partial Compliant' ORDER BY target;"
            Write-JsonResponse $Request $Response 200 @{ success=$true; count=@($rows).Count; results=@($rows) }
            return $true
        }

        'GET /results' {
            if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            $includeDeleted = $false
            $includeDeletedRaw = $Request.QueryString['includeDeleted']
            if ($includeDeletedRaw -and $includeDeletedRaw.ToString().ToLower() -eq 'true') {
                if (Test-AdminAccess -Request $Request -Config $Config) { $includeDeleted = $true }
            }
            $whereClause = if ($includeDeleted) { '' } else { 'WHERE COALESCE(s.is_deleted, false) = false' }
            $rows = Invoke-PGQuery -Query @"
SELECT
    s.scan_id, s.target, s.status, s.result_json, s.health_score, s.critical_alerts, s.warning_alerts, s.info_alerts, s.execution_time_sec, s.started_at, s.completed_at,
    s.is_deleted, s.deleted_at, s.deleted_by, s.delete_reason,
    ir.computer_name, ir.manufacturer, ir.model, ir.domain_user, ir.screensaver_policy, ir.restrict_software_installation_policy, ir.lastpolicy_checked, ir.enabled_local_user_account,
    ir.all_security_kbs, ir.all_security_kbs_installedon, ir.os_edition, ir.os_version, ir.os_build, ir.symantec_management_agent, ir.readonly_usb, ir.poweron_password, ir.admin_password, ir.timesync_with_ntp, ir.lastchecked, ir.comments
FROM scans s
LEFT JOIN scan_inventory_results ir ON s.scan_id = ir.scan_id
$whereClause
ORDER BY s.started_at DESC
LIMIT 500;
"@
            $results = $rows | ForEach-Object {
                $resultJson = $null; $hostname = $_.target; $actualFinding = ''
                if ($_.result_json) {
                    try {
                        $resultJson = $_.result_json | ConvertFrom-Json
                        if ($resultJson.hostname) { $hostname = $resultJson.hostname }
                        if ($resultJson.diagnostics) {
                            $importantFindings = $resultJson.diagnostics | Where-Object { $_.severity -in @('Critical','Warning') } | ForEach-Object {
                                $name = if ($_.metricName) { $_.metricName } else { $_.checkName }
                                $value = if ($null -ne $_.metricValue -and $_.unit) { "$($_.metricValue)$($_.unit)" } elseif ($null -ne $_.metricValue) { "$($_.metricValue)" } else { $null }
                                if ($value) { ('{0}: {1} ({2})' -f $name, $value, $_.severity) } else { ('{0} ({1})' -f $name, $_.severity) }
                            }
                            $actualFinding = ($importantFindings -join '; ')
                        }
                    } catch {}
                }
                if (-not $actualFinding -and $_.comments) { $actualFinding = $_.comments }
                [pscustomobject]@{ id=$_.scan_id; scanId=$_.scan_id; target=$_.target; hostname=$hostname; status=$_.status; healthScore=$_.health_score; criticalAlerts=$_.critical_alerts; warningAlerts=$_.warning_alerts; infoAlerts=$_.info_alerts; executionTimeSeconds=$_.execution_time_sec; startedAt=$_.started_at; completedAt=$_.completed_at; actualFinding=$actualFinding; manufacturer=$_.manufacturer; model=$_.model; lastChecked=$_.lastchecked; isDeleted=$_.is_deleted }
            }
            Write-JsonResponse $Request $Response 200 @{ success = $true; count = @($results).Count; results = @($results) }
            return $true
        }

        'GET /computers' {
            if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            $rows = Invoke-PGQuery -Query "SELECT computer_name, ip_address::text AS ip_address, operating_system, domain, computer_type, last_seen, is_active FROM computers ORDER BY computer_name;"
            Write-JsonResponse $Request $Response 200 @{ success = $true; computers = $rows }
            return $true
        }

        'POST /computers' {
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            $body = Read-JsonBody $Request
            $computerName = if ($body.computerName) { $body.computerName } elseif ($body.name) { $body.name } else { $null }
            $ipAddress    = if ($body.ipAddress) { $body.ipAddress } elseif ($body.ip) { $body.ip } else { $null }
            $computerType = if ($body.computerType) { $body.computerType } elseif ($body.type) { $body.type } else { 'Desktop' }
            $osName       = if ($body.operatingSystem) { $body.operatingSystem } elseif ($body.os) { $body.os } else { $null }
            $domainName   = if ($body.domain) { $body.domain } else { $null }
            
            if (-not $computerName -or -not $ipAddress) { 
                Write-JsonResponse $Request $Response 400 @{ success = $false; message = 'Computer name and IP address are required' }
                return $true 
            }
            
            Invoke-PGQuery -NonQuery -Query @"
INSERT INTO computers (computer_name, ip_address, computer_type, operating_system, domain, updated_at, last_seen)
VALUES (@computerName, CAST(@ipAddress AS inet), @computerType, @operatingSystem, @domain, NOW(), NOW())
ON CONFLICT (computer_name)
DO UPDATE SET ip_address=EXCLUDED.ip_address, computer_type=EXCLUDED.computer_type, operating_system=EXCLUDED.operating_system, domain=EXCLUDED.domain, updated_at=NOW(), last_seen=NOW();
"@ -Parameters @{ computerName=$computerName; ipAddress=$ipAddress; computerType=$computerType; operatingSystem=$osName; domain=$domainName }
            
            Write-JsonResponse $Request $Response 200 @{ success=$true; message='Computer registered successfully' }
            return $true
        }
    }

    # ─── Compliance Routes ────────────────────────────────────────────────
    switch ("$Method $Path") {

        'GET /compliance/report' {
            if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                # Build compliance report from latest scan data per computer
                $report = Invoke-PGQuery -Query @"
                SELECT DISTINCT ON (s.target)
                    s.target AS computer_name,
                    s.health_score,
                    s.status AS scan_status,
                    s.completed_at,
                    CASE
                        WHEN s.health_score >= 90 THEN 'Compliant'
                        WHEN s.health_score >= 70 THEN 'Partial'
                        WHEN s.health_score IS NOT NULL THEN 'Non-Compliant'
                        ELSE 'Unknown'
                    END AS compliance_status
                FROM scans s
                WHERE s.status = 'completed'
                  AND s.is_archived = false
                ORDER BY s.target, s.completed_at DESC
                LIMIT 500;
"@
                Write-JsonResponse $Request $Response 200 @{ success = $true; report = @($report) }
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }
            }
            return $true
        }

        'GET /compliance/history' {
            if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                # Compliance trend over last 30 days
                $history = Invoke-PGQuery -Query @"
                SELECT
                    DATE(completed_at) AS scan_date,
                    COUNT(*)::int AS total_scans,
                    COUNT(*) FILTER (WHERE health_score >= 90)::int AS compliant,
                    COUNT(*) FILTER (WHERE health_score >= 70 AND health_score < 90)::int AS partial,
                    COUNT(*) FILTER (WHERE health_score < 70)::int AS non_compliant,
                    ROUND(AVG(health_score), 1) AS avg_score
                FROM scans
                WHERE status = 'completed'
                  AND completed_at >= NOW() - INTERVAL '30 days'
                GROUP BY DATE(completed_at)
                ORDER BY scan_date DESC;
"@
                Write-JsonResponse $Request $Response 200 @{ success = $true; history = @($history) }
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }
            }
            return $true
        }
    }

    return $false # Route not handled by this controller
}

Export-ModuleMember -Function Invoke-InventoryRoutes
