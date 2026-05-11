<#
.SYNOPSIS
    Topology detection module for network-aware routing

.DESCRIPTION
    Determines whether targets are local (HO) or remote (MPLS) based on subnet matching
#>

function Get-TargetTopology {
    <#
    .SYNOPSIS
        Determines topology type for a target
    
    .PARAMETER Target
        Hostname or IP address
    
    .PARAMETER ConfigTopology
        Topology configuration object
    
    .RETURNS
        PSCustomObject with Topology, IP, Hostname, ThrottleLimit
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Target,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    try {
        # Resolve to IP address
        $resolvedIP = $null
        
        if ($Target -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
            # Already an IP
            $resolvedIP = $Target
            
            # Try reverse DNS for hostname
            try {
                $hostname = [System.Net.Dns]::GetHostByAddress($Target).HostName
            }
            catch {
                $hostname = $Target
            }
        }
        else {
            # Resolve hostname to IP
            try {
                $dnsResult = Resolve-DnsName -Name $Target -Type A -ErrorAction Stop
                $resolvedIP = $dnsResult[0].IPAddress
                $hostname = $Target
            }
            catch {
                Write-Warning "Failed to resolve $Target"
                return $null
            }
        }
        
        # Determine topology based on subnet matching
        $topology = 'Unknown'
        $throttleLimit = $Config.RemoteThrottleLimit
        
        foreach ($subnet in $Config.HOSubnets) {
            if (Test-IPInSubnet -IPAddress $resolvedIP -Subnet $subnet) {
                $topology = 'HO'
                $throttleLimit = $Config.HOThrottleLimit
                break
            }
        }
        
        if ($topology -eq 'Unknown') {
            foreach ($subnet in $Config.RemoteSubnets) {
                if (Test-IPInSubnet -IPAddress $resolvedIP -Subnet $subnet) {
                    $topology = 'Remote'
                    $throttleLimit = $Config.RemoteThrottleLimit
                    break
                }
            }
        }
        
        return [PSCustomObject]@{
            Hostname       = $hostname
            IP             = $resolvedIP
            Topology       = $topology
            ThrottleLimit  = $throttleLimit
            SessionTimeout = if ($topology -eq 'HO') { 
                $Config.InvokeCommandTimeout 
            }
            else { 
                $Config.CIMSessionTimeout 
            }
        }
        
    }
    catch {
        Write-Error "Topology detection failed for ${Target}: $_"
        return $null
    }
}

function Test-IPInSubnet {
    <#
    .SYNOPSIS
        Tests if an IP address is within a subnet
    
    .PARAMETER IPAddress
        IP address to test
    
    .PARAMETER Subnet
        Subnet in CIDR notation (e.g., 10.192.10.0/23)
    
    .RETURNS
        Boolean
    #>
    param(
        [Parameter(Mandatory)]
        [string]$IPAddress,
        
        [Parameter(Mandatory)]
        [string]$Subnet
    )
    
    try {
        # Parse subnet
        if ($Subnet -match '^(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/(\d{1,2})$') {
            $network = $Matches[1]
            $maskBits = [int]$Matches[2]
        }
        else {
            Write-Warning "Invalid subnet format: $Subnet"
            return $false
        }
        
        # Convert IP and network to binary
        $ipBytes = ([System.Net.IPAddress]::Parse($IPAddress)).GetAddressBytes()
        $networkBytes = ([System.Net.IPAddress]::Parse($network)).GetAddressBytes()
        
        # Create mask
        $maskBytes = [byte[]]@(0, 0, 0, 0)
        $fullBytes = [Math]::Floor($maskBits / 8)
        $remainingBits = $maskBits % 8
        
        for ($i = 0; $i -lt $fullBytes; $i++) {
            $maskBytes[$i] = 255
        }
        
        if ($remainingBits -gt 0) {
            $maskBytes[$fullBytes] = (255 -shl (8 - $remainingBits)) -band 255
        }
        
        # Apply mask and compare
        for ($i = 0; $i -lt 4; $i++) {
            if (($ipBytes[$i] -band $maskBytes[$i]) -ne ($networkBytes[$i] -band $maskBytes[$i])) {
                return $false
            }
        }
        
        return $true
        
    }
    catch {
        Write-Error "Subnet matching error: $_"
        return $false
    }
}

function Get-TopologyStatistics {
    <#
    .SYNOPSIS
        Analyzes a list of targets and returns topology distribution
    
    .PARAMETER Targets
        Array of target objects (with Topology property)
    
    .RETURNS
        Statistics object
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Targets
    )
    
    $stats = [PSCustomObject]@{
        Total                = $Targets.Count
        HO                   = ($Targets | Where-Object Topology -eq 'HO').Count
        Remote               = ($Targets | Where-Object Topology -eq 'Remote').Count
        Unknown              = ($Targets | Where-Object Topology -eq 'Unknown').Count
        EstimatedTimeMinutes = 0
    }
    
    # Estimate completion time (rough calculation)
    # Assume HO: 5 seconds per target with parallel (40 at a time)
    # Assume Remote: 30 seconds per target with parallel (4 at a time)
    
    $hoBatches = [Math]::Ceiling($stats.HO / 40)
    $remoteBatches = [Math]::Ceiling($stats.Remote / 4)
    
    $stats.EstimatedTimeMinutes = [Math]::Ceiling((($hoBatches * 5) + ($remoteBatches * 30)) / 60)
    
    return $stats
}

function Test-MPLSTarget {
    <#
    .SYNOPSIS
        Quick boolean check if target is MPLS/Remote
    
    .PARAMETER TopologyObject
        Topology object from Get-TargetTopology
    
    .RETURNS
        Boolean
    #>
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$TopologyObject
    )
    
    return ($TopologyObject.Topology -eq 'Remote')
}

Export-ModuleMember -Function Get-TargetTopology, Test-IPInSubnet, Get-TopologyStatistics, Test-MPLSTarget
