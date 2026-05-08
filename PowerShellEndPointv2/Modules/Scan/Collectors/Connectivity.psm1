<#
.SYNOPSIS
    EMS Connectivity Layer
.DESCRIPTION
    Manages CIM and DCOM sessions for remote endpoint interrogation.
#>

function Connect-EMSEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        
        [int]$TimeoutSeconds = 15
    )
    
    $result = @{
        ComputerName = $ComputerName
        Protocol     = 'None'
        Session      = $null
        Connected    = $false
        Error        = $null
    }
    
    # 1. Try CIM Session (WS-MAN / WinRM)
    try {
        $option = New-CimSessionOption -Protocol Dcom # As per user spec, Dcom is requested for CIM fallback? 
        # Wait, the user's spec said:
        # Primary method: New-CimSession -ComputerName $ComputerName -SessionOption (New-CimSessionOption -Protocol Dcom)
        # That's actually CIM over DCOM. Let's follow that.
        
        $session = New-CimSession -ComputerName $ComputerName -SessionOption $option -OperationTimeoutSec ($TimeoutSeconds * 1000) -ErrorAction Stop
        
        $result.Protocol = 'CIM'
        $result.Session = $session
        $result.Connected = $true
        return $result
    }
    catch {
        $result.Error = "CIM/DCOM failed: $($_.Exception.Message)"
    }
    
    # 2. Fallback: DCOM/WMI direct (Legacy)
    try {
        $test = Get-WmiObject -Class Win32_ComputerSystem -ComputerName $ComputerName -ErrorAction Stop
        $result.Protocol = 'DCOM'
        $result.Connected = $true
        return $result
    }
    catch {
        $result.Error = "DCOM/WMI failed: $($_.Exception.Message)"
    }
    
    return $result
}

function Disconnect-EMSEndpoint {
    param($Session)
    
    if ($Session -and $Session.Protocol -eq 'CIM' -and $Session.Session) {
        try {
            Remove-CimSession -CimSession $Session.Session -ErrorAction SilentlyContinue
        } catch {}
    }
}

Export-ModuleMember -Function Connect-EMSEndpoint, Disconnect-EMSEndpoint
