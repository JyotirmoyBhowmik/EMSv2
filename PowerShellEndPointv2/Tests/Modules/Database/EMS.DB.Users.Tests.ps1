# Requires Pester

Describe "Save-ScanResult" {
    BeforeAll {
        # Define empty mocked functions in the global scope so they can be mocked later
        function global:Invoke-PGQuery { param($Query, $Parameters) }
        function global:Write-EMSLog { param($Message, $Severity) }

        # Load the module under test
        $modulePath = "$PSScriptRoot/../../../Modules/Database/EMS.DB.Users.psm1"
        Import-Module $modulePath -Force
    }

    Context "When saving a successful scan result" {
        BeforeEach {
            # Mock Invoke-PGQuery
            Mock Invoke-PGQuery {
                return @{ scan_id = 54321 }
            } -ModuleName EMS.DB.Users

            # Mock Write-EMSLog to do nothing
            Mock Write-EMSLog { } -ModuleName EMS.DB.Users

            $scanData = [PSCustomObject]@{
                Hostname = "TestServer"
                IPAddress = "10.0.0.5"
                HealthScore = 85
                ExecutionTimeSeconds = 45
                Diagnostics = @(
                    [PSCustomObject]@{ Severity = 'Critical' },
                    [PSCustomObject]@{ Severity = 'Warning' },
                    [PSCustomObject]@{ Severity = 'Info' },
                    [PSCustomObject]@{ Severity = 'Info' }
                )
                ScanTimestamp = (Get-Date "2024-05-01 10:00:00")
            }

            $result = Save-ScanResult -ScanData $scanData -InitiatedBy 1
        }

        It "Returns the correct scan_id" {
            $result | Should -Be 54321
        }

        It "Calls Invoke-PGQuery once" {
            Assert-MockCalled Invoke-PGQuery -Times 1 -ModuleName EMS.DB.Users
        }

        It "Passes the correct parameters to the database" {
            Assert-MockCalled Invoke-PGQuery -ModuleName EMS.DB.Users -ParameterFilter {
                $Parameters.target -eq "TestServer" -and
                $Parameters.ip -eq "10.0.0.5" -and
                $Parameters.health -eq 85 -and
                $Parameters.status -eq "completed" -and
                $Parameters.exectime -eq 45 -and
                $Parameters.critical -eq 1 -and
                $Parameters.warning -eq 1 -and
                $Parameters.info -eq 2 -and
                $Parameters.timestamp -eq (Get-Date "2024-05-01 10:00:00")
            }
        }
    }

    Context "When database query fails" {
        BeforeEach {
            Mock Invoke-PGQuery {
                throw "Database connection error"
            } -ModuleName EMS.DB.Users

            Mock Write-EMSLog { } -ModuleName EMS.DB.Users

            $scanData = [PSCustomObject]@{
                Hostname = "FailServer"
                Diagnostics = @()
            }
        }

        It "Throws an error" {
            { Save-ScanResult -ScanData $scanData -InitiatedBy 1 } | Should -Throw
        }

        It "Logs the error" {
            try { Save-ScanResult -ScanData $scanData -InitiatedBy 1 } catch { }
            Assert-MockCalled Write-EMSLog -Times 1 -ModuleName EMS.DB.Users -ParameterFilter {
                $Severity -eq 'Error' -and $Message -match "Error saving scan result:"
            }
        }
    }
}
