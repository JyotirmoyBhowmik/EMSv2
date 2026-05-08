# EMS Quick Start Guide (v3.0)

Get the Enterprise Monitoring System up and running in minutes using the automated setup tools.

---

## 🚀 Fast Track (Recommended)

If you have PostgreSQL and Node.js installed, follow these three steps:

```powershell
# 1. Automated Environment Setup (As Administrator)
.\Setup-EMS.ps1 -DBPassword "ThinkPad@2026" -CreateSampleData

# 2. Start the EMS Services
.\Start-EMS-Dev.ps1

# 3. Access the Dashboard
# Open http://localhost:3000
# Login with AD or Local Admin credentials
```

---

## 📋 Standard Setup Workflow

### Step 1: Install Core Prerequisites

1.  **PostgreSQL (v16+)**: [Download Here](https://www.postgresql.org/download/windows/)
2.  **Node.js (v18+ LTS)**: [Download Here](https://nodejs.org/)
3.  **PowerShell (7.3+)**: Required for API performance.

### Step 2: Automated Configuration

The `Setup-EMS.ps1` script handles database initialization, schema patching (v3), and configuration:

```powershell
# Open PowerShell as Administrator
.\Setup-EMS.ps1 -DBPassword "YourPassword"
```

**This script performs:**
- [OK] Prerequisite validation
- [OK] **[v3 Patch]** Database schema alignment
- [OK] `EMSConfig.json` synchronization
- [OK] Initial Admin user creation
- [OK] Web UI dependency installation (`npm install`)

### Step 3: Security Configuration

Ensure the API can bind to network interfaces and pass through the firewall:

```powershell
# As Administrator
netsh http add urlacl url=http://*:5000/ user=Everyone
New-NetFirewallRule -DisplayName "EMS API" -Direction Inbound -LocalPort 5000 -Protocol TCP -Action Allow -Profile Any -Force
```

### Step 4: Launching EMS

You can start the environment using the unified launcher:

```powershell
.\Start-EMS-Dev.ps1
```

**Services Started:**
- **API Backend**: Listening on `http://*:5000`
- **Web Frontend**: Listening on `http://localhost:3000` (Dev Mode)

---

## 📊 Verification

### Check API Health
```powershell
Invoke-RestMethod -Uri "http://localhost:5000/admin/health"
```

### Check Database Tables
```powershell
psql -U ems_service -d ems_production -c "\dt"
```
*Expected: 130+ tables, including `scans` and `scan_inventory_results`.*

---

## 🐛 Troubleshooting

| Issue | Solution |
| :--- | :--- |
| **500 Internal Error** | Run `.\Setup-EMS.ps1` again to apply v3 schema patches. |
| **30000ms Timeout** | Run the `netsh` and `New-NetFirewallRule` commands in Step 3. |
| **Login Failed** | Verify `EMSConfig.json` has the correct AD domain and AdminGroup. |
| **Port 5000 Busy** | Check `Get-NetTCPConnection -LocalPort 5000` and stop the blocking process. |

---

**Version**: 3.0.1 (May 2026)  
**Quick Start Guide**
