<#
.SYNOPSIS
    CPU Collector
.DESCRIPTION
    Collects CPU specification and usage metrics.
#>

function Invoke-CPUCollection {
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
        $cim = if ($Session.Protocol -eq 'CIM') { $Session.Session } else { $null }
        
        $cpus = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_Processor -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_Processor -ComputerName $ComputerName -ErrorAction Stop
        }
        
        foreach ($cpu in $cpus) {
            $results.Metrics += [PSCustomObject]@{
                computer_name      = $ComputerName
                usage_percent      = [decimal]$cpu.LoadPercentage
                core_count         = [int]$cpu.NumberOfCores
                logical_processors = [int]$cpu.NumberOfLogicalProcessors
                processor_name     = $cpu.Name.Trim()
                processor_speed_mhz = [int]$cpu.MaxClockSpeed
                l2_cache_kb        = [int]$cpu.L2CacheSize
                l3_cache_mb        = [int]($cpu.L3CacheSize / 1024)
            }
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[CPU] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-CPUCollection
