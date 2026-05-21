BeforeAll {
    $global:ModulePath = Resolve-Path "$PSScriptRoot/../../../Modules/Authentication/StandaloneAuth.psm1"
    function global:Invoke-PGQuery {}
    function global:Initialize-PostgreSQLConnection {}
    function global:Write-EMSLog {}

    Import-Module $global:ModulePath -Force
}

Describe "Test-StandaloneAuth" {

    Context "User Not Found" {
        It "Should return Success = `$false and Message = 'User not found'" {
            Mock Get-EMSLocalCredential { return $null } -ModuleName "StandaloneAuth"

            $result = Test-StandaloneAuth -Username "nonexistent" -Password "password123" -Config @{}

            $result.Success | Should -Be $false
            $result.Message | Should -Be "User not found"
        }
    }

    Context "User is Inactive" {
        It "Should return Success = `$false and Message = 'User is inactive' when user.is_active is `$false" {
            $inactiveUser = [pscustomobject]@{
                user_id = 1
                username = "inactiveuser"
                is_active = $false
                credential_active = $true
            }
            Mock Get-EMSLocalCredential { return $inactiveUser } -ModuleName "StandaloneAuth"

            $result = Test-StandaloneAuth -Username "inactiveuser" -Password "password123" -Config @{}

            $result.Success | Should -Be $false
            $result.Message | Should -Be "User is inactive"
        }

        It "Should return Success = `$false and Message = 'User is inactive' when user.credential_active is `$false" {
            $inactiveCredUser = [pscustomobject]@{
                user_id = 1
                username = "inactivecreduser"
                is_active = $true
                credential_active = $false
            }
            Mock Get-EMSLocalCredential { return $inactiveCredUser } -ModuleName "StandaloneAuth"

            $result = Test-StandaloneAuth -Username "inactivecreduser" -Password "password123" -Config @{}

            $result.Success | Should -Be $false
            $result.Message | Should -Be "User is inactive"
        }
    }

    Context "Invalid Credentials" {
        It "Should return Success = `$false and Message = 'Invalid credentials' when Test-PasswordHash returns `$false" {
            $user = [pscustomobject]@{
                user_id = 1
                username = "validuser"
                is_active = $true
                credential_active = $true
                password_salt = "somesalt"
                password_hash = "somehash"
            }
            Mock Get-EMSLocalCredential { return $user } -ModuleName "StandaloneAuth"
            Mock Test-PasswordHash { return $false } -ModuleName "StandaloneAuth"

            $result = Test-StandaloneAuth -Username "validuser" -Password "wrongpassword" -Config @{}

            $result.Success | Should -Be $false
            $result.Message | Should -Be "Invalid credentials"
        }
    }

    Context "Valid Credentials" {
        It "Should return Success = `$true and correct user details when Test-PasswordHash returns `$true" {
            $user = [pscustomobject]@{
                user_id = 1
                username = "validuser"
                display_name = "Valid User"
                role = "admin"
                is_active = $true
                credential_active = $true
                password_salt = "somesalt"
                password_hash = "somehash"
            }
            Mock Get-EMSLocalCredential { return $user } -ModuleName "StandaloneAuth"
            Mock Test-PasswordHash { return $true } -ModuleName "StandaloneAuth"

            $result = Test-StandaloneAuth -Username "validuser" -Password "correctpassword" -Config @{}

            $result.Success | Should -Be $true
            $result.User | Should -Be "validuser"
            $result.DisplayName | Should -Be "Valid User"
            $result.Groups -contains "admin" | Should -Be $true
        }
    }

    Context "Error Handling" {
        It "Should return Success = `$false and the exception message on error, and log the error" {
            Mock Get-EMSLocalCredential { throw "Database error" } -ModuleName "StandaloneAuth"
            Mock Write-EMSLog {} -ModuleName "StandaloneAuth"

            $result = Test-StandaloneAuth -Username "erroruser" -Password "password123" -Config @{}

            $result.Success | Should -Be $false
            $result.Message | Should -Be "Database error"
            Assert-MockCalled Write-EMSLog -ModuleName "StandaloneAuth" -Times 1 -Exactly
        }
    }
}
