BeforeAll {
    $global:ModulePath = Resolve-Path "$PSScriptRoot/../../../Modules/Authentication/StandaloneAuth.psm1"

    # We need to mock Invoke-PGQuery, Get-EMSLocalCredential, New-PasswordHash, Write-EMSLog
    function global:Invoke-PGQuery {}
    function global:Write-EMSLog {}

    # Dummy DB and User functions since they are required by StandaloneAuth.psm1
    function global:Get-EMSUser {}
    function global:New-EMSUser {}
    function global:Initialize-PostgreSQLConnection {}

    Import-Module $global:ModulePath -Force
}

Describe "Set-StandalonePassword" {
    Context "Happy Path" {
        It "Should successfully update password for an existing user" {
            # Arrange
            $mockUser = [pscustomobject]@{
                user_id = 999
                username = "testuser"
            }

            Mock Get-EMSLocalCredential { return $mockUser } -ModuleName "StandaloneAuth"
            Mock New-PasswordHash { return @{ Hash = "newhash"; Salt = "newsalt" } } -ModuleName "StandaloneAuth"
            Mock Invoke-PGQuery {} -ModuleName "StandaloneAuth"
            Mock Write-EMSLog {} -ModuleName "StandaloneAuth"

            $securePassword = ConvertTo-SecureString "NewSecurePass123!" -AsPlainText -Force

            # Act
            Set-StandalonePassword -Username "testuser" -NewSecurePassword $securePassword

            # Assert
            Assert-MockCalled Get-EMSLocalCredential -ModuleName "StandaloneAuth" -Times 1 -Exactly
            Assert-MockCalled New-PasswordHash -ModuleName "StandaloneAuth" -Times 1 -Exactly
            Assert-MockCalled Invoke-PGQuery -ModuleName "StandaloneAuth" -Times 1 -Exactly
            Assert-MockCalled Write-EMSLog -ModuleName "StandaloneAuth" -Times 1 -Exactly
        }
    }

    Context "Error Handling" {
        It "Should throw an error if the user is not found" {
            # Arrange
            Mock Get-EMSLocalCredential { return $null } -ModuleName "StandaloneAuth"

            $securePassword = ConvertTo-SecureString "NewSecurePass123!" -AsPlainText -Force

            # Act & Assert
            { Set-StandalonePassword -Username "nonexistentuser" -NewSecurePassword $securePassword } | Should -Throw "User 'nonexistentuser' not found."

            Assert-MockCalled Get-EMSLocalCredential -ModuleName "StandaloneAuth" -Times 1 -Exactly
        }
    }
}
