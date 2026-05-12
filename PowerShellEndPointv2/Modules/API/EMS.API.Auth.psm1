<#
    EMS.API.Auth.psm1
    Contains route handlers for /auth.
#>

Import-Module "$PSScriptRoot\..\Security\EMS.Jwt.psm1" -ErrorAction SilentlyContinue
Import-Module "$PSScriptRoot\..\Security\EMS.Environment.psm1" -ErrorAction SilentlyContinue

function Invoke-AuthRoutes {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [string]$Method,
        [string]$Path,
        [pscustomobject]$Config
    )

    switch ("$Method $Path") {
        'POST /auth/login' {
            $body = Read-JsonBody -Request $Request
            if (-not $body -or -not $body.username -or -not $body.password) {
                Write-JsonResponse -Request $Request -Response $Response -StatusCode 400 -Body @{ error='missing credentials' }
                return $true
            }

            $provider = Resolve-ProviderValue -ProviderInput $body.provider
            $securePassword = ConvertTo-SecureString $body.password -AsPlainText -Force
            $authResult = Invoke-MultiProviderAuth -Username $body.username -SecurePassword $securePassword -Provider $provider -Config $Global:EMSConfig

            if (-not $authResult.Success) {
                Write-JsonResponse -Request $Request -Response $Response -StatusCode 401 -Body @{ error='invalid credentials' }
                return $true
            }

            $role = Resolve-UserRole -Groups $authResult.Groups -Config $Global:EMSConfig
            if (-not $role -and $authResult.Role) {
                $role = $authResult.Role
            }
            if (-not $role) {
                Write-JsonResponse -Request $Request -Response $Response -StatusCode 403 -Body @{ error='Access denied. Missing role assignment.' }
                return $true
            }

            $secret = Get-EMSEnvironmentVar -Key 'JWT_SECRET'
            if (-not $secret) {
                Write-JsonResponse -Request $Request -Response $Response -StatusCode 500 -Body @{ error='server misconfigured' }
                return $true
            }

            $token = New-EMSJwt -Subject $authResult.User `
                                -Role    $role `
                                -Groups  $authResult.Groups `
                                -Secret  $secret `
                                -ExpiresIn 3600

            Write-EMSLog -Message "Login OK user=$($authResult.User) src=$($authResult.Source)" `
                         -Severity Info -Category Auth

            Write-JsonResponse -Request $Request -Response $Response -StatusCode 200 -Body @{
                token    = $token
                username = $authResult.User
                role     = $role
            }

            return $true
        }
    }
    return $false
}

Export-ModuleMember -Function Invoke-AuthRoutes
