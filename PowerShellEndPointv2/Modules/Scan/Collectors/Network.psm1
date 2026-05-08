<#
.SYNOPSIS
    Network Collector
.DESCRIPTION
    Collects network adapter configuration and status.
#>

function Invoke-NetworkCollection {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][Guid]$ScanId,
        [int]$TimeoutSeconds = 15
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
        
        # 1. Get Adapter Config (IPs, DHCP, DNS)
        $configs = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled = True" -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_NetworkAdapterConfiguration -ComputerName $ComputerName -Filter "IPEnabled = True" -ErrorAction Stop
        }
        
        # 2. Get Adapter Hardware (Link Speed, MAC)
        $adapters = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_NetworkAdapter -Filter "NetEnabled = True" -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_NetworkAdapter -ComputerName $ComputerName -Filter "NetEnabled = True" -ErrorAction Stop
        }
        
        foreach ($adapter in $adapters) {
            $config = $configs | Where-Object { $_.Index -eq $adapter.Index -or $_.InterfaceIndex -eq $adapter.InterfaceIndex }
            
            $results.Metrics += [PSCustomObject]@{
                computer_name    = $ComputerName
                adapter_name     = $adapter.Name
                mac_address      = $adapter.MACAddress
                ip_addresses     = if ($config) { [string[]]$config.IPAddress } else { @() }
                adapter_status   = $adapter.NetConnectionStatus
                link_speed_mbps  = [int]($adapter.Speed / 1MB)
                duplex_mode      = 'Unknown' # Hard to get via WMI/CIM reliably
                dhcp_enabled     = if ($config) { [bool]$config.DHCPEnabled } else { $false }
                dns_servers      = if ($config) { [string[]]$config.DNSServerSearchOrder } else { @() }
                is_wireless      = ($adapter.AdapterTypeId -eq 9 -or $adapter.Name -match 'Wireless|Wi-Fi')
            }
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[Network] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-NetworkCollection
