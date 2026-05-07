# Legacy Desktop Application Archive

**Date Archived**: 2025-12-23  
**Reason**: Migrated to web-based architecture (EMS v2.0)

---

## Files in This Directory

This folder contains the **deprecated WPF desktop application** files from EMS v1.0:

### Application Files
- **Invoke-EMS.ps1**: Main launcher script for WPF desktop application
- **MainWindow.xaml**: XAML definition for WPF user interface
- **sample_targets.csv**: Example CSV file for bulk scanning (legacy format)

---

## Migration Notice

⚠️ **These files are NO LONGER USED in production.**

The Enterprise Endpoint Monitoring System has been modernized with:
- **Web Interface**: React-based responsive UI
- **REST API**: PowerShell Universal Dashboard backend
- **Database**: PostgreSQL for centralized storage
- **Deployment**: IIS web server

---

## For Reference Only

These files are kept for:
1. **Historical reference**: Understanding previous implementation
2. **Code reuse**: PowerShell modules are still shared with web version
3. **Fallback**: Emergency access if web version is unavailable (not recommended)

---

## Running Legacy App (Not Recommended)

If you absolutely must run the old desktop app:

```powershell
# Navigate to archive
cd C:\Users\ZORO\PowerShellEndPointv2\Archive_Legacy_Desktop_App

# Run WPF app
powershell.exe -ExecutionPolicy Bypass -File .\Invoke-EMS.ps1
```

**Limitations of Legacy App**:
- ❌ Single-user (cannot be shared)
- ❌ File-based logging (no central database)
- ❌ Desktop only (no remote access)
- ❌ No mobile support
- ❌ No audit trail
- ❌ No historical trending

---

## Migration to Web Version

See the following guides to use the new web application:

1. **Installation**: [../INSTALLATION.md](../INSTALLATION.md)
2. **Architecture**: [../README.md](../README.md)
3. **Deployment**: [../Deployment/IIS_Setup.md](../Deployment/IIS_Setup.md)

---

**Archive Created**: 2025-12-23  
**Web Version**: 2.0.0  
**Status**: Deprecated - Do Not Use in Production
