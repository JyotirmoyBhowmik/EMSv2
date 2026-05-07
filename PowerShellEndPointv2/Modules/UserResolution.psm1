<#
.SYNOPSIS
    User resolution module

.DESCRIPTION
    Maps User IDs to endpoints using SCCM User Device Affinity or Event Log forensics
#>

function Resolve-UserToEndpoint {
    <#
    .SYNOPSIS
        Resolves a User ID to their current/primary endpoint
    
    .PARAMETER UserID
        User ID to resolve (domain\user or user@domain format)
    
    .PARAMETER Config
        Configuration object
    
    .RETURNS
        Topology object(s) for resolved endpoint(s)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$UserID,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    Write-EMSLog -Message "Resolving User ID: $UserID" -Severity 'Info' -Category 'UserResolution'
    
    $resolved = $null
    
    # Strategy 1: SCCM User Device Affinity (Primary)
    if ($Config.UserResolution.UseSCCM) {
        Write-EMSLog -Message "Attempting SCCM User Device Affinity resolution" -Severity 'Info' -Category 'UserResolution'
        $resolved = Get-SCCMUserDevice -UserID $UserID -Config $Config
    }
    
    # Strategy 2: Event Log Forensics (Fallback)
    if (-not $resolved -and $Config.UserResolution.FallbackToDC) {
        Write-EMSLog -Message "SCCM resolution failed. Falling back to Event Log correlation" -Severity 'Warning' -Category 'UserResolution'
        $resolved = Search-EventLogForUser -UserID $UserID -Config $Config
    }
    
    # Strategy 3: Manual entry prompt
    if (-not $resolved) {
        Write-EMSLog -Message "Automatic resolution failed for user: $UserID" -Severity 'Error' -Category 'UserResolution'
        return $null
    }
    
    # Enrich with topology
    $topology = Get-TargetTopology -Target $resolved -Config $Config.Topology
    
    if ($topology) {
        Write-EMSLog -Message "User $UserID resolved to endpoint: $($topology.Hostname) ($($topology.IP))" `
            -Severity 'Success' -Category 'UserResolution'
    }
    
    return @($topology)
}

function Get-SCCMUserDevice {
    <#
    .SYNOPSIS
        Queries SCCM for User Device Affinity
    
    .PARAMETER UserID
        User ID to query
    
    .PARAMETER Config
        Configuration object
    
    .RETURNS
        Computer name if found
    #>
    param(
        [Parameter(Mandatory)]
        [string]$UserID,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    try {
        # Check if ConfigMgr module is available
        $cmModule = Get-Module -Name ConfigurationManager -ListAvailable
        
        if (-not $cmModule) {
            Write-EMSLog -Message "ConfigurationManager module not available" -Severity 'Warning' -Category 'UserResolution'
            return $null
        }
        
        # Import module
        Import-Module ConfigurationManager -ErrorAction Stop
        
        # Get site code
        $siteCode = $(Get-PSDrive -PSProvider CMSite -ErrorAction SilentlyContinue).Name
        
        if (-not $siteCode) {
            # Create PSDrive
            if ($Config.UserResolution.SCCMSiteServer) {
                New-PSDrive -Name "CM01" -PSProvider CMSite -Root $Config.UserResolution.SCCMSiteServer -ErrorAction Stop
                $siteCode = "CM01"
            }
            else {
                Write-EMSLog -Message "SCCM site server not configured" -Severity 'Warning' -Category 'UserResolution'
                return $null
            }
        }
        
        # Query User Device Affinity
        Push-Location "${siteCode}:"
        
        try {
            $affinity = Get-CMUserDeviceAffinity -UserName $UserID | Select-Object -First 1
            
            if ($affinity) {
                $computerName = $affinity.ResourceName
                Write-EMSLog -Message "SCCM resolved $UserID to $computerName" -Severity 'Success' -Category 'UserResolution'
                return $computerName
            }
            else {
                Write-EMSLog -Message "No device affinity found for $UserID in SCCM" -Severity 'Warning' -Category 'UserResolution'
                return $null
            }
        }
        finally {
            Pop-Location
        }
        
    }
    catch {
        Write-EMSLog -Message "SCCM query error: $_" -Severity 'Error' -Category 'UserResolution'
        return $null
    }
}

function Search-EventLogForUser {
    <#
    .SYNOPSIS
        Searches Domain Controller Event Logs for user logon events
    
    .PARAMETER UserID
        User ID to search
    
    .PARAMETER Config
        Configuration object
    
    .RETURNS
        Computer name if found
    #>
    param(
        [Parameter(Mandatory)]
        [string]$UserID,
        
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )
    
    try {
        # Get Domain Controller
        $dc = (Get-ADDomainController -Discover -Service PrimaryDC).HostName
        
        Write-EMSLog -Message "Searching Event Logs on DC: $dc" -Severity 'Info' -Category 'UserResolution'
        
        # Calculate time window
        $startTime = (Get-Date).AddMinutes(-$Config.UserResolution.EventLogTimeWindowMinutes)
        
        # Extract username (remove domain prefix)
        $username = if ($UserID -match '\\(.+)$') { $Matches[1] } else { $UserID }
        
        # Query Security Log for Event ID 4624 (Successful Logon)
        $filterHash = @{
            LogName   = 'Security'
            ID        = 4624
            StartTime = $startTime
        }
        
        Write-EMSLog -Message "Querying last $($Config.UserResolution.EventLogTimeWindowMinutes) minutes of logon events" `
            -Severity 'Info' -Category 'UserResolution'
        
        # Set timeout
        $job = Start-Job -ScriptBlock {
            param($dc, $filterHash, $user)
            
            Get-WinEvent -ComputerName $dc -FilterHashtable $filterHash -ErrorAction SilentlyContinue | 
            Where-Object {
                ($_.Properties[5].Value -eq $user) -and # TargetUserName
                ($_.Properties[8].Value -in @(2, 10)) # Logon Type: Interactive or RemoteInteractive
            } |
            Select-Object -First 1 -Property @{
                Name       = 'ComputerName'
                Expression = { $_.Properties[11].Value }
            }, TimeCreated
                
        } -ArgumentList $dc, $filterHash, $username
        
        # Wait with timeout
        $completed = Wait-Job $job -Timeout $Config.UserResolution.TimeoutSeconds
        
        if ($completed) {
            $result = Receive-Job $job
            Remove-Job $job
            
            if ($result -and $result.ComputerName) {
                $computerName = $result.ComputerName
                Write-EMSLog -Message "Event Log resolved $UserID to $computerName (Last logon: $($result.TimeCreated))" `
                    -Severity 'Success' -Category 'UserResolution'
                return $computerName
            }
            else {
                Write-EMSLog -Message "No recent logon events found for $UserID" -Severity 'Warning' -Category 'UserResolution'
                return $null
            }
        }
        else {
            # Timeout
            Stop-Job $job
            Remove-Job $job
            Write-EMSLog -Message "Event Log search timed out after $($Config.UserResolution.TimeoutSeconds) seconds" `
                -Severity 'Warning' -Category 'UserResolution'
            return $null
        }
        
    }
    catch {
        Write-EMSLog -Message "Event Log search error: $_" -Severity 'Error' -Category 'UserResolution'
        return $null
    }
}

Export-ModuleMember -Function Resolve-UserToEndpoint, Get-SCCMUserDevice, Search-EventLogForUser
