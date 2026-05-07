<#
.SYNOPSIS
    Comprehensive Test Script for EMS v2.1 Enhancements
    
.DESCRIPTION
    Tests multi-provider authentication, computer management,
    and granular metrics functionality
    
.EXAMPLE
    .\Test-EMSEnhancements.ps1
#>

[CmdletBinding()]
param(
    [switch]$FullTest,
    [switch]$QuickTest
)

# Import modules
$rootPath = Split-Path $PSScriptRoot -Parent
Import-Module "$rootPath\Modules\Logging.psm1" -Force
Import-Module "$rootPath\Modules\Database\PSPGSql.psm1" -Force
Import-Module "$rootPath\Modules\Database\MetricsData.psm1" -Force
Import-Module "$rootPath\Modules\Authentication\AuthProviders.psm1" -Force
Import-Module "$rootPath\Modules\Authentication\StandaloneAuth.psm1" -Force

# Load config
$config = Get-Content "$rootPath\Config\EMSConfig.json" -Raw | ConvertFrom-Json

# Initialize database
Initialize-PostgreSQLConnection -Config $config

Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host " EMS v2.1 Enhancement Test Suite" -ForegroundColor Cyan
Write-Host "==========================================`n" -ForegroundColor Cyan

$testResults = @{
    Passed = 0
    Failed = 0
    Tests  = @()
}

function Test-Feature {
    param(
        [string]$Name,
        [scriptblock]$Test
    )
    
    Write-Host "[TEST] $Name..." -NoNewline
    try {
        $null = & $Test
        Write-Host " ✓ PASS" -ForegroundColor Green
        $testResults.Passed++
        $testResults.Tests += @{ Name = $Name; Result = "PASS" }
        return $true
    }
    catch {
        Write-Host " ✗ FAIL - $_" -ForegroundColor Red
        $testResults.Failed++
        $testResults.Tests += @{ Name = $Name; Result = "FAIL"; Error = $_.Exception.Message }
        return $false
    }
}

# =========================================
# Test 1: Database Schema
# =========================================
Write-Host "`n[1] DATABASE SCHEMA TESTS`n" -ForegroundColor Yellow

Test-Feature "Verify computers table exists" {
    $result = Invoke-PGQuery -Query "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'computers')"
    if (-not $result.exists) { throw "computers table not found" }
}

Test-Feature "Verify computer_ad_users table exists" {
    $result = Invoke-PGQuery -Query "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'computer_ad_users')"
    if (-not $result.exists) { throw "computer_ad_users table not found" }
}

Test-Feature "Count metric tables (should be 63+)" {
    $result = Invoke-PGQuery -Query "SELECT COUNT(*) as count FROM information_schema.tables WHERE table_name LIKE 'metric_%'"
    if ($result.count -lt 60) { throw "Expected 63+ metric tables, found $($result.count)" }
    Write-Host " ($($result.count) tables found)" -ForegroundColor Gray
}

Test-Feature "Verify users auth columns exist" {
    $result = Invoke-PGQuery -Query "SELECT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'users' AND column_name = 'auth_provider')"
    if (-not $result.exists) { throw "auth_provider column not found in users table" }
}

# =========================================
# Test 2: Authentication Providers
# =========================================
Write-Host "`n[2] AUTHENTICATION TESTS`n" -ForegroundColor Yellow

Test-Feature "Create standalone test user" {
    $pwd = ConvertTo-SecureString "TestPassword123!" -AsPlainText -Force
    $userId = New-StandaloneUser -Username "test_standalone_user" -SecurePassword $pwd -Role "viewer" -ErrorAction SilentlyContinue
    if (-not $userId) {
        # User might already exist
        $existing = Get-EMSUser -Username "test_standalone_user"
        if (-not $existing) { throw "Failed to create standalone user" }
    }
}

Test-Feature "Authenticate standalone user" {
    $pwd = ConvertTo-SecureString "TestPassword123!" -AsPlainText -Force
    $result = Invoke-MultiProviderAuth -Username "test_standalone_user" -SecurePassword $pwd -Provider "Standalone" -Config $config
    if (-not $result.Success) { throw "Standalone auth failed: $($result.Message)" }
}

if ($FullTest) {
    Test-Feature "Test invalid credentials" {
        $pwd = ConvertTo-SecureString "WrongPassword" -AsPlainText -Force
        $result = Invoke-MultiProviderAuth -Username "test_standalone_user" -SecurePassword $pwd -Provider "Standalone" -Config $config
        if ($result.Success) { throw "Should have failed with wrong password" }
    }
}

# =========================================
# Test 3: Computer Management
# =========================================
Write-Host "`n[3] COMPUTER MANAGEMENT TESTS`n" -ForegroundColor Yellow

Test-Feature "Register test computer" {
    Register-Computer -ComputerName "TEST-PC-001" -IPAddress "192.168.1.100" -OperatingSystem "Windows 11" -IsDomainJoined $false -ComputerType "Desktop"
}

Test-Feature "Update computer (upsert)" {
    Register-Computer -ComputerName "TEST-PC-001" -IPAddress "192.168.1.101" -OperatingSystem "Windows 11 Pro" -IsDomainJoined $false -ComputerType "Workstation"
}

Test-Feature "Query registered computer" {
    $computer = Invoke-PGQuery -Query "SELECT * FROM computers WHERE computer_name = 'TEST-PC-001'"
    if (-not $computer) { throw "Computer not found" }
    if ($computer.computer_type -ne "Workstation") { throw "Computer type not updated" }
}

Test-Feature "Map user to computer" {
    Add-ComputerUser -ComputerName "TEST-PC-001" -UserID "testuser" -UserDisplayName "Test User" -IsPrimary $true
}

Test-Feature "Get all computers" {
    $computers = Get-AllComputers -Limit 10
    if ($computers.Count -eq 0) { throw "No computers returned" }
}

# ==========================================
# Test 4: Granular Metrics Storage
# =========================================
Write-Host "`n[4] METRICS STORAGE TESTS`n" -ForegroundColor Yellow

Test-Feature "Save CPU metric" {
    Save-CPUMetric -ComputerName "TEST-PC-001" -UsagePercent 45.5 -CoreCount 8 -LogicalProcessors 16 -ProcessorName "Intel Core i7" -ProcessorSpeedMHz 3600
}

Test-Feature "Save Memory metric" {
    Save-MemoryMetric -ComputerName "TEST-PC-001" -TotalGB 16 -AvailableGB 8.5 -UsedGB 7.5 -UsagePercent 46.9
}

Test-Feature "Save Disk metrics" {
    $disks = @(
        @{ DriveLetter = 'C'; VolumeName = 'System'; TotalGB = 500; FreeGB = 200; UsedGB = 300; UsagePercent = 60; FileSystem = 'NTFS'; IsSystemDrive = $true },
        @{ DriveLetter = 'D'; VolumeName = 'Data'; TotalGB = 1000; FreeGB = 750; UsedGB = 250; UsagePercent = 25; FileSystem = 'NTFS'; IsSystemDrive = $false }
    )
    Save-DiskMetrics -ComputerName "TEST-PC-001" -Disks $disks
}

Test-Feature "Save Windows Update metric" {
    Save-WindowsUpdateMetric -ComputerName "TEST-PC-001" -TotalUpdates 50 -PendingUpdates 3 -FailedUpdates 0 -LastUpdateDate (Get-Date).AddDays(-7) -AutoUpdateEnabled $true -RebootRequired $false
}

Test-Feature "Save Antivirus metric" {
    Save-AntivirusMetric -ComputerName "TEST-PC-001" -AVProduct "Windows Defender" -AVVersion "4.18.2211.5" -DefinitionsVersion "1.403.123.0" -DefinitionsDate (Get-Date) -RealTimeProtection $true -LastScanDate (Get-Date).AddHours(-12) -ThreatCount 0
}

# =========================================
# Test 5: Metrics Retrieval
# =========================================
Write-Host "`n[5] METRICS RETRIEVAL TESTS`n" -ForegroundColor Yellow

Test-Feature "Get CPU metrics" {
    $metrics = Get-ComputerMetrics -ComputerName "TEST-PC-001" -MetricType "cpu"
    if (-not $metrics.CPU) { throw "CPU metrics not found" }
    if ($metrics.CPU.usage_percent -ne 45.5) { throw "CPU usage mismatch" }
}

Test-Feature "Get all metrics" {
    $metrics = Get-ComputerMetrics -ComputerName "TEST-PC-001" -MetricType "all"
    $metricsFound = 0
    if ($metrics.CPU) { $metricsFound++ }
    if ($metrics.Memory) { $metricsFound++ }
    if ($metrics.Disks) { $metricsFound++ }
    if ($metricsFound -lt 2) { throw "Expected multiple metrics, found $metricsFound" }
}

Test-Feature "Get computer health summary" {
    $summary = Get-ComputerHealthSummary -Limit 10
    if (-not $summary) { throw "No health summary data" }
}

# =========================================
# Test 6: API Endpoints (if API is running)
# =========================================
if ($FullTest) {
    Write-Host "`n[6] API ENDPOINT TESTS`n" -ForegroundColor Yellow
    
    $apiBase = "http://localhost:5000/api"
    
    Test-Feature "API: Get auth providers" {
        try {
            $response = Invoke-RestMethod -Uri "$apiBase/auth/providers" -Method GET -ErrorAction Stop
            if (-not $response.providers) { throw "No providers returned" }
        }
        catch {
            if ($_.Exception.Message -like "*Unable to connect*") {
                Write-Host " (API not running, skipping)" -ForegroundColor Gray
                throw "API not running"
            }
            throw
        }
    }
}

# =========================================
# Test 7: Data Integrity
# =========================================
Write-Host "`n[7] DATA INTEGRITY TESTS`n" -ForegroundColor Yellow

Test-Feature "Check for orphaned metrics" {
    $orphaned = Invoke-PGQuery -Query @"
SELECT COUNT(*) as count FROM metric_cpu_usage 
WHERE computer_name NOT IN (SELECT computer_name FROM computers)
"@
    if ($orphaned.count -gt 0) { throw "Found $($orphaned.count) orphaned CPU metrics" }
}

Test-Feature "Verify computer last_seen updated" {
    $computer = Invoke-PGQuery -Query "SELECT last_seen FROM computers WHERE computer_name = 'TEST-PC-001'"
    $lastSeen = [DateTime]$computer.last_seen
    $minutesAgo = (Get-Date).Subtract($lastSeen).TotalMinutes
    if ($minutesAgo -gt 5) { throw "last_seen not recently updated (${minutesAgo} minutes ago)" }
}

# =========================================
# Cleanup (optional)
# =========================================
if (-not $QuickTest) {
    Write-Host "`n[8] CLEANUP`n" -ForegroundColor Yellow
    
    Test-Feature "Delete test computer" {
        Invoke-PGQuery -Query "DELETE FROM computers WHERE computer_name = 'TEST-PC-001'" -NonQuery | Out-Null
    }
    
    Test-Feature "Delete test user" {
        Invoke-PGQuery -Query "DELETE FROM users WHERE username = 'test_standalone_user'" -NonQuery | Out-Null
    }
}

# =========================================
# Summary
# =========================================
Write-Host "`n==========================================" -ForegroundColor Cyan
Write-Host " TEST SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Total Tests:  $($testResults.Passed + $testResults.Failed)" -ForegroundColor White
Write-Host "Passed:       $($testResults.Passed)" -ForegroundColor Green
Write-Host "Failed:       $($testResults.Failed)" -ForegroundColor $(if ($testResults.Failed -eq 0) { "Green" } else { "Red" })
Write-Host "Success Rate: $(if (($testResults.Passed + $testResults.Failed) -gt 0) { [math]::Round(($testResults.Passed / ($testResults.Passed + $testResults.Failed)) * 100, 1) } else { 0 })%" -ForegroundColor Cyan
Write-Host "==========================================`n" -ForegroundColor Cyan

if ($testResults.Failed -gt 0) {
    Write-Host "Failed Tests:" -ForegroundColor Red
    $testResults.Tests | Where-Object { $_.Result -eq "FAIL" } | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.Error)" -ForegroundColor Red
    }
    Write-Host ""
    exit 1
}
else {
    Write-Host "✓ All tests passed!`n" -ForegroundColor Green
    exit 0
}
