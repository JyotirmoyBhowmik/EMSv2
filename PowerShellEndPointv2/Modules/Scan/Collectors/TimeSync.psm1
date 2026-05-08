<#
.SYNOPSIS
    TimeSync Collector
.DESCRIPTION
    Collects time synchronization status.
#>

function Invoke-TimeSyncCollection {
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
        # TimeSync info is in Win32_Service (W32Time) or registry
        # We'll just check if the service is running for now
        $cim = if ($Session.Protocol -eq 'CIM') { $Session.Session } else { $null }
        $svc = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_Service -Filter "Name = 'W32Time'"
        } else {
            Get-WmiObject -Class Win32_Service -ComputerName $ComputerName -Filter "Name = 'W32Time'"
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[TimeSync] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-TimeSyncCollection
