<#
.SYNOPSIS
 EMS Scan Worker
.DESCRIPTION
 Executes endpoint scans runspaces
#>

Import-Module "$PSScriptRoot\ScanRunspacePool.psm1"
Import-Module "$PSScriptRoot\..\Database\PSPGSql.psm1"
Import-Module "$PSScriptRoot\..\Logging.psm1"

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

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.RunspacePool = $pool

    $ps.AddScript({
        param($ScanId, $Target, $Protocol)

        try {
            # Load necessary modules
            $root = "c:\Users\jyotu\Desktop\EndpointManagement\EMS\PowerShellEndPointv2"
            Import-Module "$root\Modules\Database\PSPGSql.psm1" -Force
            Import-Module "$root\Modules\Logging.psm1" -Force
            Import-Module "$root\Modules\DataFetcher.psm1" -Force
            
            $Config = Get-Content "$root\Config\EMSConfig.json" | ConvertFrom-Json

            Invoke-PGQuery -NonQuery -Query "UPDATE scans SET status='running' WHERE scan_id=@id" -Parameters @{ id = $ScanId }
            Write-EMSLog -Message "Scan started" -Category Scan -Target $Target -CorrelationId $ScanId
            Write-ScanTrace -ScanId $ScanId -StepName "Initialization" -ModuleName "ScanWorker" -Message "Starting scan for $Target"

            $start = Get-Date

            # Resolve Target to Topology
            Write-ScanTrace -ScanId $ScanId -StepName "Topology Detection" -ModuleName "TopologyDetector" -Message "Detecting topology for $Target"
            Import-Module "$root\Modules\TopologyDetector.psm1" -Force
            $enrichedTarget = Get-TargetTopology -Target $Target -Config $Config.Topology
            
            # Execute Data Fetch
            Write-ScanTrace -ScanId $ScanId -StepName "Data Fetch" -ModuleName "DataFetcher" -Message "Invoking data fetch (Protocol: $(if ($Protocol) { $Protocol } else { 'Auto' }))"
            $results = Invoke-DataFetch -Targets @($enrichedTarget) -Config $Config -Protocol $Protocol
            
            $result = $results[0]
            
            if ($result.Status -eq 'Error') {
                throw $result.Error
            }

            $duration = [int](New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds
            $json = $result | ConvertTo-Json -Depth 10

            Invoke-PGQuery -NonQuery -Query "
                UPDATE scans SET
                    status='completed',
                    health_score=@hs,
                    critical_alerts=@c,
                    warning_alerts=@w,
                    info_alerts=@i,
                    execution_time_sec=@d,
                    result_json=@r,
                    completed_at=NOW()
                WHERE scan_id=@id
            " -Parameters @{
                id = $ScanId
                hs = $result.HealthScore
                c  = $result.CriticalAlerts
                w  = $result.WarningAlerts
                i  = 0 # Add mapping if needed
                d  = $duration
                r  = $json
            }

            Write-ScanTrace -ScanId $ScanId -StepName "Finalization" -ModuleName "ScanWorker" -Message "Scan completed successfully"
            Write-EMSLog -Message "Scan completed successfully" -Severity Success -Category Scan -Target $Target -CorrelationId $ScanId
        }
        catch {
            Invoke-PGQuery -NonQuery -Query "
                UPDATE scans SET
                    status='failed',
                    error_message=@err,
                    completed_at=NOW()
                WHERE scan_id=@id
            " -Parameters @{
                id  = $ScanId
                err = $_.Exception.Message
            }

            Write-ScanTrace -ScanId $ScanId -StepName "Error" -ModuleName "ScanWorker" -Status "Error" -Message $_.Exception.Message
            Write-EMSLog -Message "Scan failed: $($_.Exception.Message)" -Severity Error -Category Scan -Target $Target -CorrelationId $ScanId
        }
    }).AddArgument($ScanId).AddArgument($Target).AddArgument($Protocol)

    $ps.BeginInvoke() | Out-Null
}

# -------------------------
# Start EMS Batch Scan
# -------------------------
function Start-EMSBatchScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Targets,
        
        [string]$Protocol = $null
    )

    # Expand CIDR ranges and resolve unique targets
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