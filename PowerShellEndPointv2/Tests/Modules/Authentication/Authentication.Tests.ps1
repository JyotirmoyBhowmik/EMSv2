BeforeAll {
    $global:ModulePath = Resolve-Path "$PSScriptRoot/../../../Modules/Authentication.psm1"

    # Dummy global functions for Write-EventLog and Write-Warning to prevent errors on Linux
    function global:Write-EventLog {}
    function global:Write-Warning {}

    Import-Module $global:ModulePath -Force
}

Describe "Write-AuditLog" {
    BeforeEach {
        # Use Pester TestDrive for cross-platform isolation and automatic cleanup
        $Global:EMSConfig = [PSCustomObject]@{
            Security = [PSCustomObject]@{
                AuditLogPath = "TestDrive:\"
            }
        }
    }

    It "Should create directory if it doesn't exist" {
        # Arrange
        $newDir = Join-Path "TestDrive:\" "newdir"
        $Global:EMSConfig.Security.AuditLogPath = $newDir

        # Act
        Write-AuditLog -Action "Login" -User "testuser" -Result "Success"

        # Assert
        Test-Path $newDir | Should -Be $true

        $logFiles = Get-ChildItem -Path $newDir -Filter "AuthAudit_*.csv"
        $logFiles.Count | Should -BeGreaterThan 0
    }

    It "Should record an audit log with required parameters successfully" {
        # Act
        Write-AuditLog -Action "Login" -User "testuser" -Result "Success"

        # Assert
        $logFiles = Get-ChildItem -Path "TestDrive:\" -Filter "AuthAudit_*.csv"
        $logFiles.Count | Should -BeGreaterThan 0

        $latestLog = $logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $logContent = Import-Csv $latestLog.FullName
        $logEntry = $logContent | Where-Object { $_.User -eq "testuser" -and $_.Action -eq "Login" } | Select-Object -Last 1

        $logEntry | Should -Not -BeNullOrEmpty
        $logEntry.Result | Should -Be "Success"
        $logEntry.Timestamp | Should -Not -BeNullOrEmpty
    }

    It "Should include optional parameters in the log" {
        # Act
        Write-AuditLog -Action "Login" -User "testuser" -Result "Failed" -Target "Server1" -RiskLevel "High" -Details "Invalid password"

        # Assert
        $logFiles = Get-ChildItem -Path "TestDrive:\" -Filter "AuthAudit_*.csv"
        $latestLog = $logFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        $logContent = Import-Csv $latestLog.FullName
        $logEntry = $logContent | Where-Object { $_.User -eq "testuser" -and $_.Action -eq "Login" } | Select-Object -Last 1

        $logEntry | Should -Not -BeNullOrEmpty
        $logEntry.Result | Should -Be "Failed"
        $logEntry.Target | Should -Be "Server1"
        $logEntry.RiskLevel | Should -Be "High"
        $logEntry.Details | Should -Be "Invalid password"
    }

    It "Should not throw error if EMSConfig or AuditLogPath is missing" {
        # Arrange
        $Global:EMSConfig = $null

        # Act & Assert
        { Write-AuditLog -Action "Login" -User "testuser" -Result "Success" } | Should -Not -Throw
    }

    It "Should call Write-Warning when an unexpected exception occurs" {
        # Mock Export-Csv to throw exception
        Mock Export-Csv { throw "Simulated Exception" } -ModuleName "Authentication"
        Mock Write-Warning {} -ModuleName "Authentication"

        # Act
        Write-AuditLog -Action "Login" -User "testuser" -Result "Success"

        # Assert
        Assert-MockCalled Write-Warning -ModuleName "Authentication"
    }
}
