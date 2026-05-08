<#
.SYNOPSIS
    ScheduledTasks Collector
.DESCRIPTION
    Collects scheduled tasks configuration and status.
#>

function Invoke-ScheduledTasksCollection {
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
        if ($Session.Protocol -eq 'CIM' -and $Session.Session) {
            # Use modern ScheduledTasks module with CIM session
            $tasks = Get-ScheduledTask -CimSession $Session.Session -ErrorAction Stop | Where-Object { $_.State -ne 'Disabled' }
            
            foreach ($t in $tasks) {
                # Get info (expensive, so we limit to non-disabled tasks)
                $results.Metrics += [PSCustomObject]@{
                    computer_name       = $ComputerName
                    task_name           = $t.TaskName
                    task_path           = $t.TaskPath
                    enabled             = ($t.State -ne 'Disabled')
                    state               = $t.State.ToString()
                    last_run_time       = $null # Requires Get-ScheduledTaskInfo
                    last_result         = 0
                    next_run_time       = $null
                    trigger_description = 'See Task Scheduler'
                    action_description  = ($t.Actions | Select-Object -First 1).Execute
                    run_as_user         = $t.Principal.UserId
                }
            }
        }
        else {
            # Legacy fallback: Use Win32_ScheduledJob (limited)
            $tasks = Get-WmiObject -Class Win32_ScheduledJob -ComputerName $ComputerName -ErrorAction SilentlyContinue
            foreach ($t in $tasks) {
                $results.Metrics += [PSCustomObject]@{
                    computer_name = $ComputerName
                    task_name     = $t.Name
                    task_path     = $t.Command
                    enabled       = $true
                    state         = 'Enabled'
                    run_as_user   = $t.Owner
                }
            }
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[ScheduledTasks] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-ScheduledTasksCollection
