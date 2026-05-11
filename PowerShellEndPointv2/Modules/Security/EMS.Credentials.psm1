<#
.SYNOPSIS
    EMS Credential Manager
.DESCRIPTION
    Manages encrypted service account credentials using DPAPI.
    Credentials are stored in PostgreSQL (service_credentials table) with
    machine-scoped DPAPI encryption, meaning they can only be decrypted
    on the same machine by the same user account that encrypted them.
#>

function Set-EMSServiceCredential {
    <#
    .SYNOPSIS
        Encrypts and stores a service account credential in the database.
    .PARAMETER CredentialType
        Type of credential (e.g., 'ScanService', 'ADService')
    .PARAMETER Username
        The service account username (e.g., 'DOMAIN\svc_ems_scan')
    .PARAMETER SecurePassword
        SecureString password
    .PARAMETER CreatedBy
        Username of the admin who set the credential
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CredentialType,

        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [SecureString]$SecurePassword,

        [string]$CreatedBy = $env:USERNAME
    )

    # Encrypt using DPAPI (machine-scoped)
    $encryptedPassword = $SecurePassword | ConvertFrom-SecureString

    Invoke-PGQuery -NonQuery -Query @"
        INSERT INTO service_credentials (credential_type, username, encrypted_password, encryption_method, created_by, updated_at)
        VALUES (@type, @user, @pass, 'DPAPI', @by, NOW())
        ON CONFLICT (credential_type) DO UPDATE SET
            username = EXCLUDED.username,
            encrypted_password = EXCLUDED.encrypted_password,
            updated_at = NOW()
"@ -Parameters @{
        type = $CredentialType
        user = $Username
        pass = $encryptedPassword
        by   = $CreatedBy
    }

    Write-EMSLog -Message "Service credential '$CredentialType' saved for user '$Username'" -Severity 'Success' -Category 'Security'
}

function Get-EMSServiceCredential {
    <#
    .SYNOPSIS
        Retrieves and decrypts a stored service account credential.
    .PARAMETER CredentialType
        Type of credential to retrieve
    .RETURNS
        PSCredential object or $null if not found
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CredentialType
    )

    $row = Invoke-PGQuery -Query "SELECT username, encrypted_password FROM service_credentials WHERE credential_type = @type LIMIT 1;" -Parameters @{ type = $CredentialType } | Select-Object -First 1

    if (-not $row -or -not $row.username) {
        return $null
    }

    try {
        $securePassword = $row.encrypted_password | ConvertTo-SecureString
        return [System.Management.Automation.PSCredential]::new($row.username, $securePassword)
    }
    catch {
        Write-EMSLog -Message "Failed to decrypt credential '$CredentialType': $($_.Exception.Message). Credential may have been created on a different machine." -Severity 'Error' -Category 'Security'
        return $null
    }
}

function Get-EMSServiceCredentialInfo {
    <#
    .SYNOPSIS
        Returns metadata about stored credentials (no passwords).
    #>
    [CmdletBinding()]
    param()

    return Invoke-PGQuery -Query "SELECT credential_type, username, encryption_method, created_by, created_at, updated_at FROM service_credentials ORDER BY credential_type;"
}

function Test-EMSServiceCredential {
    <#
    .SYNOPSIS
        Tests a stored credential by attempting AD validation or CIM connection.
    .PARAMETER CredentialType
        Type of credential to test
    .PARAMETER TestTarget
        Optional hostname to test CIM connectivity against
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CredentialType,

        [string]$TestTarget = $null
    )

    $cred = Get-EMSServiceCredential -CredentialType $CredentialType
    if (-not $cred) {
        return @{ Success = $false; Message = "Credential '$CredentialType' not found or decryption failed." }
    }

    # Test 1: Try to validate against AD if available
    try {
        $domain = $cred.UserName.Split('\')[0]
        if ($domain -and $domain -ne $cred.UserName) {
            Initialize-ADAccountManagement
            $ctx = [System.DirectoryServices.AccountManagement.PrincipalContext]::new(
                [System.DirectoryServices.AccountManagement.ContextType]::Domain,
                $domain
            )
            $user = $cred.UserName.Split('\')[1]
            $valid = $ctx.ValidateCredentials($user, $cred.GetNetworkCredential().Password)
            $ctx.Dispose()
            
            if ($valid) {
                return @{ Success = $true; Message = "AD authentication successful for '$($cred.UserName)'." }
            } else {
                return @{ Success = $false; Message = "AD authentication failed for '$($cred.UserName)'. Invalid credentials." }
            }
        }
    } catch {
        # AD not available, try CIM test
    }

    # Test 2: Try CIM session to a target
    if ($TestTarget) {
        try {
            $option = New-CimSessionOption -Protocol Dcom
            $session = New-CimSession -ComputerName $TestTarget -SessionOption $option -Credential $cred -OperationTimeoutSec 10 -ErrorAction Stop
            Remove-CimSession -CimSession $session
            return @{ Success = $true; Message = "CIM/DCOM connection to '$TestTarget' successful with credential '$($cred.UserName)'." }
        } catch {
            return @{ Success = $false; Message = "CIM/DCOM connection to '$TestTarget' failed: $($_.Exception.Message)" }
        }
    }

    return @{ Success = $true; Message = "Credential '$($cred.UserName)' exists and can be decrypted. No target specified for connectivity test." }
}

function Remove-EMSServiceCredential {
    <#
    .SYNOPSIS
        Removes a stored credential from the database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CredentialType
    )

    Invoke-PGQuery -NonQuery -Query "DELETE FROM service_credentials WHERE credential_type = @type;" -Parameters @{ type = $CredentialType }
    Write-EMSLog -Message "Service credential '$CredentialType' deleted" -Severity 'Warning' -Category 'Security'
}

Export-ModuleMember -Function Set-EMSServiceCredential, Get-EMSServiceCredential, Get-EMSServiceCredentialInfo, Test-EMSServiceCredential, Remove-EMSServiceCredential
