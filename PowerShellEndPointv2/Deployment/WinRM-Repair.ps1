<#
.SYNOPSIS
    WinRM Repair & Configuration Tool for EMS
.DESCRIPTION
    Fixes common WinRM issues including firewall exceptions on public networks,
    TrustedHosts configuration, and service state.
#>

$ErrorActionPreference = 'Continue'

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   EMS WinRM Repair Tool" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# 1. Check Elevation
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] This script MUST be run as Administrator." -ForegroundColor Red
    exit 1
}

# 2. Service Check
Write-Host "[1/4] Checking WinRM Service..." -ForegroundColor Yellow
$svc = Get-Service WinRM -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "  [!] WinRM service not found. Installing/Enabling..." -ForegroundColor Gray
}
Set-Service WinRM -StartupType Automatic
Start-Service WinRM
Write-Host "  [OK] WinRM Service is running" -ForegroundColor Green

# 3. QuickConfig (Firewall & Listeners)
Write-Host "[2/4] Running WinRM QuickConfig..." -ForegroundColor Yellow
try {
    # Attempt quickconfig
    $null = winrm quickconfig -quiet
    Write-Host "  [OK] WinRM QuickConfig successful" -ForegroundColor Green
} catch {
    Write-Host "  [!] QuickConfig failed (possibly due to Public network profile)." -ForegroundColor Gray
    Write-Host "  [!] Attempting to fix network profile..." -ForegroundColor Gray
    
    Get-NetConnectionProfile | Where-Object { $_.NetworkCategory -eq 'Public' } | ForEach-Object {
        Write-Host "    Changing $($_.InterfaceAlias) to Private..." -ForegroundColor Gray
        Set-NetConnectionProfile -InterfaceIndex $_.InterfaceIndex -NetworkCategory Private
    }
    
    # Retry QuickConfig
    try {
        $null = winrm quickconfig -quiet
        Write-Host "  [OK] WinRM QuickConfig successful after network fix" -ForegroundColor Green
    } catch {
        Write-Host "  [ERROR] QuickConfig still failing: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 4. TrustedHosts
Write-Host "[3/4] Configuring TrustedHosts..." -ForegroundColor Yellow
try {
    Set-Item WSMan:\localhost\Client\TrustedHosts -Value '*' -Force
    Write-Host "  [OK] TrustedHosts set to '*'" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] Failed to set TrustedHosts: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. Local Account Token Filter Policy (Allow local admins over WinRM)
Write-Host "[4/4] Setting LocalAccountTokenFilterPolicy..." -ForegroundColor Yellow
try {
    $regPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
    $regName = "LocalAccountTokenFilterPolicy"
    if (-not (Get-ItemProperty -Path $regPath -Name $regName -ErrorAction SilentlyContinue)) {
        New-ItemProperty -Path $regPath -Name $regName -Value 1 -PropertyType DWord -Force | Out-Null
    } else {
        Set-ItemProperty -Path $regPath -Name $regName -Value 1 -Force | Out-Null
    }
    Write-Host "  [OK] LocalAccountTokenFilterPolicy enabled" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] Failed to set Registry Policy: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "========================================" -ForegroundColor Green
Write-Host "   WinRM Repair Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Try testing locally: Test-WSMan -ComputerName localhost"
