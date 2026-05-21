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

$script:InFlightScans = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

function Invoke-EMSScanReaper {
    $still = [System.Collections.Generic.List[object]]::new()
    $items = @($script:InFlightScans.ToArray())
    $script:InFlightScans = [System.Collections.Concurrent.ConcurrentBag[object]]::new()

    foreach ($r in $items) {
        if ($r.Handle.IsCompleted) {
            try { [void]$r.PS.EndInvoke($r.Handle) }
            catch { Write-EMSLog "Scan $($r.ScanId) failed: $($_.Exception.Message)" -Severity Error }
            finally { $r.PS.Dispose() }
        } elseif (((Get-Date) - $r.Started).TotalMinutes -gt 30) {
            try { $r.PS.Stop() } catch {}
            $r.PS.Dispose()
            Write-EMSLog "Scan $($r.ScanId) killed (timeout)" -Severity Warning
        } else {
            $still.Add($r)
        }
    }
    foreach ($x in $still) { $script:InFlightScans.Add($x) }
}

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

        # Import the refactored Scan Execution module
        Import-Module "$root\Modules\Scan\ScanExecution.psm1" -Force -ErrorAction Stop

        # Execute the scan job
        Invoke-EMSScanExecution -ScanId $ScanId -Target $Target -Protocol $Protocol -Root $root

    }).AddArgument($ScanId).AddArgument($Target).AddArgument($Protocol).AddArgument($rootPath)

    $handle = $ps.BeginInvoke()
    
    $script:InFlightScans.Add([pscustomobject]@{
        PS=$ps; Handle=$handle; ScanId=$ScanId; Started=Get-Date })

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
