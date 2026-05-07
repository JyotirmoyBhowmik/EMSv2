# EMS Granular Metrics - Database Schema Reference

## Overview

EMS v2.1 replaces the generic `diagnostic_details` table with **63 dedicated metric tables**, each optimized for specific monitoring parameters.

## Core Architecture

```
computers (PK: computer_name)
    ├── computer_ad_users (mapping table)
    └── metric_* tables (63 tables, FK: computer_name)
```

---

## Core Tables

### computers
**Purpose**: Central registry of all monitored systems

| Column | Type | Description |
|--------|------|-------------|
| computer_name | VARCHAR(255) PK | Unique computer identifier |
| ip_address | INET | Current IP address |
| mac_address | VARCHAR(17) | MAC address |
| operating_system | VARCHAR(100) | OS name |
| os_version | VARCHAR(50) | OS version |
| domain | VARCHAR(100) | AD domain (if joined) |
| is_domain_joined | BOOLEAN | Domain membership status |
| computer_type | VARCHAR(50) | Desktop/Laptop/Server/Workstation |
| location | VARCHAR(100) | Physical location |
| department | VARCHAR(100) | Organizational unit |
| first_seen | TIMESTAMP | First registration |
| last_seen | TIMESTAMP | Last activity (auto-updated by triggers) |
| is_active | BOOLEAN | Active status |

**Indexes**: `computer_name` (PK), `domain`, `is_active`, `last_seen`, `ip_address`

---

### computer_ad_users
**Purpose**: Many-to-many mapping between computers and users

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL PK | Unique ID |
| computer_name | VARCHAR(255) FK | References computers |
| user_id | VARCHAR(255) | AD user ID |
| user_display_name | VARCHAR(255) | User's display name |
| user_email | VARCHAR(255) | Email address |
| is_primary_user | BOOLEAN | Primary user flag |
| last_login | TIMESTAMP | Last login time |
| login_count | INTEGER | Total logins |

**Indexes**: `computer_name`, `user_id`, `is_primary_user`

---

## Metric Tables (63 Total)

### System Health (10 tables)

#### metric_cpu_usage
**Stores**: CPU utilization and processor information

| Column | Type | Notes |
|--------|------|-------|
| computer_name | VARCHAR(255) FK+PK | |
| timestamp | TIMESTAMP PK | |
| usage_percent | DECIMAL(5,2) | Current CPU % |
| core_count | INTEGER | Physical cores |
| logical_processors | INTEGER | Logical CPUs |
| processor_name | VARCHAR(255) | CPU model |
| processor_speed_mhz | INTEGER | Clock speed |

**Query Example**:
```sql
SELECT computer_name, AVG(usage_percent) as avg_cpu
FROM metric_cpu_usage
WHERE timestamp > NOW() - INTERVAL '24 hours'
GROUP BY computer_name
HAVING AVG(usage_percent) > 80;
```

#### metric_memory
**Stores**: RAM usage statistics

| Column | Type | Notes |
|--------|------|-------|
| total_gb | DECIMAL(10,2) | Total RAM |
| available_gb | DECIMAL(10,2) | Free RAM |
| used_gb | DECIMAL(10,2) | Used RAM |
| usage_percent | DECIMAL(5,2) | Memory utilization |
| page_file_usage_percent | DECIMAL(5,2) | Page file % |

#### metric_disk_space
**Stores**: Per-drive storage information (multi-row per computer)

| Column | Type | Notes |
|--------|------|-------|
| drive_letter | CHAR(1) PK | C, D, E, etc. |
| volume_name | VARCHAR(255) | Volume label |
| total_gb | DECIMAL(10,2) | Capacity |
| free_gb | DECIMAL(10,2) | Available |
| usage_percent | DECIMAL(5,2) | Used % |
| file_system | VARCHAR(20) | NTFS, FAT32, etc. |
| is_system_drive | BOOLEAN | System drive flag |

**Additional Tables**:
- `metric_disk_performance` - IOPS, read/write speeds
- `metric_network_adapters` - NIC details
- `metric_temperature` - Hardware sensors
- `metric_power_status` - Battery, power plan
- `metric_bios_info` - Firmware details
- `metric_motherboard` - Hardware info
- `metric_system_uptime` - Boot time, uptime

---

### Security (15 tables)

#### metric_windows_updates
**Stores**: Windows Update status

| Column | Type | Notes |
|--------|------|-------|
| total_updates | INTEGER | All updates |
| pending_updates | INTEGER | Awaiting install |
| failed_updates | INTEGER | Failed count |
| last_update_date | TIMESTAMP | Last update installed |
| auto_update_enabled | BOOLEAN | Auto-update status |
| reboot_required | BOOLEAN | Reboot pending |

#### metric_antivirus
**Stores**: AV product status

| Column | Type | Notes |
|--------|------|-------|
| av_product | VARCHAR(255) | Product name |
| definitions_version | VARCHAR(100) | Signature version |
| definitions_date | DATE | Last definition update |
| real_time_protection | BOOLEAN | Real-time scan status |
| threat_count | INTEGER | Detected threats |

**Additional Tables**:
- `metric_firewall` - Firewall profiles
- `metric_user_accounts` - Local user summary
- `metric_login_history` - Login events
- `metric_failed_logins` - Failed auth attempts
- `metric_bitlocker` - Drive encryption
- `metric_tpm` - TPM status
- `metric_secure_boot` - UEFI secure boot
- `metric_audit_policies` - Audit settings
- `metric_password_policy` - Password rules
- `metric_smb_shares` - Network shares
- `metric_open_ports` - Listening ports
- `metric_certificates` - Installed certs

---

### Network (8 tables)

#### metric_network_connections
**Stores**: Active TCP/UDP connections

| Column | Type | Notes |
|--------|------|-------|
| connection_id | SERIAL PK | Unique ID |
| protocol | VARCHAR(10) | TCP/UDP |
| local_port | INTEGER | Local port |
| remote_address | INET | Remote IP |
| remote_port | INTEGER | Remote port |
| state | VARCHAR(50) | ESTABLISHED, LISTEN, etc. |
| process_name | VARCHAR(255) | Owning process |

**Additional Tables**:
- `metric_network_stats` - Traffic statistics
- `metric_dns_cache` - DNS entries
- `metric_routing_table` - Network routes
- `metric_wifi_networks` - WiFi SSIDs
- `metric_vpn_connections` - VPN sessions
- `metric_proxy_settings` - Proxy config

---

### Software & Compliance (12 tables)

#### metric_installed_software
**Stores**: Installed applications

| Column | Type | Notes |
|--------|------|-------|
| software_name | VARCHAR(255) PK | Product name |
| version | VARCHAR(100) PK | Version number |
| vendor | VARCHAR(255) | Publisher |
| install_date | DATE | Installation date |
| size_mb | DECIMAL(10,2) | Disk usage |

**Query Example**:
```sql
-- Find all computers with specific software
SELECT DISTINCT computer_name
FROM metric_installed_software
WHERE software_name LIKE '%Chrome%'
AND timestamp > NOW() - INTERVAL '7 days';
```

**Additional Tables**:
- `metric_startup_programs` - Auto-start items
- `metric_services` - Windows services
- `metric_scheduled_tasks` - Task scheduler
- `metric_browser_extensions` - Browser add-ons
- `metric_office_version` - MS Office details
- `metric_registry_settings` - Registry values
- `metric_gpo_applied` - Group policies
- `metric_environment_variables` - Env vars
- `metric_drivers` - Device drivers
- `metric_windows_features` - Installed features

---

### User Experience (10 tables)

#### metric_login_time
**Stores**: Login performance metrics

| Column | Type | Notes |
|--------|------|-------|
| user_id | VARCHAR(255) | Logged-in user |
| boot_duration_sec | INTEGER | Boot time |
| login_duration_sec | INTEGER | Login time |
| desktop_ready_sec | INTEGER | Desktop load time |
| total_duration_sec | INTEGER | Total |

**Additional Tables**:
- `metric_application_crashes` - App crash history
- `metric_browser_performance` - Browser metrics
- `metric_printing_issues` - Print problems
- `metric_mapped_drives` - Network drives
- `metric_printers` - Installed printers
- `metric_display_settings` - Monitor config
- `metric_sound_devices` - Audio devices
- `metric_usb_devices` - USB peripherals

---

### Event Logs (5 tables)

**Partitioned by Month** for performance

#### metric_system_events
**Stores**: System event log entries

| Column | Type | Notes |
|--------|------|-------|
| event_id | INTEGER | Windows event ID |
| level | VARCHAR(50) | Error/Warning/Info |
| source | VARCHAR(255) | Event source |
| message | TEXT | Event description |

**Partitioning**:
```sql
CREATE TABLE metric_system_events_2025_12 PARTITION OF metric_system_events
FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');
```

**Additional Tables**:
- `metric_application_events` - App log (partitioned)
- `metric_security_events` - Security log (partitioned)
- `metric_error_summary` - Error aggregates
- `metric_warning_summary` - Warning aggregates

---

### Performance Baselines (3 tables)

#### metric_performance_baseline
**Stores**: Historical performance averages (daily)

| Column | Type | Notes |
|--------|------|-------|
| metric_date | DATE PK | Aggregation date |
| avg_cpu_percent | DECIMAL(5,2) | Daily avg CPU |
| avg_memory_percent | DECIMAL(5,2) | Daily avg memory |
| peak_cpu_percent | DECIMAL(5,2) | Daily max CPU |

#### metric_health_score_history
**Stores**: Daily health score trends

**Additional Tables**:
- `metric_compliance_score` - Compliance tracking

---

## Querying Patterns

### Current State
```sql
-- Get latest metrics for a computer
SELECT 
    c.computer_name,
    cpu.usage_percent as current_cpu,
    mem.usage_percent as current_memory
FROM computers c
LEFT JOIN LATERAL (
    SELECT usage_percent FROM metric_cpu_usage
    WHERE computer_name = c.computer_name
    ORDER BY timestamp DESC LIMIT 1
) cpu ON true
LEFT JOIN LATERAL (
    SELECT usage_percent FROM metric_memory
    WHERE computer_name = c.computer_name
    ORDER BY timestamp DESC LIMIT 1
) mem ON true
WHERE c.is_active = true;
```

### Time-Series Analysis
```sql
-- CPU trend over last 7 days
SELECT 
    DATE_TRUNC('day', timestamp) as day,
    AVG(usage_percent) as avg_cpu,
    MAX(usage_percent) as max_cpu
FROM metric_cpu_usage
WHERE computer_name = 'PC-001'
AND timestamp > NOW() - INTERVAL '7 days'
GROUP BY day
ORDER BY day;
```

### Compliance Queries
```sql
-- Computers with pending updates > 10
SELECT computer_name, pending_updates
FROM metric_windows_updates
WHERE timestamp > NOW() - INTERVAL '24 hours'
AND pending_updates > 10;

-- Computers without antivirus
SELECT c.computer_name
FROM computers c
LEFT JOIN metric_antivirus av ON c.computer_name = av.computer_name
WHERE av.computer_name IS NULL
OR av.av_enabled = false;
```

---

## Maintenance

### Partition Management
```sql
-- Create next month's partition
CREATE TABLE metric_system_events_2026_01 PARTITION OF metric_system_events
FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
```

### Data Retention
```sql
-- Delete old metrics (>90 days)
DELETE FROM metric_cpu_usage WHERE timestamp < NOW() - INTERVAL '90 days';
```

### Vacuum & Analyze
```sql
VACUUM ANALYZE metric_cpu_usage;
VACUUM ANALYZE metric_memory;
```

---

**Schema Version**: 2.1  
**Total Tables**: 66 (3 core + 63 metrics)  
**Indexes**: 80+  
**Functions**: 15+
