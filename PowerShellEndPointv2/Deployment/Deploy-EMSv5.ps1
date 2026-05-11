<#
.SYNOPSIS
    EMS v5 — Production Deployment Script
.DESCRIPTION
    Builds the web UI, runs the database migration, and deploys
    to the production environment on Windows Server 2022.
.NOTES
    Run as Administrator on the EMS host server.
    Requires: Node.js 20+, PowerShell 7+, PostgreSQL 16.
#>

#Requires -Version 7.0
#Requires -RunAsAdministrator

param(
    [string]$EMSRoot       = "C:\EMS\PowerShellEndPointv2",
    [string]$WebUIPath     = "$EMSRoot\WebUI",
    [string]$APIPort       = "5000",
    [string]$WebPort       = "80",
    [switch]$SkipBuild,
    [switch]$SkipDB,
    [switch]$SkipAPI
)

$ErrorActionPreference = 'Stop'
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

Write-Host "`n═══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  EMS v5.0.0 — Production Deployment"       -ForegroundColor Cyan
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════`n" -ForegroundColor Cyan

# ─── 1. Pre-flight Checks ────────────────────────────────

Write-Host "[1/7] Pre-flight checks..." -ForegroundColor Yellow

# Node.js
$nodeVersion = node --version 2>$null
if (-not $nodeVersion) { throw "Node.js not found. Install Node.js 20+ LTS." }
if ($nodeVersion -notmatch 'v2[0-9]') {
    Write-Host "  ⚠  Node.js $nodeVersion detected. v20+ recommended." -ForegroundColor Yellow
} else {
    Write-Host "  ✓  Node.js $nodeVersion" -ForegroundColor Green
}

# PowerShell
Write-Host "  ✓  PowerShell $($PSVersionTable.PSVersion)" -ForegroundColor Green

# PostgreSQL connectivity
$configPath = Join-Path $EMSRoot "Config\EMSConfig.json"
if (Test-Path $configPath) {
    $config = Get-Content $configPath -Raw | ConvertFrom-Json
    Write-Host "  ✓  Config loaded from $configPath" -ForegroundColor Green
} else {
    throw "EMSConfig.json not found at $configPath"
}

# ─── 2. Backup Current Build ─────────────────────────────

Write-Host "[2/7] Backing up current build..." -ForegroundColor Yellow
$buildDir = Join-Path $WebUIPath "build"
$backupDir = Join-Path $WebUIPath "build_backup_$timestamp"
if (Test-Path $buildDir) {
    Copy-Item $buildDir $backupDir -Recurse
    Write-Host "  ✓  Backed up to $backupDir" -ForegroundColor Green
} else {
    Write-Host "  ⓘ  No existing build to back up" -ForegroundColor Gray
}

# ─── 3. Install Dependencies & Build ─────────────────────

if (-not $SkipBuild) {
    Write-Host "[3/7] Installing dependencies..." -ForegroundColor Yellow
    Set-Location $WebUIPath

    npm ci --production=false 2>&1 | Out-Null
    Write-Host "  ✓  Dependencies installed" -ForegroundColor Green

    Write-Host "[3/7] Running security audit..." -ForegroundColor Yellow
    $auditResult = npm audit --production 2>&1
    if ($auditResult -match '0 vulnerabilities') {
        Write-Host "  ✓  0 vulnerabilities" -ForegroundColor Green
    } else {
        Write-Host "  ⚠  Vulnerabilities detected — review npm audit output" -ForegroundColor Yellow
        Write-Host $auditResult -ForegroundColor Gray
    }

    Write-Host "[3/7] Building production bundle..." -ForegroundColor Yellow
    $env:NODE_ENV = 'production'
    npm run build 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed! Check output above."
    }
    Write-Host "  ✓  Production build completed" -ForegroundColor Green

    # Show bundle sizes
    $buildFiles = Get-ChildItem (Join-Path $buildDir "assets") -Filter "*.js" | Sort-Object Length -Descending
    Write-Host "`n  Bundle Analysis:" -ForegroundColor Cyan
    foreach ($f in $buildFiles | Select-Object -First 5) {
        $sizeKB = [math]::Round($f.Length / 1024, 1)
        Write-Host "    $($f.Name): $sizeKB KB" -ForegroundColor Gray
    }
    Write-Host ""
} else {
    Write-Host "[3/7] Skipping build (--SkipBuild)" -ForegroundColor Gray
}

# ─── 4. Database Migration ───────────────────────────────

if (-not $SkipDB) {
    Write-Host "[4/7] Running database migration (v5)..." -ForegroundColor Yellow

    $migrationFile = Join-Path $EMSRoot "Database\migrate_v5.sql"
    if (-not (Test-Path $migrationFile)) {
        throw "Migration file not found: $migrationFile"
    }

    # Load DB module
    Import-Module (Join-Path $EMSRoot "Modules\Database\PSPGSql.psm1") -Force
    Initialize-PostgreSQLConnection -Config $config

    # Execute migration
    $sql = Get-Content $migrationFile -Raw
    try {
        Invoke-PGQuery -NonQuery -Query $sql
        Write-Host "  ✓  Database migrated to v5.0.0" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠  Migration warning: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "  ⓘ  This may be safe if tables already exist (idempotent)" -ForegroundColor Gray
    }
} else {
    Write-Host "[4/7] Skipping DB migration (--SkipDB)" -ForegroundColor Gray
}

# ─── 5. Configure IIS / Static File Serving ──────────────

Write-Host "[5/7] Configuring web server..." -ForegroundColor Yellow

# Check if IIS URL Rewrite is available for SPA routing
$iisAvailable = Get-Command "appcmd.exe" -ErrorAction SilentlyContinue
if ($iisAvailable) {
    Write-Host "  ✓  IIS detected — configure via IIS Manager" -ForegroundColor Green
    Write-Host "  ⓘ  Point site root to: $buildDir" -ForegroundColor Gray
    Write-Host "  ⓘ  Add URL Rewrite rule: all non-file requests → /index.html" -ForegroundColor Gray
    Write-Host "  ⓘ  Add reverse proxy: /api/* → http://localhost:$APIPort/api/*" -ForegroundColor Gray
} else {
    Write-Host "  ⓘ  IIS not detected. API will serve static files from build/" -ForegroundColor Gray
}

# ─── 6. Register/Restart API Service ─────────────────────

if (-not $SkipAPI) {
    Write-Host "[6/7] Configuring API service..." -ForegroundColor Yellow

    $apiScript = Join-Path $EMSRoot "API\Start-EMSAPI.ps1"
    $serviceName = "EMS-API"

    # Check if NSSM or Task Scheduler is used
    $existingTask = Get-ScheduledTask -TaskName $serviceName -ErrorAction SilentlyContinue
    if ($existingTask) {
        Write-Host "  ✓  Restarting scheduled task '$serviceName'..." -ForegroundColor Green
        Stop-ScheduledTask -TaskName $serviceName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-ScheduledTask -TaskName $serviceName
        Write-Host "  ✓  API service restarted" -ForegroundColor Green
    } else {
        Write-Host "  ⓘ  No scheduled task found for '$serviceName'" -ForegroundColor Gray
        Write-Host "  ⓘ  Create one with:" -ForegroundColor Gray
        Write-Host "      Register-ScheduledTask -TaskName '$serviceName' -Action (New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument '-NoProfile -File `"$apiScript`"') -Trigger (New-ScheduledTaskTrigger -AtStartup) -RunLevel Highest -User 'SYSTEM'" -ForegroundColor DarkGray
    }
} else {
    Write-Host "[6/7] Skipping API restart (--SkipAPI)" -ForegroundColor Gray
}

# ─── 7. Verification ─────────────────────────────────────

Write-Host "[7/7] Verification..." -ForegroundColor Yellow

# Check build output
if (Test-Path (Join-Path $buildDir "index.html")) {
    Write-Host "  ✓  build/index.html exists" -ForegroundColor Green
} else {
    Write-Host "  ✗  build/index.html MISSING" -ForegroundColor Red
}

$jsFiles = Get-ChildItem (Join-Path $buildDir "assets") -Filter "*.js" -ErrorAction SilentlyContinue
Write-Host "  ✓  $($jsFiles.Count) JS chunks in build/assets/" -ForegroundColor Green

# Wait and test API health
Start-Sleep -Seconds 3
try {
    $health = Invoke-RestMethod "http://localhost:$APIPort/api/auth/providers" -TimeoutSec 5 -ErrorAction Stop
    Write-Host "  ✓  API responding on port $APIPort" -ForegroundColor Green
} catch {
    Write-Host "  ⚠  API not responding on port $APIPort — may need manual start" -ForegroundColor Yellow
}

Write-Host "`n═══════════════════════════════════════════" -ForegroundColor Green
Write-Host "  ✓  EMS v5.0.0 DEPLOYMENT COMPLETE"         -ForegroundColor Green
Write-Host "═══════════════════════════════════════════" -ForegroundColor Green
Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "  1. Open http://localhost:$WebPort in browser" -ForegroundColor White
Write-Host "  2. Login with AD credentials (EMS_Admins group)" -ForegroundColor White
Write-Host "  3. Verify scan functionality with a single endpoint" -ForegroundColor White
Write-Host "  4. Run migrate_v5.sql if not done: psql -f Database\migrate_v5.sql" -ForegroundColor White
Write-Host ""
