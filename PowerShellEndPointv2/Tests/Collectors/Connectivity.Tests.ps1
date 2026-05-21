$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulePath = "$here/../../Modules/Scan/Collectors/Connectivity.psm1"

# Define dummy functions globally so Import-Module doesn't complain
function global:Test-Connection { return $true }
function global:New-CimSessionOption {}
function global:New-CimSession {}
function global:Get-WmiObject {}
function global:Remove-CimSession {}

Import-Module $modulePath -Force

Describe "Connect-EMSEndpoint" {
    BeforeAll {
        $Global:TestComputerName = "TestComputer"
    }

    It "Should pass OperationTimeoutSec in seconds to New-CimSession" {
        $global:NewCimSessionArgsArray = $null

        # We need to redefine it globally since the module calls the global one directly in Linux test environment
        function global:New-CimSession {
            $global:NewCimSessionArgsArray = $args
            return "MockCimSession"
        }

        $result = Connect-EMSEndpoint -ComputerName $Global:TestComputerName -TimeoutSeconds 15

        $global:NewCimSessionArgsArray | Should -Not -BeNullOrEmpty

        # In PowerShell Linux, splatted dictionary parameters surface in $args like: "-OperationTimeoutSec:" followed by the value
        $index = [Array]::IndexOf($global:NewCimSessionArgsArray, '-OperationTimeoutSec:')
        if ($index -eq -1) {
            # In some PowerShell versions / environments splatted keys might not have a trailing colon
            $index = [Array]::IndexOf($global:NewCimSessionArgsArray, '-OperationTimeoutSec')
        }
        $index | Should -BeGreaterThan -1
        $global:NewCimSessionArgsArray[$index + 1] | Should -Be 15

        $result.Protocol | Should -Be 'CIM-DCOM'
        $result.Connected | Should -Be $true
        $result.Session | Should -Be "MockCimSession"
    }
}
