<#
    EMS.API.Scan.psm1
    Handles scan execution, status, results, and archiving.
#>

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
        if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
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
        if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
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
            if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
            $body = Read-JsonBody $Request
            if (-not $body.target) { 
                Write-JsonResponse $Request $Response 400 @{ success = $false; message = 'Target is required' }
                return $true 
            }
            $scanId = [guid]::NewGuid()
            Invoke-PGQuery -NonQuery -Query "INSERT INTO scans (scan_id, target, status, started_at) VALUES (@scanId, @target, 'queued', NOW());" -Parameters @{ scanId = $scanId; target = $body.target }
            Start-EMSScan -ScanId $scanId -Target $body.target
            Write-JsonResponse $Request $Response 202 @{ success = $true; scanId = $scanId; status = 'queued' }
            return $true
        }

        'POST /scan/bulk' {
            if (-not (Require-AdminAccess -Request $Request -Response $Response -Config $Config)) { return $true }
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
            
            try {
                $batch = Start-EMSBatchScan -Targets $targets
                Write-JsonResponse $Request $Response 202 @{ success=$true; message='Bulk scan queued successfully'; targetCount=$batch.targetCount; queuedScanCount=$batch.scanIds.Count; targets=$batch.targets; scanIds=$batch.scanIds; status='queued' }
            } catch { 
                Write-JsonResponse $Request $Response 400 @{ success = $false; message = $_.Exception.Message } 
            }
            return $true
        }

        'GET /scan/status' {
            if (-not (Require-ViewerAccess -Request $Request -Response $Response -Config $Config)) { return $true }
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

        'POST /audit/frontend-error' {
            $body = Read-JsonBody $Request
            $ctx = Get-RequestUserContext -Request $Request
            $performedBy = if ($ctx.Username) { $ctx.Username } else { 'FrontendApp' }
            
            Invoke-PGQuery -NonQuery -Query @"
INSERT INTO audit_api_requests (method, path, username, ip_address, status_code, response_time_ms, timestamp, error_message)
VALUES ('ERROR', @path, @username, CAST(@ip AS inet), 500, 0, NOW(), @errorMsg);
"@ -Parameters @{ 
                path = if ($body.url) { $body.url } else { '/frontend' };
                errorMsg = "[FRONTEND CRASH] " + ($body.message | Out-String).Trim() + " | Stack: " + ($body.stack | Out-String).Trim();
                username = $performedBy;
                ip = if ($Request.RemoteEndPoint) { $Request.RemoteEndPoint.Address.ToString() } else { '0.0.0.0' }
            }
            
            Write-JsonResponse $Request $Response 200 @{ success = $true; message = 'Error logged successfully' }
            return $true
        }
    }

    return $false
}

Export-ModuleMember -Function Invoke-ScanRoutes
