# EMS Enterprise Deployment Guide (Production)

This document provides a comprehensive guide for deploying the Enterprise Endpoint Monitoring System (EMS) in a production Windows Server environment, utilizing IIS, WinRM, PostgreSQL, and PowerShell.

## 1. Prerequisites & Environment Setup

### 1.1 Core Software Requirements
*   **Operating System**: Windows Server 2019 or 2022 (Host for IIS and PowerShell API).
*   **PostgreSQL**: Version 15.0 or higher (Data storage & Metrics).
*   **Node.js**: Version 20.x LTS or higher (Required for building the Web UI).
*   **PowerShell**: Version 7.3+ (Required for the backend API).
*   **IIS (Internet Information Services)**: Version 10+ (Static content hosting & reverse proxy).
*   **URL Rewrite Module 2.1**: Required for IIS (handles SPA routing and API proxying).

### 1.2 Network & Firewall Requirements
Ensure the following ports and protocols are permitted:
*   **Port 5000 (TCP)**: REST API (Internal loopback `127.0.0.1` only, if using IIS reverse proxy).
*   **Port 5432 (TCP)**: PostgreSQL (Internal loopback `127.0.0.1` only if on the same server).
*   **Port 80 / 443 (TCP)**: Web Interface (HTTP/HTTPS access for users).
*   **Port 5985 / 5986 (TCP)**: WinRM (HTTP/HTTPS) for remote endpoint scanning.

---

## 2. PostgreSQL Database Setup

### 2.1 Database and Role Initialization
Open PowerShell or a `psql` terminal as an administrator and execute:

```sql
-- 1. Create a dedicated service account
CREATE USER ems_service WITH PASSWORD 'StrongDatabasePassword123!';

-- 2. Create the production database
CREATE DATABASE ems_production OWNER ems_service;

-- 3. Grant privileges
GRANT ALL PRIVILEGES ON DATABASE ems_production TO ems_service;
```

### 2.2 Schema Deployment
Deploy the schema scripts located in `PowerShellEndPointv2\Database` in the correct order:
```powershell
$env:PGPASSWORD = 'StrongDatabasePassword123!'
$db = "ems_production"
$user = "ems_service"

psql -U $user -d $db -f ".\PowerShellEndPointv2\Database\schema.sql"
# Apply any relevant migration scripts (e.g., migrate_v5.sql)
psql -U $user -d $db -f ".\PowerShellEndPointv2\Database\migrate_v5.sql"
```

---

## 3. Web UI (React) Deployment to IIS

### 3.1 Build the Production Bundle
Compile the React application into static assets.
```powershell
cd .\PowerShellEndPointv2\WebUI
npm ci --production=false
$env:NODE_ENV = 'production'
npm run build
```
This generates a `build\` directory containing the optimized static files.

### 3.2 IIS Configuration
1.  **Install IIS Features**: Ensure `Web-Server`, `IIS-StaticContent`, and the **URL Rewrite Module** are installed.
2.  **Create Application Pool**: Create an App Pool named `EMS_WebUI_AppPool`. Set the **.NET CLR Version** to `No Managed Code` (since it's a static SPA).
3.  **Create Website**: Map a new IIS Website (e.g., `EMS_WebUI`) to the `build\` directory. Bind it to Port 80 (and/or 443 with a valid SSL certificate).
4.  **Permissions**: Ensure the `IIS_IUSRS` group has Read/Execute permissions on the `build\` folder.

### 3.3 URL Rewrite (`web.config`)
A `web.config` file must be placed in the `build\` root to handle SPA routing and reverse proxy requests to the PowerShell API.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <!-- Proxy /api requests to the backend PowerShell service -->
        <rule name="ReverseProxyAPI" stopProcessing="true">
            <match url="^api/(.*)" />
            <action type="Rewrite" url="http://localhost:5000/api/{R:1}" />
        </rule>
        <!-- SPA Routing: Redirect everything else to index.html -->
        <rule name="React Routes" stopProcessing="true">
          <match url=".*" />
          <conditions logicalGrouping="MatchAll">
            <add input="{REQUEST_FILENAME}" matchType="IsFile" negate="true" />
            <add input="{REQUEST_FILENAME}" matchType="IsDirectory" negate="true" />
          </conditions>
          <action type="Rewrite" url="/" />
        </rule>
      </rules>
    </rewrite>
    <staticContent>
      <mimeMap fileExtension=".json" mimeType="application/json" />
      <mimeMap fileExtension=".woff2" mimeType="application/font-woff2" />
    </staticContent>
  </system.webServer>
</configuration>
```

---

## 4. Backend API (PowerShell) Deployment

### 4.1 Configuration (`EMSConfig.json`)
Update `PowerShellEndPointv2\Config\EMSConfig.json`. Ensure database credentials match step 2.1.
**Note**: Passwords and secrets should ideally be managed via the `Set-EMSEnvironmentVar` DPAPI wrapper in production, but `EMSConfig.json` is the initial source.

```json
{
  "Database": {
    "Host": "localhost",
    "Port": 5432,
    "DatabaseName": "ems_production",
    "Username": "ems_service",
    "Password": "StrongDatabasePassword123!"
  },
  "API": {
    "ListenAddress": "http://localhost:5000/",
    "JWTSecretKey": "<GENERATE_A_LONG_SECURE_RANDOM_STRING>"
  }
}
```

### 4.2 Run API as a Service
The `Start-EMSAPI.ps1` script handles API requests. For production, it must run continuously.
**Using Scheduled Tasks (Native):**
```powershell
$apiScript = "C:\EMS\PowerShellEndPointv2\API\Start-EMSAPI.ps1"
$action = New-ScheduledTaskAction -Execute 'pwsh.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$apiScript`""
$trigger = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName "EMS-API-Service" -Action $action -Trigger $trigger -RunLevel Highest -User 'SYSTEM'
Start-ScheduledTask -TaskName "EMS-API-Service"
```
*(Alternatively, use NSSM - Non-Sucking Service Manager to run it as a proper Windows Service).*

---

## 5. WinRM & Endpoint Configuration

To collect data from endpoints, WinRM must be enabled and accessible.
1.  **Enable WinRM**: On target machines, run `Enable-PSRemoting -Force`.
2.  **Firewall Rules**: Ensure Port `5985` (HTTP) or `5986` (HTTPS) is open inbound on the targets from the EMS Server IP.
3.  **Authentication**: The EMS Server's service account (e.g., `SYSTEM` or a dedicated Active Directory Service Account) needs `Administrators` or `Remote Management Users` privileges on the target endpoints to execute WMI/CIM queries successfully.

---

## 6. Security & OWASP Top 10 Mitigations

EMS incorporates several mechanisms to address OWASP Top 10 vulnerabilities.

| OWASP Risk | EMS Mitigation Strategy |
| :--- | :--- |
| **A01: Broken Access Control** | The API validates JWTs on every protected route. It aggressively strips client-supplied identity headers (`X-EMS-Username`, `X-EMS-Role`) to prevent spoofing. Routes enforce Role-Based Access Control (RBAC) via `Test-ViewerAccessRequirement` and AD group mapping. |
| **A02: Cryptographic Failures** | Authentication tokens are signed JWTs (HS256) using a strong server-side secret (`JWT_SECRET`). The application enforces HTTPS headers (`Strict-Transport-Security`, `X-Content-Type-Options`) and utilizes DPAPI (`EMS.Environment.psm1`) for encrypting DB connection strings and secrets at rest. |
| **A03: Injection** | SQL Injection is prevented by strictly using `Invoke-PGQuery` with parameterized inputs (e.g., `VALUES (@m, @p, @u)`). String interpolation is actively forbidden for SQL queries. |
| **A04: Insecure Design** | The architecture strictly separates the frontend SPA, backend API, and database. Rate limiting is implemented globally in the API listener to prevent brute-force and DoS attacks. |
| **A05: Security Misconfiguration** | IIS requires minimal features. Unnecessary HTTP methods (e.g., TRACE) are blocked by default. The API does not expose stack traces in production 500 errors. |
| **A06: Vulnerable and Outdated Components** | Dependencies in `package.json` are audited (`npm audit`). The deployment script checks for modern Node.js/PowerShell versions. |
| **A07: Identification and Auth Failures** | Rate limiting restricts rapid login attempts. AD authentication is required (no default fallback passwords). |
| **A08: Software and Data Integrity Failures** | Pester integration tests and CI/CD pipelines validate module functionality. Production environments utilize signed commits or restricted push access. |
| **A09: Security Logging and Monitoring** | All API requests are logged to the `audit_api_requests` database table, capturing IP, path, status, and execution time. `Write-EMSLog` records application-level errors and security events. |
| **A10: SSRF** | API endpoints strictly validate target hostnames (e.g., IP/hostname parsing for WinRM) and avoid fetching data from uncontrolled external URLs. |

---

## 7. Known Challenges & Troubleshooting

### 7.1 API Failing to Bind (Port 5000)
*   **Challenge**: The PowerShell listener fails with `Access Denied` or `Port in use`.
*   **Solution**: Ensure the running account (e.g., `SYSTEM`) has permission to bind to the port using `netsh http add urlacl url=http://localhost:5000/ user=Everyone`. Verify no other service occupies port 5000.

### 7.2 IIS URL Rewrite 404 Errors / Infinite Loops
*   **Challenge**: React routes return 404 or the API reverse proxy fails.
*   **Solution**: Ensure the URL Rewrite module is installed globally in IIS. Verify the `web.config` rules are executing in the correct order (Proxy API *first*, then React SPA fallback).

### 7.3 WinRM "Access Denied" or "RPC Server Unavailable"
*   **Challenge**: The EMS Server cannot reach endpoints.
*   **Solution**: This is typically a firewall issue on the endpoint blocking port 5985, or the EMS service account lacks local Administrator rights on the target machine. Use `Test-NetConnection -ComputerName <Target> -Port 5985` to debug connectivity.

### 7.4 Database Parameter Limits
*   **Challenge**: Bulk insert operations failing with parameter limit exceeded errors.
*   **Solution**: PostgreSQL has a hard limit of 65535 parameters per query. The EMS module's `Invoke-PGQuery` calls must utilize chunking (e.g., 1000 items per batch) for large datasets.

### 7.5 PowerShell Version Mismatch
*   **Challenge**: Modules fail to load or syntax errors occur.
*   **Solution**: Ensure the API is executing under PowerShell 7+ (`pwsh.exe`), not Windows PowerShell 5.1 (`powershell.exe`).
