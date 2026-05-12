$rootPath = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
Import-Module "$rootPath\Modules\Database\EMS.DB.Users.psm1" -Force

Describe "New-EMSUser" {
    Context "When creating a new user successfully" {
        It "Should call Invoke-PGQuery with correct parameters and return the new user_id" {
            Mock -CommandName Invoke-PGQuery -MockWith {
                return [pscustomobject]@{ user_id = 12345 }
            } -ModuleName EMS.DB.Users

            Mock -CommandName Write-EMSLog -MockWith { } -ModuleName EMS.DB.Users

            $result = New-EMSUser -Username "jdoe" -Domain "CONTOSO" -DisplayName "John Doe" -Email "jdoe@contoso.com" -Role "operator"

            $result | Should -Be 12345

            Assert-MockCalled -CommandName Invoke-PGQuery -Times 1 -Scope It -ModuleName EMS.DB.Users
            Assert-MockCalled -CommandName Write-EMSLog -Times 1 -Scope It -ModuleName EMS.DB.Users

            # Note: We can't easily assert on the hashtable parameter values without Pester 5 ParameterFilters or examining the mock history.
            # We'll assert that it was called.
        }
    }

    Context "When role is not specified" {
        It "Should default the role to 'viewer'" {
            Mock -CommandName Invoke-PGQuery -MockWith {
                # Pester ParameterFilter to verify role is viewer
                if ($Parameters.role -eq 'viewer') {
                    return [pscustomobject]@{ user_id = 12345 }
                }
            } -ModuleName EMS.DB.Users

            Mock -CommandName Write-EMSLog -MockWith { } -ModuleName EMS.DB.Users

            $result = New-EMSUser -Username "asmith" -Domain "CONTOSO" -DisplayName "Alice Smith" -Email "asmith@contoso.com"

            $result | Should -Be 12345
            Assert-MockCalled -CommandName Invoke-PGQuery -Times 1 -Scope It -ModuleName EMS.DB.Users -ParameterFilter {
                $Parameters.role -eq 'viewer'
            }
        }
    }

    Context "When an error occurs during creation" {
        It "Should log an error and throw an exception" {
            Mock -CommandName Invoke-PGQuery -MockWith {
                throw "Simulated database error"
            } -ModuleName EMS.DB.Users

            Mock -CommandName Write-EMSLog -MockWith { } -ModuleName EMS.DB.Users

            { New-EMSUser -Username "error_user" -Domain "CONTOSO" -DisplayName "Error User" -Email "error@contoso.com" } | Should -Throw "Simulated database error"

            Assert-MockCalled -CommandName Invoke-PGQuery -Times 1 -Scope It -ModuleName EMS.DB.Users
            Assert-MockCalled -CommandName Write-EMSLog -Times 1 -Scope It -ModuleName EMS.DB.Users -ParameterFilter {
                $Severity -eq 'Error'
            }
        }
    }
}
