<#
    EMS REST API for Enterprise Monitoring System

.NOTES
    Version: 2.9 (Role-based Login + EMS_Admins / EMS_Monitor Authorization)
    Runtime: PowerShell 7.x
#>

#Requires -Version 7.0

#region Initialization

$ErrorActionPreference = 'Stop'

$RootPath   = Split-Path $PSScriptRoot -Parent
$ModulePath = Join-Path $RootPath 'Modules'
$ConfigPath = Join-Path $RootPath 'Config\EMSConfig.json'

Import-Module "$ModulePath\Logging.psm1" -Force
Import-Module "$ModulePath\Database\PSPGSql.psm1" -Force
Import-Module "$ModulePath\Authentication.psm1" -Force
Import-Module "$ModulePath\Authentication\AuthProviders.psm1" -Force

$Global:EMSConfig = Get-Content $ConfigPath -Raw | ConvertFrom-Json
Initialize-PostgreSQLConnection -Config $Global:EMSConfig | Out-Null

if (-not $Global:EMSConfig.PSObject.Properties['Security']) {
    $Global:EMSConfig | Add-Member -MemberType NoteProperty -Name Security -Value ([pscustomobject]@{})
}
if (-not $Global:EMSConfig.Security.PSObject.Properties['AdminGroup']) {
    $Global:EMSConfig.Security | Add-Member -MemberType NoteProperty -Name AdminGroup -Value 'EMS_Admins'
}
if (-not $Global:EMSConfig.Security.PSObject.Properties['MonitorGroup']) {
    $Global:EMSConfig.Security | Add-Member -MemberType NoteProperty -Name MonitorGroup -Value 'EMS_Monitor'
}

Write-Host '[INFO] EMS REST API initializing...' -ForegroundColor Cyan

#endregion

#region Helper Functions

function Add-CorsHeaders {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response
    )

    $origin = $Request.Headers['Origin']

    if (
        $origin -and
        $origin -match '^https?://(localhost|10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2[0-9]|3[0-1])\.\d{1,3}\.\d{1,3})(:\d+)?$'
    ) {
        $Response.Headers['Access-Control-Allow-Origin']  = $origin
        $Response.Headers['Vary']                         = 'Origin'
        $Response.Headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization, X-EMS-Username, X-EMS-Groups, X-EMS-Role'
        $Response.Headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
    }
}

function Write-JsonResponse {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [object]$Body
    )

    Add-CorsHeaders -Request $Request -Response $Response

    $json   = $Body | ConvertTo-Json -Depth 12
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)

    $Response.StatusCode      = $StatusCode
    $Response.ContentType     = 'application/json'
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.OutputStream.Close()
}

function Read-JsonBody {
    param([System.Net.HttpListenerRequest]$Request)

    if ($Request.ContentType -notlike 'application/json*') {
        throw 'Invalid Content-Type'
    }

    $reader = [System.IO.StreamReader]::new($Request.InputStream)
    $raw    = $reader.ReadToEnd()

    if (-not $raw) {
        throw 'Empty request body'
    }

    return $raw | ConvertFrom-Json
}

function Resolve-ProviderValue {
    param($ProviderInput)

    if (-not $ProviderInput) { return 'Standalone' }
    if ($ProviderInput -is [string]) { return $ProviderInput }

    foreach ($prop in @('Name','Id','Value','Label','name','id','value','label')) {
        if ($ProviderInput.PSObject.Properties[$prop] -and $ProviderInput.$prop) {
            return [string]$ProviderInput.$prop
        }
    }

    return 'Standalone'
}

function Convert-IPv4ToUInt32 {
    param([Parameter(Mandatory)][string]$IPAddress)
    $bytes = [System.Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
    [array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Convert-UInt32ToIPv4 {
    param([Parameter(Mandatory)][uint32]$Value)
    $bytes = [BitConverter]::GetBytes($Value)
    [array]::Reverse($bytes)
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Expand-CidrRange {
    param([Parameter(Mandatory)][string]$Cidr)

    if ($Cidr -notmatch '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$') {
        throw "Invalid CIDR format: $Cidr"
    }

    $networkIp = $Matches[1]
    $prefix    = [int]$Matches[2]

    if ($prefix -lt 0 -or $prefix -gt 32) {
        throw "Invalid CIDR prefix: $Cidr"
    }

    if ($prefix -eq 32) { return @($networkIp) }

    $ipValue = Convert-IPv4ToUInt32 -IPAddress $networkIp
    $mask = if ($prefix -eq 0) { [uint32]0 } else { [uint32]([uint32]::MaxValue -shl (32 - $prefix)) }
    $network = $ipValue -band $mask
    $hostCount = [math]::Pow(2, (32 - $prefix))
    $broadcast = [uint32]($network + $hostCount - 1)

    $targets = New-Object System.Collections.Generic.List[string]
    for ($i = [uint32]($network + 1); $i -lt $broadcast; $i++) {
        [void]$targets.Add((Convert-UInt32ToIPv4 -Value $i))
    }

    return $targets
}

function Resolve-ScanTargets {
    param([Parameter(Mandatory)][string[]]$Targets)

    $allTargets = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $Targets) {
        if (-not $entry) { continue }
        $parts = $entry -split '[,\r\n]'
        foreach ($raw in $parts) {
            $item = $raw.Trim()
            if (-not $item) { continue }
            if ($item -match '^\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}$') {
                $expanded = Expand-CidrRange -Cidr $item
                foreach ($ip in $expanded) { [void]$allTargets.Add($ip) }
            }
            else { [void]$allTargets.Add($item) }
        }
    }

    $seen = @{}
    $uniqueTargets = New-Object System.Collections.Generic.List[string]
    foreach ($t in $allTargets) {
        if (-not $seen.ContainsKey($t)) {
            $seen[$t] = $true
            [void]$uniqueTargets.Add($t)
        }
    }

    return $uniqueTargets
}

function Get-RequestUserContext {
    param([System.Net.HttpListenerRequest]$Request)

    $username  = $Request.Headers['X-EMS-Username']
    $groupsRaw = $Request.Headers['X-EMS-Groups']
    $role      = $Request.Headers['X-EMS-Role']

    $groups = @()
    if ($groupsRaw) {
        $groups = $groupsRaw -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }

    return [pscustomobject]@{
        Username = $username
        Groups   = $groups
        Role     = $role
    }
}

function Test-GroupMembership {
    param(
        [string[]]$Groups,
        [string]$RequiredGroup
    )

    foreach ($group in @($Groups)) {
        if (-not $group) { continue }

        if ($group -ieq $RequiredGroup) {
            return $true
        }

        $escapedRequired = [regex]::Escape($RequiredGroup)
        if ($group -match ('(?i)(?:^|,)CN=' + $escapedRequired + '(?:,|$)')) {
            return $true
        }
    }

    return $false
}

function Resolve-UserRole {
    param(
        [string[]]$Groups,
        [pscustomobject]$Config
    )

    $adminGroup   = [string]$Config.Security.AdminGroup
    $monitorGroup = [string]$Config.Security.MonitorGroup

    if (Test-GroupMembership -Groups $Groups -RequiredGroup $adminGroup) {
        return 'Admin'
    }

    if (Test-GroupMembership -Groups $Groups -RequiredGroup $monitorGroup) {
        return 'Monitor'
    }

    return $null
}

function Get-UserPermissionsObject {
    param([string]$Role)

    switch ($Role) {
        'Admin' {
            return @{
                canView    = $true
                canScan    = $true
                canArchive = $true
                canAdmin   = $true
            }
        }
        'Monitor' {
            return @{
                canView    = $true
                canScan    = $false
                canArchive = $false
                canAdmin   = $false
            }
        }
        default {
            return @{
                canView    = $false
                canScan    = $false
                canArchive = $false
                canAdmin   = $false
            }
        }
    }
}

function Test-ViewerAccess {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [pscustomobject]$Config
    )

    $ctx = Get-RequestUserContext -Request $Request
    if (-not $ctx.Username) { return $false }

    $role = if ($ctx.Role) { $ctx.Role } else { Resolve-UserRole -Groups $ctx.Groups -Config $Config }
    return $role -in @('Admin', 'Monitor')
}

function Test-AdminAccess {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [pscustomobject]$Config
    )

    $ctx = Get-RequestUserContext -Request $Request
    if (-not $ctx.Username) { return $false }

    $role = if ($ctx.Role) { $ctx.Role } else { Resolve-UserRole -Groups $ctx.Groups -Config $Config }
    return $role -eq 'Admin'
}

function Require-ViewerAccess {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [pscustomobject]$Config
    )

    if (-not (Test-ViewerAccess -Request $Request -Config $Config)) {
        Write-JsonResponse $Request $Response 403 @{ success = $false; message = 'EMS_Admins or EMS_Monitor membership is required' }
        return $false
    }

    return $true
}

function Require-AdminAccess {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [pscustomobject]$Config
    )

    if (-not (Test-AdminAccess -Request $Request -Config $Config)) {
        Write-JsonResponse $Request $Response 403 @{ success = $false; message = 'EMS_Admins membership is required for this action' }
        return $false
    }

    return $true
}

#endregion

#region Async Scan Worker

function Start-EMSScan {
    param(
        [Parameter(Mandatory)][Guid]$ScanId,
        [Parameter(Mandatory)][string]$Target
    )

    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.Open()

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $runspace

    $null = $ps.AddScript({
        param($ScanId, $Target, $RootPath, $Config)

        function Test-EndpointReachable {
            param([Parameter(Mandatory)][string]$Target,[int]$Attempts = 3,[int]$DelaySeconds = 2)
            for ($i = 1; $i -le $Attempts; $i++) {
                try {
                    $reply = Test-Connection -TargetName $Target -Count 1 -ErrorAction Stop | Select-Object -First 1
                    return [pscustomobject]@{ Reachable = $true; Attempt = $i; Reply = $reply }
                } catch {
                    if ($i -lt $Attempts) { Start-Sleep -Seconds $DelaySeconds }
                }
            }
            return [pscustomobject]@{ Reachable = $false; Attempt = $Attempts; Reply = $null }
        }

        function Get-UtilizationSeverity { param([double]$Value) if ($Value -ge 90) { 'Critical' } elseif ($Value -ge 70) { 'Warning' } else { 'Info' } }
        function Get-DiagnosticStatus { param([string]$Severity) switch ($Severity) { 'Critical' { 'Critical' } 'Warning' { 'Degraded' } default { 'OK' } } }

        function Get-RemoteRegistryValue {
            param([Parameter(Mandatory)][Microsoft.Management.Infrastructure.CimSession]$Session,[Parameter(Mandatory)][ValidateSet('HKLM','HKU')][string]$Hive,[Parameter(Mandatory)][string]$KeyPath,[Parameter(Mandatory)][string]$ValueName)
            $hiveMap = @{ HKLM = 2147483650; HKU = 2147483651 }
            try {
                $reg = Get-CimInstance -CimSession $Session -Namespace root/cimv2 -ClassName StdRegProv -ErrorAction Stop
                $stringResult = Invoke-CimMethod -InputObject $reg -MethodName GetStringValue -Arguments @{ hDefKey = [uint32]$hiveMap[$Hive]; sSubKeyName = $KeyPath; sValueName = $ValueName } -ErrorAction SilentlyContinue
                if ($stringResult.sValue) { return $stringResult.sValue }
                $dwordResult = Invoke-CimMethod -InputObject $reg -MethodName GetDWORDValue -Arguments @{ hDefKey = [uint32]$hiveMap[$Hive]; sSubKeyName = $KeyPath; sValueName = $ValueName } -ErrorAction SilentlyContinue
                if ($null -ne $dwordResult.uValue) { return [string]$dwordResult.uValue }
            } catch { return $null }
            return $null
        }

        function Test-RsopPolicyEvidence {
            param(
                [Parameter(Mandatory)][Microsoft.Management.Infrastructure.CimSession]$Session,
                [string]$Sid,
                [string[]]$Patterns
            )

            $found = $false
            $matchText = $null

            $namespaces = New-Object System.Collections.Generic.List[string]

            if ($Sid) {
                $rsopSid = $Sid -replace '-', '_'
                [void]$namespaces.Add("root\RSOP\User\$rsopSid")
            }

            [void]$namespaces.Add("root\RSOP\Computer")

            foreach ($ns in $namespaces) {
                foreach ($className in @('RSOP_RegistryPolicySetting','RSOP_PolicySetting')) {
                    try {
                        $items = Get-CimInstance -CimSession $Session -Namespace $ns -ClassName $className -ErrorAction SilentlyContinue

                        foreach ($item in @($items)) {
                            $text = ($item | Out-String)

                            foreach ($pattern in @($Patterns)) {
                                if ($text -match [regex]::Escape($pattern)) {
                                    $found = $true
                                    $matchText = "$ns/$className matched [$pattern]"
                                    return [pscustomobject]@{
                                        Found = $found
                                        Match = $matchText
                                    }
                                }
                            }
                        }
                    }
                    catch {
                        # RSOP namespace/classes may not exist on all endpoints.
                    }
                }
            }

            return [pscustomobject]@{
                Found = $false
                Match = $null
            }
        }
        function Resolve-RemoteLoggedOnUserSid {
            param(
                [Parameter(Mandatory)][Microsoft.Management.Infrastructure.CimSession]$Session,
                [string]$DomainUser
            )

            if (-not $DomainUser -or $DomainUser -eq 'N/A') {
                return $null
            }

            $domain = $null
            $user   = $null

            if ($DomainUser -match '^(?<domain>[^\\]+)\\(?<user>.+)$') {
                $domain = $Matches['domain']
                $user   = $Matches['user']
            }
            else {
                $user = $DomainUser
            }

            # Method 1: Translate domain\user to SID using domain lookup from API server
            try {
                $ntName = if ($domain) { "$domain\$user" } else { $user }
                $sid = ([System.Security.Principal.NTAccount]$ntName).Translate([System.Security.Principal.SecurityIdentifier]).Value
                if ($sid) { return $sid }
            }
            catch {}

            # Method 2: Query remote Win32_UserAccount through DCOM
            try {
                if ($domain -and $user) {
                    $safeDomain = $domain.Replace("'", "''")
                    $safeUser   = $user.Replace("'", "''")
                    $acct = Get-CimInstance -CimSession $Session -ClassName Win32_UserAccount -Filter "Name='$safeUser' AND Domain='$safeDomain'" -ErrorAction SilentlyContinue | Select-Object -First 1
                    if ($acct -and $acct.SID) { return [string]$acct.SID }
                }
            }
            catch {}

            # Method 3: Enumerate loaded HKU SIDs and match Volatile Environment USERNAME/USERDOMAIN
            try {
                $reg = Get-CimInstance -CimSession $Session -Namespace root/cimv2 -ClassName StdRegProv -ErrorAction Stop
                $enum = Invoke-CimMethod -InputObject $reg -MethodName EnumKey -Arguments @{
                    hDefKey     = [uint32]2147483651
                    sSubKeyName = ''
                } -ErrorAction SilentlyContinue

                foreach ($sidKey in @($enum.sNames)) {
                    if ($sidKey -notmatch '^S-1-5-21-') { continue }

                    $vu = Invoke-CimMethod -InputObject $reg -MethodName GetStringValue -Arguments @{
                        hDefKey     = [uint32]2147483651
                        sSubKeyName = "$sidKey\Volatile Environment"
                        sValueName  = 'USERNAME'
                    } -ErrorAction SilentlyContinue

                    $vd = Invoke-CimMethod -InputObject $reg -MethodName GetStringValue -Arguments @{
                        hDefKey     = [uint32]2147483651
                        sSubKeyName = "$sidKey\Volatile Environment"
                        sValueName  = 'USERDOMAIN'
                    } -ErrorAction SilentlyContinue

                    if ($vu.sValue -and $user -and ($vu.sValue -ieq $user)) {
                        if (-not $domain -or -not $vd.sValue -or ($vd.sValue -ieq $domain)) {
                            return $sidKey
                        }
                    }
                }
            }
            catch {}
            # Method 4: Win32_UserProfile fallback for domain logged-on user.
            # Covers cases like SNPL\500004 where Win32_UserAccount returns blank
            # but Win32_UserProfile has C:\Users\500004 with the correct SID.
            try {
                if ($user) {
                    $profiles = Get-CimInstance -CimSession $Session -ClassName Win32_UserProfile -ErrorAction SilentlyContinue

                    foreach ($profile in @($profiles)) {
                        if (-not $profile.SID -or -not $profile.LocalPath) { continue }

                        $profileLeaf = Split-Path -Path ([string]$profile.LocalPath) -Leaf

                        if (
                            $profileLeaf -ieq $user -or
                            $profileLeaf -like "$user.*" -or
                            $profileLeaf -like "*.$user"
                        ) {
                            return [string]$profile.SID
                        }
                    }

                    $loadedProfiles = @(
                        $profiles | Where-Object {
                            $_.Loaded -eq $true -and
                            $_.SID -match '^S-1-5-21-' -and
                            $_.LocalPath
                        }
                    )

                    if ($loadedProfiles.Count -eq 1) {
                        return [string]$loadedProfiles[0].SID
                    }
                }
            }
            catch {}

            return $null
        }
        function Resolve-TargetIPAddress {
            param([Parameter(Mandatory)][string]$Target)
            if ($Target -match '^(?:\d{1,3}\.){3}\d{1,3}$') { return $Target }
            try {
                $resolved = [System.Net.Dns]::GetHostAddresses($Target) | Where-Object { $_.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork } | Select-Object -First 1
                if ($resolved) { return $resolved.IPAddressToString }
            } catch {}
            return $null
        }

        function Get-TargetMetrics {
            param([string]$ComputerName)
            $session = $null
            try {
                $targetNames = @('.', 'localhost', $env:COMPUTERNAME)
                $isLocal = $targetNames -contains $ComputerName
                if ($isLocal) {
                    $cpuInstances = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop
                    $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
                    $systemDrive = [string]$os.SystemDrive
                    $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$systemDrive'" -ErrorAction Stop
                } else {
                    $sessionOption = New-CimSessionOption -Protocol Dcom
                    $session = New-CimSession -ComputerName $ComputerName -SessionOption $sessionOption -ErrorAction Stop
                    $cpuInstances = Get-CimInstance -CimSession $session -ClassName Win32_Processor -ErrorAction Stop
                    $os = Get-CimInstance -CimSession $session -ClassName Win32_OperatingSystem -ErrorAction Stop
                    $systemDrive = [string]$os.SystemDrive
                    $disk = Get-CimInstance -CimSession $session -ClassName Win32_LogicalDisk -Filter "DeviceID='$systemDrive'" -ErrorAction Stop
                }
                $cpuAverage = ($cpuInstances | Measure-Object -Property LoadPercentage -Average).Average
                $cpuUtilization = if ($null -ne $cpuAverage) { [Math]::Round([double]$cpuAverage, 0) } else { 0 }
                $memoryUtilization = if ($os.TotalVisibleMemorySize -gt 0) { [Math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 0) } else { 0 }
                if (-not $disk) {
                    if ($isLocal) { $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | Select-Object -First 1 }
                    else { $disk = Get-CimInstance -CimSession $session -ClassName Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop | Select-Object -First 1 }
                }
                $driveUtilization = 0; $driveName = $null
                if ($disk -and $disk.Size -gt 0) { $driveUtilization = [Math]::Round((($disk.Size - $disk.FreeSpace) / $disk.Size) * 100, 0); $driveName = $disk.DeviceID }
                return [pscustomobject]@{ cpuUtilization=$cpuUtilization; memoryUtilization=$memoryUtilization; driveUtilization=$driveUtilization; systemDrive = if ($driveName) { $driveName } else { $systemDrive } }
            } finally { if ($session) { $session | Remove-CimSession -ErrorAction SilentlyContinue } }
        }

        function Get-EndpointInventory {
            param([string]$Target)
            $session = $null
            try {
                $sessionOption = New-CimSessionOption -Protocol Dcom
                $session = New-CimSession -ComputerName $Target -SessionOption $sessionOption -ErrorAction Stop
                $cs = Get-CimInstance -CimSession $session -ClassName Win32_ComputerSystem -ErrorAction Stop
                $os = Get-CimInstance -CimSession $session -ClassName Win32_OperatingSystem -ErrorAction Stop
                $localUsers = Get-CimInstance -CimSession $session -ClassName Win32_UserAccount -Filter 'LocalAccount=True' -ErrorAction SilentlyContinue
                $services = Get-CimInstance -CimSession $session -ClassName Win32_Service -ErrorAction SilentlyContinue
                $osEdition = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ValueName 'EditionID'
                if (-not $osEdition) { $osEdition = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ValueName 'ProductName' }
                if (-not $osEdition -and $os.Caption) { $osEdition = [string]$os.Caption }
                $osVersion = [string]$os.Version
                $osBuild   = [string]$os.BuildNumber
                # User-aware policy detection using WMI/DCOM StdRegProv.
                # Screensaver policies are normally user-based under HKU\<SID>\Software\Policies.
                # Software restriction can be machine-based or user-based, so both HKLM and HKU are checked.
                $loggedOnUserSid = Resolve-RemoteLoggedOnUserSid -Session $session -DomainUser $cs.UserName

                $screensaverSources = New-Object System.Collections.Generic.List[string]
                $screenSaveActive  = $null
                $screenSaverSecure = $null
                $screenSaveTimeOut = $null
                $screenSaverExe    = $null

                if ($loggedOnUserSid) {
                    $userDesktopPolicyPath = "$loggedOnUserSid\Software\Policies\Microsoft\Windows\Control Panel\Desktop"

                    $screenSaveActive  = Get-RemoteRegistryValue -Session $session -Hive HKU -KeyPath $userDesktopPolicyPath -ValueName 'ScreenSaveActive'
                    $screenSaverSecure = Get-RemoteRegistryValue -Session $session -Hive HKU -KeyPath $userDesktopPolicyPath -ValueName 'ScreenSaverIsSecure'
                    $screenSaveTimeOut = Get-RemoteRegistryValue -Session $session -Hive HKU -KeyPath $userDesktopPolicyPath -ValueName 'ScreenSaveTimeOut'
                    $screenSaverExe    = Get-RemoteRegistryValue -Session $session -Hive HKU -KeyPath $userDesktopPolicyPath -ValueName 'SCRNSAVE.EXE'

                    if ($screenSaveActive -or $screenSaverSecure -or $screenSaveTimeOut -or $screenSaverExe) {
                        [void]$screensaverSources.Add("UserPolicySID=$loggedOnUserSid; Active=$screenSaveActive; Secure=$screenSaverSecure; Timeout=$screenSaveTimeOut; Exe=$screenSaverExe")
                    }
                    else {
                        # Fallback: non-policy user desktop location, useful for visibility if policy writes here.
                        $userDesktopPath = "$loggedOnUserSid\Control Panel\Desktop"
                        $screenSaveActive2  = Get-RemoteRegistryValue -Session $session -Hive HKU -KeyPath $userDesktopPath -ValueName 'ScreenSaveActive'
                        $screenSaverSecure2 = Get-RemoteRegistryValue -Session $session -Hive HKU -KeyPath $userDesktopPath -ValueName 'ScreenSaverIsSecure'
                        $screenSaveTimeOut2 = Get-RemoteRegistryValue -Session $session -Hive HKU -KeyPath $userDesktopPath -ValueName 'ScreenSaveTimeOut'
                        $screenSaverExe2    = Get-RemoteRegistryValue -Session $session -Hive HKU -KeyPath $userDesktopPath -ValueName 'SCRNSAVE.EXE'

                        if ($screenSaveActive2 -or $screenSaverSecure2 -or $screenSaveTimeOut2 -or $screenSaverExe2) {
                            [void]$screensaverSources.Add("UserDesktopSID=$loggedOnUserSid; Active=$screenSaveActive2; Secure=$screenSaverSecure2; Timeout=$screenSaveTimeOut2; Exe=$screenSaverExe2")
                        }
                    }
                }

                # Machine-level fallback, kept for compatibility.
                $machineScreenSaveActive  = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop' -ValueName 'ScreenSaveActive'
                $machineScreenSaverSecure = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop' -ValueName 'ScreenSaverIsSecure'
                $machineScreenSaveTimeOut = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop' -ValueName 'ScreenSaveTimeOut'
                $machineScreenSaverExe    = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SOFTWARE\Policies\Microsoft\Windows\Control Panel\Desktop' -ValueName 'SCRNSAVE.EXE'

                if ($machineScreenSaveActive -or $machineScreenSaverSecure -or $machineScreenSaveTimeOut -or $machineScreenSaverExe) {
                    [void]$screensaverSources.Add("MachinePolicy; Active=$machineScreenSaveActive; Secure=$machineScreenSaverSecure; Timeout=$machineScreenSaveTimeOut; Exe=$machineScreenSaverExe")
                }

                # RSOP fallback for user-applied screensaver GPO.
                # This catches cases where gpresult shows the policy but HKU registry read does not expose it.
                if ($screensaverSources.Count -eq 0) {
                    $rsopScreen = Test-RsopPolicyEvidence -Session $session -Sid $loggedOnUserSid -Patterns @(
                        'ScreenSaveActive',
                        'ScreenSaverIsSecure',
                        'ScreenSaveTimeOut',
                        'SCRNSAVE.EXE',
                        'Control Panel\Desktop',
                        'Screen Saver'
                    )

                    if ($rsopScreen.Found) {
                        [void]$screensaverSources.Add("RSOP User/Machine GPO evidence: $($rsopScreen.Match)")
                    }
                }
                $screensaverPolicy = if ($screensaverSources.Count -gt 0) {
                    'Configured'
                }
                else {
                    if ($loggedOnUserSid) { "Not Configured - Checked user SID $loggedOnUserSid and machine policy" }
                    else { 'Not Configured - Logged-on user SID could not be resolved; checked machine policy only' }
                }

                $restrictSources = New-Object System.Collections.Generic.List[string]

                # Machine-level Software Restriction Policy
                $machineSaferDefaultLevel = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SOFTWARE\Policies\Microsoft\Windows\Safer\CodeIdentifiers' -ValueName 'DefaultLevel'
                if ($machineSaferDefaultLevel) {
                    [void]$restrictSources.Add("Machine SRP DefaultLevel=$machineSaferDefaultLevel")
                }

                # User-level Software Restriction Policy
                if ($loggedOnUserSid) {
                    $userSaferPath = "$loggedOnUserSid\Software\Policies\Microsoft\Windows\Safer\CodeIdentifiers"
                    $userSaferDefaultLevel = Get-RemoteRegistryValue -Session $session -Hive HKU -KeyPath $userSaferPath -ValueName 'DefaultLevel'
                    if ($userSaferDefaultLevel) {
                        [void]$restrictSources.Add("User SRP SID=$loggedOnUserSid DefaultLevel=$userSaferDefaultLevel")
                    }
                }

                # AppLocker / SRPv2 normally stores enforcement per collection.
                foreach ($collection in @('Exe','Msi','Script','Dll','Appx')) {
                    $mode = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath "SOFTWARE\Policies\Microsoft\Windows\SrpV2\$collection" -ValueName 'EnforcementMode'
                    if ($mode) {
                        [void]$restrictSources.Add("AppLocker $collection EnforcementMode=$mode")
                    }
                }

                # Legacy root check retained for compatibility.
                $applockerRootState = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SOFTWARE\Policies\Microsoft\Windows\SrpV2' -ValueName 'EnforcementMode'
                if ($applockerRootState) {
                    [void]$restrictSources.Add("AppLocker Root EnforcementMode=$applockerRootState")
                }

                # Windows Installer restrictions, machine and user.
                $machineDisableMSI = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SOFTWARE\Policies\Microsoft\Windows\Installer' -ValueName 'DisableMSI'
                if ($machineDisableMSI) {
                    [void]$restrictSources.Add("Machine Installer DisableMSI=$machineDisableMSI")
                }

                if ($loggedOnUserSid) {
                    $userInstallerPath = "$loggedOnUserSid\Software\Policies\Microsoft\Windows\Installer"
                    $userDisableMSI = Get-RemoteRegistryValue -Session $session -Hive HKU -KeyPath $userInstallerPath -ValueName 'DisableMSI'
                    if ($userDisableMSI) {
                        [void]$restrictSources.Add("User Installer SID=$loggedOnUserSid DisableMSI=$userDisableMSI")
                    }
                }

                # Additional Windows Installer restriction checks.
                # Some GPOs use DisableUserInstalls or AlwaysInstallElevated instead of DisableMSI.
                $machineDisableUserInstalls = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SOFTWARE\Policies\Microsoft\Windows\Installer' -ValueName 'DisableUserInstalls'
                if ($machineDisableUserInstalls) {
                    [void]$restrictSources.Add("Machine Installer DisableUserInstalls=$machineDisableUserInstalls")
                }

                $machineAlwaysInstallElevated = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SOFTWARE\Policies\Microsoft\Windows\Installer' -ValueName 'AlwaysInstallElevated'
                if ($machineAlwaysInstallElevated) {
                    [void]$restrictSources.Add("Machine Installer AlwaysInstallElevated=$machineAlwaysInstallElevated")
                }

                if ($loggedOnUserSid) {
                    $userInstallerPath = "$loggedOnUserSid\Software\Policies\Microsoft\Windows\Installer"

                    $userDisableUserInstalls = Get-RemoteRegistryValue -Session $session -Hive HKU -KeyPath $userInstallerPath -ValueName 'DisableUserInstalls'
                    if ($userDisableUserInstalls) {
                        [void]$restrictSources.Add("User Installer SID=$loggedOnUserSid DisableUserInstalls=$userDisableUserInstalls")
                    }

                    $userAlwaysInstallElevated = Get-RemoteRegistryValue -Session $session -Hive HKU -KeyPath $userInstallerPath -ValueName 'AlwaysInstallElevated'
                    if ($userAlwaysInstallElevated) {
                        [void]$restrictSources.Add("User Installer SID=$loggedOnUserSid AlwaysInstallElevated=$userAlwaysInstallElevated")
                    }
                }

                # RSOP fallback for user/machine applied software restriction GPO.
                if ($restrictSources.Count -eq 0) {
                    $rsopRestrict = Test-RsopPolicyEvidence -Session $session -Sid $loggedOnUserSid -Patterns @(
                        'Software\Policies\Microsoft\Windows\Safer\CodeIdentifiers',
                        'Safer\CodeIdentifiers',
                        'Software Restriction',
                        'DisallowRun',
                        'RestrictRun',
                        'SrpV2',
                        'AppLocker',
                        'DisableMSI',
                        'DisableUserInstalls',
                        'AlwaysInstallElevated',
                        'Windows\Installer'
                    )

                    if ($rsopRestrict.Found) {
                        [void]$restrictSources.Add("RSOP User/Machine GPO evidence: $($rsopRestrict.Match)")
                    }
                }
                $restrictSoftwarePolicy = if ($restrictSources.Count -gt 0) {
                    'Configured'
                }
                else {
                    if ($loggedOnUserSid) { "Not Configured - Checked user SID $loggedOnUserSid and machine policy" }
                    else { 'Not Configured - Logged-on user SID could not be resolved; checked machine policy only' }
                }
$lastPolicyChecked = 'Unknown'
                try {
                    $gpEvents = Get-WinEvent -ComputerName $Target -LogName 'Microsoft-Windows-GroupPolicy/Operational' -MaxEvents 50 -ErrorAction Stop | Where-Object { $_.Id -in 8000,8001,5312,4016,7016 } | Sort-Object TimeCreated -Descending
                    if ($gpEvents -and $gpEvents.Count -gt 0) { $lastPolicyChecked = $gpEvents[0].TimeCreated.ToString('yyyy-MM-dd HH:mm:ss') }
                } catch { $lastPolicyChecked = 'Unknown' }
                $enabledLocalUsers = $localUsers | Where-Object { $_.Disabled -eq $false } | Select-Object -ExpandProperty Name -ErrorAction SilentlyContinue
                $enabledLocalUsersText = if ($enabledLocalUsers) { ($enabledLocalUsers -join '; ') } else { 'None' }
                $securityKBs = @(); try { $securityKBs = Get-HotFix -ComputerName $Target -ErrorAction Stop | Where-Object { $_.HotFixID -match '^KB' -and ($_.Description -like '*Security*' -or $_.Description -like '*Update*') } | Sort-Object InstalledOn -Descending | Select-Object -First 2 } catch { $securityKBs = @() }
                $allSecurityKBs = if ($securityKBs.Count -gt 0) { ($securityKBs | Select-Object -ExpandProperty HotFixID) -join '; ' } else { 'None' }
                $allSecurityKBsInstalledOn = if ($securityKBs.Count -gt 0) { ($securityKBs | ForEach-Object { if ($_.InstalledOn) { (Get-Date $_.InstalledOn).ToString('yyyy-MM-dd') } else { 'Unknown' } }) -join '; ' } else { 'None' }
                $symantecSvc = $services | Where-Object { $_.Name -in @('smc','SepMasterService','SymantecManagementClient') -or $_.DisplayName -like '*Symantec*' } | Select-Object -First 1
                $symantecStatus = if ($symantecSvc) { "$($symantecSvc.Name) - $($symantecSvc.State)" } else { 'Not Installed' }
                # Read-only USB / removable storage write restriction detection.
                # Checks legacy StorageDevicePolicies, GPO RemovableStorageDevices, user policy under HKU, and RSOP evidence.
                $readOnlyUsbSources = New-Object System.Collections.Generic.List[string]

                # Legacy/local machine write-protect setting.
                $writeProtect = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SYSTEM\CurrentControlSet\Control\StorageDevicePolicies' -ValueName 'WriteProtect'
                if ($writeProtect -eq '1') {
                    [void]$readOnlyUsbSources.Add('HKLM StorageDevicePolicies WriteProtect=1')
                }

                # Machine GPO: Removable Storage Devices root policy.
                $machineRemovableRoot = 'SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices'
                foreach ($valueName in @('Deny_Write','Deny_All')) {
                    $v = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath $machineRemovableRoot -ValueName $valueName
                    if ($v -eq '1') {
                        [void]$readOnlyUsbSources.Add("HKLM RemovableStorageDevices $valueName=1")
                    }
                }

                # Machine GPO: Removable Disk class GUID policy.
                $removableDiskGuid = '{53f56307-b6bf-11d0-94f2-00a0c91efb8b}'
                $machineRemovableDiskPath = "SOFTWARE\Policies\Microsoft\Windows\RemovableStorageDevices\$removableDiskGuid"
                foreach ($valueName in @('Deny_Write','Deny_All')) {
                    $v = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath $machineRemovableDiskPath -ValueName $valueName
                    if ($v -eq '1') {
                        [void]$readOnlyUsbSources.Add("HKLM RemovableDisk $valueName=1")
                    }
                }

                # User GPO under logged-on user's HKU hive.
                if ($loggedOnUserSid) {
                    $userRemovableRoot = "$loggedOnUserSid\Software\Policies\Microsoft\Windows\RemovableStorageDevices"
                    foreach ($valueName in @('Deny_Write','Deny_All')) {
                        $v = Get-RemoteRegistryValue -Session $session -Hive HKU -KeyPath $userRemovableRoot -ValueName $valueName
                        if ($v -eq '1') {
                            [void]$readOnlyUsbSources.Add("HKU User RemovableStorageDevices $valueName=1")
                        }
                    }

                    $userRemovableDiskPath = "$loggedOnUserSid\Software\Policies\Microsoft\Windows\RemovableStorageDevices\$removableDiskGuid"
                    foreach ($valueName in @('Deny_Write','Deny_All')) {
                        $v = Get-RemoteRegistryValue -Session $session -Hive HKU -KeyPath $userRemovableDiskPath -ValueName $valueName
                        if ($v -eq '1') {
                            [void]$readOnlyUsbSources.Add("HKU User RemovableDisk $valueName=1")
                        }
                    }
                }

                # RSOP fallback: catches GPO evidence when registry value is not directly visible.
                if ($readOnlyUsbSources.Count -eq 0 -and (Get-Command Test-RsopPolicyEvidence -ErrorAction SilentlyContinue)) {
                    $rsopUsb = Test-RsopPolicyEvidence -Session $session -Sid $loggedOnUserSid -Patterns @(
                        'RemovableStorageDevices',
                        'Deny_Write',
                        'Deny_All',
                        'StorageDevicePolicies',
                        'WriteProtect',
                        'Removable Disks',
                        'Deny write access'
                    )

                    if ($rsopUsb.Found) {
                        [void]$readOnlyUsbSources.Add("RSOP evidence: $($rsopUsb.Match)")
                    }
                }

                $readOnlyUsb = if ($readOnlyUsbSources.Count -gt 0) { 'Enabled' } else { 'Disabled / Not Configured' }
                $timeType = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -ValueName 'Type'
                $ntpServer = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SYSTEM\CurrentControlSet\Services\W32Time\Parameters' -ValueName 'NtpServer'
                $ntpClientEnabled = Get-RemoteRegistryValue -Session $session -Hive HKLM -KeyPath 'SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpClient' -ValueName 'Enabled'
                $w32timeSvc = $services | Where-Object { $_.Name -eq 'W32Time' } | Select-Object -First 1
                $timeSync = if ($timeType -or $ntpServer -or $ntpClientEnabled -eq '1' -or ($w32timeSvc -and $w32timeSvc.State -eq 'Running')) { 'Configured' } else { 'Unknown' }
                # BIOS password status detection restored from previous working version.
                # Vendor-specific WMI/CIM namespaces are used because BIOS password status is not exposed
                # through a single standard Windows class across Dell, HP and Lenovo endpoints.
                $manufacturer = [string]$cs.Manufacturer
                $poweronPasswordStatus = 'Unknown'
                $adminPasswordStatus   = 'Unknown'

                try {
                    if ($manufacturer -match 'Dell') {
                        $dellPwd = Get-CimInstance -CimSession $session `
                            -Namespace 'root\dcim\sysman' `
                            -ClassName 'DCIM_BIOSPassword' `
                            -ErrorAction SilentlyContinue

                        if ($dellPwd) {
                            $poweronPasswordStatus = if ($dellPwd.IsPasswordSet) { 'Configured' } else { 'Not Configured' }
                            $adminPasswordStatus   = if ($dellPwd.AdminPasswordSet) { 'Configured' } else { 'Not Configured' }
                        }
                    }
                    elseif ($manufacturer -match 'HP|Hewlett') {
                        $hpPwd = Get-CimInstance -CimSession $session `
                            -Namespace 'root\HP\InstrumentedBIOS' `
                            -ClassName 'HP_BIOSSetting' `
                            -ErrorAction SilentlyContinue |
                            Where-Object { $_.Name -match 'Password' }

                        if ($hpPwd) {
                            $poweronPasswordStatus = 'Configured'
                            $adminPasswordStatus   = 'Configured'
                        }
                    }
                    elseif ($manufacturer -match 'Lenovo') {
                        $lenovoPwd = Get-CimInstance -CimSession $session `
                            -Namespace 'root\wmi' `
                            -ClassName 'Lenovo_BiosSetting' `
                            -ErrorAction SilentlyContinue |
                            Where-Object { $_.CurrentSetting -match 'Password' }

                        if ($lenovoPwd) {
                            $poweronPasswordStatus = 'Configured'
                            $adminPasswordStatus   = 'Configured'
                        }
                    }
                }
                catch {
                    $poweronPasswordStatus = 'Unknown'
                    $adminPasswordStatus   = 'Unknown'
                }
                return [pscustomobject]@{
                    ComputerName=$cs.Name; Manufacturer=$cs.Manufacturer; Model=$cs.Model; DomainUser = if ($cs.UserName) { $cs.UserName } else { 'N/A' }
                    Screensaver_Policy=$screensaverPolicy; RestrictSoftwareInstallation_Policy=$restrictSoftwarePolicy; LastPolicy_Checked=$lastPolicyChecked
                    EnabledLocalUserAccount=$enabledLocalUsersText; AllSecurityKBs=$allSecurityKBs; AllSecurityKBsInstalledOn=$allSecurityKBsInstalledOn
                    OS_Edition = if ($osEdition) { $osEdition } else { 'Unknown' }; OS_Version=$osVersion; OS_Build=$osBuild
                    SymantecManagementAgent=$symantecStatus; ReadOnlyUSB=$readOnlyUsb; Poweron_Password=$poweronPasswordStatus; Admin_Password=$adminPasswordStatus; TimeSyncWithNTP=$timeSync; LastChecked=Get-Date; Comments=$null
                }
            } finally { if ($session) { $session | Remove-CimSession -ErrorAction SilentlyContinue } }
        }

        try {
            Import-Module "$RootPath\Modules\Logging.psm1" -Force
            Import-Module "$RootPath\Modules\Database\PSPGSql.psm1" -Force
            Import-Module CimCmdlets -ErrorAction Stop
            Initialize-PostgreSQLConnection -Config $Config | Out-Null
            Invoke-PGQuery -NonQuery -Query @"
UPDATE scans
SET status = 'running'
WHERE scan_id = @scanId;
"@ -Parameters @{ scanId = $ScanId }
            Write-EMSLog -Message 'Scan started' -Category Scan -Target $Target
            $start = Get-Date
            $reachability = Test-EndpointReachable -Target $Target -Attempts 3 -DelaySeconds 2
            if (-not $reachability.Reachable) {
                $duration = [Math]::Round((New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds, 2)
                $resolvedIpAddress = Resolve-TargetIPAddress -Target $Target
                $result = @{ hostname=$Target; ipAddress=$resolvedIpAddress; healthScore=0; criticalAlerts=0; warningAlerts=1; infoAlerts=0; diagnostics=@([pscustomobject]@{category='Connectivity'; checkName='Reachability'; metricName='Reachability'; metricValue=$null; unit=''; status='Failed'; severity='Warning'; message='Not reachable after 3 attempts.'}) }
                $json = $result | ConvertTo-Json -Depth 10
                Invoke-PGQuery -NonQuery -Query @"
UPDATE scans
SET status='failed', health_score=0, critical_alerts=0, warning_alerts=1, info_alerts=0, execution_time_sec=@d, result_json=CAST(@json AS jsonb), error_message='Not reachable after 3 attempts', completed_at=NOW()
WHERE scan_id=@scanId;
"@ -Parameters @{ scanId=$ScanId; d=$duration; json=$json }
                Invoke-PGQuery -NonQuery -Query @"
INSERT INTO scan_inventory_results (scan_id, computer_name, lastchecked, comments)
VALUES (@scanId, @computerName, NOW(), @comments)
ON CONFLICT (scan_id)
DO UPDATE SET computer_name=EXCLUDED.computer_name, comments=EXCLUDED.comments, lastchecked=NOW();
"@ -Parameters @{ scanId=$ScanId; computerName=$Target; comments='Not reachable after 3 attempts' }
                Write-EMSLog -Message 'Scan failed: Not reachable after 3 attempts' -Severity Warning -Category Scan -Target $Target
                return
            }
            $latencyMs = $null
            if ($null -ne $reachability.Reply -and $reachability.Reply.PSObject.Properties['Latency']) { $latencyMs = [double]$reachability.Reply.Latency }
            $metricCollectionError = $null; $cpuUtilization = $null; $memoryUtilization = $null; $driveUtilization = $null; $driveName = $null
            try {
                $metrics = Get-TargetMetrics -ComputerName $Target
                $cpuUtilization=[double]$metrics.cpuUtilization; $memoryUtilization=[double]$metrics.memoryUtilization; $driveUtilization=[double]$metrics.driveUtilization; $driveName=[string]$metrics.systemDrive
            } catch { $metricCollectionError = if ($_.Exception.Message -match 'Access is denied|Access denied') { 'Access denied while collecting CPU/Memory/Drive metrics' } else { $_.Exception.Message } }
            $inventory = $null; $inventoryError = $null
            try { $inventory = Get-EndpointInventory -Target $Target } catch {
                $inventoryError = if ($_.Exception.Message -match 'Access is denied|Access denied') { 'Access denied while collecting inventory data' } else { $_.Exception.Message }
                $inventory = [pscustomobject]@{ ComputerName=$Target; Manufacturer=$null; Model=$null; DomainUser=$null; Screensaver_Policy=$null; RestrictSoftwareInstallation_Policy=$null; LastPolicy_Checked=$null; EnabledLocalUserAccount=$null; AllSecurityKBs=$null; AllSecurityKBsInstalledOn=$null; OS_Edition=$null; OS_Version=$null; OS_Build=$null; SymantecManagementAgent=$null; ReadOnlyUSB=$null; Poweron_Password='Unknown'; Admin_Password='Unknown'; TimeSyncWithNTP=$null; LastChecked=Get-Date; Comments="Inventory collection failed: $inventoryError" }
            }
            $diagnostics = @()
            if ($metricCollectionError) {
                $diagnostics += [pscustomobject]@{ category='Performance'; checkName='MetricCollection'; metricName='Metric Collection'; metricValue=$null; unit=''; status='Degraded'; severity='Warning'; message="Unable to collect CPU/Memory/Drive metrics: $metricCollectionError" }
            } else {
                $cpuSeverity = Get-UtilizationSeverity -Value $cpuUtilization
                $diagnostics += [pscustomobject]@{ category='Performance'; checkName='CPUUtilization'; metricName='CPU Utilization'; metricValue=$cpuUtilization; unit='%'; status=(Get-DiagnosticStatus -Severity $cpuSeverity); severity=$cpuSeverity; message="CPU utilization is $cpuUtilization%." }
                $memorySeverity = Get-UtilizationSeverity -Value $memoryUtilization
                $diagnostics += [pscustomobject]@{ category='Performance'; checkName='MemoryUtilization'; metricName='Memory Utilization'; metricValue=$memoryUtilization; unit='%'; status=(Get-DiagnosticStatus -Severity $memorySeverity); severity=$memorySeverity; message="Memory utilization is $memoryUtilization%." }
                $driveSeverity = Get-UtilizationSeverity -Value $driveUtilization
                                $driveMetricName = 'Drive Utilization'
                $driveMessage    = "Drive utilization is $driveUtilization%."
                if ($driveName) {
                    $driveMetricName = "Drive Utilization ($driveName)"
                    $driveMessage    = "Drive utilization for $driveName is $driveUtilization%."
                }
                $diagnostics += [pscustomobject]@{
                    category    = 'Storage'
                    checkName   = 'DriveUtilization'
                    metricName  = $driveMetricName
                    metricValue = $driveUtilization
                    unit        = '%'
                    status      = (Get-DiagnosticStatus -Severity $driveSeverity)
                    severity    = $driveSeverity
                    message     = $driveMessage
                }
            }
            $pingMessage = 'Ping response received.'
if ($null -ne $latencyMs) {
    $pingMessage = "Ping response received. Measured latency: $latencyMs ms."
}

$diagnostics += [pscustomobject]@{
    category    = 'Connectivity'
    checkName   = 'PingResponse'
    metricName  = 'Ping Response'
    metricValue = $latencyMs
    unit        = ' ms'
    status      = 'OK'
    severity    = 'Info'
    message     = $pingMessage
		}
            $diagnostics += [pscustomobject]@{ category='System'; checkName='ScanExecution'; metricName='Scan Execution'; metricValue=$null; unit=''; status='Completed'; severity='Info'; message='Scan completed successfully.' }
            $criticalAlerts = ($diagnostics | Where-Object { $_.severity -eq 'Critical' }).Count
            $warningAlerts  = ($diagnostics | Where-Object { $_.severity -eq 'Warning' }).Count
            $infoAlerts     = ($diagnostics | Where-Object { $_.severity -eq 'Info' }).Count
            $healthScore = 100 - ($criticalAlerts * 25) - ($warningAlerts * 10)
            if ($healthScore -lt 0) { $healthScore = 0 }
            if ($healthScore -gt 100) { $healthScore = 100 }
            if ($inventoryError -and -not $inventory.Comments) { $inventory.Comments = "Inventory collection failed: $inventoryError" }
            elseif ($metricCollectionError -and -not $inventory.Comments) { $inventory.Comments = "Metric collection failed: $metricCollectionError" }
            $resolvedIpAddress = Resolve-TargetIPAddress -Target $Target
            $result = @{ hostname=$Target; ipAddress=$resolvedIpAddress; healthScore=[Math]::Round($healthScore, 0); criticalAlerts=$criticalAlerts; warningAlerts=$warningAlerts; infoAlerts=$infoAlerts; diagnostics=$diagnostics }
            $duration = [Math]::Round((New-TimeSpan -Start $start -End (Get-Date)).TotalSeconds, 2)
            $json = $result | ConvertTo-Json -Depth 10
            Invoke-PGQuery -NonQuery -Query @"
UPDATE scans
SET status='completed', health_score=@hs, critical_alerts=@c, warning_alerts=@w, info_alerts=@i, execution_time_sec=@d, result_json=CAST(@json AS jsonb), completed_at=NOW()
WHERE scan_id=@scanId;
"@ -Parameters @{ scanId=$ScanId; hs=$result.healthScore; c=$result.criticalAlerts; w=$result.warningAlerts; i=$result.infoAlerts; d=$duration; json=$json }
            Invoke-PGQuery -NonQuery -Query @"
INSERT INTO scan_inventory_results (
    scan_id, computer_name, manufacturer, model, domain_user, screensaver_policy, restrict_software_installation_policy, lastpolicy_checked, enabled_local_user_account, all_security_kbs, all_security_kbs_installedon, os_edition, os_version, os_build, symantec_management_agent, readonly_usb, poweron_password, admin_password, timesync_with_ntp, lastchecked, comments
)
VALUES (
    @scanId, @computerName, @manufacturer, @model, @domainUser, @screensaverPolicy, @restrictSoftwarePolicy, @lastPolicyChecked, @enabledLocalUserAccount, @allSecurityKBs, @allSecurityKBsInstalledOn, @osEdition, @osVersion, @osBuild, @symantecAgent, @readOnlyUsb, @poweronPassword, @adminPassword, @timeSyncWithNtp, @lastChecked, @comments
)
ON CONFLICT (scan_id)
DO UPDATE SET
    computer_name=EXCLUDED.computer_name, manufacturer=EXCLUDED.manufacturer, model=EXCLUDED.model, domain_user=EXCLUDED.domain_user, screensaver_policy=EXCLUDED.screensaver_policy, restrict_software_installation_policy=EXCLUDED.restrict_software_installation_policy, lastpolicy_checked=EXCLUDED.lastpolicy_checked, enabled_local_user_account=EXCLUDED.enabled_local_user_account, all_security_kbs=EXCLUDED.all_security_kbs, all_security_kbs_installedon=EXCLUDED.all_security_kbs_installedon, os_edition=EXCLUDED.os_edition, os_version=EXCLUDED.os_version, os_build=EXCLUDED.os_build, symantec_management_agent=EXCLUDED.symantec_management_agent, readonly_usb=EXCLUDED.readonly_usb, poweron_password=EXCLUDED.poweron_password, admin_password=EXCLUDED.admin_password, timesync_with_ntp=EXCLUDED.timesync_with_ntp, lastchecked=EXCLUDED.lastchecked, comments=EXCLUDED.comments;
"@ -Parameters @{ scanId=$ScanId; computerName=$inventory.ComputerName; manufacturer=$inventory.Manufacturer; model=$inventory.Model; domainUser=$inventory.DomainUser; screensaverPolicy=$inventory.Screensaver_Policy; restrictSoftwarePolicy=$inventory.RestrictSoftwareInstallation_Policy; lastPolicyChecked=$inventory.LastPolicy_Checked; enabledLocalUserAccount=$inventory.EnabledLocalUserAccount; allSecurityKBs=$inventory.AllSecurityKBs; allSecurityKBsInstalledOn=$inventory.AllSecurityKBsInstalledOn; osEdition=$inventory.OS_Edition; osVersion=$inventory.OS_Version; osBuild=$inventory.OS_Build; symantecAgent=$inventory.SymantecManagementAgent; readOnlyUsb=$inventory.ReadOnlyUSB; poweronPassword=$inventory.Poweron_Password; adminPassword=$inventory.Admin_Password; timeSyncWithNtp=$inventory.TimeSyncWithNTP; lastChecked=$inventory.LastChecked; comments=$inventory.Comments }
            Write-EMSLog -Message 'Scan completed successfully' -Severity Success -Category Scan -Target $Target
        } catch {
            try {
                Import-Module "$RootPath\Modules\Database\PSPGSql.psm1" -Force
                Initialize-PostgreSQLConnection -Config $Config | Out-Null
                Invoke-PGQuery -NonQuery -Query @"
UPDATE scans SET status='failed', error_message=@err, completed_at=NOW() WHERE scan_id=@scanId;
"@ -Parameters @{ scanId = $ScanId; err = $_.Exception.Message }
            } catch {}
            try {
                Import-Module "$RootPath\Modules\Logging.psm1" -Force
                Write-EMSLog -Message "Scan failed: $($_.Exception.Message)" -Severity Error -Category Scan -Target $Target
            } catch {}
        }
    }).AddArgument($ScanId).AddArgument($Target).AddArgument($RootPath).AddArgument($Global:EMSConfig)

    $null = $ps.BeginInvoke()
}

function Start-EMSBatchScan {
    param([Parameter(Mandatory)][string[]]$Targets,[int]$LaunchDelayMs = 100)
    $resolvedTargets = Resolve-ScanTargets -Targets $Targets
    if (-not $resolvedTargets -or $resolvedTargets.Count -eq 0) { throw 'No valid targets found for bulk scan.' }
    $queuedScanIds = New-Object System.Collections.Generic.List[string]
    foreach ($target in $resolvedTargets) {
        $scanId = [guid]::NewGuid()
        Invoke-PGQuery -NonQuery -Query @"
INSERT INTO scans (scan_id, target, status, started_at)
VALUES (@scanId, @target, 'queued', NOW());
"@ -Parameters @{ scanId = $scanId; target = $target }
        [void]$queuedScanIds.Add($scanId.ToString())
        Start-EMSScan -ScanId $scanId -Target $target
        Start-Sleep -Milliseconds $LaunchDelayMs
    }
    return [pscustomobject]@{ targetCount = $resolvedTargets.Count; targets = $resolvedTargets; scanIds = $queuedScanIds }
}

#endregion

#region HTTP Listener

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add('http://+:5000/')
$listener.Start()

Write-Host '========================================'
Write-Host ' EMS REST API (Async Scan Mode + RBAC)'
Write-Host '========================================'
Write-Host ' Address: http://10.192.6.87:5000'
Write-Host ' Allowed AD groups:'
Write-Host "   Admin   : $($Global:EMSConfig.Security.AdminGroup)"
Write-Host "   Monitor : $($Global:EMSConfig.Security.MonitorGroup)"
Write-Host '========================================'

#endregion

#region Request Loop

while ($listener.IsListening) {
    $context  = $listener.GetContext()
    $request  = $context.Request
    $response = $context.Response

    $method = $request.HttpMethod
    $path   = $request.Url.AbsolutePath.TrimEnd('/')

    try {
        if ($method -eq 'OPTIONS') {
            Add-CorsHeaders -Request $request -Response $response
            $response.StatusCode = 204
            $response.Close()
            continue
        }

        Write-Host "[$method] $path" -ForegroundColor Yellow

        if ($method -eq 'GET' -and $path -match '^/computers/(.+)$') {
            if (-not (Require-ViewerAccess -Request $request -Response $response -Config $Global:EMSConfig)) { continue }
            $computerName = [System.Uri]::UnescapeDataString($Matches[1])
            $computer = Invoke-PGQuery -Query @"
SELECT computer_name, ip_address::text AS ip_address, mac_address, operating_system, os_version, os_build, domain, is_domain_joined, computer_type, manufacturer, model, serial_number, location, department, asset_tag, first_seen, last_seen, is_active, notes
FROM computers WHERE computer_name = @computerName LIMIT 1;
"@ -Parameters @{ computerName = $computerName } | Select-Object -First 1
            if (-not $computer) { Write-JsonResponse $request $response 404 @{ success = $false; message = 'Computer not found' }; continue }
            $users = @(); try { $users = Invoke-PGQuery -Query @"
SELECT computer_name, ad_username, display_name, email, department, title, last_logon
FROM computer_ad_users WHERE computer_name = @computerName ORDER BY ad_username;
"@ -Parameters @{ computerName = $computerName } } catch { $users = @() }
            Write-JsonResponse $request $response 200 @{ success = $true; computer = $computer; users = $users }
            continue
        }

        if ($method -eq 'GET' -and $path -match '^/results/(.+)$') {
            if (-not (Require-ViewerAccess -Request $request -Response $response -Config $Global:EMSConfig)) { continue }
            $resultIdRaw = [System.Uri]::UnescapeDataString($Matches[1])
            try { $resultId = [Guid]::Parse($resultIdRaw) } catch { Write-JsonResponse $request $response 400 @{ success = $false; message = 'Invalid result ID format' }; continue }
            $row = Invoke-PGQuery -Query @"
SELECT scan_id, target, status, health_score, critical_alerts, warning_alerts, info_alerts, execution_time_sec, result_json, error_message, started_at, completed_at
FROM scans WHERE scan_id = @scanId LIMIT 1;
"@ -Parameters @{ scanId = $resultId } | Select-Object -First 1
            if (-not $row) { Write-JsonResponse $request $response 404 @{ success = $false; message = 'Result not found' }; continue }
            $resultJson = $null
            if ($row.result_json) { try { $resultJson = $row.result_json | ConvertFrom-Json } catch { $resultJson = $null } }
            Write-JsonResponse $request $response 200 @{ success=$true; id=$row.scan_id; scanId=$row.scan_id; target=$row.target; status=$row.status; healthScore=$row.health_score; criticalAlerts=$row.critical_alerts; warningAlerts=$row.warning_alerts; infoAlerts=$row.info_alerts; executionTimeSeconds=$row.execution_time_sec; errorMessage=$row.error_message; startedAt=$row.started_at; completedAt=$row.completed_at; result=$resultJson }
            continue
        }

        switch ("$method $path") {
            'GET /auth/providers' {
                $providers = $Global:EMSConfig.Authentication.Providers | Where-Object Enabled | Sort-Object Priority | ForEach-Object {
                    $providerName = [string]$_.Name
                    $providerLabel = "$providerName Authentication"
                    [pscustomobject]@{ Name=$providerName; DisplayName=$providerLabel; RequiresCredentials=$true; Priority=[int]$_.Priority; Id=$providerName; Value=$providerName; Label=$providerLabel }
                }
                $defaultProvider = if ($providers.Count -gt 0) { $providers[0].Name } else { $null }
                Write-JsonResponse $request $response 200 @{ providers = $providers; defaultProvider = $defaultProvider }
            }

            'GET /auth/validate' {
                if (-not (Require-ViewerAccess -Request $request -Response $response -Config $Global:EMSConfig)) { break }
                $ctx  = Get-RequestUserContext -Request $request
                $role = Resolve-UserRole -Groups $ctx.Groups -Config $Global:EMSConfig
                Write-JsonResponse $request $response 200 @{ valid = $true; role = $role; permissions = (Get-UserPermissionsObject -Role $role) }
            }

            'POST /auth/login' {
                $body = Read-JsonBody $request
                if (-not $body.username -or -not $body.password) {
                    Write-JsonResponse $request $response 400 @{ success = $false; message = 'Username and password are required' }
                    break
                }

                $provider = Resolve-ProviderValue -ProviderInput $body.provider
                $securePassword = ConvertTo-SecureString $body.password -AsPlainText -Force
                $auth = Invoke-MultiProviderAuth -Username $body.username -SecurePassword $securePassword -Provider $provider -Config $Global:EMSConfig

                if (-not $auth.Success) {
                    Write-JsonResponse $request $response 401 @{ success = $false; message = 'Authentication failed' }
                    break
                }

                $role = Resolve-UserRole -Groups $auth.Groups -Config $Global:EMSConfig
                if (-not $role) {
                    Write-JsonResponse $request $response 403 @{
                        success = $false
                        message = 'Access denied. Only EMS_Admins and EMS_Monitor members are allowed to sign in.'
                    }
                    break
                }

                $permissions = Get-UserPermissionsObject -Role $role
                Write-JsonResponse $request $response 200 @{
                    success  = $true
                    provider = $auth.Provider
                    token    = [guid]::NewGuid().ToString()
                    user     = @{
                        username    = $auth.User
                        displayName = $auth.DisplayName
                        email       = $auth.Email
                        groups      = $auth.Groups
                        role        = $role
                        permissions = $permissions
                    }
                }
            }

            'GET /api/dashboard/stats' {
                if (-not (Require-ViewerAccess -Request $request -Response $response -Config $Global:EMSConfig)) { break }
                $totalComputers=0; $activeComputers=0; $totalScans=0; $healthyEndpoints=0; $criticalAlerts=0; $uniqueEndpoints=0; $completedScans=0; $failedScans=0; $inProgressScans=0; $averageScanTime=$null; $lastScan=$null; $excellentCount=0; $goodCount=0; $fairCount=0; $poorCount=0; $compliantEndpoints=0; $partialCompliantEndpoints=0; $collectionFailedEndpoints=0; $dellBiosUnknownEndpoints=0; $biosPasswordUnknownEndpoints=0; $metricWarningEndpoints=0
                try { $row = Invoke-PGQuery -Query 'SELECT COUNT(*)::int AS total FROM computers;' | Select-Object -First 1; if ($row) { $totalComputers = [int]$row.total } } catch {}
                try { $row = Invoke-PGQuery -Query 'SELECT COUNT(*)::int AS total FROM computers WHERE is_active = true;' | Select-Object -First 1; if ($row) { $activeComputers = [int]$row.total } } catch {}
                try {
                    $row = Invoke-PGQuery -Query @"
SELECT
    COUNT(*)::int AS total_scans,
    COUNT(DISTINCT target)::int AS unique_endpoints,
    COUNT(*) FILTER (WHERE status = 'completed')::int AS completed_scans,
    COUNT(*) FILTER (WHERE status = 'failed')::int AS failed_scans,
    COUNT(*) FILTER (WHERE status IN ('queued', 'running'))::int AS in_progress_scans,
    COUNT(*) FILTER (WHERE status = 'completed' AND health_score >= 90)::int AS healthy_endpoints,
    COALESCE(SUM(critical_alerts) FILTER (WHERE status = 'completed'), 0)::int AS critical_alerts,
    ROUND(COALESCE(AVG(execution_time_sec) FILTER (WHERE status = 'completed' AND execution_time_sec IS NOT NULL),0)::numeric,2) AS average_scan_time,
    MAX(completed_at) AS last_scan,
    COUNT(*) FILTER (WHERE status = 'completed' AND health_score >= 90)::int AS excellent_count,
    COUNT(*) FILTER (WHERE status = 'completed' AND health_score >= 70 AND health_score < 90)::int AS good_count,
    COUNT(*) FILTER (WHERE status = 'completed' AND health_score >= 50 AND health_score < 70)::int AS fair_count,
    COUNT(*) FILTER (WHERE status = 'completed' AND health_score < 50)::int AS poor_count
FROM scans
WHERE COALESCE(is_deleted, false) = false;
"@ | Select-Object -First 1
                    if ($row) {
                        $totalScans=[int]$row.total_scans; $healthyEndpoints=[int]$row.healthy_endpoints; $criticalAlerts=[int]$row.critical_alerts; $uniqueEndpoints=[int]$row.unique_endpoints; $completedScans=[int]$row.completed_scans; $failedScans=[int]$row.failed_scans; $inProgressScans=[int]$row.in_progress_scans; $averageScanTime = if ($row.average_scan_time -ne $null) { [double]$row.average_scan_time } else { $null }; $lastScan=$row.last_scan; $excellentCount=[int]$row.excellent_count; $goodCount=[int]$row.good_count; $fairCount=[int]$row.fair_count; $poorCount=[int]$row.poor_count
                    }
                } catch { Write-JsonResponse $request $response 500 @{ success = $false; error = $_.Exception.Message }; break }
                try {
                    $complianceRows = Invoke-PGQuery -Query @"
SELECT
    compliance_bucket,
    COUNT(*)::int AS endpoint_count
FROM v_ems_latest_compliance_classified
GROUP BY compliance_bucket;
"@

                    foreach ($r in @($complianceRows)) {
                        if ($r.compliance_bucket -eq 'Compliant') {
                            $compliantEndpoints = [int]$r.endpoint_count
                        }
                        elseif ($r.compliance_bucket -eq 'Partial Compliant') {
                            $partialCompliantEndpoints = [int]$r.endpoint_count
                        }
                    }

                    $collectionFailedRow = Invoke-PGQuery -Query @"
SELECT COUNT(*)::int AS count
FROM v_ems_latest_compliance_classified
WHERE compliance_issues ILIKE '%Inventory collection failed%';
"@ | Select-Object -First 1
                    if ($collectionFailedRow) { $collectionFailedEndpoints = [int]$collectionFailedRow.count }

                    $biosPasswordUnknownRow = Invoke-PGQuery -Query @"
SELECT COUNT(*)::int AS count
FROM v_ems_latest_compliance_classified
WHERE COALESCE(manufacturer,'') NOT IN ('', 'Unknown')
  AND COALESCE(model,'') NOT IN ('', 'Unknown')
  AND COALESCE(compliance_issues,'') NOT ILIKE '%Inventory collection failed%'
  AND (
      COALESCE(poweron_password,'') <> 'Configured'
      OR COALESCE(admin_password,'') <> 'Configured'
  );
"@ | Select-Object -First 1
                    if ($biosPasswordUnknownRow) {
                        $biosPasswordUnknownEndpoints = [int]$biosPasswordUnknownRow.count
                        # Backward-compatible alias for existing frontend/API consumers.
                        $dellBiosUnknownEndpoints = $biosPasswordUnknownEndpoints
                    }

                    $metricWarningRow = Invoke-PGQuery -Query @"
SELECT COUNT(*)::int AS count
FROM v_ems_latest_compliance_classified
WHERE COALESCE(compliance_warnings,'') <> '';
"@ | Select-Object -First 1
                    if ($metricWarningRow) { $metricWarningEndpoints = [int]$metricWarningRow.count }
                }
                catch {
                    $compliantEndpoints = 0
                    $partialCompliantEndpoints = 0
                    $collectionFailedEndpoints = 0
                    $dellBiosUnknownEndpoints = 0
                    $biosPasswordUnknownEndpoints = 0
                    $metricWarningEndpoints = 0
                }
                Write-JsonResponse $request $response 200 @{ success=$true; totalComputers=$totalComputers; activeComputers=$activeComputers; totalScans=$totalScans; healthyEndpoints=$healthyEndpoints; criticalAlerts=$criticalAlerts; uniqueEndpoints=$uniqueEndpoints; completedScans=$completedScans; failedScans=$failedScans; inProgressScans=$inProgressScans; averageScanTime=$averageScanTime; lastScan=$lastScan; excellentCount=$excellentCount; goodCount=$goodCount; fairCount=$fairCount; poorCount=$poorCount; compliantEndpoints=$compliantEndpoints; partialCompliantEndpoints=$partialCompliantEndpoints; collectionFailedEndpoints=$collectionFailedEndpoints; dellBiosUnknownEndpoints=$dellBiosUnknownEndpoints; biosPasswordUnknownEndpoints=$biosPasswordUnknownEndpoints; metricWarningEndpoints=$metricWarningEndpoints; stats=@{ totalScans=$totalScans; healthyEndpoints=$healthyEndpoints; criticalAlerts=$criticalAlerts; uniqueEndpoints=$uniqueEndpoints; completedScans=$completedScans; failedScans=$failedScans; inProgressScans=$inProgressScans; averageScanTime=$averageScanTime; lastScan=$lastScan; excellentCount=$excellentCount; goodCount=$goodCount; fairCount=$fairCount; poorCount=$poorCount; totalComputers=$totalComputers; activeComputers=$activeComputers; compliantEndpoints=$compliantEndpoints; partialCompliantEndpoints=$partialCompliantEndpoints; collectionFailedEndpoints=$collectionFailedEndpoints; dellBiosUnknownEndpoints=$dellBiosUnknownEndpoints; biosPasswordUnknownEndpoints=$biosPasswordUnknownEndpoints; metricWarningEndpoints=$metricWarningEndpoints }; scanStatus=@{ completed=$completedScans; failed=$failedScans; inProgress=$inProgressScans }; performance=@{ averageScanTime=$averageScanTime; lastScan=$lastScan }; healthOverview=@{ excellent=$excellentCount; good=$goodCount; fair=$fairCount; poor=$poorCount } }
            }

            'GET /api/compliance/compliant' {
                if (-not (Require-ViewerAccess -Request $request -Response $response -Config $Global:EMSConfig)) { break }
                $rows = Invoke-PGQuery -Query @"
SELECT
    target AS hostname,
    computer_name,
    manufacturer,
    model,
    domain_user,
    screensaver_policy,
    restrict_software_installation_policy,
    all_security_kbs,
    all_security_kbs_installedon,
    os_edition,
    os_version,
    os_build,
    symantec_management_agent,
    readonly_usb,
    poweron_password,
    admin_password,
    timesync_with_ntp,
    lastchecked
FROM v_ems_latest_compliance_classified
WHERE compliance_bucket = 'Compliant'
ORDER BY target;
"@
                $rowsArray = @($rows)
                Write-JsonResponse $request $response 200 @{ success=$true; count=$rowsArray.Count; results=$rowsArray }
            }

            'GET /api/compliance/partial' {
                if (-not (Require-ViewerAccess -Request $request -Response $response -Config $Global:EMSConfig)) { break }
                $rows = Invoke-PGQuery -Query @"
SELECT
    target AS hostname,
    computer_name,
    manufacturer,
    model,
    domain_user,
    compliance_issues,
    compliance_warnings,
    screensaver_policy,
    restrict_software_installation_policy,
    readonly_usb,
    poweron_password,
    admin_password,
    timesync_with_ntp,
    lastchecked,
    comments
FROM v_ems_latest_compliance_classified
WHERE compliance_bucket = 'Partial Compliant'
ORDER BY target;
"@
                $rowsArray = @($rows)
                Write-JsonResponse $request $response 200 @{ success=$true; count=$rowsArray.Count; results=$rowsArray }
            }
            'GET /results' {
                if (-not (Require-ViewerAccess -Request $request -Response $response -Config $Global:EMSConfig)) { break }
                $includeDeleted = $false
                $includeDeletedRaw = $request.QueryString['includeDeleted']
                if ($includeDeletedRaw -and $includeDeletedRaw.ToString().ToLower() -eq 'true') {
                    if (Test-AdminAccess -Request $request -Config $Global:EMSConfig) { $includeDeleted = $true }
                }
                $whereClause = if ($includeDeleted) { '' } else { 'WHERE COALESCE(s.is_deleted, false) = false' }
                $rows = Invoke-PGQuery -Query @"
SELECT
    s.scan_id, s.target, s.status, s.result_json, s.health_score, s.critical_alerts, s.warning_alerts, s.info_alerts, s.execution_time_sec, s.started_at, s.completed_at,
    s.is_deleted, s.deleted_at, s.deleted_by, s.delete_reason,
    ir.computer_name, ir.manufacturer, ir.model, ir.domain_user, ir.screensaver_policy, ir.restrict_software_installation_policy, ir.lastpolicy_checked, ir.enabled_local_user_account,
    ir.all_security_kbs, ir.all_security_kbs_installedon, ir.os_edition, ir.os_version, ir.os_build, ir.symantec_management_agent, ir.readonly_usb, ir.poweron_password, ir.admin_password, ir.timesync_with_ntp, ir.lastchecked, ir.comments
FROM scans s
LEFT JOIN scan_inventory_results ir ON s.scan_id = ir.scan_id
$whereClause
ORDER BY s.started_at DESC
LIMIT 500;
"@
                $results = $rows | ForEach-Object {
                    $resultJson = $null; $hostname = $_.target; $ipAddress = $null; $userId = $null; $topology = $null; $actualFinding = ''
                    if ($_.result_json) {
                        try {
                            $resultJson = $_.result_json | ConvertFrom-Json
                            if ($resultJson.hostname) { $hostname = $resultJson.hostname }
                            if ($resultJson.ipAddress) { $ipAddress = $resultJson.ipAddress }
                            if ($resultJson.userId) { $userId = $resultJson.userId }
                            if ($resultJson.topology) { $topology = $resultJson.topology }
                            if ($resultJson.diagnostics) {
                                $importantFindings = $resultJson.diagnostics | Where-Object { $_.severity -in @('Critical','Warning') } | ForEach-Object {
                                    $name = if ($_.metricName) { $_.metricName } else { $_.checkName }
                                    $value = if ($null -ne $_.metricValue -and $_.unit) { "$($_.metricValue)$($_.unit)" } elseif ($null -ne $_.metricValue) { "$($_.metricValue)" } else { $null }
                                    if ($value) { ('{0}: {1} ({2})' -f $name, $value, $_.severity) } else { ('{0} ({1})' -f $name, $_.severity) }
                                }
                                $actualFinding = ($importantFindings -join '; ')
                            }
                        } catch { $resultJson = $null }
                    }
                    if (-not $actualFinding -and $_.comments) { $actualFinding = $_.comments }
                    $timestampValue = $null
                    if ($_.completed_at) {
                        $timestampValue = $_.completed_at
                    }
                    else {
                        $timestampValue = $_.started_at
                    }
                    [pscustomobject]@{ id=$_.scan_id; scanId=$_.scan_id; target=$_.target; hostname=$hostname; ipAddress=$ipAddress; userId=$userId; topology=$topology; status=$_.status; healthScore=$_.health_score; criticalAlerts=$_.critical_alerts; warningAlerts=$_.warning_alerts; infoAlerts=$_.info_alerts; executionTimeSeconds=$_.execution_time_sec; startedAt=$_.started_at; completedAt=$_.completed_at; timestamp=$timestampValue; actualFinding=$actualFinding; ComputerName=$_.computer_name; Manufacturer=$_.manufacturer; Model=$_.model; DomainUser=$_.domain_user; Screensaver_Policy=$_.screensaver_policy; RestrictSoftwareInstallation_Policy=$_.restrict_software_installation_policy; LastPolicy_Checked=$_.lastpolicy_checked; EnabledLocalUserAccount=$_.enabled_local_user_account; AllSecurityKBs=$_.all_security_kbs; AllSecurityKBsInstalledOn=$_.all_security_kbs_installedon; OS_Edition=$_.os_edition; OS_Version=$_.os_version; OS_Build=$_.os_build; SymantecManagementAgent=$_.symantec_management_agent; ReadOnlyUSB=$_.readonly_usb; Poweron_Password=$_.poweron_password; Admin_Password=$_.admin_password; TimeSyncWithNTP=$_.timesync_with_ntp; LastChecked=$_.lastchecked; Comments=$_.comments; IsDeleted=$_.is_deleted; DeletedAt=$_.deleted_at; DeletedBy=$_.deleted_by; DeleteReason=$_.delete_reason }
                }
                $resultsArray = @($results)
                Write-JsonResponse $request $response 200 @{ success = $true; count = $resultsArray.Count; results = $resultsArray }
            }

            'GET /computers' {
                if (-not (Require-ViewerAccess -Request $request -Response $response -Config $Global:EMSConfig)) { break }
                $rows = Invoke-PGQuery -Query @"
SELECT computer_name, ip_address::text AS ip_address, operating_system, domain, computer_type, last_seen, is_active
FROM computers ORDER BY computer_name;
"@
                Write-JsonResponse $request $response 200 @{ success = $true; computers = $rows }
            }

            'POST /computers' {
                if (-not (Require-AdminAccess -Request $request -Response $response -Config $Global:EMSConfig)) { break }
                $body = Read-JsonBody $request
                $computerName = if ($body.computerName) { $body.computerName } elseif ($body.name) { $body.name } else { $null }
                $ipAddress    = if ($body.ipAddress) { $body.ipAddress } elseif ($body.ip) { $body.ip } else { $null }
                $computerType = if ($body.computerType) { $body.computerType } elseif ($body.type) { $body.type } else { 'Desktop' }
                $osName       = if ($body.operatingSystem) { $body.operatingSystem } elseif ($body.os) { $body.os } else { $null }
                $domainName   = if ($body.domain) { $body.domain } else { $null }
                if (-not $computerName -or -not $ipAddress) { Write-JsonResponse $request $response 400 @{ success = $false; message = 'Computer name and IP address are required' }; break }
                if ($computerType -notin @('Desktop','Laptop','Server','Workstation')) { $computerType = 'Desktop' }
                Invoke-PGQuery -NonQuery -Query @"
INSERT INTO computers (computer_name, ip_address, computer_type, operating_system, domain, updated_at, last_seen)
VALUES (@computerName, CAST(@ipAddress AS inet), @computerType, @operatingSystem, @domain, NOW(), NOW())
ON CONFLICT (computer_name)
DO UPDATE SET ip_address=EXCLUDED.ip_address, computer_type=EXCLUDED.computer_type, operating_system=EXCLUDED.operating_system, domain=EXCLUDED.domain, updated_at=NOW(), last_seen=NOW();
"@ -Parameters @{ computerName=$computerName; ipAddress=$ipAddress; computerType=$computerType; operatingSystem=$osName; domain=$domainName }
                Write-JsonResponse $request $response 200 @{ success=$true; message='Computer registered successfully'; computer=@{ name=$computerName; ipAddress=$ipAddress; computerType=$computerType; operatingSystem=$osName; domain=$domainName } }
            }

            'POST /scan/single' {
                if (-not (Require-AdminAccess -Request $request -Response $response -Config $Global:EMSConfig)) { break }
                $body = Read-JsonBody $request
                if (-not $body.target) { Write-JsonResponse $request $response 400 @{ success = $false; message = 'Target is required' }; break }
                $scanId = [guid]::NewGuid()
                Invoke-PGQuery -NonQuery -Query @"
INSERT INTO scans (scan_id, target, status, started_at)
VALUES (@scanId, @target, 'queued', NOW());
"@ -Parameters @{ scanId = $scanId; target = $body.target }
                Start-EMSScan -ScanId $scanId -Target $body.target
                Write-JsonResponse $request $response 202 @{ success = $true; scanId = $scanId; status = 'queued' }
            }

            'POST /scan/bulk' {
                if (-not (Require-AdminAccess -Request $request -Response $response -Config $Global:EMSConfig)) { break }
                $body = Read-JsonBody $request
                $targets = @()
                if ($body.targets) {
                    if ($body.targets -is [System.Collections.IEnumerable] -and -not ($body.targets -is [string])) { $targets = @($body.targets) }
                    else { $targets = @([string]$body.targets) }
                } elseif ($body.target) { $targets = @([string]$body.target) }
                if (-not $targets -or $targets.Count -eq 0) { Write-JsonResponse $request $response 400 @{ success = $false; message = 'At least one target or CIDR range is required' }; break }
                try {
                    $batch = Start-EMSBatchScan -Targets $targets
                    Write-JsonResponse $request $response 202 @{ success=$true; message='Bulk scan queued successfully'; targetCount=$batch.targetCount; queuedScanCount=$batch.scanIds.Count; targets=$batch.targets; scanIds=$batch.scanIds; status='queued' }
                } catch { Write-JsonResponse $request $response 400 @{ success = $false; message = $_.Exception.Message } }
            }

            'GET /scan/status' {
                if (-not (Require-ViewerAccess -Request $request -Response $response -Config $Global:EMSConfig)) { break }
                $scanIdRaw = $request.QueryString['scanId']
                if (-not $scanIdRaw) { Write-JsonResponse $request $response 400 @{ success = $false; message = 'scanId is required' }; break }
                try { $scanId = [Guid]::Parse($scanIdRaw) } catch { Write-JsonResponse $request $response 400 @{ success = $false; message = 'Invalid scanId format' }; break }
                $row = Invoke-PGQuery -Query @"
SELECT scan_id, target, status, started_at, completed_at, error_message
FROM scans WHERE scan_id = @scanId LIMIT 1;
"@ -Parameters @{ scanId = $scanId } | Select-Object -First 1
                if (-not $row) { Write-JsonResponse $request $response 404 @{ success = $false; message = 'Scan not found' }; break }
                Write-JsonResponse $request $response 200 @{ success=$true; scanId=$row.scan_id; target=$row.target; status=$row.status; startedAt=$row.started_at; completedAt=$row.completed_at; errorMessage=$row.error_message }
            }

            'GET /scan/result' {
                if (-not (Require-ViewerAccess -Request $request -Response $response -Config $Global:EMSConfig)) { break }
                $scanIdRaw = $request.QueryString['scanId']
                if (-not $scanIdRaw) { Write-JsonResponse $request $response 400 @{ success = $false; message = 'scanId is required' }; break }
                try { $scanId = [Guid]::Parse($scanIdRaw) } catch { Write-JsonResponse $request $response 400 @{ success = $false; message = 'Invalid scanId format' }; break }
                $row = Invoke-PGQuery -Query @"
SELECT scan_id, target, status, health_score, critical_alerts, warning_alerts, info_alerts, execution_time_sec, result_json, error_message, started_at, completed_at
FROM scans WHERE scan_id = @scanId LIMIT 1;
"@ -Parameters @{ scanId = $scanId } | Select-Object -First 1
                if (-not $row) { Write-JsonResponse $request $response 404 @{ success = $false; message = 'Scan not found' }; break }
                if ($row.status -ne 'completed') { Write-JsonResponse $request $response 200 @{ success=$true; scanId=$row.scan_id; target=$row.target; status=$row.status; startedAt=$row.started_at; completedAt=$row.completed_at; errorMessage=$row.error_message }; break }
                $result = $null; if ($row.result_json) { try { $result = $row.result_json | ConvertFrom-Json } catch { $result = $null } }
                Write-JsonResponse $request $response 200 @{ success=$true; scanId=$row.scan_id; target=$row.target; status=$row.status; healthScore=$row.health_score; criticalAlerts=$row.critical_alerts; warningAlerts=$row.warning_alerts; infoAlerts=$row.info_alerts; executionTimeSeconds=$row.execution_time_sec; result=$result; startedAt=$row.started_at; completedAt=$row.completed_at }
            }

            default {
                if ($method -eq 'POST' -and $path -match '^/results/([0-9a-fA-F-]+)/archive$') {
                    if (-not (Require-AdminAccess -Request $request -Response $response -Config $Global:EMSConfig)) { break }
                    try { $scanId = [Guid]::Parse($Matches[1]) } catch { Write-JsonResponse $request $response 400 @{ success = $false; message = 'Invalid scan ID format' }; break }
                    $body = $null; $reason = $null
                    try { if ($request.HasEntityBody) { $body = Read-JsonBody $request; if ($body.reason) { $reason = [string]$body.reason } } } catch { $reason = $null }
                    $ctx = Get-RequestUserContext -Request $request
                    $performedBy = if ($ctx.Username) { $ctx.Username } else { 'UnknownAdmin' }
                    $existing = Invoke-PGQuery -Query @"
SELECT scan_id, target, status, is_deleted FROM scans WHERE scan_id = @scanId LIMIT 1;
"@ -Parameters @{ scanId = $scanId } | Select-Object -First 1
                    if (-not $existing) { Write-JsonResponse $request $response 404 @{ success = $false; message = 'Scan row not found' }; break }
                    if ($existing.is_deleted -eq $true) { Write-JsonResponse $request $response 200 @{ success = $true; message = 'Row already archived' }; break }
                    Invoke-PGQuery -NonQuery -Query @"
UPDATE scans SET is_deleted = true, deleted_at = NOW(), deleted_by = @deletedBy, delete_reason = @reason WHERE scan_id = @scanId;
"@ -Parameters @{ scanId=$scanId; deletedBy=$performedBy; reason=$reason }
                    Invoke-PGQuery -NonQuery -Query @"
INSERT INTO scan_actions_audit (scan_id, action_type, performed_by, reason, old_status, target)
VALUES (@scanId, 'archive', @performedBy, @reason, @oldStatus, @target);
"@ -Parameters @{ scanId=$scanId; performedBy=$performedBy; reason=$reason; oldStatus=$existing.status; target=$existing.target }
                    Write-JsonResponse $request $response 200 @{ success=$true; message='Scan row archived successfully'; scanId=$scanId }
                    break
                }

                if ($method -eq 'POST' -and $path -match '^/results/([0-9a-fA-F-]+)/restore$') {
                    if (-not (Require-AdminAccess -Request $request -Response $response -Config $Global:EMSConfig)) { break }
                    try { $scanId = [Guid]::Parse($Matches[1]) } catch { Write-JsonResponse $request $response 400 @{ success = $false; message = 'Invalid scan ID format' }; break }
                    $ctx = Get-RequestUserContext -Request $request
                    $performedBy = if ($ctx.Username) { $ctx.Username } else { 'UnknownAdmin' }
                    $existing = Invoke-PGQuery -Query @"
SELECT scan_id, target, status, is_deleted FROM scans WHERE scan_id = @scanId LIMIT 1;
"@ -Parameters @{ scanId = $scanId } | Select-Object -First 1
                    if (-not $existing) { Write-JsonResponse $request $response 404 @{ success = $false; message = 'Scan row not found' }; break }
                    Invoke-PGQuery -NonQuery -Query @"
UPDATE scans SET is_deleted = false, deleted_at = null, deleted_by = null, delete_reason = null WHERE scan_id = @scanId;
"@ -Parameters @{ scanId = $scanId }
                    Invoke-PGQuery -NonQuery -Query @"
INSERT INTO scan_actions_audit (scan_id, action_type, performed_by, reason, old_status, target)
VALUES (@scanId, 'restore', @performedBy, null, @oldStatus, @target);
"@ -Parameters @{ scanId=$scanId; performedBy=$performedBy; oldStatus=$existing.status; target=$existing.target }
                    Write-JsonResponse $request $response 200 @{ success=$true; message='Scan row restored successfully'; scanId=$scanId }
                    break
                }

                Write-JsonResponse $request $response 404 @{ error = 'Endpoint not found' }
            }
        }
    }
    catch {
        Write-JsonResponse $request $response 400 @{ error = $_.Exception.Message }
    }
}

#endregion















