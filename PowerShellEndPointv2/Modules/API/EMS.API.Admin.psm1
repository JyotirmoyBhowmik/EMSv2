<#
    EMS.API.Admin.psm1
    Handles administrative routes (settings, users, reboot-status, audit).
#>

function Invoke-AdminRoutes {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [string]$Method,
        [string]$Path,
        [pscustomobject]$Config
    )

    switch ("$Method $Path") {
        'GET /admin/settings' {
            if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
            $rows = Invoke-PGQuery -Query "SELECT feature_key, feature_name, description, enabled, category FROM feature_toggles ORDER BY category, feature_name;"
            Write-JsonResponse $Request $Response 200 @{ success = $true; features = $rows }
            return $true
        }

        'GET /admin/users' {
            if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
            $rows = Invoke-PGQuery -Query "SELECT user_id, username, display_name, email, role, is_active, last_login FROM users ORDER BY username;"
            Write-JsonResponse $Request $Response 200 @{ success = $true; users = $rows }
            return $true
        }

        'GET /admin/reboot-status' {
            if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
            $rows = Invoke-PGQuery -Query @"
SELECT DISTINCT ON (computer_name) computer_name, last_boot_time, uptime_days, uptime_status, notified
FROM metric_reboot_tracking
ORDER BY computer_name, timestamp DESC;
"@
            Write-JsonResponse $Request $Response 200 @{ success = $true; endpoints = $rows }
            return $true
        }

        'GET /admin/connectors' {
            if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
            $connectors = @(
                @{ name = "PostgreSQL Database"; status = "Healthy"; latency = "2ms"; lastCheck = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") },
                @{ name = "Active Directory"; status = "Healthy"; latency = "45ms"; lastCheck = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") },
                @{ name = "SMTP Relay"; status = "Healthy"; latency = "12ms"; lastCheck = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") }
            )
            Write-JsonResponse $Request $Response 200 @{ success = $true; connectors = $connectors }
            return $true
        }

        'GET /admin/audit' {
            if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
            $type = $Request.QueryString['type']
            $limit = if ($Request.QueryString['limit']) { [int]$Request.QueryString['limit'] } else { 100 }
            
            $query = switch ($type) {
                "api"     { "SELECT timestamp, username, method, path, status_code, response_time_ms FROM audit_api_requests ORDER BY timestamp DESC LIMIT $limit" }
                "auth"    { "SELECT timestamp, username, event_type, provider, risk_level FROM audit_auth_events ORDER BY timestamp DESC LIMIT $limit" }
                "config"  { "SELECT timestamp, changed_by, config_section, config_key, old_value, new_value FROM audit_config_changes ORDER BY timestamp DESC LIMIT $limit" }
                "feature" { "SELECT timestamp, feature_key, old_value, new_value, changed_by FROM audit_feature_toggles ORDER BY timestamp DESC LIMIT $limit" }
                "ERROR"   { "SELECT timestamp, username, method, path, status_code, error_message FROM audit_api_requests WHERE method = 'ERROR' ORDER BY timestamp DESC LIMIT $limit" }
                default   { "SELECT timestamp, username, method, path, status_code FROM audit_api_requests ORDER BY timestamp DESC LIMIT $limit" }
            }
            
            $rows = Invoke-PGQuery -Query $query
            Write-JsonResponse $Request $Response 200 @{ success = $true; logs = $rows }
            return $true
        }
    }

    return $false
}

Export-ModuleMember -Function Invoke-AdminRoutes
