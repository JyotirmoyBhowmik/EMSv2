<#
.SYNOPSIS
    Memory Collector
.DESCRIPTION
    Collects physical and virtual memory usage metrics.
#>

function Invoke-MemoryCollection {
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
        
        $totalVisibleKB = $os.TotalVisibleMemorySize
        $freeKB = $os.FreePhysicalMemory
        
        $totalGB = [math]::Round($totalVisibleKB / 1MB, 2)
        $availGB = [math]::Round($freeKB / 1MB, 2)
        $usedGB = $totalGB - $availGB
        $usagePercent = [math]::Round(($usedGB / $totalGB) * 100, 2)
        
        $results.Metrics += [PSCustomObject]@{
            computer_name           = $ComputerName
            total_gb                = [decimal]$totalGB
            available_gb            = [decimal]$availGB
            used_gb                 = [decimal]$usedGB
            usage_percent           = [decimal]$usagePercent
            committed_gb            = [decimal][math]::Round(($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / 1MB, 2)
            page_file_total_gb      = [decimal][math]::Round(($os.SizeStoredInPagingFiles) / 1MB, 2)
            page_file_usage_percent = [decimal][math]::Round((($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / $os.TotalVirtualMemorySize) * 100, 2)
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[Memory] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-MemoryCollection
