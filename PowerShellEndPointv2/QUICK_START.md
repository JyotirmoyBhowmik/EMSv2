# EMS Quick Start Guide

Get the Enterprise Monitoring System up and running in minutes!

---

## 🚀 Fast Track (Prerequisites Already Installed)

If you already have PostgreSQL, Node.js, and all modules installed:

```powershell
# 1. Configure and test
.\Setup-EMS.ps1 -DBPassword "YourPassword123!" -CreateSampleData

# 2. Start both services
.\Start-EMS-Dev.ps1

# 3. Open browser to http://localhost:3000
# 4. Login with AD credentials
```

That's it! You're running EMS.

---

## 📋 Step-by-Step Setup

### Step 1: Install Prerequisites (One Time)

**PostgreSQL**:
```powershell
# Download from https://www.postgresql.org/download/windows/
# Or use Chocolatey:
choco install postgresql15 -y
```

**Node.js**:
```powershell
# Download from https://nodejs.org/
# Or use Chocolatey:
choco install nodejs-lts -y
```

**Npgsql Driver**:
```powershell
cd C:\Users\ZORO\PowerShellEndPointv2
nuget install Npgsql -OutputDirectory .\Lib -Version 7.0.6
```

**PowerShell Module**:
```powershell
Install-Module UniversalDashboard -Force
```

### Step 2: Create Database

```powershell
# Connect to PostgreSQL
psql -U postgres

# In psql prompt:
CREATE DATABASE ems_production;
CREATE USER ems_service WITH PASSWORD 'YourPassword123!';
\q

# Deploy schema
cd C:\Users\ZORO\PowerShellEndPointv2\Database
psql -U postgres -d ems_production -f schema.sql

# Grant permissions
psql -U postgres -d ems_production
GRANT ALL ON ALL TABLES IN SCHEMA public TO ems_service;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO ems_service;
\q
```

### Step 3: Configure EMS

Run the automated setup:
```powershell
cd C:\Users\ZORO\PowerShellEndPointv2
.\Setup-EMS.ps1 -DBPassword "YourPassword123!" -CreateSampleData
```

This script will:
- ✓ Check all prerequisites
- ✓ Update configuration file
- ✓ Test database connection
- ✓ Create admin user
- ✓ Install npm packages
- ✓ Generate sample test data

### Step 4: Create AD Security Group

```powershell
# As Domain Admin
Import-Module ActiveDirectory
New-ADGroup -Name "EMS_Admins" -GroupCategory Security -GroupScope Global
Add-ADGroupMember -Identity "EMS_Admins" -Members "yourusername"
```

### Step 5: Start Development Environment

```powershell
.\Start-EMS-Dev.ps1
```

This opens two windows:
- **Window 1**: API Backend (port 5000)
- **Window 2**: React Frontend (port 3000)

Browser will auto-open to http://localhost:3000

### Step 6: Login and Test

1. Login with your AD credentials (format: `DOMAIN\username`)
2. Explore the dashboard
3. Try a scan (use sample data hostnames)
4. View results history

---

## 🔧 Manual Start (Alternative)

If you prefer to start services manually:

**Terminal 1 - Start API**:
```powershell
cd C:\Users\ZORO\PowerShellEndPointv2\API
.\Start-EMSAPI.ps1
```

**Terminal 2 - Start React**:
```powershell
cd C:\Users\ZORO\PowerShellEndPointv2\WebUI
npm start
```

---

## 📊 Test with Sample Data

Create realistic test data:
```powershell
cd Database
.\Create-SampleData.ps1 -Count 50 -IncludeDiagnostics
```

This generates:
- 50 scan results
- Multiple users
- Various health scores
- Different topologies
- Sample diagnostics

---

## ✅ Verify Everything Works

### Check API
```powershell
# Test authentication
$body = @{
    username = "DOMAIN\yourusername"
    password = "yourpassword"
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:5000/api/auth/login" `
                  -Method POST `
                  -Body $body `
                  -ContentType "application/json"
```

Should return:
```json
{
  "success": true,
  "token": "eyJ...",
  "user": { ... }
}
```

### Check Database
```powershell
# Count scans
psql -U postgres -d ems_production -c "SELECT COUNT(*) FROM scan_results;"

# View recent scans
psql -U postgres -d ems_production -c "SELECT hostname, health_score FROM scan_results ORDER BY scan_timestamp DESC LIMIT 5;"
```

---

## 🐛 Common Issues

### Database Connection Failed
```powershell
# Check PostgreSQL service
Get-Service postgresql*

# If stopped, start it:
Start-Service postgresql-x64-15
```

### API Won't Start - Port in Use
```powershell
# Find what's using port 5000
Get-NetTCPConnection -LocalPort 5000

# Change port in Config\EMSConfig.json if needed
```

### React Won't Build
```powershell
# Clear cache and reinstall
cd WebUI
Remove-Item -Recurse node_modules
npm cache clean --force
npm install
```

### Login Failed - Unauthorized
```powershell
# Verify you're in EMS_Admins group
Get-ADGroupMember -Identity "EMS_Admins"

# Add yourself if missing
Add-ADGroupMember -Identity "EMS_Admins" -Members "yourusername"

# Force group policy update
gpupdate /force
```

---

## 📖 Next Steps

- **Production Deployment**: See [Deployment/IIS_Setup.md](Deployment/IIS_Setup.md)
- **Full Documentation**: See [INSTALLATION.md](INSTALLATION.md)
- **API Reference**: See [API/Start-EMSAPI.ps1](API/Start-EMSAPI.ps1) comments
- **UI/UX Guide**: See [WebUI/UI_UX_DESIGN.md](WebUI/UI_UX_DESIGN.md)

---

## 🎯 Development Workflow

**Daily Development**:
```powershell
# Start services
.\Start-EMS-Dev.ps1

# Make changes to code
# React: Edit files in WebUI\src\
# API: Edit API\Start-EMSAPI.ps1
# Database: Edit Modules\Database\PSPGSql.psm1

# React auto-reloads, API needs restart
# Stop API window (Ctrl+C) and restart
```

**Testing Changes**:
```powershell
# Generate fresh test data
.\Database\Create-SampleData.ps1 -Count 10

# Clear database and start fresh
psql -U postgres -d ems_production -c "TRUNCATE scan_results CASCADE;"
```

**Build for Production**:
```powershell
cd WebUI
npm run build
# Output in ./build/ ready for IIS
```

---

**Quick Start Version**: 1.0  
**Last Updated**: 2025-12-24
