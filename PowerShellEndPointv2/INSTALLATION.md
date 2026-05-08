# EMS v3.0 - Enterprise Setup & Installation Guide

**Version**: 3.0.1  
**Last Updated**: 2026-05-08  
**Architecture**: React + PowerShell REST API + PostgreSQL

---

## 📋 Table of Contents
1. [Prerequisites](#prerequisites)
2. [Automated Installation (Recommended)](#automated-installation)
3. [Manual Installation (Advanced)](#manual-installation)
4. [Security & Firewall](#security-and-firewall)
5. [Frontend Configuration](#frontend-configuration)
6. [Verification](#verification)

---

## 🏗️ Prerequisites

Ensure the following components are installed before proceeding:

| Component | Minimum Version | Link |
| :--- | :--- | :--- |
| **PostgreSQL** | 16.0 | [Download](https://www.postgresql.org/download/windows/) |
| **Node.js** | 20.x (LTS) | [Download](https://nodejs.org/) |
| **PowerShell** | 7.3+ (Core) | [Download](https://github.com/PowerShell/PowerShell) |
| **Npgsql Driver** | 7.0.6 | [NuGet](https://www.nuget.org/packages/Npgsql) |

---

## 🚀 Automated Installation (Recommended)

The `Setup-EMS.ps1` script is the primary tool for deploying and reconciling the EMS environment.

### 1. Execute Setup
Open PowerShell as **Administrator** and run:

```powershell
.\Setup-EMS.ps1 -DBPassword "YourSecurePassword" -CreateSampleData
```

**What the script does:**
- Validates the presence of `psql`, `node`, and `npm`.
- Updates `Config/EMSConfig.json` with your database credentials.
- Initializes the `ems_production` database.
- Applies the **v3 Schema Patch** (adding `scans`, `scan_inventory_results`, and compliance views).
- Creates the initial `admin` user.
- Performs `npm install` in the `WebUI` directory.

---

## 🔧 Manual Installation

If you prefer to set up the components manually, follow these steps:

### 1. Database Creation
```sql
CREATE DATABASE ems_production;
CREATE USER ems_service WITH PASSWORD 'YourSecurePassword';
GRANT ALL PRIVILEGES ON DATABASE ems_production TO ems_service;
```

### 2. Schema Deployment
Execute the SQL scripts in the following order:
```powershell
psql -U postgres -d ems_production -f Database\schema.sql
psql -U postgres -d ems_production -f Database\schema_granular_metrics_part1.sql
psql -U postgres -d ems_production -f Database\schema_granular_metrics_part2.sql
psql -U postgres -d ems_production -f Database\fix_production_schema_v3.sql
```

### 3. Backend Configuration
Edit `Config/EMSConfig.json` to point to your PostgreSQL instance:
```json
"Database": {
    "Host": "localhost",
    "DatabaseName": "ems_production",
    "Username": "ems_service",
    "Password": "YourSecurePassword"
}
```

---

## 🛡️ Security and Firewall

To allow the API to function correctly in a networked enterprise environment, you **must** reserve the URL and open the firewall port.

### 1. URL Reservation
```powershell
# Allows the API to bind to all available IP addresses
netsh http add urlacl url=http://*:5000/ user=Everyone
```

### 2. Firewall Rule
```powershell
# Opens Port 5000 for inbound API traffic
New-NetFirewallRule -DisplayName "EMS API" -Direction Inbound -LocalPort 5000 -Protocol TCP -Action Allow -Force
```

---

## 🌐 Frontend Configuration

The React frontend communicates with the backend via the `REACT_APP_API_URL` environment variable.

1.  Navigate to the `WebUI` folder.
2.  Create or edit the `.env` file.
3.  Set the API URL to your server's network IP:
    ```env
    REACT_APP_API_URL=http://10.192.6.109:5000
    ```

---

## ✅ Verification

### Health Check
Verify the API is running and connected to the database:
`GET http://localhost:5000/admin/health`

### Dashboard Stats
Verify the dashboard can aggregate data (no 500 errors):
`GET http://localhost:5000/api/dashboard/stats`

---

**Certified By**: Enterprise Monitoring Team  
**Last Updated**: May 2026
