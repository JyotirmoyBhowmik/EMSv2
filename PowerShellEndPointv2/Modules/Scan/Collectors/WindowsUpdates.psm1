<#
.SYNOPSIS
    WindowsUpdates Collector
.DESCRIPTION
    Collects information about installed updates and update service status.
#>

function Invoke-WindowsUpdatesCollection {
    param(
        [Parameter(Mandatory)]$Session,
        [Parameter(Mandatory)][string]$ComputerName,
        [Parameter(Mandatory)][Guid]$ScanId,
        [int]$TimeoutSeconds = 30
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
        
        # 1. Get Installed Updates (QFEs)
        $qfes = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_QuickFixEngineering -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_QuickFixEngineering -ComputerName $ComputerName -ErrorAction Stop
        }
        
        # 2. Get Update Service Status
        $svc = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_Service -Filter "Name = 'wuauserv'" -ErrorAction SilentlyContinue
        } else {
            Get-WmiObject -Class Win32_Service -ComputerName $ComputerName -Filter "Name = 'wuauserv'" -ErrorAction SilentlyContinue
        }
        
        # 3. Check for Reboot Required (Registry check via CIM/WMI)
        # HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired
        # This is hard to do via raw CIMInstance. We'll skip or use a heuristic.
        
        $results.Metrics += [PSCustomObject]@{
            computer_name       = $ComputerName
            total_updates       = $qfes.Count
            pending_updates     = 0 # Placeholder: Requires remote script execution
            failed_updates      = 0
            hidden_updates      = 0
            last_update_date    = ($qfes | Sort-Object InstalledOn -Descending | Select-Object -First 1).InstalledOn
            last_check_date     = Get-Date
            auto_update_enabled = ($svc.StartMode -eq 'Auto')
            reboot_required     = $false # Heuristic needed
            update_service      = 'Windows Update'
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[WindowsUpdates] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-WindowsUpdatesCollection
