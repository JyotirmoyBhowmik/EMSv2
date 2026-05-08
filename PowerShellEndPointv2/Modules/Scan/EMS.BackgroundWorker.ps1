<#
.SYNOPSIS
    EMS Background Worker
.DESCRIPTION
    Polls the database for scheduled scans and executes them.
#>

$root = "c:\Users\jyotu\Desktop\EndpointManagement\EMS\PowerShellEndPointv2"
Import-Module "$root\Modules\Logging.psm1" -Force
Import-Module "$root\Modules\Database\PSPGSql.psm1" -Force
Import-Module "$root\Modules\Scan\ScanWorker.psm1" -Force

$config = Get-Content "$root\Config\EMSConfig.json" | ConvertFrom-Json
Initialize-PostgreSQLConnection -Config $config

Write-EMSLog -Message "EMS Background Worker started" -Category 'Background'

while ($true) {
    try {
        # 1. Find schedules that are due
        $dueSchedules = Invoke-PGQuery -Query @"
            SELECT * FROM scheduled_scans 
            WHERE enabled = true 
            AND (next_run IS NULL OR next_run <= NOW())
"@
        
        foreach ($sched in $dueSchedules) {
            Write-EMSLog -Message "Executing scheduled scan: $($sched.schedule_name)" -Category 'Background'
            
            # 2. Trigger Batch Scan
            $targets = $sched.target_list
            if ($targets) {
                $batch = Start-EMSBatchScan -Targets $targets
                Write-EMSLog -Message "Queued $($batch.targetCount) targets for schedule $($sched.schedule_name)" -Category 'Background'
            }
            
            # 3. Update next_run (Simple 24h increment for now if cron logic missing)
            Invoke-PGQuery -NonQuery -Query @"
                UPDATE scheduled_scans 
                SET last_run = NOW(), 
                    next_run = NOW() + INTERVAL '1 day' 
                WHERE schedule_id = @id
"@ -Parameters @{ id = $sched.schedule_id }
        }
    }
    catch {
        Write-EMSLog -Message "Background worker error: $($_.Exception.Message)" -Severity 'Error' -Category 'Background'
    }
    
    Start-Sleep -Seconds 60
}
