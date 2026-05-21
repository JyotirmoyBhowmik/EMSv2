Describe "Authentication Module - Initialize-ADAccountManagement" {
    BeforeAll {
        $script:ModulePath = Resolve-Path "$PSScriptRoot/../../Modules/Authentication.psm1"
    }

    Context "When Initialize-ADAccountManagement executes" {
        BeforeAll {
            Import-Module $script:ModulePath -Force
        }

        It "Successfully ensures the assembly is loaded" {
            InModuleScope Authentication {
                Mock Add-Type {
                    Microsoft.PowerShell.Utility\Add-Type -TypeDefinition @"
                    namespace System.DirectoryServices.AccountManagement {
                        public class ContextType {}
                    }
"@
                }

                { Initialize-ADAccountManagement } | Should -Not -Throw
            }
        }

        It "Throws exception when the assembly cannot be loaded" {
            # Since the assembly is natively loaded in our test environment (PowerShell 7),
            # the only way to accurately test the failure condition logic without altering the real source code
            # is to create a dynamic copy of the module with an impossible type.
            $moduleContent = Get-Content $script:ModulePath -Raw
            $modifiedContent = $moduleContent -replace '"System\.DirectoryServices\.AccountManagement\.ContextType"', '"Dummy.Missing.Type.That.Fails"'

            $tempDir = [System.IO.Path]::GetTempPath()
            $tempModulePath = Join-Path $tempDir "AuthenticationTest_$([guid]::NewGuid().ToString()).psm1"
            Set-Content -Path $tempModulePath -Value $modifiedContent

            try {
                Import-Module $tempModulePath -Force
                InModuleScope (Split-Path $tempModulePath -LeafBase) {
                    Mock Add-Type { }
                    { Initialize-ADAccountManagement } | Should -Throw "System.DirectoryServices.AccountManagement could not be loaded."
                }
            } finally {
                Remove-Module (Split-Path $tempModulePath -LeafBase) -ErrorAction SilentlyContinue
                Remove-Item -Path $tempModulePath -ErrorAction SilentlyContinue
            }
        }
    }
}
