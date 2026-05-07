<#
.SYNOPSIS
    LDAP Authentication Provider
    
.DESCRIPTION
    Authenticates users against LDAP servers
    Supports generic LDAP (OpenLDAP, etc.)
#>

<#
.SYNOPSIS
    Tests LDAP authentication
#>
function Test-LDAPAuth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [Parameter(Mandatory)]
        [string]$Password,
        
        [Parameter(Mandatory)]
        [object]$Config
    )
    
    try {
        $ldapServer = $Config.Server
        $baseDN = $Config.BaseDN
        $bindDN = $Config.BindDN
        $bindPassword = $Config.BindPassword
        
        # Construct user DN
        $userDN = "uid=$Username,$baseDN"
        
        # Try to bind with user credentials
        $ldap = New-Object System.DirectoryServices.DirectoryEntry(
            "LDAP://$ldapServer/$userDN",
            $userDN,
            $Password
        )
        
        # Attempt to read a property to validate bind
        $name = $ldap.name
        
        if ($name) {
            # Successful bind - get user attributes
            $displayName = $ldap.displayName
            $mail = $ldap.mail
            $memberOf = $ldap.memberOf
            
            return @{
                Success     = $true
                User        = $Username
                ExternalID  = $userDN
                DisplayName = if ($displayName) { $displayName.ToString() } else { $Username }
                Email       = if ($mail) { $mail.ToString() } else { $null }
                Groups      = if ($memberOf) { @($memberOf) } else { @() }
            }
        }
        
        return @{ Success = $false }
    }
    catch [System.DirectoryServices.DirectoryServicesCOMException] {
        # Invalid credentials or connection error
        return @{ Success = $false; Message = "LDAP authentication failed" }
    }
    catch {
        return @{ Success = $false; Error = $_.Exception.Message }
    }
    finally {
        if ($ldap) {
            $ldap.Dispose()
        }
    }
}

<#
.SYNOPSIS
    Searches LDAP for user information
#>
function Search-LDAPUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,
        
        [Parameter(Mandatory)]
        [object]$Config
    )
    
    try {
        $ldapServer = $Config.Server
        $baseDN = $Config.BaseDN
        $bindDN = $Config.BindDN
        $bindPassword = $Config.BindPassword
        
        # Connect with service account
        $ldap = New-Object System.DirectoryServices.DirectoryEntry(
            "LDAP://$ldapServer/$baseDN",
            $bindDN,
            $bindPassword
        )
        
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($ldap)
        $searcher.Filter = "(uid=$Username)"
        $searcher.PropertiesToLoad.AddRange(@("cn", "mail", "displayName", "memberOf"))
        
        $result = $searcher.FindOne()
        
        if ($result) {
            return @{
                Found       = $true
                DN          = $result.Properties["distinguishedName"][0]
                DisplayName = $result.Properties["displayName"][0]
                Email       = $result.Properties["mail"][0]
                Groups      = @($result.Properties["memberOf"])
            }
        }
        
        return @{ Found = $false }
    }
    catch {
        return @{ Found = $false; Error = $_.Exception.Message }
    }
    finally {
        if ($searcher) { $searcher.Dispose() }
        if ($ldap) { $ldap.Dispose() }
    }
}

Export-ModuleMember -Function @(
    'Test-LDAPAuth',
    'Search-LDAPUser'
)
