<#
.SYNOPSIS
    Enhanced Software Compliance Diagnostics
    
.DESCRIPTION
    Monitors installed software including Seclore and OneDrive
#>

function Get-InstalledSoftwareMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $scriptBlock = {
            $software = @()
            
            # Get from registry (both 64-bit and 32-bit)
            $paths = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
                "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
            )
            
            foreach ($path in $paths) {
                $items = Get-ItemProperty $path -ErrorAction SilentlyContinue
                foreach ($item in $items) {
                    if ($item.DisplayName) {
                        $software += @{
                            Name            = $item.DisplayName
                            Version         = $item.DisplayVersion
                            Vendor          = $item.Publisher
                            InstallDate     = $item.InstallDate
                            InstallLocation = $item.InstallLocation
                            SizeMB          = if ($item.EstimatedSize) { [Math]::Round($item.EstimatedSize / 1024, 2) } else { 0 }
                        }
                    }
                }
            }
            
            return $software | Select-Object -Unique Name, Version, Vendor, InstallDate, InstallLocation, SizeMB
        }
        
        $result = if ($ComputerName) {
            Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            & $scriptBlock
        }
        
        return @{
            CheckName = "Installed_Software"
            Status    = 'OK'
            Details   = @{ Software = $result }
        }
    }
    catch {
        return @{ CheckName = "Installed_Software"; Status = 'Error'; Details = $null }
    }
}

function Get-SecloreStatusMetricData {
    <#
    .SYNOPSIS
        Monitors Seclore DRM client status
    #>
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $scriptBlock = {
            # Check if Seclore is installed
            $seclore = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
            Where-Object { $_.DisplayName -like "*Seclore*" }
            
            if ($seclore) {
                # Check Seclore service
                $service = Get-Service -Name "Seclore*" -ErrorAction SilentlyContinue
                
                # Check Seclore process
                $process = Get-Process -Name "Seclore*" -ErrorAction SilentlyContinue
                
                # Check plugin status for Office applications
                $officePlugins = @{
                    Word       = Test-Path "C:\Program Files\Seclore\FileSecure\Plugins\MSWord" -ErrorAction SilentlyContinue
                    Excel      = Test-Path "C:\Program Files\Seclore\FileSecure\Plugins\MSExcel" -ErrorAction SilentlyContinue
                    PowerPoint = Test-Path "C:\Program Files\Seclore\FileSecure\Plugins\MSPowerPoint" -ErrorAction SilentlyContinue
                    Outlook    = Test-Path "C:\Program Files\Seclore\FileSecure\Plugins\MSOutlook" -ErrorAction SilentlyContinue
                }
                
                return @{
                    Installed              = $true
                    Version                = $seclore.DisplayVersion
                    ServiceRunning         = ($service -and $service.Status -eq 'Running')
                    ApplicationRunning     = ($process -ne $null)
                    OfficePluginsInstalled = $officePlugins
                    InstallLocation        = $seclore.InstallLocation
                }
            }
            else {
                return @{
                    Installed          = $false
                    Version            = $null
                    ServiceRunning     = $false
                    ApplicationRunning = $false
                }
            }
        }
        
        $result = if ($ComputerName) {
            Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            & $scriptBlock
        }
        
        $status = if ($result.Installed -and $result.ServiceRunning) { 'OK' } 
        elseif ($result.Installed) { 'Warning' } 
        else { 'Critical' }
        
        return @{
            CheckName = "Seclore_Status"
            Status    = $status
            Details   = $result
        }
    }
    catch {
        return @{ CheckName = "Seclore_Status"; Status = 'Error'; Details = $null }
    }
}

function Get-OneDriveStatusMetricData {
    <#
    .SYNOPSIS
        Monitors OneDrive sync status and configuration
    #>
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $scriptBlock = {
            # Check if OneDrive is installed
            $onedrive = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\OneDriveSetup.exe" -ErrorAction SilentlyContinue
            
            if ($onedrive) {
                # Check OneDrive process
                $process = Get-Process -Name "OneDrive" -ErrorAction SilentlyContinue
                
                # Get OneDrive sync status
                $syncStatus = "Unknown"
                $syncLocation = $null
                
                # Try to get sync location from registry
                $userProfile = [Environment]::GetFolderPath("UserProfile")
                $oneDrivePath = Join-Path $userProfile "OneDrive"
                
                if (Test-Path $oneDrivePath) {
                    $syncLocation = $oneDrivePath
                    $syncStatus = "Configured"
                }
                
                # Check for sync errors (look for .tmp files or conflicted copies)
                $syncErrors = 0
                if ($syncLocation) {
                    $conflictFiles = Get-ChildItem $syncLocation -Recurse -Filter "*-conflict-*" -ErrorAction SilentlyContinue
                    $syncErrors = $conflictFiles.Count
                }
                
                # Get business/personal configuration
                $businessConfigured = Test-Path (Join-Path $userProfile "OneDrive - *") -ErrorAction SilentlyContinue
                
                return @{
                    Installed          = $true
                    Version            = $onedrive.DisplayVersion
                    Running            = ($process -ne $null)
                    SyncLocation       = $syncLocation
                    SyncStatus         = $syncStatus
                    SyncErrors         = $syncErrors
                    BusinessConfigured = $businessConfigured
                    StorageUsed        = if ($syncLocation -and (Test-Path $syncLocation)) {
                        [Math]::Round((Get-ChildItem $syncLocation -Recurse -ErrorAction SilentlyContinue | 
                                Measure-Object -Property Length -Sum).Sum / 1GB, 2)
                    }
                    else { 0 }
                }
            }
            else {
                return @{
                    Installed  = $false
                    Version    = $null
                    Running    = $false
                    SyncStatus = "Not Installed"
                }
            }
        }
        
        $result = if ($ComputerName) {
            Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            & $scriptBlock
        }
        
        $status = if ($result.Installed -and $result.Running -and $result.SyncErrors -eq 0) { 'OK' } 
        elseif ($result.Installed -and $result.Running) { 'Warning' } 
        elseif ($result.Installed) { 'Critical' }
        else { 'N/A' }
        
        return @{
            CheckName = "OneDrive_Status"
            Status    = $status
            Details   = $result
        }
    }
    catch {
        return @{ CheckName = "OneDrive_Status"; Status = 'Error'; Details = $null }
    }
}

function Get-ServicesMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $services = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_Service
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_Service
        }
        
        $serviceData = @()
        foreach ($svc in $services | Where-Object { $_.StartMode -eq 'Auto' }) {
            $serviceData += @{
                ServiceName = $svc.Name
                DisplayName = $svc.DisplayName
                State       = $svc.State
                StartMode   = $svc.StartMode
                Status      = $svc.Status
            }
        }
        
        return @{
            CheckName = "Services_Status"
            Status    = 'OK'
            Details   = @{ Services = $serviceData }
        }
    }
    catch {
        return @{ CheckName = "Services_Status"; Status = 'Error'; Details = $null }
    }
}

function Get-StartupProgramsMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $scriptBlock = {
            $startup = @()
            
            # Get from registry Run keys
            $runKeys = @(
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
                "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
            )
            
            foreach ($key in $runKeys) {
                $items = Get-ItemProperty $key -ErrorAction SilentlyContinue
                if ($items) {
                    foreach ($prop in $items.PSObject.Properties) {
                        if ($prop.Name -notlike "PS*") {
                            $startup += @{
                                Name     = $prop.Name
                                Command  = $prop.Value
                                Location = $key
                            }
                        }
                    }
                }
            }
            
            # Get from Startup folder
            $startupFolder = [Environment]::GetFolderPath("Startup")
            if (Test-Path $startupFolder) {
                $shortcuts = Get-ChildItem $startupFolder -Filter "*.lnk"
                foreach ($shortcut in $shortcuts) {
                    $startup += @{
                        Name     = $shortcut.Name
                        Command  = $shortcut.FullName
                        Location = "Startup Folder"
                    }
                }
            }
            
            return $startup
        }
        
        $result = if ($ComputerName) {
            Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            & $scriptBlock
        }
        
        return @{
            CheckName = "Startup_Programs"
            Status    = 'OK'
            Details   = @{ Programs = $result }
        }
    }
    catch {
        return @{ CheckName = "Startup_Programs"; Status = 'Error'; Details = $null }
    }
}

function Invoke-SoftwareComplianceChecks {
    <#
    .SYNOPSIS
        Runs all software compliance checks including Seclore and OneDrive
    #>
    param(
        [string]$ComputerName,
        [CimSession]$CimSession
    )
    
    $results = @()
    
    $results += Get-InstalledSoftwareMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-SecloreStatusMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-OneDriveStatusMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-ServicesMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-StartupProgramsMetricData -ComputerName $ComputerName -CimSession $CimSession
    
    return $results
}

Export-ModuleMember -Function Invoke-SoftwareComplianceChecks, Get-*MetricData
