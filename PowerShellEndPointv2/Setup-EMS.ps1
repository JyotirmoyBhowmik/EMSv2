<#
.SYNOPSIS
    Quick setup script for EMS Web Architecture
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$DBPassword,
    [string]$DBHost = 'localhost',
    [string]$DBName = 'ems_production',
    [string]$DBUser = 'ems_service',
    [switch]$SkipDatabaseTest,
    [switch]$CreateSampleData
)

$ErrorActionPreference = 'Stop'

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host '[ERROR] This setup script requires Administrator privileges.' -ForegroundColor Red
    exit 1
}

Write-Host '========================================' -ForegroundColor Cyan
Write-Host ' EMS Web Architecture - Quick Setup' -ForegroundColor Cyan
Write-Host '========================================' -ForegroundColor Cyan

Write-Host '[1/6] Checking prerequisites...' -ForegroundColor Yellow
$checks = @()
try { $null = psql --version; Write-Host '  [OK] PostgreSQL installed' -ForegroundColor Green; $checks += $true } catch { Write-Host '  [ERROR] PostgreSQL not found' -ForegroundColor Red; $checks += $false }
try { $null = node --version; Write-Host '  [OK] Node.js installed' -ForegroundColor Green; $checks += $true } catch { Write-Host '  [ERROR] Node.js not found' -ForegroundColor Red; $checks += $false }
if (Test-Path '.\Lib\Npgsql.*\lib\net*.0\Npgsql.dll') { Write-Host '  [OK] Npgsql driver installed' -ForegroundColor Green; $checks += $true } else { Write-Host '  [ERROR] Npgsql driver missing' -ForegroundColor Red; $checks += $false }
if (Get-Module -ListAvailable UniversalDashboard) { Write-Host '  [OK] UniversalDashboard installed' -ForegroundColor Green; $checks += $true } else { Write-Host '  [ERROR] UniversalDashboard missing' -ForegroundColor Red; $checks += $false }

if ($checks -contains $false) { exit 1 }

Write-Host '[2/6] Updating configuration...' -ForegroundColor Yellow
$configPath = '.\Config\EMSConfig.json'
$config = Get-Content $configPath -Raw | ConvertFrom-Json
$config.Database.Host = $DBHost
$config.Database.DatabaseName = $DBName
$config.Database.Username = $DBUser

Import-Module "$PSScriptRoot\Modules\Security\EMS.Environment.psm1" -Force
Set-EMSEnvironmentVar -Key 'DB_PASSWORD' -Value $DBPassword -IsSensitive $true `
                      -Description 'PostgreSQL password for ems_service'

foreach ($prop in @('Password')) {
    if ($config.Database.PSObject.Properties[$prop]) {
        $config.Database.PSObject.Properties.Remove($prop)
    }
}
foreach ($prop in @('JWTSecretKey')) {
    if ($config.API.PSObject.Properties[$prop]) {
        $config.API.PSObject.Properties.Remove($prop)
    }
}
foreach ($prop in @('BindPassword')) {
    if ($config.LDAP.PSObject.Properties[$prop]) {
        $config.LDAP.PSObject.Properties.Remove($prop)
    }
}
$config | ConvertTo-Json -Depth 10 | Set-Content $configPath -Encoding UTF8
Write-Host '  [OK] Configuration updated' -ForegroundColor Green

if (-not $SkipDatabaseTest) {
    Write-Host '[3/6] Testing database connection...' -ForegroundColor Yellow
    Import-Module '.\Modules\Logging.psm1' -Force
    Import-Module '.\Modules\Database\PSPGSql.psm1' -Force
    Import-Module '.\Modules\Database\EMS.DB.Users.psm1' -Force
    try {
        Initialize-PostgreSQLConnection -Config $config
        if (Test-PostgreSQLConnection) { Write-Host '  [OK] Database connection successful' -ForegroundColor Green }
        else { exit 1 }
    } catch { exit 1 }

    Write-Host '[4/6] Patching database schema...' -ForegroundColor Yellow
    try {
        $patches = @('.\Database\fix_production_schema_v3.sql', '.\Database\optimize_performance.sql')
        foreach ($p in $patches) {
            if (Test-Path $p) {
                $patchSql = Get-Content $p -Raw
                Invoke-PGQuery -NonQuery -Query $patchSql
                Write-Host "  [OK] Applied patch: $(Split-Path $p -Leaf)" -ForegroundColor Green
            }
        }
    } catch { Write-Host '  [ERROR] Patch failed: ' + $_ -ForegroundColor Red }
}

Write-Host '[5/6] Creating admin user...' -ForegroundColor Yellow
try {
    $existingUser = Get-EMSUser -Username 'admin'
    if (-not $existingUser) { $null = New-EMSUser -Username 'admin' -DisplayName 'Admin' -Role 'admin' }
    Write-Host '  [OK] Admin user verified' -ForegroundColor Green
} catch {}

Write-Host '[6/6] Web UI dependencies...' -ForegroundColor Yellow
if (Test-Path '.\WebUI\package.json') {
    Push-Location '.\WebUI'
    if (-not (Test-Path '.\node_modules')) { npm install --silent 2>&1 | Out-Null }
    Pop-Location
    Write-Host '  [OK] Web UI ready' -ForegroundColor Green
}

Write-Host '========================================' -ForegroundColor Green
Write-Host ' Setup Complete!' -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Green
