<#
.SYNOPSIS
    Processes Collector
.DESCRIPTION
    Collects snapshot of running processes.
#>

function Invoke-ProcessesCollection {
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
    
    # Critical system processes to tag
    $criticalNames = @('lsass', 'csrss', 'smss', 'services', 'wininit', 'svchost')
    
    try {
        $cim = if ($Session.Protocol -match 'CIM') { $Session.Session } else { $null }
        
        $procs = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_Process -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_Process -ComputerName $ComputerName -ErrorAction Stop
        }
        
        foreach ($p in $procs) {
            # Filter: Only collect processes with significant memory usage or critical ones to avoid DB bloat
            $wsMB = [math]::Round($p.WorkingSetSize / 1MB, 2)
            
            if ($wsMB -gt 50 -or $p.Name.Split('.')[0] -in $criticalNames) {
                $results.Metrics += [PSCustomObject]@{
                    computer_name     = $ComputerName
                    process_id        = [int]$p.ProcessId
                    process_name      = $p.Name
                    path              = $p.ExecutablePath
                    working_set_mb    = [decimal]$wsMB
                    cpu_usage_percent = 0 # Difficult to get a snapshot without polling
                    user_name         = 'Unknown' # Requires expensive GetOwner() call
                    is_critical       = ($p.Name.Split('.')[0] -in $criticalNames)
                }
            }
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[Processes] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-ProcessesCollection
