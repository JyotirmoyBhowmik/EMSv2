<#
    EMS.Jwt.psm1
    JWT Token Management
#>


$script:Base64UrlEncode = {
    param([byte[]]$bytes)
    [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
}
$script:Base64UrlDecode = {
    param([string]$s)
    $s = $s.Replace('-','+').Replace('_','/')
    switch ($s.Length % 4) { 2 { $s += '==' }; 3 { $s += '=' } }
    [Convert]::FromBase64String($s)
}

function New-EMSJwt {
    <#
    .SYNOPSIS Issues a signed JWT (HS256).
    #>
    param(
        [Parameter(Mandatory)][string]   $Subject,
        [Parameter(Mandatory)][string]   $Role,
        [string[]] $Groups       = @(),
        [string]   $Issuer       = 'ems-api',
        [string]   $Audience     = 'ems-webui',
        [int]      $ExpiresIn    = 3600,
        [Parameter(Mandatory)][string]   $Secret,
        [hashtable]$ExtraClaims = @{}
    )
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $header  = @{ alg='HS256'; typ='JWT' } | ConvertTo-Json -Compress
    $payload = @{
        sub    = $Subject
        role   = $Role
        groups = @($Groups)
        iss    = $Issuer
        aud    = $Audience
        iat    = $now
        nbf    = $now
        exp    = $now + $ExpiresIn
        jti    = [Guid]::NewGuid().ToString('N')
    }
    foreach ($k in $ExtraClaims.Keys) { $payload[$k] = $ExtraClaims[$k] }
    $payloadJson = $payload | ConvertTo-Json -Compress

    $h = & $script:Base64UrlEncode ([Text.Encoding]::UTF8.GetBytes($header))
    $p = & $script:Base64UrlEncode ([Text.Encoding]::UTF8.GetBytes($payloadJson))
    $signingInput = "$h.$p"

    $hmac = [System.Security.Cryptography.HMACSHA256]::new(
              [Text.Encoding]::UTF8.GetBytes($Secret))
    try {
        $sig = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($signingInput))
        $s   = & $script:Base64UrlEncode $sig
        return "$signingInput.$s"
    } finally { $hmac.Dispose() }
}

function ConvertFrom-EMSJwt {
    <#
    .SYNOPSIS Verifies HS256 signature, expiry, issuer, audience. Returns claims, or $null.
    #>
    param(
        [Parameter(Mandatory)][string] $Token,
        [Parameter(Mandatory)][string] $Secret,
        [string] $ExpectedIssuer   = 'ems-api',
        [string] $ExpectedAudience = 'ems-webui',
        [int]    $ClockSkewSec     = 30
    )
    $parts = $Token -split '\.'
    if ($parts.Count -ne 3) { return $null }

    $signingInput = "$($parts[0]).$($parts[1])"
    $hmac = [System.Security.Cryptography.HMACSHA256]::new(
              [Text.Encoding]::UTF8.GetBytes($Secret))
    try {
        $expected = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($signingInput))
    } finally { $hmac.Dispose() }
    try {
        $given = & $script:Base64UrlDecode $parts[2]
    } catch { return $null }

    if ($null -eq $given -or $given.Length -eq 0) { return $null }

    if (-not [System.Security.Cryptography.CryptographicOperations]::FixedTimeEquals(
              [byte[]]$expected, [byte[]]$given)) { return $null }

    try {
        $headerJson  = [Text.Encoding]::UTF8.GetString((& $script:Base64UrlDecode $parts[0]))
        $payloadJson = [Text.Encoding]::UTF8.GetString((& $script:Base64UrlDecode $parts[1]))
        $header  = $headerJson  | ConvertFrom-Json
        $payload = $payloadJson | ConvertFrom-Json
    } catch { return $null }

    if ($header.alg -ne 'HS256') { return $null }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($payload.exp + $ClockSkewSec -lt $now)   { return $null }
    if ($payload.nbf - $ClockSkewSec -gt $now)   { return $null }
    if ($ExpectedIssuer   -and $payload.iss -ne $ExpectedIssuer)   { return $null }
    if ($ExpectedAudience -and $payload.aud -ne $ExpectedAudience) { return $null }
    return $payload
}

Export-ModuleMember -Function New-EMSJwt, ConvertFrom-EMSJwt
