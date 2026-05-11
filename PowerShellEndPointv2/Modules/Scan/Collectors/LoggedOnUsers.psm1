<#
.SYNOPSIS
    LoggedOnUsers Collector
.DESCRIPTION
    Collects currently logged on user information.
#>

function Invoke-LoggedOnUsersCollection {
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
        $cim = if ($Session.Protocol -match 'CIM') { $Session.Session } else { $null }
        
        $cs = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_ComputerSystem -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_ComputerSystem -ComputerName $ComputerName -ErrorAction Stop
        }
        
        if ($cs.UserName) {
            $results.Metrics += [PSCustomObject]@{
                computer_name  = $ComputerName
                login_time     = Get-Date # Current snapshot
                user_name      = $cs.UserName
                login_type     = 'Interactive'
                source_ip      = '127.0.0.1'
                session_duration_minutes = 0
            }
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[LoggedOnUsers] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-LoggedOnUsersCollection
