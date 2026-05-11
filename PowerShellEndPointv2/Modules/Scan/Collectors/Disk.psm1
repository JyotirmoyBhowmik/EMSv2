<#
.SYNOPSIS
    Disk Collector
.DESCRIPTION
    Collects logical disk space and health metrics.
#>

function Invoke-DiskCollection {
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
        
        $disks = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_LogicalDisk -Filter "DriveType = 3" -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_LogicalDisk -ComputerName $ComputerName -Filter "DriveType = 3" -ErrorAction Stop
        }
        
        foreach ($disk in $disks) {
            $totalGB = [math]::Round($disk.Size / 1GB, 2)
            $freeGB = [math]::Round($disk.FreeSpace / 1GB, 2)
            $usedGB = $totalGB - $freeGB
            $usagePercent = [math]::Round(($usedGB / $totalGB) * 100, 2)
            
            $results.Metrics += [PSCustomObject]@{
                computer_name   = $ComputerName
                drive_letter    = $disk.DeviceID.Replace(':', '')
                volume_name     = $disk.VolumeName
                total_gb        = [decimal]$totalGB
                free_gb         = [decimal]$freeGB
                used_gb         = [decimal]$usedGB
                usage_percent   = [decimal]$usagePercent
                file_system     = $disk.FileSystem
                drive_type      = 'Fixed'
                is_system_drive = ($disk.DeviceID -eq 'C:')
            }
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[Disk] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-DiskCollection
