<#
.SYNOPSIS
    Migrates existing CSV logs to PostgreSQL database

.DESCRIPTION
    Imports CSV-based audit logs and scan results into PostgreSQL database
    Supports incremental migration and data validation
    
.PARAMETER CSVLogPath
    Path to directory containing CSV log files
    
.PARAMETER SkipExisting
    Skip records that already exist in database
    
.EXAMPLE
    .\migrate_csv_to_postgresql.ps1 -CSVLogPath "C:\EMSLogs"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CSVLogPath,
    
    [switch]$SkipExisting
)

# Import required modules
$ModulePath = Join-Path $PSScriptRoot "..\Modules"
Import-Module "$ModulePath\Logging.psm1" -Force
Import-Module "$ModulePath\Database\PSPGSql.psm1" -Force

# Load configuration
$configPath = Join-Path $PSScriptRoot "..\Config\EMSConfig.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " EMS CSV to PostgreSQL Migration" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Initialize database connection
Write-Host "[1/4] Initializing database connection..." -ForegroundColor Yellow
if (-not (Initialize-PostgreSQLConnection -Config $config)) {
    Write-Host "Failed to initialize database connection!" -ForegroundColor Red
    exit 1
}

if (-not (Test-PostgreSQLConnection)) {
    Write-Host "Database connection test failed!" -ForegroundColor Red
    exit 1
}

Write-Host "✓ Database connection successful`n" -ForegroundColor Green

# Migrate authentication logs
Write-Host "[2/4] Migrating authentication logs..." -ForegroundColor Yellow
$authLogs = Get-ChildItem -Path $CSVLogPath -Filter "AuthAudit_*.csv" -ErrorAction SilentlyContinue

if ($authLogs) {
    $totalAuthRecords = 0
    foreach ($logFile in $authLogs) {
        Write-Host "  Processing: $($logFile.Name)" -ForegroundColor Gray
        
        try {
            $records = Import-Csv -Path $logFile.FullName
            
            foreach ($record in $records) {
                # Check if user exists, create if not
                $user = Get-EMSUser -Username $record.Username
                if (-not $user -and -not $SkipExisting) {
                    try {
                        New-EMSUser -Username $record.Username -DisplayName $record.Username -Role "operator"
                        $user = Get-EMSUser -Username $record.Username
                    }
                    catch {
                        Write-Warning "Could not create user $($record.Username): $_"
                        continue
                    }
                }
                
                if ($user) {
                    # Insert audit log
                    $query = @"
INSERT INTO audit_logs (timestamp, user_id, username, action, result, risk_level)
VALUES (@timestamp, @userid, @username, @action, @result, @risk)
ON CONFLICT DO NOTHING
"@
                    
                    $params = @{
                        timestamp = [datetime]$record.Timestamp
                        userid    = $user.user_id
                        username  = $record.Username
                        action    = $record.Action
                        result    = $record.Result
                        risk      = if ($record.Result -eq 'Failed') { 'Medium' } else { 'Low' }
                    }
                    
                    Invoke-PGQuery -Query $query -Parameters $params -NonQuery | Out-Null
                    $totalAuthRecords++
                }
            }
        }
        catch {
            Write-Warning "Error processing $($logFile.Name): $_"
        }
    }
    
    Write-Host "✓ Migrated $totalAuthRecords authentication records`n" -ForegroundColor Green
}
else {
    Write-Host "  No authentication logs found`n" -ForegroundColor Gray
}

# Migrate activity logs
Write-Host "[3/4] Migrating activity/scan logs..." -ForegroundColor Yellow
$activityLogs = Get-ChildItem -Path $CSVLogPath -Filter "EMS_*.csv" -ErrorAction SilentlyContinue

if ($activityLogs) {
    $totalScanRecords = 0  
    foreach ($logFile in $activityLogs) {
        Write-Host "  Processing: $($logFile.Name)" -ForegroundColor Gray
        
        try {
            $records = Import-Csv -Path $logFile.FullName
            
            foreach ($record in $records) {
                # Skip if not a scan result
                if ($record.Hostname -and $record.HealthScore) {
                    # Create mock scan data object
                    $scanData = [PSCustomObject]@{
                        Hostname             = $record.Hostname
                        IPAddress            = $record.IPAddress
                        UserID               = $record.UserID
                        ScanTimestamp        = if ($record.Timestamp) { [datetime]$record.Timestamp } else { Get-Date }
                        HealthScore          = [int]$record.HealthScore
                        Topology             = $record.Topology
                        ExecutionTimeSeconds = if ($record.ExecutionTime) { [decimal]$record.ExecutionTime } else { 0 }
                        Diagnostics          = @()  # Detailed diagnostics not available in CSV
                    }
                    
                    # Get initiating user
                    $initiatedBy = 1  # Default to admin user
                    if ($record.InitiatedBy) {
                        $user = Get-EMSUser -Username $record.InitiatedBy
                        if ($user) {
                            $initiatedBy = $user.user_id
                        }
                    }
                    
                    try {
                        Save-ScanResult -ScanData $scanData -InitiatedBy $initiatedBy
                        $totalScanRecords++
                    }
                    catch {
                        if (-not $SkipExisting) {
                            Write-Warning "Could not save scan result for $($record.Hostname): $_"
                        }
                    }
                }
            }
        }
        catch {
            Write-Warning "Error processing $($logFile.Name): $_"
        }
    }
    
    Write-Host "✓ Migrated $totalScanRecords scan records`n" -ForegroundColor Green
}
else {
    Write-Host "  No activity logs found`n" -ForegroundColor Gray
}

# Migration summary
Write-Host "[4/4] Migration Summary" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Gray

$stats = Get-DashboardStats
if ($stats) {
    Write-Host "Total Scans:        $($stats.total_scans)" -ForegroundColor White
    Write-Host "Unique Endpoints:   $($stats.unique_endpoints)" -ForegroundColor White
    Write-Host "Health Distribution:" -ForegroundColor White
    Write-Host "  - Excellent (≥90): $($stats.excellent_health)" -ForegroundColor Green
    Write-Host "  - Good (70-89):    $($stats.good_health)" -ForegroundColor Cyan
    Write-Host "  - Fair (50-69):    $($stats.fair_health)" -ForegroundColor Yellow
    Write-Host "  - Poor (<50):      $($stats.poor_health)" -ForegroundColor Red
}

Write-Host "`n✓ Migration completed successfully!" -ForegroundColor Green
Write-Host "========================================`n" -ForegroundColor Cyan

# Refresh materialized view
Write-Host "Refreshing dashboard statistics view..." -ForegroundColor Gray
Invoke-PGQuery -Query "REFRESH MATERIALIZED VIEW dashboard_statistics" -NonQuery | Out-Null
Write-Host "✓ Complete`n" -ForegroundColor Green
