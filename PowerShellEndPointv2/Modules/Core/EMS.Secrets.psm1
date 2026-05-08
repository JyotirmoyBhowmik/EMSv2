<#
.SYNOPSIS
    EMS Secrets Management
.DESCRIPTION
    Provides DPAPI encryption for sensitive data like DB passwords.
#>

function Protect-EMSSecret {
    param([string]$PlainText)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $protected = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, 'CurrentUser')
    return [Convert]::ToBase64String($protected)
}

function Unprotect-EMSSecret {
    param([string]$EncryptedBase64)
    if (-not $EncryptedBase64) { return $null }
    $protected = [Convert]::FromBase64String($EncryptedBase64)
    $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect($protected, $null, 'CurrentUser')
    return [System.Text.Encoding]::UTF8.GetString($bytes)
}

Export-ModuleMember -Function Protect-EMSSecret, Unprotect-EMSSecret
