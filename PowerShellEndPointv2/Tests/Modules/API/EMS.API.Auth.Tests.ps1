BeforeAll {
    $global:ModulePath = Resolve-Path "$PSScriptRoot/../../../Modules/API/EMS.API.Auth.psm1"

    function global:Read-JsonBody {}
    function global:Write-JsonResponse {}
    function global:Resolve-ProviderValue {}
    function global:ConvertTo-SecureString {}
    function global:Invoke-MultiProviderAuth {}
    function global:Resolve-UserRole {}
    function global:Get-EMSEnvironmentVar {}
    function global:New-EMSJwt {}
    function global:Write-EMSLog {}

    Import-Module $global:ModulePath -Force

    $global:GlobalConfig = [pscustomobject]@{
        API = [pscustomobject]@{
            AllowedOrigins = @("http://localhost:3000")
        }
    }

    $global:EMSConfig = $global:GlobalConfig
}

Describe "Invoke-AuthRoutes" {
    Context "When path does not match" {
        It "Should return false" {
            $result = Invoke-AuthRoutes -Request $null -Response $null -Method "GET" -Path "/auth/login" -Config $null
            $result | Should -Be $false
        }
    }

    Context "POST /auth/login - Missing Body or Credentials" {
        It "Should return 400 and true when body is missing" {
            Mock Read-JsonBody { return $null } -ModuleName "EMS.API.Auth"
            Mock Write-JsonResponse {} -ModuleName "EMS.API.Auth"

            $result = Invoke-AuthRoutes -Request $null -Response $null -Method "POST" -Path "/auth/login" -Config $global:GlobalConfig

            $result | Should -Be $true
            Assert-MockCalled Write-JsonResponse -ModuleName "EMS.API.Auth" -Times 1 -Exactly
        }

        It "Should return 400 and true when username is missing" {
            Mock Read-JsonBody { return [pscustomobject]@{ password = "pass" } } -ModuleName "EMS.API.Auth"
            Mock Write-JsonResponse {} -ModuleName "EMS.API.Auth"

            $result = Invoke-AuthRoutes -Request $null -Response $null -Method "POST" -Path "/auth/login" -Config $global:GlobalConfig

            $result | Should -Be $true
            Assert-MockCalled Write-JsonResponse -ModuleName "EMS.API.Auth" -Times 1 -Exactly
        }

        It "Should return 400 and true when password is missing" {
            Mock Read-JsonBody { return [pscustomobject]@{ username = "user" } } -ModuleName "EMS.API.Auth"
            Mock Write-JsonResponse {} -ModuleName "EMS.API.Auth"

            $result = Invoke-AuthRoutes -Request $null -Response $null -Method "POST" -Path "/auth/login" -Config $global:GlobalConfig

            $result | Should -Be $true
            Assert-MockCalled Write-JsonResponse -ModuleName "EMS.API.Auth" -Times 1 -Exactly
        }
    }

    Context "POST /auth/login - Invalid Credentials" {
        It "Should return 401 when auth fails" {
            Mock Read-JsonBody { return [pscustomobject]@{ username = "user"; password = "bad"; provider = "ad" } } -ModuleName "EMS.API.Auth"
            Mock Resolve-ProviderValue { return "ad" } -ModuleName "EMS.API.Auth"
            Mock ConvertTo-SecureString { return "secure_string_mock" } -ModuleName "EMS.API.Auth"
            Mock Invoke-MultiProviderAuth { return [pscustomobject]@{ Success = $false } } -ModuleName "EMS.API.Auth"
            Mock Write-JsonResponse {} -ModuleName "EMS.API.Auth"

            $result = Invoke-AuthRoutes -Request $null -Response $null -Method "POST" -Path "/auth/login" -Config $global:GlobalConfig

            $result | Should -Be $true
            Assert-MockCalled Write-JsonResponse -ModuleName "EMS.API.Auth" -Times 1 -Exactly
        }
    }

    Context "POST /auth/login - Missing Role" {
        It "Should return 403 when role cannot be resolved" {
            Mock Read-JsonBody { return [pscustomobject]@{ username = "user"; password = "pwd"; provider = "ad" } } -ModuleName "EMS.API.Auth"
            Mock Resolve-ProviderValue { return "ad" } -ModuleName "EMS.API.Auth"
            Mock ConvertTo-SecureString { return "secure_string_mock" } -ModuleName "EMS.API.Auth"
            Mock Invoke-MultiProviderAuth { return [pscustomobject]@{ Success = $true; User = "user"; Groups = @(); Role = $null } } -ModuleName "EMS.API.Auth"
            Mock Resolve-UserRole { return $null } -ModuleName "EMS.API.Auth"
            Mock Write-JsonResponse {} -ModuleName "EMS.API.Auth"

            $result = Invoke-AuthRoutes -Request $null -Response $null -Method "POST" -Path "/auth/login" -Config $global:GlobalConfig

            $result | Should -Be $true
            Assert-MockCalled Write-JsonResponse -ModuleName "EMS.API.Auth" -Times 1 -Exactly
        }
    }

    Context "POST /auth/login - Server Misconfiguration" {
        It "Should return 500 when JWT_SECRET is missing" {
            Mock Read-JsonBody { return [pscustomobject]@{ username = "user"; password = "pwd"; provider = "ad" } } -ModuleName "EMS.API.Auth"
            Mock Resolve-ProviderValue { return "ad" } -ModuleName "EMS.API.Auth"
            Mock ConvertTo-SecureString { return "secure_string_mock" } -ModuleName "EMS.API.Auth"
            Mock Invoke-MultiProviderAuth { return [pscustomobject]@{ Success = $true; User = "user"; Groups = @(); Role = "admin" } } -ModuleName "EMS.API.Auth"
            Mock Resolve-UserRole { return "admin" } -ModuleName "EMS.API.Auth"
            Mock Get-EMSEnvironmentVar { return $null } -ModuleName "EMS.API.Auth"
            Mock Write-JsonResponse {} -ModuleName "EMS.API.Auth"

            $result = Invoke-AuthRoutes -Request $null -Response $null -Method "POST" -Path "/auth/login" -Config $global:GlobalConfig

            $result | Should -Be $true
            Assert-MockCalled Write-JsonResponse -ModuleName "EMS.API.Auth" -Times 1 -Exactly
        }
    }

    Context "POST /auth/login - Success" {
        It "Should return 200 and a token" {
            Mock Read-JsonBody { return [pscustomobject]@{ username = "user"; password = "pwd"; provider = "ad" } } -ModuleName "EMS.API.Auth"
            Mock Resolve-ProviderValue { return "ad" } -ModuleName "EMS.API.Auth"
            Mock ConvertTo-SecureString { return "secure_string_mock" } -ModuleName "EMS.API.Auth"
            Mock Invoke-MultiProviderAuth { return [pscustomobject]@{ Success = $true; User = "user"; Groups = @("g1"); Source = "AD"; Role = "admin" } } -ModuleName "EMS.API.Auth"
            Mock Resolve-UserRole { return "admin" } -ModuleName "EMS.API.Auth"
            Mock Get-EMSEnvironmentVar { return "secret" } -ModuleName "EMS.API.Auth"
            Mock New-EMSJwt { return "jwt.token.here" } -ModuleName "EMS.API.Auth"
            Mock Write-EMSLog {} -ModuleName "EMS.API.Auth"
            Mock Write-JsonResponse {} -ModuleName "EMS.API.Auth"

            $result = Invoke-AuthRoutes -Request $null -Response $null -Method "POST" -Path "/auth/login" -Config $global:GlobalConfig

            $result | Should -Be $true
            Assert-MockCalled Write-EMSLog -ModuleName "EMS.API.Auth" -Times 1 -Exactly
            Assert-MockCalled Write-JsonResponse -ModuleName "EMS.API.Auth" -Times 1 -Exactly
        }

        It "Should fallback to authResult.Role if Resolve-UserRole returns null" {
            Mock Read-JsonBody { return [pscustomobject]@{ username = "user"; password = "pwd"; provider = "ad" } } -ModuleName "EMS.API.Auth"
            Mock Resolve-ProviderValue { return "ad" } -ModuleName "EMS.API.Auth"
            Mock ConvertTo-SecureString { return "secure_string_mock" } -ModuleName "EMS.API.Auth"
            Mock Invoke-MultiProviderAuth { return [pscustomobject]@{ Success = $true; User = "user"; Groups = @("g1"); Source = "AD"; Role = "fallback_role" } } -ModuleName "EMS.API.Auth"
            Mock Resolve-UserRole { return $null } -ModuleName "EMS.API.Auth"
            Mock Get-EMSEnvironmentVar { return "secret" } -ModuleName "EMS.API.Auth"
            Mock New-EMSJwt { return "jwt.token.here" } -ModuleName "EMS.API.Auth"
            Mock Write-EMSLog {} -ModuleName "EMS.API.Auth"
            Mock Write-JsonResponse {} -ModuleName "EMS.API.Auth"

            $result = Invoke-AuthRoutes -Request $null -Response $null -Method "POST" -Path "/auth/login" -Config $global:GlobalConfig

            $result | Should -Be $true
            Assert-MockCalled Write-EMSLog -ModuleName "EMS.API.Auth" -Times 1 -Exactly
            Assert-MockCalled Write-JsonResponse -ModuleName "EMS.API.Auth" -Times 1 -Exactly

            # Additional check: verify New-EMSJwt was called
            Assert-MockCalled New-EMSJwt -ModuleName "EMS.API.Auth" -Times 1 -Exactly
        }
    }
}
