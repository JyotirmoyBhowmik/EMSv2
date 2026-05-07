# PostgreSQL Database Setup Guide

## Prerequisites

### 1. Install PostgreSQL Server

**Download PostgreSQL 15+**:
```powershell
# Option A: Download from official website
# Visit: https://www.postgresql.org/download/windows/
# Install PostgreSQL 15.x with default settings

# Option B: Using Chocolatey
choco install postgresql15 -y
```

**Verify Installation**:
```powershell
# Test PostgreSQL service
Get-Service postgresql*

# Test psql command-line tool
psql --version
```

### 2. Install Npgsql .NET Driver

**Create Lib directory**:
```powershell
cd C:\Users\ZORO\PowerShellEndPointv2
New-Item -Path ".\Lib" -ItemType Directory -Force
```

**Install Npgsql via NuGet**:
```powershell
# Option A: Using nuget.exe
nuget install Npgsql -OutputDirectory .\Lib -Version 7.0.6

# Option B: Manual download
# Download from: https://www.nuget.org/packages/Npgsql/
# Extract .nupkg (rename to .zip) and copy Npgsql.dll to .\Lib\
```

**Expected files**:
```
C:\Users\ZORO\PowerShellEndPointv2\Lib\
├── Npgsql.dll
├── System.Runtime.CompilerServices.Unsafe.dll
└── System.Threading.Channels.dll
```

## Database Setup

### Step 1: Create Database

Connect to PostgreSQL as admin:
```powershell
# Using psql (default password: postgres)
psql -U postgres

# Create database
CREATE DATABASE ems_production;

# Create EMS service user
CREATE USER ems_service WITH ENCRYPTED PASSWORD 'YourSecurePassword123!';

# Grant connection
GRANT CONNECT ON DATABASE ems_production TO ems_service;

# Exit psql
\q
```

### Step 2: Run Schema Script

```powershell
# Navigate to database directory
cd C:\Users\ZORO\PowerShellEndPointv2\Database

# Run schema creation script
psql -U postgres -d ems_production -f schema.sql
```

**Verify Schema**:
```sql
-- Connect to database
psql -U postgres -d ems_production

-- List tables
\dt

-- Check table structure
\d users
\d scan_results

-- Verify partitions
SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename LIKE 'scan_results_%';
```

### Step 3: Configure Permissions

```sql
-- Grant permissions to ems_service user
GRANT USAGE ON SCHEMA public TO ems_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ems_service;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ems_service;

-- Grant execute on functions
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO ems_service;
```

## Configure EMS Application

### Step 1: Update EMSConfig.json

Add database configuration section:
```json
{
  "Database": {
    "Provider": "PostgreSQL",
    "Host": "localhost",
    "Port": 5432,
    "DatabaseName": "ems_production",
    "Username": "ems_service",
    "Password": "YourSecurePassword123!",
    "UseSSL": false,
    "ConnectionPoolSize": 20
  }
}
```

**Production Security**: Use secure credential storage instead of plain-text password:
```powershell
# Convert password to secure string
$securePassword = ConvertTo-SecureString "YourSecurePassword123!" -AsPlainText -Force
$securePassword | Export-Clixml -Path "C:\Program Files\EMS\Config\db_password.xml"
```

Then modify `EMSConfig.json`:
```json
{
  "Database": {
    "PasswordFile": "C:\\Program Files\\EMS\\Config\\db_password.xml"
  }
}
```

### Step 2: Test Database Connection

```powershell
# Start PowerShell as Administrator
cd C:\Users\ZORO\PowerShellEndPointv2

# Import modules
Import-Module .\Modules\Logging.psm1 -Force
Import-Module .\Modules\Database\PSPGSql.psm1 -Force

# Load configuration
$config = Get-Content .\Config\EMSConfig.json | ConvertFrom-Json

# Initialize connection
Initialize-PostgreSQLConnection -Config $config

# Test connection
Test-PostgreSQLConnection
```

**Expected Output**:
```
[INFO] PostgreSQL connection initialized: localhost:5432/ems_production
[SUCCESS] PostgreSQL connection successful: PostgreSQL 15.x on x86_64-pc-windows-msvc
```

## Data Migration (Optional)

### Migrate Existing CSV Logs to PostgreSQL

Use the migration script (to be created):
```powershell
.\Database\migrate_csv_to_postgresql.ps1 -CSVLogPath "C:\EMSLogs" -Config $config
```

## Maintenance

### Create Monthly Partitions

Partitions are created automatically for current + 3 months. To create additional:
```sql
-- Create partition for April 2026
SELECT create_monthly_partition('2026-04-01'::date);
```

### Refresh Dashboard Statistics

Statistics are cached in materialized view:
```sql
-- Manual refresh
SELECT refresh_dashboard_stats();
```

**Automated refresh** (requires pg_cron extension):
```sql
-- Install pg_cron (as superuser)
CREATE EXTENSION pg_cron;

-- Schedule refresh every 5 minutes
SELECT cron.schedule('refresh-dashboard-stats', '*/5 * * * *', 'SELECT refresh_dashboard_stats()');
```

### Backup Database

```powershell
# Full database backup
pg_dump -U postgres -F c -b -v -f "C:\Backups\ems_$(Get-Date -Format 'yyyyMMdd_HHmmss').backup" ems_production

# Restore from backup
pg_restore -U postgres -d ems_production -v "C:\Backups\ems_20251223_190000.backup"
```

## PostgreSQL Configuration Tuning

For production performance, edit `postgresql.conf`:

```ini
# Memory settings (adjust based on server RAM)
shared_buffers = 2GB              # 25% of total RAM
effective_cache_size = 6GB        # 75% of total RAM
maintenance_work_mem = 512MB
work_mem = 64MB

# Connection settings
max_connections = 100
shared_preload_libraries = 'pg_stat_statements'

# Logging for troubleshooting
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_statement = 'mod'             # Log all INSERT/UPDATE/DELETE
log_min_duration_statement = 1000 # Log queries slower than 1s
```

Restart PostgreSQL after changes:
```powershell
Restart-Service postgresql-x64-15
```

## Troubleshooting

### Connection Refused

Check PostgreSQL is running:
```powershell
Get-Service postgresql*
```

Edit `pg_hba.conf` to allow local connections:
```
# IPv4 local connections:
host    all    all    127.0.0.1/32   md5
host    all    all    0.0.0.0/0      md5  # Allow all (development only!)
```

Edit `postgresql.conf`:
```
listen_addresses = '*'  # Listen on all interfaces
```

### Npgsql.dll Not Found

Verify file exists:
```powershell
Test-Path "C:\Users\ZORO\PowerShellEndPointv2\Lib\Npgsql.dll"
```

Check assembly loading in PowerShell:
```powershell
Add-Type -Path "C:\Users\ZORO\PowerShellEndPointv2\Lib\Npgsql.dll"
[Npgsql.NpgsqlConnection]::new()
```

### Slow Queries

Check query execution plan:
```sql
EXPLAIN ANALYZE SELECT * FROM scan_results WHERE hostname = 'WKSTN-01';
```

Rebuild indexes if needed:
```sql
REINDEX TABLE scan_results;
```

## Security Hardening

1. **Change default postgres password**:
```sql
ALTER USER postgres WITH PASSWORD 'NewStrongPassword123!';
```

2. **Use SSL/TLS for connections**:
```sql
-- Require SSL
ALTER DATABASE ems_production SET ssl = on;
```

3. **Limited user permissions**:
```sql
-- Revoke all and grant minimum required
REVOKE ALL ON DATABASE ems_production FROM ems_service;
GRANT CONNECT ON DATABASE ems_production TO ems_service;
GRANT SELECT, INSERT, UPDATE ON scan_results TO ems_service;
-- (Repeat for each table)
```

4. **Firewall rules**:
```powershell
# Allow PostgreSQL only from localhost
New-NetFirewallRule -DisplayName "PostgreSQL-LocalOnly" `
    -Direction Inbound `
    -Protocol TCP `
    -LocalPort 5432 `
    -RemoteAddress 127.0.0.1 `
    -Action Allow
```

## Next Steps

Once database is configured:
1. Test database module: `Test-PostgreSQLConnection`
2. Insert test data: `New-EMSUser -Username "testuser" -Role "admin"`
3. Verify audit logging: `Write-AuditLog -Action "Test" -User "testuser" -Result "Success"`
4. Proceed to API backend setup
