<#
.SYNOPSIS
    Authentication and authorization module for EMS

.DESCRIPTION
    Handles Active Directory credential validation, group membership verification,
    and audit logging for EMS.
#>

function Initialize-ADAccountManagement {
    [CmdletBinding()]
    param()

    if (-not ("System.DirectoryServices.AccountManagement.ContextType" -as [type])) {
        Add-Type -AssemblyName System.DirectoryServices.AccountManagement -ErrorAction Stop
    }

    if (-not ("System.DirectoryServices.AccountManagement.ContextType" -as [type])) {
        throw "System.DirectoryServices.AccountManagement could not be loaded."
    }
}

function Test-ADCredential {
    <#
    .SYNOPSIS
        Validates credentials against Active Directory

    .PARAMETER Username
        Username in domain\user or user@domain format

    .PARAMETER SecurePassword
        SecureString containing the password

    .PARAMETER Domain
        Optional domain / forest DNS name or NetBIOS domain name

    .RETURNS
        Boolean indicating successful authentication
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [SecureString]$SecurePassword,

        [string]$Domain
    )

    try {
        Initialize-ADAccountManagement

        # Normalize username and domain
        $user = $Username
        if ($Username -match '(.+)\\(.+)') {
            if (-not $Domain) { $Domain = $Matches[1] }
            $user = $Matches[2]
        }
        elseif ($Username -match '(.+)@(.+)') {
            if (-not $Domain) { $Domain = $Matches[2] }
            $user = $Username
        }
        else {
            if (-not $Domain) {
                $Domain = $env:USERDNSDOMAIN
                if (-not $Domain) { $Domain = $env:USERDOMAIN }
            }
        }

        if (-not $Domain) {
            throw "Domain could not be determined. Use DOMAIN\username or username@domain."
        }

        $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
        try {
            $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($BSTR)
        }
        finally {
            if ($BSTR -ne [IntPtr]::Zero) {
                [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
            }
        }

        $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
            [System.DirectoryServices.AccountManagement.ContextType]::Domain,
            $Domain
        )

        try {
            $isValid = $context.ValidateCredentials($user, $plainPassword)
        }
        finally {
            $context.Dispose()
        }

        return [bool]$isValid
    }
    catch {
        Write-Error "Authentication error: $($_.Exception.Message)"
        return $false
    }
}

function Test-UserAuthorization {
    <#
    .SYNOPSIS
        Checks if user is member of required security group

    .PARAMETER Username
        Username to check

    .PARAMETER RequiredGroup
        AD security group name

    .RETURNS
        Boolean indicating group membership
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [string]$RequiredGroup
    )

    try {
        Initialize-ADAccountManagement

        $domain = $null
        $user = $Username

        if ($Username -match '(.+)\\(.+)') {
            $domain = $Matches[1]
            $user = $Matches[2]
        }
        elseif ($Username -match '(.+)@(.+)') {
            $user = $Matches[1]
            $domain = $Matches[2]
        }
        else {
            $domain = $env:USERDNSDOMAIN
            if (-not $domain) { $domain = $env:USERDOMAIN }
        }

        if (-not $domain) {
            throw "Domain could not be determined for authorization check."
        }

        $context = New-Object System.DirectoryServices.AccountManagement.PrincipalContext(
            [System.DirectoryServices.AccountManagement.ContextType]::Domain,
            $domain
        )

        try {
            $userPrincipal = [System.DirectoryServices.AccountManagement.UserPrincipal]::FindByIdentity($context, $user)
            if (-not $userPrincipal) {
                Write-Warning "User not found: $Username"
                return $false
            }

            $groups = $userPrincipal.GetAuthorizationGroups()
            foreach ($group in $groups) {
                if ($group.Name -eq $RequiredGroup) {
                    return $true
                }
            }

            return $false
        }
        finally {
            if ($userPrincipal) { $userPrincipal.Dispose() }
            $context.Dispose()
        }
    }
    catch {
        Write-Error "Authorization check error: $($_.Exception.Message)"
        return $false
    }
}

function Write-AuditLog {
    <#
    .SYNOPSIS
        Records authentication and authorization events
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Action,

        [Parameter(Mandatory)]
        [string]$User,

        [Parameter(Mandatory)]
        [string]$Result,

        [string]$Details = '',
        [string]$RiskLevel = '',
        [string]$Target = ''
    )

    try {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $computerName = $env:COMPUTERNAME

        $logEntry = [PSCustomObject]@{
            Timestamp = $timestamp
            Computer  = $computerName
            User      = $User
            Action    = $Action
            Result    = $Result
            Target    = $Target
            RiskLevel = $RiskLevel
            Details   = $Details
        }

        if ($Global:EMSConfig -and $Global:EMSConfig.Security -and $Global:EMSConfig.Security.AuditLogPath) {
            $logPath = Join-Path $Global:EMSConfig.Security.AuditLogPath "AuthAudit_$(Get-Date -Format 'yyyyMM').csv"

            $logDir = Split-Path $logPath -Parent
            if (-not (Test-Path $logDir)) {
                New-Item -Path $logDir -ItemType Directory -Force | Out-Null
            }

            $logEntry | Export-Csv -Path $logPath -Append -NoTypeInformation
        }

        $logName = 'Application'
        $source  = 'EMS'

        if (-not [System.Diagnostics.EventLog]::SourceExists($source)) {
            try {
                [System.Diagnostics.EventLog]::CreateEventSource($source, $logName)
            }
            catch {
                # Ignore if no permission
            }
        }

        if ([System.Diagnostics.EventLog]::SourceExists($source)) {
            $eventType = switch ($Result) {
                'Success'      { 'Information' }
                'Failed'       { 'FailureAudit' }
                'Unauthorized' { 'Warning' }
                default        { 'Information' }
            }

            $message = "EMS $Action - User: $User, Result: $Result"
            if ($Target)    { $message += ", Target: $Target" }
            if ($RiskLevel) { $message += ", RiskLevel: $RiskLevel" }
            if ($Details)   { $message += ", Details: $Details" }

            Write-EventLog -LogName $logName -Source $source -EventId 1000 -EntryType $eventType -Message $message
        }
    }
    catch {
        Write-Warning "Failed to write audit log: $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function Test-ADCredential, Test-UserAuthorization, Write-AuditLog