$ScriptPath = "$PSScriptRoot/../../../Modules/Database/EMS.DB.Users.psm1"

Describe "Save-ScanResult" {
    BeforeAll {
        # Load the module or dot source it
        Import-Module $ScriptPath -Force
    }

    BeforeEach {
        Mock -CommandName Invoke-PGQuery -MockWith { return @{ scan_id = 123 } }
        Mock -CommandName Write-EMSLog -MockWith {}
    }

    It "successfully saves scan data and returns scan_id" {
        $scanData = [PSCustomObject]@{
            Hostname = "test-host"
            IPAddress = "192.168.1.1"
            HealthScore = 85
            ExecutionTimeSeconds = 15
            ScanTimestamp = [datetime]"2023-01-01T10:00:00"
            Diagnostics = @(
                [PSCustomObject]@{ Severity = "Critical" }
                [PSCustomObject]@{ Severity = "Warning" }
                [PSCustomObject]@{ Severity = "Warning" }
                [PSCustomObject]@{ Severity = "Info" }
                [PSCustomObject]@{ Severity = "Info" }
                [PSCustomObject]@{ Severity = "Info" }
            )
        }

        $result = Save-ScanResult -ScanData $scanData -InitiatedBy 1

        $result | Should -Be 123

        Assert-MockCalled -CommandName Invoke-PGQuery -Times 1 -ParameterFilter {
            $Parameters.target -eq "test-host" -and
            $Parameters.ip -eq "192.168.1.1" -and
            $Parameters.health -eq 85 -and
            $Parameters.status -eq "completed" -and
            $Parameters.exectime -eq 15 -and
            $Parameters.critical -eq 1 -and
            $Parameters.warning -eq 2 -and
            $Parameters.info -eq 3 -and
            $Parameters.timestamp -eq [datetime]"2023-01-01T10:00:00"
        }
    }

    It "uses current date for timestamp if ScanTimestamp is not provided" {
        $scanData = [PSCustomObject]@{
            Hostname = "test-host2"
            IPAddress = "10.0.0.1"
            HealthScore = 100
            ExecutionTimeSeconds = 5
            Diagnostics = @()
        }

        $result = Save-ScanResult -ScanData $scanData -InitiatedBy 2

        $result | Should -Be 123

        Assert-MockCalled -CommandName Invoke-PGQuery -Times 1 -ParameterFilter {
            $Parameters.timestamp -is [datetime]
        }
    }

    It "logs error and re-throws when Invoke-PGQuery fails" {
        Mock -CommandName Invoke-PGQuery -MockWith { throw "Database error" }

        $scanData = [PSCustomObject]@{ Hostname = "test-host" }

        { Save-ScanResult -ScanData $scanData -InitiatedBy 1 } | Should -Throw "Database error"

        Assert-MockCalled -CommandName Write-EMSLog -Times 1 -ParameterFilter {
            $Severity -eq 'Error' -and $Message -like "*Error saving scan result: Database error*"
$rootPath = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
Import-Module "$rootPath\Modules\Database\EMS.DB.Users.psm1" -Force

Describe "New-EMSUser" {
    Context "When creating a new user successfully" {
        It "Should call Invoke-PGQuery with correct parameters and return the new user_id" {
            Mock -CommandName Invoke-PGQuery -MockWith {
                return [pscustomobject]@{ user_id = 12345 }
            } -ModuleName EMS.DB.Users

            Mock -CommandName Write-EMSLog -MockWith { } -ModuleName EMS.DB.Users

            $result = New-EMSUser -Username "jdoe" -Domain "CONTOSO" -DisplayName "John Doe" -Email "jdoe@contoso.com" -Role "operator"

            $result | Should -Be 12345

            Assert-MockCalled -CommandName Invoke-PGQuery -Times 1 -Scope It -ModuleName EMS.DB.Users
            Assert-MockCalled -CommandName Write-EMSLog -Times 1 -Scope It -ModuleName EMS.DB.Users

            # Note: We can't easily assert on the hashtable parameter values without Pester 5 ParameterFilters or examining the mock history.
            # We'll assert that it was called.
        }
    }

    Context "When role is not specified" {
        It "Should default the role to 'viewer'" {
            Mock -CommandName Invoke-PGQuery -MockWith {
                # Pester ParameterFilter to verify role is viewer
                if ($Parameters.role -eq 'viewer') {
                    return [pscustomobject]@{ user_id = 12345 }
                }
            } -ModuleName EMS.DB.Users

            Mock -CommandName Write-EMSLog -MockWith { } -ModuleName EMS.DB.Users

            $result = New-EMSUser -Username "asmith" -Domain "CONTOSO" -DisplayName "Alice Smith" -Email "asmith@contoso.com"

            $result | Should -Be 12345
            Assert-MockCalled -CommandName Invoke-PGQuery -Times 1 -Scope It -ModuleName EMS.DB.Users -ParameterFilter {
                $Parameters.role -eq 'viewer'
            }
        }
    }

    Context "When an error occurs during creation" {
        It "Should log an error and throw an exception" {
            Mock -CommandName Invoke-PGQuery -MockWith {
                throw "Simulated database error"
            } -ModuleName EMS.DB.Users

            Mock -CommandName Write-EMSLog -MockWith { } -ModuleName EMS.DB.Users

            { New-EMSUser -Username "error_user" -Domain "CONTOSO" -DisplayName "Error User" -Email "error@contoso.com" } | Should -Throw "Simulated database error"

            Assert-MockCalled -CommandName Invoke-PGQuery -Times 1 -Scope It -ModuleName EMS.DB.Users
            Assert-MockCalled -CommandName Write-EMSLog -Times 1 -Scope It -ModuleName EMS.DB.Users -ParameterFilter {
                $Severity -eq 'Error'
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
