$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

Describe "EMS.API.Scan" {
    BeforeAll {
        function global:Invoke-PGQuery { param($Query, $Parameters, [switch]$NonQuery) return $null }
        function global:Test-AdminAccessRequirement { param($Request, $Response, $Config) return $true }
        function global:Test-ViewerAccessRequirement { param($Request, $Response, $Config) return $true }
        function global:Read-JsonBody { param($Request) return @{} }
        function global:Write-JsonResponse { param($Request, $Response, $StatusCode, $Data) }
        function global:Get-RequestUserContext { param($Request) return @{ Username = 'testAdmin' } }
        function global:Start-EMSScan { param($ScanId, $Target, $Protocol) }
        function global:Start-EMSBatchScan { param($Targets, $Protocol) return @{ targetCount = 1; targets = @('test'); scanIds = @([guid]::NewGuid()) } }
        function global:Read-EMSRequestBody { param($Request, $MaxBytes) return "{}" }
        function global:Write-EMSLog {}

        # Load the module under test but removing strict typing from param block to allow mock objects
        $modulePath = Resolve-Path "$PSScriptRoot/../../Modules/API/EMS.API.Scan.psm1" -ErrorAction SilentlyContinue
        $content = Get-Content $modulePath -Raw
        $content = $content -replace '\[System.Net.HttpListenerRequest\]', ''
        $content = $content -replace '\[System.Net.HttpListenerResponse\]', ''

        $tempPath = "$PSScriptRoot/Temp.EMS.API.Scan.psm1"
        Set-Content -Path $tempPath -Value $content
        Import-Module $tempPath -Force
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    }

    Context "Invoke-ScanRoutes" {
        BeforeEach {
            # Need to create a real-ish System.Net.IPAddress to allow .ToString()
            $ipAddressMock = [System.Net.IPAddress]::Parse('127.0.0.1')
            $mockRequest = [pscustomobject]@{
                HasEntityBody = $true
                RemoteEndPoint = [pscustomobject]@{ Address = $ipAddressMock }
                QueryString = @{}
            }
            $mockResponse = [pscustomobject]@{
                StatusCode = 200
            }
            $mockConfig = [pscustomobject]@{}

            # Reset the concurrent dictionary before each test for rate-limiting
            $dict = (Get-Module Temp.EMS.API.Scan).SessionState.PSVariable.GetValue('script:FrontendErrorBuckets')
            if ($dict) {
                $dict.Clear()
            }
        }

        It "should return true and process /scan/single" {
            Mock Read-JsonBody { return [pscustomobject]@{ target = '192.168.1.1' } } -ModuleName Temp.EMS.API.Scan
            Mock Write-JsonResponse { } -ModuleName Temp.EMS.API.Scan
            Mock Invoke-PGQuery { } -ModuleName Temp.EMS.API.Scan
            Mock Start-EMSScan { } -ModuleName Temp.EMS.API.Scan
            Mock Test-AdminAccessRequirement { return $true } -ModuleName Temp.EMS.API.Scan

            $result = Invoke-ScanRoutes -Request $mockRequest -Response $mockResponse -Method 'POST' -Path '/scan/single' -Config $mockConfig

            $result | Should -Be $true
            Assert-MockCalled Read-JsonBody -Times 1 -ModuleName Temp.EMS.API.Scan
            Assert-MockCalled Invoke-PGQuery -Times 1 -ModuleName Temp.EMS.API.Scan
            Assert-MockCalled Start-EMSScan -Times 1 -ModuleName Temp.EMS.API.Scan
            Assert-MockCalled Write-JsonResponse -Times 1 -ModuleName Temp.EMS.API.Scan -ParameterFilter { $StatusCode -eq 202 }
        }

        It "should return true and process POST /results/[guid]/archive" {
            $scanId = [guid]::NewGuid()
            Mock Invoke-PGQuery {
                if ($NonQuery) { return }
                return [pscustomobject]@{ scan_id = $scanId; target = '192.168.1.1'; status = 'completed'; is_deleted = $false }
            } -ModuleName Temp.EMS.API.Scan
            Mock Write-JsonResponse { } -ModuleName Temp.EMS.API.Scan
            Mock Get-RequestUserContext { return [pscustomobject]@{ Username = 'admin' } } -ModuleName Temp.EMS.API.Scan
            Mock Test-AdminAccessRequirement { return $true } -ModuleName Temp.EMS.API.Scan

            $result = Invoke-ScanRoutes -Request $mockRequest -Response $mockResponse -Method 'POST' -Path "/results/$scanId/archive" -Config $mockConfig

            $result | Should -Be $true
            Assert-MockCalled Write-JsonResponse -Times 1 -ModuleName Temp.EMS.API.Scan -ParameterFilter { $StatusCode -eq 200 }
        }

        It "should handle POST /results/[guid]/archive when scan row not found" {
            $scanId = [guid]::NewGuid()
            Mock Invoke-PGQuery { return $null } -ModuleName Temp.EMS.API.Scan
            Mock Write-JsonResponse { } -ModuleName Temp.EMS.API.Scan
            Mock Get-RequestUserContext { return [pscustomobject]@{ Username = 'admin' } } -ModuleName Temp.EMS.API.Scan
            Mock Test-AdminAccessRequirement { return $true } -ModuleName Temp.EMS.API.Scan

            $result = Invoke-ScanRoutes -Request $mockRequest -Response $mockResponse -Method 'POST' -Path "/results/$scanId/archive" -Config $mockConfig

            $result | Should -Be $true
            Assert-MockCalled Write-JsonResponse -Times 1 -ModuleName Temp.EMS.API.Scan -ParameterFilter { $StatusCode -eq 404 }
        }

        It "should handle POST /results/[guid]/archive when row already archived" {
            $scanId = [guid]::NewGuid()
            Mock Invoke-PGQuery { return [pscustomobject]@{ scan_id = $scanId; target = '192.168.1.1'; status = 'completed'; is_deleted = $true } } -ModuleName Temp.EMS.API.Scan
            Mock Write-JsonResponse { } -ModuleName Temp.EMS.API.Scan
            Mock Get-RequestUserContext { return [pscustomobject]@{ Username = 'admin' } } -ModuleName Temp.EMS.API.Scan
            Mock Test-AdminAccessRequirement { return $true } -ModuleName Temp.EMS.API.Scan

            $result = Invoke-ScanRoutes -Request $mockRequest -Response $mockResponse -Method 'POST' -Path "/results/$scanId/archive" -Config $mockConfig

            $result | Should -Be $true
            Assert-MockCalled Write-JsonResponse -Times 1 -ModuleName Temp.EMS.API.Scan -ParameterFilter { $StatusCode -eq 200 }
        }

        It "should return true and process POST /results/[guid]/restore" {
            $scanId = [guid]::NewGuid()
            Mock Invoke-PGQuery {
                if ($NonQuery) { return }
                return [pscustomobject]@{ scan_id = $scanId; target = '192.168.1.1'; status = 'completed'; is_deleted = $true }
            } -ModuleName Temp.EMS.API.Scan
            Mock Write-JsonResponse { } -ModuleName Temp.EMS.API.Scan
            Mock Get-RequestUserContext { return [pscustomobject]@{ Username = 'admin' } } -ModuleName Temp.EMS.API.Scan
            Mock Test-AdminAccessRequirement { return $true } -ModuleName Temp.EMS.API.Scan

            $result = Invoke-ScanRoutes -Request $mockRequest -Response $mockResponse -Method 'POST' -Path "/results/$scanId/restore" -Config $mockConfig

            $result | Should -Be $true
            Assert-MockCalled Write-JsonResponse -Times 1 -ModuleName Temp.EMS.API.Scan -ParameterFilter { $StatusCode -eq 200 }
        }

        It "should return true and process POST /scan/bulk" {
            Mock Read-JsonBody { return [pscustomobject]@{ targets = @('192.168.1.1', '192.168.1.2') } } -ModuleName Temp.EMS.API.Scan
            Mock Write-JsonResponse { } -ModuleName Temp.EMS.API.Scan
            Mock Start-EMSBatchScan { return [pscustomobject]@{ targetCount = 2; targets = @('192.168.1.1', '192.168.1.2'); scanIds = @([guid]::NewGuid(), [guid]::NewGuid()) } } -ModuleName Temp.EMS.API.Scan
            Mock Test-AdminAccessRequirement { return $true } -ModuleName Temp.EMS.API.Scan

            $result = Invoke-ScanRoutes -Request $mockRequest -Response $mockResponse -Method 'POST' -Path '/scan/bulk' -Config $mockConfig

            $result | Should -Be $true
            Assert-MockCalled Read-JsonBody -Times 1 -ModuleName Temp.EMS.API.Scan
            Assert-MockCalled Start-EMSBatchScan -Times 1 -ModuleName Temp.EMS.API.Scan
            Assert-MockCalled Write-JsonResponse -Times 1 -ModuleName Temp.EMS.API.Scan -ParameterFilter { $StatusCode -eq 202 }
        }

        It "should return true and process GET /scan/status" {
            $scanId = [guid]::NewGuid()
            $mockRequest.QueryString = @{ 'scanId' = $scanId.ToString() }

            Mock Invoke-PGQuery { return [pscustomobject]@{ scan_id = $scanId; target = '192.168.1.1'; status = 'completed' } } -ModuleName Temp.EMS.API.Scan
            Mock Write-JsonResponse { } -ModuleName Temp.EMS.API.Scan
            Mock Test-ViewerAccessRequirement { return $true } -ModuleName Temp.EMS.API.Scan

            $result = Invoke-ScanRoutes -Request $mockRequest -Response $mockResponse -Method 'GET' -Path '/scan/status' -Config $mockConfig

            $result | Should -Be $true
            Assert-MockCalled Invoke-PGQuery -Times 1 -ModuleName Temp.EMS.API.Scan
            Assert-MockCalled Write-JsonResponse -Times 1 -ModuleName Temp.EMS.API.Scan -ParameterFilter { $StatusCode -eq 200 }
        }

        It "should return true and process GET /scan/trace" {
            $scanId = [guid]::NewGuid()
            $mockRequest.QueryString = @{ 'scanId' = $scanId.ToString() }

            Mock Invoke-PGQuery { return @([pscustomobject]@{ trace_id = 1; step_name = 'test' }) } -ModuleName Temp.EMS.API.Scan
            Mock Write-JsonResponse { } -ModuleName Temp.EMS.API.Scan
            Mock Test-ViewerAccessRequirement { return $true } -ModuleName Temp.EMS.API.Scan

            $result = Invoke-ScanRoutes -Request $mockRequest -Response $mockResponse -Method 'GET' -Path '/scan/trace' -Config $mockConfig

            $result | Should -Be $true
            Assert-MockCalled Invoke-PGQuery -Times 1 -ModuleName Temp.EMS.API.Scan
            Assert-MockCalled Write-JsonResponse -Times 1 -ModuleName Temp.EMS.API.Scan -ParameterFilter { $StatusCode -eq 200 }
        }

        It "should return true and process POST /audit/frontend-error" {
            Mock Read-EMSRequestBody { return '{"message":"error", "stack":"stack", "url":"http://test"}' } -ModuleName Temp.EMS.API.Scan
            Mock Invoke-PGQuery { } -ModuleName Temp.EMS.API.Scan
            Mock Write-JsonResponse { } -ModuleName Temp.EMS.API.Scan
            Mock Get-RequestUserContext { return [pscustomobject]@{ Username = 'testAdmin' } } -ModuleName Temp.EMS.API.Scan

            $result = Invoke-ScanRoutes -Request $mockRequest -Response $mockResponse -Method 'POST' -Path '/audit/frontend-error' -Config $mockConfig

            $result | Should -Be $true
            Assert-MockCalled Read-EMSRequestBody -Times 1 -ModuleName Temp.EMS.API.Scan
            Assert-MockCalled Invoke-PGQuery -Times 1 -ModuleName Temp.EMS.API.Scan
            Assert-MockCalled Write-JsonResponse -Times 1 -ModuleName Temp.EMS.API.Scan -ParameterFilter { $StatusCode -eq 204 }
        }

        It "should rate-limit POST /audit/frontend-error" {
            Mock Read-EMSRequestBody { return '{"message":"error", "stack":"stack", "url":"http://test"}' } -ModuleName Temp.EMS.API.Scan
            Mock Invoke-PGQuery { } -ModuleName Temp.EMS.API.Scan
            Mock Write-JsonResponse { } -ModuleName Temp.EMS.API.Scan
            Mock Get-RequestUserContext { return [pscustomobject]@{ Username = 'testAdmin' } } -ModuleName Temp.EMS.API.Scan

            # Perform 6 requests to trigger rate limiting
            for ($i = 0; $i -lt 6; $i++) {
                $result = Invoke-ScanRoutes -Request $mockRequest -Response $mockResponse -Method 'POST' -Path '/audit/frontend-error' -Config $mockConfig
                $result | Should -Be $true
            }

            Assert-MockCalled Read-EMSRequestBody -Times 5 -ModuleName Temp.EMS.API.Scan
            Assert-MockCalled Write-JsonResponse -Times 1 -ModuleName Temp.EMS.API.Scan -ParameterFilter { $StatusCode -eq 429 }
        }

        It "should return false for unknown route" {
            $result = Invoke-ScanRoutes -Request $mockRequest -Response $mockResponse -Method 'GET' -Path '/unknown/route' -Config $mockConfig

            $result | Should -Be $false
        }
    }

    Context "Test-FrontendErrorAllowed" {
        BeforeAll {
            Import-Module $modulePath -Force
        }

        It "allows requests under the limit" {
            $ip = "127.0.0.1"
            InModuleScope EMS.API.Scan {
                $script:FrontendErrorBuckets.Clear()

                for ($i = 0; $i -lt 5; $i++) {
                    $result = Test-FrontendErrorAllowed -Ip $ip
                    $result | Should -Be $true
                }
            }
        }

        It "blocks requests over the limit" {
            $ip = "127.0.0.2"
            InModuleScope EMS.API.Scan {
                $script:FrontendErrorBuckets.Clear()

                for ($i = 0; $i -lt 5; $i++) {
                    $result = Test-FrontendErrorAllowed -Ip $ip
                    $result | Should -Be $true
                }

                $result = Test-FrontendErrorAllowed -Ip $ip
                $result | Should -Be $false
            }
        }

        It "resets the limit after the window expires" {
            $ip = "127.0.0.3"
            InModuleScope EMS.API.Scan {
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
