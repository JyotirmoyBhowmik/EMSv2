BeforeAll {
    $global:ModulePath = Resolve-Path "$PSScriptRoot/../../../Modules/API/EMS.API.Admin.psm1"

    function global:Test-AdminAccessRequirement { return $true }
    function global:Get-RequestUserContext { return [pscustomobject]@{ Username = "testadmin" } }
    function global:Write-JsonResponse {
        param($Request, $Response, $StatusCode, $Body)
    }
    function global:Invoke-PGQuery {}
    function global:Read-JsonBody {}
    function global:Test-StandaloneAuth { return [pscustomobject]@{ Success = $true } }
    function global:Set-StandalonePassword {}
    function global:Get-EMSServiceCredentialInfo { return @() }
    function global:Test-EMSServiceCredential { return [pscustomobject]@{ Success=$true; Message="OK" } }
    function global:Set-EMSServiceCredential {}
    function global:Get-EMSEnvironmentConfig { return @() }
    function global:Set-EMSEnvironmentVar {}

    Import-Module $global:ModulePath -Force
}

Describe "EMS.API.Admin - Invoke-AdminRoutes" {
    BeforeEach {
        $global:MockResponse = $null
        $global:MockStatusCode = $null
        $global:MockError = $null
    }

    Context "GET /admin/health" {
        It "Should return health metrics" {
            Mock Test-AdminAccessRequirement { return $true } -ModuleName "EMS.API.Admin"
            Mock Invoke-PGQuery { return $true } -ModuleName "EMS.API.Admin"
            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockResponse = $Body
                $global:MockStatusCode = $StatusCode
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'GET' -Path '/admin/health' -Config @{}

            $result[-1] | Should -Be $true
            # Note: Changed from Assert-MockCalled to Should -Invoke as requested by code review
            Should -Invoke -CommandName Write-JsonResponse -ModuleName "EMS.API.Admin" -Times 1 -Exactly
            $global:MockStatusCode | Should -Be 200
            $global:MockResponse.success | Should -Be $true
            $global:MockResponse.database.status | Should -Be 'Healthy'
        }
    }

    Context "GET /admin/settings" {
        It "Should return feature toggles" {
            Mock Test-AdminAccessRequirement { return $true } -ModuleName "EMS.API.Admin"
            Mock Invoke-PGQuery {
                return @(
                    [pscustomobject]@{ feature_key = 'test1'; enabled = $true }
                )
            } -ModuleName "EMS.API.Admin"
            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockResponse = $Body
                $global:MockStatusCode = $StatusCode
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'GET' -Path '/admin/settings' -Config @{}

            $result[-1] | Should -Be $true
            $global:MockStatusCode | Should -Be 200
            $global:MockResponse.features.Count | Should -Be 1
        }
    }

    Context "GET /admin/users" {
        It "Should return users" {
            Mock Test-AdminAccessRequirement { return $true } -ModuleName "EMS.API.Admin"
            Mock Invoke-PGQuery {
                return @(
                    [pscustomobject]@{ user_id = '123'; username = 'alice' }
                )
            } -ModuleName "EMS.API.Admin"
            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockResponse = $Body
                $global:MockStatusCode = $StatusCode
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'GET' -Path '/admin/users' -Config @{}

            $result[-1] | Should -Be $true
            $global:MockStatusCode | Should -Be 200
            $global:MockResponse.users.Count | Should -Be 1
        }
    }

    Context "GET /admin/reboot-status" {
        It "Should return endpoint reboot status" {
            Mock Test-AdminAccessRequirement { return $true } -ModuleName "EMS.API.Admin"
            Mock Invoke-PGQuery { return @() } -ModuleName "EMS.API.Admin"
            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockResponse = $Body
                $global:MockStatusCode = $StatusCode
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'GET' -Path '/admin/reboot-status' -Config @{}

            $result[-1] | Should -Be $true
            $global:MockStatusCode | Should -Be 200
            $global:MockResponse.success | Should -Be $true
        }
    }

    Context "GET /admin/connectors" {
        It "Should return connector statuses" {
            Mock Test-AdminAccessRequirement { return $true } -ModuleName "EMS.API.Admin"
            Mock Invoke-PGQuery { return $true } -ModuleName "EMS.API.Admin"
            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockResponse = $Body
                $global:MockStatusCode = $StatusCode
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'GET' -Path '/admin/connectors' -Config @{}

            $result[-1] | Should -Be $true
            $global:MockStatusCode | Should -Be 200
            $global:MockResponse.connectors.Count | Should -BeGreaterThan 0
        }
    }

    Context "POST /admin/users" {
        It "Should create a user and return 201" {
            Mock Test-AdminAccessRequirement { return $true } -ModuleName "EMS.API.Admin"
            Mock Read-JsonBody {
                return [pscustomobject]@{
                    username = 'newuser'
                    display_name = 'New User'
                    email = 'new@user.com'
                    role = 'admin'
                }
            } -ModuleName "EMS.API.Admin"
            Mock Invoke-PGQuery {} -ModuleName "EMS.API.Admin"
            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockResponse = $Body
                $global:MockStatusCode = $StatusCode
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'POST' -Path '/admin/users' -Config @{}

            $result[-1] | Should -Be $true
            $global:MockStatusCode | Should -Be 201
            $global:MockResponse.success | Should -Be $true
        }

        It "Should return 400 if username is missing" {
            Mock Test-AdminAccessRequirement { return $true } -ModuleName "EMS.API.Admin"
            Mock Read-JsonBody { return [pscustomobject]@{ role = 'admin' } } -ModuleName "EMS.API.Admin"
            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockResponse = $Body
                $global:MockStatusCode = $StatusCode
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'POST' -Path '/admin/users' -Config @{}

            $result[-1] | Should -Be $true
            $global:MockStatusCode | Should -Be 400
        }
    }

    Context "POST /auth/change-password" {
        It "Should return 401 if unauthorized" {
            Mock Get-RequestUserContext { return [pscustomobject]@{ Username = $null } } -ModuleName "EMS.API.Admin"
            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockStatusCode = $StatusCode
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'POST' -Path '/auth/change-password' -Config @{}

            $result[-1] | Should -Be $true
            $global:MockStatusCode | Should -Be 401
        }

        It "Should return 400 if passwords missing" {
            Mock Get-RequestUserContext { return [pscustomobject]@{ Username = "user" } } -ModuleName "EMS.API.Admin"
            Mock Read-JsonBody { return [pscustomobject]@{ oldPassword = 'old' } } -ModuleName "EMS.API.Admin"
            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockStatusCode = $StatusCode
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'POST' -Path '/auth/change-password' -Config @{}

            $result[-1] | Should -Be $true
            $global:MockStatusCode | Should -Be 400
        }

        It "Should update password successfully" {
            Mock Get-RequestUserContext { return [pscustomobject]@{ Username = "user" } } -ModuleName "EMS.API.Admin"
            Mock Read-JsonBody { return [pscustomobject]@{ oldPassword = 'old'; newPassword = 'new' } } -ModuleName "EMS.API.Admin"
            Mock Test-StandaloneAuth { return [pscustomobject]@{ Success = $true } } -ModuleName "EMS.API.Admin"
            Mock Set-StandalonePassword {} -ModuleName "EMS.API.Admin"
            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockStatusCode = $StatusCode
                $global:MockResponse = $Body
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'POST' -Path '/auth/change-password' -Config @{}

            $result[-1] | Should -Be $true
            $global:MockStatusCode | Should -Be 200
            $global:MockResponse.success | Should -Be $true
        }
    }

    Context "PUT /admin/settings/:key" {
        It "Should update feature toggle" {
            Mock Test-AdminAccessRequirement { return $true } -ModuleName "EMS.API.Admin"
            Mock Read-JsonBody { return [pscustomobject]@{ enabled = $true } } -ModuleName "EMS.API.Admin"

            Mock Invoke-PGQuery {
                return [pscustomobject]@{ enabled = $false }
            } -ModuleName "EMS.API.Admin"

            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockStatusCode = $StatusCode
                $global:MockResponse = $Body
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'PUT' -Path '/admin/settings/test-feature' -Config @{}

            $result[-1] | Should -Be $true
            $global:MockStatusCode | Should -Be 200
            $global:MockResponse.featureKey | Should -Be 'test-feature'
            $global:MockResponse.enabled | Should -Be $true
        }

        It "Should return 404 if feature not found" {
            Mock Test-AdminAccessRequirement { return $true } -ModuleName "EMS.API.Admin"
            Mock Read-JsonBody { return [pscustomobject]@{ enabled = $true } } -ModuleName "EMS.API.Admin"
            Mock Invoke-PGQuery { return $null } -ModuleName "EMS.API.Admin"
            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockStatusCode = $StatusCode
                $global:MockResponse = $Body
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'PUT' -Path '/admin/settings/test-feature' -Config @{}

            $result[-1] | Should -Be $true
            $global:MockStatusCode | Should -Be 404
        }
    }

    Context "PUT /admin/users/:id" {
        It "Should update user" {
            Mock Test-AdminAccessRequirement { return $true } -ModuleName "EMS.API.Admin"
            Mock Read-JsonBody { return [pscustomobject]@{ displayName = 'New Name'; email = 'email@x.com'; role = 'admin'; is_active = $true } } -ModuleName "EMS.API.Admin"
            Mock Invoke-PGQuery {} -ModuleName "EMS.API.Admin"
            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockStatusCode = $StatusCode
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'PUT' -Path '/admin/users/123' -Config @{}

            $result[-1] | Should -Be $true
            $global:MockStatusCode | Should -Be 200
        }
    }

    Context "DELETE /admin/users/:id" {
        It "Should delete user" {
            Mock Test-AdminAccessRequirement { return $true } -ModuleName "EMS.API.Admin"
            Mock Invoke-PGQuery {} -ModuleName "EMS.API.Admin"
            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockStatusCode = $StatusCode
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'DELETE' -Path '/admin/users/123' -Config @{}

            $result[-1] | Should -Be $true
            $global:MockStatusCode | Should -Be 200
        }
    }

    Context "Error Handling" {
        It "Should catch database exceptions and return 500" {
            Mock Test-AdminAccessRequirement { return $true } -ModuleName "EMS.API.Admin"
            Mock Invoke-PGQuery { throw "DB error" } -ModuleName "EMS.API.Admin"
            Mock Write-JsonResponse {
                param($Request, $Response, $StatusCode, $Body)
                $global:MockStatusCode = $StatusCode
            } -ModuleName "EMS.API.Admin"

            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'GET' -Path '/admin/users' -Config @{}

            $result[-1] | Should -Be $true
            $global:MockStatusCode | Should -Be 500
        }
    }

    Context "Unmatched Route" {
        It "Should return false for unknown routes" {
            $result = Invoke-AdminRoutes -Request $null -Response $null -Method 'GET' -Path '/unknown/path' -Config @{}

            $result[-1] | Should -Be $false
        }
    }
}
