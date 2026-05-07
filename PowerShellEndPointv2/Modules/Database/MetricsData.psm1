<#
.SYNOPSIS
    Metrics Data Access Module
    
.DESCRIPTION
    Functions for querying and managing granular metric tables
    
.NOTES
    Version: 2.1
#>

<#
.SYNOPSIS
    Registers or updates a computer in the database
#>
function Register-Computer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        
        [string]$IPAddress,
        [string]$MACAddress,
        [string]$OperatingSystem,
        [string]$OSVersion,
        [string]$Domain,
        [bool]$IsDomainJoined = $true,
        [string]$ComputerType = 'Desktop',
        [string]$Location,
        [string]$Department
    )
    
    $query = @"
INSERT INTO computers (computer_name, ip_address, mac_address, operating_system, os_version, 
                       domain, is_domain_joined, computer_type, location, department)
VALUES (@name, @ip, @mac, @os, @osver, @domain, @joined, @type, @location, @dept)
ON CONFLICT (computer_name) 
DO UPDATE SET 
    ip_address = EXCLUDED.ip_address,
    mac_address = COALESCE(EXCLUDED.mac_address, computers.mac_address),
    operating_system = EXCLUDED.operating_system,
    os_version = EXCLUDED.os_version,
    domain = EXCLUDED.domain,
    is_domain_joined = EXCLUDED.is_domain_joined,
    computer_type = EXCLUDED.computer_type,
    location = COALESCE(EXCLUDED.location, computers.location),
    department = COALESCE(EXCLUDED.department, computers.department),
    last_seen = NOW(),
    updated_at = NOW()
"@
    
    $params = @{
        name     = $ComputerName
        ip       = $IPAddress
        mac      = $MACAddress
        os       = $OperatingSystem
        osver    = $OSVersion
        domain   = $Domain
        joined   = $IsDomainJoined
        type     = $ComputerType
        location = $Location
        dept     = $Department
    }
    
    Invoke-PGQuery -Query $query -Parameters $params -NonQuery | Out-Null
}

<#
.SYNOPSIS
    Maps a user to a computer
#>
function Add-ComputerUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        
        [Parameter(Mandatory)]
        [string]$UserID,
        
        [string]$UserDisplayName,
        [string]$UserEmail,
        [bool]$IsPrimary = $false
    )
    
    $query = @"
INSERT INTO computer_ad_users (computer_name, user_id, user_display_name, user_email, is_primary_user, last_login)
VALUES (@computer, @userid, @displayname, @email, @primary, NOW())
ON CONFLICT (computer_name, user_id)
DO UPDATE SET
    user_display_name = EXCLUDED.user_display_name,
    user_email = EXCLUDED.user_email,
    is_primary_user = EXCLUDED.is_primary_user,
    last_login = NOW(),
    login_count = computer_ad_users.login_count + 1,
    updated_at = NOW()
"@
    
    Invoke-PGQuery -Query $query -Parameters @{
        computer    = $ComputerName
        userid      = $UserID
        displayname = $UserDisplayName
        email       = $UserEmail
        primary     = $IsPrimary
    } -NonQuery | Out-Null
}

<#
.SYNOPSIS
    Saves CPU usage metric
#>
function Save-CPUMetric {
    param(
        [string]$ComputerName,
        [decimal]$UsagePercent,
        [int]$CoreCount,
        [int]$LogicalProcessors,
        [string]$ProcessorName,
        [int]$ProcessorSpeedMHz
    )
    
    $query = @"
INSERT INTO metric_cpu_usage (computer_name, usage_percent, core_count, logical_processors, processor_name, processor_speed_mhz)
VALUES (@computer, @usage, @cores, @logical, @name, @speed)
"@
    
    Invoke-PGQuery -Query $query -Parameters @{
        computer = $ComputerName
        usage    = $UsagePercent
        cores    = $CoreCount
        logical  = $LogicalProcessors
        name     = $ProcessorName
        speed    = $ProcessorSpeedMHz
    } -NonQuery | Out-Null
}

<#
.SYNOPSIS
    Saves memory metric
#>
function Save-MemoryMetric {
    param(
        [string]$ComputerName,
        [decimal]$TotalGB,
        [decimal]$AvailableGB,
        [decimal]$UsedGB,
        [decimal]$UsagePercent
    )
    
    $query = @"
INSERT INTO metric_memory (computer_name, total_gb, available_gb, used_gb, usage_percent)
VALUES (@computer, @total, @avail, @used, @percent)
"@
    
    Invoke-PGQuery -Query $query -Parameters @{
        computer = $ComputerName
        total    = $TotalGB
        avail    = $AvailableGB
        used     = $UsedGB
        percent  = $UsagePercent
    } -NonQuery | Out-Null
}

<#
.SYNOPSIS
    Saves disk space metrics
#>
function Save-DiskMetrics {
    param(
        [string]$ComputerName,
        [array]$Disks
    )
    
    foreach ($disk in $Disks) {
        $query = @"
INSERT INTO metric_disk_space (computer_name, drive_letter, volume_name, total_gb, free_gb, used_gb, usage_percent, file_system, is_system_drive)
VALUES (@computer, @letter, @volume, @total, @free, @used, @percent, @fs, @system)
"@
        
        Invoke-PGQuery -Query $query -Parameters @{
            computer = $ComputerName
            letter   = $disk.DriveLetter
            volume   = $disk.VolumeName
            total    = $disk.TotalGB
            free     = $disk.FreeGB
            used     = $disk.UsedGB
            percent  = $disk.UsagePercent
            fs       = $disk.FileSystem
            system   = $disk.IsSystemDrive
        } -NonQuery | Out-Null
    }
}

<#
.SYNOPSIS
    Saves Windows Update metrics
#>
function Save-WindowsUpdateMetric {
    param(
        [string]$ComputerName,
        [int]$TotalUpdates,
        [int]$PendingUpdates,
        [int]$FailedUpdates,
        [datetime]$LastUpdateDate,
        [bool]$AutoUpdateEnabled,
        [bool]$RebootRequired
    )
    
    $query = @"
INSERT INTO metric_windows_updates (computer_name, total_updates, pending_updates, failed_updates, 
                                     last_update_date, auto_update_enabled, reboot_required)
VALUES (@computer, @total, @pending, @failed, @lastdate, @auto, @reboot)
"@
    
    Invoke-PGQuery -Query $query -Parameters @{
        computer = $ComputerName
        total    = $TotalUpdates
        pending  = $PendingUpdates
        failed   = $FailedUpdates
        lastdate = $LastUpdateDate
        auto     = $AutoUpdateEnabled
        reboot   = $RebootRequired
    } -NonQuery | Out-Null
}

<#
.SYNOPSIS
    Saves antivirus metrics
#>
function Save-AntivirusMetric {
    param(
        [string]$ComputerName,
        [string]$AVProduct,
        [string]$AVVersion,
        [string]$DefinitionsVersion,
        [datetime]$DefinitionsDate,
        [bool]$RealTimeProtection,
        [datetime]$LastScanDate,
        [int]$ThreatCount
    )
    
    $query = @"
INSERT INTO metric_antivirus (computer_name, av_product, av_version, definitions_version, definitions_date,
                               real_time_protection, last_scan_date, threat_count, av_enabled)
VALUES (@computer, @product, @version, @defver, @defdate, @realtime, @lastscan, @threats, @enabled)
"@
    
    $params = @{
        computer = $ComputerName
        product  = $AVProduct
        version  = $AVVersion
        defver   = $DefinitionsVersion
        defdate  = $DefinitionsDate
        realtime = $RealTimeProtection
        lastscan = $LastScanDate
        threats  = $ThreatCount
        enabled  = $RealTimeProtection
    }
    
    Invoke-PGQuery -Query $query -Parameters $params -NonQuery | Out-Null
}

<#
.SYNOPSIS
    Saves installed software metrics
#>
function Save-InstalledSoftware {
    param(
        [string]$ComputerName,
        [array]$Software
    )
    
    foreach ($app in $Software) {
        $query = @"
INSERT INTO metric_installed_software (computer_name, software_name, version, vendor, install_date, install_location, size_mb)
VALUES (@computer, @name, @version, @vendor, @date, @location, @size)
ON CONFLICT (computer_name, timestamp, software_name, version) DO NOTHING
"@
        
        Invoke-PGQuery -Query $query -Parameters @{
            computer = $ComputerName
            name     = $app.Name
            version  = $app.Version
            vendor   = $app.Vendor
            date     = $app.InstallDate
            location = $app.InstallLocation
            size     = $app.SizeMB
        } -NonQuery | Out-Null
    }
}

<#
.SYNOPSIS
    Gets latest metrics for a computer
#>
function Get-ComputerMetrics {
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        
        [ValidateSet('cpu', 'memory', 'disk', 'updates', 'antivirus', 'all')]
        [string]$MetricType = 'all'
    )
    
    $result = @{
        ComputerName = $ComputerName
        Timestamp    = Get-Date
    }
    
    if ($MetricType -eq 'cpu' -or $MetricType -eq 'all') {
        $cpu = Invoke-PGQuery -Query "SELECT * FROM metric_cpu_usage WHERE computer_name = @name ORDER BY timestamp DESC LIMIT 1" -Parameters @{ name = $ComputerName }
        $result.CPU = $cpu
    }
    
    if ($MetricType -eq 'memory' -or $MetricType -eq 'all') {
        $memory = Invoke-PGQuery -Query "SELECT * FROM metric_memory WHERE computer_name = @name ORDER BY timestamp DESC LIMIT 1" -Parameters @{ name = $ComputerName }
        $result.Memory = $memory
    }
    
    if ($MetricType -eq 'disk' -or $MetricType -eq 'all') {
        $disks = Invoke-PGQuery -Query "SELECT * FROM metric_disk_space WHERE computer_name = @name AND timestamp > NOW() - INTERVAL '1 hour'" -Parameters @{ name = $ComputerName }
        $result.Disks = $disks
    }
    
    if ($MetricType -eq 'updates' -or $MetricType -eq 'all') {
        $updates = Invoke-PGQuery -Query "SELECT * FROM metric_windows_updates WHERE computer_name = @name ORDER BY timestamp DESC LIMIT 1" -Parameters @{ name = $ComputerName }
        $result.Updates = $updates
    }
    
    if ($MetricType -eq 'antivirus' -or $MetricType -eq 'all') {
        $av = Invoke-PGQuery -Query "SELECT * FROM metric_antivirus WHERE computer_name = @name ORDER BY timestamp DESC LIMIT 1" -Parameters @{ name = $ComputerName }
        $result.Antivirus = $av
    }
    
    return $result
}

<#
.SYNOPSIS
    Gets all computers
#>
function Get-AllComputers {
    param(
        [bool]$ActiveOnly = $true,
        [int]$Limit = 100
    )
    
    $query = if ($ActiveOnly) {
        "SELECT * FROM computers WHERE is_active = true ORDER BY last_seen DESC LIMIT @limit"
    }
    else {
        "SELECT * FROM computers ORDER BY last_seen DESC LIMIT @limit"
    }
    
    return Invoke-PGQuery -Query $query -Parameters @{ limit = $Limit }
}

<#
.SYNOPSIS
    Gets computer health summary from materialized view
#>
function Get-ComputerHealthSummary {
    param([int]$Limit = 50)
    
    $query = "SELECT * FROM view_computer_health_summary ORDER BY last_seen DESC LIMIT @limit"
    return Invoke-PGQuery -Query $query -Parameters @{ limit = $Limit }
}

Export-ModuleMember -Function @(
    'Register-Computer',
    'Add-ComputerUser',
    'Save-CPUMetric',
    'Save-MemoryMetric',
    'Save-DiskMetrics',
    'Save-WindowsUpdateMetric',
    'Save-AntivirusMetric',
    'Save-InstalledSoftware',
    'Get-ComputerMetrics',
    'Get-AllComputers',
    'Get-ComputerHealthSummary'
)
