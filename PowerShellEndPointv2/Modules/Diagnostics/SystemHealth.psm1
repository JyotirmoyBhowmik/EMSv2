<#
.SYNOPSIS
    Enhanced System Health Diagnostics - Outputs Structured Metric Data
    
.DESCRIPTION
    Returns properly structured data for direct insertion into granular metric tables
#>

function Get-CPUMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $cpu = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_Processor
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_Processor
        }
        
        $loadPercent = ($cpu | Measure-Object -Property LoadPercentage -Average).Average
        
        return @{
            CheckName = "CPU_Usage"
            Status    = if ($loadPercent -gt 90) { 'Critical' } elseif ($loadPercent -gt 75) { 'Warning' } else { 'OK' }
            Details   = @{
                UsagePercent      = [decimal]$loadPercent
                CoreCount         = $cpu.NumberOfCores
                LogicalProcessors = $cpu.NumberOfLogicalProcessors
                ProcessorName     = $cpu.Name
                SpeedMHz          = $cpu.MaxClockSpeed
                CurrentClockSpeed = $cpu.CurrentClockSpeed
            }
        }
    }
    catch {
        return @{ CheckName = "CPU_Usage"; Status = 'Error'; Details = $null }
    }
}

function Get-MemoryMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $os = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_OperatingSystem
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_OperatingSystem
        }
        
        $totalGB = [decimal]([Math]::Round($os.TotalVisibleMemorySize / 1MB, 2))
        $freeGB = [decimal]([Math]::Round($os.FreePhysicalMemory / 1MB, 2))
        $usedGB = $totalGB - $freeGB
        $usedPercent = [decimal](($usedGB / $totalGB) * 100)
        
        return @{
            CheckName = "Memory_Usage"
            Status    = if ($usedPercent -gt 95) { 'Critical' } elseif ($usedPercent -gt 85) { 'Warning' } else { 'OK' }
            Details   = @{
                TotalGB              = $totalGB
                AvailableGB          = $freeGB
                UsedGB               = $usedGB
                UsagePercent         = [Math]::Round($usedPercent, 2)
                PageFileUsagePercent = [decimal]([Math]::Round((($os.TotalVirtualMemorySize - $os.FreeVirtualMemory) / $os.TotalVirtualMemorySize) * 100, 2))
            }
        }
    }
    catch {
        return @{ CheckName = "Memory_Usage"; Status = 'Error'; Details = $null }
    }
}

function Get-DiskMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $disks = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_LogicalDisk -Filter "DriveType=3"
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_LogicalDisk -Filter "DriveType=3"
        }
        
        $diskData = @()
        foreach ($disk in $disks) {
            $totalGB = [decimal]([Math]::Round($disk.Size / 1GB, 2))
            $freeGB = [decimal]([Math]::Round($disk.FreeSpace / 1GB, 2))
            $usedGB = $totalGB - $freeGB
            $usagePercent = [decimal]([Math]::Round(($usedGB / $totalGB) * 100, 2))
            
            $diskData += @{
                DriveLetter   = $disk.DeviceID.Replace(':', '')
                VolumeName    = $disk.VolumeName
                TotalGB       = $totalGB
                FreeGB        = $freeGB
                UsedGB        = $usedGB
                UsagePercent  = $usagePercent
                FileSystem    = $disk.FileSystem
                IsSystemDrive = ($disk.DeviceID -eq 'C:')
            }
        }
        
        $status = if ($diskData | Where-Object { $_.UsagePercent -gt 95 }) { 'Critical' } 
        elseif ($diskData | Where-Object { $_.UsagePercent -gt 90 }) { 'Warning' } 
        else { 'OK' }
        
        return @{
            CheckName = "Disk_Space"
            Status    = $status
            Details   = @{ Disks = $diskData }
        }
    }
    catch {
        return @{ CheckName = "Disk_Space"; Status = 'Error'; Details = $null }
    }
}

function Get-SystemUptimeMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $os = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_OperatingSystem
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_OperatingSystem
        }
        
        $bootTime = $os.LastBootUpTime
        $uptime = (Get-Date) - $bootTime
        
        return @{
            CheckName = "System_Uptime"
            Status    = if ($uptime.TotalDays -gt 30) { 'Critical' } elseif ($uptime.TotalDays -gt 14) { 'Warning' } else { 'OK' }
            Details   = @{
                BootTime         = $bootTime
                UptimeDays       = [decimal]([Math]::Round($uptime.TotalDays, 2))
                UptimeHours      = [int]$uptime.TotalHours
                LastRebootReason = $os.LastBootUpTime.ToString()
            }
        }
    }
    catch {
        return @{ CheckName = "System_Uptime"; Status = 'Error'; Details = $null }
    }
}

function Get-PowerStatusMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $battery = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_Battery
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_Battery
        }
        
        if ($battery) {
            $chargePercent = $battery.EstimatedChargeRemaining
            $designCapacity = $battery.DesignCapacity
            $fullChargeCapacity = $battery.FullChargeCapacity
            $health = if ($designCapacity -and $fullChargeCapacity) {
                [decimal]([Math]::Round(($fullChargeCapacity / $designCapacity) * 100, 2))
            }
            else { 100 }
            
            return @{
                CheckName = "Power_Status"
                Status    = if ($health -lt 50) { 'Critical' } elseif ($health -lt 70) { 'Warning' } else { 'OK' }
                Details   = @{
                    BatteryPresent   = $true
                    ChargePercent    = [decimal]$chargePercent
                    BatteryHealth    = $health
                    IsCharging       = ($battery.BatteryStatus -eq 2)
                    EstimatedRuntime = $battery.EstimatedRunTime
                    PowerPlan        = "Balanced" # Get from registry if needed
                }
            }
        }
        else {
            return @{
                CheckName = "Power_Status"
                Status    = 'N/A'
                Details   = @{
                    BatteryPresent = $false
                    PowerPlan      = "High Performance"
                }
            }
        }
    }
    catch {
        return @{ CheckName = "Power_Status"; Status = 'Error'; Details = $null }
    }
}

function Get-BIOSMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $bios = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_BIOS
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_BIOS
        }
        
        return @{
            CheckName = "BIOS_Info"
            Status    = 'OK'
            Details   = @{
                Manufacturer = $bios.Manufacturer
                Version      = $bios.SMBIOSBIOSVersion
                ReleaseDate  = $bios.ReleaseDate
                SerialNumber = $bios.SerialNumber
                UEFIMode     = $false # Detect via registry if needed
            }
        }
    }
    catch {
        return @{ CheckName = "BIOS_Info"; Status = 'Error'; Details = $null }
    }
}

function Get-MotherboardMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $board = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_BaseBoard
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_BaseBoard
        }
        
        return @{
            CheckName = "Motherboard_Info"
            Status    = 'OK'
            Details   = @{
                Manufacturer = $board.Manufacturer
                Product      = $board.Product
                Version      = $board.Version
                SerialNumber = $board.SerialNumber
            }
        }
    }
    catch {
        return @{ CheckName = "Motherboard_Info"; Status = 'Error'; Details = $null }
    }
}

function Get-NetworkAdaptersMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $adapters = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_NetworkAdapter | Where-Object { $_.NetEnabled -eq $true }
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_NetworkAdapter | Where-Object { $_.NetEnabled -eq $true }
        }
        
        $adapterData = @()
        foreach ($adapter in $adapters) {
            $adapterData += @{
                AdapterName = $adapter.Name
                MACAddress  = $adapter.MACAddress
                Speed       = $adapter.Speed
                Status      = $adapter.NetConnectionStatus
                AdapterType = $adapter.AdapterType
            }
        }
        
        return @{
            CheckName = "Network_Adapters"
            Status    = 'OK'
            Details   = @{ Adapters = $adapterData }
        }
    }
    catch {
        return @{ CheckName = "Network_Adapters"; Status = 'Error'; Details = $null }
    }
}

function Invoke-SystemHealthChecks {
    <#
    .SYNOPSIS
        Runs all system health checks and returns structured metric data
    #>
    param(
        [string]$ComputerName,
        [CimSession]$CimSession,
        [array]$CriticalServices
    )
    
    $results = @()
    
    # Collect all metrics
    $results += Get-CPUMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-MemoryMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-DiskMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-SystemUptimeMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-PowerStatusMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-BIOSMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-MotherboardMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-NetworkAdaptersMetricData -ComputerName $ComputerName -CimSession $CimSession
    
    return $results
}

Export-ModuleMember -Function Invoke-SystemHealthChecks, Get-*MetricData
