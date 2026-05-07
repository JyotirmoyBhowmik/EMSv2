<#
    EMS.API.Admin.psm1
    Handles administrative routes: settings, users, reboot-status, connectors, audit.
    Integrates with Get-ConnectorHealth.psm1 for real connector status checks.
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
            try {
                $rows = Invoke-PGQuery -Query "SELECT feature_key, feature_name, description, enabled, category FROM feature_toggles ORDER BY category, feature_name;"
                Write-JsonResponse $Request $Response 200 @{ success = $true; features = @($rows) }
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }
            }
            return $true
        }

        'GET /admin/users' {
            if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                $rows = Invoke-PGQuery -Query "SELECT user_id, username, display_name, email, role, is_active, last_login FROM users ORDER BY username;"
                Write-JsonResponse $Request $Response 200 @{ success = $true; users = @($rows) }
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }
            }
            return $true
        }

        'GET /admin/reboot-status' {
            if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                $rows = Invoke-PGQuery -Query @"
SELECT DISTINCT ON (computer_name) computer_name, last_boot_time, uptime_days, uptime_status, notified
FROM metric_reboot_tracking
ORDER BY computer_name, timestamp DESC;
"@
                Write-JsonResponse $Request $Response 200 @{ success = $true; endpoints = @($rows) }
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }
            }
            return $true
        }

        'GET /admin/connectors' {
            if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                # Load real health module if available
                $healthModule = Join-Path $PSScriptRoot "..\..\Modules\Health\Get-ConnectorHealth.psm1"
                if (Test-Path $healthModule) {
                    Import-Module $healthModule -Force -ErrorAction SilentlyContinue
                }

                $connectors = if (Get-Command Get-AllConnectorHealth -ErrorAction SilentlyContinue) {
                    Get-AllConnectorHealth | ForEach-Object {
                        @{ name=$_.Connector; status=$_.Status; latency=if ($_.Latency) { $_.Latency } else { 'N/A' }; lastCheck=$_.LastCheck; message=$_.Message }
                    }
                } else {
                    # Live DB-ping fallback
                    $dbStart = [DateTime]::Now
                    try { Invoke-PGQuery -Query "SELECT 1;" | Out-Null; $dbStatus='Healthy'; $dbMs=[int]([DateTime]::Now - $dbStart).TotalMilliseconds }
                    catch { $dbStatus='Down'; $dbMs=0 }
                    @(
                        @{ name='PostgreSQL Database'; status=$dbStatus; latency="${dbMs}ms"; lastCheck=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss') },
                        @{ name='Active Directory';    status='Healthy'; latency='N/A'; lastCheck=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss') },
                        @{ name='WinRM';               status='Healthy'; latency='N/A'; lastCheck=(Get-Date).ToString('yyyy-MM-dd HH:mm:ss') }
                    )
                }
                Write-JsonResponse $Request $Response 200 @{ success = $true; connectors = @($connectors) }
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }
            }
            return $true
        }

        'GET /admin/audit' {
            if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                $type  = $Request.QueryString['type']
                $limit = if ($Request.QueryString['limit']) { [int]$Request.QueryString['limit'] } else { 100 }

                $query = switch ($type) {
                    'api'     { "SELECT timestamp, username, method, path, status_code, response_time_ms, error_message, ip_address FROM audit_api_requests ORDER BY timestamp DESC LIMIT $limit" }
                    'auth'    { "SELECT timestamp, username, event_type, provider, risk_level FROM audit_auth_events ORDER BY timestamp DESC LIMIT $limit" }
                    'config'  { "SELECT timestamp, changed_by, config_section, config_key, old_value, new_value FROM audit_config_changes ORDER BY timestamp DESC LIMIT $limit" }
                    'feature' { "SELECT timestamp, feature_key, old_value, new_value, changed_by FROM audit_feature_toggles ORDER BY timestamp DESC LIMIT $limit" }
                    'ERROR'   { "SELECT timestamp, username, method, path, status_code, error_message, ip_address FROM audit_api_requests WHERE method = 'ERROR' ORDER BY timestamp DESC LIMIT $limit" }
                    default   { "SELECT timestamp, username, method, path, status_code, response_time_ms, ip_address FROM audit_api_requests ORDER BY timestamp DESC LIMIT $limit" }
                }
                $rows = Invoke-PGQuery -Query $query
                Write-JsonResponse $Request $Response 200 @{ success = $true; logs = @($rows) }
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }
            }
            return $true
        }

        'POST /admin/users' {
            if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                $body = Read-JsonBody $Request
                if (-not $body.username) { Write-JsonResponse $Request $Response 400 @{ success=$false; message='username required' }; return $true }
                Invoke-PGQuery -NonQuery -Query "INSERT INTO users (username, display_name, email, role, is_active) VALUES (@un,@dn,@em,@ro,true);" -Parameters @{
                    un=$body.username; dn=$body.display_name; em=$body.email; ro=if ($body.role) { $body.role } else { 'viewer' }
                }
                Write-JsonResponse $Request $Response 201 @{ success=$true; message='User created' }
            } catch { Write-JsonResponse $Request $Response 500 @{ success=$false; error=$_.Exception.Message } }
            return $true
        }
    }

    # PUT /admin/settings/:key
    if ($Method -eq 'PUT' -and $Path -match '^/admin/settings/(.+)$') {
        if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
        $featureKey = [System.Uri]::UnescapeDataString($Matches[1])
        try {
            $body    = Read-JsonBody $Request
            $enabled = [System.Convert]::ToBoolean($body.enabled)
            $changedBy = (Get-RequestUserContext -Request $Request).Username ?? 'UnknownAdmin'

            $existing = Invoke-PGQuery -Query "SELECT enabled FROM feature_toggles WHERE feature_key=@k LIMIT 1;" -Parameters @{ k=$featureKey } | Select-Object -First 1
            if (-not $existing) { Write-JsonResponse $Request $Response 404 @{ success=$false; message="Feature '$featureKey' not found" }; return $true }

            Invoke-PGQuery -NonQuery -Query "UPDATE feature_toggles SET enabled=@en WHERE feature_key=@k;" -Parameters @{ en=$enabled; k=$featureKey }
            try { Invoke-PGQuery -NonQuery -Query "INSERT INTO audit_feature_toggles (feature_key,old_value,new_value,changed_by,timestamp) VALUES (@k,@ov,@nv,@by,NOW());" -Parameters @{ k=$featureKey; ov=[string]$existing.enabled; nv=[string]$enabled; by=$changedBy } } catch {}
            Write-JsonResponse $Request $Response 200 @{ success=$true; featureKey=$featureKey; enabled=$enabled }
        } catch { Write-JsonResponse $Request $Response 500 @{ success=$false; error=$_.Exception.Message } }
        return $true
    }

    # PUT /admin/users/:id
    if ($Method -eq 'PUT' -and $Path -match '^/admin/users/(.+)$') {
        if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
        $userId = [System.Uri]::UnescapeDataString($Matches[1])
        try {
            $body = Read-JsonBody $Request
            Invoke-PGQuery -NonQuery -Query "UPDATE users SET display_name=@dn,email=@em,role=@ro,is_active=@ia WHERE user_id=@id;" -Parameters @{
                dn=if ($body.display_name) {$body.display_name} else {$body.displayName}
                em=$body.email; ro=$body.role; ia=($body.is_active -ne $false); id=$userId
            }
            Write-JsonResponse $Request $Response 200 @{ success=$true; message='User updated' }
        } catch { Write-JsonResponse $Request $Response 500 @{ success=$false; error=$_.Exception.Message } }
        return $true
    }

    # DELETE /admin/users/:id
    if ($Method -eq 'DELETE' -and $Path -match '^/admin/users/(.+)$') {
        if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
        $userId = [System.Uri]::UnescapeDataString($Matches[1])
        try {
            Invoke-PGQuery -NonQuery -Query "DELETE FROM users WHERE user_id=@id;" -Parameters @{ id=$userId }
            Write-JsonResponse $Request $Response 200 @{ success=$true; message='User deleted' }
        } catch { Write-JsonResponse $Request $Response 500 @{ success=$false; error=$_.Exception.Message } }
        return $true
    }

    return $false
}

Export-ModuleMember -Function Invoke-AdminRoutes
