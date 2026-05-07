# EMS v2.1 - Complete Step-by-Step Setup Guide

**Version**: 2.1  
**Last Updated**: 2025-12-29  
**Estimated Time**: 45-60 minutes

---

## 📋 Overview

This guide walks you through setting up the Enterprise Monitoring System v2.1 from scratch. Each step includes detailed comments explaining what's happening and why.

**What You'll Set Up**:
- PostgreSQL database with 131 tables
- Multi-provider authentication (Standalone, AD, LDAP)
- PowerShell API backend
- React web UI frontend
- 63 granular metric tables
- Application monitoring (Zscaler, Seclore, OneDrive)

---

## ✅ Prerequisites Check

### Step 1: Verify PowerShell Version

```powershell
# Check PowerShell version - need 5.1 or higher
$PSVersionTable.PSVersion

# Expected output: Major 5 or higher
# Example: Major=7, Minor=4
```

**Why**: The system uses modern PowerShell features like classes and async operations.

---

### Step 2: Install PostgreSQL

```powershell
# Download PostgreSQL 14+ from https://www.postgresql.org/download/windows/
# Or use installer:
# During installation:
# - Port: 5432 (default)
# - Password: Choose a strong password (you'll need this)
# - Locale: Default
# - Components: Install PostgreSQL Server, pgAdmin, Command Line Tools

# After installation, verify:
psql --version

# Expected: psql (PostgreSQL) 14.x or higher
```

**Why**: PostgreSQL provides advanced features like JSONB, partitioning, and materialized views needed for performance.

**Important**: Remember the postgres superuser password - you'll need it for database setup.

---

### Step 3: Install Node.js and npm

```powershell
# Download Node.js LTS from https://nodejs.org/
# Minimum version: 16.x
# Recommended: 18.x or 20.x

# After installation, verify:
node --version
npm --version

# Expected output:
# node: v18.x.x or higher
# npm: 9.x.x or higher
```

**Why**: React web UI requires Node.js and npm for development and building.

---

### Step 4: Install Git (if not already installed)

```powershell
# Download from https://git-scm.com/download/win
# Or check if already installed:
git --version

# Expected: git version 2.x.x
```

**Why**: Used for version control and pulling updates.

---

### Step 5: Verify PowerShell Modules

```powershell
# Check if required modules are available
# These are typically built-in with Windows, but verify:

Get-Module -ListAvailable -Name PSScheduledJob
Get-Module -ListAvailable -Name ActiveDirectory  # Optional - only if using AD auth

# If ActiveDirectory module missing and needed:
# Install RSAT tools from Windows Settings > Optional Features
```

**Why**: System uses PowerShell modules for scheduling and AD integration.

---

## 🗄️ Database Setup

### Step 6: Create Database

```powershell
# Navigate to project directory
cd C:\Users\ZORO\PowerShellEndPointv2

# Open PostgreSQL command prompt
# You'll be prompted for the postgres password you set during installation
psql -U postgres

# Now you're in PostgreSQL prompt (postgres=#)
# Create the database:
CREATE DATABASE ems_production;

# Verify it was created:
\l

# You should see ems_production in the list

# Connect to the new database:
\c ems_production

# You should see: "You are now connected to database "ems_production""

# Exit PostgreSQL:
\q
```

**Why**: Creates an isolated database for the EMS system with proper naming convention.

**Comment**: `ems_production` is the production database name. For testing, you might create `ems_development` or `ems_test` following the same steps.

---

### Step 7: Create Database User (Service Account)

```powershell
# Reconnect to PostgreSQL
psql -U postgres -d ems_production

# Create dedicated user for the application
# Replace 'YourSecurePassword123!' with a strong password
CREATE USER ems_service WITH PASSWORD 'YourSecurePassword123!';

# Grant necessary privileges
GRANT CONNECT ON DATABASE ems_production TO ems_service;
GRANT USAGE ON SCHEMA public TO ems_service;
GRANT CREATE ON SCHEMA public TO ems_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO ems_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO ems_service;

# Exit
\q
```

**Why**: Creates a dedicated service account with minimum required permissions (principle of least privilege).

**Security Note**: Never use the `postgres` superuser for application connections. Always use dedicated service accounts.

**Remember This Password**: You'll add it to the config file in Step 10.

---

### Step 8: Deploy Base Database Schema

```powershell
# Deploy the main schema
# This creates users, scan_results, diagnostic_details tables
psql -U postgres -d ems_production -f Database\schema.sql

# Expected output: Multiple CREATE TABLE, CREATE INDEX messages
# Ending with: CREATE INDEX, CREATE FUNCTION, etc.

# Verify tables were created:
psql -U postgres -d ems_production -c "\dt"

# You should see: users, scan_results, diagnostic_details, activity_log, auth_log
```

**Why**: Sets up core tables for authentication, scan results, and logging.

**What This Creates**:
- `users` - User authentication and authorization
- `scan_results` - Scan history and health scores
- `diagnostic_details` - Legacy diagnostic data (JSONB)
- `activity_log` - User activity tracking
- `auth_log` - Authentication attempts and failures

---

### Step 9: Deploy Multi-Auth Schema

```powershell
# Add multi-provider authentication columns and functions
psql -U postgres -d ems_production -f Database\migration_multi_auth.sql

# Expected output: ALTER TABLE, CREATE INDEX, CREATE FUNCTION messages

# Verify new columns exist:
psql -U postgres -d ems_production -c "\d users"

# You should now see additional columns:
# - auth_provider
# - external_id
# - password_hash
# - failed_login_attempts
# - account_locked_until
# etc.
```

**Why**: Extends the users table to support multiple authentication providers (Standalone, AD, LDAP, ADFS).

**What This Adds**:
- Authentication provider tracking
- Account lockout mechanism
- Password change enforcement
- External ID mapping for federated auth

---

### Step 10: Deploy Granular Metrics Schema (Part 1)

```powershell
# Deploy first 33 metric tables (System Health, Security, Network)
psql -U postgres -d ems_production -f Database\schema_granular_metrics_part1.sql

# This will take 30-60 seconds
# Expected output: Many CREATE TABLE messages

# Count metric tables created so far:
psql -U postgres -d ems_production -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name LIKE 'metric_%';"

# Expected: 33
```

**Why**: Creates highly normalized metric tables for better query performance and data integrity.

**What This Creates**:
- **System Health** (10 tables): CPU, Memory, Disk, Temperature, Power, BIOS, Motherboard, Network, Uptime
- **Security** (15 tables): Updates, Antivirus, Firewall, BitLocker, TPM, Secure Boot, Users, Logins, Shares, Ports, Certificates
- **Network** (8 tables): Connections, Stats, DNS, Routing, Speed, WiFi, VPN, Proxy

---

### Step 11: Deploy Granular Metrics Schema (Part 2)

```powershell
# Deploy remaining 30 metric tables (Software, User Experience, Events, Performance)
psql -U postgres -d ems_production -f Database\schema_granular_metrics_part2.sql

# This will take 30-60 seconds
# Expected output: CREATE TABLE, CREATE INDEX, CREATE TRIGGER, CREATE MATERIALIZED VIEW

# Verify total metric tables:
psql -U postgres -d ems_production -c "SELECT COUNT(*) FROM information_schema.tables WHERE table_name LIKE 'metric_%';"

# Expected: 63
```

**Why**: Completes the granular metrics schema with software, user experience, and event tracking.

**What This Creates**:
- **Software** (12 tables): Installed apps, Services, Startup, Tasks, Extensions, Office, GPO, Drivers, Features
- **User Experience** (10 tables): Login time, Crashes, Browser, Printing, Drives, Printers, Display, Sound, USB, Bluetooth
- **Event Logs** (5 tables - partitioned): System, Application, Security events, Error/Warning summaries
- **Performance** (3 tables): Baselines, Health history, Compliance scores

**Plus**:
- Triggers to auto-update `computers.last_seen`
- Materialized views for dashboard performance

---

### Step 12: Deploy Application Metrics

```powershell
# Deploy Zscaler, Seclore, and OneDrive monitoring tables
psql -U postgres -d ems_production -f Database\schema_application_metrics.sql

# Expected output: CREATE TABLE for metric_app_zscaler, metric_app_seclore, metric_app_onedrive

# Verify all tables:
psql -U postgres -d ems_production -c "\dt" | wc -l

# Expected: 131+ tables
```

**Why**: Adds application-specific monitoring for key enterprise applications.

**What This Creates**:
- `metric_app_zscaler` - Zscaler security client status
- `metric_app_seclore` - Seclore DRM and Office plugins
- `metric_app_onedrive` - OneDrive sync status and errors

---

### Step 13: Grant Permissions to Service Account

```powershell
# Grant all permissions on new tables to ems_service user
psql -U postgres -d ems_production

# Run these commands in the PostgreSQL prompt:
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO ems_service;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO ems_service;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO ems_service;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO ems_service;

# Verify permissions:
\dp computers

# You should see ems_service with permissions

# Exit:
\q
```

**Why**: Ensures the application service account can read/write all tables.

**Security**: The service account has full access to the `ems_production` database but cannot access other databases or create new databases.

---

## ⚙️ Configuration Setup

### Step 14: Configure Database Connection

```powershell
# Open the configuration file in your editor
notepad Config\EMSConfig.json

# Or use VS Code if installed:
code Config\EMSConfig.json
```

**Update the Database section**:

```json
{
  "Database": {
    "Server": "localhost",
    "Port": 5432,
    "Database": "ems_production",
    "Username": "ems_service",
    "Password": "YourSecurePassword123!",  // ← Replace with password from Step 7
    "ConnectionTimeout": 30,
    "CommandTimeout": 300,
    "EnableSSL": false  // Set to true in production with proper SSL setup
  }
}
```

**Why**: Configures the connection string for database access.

**Important**:
- Replace `YourSecurePassword123!` with the actual password you set in Step 7
- In production, enable SSL and use encrypted connections
- Never commit this file with passwords to version control

---

### Step 15: Configure Authentication Providers

```json
// Still in Config\EMSConfig.json
{
  "Authentication": {
    "Providers": [
      {
        "Name": "Standalone",
        "Enabled": true,       // ← Local database users
        "Priority": 1,         // ← Try this first
        "AllowRegistration": false
      },
      {
        "Name": "ActiveDirectory",
        "Enabled": true,       // ← Set to false if not using AD
        "Domain": "YOURDOMAIN",  // ← Replace with your AD domain
        "Priority": 2,
        "RequireGroup": "EMS_Admins"  // ← AD group for authorization
      },
      {
        "Name": "LDAP",
        "Enabled": false,      // ← Set to true if using LDAP
        "Server": "ldap://ldap.company.com:389",
        "BaseDN": "dc=company,dc=com",
        "BindDN": "cn=ems_svc,ou=services,dc=company,dc=com",
        "BindPassword": "LDAP_SERVICE_PASSWORD",
        "Priority": 3
      }
    ],
    "FallbackChain": true,   // ← Try providers in order until one succeeds
    "SessionTimeoutMinutes": 480,  // 8 hours
    "MaxFailedAttempts": 5,
    "LockoutDurationMinutes": 30
  }
}
```

**Why**: Configures which authentication methods are available.

**Configuration Guide**:
- **Standalone**: Always leave enabled for initial testing
- **ActiveDirectory**: Enable if in domain environment, set correct domain name
- **LDAP**: Enable for non-AD LDAP servers (OpenLDAP, etc.)
- **FallbackChain**: If true, tries each provider in priority order
- **Requirements**: Adjust group names, DNs, and passwords as needed

**Best Practice**: Start with Standalone only, then add AD/LDAP after basic system is working.

---

### Step 16: Create Initial Standalone User

```powershell
# Import the standalone auth module
Import-Module .\Modules\Authentication\StandaloneAuth.psm1

# Create a secure password object
$password = Read-Host -AsSecureString -Prompt "Enter password for admin user"

# Create the admin user
New-StandaloneUser -Username "admin" -SecurePassword $password -DisplayName "System Administrator" -Email "admin@company.com" -Role "admin"

# Expected output: User ID number (e.g., 1)
```

**Why**: Creates the first user account so you can log in.

**User Roles**:
- `admin` - Full access (create users, configure system, view all data)
- `operator` - Run scans, view results, manage computers
- `viewer` - Read-only access to dashboard and results

**Important**: Remember this password - you'll use it to log in.

---

## 🔌 API Backend Setup

### Step 17: Test Database Connection

```powershell
# Import the database module
Import-Module .\Modules\Database\PSPGSql.psm1

# Load config
$config = Get-Content .\Config\EMSConfig.json -Raw | ConvertFrom-Json

# Initialize connection
Initialize-PostgreSQLConnection -Config $config

# Test query
$result = Invoke-PGQuery -Query "SELECT COUNT(*) as table_count FROM information_schema.tables WHERE table_schema='public'"

# Display result
$result.table_count

# Expected: 131 or more
```

**Why**: Verifies the database connection works before starting the API.

**Troubleshooting**:
- If connection fails, check:
  - PostgreSQL service is running: `Get-Service -Name postgresql*`
  - Firewall allows port 5432
  - Username/password in config is correct
  - Database name is correct

---

### Step 18: Verify PowerShell Modules

```powershell
# Check all required modules can load
Import-Module .\Modules\Logging.psm1 -Force
Import-Module .\Modules\Database\PSPGSql.psm1 -Force
Import-Module .\Modules\Database\MetricsData.psm1 -Force
Import-Module .\Modules\Authentication\AuthProviders.psm1 -Force
Import-Module .\Modules\Authentication\StandaloneAuth.psm1 -Force
Import-Module .\Modules\Diagnostics\SystemHealth.psm1 -Force
Import-Module .\Modules\Diagnostics\SecurityPosture.psm1 -Force
Import-Module .\Modules\Diagnostics\SoftwareCompliance.psm1 -Force
Import-Module .\Modules\InputBroker.psm1 -Force
Import-Module .\Modules\DataFetcher.psm1 -Force

# Expected: No errors

# List loaded modules
Get-Module | Where-Object { $_.Path -like "*PowerShellEndPointv2*" }

# You should see all the modules listed above
```

**Why**: Ensures all PowerShell modules are syntactically correct and can be loaded.

**If Errors Occur**:
- Check for syntax errors in the module files
- Ensure all dependencies are available
- Check PowerShell execution policy: `Get-ExecutionPolicy`
- If restricted: `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`

---

### Step 19: Start API Server (First Time)

```powershell
# Start the API in a new PowerShell window
# This keeps it running while you continue setup
Start-Process powershell -ArgumentList "-NoExit", "-File", ".\API\Start-EMSAPI.ps1"

# Wait for API to start (about 10-15 seconds)
# You should see output:
# "Starting Universal Dashboard API Server..."
# "API Server started successfully on http://localhost:5000"
# List of endpoints

# Test API is responding:
Invoke-RestMethod -Uri "http://localhost:5000/api/dashboard/stats" -Method GET

# Expected: Should fail with 401 Unauthorized (correct - not logged in yet)
```

**Why**: Starts the PowerShell Universal Dashboard API server that handles all backend operations.

**What Happens**:
1. Loads all modules
2. Initializes database connection
3. Creates API endpoints
4. Starts HTTP listener on port 5000
5. Waits for requests

**Common Issues**:
- **Port 5000 already in use**: Another service using that port. Change in Start-EMSAPI.ps1 or stop the other service
- **Module import errors**: Check Step 18 troubleshooting
- **Database connection error**: Check Step 17

---

## 🎨 Web UI Setup

### Step 20: Install Web UI Dependencies

```powershell
# Navigate to WebUI directory
cd WebUI

# Install all npm packages
# This will take 2-3 minutes
npm install

# Expected output: Lots of package installation messages
# Ending with: "added XXX packages in YYs"

# You should see node_modules folder created
ls

# Verify React and dependencies installed:
npm list react react-dom react-router-dom axios

# Expected: Shows installed versions
```

**Why**: Downloads all JavaScript libraries needed for the React web application.

**What This Installs**:
- React 18.x - UI framework
- React Router - Page routing
- Axios - HTTP requests
- Other dependencies for build tooling

**If Errors**: Delete `node_modules` folder and `package-lock.json`, then run `npm install` again.

---

### Step 21: Configure API Endpoint URL

```powershell
# Still in WebUI directory
# Check if .env file exists:
Test-Path .env

# If false, create it:
New-Item -Path .env -ItemType File

# Edit the file:
notepad .env

# Add this line:
REACT_APP_API_URL=http://localhost:5000
```

**Why**: Tells the React app where to find the API server.

**Options**:
- **Development**: `http://localhost:5000` (what we're using)
- **Production same server**: `http://your-server-ip:5000`
- **Production different server**: `http://api.company.com:5000`

**Important**: If you changed the API port in Step 19, update it here too.

---

### Step 22: Start Web UI Development Server

```powershell
# Still in WebUI directory
# Start the React development server
npm start

# This will:
# 1. Compile the React app (takes 10-30 seconds first time)
# 2. Open your browser to http://localhost:3000
# 3. Show compilation success message

# Expected output:
# "Compiled successfully!"
# "webpack compiled with 0 warnings"
# "You can now view ems-webui in the browser"
# "Local: http://localhost:3000"
```

**Why**: Starts the React development server with hot-reload for the web interface.

**What Happens**:
- Compiles JSX to JavaScript
- Bundles all components
- Starts dev server on port 3000
- Opens browser automatically
- Watches for file changes (auto-reloads on edits)

**Your browser should open to the login page!**

---

## 🧪 Testing & Verification

### Step 23: Test Login

**In the browser at http://localhost:3000**:

1. You should see the login page
2. **Authentication Method**: Select "Local Account" (Standalone)
3. **Username**: Enter `admin`
4. **Password**: Enter the password you set in Step 16
5. Click **Sign In**

**Expected**: Redirects to dashboard showing:
- Navigation sidebar
- Statistics cards (will show 0s initially - no scans yet)
- Empty charts

**If Login Fails**:
- Check browser console (F12) for errors
- Verify API is running (check PowerShell window from Step 19)
- Check username/password is correct
- Verify user was created successfully in Step 16

---

### Step 24: Test Computer Registration

**In the web UI**:

1. Click **Computers** in sidebar
2. Click **Register New Computer** button
3. Fill in form:
   - Computer Name: `TEST-PC-001`
   - IP Address: `192.168.1.100`
   - Operating System: `Windows 11`
   - Domain: Leave blank
   - Computer Type: `Desktop`
4. Click **Register**

**Expected**: 
- Success message
- Computer appears in table
- Status shows green "Active" dot

**Why**: Tests basic API functionality and database write operations.

---

### Step 25: View Metrics Explorer

**In the web UI**:

1. Click **Metrics Explorer** in sidebar
2. You should see 7 categories with 63 total metrics
3. Click on **CPU Usage**
4. You should see:
   - Filters panel
   - Export CSV button
   - Empty table (no data yet)
   - "No data found" message

**Expected**: Page loads successfully, UI works, just no data yet.

**Why**: Verifies all 63 metric pages are accessible and functional.

---

### Step 26: Run Automated Tests

```powershell
# Go back to root directory
cd C:\Users\ZORO\PowerShellEndPointv2

# Run the comprehensive test suite
.\Tests\Test-EMSEnhancements.ps1

# This will:
# 1. Test database schema (verify all tables exist)
# 2. Test authentication (create/auth test user)
# 3. Test computer registration
# 4. Test metrics storage
# 5. Test metrics retrieval
# 6. Test data integrity

# Expected output:
# Multiple "[TEST] Description... ✓ PASS" messages
# Ending with:
# "TEST SUMMARY"
# "Total Tests: 25"
# "Passed: 25"
# "Failed: 0"
# "✓ All tests passed!"
```

**Why**: Automated verification that all core functionality works.

**If Tests Fail**:
- Note which test failed
- Check the error message
- Verify that step was completed correctly
- Check database connection
- Check module imports

---

### Step 27: Test Scan Functionality (Optional but Recommended)

```powershell
# Create a test scan
# Import required modules
Import-Module .\Modules\InputBroker.psm1
Import-Module .\Modules\DataFetcher.psm1

# Load config
$config = Get-Content .\Config\EMSConfig.json -Raw | ConvertFrom-Json

# Scan localhost
$targets = Invoke-InputRouter -Input "localhost" -Config $config
$results = Invoke-DataFetch -Targets $targets -Config $config

# Display results
$results | Format-List

# You should see:
# - Hostname: Your computer name
# - IP: 127.0.0.1
# - SystemHealth: Array of checks (CPU, Memory, Disk, etc.)
# - Security: Array of security checks
# - Software: Array of software checks
# - HealthScore: Number (0-100)
# - Status: Complete
```

**Why**: Tests the complete scan pipeline including diagnostics and metric storage.

**What This Tests**:
- Input parsing
- Topology detection
- WMI/CIM queries
- Diagnostic modules
- Metric data structuring
- Database insertion

---

### Step 28: Verify Metrics Were Stored

```powershell
# Check that scan data was saved to metric tables
psql -U postgres -d ems_production

# Run these queries:

-- Check CPU metrics
SELECT computer_name, timestamp, usage_percent, core_count 
FROM metric_cpu_usage 
ORDER BY timestamp DESC 
LIMIT 5;

-- Check Memory metrics
SELECT computer_name, timestamp, total_gb, used_gb, usage_percent 
FROM metric_memory 
ORDER BY timestamp DESC 
LIMIT 5;

-- Check Windows Updates
SELECT computer_name, timestamp, pending_updates, auto_update_enabled 
FROM metric_windows_updates 
ORDER BY timestamp DESC 
LIMIT 5;

-- Count total metrics stored
SELECT 
  'CPU' as metric, COUNT(*) as count FROM metric_cpu_usage
UNION 
SELECT 'Memory', COUNT(*) FROM metric_memory
UNION
SELECT 'Disk', COUNT(*) FROM metric_disk_space;

-- Exit
\q
```

**Expected**: You should see rows with data for your computer from the scan in Step 27.

**Why**: Verifies the complete data flow: scan → diagnostics → metrics → database.

---

## 🎉 Setup Complete!

### Step 29: Verify Complete Installation

**Checklist**:

- [x] PostgreSQL installed and running
- [x] Database `ems_production` created with 131+ tables
- [x] Service account `ems_service` created with permissions
- [x] Config file updated with database credentials
- [x] Standalone admin user created
- [x] API server running on port 5000
- [x] Web UI running on port 3000
- [x] Can log in successfully
- [x] Can navigate all pages
- [x] Automated tests passing
- [x] Scan functionality working
- [x] Metrics being stored

**Your System Status**: ✅ **FULLY OPERATIONAL**

---

### Step 30: Next Steps

**Production Deployment**:
1. Build production React app: `cd WebUI && npm run build`
2. Configure Windows Service for API
3. Set up IIS or Apache for React build
4. Enable SSL/TLS
5. Configure firewall rules
6. Set up scheduled scans
7. Configure backup jobs

**See**: `DEPLOYMENT_CHECKLIST.md` for production deployment guide

**Monitoring**:
- Add computers to monitor
- Configure scan schedules
- Set up alerting
- Review dashboards
- Export reports

**Customization**:
- Add custom metrics
- Configure diagnostic thresholds
- Customize dashboard
- Add additional authentication providers
- Configure remediation actions

---

## 🔧 Troubleshooting Common Issues

### Issue: "Cannot connect to database"

**Check**:
```powershell
# Is PostgreSQL running?
Get-Service -Name postgresql*

# If not, start it:
Start-Service postgresql-x64-14  # Adjust version number

# Can you connect manually?
psql -U postgres -d ems_production

# Is password correct in config?
cat Config\EMSConfig.json | Select-String "Password"
```

---

### Issue: "Module not found" errors

**Solution**:
```powershell
# Check execution policy
Get-ExecutionPolicy

# If Restricted, set to RemoteSigned:
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# Verify module paths are correct:
ls Modules\*.psm1 -Recurse
```

---

### Issue: "Port already in use"

**Solution**:
```powershell
# Find what's using the port:
netstat -ano | findstr :5000

# Kill the process (replace PID):
Stop-Process -Id <PID> -Force

# Or change API port in Start-EMSAPI.ps1
```

---

### Issue: "npm install fails"

**Solution**:
```powershell
cd WebUI

# Clear npm cache
npm cache clean --force

# Delete node_modules and lock file
Remove-Item node_modules -Recurse -Force
Remove-Item package-lock.json -Force

# Retry install
npm install
```

---

### Issue: "Blank page after login"

**Check**:
```powershell
# Browser console (F12) - look for errors
# Common causes:
# 1. API not running - check PowerShell window
# 2. API URL wrong - check WebUI\.env file
# 3. CORS issue - check API CORS settings
# 4. Build issue - try npm start again
```

---

## 📚 Additional Resources

**Documentation**:
- `README.md` - Project overview
- `INSTALLATION.md` - Detailed installation (this guide)
- `QUICK_START.md` - Quick setup for experienced users
- `Authentication_Guide.md` - Auth provider configuration
- `Metric_Schema_Reference.md` - All 63 metric tables
- `DEPLOYMENT_CHECKLIST.md` - Production deployment

**Support**:
- Check logs: `Logs\*.log`
- Run tests: `.\Tests\Test-EMSEnhancements.ps1`
- Database queries: `psql -U postgres -d ems_production`

---

**Setup Complete!** 🎊

Your Enterprise Monitoring System v2.1 is now fully operational.

**Time to completion**: ~45 minutes  
**System status**: ✅ Production Ready  
**Next**: Start monitoring your endpoints!
