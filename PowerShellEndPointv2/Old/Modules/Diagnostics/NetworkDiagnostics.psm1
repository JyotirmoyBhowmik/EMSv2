<#
.SYNOPSIS
    Network diagnostics module

.DESCRIPTION
    Implements 10 network connectivity and performance checks
#>

function Get-IPConfiguration {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $adapters = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True"
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True"
        }
        
        $results = @()
        foreach ($adapter in $adapters) {
            $ip = $adapter.IPAddress[0]
            $isAPIP = $ip -match '^169\.254\.'
            
            $status = if ($isAPIP) { 'Critical' } else { 'OK' }
            
            $results += [PSCustomObject]@{
                Diagnostic = "IP Configuration - $($adapter.Description)"
                Result     = "IP: $ip, Subnet: $($adapter.IPSubnet[0]), Gateway: $($adapter.DefaultIPGateway -join ', ')"
                Status     = $status
            }
        }
        
        return $results
    }
    catch {
        return [PSCustomObject]@{
            Diagnostic = 'IP Configuration'
            Result     = "Error: $_"
            Status     = 'Error'
        }
    }
}

function Test-DNSResolution {
    param([string]$ComputerName)
    
    try {
        $testTargets = @('google.com', 'microsoft.com')
        
        $scriptBlock = {
            param($targets)
            $results = @()
            foreach ($target in $targets) {
                try {
                    $resolved = Resolve-DnsName -Name $target -Type A -ErrorAction Stop
                    $results += "$target = $($resolved[0].IPAddress)"
                }
                catch {
                    $results += "$target = FAILED"
                }
            }
            return $results -join '; '
        }
        
        if ($ComputerName) {
            $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock -ArgumentList (, $testTargets)
        }
        else {
            $result = & $scriptBlock -targets $testTargets
        }
        
        $status = if ($result -match 'FAILED') { 'Critical' } else { 'OK' }
        
        return [PSCustomObject]@{
            Diagnostic = 'DNS Resolution'
            Result     = $result
            Status     = $status
        }
    }
    catch {
        return [PSCustomObject]@{
            Diagnostic = 'DNS Resolution'
            Result     = "Error: $_"
            Status     = 'Error'
        }
    }
}

function Measure-Latency {
    param([string]$ComputerName)
    
    try {
        $scriptBlock = {
            $gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0').NextHop | Select-Object -First 1
            
            if ($gateway) {
                $ping = Test-Connection -ComputerName $gateway -Count 4 -Quiet
                $latency = (Test-Connection -ComputerName $gateway -Count 4 | Measure-Object -Property ResponseTime -Average).Average
                
                return @{
                    Gateway = $gateway
                    Latency = $latency
                    Success = $ping
                }
            }
            
            return @{ Gateway = 'Unknown'; Latency = 0; Success = $false }
        }
        
        if ($ComputerName) {
            $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            $result = & $scriptBlock
        }
        
        $status = if ($result.Latency -gt 100) { 'Warning' } elseif ($result.Latency -gt 50) { 'Warning' } else { 'OK' }
        
        return [PSCustomObject]@{
            Diagnostic = 'Latency to Gateway'
            Result     = "$($result.Gateway) - $([Math]::Round($result.Latency, 2))ms"
            Status     = $status
        }
    }
    catch {
        return [PSCustomObject]@{
            Diagnostic = 'Latency to Gateway'
            Result     = "Error: $_"
            Status     = 'Error'
        }
    }
}

function Test-PacketLoss {
    param([string]$ComputerName)
    
    try {
        $scriptBlock = {
            $gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0').NextHop | Select-Object -First 1
            
            if ($gateway) {
                $pings = Test-Connection -ComputerName $gateway -Count 20
                $received = ($pings | Measure-Object).Count
                $lossPercent = ((20 - $received) / 20) * 100
                
                # Calculate jitter
                $latencies = $pings | Select-Object -ExpandProperty ResponseTime
                $avgLatency = ($latencies | Measure-Object -Average).Average
                $jitter = ($latencies | ForEach-Object { [Math]::Abs($_ - $avgLatency) } | Measure-Object -Average).Average
                
                return @{
                    Loss   = $lossPercent
                    Jitter = $jitter
                }
            }
            
            return @{ Loss = 100; Jitter = 0 }
        }
        
        if ($ComputerName) {
            $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            $result = & $scriptBlock
        }
        
        $status = if ($result.Loss -gt 5) { 'Critical' } elseif ($result.Loss -gt 1) { 'Warning' } else { 'OK' }
        
        return [PSCustomObject]@{
            Diagnostic = 'Packet Loss & Jitter'
            Result     = "Loss: $([Math]::Round($result.Loss, 2))%, Jitter: $([Math]::Round($result.Jitter, 2))ms"
            Status     = $status
        }
    }
    catch {
        return [PSCustomObject]@{
            Diagnostic = 'Packet Loss & Jitter'
            Result     = "Error: $_"
            Status     = 'Error'
        }
    }
}

function Get-NICSpeed {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $adapters = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_NetworkAdapter -Filter "NetConnectionStatus=2"
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_NetworkAdapter -Filter "NetConnectionStatus=2"
        }
        
        $results = @()
        foreach ($adapter in $adapters) {
            $speedMbps = $adapter.Speed / 1MB
            
            # Flag if Gigabit NIC running at 100Mbps (cabling issue)
            $status = if ($adapter.AdapterType -match 'Gigabit' -and $speedMbps -lt 1000) {
                'Warning'
            }
            else {
                'OK'
            }
            
            $results += [PSCustomObject]@{
                Diagnostic = "NIC Speed - $($adapter.Name)"
                Result     = "$speedMbps Mbps"
                Status     = $status
            }
        }
        
        return $results
    }
    catch {
        return [PSCustomObject]@{
            Diagnostic = 'NIC Speed'
            Result     = "Error: $_"
            Status     = 'Error'
        }
    }
}

function Get-ActiveConnections {
    param([string]$ComputerName)
    
    try {
        $scriptBlock = {
            $connections = Get-NetTCPConnection -State Established, TimeWait -ErrorAction SilentlyContinue
            
            $established = ($connections | Where-Object State -eq 'Established' | Measure-Object).Count
            $timeWait = ($connections | Where-Object State -eq 'TimeWait' | Measure-Object).Count
            
            return @{
                Established = $established
                TimeWait    = $timeWait
            }
        }
        
        if ($ComputerName) {
            $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            $result = & $scriptBlock
        }
        
        return [PSCustomObject]@{
            Diagnostic = 'Active TCP Connections'
            Result     = "Established: $($result.Established), TimeWait: $($result.TimeWait)"
            Status     = 'OK'
        }
    }
    catch {
        return [PSCustomObject]@{
            Diagnostic = 'Active TCP Connections'
            Result     = "Error: $_"
            Status     = 'Error'
        }
    }
}

function Get-WiFiSignalStrength {
    param([string]$ComputerName)
    
    try {
        $scriptBlock = {
            $wifi = netsh wlan show interfaces | Select-String 'Signal'
            
            if ($wifi) {
                $signal = $wifi -replace '.*:\s*(\d+)%', '$1'
                return @{
                    HasWiFi = $true
                    Signal  = [int]$signal
                }
            }
            
            return @{ HasWiFi = $false; Signal = 0 }
        }
        
        if ($ComputerName) {
            $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            $result = & $scriptBlock
        }
        
        if (-not $result.HasWiFi) {
            return [PSCustomObject]@{
                Diagnostic = 'Wi-Fi Signal Strength'
                Result     = 'No wireless adapter'
                Status     = 'N/A'
            }
        }
        
        $status = if ($result.Signal -lt 50) { 'Critical' } elseif ($result.Signal -lt 70) { 'Warning' } else { 'OK' }
        
        return [PSCustomObject]@{
            Diagnostic = 'Wi-Fi Signal Strength'
            Result     = "$($result.Signal)%"
            Status     = $status
        }
    }
    catch {
        return [PSCustomObject]@{
            Diagnostic = 'Wi-Fi Signal Strength'
            Result     = "Error: $_"
            Status     = 'Error'
        }
    }
}

function Get-DHCPLeaseInfo {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $adapters = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True AND DHCPEnabled=True"
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True AND DHCPEnabled=True"
        }
        
        $results = @()
        foreach ($adapter in $adapters) {
            $leaseExpires = [Management.ManagementDateTimeConverter]::ToDateTime($adapter.DHCPLeaseExpires)
            $daysUntilExpiry = ($leaseExpires - (Get-Date)).TotalDays
            
            $status = if ($daysUntilExpiry -lt 1) { 'Warning' } else { 'OK' }
            
            $results += [PSCustomObject]@{
                Diagnostic = "DHCP Lease - $($adapter.Description)"
                Result     = "Expires: $leaseExpires ($([Math]::Round($daysUntilExpiry, 1)) days)"
                Status     = $status
            }
        }
        
        if ($results.Count -eq 0) {
            return [PSCustomObject]@{
                Diagnostic = 'DHCP Lease'
                Result     = 'Static IP configuration'
                Status     = 'Info'
            }
        }
        
        return $results
    }
    catch {
        return [PSCustomObject]@{
            Diagnostic = 'DHCP Lease'
            Result     = "Error: $_"
            Status     = 'Error'
        }
    }
}

function Get-ARPTable {
    param([string]$ComputerName)
    
    try {
        $scriptBlock = {
            $arpTable = Get-NetNeighbor -AddressFamily IPv4 -ErrorAction SilentlyContinue
            $static = ($arpTable | Where-Object State -eq 'Permanent' | Measure-Object).Count
            $dynamic = ($arpTable | Where-Object State -ne 'Permanent' | Measure-Object).Count
            
            return @{
                Static  = $static
                Dynamic = $dynamic
            }
        }
        
        if ($ComputerName) {
            $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            $result = & $scriptBlock
        }
        
        # Static ARP entries could indicate ARP poisoning
        $status = if ($result.Static -gt 0) { 'Warning' } else { 'OK' }
        
        return [PSCustomObject]@{
            Diagnostic = 'ARP Table'
            Result     = "Static: $($result.Static), Dynamic: $($result.Dynamic)"
            Status     = $status
        }
    }
    catch {
        return [PSCustomObject]@{
            Diagnostic = 'ARP Table'
            Result     = "Error: $_"
            Status     = 'Error'
        }
    }
}

function Get-AdapterVendor {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $adapters = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_NetworkAdapter -Filter "NetConnectionStatus=2"
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_NetworkAdapter -Filter "NetConnectionStatus=2"
        }
        
        $results = @()
        foreach ($adapter in $adapters) {
            $results += [PSCustomObject]@{
                Diagnostic = "Adapter Vendor - $($adapter.Name)"
                Result     = $adapter.Manufacturer
                Status     = 'Info'
            }
        }
        
        return $results
    }
    catch {
        return [PSCustomObject]@{
            Diagnostic = 'Adapter Vendor'
            Result     = "Error: $_"
            Status     = 'Error'
        }
    }
}

function Invoke-NetworkDiagnostics {
    <#
    .SYNOPSIS
        Runs all network diagnostic checks
    #>
    param(
        [string]$ComputerName,
        [CimSession]$CimSession
    )
    
    $results = @()
    
    $results += Get-IPConfiguration -ComputerName $ComputerName -CimSession $CimSession
    $results += Test-DNSResolution -ComputerName $ComputerName
    $results += Measure-Latency -ComputerName $ComputerName
    $results += Test-PacketLoss -ComputerName $ComputerName
    $results += Get-NICSpeed -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-ActiveConnections -ComputerName $ComputerName
    $results += Get-WiFiSignalStrength -ComputerName $ComputerName
    $results += Get-DHCPLeaseInfo -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-ARPTable -ComputerName $ComputerName
    $results += Get-AdapterVendor -ComputerName $ComputerName -CimSession $CimSession
    
    return $results
}

Export-ModuleMember -Function Invoke-NetworkDiagnostics, Get-*, Test-*, Measure-*
