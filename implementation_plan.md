# EMS v3.0 — Enterprise Feature Expansion Plan

This plan covers a massive upgrade to the Enterprise Endpoint Monitoring System: 99 features, comprehensive audit logging, lifecycle management, admin settings console, reboot monitoring dashboard, npm security fixes, and favicon fix.

## User Review Required

> [!IMPORTANT]
> This is a **very large** undertaking spanning Backend (PowerShell API), Frontend (React), and Database (PostgreSQL). It is organized into **8 phases** that can be executed incrementally. Each phase builds on the previous one.

> [!WARNING]
> **Breaking Changes**: The `package.json` will be fully updated with latest packages. The existing `react-icons` local `.tgz` file reference will be replaced with the npm registry version.

## Open Questions

1. **SMTP Configuration**: For the "send custom reboot mail" feature, do you have an SMTP relay server available (e.g., Exchange, Office 365, SendGrid)? Or should I use PowerShell's `Send-MailMessage` with a local relay?
2. **User Lifecycle**: Should "User" refer to EMS portal users (admins/operators) or AD domain users on endpoints?
3. **Connector Health**: What "connectors" should be monitored? (e.g., PostgreSQL, AD/LDAP, SMTP, WinRM, CIM/DCOM?)

---

## Phase 1: Foundation & Bug Fixes (Immediate)

### 1.1 Fix Favicon Error
#### [MODIFY] [index.html](file:///c:/Users/jyotu/Desktop/EndpointManagement/EMS/PowerShellEndPointv2/WebUI/public/index.html)
- Generate a proper EMS favicon (SVG inline or `.ico` file)
- Add `<link rel="icon">` tag to `index.html`
- Add Apple touch icon and manifest references

### 1.2 Fix npm Vulnerabilities & Update Packages
#### [MODIFY] [package.json](file:///c:/Users/jyotu/Desktop/EndpointManagement/EMS/PowerShellEndPointv2/WebUI/package.json)
- Update all dependencies to latest stable versions:
  - `react` → `^18.3.1`, `react-dom` → `^18.3.1`
  - `react-scripts` → `5.0.1` → latest or migrate to **Vite** for speed
  - `axios` → `^1.7.9`
  - `react-router-dom` → `^6.28.0`
  - `react-icons` → `^5.4.0` (from npm registry, remove `.tgz` reference)
- Add new dependencies:
  - `recharts` (charts/graphs for dashboards)
  - `date-fns` (date formatting)
  - `react-hot-toast` (notifications)

### 1.3 Version Control
#### [MODIFY] [package.json](file:///c:/Users/jyotu/Desktop/EndpointManagement/EMS/PowerShellEndPointv2/WebUI/package.json)
- Bump version to `3.0.0`
#### [NEW] `PowerShellEndPointv2/CHANGELOG.md`
- Create version history document

---

## Phase 2: Comprehensive Audit System

### 2.1 Enhanced Audit Schema
#### [NEW] `Database/schema_audit_v3.sql`
New tables:
- `audit_api_requests` — Every API call logged (method, path, user, IP, response code, duration)
- `audit_auth_events` — Login/logout/failed attempts/lockouts
- `audit_config_changes` — Configuration changes with before/after snapshots
- `audit_data_access` — Who viewed what data and when
- `audit_remediation_actions` — All remediation actions with approval chain
- `audit_feature_toggles` — Feature enable/disable change history

### 2.2 API Audit Middleware
#### [MODIFY] [Start-EMSAPI.ps1](file:///c:/Users/jyotu/Desktop/EndpointManagement/EMS/PowerShellEndPointv2/API/Start-EMSAPI.ps1)
- Add `Write-AuditLog` function that logs every request to `audit_api_requests`
- Wrap the request loop with automatic audit logging (method, path, user, IP, status code, execution time)

### 2.3 Audit Dashboard (Frontend)
#### [NEW] `WebUI/src/components/AuditLog.js`
- Filterable table: by user, action type, date range, risk level
- Export to CSV
- Real-time log streaming

---

## Phase 3: Admin Settings Console

### 3.1 Feature Toggle System
#### [NEW] `Database/schema_feature_toggles.sql`
```sql
CREATE TABLE feature_toggles (
    feature_key VARCHAR(100) PRIMARY KEY,
    feature_name VARCHAR(255),
    description TEXT,
    enabled BOOLEAN DEFAULT true,
    category VARCHAR(50), -- 'Scanning', 'Security', 'Reporting', 'Notifications'
    changed_by VARCHAR(255),
    changed_at TIMESTAMP DEFAULT NOW()
);
```

### 3.2 Admin Settings API
#### [MODIFY] [Start-EMSAPI.ps1](file:///c:/Users/jyotu/Desktop/EndpointManagement/EMS/PowerShellEndPointv2/API/Start-EMSAPI.ps1)
New endpoints:
- `GET /admin/settings` — Get all feature toggles
- `PUT /admin/settings/:key` — Enable/disable a feature
- `GET /admin/audit` — Get audit logs with filters
- `GET /admin/connectors` — Get connector health status

### 3.3 Admin Console (Frontend)
#### [NEW] `WebUI/src/components/AdminSettings.js`
- Toggle switches for each feature (Scanning, Remediation, Bulk Import, SMTP Notifications, etc.)
- Visual grouping by category
- Change confirmation dialogs
- Audit trail of who changed what

---

## Phase 4: Reboot Monitoring & Mail System

### 4.1 Last Restart Detection Module
#### [NEW] `Modules/Scan/Get-LastReboot.psm1`
- Collects last restart time via `Get-CimInstance Win32_OperatingSystem | Select LastBootUpTime`
- Calculates uptime in days
- Classifies: `Normal` (< 14 days), `Warning` (14–30 days), `Critical` (> 30 days)
- Stores results in `metric_uptime` table

### 4.2 Reboot Dashboard (Frontend)
#### [NEW] `WebUI/src/components/RebootDashboard.js`
- Summary cards: Total endpoints, Needs Reboot (>30 days), Warning (14–30 days), Healthy
- Filterable data table with columns: Computer Name, Last Reboot, Uptime (Days), Status, User, Actions
- Filter by: Status (Critical/Warning/Normal), Department, Topology (HO/Remote)
- Bulk select checkboxes
- "Send Reboot Notification" button for selected endpoints

### 4.3 Custom Mail System
#### [NEW] `Modules/Notifications/Send-EMSMail.psm1`
- `Send-RebootNotification` — Sends customizable email to endpoint users
- Configurable SMTP settings in `EMSConfig.json`
- Email templates with variables (`{ComputerName}`, `{UptimeDays}`, `{UserName}`, `{DueDate}`)

### 4.4 Mail API Endpoints
#### [MODIFY] [Start-EMSAPI.ps1](file:///c:/Users/jyotu/Desktop/EndpointManagement/EMS/PowerShellEndPointv2/API/Start-EMSAPI.ps1)
- `POST /admin/send-reboot-mail` — Send reboot notification to selected endpoints
- `GET /admin/mail-templates` — Get available email templates
- `PUT /admin/mail-config` — Update SMTP settings

---

## Phase 5: User Lifecycle Management

### 5.1 User Management Schema
#### [NEW] `Database/schema_user_lifecycle.sql`
- `user_lifecycle_events` — Track user creation, role changes, deactivation, reactivation
- `user_sessions` — Active sessions tracking
- `user_permissions` — Granular permission assignments

### 5.2 User Management API
#### [MODIFY] [Start-EMSAPI.ps1](file:///c:/Users/jyotu/Desktop/EndpointManagement/EMS/PowerShellEndPointv2/API/Start-EMSAPI.ps1)
- `GET /admin/users` — List all users with status
- `POST /admin/users` — Create user
- `PUT /admin/users/:id` — Update user role/status
- `DELETE /admin/users/:id` — Deactivate user (soft delete)
- `GET /admin/users/:id/activity` — Get user activity history

### 5.3 User Management UI
#### [NEW] `WebUI/src/components/UserManagement.js`
- User table with filters (Active/Inactive/Locked)
- Create/Edit user forms
- Role assignment (Admin, Operator, Viewer)
- Activity timeline per user
- Session management (view/terminate active sessions)

---

## Phase 6: Connector Health Monitoring

### 6.1 Connector Health Module
#### [NEW] `Modules/Health/Get-ConnectorHealth.psm1`
- `Test-DatabaseConnector` — PostgreSQL connectivity, latency, pool stats
- `Test-ADConnector` — Active Directory reachability, bind test
- `Test-SMTPConnector` — SMTP server test (if configured)
- `Test-WinRMConnector` — WinRM remoting availability check
- `Test-CIMConnector` — DCOM/CIM session test to sample endpoints

### 6.2 Connector Health API & UI
#### [MODIFY] [Start-EMSAPI.ps1](file:///c:/Users/jyotu/Desktop/EndpointManagement/EMS/PowerShellEndPointv2/API/Start-EMSAPI.ps1)
- `GET /admin/connectors` — Returns health status of all connectors
#### [NEW] `WebUI/src/components/ConnectorHealth.js`
- Visual cards: Database (green/red), AD (green/red), SMTP, WinRM, CIM
- Latency indicators, last-check timestamps
- Auto-refresh every 60 seconds

---

## Phase 7: Endpoint Lifecycle Management

### 7.1 Endpoint Lifecycle Schema
#### [NEW] `Database/schema_endpoint_lifecycle.sql`
- `endpoint_lifecycle_events` — Track: Discovered, Provisioned, Active, Maintenance, Decommissioned
- `endpoint_tags` — Custom tagging (Department, Location, Owner)
- `endpoint_notes` — Admin notes per endpoint

### 7.2 Endpoint Lifecycle API & UI
#### [MODIFY] [Start-EMSAPI.ps1](file:///c:/Users/jyotu/Desktop/EndpointManagement/EMS/PowerShellEndPointv2/API/Start-EMSAPI.ps1)
- `PUT /computers/:name/lifecycle` — Update lifecycle state
- `POST /computers/:name/tags` — Add/remove tags
- `POST /computers/:name/notes` — Add admin note
#### [NEW] `WebUI/src/components/EndpointLifecycle.js`
- Lifecycle state indicators (color-coded badges)
- Tag management interface
- Notes timeline
- Bulk lifecycle state changes

---

## Phase 8: 99 Enterprise Features Catalog

All features organized by category. Features marked with ✅ already exist; features marked with 🆕 are new.

### Scanning & Discovery (1–15)
1. ✅ Single endpoint scan
2. ✅ Bulk/CIDR scan
3. 🆕 Scheduled recurring scans (cron-based)
4. 🆕 Auto-discovery via AD computer objects
5. ✅ Agentless CIM/WMI collection
6. 🆕 WinRM-based collection (fallback)
7. ✅ Topology detection (HO/Remote)
8. 🆕 Scan queue management & prioritization
9. 🆕 Scan cancellation
10. ✅ Scan status tracking
11. 🆕 Scan result comparison (diff between scans)
12. 🆕 Scan templates (quick, full, security-only)
13. 🆕 Offline endpoint detection
14. 🆕 Wake-on-LAN integration
15. 🆕 Scan throttling per subnet

### Security & Compliance (16–30)
16. ✅ BitLocker status check
17. ✅ Firewall profile validation
18. ✅ Antivirus status check
19. ✅ Windows Update compliance
20. ✅ Screensaver policy detection
21. ✅ USB policy enforcement check
22. ✅ AppLocker status
23. ✅ LAPS password status
24. ✅ Local admin enumeration
25. 🆕 Security baseline scoring
26. 🆕 CIS benchmark mapping
27. 🆕 Vulnerability assessment summary
28. 🆕 Certificate expiry monitoring
29. 🆕 Password policy compliance
30. 🆕 Privileged access review

### Hardware & Inventory (31–45)
31. ✅ BIOS/UEFI information
32. ✅ TPM status
33. ✅ Disk health (SMART)
34. ✅ Memory utilization
35. ✅ CPU performance
36. ✅ Network adapter inventory
37. 🆕 Battery health (laptops)
38. 🆕 Monitor/display inventory
39. 🆕 Peripheral device tracking
40. 🆕 Warranty status integration
41. 🆕 Asset tagging
42. 🆕 Hardware change detection
43. ✅ Serial number collection
44. ✅ Manufacturer/model detection
45. 🆕 Firmware version tracking

### Software Management (46–55)
46. ✅ Installed software inventory
47. ✅ Blacklisted software detection
48. 🆕 Software license tracking
49. 🆕 Software version compliance
50. ✅ Windows services monitoring
51. ✅ Startup program audit
52. ✅ Browser extension inventory
53. ✅ Office version detection
54. 🆕 Patch deployment tracking
55. 🆕 Application crash analysis

### User Experience (56–65)
56. ✅ Login time performance
57. 🆕 Reboot monitoring & notification (NEW — Phase 4)
58. ✅ Application crash tracking
59. ✅ Browser performance
60. ✅ Printer status
61. ✅ Mapped drive validation
62. 🆕 VPN connectivity check
63. 🆕 Network speed test
64. 🆕 Desktop responsiveness score
65. 🆕 User satisfaction survey integration

### Dashboard & Reporting (66–80)
66. ✅ Compliance classification dashboard
67. ✅ Health score visualization
68. ✅ Scan status overview
69. 🆕 Reboot dashboard with filters (NEW — Phase 4)
70. 🆕 Trend analysis charts
71. 🆕 Executive summary report
72. ✅ CSV export
73. 🆕 PDF report generation
74. 🆕 Scheduled report delivery (email)
75. 🆕 Custom report builder
76. 🆕 Real-time alerts dashboard
77. 🆕 Geographic endpoint map
78. 🆕 Department-level analytics
79. 🆕 SLA compliance tracking
80. 🆕 Comparative analysis (month-over-month)

### Administration (81–92)
81. ✅ Role-based access (Admin/Monitor)
82. 🆕 Feature toggle console (NEW — Phase 3)
83. 🆕 User lifecycle management (NEW — Phase 5)
84. 🆕 Connector health monitoring (NEW — Phase 6)
85. 🆕 Endpoint lifecycle management (NEW — Phase 7)
86. ✅ AD group integration
87. 🆕 SMTP mail configuration
88. 🆕 Custom notification templates
89. 🆕 System health self-check
90. 🆕 Database maintenance tools
91. 🆕 Log viewer (in-browser)
92. 🆕 API rate limiting

### Audit & Security (93–99)
93. ✅ Basic audit logging
94. 🆕 Comprehensive API request audit (NEW — Phase 2)
95. 🆕 Authentication event audit (NEW — Phase 2)
96. 🆕 Configuration change audit (NEW — Phase 2)
97. 🆕 Data access audit (NEW — Phase 2)
98. 🆕 Audit log export & retention
99. 🆕 Security incident timeline

---

## Verification Plan

### Automated Tests
- `npm audit` after package updates (should show 0 critical vulnerabilities)
- `npm run build` succeeds without errors
- API starts without errors with all new endpoints loaded
- Database schema migrations run without errors

### Manual Verification
- Favicon displays correctly in browser tab
- Admin Settings page loads with feature toggles
- Reboot Dashboard shows correct uptime data
- Audit logs capture API requests
- Mail sends successfully to test recipients
