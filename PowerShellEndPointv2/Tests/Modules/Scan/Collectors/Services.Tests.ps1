$sut = "$PSScriptRoot/../../../../Modules/Scan/Collectors/Services.psm1"

Import-Module $sut -Force

Describe "Invoke-ServicesCollection" {
    BeforeAll {
        function global:Get-CimInstance { }
        function global:Get-WmiObject { }
    }

    Context "When CIM session is provided" {
        It "Should collect services and return success" {
            Mock -CommandName Get-CimInstance -MockWith {
                return @(
                    [PSCustomObject]@{
                        Name = "TestService1"
                        DisplayName = "Test Service 1"
                        State = "Running"
                        StartMode = "Auto"
                        StartName = "LocalSystem"
                        ProcessId = 1234
                    },
                    [PSCustomObject]@{
                        Name = "TestService2"
                        DisplayName = "Test Service 2"
                        State = "Stopped"
                        StartMode = "Manual"
                        StartName = "LocalSystem"
                        ProcessId = 0
                    },
                    [PSCustomObject]@{
                        Name = "WinRM"
                        DisplayName = "Windows Remote Management (WS-Management)"
                        State = "Running"
                        StartMode = "Auto"
                        StartName = "NetworkService"
                        ProcessId = 5678
                    }
                )
            } -ModuleName "Services"

            $mockSession = [PSCustomObject]@{
                Protocol = "CIM"
                Session = "MockSession"
            }

            $scanId = [Guid]::NewGuid()
            $result = Invoke-ServicesCollection -Session $mockSession -ComputerName "TestComp" -ScanId $scanId

            $result.Success | Should -Be $true
            $result.Metrics.Count | Should -Be 2 # One running, one critical
            $result.Metrics[0].service_name | Should -Be "TestService1"
            $result.Metrics[1].service_name | Should -Be "WinRM"
            $result.Metrics[1].is_critical | Should -Be $true
            Assert-MockCalled -CommandName Get-CimInstance -Times 1 -Exactly -ModuleName "Services"
        }
    }

    Context "When WMI session is provided" {
        It "Should collect services using WMI and return success" {
            Mock -CommandName Get-WmiObject -MockWith {
                return @(
                    [PSCustomObject]@{
                        Name = "TestService3"
                        DisplayName = "Test Service 3"
                        State = "Running"
                        StartMode = "Auto"
                        StartName = "LocalSystem"
                        ProcessId = 4321
                    }
                )
            } -ModuleName "Services"

            $mockSession = [PSCustomObject]@{
                Protocol = "WMI"
                Session = $null
            }

            $scanId = [Guid]::NewGuid()
            $result = Invoke-ServicesCollection -Session $mockSession -ComputerName "TestComp" -ScanId $scanId

            $result.Success | Should -Be $true
            $result.Metrics.Count | Should -Be 1
            $result.Metrics[0].service_name | Should -Be "TestService3"
            Assert-MockCalled -CommandName Get-WmiObject -Times 1 -Exactly -ModuleName "Services"
        }
    }

    Context "When exception occurs" {
        It "Should handle errors gracefully" {
            Mock -CommandName Get-CimInstance -MockWith { throw "Failed to connect to CIM" } -ModuleName "Services"

            $mockSession = [PSCustomObject]@{
                Protocol = "CIM"
                Session = "MockSession"
            }

            $scanId = [Guid]::NewGuid()
            $result = Invoke-ServicesCollection -Session $mockSession -ComputerName "TestComp" -ScanId $scanId

            $result.Success | Should -Be $false
            $result.Errors.Count | Should -BeGreaterThan 0
            $result.Errors[0] | Should -Match "Failed to connect to CIM"
        }
    }
}
