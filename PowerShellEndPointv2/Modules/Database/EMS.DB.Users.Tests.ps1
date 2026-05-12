Describe "Get-EMSUser" {
    BeforeAll {
        function global:Invoke-PGQuery { param($Query, $Parameters, [switch]$NonQuery) }
        function global:Write-EMSLog { param($Message, $Severity) }
        Import-Module "$PSScriptRoot/EMS.DB.Users.psm1" -Force
    }

    It "Should retrieve a user by Username" {
        Mock Invoke-PGQuery {
            return @(
                [pscustomobject]@{ user_id = 1; username = "testuser"; role = "admin" }
            )
        } -ModuleName EMS.DB.Users

        $result = Get-EMSUser -Username "testuser"

        $result.username | Should -Be "testuser"
        $result.user_id | Should -Be 1
        Assert-MockCalled Invoke-PGQuery -Times 1 -ParameterFilter {
            $Query -match "username = @username" -and $Parameters.username -eq "testuser"
        } -ModuleName EMS.DB.Users
    }

    It "Should retrieve a user by UserId" {
        Mock Invoke-PGQuery {
            return @(
                [pscustomobject]@{ user_id = 2; username = "user2"; role = "viewer" }
            )
        } -ModuleName EMS.DB.Users

        $result = Get-EMSUser -UserId 2

        $result.user_id | Should -Be 2
        Assert-MockCalled Invoke-PGQuery -Times 1 -ParameterFilter {
            $Query -match "user_id = @userid" -and $Parameters.userid -eq 2
        } -ModuleName EMS.DB.Users
    }

    It "Should return only the first result if multiple are returned" {
        Mock Invoke-PGQuery {
            return @(
                [pscustomobject]@{ user_id = 1; username = "testuser" },
                [pscustomobject]@{ user_id = 2; username = "testuser" }
            )
        } -ModuleName EMS.DB.Users

        $result = Get-EMSUser -Username "testuser"

        $result.user_id | Should -Be 1
        $result -is [array] | Should -Be $false
    }

    It "Should return null and log error on exception" {
        Mock Invoke-PGQuery { throw "Database connection failed" } -ModuleName EMS.DB.Users
        Mock Write-EMSLog {} -ModuleName EMS.DB.Users

        $result = Get-EMSUser -Username "erroruser"

        $result | Should -BeNullOrEmpty
        Assert-MockCalled Write-EMSLog -Times 1 -ParameterFilter {
            $Message -match "Error retrieving user: Database connection failed" -and $Severity -eq 'Error'
        } -ModuleName EMS.DB.Users
    }
}
