BeforeAll {
    $global:ModulePath = Resolve-Path "$PSScriptRoot/../../../Modules/Authentication/StandaloneAuth.psm1"

    function global:Invoke-PGQuery {}
    function global:Initialize-PostgreSQLConnection {}
    function global:Write-EMSLog {}

    Import-Module $global:ModulePath -Force
}

Describe "StandaloneAuth - Test-PasswordHash" {
    Context "When testing a valid password against its hash" {
        It "returns true for a correct password" {
            $password = "MySecurePassword123!"
            $hashData = New-PasswordHash -Password $password

            $result = Test-PasswordHash -Password $password -Salt $hashData.Salt -StoredHash $hashData.Hash

            $result | Should -Be $true
        }

        It "handles very long passwords" {
            $password = "A" * 1000
            $hashData = New-PasswordHash -Password $password

            $result = Test-PasswordHash -Password $password -Salt $hashData.Salt -StoredHash $hashData.Hash

            $result | Should -Be $true
        }

        It "handles passwords with special characters" {
            $password = "!@#$%^&*()_+{}|[]\:`~<>?,./"
            $hashData = New-PasswordHash -Password $password

            $result = Test-PasswordHash -Password $password -Salt $hashData.Salt -StoredHash $hashData.Hash

            $result | Should -Be $true
        }
    }

    Context "When testing an invalid password against a hash" {
        It "returns false for an incorrect password" {
            $password = "MySecurePassword123!"
            $wrongPassword = "WrongPassword456"
            $hashData = New-PasswordHash -Password $password

            $result = Test-PasswordHash -Password $wrongPassword -Salt $hashData.Salt -StoredHash $hashData.Hash

            $result | Should -Be $false
        }

        It "returns false when given a different salt" {
            $password = "MySecurePassword123!"
            $hashData = New-PasswordHash -Password $password
            $otherHashData = New-PasswordHash -Password "OtherPassword"

            $result = Test-PasswordHash -Password $password -Salt $otherHashData.Salt -StoredHash $hashData.Hash

            $result | Should -Be $false
        }

        It "returns false when given a different stored hash" {
            $password = "MySecurePassword123!"
            $hashData = New-PasswordHash -Password $password
            $otherHashData = New-PasswordHash -Password "OtherPassword"

            $result = Test-PasswordHash -Password $password -Salt $hashData.Salt -StoredHash $otherHashData.Hash

            $result | Should -Be $false
        }
    }

    Context "When given missing parameters" {
        It "throws an error if password is empty string or null" {
            $password = ""
            { Test-PasswordHash -Password $password -Salt "test_salt" -StoredHash "test_hash" } | Should -Throw -ErrorId "ParameterArgumentValidationErrorEmptyStringNotAllowed,Test-PasswordHash"
        }

        It "throws an error if salt is missing" {
            $password = "password123"
            { Test-PasswordHash -Password $password -StoredHash "test_hash" } | Should -Throw -ErrorId "MissingMandatoryParameter,Test-PasswordHash"
        }

        It "throws an error if stored hash is missing" {
            $password = "password123"
            { Test-PasswordHash -Password $password -Salt "test_salt" } | Should -Throw -ErrorId "MissingMandatoryParameter,Test-PasswordHash"
        }
    }
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
