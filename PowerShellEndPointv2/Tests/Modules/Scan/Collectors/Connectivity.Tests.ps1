$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

Describe "Connectivity Module" {
    BeforeAll {
        $modulePath = Resolve-Path "$PSScriptRoot/../../../../Modules/Scan/Collectors/Connectivity.psm1" -ErrorAction SilentlyContinue

        function global:Test-Connection {}
        function global:New-CimSessionOption {}
        function global:Get-WmiObject {}
        function global:Remove-CimSession {}

        # The key to Pester mocks receiving parameters properly from splatted hashtables is that
        # the mocked function MUST define those parameters!
        # When New-CimSession is mocked globally without params, Pester does not know about $OperationTimeoutSec.
        function global:New-CimSession {
            param(
                $ComputerName,
                $SessionOption,
                $OperationTimeoutSec,
                $ErrorAction,
                $Credential
            )
        }

        Import-Module $modulePath -Force
    }

    Context "Connect-EMSEndpoint" {
        It "should pass the correct OperationTimeoutSec to New-CimSession" {
            $mockComputerName = "TEST-PC"
            $mockTimeout = 15

            Mock Test-Connection { return $true } -ModuleName Connectivity
            Mock New-CimSessionOption { return "MockOption" } -ModuleName Connectivity
            Mock New-CimSession { return "MockSession" } -ModuleName Connectivity

            $result = Connect-EMSEndpoint -ComputerName $mockComputerName -TimeoutSeconds $mockTimeout

            $result.Connected | Should -Be $true
            $result.Protocol | Should -Be "CIM-DCOM"
            $result.Session | Should -Be "MockSession"

            Assert-MockCalled New-CimSession -Times 1 -Exactly -ModuleName Connectivity -ParameterFilter {
                $OperationTimeoutSec -eq $mockTimeout
            }
        }

        It "should fallback to WMI if CIM session fails" {
            $mockComputerName = "TEST-PC"
            $mockTimeout = 15

            Mock Test-Connection { return $true } -ModuleName Connectivity
            Mock New-CimSessionOption { return "MockOption" } -ModuleName Connectivity
            Mock New-CimSession { throw "CIM Failure" } -ModuleName Connectivity
            Mock Get-WmiObject { return "MockWmiObj" } -ModuleName Connectivity

            $result = Connect-EMSEndpoint -ComputerName $mockComputerName -TimeoutSeconds $mockTimeout

            $result.Connected | Should -Be $true
            $result.Protocol | Should -Be "Legacy-DCOM"

            Assert-MockCalled New-CimSession -Times 1 -Exactly -ModuleName Connectivity
            Assert-MockCalled Get-WmiObject -Times 1 -Exactly -ModuleName Connectivity
        }

        It "should return error if ping fails" {
            $mockComputerName = "TEST-PC"

            Mock Test-Connection { return $false } -ModuleName Connectivity

            $result = Connect-EMSEndpoint -ComputerName $mockComputerName

            $result.Connected | Should -Be $false
            $result.Error | Should -Match "Host unreachable"

            Assert-MockCalled Test-Connection -Times 1 -Exactly -ModuleName Connectivity
        }
    }

    Context "Disconnect-EMSEndpoint" {
        It "should call Remove-CimSession when Protocol is CIM-DCOM" {
            $mockSessionObj = @{
                Protocol = 'CIM-DCOM'
                Session = 'RealMockSession'
            }

            Mock Remove-CimSession {} -ModuleName Connectivity

            Disconnect-EMSEndpoint -Session $mockSessionObj

            Assert-MockCalled Remove-CimSession -Times 1 -Exactly -ModuleName Connectivity
        }

        It "should not call Remove-CimSession when Protocol is Legacy-DCOM" {
            $mockSessionObj = @{
                Protocol = 'Legacy-DCOM'
                Session = $null
            }

            Mock Remove-CimSession {} -ModuleName Connectivity

            Disconnect-EMSEndpoint -Session $mockSessionObj

            Assert-MockCalled Remove-CimSession -Times 0 -Exactly -ModuleName Connectivity
        }
    }
}
