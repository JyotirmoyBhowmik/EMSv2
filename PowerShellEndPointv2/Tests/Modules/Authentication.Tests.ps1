BeforeAll {
    $global:ModulePath = Resolve-Path "$PSScriptRoot/../../Modules/Authentication.psm1"

    # We define dummy global functions that might be required
    function global:Write-EMSLog {}
}

Describe "Test-ADCredential" {
    BeforeAll {
        Import-Module $global:ModulePath -Force
    }

    Context "Normalization and Validation" {
        It "Validates successful credentials with username@domain format" {
            $secPassword = ConvertTo-SecureString "password123" -AsPlainText -Force

            Mock Initialize-ADAccountManagement {} -ModuleName "Authentication"
            Mock New-Object {
                $mockContext = [PSCustomObject]@{}
                Add-Member -InputObject $mockContext -MemberType ScriptMethod -Name "ValidateCredentials" -Value { param($u, $p) return $true }
                Add-Member -InputObject $mockContext -MemberType ScriptMethod -Name "Dispose" -Value { }
                return $mockContext
            } -ModuleName "Authentication"

            $result = Test-ADCredential -Username "testuser@mydomain.com" -SecurePassword $secPassword

            $result | Should -Be $true
            Assert-MockCalled New-Object -ModuleName "Authentication" -Times 1 -Exactly
        }

        It "Validates successful credentials with domain\username format" {
            $secPassword = ConvertTo-SecureString "password123" -AsPlainText -Force

            Mock Initialize-ADAccountManagement {} -ModuleName "Authentication"
            Mock New-Object {
                $mockContext = [PSCustomObject]@{}
                Add-Member -InputObject $mockContext -MemberType ScriptMethod -Name "ValidateCredentials" -Value { param($u, $p) return $true }
                Add-Member -InputObject $mockContext -MemberType ScriptMethod -Name "Dispose" -Value { }
                return $mockContext
            } -ModuleName "Authentication"

            $result = Test-ADCredential -Username "mydomain\testuser" -SecurePassword $secPassword

            $result | Should -Be $true
            Assert-MockCalled New-Object -ModuleName "Authentication" -Times 1 -Exactly
        }

        It "Validates credentials with missing domain using environment variables" {
            $secPassword = ConvertTo-SecureString "password123" -AsPlainText -Force

            # Save original environment variable
            $originalDomain = $env:USERDNSDOMAIN
            $env:USERDNSDOMAIN = "envdomain.local"

            Mock Initialize-ADAccountManagement {} -ModuleName "Authentication"
            Mock New-Object {
                $mockContext = [PSCustomObject]@{}
                Add-Member -InputObject $mockContext -MemberType ScriptMethod -Name "ValidateCredentials" -Value { param($u, $p) return $true }
                Add-Member -InputObject $mockContext -MemberType ScriptMethod -Name "Dispose" -Value { }
                return $mockContext
            } -ModuleName "Authentication"

            try {
                $result = Test-ADCredential -Username "testuser" -SecurePassword $secPassword

                $result | Should -Be $true
                Assert-MockCalled New-Object -ModuleName "Authentication" -Times 1 -Exactly -ParameterFilter {
                    $ArgumentList[1] -eq "envdomain.local"
                }
            } finally {
                # Restore environment variable
                $env:USERDNSDOMAIN = $originalDomain
            }
        }
    }

    Context "Authentication Failures" {
        It "Returns false on invalid credentials" {
            $secPassword = ConvertTo-SecureString "wrongpassword" -AsPlainText -Force

            Mock Initialize-ADAccountManagement {} -ModuleName "Authentication"
            Mock New-Object {
                $mockContext = [PSCustomObject]@{}
                Add-Member -InputObject $mockContext -MemberType ScriptMethod -Name "ValidateCredentials" -Value { param($u, $p) return $false }
                Add-Member -InputObject $mockContext -MemberType ScriptMethod -Name "Dispose" -Value { }
                return $mockContext
            } -ModuleName "Authentication"

            $result = Test-ADCredential -Username "testuser@mydomain.com" -SecurePassword $secPassword

            $result | Should -Be $false
        }

        It "Returns false and writes error on exception during validation" {
            $secPassword = ConvertTo-SecureString "password123" -AsPlainText -Force

            Mock Initialize-ADAccountManagement {} -ModuleName "Authentication"
            Mock New-Object {
                throw "LDAP server unavailable"
            } -ModuleName "Authentication"
            Mock Write-Error {} -ModuleName "Authentication"

            $result = Test-ADCredential -Username "testuser@mydomain.com" -SecurePassword $secPassword

            $result | Should -Be $false
            Assert-MockCalled Write-Error -ModuleName "Authentication" -Times 1 -Exactly
        }

        It "Throws when domain cannot be determined" {
            $secPassword = ConvertTo-SecureString "password123" -AsPlainText -Force

            # Save and clear environment variables
            $originalDnsDomain = $env:USERDNSDOMAIN
            $originalUserDomain = $env:USERDOMAIN
            $env:USERDNSDOMAIN = ""
            $env:USERDOMAIN = ""

            Mock Initialize-ADAccountManagement {} -ModuleName "Authentication"
            Mock Write-Error {} -ModuleName "Authentication"

            try {
                $result = Test-ADCredential -Username "testuser" -SecurePassword $secPassword

                $result | Should -Be $false
                Assert-MockCalled Write-Error -ModuleName "Authentication" -Times 1 -Exactly -ParameterFilter {
                    $Message -match "Domain could not be determined"
                }
            } finally {
                # Restore environment variables
                $env:USERDNSDOMAIN = $originalDnsDomain
                $env:USERDOMAIN = $originalUserDomain
            }
        }
    }
}
