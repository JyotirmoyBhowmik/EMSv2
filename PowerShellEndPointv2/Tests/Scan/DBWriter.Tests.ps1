BeforeAll {
    $rootPath = "$PSScriptRoot/../.."

    # Provide empty stub definitions for the functions IN THE GLOBAL SCOPE so the module binds them
    function global:Invoke-PGQuery {
        [CmdletBinding()]
        param([string]$Query, [hashtable]$Parameters, [switch]$NonQuery)
    }

    function global:Write-EMSLog {
        [CmdletBinding()]
        param([string]$Message, [string]$Severity, [string]$Category)
    }

    # Load the module
    Import-Module "$rootPath/Modules/Scan/DBWriter.psm1" -Force
}

Describe "Write-MetricsToDatabase" {
    BeforeEach {
        $global:PGQueryCalls = @()
        $global:LogMessages = @()

        # We MUST mock them using `-ModuleName` because `Write-MetricsToDatabase` is inside a module scope.
        Mock -CommandName Invoke-PGQuery -ModuleName DBWriter -MockWith {
            param($Query, $Parameters, $NonQuery)
            $global:PGQueryCalls += @{
                Query = $Query
                Parameters = $Parameters
                NonQuery = $NonQuery
            }
        }

        Mock -CommandName Write-EMSLog -ModuleName DBWriter -MockWith {
            param($Message, $Severity, $Category)
            $global:LogMessages += @{
                Message = $Message
                Severity = $Severity
                Category = $Category
            }
        }
    }

    AfterEach {
        $global:PGQueryCalls = @()
        $global:LogMessages = @()
    }

    It "should do nothing if Metrics is empty or null" {
        try {
            Write-MetricsToDatabase -TableName "test_table" -Metrics $null -ErrorAction Stop
        } catch { }
        $global:PGQueryCalls.Count | Should -Be 0
    }

    It "should write an ordinary metric as an INSERT" {
        $metric = [PSCustomObject]@{
            computer_name = "test-pc"
            cpu_usage = 50
        }
        Write-MetricsToDatabase -TableName "metric_cpu" -Metrics @($metric)
        $global:PGQueryCalls.Count | Should -Be 1

        $call = $global:PGQueryCalls[0]
        $call.Query | Should -Match "^INSERT INTO metric_cpu"
        $call.Query | Should -Match "\(computer_name, cpu_usage\)"
        $call.Query | Should -Match "VALUES \(@computer_name, @cpu_usage\)"

        $call.Parameters.Count | Should -Be 2
        $call.Parameters["computer_name"] | Should -Be "test-pc"
        $call.Parameters["cpu_usage"] | Should -Be 50
    }

    It "should write a 'computers' metric as an UPSERT (ON CONFLICT)" {
        $metric = [PSCustomObject]@{
            computer_name = "test-pc"
            os_version = "Windows 11"
        }
        Write-MetricsToDatabase -TableName "computers" -Metrics @($metric)
        $global:PGQueryCalls.Count | Should -Be 1

        $call = $global:PGQueryCalls[0]
        $call.Query | Should -Match "ON CONFLICT \(computer_name\)"
        $call.Query | Should -Match "DO UPDATE SET"
        $call.Query | Should -Match "os_version = EXCLUDED.os_version"
        # Since computer_name is conflict target, it should not be in DO UPDATE SET except for the EXCLUDED assignment of other cols
        $call.Query | Should -Not -Match "computer_name = EXCLUDED.computer_name"
    }

    It "should handle multiple metrics" {
        $metric1 = [PSCustomObject]@{ id = 1; value = "A" }
        $metric2 = [PSCustomObject]@{ id = 2; value = "B" }
        Write-MetricsToDatabase -TableName "test_table" -Metrics @($metric1, $metric2)
        $global:PGQueryCalls.Count | Should -Be 2

        $global:LogMessages | Where-Object { $_.Message -match "Written 2 rows to test_table" } | Measure-Object | Select-Object -ExpandProperty Count | Should -Be 1
    }

    It "should log an error if Invoke-PGQuery throws an exception" {
        Mock -CommandName Invoke-PGQuery -ModuleName DBWriter -MockWith {
            param($Query, $Parameters, $NonQuery)
            throw "Database error"
        }
        $metric = [PSCustomObject]@{ id = 1 }
        Write-MetricsToDatabase -TableName "test_table" -Metrics @($metric)

        $errorLog = $global:LogMessages | Where-Object { $_.Severity -eq 'Error' }
        $errorLog | Should -Not -BeNullOrEmpty
        $errorLog.Message | Should -Match "Failed to write metric to test_table: Database error"
    }
}
