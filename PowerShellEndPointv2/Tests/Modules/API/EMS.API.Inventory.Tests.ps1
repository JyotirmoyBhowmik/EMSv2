Describe "Invoke-InventoryRoutes" {
    BeforeAll {
        $rootPath = "$PSScriptRoot/../../.."

        function global:Test-ViewerAccessRequirement { return $true }
        function global:Test-AdminAccessRequirement { return $true }
        function global:Test-AdminAccess { return $false }
        function global:Invoke-PGQuery { return @() }
        function global:Write-JsonResponse { }
        function global:Read-JsonBody { }

        # Load the module, but don't force strict type constraints on Request/Response for testing
        $moduleText = Get-Content "$rootPath/Modules/API/EMS.API.Inventory.psm1" -Raw
        $moduleText = $moduleText -replace '\[System\.Net\.HttpListenerRequest\]\$Request', '$Request'
        $moduleText = $moduleText -replace '\[System\.Net\.HttpListenerResponse\]\$Response', '$Response'
        $global:testModulePath = "$rootPath/Modules/API/EMS.API.Inventory.Test.psm1"
        Set-Content -Path $global:testModulePath -Value $moduleText

        Import-Module $global:testModulePath -Force
    }

    AfterAll {
        if (Test-Path $global:testModulePath) {
            Remove-Item $global:testModulePath -Force
        }
    }

    BeforeEach {
        $global:JsonResponseCalls = @()
        $global:PGQueryCalls = @()

        Mock Test-ViewerAccessRequirement { return $true } -ModuleName EMS.API.Inventory.Test
        Mock Test-AdminAccessRequirement { return $true } -ModuleName EMS.API.Inventory.Test
        Mock Test-AdminAccess { return $false } -ModuleName EMS.API.Inventory.Test

        Mock Invoke-PGQuery {
            param($Query, $Parameters, [switch]$NonQuery)
            $global:PGQueryCalls += @{ Query = $Query; Parameters = $Parameters; NonQuery = $NonQuery }
            return @()
        } -ModuleName EMS.API.Inventory.Test

        Mock Write-JsonResponse {
            param($Request, $Response, $StatusCode, $Data)
            $global:JsonResponseCalls += @{ StatusCode = $StatusCode; Data = $Data }
        } -ModuleName EMS.API.Inventory.Test

        Mock Read-JsonBody { return [pscustomobject]@{} } -ModuleName EMS.API.Inventory.Test
    }

    Context "Route Unhandled" {
        It "Returns false if the route does not match" {
            $Request = [pscustomobject]@{ QueryString = @{} }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "GET" -Path "/unknown" -Config @{}
            $result | Should -Be $false
            $global:JsonResponseCalls.Count | Should -Be 0
        }
    }

    Context "GET /computers" {
        It "Returns a list of computers" {
            Mock Invoke-PGQuery {
                param($Query, $Parameters, [switch]$NonQuery)
                return @(
                    [pscustomobject]@{ computer_name = "PC-01"; ip_address = "10.0.0.1" }
                )
            } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ QueryString = @{} }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "GET" -Path "/computers" -Config @{}

            $result | Should -Be $true

            $global:JsonResponseCalls.Count | Should -Be 1
            $global:JsonResponseCalls[0].StatusCode | Should -Be 200
            $global:JsonResponseCalls[0].Data.success | Should -Be $true
            $global:JsonResponseCalls[0].Data.computers.Count | Should -Be 1
            $global:JsonResponseCalls[0].Data.computers[0].computer_name | Should -Be "PC-01"

            Assert-MockCalled Invoke-PGQuery -ModuleName EMS.API.Inventory.Test -Times 1 -Exactly
        }

        It "Requires Viewer Access" {
            Mock Test-ViewerAccessRequirement { return $false } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ QueryString = @{} }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "GET" -Path "/computers" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 0
        }
    }

    Context "POST /computers" {
        It "Requires Admin Access" {
            Mock Test-AdminAccessRequirement { return $false } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "POST" -Path "/computers" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 0
        }

        It "Registers a computer successfully" {
            Mock Read-JsonBody {
                return [pscustomobject]@{ computerName = "PC-01"; ipAddress = "10.0.0.1"; computerType = "Laptop"; operatingSystem = "Windows 11" }
            } -ModuleName EMS.API.Inventory.Test

            Mock Invoke-PGQuery {
                param($Query, $Parameters, [switch]$NonQuery)
                $global:PGQueryCalls += @{ Query = $Query; Parameters = $Parameters; NonQuery = $NonQuery }
            } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "POST" -Path "/computers" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 1
            $global:JsonResponseCalls[0].StatusCode | Should -Be 200
            $global:JsonResponseCalls[0].Data.success | Should -Be $true

            Assert-MockCalled Invoke-PGQuery -ModuleName EMS.API.Inventory.Test -Times 1 -Exactly
            $global:PGQueryCalls[0].Query | Should -Match "INSERT INTO computers"
            $global:PGQueryCalls[0].Parameters.computerName | Should -Be "PC-01"
            $global:PGQueryCalls[0].Parameters.ipAddress | Should -Be "10.0.0.1"
            $global:PGQueryCalls[0].Parameters.computerType | Should -Be "Laptop"
        }

        It "Returns 400 if required fields are missing" {
            Mock Read-JsonBody {
                return [pscustomobject]@{ computerType = "Laptop" }
            } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "POST" -Path "/computers" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 1
            $global:JsonResponseCalls[0].StatusCode | Should -Be 400
            $global:JsonResponseCalls[0].Data.success | Should -Be $false
            $global:JsonResponseCalls[0].Data.message | Should -Match "Computer name and IP address are required"

            Assert-MockCalled Invoke-PGQuery -ModuleName EMS.API.Inventory.Test -Times 0 -Exactly
        }
    }

    Context "GET /computers/:name" {
        It "Returns a single computer" {
            Mock Invoke-PGQuery {
                param($Query, $Parameters, [switch]$NonQuery)
                if ($Query -match "FROM computers WHERE computer_name") {
                    return @( [pscustomobject]@{ computer_name = "PC-01"; ip_address = "10.0.0.1" } )
                } elseif ($Query -match "FROM computer_ad_users WHERE computer_name") {
                    return @( [pscustomobject]@{ ad_username = "user1" } )
                }
                return @()
            } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "GET" -Path "/computers/PC-01" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 1
            $global:JsonResponseCalls[0].StatusCode | Should -Be 200
            $global:JsonResponseCalls[0].Data.success | Should -Be $true
            $global:JsonResponseCalls[0].Data.computer.computer_name | Should -Be "PC-01"
            $global:JsonResponseCalls[0].Data.users[0].ad_username | Should -Be "user1"

            Assert-MockCalled Invoke-PGQuery -ModuleName EMS.API.Inventory.Test -Times 2 -Exactly
        }

        It "Returns 404 if computer not found" {
            Mock Invoke-PGQuery {
                param($Query, $Parameters, [switch]$NonQuery)
                return @()
            } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "GET" -Path "/computers/UnknownPC" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 1
            $global:JsonResponseCalls[0].StatusCode | Should -Be 404
            $global:JsonResponseCalls[0].Data.success | Should -Be $false
        }
    }

    Context "GET /results/:id" {
        It "Returns a scan result" {
            Mock Invoke-PGQuery {
                param($Query, $Parameters, [switch]$NonQuery)
                if ($Query -match "FROM scans WHERE scan_id") {
                    return @( [pscustomobject]@{ scan_id = "00000000-0000-0000-0000-000000000000"; target = "PC-01" } )
                }
                return @()
            } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "GET" -Path "/results/00000000-0000-0000-0000-000000000000" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 1
            $global:JsonResponseCalls[0].StatusCode | Should -Be 200
            $global:JsonResponseCalls[0].Data.success | Should -Be $true
            $global:JsonResponseCalls[0].Data.target | Should -Be "PC-01"
        }

        It "Returns 400 for invalid guid" {
            $Request = [pscustomobject]@{ }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "GET" -Path "/results/invalid-guid" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 1
            $global:JsonResponseCalls[0].StatusCode | Should -Be 400
            $global:JsonResponseCalls[0].Data.success | Should -Be $false
        }

        It "Returns 404 if result not found" {
            Mock Invoke-PGQuery {
                param($Query, $Parameters, [switch]$NonQuery)
                return @()
            } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "GET" -Path "/results/00000000-0000-0000-0000-000000000000" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 1
            $global:JsonResponseCalls[0].StatusCode | Should -Be 404
            $global:JsonResponseCalls[0].Data.success | Should -Be $false
        }
    }

    Context "GET /dashboard/stats" {
        It "Returns dashboard stats" {
            Mock Invoke-PGQuery {
                param($Query, $Parameters, [switch]$NonQuery)
                return @( [pscustomobject]@{ total = 10; active = 5 } )
            } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ QueryString = @{} }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "GET" -Path "/dashboard/stats" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 1
            $global:JsonResponseCalls[0].StatusCode | Should -Be 200
            $global:JsonResponseCalls[0].Data.success | Should -Be $true
            $global:JsonResponseCalls[0].Data.stats.totalComputers | Should -Be 10
        }
    }

    Context "GET /compliance/report" {
        It "Returns compliance report" {
            Mock Invoke-PGQuery {
                param($Query, $Parameters, [switch]$NonQuery)
                return @( [pscustomobject]@{ computer_name = "PC-01"; compliance_status = "Compliant" } )
            } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ QueryString = @{} }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "GET" -Path "/compliance/report" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 1
            $global:JsonResponseCalls[0].StatusCode | Should -Be 200
            $global:JsonResponseCalls[0].Data.success | Should -Be $true
            $global:JsonResponseCalls[0].Data.report.Count | Should -Be 1
            $global:JsonResponseCalls[0].Data.report[0].computer_name | Should -Be "PC-01"
        }

        It "Returns 500 if database query fails" {
            Mock Invoke-PGQuery { throw "DB Error" } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ QueryString = @{} }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "GET" -Path "/compliance/report" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 1
            $global:JsonResponseCalls[0].StatusCode | Should -Be 500
            $global:JsonResponseCalls[0].Data.success | Should -Be $false
            $global:JsonResponseCalls[0].Data.error | Should -Match "DB Error"
        }
    }

    Context "GET /compliance/history" {
        It "Returns compliance history" {
            Mock Invoke-PGQuery {
                param($Query, $Parameters, [switch]$NonQuery)
                return @( [pscustomobject]@{ scan_date = "2023-01-01"; total_scans = 5 } )
            } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ QueryString = @{} }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "GET" -Path "/compliance/history" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 1
            $global:JsonResponseCalls[0].StatusCode | Should -Be 200
            $global:JsonResponseCalls[0].Data.success | Should -Be $true
            $global:JsonResponseCalls[0].Data.history.Count | Should -Be 1
            $global:JsonResponseCalls[0].Data.history[0].scan_date | Should -Be "2023-01-01"
        }

        It "Returns 500 if database query fails" {
            Mock Invoke-PGQuery { throw "DB Error" } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ QueryString = @{} }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "GET" -Path "/compliance/history" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 1
            $global:JsonResponseCalls[0].StatusCode | Should -Be 500
            $global:JsonResponseCalls[0].Data.success | Should -Be $false
            $global:JsonResponseCalls[0].Data.error | Should -Match "DB Error"
        }
    }

    Context "GET /results" {
        It "Returns a list of scan results" {
            Mock Invoke-PGQuery {
                param($Query, $Parameters, [switch]$NonQuery)
                return @( [pscustomobject]@{ scan_id = "0000"; target = "PC-01" } )
            } -ModuleName EMS.API.Inventory.Test

            $Request = [pscustomobject]@{ QueryString = @{} }
            $Response = [pscustomobject]@{ }

            $result = Invoke-InventoryRoutes -Request $Request -Response $Response -Method "GET" -Path "/results" -Config @{}

            $result | Should -Be $true
            $global:JsonResponseCalls.Count | Should -Be 1
            $global:JsonResponseCalls[0].StatusCode | Should -Be 200
            $global:JsonResponseCalls[0].Data.success | Should -Be $true
            $global:JsonResponseCalls[0].Data.results.Count | Should -Be 1
            $global:JsonResponseCalls[0].Data.results[0].target | Should -Be "PC-01"
        }
    }
}
