<#
.SYNOPSIS
    EMS Scan Worker (Collector-Based)
.DESCRIPTION
    Orchestrates endpoint scans using modular collectors.
#>

Import-Module "$PSScriptRoot\ScanRunspacePool.psm1"
Import-Module "$PSScriptRoot\..\Database\PSPGSql.psm1"
Import-Module "$PSScriptRoot\..\Logging.psm1"
Import-Module "$PSScriptRoot\HealthScore.psm1"
Import-Module "$PSScriptRoot\DBWriter.psm1"
Import-Module "$PSScriptRoot\Collectors\Connectivity.psm1"

# -------------------------
# Trace Logging Helper
# -------------------------
function Write-ScanTrace {
    param(
        [Guid]$ScanId,
        [string]$StepName,
        [string]$ModuleName,
        [string]$Status = 'Info',
        [string]$Message = ''
    )
    
    try {
        Invoke-PGQuery -NonQuery -Query @"
            INSERT INTO scan_trace (scan_id, step_name, module_name, status, message)
            VALUES (@id, @step, @mod, @stat, @msg)
"@ -Parameters @{
            id   = $ScanId
            step = $StepName
            mod  = $ModuleName
            stat = $Status
            msg  = $Message
        }
    } catch {
        # Fallback to general log if table missing or error
        Write-EMSLog -Message "[$StepName][$ModuleName] $Message" -Category 'Trace' -CorrelationId $ScanId
    }
}

# -------------------------
# Start EMS Scan
# -------------------------
function Start-EMSScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Guid]$ScanId,

        [Parameter(Mandatory)]
        [string]$Target,

        [Parameter(Mandatory)]
        [string]$Protocol = $null
    )

    $pool = Get-ScanRunspacePool

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.RunspacePool = $pool

    $ps.AddScript({
        param($ScanId, $Target, $Protocol)

        try {
            $root = "c:\Users\jyotu\Desktop\EndpointManagement\EMS\PowerShellEndPointv2"
            
            # Load required modules
            Import-Module "$root\Modules\Logging.psm1" -Force
            Import-Module "$root\Modules\Database\PSPGSql.psm1" -Force
            Import-Module "$root\Modules\Scan\DBWriter.psm1" -Force
            Import-Module "$root\Modules\Scan\HealthScore.psm1" -Force
            Import-Module "$root\Modules\Scan\Collectors\Connectivity.psm1" -Force
            
            $config = Get-Content "$root\Config\EMSConfig.json" | ConvertFrom-Json
            Initialize-PostgreSQLConnection -Config $config

            # 1. Initialize Scan
            Invoke-PGQuery -NonQuery -Query "UPDATE scans SET status='running' WHERE scan_id=@id" -Parameters @{ id = $ScanId }
            Write-ScanTrace -ScanId $ScanId -StepName "Initialization" -ModuleName "ScanWorker" -Message "Starting collector-based scan for $Target"

            $start = Get-Date
            $collectorResults = @{}
            $allErrors = @()

            # 2. Connect to Endpoint
            Write-ScanTrace -ScanId $ScanId -StepName "Connectivity" -ModuleName "Connectivity" -Message "Connecting to $Target..."
            $conn = Connect-EMSEndpoint -ComputerName $Target -TimeoutSeconds $config.Topology.CIMSessionTimeout
            
            if (-not $conn.Connected) {
                $errorMsg = if ($conn.Error) { $conn.Error } else { "Failed to connect to $Target" }
                Write-ScanTrace -ScanId $ScanId -StepName "Connectivity" -ModuleName "Connectivity" -Status "Error" -Message $errorMsg
                throw $errorMsg
            }

            Write-ScanTrace -ScanId $ScanId -StepName "Connectivity" -ModuleName "Connectivity" -Status "Success" -Message "Connected via $($conn.Protocol)"

            # 3. Invoke Collectors
            $collectors = @(
                'OSInfo', 'CPU', 'Memory', 'Disk',                  # P0
                'Network', 'Services', 'WindowsUpdates', 'BitLocker', # P1
                'Defender', 'Firewall', 'InstalledSoftware', 'LocalUsers',
                'Processes', 'StartupPrograms', 'ScheduledTasks', 'BrowserExtensions', # P2
                'Uptime', 'LoggedOnUsers', 'TimeSync'
            )
            
            foreach ($colName in $collectors) {
                Write-ScanTrace -ScanId $ScanId -StepName "Collection" -ModuleName $colName -Message "Running $colName collector..."
                
                try {
                    $modulePath = "$root\Modules\Scan\Collectors\$colName.psm1"
                    Import-Module $modulePath -Force
                    
                    $funcName = "Invoke-${colName}Collection"
                    if ($colName -eq 'Defender') { $funcName = "Invoke-DefenderCollection" }
                    elseif ($colName -eq 'Firewall') { $funcName = "Invoke-FirewallCollection" }
                    
                    $result = & $funcName -Session $conn -ComputerName $Target -ScanId $ScanId
                    
                    $collectorResults[$colName] = $result
                    if ($result.Success) {
                        # Map to table names
                        $tableName = switch($colName) {
                            'OSInfo'            { 'computers' }
                            'CPU'               { 'metric_cpu_usage' }
                            'Memory'            { 'metric_memory' }
                            'Disk'              { 'metric_disk_space' }
                            'Network'           { 'metric_network_adapters' }
                            'Services'          { 'metric_services' }
                            'WindowsUpdates'    { 'metric_windows_updates' }
                            'BitLocker'         { 'metric_bitlocker' }
                            'Defender'          { 'metric_antivirus' }
                            'Firewall'          { 'metric_firewall' }
                            'InstalledSoftware' { 'metric_installed_software' }
                            'LocalUsers'        { 'metric_user_accounts' }
                            'Processes'         { 'metric_processes' }
                            'StartupPrograms'   { 'metric_startup_programs' }
                            'ScheduledTasks'    { 'metric_scheduled_tasks' }
                            'BrowserExtensions' { 'metric_browser_extensions' }
                            'Uptime'            { 'metric_system_uptime' }
                            'LoggedOnUsers'     { 'metric_login_history' }
                            'TimeSync'          { $null } # Currently no table
                            Default             { $null }
                        }
                        
                        if ($tableName -and $result.Metrics.Count -gt 0) {
                            Write-MetricsToDatabase -TableName $tableName -Metrics $result.Metrics
                        }
                        
                        Write-ScanTrace -ScanId $ScanId -StepName "Collection" -ModuleName $colName -Status "Success" -Message "Collected $($result.Metrics.Count) metrics in $($result.Duration)s"
                    }
                    else {
                        $allErrors += $result.Errors
                        Write-ScanTrace -ScanId $ScanId -StepName "Collection" -ModuleName $colName -Status "Warning" -Message ($result.Errors -join '; ')
                    }
                }
                catch {
                    $allErrors += "[$colName] Error: $($_.Exception.Message)"
                    Write-ScanTrace -ScanId $ScanId -StepName "Collection" -ModuleName $colName -Status "Error" -Message $_.Exception.Message
                }
            }

            # 4. Disconnect
            Disconnect-EMSEndpoint -Session $conn

            # 5. Calculate Health Score
            Write-ScanTrace -ScanId $ScanId -StepName "Scoring" -ModuleName "HealthScore" -Message "Calculating health score..."
            $score = Compute-EMSHealthScore -CollectorResults $collectorResults
            
            # 6. Finalize Scan
            $duration = [int](Get-Date - $start).TotalSeconds
            
            Invoke-PGQuery -NonQuery -Query @"
                UPDATE scans SET
                    status='completed',
                    health_score=@hs,
                    execution_time_sec=@d,
                    completed_at=NOW()
                WHERE scan_id=@id
"@ -Parameters @{
                id = $ScanId
                hs = $score
                d  = $duration
            }

            Write-ScanTrace -ScanId $ScanId -StepName "Finalization" -ModuleName "ScanWorker" -Status "Success" -Message "Scan completed. Score: $score, Time: ${duration}s"

        }
        catch {
            Invoke-PGQuery -NonQuery -Query "UPDATE scans SET status='failed', error_message=@err, completed_at=NOW() WHERE scan_id=@id" -Parameters @{
                id  = $ScanId
                err = $_.Exception.Message
            }
            Write-ScanTrace -ScanId $ScanId -StepName "Error" -ModuleName "ScanWorker" -Status "Error" -Message $_.Exception.Message
            Write-EMSLog -Message "Scan failed for $Target: $($_.Exception.Message)" -Severity 'Error' -Category 'Scan' -CorrelationId $ScanId
        }
    }).AddArgument($ScanId).AddArgument($Target)

    $ps.BeginInvoke() | Out-Null
}

function Start-EMSBatchScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Targets
    )
    
    # Resolve and expand targets
    Import-Module "$PSScriptRoot\..\Core\EMS.Core.psm1" -Force
    $resolvedTargets = Resolve-ScanTargets -Targets $Targets
    
    $scanIds = @()
    foreach ($target in $resolvedTargets) {
        $scanId = [guid]::NewGuid()
        $scanIds += $scanId
        
        # Insert initial record
        Invoke-PGQuery -NonQuery -Query "INSERT INTO scans (scan_id, target, status, started_at) VALUES (@scanId, @target, 'queued', NOW());" -Parameters @{ scanId = $scanId; target = $target }
        
        # Start individual scan
        Start-EMSScan -ScanId $scanId -Target $target -Protocol $protocol
    }

    return [pscustomobject]@{
        targetCount = $resolvedTargets.Count
        scanIds     = $scanIds
    }
}

Export-ModuleMember -Function Start-EMSScan, Start-EMSBatchScan, Write-ScanTrace