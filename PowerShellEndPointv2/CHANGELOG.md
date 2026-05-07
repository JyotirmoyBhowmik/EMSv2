# EMS Changelog

## [3.0.0] - 2026-05-07

### Added
- **99 Enterprise Features** cataloged and tracked
- **Comprehensive Audit System** — API request logging, auth events, config change tracking
- **Admin Settings Console** — Feature toggle switches to enable/disable system functions
- **Reboot Monitoring Dashboard** — Last restart tracking with filterable table and custom mail notifications
- **User Lifecycle Management** — User CRUD, role management, activity timeline
- **Connector Health Monitoring** — Real-time health checks for Database, AD, SMTP, WinRM, CIM
- **Endpoint Lifecycle Management** — Lifecycle states, tagging, notes, bulk operations
- **Custom Mail System** — SMTP-based reboot notification emails with templates
- Updated all npm packages to latest stable versions
- Added `recharts` for dashboard charts
- Added `date-fns` for date formatting
- Added `react-hot-toast` for notifications
- Fixed favicon error (generated proper EMS icon)

### Changed
- Bumped version to 3.0.0
- `react-icons` now installed from npm registry (removed local .tgz)
- API listener updated from `*` to `+` for Windows compatibility

### Security
- Fixed npm audit vulnerabilities by upgrading all dependencies

## [2.9.0] - 2026-05-06
- Role-based Login with EMS_Admins / EMS_Monitor Authorization
- Compliance Classification Dashboard
- Collection Failed card
- BIOS Password Unknown tracking

## [1.0.0] - 2025-12-23
- Initial release
- PowerShell REST API with HttpListener
- React 18 frontend
- PostgreSQL database with partitioning
- AD-based authentication
