# Complete DataFetcher.psm1 Update Guide

## Changes Made

### Diagnostic Modules - COMPLETE ✅
1. **SystemHealth.psm1** - Restructured output format
2. **SecurityPosture.psm1** - Added Zscaler monitoring
3. **SoftwareCompliance.psm1** - Added Seclore and OneDrive monitoring

### New Metric Tables Required

Add these tables to your database schema:

```sql
-- Zscaler monitoring
CREATE TABLE metric_app_zscaler (
    computer_name VARCHAR(255) REFERENCES computers(computer_name),
    timestamp TIMESTAMP DEFAULT NOW(),
    installed BOOLEAN,
    version VARCHAR(100),
    service_running BOOLEAN,
    app_running BOOLEAN,
    PRIMARY KEY (computer_name, timestamp)
);

CREATE INDEX idx_zscaler_computer_time ON metric_app_zscaler(computer_name, timestamp DESC);

-- Seclore DRM monitoring
CREATE TABLE metric_app_seclore (
    computer_name VARCHAR(255) REFERENCES computers(computer_name),
    timestamp TIMESTAMP DEFAULT NOW(),
    installed BOOLEAN,
    version VARCHAR(100),
    service_running BOOLEAN,
    office_plugins_installed JSONB,
    install_location VARCHAR(500),
    PRIMARY KEY (computer_name, timestamp)
);

CREATE INDEX idx_seclore_computer_time ON metric_app_seclore(computer_name, timestamp DESC);

-- OneDrive sync monitoring
CREATE TABLE metric_app_onedrive (
    computer_name VARCHAR(255) REFERENCES computers(computer_name),
    timestamp TIMESTAMP DEFAULT NOW(),
    installed BOOLEAN,
    version VARCHAR(100),
    running BOOLEAN,
    sync_status VARCHAR(50),
    sync_errors INTEGER DEFAULT 0,
    storage_used_gb DECIMAL(10,2),
    business_configured BOOLEAN,
    PRIMARY KEY (computer_name, timestamp)
);

CREATE INDEX idx_onedrive_computer_time ON metric_app_onedrive(computer_name, timestamp DESC);
```

### DataFetcher.psm1 - Manual Update Required

**Current Structure**: The DataFetcher already has `Save-DiagnosticsToMetrics` function from our previous update.

**Required Changes**:

1. **Update line ~79** in Start-HOQueue scriptblock:
```powershell
# Add after line importing SecurityPosture
Import-Module "$modulePath\\Diagnostics\\SoftwareCompliance.psm1" -Force
$results.Software = Invoke-SoftwareComplianceChecks -ComputerName $hostname
```

2. **Update line ~196** in Start-MPLSQueue scriptblock:
```powershell
# Add after SecurityChecks
Import-Module "$modulePath\\Diagnostics\\SoftwareCompliance.psm1" -Force
$results.Software = Invoke-SoftwareComplianceChecks -ComputerName $hostname -CimSession $cimSession
```

3. **Result hashtable**: Add `Software = @()` to both script blocks

4. **Health score calculation**: Update to include Software results:
```powershell
$criticalCount = ($results.SystemHealth + $results.Security + $results.Software | Where-Object { $_.Status -eq 'Critical' }).Count
```

### Verification Steps

1. **Deploy new database tables**:
```powershell
psql -U postgres -d ems_production -f Database\schema_application_metrics.sql
```

2. **Test updated modules**:
```powershell
Import-Module .\Modules\Diagnostics\SoftwareCompliance.psm1
$result = Get-SecloreStatusMetricData
$result.Details  # Should show Seclore installation status
```

3. **Test full scan**:
```powershell
.\API\Start-EMSAPI.ps1
# Then POST /api/scan/single with a test computer
```

4. **Verify metrics saved**:
```sql
SELECT * FROM metric_app_seclore WHERE computer_name = 'TEST-PC' ORDER BY timestamp DESC LIMIT 1;
SELECT * FROM metric_app_onedrive WHERE computer_name = 'TEST-PC' ORDER BY timestamp DESC LIMIT 1;
SELECT * FROM metric_app_zscaler WHERE computer_name = 'TEST-PC' ORDER BY timestamp DESC LIMIT 1;
```

## Summary

✅ SystemHealth.psm1 - Complete restructure  
✅ SecurityPosture.psm1 - Added Zscaler  
✅ SoftwareCompliance.psm1 - Added Seclore, OneDrive  
⚠️ DataFetcher.psm1 - Minor manual edits needed (3 locations)  
⚠️ Database - Need to add 3 new tables

**Status**: 95% Complete - Just need DB tables and minor DataFetcher tweaks
