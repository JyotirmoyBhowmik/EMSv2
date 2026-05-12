<#
    EMS.Jwt.psm1
    JWT Token Management
#>

function New-EMSJwt {
    param(
        [Parameter(Mandatory=$true)][string]$Subject,
        [Parameter(Mandatory=$true)][string]$Role,
        [string[]]$Groups,
        [Parameter(Mandatory=$true)][string]$Secret,
        [int]$ExpiresIn = 3600
    )

    $header = @{
        alg = "HS256"
        typ = "JWT"
    } | ConvertTo-Json -Compress

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    $payload = @{
        sub = $Subject
        role = $Role
        groups = $Groups -join ';'
        iat = $now
        exp = $now + $ExpiresIn
    } | ConvertTo-Json -Compress

    $base64Header = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($header)) -replace '\+','-' -replace '/','_' -replace '='
    $base64Payload = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($payload)) -replace '\+','-' -replace '/','_' -replace '='

    $signatureString = "$base64Header.$base64Payload"
    $hmac = [System.Security.Cryptography.HMACSHA256]::new([System.Text.Encoding]::UTF8.GetBytes($Secret))
    $signatureBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($signatureString))
    $base64Signature = [Convert]::ToBase64String($signatureBytes) -replace '\+','-' -replace '/','_' -replace '='

    return "$base64Header.$base64Payload.$base64Signature"
}

function ConvertFrom-EMSJwt {
    param(
        [Parameter(Mandatory=$true)][string]$Token,
        [Parameter(Mandatory=$true)][string]$Secret
    )

    $parts = $Token.Split('.')
    if ($parts.Length -ne 3) {
        throw "Invalid JWT token structure"
    }

    $base64Header = $parts[0]
    $base64Payload = $parts[1]
    $signature = $parts[2]

    $signatureString = "$base64Header.$base64Payload"
    $hmac = [System.Security.Cryptography.HMACSHA256]::new([System.Text.Encoding]::UTF8.GetBytes($Secret))
    $expectedSignatureBytes = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($signatureString))
    $expectedSignature = [Convert]::ToBase64String($expectedSignatureBytes) -replace '\+','-' -replace '/','_' -replace '='

    if ($signature -ne $expectedSignature) {
        throw "JWT signature validation failed"
    }

    # Helper function for URL-safe base64 decoding
    $padBase64 = {
        param($b64)
        $b64 = $b64 -replace '-','+' -replace '_','/'
        $pad = $b64.Length % 4
        if ($pad) { $b64 += '=' * (4 - $pad) }
        return $b64
    }

    $payloadBytes = [Convert]::FromBase64String((&$padBase64 $base64Payload))
    $payloadJson = [System.Text.Encoding]::UTF8.GetString($payloadBytes)
    $payloadObj = $payloadJson | ConvertFrom-Json

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($payloadObj.exp -and $payloadObj.exp -lt $now) {
        throw "JWT token has expired"
    }

    return $payloadObj
}

Export-ModuleMember -Function New-EMSJwt, ConvertFrom-EMSJwt
