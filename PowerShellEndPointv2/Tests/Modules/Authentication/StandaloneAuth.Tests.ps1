BeforeAll {
    $global:ModulePath = Resolve-Path "$PSScriptRoot/../../../Modules/Authentication/StandaloneAuth.psm1"

    # We must mock using InModuleScope pattern or redefine global function
    # because standard Pester Mock doesn't always intercept module-internal calls correctly.
    function global:Invoke-PGQuery {
        [CmdletBinding()]
        param(
            [Parameter()]
            [switch]$NonQuery,

            [Parameter()]
            [string]$Query,

            [Parameter()]
            [hashtable]$Parameters
        )
        if ($Query -match "SELECT u.user_id") {
            if ($Parameters.username -eq "erroruser") {
                throw "Database connection failed"
            }
            if ($Parameters.username -eq "testuser") {
                return [pscustomobject]@{
                    user_id = 1
                    username = "testuser"
                    domain = "LOCAL"
                    display_name = "Test User"
                    role = "admin"
                    is_active = $true
                    password_hash = "somehash"
                    password_salt = "somesalt"
                    credential_active = $true
                }
            }
            return $null
        }
    }
    function global:Write-EMSLog {}
    function global:Initialize-PostgreSQLConnection {}
    Import-Module $global:ModulePath -Force
}

Describe "Get-EMSLocalCredential" {
    Context "Happy Path" {
        It "Should successfully query for a local credential" {
            # Act
            $result = Get-EMSLocalCredential -Username "testuser"

            # Assert
            $result.username | Should -Be "testuser"
            $result.password_hash | Should -Be "somehash"
            $result.domain | Should -Be "LOCAL"
        }

        It "Should return null when user does not exist" {
            # Act
            $result = Get-EMSLocalCredential -Username "nonexistentuser"

            # Assert
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Error Handling" {
        It "Should rethrow when Invoke-PGQuery fails" {
            # Act & Assert
            { Get-EMSLocalCredential -Username "erroruser" } | Should -Throw "Database connection failed"
        }
    }
}
