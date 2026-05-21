# Enterprise Endpoint Monitoring System (EMS) Analysis Report

## 1. File and Code Interconnectivity

The EMS is built on a 3-tier architecture. The core files and their interconnections are as follows:

*   **Frontend (React WebUI):** Located in `PowerShellEndPointv2/WebUI/`.
    *   **Components:** UI elements in `src/components/` (e.g., `Dashboard.jsx`, `ScanEndpoint.jsx`, `AdminSettings.jsx`).
    *   **API Client:** `src/services/api.js` acts as the bridge, using `ky` to send HTTP requests to the backend API.
*   **Backend (PowerShell REST API):** Located in `PowerShellEndPointv2/API/`.
    *   **Entry Point:** `Start-EMSAPI.ps1` runs a custom HTTP server (`System.Net.HttpListener`).
    *   **Configuration:** Reads `PowerShellEndPointv2/Config/EMSConfig.json` for database connection details, allowed origins (CORS), and authentication settings.
    *   **Modules:** Delegates logic to `PowerShellEndPointv2/Modules/` (e.g., `Authentication.psm1`, `Scan/Get-LastReboot.psm1`, `Database/PSPGSql.psm1`).
*   **Database (PostgreSQL):** Defined in `PowerShellEndPointv2/Database/`.
    *   **Schema:** `ems_complete_schema.sql` defines the structure, including granular metric tables and materialized views for dashboard stats.

## 2. Action Flow

1.  **User Trigger:** A user initiates an action (e.g., clicks "Scan") in a React component (`ScanEndpoint.jsx`).
2.  **API Call:** The component calls a function in `services/api.js`, which sends an authenticated POST request to the backend (e.g., `http://localhost:5000/api/scan/single`).
3.  **Backend Processing:** `Start-EMSAPI.ps1` receives the request, validates the JWT, and routes it. It often spawns a background PowerShell Runspace to handle long-running tasks without blocking.
4.  **Data Collection:** The module (e.g., a scan module) connects to the target machine (via CIM/DCOM) to collect metrics.
5.  **Database Storage:** The module uses `PSPGSql.psm1` to execute queries (via `Invoke-PGQuery`), storing the collected data in the PostgreSQL database.
6.  **Response:** The backend returns a JSON response to the frontend, updating the UI.

## 3. Dependent Services

*   **PostgreSQL (15+):** Required for data storage.
*   **Node.js (16+):** Required to build and serve the React frontend.
*   **PowerShell (5.1+):** Required to run the backend API and modules.
*   **Active Directory (AD):** Optional but common for authentication (`EMS_Admins` group).
*   **Windows Endpoints:** Target machines must support CIM/DCOM connections.
*   **IIS (10+):** Recommended for production hosting of the frontend and proxying to the backend.

## 4. Gaps and Weaknesses

*   **Transport Security:** The backend currently defaults to `http://`. Production requires HTTPS (TLS/SSL).
*   **Remoting Protocol:** Relies heavily on legacy DCOM (Port 135) via `New-CimSession`. This is often blocked by firewalls.
*   **Background Tasks:** The database has a `scheduled_scans` table, but the backend lacks a persistent worker process to execute them automatically.
*   **Access Control:** RBAC is limited (Admin/Monitor). More granular roles (e.g., Remediation Operator) are needed.
*   **Alerting:** Lack of proactive alerting (e.g., email or webhook notifications when a threshold is breached).
*   **Testing:** Lack of frontend tests and potential brittleness in PowerShell module integration testing.

## 5. Suggested Enhancements

*   **Implement HTTPS:** Configure `Start-EMSAPI.ps1` to use SSL certificates or deploy it behind a secure reverse proxy.
*   **Modernize Remoting:** Switch from DCOM to WinRM (WS-Management) for `New-CimSession` to improve firewall compatibility.
*   **Develop a Background Worker Service:** Create a separate, persistent PowerShell script/service to handle scheduled scans and asynchronous tasks.
*   **Expand RBAC:** Implement granular permissions in the database and API.
*   **Proactive Alerting System:** Implement the planned `Send-EMSMail.psm1` for threshold-based notifications.
*   **Improve Test Coverage:** Add Vitest/Jest tests for the React frontend and isolated Pester tests for PowerShell modules.

## 6. Draft Prompt for Future Development

**Prompt:**

"Please develop the following missing features and fixes for the Enterprise Endpoint Monitoring System (EMS):

1.  **Modernize PowerShell Remoting:** Update the core scanning modules (e.g., `Start-EMSScan` and related CIM functions) to use WinRM (WS-Management) instead of DCOM. Ensure this is configurable with a fallback mechanism if WinRM fails.
2.  **Implement a Background Worker:** Create a new PowerShell script (e.g., `Start-EMSWorker.ps1`) that runs continuously as a service. It should poll the `scheduled_scans` PostgreSQL table and execute scheduled tasks autonomously.
3.  **Proactive Email Alerting:** Implement the `Send-EMSMail.psm1` module. It needs to read SMTP configurations from `EMSConfig.json` (or the DPAPI environment config) and provide a function to send alerts when specific metric thresholds (e.g., CPU > 90% or Uptime > 30 days) are breached. Integrate this check into the scanning pipeline.
4.  **Enhance Frontend Testing:** Set up a basic test suite for the React WebUI using Vitest. Write at least two component tests (e.g., for `Dashboard.jsx` and `Login.jsx`) to ensure the testing framework is correctly configured and functional."
