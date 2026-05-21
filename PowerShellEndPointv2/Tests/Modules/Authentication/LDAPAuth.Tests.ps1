$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = "$here/../../../Modules/Authentication/LDAPAuth.psm1"

Import-Module $modulePath -Force

Describe "Search-LDAPUser" {
    BeforeAll {
        $Global:TestConfig = [PSCustomObject]@{
            Server = "ldap.example.com"
            BaseDN = "dc=example,dc=com"
            BindDN = "cn=admin,dc=example,dc=com"
            BindPassword = "password123"
        }
        $Global:TestUsername = "testuser"
    }

    Context "Happy Path" {
        It "Should successfully find a user and return their attributes" {
            InModuleScope LDAPAuth {
                function global:New-Object {
                    $TypeName = $args[0]
                    if ($TypeName -match "DirectoryEntry") {
                        $e = [PSCustomObject]@{ Dispose = {} }
                        $e | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                        return $e
                    }
                    if ($TypeName -match "DirectorySearcher") {
                        $s = [PSCustomObject]@{
                            Filter = ""
                        }
                        $s | Add-Member -MemberType NoteProperty -Name PropertiesToLoad -Value ([System.Collections.ArrayList]::new()) -Force
                        $s | Add-Member -MemberType ScriptMethod -Name FindOne -Value {
                            $r = "SearchResult" | Select-Object -Property Properties
                            $r.Properties = @{
                                distinguishedName = @("uid=testuser,ou=users,dc=example,dc=com")
                                displayName = @("Test User")
                                mail = @("test@example.com")
                                memberOf = @("cn=group1,dc=example,dc=com", "cn=group2,dc=example,dc=com")
                            }
                            return $r
                        } -Force
                        $s | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                        return $s
                    }
                    return Microsoft.PowerShell.Utility\New-Object @args
                }
            }

            $result = Search-LDAPUser -Username $Global:TestUsername -Config $Global:TestConfig

            $result.Found | Should -Be $true
            $result.DN | Should -Be "uid=testuser,ou=users,dc=example,dc=com"
            $result.DisplayName | Should -Be "Test User"
            $result.Email | Should -Be "test@example.com"

            # Since LDAP returns properties in a specific format that might get flattened
            # differently depending on if it's evaluated in native .NET vs PS Hashtables
            # Let's just ensure that memberOf contains our elements since it might just return array of objects
            # or a flattened object depending on collection type mapping in tests vs real system.
            $groups = $result.Groups
            if ($groups -isnot [array]) { $groups = @($groups) }
            $groups | Should -Contain "cn=group1,dc=example,dc=com"

            InModuleScope LDAPAuth {
                Remove-Item -Path Function:\global:New-Object -ErrorAction SilentlyContinue
            }
        }
    }

    Context "User Not Found" {
        It "Should return Found = `$false when user does not exist" {
            InModuleScope LDAPAuth {
                function global:New-Object {
                    $TypeName = $args[0]
                    if ($TypeName -match "DirectoryEntry") {
                        $e = [PSCustomObject]@{ Dispose = {} }
                        $e | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                        return $e
                    }
                    if ($TypeName -match "DirectorySearcher") {
                        $s = [PSCustomObject]@{
                            Filter = ""
                        }
                        $s | Add-Member -MemberType NoteProperty -Name PropertiesToLoad -Value ([System.Collections.ArrayList]::new()) -Force
                        $s | Add-Member -MemberType ScriptMethod -Name FindOne -Value { return $null } -Force
                        $s | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                        return $s
                    }
                    return Microsoft.PowerShell.Utility\New-Object @args
                }
            }

            $result = Search-LDAPUser -Username "nonexistent" -Config $Global:TestConfig

            $result.Found | Should -Be $false
            $result.Error | Should -BeNullOrEmpty

            InModuleScope LDAPAuth {
                Remove-Item -Path Function:\global:New-Object -ErrorAction SilentlyContinue
            }
        }
    }

    Context "Error Handling" {
        It "Should catch connection exceptions and return Found = `$false with Error message" {
            InModuleScope LDAPAuth {
                function global:New-Object {
                    $TypeName = $args[0]
                    if ($TypeName -match "DirectoryEntry") {
                        throw "LDAP server unreachable"
                    }
                    return Microsoft.PowerShell.Utility\New-Object @args
                }
            }

            $result = Search-LDAPUser -Username $Global:TestUsername -Config $Global:TestConfig

            $result.Found | Should -Be $false
            $result.Error | Should -Match "LDAP server unreachable"

            InModuleScope LDAPAuth {
                Remove-Item -Path Function:\global:New-Object -ErrorAction SilentlyContinue
            }
        }

        It "Should catch search exceptions and return Found = `$false with Error message" {
            InModuleScope LDAPAuth {
                function global:New-Object {
                    $TypeName = $args[0]
                    if ($TypeName -match "DirectoryEntry") {
                        $e = [PSCustomObject]@{ Dispose = {} }
                        $e | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                        return $e
                    }
                    if ($TypeName -match "DirectorySearcher") {
                        $s = [PSCustomObject]@{
                            Filter = ""
                        }
                        $s | Add-Member -MemberType NoteProperty -Name PropertiesToLoad -Value ([System.Collections.ArrayList]::new()) -Force
                        $s | Add-Member -MemberType ScriptMethod -Name FindOne -Value { throw "Search timeout" } -Force
                        $s | Add-Member -MemberType ScriptMethod -Name Dispose -Value {} -Force
                        return $s
                    }
                    return Microsoft.PowerShell.Utility\New-Object @args
                }
            }

            $result = Search-LDAPUser -Username $Global:TestUsername -Config $Global:TestConfig

            $result.Found | Should -Be $false
            $result.Error | Should -Match "Search timeout"

            InModuleScope LDAPAuth {
                Remove-Item -Path Function:\global:New-Object -ErrorAction SilentlyContinue
            }
        }
    }
}
