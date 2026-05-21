function global:Write-EMSLog {}
Import-Module "$PSScriptRoot\..\..\Modules\API\EMS.API.Scan.psm1" -Force

Describe 'EMS.API.Scan' {
    InModuleScope 'EMS.API.Scan' {
        Context 'Test-FrontendErrorAllowed' {
            It 'allows requests under the limit' {
                $ip = "127.0.0.1"
                $script:FrontendErrorBuckets.Clear()

                for ($i = 0; $i -lt 5; $i++) {
                    $result = Test-FrontendErrorAllowed -Ip $ip
                    $result | Should -Be $true
                }
            }

            It 'blocks requests over the limit' {
                $ip = "127.0.0.2"
                $script:FrontendErrorBuckets.Clear()

                for ($i = 0; $i -lt 5; $i++) {
                    $result = Test-FrontendErrorAllowed -Ip $ip
                    $result | Should -Be $true
                }

                $result = Test-FrontendErrorAllowed -Ip $ip
                $result | Should -Be $false
            }

            It 'resets the limit after the window expires' {
                $ip = "127.0.0.3"
                $script:FrontendErrorBuckets.Clear()

                $oldTime = [DateTime]::Now.AddSeconds(-65)
                $addValueFactory = [Func[string, object]] { param($k) return [pscustomobject]@{ Count=5; WindowStart=$oldTime } }
                $updateValueFactory = [Func[string, object, object]] { param($k, $old) return [pscustomobject]@{ Count=5; WindowStart=$oldTime } }

                $null = $script:FrontendErrorBuckets.AddOrUpdate($ip, $addValueFactory, $updateValueFactory)

                $result = Test-FrontendErrorAllowed -Ip $ip
                $result | Should -Be $true
            }
        }
    }
}
