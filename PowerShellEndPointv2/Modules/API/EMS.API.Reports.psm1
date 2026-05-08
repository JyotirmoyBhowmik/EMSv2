<#
    EMS.API.Reports.psm1
    Advanced reporting engine for Compliance, Historical Trends, and Drift Analysis.
#>

function Invoke-ReportRoutes {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [string]$Method,
        [string]$Path,
        [pscustomobject]$Config
    )

    # 1. Regex Path Parsing
    if ($Method -eq 'GET' -and $Path -match '^/historical/timeline/(.+)$') {
        if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
        $hostname = [System.Uri]::UnescapeDataString($Matches[1])
        
        $history = Invoke-PGQuery -Query @"
            SELECT scan_id, health_score, critical_alerts, warning_alerts, completed_at 
            FROM scans 
            WHERE target = @hostname AND status = 'completed'
            ORDER BY completed_at DESC 
            LIMIT 50
"@ -Parameters @{ hostname = $hostname }
        
        Write-JsonResponse $Request $Response 200 @{ success = $true; hostname = $hostname; history = $history }
        return $true
    }

    # 2. Static Routes
    switch ("$Method $Path") {
        'GET /historical/heatmap' {
            if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            
            $heatmap = Invoke-PGQuery -Query @"
                SELECT 
                    substring(target from '^[^.]+') as short_name,
                    health_score,
                    completed_at
                FROM scans 
                WHERE status = 'completed' AND completed_at > NOW() - INTERVAL '30 days'
                ORDER BY completed_at DESC
"@
            Write-JsonResponse $Request $Response 200 @{ success = $true; data = $heatmap }
            return $true
        }

        'GET /historical/drift' {
            if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            
            # Simple drift analysis: endpoints whose health score dropped by > 10 points in the last 2 scans
            $drift = Invoke-PGQuery -Query @"
                WITH last_two AS (
                    SELECT target, health_score, 
                           LAG(health_score) OVER (PARTITION BY target ORDER BY completed_at ASC) as prev_score
                    FROM scans
                    WHERE status = 'completed'
                )
                SELECT target, prev_score, health_score as current_score, (prev_score - health_score) as drop
                FROM last_two
                WHERE prev_score IS NOT NULL AND (prev_score - health_score) > 10
"@
            Write-JsonResponse $Request $Response 200 @{ success = $true; data = $drift }
            return $true
        }

        'GET /historical/cutover' {
            if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            
            $beforeDate = $Request.QueryString['before'] # e.g. '2023-10-01'
            $afterDate  = $Request.QueryString['after']  # e.g. '2023-10-15'
            
            if (-not $beforeDate -or -not $afterDate) {
                Write-JsonResponse $Request $Response 400 @{ success = $false; message = 'Both before and after dates are required' }
                return $true
            }
            
            $report = Invoke-PGQuery -Query @"
                WITH before_state AS (
                    SELECT DISTINCT ON (target) target, health_score as score_before
                    FROM scans 
                    WHERE status = 'completed' AND completed_at <= @before::timestamp
                    ORDER BY target, completed_at DESC
                ),
                after_state AS (
                    SELECT DISTINCT ON (target) target, health_score as score_after
                    FROM scans 
                    WHERE status = 'completed' AND completed_at <= @after::timestamp
                    ORDER BY target, completed_at DESC
                )
                SELECT b.target, b.score_before, a.score_after, (a.score_after - b.score_before) as change
                FROM before_state b
                JOIN after_state a ON b.target = a.target
                ORDER BY change ASC
"@ -Parameters @{ before = $beforeDate; after = $afterDate }
            
            Write-JsonResponse $Request $Response 200 @{ success = $true; data = $report }
            return $true
        }
    }

    return $false
}

Export-ModuleMember -Function Invoke-ReportRoutes
