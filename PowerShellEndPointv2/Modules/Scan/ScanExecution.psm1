<#
.SYNOPSIS
    EMS Scan Execution
.DESCRIPTION
    Encapsulates the core execution logic for endpoint scans, running within a runspace.
#>

function Get-CollectorTableName {
    param([string]$CollectorName)
    switch($CollectorName) {
        'OSInfo'            { return 'computers' }
        'CPU'               { return 'metric_cpu_usage' }
        'Memory'            { return 'metric_memory' }
        'Disk'              { return 'metric_disk_space' }
        'Network'           { return 'metric_network_adapters' }
        'Services'          { return 'metric_services' }
        'WindowsUpdates'    { return 'metric_windows_updates' }
        'BitLocker'         { return 'metric_bitlocker' }
        'Defender'          { return 'metric_antivirus' }
        'Firewall'          { return 'metric_firewall' }
        'InstalledSoftware' { return 'metric_installed_software' }
        'LocalUsers'        { return 'metric_user_accounts' }
        'Processes'         { return 'metric_processes' }
        'StartupPrograms'   { return 'metric_startup_programs' }
        'ScheduledTasks'    { return 'metric_scheduled_tasks' }
        'BrowserExtensions' { return 'metric_browser_extensions' }
        'Uptime'            { return 'metric_system_uptime' }
        'LoggedOnUsers'     { return 'metric_login_history' }
        'TimeSync'          { return $null }
        Default             { return $null }
    }
}

function Write-ScanLog {
    param([string]$ScanLogPath, [string]$Msg)
    try {
        $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        Add-Content -Path $ScanLogPath -Value "[$ts] $Msg" -ErrorAction SilentlyContinue
    } catch {}
}

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

function Initialize-ScanEnvironment {
    param([string]$Root, [string]$ScanLogPath)
    Write-ScanLog -ScanLogPath $ScanLogPath -Msg "Loading modules from: $Root"
    Import-Module "$Root\Modules\Logging.psm1" -Force -ErrorAction Stop
    Import-Module "$Root\Modules\Database\PSPGSql.psm1" -Force -ErrorAction Stop
    Import-Module "$Root\Modules\Scan\DBWriter.psm1" -Force -ErrorAction Stop
    Import-Module "$Root\Modules\Scan\HealthScore.psm1" -Force -ErrorAction Stop
    Import-Module "$Root\Modules\Scan\Collectors\Connectivity.psm1" -Force -ErrorAction Stop
    Write-ScanLog -ScanLogPath $ScanLogPath -Msg "Modules loaded successfully"

    $config = Get-Content "$Root\Config\EMSConfig.json" -Raw | ConvertFrom-Json
    Initialize-PostgreSQLConnection -Config $config
    Write-ScanLog -ScanLogPath $ScanLogPath -Msg "DB connection initialized"
    return $config
}

function Get-ScanCredential {
    param([string]$Root, [string]$ScanLogPath)
    $scanCredential = $null
    try {
        $credModule = "$Root\Modules\Security\EMS.Credentials.psm1"
        if (Test-Path $credModule) {
            Import-Module $credModule -Force
            $scanCredential = Get-EMSServiceCredential -CredentialType 'ScanService'
            if ($scanCredential) {
                Write-ScanLog -ScanLogPath $ScanLogPath -Msg "Loaded scan credential: $($scanCredential.UserName)"
            }
        }
    } catch {
        Write-ScanLog -ScanLogPath $ScanLogPath -Msg "No stored scan credential: $($_.Exception.Message)"
    }
    return $scanCredential
}

function Connect-ScanEndpoint {
    param($Target, $Config, $ScanCredential, $ScanId, $ScanLogPath)
    Write-ScanTrace -ScanId $ScanId -StepName "Connectivity" -ModuleName "Connectivity" -Message "Connecting to $Target..."
    Write-ScanLog -ScanLogPath $ScanLogPath -Msg "Connecting to $Target..."

    $connectParams = @{
        ComputerName   = $Target
        TimeoutSeconds = 15
    }
    if ($Config.Topology.CIMSessionTimeout) {
        $connectParams.TimeoutSeconds = [int]$Config.Topology.CIMSessionTimeout
    }
    if ($ScanCredential) {
        $connectParams['Credential'] = $ScanCredential
    }

    $conn = Connect-EMSEndpoint @connectParams

    if (-not $conn.Connected) {
        $errorMsg = if ($conn.Error) { $conn.Error } else { "Failed to connect to $Target" }
        Write-ScanTrace -ScanId $ScanId -StepName "Connectivity" -ModuleName "Connectivity" -Status "Error" -Message $errorMsg
        Write-ScanLog -ScanLogPath $ScanLogPath -Msg "Connection FAILED: $errorMsg"
        throw $errorMsg
    }

    Write-ScanTrace -ScanId $ScanId -StepName "Connectivity" -ModuleName "Connectivity" -Status "Success" -Message "Connected via $($conn.Protocol)"
    Write-ScanLog -ScanLogPath $ScanLogPath -Msg "Connected via $($conn.Protocol)"
    return $conn
}

function Run-ScanCollectors {
    param($Conn, $Target, $ScanId, $Root, $ScanLogPath, [ref]$AllErrors)
    $collectors = @(
        'OSInfo', 'CPU', 'Memory', 'Disk',
        'Network', 'Services', 'WindowsUpdates', 'BitLocker',
        'Defender', 'Firewall', 'InstalledSoftware', 'LocalUsers',
        'Processes', 'StartupPrograms', 'ScheduledTasks', 'BrowserExtensions',
        'Uptime', 'LoggedOnUsers', 'TimeSync'
    )

    $collectorResults = @{}

    foreach ($colName in $collectors) {
        Write-ScanTrace -ScanId $ScanId -StepName "Collection" -ModuleName $colName -Message "Running $colName collector..."

        try {
            $modulePath = "$Root\Modules\Scan\Collectors\$colName.psm1"
            if (-not (Test-Path $modulePath)) {
                Write-ScanLog -ScanLogPath $ScanLogPath -Msg "Collector not found: $modulePath"
                $AllErrors.Value += "[$colName] Module file not found"
                continue
            }
            Import-Module $modulePath -Force

            $funcName = "Invoke-${colName}Collection"
            $result = & $funcName -Session $Conn -ComputerName $Target -ScanId $ScanId

            $collectorResults[$colName] = $result
            if ($result.Success) {
                $tableName = Get-CollectorTableName -CollectorName $colName

                if ($tableName -and $result.Metrics -and $result.Metrics.Count -gt 0) {
                    try {
                        Write-MetricsToDatabase -TableName $tableName -Metrics $result.Metrics
                    } catch {
                        Write-ScanLog -ScanLogPath $ScanLogPath -Msg "[$colName] DB write failed: $($_.Exception.Message)"
                    }
                }

                $metricCount = if ($result.Metrics) { $result.Metrics.Count } else { 0 }
                $dur = if ($result.Duration) { $result.Duration } else { '?' }
                Write-ScanTrace -ScanId $ScanId -StepName "Collection" -ModuleName $colName -Status "Success" -Message "Collected $metricCount metrics in ${dur}s"
                Write-ScanLog -ScanLogPath $ScanLogPath -Msg "[$colName] SUCCESS: $metricCount metrics"
            }
            else {
                $errMsg = if ($result.Errors) { $result.Errors -join '; ' } else { 'Unknown error' }
                $AllErrors.Value += $errMsg
                Write-ScanTrace -ScanId $ScanId -StepName "Collection" -ModuleName $colName -Status "Warning" -Message $errMsg
                Write-ScanLog -ScanLogPath $ScanLogPath -Msg "[$colName] WARNING: $errMsg"
            }
        }
        catch {
            $AllErrors.Value += "[$colName] Error: $($_.Exception.Message)"
            Write-ScanTrace -ScanId $ScanId -StepName "Collection" -ModuleName $colName -Status "Error" -Message $_.Exception.Message
            Write-ScanLog -ScanLogPath $ScanLogPath -Msg "[$colName] ERROR: $($_.Exception.Message)"
        }
    }

    return $collectorResults
}

function Finalize-ScanExecution {
    param($ScanId, $Score, $Start, $AllErrors, $ScanLogPath)
    $duration = [int]((Get-Date) - $Start).TotalSeconds

    Invoke-PGQuery -NonQuery -Query @"
        UPDATE scans SET
            status='completed',
            health_score=@hs,
            execution_time_sec=@d,
            completed_at=NOW()
        WHERE scan_id=@id
"@ -Parameters @{
        id = $ScanId
        hs = $Score
        d  = $duration
    }

    Write-ScanTrace -ScanId $ScanId -StepName "Finalization" -ModuleName "ScanWorker" -Status "Success" -Message "Scan completed. Score: $Score, Time: ${duration}s, Errors: $($AllErrors.Count)"
    Write-ScanLog -ScanLogPath $ScanLogPath -Msg "=== SCAN COMPLETED: Score=$Score, Duration=${duration}s, Errors=$($AllErrors.Count) ==="
}

function Invoke-EMSScanExecution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [Guid]$ScanId,

        [Parameter(Mandatory=$true)]
        [string]$Target,

        [string]$Protocol,

        [Parameter(Mandatory=$true)]
        [string]$Root
    )

    $scanLogPath = Join-Path $Root "Logs\scan_$($ScanId).log"
    Write-ScanLog -ScanLogPath $scanLogPath -Msg "=== SCAN START: $Target (ID: $ScanId) ==="

    try {
        $config = Initialize-ScanEnvironment -Root $Root -ScanLogPath $scanLogPath
        $scanCredential = Get-ScanCredential -Root $Root -ScanLogPath $scanLogPath

        # 1. Initialize Scan
        Invoke-PGQuery -NonQuery -Query "UPDATE scans SET status='running' WHERE scan_id=@id" -Parameters @{ id = $ScanId }
        Write-ScanTrace -ScanId $ScanId -StepName "Initialization" -ModuleName "ScanWorker" -Message "Starting collector-based scan for $Target"
        Write-ScanLog -ScanLogPath $scanLogPath -Msg "Scan status set to 'running'"

        $start = Get-Date
        $allErrors = @()

        # 2. Connect to Endpoint
        $conn = Connect-ScanEndpoint -Target $Target -Config $config -ScanCredential $scanCredential -ScanId $ScanId -ScanLogPath $scanLogPath

        # 3. Invoke Collectors
        $collectorResults = Run-ScanCollectors -Conn $conn -Target $Target -ScanId $ScanId -Root $Root -ScanLogPath $scanLogPath -AllErrors ([ref]$allErrors)

        # 4. Disconnect
        Disconnect-EMSEndpoint -Session $conn
        Write-ScanLog -ScanLogPath $scanLogPath -Msg "Disconnected from $Target"

        # 5. Calculate Health Score
        Write-ScanTrace -ScanId $ScanId -StepName "Scoring" -ModuleName "HealthScore" -Message "Calculating health score..."
        $score = 0
        try {
            $score = Compute-EMSHealthScore -CollectorResults $collectorResults
        } catch {
            $score = 50
            Write-ScanLog -ScanLogPath $scanLogPath -Msg "HealthScore calculation failed: $($_.Exception.Message), defaulting to 50"
        }

        # 6. Finalize Scan
        Finalize-ScanExecution -ScanId $ScanId -Score $score -Start $start -AllErrors $allErrors -ScanLogPath $scanLogPath
    }
    catch {
        Write-ScanLog -ScanLogPath $scanLogPath -Msg "=== SCAN FAILED: $($_.Exception.Message) ==="
        Write-ScanLog -ScanLogPath $scanLogPath -Msg "Stack: $($_.ScriptStackTrace)"
        try {
            Invoke-PGQuery -NonQuery -Query "UPDATE scans SET status='failed', error_message=@err, completed_at=NOW() WHERE scan_id=@id" -Parameters @{
                id  = $ScanId
                err = $_.Exception.Message
            }
            Write-ScanTrace -ScanId $ScanId -StepName "Error" -ModuleName "ScanWorker" -Status "Error" -Message $_.Exception.Message
        } catch {
            Write-ScanLog -ScanLogPath $scanLogPath -Msg "Failed to update DB with error: $($_.Exception.Message)"
        }
    }
}

Export-ModuleMember -Function Invoke-EMSScanExecution
