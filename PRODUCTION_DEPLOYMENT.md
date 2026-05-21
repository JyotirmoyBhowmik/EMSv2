# Enterprise Endpoint Monitoring System (EMS) — Production Deployment Master Guide

This guide is the single source of truth for installing, configuring, hardening, and running EMS v5 in a production Windows Server environment. It covers Active Directory group integration, secure PostgreSQL migrations, Vite frontend builds, IIS static hosting, secure environment variables (DPAPI), and system bootstrapping.

---

## 1. Prerequisites & Environment Specs

Before proceeding, confirm the presence of the following components on the host server:

### 1.1 Software Requirements
*   **Operating System**: Windows Server 2016 / 2019 / 2022
*   **PowerShell**: Version 7.3+ (installed as `pwsh.exe` — required for the backend API daemon)
*   **PostgreSQL**: Version 15.0 or higher
*   **Node.js**: Version 20.x LTS or higher (only required on the build server/agent, not strictly needed on the production host if assets are built externally)
*   **IIS (Internet Information Services)**: Version 10+
*   **IIS Extensions**:
    *   [URL Rewrite Module 2.1](https://www.iis.net/downloads/microsoft/url-rewrite)
    *   [Application Request Routing (ARR) 3.0](https://www.iis.net/downloads/microsoft/application-request-routing)

### 1.2 Firewall & Network Port Configuration
Ensure the following ports are open inbound to allow communication:

| Port | Protocol | Usage | Source / Destination |
| :--- | :--- | :--- | :--- |
| **80** | TCP | HTTP (Redirects to HTTPS) | Clients -> IIS Server |
| **443** | TCP | HTTPS (Secure Web UI) | Clients -> IIS Server |
| **5000** | TCP | PowerShell API Daemon | Localhost (127.0.0.1) internal loopback only |
| **5432** | TCP | PostgreSQL Server | Localhost (or internal database segment) |
| **5985** | TCP | WinRM (HTTP) | EMS Server -> Monitored Workstations |
| **5986** | TCP | WinRM (HTTPS) | EMS Server -> Monitored Workstations (Secure) |

---

## 2. Active Directory Configuration (LDAP & RBAC)

EMS maps permissions directly to Active Directory Domain Services security groups. 

### 2.1 Active Directory Group Creation
Create the following three security groups within your active directory Domain or Organization Unit (OU):

1.  **EMS_Admins**:
    *   *Role*: Administrators
    *   *Permissions*: Complete write and read permissions, managing settings, creating users, and configuring credentials.
2.  **EMS_Operators**:
    *   *Role*: Operators
    *   *Permissions*: Run scans on demand, view system metrics, restore deleted files, and modify scan schedules.
3.  **EMS_Viewers**:
    *   *Role*: Viewers
    *   *Permissions*: Read-only dashboard access. Cannot perform scans or modify settings.

### 2.2 Endpoint Scan Permission Setup
To perform CIM/DCOM queries on remote endpoints, the account executing the EMS backend daemon (or the service credentials configured in EMS) must have administrative privileges on the target machines.
*   **Active Directory Setup**: Create a dedicated service account (e.g., `DOMAIN\ems_scanner`).
*   **Group Policy Object (GPO)**: Configure a GPO to add the `DOMAIN\ems_scanner` account to the local **Administrators** or **Remote Management Users** group on all target workstations and servers.

---

## 3. PostgreSQL Database Deployment

### 3.1 Database and User Initialization
Execute this block as a database administrator via `pgAdmin` or a `psql` console:

```sql
-- 1. Create a dedicated service account
CREATE USER ems_service WITH PASSWORD 'StrongProductionPassword123!';

-- 2. Create the production database
CREATE DATABASE ems_production OWNER ems_service;

-- 3. Grant schema privileges
GRANT ALL PRIVILEGES ON DATABASE ems_production TO ems_service;
```

### 3.2 Schema and Migration Application
Run the setup and migration scripts from the repository to build the database schema:

```powershell
# Set environment password temporarily for connection
$env:PGPASSWORD = 'StrongProductionPassword123!'

# 1. Apply the complete unified schema
psql -h localhost -U ems_service -d ems_production -f ".\PowerShellEndPointv2\Database\ems_complete_schema.sql"

# 2. Apply the latest Wave 2 migrations (nullable, additive only)
psql -h localhost -U ems_service -d ems_production -f ".\PowerShellEndPointv2\Database\migrate_v5.sql"
```

---

## 4. Building the Web Frontend (React + Vite)

The UI has been migrated from Create React App to **Vite 6** to support optimized tree-shaking, sub-millisecond hot-reloading, and zero security vulnerabilities.

### 4.1 Compile Static Assets
Run this on a machine with Node.js 20+ to compile the frontend:

```powershell
# Navigate to the UI project root
cd PowerShellEndPointv2\WebUI

# Install clean dependencies
npm ci --production=false

# Run build process (transpiles TypeScript and compiles optimized assets)
npm run build
```

Expected output:
*   `✓ built in ~35s`
*   `build/` folder created containing `index.html` and static assets under `build/assets/`

---

## 5. Web UI Static Hosting & IIS Configuration

We host the static Web UI files on **IIS** and use **URL Rewrite** to redirect API calls directly to the background PowerShell daemon.

### 5.1 Create the Website in IIS
1.  Open **IIS Manager** (`inetmgr`).
2.  Right-click **Sites** -> **Add Website**.
    *   *Site Name*: `EMS_WebUI`
    *   *Physical Path*: `C:\EMS\PowerShellEndPointv2\WebUI\build`
    *   *Port*: `80` (Add binding `443` for SSL).
3.  Ensure the Application Pool is configured with **.NET CLR Version** set to **No Managed Code** (since it only serves static assets).

### 5.2 Configure ARR (Reverse Proxy)
To allow IIS to proxy API requests to the PowerShell daemon on port 5000:
1.  Open **IIS Manager** -> Click the top-level **Server Node**.
2.  Open **Application Request Routing Cache**.
3.  Click **Server Settings** on the Actions Pane (right side).
4.  Check the **Enable Proxy** box and click **Apply**.

### 5.3 Configure Rewrite Rules (`web.config`)
Verify or create a `web.config` file in the root of your `build\` directory with the following contents:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <!-- Rule 1: Proxy all API requests to the backend PowerShell daemon -->
        <rule name="ReverseProxyAPI" stopProcessing="true">
            <match url="^api/(.*)" />
            <action type="Rewrite" url="http://localhost:5000/api/{R:1}" />
        </rule>
        <!-- Rule 2: SPA fallback routing for client-side React Router -->
        <rule name="React Routes" stopProcessing="true">
          <match url=".*" />
          <conditions logicalGrouping="MatchAll">
            <add input="{REQUEST_FILENAME}" matchType="IsFile" negate="true" />
            <add input="{REQUEST_FILENAME}" matchType="IsDirectory" negate="true" />
          </conditions>
          <action type="Rewrite" url="/index.html" />
        </rule>
      </rules>
    </rewrite>
    <staticContent>
      <mimeMap fileExtension=".json" mimeType="application/json" />
      <mimeMap fileExtension=".woff2" mimeType="font/woff2" />
    </staticContent>
  </system.webServer>
</configuration>
```

---

## 6. Configuring & Running the PowerShell API Daemon

The PowerShell backend daemon listens on port 5000 and processes API requests.

### 6.1 Basic Configuration (`EMSConfig.json`)
Verify `PowerShellEndPointv2\Config\EMSConfig.json` exists with the listener address and base settings:

```json
{
  "Database": {
    "Host": "localhost",
    "Port": 5432,
    "DatabaseName": "ems_production",
    "Username": "ems_service",
    "Password": "StrongProductionPassword123!"
  },
  "API": {
    "ListenAddress": "http://localhost:5000/",
    "JWTSecretKey": "GENERATE_A_LONG_SECURE_RANDOM_SECRET_KEY"
  }
}
```

### 6.2 Hardening Secrets at Rest (Windows DPAPI)
In a hardened production environment, database passwords and JWT secret keys should never remain in plain text. You should encrypt them at rest using the Windows **Data Protection API (DPAPI)**:

```powershell
Import-Module "C:\EMS\PowerShellEndPointv2\Modules\Security\EMS.Environment.psm1"

# Encrypt database connection password under system account context
Set-EMSEnvironmentVar -Name "EMS_DB_PASSWORD" -Value "StrongProductionPassword123!" -Encrypt

# Encrypt your secure JWT signing key
Set-EMSEnvironmentVar -Name "EMS_JWT_SECRET" -Value "YOUR_VERY_LONG_SECURE_JWT_SECRET_STRING" -Encrypt
```
*Note: The PowerShell daemon automatically checks for DPAPI variables first at startup, ignoring plain-text passwords in EMSConfig.json if they are found.*

### 6.3 Registering the Background Service Daemon
To run the API daemon persistently on system boot with redirect logging:

```powershell
# Define script and log redirection
$apiScript = "C:\EMS\PowerShellEndPointv2\API\Start-EMSAPI.ps1"
$logPath = "C:\EMS\PowerShellEndPointv2\Logs\api_daemon.log"

# Set up Scheduled Task arguments to run pwsh.exe and redirect logs
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$apiScript`" > `"$logPath`" 2>&1"
    
$trigger = New-ScheduledTaskTrigger -AtStartup

# Register task to run as the secure local SYSTEM context
Register-ScheduledTask -TaskName "EMS-API-Service" -Action $action -Trigger $trigger -RunLevel Highest -User 'SYSTEM'

# Start the background service task
Start-ScheduledTask -TaskName "EMS-API-Service"
```

---

## 7. System Bootstrapping (Initial Standalone Admin)

Once the backend service and database are initialized, you need an administrative account to log in. Run this command on the server to seed the initial standalone administrator directly into PostgreSQL:

```powershell
Import-Module "C:\EMS\PowerShellEndPointv2\Modules\Authentication\StandaloneAuth.psm1"

# Convert plain-text bootstrap password to a secure string
$securePwd = ConvertTo-SecureString "BootstrapAdminPwd123!" -AsPlainText -Force

# Create the administrator account directly in the database
New-StandaloneUser -Username "ems_admin" -SecurePassword $securePwd -DisplayName "Bootstrap Administrator" -Role "admin"
```

---

## 8. Verification & Diagnostics

Once deployment is complete, verify the server components using these simple diagnostic queries:

### 8.1 API Status Check
```powershell
# Query the REST endpoint to confirm the authentication engine is alive
Invoke-RestMethod http://localhost:5000/api/auth/providers
```
*Expected response format*: `@{"providers"=@(@{"Name"="Standalone"; "RequiresCredentials"=$true}, @{"Name"="ActiveDirectory"; ...})}`

### 8.2 Database Version Verification
```powershell
# Check applied migrations
psql -h localhost -U ems_service -d ems_production -c "SELECT * FROM schema_version ORDER BY applied_at DESC LIMIT 1;"
```
*Expected response*: `Applied version 5.0.0`

### 8.3 Daemon Log Inspection
If the API does not respond, review the runtime redirect logs for unhandled exceptions or permission blocks:
```powershell
Get-Content -Path "C:\EMS\PowerShellEndPointv2\Logs\api_daemon.log" -Tail 50
```

---

## 9. Rollback Plan

If you encounter issues during a version update, follow these steps to revert the environment to a known working state:

1.  **Revert Frontend static files**:
    ```powershell
    # Revert to the latest backup bundle
    $latestBackup = Get-ChildItem "C:\EMS\PowerShellEndPointv2\WebUI\build_backup_*" | 
        Sort-Object Name -Descending | Select-Object -First 1
    Copy-Item $latestBackup.FullName "C:\EMS\PowerShellEndPointv2\WebUI\build" -Recurse -Force
    ```
2.  **Database Migration Reversion**: No rollback required for schema updates. All Wave 2 column additions are nullable and additive-only; old system code will simply ignore the new columns.
3.  **Restart background service**:
    ```powershell
    Stop-ScheduledTask -TaskName "EMS-API-Service"
    Start-ScheduledTask -TaskName "EMS-API-Service"
    ```
