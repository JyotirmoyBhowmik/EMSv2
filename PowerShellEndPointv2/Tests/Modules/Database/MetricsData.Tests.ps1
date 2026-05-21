$global:ModulePath = Resolve-Path "$PSScriptRoot/../../../Modules/Database/MetricsData.psm1"

BeforeAll {
    # Define a dummy global Invoke-PGQuery if missing, so Import-Module doesn't fail
    if (-not (Get-Command Invoke-PGQuery -ErrorAction SilentlyContinue)) {
        function global:Invoke-PGQuery { param($Query, $Parameters, [switch]$NonQuery) }
    }

    Import-Module $global:ModulePath -Force
}

Describe "Save-DiskMetrics" {
    It "should build queries using List[string] instead of array concatenation" {
        $computerName = "TestPC"
        $disks = @(
            @{ DriveLetter = "C:"; VolumeName = "OS"; TotalGB = 100; FreeGB = 50; UsedGB = 50; UsagePercent = 50; FileSystem = "NTFS"; IsSystemDrive = $true },
            @{ DriveLetter = "D:"; VolumeName = "Data"; TotalGB = 500; FreeGB = 400; UsedGB = 100; UsagePercent = 20; FileSystem = "NTFS"; IsSystemDrive = $false }
        )

        # We redefine the mock inside the module scope if needed, or we can just redefine global
        function global:Invoke-PGQuery {
            param($Query, $Parameters, [switch]$NonQuery)
            $global:LastQuery = $Query
            $global:LastParams = $Parameters
        }

        Save-DiskMetrics -ComputerName $computerName -Disks $disks

        $global:LastQuery | Should -BeLike "*VALUES (@computer, @letter_0, @volume_0, @total_0, @free_0, @used_0, @percent_0, @fs_0, @system_0), (@computer, @letter_1, @volume_1, @total_1, @free_1, @used_1, @percent_1, @fs_1, @system_1)"
        $global:LastParams["letter_0"] | Should -Be "C:"
        $global:LastParams["letter_1"] | Should -Be "D:"
    }
}
