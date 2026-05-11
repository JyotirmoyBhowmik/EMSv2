<#
.SYNOPSIS
    Enhanced Security Posture Diagnostics - Structured Output
    
.DESCRIPTION
    Returns structured security metric data for granular tables
    Includes monitoring for Zscaler security client
#>

function Get-WindowsUpdateMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $scriptBlock = {
            $updateSession = New-Object -ComObject Microsoft.Update.Session
            $updateSearcher = $updateSession.CreateUpdateSearcher()
            $searchResult = $updateSearcher.Search("IsInstalled=0")
            $pendingUpdates = $searchResult.Updates.Count
            
            # Get last update time
            $lastUpdate = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 1
            
            # Check auto-update settings
            $au = New-Object -ComObject Microsoft.Update.AutoUpdate
            $auEnabled = $au.ServiceEnabled
            
            # Check reboot requirement
            $rebootRequired = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue) -ne $null
            
            return @{
                PendingUpdates    = $pendingUpdates
                TotalUpdates      = $searchResult.Updates.Count
                FailedUpdates     = 0 # Would need to query update history
                LastUpdateDate    = if ($lastUpdate) { $lastUpdate.InstalledOn } else { $null }
                AutoUpdateEnabled = $auEnabled
                RebootRequired    = $rebootRequired
            }
        }
        
        $result = if ($ComputerName) {
            Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            & $scriptBlock
        }
        
        return @{
            CheckName = "Windows_Updates"
            Status    = if ($result.PendingUpdates -gt 20) { 'Critical' } elseif ($result.PendingUpdates -gt 5) { 'Warning' } else { 'OK' }
            Details   = $result
        }
    }
    catch {
        return @{ CheckName = "Windows_Updates"; Status = 'Error'; Details = $null }
    }
}

function Get-AntivirusMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $av = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -Namespace "root\SecurityCenter2" -ClassName AntivirusProduct
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -Namespace "root\SecurityCenter2" -ClassName AntivirusProduct
        }
        
        if ($av) {
            # Get Windows Defender status if present
            $defender = if ($CimSession) {
                Get-CimInstance -CimSession $CimSession -Namespace "root\Microsoft\Windows\Defender" -ClassName MSFT_MpComputerStatus -ErrorAction SilentlyContinue
            }
            else {
                Get-CimInstance -ComputerName $ComputerName -Namespace "root\Microsoft\Windows\Defender" -ClassName MSFT_MpComputerStatus -ErrorAction SilentlyContinue
            }
            
            return @{
                CheckName = "Antivirus_Status"
                Status    = if ($defender -and $defender.RealTimeProtectionEnabled) { 'OK' } else { 'Critical' }
                Details   = @{
                    Product            = if ($defender) { "Windows Defender" } else { $av.displayName }
                    Version            = if ($defender) { $defender.AMProductVersion } else { "Unknown" }
                    DefinitionsVersion = if ($defender) { $defender.AntivirusSignatureVersion } else { "Unknown" }
                    DefinitionsDate    = if ($defender) { $defender.AntivirusSignatureLastUpdated } else { $null }
                    RealTimeProtection = if ($defender) { $defender.RealTimeProtectionEnabled } else { $false }
                    LastScanDate       = if ($defender) { $defender.QuickScanEndTime } else { $null }
                    ThreatCount        = if ($defender) { $defender.TotalThreatsCount } else { 0 }
                }
            }
        }
        else {
            return @{
                CheckName = "Antivirus_Status"
                Status    = 'Critical'
                Details   = @{ Product = "None"; RealTimeProtection = $false }
            }
        }
    }
    catch {
        return @{ CheckName = "Antivirus_Status"; Status = 'Error'; Details = $null }
    }
}

function Get-FirewallMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $scriptBlock = {
            $profiles = Get-NetFirewallProfile
            
            $profileData = @()
            foreach ($profile in $profiles) {
                $profileData += @{
                    ProfileName           = $profile.Name
                    Enabled               = $profile.Enabled
                    DefaultInboundAction  = $profile.DefaultInboundAction.ToString()
                    DefaultOutboundAction = $profile.DefaultOutboundAction.ToString()
                }
            }
            return $profileData
        }
        
        $result = if ($ComputerName) {
            Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            & $scriptBlock
        }
        
        $allEnabled = ($result | Where-Object { -not $_.Enabled }).Count -eq 0
        
        return @{
            CheckName = "Firewall_Status"
            Status    = if ($allEnabled) { 'OK' } else { 'Critical' }
            Details   = @{ Profiles = $result }
        }
    }
    catch {
        return @{ CheckName = "Firewall_Status"; Status = 'Error'; Details = $null }
    }
}

function Get-BitLockerMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $scriptBlock = {
            $volumes = Get-BitLockerVolume
            
            $volumeData = @()
            foreach ($vol in $volumes) {
                $volumeData += @{
                    MountPoint           = $vol.MountPoint
                    EncryptionMethod     = $vol.EncryptionMethod.ToString()
                    ProtectionStatus     = $vol.ProtectionStatus.ToString()
                    EncryptionPercentage = $vol.EncryptionPercentage
                    VolumeStatus         = $vol.VolumeStatus.ToString()
                }
            }
            return $volumeData
        }
        
        $result = if ($ComputerName) {
            Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            & $scriptBlock
        }
        
        $allEncrypted = ($result | Where-Object { $_.ProtectionStatus -ne "On" }).Count -eq 0
        
        return @{
            CheckName = "BitLocker_Status"
            Status    = if ($allEncrypted) { 'OK' } else { 'Warning' }
            Details   = @{ Volumes = $result }
        }
    }
    catch {
        return @{ CheckName = "BitLocker_Status"; Status = 'Error'; Details = $null }
    }
}

function Get-TPMMetricData {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $tpm = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -Namespace "root\CIMv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction SilentlyContinue
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -Namespace "root\CIMv2\Security\MicrosoftTpm" -ClassName Win32_Tpm -ErrorAction SilentlyContinue
        }
        
        if ($tpm) {
            return @{
                CheckName = "TPM_Status"
                Status    = if ($tpm.IsActivated_InitialValue -and $tpm.IsEnabled_InitialValue) { 'OK' } else { 'Warning' }
                Details   = @{
                    Present      = $true
                    Enabled      = $tpm.IsEnabled_InitialValue
                    Activated    = $tpm.IsActivated_InitialValue
                    Version      = $tpm.SpecVersion
                    Manufacturer = $tpm.ManufacturerIdTxt
                }
            }
        }
        else {
            return @{
                CheckName = "TPM_Status"
                Status    = 'Warning'
                Details   = @{ Present = $false }
            }
        }
    }
    catch {
        return @{ CheckName = "TPM_Status"; Status = 'Error'; Details = $null }
    }
}

function Get-ZscalerStatusMetricData {
    <#
    .SYNOPSIS
        Monitors Zscaler security client status
    #>
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $scriptBlock = {
            # Check if Zscaler is installed
            $zscaler = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | 
            Where-Object { $_.DisplayName -like "*Zscaler*" }
            
            if ($zscaler) {
                # Check Zscaler service
                $service = Get-Service -Name "ZscalerService" -ErrorAction SilentlyContinue
                
                # Check Zscaler app running
                $process = Get-Process -Name "Zscaler*" -ErrorAction SilentlyContinue
                
                return @{
                    Installed          = $true
                    Version            = $zscaler.DisplayVersion
                    ServiceRunning     = ($service -and $service.Status -eq 'Running')
                    ApplicationRunning = ($process -ne $null)
                    ServiceStatus      = if ($service) { $service.Status.ToString() } else { "Not Found" }
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
            CheckName = "Zscaler_Status"
            Status    = $status
            Details   = $result
        }
    }
    catch {
        return @{ CheckName = "Zscaler_Status"; Status = 'Error'; Details = $null }
    }
}

function Invoke-SecurityChecks {
    <#
    .SYNOPSIS
        Runs all security posture checks including Zscaler
    #>
    param(
        [string]$ComputerName,
        [CimSession]$CimSession
    )
    
    $results = @()
    
    $results += Get-WindowsUpdateMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-AntivirusMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-FirewallMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-BitLockerMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-TPMMetricData -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-ZscalerStatusMetricData -ComputerName $ComputerName -CimSession $CimSession
    
    return $results
}

Export-ModuleMember -Function Invoke-SecurityChecks, Get-*MetricData
