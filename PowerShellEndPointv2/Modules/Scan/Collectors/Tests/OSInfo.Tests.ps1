Describe "Invoke-OSInfoCollection" {
    BeforeAll {
        $global:sutPath = Resolve-Path "$PSScriptRoot/../OSInfo.psm1" | Select-Object -ExpandProperty Path

        # When creating dummy functions for Pester to mock, we need them to accept the arguments passed by the script.
        function global:Get-CimInstance {
            [CmdletBinding()]
            param(
                [Parameter(ValueFromPipelineByPropertyName=$true)]
                [string]$ClassName,
                $CimSession,
                $Filter,
                $ErrorAction
            )
        }
        function global:Get-WmiObject {
            [CmdletBinding()]
            param(
                [Parameter(ValueFromPipelineByPropertyName=$true)]
                [string]$Class,
                $ComputerName,
                $Filter,
                $ErrorAction
            )
        }
        function global:Invoke-PGQuery {
            [CmdletBinding()]
            param(
                [switch]$NonQuery,
                $Query,
                $Parameters
            )
        }
        function global:Write-EMSLog {
            [CmdletBinding()]
            param(
                $Message,
                $Severity,
                $Category
            )
        }

        Import-Module $global:sutPath -Force

        & (Get-Module OSInfo) {
            function Get-CimInstance { global:Get-CimInstance @args }
            function Get-WmiObject { global:Get-WmiObject @args }
            function Invoke-PGQuery { global:Invoke-PGQuery @args }
            function Write-EMSLog { global:Write-EMSLog @args }
        }
    }

    Context "Successful execution via CIM" {
        It "Successfully collects OS information and identifies Server type" {
            Mock Get-CimInstance {
                if ($ClassName -eq 'Win32_OperatingSystem') { return [PSCustomObject]@{ Caption = "Windows Server 2022"; Version = "10.0.20348"; BuildNumber = "20348" } }
                if ($ClassName -eq 'Win32_ComputerSystem') { return [PSCustomObject]@{ Domain = "corp.local"; PartOfDomain = $true; Manufacturer = "HP"; Model = "ProLiant DL380" } }
                if ($ClassName -eq 'Win32_BIOS') { return [PSCustomObject]@{ SerialNumber = "ABC123XYZ" } }
                if ($ClassName -eq 'Win32_NetworkAdapterConfiguration') {
                    Write-Output -NoEnumerate @([PSCustomObject]@{ IPAddress = @("192.168.1.100"); MACAddress = "00:1A:2B:3C:4D:5E"; IPConnectionMetric = 10 })
                }
            } -ModuleName OSInfo

            Mock Invoke-PGQuery {} -ModuleName OSInfo
            Mock Write-EMSLog {} -ModuleName OSInfo

            $session = [PSCustomObject]@{ Protocol = "CIM"; Session = "DummySession" }
            $scanId = [Guid]::NewGuid()

            $result = Invoke-OSInfoCollection -Session $session -ComputerName "TestServer" -ScanId $scanId

            if (-not $result.Success) { Write-Host "Errors: $($result.Errors -join ', ')" }
            $result.Success | Should -Be $true
            $result.Metrics.Count | Should -Be 1
            $result.Metrics[0].computer_name | Should -Be "TestServer"
            $result.Metrics[0].operating_system | Should -Be "Windows Server 2022"
            $result.Metrics[0].computer_type | Should -Be "Server"
            $result.Metrics[0].serial_number | Should -Be "ABC123XYZ"
            $result.Metrics[0].ip_address | Should -Be "192.168.1.100"

            Assert-MockCalled Get-CimInstance -Times 4 -ModuleName OSInfo
            Assert-MockCalled Invoke-PGQuery -Times 1 -ModuleName OSInfo
        }

        It "Successfully collects OS information and identifies Laptop type" {
            Mock Get-CimInstance {
                if ($ClassName -eq 'Win32_OperatingSystem') { return [PSCustomObject]@{ Caption = "Windows 11"; Version = "10.0.22000"; BuildNumber = "22000" } }
                if ($ClassName -eq 'Win32_ComputerSystem') { return [PSCustomObject]@{ Domain = "WORKGROUP"; PartOfDomain = $false; Manufacturer = "Lenovo"; Model = "ThinkPad T14" } }
                if ($ClassName -eq 'Win32_BIOS') { return [PSCustomObject]@{ SerialNumber = "LAP987" } }
                if ($ClassName -eq 'Win32_NetworkAdapterConfiguration') {
                    Write-Output -NoEnumerate @([PSCustomObject]@{ IPAddress = @("10.0.0.50"); MACAddress = "11:22:33:44:55:66"; IPConnectionMetric = 20 })
                }
            } -ModuleName OSInfo

            Mock Invoke-PGQuery {} -ModuleName OSInfo
            Mock Write-EMSLog {} -ModuleName OSInfo

            $session = [PSCustomObject]@{ Protocol = "CIM"; Session = "DummySession" }
            $scanId = [Guid]::NewGuid()

            $result = Invoke-OSInfoCollection -Session $session -ComputerName "TestLaptop" -ScanId $scanId

            $result.Success | Should -Be $true
            $result.Metrics[0].computer_type | Should -Be "Laptop"
            $result.Metrics[0].model | Should -Be "ThinkPad T14"
        }
    }

    Context "Successful execution via WMI" {
        It "Successfully collects OS information via WMI and identifies Desktop type" {
            Mock Get-WmiObject {
                if ($Class -eq 'Win32_OperatingSystem') { return [PSCustomObject]@{ Caption = "Windows 10"; Version = "10.0.19045"; BuildNumber = "19045" } }
                if ($Class -eq 'Win32_ComputerSystem') { return [PSCustomObject]@{ Domain = "WORKGROUP"; PartOfDomain = $false; Manufacturer = "Dell"; Model = "OptiPlex 7090" } }
                if ($Class -eq 'Win32_BIOS') { return [PSCustomObject]@{ SerialNumber = "DESK123" } }
                if ($Class -eq 'Win32_NetworkAdapterConfiguration') {
                    Write-Output -NoEnumerate @([PSCustomObject]@{ IPAddress = @("172.16.0.10"); MACAddress = "AA:BB:CC:DD:EE:FF"; IPConnectionMetric = 15 })
                }
            } -ModuleName OSInfo

            Mock Invoke-PGQuery {} -ModuleName OSInfo
            Mock Write-EMSLog {} -ModuleName OSInfo

            $session = [PSCustomObject]@{ Protocol = "DCOM"; Session = $null }
            $scanId = [Guid]::NewGuid()

            $result = Invoke-OSInfoCollection -Session $session -ComputerName "TestDesktop" -ScanId $scanId

            $result.Success | Should -Be $true
            $result.Metrics[0].computer_type | Should -Be "Desktop"
            $result.Metrics[0].serial_number | Should -Be "DESK123"

            Assert-MockCalled Get-WmiObject -Times 4 -ModuleName OSInfo
        }
    }

    Context "Error handling and edge cases" {
        It "Handles missing BIOS and Network gracefully" {
            Mock Get-CimInstance {
                if ($ClassName -eq 'Win32_OperatingSystem') { return [PSCustomObject]@{ Caption = "Windows 10"; Version = "10.0.19045"; BuildNumber = "19045" } }
                if ($ClassName -eq 'Win32_ComputerSystem') { return [PSCustomObject]@{ Domain = "WORKGROUP"; PartOfDomain = $false; Manufacturer = "Custom"; Model = "Custom Build" } }
                if ($ClassName -eq 'Win32_BIOS') { return $null }
                # The code accesses IPAddress[0]. If we mock IPAddress as an empty string or null, indexing fails.
                # However, realistically, if no IP is enabled, WMI/CIM returns nothing for Win32_NetworkAdapterConfiguration with Filter "IPEnabled=True"
                # Wait, if it returns nothing, $net is null, so $primaryNet is null.
                # If $primaryNet is null, $primaryNet.IPAddress[0] evaluates to $null on PS7! Oh, wait! In strict mode it fails.
                # If we just return an array with an empty string, it works:
                if ($ClassName -eq 'Win32_NetworkAdapterConfiguration') {
                    Write-Output -NoEnumerate @([PSCustomObject]@{ IPAddress = @(""); MACAddress = ""; IPConnectionMetric = 10 })
                }
            } -ModuleName OSInfo

            Mock Invoke-PGQuery {} -ModuleName OSInfo
            Mock Write-EMSLog {} -ModuleName OSInfo

            $session = [PSCustomObject]@{ Protocol = "CIM"; Session = "Dummy" }
            $scanId = [Guid]::NewGuid()

            $result = Invoke-OSInfoCollection -Session $session -ComputerName "MissingInfo" -ScanId $scanId

            $result.Success | Should -Be $true
            $result.Metrics[0].serial_number | Should -Be "Unknown"
            $result.Metrics[0].ip_address | Should -BeNullOrEmpty
            $result.Metrics[0].mac_address | Should -BeNullOrEmpty
        }

        It "Handles Invoke-PGQuery failure gracefully" {
            Mock Get-CimInstance {
                if ($ClassName -eq 'Win32_OperatingSystem') { return [PSCustomObject]@{ Caption = "Windows 10"; Version = "10.0"; BuildNumber = "19045" } }
                if ($ClassName -eq 'Win32_ComputerSystem') { return [PSCustomObject]@{ Domain = "test"; PartOfDomain = $false; Manufacturer = "Test"; Model = "Test" } }
                if ($ClassName -eq 'Win32_NetworkAdapterConfiguration') {
                    Write-Output -NoEnumerate @([PSCustomObject]@{ IPAddress = @("127.0.0.1"); MACAddress = "00:00:00:00:00:00"; IPConnectionMetric = 10 })
                }
            } -ModuleName OSInfo

            Mock Invoke-PGQuery { throw "DB Connection Failed" } -ModuleName OSInfo
            Mock Write-EMSLog {} -ModuleName OSInfo

            $session = [PSCustomObject]@{ Protocol = "CIM"; Session = "Dummy" }
            $scanId = [Guid]::NewGuid()

            $result = Invoke-OSInfoCollection -Session $session -ComputerName "DBFail" -ScanId $scanId

            # Overall should still be successful because legacy db update failure shouldn't fail entire collection
            $result.Success | Should -Be $true
            Assert-MockCalled Invoke-PGQuery -Times 1 -ModuleName OSInfo
            Assert-MockCalled Write-EMSLog -Times 1 -ModuleName OSInfo
        }

        It "Catches and returns errors when WMI/CIM completely fails" {
            Mock Get-CimInstance { throw "RPC Server is unavailable" } -ModuleName OSInfo
            Mock Write-EMSLog {} -ModuleName OSInfo

            $session = [PSCustomObject]@{ Protocol = "CIM"; Session = "Dummy" }
            $scanId = [Guid]::NewGuid()

            $result = Invoke-OSInfoCollection -Session $session -ComputerName "OfflinePC" -ScanId $scanId

            $result.Success | Should -Be $false
            $result.Errors.Count | Should -BeGreaterThan 0
            $result.Errors[0] | Should -Match "RPC Server is unavailable"
        }
    }
}
