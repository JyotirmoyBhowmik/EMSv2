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
Describe "Invoke-ServicesCollection" {
    BeforeAll {
        $modulePath = Resolve-Path "$PSScriptRoot/../../../../Modules/Scan/Collectors/Services.psm1"
        Import-Module $modulePath -Force
    }

    Context "WMI (Windows PowerShell compatibility)" {
        # Define global stubs if not present in core
        function global:Get-WmiObject {}

        It "returns a failure result when an exception is thrown" {
            $mockSession = [PSCustomObject]@{
                Protocol = 'WMI'
                Session = $null
            }

            Mock Get-WmiObject { throw "WMI Error" } -ModuleName Services

            $result = Invoke-ServicesCollection -Session $mockSession -ComputerName "TestPC" -ScanId ([Guid]::NewGuid())

            $result.Success | Should -Be $false
            $result.Errors.Count | Should -Be 1
            $result.Errors[0] | Should -Match "WMI Error"
        }

        It "successfully collects service metrics using WMI" {
            $mockSession = [PSCustomObject]@{
                Protocol = 'WMI'
                Session = $null
            }

            Mock Get-WmiObject {
                return @(
                    [PSCustomObject]@{
                        Name = "RunningSvc"
                        DisplayName = "Running Service"
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
                )
            } -ModuleName Services

            $result = Invoke-ServicesCollection -Session $mockSession -ComputerName "TestPC" -ScanId ([Guid]::NewGuid())

            $result.Success | Should -Be $true
            $result.Errors.Count | Should -Be 0
            $result.Metrics.Count | Should -Be 1
            $result.Metrics[0].service_name | Should -Be "RunningSvc"
        }
    }

    Context "CIM (PowerShell Core / Modern)" {
        # Define global stubs if not present
        function global:Get-CimInstance {}

        It "returns a failure result when an exception is thrown" {
            $mockSession = [PSCustomObject]@{
                Protocol = 'CIM'
                Session = "SomeCimSession"
            }

            Mock Get-CimInstance { throw "CIM Error" } -ModuleName Services

            $result = Invoke-ServicesCollection -Session $mockSession -ComputerName "TestPC" -ScanId ([Guid]::NewGuid())

            $result.Success | Should -Be $false
            $result.Errors.Count | Should -Be 1
            $result.Errors[0] | Should -Match "CIM Error"
        }

        It "successfully collects service metrics using CIM" {
            $mockSession = [PSCustomObject]@{
                Protocol = 'CIM'
                Session = "SomeCimSession"
            }

            Mock Get-CimInstance {
                return @(
                    [PSCustomObject]@{
                        Name = "RunningSvcCim"
                        DisplayName = "Running Service CIM"
                        State = "Running"
                        StartMode = "Auto"
                        StartName = "LocalSystem"
                        ProcessId = 5678
                    }
                )
            } -ModuleName Services

            $result = Invoke-ServicesCollection -Session $mockSession -ComputerName "TestPC" -ScanId ([Guid]::NewGuid())

            $result.Success | Should -Be $true
            $result.Errors.Count | Should -Be 0
            $result.Metrics.Count | Should -Be 1
            $result.Metrics[0].service_name | Should -Be "RunningSvcCim"
        }
    }

    Context "Filtering Logic" {
        # Define global stubs if not present
        function global:Get-CimInstance {}

        It "includes only running, auto-start, or critical services" {
            $mockSession = [PSCustomObject]@{
                Protocol = 'CIM'
                Session = "SomeCimSession"
            }

            Mock Get-CimInstance {
                return @(
                    # 1. Running, Auto (Include)
                    [PSCustomObject]@{
                        Name = "AppHostSvc"
                        DisplayName = "Application Host Helper Service"
                        State = "Running"
                        StartMode = "Auto"
                        StartName = "LocalSystem"
                        ProcessId = 100
                    },
                    # 2. Stopped, Auto (Include - could be failed or delayed)
                    [PSCustomObject]@{
                        Name = "BITS"
                        DisplayName = "Background Intelligent Transfer Service"
                        State = "Stopped"
                        StartMode = "Auto"
                        StartName = "LocalSystem"
                        ProcessId = 0
                    },
                    # 3. Stopped, Manual, Critical (Include - critical name)
                    [PSCustomObject]@{
                        Name = "WinRM"
                        DisplayName = "Windows Remote Management (WS-Management)"
                        State = "Stopped"
                        StartMode = "Manual"
                        StartName = "NetworkService"
                        ProcessId = 0
                    },
                    # 4. Running, Manual (Include - it is running)
                    [PSCustomObject]@{
                        Name = "Spooler"
                        DisplayName = "Print Spooler"
                        State = "Running"
                        StartMode = "Manual"
                        StartName = "LocalSystem"
                        ProcessId = 200
                    },
                    # 5. Stopped, Disabled, Non-Critical (Exclude)
                    [PSCustomObject]@{
                        Name = "XboxGipSvc"
                        DisplayName = "Xbox Accessory Management Service"
                        State = "Stopped"
                        StartMode = "Disabled"
                        StartName = "LocalSystem"
                        ProcessId = 0
                    },
                    # 6. Stopped, Manual, Non-Critical (Exclude)
                    [PSCustomObject]@{
                        Name = "wercplsupport"
                        DisplayName = "Problem Reports and Solutions Control Panel Support"
                        State = "Stopped"
                        StartMode = "Manual"
                        StartName = "LocalSystem"
                        ProcessId = 0
                    }
                )
            } -ModuleName Services

            $result = Invoke-ServicesCollection -Session $mockSession -ComputerName "TestPC" -ScanId ([Guid]::NewGuid())

            $result.Success | Should -Be $true
            $result.Metrics.Count | Should -Be 4

            $includedNames = $result.Metrics | Select-Object -ExpandProperty service_name
            $includedNames | Should -Contain "AppHostSvc"
            $includedNames | Should -Contain "BITS"
            $includedNames | Should -Contain "WinRM"
            $includedNames | Should -Contain "Spooler"

            $includedNames | Should -Not -Contain "XboxGipSvc"
            $includedNames | Should -Not -Contain "wercplsupport"

            # Check critical tag
            $winRmMetric = $result.Metrics | Where-Object { $_.service_name -eq "WinRM" }
            $winRmMetric.is_critical | Should -Be $true

            $appHostMetric = $result.Metrics | Where-Object { $_.service_name -eq "AppHostSvc" }
            $appHostMetric.is_critical | Should -Be $false
        }
    }
}
