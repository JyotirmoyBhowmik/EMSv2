<#
.SYNOPSIS
    Quick setup script for EMS Web Architecture
    
.DESCRIPTION
    Automates initial setup and verification of:
    - Database connection
    - Required modules
    - Configuration validity
    - Creates test user
    
.EXAMPLE
    .\Setup-EMS.ps1 -DBPassword "YourPassword123!"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DBPassword,
    
    [string]$DBHost = "localhost",
    [string]$DBName = "ems_production",
    [string]$DBUser = "ems_service",
    
    [switch]$SkipDatabaseTest,
    [switch]$CreateSampleData
)

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " EMS Web Architecture - Quick Setup" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Step 1: Verify prerequisites
Write-Host "[1/6] Checking prerequisites..." -ForegroundColor Yellow

$checks = @()

# PostgreSQL
try {
    $null = psql --version
    Write-Host "  ✓ PostgreSQL installed" -ForegroundColor Green
    $checks += $true
}
catch {
    Write-Host "  ✗ PostgreSQL not found in PATH" -ForegroundColor Red
    $checks += $false
}

# Node.js
try {
    $null = node --version
    Write-Host "  ✓ Node.js installed" -ForegroundColor Green
    $checks += $true
}
catch {
    Write-Host "  ✗ Node.js not found" -ForegroundColor Red
    $checks += $false
}

# Npgsql
if (Test-Path ".\Lib\Npgsql.*\lib\net*.0\Npgsql.dll") {
    Write-Host "  ✓ Npgsql driver installed" -ForegroundColor Green
    $checks += $true
}
else {
    Write-Host "  ✗ Npgsql driver not found in .\Lib\" -ForegroundColor Red
    Write-Host "    Run: nuget install Npgsql -OutputDirectory .\Lib -Version 7.0.6" -ForegroundColor Yellow
    $checks += $false
}

# UniversalDashboard module
if (Get-Module -ListAvailable UniversalDashboard) {
    Write-Host "  ✓ UniversalDashboard module installed" -ForegroundColor Green
    $checks += $true
}
else {
    Write-Host "  ✗ UniversalDashboard module not found" -ForegroundColor Red
    Write-Host "    Run: Install-Module UniversalDashboard -Force" -ForegroundColor Yellow
    $checks += $false
}

if ($checks -contains $false) {
    Write-Host "`n⚠️  Prerequisites missing. Please install missing components.`n" -ForegroundColor Red
    exit 1
}

# Step 2: Update configuration
Write-Host "`n[2/6] Updating configuration..." -ForegroundColor Yellow

$configPath = ".\Config\EMSConfig.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json

$config.Database.Host = $DBHost
$config.Database.DatabaseName = $DBName
$config.Database.Username = $DBUser
$config.Database.Password = $DBPassword

# Generate JWT secret if not set
if ($config.API.JWTSecretKey -eq "REPLACE_WITH_SECURE_KEY" -or $config.API.JWTSecretKey.Length -lt 32) {
    $jwtSecret = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object { [char]$_ })
    $config.API.JWTSecretKey = $jwtSecret
    Write-Host "  ✓ Generated new JWT secret key" -ForegroundColor Green
}

$config | ConvertTo-Json -Depth 10 | Set-Content $configPath
Write-Host "  ✓ Configuration updated" -ForegroundColor Green

# Step 3: Test database connection
if (-not $SkipDatabaseTest) {
    Write-Host "`n[3/6] Testing database connection..." -ForegroundColor Yellow
    
    Import-Module .\Modules\Logging.psm1 -Force
    Import-Module .\Modules\Database\PSPGSql.psm1 -Force
    
    try {
        if (Initialize-PostgreSQLConnection -Config $config) {
            if (Test-PostgreSQLConnection) {
                Write-Host "  ✓ Database connection successful" -ForegroundColor Green
            }
            else {
                Write-Host "  ✗ Database connection failed" -ForegroundColor Red
                exit 1
            }
        }
    }
    catch {
        Write-Host "  ✗ Error: $_" -ForegroundColor Red
        exit 1
    }
}
else {
    Write-Host "`n[3/6] Skipping database test..." -ForegroundColor Gray
}

# Step 4: Create admin user
Write-Host "`n[4/6] Creating initial admin user..." -ForegroundColor Yellow

try {
    $existingUser = Get-EMSUser -Username "admin"
    if ($existingUser) {
        Write-Host "  ℹ  Admin user already exists (ID: $($existingUser.user_id))" -ForegroundColor Cyan
    }
    else {
        $userId = New-EMSUser -Username "admin" -DisplayName "System Administrator" -Role "admin"
        Write-Host "  ✓ Created admin user (ID: $userId)" -ForegroundColor Green
    }
}
catch {
    Write-Host "  ⚠  Could not create admin user: $_" -ForegroundColor Yellow
}

# Step 5: Install Web UI dependencies
Write-Host "`n[5/6] Installing Web UI dependencies..." -ForegroundColor Yellow

if (Test-Path ".\WebUI\package.json") {
    Push-Location .\WebUI
    try {
        if (-not (Test-Path ".\node_modules")) {
            Write-Host "  Installing npm packages (this may take a few minutes)..." -ForegroundColor Gray
            npm install --silent 2>&1 | Out-Null
            Write-Host "  ✓ npm packages installed" -ForegroundColor Green
        }
        else {
            Write-Host "  ℹ  node_modules already exists, skipping install" -ForegroundColor Cyan
        }
    }
    finally {
        Pop-Location
    }
}
else {
    Write-Host "  ⚠  WebUI package.json not found" -ForegroundColor Yellow
}

# Step 6: Create sample data (optional)
if ($CreateSampleData) {
    Write-Host "`n[6/6] Creating sample test data..." -ForegroundColor Yellow
    
    # Create sample scan results
    $sampleData = @(
        @{
            Hostname             = "DESKTOP-TEST-01"
            IPAddress            = "192.168.1.100"
            UserID               = "testuser1"
            HealthScore          = 95
            Topology             = "HO"
            ExecutionTimeSeconds = 8.5
            Diagnostics          = @()
        },
        @{
            Hostname             = "LAPTOP-TEST-02"
            IPAddress            = "192.168.1.101"
            UserID               = "testuser2"
            HealthScore          = 75
            Topology             = "Remote"
            ExecutionTimeSeconds = 15.2
            Diagnostics          = @()
        }
    )
    
    foreach ($sample in $sampleData) {
        try {
            $scanData = [PSCustomObject]$sample
            $scanData.ScanTimestamp = Get-Date
            Save-ScanResult -ScanData $scanData -InitiatedBy 1
            Write-Host "  ✓ Created sample scan: $($sample.Hostname)" -ForegroundColor Green
        }
        catch {
            Write-Host "  ⚠  Could not create sample: $_" -ForegroundColor Yellow
        }
    }
}
else {
    Write-Host "`n[6/6] Skipping sample data creation..." -ForegroundColor Gray
}

# Summary
Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Setup Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green

Write-Host "`nNext Steps:" -ForegroundColor Cyan
Write-Host "1. Start API:  .\API\Start-EMSAPI.ps1" -ForegroundColor White
Write-Host "2. Start WebUI: cd WebUI; npm start" -ForegroundColor White
Write-Host "3. Access: http://localhost:3000" -ForegroundColor White
Write-Host "`nDefault Credentials: Use AD credentials (user must be in EMS_Admins group)" -ForegroundColor Yellow
Write-Host "`n========================================`n" -ForegroundColor Green
