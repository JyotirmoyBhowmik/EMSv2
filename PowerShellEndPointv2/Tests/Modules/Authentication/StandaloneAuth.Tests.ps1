BeforeAll {
    $global:ModulePath = Resolve-Path "$PSScriptRoot/../../../Modules/Authentication/StandaloneAuth.psm1"
    function global:Invoke-PGQuery {}
    function global:Initialize-PostgreSQLConnection {}
    function global:Write-EMSLog {}
    Import-Module $global:ModulePath -Force
}

Describe "Ensure-LocalCredentialTable" {
    Context "Happy Path" {
        It "Should execute the CREATE TABLE query" {
            # Arrange
            Mock Invoke-PGQuery {} -ModuleName "StandaloneAuth"

            # Act
            & (Get-Module "StandaloneAuth") Ensure-LocalCredentialTable

            # Assert
            Assert-MockCalled Invoke-PGQuery -ModuleName "StandaloneAuth" -Times 1 -Exactly
        }
    }

    Context "Error Handling" {
        It "Should throw when Invoke-PGQuery fails" {
            # Arrange
            Mock Invoke-PGQuery { throw "Database execution failed" } -ModuleName "StandaloneAuth"

            # Act & Assert
            { & (Get-Module "StandaloneAuth") Ensure-LocalCredentialTable } | Should -Throw "Database execution failed"
        }
    }
}
