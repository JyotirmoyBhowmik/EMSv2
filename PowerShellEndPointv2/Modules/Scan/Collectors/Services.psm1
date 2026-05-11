<#
.SYNOPSIS
    Services Collector
.DESCRIPTION
    Collects system service status and configuration.
#>

function Invoke-ServicesCollection {
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
    
    # Define critical services to tag
    $criticalNames = @('WinRM', 'wuauserv', 'LanmanWorkstation', 'RpcSs', 'EventLog', 'MpsSvc')
    
    try {
        $cim = if ($Session.Protocol -match 'CIM') { $Session.Session } else { $null }
        
        $services = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_Service -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_Service -ComputerName $ComputerName -ErrorAction Stop
        }
        
        foreach ($svc in $services) {
            # Only collect services that are Running or supposed to be Auto but stopped, 
            # OR critical services. This avoids bloating the DB with thousands of disabled services.
            if ($svc.State -eq 'Running' -or $svc.StartMode -eq 'Auto' -or $svc.Name -in $criticalNames) {
                $results.Metrics += [PSCustomObject]@{
                    computer_name  = $ComputerName
                    service_name   = $svc.Name
                    display_name   = $svc.DisplayName
                    state          = $svc.State
                    start_mode     = $svc.StartMode
                    account        = $svc.StartName
                    process_id     = [int]$svc.ProcessId
                    is_critical    = ($svc.Name -in $criticalNames)
                }
            }
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[Services] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-ServicesCollection
