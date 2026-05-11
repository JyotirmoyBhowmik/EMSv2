<#
.SYNOPSIS
    EMS Environment Variable Manager
.DESCRIPTION
    Manages encrypted environment configuration values.
    Sensitive values like DB_PASSWORD, JWT_SECRET are stored encrypted
    in the database (environment_config table) using DPAPI.
    Non-sensitive values are stored as plaintext.
#>

function Set-EMSEnvironmentVar {
    <#
    .SYNOPSIS
        Encrypts and stores an environment variable in the database.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [string]$Value,

        [string]$Description = '',
        [bool]$IsSensitive = $true,
        [string]$UpdatedBy = $env:USERNAME
    )

    $storedValue = if ($IsSensitive) {
        # Encrypt sensitive values using DPAPI
        $secure = ConvertTo-SecureString $Value -AsPlainText -Force
        $secure | ConvertFrom-SecureString
    } else {
        $Value
    }

    Invoke-PGQuery -NonQuery -Query @"
        INSERT INTO environment_config (config_key, encrypted_value, is_sensitive, description, updated_by, updated_at)
        VALUES (@key, @val, @sens, @desc, @by, NOW())
        ON CONFLICT (config_key) DO UPDATE SET
            encrypted_value = EXCLUDED.encrypted_value,
            is_sensitive = EXCLUDED.is_sensitive,
            description = EXCLUDED.description,
            updated_by = EXCLUDED.updated_by,
            updated_at = NOW()
"@ -Parameters @{
        key  = $Key
        val  = $storedValue
        sens = $IsSensitive
        desc = $Description
        by   = $UpdatedBy
    }

    Write-EMSLog -Message "Environment variable '$Key' updated (sensitive=$IsSensitive)" -Severity 'Success' -Category 'Config'
}

function Get-EMSEnvironmentVar {
    <#
    .SYNOPSIS
        Retrieves and decrypts an environment variable from the database.
    .RETURNS
        Decrypted string value, or $null if not found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $row = Invoke-PGQuery -Query "SELECT encrypted_value, is_sensitive FROM environment_config WHERE config_key = @key LIMIT 1;" -Parameters @{ key = $Key } | Select-Object -First 1

    if (-not $row) { return $null }

    if ($row.is_sensitive) {
        try {
            $secure = $row.encrypted_value | ConvertTo-SecureString
            return [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            )
        }
        catch {
            Write-EMSLog -Message "Failed to decrypt environment variable '$Key': $($_.Exception.Message)" -Severity 'Error' -Category 'Config'
            return $null
        }
    }

    return $row.encrypted_value
}

function Get-EMSEnvironmentConfig {
    <#
    .SYNOPSIS
        Returns metadata about all stored environment variables (no decrypted values for sensitive keys).
    #>
    [CmdletBinding()]
    param()

    $rows = Invoke-PGQuery -Query "SELECT config_key, is_sensitive, description, updated_by, updated_at FROM environment_config ORDER BY config_key;"
    
    return $rows | ForEach-Object {
        [pscustomobject]@{
            key         = $_.config_key
            isSensitive = $_.is_sensitive
            value       = if ($_.is_sensitive) { '••••••••' } else { (Get-EMSEnvironmentVar -Key $_.config_key) }
            description = $_.description
            updatedBy   = $_.updated_by
            updatedAt   = $_.updated_at
        }
    }
}

function Remove-EMSEnvironmentVar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    Invoke-PGQuery -NonQuery -Query "DELETE FROM environment_config WHERE config_key = @key;" -Parameters @{ key = $Key }
    Write-EMSLog -Message "Environment variable '$Key' deleted" -Severity 'Warning' -Category 'Config'
}

Export-ModuleMember -Function Set-EMSEnvironmentVar, Get-EMSEnvironmentVar, Get-EMSEnvironmentConfig, Remove-EMSEnvironmentVar
