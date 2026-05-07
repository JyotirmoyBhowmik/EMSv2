<#
.SYNOPSIS
    Multi-Provider Authentication Module for EMS

.DESCRIPTION
    Supports multiple authentication providers:
    - Standalone: Local database users
   
    - LDAP: Generic LDAP servers
    - ADFS: Active Directory Federation Services
    - SSO: SAML/OAuth2 providers
#>

$ModulePath = $PSScriptRoot

# Local auth providers
Import-Module "$ModulePath\StandaloneAuth.psm1" -Force
Import-Module "$ModulePath\LDAPAuth.psm1" -Force

# Load parent auth module if Test-ADCredential is not already available
if (-not (Get-Command Test-ADCredential -ErrorAction SilentlyContinue)) {
    $parentAuthModule = Join-Path $PSScriptRoot "..\Authentication.psm1"
    if (Test-Path $parentAuthModule) {
        Import-Module $parentAuthModule -Force
    }
}

function Invoke-MultiProviderAuth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [SecureString]$SecurePassword,

        [string]$Provider,

        [Parameter(Mandatory)]
        [object]$Config
    )

    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    try {
        $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    $enabledProviders = $Config.Authentication.Providers |
        Where-Object { $_.Enabled -eq $true } |
        Sort-Object Priority

    if ($Provider) {
        $enabledProviders = $enabledProviders | Where-Object { $_.Name -eq $Provider }
        if (-not $enabledProviders) {
            return @{
                Success  = $false
                Message  = "Provider '$Provider' not found or not enabled"
                Provider = $null
                User     = $null
            }
        }
    }

    foreach ($providerConfig in $enabledProviders) {
        try {
            $result = $null

            switch ($providerConfig.Name) {
                "Standalone" {
                    $result = Test-StandaloneAuth -Username $Username -Password $plainPassword -Config $Config
                }
                "ActiveDirectory" {
                    $result = Test-ADAuth -Username $Username -SecurePassword $SecurePassword -Domain $providerConfig.Domain
                }
                "LDAP" {
                    $result = Test-LDAPAuth -Username $Username -Password $plainPassword -Config $providerConfig
                }
                "ADFS" {
                    $result = Test-ADFSAuth -Username $Username -Password $plainPassword -Config $providerConfig
                }
                "SSO" {
                    continue
                }
            }

            if ($result -and $result.Success) {
                return @{
                    Success     = $true
                    Provider    = $providerConfig.Name
                    User        = $result.User
                    ExternalID  = $result.ExternalID
                    DisplayName = $result.DisplayName
                    Email       = $result.Email
                    Groups      = $result.Groups
                }
            }
        }
        catch {
            if (Get-Command Write-EMSLog -ErrorAction SilentlyContinue) {
                Write-EMSLog -Message "Auth provider $($providerConfig.Name) error: $($_.Exception.Message)" -Severity 'Warning'
            }

            if (-not $Config.Authentication.FallbackChain) {
                return @{
                    Success  = $false
                    Message  = "Authentication failed: $($_.Exception.Message)"
                    Provider = $providerConfig.Name
                }
            }
        }
    }

    return @{
        Success  = $false
        Message  = "Authentication failed for all configured providers"
        Provider = $null
        User     = $null
    }
}

function Get-OrCreateAuthUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$AuthResult,

        [Parameter(Mandatory)]
        [object]$Config
    )

    $dbUser = Get-EMSUser -Username $AuthResult.User

    if ($dbUser) {
        Update-EMSUserLogin -UserId $dbUser.user_id
        return $dbUser
    }

    $domain = switch ($AuthResult.Provider) {
        'Standalone'      { 'LOCAL' }
        'ActiveDirectory' { 'AD' }
        'LDAP'            { 'LDAP' }
        'ADFS'            { 'ADFS' }
        default           { 'EXT' }
    }

    $display = if ($AuthResult.DisplayName) { $AuthResult.DisplayName } else { $AuthResult.User }

    $newUser = New-EMSUser -Username $AuthResult.User -Domain $domain -DisplayName $display -Role 'operator'
    Update-EMSUserLogin -UserId $newUser.user_id
    return $newUser
}

function Test-ADAuth {
    [CmdletBinding()]
    param(
        [string]$Username,
        [SecureString]$SecurePassword,
        [string]$Domain
    )

    try {
        # Pass Domain through to low-level AD credential validation
        $isValid = Test-ADCredential -Username $Username -SecurePassword $SecurePassword -Domain $Domain

        if (-not $isValid) {
            return @{
                Success = $false
                Message = "Invalid AD credentials"
            }
        }

        $displayName = $Username
        $email = $null
        $groups = @()

        if (Get-Command Get-ADUser -ErrorAction SilentlyContinue) {
            try {
                $sam = $Username
                if ($sam -match '\\') {
                    $sam = $sam.Split('\')[-1]
                }
                elseif ($sam -match '@') {
                    $sam = $sam.Split('@')[0]
                }

                $adUser = Get-ADUser -Identity $sam -Properties DisplayName, EmailAddress, MemberOf -ErrorAction Stop
                if ($adUser) {
                    if ($adUser.DisplayName)  { $displayName = $adUser.DisplayName }
                    if ($adUser.EmailAddress) { $email = $adUser.EmailAddress }
                    if ($adUser.MemberOf)     { $groups = $adUser.MemberOf }
                }
            }
            catch {
                if (Get-Command Write-EMSLog -ErrorAction SilentlyContinue) {
                    Write-EMSLog -Message "Get-ADUser fallback failed for $Username : $($_.Exception.Message)" -Severity 'Warning'
                }
            }
        }

        return @{
            Success     = $true
            User        = $Username
            ExternalID  = $null
            DisplayName = $displayName
            Email       = $email
            Groups      = $groups
        }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

function Test-ADFSAuth {
    [CmdletBinding()]
    param(
        [string]$Username,
        [string]$Password,
        [object]$Config
    )

    try {
        $adfsUrl = "$($Config.ServerURL)/adfs/services/trust/13/usernamemixed"

        $soapRequest = @"
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"
            xmlns:a="http://www.w3.org/2005/08/addressing"
            xmlns:u="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-utility-1.0.xsd">
  <s:Header>
    <a:Action s:mustUnderstand="1">http://docs.oasis-open.org/ws-sx/ws-trust/200512/RST/Issue</a:Action>
    <a:To s:mustUnderstand="1">$adfsUrl</a:To>
    <o:Security s:mustUnderstand="1" xmlns:o="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd">
      <o:UsernameToken u:Id="uuid-$([guid]::NewGuid().ToString())">
        <o:Username>$Username</o:Username>
        <o:Password Type="http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-username-token-profile-1.0#PasswordText">$Password</o:Password>
      </o:UsernameToken>
    </o:Security>
  </s:Header>
  <s:Body>
    <trust:RequestSecurityToken xmlns:trust="http://docs.oasis-open.org/ws-sx/ws-trust/200512">
      <wsp:AppliesTo xmlns:wsp="http://schemas.xmlsoap.org/ws/2004/09/policy">
        <a:EndpointReference>
          <a:Address>$($Config.RelyingPartyIdentifier)</a:Address>
        </a:EndpointReference>
      </wsp:AppliesTo>
      <trust:RequestType>http://docs.oasis-open.org/ws-sx/ws-trust/200512/Issue</trust:RequestType>
    </trust:RequestSecurityToken>
  </s:Body>
</s:Envelope>
"@

        $response = Invoke-RestMethod -Uri $adfsUrl -Method POST -Body $soapRequest -ContentType "application/soap+xml"

        if ($response) {
            return @{
                Success     = $true
                User        = $Username
                ExternalID  = $null
                DisplayName = $Username
                Email       = $null
                Groups      = @()
            }
        }

        return @{ Success = $false }
    }
    catch {
        return @{
            Success = $false
            Error   = $_.Exception.Message
        }
    }
}

Export-ModuleMember -Function @(
    'Invoke-MultiProviderAuth',
    'Get-OrCreateAuthUser',
    'Test-ADAuth',
    'Test-ADFSAuth'
)