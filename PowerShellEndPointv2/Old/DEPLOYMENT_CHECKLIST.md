# EMS Deployment Checklist

Use this checklist to ensure proper deployment of the EMS Web Architecture.

---

## Pre-Deployment

### Prerequisites Installed
- [ ] PostgreSQL 15+ installed and running
- [ ] Node.js 16+ installed
- [ ] PowerShell 5.1+ available
- [ ] IIS 10+ installed (production only)
- [ ] Npgsql driver downloaded to `.\Lib\`
- [ ] UniversalDashboard module installed

### Network & Permissions
- [ ] Firewall ports opened (80, 443, 5432, 5000)
- [ ] DNS resolution working
- [ ] AD security group `EMS_Admins` created
- [ ] Users added to `EMS_Admins` group
- [ ] WinRM enabled on target endpoints

---

## Database Setup

### PostgreSQL Configuration
- [ ] Database `ems_production` created
- [ ] User `ems_service` created with password
- [ ] Schema deployed (`psql -f Database\schema.sql`)
- [ ] Permissions granted to service user
- [ ] Connection test successful

### Verification Commands
```powershell
# Test connection
Import-Module .\Modules\Database\PSPGSql.psm1
Initialize-PostgreSQLConnection -Config $config
Test-PostgreSQLConnection

# Verify tables
psql -U postgres -d ems_production -c "\dt"
# Should show: users, scan_results, diagnostic_details, audit_logs, etc.
```

---

## Application Configuration

### EMSConfig.json Updated
- [ ] Database connection settings correct
- [ ] Database password set (not default)
- [ ] JWT secret key generated (32+ chars)
- [ ] API listen address configured
- [ ] CORS origins set correctly
- [ ] Admin group name matches AD group
- [ ] Network subnets configured
- [ ] UseSCCM set to `false` (if no SCCM)

### Generate JWT Secret
```powershell
-join ((65..90) + (97..122) + (48..57) | Get-Random -Count 32 | ForEach-Object {[char]$_})
```

---

## Development Testing

### API Backend
- [ ] Modules import without errors
- [ ] `.\API\Start-EMSAPI.ps1` runs successfully
- [ ] API responds on http://localhost:5000
- [ ] Login endpoint returns JWT token
- [ ] Database queries execute

### Test API Endpoint
```powershell
$body = @{ username = "CORP\testuser"; password = "password" } | ConvertTo-Json
Invoke-RestMethod -Uri "http://localhost:5000/api/auth/login" -Method POST -Body $body -ContentType "application/json"
```

### Web Frontend
- [ ] `npm install` completes in `.\WebUI\`
- [ ] `npm start` launches dev server
- [ ] Browser opens to http://localhost:3000
- [ ] Login page renders correctly
- [ ] Can authenticate with AD credentials
- [ ] Dashboard displays after login
- [ ] Scan functionality works
- [ ] Results history shows data

---

## Production Build

### React Application
- [ ] `npm run build` completes successfully
- [ ] Build artifacts created in `.\WebUI\build\`
- [ ] No console errors in production build
- [ ] Environment variables set (if any)

### Build Commands
```powershell
cd WebUI
npm run build
# Output: Optimized production build in ./build/
```

---

## IIS Deployment (Production)

### IIS Configuration
- [ ] IIS features installed
- [ ] URL Rewrite module installed
- [ ] Application pool `EMS_Pool` created
- [ ] Website `EMS` created
- [ ] Physical path set to `C:\inetpub\ems\webui\`
- [ ] Bindings configured (port 80/443)
- [ ] `web.config` created with React Router rewrite rules
- [ ] Reverse proxy configured for `/api/*`

### File Deployment
- [ ] React build files copied to `C:\inetpub\ems\webui\`
- [ ] `web.config` in webui root
- [ ] Permissions set (IIS_IUSRS readable)

### API Service
- [ ] NSSM installed (`choco install nssm`)
- [ ] Service `EMS_API` created
- [ ] Service configured to run `Start-EMSAPI.ps1`
- [ ] Service starts successfully
- [ ] Service set to auto-start
- [ ] Logs directory created and writable

### Install Service
```powershell
nssm install EMS_API powershell.exe "-ExecutionPolicy Bypass -File C:\Path\To\API\Start-EMSAPI.ps1"
nssm set EMS_API AppDirectory "C:\Path\To\API"
Start-Service EMS_API
```

---

## Security Hardening

### HTTPS Configuration
- [ ] SSL certificate obtained
- [ ] Certificate imported to Local Machine store
- [ ] HTTPS binding added to IIS site
- [ ] Certificate bound to HTTPS binding
- [ ] HTTP to HTTPS redirect configured (optional)
- [ ] Force HTTPS in React app config

### Access Control
- [ ] Only `EMS_Admins` group members can login
- [ ] API port 5000 restricted to localhost only
- [ ] PostgreSQL port 5432 internal only
- [ ] File system permissions restricted
- [ ] Sensitive config files protected

### Firewall Rules
```powershell
# Allow HTTP/HTTPS
New-NetFirewallRule -DisplayName "EMS Web - HTTP" -Direction Inbound -Protocol TCP -LocalPort 80 -Action Allow
New-NetFirewallRule -DisplayName "EMS Web - HTTPS" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow

# Block external API access
New-NetFirewallRule -DisplayName "EMS API - Block External" -Direction Inbound -Protocol TCP -LocalPort 5000 -RemoteAddress Any -Action Block
```

---

## Data Migration (If Applicable)

### CSV Log Import
- [ ] Legacy log directory identified
- [ ] Migration script tested
- [ ] Dry-run completed successfully
- [ ] Full migration executed
- [ ] Data verification completed
- [ ] Dashboard stats refreshed

### Migration Command
```powershell
.\Database\migrate_csv_to_postgresql.ps1 -CSVLogPath "C:\EMSLogs"
```

---

## Verification & Testing

### End-to-End Testing
- [ ] Can access web UI from browser
- [ ] Login with AD credentials successful
- [ ] Dashboard loads with statistics
- [ ] Can initiate single scan
- [ ] Scan results save to database
- [ ] Results appear in history
- [ ] Health scores calculated correctly
- [ ] Diagnostic details display
- [ ] Audit logs written
- [ ] Can logout successfully

### Performance Testing
- [ ] Page load times acceptable (<3s)
- [ ] Scan execution completes reasonably (<30s)
- [ ] Database queries optimized (check indexes)
- [ ] API responses under 1s for queries
- [ ] Dashboard auto-refresh works

### Browser Compatibility
- [ ] Chrome/Edge (latest)
- [ ] Firefox (latest)
- [ ] Safari (if Mac users)
- [ ] Mobile responsive (phone/tablet)

---

## Monitoring & Maintenance

### Logging Setup
- [ ] Application logs directory created
- [ ] IIS logs enabled and accessible
- [ ] PostgreSQL logs configured
- [ ] API service logs readable
- [ ] Error reporting configured

### Backup Strategy
- [ ] PostgreSQL automated backups scheduled
- [ ] Backup retention policy defined
- [ ] Backup restore tested
- [ ] Configuration files backed up

### Backup Commands
```powershell
# PostgreSQL backup
pg_dump -U postgres -F c -f "ems_backup_$(Get-Date -Format 'yyyyMMdd').dump" ems_production

# Restore
pg_restore -U postgres -d ems_production -c "ems_backup_20251224.dump"
```

### Maintenance Tasks
- [ ] Monthly database partition creation scheduled
- [ ] Dashboard statistics refresh configured
- [ ] Log rotation configured
- [ ] Disk space monitoring enabled

---

## Documentation & Training

### User Documentation
- [ ] Access URL documented and shared
- [ ] Login instructions provided
- [ ] User guide created (optional)
- [ ] Support contact information shared

### Administrator Handoff
- [ ] Database credentials documented securely
- [ ] Service restart procedures documented
- [ ] Troubleshooting guide provided
- [ ] Escalation procedures defined

---

## Rollback Plan

### Emergency Rollback
- [ ] Legacy application still accessible (if needed)
- [ ] Database backup available
- [ ] Previous configuration saved
- [ ] Rollback procedure documented

---

## Sign-Off

### Development Team
- [ ] All unit tests passing
- [ ] Code reviewed
- [ ] Documentation complete
- [ ] Deployment guide reviewed

**Developer Sign-off**: _________________ Date: _________

### Operations Team
- [ ] Infrastructure ready
- [ ] Monitoring configured
- [ ] Backups verified
- [ ] Support procedures in place

**Operations Sign-off**: _________________ Date: _________

### Business Owner
- [ ] Acceptance testing complete
- [ ] Business requirements met
- [ ] Users trained
- [ ] Go-live approved

**Business Sign-off**: _________________ Date: _________

---

## Post-Deployment

### Day 1
- [ ] Monitor error logs closely
- [ ] Check API service status
- [ ] Verify database connections
- [ ] Respond to user issues quickly

### Week 1
- [ ] Review performance metrics
- [ ] Gather user feedback
- [ ] Address any bugs
- [ ] Optimize slow queries

### Month 1
- [ ] Review audit logs
- [ ] Check disk usage growth
- [ ] Evaluate backup strategy
- [ ] Plan enhancements

---

**Deployment Date**: _______________  
**Deployed By**: _______________  
**Production URL**: _______________
