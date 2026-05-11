<#
.SYNOPSIS
    EMS Scan Worker (Collector-Based)
.DESCRIPTION
    Orchestrates endpoint scans using modular collectors.
    Runs each scan in a separate runspace for concurrency.
#>

Import-Module "$PSScriptRoot\ScanRunspacePool.psm1"
Import-Module "$PSScriptRoot\..\Database\PSPGSql.psm1"
Import-Module "$PSScriptRoot\..\Logging.psm1"
Import-Module "$PSScriptRoot\HealthScore.psm1"
Import-Module "$PSScriptRoot\DBWriter.psm1"
Import-Module "$PSScriptRoot\Collectors\Connectivity.psm1"

# Compute the project root path at import time (in the parent scope)
$script:EMSRoot = (Resolve-Path "$PSScriptRoot\..\..").Path

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

        [string]$Protocol = $null
    )

    $pool = Get-ScanRunspacePool
    # Capture root path to pass into runspace
    $rootPath = $script:EMSRoot

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.RunspacePool = $pool

    $ps.AddScript({
        param($ScanId, $Target, $Protocol, $root)

        # Write a log file for debugging (always)
        $scanLogPath = Join-Path $root "Logs\scan_$($ScanId).log"
        function Write-ScanLog {
            param([string]$Msg)
            try {
                $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                Add-Content -Path $scanLogPath -Value "[$ts] $Msg" -ErrorAction SilentlyContinue
            } catch {}
        }
        
        Write-ScanLog "=== SCAN START: $Target (ID: $ScanId) ==="

        try {
            # Load required modules
            Write-ScanLog "Loading modules from: $root"
            Import-Module "$root\Modules\Logging.psm1" -Force -ErrorAction Stop
            Import-Module "$root\Modules\Database\PSPGSql.psm1" -Force -ErrorAction Stop
            Import-Module "$root\Modules\Scan\DBWriter.psm1" -Force -ErrorAction Stop
            Import-Module "$root\Modules\Scan\HealthScore.psm1" -Force -ErrorAction Stop
            Import-Module "$root\Modules\Scan\Collectors\Connectivity.psm1" -Force -ErrorAction Stop
            Write-ScanLog "Modules loaded successfully"
            
            $config = Get-Content "$root\Config\EMSConfig.json" -Raw | ConvertFrom-Json
            Initialize-PostgreSQLConnection -Config $config
            Write-ScanLog "DB connection initialized"

            # --- Define Write-ScanTrace inside the runspace (no parent scope access) ---
            function Write-ScanTrace {
                param([Guid]$ScanId, [string]$StepName, [string]$ModuleName, [string]$Status = 'Info', [string]$Message = '')
                try {
                    Invoke-PGQuery -NonQuery -Query "INSERT INTO scan_trace (scan_id, step_name, module_name, status, message) VALUES (@id, @step, @mod, @stat, @msg)" -Parameters @{
                        id = $ScanId; step = $StepName; mod = $ModuleName; stat = $Status; msg = $Message
                    }
                } catch {
                    Write-EMSLog -Message "[$StepName][$ModuleName] $Message" -Category 'Trace' -CorrelationId $ScanId
                }
            }

            # --- Load service credential if available ---
            $scanCredential = $null
            try {
                $credModule = "$root\Modules\Security\EMS.Credentials.psm1"
                if (Test-Path $credModule) {
                    Import-Module $credModule -Force
                    $scanCredential = Get-EMSServiceCredential -CredentialType 'ScanService'
                    if ($scanCredential) {
                        Write-ScanLog "Loaded scan credential: $($scanCredential.UserName)"
                    }
                }
            } catch {
                Write-ScanLog "No stored scan credential: $($_.Exception.Message)"
            }

            # 1. Initialize Scan
            Invoke-PGQuery -NonQuery -Query "UPDATE scans SET status='running' WHERE scan_id=@id" -Parameters @{ id = $ScanId }
            Write-ScanTrace -ScanId $ScanId -StepName "Initialization" -ModuleName "ScanWorker" -Message "Starting collector-based scan for $Target"
            Write-ScanLog "Scan status set to 'running'"

            $start = Get-Date
            $collectorResults = @{}
            $allErrors = @()

            # 2. Connect to Endpoint
            Write-ScanTrace -ScanId $ScanId -StepName "Connectivity" -ModuleName "Connectivity" -Message "Connecting to $Target..."
            Write-ScanLog "Connecting to $Target..."
            
            $connectParams = @{
                ComputerName   = $Target
                TimeoutSeconds = 15
            }
            if ($config.Topology.CIMSessionTimeout) {
                $connectParams.TimeoutSeconds = [int]$config.Topology.CIMSessionTimeout
            }
            if ($scanCredential) {
                $connectParams['Credential'] = $scanCredential
            }
            
            $conn = Connect-EMSEndpoint @connectParams
            
            if (-not $conn.Connected) {
                $errorMsg = if ($conn.Error) { $conn.Error } else { "Failed to connect to $Target" }
                Write-ScanTrace -ScanId $ScanId -StepName "Connectivity" -ModuleName "Connectivity" -Status "Error" -Message $errorMsg
                Write-ScanLog "Connection FAILED: $errorMsg"
                throw $errorMsg
            }

            Write-ScanTrace -ScanId $ScanId -StepName "Connectivity" -ModuleName "Connectivity" -Status "Success" -Message "Connected via $($conn.Protocol)"
            Write-ScanLog "Connected via $($conn.Protocol)"

            # 3. Invoke Collectors
            $collectors = @(
                'OSInfo', 'CPU', 'Memory', 'Disk',
                'Network', 'Services', 'WindowsUpdates', 'BitLocker',
                'Defender', 'Firewall', 'InstalledSoftware', 'LocalUsers',
                'Processes', 'StartupPrograms', 'ScheduledTasks', 'BrowserExtensions',
                'Uptime', 'LoggedOnUsers', 'TimeSync'
            )
            
            foreach ($colName in $collectors) {
                Write-ScanTrace -ScanId $ScanId -StepName "Collection" -ModuleName $colName -Message "Running $colName collector..."
                
                try {
                    $modulePath = "$root\Modules\Scan\Collectors\$colName.psm1"
                    if (-not (Test-Path $modulePath)) {
                        Write-ScanLog "Collector not found: $modulePath"
                        $allErrors += "[$colName] Module file not found"
                        continue
                    }
                    Import-Module $modulePath -Force
                    
                    $funcName = "Invoke-${colName}Collection"
                    
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
                            'TimeSync'          { $null }
                            Default             { $null }
                        }
                        
                        if ($tableName -and $result.Metrics -and $result.Metrics.Count -gt 0) {
                            try {
                                Write-MetricsToDatabase -TableName $tableName -Metrics $result.Metrics
                            } catch {
                                Write-ScanLog "[$colName] DB write failed: $($_.Exception.Message)"
                            }
                        }
                        
                        $metricCount = if ($result.Metrics) { $result.Metrics.Count } else { 0 }
                        $dur = if ($result.Duration) { $result.Duration } else { '?' }
                        Write-ScanTrace -ScanId $ScanId -StepName "Collection" -ModuleName $colName -Status "Success" -Message "Collected $metricCount metrics in ${dur}s"
                        Write-ScanLog "[$colName] SUCCESS: $metricCount metrics"
                    }
                    else {
                        $errMsg = if ($result.Errors) { $result.Errors -join '; ' } else { 'Unknown error' }
                        $allErrors += $errMsg
                        Write-ScanTrace -ScanId $ScanId -StepName "Collection" -ModuleName $colName -Status "Warning" -Message $errMsg
                        Write-ScanLog "[$colName] WARNING: $errMsg"
                    }
                }
                catch {
                    $allErrors += "[$colName] Error: $($_.Exception.Message)"
                    Write-ScanTrace -ScanId $ScanId -StepName "Collection" -ModuleName $colName -Status "Error" -Message $_.Exception.Message
                    Write-ScanLog "[$colName] ERROR: $($_.Exception.Message)"
                }
            }

            # 4. Disconnect
            Disconnect-EMSEndpoint -Session $conn
            Write-ScanLog "Disconnected from $Target"

            # 5. Calculate Health Score
            Write-ScanTrace -ScanId $ScanId -StepName "Scoring" -ModuleName "HealthScore" -Message "Calculating health score..."
            $score = 0
            try {
                $score = Compute-EMSHealthScore -CollectorResults $collectorResults
            } catch {
                $score = 50
                Write-ScanLog "HealthScore calculation failed: $($_.Exception.Message), defaulting to 50"
            }
            
            # 6. Finalize Scan
            $duration = [int]((Get-Date) - $start).TotalSeconds
            
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

            Write-ScanTrace -ScanId $ScanId -StepName "Finalization" -ModuleName "ScanWorker" -Status "Success" -Message "Scan completed. Score: $score, Time: ${duration}s, Errors: $($allErrors.Count)"
            Write-ScanLog "=== SCAN COMPLETED: Score=$score, Duration=${duration}s, Errors=$($allErrors.Count) ==="

        }
        catch {
            Write-ScanLog "=== SCAN FAILED: $($_.Exception.Message) ==="
            Write-ScanLog "Stack: $($_.ScriptStackTrace)"
            try {
                Invoke-PGQuery -NonQuery -Query "UPDATE scans SET status='failed', error_message=@err, completed_at=NOW() WHERE scan_id=@id" -Parameters @{
                    id  = $ScanId
                    err = $_.Exception.Message
                }
                Write-ScanTrace -ScanId $ScanId -StepName "Error" -ModuleName "ScanWorker" -Status "Error" -Message $_.Exception.Message
            } catch {
                Write-ScanLog "Failed to update DB with error: $($_.Exception.Message)"
            }
        }
    }).AddArgument($ScanId).AddArgument($Target).AddArgument($Protocol).AddArgument($rootPath)

    $handle = $ps.BeginInvoke()
    
    # Store handle for monitoring (optional)
    Write-EMSLog -Message "Scan dispatched for $Target (ScanId: $ScanId)" -Severity 'Info' -Category 'Scan'
}

function Start-EMSBatchScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Targets,

        [string]$Protocol = $null
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
        Start-EMSScan -ScanId $scanId -Target $target -Protocol $Protocol
    }

    return [pscustomobject]@{
        targetCount = $resolvedTargets.Count
        scanIds     = $scanIds
        targets     = $resolvedTargets
    }
}

Export-ModuleMember -Function Start-EMSScan, Start-EMSBatchScan, Write-ScanTrace