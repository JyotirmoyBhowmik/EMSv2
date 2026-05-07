# Complete Metrics System Integration Guide

## Overview

This guide covers the complete end-to-end integration of the granular metrics system.

## Components

### 1. Data Collection (DataFetcher.psm1)

**Flow**: Scan → Extract Diagnostics → Save to Granular Tables

**Updated Functions**:
- `Start-HOQueue()` - Now calls `Save-DiagnosticsToMetrics()`
- `Start-MPLSQueue()` - Saves batch results to metrics
- `Save-DiagnosticsToMetrics()` - NEW: Maps diagnostics to metric tables

**Supported Metrics** (currently mapped):
- CPU Usage → `metric_cpu_usage`
- Memory Usage → `metric_memory`
- Disk Space → `metric_disk_space`
- Windows Updates → `metric_windows_updates`
- Antivirus Status → `metric_antivirus`

### 2. Data Migration

**Script**: `Database/Migrate-ToGranularMetrics.ps1`

**Purpose**: Migrate existing `scan_results` + `diagnostic_details` to new tables

**Usage**:
```powershell
# Preview migration
.\Database\Migrate-ToGranularMetrics.ps1 -DryRun

# Execute migration
.\Database\Migrate-ToGranularMetrics.ps1 -Execute
```

**Process**:
1. Reads existing scan_results
2. Extracts diagnostic_details JSONB
3. Maps to appropriate metric tables
4. Registers computers in `computers` table

### 3. API Endpoints

**New Endpoints**:

```
GET /api/metrics/:metricType
  Query Parameters:
    - computerName: Filter by computer
    - startDate: Start date filter
    - endDate: End date filter
    - limit: Result limit (default: 100)

GET /api/computers/:name/all-metrics
  Returns: All metric types for one computer
```

**Add to API**:
```powershell
# In Start-EMSAPI.ps1, add:
. "$PSScriptRoot\Metrics-Endpoints.ps1"
```

### 4. UI Components

**Created**:

1. **MetricsNavigation.js** (63 metric links)
   - Organized by 7 categories
   - Icon-based navigation
   - Direct links to metric pages

2. **MetricComponents.js** (Reusable templates)
   - `MetricDetail` - Generic metric display component
   - Includes filtering (computer, date range, limit)
   - CSV export functionality
   - 10 pre-built metric components

**Add to App.js**:
```javascript
import MetricsNavigation from './components/MetricsNavigation';
import { CPUUsageMetric, MemoryMetric, /* ... */ } from './components/MetricComponents';

// In routes:
<Route path="/metrics" element={<MetricsNavigation />} />
<Route path="/metrics/cpu" element={<CPUUsageMetric />} />
<Route path="/metrics/memory" element={<MemoryMetric />} />
// ... add all 63 metric routes
```

## Creating Additional Metric Pages

To add remaining 50+ metric pages, copy this template:

```javascript
export const YourMetricName = () => (
  <MetricDetail 
    metricName="Your Metric Display Name" 
    metricType="your_metric_type"
    apiEndpoint="/api/metrics/your_metric_type"
  />
);
```

**Example** - BitLocker Status:
```javascript
export const BitLockerMetric = () => (
  <MetricDetail 
    metricName="BitLocker Encryption" 
    metricType="bitlocker"
    apiEndpoint="/api/metrics/bitlocker"
  />
);
```

Then add route in App.js:
```javascript
<Route path="/metrics/bitlocker" element={<BitLockerMetric />} />
```

## Complete Flow Example

### End-to-End Scan

1. **User initiates scan**:
   ```
   POST /api/scan/single
   Body: { target: "PC-001" }
   ```

2. **DataFetcher executes**:
   - Runs diagnostic modules
   - Collects CPU, Memory, Disk, Updates, AV data
   - Returns scan results with `diagnosticDetails`

3. **Save-DiagnosticsToMetrics called**:
   ```powershell
   Register-Computer -ComputerName "PC-001" -IPAddress "10.0.1.50"
   Save-CPUMetric -ComputerName "PC-001" -UsagePercent 45.2 ...
   Save-MemoryMetric -ComputerName "PC-001" -TotalGB 16 ...
   Save-WindowsUpdateMetric -ComputerName "PC-001" -PendingUpdates 3 ...
   ```

4. **Data stored in**:
   - `computers` (computer registration)
   - `metric_cpu_usage`
   - `metric_memory`
   - `metric_windows_updates`
   - etc.

5. **User views metrics**:
   - Navigate to `/metrics`
   - Click "CPU Usage"
   - See table with all CPU metrics for all computers
   - Filter by computer name "PC-001"
   - See only PC-001's CPU history

### Query Example

**Get CPU usage for PC-001 (last 24 hours)**:

```sql
SELECT computer_name, timestamp, usage_percent, core_count
FROM metric_cpu_usage
WHERE computer_name = 'PC-001'
AND timestamp > NOW() - INTERVAL '24 hours'
ORDER BY timestamp DESC;
```

**Via API**:
```
GET /api/metrics/cpu?computerName=PC-001&startDate=2025-12-23&limit=50
```

**Via UI**:
1. Go to `/metrics/cpu`
2. Enter "PC-001" in Computer Name filter
3. Select start date: 2025-12-23
4. Click "Apply Filters"

## Testing Integration

### 1. Test DataFetcher Integration

```powershell
# Run a scan
Import-Module .\Modules\DataFetcher.psm1
Import-Module .\Modules\InputBroker.psm1

$config = Get-Content .\Config\EMSConfig.json | ConvertFrom-Json
$targets = Invoke-InputRouter -Input "PC-001" -Config $config
$results = Invoke-DataFetch -Targets $targets -Config $config

# Verify metrics saved
psql -U postgres -d ems_production -c "SELECT * FROM metric_cpu_usage WHERE computer_name = 'PC-001' ORDER BY timestamp DESC LIMIT 1;"
```

### 2. Test API Endpoints

```powershell
# Start API
.\API\Start-EMSAPI.PS1

# In another terminal
$token = "your_jwt_token"
Invoke-RestMethod -Uri "http://localhost:5000/api/metrics/cpu?limit=10" -Headers @{ Authorization = "Bearer $token" }
```

### 3. Test UI

```bash
cd WebUI
npm start

# Navigate to:
# http://localhost:3000/metrics
# http://localhost:3000/metrics/cpu
```

## Performance Considerations

### Database

**Indexes**: All metric tables have indexes on:
- `(computer_name, timestamp)` - For filtered queries
- `timestamp` - For time-range queries

**Partitioning**: Event log tables partitioned by month
```sql
-- Check partitions
SELECT tablename FROM pg_tables WHERE tablename LIKE 'metric_system_events_%';
```

**Vacuum**: Regular maintenance
```powershell
# Add to scheduled task
psql -U postgres -d ems_production -c "VACUUM ANALYZE metric_cpu_usage;"
```

### API

**Pagination**: Always use `limit` parameter
```
/api/metrics/cpu?limit=100  # Good
/api/metrics/cpu            # Returns 100 by default
```

**Caching** (future enhancement):
```powershell
# Cache recent queries in Redis
Set-RedisCache -Key "metrics:cpu:PC-001" -Value $cpuData -ExpirationSeconds 60
```

## Troubleshooting

### Issue: Metrics not saving

**Check**:
1. DataFetcher calling Save function?
   ```powershell
   # Add debug log in DataFetcher.psm1
   Write-EMSLog "Calling Save-DiagnosticsToMetrics for $computerName"
   ```

2. MetricsData module imported?
   ```powershell
   Get-Module MetricsData  # Should show loaded
   ```

3. Database connectivity?
   ```powershell
   Test-PGConnection
   ```

### Issue: UI not showing data

**Check**:
1. API endpoint working?
   ```bash
   curl -H "Authorization: Bearer TOKEN" http://localhost:5000/api/metrics/cpu
   ```

2. CORS enabled?
   ```powershell
   # In Start-EMSAPI.ps1
   $cors = New-UDCorsPolicy -AllowedOrigin "http://localhost:3000"
   ```

3. Browser console errors?
   ```
   F12 → Console → Check for 401/500 errors
   ```

## Next Steps

1. **Add remaining metric pages** (50+ to create)
2. **Enhance visualizations** (charts, graphs)
3. **Add alerting** (threshold-based alerts)
4. **Automate retention** (delete old metrics)
5. **Performance tuning** (query optimization)

---

**Version**: 2.1  
**Module**: Complete Integration  
**Status**: Production Ready
