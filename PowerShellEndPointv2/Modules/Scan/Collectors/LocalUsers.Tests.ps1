$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
Import-Module "$here\$sut" -Force

Describe "Invoke-LocalUsersCollection" {
    Context "When using CIM Session" {
        It "Collects local users successfully using Get-CimInstance" {
            # Mock Get-CimInstance
            Mock Get-CimInstance {
                return @(
                    [PSCustomObject]@{ Name = 'Administrator'; Disabled = $false; PasswordExpires = $true },
                    [PSCustomObject]@{ Name = 'Guest'; Disabled = $true; PasswordExpires = $false },
                    [PSCustomObject]@{ Name = 'User1'; Disabled = $false; PasswordExpires = $false }
                )
            }

            $mockSession = [PSCustomObject]@{
                Protocol = 'CIM'
                Session  = 'MockCimSession'
            }

            $scanId = [Guid]::NewGuid()
            $result = Invoke-LocalUsersCollection -Session $mockSession -ComputerName 'TestComputer' -ScanId $scanId

            $result.Success | Should -Be $true
            $result.ScanId | Should -Be $scanId
            $result.Metrics.Count | Should -Be 1
            $metric = $result.Metrics[0]

            $metric.computer_name | Should -Be 'TestComputer'
            $metric.total_users | Should -Be 3
            $metric.enabled_users | Should -Be 2
            $metric.disabled_users | Should -Be 1
            $metric.guest_enabled | Should -Be $false
            $metric.password_never_expires_count | Should -Be 2

            Assert-MockCalled Get-CimInstance -Times 1 -Exactly
        }
    }

    Context "When using WMI" {
        It "Collects local users successfully using Get-WmiObject" {
            # Mock Get-WmiObject
            Mock Get-WmiObject {
                return @(
                    [PSCustomObject]@{ Name = 'Administrator'; Disabled = $false; PasswordExpires = $true },
                    [PSCustomObject]@{ Name = 'Guest'; Disabled = $false; PasswordExpires = $true }
                )
            }

            $mockSession = [PSCustomObject]@{
                Protocol = 'DCOM'
                Session  = $null
            }

            $result = Invoke-LocalUsersCollection -Session $mockSession -ComputerName 'TestComputer' -ScanId ([Guid]::NewGuid())

            $result.Success | Should -Be $true
            $result.Metrics.Count | Should -Be 1
            $metric = $result.Metrics[0]

            $metric.total_users | Should -Be 2
            $metric.enabled_users | Should -Be 2
            $metric.disabled_users | Should -Be 0
            $metric.guest_enabled | Should -Be $true

            Assert-MockCalled Get-WmiObject -Times 1 -Exactly
        }
    }

    Context "When an exception occurs" {
        It "Returns Success = false and populates Errors" {
            Mock Get-CimInstance {
                throw "Access Denied"
            }

            $mockSession = [PSCustomObject]@{
                Protocol = 'CIM'
                Session  = 'MockCimSession'
            }

            $result = Invoke-LocalUsersCollection -Session $mockSession -ComputerName 'TestComputer' -ScanId ([Guid]::NewGuid())

            $result.Success | Should -Be $false
            $result.Errors.Count | Should -Be 1
            $result.Errors[0] | Should -Match "Access Denied"
        }
    }

    Context "When Guest user is not present" {
        It "Sets guest_enabled to false" {
            Mock Get-CimInstance {
                return @(
                    [PSCustomObject]@{ Name = 'Administrator'; Disabled = $false; PasswordExpires = $true }
                )
            }

            $mockSession = [PSCustomObject]@{
                Protocol = 'CIM'
                Session  = 'MockCimSession'
            }

            $result = Invoke-LocalUsersCollection -Session $mockSession -ComputerName 'TestComputer' -ScanId ([Guid]::NewGuid())

            $result.Success | Should -Be $true
            $result.Metrics[0].guest_enabled | Should -Be $false
        }
    }
}
