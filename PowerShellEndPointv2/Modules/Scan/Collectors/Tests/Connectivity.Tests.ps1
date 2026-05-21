$global:ModulePath = Resolve-Path "$PSScriptRoot/../Connectivity.psm1"

BeforeAll {
    Import-Module $global:ModulePath -Force
}

Describe "Connectivity Collector" {
    BeforeAll {
        function global:Test-Connection { return $true }

        function global:New-CimSessionOption { return "dummyOption" }
        function global:New-CimSession {
            param($ComputerName, $SessionOption, $OperationTimeoutSec, $ErrorAction, $Credential)
            $global:passedTimeout = $OperationTimeoutSec
            return "dummySession"
        }
        function global:Get-WmiObject { return "dummyWMI" }
        function global:Remove-CimSession { }
    }

    It "Verifies that Connect-EMSEndpoint passes OperationTimeoutSec correctly" {
        $result = Connect-EMSEndpoint -ComputerName "localhost" -TimeoutSeconds 20

        $global:passedTimeout | Should -Be 20
        $result.Connected | Should -Be $true
        $result.Protocol | Should -Be 'CIM-DCOM'
    }
}
