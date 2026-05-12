# Set strict mode off for mocking
Set-StrictMode -Off

function global:Invoke-PGQuery {}
function global:Write-EMSLog {}

Import-Module Pester

Describe "Save-ScanResult" {
    BeforeAll {
        $modulePath = "$PSScriptRoot/../../../Modules/Database/EMS.DB.Users.psm1"
        $scriptContent = Get-Content $modulePath -Raw
        $scriptContent = $scriptContent -replace '(?m)^Export-ModuleMember.*', ''
        Invoke-Expression $scriptContent
    }

    Context "When saving a scan result is successful" {
        It "Returns the scan_id from the database and passes correct parameters" {
            $global:passedParamsObj = $null
            Mock Invoke-PGQuery -MockWith {
                param($Query, $Parameters)
                $global:passedParamsObj = $Parameters
                return [pscustomobject]@{ scan_id = 42 }
            }

            $fakeScanData = [pscustomobject]@{
                Hostname = "test-host"
                IPAddress = "192.168.1.1"
                HealthScore = 95
                ExecutionTimeSeconds = 120
                Diagnostics = @(
                    [pscustomobject]@{ Severity = 'Critical' },
                    [pscustomobject]@{ Severity = 'Warning' },
                    [pscustomobject]@{ Severity = 'Warning' },
                    [pscustomobject]@{ Severity = 'Info' }
                )
                ScanTimestamp = "2023-01-01T12:00:00Z"
            }

            $result = Save-ScanResult -ScanData $fakeScanData -InitiatedBy 1

            $result | Should -Be 42
            Assert-MockCalled Invoke-PGQuery -Times 1

            $global:passedParamsObj.target | Should -Be "test-host"
            $global:passedParamsObj.ip | Should -Be "192.168.1.1"
            $global:passedParamsObj.health | Should -Be 95
            $global:passedParamsObj.status | Should -Be "completed"
            $global:passedParamsObj.exectime | Should -Be 120
            $global:passedParamsObj.critical | Should -Be 1
            $global:passedParamsObj.warning | Should -Be 2
            $global:passedParamsObj.info | Should -Be 1
            $global:passedParamsObj.timestamp | Should -Be "2023-01-01T12:00:00Z"
        }

        It "Uses current date if ScanTimestamp is not provided" {
            $global:passedParamsObj = $null
            Mock Invoke-PGQuery -MockWith {
                param($Query, $Parameters)
                $global:passedParamsObj = $Parameters
                return [pscustomobject]@{ scan_id = 43 }
            }

            $fakeScanData = [pscustomobject]@{
                Hostname = "test-host2"
                IPAddress = "192.168.1.2"
                HealthScore = 100
                ExecutionTimeSeconds = 60
                Diagnostics = @()
            }

            $result = Save-ScanResult -ScanData $fakeScanData -InitiatedBy 1

            $result | Should -Be 43
            Assert-MockCalled Invoke-PGQuery -Times 1
            $global:passedParamsObj.timestamp | Should -BeOfType [DateTime]

            # Additional assertions to make sure defaults are handled
            $global:passedParamsObj.critical | Should -Be 0
            $global:passedParamsObj.warning | Should -Be 0
            $global:passedParamsObj.info | Should -Be 0
        }
    }

    Context "When saving a scan result fails" {
        It "Logs the error and throws" {
            Mock Invoke-PGQuery -MockWith { throw "db error" }

            $global:loggedSeverity = $null
            $global:loggedMessage = $null
            Mock Write-EMSLog -MockWith {
                param($Message, $Severity)
                $global:loggedSeverity = $Severity
                $global:loggedMessage = $Message
            }

            $fakeScanData = [pscustomobject]@{
                Hostname = "test-host"
                IPAddress = "192.168.1.1"
                HealthScore = 95
                ExecutionTimeSeconds = 120
                Diagnostics = @()
            }

            { Save-ScanResult -ScanData $fakeScanData -InitiatedBy 1 } | Should -Throw
            Assert-MockCalled Write-EMSLog -Times 1
            $global:loggedSeverity | Should -Be 'Error'
            $global:loggedMessage | Should -Match "Error saving scan result"
        }
    }
}
