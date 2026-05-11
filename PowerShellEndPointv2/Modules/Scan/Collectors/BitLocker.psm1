<#
.SYNOPSIS
    BitLocker Collector
.DESCRIPTION
    Collects BitLocker encryption status for logical volumes.
#>

function Invoke-BitLockerCollection {
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
    
    try {
        $cim = if ($Session.Protocol -match 'CIM') { $Session.Session } else { $null }
        $namespace = 'Root\CIMV2\Security\MicrosoftVolumeEncryption'
        
        $volumes = if ($cim) {
            Get-CimInstance -CimSession $cim -Namespace $namespace -ClassName Win32_EncryptableVolume -ErrorAction Stop
        } else {
            Get-WmiObject -Namespace $namespace -Class Win32_EncryptableVolume -ComputerName $ComputerName -ErrorAction Stop
        }
        
        foreach ($vol in $volumes) {
            # Protection Status: 0=Off, 1=On, 2=Unknown
            $status = switch ($vol.ProtectionStatus) {
                0 { 'Off' }
                1 { 'On' }
                default { 'Unknown' }
            }
            
            $results.Metrics += [PSCustomObject]@{
                computer_name         = $ComputerName
                drive_letter          = $vol.DriveLetter.Replace(':', '')
                protection_status     = $status
                encryption_percentage = [decimal]$vol.ConversionStatus # This is usually a percentage in some versions or a code in others
                encryption_method     = $vol.EncryptionMethod
                key_protectors        = @() # Requires calling a method, skipping for now
                conversion_status     = $vol.ConversionStatus
            }
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[BitLocker] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-BitLockerCollection
