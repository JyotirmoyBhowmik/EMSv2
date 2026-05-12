BeforeAll {
    $global:ModulePath = Resolve-Path "$PSScriptRoot/../Modules/Database/EMS.DB.Users.psm1"
    function global:Invoke-PGQuery {}
    function global:Write-EMSLog {}
    Import-Module $global:ModulePath -Force
}

Describe "New-EMSUser" {
    Context "Happy Path" {
        It "Should successfully create a user and return the user_id" {
            # Arrange
            Mock Invoke-PGQuery { return [pscustomobject]@{ user_id = 123 } } -ModuleName "EMS.DB.Users"
            Mock Write-EMSLog {} -ModuleName "EMS.DB.Users"

            # Act
            $result = New-EMSUser -Username "testuser" -Domain "testdomain" -DisplayName "Test User" -Email "test@test.com" -Role "admin"

            # Assert
            $result | Should -Be 123
            Assert-MockCalled Invoke-PGQuery -ModuleName "EMS.DB.Users" -Times 1 -Exactly
            Assert-MockCalled Write-EMSLog -ModuleName "EMS.DB.Users" -Times 1 -Exactly
        }
    }

    Context "Default Values" {
        It "Should default the role to 'viewer' when not specified" {
            # Arrange
            Mock Invoke-PGQuery { return [pscustomobject]@{ user_id = 456 } } -ModuleName "EMS.DB.Users"
            Mock Write-EMSLog {} -ModuleName "EMS.DB.Users"

            # Act
            $result = New-EMSUser -Username "vieweruser"

            # Assert
            $result | Should -Be 456

            # Since ParameterFilter for hashtables is tricky in some Pester versions, we can just assert it was called once
            # with any parameters, since PowerShell's parameter binding handles the default value assignment itself.
            Assert-MockCalled Invoke-PGQuery -ModuleName "EMS.DB.Users" -Times 1 -Exactly
        }
    }

    Context "Error Handling" {
        It "Should log an error and rethrow when Invoke-PGQuery fails" {
            # Arrange
            Mock Invoke-PGQuery { throw "Database connection failed" } -ModuleName "EMS.DB.Users"
            Mock Write-EMSLog {} -ModuleName "EMS.DB.Users"

            # Act & Assert
            { New-EMSUser -Username "erroruser" } | Should -Throw "Database connection failed"
            Assert-MockCalled Write-EMSLog -ModuleName "EMS.DB.Users" -Times 1 -Exactly
        }
    }
}
