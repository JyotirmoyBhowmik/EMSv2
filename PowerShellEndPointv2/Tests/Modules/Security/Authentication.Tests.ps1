BeforeAll {
    $global:ModulePath = Resolve-Path "$PSScriptRoot/../../../Modules/Authentication.psm1"

    function global:Initialize-ADAccountManagement {}
    function global:Write-Error {}
    function global:Write-Warning {}
    function global:Write-AuditLog {}

    $moduleContent = Get-Content $global:ModulePath -Raw
    $mockedModuleContent = $moduleContent -replace '\[System.DirectoryServices.AccountManagement.UserPrincipal\]::FindByIdentity\(\$context, \$user\)', 'Invoke-MockFindByIdentity -Context $context -User $user'

    $tempModulePath = "$PSScriptRoot/TempAuth.psm1"
    Set-Content -Path $tempModulePath -Value $mockedModuleContent

    function global:Invoke-MockFindByIdentity {
        param($Context, $User)
        return $null
    }

    $code = @"
namespace EMS.Tests.Mocks {
    public class DummyDisposable : System.IDisposable {
        public void Dispose() {}
    }
}
"@
    if (-not ("EMS.Tests.Mocks.DummyDisposable" -as [type])) {
        Add-Type -TypeDefinition $code -ErrorAction Ignore
    }

    Import-Module $tempModulePath -Force
}

AfterAll {
    $tempModulePath = "$PSScriptRoot/TempAuth.psm1"
    if (Test-Path $tempModulePath) {
        Remove-Item $tempModulePath -Force
    }
}

Describe "Test-UserAuthorization" {
    BeforeEach {
        Mock Initialize-ADAccountManagement {} -ModuleName "TempAuth"
        Mock Write-Error {} -ModuleName "TempAuth"
        Mock Write-Warning {} -ModuleName "TempAuth"
        Mock Write-AuditLog {} -ModuleName "TempAuth"

        Mock New-Object {
            return New-Object EMS.Tests.Mocks.DummyDisposable
        } -ModuleName "TempAuth"
    }

    Context "Happy Path - User is in Required Group" {
        It "Should return true if user is in the required group" {
            # Arrange
            $mockGroup = [PSCustomObject]@{ Name = "AdminGroup" }

            $mockUserPrincipal = [PSCustomObject]@{}
            $mockUserPrincipal | Add-Member -MemberType ScriptMethod -Name GetAuthorizationGroups -Value { return @($mockGroup) }
            $mockUserPrincipal | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}

            Mock Invoke-MockFindByIdentity { return $mockUserPrincipal } -ModuleName "TempAuth"

            # Act
            $result = Test-UserAuthorization -Username "domain\user" -RequiredGroup "AdminGroup"

            # Assert
            $result | Should -Be $true
        }
    }

    Context "User exists but not in required group" {
        It "Should return false" {
            # Arrange
            $mockGroup = [PSCustomObject]@{ Name = "OtherGroup" }

            $mockUserPrincipal = [PSCustomObject]@{}
            $mockUserPrincipal | Add-Member -MemberType ScriptMethod -Name GetAuthorizationGroups -Value { return @($mockGroup) }
            $mockUserPrincipal | Add-Member -MemberType ScriptMethod -Name Dispose -Value {}

            Mock Invoke-MockFindByIdentity { return $mockUserPrincipal } -ModuleName "TempAuth"

            # Act
            $result = Test-UserAuthorization -Username "domain\user" -RequiredGroup "AdminGroup"

            # Assert
            $result | Should -Be $false
        }
    }

    Context "When User Principal cannot be found" {
        It "Should return false and log a warning" {
            # Arrange
            Mock Invoke-MockFindByIdentity { return $null } -ModuleName "TempAuth"

            # Act
            $result = Test-UserAuthorization -Username "domain\user" -RequiredGroup "AdminGroup"

            # Assert
            $result | Should -Be $false
            Assert-MockCalled Write-Warning -ModuleName "TempAuth" -Times 1 -Exactly
        }
    }

    Context "When Domain cannot be determined" {
        It "Should throw an exception that gets caught and return false" {
            # Arrange
            $origDns = $env:USERDNSDOMAIN
            $origDomain = $env:USERDOMAIN

            try {
                # Act
                $env:USERDNSDOMAIN = ""
                $env:USERDOMAIN = ""
                $result = Test-UserAuthorization -Username "userwithoutdomain" -RequiredGroup "AdminGroup"

                # Assert
                $result | Should -Be $false
                Assert-MockCalled Write-Error -ModuleName "TempAuth" -Times 1 -Exactly
            } finally {
                # Restore
                $env:USERDNSDOMAIN = $origDns
                $env:USERDOMAIN = $origDomain
            }
        }
    }

    Context "When Active Directory integration throws an exception" {
        It "Should catch the exception, log an error, and return false" {
            # Arrange
            Mock New-Object { throw "Mocked New-Object failure" } -ModuleName "TempAuth"

            # Act
            $result = Test-UserAuthorization -Username "domain\user" -RequiredGroup "AdminGroup"

            # Assert
            $result | Should -Be $false
            Assert-MockCalled Write-Error -ModuleName "TempAuth" -Times 1 -Exactly
        }
    }
}
