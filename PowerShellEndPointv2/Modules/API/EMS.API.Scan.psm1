<#
    EMS.API.Scan.psm1
    Handles scan execution, status, results, and archiving.
#>

$script:FrontendErrorBuckets =
    [System.Collections.Concurrent.ConcurrentDictionary[string,object]]::new()

function Test-FrontendErrorAllowed {
    param([string]$Ip)
    $now = [DateTime]::Now

    $addValueFactory = [Func[string, object]] { param($k) return [pscustomobject]@{ Count=1; WindowStart=$now } }
    $updateValueFactory = [Func[string, object, object]] {
        param($k, $old)
        $oldStart = $old.WindowStart
        if (($now - $oldStart).TotalSeconds -gt 60) {
            return [pscustomobject]@{ Count=1; WindowStart=$now }
        } else {
            return [pscustomobject]@{ Count=($old.Count + 1); WindowStart=$oldStart }
        }
    }

    $entry = $script:FrontendErrorBuckets.AddOrUpdate($Ip, $addValueFactory, $updateValueFactory)
    return ($entry.Count -le 5)
}

function Invoke-ScanRoutes {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [string]$Method,
        [string]$Path,
        [pscustomobject]$Config
    )

    # Regex matches for Scan Results
    if ($Method -eq 'POST' -and $Path -match '^/results/([0-9a-fA-F-]+)/archive$') {
        if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
        try { $scanId = [Guid]::Parse($Matches[1]) } catch { 
            Write-JsonResponse $Request $Response 400 @{ success = $false; message = 'Invalid scan ID format' }
            return $true 
        }
        
        $body = $null; $reason = $null
        try { if ($Request.HasEntityBody) { $body = Read-JsonBody $Request; if ($body.reason) { $reason = [string]$body.reason } } } catch {}
        
        $ctx = Get-RequestUserContext -Request $Request
        $performedBy = if ($ctx.Username) { $ctx.Username } else { 'UnknownAdmin' }
        
        $existing = Invoke-PGQuery -Query "SELECT scan_id, target, status, is_deleted FROM scans WHERE scan_id = @scanId LIMIT 1;" -Parameters @{ scanId = $scanId } | Select-Object -First 1
        if (-not $existing) { 
            Write-JsonResponse $Request $Response 404 @{ success = $false; message = 'Scan row not found' }
            return $true 
        }
        
        if ($existing.is_deleted -eq $true) { 
            Write-JsonResponse $Request $Response 200 @{ success = $true; message = 'Row already archived' }
            return $true 
        }
        
        Invoke-PGQuery -NonQuery -Query "UPDATE scans SET is_deleted = true, deleted_at = NOW(), deleted_by = @deletedBy, delete_reason = @reason WHERE scan_id = @scanId;" -Parameters @{ scanId=$scanId; deletedBy=$performedBy; reason=$reason }
        Invoke-PGQuery -NonQuery -Query "INSERT INTO scan_actions_audit (scan_id, action_type, performed_by, reason, old_status, target) VALUES (@scanId, 'archive', @performedBy, @reason, @oldStatus, @target);" -Parameters @{ scanId=$scanId; performedBy=$performedBy; reason=$reason; oldStatus=$existing.status; target=$existing.target }
        
        Write-JsonResponse $Request $Response 200 @{ success=$true; message='Scan row archived successfully'; scanId=$scanId }
        return $true
    }

    if ($Method -eq 'POST' -and $Path -match '^/results/([0-9a-fA-F-]+)/restore$') {
        if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
        try { $scanId = [Guid]::Parse($Matches[1]) } catch { 
            Write-JsonResponse $Request $Response 400 @{ success = $false; message = 'Invalid scan ID format' }
            return $true 
        }
        
        $ctx = Get-RequestUserContext -Request $Request
        $performedBy = if ($ctx.Username) { $ctx.Username } else { 'UnknownAdmin' }
        
        $existing = Invoke-PGQuery -Query "SELECT scan_id, target, status, is_deleted FROM scans WHERE scan_id = @scanId LIMIT 1;" -Parameters @{ scanId = $scanId } | Select-Object -First 1
        if (-not $existing) { 
            Write-JsonResponse $Request $Response 404 @{ success = $false; message = 'Scan row not found' }
            return $true 
        }
        
        Invoke-PGQuery -NonQuery -Query "UPDATE scans SET is_deleted = false, deleted_at = null, deleted_by = null, delete_reason = null WHERE scan_id = @scanId;" -Parameters @{ scanId = $scanId }
        Invoke-PGQuery -NonQuery -Query "INSERT INTO scan_actions_audit (scan_id, action_type, performed_by, reason, old_status, target) VALUES (@scanId, 'restore', @performedBy, null, @oldStatus, @target);" -Parameters @{ scanId=$scanId; performedBy=$performedBy; oldStatus=$existing.status; target=$existing.target }
        
        Write-JsonResponse $Request $Response 200 @{ success=$true; message='Scan row restored successfully'; scanId=$scanId }
        return $true
    }

    # Static Routes
    switch ("$Method $Path") {
        'POST /scan/single' {
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            $body = Read-JsonBody $Request
            if (-not $body.target) { 
                Write-JsonResponse $Request $Response 400 @{ success = $false; message = 'Target is required' }
                return $true 
            }
            $scanId = [guid]::NewGuid()
            $protocol = if ($body.protocol) { $body.protocol } else { $null }
            Invoke-PGQuery -NonQuery -Query "INSERT INTO scans (scan_id, target, status, started_at) VALUES (@scanId, @target, 'queued', NOW());" -Parameters @{ scanId = $scanId; target = $body.target }
            Start-EMSScan -ScanId $scanId -Target $body.target -Protocol $protocol
            Write-JsonResponse $Request $Response 202 @{ success = $true; scanId = $scanId; status = 'queued' }
            return $true
        }

        'POST /scan/bulk' {
            if (-not (Test-AdminAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            $body = Read-JsonBody $Request
            $targets = @()
            if ($body.targets) {
                if ($body.targets -is [System.Collections.IEnumerable] -and -not ($body.targets -is [string])) { $targets = @($body.targets) }
                else { $targets = @([string]$body.targets) }
            } elseif ($body.target) { $targets = @([string]$body.target) }
            
            if (-not $targets -or $targets.Count -eq 0) { 
                Write-JsonResponse $Request $Response 400 @{ success = $false; message = 'At least one target or CIDR range is required' }
                return $true 
            }
            
            $protocol = if ($body.protocol) { $body.protocol } else { $null }
            try {
                $batch = Start-EMSBatchScan -Targets $targets -Protocol $protocol
                Write-JsonResponse $Request $Response 202 @{ success=$true; message='Bulk scan queued successfully'; targetCount=$batch.targetCount; queuedScanCount=$batch.scanIds.Count; targets=$batch.targets; scanIds=$batch.scanIds; status='queued' }
            } catch { 
                Write-JsonResponse $Request $Response 400 @{ success = $false; message = $_.Exception.Message } 
            }
            return $true
        }

        'GET /scan/status' {
            if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            $scanIdRaw = $Request.QueryString['scanId']
            if (-not $scanIdRaw) { 
                Write-JsonResponse $Request $Response 400 @{ success = $false; message = 'scanId is required' }
                return $true 
            }
            try { $scanId = [Guid]::Parse($scanIdRaw) } catch { 
                Write-JsonResponse $Request $Response 400 @{ success = $false; message = 'Invalid scanId format' }
                return $true 
            }
            
            $row = Invoke-PGQuery -Query "SELECT scan_id, target, status, started_at, completed_at, error_message FROM scans WHERE scan_id = @scanId LIMIT 1;" -Parameters @{ scanId = $scanId } | Select-Object -First 1
            if (-not $row) { 
                Write-JsonResponse $Request $Response 404 @{ success = $false; message = 'Scan not found' }
                return $true 
            }
            
            Write-JsonResponse $Request $Response 200 @{ success=$true; scanId=$row.scan_id; target=$row.target; status=$row.status; startedAt=$row.started_at; completedAt=$row.completed_at; errorMessage=$row.error_message }
            return $true
        }

        'GET /scan/trace' {
            if (-not (Test-ViewerAccessRequirement -Request $Request -Response $Response -Config $Config)) { return $true }
            $scanIdRaw = $Request.QueryString['scanId']
            if (-not $scanIdRaw) { 
                Write-JsonResponse $Request $Response 400 @{ success = $false; message = 'scanId is required' }
                return $true 
            }
            try { $scanId = [Guid]::Parse($scanIdRaw) } catch { 
                Write-JsonResponse $Request $Response 400 @{ success = $false; message = 'Invalid scanId format' }
                return $true 
            }
            
            $traces = Invoke-PGQuery -Query "SELECT trace_id, step_name, module_name, status, message, timestamp FROM scan_trace WHERE scan_id = @scanId ORDER BY timestamp ASC, trace_id ASC;" -Parameters @{ scanId = $scanId }
            Write-JsonResponse $Request $Response 200 @{ success=$true; scanId=$scanId; traces=$traces }
            return $true
        }

        'POST /audit/frontend-error' {
            $ip = if ($Request.RemoteEndPoint) { $Request.RemoteEndPoint.Address.ToString() } else { '0.0.0.0' }
            if (-not (Test-FrontendErrorAllowed -Ip $ip)) {
                Write-JsonResponse $Request $Response 429 @{ error='rate-limited' }
                return $true
            }

            $raw = Read-EMSRequestBody -Request $Request -MaxBytes 4096
            if (-not $raw) { Write-JsonResponse $Request $Response 400 @{error='empty'}; return $true }

            try { $body = $raw | ConvertFrom-Json -ErrorAction Stop }
            catch { Write-JsonResponse $Request $Response 400 @{error='bad json'}; return $true }

            $clip = { param($s,$n) if (-not $s) {''} elseif ($s.Length -gt $n) {$s.Substring(0,$n)} else {$s} }
            $enc  = { param($s) [System.Net.WebUtility]::HtmlEncode($s) }

            $msg = & $enc (& $clip ([string]$body.message) 1000)
            $stk = & $enc (& $clip ([string]$body.stack)   4000)
            $url = & $enc (& $clip ([string]$body.url)     500)

            $ctx = Get-RequestUserContext -Request $Request
            $performedBy = if ($ctx.Username) { $ctx.Username } else { 'FrontendApp' }

            Invoke-PGQuery -NonQuery -Query @"
INSERT INTO audit_api_requests (method, path, username, ip_address, status_code, response_time_ms, timestamp, error_message)
VALUES ('ERROR', @path, @username, CAST(@ip AS inet), 500, 0, NOW(), @errorMsg);
"@ -Parameters @{ 
                path = '/audit/frontend-error';
                errorMsg = "[FRONTEND CRASH] " + (@{message=$msg; stack=$stk; url=$url} | ConvertTo-Json -Compress);
                username = $performedBy;
                ip = $ip
            }
            
            Write-JsonResponse $Request $Response 204 $null
            return $true
        }
    }

    return $false
}

Export-ModuleMember -Function Invoke-ScanRoutes
