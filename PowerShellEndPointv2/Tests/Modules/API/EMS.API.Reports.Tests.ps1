BeforeAll {
    $global:ModulePath = Resolve-Path "$PSScriptRoot/../../../Modules/API/EMS.API.Reports.psm1"

    # Dummy global definitions to avoid missing dependency errors during Import-Module
    function global:Invoke-PGQuery {}
    function global:Test-ViewerAccessRequirement {}
    function global:Write-JsonResponse {}

    Import-Module $global:ModulePath -Force
}

Describe "Invoke-ReportRoutes" {

    # Setup some mock objects
    BeforeEach {
        $script:Request = $null
        $script:Response = $null
        $script:Config = [pscustomobject]@{ SomeSetting = "Value" }
    }

    Context "GET /historical/timeline/:hostname" {
        It "Should return true but not query data if Test-ViewerAccessRequirement fails" {
            Mock Test-ViewerAccessRequirement { return $false } -ModuleName "EMS.API.Reports"
            Mock Invoke-PGQuery {} -ModuleName "EMS.API.Reports"

            $result = Invoke-ReportRoutes -Request $null -Response $null -Method "GET" -Path "/historical/timeline/server01" -Config $script:Config

            $result | Should -Be $true
            Assert-MockCalled Test-ViewerAccessRequirement -ModuleName "EMS.API.Reports" -Times 1 -Exactly
            Assert-MockCalled Invoke-PGQuery -ModuleName "EMS.API.Reports" -Times 0 -Exactly
        }

        It "Should query data and write JSON response on happy path" {
            Mock Test-ViewerAccessRequirement { return $true } -ModuleName "EMS.API.Reports"
            Mock Invoke-PGQuery { return @( @{ health_score = 100 } ) } -ModuleName "EMS.API.Reports"
            Mock Write-JsonResponse {} -ModuleName "EMS.API.Reports"

            $result = Invoke-ReportRoutes -Request $null -Response $null -Method "GET" -Path "/historical/timeline/server01" -Config $script:Config

            $result | Should -Be $true

            Assert-MockCalled Test-ViewerAccessRequirement -ModuleName "EMS.API.Reports" -Times 1 -Exactly
            Assert-MockCalled Invoke-PGQuery -ModuleName "EMS.API.Reports" -Times 1 -Exactly
            Assert-MockCalled Write-JsonResponse -ModuleName "EMS.API.Reports" -Times 1 -Exactly
        }
    }

    Context "GET /historical/heatmap" {
        It "Should return true but not query data if Test-ViewerAccessRequirement fails" {
            Mock Test-ViewerAccessRequirement { return $false } -ModuleName "EMS.API.Reports"
            Mock Invoke-PGQuery {} -ModuleName "EMS.API.Reports"

            $result = Invoke-ReportRoutes -Request $null -Response $null -Method "GET" -Path "/historical/heatmap" -Config $script:Config

            $result | Should -Be $true
            Assert-MockCalled Test-ViewerAccessRequirement -ModuleName "EMS.API.Reports" -Times 1 -Exactly
            Assert-MockCalled Invoke-PGQuery -ModuleName "EMS.API.Reports" -Times 0 -Exactly
        }

        It "Should query data and write JSON response on happy path" {
            Mock Test-ViewerAccessRequirement { return $true } -ModuleName "EMS.API.Reports"
            Mock Invoke-PGQuery { return @( @{ health_score = 90 } ) } -ModuleName "EMS.API.Reports"
            Mock Write-JsonResponse {} -ModuleName "EMS.API.Reports"

            $result = Invoke-ReportRoutes -Request $null -Response $null -Method "GET" -Path "/historical/heatmap" -Config $script:Config

            $result | Should -Be $true

            Assert-MockCalled Test-ViewerAccessRequirement -ModuleName "EMS.API.Reports" -Times 1 -Exactly
            Assert-MockCalled Invoke-PGQuery -ModuleName "EMS.API.Reports" -Times 1 -Exactly
            Assert-MockCalled Write-JsonResponse -ModuleName "EMS.API.Reports" -Times 1 -Exactly
        }
    }

    Context "GET /historical/drift" {
        It "Should return true but not query data if Test-ViewerAccessRequirement fails" {
            Mock Test-ViewerAccessRequirement { return $false } -ModuleName "EMS.API.Reports"
            Mock Invoke-PGQuery {} -ModuleName "EMS.API.Reports"

            $result = Invoke-ReportRoutes -Request $null -Response $null -Method "GET" -Path "/historical/drift" -Config $script:Config

            $result | Should -Be $true
            Assert-MockCalled Test-ViewerAccessRequirement -ModuleName "EMS.API.Reports" -Times 1 -Exactly
            Assert-MockCalled Invoke-PGQuery -ModuleName "EMS.API.Reports" -Times 0 -Exactly
        }

        It "Should query data and write JSON response on happy path" {
            Mock Test-ViewerAccessRequirement { return $true } -ModuleName "EMS.API.Reports"
            Mock Invoke-PGQuery { return @( @{ drop = 15 } ) } -ModuleName "EMS.API.Reports"
            Mock Write-JsonResponse {} -ModuleName "EMS.API.Reports"

            $result = Invoke-ReportRoutes -Request $null -Response $null -Method "GET" -Path "/historical/drift" -Config $script:Config

            $result | Should -Be $true

            Assert-MockCalled Test-ViewerAccessRequirement -ModuleName "EMS.API.Reports" -Times 1 -Exactly
            Assert-MockCalled Invoke-PGQuery -ModuleName "EMS.API.Reports" -Times 1 -Exactly
            Assert-MockCalled Write-JsonResponse -ModuleName "EMS.API.Reports" -Times 1 -Exactly
        }
    }

    Context "GET /historical/cutover" {
        BeforeAll {
            # Create a wrapper function in global scope that bypasses strong typing
            InModuleScope "EMS.API.Reports" {
                $funcInfo = Get-Command "Invoke-ReportRoutes"
                $sb = $funcInfo.ScriptBlock.ToString()
                $sb = $sb -replace '\[System.Net.HttpListenerRequest\]\$Request', '$Request'
                $sb = $sb -replace '\[System.Net.HttpListenerResponse\]\$Response', '$Response'
                Set-Item -Path function:global:Invoke-ReportRoutes-Untyped -Value ([scriptblock]::Create($sb))
            }
        }

        It "Should return true but not query data if Test-ViewerAccessRequirement fails" {
            Mock Test-ViewerAccessRequirement { return $false }
            Mock Invoke-PGQuery {}

            $result = Invoke-ReportRoutes-Untyped -Request $null -Response $null -Method "GET" -Path "/historical/cutover" -Config $script:Config

            $result | Should -Be $true
            Assert-MockCalled Test-ViewerAccessRequirement -Times 1 -Exactly
            Assert-MockCalled Invoke-PGQuery -Times 0 -Exactly
        }

        It "Should return 400 bad request if before or after dates are missing" {
            Mock Test-ViewerAccessRequirement { return $true }
            Mock Write-JsonResponse {}
            Mock Invoke-PGQuery {}

            $mockRequest = [pscustomobject]@{
                QueryString = @{}
            }

            $result = Invoke-ReportRoutes-Untyped -Request $mockRequest -Response $null -Method "GET" -Path "/historical/cutover" -Config $script:Config

            $result | Should -Be $true

            Assert-MockCalled Write-JsonResponse -Times 1 -Exactly
            Assert-MockCalled Invoke-PGQuery -Times 0 -Exactly
        }

        It "Should query data and write JSON response on happy path" {
            Mock Test-ViewerAccessRequirement { return $true }
            Mock Invoke-PGQuery { return @( @{ change = 5 } ) }
            Mock Write-JsonResponse {}

            $mockRequest = [pscustomobject]@{
                QueryString = @{
                    'before' = '2023-10-01'
                    'after'  = '2023-10-15'
                }
            }

            $result = Invoke-ReportRoutes-Untyped -Request $mockRequest -Response $null -Method "GET" -Path "/historical/cutover" -Config $script:Config

            $result | Should -Be $true

            Assert-MockCalled Test-ViewerAccessRequirement -Times 1 -Exactly
            Assert-MockCalled Invoke-PGQuery -Times 1 -Exactly
            Assert-MockCalled Write-JsonResponse -Times 1 -Exactly
        }
    }

    Context "Unknown Routes" {
        It "Should return false for an unknown route" {
            $result = Invoke-ReportRoutes -Request $null -Response $null -Method "POST" -Path "/historical/timeline/server01" -Config $script:Config
            $result | Should -Be $false
        }
    }
}
