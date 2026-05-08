<#
.SYNOPSIS
    Firewall Collector
.DESCRIPTION
    Collects Windows Firewall profile status and settings.
#>

function Invoke-FirewallCollection {
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
        $namespace = 'Root\StandardCimv2'
        
        $profiles = if ($cim) {
            Get-CimInstance -CimSession $cim -Namespace $namespace -ClassName MSFT_NetFirewallProfile -ErrorAction Stop
        } else {
            Get-WmiObject -Namespace $namespace -Class MSFT_NetFirewallProfile -ComputerName $ComputerName -ErrorAction Stop
        }
        
        $domain = $profiles | Where-Object { $_.Name -eq 'Domain' }
        $private = $profiles | Where-Object { $_.Name -eq 'Private' }
        $public = $profiles | Where-Object { $_.Name -eq 'Public' }
        
        $results.Metrics += [PSCustomObject]@{
            computer_name           = $ComputerName
            domain_profile_enabled  = ($domain.Enabled -eq 1)
            private_profile_enabled = ($private.Enabled -eq 1)
            public_profile_enabled  = ($public.Enabled -eq 1)
            active_profile          = ($profiles | Where-Object { $_.IsActive -eq $true }).Name
            inbound_default_action  = $domain.DefaultInboundAction
            outbound_default_action = $domain.DefaultOutboundAction
            firewall_product        = 'Windows Firewall'
            total_rules             = 0 # Requires expensive query, skipping for now
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[Firewall] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-FirewallCollection
