<#
    EMS.Core.psm1
    Shared infrastructure utilities for the Enterprise Monitoring System.
#>

function Add-EMSCORSHeaders {
    param($Response,$Request,$Config)
    $origin = $Request.Headers['Origin']
    if ($origin -and ($Config.API.AllowedOrigins -contains $origin)) {
        $Response.Headers.Add('Access-Control-Allow-Origin', $origin)
        $Response.Headers.Add('Vary', 'Origin')
        $Response.Headers.Add('Access-Control-Allow-Credentials','true')
    }
    $Response.Headers.Add('Access-Control-Allow-Methods','GET,POST,PUT,DELETE,OPTIONS')
    $Response.Headers.Add('Access-Control-Allow-Headers','Authorization,Content-Type,X-CSRF-Token')
}

function Write-JsonResponse {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode,
        [object]$Body
    )

    Add-EMSCORSHeaders -Request $Request -Response $Response -Config $Global:EMSConfig

    $json = $Body | ConvertTo-Json -Depth 10 -Compress
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)

    $Response.StatusCode      = $StatusCode
    $Response.ContentType     = 'application/json'
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.OutputStream.Close()
}

function Read-JsonBody {
    param([System.Net.HttpListenerRequest]$Request)

    if ($Request.ContentType -notlike 'application/json*') {
        throw 'Invalid Content-Type'
    }

    $reader = [System.IO.StreamReader]::new($Request.InputStream)
    $raw    = $reader.ReadToEnd()

    if (-not $raw) {
        throw 'Empty request body'
    }

    return $raw | ConvertFrom-Json
}

function Resolve-ProviderValue {
    param($ProviderInput)

    if (-not $ProviderInput) { return 'Standalone' }
    if ($ProviderInput -is [string]) { return $ProviderInput }

    foreach ($prop in @('Name','Id','Value','Label','name','id','value','label')) {
        if ($ProviderInput.PSObject.Properties[$prop] -and $ProviderInput.$prop) {
            return [string]$ProviderInput.$prop
        }
    }

    return 'Standalone'
}

function Convert-IPv4ToUInt32 {
    param([Parameter(Mandatory)][string]$IPAddress)
    $bytes = [System.Net.IPAddress]::Parse($IPAddress).GetAddressBytes()
    [array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function Convert-UInt32ToIPv4 {
    param([Parameter(Mandatory)][uint32]$Value)
    $bytes = [BitConverter]::GetBytes($Value)
    [array]::Reverse($bytes)
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Expand-CidrRange {
    param([Parameter(Mandatory)][string]$Cidr)

    if ($Cidr -notmatch '^(\d{1,3}(?:\.\d{1,3}){3})/(\d{1,2})$') {
        throw "Invalid CIDR format: $Cidr"
    }

    $networkIp = $Matches[1]
    $prefix    = [int]$Matches[2]

    if ($prefix -lt 0 -or $prefix -gt 32) {
        throw "Invalid CIDR prefix: $Cidr"
    }

    if ($prefix -eq 32) { return @($networkIp) }

    $ipValue = Convert-IPv4ToUInt32 -IPAddress $networkIp
    $mask = if ($prefix -eq 0) { [uint32]0 } else { [uint32]([uint32]::MaxValue -shl (32 - $prefix)) }
    $network = $ipValue -band $mask
    $hostCount = [math]::Pow(2, (32 - $prefix))
    $broadcast = [uint32]($network + $hostCount - 1)

    $targets = New-Object System.Collections.Generic.List[string]
    for ($i = [uint32]($network + 1); $i -lt $broadcast; $i++) {
        [void]$targets.Add((Convert-UInt32ToIPv4 -Value $i))
    }

    return $targets
}

function Resolve-ScanTargets {
    param([Parameter(Mandatory)][string[]]$Targets)

    $allTargets = New-Object System.Collections.Generic.List[string]
    foreach ($entry in $Targets) {
        if (-not $entry) { continue }
        $parts = $entry -split '[,\r\n]'
        foreach ($raw in $parts) {
            $item = $raw.Trim()
            if (-not $item) { continue }
            if ($item -match '^\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}$') {
                $expanded = Expand-CidrRange -Cidr $item
                foreach ($ip in $expanded) { [void]$allTargets.Add($ip) }
            }
            else { [void]$allTargets.Add($item) }
        }
    }

    $seen = @{}
    $uniqueTargets = New-Object System.Collections.Generic.List[string]
    foreach ($t in $allTargets) {
        if (-not $seen.ContainsKey($t)) {
            $seen[$t] = $true
            [void]$uniqueTargets.Add($t)
        }
    }

    return $uniqueTargets
}

Export-ModuleMember -Function Add-EMSCORSHeaders, Write-JsonResponse, Read-JsonBody, Resolve-ProviderValue, Convert-IPv4ToUInt32, Convert-UInt32ToIPv4, Expand-CidrRange, Resolve-ScanTargets
