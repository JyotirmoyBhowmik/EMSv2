# EMS Enterprise Deployment & Setup Plan (V2)

This document provides a comprehensive, step-by-step guide for deploying the Enterprise Endpoint Monitoring System (EMS) in a production environment.

---

## 1. Environment Prerequisites

### 1.1 Core Software
| Component | Requirement | Purpose |
| :--- | :--- | :--- |
| **Operating System** | Windows Server 2019/2022 | Hosting environment |
| **PowerShell** | 7.3+ (Core) | API Backend execution |
| **PostgreSQL** | 15.0 or higher | Data storage & Metrics |
| **Node.js** | 18.x or 20.x (LTS) | Building the Web Frontend |
| **Git for Windows** | Latest | Version control & updates |

### 1.2 Network Requirements
Ensure the following ports are open in the Windows Firewall:
- **Port 5000**: REST API (TCP)
- **Port 5432**: PostgreSQL (TCP) - *Localhost only recommended*
- **Port 3000 / 80 / 443**: Web Interface (TCP)
- **Port 135 / 445 / 5985**: Remote scanning protocols (RPC/SMB/WinRM)

---

## 2. Database Infrastructure Setup

### 2.1 Role & Database Creation
Log into `psql` as the `postgres` superuser and execute:

```sql
-- 1. Create the dedicated service user
CREATE USER ems_service WITH PASSWORD 'Annapurna@2026';

-- 2. Create the production database
CREATE DATABASE ems_production OWNER ems_service;

-- 3. Grant permissions
GRANT ALL PRIVILEGES ON DATABASE ems_production TO ems_service;
```

### 2.2 Schema Implementation
Navigate to the `Database` folder in the project root and run the scripts in order:

```powershell
# Run from PowerShell (replace with your path)
$env:PGPASSWORD = 'Annapurna@2026'
psql -U ems_service -d ems_production -f ".\Database\schema.sql"
psql -U ems_service -d ems_production -f ".\Database\schema_granular_metrics_part1.sql"
psql -U ems_service -d ems_production -f ".\Database\schema_granular_metrics_part2.sql"
```

---

## 3. Backend API Configuration

### 3.1 Edit `EMSConfig.json`
Located in `PowerShellEndPointv2\Config\EMSConfig.json`. Update the following:

```json
{
  "Database": {
    "Host": "localhost",
    "DatabaseName": "ems_production",
    "Username": "ems_service",
    "Password": "Annapurna@2026"
  },
  "API": {
    "ListenAddress": "http://+:5000",
    "JWTSecretKey": "GENERATED_32_CHAR_SECRET"
  }
}
```

### 3.2 URL Reservation
Run as **Administrator** to allow the API to listen on all interfaces:

```powershell
netsh http add urlacl url=http://+:5000/ user=Everyone
```

---

## 4. Production Hosting (Backend)

### 4.1 Method A: Windows Service (NSSM Recommended)
1. Download **NSSM** (Non-Sucking Service Manager).
2. Run `nssm install EMS_API`.
3. Set **Path**: `C:\Program Files\PowerShell\7\pwsh.exe`
4. Set **Arguments**: `-ExecutionPolicy Bypass -File "C:\EMS\PowerShellEndPointv2\API\Start-EMSAPI.ps1"`
5. Set **User**: Use a dedicated Service Account.

### 4.2 Method B: Scheduled Task (Native Windows)
1. Open **Task Scheduler** -> **Create Task**.
2. Name: `EMS_API_Daemon`.
3. Trigger: **At System Startup**.
4. Action: Start a Program (`pwsh.exe`).
5. Arguments: `-WindowStyle Hidden -File "C:\EMS\PowerShellEndPointv2\API\Start-EMSAPI.ps1"`.
6. Security: **Run whether user is logged on or not** + **Highest Privileges**.

---

## 5. Web Interface Deployment

### 5.1 Build the Production Bundle
```powershell
cd .\WebUI
npm install
npm run build
```

### 5.2 IIS Integration (Recommended)
1. Install **IIS** with the **Static Content** feature.
2. Create a new Website pointing to the `WebUI\build` folder.
3. Install **URL Rewrite Module**.
4. Configure a reverse proxy rule to map `/api/*` to `http://localhost:5000/`.

---

## 6. Maintenance & Updates

### 6.1 Pulling Updates (Pull-Only)
In your production directory:
```powershell
git fetch origin
git reset --hard origin/main
# If UI changed, rebuild:
cd WebUI; npm run build
```

### 6.2 Monitoring Logs
Logs are generated daily in `PowerShellEndPointv2\Logs\EMS_YYYYMMDD.csv`. Monitor these for:
- Database connection errors.
- Remote scanning "Access Denied" (DCOM/WMI) issues.
- Authentication failures.

---
**Document Version**: 2.1 (May 2026)
**Owner**: Enterprise Monitoring Team
