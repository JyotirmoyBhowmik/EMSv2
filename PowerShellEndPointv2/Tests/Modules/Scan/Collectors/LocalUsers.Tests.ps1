$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

Describe "Invoke-LocalUsersCollection" {
    BeforeAll {
        $modulePath = Resolve-Path "$PSScriptRoot/../../../../Modules/Scan/Collectors/LocalUsers.psm1" -ErrorAction SilentlyContinue
        Import-Module $modulePath -Force

        # Mock commands globally to prevent CommandNotFoundException if not running on Windows
        function global:Get-CimInstance {}
        function global:Get-WmiObject {}
    }

    Context "When using CIM session (happy path)" {
        It "should collect local user metrics successfully" {
            $mockSession = @{ Protocol = 'CIM'; Session = 'MockSession' }
            $mockScanId = [Guid]::NewGuid()
            $mockComputerName = 'TEST-PC'

            Mock Get-CimInstance {
                [PSCustomObject]@{ Name = 'Admin'; Disabled = $false; LocalAccount = $true; PasswordExpires = $false }
                [PSCustomObject]@{ Name = 'User1'; Disabled = $true; LocalAccount = $true; PasswordExpires = $true }
                [PSCustomObject]@{ Name = 'Guest'; Disabled = $true; LocalAccount = $true; PasswordExpires = $false }
            } -ModuleName LocalUsers

            $result = Invoke-LocalUsersCollection -Session $mockSession -ComputerName $mockComputerName -ScanId $mockScanId

            $result.Success | Should -Be $true
            $metrics = $result.Metrics[0]
            $metrics.total_users | Should -Be 3
            $metrics.enabled_users | Should -Be 1
            $metrics.disabled_users | Should -Be 2
            $metrics.guest_enabled | Should -Be $false
            $metrics.password_never_expires_count | Should -Be 2

            Assert-MockCalled Get-CimInstance -Times 1 -Exactly -ModuleName LocalUsers
        }
    }

    Context "When using WMI session (happy path)" {
        It "should collect local user metrics successfully via WMI" {
            $mockSession = @{ Protocol = 'DCOM' } # Non-CIM
            $mockScanId = [Guid]::NewGuid()
            $mockComputerName = 'TEST-PC'

            Mock Get-WmiObject {
                [PSCustomObject]@{ Name = 'Admin'; Disabled = $false; LocalAccount = $true; PasswordExpires = $false }
                [PSCustomObject]@{ Name = 'User1'; Disabled = $true; LocalAccount = $true; PasswordExpires = $true }
                [PSCustomObject]@{ Name = 'Guest'; Disabled = $false; LocalAccount = $true; PasswordExpires = $false }
            } -ModuleName LocalUsers

            $result = Invoke-LocalUsersCollection -Session $mockSession -ComputerName $mockComputerName -ScanId $mockScanId

            $result.Success | Should -Be $true

            $metrics = $result.Metrics[0]
            $metrics.total_users | Should -Be 3
            $metrics.enabled_users | Should -Be 2
            $metrics.disabled_users | Should -Be 1
            $metrics.guest_enabled | Should -Be $true
            $metrics.password_never_expires_count | Should -Be 2

            Assert-MockCalled Get-WmiObject -Times 1 -Exactly -ModuleName LocalUsers
        }
    }

    Context "When exception occurs" {
        It "should catch the exception and return Success as false" {
            $mockSession = @{ Protocol = 'CIM'; Session = 'MockSession' }
            $mockScanId = [Guid]::NewGuid()
            $mockComputerName = 'TEST-PC'

            Mock Get-CimInstance {
                throw "WMI provider failure"
            } -ModuleName LocalUsers

            $result = Invoke-LocalUsersCollection -Session $mockSession -ComputerName $mockComputerName -ScanId $mockScanId

            $result.Success | Should -Be $false
            $result.Metrics.Count | Should -Be 0
            $result.Errors.Count | Should -Be 1
            $result.Errors[0] | Should -Match "WMI provider failure"

            Assert-MockCalled Get-CimInstance -Times 1 -Exactly -ModuleName LocalUsers
        }
    }
}
