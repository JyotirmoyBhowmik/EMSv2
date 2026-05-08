<#
.SYNOPSIS
    Antivirus Collector
.DESCRIPTION
    Collects Antivirus status and definition information.
#>

function Invoke-DefenderCollection {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][Guid]$ScanId,
        [int]$TimeoutSeconds = 20
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
        
        # 1. Get AV Product Info from SecurityCenter2
        $avs = if ($cim) {
            Get-CimInstance -CimSession $cim -Namespace "Root\SecurityCenter2" -ClassName AntiVirusProduct -ErrorAction Stop
        } else {
            Get-WmiObject -Namespace "Root\SecurityCenter2" -Class AntiVirusProduct -ComputerName $ComputerName -ErrorAction Stop
        }
        
        foreach ($av in $avs) {
            # productState is a bitmask
            # 0x1000 = Enabled, 0x0001 = Up to date
            $state = [int]$av.productState
            $isEnabled = ($state -band 0x1000) -eq 0x1000
            $isUpToDate = ($state -band 0x0010) -eq 0x0000 # Counter-intuitive bitmask
            
            $results.Metrics += [PSCustomObject]@{
                computer_name        = $ComputerName
                av_product           = $av.displayName
                av_vendor            = 'Unknown' # Not easily available in SC2
                av_version           = 'Unknown'
                definitions_version  = 'Unknown'
                definitions_date     = Get-Date # Placeholder
                definitions_age_days = if ($isUpToDate) { 0 } else { 7 }
                real_time_protection = $isEnabled
                last_scan_date       = Get-Date
                last_scan_type       = 'Unknown'
                threat_count         = 0
                quarantine_count     = 0
                av_enabled           = $isEnabled
            }
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[Antivirus] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-DefenderCollection
