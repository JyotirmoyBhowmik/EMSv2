function global:Invoke-PGQuery {}
function global:Write-EMSLog {}

. ./PowerShellEndPointv2/Modules/Database/EMS.DB.Users.psm1

Import-Module Pester

Describe "Save-ScanResult" {
    Context "When saving a scan result is successful" {
        It "Returns the scan_id from the database" {
            Mock Invoke-PGQuery -MockWith { return @{ scan_id = 42 } }

            $fakeScanData = @{
                Hostname = "test-host"
                IPAddress = "192.168.1.1"
                HealthScore = 95
                ExecutionTimeSeconds = 120
                Diagnostics = @(
                    @{ Severity = 'Critical' },
                    @{ Severity = 'Warning' },
                    @{ Severity = 'Warning' },
                    @{ Severity = 'Info' }
                )
                ScanTimestamp = "2023-01-01T12:00:00Z"
            }

            $result = Save-ScanResult -ScanData $fakeScanData -InitiatedBy 1

            $result | Should -Be 42
            Assert-MockCalled Invoke-PGQuery -Times 1
        }
    }

    Context "When saving a scan result fails" {
        It "Logs the error and throws" {
            Mock Invoke-PGQuery -MockWith { throw "db error" }
            Mock Write-EMSLog -MockWith {}

            $fakeScanData = @{
                Hostname = "test-host"
                IPAddress = "192.168.1.1"
                HealthScore = 95
                ExecutionTimeSeconds = 120
                Diagnostics = @()
            }

            { Save-ScanResult -ScanData $fakeScanData -InitiatedBy 1 } | Should -Throw
            Assert-MockCalled Write-EMSLog -Times 1 -ParameterFilter { $Severity -eq 'Error' }
        }
    }
}
Invoke-Pester ./test_pester.ps1
