BeforeAll {
    $global:ModulePath = Resolve-Path "$PSScriptRoot/../../../Modules/Authentication/StandaloneAuth.psm1"

    function global:Invoke-PGQuery {}
    function global:Initialize-PostgreSQLConnection {}
    function global:Write-EMSLog {}

    Import-Module $global:ModulePath -Force
}

Describe "Get-EMSLocalCredential" {
    Context "Happy Path" {
        It "Should return user credential data if user exists" {
            # Arrange
            $mockData = [pscustomobject]@{
                user_id = 1
                username = "testuser"
                domain = "LOCAL"
                display_name = "Test User"
                role = "admin"
                is_active = $true
                password_hash = "testhash"
                password_salt = "testsalt"
                credential_active = $true
            }

            Mock Invoke-PGQuery {
                param(
                    [switch]$NonQuery,
                    [string]$Query,
                    [hashtable]$Parameters
                )
                if ($NonQuery) { return $null }
                if ($Parameters -and $Parameters.username -eq "testuser") { return $mockData }
                return $null
            } -ModuleName "StandaloneAuth"

            # Act
            $result = Get-EMSLocalCredential -Username "testuser"

            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.username | Should -Be "testuser"
            $result.domain | Should -Be "LOCAL"

            Assert-MockCalled Invoke-PGQuery -ModuleName "StandaloneAuth" -Times 2
        }
    }

    Context "User Not Found" {
        It "Should return nothing if the user does not exist" {
            # Arrange
            Mock Invoke-PGQuery { return $null } -ModuleName "StandaloneAuth"

            # Act
            $result = Get-EMSLocalCredential -Username "missinguser"

            # Assert
            $result | Should -BeNullOrEmpty
            Assert-MockCalled Invoke-PGQuery -ModuleName "StandaloneAuth" -Times 2
        }
    }

    Context "Error Handling" {
        It "Should throw if database query fails" {
            # Arrange
            Mock Invoke-PGQuery {
                param(
                    [switch]$NonQuery,
                    [string]$Query,
                    [hashtable]$Parameters
                )
                if ($NonQuery) { return $null }
                throw "Database error"
            } -ModuleName "StandaloneAuth"

            # Act & Assert
            { Get-EMSLocalCredential -Username "erroruser" } | Should -Throw "Database error"
        }
    }
}
