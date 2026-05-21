$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = "$here/../../Modules/Scan/Collectors/Connectivity.psm1"

Import-Module $modulePath -Force

Describe "Connectivity Module" {
    BeforeAll {
        if (-not (Get-Command Test-Connection -ErrorAction SilentlyContinue)) {
            function Global:Test-Connection { return $true }
        }
        if (-not (Get-Command New-CimSessionOption -ErrorAction SilentlyContinue)) {
            function Global:New-CimSessionOption { return "MockOption" }
        }
        if (-not (Get-Command New-CimSession -ErrorAction SilentlyContinue)) {
            function Global:New-CimSession { return "MockSession" }
        }
        if (-not (Get-Command Get-WmiObject -ErrorAction SilentlyContinue)) {
            function Global:Get-WmiObject { return "MockWMI" }
        }
        if (-not (Get-Command Remove-CimSession -ErrorAction SilentlyContinue)) {
            function Global:Remove-CimSession {}
        }
    }

    Context "Connect-EMSEndpoint" {
        It "Should pass TimeoutSeconds exactly to OperationTimeoutSec" {
            InModuleScope Connectivity {
                function Test-Connection { return $true }
                function New-CimSessionOption { return "MockOption" }
                $script:NewCimSessionCalled = $false
                $script:PassedTimeout = $null

                function New-CimSession {
                    param(
                        $ComputerName,
                        $SessionOption,
                        $OperationTimeoutSec,
                        $ErrorAction,
                        $Credential
                    )
                    $script:NewCimSessionCalled = $true
                    $script:PassedTimeout = $OperationTimeoutSec

                    if (-not $script:PassedTimeout) {
                       $script:PassedTimeout = $PSBoundParameters['OperationTimeoutSec']
                    }

                    return "MockSession"
                }

                $result = Connect-EMSEndpoint -ComputerName "TestPC" -TimeoutSeconds 15

                $result.Connected | Should -Be $true
                $result.Protocol | Should -Be 'CIM-DCOM'

                $script:NewCimSessionCalled | Should -Be $true
                $script:PassedTimeout | Should -Be 15
            }
        }
    }

    Context "Disconnect-EMSEndpoint" {
        It "Should correctly identify and remove CIM-DCOM sessions" {
            InModuleScope Connectivity {
                $script:RemoveCimSessionCalled = $false
                $script:RemovedSession = $null

                function Remove-CimSession {
                    param($CimSession, $ErrorAction)
                    $script:RemoveCimSessionCalled = $true
                    $script:RemovedSession = $CimSession
                }

                $mockSessionObj = [PSCustomObject]@{
                    Protocol = 'CIM-DCOM'
                    Session = 'ActualMockSessionData'
                }

                Disconnect-EMSEndpoint -Session $mockSessionObj

                $script:RemoveCimSessionCalled | Should -Be $true
                $script:RemovedSession | Should -Be 'ActualMockSessionData'
            }
        }
    }
}
