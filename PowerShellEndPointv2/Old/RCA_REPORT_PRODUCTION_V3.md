# Root Cause Analysis (RCA) - Production API Connectivity & UI Stability

## 1. Issue Description
Users reported persistent `404 (Not Found)` errors in the browser console when accessing administrative dashboards (User Management, Reboot Dashboard, Connector Health, System Errors). Additionally, the UI was prone to crashing when backend data was malformed or missing.

## 2. Root Cause Analysis

### A. Environment Configuration Mismatch (Primary Cause)
*   **Finding**: The production console logs showed the frontend attempting to connect to `http://10.192.6.109:5000`.
*   **Root Cause**: The `.env` file in the source code was configured with `REACT_APP_API_URL=http://10.192.6.87:5000`.
*   **Impact**: Every administrative API call was routed to an old or incorrect IP address, resulting in network-level 404 errors regardless of whether the backend code was correct.

### B. Missing & Misaligned API Endpoints
*   **Finding**: Even if the IP were correct, several administrative routes were not registered in the PowerShell API.
*   **Root Cause**: New features (System Errors, Connector Health) were implemented in the UI but the corresponding `switch` cases in `Start-EMSAPI.ps1` were missing or using different column names than the database schema.
*   **Impact**: Backend-side 404s for the newly added features.

### C. Lack of Defensive Frontend Programming
*   **Finding**: Components were calling `.filter()` or `.map()` directly on API responses.
*   **Root Cause**: When the API returned a 404 (which returns an error object) instead of the expected array, the code crashed with `TypeError: data.filter is not a function`.
*   **Impact**: Total UI crash (White Screen of Death) instead of a graceful "No Data" message.

---

## 3. Resolution Steps Taken

### Phase 1: Frontend Hardening
*   **Action**: Updated all administrative components (`UserManagement`, `RebootDashboard`, `AuditLog`, `SystemErrors`, `AdminSettings`) with `Array.isArray()` checks.
*   **Result**: The UI no longer crashes on API errors; it displays a "No data" message gracefully.

### Phase 2: Backend Alignment
*   **Action**: Updated `Start-EMSAPI.ps1` to include all missing administrative routes.
*   **Action**: Fixed column name mismatches in the Audit logging SQL queries to match the `audit_api_requests` table schema.
*   **Result**: Backend is now fully prepared to serve the administrative dashboards.

### Phase 3: Production Environment Correction
*   **Action**: Updated `.env` to the correct production IP: `http://10.192.6.109:5000`.
*   **Action**: Performed a fresh production build (`npm run build`).
*   **Action**: Force-pushed the new build artifacts to GitHub for deployment.

---

## 4. Verification & Deployment Instructions

### To Apply the Fixes:
1.  **Pull latest code on the production server**:
    ```powershell
    git pull origin main
    ```
2.  **Restart the API**:
    Stop and start `Start-EMSAPI.ps1`.
3.  **Update IIS Files**:
    Copy the pre-built files I pushed to your IIS directory:
    ```powershell
    Copy-Item -Path "D:\EMS\PowerShellEndPointv2\WebUI\build\*" -Destination "C:\inetpub\wwwroot\ems" -Recurse -Force
    ```

## 5. Prevention Plan
*   **Centralized Config**: Moved the API URL to a single `.env` file.
*   **Build Automation**: The `Deploy-EMSWebUI.ps1` script should be used for all future updates to ensure the build process is consistent.
*   **Global Error Handling**: The `ErrorBoundary` implemented in `index.js` will now catch and report any future UI issues to the System Errors log.

