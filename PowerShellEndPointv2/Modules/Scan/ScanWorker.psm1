<#
.SYNOPSIS
 EMS Scan Worker
.DESCRIPTION
 Executes endpoint scans runspaces
#>

Import-Module "$PSScriptRoot\ScanRunspacePool.psm1" -Force
Import-Module "$PSScriptRoot\..\Database\PSPGSql.psm1" -Force
Import-Module "$PSScriptRoot\..\Logging.psm1" -Force

# -------------------------
# Start EMS Scan
# -------------------------
function Start-EMSScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Guid]$ScanId,

        [Parameter(Mandatory)]
        [string]$Target
    )

    $pool = Get-ScanRunspacePool

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.RunspacePool = $pool

    $ps.AddScript({
        param($ScanId, $Target)

        try {
            Invoke-PGQuery -NonQuery -Query "
                UPDATE scans SET status='running'
                WHERE scan_id=@id
            " -Parameters @{ id = $ScanId }

            Write-EMSLog -Message "Scan started" -Category Scan -Target $Target -CorrelationId $ScanId

            $start = Get-Date

            # ===================================================
            # REAL SCAN LOGIC (Replace gradually with collectors)
            # ===================================================
            Test-Connection -ComputerName $Target -Count 1 -ErrorAction Stop | Out-Null
            Start-Sleep -Seconds 3
            # ===================================================

            $result = @{
                hostname        = $Target
                healthScore     = 92
                criticalAlerts  = 0
                warningAlerts   = 1
                infoAlerts      = 2
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
                hs = $result.healthScore
                c  = $result.criticalAlerts
                w  = $result.warningAlerts
                i  = $result.infoAlerts
                d  = $duration
                r  = $json
            }

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

            Write-EMSLog -Message "Scan failed: $($_.Exception.Message)" -Severity Error -Category Scan -Target $Target -CorrelationId $ScanId
        }
    }).AddArgument($ScanId).AddArgument($Target)

    $ps.BeginInvoke() | Out-Null
}

Export-ModuleMember -Function Start-EMSScan