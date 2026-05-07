<#
.SYNOPSIS
    User Experience diagnostics module

.DESCRIPTION
    Implements 10 user-centric diagnostic checks
#>

function Test-AccountLockout {
    param([string]$UserID, [string]$ComputerName)
    
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        
        if (-not $UserID) {
            # Try to get current logged-on user
            $scriptBlock = {
                $user = (Get-WmiObject -Class Win32_ComputerSystem).UserName
                if ($user) {
                    return $user.Split('\')[1]
                }
                return $null
            }
            
            if ($ComputerName) {
                $UserID = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
            }
            else {
                $UserID = & $scriptBlock
            }
        }
        
        if ($UserID) {
            $user = Get-ADUser $UserID -Properties LockedOut -ErrorAction Stop
            
            $status = if ($user.LockedOut) { 'Critical' } else { 'OK' }
            
            return [PSCustomObject]@{
                Metric     = 'Account Lockout'
                Value      = "User: $UserID, Locked: $($user.LockedOut)"
                Assessment = $status
            }
        }
        
        return [PSCustomObject]@{
            Metric     = 'Account Lockout'
            Value      = 'No user logged on'
            Assessment = 'Info'
        }
    }
    catch {
        return [PSCustomObject]@{
            Metric     = 'Account Lockout'
            Value      = "Error: $_"
            Assessment = 'Error'
        }
    }
}

function Get-PasswordAge {
    param([string]$UserID)
    
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        
        if ($UserID) {
            $user = Get-ADUser $UserID -Properties PasswordLastSet -ErrorAction Stop
            
            if ($user.PasswordLastSet) {
                $daysSinceChange = ((Get-Date) - $user.PasswordLastSet).Days
                
                $status = if ($daysSinceChange -gt 90) { 'Warning' } else { 'OK' }
                
                return [PSCustomObject]@{
                    Metric     = 'Password Age'
                    Value      = "$daysSinceChange days since last change"
                    Assessment = $status
                }
            }
        }
        
        return [PSCustomObject]@{
            Metric     = 'Password Age'
            Value      = 'Unable to determine'
            Assessment = 'Info'
        }
    }
    catch {
        return [PSCustomObject]@{
            Metric     = 'Password Age'
            Value      = "Error: $_"
            Assessment = 'Error'
        }
    }
}

function Get-LastLogonTime {
    param([string]$UserID)
    
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        
        if ($UserID) {
            $user = Get-ADUser $UserID -Properties LastLogonDate -ErrorAction Stop
            
            if ($user.LastLogonDate) {
                return [PSCustomObject]@{
                    Metric     = 'Last Logon'
                    Value      = $user.LastLogonDate.ToString('yyyy-MM-dd HH:mm:ss')
                    Assessment = 'Info'
                }
            }
        }
        
        return [PSCustomObject]@{
            Metric     = 'Last Logon'
            Value      = 'Unknown'
            Assessment = 'Info'
        }
    }
    catch {
        return [PSCustomObject]@{
            Metric     = 'Last Logon'
            Value      = "Error: $_"
            Assessment = 'Error'
        }
    }
}

function Measure-ProfileSize {
    param([string]$ComputerName)
    
    try {
        $scriptBlock = {
            $user = (Get-WmiObject -Class Win32_ComputerSystem).UserName
            
            if ($user) {
                $username = $user.Split('\')[1]
                $profilePath = "C:\Users\$username"
                
                if (Test-Path $profilePath) {
                    $size = (Get-ChildItem $profilePath -Recurse -ErrorAction SilentlyContinue | 
                        Measure-Object -Property Length -Sum).Sum / 1GB
                    
                    return @{
                        Path   = $profilePath
                        SizeGB = $size
                    }
                }
            }
            
            return @{ Path = 'Unknown'; SizeGB = 0 }
        }
        
        if ($ComputerName) {
            $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            $result = & $scriptBlock
        }
        
        $status = if ($result.SizeGB -gt 5) { 'Warning' } else { 'OK' }
        
        return [PSCustomObject]@{
            Metric     = 'Profile Size'
            Value      = "$([Math]::Round($result.SizeGB, 2)) GB"
            Assessment = $status
        }
    }
    catch {
        return [PSCustomObject]@{
            Metric     = 'Profile Size'
            Value      = "Error: $_"
            Assessment = 'Error'
        }
    }
}

function Measure-TempFolderSize {
    param([string]$ComputerName)
    
    try {
        $scriptBlock = {
            $tempPaths = @($env:TEMP, 'C:\Windows\Temp')
            $totalSize = 0
            
            foreach ($path in $tempPaths) {
                if (Test-Path $path) {
                    $size = (Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | 
                        Measure-Object -Property Length -Sum).Sum
                    $totalSize += $size
                }
            }
            
            return $totalSize / 1GB
        }
        
        if ($ComputerName) {
            $sizeGB = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            $sizeGB = & $scriptBlock
        }
        
        $status = if ($sizeGB -gt 1) { 'Warning' } else { 'OK' }
        
        return [PSCustomObject]@{
            Metric     = 'Temp Folder Size'
            Value      = "$([Math]::Round($sizeGB, 2)) GB"
            Assessment = $status
        }
    }
    catch {
        return [PSCustomObject]@{
            Metric     = 'Temp Folder Size'
            Value      = "Error: $_"
            Assessment = 'Error'
        }
    }
}

function Get-MappedDrives {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $drives = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_MappedLogicalDisk
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_MappedLogicalDisk
        }
        
        if ($drives) {
            $driveList = ($drives | ForEach-Object { "$($_.Name) -> $($_.ProviderName)" }) -join '; '
            
            return [PSCustomObject]@{
                Metric     = 'Mapped Drives'
                Value      = $driveList
                Assessment = 'Info'
            }
        }
        else {
            return [PSCustomObject]@{
                Metric     = 'Mapped Drives'
                Value      = 'No mapped drives'
                Assessment = 'Info'
            }
        }
    }
    catch {
        return [PSCustomObject]@{
            Metric     = 'Mapped Drives'
            Value      = "Error: $_"
            Assessment = 'Error'
        }
    }
}

function Get-PrinterConfiguration {
    param([string]$ComputerName, [CimSession]$CimSession)
    
    try {
        $printers = if ($CimSession) {
            Get-CimInstance -CimSession $CimSession -ClassName Win32_Printer
        }
        else {
            Get-CimInstance -ComputerName $ComputerName -ClassName Win32_Printer
        }
        
        $default = $printers | Where-Object Default -eq $true | Select-Object -First 1
        $count = ($printers | Measure-Object).Count
        
        $value = "$count printer(s) installed"
        if ($default) {
            $value += ", Default: $($default.Name)"
        }
        
        return [PSCustomObject]@{
            Metric     = 'Printers'
            Value      = $value
            Assessment = 'Info'
        }
    }
    catch {
        return [PSCustomObject]@{
            Metric     = 'Printers'
            Value      = "Error: $_"
            Assessment = 'Error'
        }
    }
}

function Get-GroupMembership {
    param([string]$UserID)
    
    try {
        Import-Module ActiveDirectory -ErrorAction Stop
        
        if ($UserID) {
            $user = Get-ADUser $UserID -Properties MemberOf -ErrorAction Stop
            
            $groupCount = ($user.MemberOf | Measure-Object).Count
            $groups = ($user.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace 'CN=' }) -join ', '
            
            return [PSCustomObject]@{
                Metric     = 'Group Membership'
                Value      = "$groupCount groups: $groups"
                Assessment = 'Info'
            }
        }
        
        return [PSCustomObject]@{
            Metric     = 'Group Membership'
            Value      = 'Unable to determine'
            Assessment = 'Info'
        }
    }
    catch {
        return [PSCustomObject]@{
            Metric     = 'Group Membership'
            Value      = "Error: $_"
            Assessment = 'Error'
        }
    }
}

function Test-FolderRedirection {
    param([string]$ComputerName)
    
    try {
        $scriptBlock = {
            $desktopPath = [Environment]::GetFolderPath('Desktop')
            $documentsPath = [Environment]::GetFolderPath('MyDocuments')
            
            $desktopRedirected = $desktopPath -notlike "C:\Users\*"
            $documentsRedirected = $documentsPath -notlike "C:\Users\*"
            
            return @{
                Desktop   = @{
                    Path       = $desktopPath
                    Redirected = $desktopRedirected
                }
                Documents = @{
                    Path       = $documentsPath
                    Redirected = $documentsRedirected
                }
            }
        }
        
        if ($ComputerName) {
            $result = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            $result = & $scriptBlock
        }
        
        $value = "Desktop: $(if ($result.Desktop.Redirected) { 'Redirected' } else { 'Local' }), Documents: $(if ($result.Documents.Redirected) { 'Redirected' } else { 'Local' })"
        
        return [PSCustomObject]@{
            Metric     = 'Folder Redirection'
            Value      = $value
            Assessment = 'Info'
        }
    }
    catch {
        return [PSCustomObject]@{
            Metric     = 'Folder Redirection'
            Value      = "Error: $_"
            Assessment = 'Error'
        }
    }
}

function Get-UserIdleTime {
    param([string]$ComputerName)
    
    try {
        $scriptBlock = {
            Add-Type @'
using System;
using System.Runtime.InteropServices;

public class IdleTimeInfo {
    [DllImport("user32.dll")]
    static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);

    [StructLayout(LayoutKind.Sequential)]
    struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }

    public static uint GetIdleTime() {
        LASTINPUTINFO lastInputInfo = new LASTINPUTINFO();
        lastInputInfo.cbSize = (uint)Marshal.SizeOf(lastInputInfo);
        GetLastInputInfo(ref lastInputInfo);
        return ((uint)Environment.TickCount - lastInputInfo.dwTime);
    }
}
'@
            
            $idleMs = [IdleTimeInfo]::GetIdleTime()
            return $idleMs / 1000 / 60  # Convert to minutes
        }
        
        if ($ComputerName) {
            $idleMinutes = Invoke-Command -ComputerName $ComputerName -ScriptBlock $scriptBlock
        }
        else {
            $idleMinutes = & $scriptBlock
        }
        
        $status = if ($idleMinutes -gt 30) { 'Info' } else { 'Active' }
        
        return [PSCustomObject]@{
            Metric     = 'User Idle Time'
            Value      = "$([Math]::Round($idleMinutes, 1)) minutes"
            Assessment = $status
        }
    }
    catch {
        return [PSCustomObject]@{
            Metric     = 'User Idle Time'
            Value      = "Error: $_"
            Assessment = 'Error'
        }
    }
}

function Invoke-UserExperienceChecks {
    <#
    .SYNOPSIS
        Runs all user experience diagnostic checks
    #>
    param(
        [string]$ComputerName,
        [CimSession]$CimSession,
        [string]$UserID
    )
    
    $results = @()
    
    $results += Test-AccountLockout -UserID $UserID -ComputerName $ComputerName
    $results += Get-PasswordAge -UserID $UserID
    $results += Get-LastLogonTime -UserID $UserID
    $results += Measure-ProfileSize -ComputerName $ComputerName
    $results += Measure-TempFolderSize -ComputerName $ComputerName
    $results += Get-MappedDrives -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-PrinterConfiguration -ComputerName $ComputerName -CimSession $CimSession
    $results += Get-GroupMembership -UserID $UserID
    $results += Test-FolderRedirection -ComputerName $ComputerName
    $results += Get-UserIdleTime -ComputerName $ComputerName
    
    return $results
}

Export-ModuleMember -Function Invoke-UserExperienceChecks, Test-*, Get-*, Measure-*
