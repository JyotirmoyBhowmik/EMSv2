$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

Describe "Test-LDAPAuth" {
    BeforeAll {
        $global:ModulePath = Resolve-Path "$PSScriptRoot/../../../Modules/Authentication/LDAPAuth.psm1" -ErrorAction SilentlyContinue
        Import-Module $global:ModulePath -Force
        function global:New-Object { param($TypeName, $ArgumentList) }

        $global:mockClasses = @"
class MockDirectorySearcher {
    [string]`$Filter
    [System.Collections.ArrayList]`$PropertiesToLoad = [System.Collections.ArrayList]::new()

    [object] FindOne() {
        `$props = @{
            "distinguishedName" = @("uid=testuser,dc=example,dc=com")
            "displayName" = @("Test User")
            "mail" = @("test@example.com")
            "memberOf" = @("Group1")
        }
        return [PSCustomObject]@{ Properties = `$props }
    }

    [void] Dispose() {}
}

class MockDirectorySearcherNull {
    [string]`$Filter
    [System.Collections.ArrayList]`$PropertiesToLoad = [System.Collections.ArrayList]::new()

    [object] FindOne() {
        return `$null
    }

    [void] Dispose() {}
}
"@
        Invoke-Expression $global:mockClasses
    }

    Context "Happy Path" {
        It "Should return success when LDAP bind is successful with all properties" {
            $mockConfig = [PSCustomObject]@{
                Server = "ldap.example.com"
                BaseDN = "dc=example,dc=com"
                BindDN = "cn=admin,dc=example,dc=com"
                BindPassword = "password"
            }

            Mock New-Object {
                $mockLdap = [PSCustomObject]@{
                    name = "testuser"
                    displayName = "Test User"
                    mail = "test@example.com"
                    memberOf = @("Group1", "Group2")
                }
                $mockLdap | Add-Member -MemberType ScriptMethod -Name "Dispose" -Value {} -PassThru
            } -ModuleName LDAPAuth

            $result = Test-LDAPAuth -Username "testuser" -Password "password" -Config $mockConfig

            $result.Success | Should -Be $true
            $result.User | Should -Be "testuser"
            $result.DisplayName -contains "Test User" | Should -Be $true
            $result.Email -contains "test@example.com" | Should -Be $true

            $result.Groups -contains "Group1" | Should -Be $true
            $result.Groups -contains "Group2" | Should -Be $true

            Assert-MockCalled New-Object -ModuleName LDAPAuth -Times 1 -Exactly
        }

        It "Should handle missing optional attributes gracefully" {
            $mockConfig = [PSCustomObject]@{
                Server = "ldap.example.com"
                BaseDN = "dc=example,dc=com"
                BindDN = "cn=admin,dc=example,dc=com"
                BindPassword = "password"
            }

            Mock New-Object {
                $mockLdap = [PSCustomObject]@{
                    name = "testuser2"
                    displayName = $null
                    mail = $null
                    memberOf = $null
                }
                $mockLdap | Add-Member -MemberType ScriptMethod -Name "Dispose" -Value {} -PassThru
            } -ModuleName LDAPAuth

            $result = Test-LDAPAuth -Username "testuser2" -Password "password" -Config $mockConfig

            $result.Success | Should -Be $true
            $result.User | Should -Be "testuser2"
            $result.DisplayName | Should -Be "testuser2" # Falls back to Username
            $result.Email | Should -BeNullOrEmpty
            if ($null -ne $result.Groups) {
                $result.Groups.Count | Should -Be 0
            }

            Assert-MockCalled New-Object -ModuleName LDAPAuth -Times 1 -Exactly
        }
    }

    Context "Error Handling" {
        It "Should return false if user is not found (null name)" {
            $mockConfig = [PSCustomObject]@{
                Server = "ldap.example.com"
                BaseDN = "dc=example,dc=com"
            }

            Mock New-Object {
                $mockLdap = [PSCustomObject]@{
                    name = $null
                }
                $mockLdap | Add-Member -MemberType ScriptMethod -Name "Dispose" -Value {} -PassThru
            } -ModuleName LDAPAuth

            $result = Test-LDAPAuth -Username "wronguser" -Password "password" -Config $mockConfig

            $result.Success | Should -Be $false
            Assert-MockCalled New-Object -ModuleName LDAPAuth -Times 1 -Exactly
        }

        It "Should handle exceptions for invalid credentials" {
            $mockConfig = [PSCustomObject]@{
                Server = "ldap.example.com"
                BaseDN = "dc=example,dc=com"
            }

            Mock New-Object {
                throw [System.Management.Automation.MethodInvocationException]::new("LDAP authentication failed")
            } -ModuleName LDAPAuth

            $result = Test-LDAPAuth -Username "testuser" -Password "wrongpass" -Config $mockConfig

            $result.Success | Should -Be $false
            $result.Error -match "LDAP authentication failed" | Should -Be $true
        }

        It "Should handle generic exceptions correctly" {
            $mockConfig = [PSCustomObject]@{
                Server = "ldap.example.com"
                BaseDN = "dc=example,dc=com"
            }

            Mock New-Object {
                throw [System.Exception]::new("Server unreachable")
            } -ModuleName LDAPAuth

            $result = Test-LDAPAuth -Username "testuser" -Password "password" -Config $mockConfig

            $result.Success | Should -Be $false
            $result.Error | Should -Be "Server unreachable"
        }
    }
}

Describe "Search-LDAPUser" {
    BeforeAll {
        $global:ModulePath = Resolve-Path "$PSScriptRoot/../../../Modules/Authentication/LDAPAuth.psm1" -ErrorAction SilentlyContinue
        Import-Module $global:ModulePath -Force
        function global:New-Object { param($TypeName, $ArgumentList) }
        Invoke-Expression $global:mockClasses
    }

    Context "Happy Path" {
        It "Should find a user and return their attributes" {
            $mockConfig = [PSCustomObject]@{
                Server = "ldap.example.com"
                BaseDN = "dc=example,dc=com"
                BindDN = "cn=admin,dc=example,dc=com"
                BindPassword = "password"
            }

            Mock New-Object {
                if ($TypeName -match "DirectoryEntry") {
                    $mockLdap = [PSCustomObject]@{ }
                    $mockLdap | Add-Member -MemberType ScriptMethod -Name "Dispose" -Value {} -PassThru
                    return $mockLdap
                }

                if ($TypeName -match "DirectorySearcher") {
                    return [MockDirectorySearcher]::new()
                }
            } -ModuleName LDAPAuth

            $result = Search-LDAPUser -Username "testuser" -Config $mockConfig

            $result.Found | Should -Be $true
            $result.DN | Should -Be "uid=testuser,dc=example,dc=com"
            $result.DisplayName | Should -Be "Test User"
            $result.Email | Should -Be "test@example.com"
            $result.Groups -contains "Group1" | Should -Be $true
        }
    }

    Context "Error Handling" {
        It "Should return found false if FindOne returns null" {
            $mockConfig = [PSCustomObject]@{
                Server = "ldap.example.com"
                BaseDN = "dc=example,dc=com"
            }

            Mock New-Object {
                if ($TypeName -match "DirectoryEntry") {
                    $mockLdap = [PSCustomObject]@{ }
                    $mockLdap | Add-Member -MemberType ScriptMethod -Name "Dispose" -Value {} -PassThru
                    return $mockLdap
                }

                if ($TypeName -match "DirectorySearcher") {
                    return [MockDirectorySearcherNull]::new()
                }
            } -ModuleName LDAPAuth

            $result = Search-LDAPUser -Username "missinguser" -Config $mockConfig

            $result.Found | Should -Be $false
        }

        It "Should handle exceptions during search" {
            $mockConfig = [PSCustomObject]@{
                Server = "ldap.example.com"
                BaseDN = "dc=example,dc=com"
            }

            Mock New-Object {
                throw [System.Exception]::new("Search failed")
            } -ModuleName LDAPAuth

            $result = Search-LDAPUser -Username "testuser" -Config $mockConfig

            $result.Found | Should -Be $false
            $result.Error | Should -Be "Search failed"
        }

        It "Should catch connection exceptions during search" {
            $mockConfig = [PSCustomObject]@{
                Server = "ldap.example.com"
                BaseDN = "dc=example,dc=com"
            }

            Mock New-Object {
                if ($TypeName -match "DirectoryEntry") {
                    throw "LDAP server unreachable"
                }
            } -ModuleName LDAPAuth

            $result = Search-LDAPUser -Username "testuser" -Config $mockConfig

            $result.Found | Should -Be $false
            $result.Error | Should -Match "LDAP server unreachable"
        }
    }
}
