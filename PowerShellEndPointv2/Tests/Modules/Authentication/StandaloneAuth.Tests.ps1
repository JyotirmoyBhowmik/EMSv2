Describe "StandaloneAuth - Test-PasswordHash" {
    BeforeAll {
        function global:Invoke-PGQuery {}
        function global:Initialize-PostgreSQLConnection {}
        function global:Write-EMSLog {}

        Import-Module "$PSScriptRoot/../../../Modules/Authentication/StandaloneAuth.psm1" -Force
    }

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
