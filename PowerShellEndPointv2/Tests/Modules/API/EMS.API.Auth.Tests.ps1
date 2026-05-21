Describe 'EMS.API.Auth.Invoke-AuthRoutes' {
    BeforeAll {
        function global:Read-JsonBody { return $null }
        function global:Write-JsonResponse {}
        function global:Resolve-ProviderValue {}
        function global:Invoke-MultiProviderAuth {}
        function global:Resolve-UserRole {}
        function global:Get-EMSEnvironmentVar {}
        function global:New-EMSJwt {}
        function global:Write-EMSLog {}

        Import-Module "$PSScriptRoot\..\..\..\Modules\API\EMS.API.Auth.psm1" -Force
    }

    It 'Returns false for unknown routes' {
        $result = Invoke-AuthRoutes -Method 'GET' -Path '/auth/unknown'
        $result | Should -Be $false
    }

    It 'Returns 400 for missing credentials' {
        InModuleScope EMS.API.Auth {
            $script:writeJsonArgs = $null
            function Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $script:writeJsonArgs = @{ StatusCode = $StatusCode; Body = $Body }
            }

            # Missing credentials
            function Read-JsonBody { return @{ username = 'test'; provider = 'local' } }

            $global:authResult = Invoke-AuthRoutes -Method 'POST' -Path '/auth/login'
        }
        $global:authResult | Should -Be $true

        InModuleScope EMS.API.Auth {
            $script:writeJsonArgs.StatusCode | Should -Be 400
        }
    }

    It 'Returns 401 for invalid credentials' {
        InModuleScope EMS.API.Auth {
            $script:writeJsonArgs = $null
            function Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $script:writeJsonArgs = @{ StatusCode = $StatusCode; Body = $Body }
            }

            function Read-JsonBody { return @{ username = 'test'; password = 'pwd'; provider = 'local' } }
            function Resolve-ProviderValue { return 'local' }
            function Invoke-MultiProviderAuth { return @{ Success = $false } }

            $global:authResult = Invoke-AuthRoutes -Method 'POST' -Path '/auth/login'
        }
        $global:authResult | Should -Be $true

        InModuleScope EMS.API.Auth {
            $script:writeJsonArgs.StatusCode | Should -Be 401
        }
    }

    It 'Returns 403 for missing role assignment' {
        InModuleScope EMS.API.Auth {
            $script:writeJsonArgs = $null
            function Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $script:writeJsonArgs = @{ StatusCode = $StatusCode; Body = $Body }
            }

            function Read-JsonBody { return @{ username = 'test'; password = 'pwd'; provider = 'local' } }
            function Resolve-ProviderValue { return 'local' }
            function Invoke-MultiProviderAuth { return @{ Success = $true; User = 'test'; Groups = @() } }
            function Resolve-UserRole { return $null }

            $global:authResult = Invoke-AuthRoutes -Method 'POST' -Path '/auth/login'
        }
        $global:authResult | Should -Be $true

        InModuleScope EMS.API.Auth {
            $script:writeJsonArgs.StatusCode | Should -Be 403
        }
    }

    It 'Returns 500 when server misconfigured (missing JWT_SECRET)' {
        InModuleScope EMS.API.Auth {
            $script:writeJsonArgs = $null
            function Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $script:writeJsonArgs = @{ StatusCode = $StatusCode; Body = $Body }
            }

            function Read-JsonBody { return @{ username = 'test'; password = 'pwd'; provider = 'local' } }
            function Resolve-ProviderValue { return 'local' }
            function Invoke-MultiProviderAuth { return @{ Success = $true; User = 'test'; Groups = @(); Role = 'User' } }
            function Resolve-UserRole { return 'User' }
            function Get-EMSEnvironmentVar { return $null }

            $global:authResult = Invoke-AuthRoutes -Method 'POST' -Path '/auth/login'
        }
        $global:authResult | Should -Be $true

        InModuleScope EMS.API.Auth {
            $script:writeJsonArgs.StatusCode | Should -Be 500
        }
    }

    It 'Returns 200 with token for valid login' {
        InModuleScope EMS.API.Auth {
            $script:writeJsonArgs = $null
            function Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $script:writeJsonArgs = @{ StatusCode = $StatusCode; Body = $Body }
            }

            function Read-JsonBody { return @{ username = 'test'; password = 'pwd'; provider = 'local' } }
            function Resolve-ProviderValue { return 'local' }
            function Invoke-MultiProviderAuth { return @{ Success = $true; User = 'test'; Groups = @(); Role = 'User' } }
            function Resolve-UserRole { return 'User' }
            function Get-EMSEnvironmentVar { return 'secret' }
            function New-EMSJwt { return 'mock.token.str' }
            function Write-EMSLog {}

            $global:authResult = Invoke-AuthRoutes -Method 'POST' -Path '/auth/login'
        }
        $global:authResult | Should -Be $true

        InModuleScope EMS.API.Auth {
            $script:writeJsonArgs.StatusCode | Should -Be 200
            $script:writeJsonArgs.Body.token | Should -Be 'mock.token.str'
        }
    }
}
