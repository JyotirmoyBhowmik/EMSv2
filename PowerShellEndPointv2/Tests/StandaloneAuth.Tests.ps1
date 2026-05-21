Describe 'StandaloneAuth - New-PasswordHash' {
    BeforeAll {
        # Mock global database functions to prevent DB connection exceptions upon import
        function global:Invoke-PGQuery {}
        function global:Initialize-PostgreSQLConnection {}

        Import-Module "$PSScriptRoot\..\Modules\Authentication\StandaloneAuth.psm1" -Force
    }

    It 'generates a hash and salt when no salt is provided' {
        $result = New-PasswordHash -Password "MySecret123"

        $result | Should -Not -BeNullOrEmpty
        $result.Hash | Should -Not -BeNullOrEmpty
        $result.Salt | Should -Not -BeNullOrEmpty
    }

    It 'uses provided salt to generate consistent hash' {
        $password = "MySecret123"
        $firstResult = New-PasswordHash -Password $password
        $salt = $firstResult.Salt

        $secondResult = New-PasswordHash -Password $password -Salt $salt

        $secondResult.Hash | Should -Be $firstResult.Hash
        $secondResult.Salt | Should -Be $salt
    }

    It 'generates different hashes for different passwords' {
        $result1 = New-PasswordHash -Password "PasswordA"
        $result2 = New-PasswordHash -Password "PasswordB"

        $result1.Hash | Should -Not -Be $result2.Hash
    }

    It 'generates different salts for the same password when salt is not provided' {
        $result1 = New-PasswordHash -Password "SamePassword"
        $result2 = New-PasswordHash -Password "SamePassword"

        $result1.Salt | Should -Not -Be $result2.Salt
        $result1.Hash | Should -Not -Be $result2.Hash
    }

    It 'throws when password is empty string' {
        { New-PasswordHash -Password "" } | Should -Throw
    }

    It 'throws when password is not provided' {
        # Using $null to force a throw without interactive prompt
        { New-PasswordHash -Password $null } | Should -Throw
    }
}
