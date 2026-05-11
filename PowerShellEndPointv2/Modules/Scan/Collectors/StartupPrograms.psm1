<#
.SYNOPSIS
    StartupPrograms Collector
.DESCRIPTION
    Collects programs configured to start automatically.
#>

function Invoke-StartupProgramsCollection {
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
        
        $startups = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_StartupCommand -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_StartupCommand -ComputerName $ComputerName -ErrorAction Stop
        }
        
        foreach ($s in $startups) {
            $results.Metrics += [PSCustomObject]@{
                computer_name = $ComputerName
                program_name  = $s.Name
                command       = $s.Command
                location      = $s.Location
                user_context  = $s.User
                enabled       = $true # If it's in this class, it's usually active
                impact        = 'Unknown'
            }
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[Startup] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-StartupProgramsCollection
