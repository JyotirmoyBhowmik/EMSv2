<#
    Get-LastReboot.psm1
    EMS v3.0 — Reboot Monitoring Module
    Collects last restart time, calculates uptime, classifies health status.
#>

function Get-EndpointRebootInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        [int]$WarningThresholdDays = 14,
        [int]$CriticalThresholdDays = 30
    )

    try {
        $cimParams = @{
            ComputerName = $ComputerName
            ClassName    = 'Win32_OperatingSystem'
            Property     = 'LastBootUpTime', 'CSName'
            ErrorAction  = 'Stop'
        }

        $os = Get-CimInstance @cimParams

        if (-not $os -or -not $os.LastBootUpTime) {
            return [pscustomobject]@{
                ComputerName = $ComputerName
                LastBootTime = $null
                UptimeDays   = -1
                UptimeStatus = 'Unknown'
                ErrorMessage = 'Unable to retrieve boot time'
            }
        }

        $lastBoot  = $os.LastBootUpTime
        $uptimeDays = [math]::Floor(((Get-Date) - $lastBoot).TotalDays)

        $status = switch ($true) {
            ($uptimeDays -ge $CriticalThresholdDays) { 'Critical' }
            ($uptimeDays -ge $WarningThresholdDays)  { 'Warning'  }
            default                                   { 'Normal'   }
        }

        return [pscustomobject]@{
            ComputerName = $ComputerName
            LastBootTime = $lastBoot
            UptimeDays   = $uptimeDays
            UptimeStatus = $status
            ErrorMessage = $null
        }
    }
    catch {
        return [pscustomobject]@{
            ComputerName = $ComputerName
            LastBootTime = $null
            UptimeDays   = -1
            UptimeStatus = 'Unreachable'
            ErrorMessage = $_.Exception.Message
        }
    }
}

function Save-RebootInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject]$RebootInfo
    )

    if ($RebootInfo.UptimeStatus -eq 'Unreachable') { return }

    $lastBootStr = if ($RebootInfo.LastBootTime) { $RebootInfo.LastBootTime.ToString('yyyy-MM-dd HH:mm:ss') } else { $null }

    Invoke-PGQuery -NonQuery -Query @"
INSERT INTO metric_reboot_tracking (computer_name, last_boot_time, uptime_days, uptime_status)
VALUES (@computerName, @lastBootTime, @uptimeDays, @uptimeStatus)
ON CONFLICT (computer_name, timestamp) DO UPDATE
SET last_boot_time = EXCLUDED.last_boot_time,
    uptime_days = EXCLUDED.uptime_days,
    uptime_status = EXCLUDED.uptime_status;
"@ -Parameters @{
        computerName = $RebootInfo.ComputerName
        lastBootTime = $lastBootStr
        uptimeDays   = $RebootInfo.UptimeDays
        uptimeStatus = $RebootInfo.UptimeStatus
    }
}

Export-ModuleMember -Function Get-EndpointRebootInfo, Save-RebootInfo
