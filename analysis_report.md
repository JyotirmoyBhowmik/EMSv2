# EMS Codebase Analysis Report

## 1. Executive Summary
The Enterprise Endpoint Monitoring System (EMS) is a high-performance, agentless monitoring solution. It leverages PowerShell's deep integration with Windows (via CIM/WMI) to collect granular metrics without requiring a client-side agent. The data is stored in a robust PostgreSQL database and presented through a modern React web interface.

## 2. Architecture Overview
The system follows a classic 3-tier architecture with a unique twist: the backend logic is implemented entirely in PowerShell.

-   **Frontend (Presentation Layer)**: React 18 application. Built with a component-based architecture. Uses `services/api.js` to communicate with the backend.
-   **Backend (Application Layer)**: PowerShell REST API.
    -   **Engine**: `API/Start-EMSAPI.ps1`. Custom HTTP server using `System.Net.HttpListener`.
    -   **Parallelism**: Uses PowerShell Runspaces to execute scans across multiple targets concurrently without blocking the main API thread.
    -   **Connectivity**: Agentless via CIM (DCOM protocol).
-   **Database (Data Layer)**: PostgreSQL.
    -   **Schema**: Granular metric tables (63+ tables) and partitioned `scan_results`.
    -   **Optimization**: Materialized views (`dashboard_statistics`, `view_computer_health_summary`) for fast dashboard loading.

## 3. Core Features
| Feature | Implementation | Notes |
| :--- | :--- | :--- |
| **Multi-Provider Auth** | `Modules/Authentication.psm1` | Supports AD and local auth. |
| **Inventory Collection** | `API/Start-EMSAPI.ps1` (Internal functions) | BIOS, TPM, Software, Services, etc. |
| **Security Monitoring** | `Modules/Scan/` modules | Checks BitLocker, Firewall, AV, and GPO. |
| **Bulk Scanning** | `API/Start-EMSAPI.ps1` | Supports CIDR expansion and batching. |
| **Real-time Dashboard** | `WebUI/src/components/Dashboard.js` | Visualizes health scores and alerts. |
| **Audit Trail** | `audit_logs` table | Tracks every admin action and login. |

## 4. Technical Deep Dive (Code Level)

### API Logic (`Start-EMSAPI.ps1`)
- **Runspace Management**: The `Start-EMSScan` function creates a fresh runspace for every scan. This ensures isolation and stability.
- **Metric Resolution**: Functions like `Get-RemoteRegistryValue` and `Test-RsopPolicyEvidence` show deep knowledge of Windows internals, especially for detecting policies that don't always appear in standard WMI classes.

### Database Logic (`schema_granular_metrics_part1.sql`)
- **Normalization**: Every metric (CPU, Memory, etc.) has its own table, allowing for precise time-series analysis.
- **Relational Integrity**: Uses `REFERENCES computers(computer_name) ON DELETE CASCADE` to maintain data hygiene.

## 5. Identified Gaps & Missing Features
1.  **Transport Security**: Currently uses `http://`. Needs TLS/SSL configuration for enterprise production.
2.  **Modern Remoting**: Relies on DCOM (Port 135). Should support WinRM (WS-Management) for better firewall compatibility.
3.  **Background Worker**: Scheduling logic exists in the schema (`scheduled_scans`) but the backend lacks a persistent worker to trigger these automatically.
4.  **RBAC Expansion**: Roles are limited to Admin/Monitor. Needs more granular permissions (e.g., "Remediation Operator").
5.  **Alerting System**: No proactive alerting (Email/Webhook) when thresholds are breached.

## 6. Recommendations
-   **Implement HTTPS**: Wrap the PowerShell API in a reverse proxy (IIS/Nginx) or use SSL certificates directly.
-   **Integrate WinRM**: Update `New-CimSession` to use WSMan protocol by default.
-   **Worker Service**: Create a separate PowerShell service to handle scheduled tasks.
