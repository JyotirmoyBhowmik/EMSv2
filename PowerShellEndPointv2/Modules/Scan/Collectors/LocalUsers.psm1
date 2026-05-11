<#
.SYNOPSIS
    LocalUsers Collector
.DESCRIPTION
    Collects summary of local user accounts.
#>

function Invoke-LocalUsersCollection {
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
        
        $users = if ($cim) {
            Get-CimInstance -CimSession $cim -ClassName Win32_UserAccount -Filter "LocalAccount = True" -ErrorAction Stop
        } else {
            Get-WmiObject -Class Win32_UserAccount -ComputerName $ComputerName -Filter "LocalAccount = True" -ErrorAction Stop
        }
        
        $enabled = $users | Where-Object { $_.Disabled -eq $false }
        $disabled = $users | Where-Object { $_.Disabled -eq $true }
        $guest = $users | Where-Object { $_.Name -eq 'Guest' }
        
        $results.Metrics += [PSCustomObject]@{
            computer_name                = $ComputerName
            total_users                  = $users.Count
            enabled_users                = $enabled.Count
            disabled_users               = $disabled.Count
            admin_users                  = 0 # Requires checking group membership, skipping for now
            guest_enabled                = if ($guest) { -not $guest.Disabled } else { $false }
            password_never_expires_count = ($users | Where-Object { $_.PasswordExpires -eq $false }).Count
            inactive_users_30days        = 0
        }
        
        $results.Success = $true
    }
    catch {
        $results.Errors += "[LocalUsers] $($_.Exception.Message)"
    }
    
    $sw.Stop()
    $results.Duration = $sw.Elapsed.TotalSeconds
    return $results
}

Export-ModuleMember -Function Invoke-LocalUsersCollection
