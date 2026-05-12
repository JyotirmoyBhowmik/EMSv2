# Set up global mock functions
function global:Write-EMSLog {}
function global:Invoke-PGQuery {}

$sut = "$PSScriptRoot/../../../Modules/Database/EMS.DB.Users.psm1"
if (-not (Test-Path $sut)) {
    $sut = (Resolve-Path "./PowerShellEndPointv2/Modules/Database/EMS.DB.Users.psm1").Path
}

Import-Module $sut -Force

Describe "Update-EMSUserLogin" {
    AfterAll {
        Remove-Module EMS.DB.Users -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Write-EMSLog -ErrorAction SilentlyContinue
        Remove-Item Function:\global:Invoke-PGQuery -ErrorAction SilentlyContinue
    }

    InModuleScope EMS.DB.Users {
        Context "When updating user login succeeds" {
            It "Returns true when rows are affected" {
                $script:invokePGQueryCalls = @()
                function global:Invoke-PGQuery {
                    param($Query, $Parameters, [switch]$NonQuery)
                    $script:invokePGQueryCalls += @{ Query = $Query; Parameters = $Parameters; NonQuery = $NonQuery.IsPresent }
                    return 1
                }

                $result = Update-EMSUserLogin -UserId 1

                $result | Should -Be $true
                $script:invokePGQueryCalls.Count | Should -Be 1
                $script:invokePGQueryCalls[0].Query | Should -Be "UPDATE users SET last_login = NOW(), failed_login_attempts = 0 WHERE user_id = @userid"
                $script:invokePGQueryCalls[0].Parameters.userid | Should -Be 1
            }
        }

        Context "When updating user login affects zero rows" {
            It "Returns false when no rows are affected" {
                $script:invokePGQueryCalls = @()
                function global:Invoke-PGQuery {
                    param($Query, $Parameters, [switch]$NonQuery)
                    $script:invokePGQueryCalls += @{ Query = $Query; Parameters = $Parameters; NonQuery = $NonQuery.IsPresent }
                    return 0
                }

                $result = Update-EMSUserLogin -UserId 2

                $result | Should -Be $false
                $script:invokePGQueryCalls.Count | Should -Be 1
                $script:invokePGQueryCalls[0].Parameters.userid | Should -Be 2
            }
        }

        Context "When an exception occurs" {
            It "Logs an error and returns false" {
                $script:writeEMSLogCalls = @()
                function global:Invoke-PGQuery { throw "Database connection failed" }
                function global:Write-EMSLog {
                    param($Message, $Severity)
                    $script:writeEMSLogCalls += @{ Message = $Message; Severity = $Severity }
                }

                $result = Update-EMSUserLogin -UserId 3

                $result | Should -Be $false
                $script:writeEMSLogCalls.Count | Should -Be 1
                $script:writeEMSLogCalls[0].Severity | Should -Be 'Error'
                $script:writeEMSLogCalls[0].Message | Should -Match "Error updating user login: "
            }
        }
    }
}
