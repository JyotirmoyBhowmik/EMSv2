<#
.SYNOPSIS
    InstalledSoftware Collector
.DESCRIPTION
    Collects installed software inventory. Note: Win32_Product can be slow.
#>

function Invoke-InstalledSoftwareCollection {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][Guid]$ScanId,
        [int]$TimeoutSeconds = 60
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
        
        # Win32_Product is slow but standard.
        $software = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_Product -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_Product -ComputerName $ComputerName -ErrorAction Stop
        }
        
        foreach ($app in $software) {
            $results.Metrics += [PSCustomObject]@{
                computer_name       = $ComputerName
                software_name       = $app.Name
                version             = $app.Version
                vendor              = $app.Vendor
                install_date        = try { [DateTime]::ParseExact($app.InstallDate, "yyyyMMdd", $null) } catch { $null }
                install_location    = $app.InstallLocation
                size_mb             = 0 # Not easily available
                install_source      = $app.InstallSource
                is_system_component = $false
            }
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[Software] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-InstalledSoftwareCollection
