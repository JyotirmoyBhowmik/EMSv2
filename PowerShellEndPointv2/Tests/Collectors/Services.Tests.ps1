$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = "$here/../../Modules/Scan/Collectors/Services.psm1"

Import-Module $modulePath -Force

Describe "Invoke-ServicesCollection" {
    BeforeAll {
        $Global:TestScanId = [Guid]::NewGuid()
        $Global:TestComputerName = "TestComputer"

        $Global:MockServices = @(
            [PSCustomObject]@{
                Name = 'WinRM'
                DisplayName = 'Windows Remote Management (WS-Management)'
                State = 'Running'
                StartMode = 'Auto'
                StartName = 'NetworkService'
                ProcessId = 1234
            },
            [PSCustomObject]@{
                Name = 'wuauserv'
                DisplayName = 'Windows Update'
                State = 'Stopped'
                StartMode = 'Manual'
                StartName = 'LocalSystem'
                ProcessId = 0
            },
            [PSCustomObject]@{
                Name = 'Spooler'
                DisplayName = 'Print Spooler'
                State = 'Stopped'
                StartMode = 'Auto'
                StartName = 'LocalSystem'
                ProcessId = 0
            },
            [PSCustomObject]@{
                Name = 'W32Time'
                DisplayName = 'Windows Time'
                State = 'Running'
                StartMode = 'Manual'
                StartName = 'LocalService'
                ProcessId = 5678
            },
            [PSCustomObject]@{
                Name = 'AppIDSvc'
                DisplayName = 'Application Identity'
                State = 'Stopped'
                StartMode = 'Manual'
                StartName = 'LocalService'
                ProcessId = 0
            }
        )

        # Simply define empty functions in global scope so Pester doesn't complain about command not found when attempting to mock.
        # This is a requirement for PowerShell Core on Linux where WMI/CIM cmdlets don't exist at all.
        if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
            function Global:Get-CimInstance {}
        }
        if (-not (Get-Command Get-WmiObject -ErrorAction SilentlyContinue)) {
            function Global:Get-WmiObject {}
        }
    }

    Context "When called with CIM session" {
        It "Should return correctly filtered results using Get-CimInstance" {
            $cimSession = New-Object -TypeName PSObject -Property @{ Protocol = 'CIM'; Session = 'MockSession' }

            Mock Get-CimInstance { return $Global:MockServices } -ModuleName Services

            $result = Invoke-ServicesCollection -Session $cimSession -ComputerName $Global:TestComputerName -ScanId $Global:TestScanId

            if ($result.Errors.Count -gt 0) { Write-Host "Errors: $($result.Errors)" }

            $result.Success | Should -Be $true
            $result.ScanId | Should -Be $Global:TestScanId
            $result.Errors.Count | Should -Be 0
            $result.Duration | Should -BeGreaterOrEqual 0

            $result.Metrics.Count | Should -Be 4

            $names = $result.Metrics.service_name
            $names | Should -Contain 'WinRM'
            $names | Should -Contain 'wuauserv'
            $names | Should -Contain 'Spooler'
            $names | Should -Contain 'W32Time'
            $names | Should -Not -Contain 'AppIDSvc'

            $winrm = $result.Metrics | Where-Object { $_.service_name -eq 'WinRM' }
            $winrm.is_critical | Should -Be $true
            $winrm.process_id | Should -Be 1234

            $w32time = $result.Metrics | Where-Object { $_.service_name -eq 'W32Time' }
            $w32time.is_critical | Should -Be $false

            Assert-MockCalled Get-CimInstance -ModuleName Services -Times 1 -Exactly
        }
    }

    Context "When called without CIM session (WMI fallback)" {
        It "Should return correctly filtered results using Get-WmiObject" {
            $wmiSession = New-Object -TypeName PSObject -Property @{ Protocol = 'DCOM' }

            Mock Get-WmiObject { return $Global:MockServices } -ModuleName Services

            $result = Invoke-ServicesCollection -Session $wmiSession -ComputerName $Global:TestComputerName -ScanId $Global:TestScanId

            if ($result.Errors.Count -gt 0) { Write-Host "Errors: $($result.Errors)" }

            $result.Success | Should -Be $true
            $result.Metrics.Count | Should -Be 4

            Assert-MockCalled Get-WmiObject -ModuleName Services -Times 1 -Exactly
        }
    }

    Context "When an error occurs during collection" {
        It "Should catch the error and set Success to false with CIM session" {
            $cimSession = New-Object -TypeName PSObject -Property @{ Protocol = 'CIM'; Session = 'MockSession' }

            Mock Get-CimInstance { throw "CIM Connection Failed" } -ModuleName Services

            $result = Invoke-ServicesCollection -Session $cimSession -ComputerName $Global:TestComputerName -ScanId $Global:TestScanId

            $result.Success | Should -Be $false
            $result.Metrics.Count | Should -Be 0
            $result.Errors.Count | Should -Be 1
            $result.Errors[0] | Should -Match "\[Services\] CIM Connection Failed"

            Assert-MockCalled Get-CimInstance -ModuleName Services -Times 1 -Exactly
        }

        It "Should catch the error and set Success to false with WMI fallback" {
            $wmiSession = New-Object -TypeName PSObject -Property @{ Protocol = 'DCOM' }

            Mock Get-WmiObject { throw "WMI Connection Failed" } -ModuleName Services

            $result = Invoke-ServicesCollection -Session $wmiSession -ComputerName $Global:TestComputerName -ScanId $Global:TestScanId

            $result.Success | Should -Be $false
            $result.Metrics.Count | Should -Be 0
            $result.Errors.Count | Should -Be 1
            $result.Errors[0] | Should -Match "\[Services\] WMI Connection Failed"

            Assert-MockCalled Get-WmiObject -ModuleName Services -Times 1 -Exactly
        }
    }
}
