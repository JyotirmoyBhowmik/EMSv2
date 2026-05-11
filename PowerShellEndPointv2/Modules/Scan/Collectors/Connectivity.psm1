<#
.SYNOPSIS
    EMS Connectivity Layer
.DESCRIPTION
    Manages CIM and DCOM sessions for remote endpoint interrogation.
    Supports optional PSCredential for service account authentication.
#>

function Connect-EMSEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        
        [int]$TimeoutSeconds = 15,

        # Optional credential for service account scanning
        [System.Management.Automation.PSCredential]$Credential = $null
    )
    
    $result = @{
        ComputerName = $ComputerName
        Protocol     = 'None'
        Session      = $null
        Connected    = $false
        Error        = $null
    }
    
    # 0. Basic Ping Test
    try {
        if (-not (Test-Connection -ComputerName $ComputerName -Count 1 -Quiet -TimeoutSeconds 5)) {
            $result.Error = "Host unreachable — ping to '$ComputerName' failed. Verify the hostname/IP is correct and the machine is powered on."
            return $result
        }
    } catch {
        $result.Error = "Ping failed: $($_.Exception.Message)"
        return $result
    }

    # 1. Try CIM Session (DCOM Protocol — works even if WinRM is disabled)
    try {
        $option = New-CimSessionOption -Protocol Dcom
        
        $cimParams = @{
            ComputerName       = $ComputerName
            SessionOption      = $option
            # BUG FIX: OperationTimeoutSec is in SECONDS, not milliseconds.
            # Was: ($TimeoutSeconds * 1000) which produced 15000s (4+ hours)
            OperationTimeoutSec = $TimeoutSeconds
            ErrorAction        = 'Stop'
        }
        if ($Credential) {
            $cimParams['Credential'] = $Credential
        }
        
        $session = New-CimSession @cimParams
        
        $result.Protocol  = 'CIM-DCOM'
        $result.Session   = $session
        $result.Connected = $true
        return $result
    }
    catch {
        $result.Error = "CIM/DCOM connection failed: $($_.Exception.Message)"
    }
    
    # 2. Fallback: Legacy WMI/DCOM
    try {
        $wmiParams = @{
            Class         = 'Win32_ComputerSystem'
            ComputerName  = $ComputerName
            ErrorAction   = 'Stop'
        }
        if ($Credential) {
            $wmiParams['Credential'] = $Credential
        }
        
        $test = Get-WmiObject @wmiParams
        $result.Protocol  = 'Legacy-DCOM'
        $result.Connected = $true
        return $result
    }
    catch {
        $msg = $_.Exception.Message
        $diag = "All connection methods failed. "
        if ($msg -match "Access is denied") { $diag += "POTENTIAL BLOCK: Antivirus/EDR rejected the connection." }
        elseif ($msg -match "RPC server is unavailable") { $diag += "FIREWALL: Ports 135/445/5985 blocked." }
        
        $result.Error = "$diag ($msg)"
    }
    
    return $result
}

function Disconnect-EMSEndpoint {
    param($Session)
    
    # BUG FIX: Protocol was changed from 'CIM' to 'CIM-DCOM' but this check was never updated,
    # causing sessions to leak. Now matches the actual protocol string.
    if ($Session -and $Session.Protocol -eq 'CIM-DCOM' -and $Session.Session) {
        try {
            Remove-CimSession -CimSession $Session.Session -ErrorAction SilentlyContinue
        } catch {}
    }
}

Export-ModuleMember -Function Connect-EMSEndpoint, Disconnect-EMSEndpoint
