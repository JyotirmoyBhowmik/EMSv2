$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$global:sutPath = (Split-Path -Parent $here) + "/BitLocker.psm1"

Describe "Invoke-BitLockerCollection" {
    BeforeAll {
        Import-Module $global:sutPath -Force

        # Define dummy global functions to bypass missing Windows-specific commands
        function global:Get-CimInstance {}
        function global:Get-WmiObject {}

        $mod = Get-Module BitLocker
        if ($null -ne $mod) {
            # Inject into module scope
            & $mod {
                function Get-CimInstance {}
                function Get-WmiObject {}
            }
        }
    }

    Context "When CIM Session is provided" {
        It "Should call Get-CimInstance and correctly process data" {
            $session = @{
                Protocol = "CIM"
                Session = "dummy-cim-session"
            }
            $scanId = [Guid]::NewGuid()

            Mock Get-CimInstance {
                return @(
                    [PSCustomObject]@{
                        DriveLetter = "C:"
                        ProtectionStatus = 1
                        ConversionStatus = 100
                        EncryptionMethod = "AES_256"
                    },
                    [PSCustomObject]@{
                        DriveLetter = "D:"
                        ProtectionStatus = 0
                        ConversionStatus = 0
                        EncryptionMethod = "None"
                    }
                )
            } -ModuleName BitLocker

            $result = Invoke-BitLockerCollection -Session $session -ComputerName "Test-PC" -ScanId $scanId

            Assert-MockCalled Get-CimInstance -ModuleName BitLocker -Times 1 -Exactly

            $result.Success | Should -Be $true
            $result.ScanId | Should -Be $scanId
            $result.Metrics.Count | Should -Be 2

            $result.Metrics[0].drive_letter | Should -Be "C"
            $result.Metrics[0].protection_status | Should -Be "On"
            $result.Metrics[0].encryption_percentage | Should -Be 100
            $result.Metrics[0].encryption_method | Should -Be "AES_256"

            $result.Metrics[1].drive_letter | Should -Be "D"
            $result.Metrics[1].protection_status | Should -Be "Off"
            $result.Metrics[1].encryption_percentage | Should -Be 0
            $result.Metrics[1].encryption_method | Should -Be "None"
        }

        It "Should handle unknown protection status" {
            $session = @{
                Protocol = "CIM"
                Session = "dummy-cim-session"
            }
            $scanId = [Guid]::NewGuid()

            Mock Get-CimInstance {
                return @(
                    [PSCustomObject]@{
                        DriveLetter = "E:"
                        ProtectionStatus = 2
                        ConversionStatus = 50
                        EncryptionMethod = "Unknown"
                    }
                )
            } -ModuleName BitLocker

            $result = Invoke-BitLockerCollection -Session $session -ComputerName "Test-PC" -ScanId $scanId

            $result.Success | Should -Be $true
            $result.Metrics.Count | Should -Be 1
            $result.Metrics[0].protection_status | Should -Be "Unknown"
        }
    }

    Context "When WMI Session is provided" {
        It "Should call Get-WmiObject and process data correctly" {
            $session = @{
                Protocol = "WMI"
                Session = "dummy-wmi-session"
            }
            $scanId = [Guid]::NewGuid()

            Mock Get-WmiObject {
                return @(
                    [PSCustomObject]@{
                        DriveLetter = "C:"
                        ProtectionStatus = 1
                        ConversionStatus = 100
                        EncryptionMethod = "AES_256"
                    }
                )
            } -ModuleName BitLocker

            $result = Invoke-BitLockerCollection -Session $session -ComputerName "Test-PC" -ScanId $scanId

            Assert-MockCalled Get-WmiObject -ModuleName BitLocker -Times 1 -Exactly

            $result.Success | Should -Be $true
            $result.Metrics.Count | Should -Be 1
            $result.Metrics[0].drive_letter | Should -Be "C"
            $result.Metrics[0].protection_status | Should -Be "On"
        }
    }

    Context "When an error occurs" {
        It "Should catch exception and return Success = false" {
            $session = @{
                Protocol = "CIM"
                Session = "dummy-cim-session"
            }
            $scanId = [Guid]::NewGuid()

            Mock Get-CimInstance {
                throw "Access denied"
            } -ModuleName BitLocker

            $result = Invoke-BitLockerCollection -Session $session -ComputerName "Test-PC" -ScanId $scanId

            $result.Success | Should -Be $false
            $result.Errors.Count | Should -Be 1
            $result.Errors[0] | Should -Be "[BitLocker] Access denied"
        }
    }
}
