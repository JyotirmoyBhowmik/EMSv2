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
        }
    }
}
