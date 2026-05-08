#requires -Version 5.1

<#
StandaloneAuth.psm1
Final hybrid version:
- Works standalone from PowerShell
- Works inside EMS API via AuthProviders.psm1
- Uses PSPGSql if already loaded; otherwise loads and initializes it
#>
# ---------------------------------------------------------
# Ensure DB module is available
# ---------------------------------------------------------
if (-not (Get-Command Invoke-PGQuery -ErrorAction SilentlyContinue)) {
    $dbModule = Join-Path $PSScriptRoot "..\Database\PSPGSql.psm1"
    if (-not (Test-Path $dbModule)) {
        throw "PSPGSql.psm1 not found at path: $dbModule"
    }
    Import-Module $dbModule -Force
}

# ---------------------------------------------------------
# Ensure DB connection is initialized
# ---------------------------------------------------------
if (-not (Get-Command Initialize-PostgreSQLConnection -ErrorAction SilentlyContinue)) {
    throw "Initialize-PostgreSQLConnection is not available. PSPGSql.psm1 did not import correctly."
}
# Note: Connection initialization is now handled centrally by Start-EMSAPI.ps1 or caller.

function Ensure-LocalCredentialTable {
    [CmdletBinding()]
    param()

    Invoke-PGQuery -NonQuery -Query @"
CREATE TABLE IF NOT EXISTS user_credentials (
    user_id          integer PRIMARY KEY REFERENCES users(user_id) ON DELETE CASCADE,
    password_hash    text NOT NULL,
    password_salt    text NOT NULL,
    is_active        boolean NOT NULL DEFAULT true,
    created_at       timestamp NOT NULL DEFAULT now(),
    updated_at       timestamp NULL
)
"@ | Out-Null
}

# ---------------------------------------------------------
# Password hashing helpers
# ---------------------------------------------------------
function New-PasswordHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Password,

        [string]$Salt
    )

    if (-not $Salt) {
        $bytes = New-Object byte[] 16
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $Salt = [Convert]::ToBase64String($bytes)
    }

    $derive = New-Object System.Security.Cryptography.Rfc2898DeriveBytes(
        $Password,
        [Convert]::FromBase64String($Salt),
        100000
    )

    $hash = [Convert]::ToBase64String($derive.GetBytes(32))

    return @{
        Salt = $Salt
        Hash = $hash
    }
}

function Test-PasswordHash {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Password,

        [Parameter(Mandatory)]
        [string]$Salt,

        [Parameter(Mandatory)]
        [string]$StoredHash
    )

    $result = New-PasswordHash -Password $Password -Salt $Salt
    return ($result.Hash -eq $StoredHash)
}

# ---------------------------------------------------------
# Local credential lookup
# ---------------------------------------------------------
function Get-EMSLocalCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username
    )

    Ensure-LocalCredentialTable

    $query = @"
SELECT u.user_id,
       u.username,
       u.domain,
       u.display_name,
       u.role,
       u.is_active,
       c.password_hash,
       c.password_salt,
       c.is_active AS credential_active
FROM users u
JOIN user_credentials c ON u.user_id = c.user_id
WHERE u.username = @username
  AND u.domain = 'LOCAL'
LIMIT 1
"@

    return (Invoke-PGQuery -Query $query -Parameters @{ username = $Username } | Select-Object -First 1)
}

# ---------------------------------------------------------
# Standalone login
# ---------------------------------------------------------
function Test-StandaloneAuth {
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
        $user = Get-EMSLocalCredential -Username $Username

        if (-not $user) {
            return @{
                Success = $false
                Message = "User not found"
            }
        }

        if (-not $user.is_active -or -not $user.credential_active) {
            return @{
                Success = $false
                Message = "User is inactive"
            }
        }

        $isValid = Test-PasswordHash -Password $Password -Salt $user.password_salt -StoredHash $user.password_hash
        if (-not $isValid) {
            return @{
                Success = $false
                Message = "Invalid credentials"
            }
        }

        return @{
            Success     = $true
            User        = $user.username
            ExternalID  = $null
            DisplayName = $user.display_name
            Email       = $null
            Groups      = @()
        }
    }
    catch {
        if (Get-Command Write-EMSLog -ErrorAction SilentlyContinue) {
            Write-EMSLog -Message "Standalone authentication error: $($_.Exception.Message)" -Severity 'Error'
        }

        return @{
            Success = $false
            Message = $_.Exception.Message
        }
    }
}

# ---------------------------------------------------------
# Create standalone local EMS user
# ---------------------------------------------------------
function New-StandaloneUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [SecureString]$SecurePassword,

        [string]$DisplayName,

        [ValidateSet('admin','operator','viewer')]
        [string]$Role = 'viewer'
    )

    if (-not (Get-Command Get-EMSUser -ErrorAction SilentlyContinue)) {
        throw "Get-EMSUser is not available. PSPGSql.psm1 may not be loaded correctly."
    }

    if (-not (Get-Command New-EMSUser -ErrorAction SilentlyContinue)) {
        throw "New-EMSUser is not available. PSPGSql.psm1 may not be loaded correctly."
    }

    Ensure-LocalCredentialTable

    if (Get-EMSUser -Username $Username) {
        throw "User '$Username' already exists."
    }

    $display = if ([string]::IsNullOrWhiteSpace($DisplayName)) { $Username } else { $DisplayName }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
	try {
    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
	}
	finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

    $newUser = New-EMSUser -Username $Username -Domain 'LOCAL' -DisplayName $display -Role $Role
    $hashData = New-PasswordHash -Password $plainPassword

    Invoke-PGQuery -NonQuery -Query @"
INSERT INTO user_credentials (user_id, password_hash, password_salt, is_active, created_at)
VALUES (@userid, @hash, @salt, true, NOW())
"@ -Parameters @{
        userid = $newUser.user_id
        hash   = $hashData.Hash
        salt   = $hashData.Salt
    } | Out-Null

    if (Get-Command Write-EMSLog -ErrorAction SilentlyContinue) {
        Write-EMSLog -Message "Standalone (LOCAL) user created: $Username" -Severity 'Success'
    }

    return $newUser
}

# ---------------------------------------------------------
# Update standalone local EMS user password
# ---------------------------------------------------------
function Set-StandalonePassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Username,

        [Parameter(Mandatory)]
        [SecureString]$NewSecurePassword
    )

    $user = Get-EMSLocalCredential -Username $Username
    if (-not $user) {
        throw "User '$Username' not found."
    }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($NewSecurePassword)
    try {
        $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }

    $hashData = New-PasswordHash -Password $plainPassword
    
    Invoke-PGQuery -NonQuery -Query @"
UPDATE user_credentials 
SET password_hash = @hash, 
    password_salt = @salt, 
    updated_at = NOW() 
WHERE user_id = @userid
"@ -Parameters @{
        userid = $user.user_id
        hash   = $hashData.Hash
        salt   = $hashData.Salt
    } | Out-Null

    if (Get-Command Write-EMSLog -ErrorAction SilentlyContinue) {
        Write-EMSLog -Message "Password updated for LOCAL user: $Username" -Severity 'Info'
    }
}

Export-ModuleMember -Function @(
    'Test-StandaloneAuth',
    'New-StandaloneUser',
    'Set-StandalonePassword',
    'Get-EMSLocalCredential',
    'New-PasswordHash',
    'Test-PasswordHash'
)

