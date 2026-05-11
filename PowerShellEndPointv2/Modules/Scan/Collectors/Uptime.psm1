<#
.SYNOPSIS
    Uptime Collector
.DESCRIPTION
    Collects system boot time and calculates uptime.
#>

function Invoke-UptimeCollection {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][Guid]$ScanId,
        [int]$TimeoutSeconds = 10
    )
    
    $results = @{
        ScanId   = $ScanId
        Success  = $false
        Metrics  = @()
        Errors   = @()
        Duration = 0
    }
    
    $sw = [Diagnostics.Stopwatch]::StartNew()
    
    try {
        $cim = if ($Session.Protocol -match 'CIM') { $Session.Session } else { $null }
        
        $os = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_OperatingSystem -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_OperatingSystem -ComputerName $ComputerName -ErrorAction Stop
        }
        
        $lastBoot = $os.LastBootUpTime
        $uptime = New-TimeSpan -Start $lastBoot -End (Get-Date)
        
        $results.Metrics += [PSCustomObject]@{
            computer_name        = $ComputerName
            last_boot_time       = $lastBoot
            uptime_days          = [int]$uptime.Days
            uptime_hours         = [int]$uptime.Hours
            uptime_minutes       = [int]$uptime.Minutes
            total_uptime_minutes = [int]$uptime.TotalMinutes
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[Uptime] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-UptimeCollection
