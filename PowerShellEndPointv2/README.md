# Enterprise Endpoint Monitoring System - Web Architecture

## Project Overview

The Enterprise Endpoint Monitoring System (EMS) has been migrated from a WPF desktop application to a modern web-based architecture with PostgreSQL database backend.

## Architecture Components

### 1. Database Layer (PostgreSQL)
- **Location**: `Database/`
- **Schema**: `schema.sql`
- **Module**: `Modules/Database/PSPGSql.psm1`
- **Features**:
  - Partitioned tables for performance
  - Materialized views for dashboard stats
  - JSONB storage for flexible diagnostics
  - Full audit trail

### 2. REST API Backend (PowerShell Universal Dashboard)
- **Location**: `API/Start-EMSAPI.ps1`
- **Port**: 5000 (configurable in `EMSConfig.json`)
- **Authentication**: JWT tokens with AD validation
- **Endpoints**:
  - `/api/auth/login` - User authentication
  - `/api/auth/validate` - Token validation
  - `/api/scan/single` - Single endpoint scan
  - `/api/results` - Results retrieval (paginated)
  - `/api/results/:id` - Specific scan details
  - `/api/dashboard/stats` - Dashboard statistics

### 3. Web Frontend (React)
- **Location**: `WebUI/`
- **Technology**: React 18 + React Router
- **Features**:
  - Responsive design
  - Real-time dashboard
  - Scan execution interface
  - Results history browser
  - **[v3.0]** Admin Settings Console (Feature Toggles)
  - **[v3.0]** Comprehensive Audit Log Viewer
  - **[v3.0]** Reboot Monitoring & Mail Dashboard
  - **[v3.0]** User & Endpoint Lifecycle Management
  - **[v3.0]** Connector Health Monitoring
- **Build**: `npm run build`
- **Dev Server**: `npm start` (port 3000)

### 4. IIS Deployment
- **Location**: `Deployment/IIS_Setup.md`
- **Features**:
  - Static file hosting for React app
  - Reverse proxy to API backend
  - URL rewriting for React Router
  - HTTPS configuration

---

## Quick Start

### Prerequisites
- PostgreSQL 15+
- Node.js 16+
- PowerShell 5.1+
- IIS 10+ (for production)

### Development Setup

**1. Database**:
```powershell
# Install PostgreSQL
# Create database: ems_production
# Run schema:
psql -U postgres -d ems_production -f Database\schema.sql

# Install Npgsql driver
nuget install Npgsql -OutputDirectory .\Lib -Version 7.0.6
```

**2. Configure**:
Update `Config\EMSConfig.json`:
- Database connection settings
- API configuration
- Security settings

**3. Start API**:
```powershell
.\API\Start-EMSAPI.ps1
```

**4. Start Web UI**:
```powershell
cd WebUI
npm install
npm start
```

**5. Access Application**:
- Development: http://localhost:3000
- Login with AD credentials (user must be in `EMS_Admins` group)

---

---

## Enterprise Deployment Strategy

This project follows a strict **Dev-to-Prod** workflow designed for secure enterprise environments.

### 1. Workflow Overview
- **Development Environment**: Full Git installation. Development happens here. Code is pushed to the central GitHub repository.
- **Production Environment**: Minimal Git installation (client only). No direct code modification allowed. Production pulls updates from the GitHub repository.

### 2. Environment Configuration
| Feature | Development | Production |
| :--- | :--- | :--- |
| **Git Role** | Push / Pull | **Pull Only** |
| **Code Access** | Write | Read-Only |
| **DB Mode** | Dev/Test | Production (Partitioned) |
| **Security** | Local Auth | Full AD Integration + HTTPS |

### 3. Updating Production
To update the production environment:
1.  **Stage & Push**: On the Dev machine:
    ```powershell
    git add .
    git commit -m "Description of changes"
    git push origin main
    ```
2.  **Pull Updates**: On the Production server:
    ```powershell
    git pull origin main
    # Follow build steps if WebUI changes
    cd WebUI; npm run build; iisreset
    ```

> [!NOTE]
> The Production environment is configured to **never push** changes back to Git, ensuring that the production codebase remains a pristine reflection of the approved main branch.

---

## Configuration

### Database (`EMSConfig.json`)
```json
{
  "Database": {
    "Host": "localhost",
    "Port": 5432,
    "DatabaseName": "ems_production",
    "Username": "ems_service",
    "Password": "..."
  }
}
```

### API (`EMSConfig.json`)
```json
{
  "API": {
    "ListenAddress": "http://localhost:5000",
    "JWTSecretKey": "...",
    "EnableCORS": true,
    "AllowedOrigins": ["http://localhost:3000"]
  }
}
```

### User Resolution (No SCCM)
```json
{
  "UserResolution": {
    "UseSCCM": false,
    "FallbackToDC": true
  }
}
```

---

## Migration from CSV Logs

To import existing CSV logs into PostgreSQL:

```powershell
.\Database\migrate_csv_to_postgresql.ps1 -CSVLogPath "C:\EMSLogs"
```

---

## Monitoring & Maintenance

### View Logs
```powershell
# API logs (if running as service)
Get-Content "C:\Users\ZORO\PowerShellEndPointv2\Logs\api_stdout.log" -Tail 50

# IIS logs
Get-Content "C:\inetpub\logs\LogFiles\W3SVC1\*.log" -Tail 50
```

### Database Maintenance
```sql
-- Create next month's partition
SELECT create_monthly_partition('2026-05-01'::date);

-- Refresh dashboard stats
SELECT refresh_dashboard_stats();

-- Backup database
pg_dump -U postgres -F c -f backup.dump ems_production
```

### Update React App
```powershell
cd WebUI
npm run build
Copy-Item -Path ".\build\*" -Destination "C:\inetpub\ems\webui\" -Recurse -Force
iisreset
```

---

## Troubleshooting

### API Not Responding
```powershell
# Check service status
Get-Service EMS_API

# Restart service
Restart-Service EMS_API

# Test manually
.\API\Start-EMSAPI.ps1
```

### Database Connection Issues
```powershell
# Test connection
Import-Module .\Modules\Database\PSPGSql.psm1
Initialize-PostgreSQLConnection -Config $config
Test-PostgreSQLConnection
```

### IIS 500 Errors
- Check `web.config` syntax
- Verify URL Rewrite module installed
- Review IIS Application Event Log
- Confirm API backend is running

---

## Security

### Production Recommendations
1. **Use HTTPS**: Install enterprise CA certificate
2. **Secure Database Password**: Use Windows Credential Manager
3. **JWT Secret**: Generate strong random key (32+ characters)
4. **Firewall**: Restrict API port to localhost only
5. **AD Groups**: Limit `EMS_Admins` membership
6. **Audit Logs**: Monitor for unauthorized access attempts

### Password Storage
```powershell
# Store database password securely
$securePassword = Read-Host "Database Password" -AsSecureString
$securePassword | Export-Clixml -Path "Config\db_password.xml"

# Update EMSConfig.json
"PasswordFile": "C:\\Path\\To\\Config\\db_password.xml"
```

---

## File Structure

```
PowerShellEndPointv2/
├── API/
│   └── Start-EMSAPI.ps1        # REST API server
├── Config/
│   └── EMSConfig.json          # Main configuration
├── Database/
│   ├── schema.sql              # PostgreSQL schema
│   ├── migrate_csv_to_postgresql.ps1
│   └── README.md               # Database setup guide
├── Deployment/
│   └── IIS_Setup.md            # IIS deployment guide
├── Lib/
│   └── Npgsql.dll              # PostgreSQL .NET driver
├── Modules/
│   ├── Database/
│   │   └── PSPGSql.psm1        # Database connectivity
│   ├── Health/
│   │   └── Get-ConnectorHealth.psm1 # [v3.0] Connector health monitoring
│   ├── Notifications/
│   │   └── Send-EMSMail.psm1   # [v3.0] Email notifications
│   ├── Scan/
│   │   └── Get-LastReboot.psm1 # [v3.0] Reboot monitoring
│   ├── Authentication.psm1
│   ├── DataFetcher.psm1
│   └── ... (existing modules)
├── WebUI/
│   ├── public/
│   ├── src/
│   │   ├── components/
│   │   │   ├── Login.js
│   │   │   ├── Dashboard.js
│   │   │   ├── ScanEndpoint.js
│   │   │   ├── ResultsHistory.js
│   │   │   ├── AdminSettings.js    # [v3.0] Feature toggles
│   │   │   ├── AuditLog.js         # [v3.0] Audit viewer
│   │   │   ├── RebootDashboard.js  # [v3.0] Reboot monitoring
│   │   │   ├── ConnectorHealth.js  # [v3.0] Connector health
│   │   │   ├── UserManagement.js   # [v3.0] User lifecycle
│   │   │   └── EndpointLifecycle.js# [v3.0] Endpoint lifecycle
│   │   ├── services/
│   │   │   └── api.js
│   │   ├── App.js
│   │   └── index.js
│   ├── package.json
│   └── README.md
├── Invoke-EMS.ps1              # Original WPF app (legacy)
└── README.md                   # This file
```

---

## Support

For issues or questions:
1. Review logs in `Logs/` directory
2. Check `Database/README.md` for database help
3. See `Deployment/IIS_Setup.md` for deployment issues
4. Review PowerShell module documentation in code comments

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 3.0.0 | 2026-05-07 | Enterprise Feature Expansion (99 features, Admin Console, Lifecycle, Audit, Reboot Mon) |
| 2.0.0 | 2025-12-23 | Web architecture migration (PostgreSQL + React + API) |
| 1.0.0 | 2025-12-23 | Initial WPF desktop application |

---

**Congratulations!** Your EMS system is now modernized with a web-based architecture, enabling multi-user access, centralized data storage, and scalable deployment.
