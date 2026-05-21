Describe "Test-EMSRateLimit" {
    BeforeAll {
        $scriptPath = "$PSScriptRoot/../../API/Start-EMSAPI.ps1"
        $scriptContent = Get-Content $scriptPath -Raw

        # Extract the section for Rate Limiting
        $startIdx = $scriptContent.IndexOf("# 3. Rate Limiting Setup")
        $endIdx = $scriptContent.IndexOf("while (`$listener.IsListening)")

        if ($startIdx -ge 0 -and $endIdx -ge 0) {
            $extractedScript = $scriptContent.Substring($startIdx, $endIdx - $startIdx)
            Invoke-Expression $extractedScript
        } else {
            throw "Could not extract Test-EMSRateLimit function."
        }
    }

    BeforeEach {
        $Global:RateLimitCache.Clear()
    }

    It "Should allow requests within the limit" {
        $key = "TestKey1"
        $result1 = Test-EMSRateLimit -Key $key -Max 2 -WindowSec 10
        $result2 = Test-EMSRateLimit -Key $key -Max 2 -WindowSec 10

        $result1 | Should -Be $true
        $result2 | Should -Be $true
    }

    It "Should reject requests exceeding the limit" {
        $key = "TestKey2"
        $result1 = Test-EMSRateLimit -Key $key -Max 2 -WindowSec 10
        $result2 = Test-EMSRateLimit -Key $key -Max 2 -WindowSec 10
        $result3 = Test-EMSRateLimit -Key $key -Max 2 -WindowSec 10

        $result1 | Should -Be $true
        $result2 | Should -Be $true
        $result3 | Should -Be $false
    }

    It "Should reset the limit after the window expires" {
        $key = "TestKey3"
        $result1 = Test-EMSRateLimit -Key $key -Max 1 -WindowSec 1
        $result2 = Test-EMSRateLimit -Key $key -Max 1 -WindowSec 1

        $result1 | Should -Be $true
        $result2 | Should -Be $false

        Start-Sleep -Seconds 2

        $result3 = Test-EMSRateLimit -Key $key -Max 1 -WindowSec 1
        $result3 | Should -Be $true
    }
}
