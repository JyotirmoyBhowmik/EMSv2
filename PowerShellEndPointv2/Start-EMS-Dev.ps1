<#
.SYNOPSIS
    Start EMS in development mode
    
.DESCRIPTION
    Launches both API backend and React frontend in separate windows
    
.EXAMPLE
    .\Start-EMS-Dev.ps1
#>

[CmdletBinding()]
param()

Write-Host "`nStarting EMS Development Environment...`n" -ForegroundColor Cyan

$rootPath = $PSScriptRoot

# Start API in new window
Write-Host "Starting API Backend (new window)..." -ForegroundColor Yellow
$apiPath = Join-Path $rootPath "API\Start-EMSAPI.ps1"
Start-Process powershell -ArgumentList "-NoExit", "-ExecutionPolicy Bypass", "-File `"$apiPath`""

Start-Sleep -Seconds 2

# Start React dev server in new window
Write-Host "Starting React Frontend (new window)..." -ForegroundColor Yellow
$webuiPath = Join-Path $rootPath "WebUI"
Start-Process powershell -ArgumentList "-NoExit", "-Command `"cd '$webuiPath'; npm start`""

Write-Host "`n✓ Started both services!" -ForegroundColor Green
Write-Host "`nAPI:    http://localhost:5000" -ForegroundColor Cyan
Write-Host "Web UI: http://localhost:3000" -ForegroundColor Cyan
Write-Host "`nPress Ctrl+C in each window to stop services`n" -ForegroundColor Yellow
