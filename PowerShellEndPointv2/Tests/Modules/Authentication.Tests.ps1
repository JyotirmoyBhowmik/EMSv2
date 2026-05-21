BeforeAll {
    $global:ModulePath = Resolve-Path "$PSScriptRoot/../../Modules/Authentication.psm1"

    # We define dummy global functions that might be required
    function global:Write-EMSLog {}
}

Describe "Authentication Module - Initialize-ADAccountManagement" {
    Context "When Initialize-ADAccountManagement executes" {
        BeforeAll {
            Import-Module $global:ModulePath -Force
        }

        It "Successfully ensures the assembly is loaded" {
            InModuleScope Authentication {
                Mock Add-Type {
                    Microsoft.PowerShell.Utility\Add-Type -TypeDefinition @"
                    namespace System.DirectoryServices.AccountManagement {
                        public class ContextType {}
                    }
"@
                }

                { Initialize-ADAccountManagement } | Should -Not -Throw
            }
        }

        It "Throws exception when the assembly cannot be loaded" {
            # Since the assembly is natively loaded in our test environment (PowerShell 7),
            # the only way to accurately test the failure condition logic without altering the real source code
            # is to create a dynamic copy of the module with an impossible type.
            $moduleContent = Get-Content $global:ModulePath -Raw
            $modifiedContent = $moduleContent -replace '"System\.DirectoryServices\.AccountManagement\.ContextType"', '"Dummy.Missing.Type.That.Fails"'

            $tempDir = [System.IO.Path]::GetTempPath()
            $tempModulePath = Join-Path $tempDir "AuthenticationTest_$([guid]::NewGuid().ToString()).psm1"
            Set-Content -Path $tempModulePath -Value $modifiedContent

            try {
                Import-Module $tempModulePath -Force
                InModuleScope (Split-Path $tempModulePath -LeafBase) {
                    Mock Add-Type { }
                    { Initialize-ADAccountManagement } | Should -Throw "System.DirectoryServices.AccountManagement could not be loaded."
                }
            } finally {
                Remove-Module (Split-Path $tempModulePath -LeafBase) -ErrorAction SilentlyContinue
                Remove-Item -Path $tempModulePath -ErrorAction SilentlyContinue
            }
        }
    }
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
