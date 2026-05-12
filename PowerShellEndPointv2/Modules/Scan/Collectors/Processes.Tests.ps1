$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
Import-Module "$here/$sut" -Force

Describe "Invoke-ProcessesCollection" {
    $ScanId = [Guid]::NewGuid()
    $ComputerName = 'TestPC'

    Context "When session protocol is CIM" {
        $mockSession = [PSCustomObject]@{
            Protocol = 'CIM'
            Session  = 'MockCimSession'
        }

        It "Should use Get-CimInstance and filter processes correctly" {
            # Arrange
            $mockProcesses = @(
                [PSCustomObject]@{
                    ProcessId = 1000
                    Name = 'highmemory.exe'
                    ExecutablePath = 'C:\highmemory.exe'
                    WorkingSetSize = 100MB # > 50MB
                },
                [PSCustomObject]@{
                    ProcessId = 1001
                    Name = 'lowmemory.exe'
                    ExecutablePath = 'C:\lowmemory.exe'
                    WorkingSetSize = 10MB # < 50MB, not critical
                },
                [PSCustomObject]@{
                    ProcessId = 1002
                    Name = 'lsass.exe'
                    ExecutablePath = 'C:\Windows\System32\lsass.exe'
                    WorkingSetSize = 5MB # < 50MB, but critical
                }
            )

            Mock Get-CimInstance { return $mockProcesses }

            # Act
            $result = Invoke-ProcessesCollection -Session $mockSession -ComputerName $ComputerName -ScanId $ScanId

            # Assert
            $result.Success | Should -Be $true
            $result.Metrics.Count | Should -Be 2

            $highMemProc = $result.Metrics | Where-Object { $_.process_name -eq 'highmemory.exe' }
            $highMemProc | Should -Not -BeNullOrEmpty
            $highMemProc.is_critical | Should -Be $false

            $criticalProc = $result.Metrics | Where-Object { $_.process_name -eq 'lsass.exe' }
            $criticalProc | Should -Not -BeNullOrEmpty
            $criticalProc.is_critical | Should -Be $true

            Assert-MockCalled Get-CimInstance -Times 1 -Exactly
            Assert-MockCalled Get-WmiObject -Times 0 -Exactly
        }

        It "Should handle errors from Get-CimInstance" {
            # Arrange
            Mock Get-CimInstance { throw "CIM connection failed" }

            # Act
            $result = Invoke-ProcessesCollection -Session $mockSession -ComputerName $ComputerName -ScanId $ScanId

            # Assert
            $result.Success | Should -Be $false
            $result.Errors.Count | Should -Be 1
            $result.Errors[0] | Should -Match "CIM connection failed"
            Assert-MockCalled Get-CimInstance -Times 1 -Exactly
        }
    }

    Context "When session protocol is not CIM" {
        $mockSession = [PSCustomObject]@{
            Protocol = 'WMI'
            Session  = 'MockWmiSession'
        }

        It "Should use Get-WmiObject and filter processes correctly" {
            # Arrange
            $mockProcesses = @(
                [PSCustomObject]@{
                    ProcessId = 2000
                    Name = 'wmiprocess.exe'
                    ExecutablePath = 'C:\wmiprocess.exe'
                    WorkingSetSize = 60MB # > 50MB
                }
            )

            Mock Get-WmiObject { return $mockProcesses }

            # Act
            $result = Invoke-ProcessesCollection -Session $mockSession -ComputerName $ComputerName -ScanId $ScanId

            # Assert
            $result.Success | Should -Be $true
            $result.Metrics.Count | Should -Be 1
            $result.Metrics[0].process_name | Should -Be 'wmiprocess.exe'

            Assert-MockCalled Get-WmiObject -Times 1 -Exactly
            Assert-MockCalled Get-CimInstance -Times 0 -Exactly
        }

        It "Should handle errors from Get-WmiObject" {
            # Arrange
            Mock Get-WmiObject { throw "WMI connection failed" }

            # Act
            $result = Invoke-ProcessesCollection -Session $mockSession -ComputerName $ComputerName -ScanId $ScanId

            # Assert
            $result.Success | Should -Be $false
            $result.Errors.Count | Should -Be 1
            $result.Errors[0] | Should -Match "WMI connection failed"
            Assert-MockCalled Get-WmiObject -Times 1 -Exactly
        }
    }
}
