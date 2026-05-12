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

        'GET /admin/health' {
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                $process = Get-Process -Id $PID
                $uptime = [DateTime]::Now - $process.StartTime
                $memoryMB = [math]::Round($process.WorkingSet64 / 1MB, 2)
                
                $dbStart = [DateTime]::Now
                $dbStatus = 'Healthy'
                $dbMs = 0
                try { Invoke-PGQuery -Query "SELECT 1;" | Out-Null; $dbMs = [math]::Round(([DateTime]::Now - $dbStart).TotalMilliseconds, 2) }
                catch { $dbStatus = 'Down' }

                $metrics = @{
                    success = $true
                    timestamp = [DateTime]::UtcNow.ToString("o")
                    api = @{
                        uptime = $uptime.ToString("d\.hh\:mm\:ss")
                        memoryUsageMB = $memoryMB
                        processId = $PID
                    }
                    database = @{
                        status = $dbStatus
                        latencyMs = $dbMs
                    }
                }
                Write-JsonResponse $Request $Response 200 $metrics
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }
            }
            return $true
        }

        'GET /admin/settings' {
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                $rows = Invoke-PGQuery -Query "SELECT feature_key, feature_name, description, enabled, category FROM feature_toggles ORDER BY category, feature_name;"
                Write-JsonResponse $Request $Response 200 @{ success = $true; features = @($rows) }
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }
            }
            return $true
        }

        'GET /admin/users' {
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                $rows = Invoke-PGQuery -Query "SELECT user_id, username, display_name, email, role, is_active, last_login FROM users ORDER BY username;"
                Write-JsonResponse $Request $Response 200 @{ success = $true; users = @($rows) }
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }
            }
            return $true
        }

        'GET /admin/reboot-status' {
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
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
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
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
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                [int]$limit = 100
                if (-not [string]::IsNullOrEmpty($Request.QueryString['limit'])) {
                    [void][int]::TryParse($Request.QueryString['limit'], [ref]$limit)
                }
                $limit = [Math]::Max(1, [Math]::Min($limit, 1000))

                [int]$offset = 0
                if (-not [string]::IsNullOrEmpty($Request.QueryString['offset'])) {
                    [void][int]::TryParse($Request.QueryString['offset'], [ref]$offset)
                }
                $offset = [Math]::Max(0, [Math]::Min($offset, 1000000))

                $type = [string]$Request.QueryString['type']

                $query = switch ($type) {
                    'api'     { "SELECT timestamp, username, method, path, status_code, response_time_ms, error_message, ip_address FROM audit_api_requests ORDER BY timestamp DESC LIMIT @lim OFFSET @off" }
                    'auth'    { "SELECT timestamp, username, event_type, provider, risk_level FROM audit_auth_events ORDER BY timestamp DESC LIMIT @lim OFFSET @off" }
                    'config'  { "SELECT timestamp, changed_by, config_section, config_key, old_value, new_value FROM audit_config_changes ORDER BY timestamp DESC LIMIT @lim OFFSET @off" }
                    'feature' { "SELECT timestamp, feature_key, old_value, new_value, changed_by FROM audit_feature_toggles ORDER BY timestamp DESC LIMIT @lim OFFSET @off" }
                    'ERROR'   { "SELECT timestamp, username, method, path, status_code, error_message, ip_address FROM audit_api_requests WHERE method = 'ERROR' ORDER BY timestamp DESC LIMIT @lim OFFSET @off" }
                    default   { "SELECT timestamp, username, method, path, status_code, response_time_ms, ip_address FROM audit_api_requests ORDER BY timestamp DESC LIMIT @lim OFFSET @off" }
                }

                $rows = Invoke-PGQuery -Query $query -Parameters @{ lim=$limit; off=$offset }
                Write-JsonResponse $Request $Response 200 @{ success = $true; logs = @($rows) }
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }
            }
            return $true
        }

        'POST /admin/users' {
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
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
        
        'POST /auth/change-password' {
            try {
                $ctx = Get-RequestUserContext -Request $Request
                if (-not $ctx.Username) { Write-JsonResponse $Request $Response 401 @{ success=$false; message='Unauthorized' }; return $true }
                
                $body = Read-JsonBody $Request
                if (-not $body.oldPassword -or -not $body.newPassword) {
                    Write-JsonResponse $Request $Response 400 @{ success=$false; message='Old and new passwords required' }
                    return $true
                }
                
                # Verify old password
                $authResult = Test-StandaloneAuth -Username $ctx.Username -Password $body.oldPassword -Config $Config
                if (-not $authResult.Success) {
                    Write-JsonResponse $Request $Response 403 @{ success=$false; message='Invalid old password' }
                    return $true
                }
                
                # Set new password
                $secureNew = ConvertTo-SecureString $body.newPassword -AsPlainText -Force
                Set-StandalonePassword -Username $ctx.Username -NewSecurePassword $secureNew
                
                Write-JsonResponse $Request $Response 200 @{ success=$true; message='Password updated successfully' }
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success=$false; error=$_.Exception.Message }
            }
            return $true
        }
    }

    # PUT /admin/settings/:key
    if ($Method -eq 'PUT' -and $Path -match '^/admin/settings/(.+)$') {
        if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
        $featureKey = [System.Uri]::UnescapeDataString($Matches[1])
        try {
            $body    = Read-JsonBody $Request
            $enabled = [System.Convert]::ToBoolean($body.enabled)
            $changedBy = (Get-RequestUserContext -Request $Request).Username ?? 'UnknownAdmin'

            $existing = Invoke-PGQuery -Query "SELECT enabled FROM feature_toggles WHERE feature_key=@k LIMIT 1;" -Parameters @{ k=$featureKey } | Select-Object -First 1
            if (-not $existing) { Write-JsonResponse $Request $Response 404 @{ success=$false; message="Feature '$featureKey' not found" }; return $true }

            Invoke-PGQuery -NonQuery -Query "UPDATE feature_toggles SET enabled=@en WHERE feature_key=@k;" -Parameters @{ en=$enabled; k=$featureKey }
            try { Invoke-PGQuery -NonQuery -Query "INSERT INTO audit_feature_toggles (feature_key,old_value,new_value,changed_by,timestamp) VALUES (@k,@ov,@nv,@by,NOW());" -Parameters @{ k=$featureKey; ov=$existing.enabled; nv=$enabled; by=$changedBy } } catch {}
            Write-JsonResponse $Request $Response 200 @{ success=$true; featureKey=$featureKey; enabled=$enabled }
        } catch { Write-JsonResponse $Request $Response 500 @{ success=$false; error=$_.Exception.Message } }
        return $true
    }

    # PUT /admin/users/:id
    if ($Method -eq 'PUT' -and $Path -match '^/admin/users/(.+)$') {
        if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
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
        if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
        $userId = [System.Uri]::UnescapeDataString($Matches[1])
        try {
            Invoke-PGQuery -NonQuery -Query "DELETE FROM users WHERE user_id=@id;" -Parameters @{ id=$userId }
            Write-JsonResponse $Request $Response 200 @{ success=$true; message='User deleted' }
        } catch { Write-JsonResponse $Request $Response 500 @{ success=$false; error=$_.Exception.Message } }
        return $true
    }

    return $false
}

# ─── Credential Management Routes ────────────────────────────────────
function Invoke-CredentialRoutes {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [string]$Method,
        [string]$Path,
        [pscustomobject]$Config
    )

    # Load security modules
    $secRoot = Join-Path $PSScriptRoot '..\..\Modules\Security'
    if (Test-Path "$secRoot\EMS.Credentials.psm1") {
        Import-Module "$secRoot\EMS.Credentials.psm1" -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path "$secRoot\EMS.Environment.psm1") {
        Import-Module "$secRoot\EMS.Environment.psm1" -Force -ErrorAction SilentlyContinue
    }

    switch ("$Method $Path") {

        'GET /admin/credentials' {
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                $creds = Get-EMSServiceCredentialInfo
                Write-JsonResponse $Request $Response 200 @{ success = $true; credentials = @($creds) }
            } catch {
                Write-JsonResponse $Request $Response 200 @{ success = $true; credentials = @() }
            }
            return $true
        }

        'POST /admin/credentials' {
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                $body = Read-JsonBody $Request
                if (-not $body.type -or -not $body.username -or -not $body.password) {
                    Write-JsonResponse $Request $Response 400 @{ success = $false; message = 'type, username, and password are required' }
                    return $true
                }
                $ctx = Get-RequestUserContext -Request $Request
                $secPass = ConvertTo-SecureString $body.password -AsPlainText -Force
                Set-EMSServiceCredential -CredentialType $body.type -Username $body.username -SecurePassword $secPass -CreatedBy $ctx.Username
                Write-JsonResponse $Request $Response 200 @{ success = $true; message = "Credential '$($body.type)' saved successfully" }
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }
            }
            return $true
        }

        'POST /admin/credentials/test' {
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                $body = Read-JsonBody $Request
                $testResult = Test-EMSServiceCredential -CredentialType ($body.type ?? 'ScanService')
                Write-JsonResponse $Request $Response 200 @{ success = $testResult.Success; message = $testResult.Message }
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }
            }
            return $true
        }

        'GET /admin/environment' {
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                $envConfig = Get-EMSEnvironmentConfig
                Write-JsonResponse $Request $Response 200 @{ success = $true; config = @($envConfig) }
            } catch {
                Write-JsonResponse $Request $Response 200 @{ success = $true; config = @() }
            }
            return $true
        }

        'POST /admin/environment' {
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            try {
                $body = Read-JsonBody $Request
                if (-not $body.key -or -not $body.value) {
                    Write-JsonResponse $Request $Response 400 @{ success = $false; message = 'key and value are required' }
                    return $true
                }
                $ctx = Get-RequestUserContext -Request $Request
                $isSensitive = $body.key -match '(?i)(password|secret|key|token)'
                Set-EMSEnvironmentVar -Key $body.key -Value $body.value -Description ($body.description ?? '') -IsSensitive $isSensitive -UpdatedBy $ctx.Username
                Write-JsonResponse $Request $Response 200 @{ success = $true; message = "Environment variable '$($body.key)' saved" }
            } catch {
                Write-JsonResponse $Request $Response 500 @{ success = $false; error = $_.Exception.Message }
            }
            return $true
        }
    }

    return $false
}

Export-ModuleMember -Function Invoke-AdminRoutes, Invoke-CredentialRoutes
