-- EMS Granular Metrics Database Schema - Part 2
-- Software, User Experience, Events, and Performance tables

-- ===================================
-- SOFTWARE & COMPLIANCE METRICS (12 tables)
-- ===================================

-- 34. Installed Software
CREATE TABLE metric_installed_software (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    software_name VARCHAR(255),
    version VARCHAR(100),
    vendor VARCHAR(255),
    install_date DATE,
    install_location VARCHAR(500),
    size_mb DECIMAL(10,2),
    install_source VARCHAR(255),
    is_system_component BOOLEAN DEFAULT false,
    PRIMARY KEY (computer_name, timestamp, software_name, version)
);
CREATE INDEX idx_software_name ON metric_installed_software(software_name);

-- 35. Startup Programs
CREATE TABLE metric_startup_programs (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    program_name VARCHAR(255),
    command VARCHAR(1000),
    location VARCHAR(100), -- Startup folder, Registry, Task Scheduler
    user_context VARCHAR(100), -- All Users, Current User
    enabled BOOLEAN,
    impact VARCHAR(20), -- High, Medium, Low
    PRIMARY KEY (computer_name, timestamp, program_name, location)
);

-- 36. Windows Services
CREATE TABLE metric_services (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    service_name VARCHAR(255),
    display_name VARCHAR(255),
    status VARCHAR(50),
    startup_type VARCHAR(50),
    account VARCHAR(255),
    path_name VARCHAR(1000),
    description TEXT,
    dependencies TEXT[],
    is_critical BOOLEAN DEFAULT false,
    PRIMARY KEY (computer_name, timestamp, service_name)
);

-- 37. Scheduled Tasks
CREATE TABLE metric_scheduled_tasks (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    task_name VARCHAR(255),
    task_path VARCHAR(500),
    enabled BOOLEAN,
    state VARCHAR(50),
    last_run_time TIMESTAMP,
    last_result INTEGER,
    next_run_time TIMESTAMP,
    trigger_description TEXT,
    action_description TEXT,
    run_as_user VARCHAR(255),
    PRIMARY KEY (computer_name, timestamp, task_name)
);

-- 38. Browser Extensions
CREATE TABLE metric_browser_extensions (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    browser VARCHAR(50), -- Chrome, Edge, Firefox
    extension_name VARCHAR(255),
    extension_id VARCHAR(100),
    version VARCHAR(50),
    enabled BOOLEAN,
    permissions TEXT[],
    install_date DATE,
    PRIMARY KEY (computer_name, timestamp, browser, extension_id)
);

-- 39. Office Version
CREATE TABLE metric_office_version (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    office_version VARCHAR(50),
    office_edition VARCHAR(100),
    office_architecture VARCHAR(10), -- x86, x64
    license_status VARCHAR(50),
    product_key_last_5 VARCHAR(5),
    click_to_run BOOLEAN,
    update_channel VARCHAR(100),
    applications TEXT[], -- Word, Excel, PowerPoint, etc.
    PRIMARY KEY (computer_name, timestamp)
);

-- 40. Registry Settings (Monitored keys)
CREATE TABLE metric_registry_settings (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    registry_path VARCHAR(1000),
    value_name VARCHAR(255),
    value_data TEXT,
    value_type VARCHAR(50),
    compliance_status VARCHAR(50), -- Compliant, Non-Compliant, NotFound
    expected_value TEXT,
    PRIMARY KEY (computer_name, timestamp, registry_path, value_name)
);

-- 41. Group Policies Applied
CREATE TABLE metric_gpo_applied (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    gpo_name VARCHAR(255),
    gpo_guid VARCHAR(50),
    gpo_status VARCHAR(50), -- Enabled, Disabled, Forced
    applied_time TIMESTAMP,
    gpo_version VARCHAR(50),
    domain VARCHAR(100),
    PRIMARY KEY (computer_name, timestamp, gpo_guid)
);

-- 42. Environment Variables
CREATE TABLE metric_environment_variables (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    variable_name VARCHAR(255),
    variable_value TEXT,
    variable_type VARCHAR(50), -- System, User
    PRIMARY KEY (computer_name, timestamp, variable_name, variable_type)
);

-- 43. Device Drivers
CREATE TABLE metric_drivers (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    device_name VARCHAR(255),
    driver_provider VARCHAR(100),
    driver_version VARCHAR(50),
    driver_date DATE,
    driver_signer VARCHAR(100),
    is_signed BOOLEAN,
    device_class VARCHAR(100),
    device_status VARCHAR(50),
    PRIMARY KEY (computer_name, timestamp, device_name, driver_version)
);

-- 44. Windows Features
CREATE TABLE metric_windows_features (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    feature_name VARCHAR(255),
    feature_state VARCHAR(50), -- Enabled, Disabled, EnablePending
    feature_type VARCHAR(100),
    PRIMARY KEY (computer_name, timestamp, feature_name)
);

-- 45. PowerShell Version
CREATE TABLE metric_powershell_version (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    ps_version VARCHAR(50),
    ps_edition VARCHAR(50), -- Desktop, Core
    clr_version VARCHAR(50),
    ws_management_version VARCHAR(50),
    serialization_version VARCHAR(50),
    execution_policy VARCHAR(50),
    PRIMARY KEY (computer_name, timestamp)
);

-- ===================================
-- USER EXPERIENCE METRICS (10 tables)
-- ===================================

-- 46. Login Time Performance
CREATE TABLE metric_login_time (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    user_id VARCHAR(255),
    boot_duration_sec INTEGER,
    login_duration_sec INTEGER,
    desktop_ready_sec INTEGER,
    total_duration_sec INTEGER,
    gpo_processing_sec INTEGER,
    profile_load_sec INTEGER,
    PRIMARY KEY (computer_name, timestamp)
);

-- 47. Application Crashes
CREATE TABLE metric_application_crashes (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    application_name VARCHAR(255),
    application_version VARCHAR(100),
    crash_time TIMESTAMP,
    exception_code VARCHAR(20),
    faulting_module VARCHAR(255),
    crash_count_7d INTEGER,
    crash_count_30d INTEGER,
    PRIMARY KEY (computer_name, timestamp, application_name, crash_time)
);

-- 48. Browser Performance
CREATE TABLE metric_browser_performance (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    browser_name VARCHAR(50),
    browser_version VARCHAR(50),
    page_load_time_avg_ms INTEGER,
    memory_usage_mb DECIMAL(10,2),
    cpu_usage_percent DECIMAL(5,2),
    cache_size_mb DECIMAL(10,2),
    extension_count INTEGER,
    tab_count INTEGER,
    PRIMARY KEY (computer_name, timestamp, browser_name)
);

-- 49. Printing Issues
CREATE TABLE metric_printing_issues (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    total_print_jobs INTEGER,
    failed_print_jobs INTEGER,
    pending_print_jobs INTEGER,
    last_error_time TIMESTAMP,
    last_error_code INTEGER,
    last_error_message TEXT,
    PRIMARY KEY (computer_name, timestamp)
);

-- 50. Mapped Network Drives
CREATE TABLE metric_mapped_drives (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    drive_letter CHAR(1),
    network_path VARCHAR(500),
    status VARCHAR(50), -- Connected, Disconnected, Unavailable
    persistent BOOLEAN,
    user_name VARCHAR(255),
    PRIMARY KEY (computer_name, timestamp, drive_letter)
);

-- 51. Installed Printers
CREATE TABLE metric_printers (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    printer_name VARCHAR(255),
    printer_status VARCHAR(50),
    is_default BOOLEAN,
    is_network BOOLEAN,
    port_name VARCHAR(100),
    driver_name VARCHAR(255),
    driver_version VARCHAR(50),
    share_name VARCHAR(255),
    location VARCHAR(255),
    PRIMARY KEY (computer_name, timestamp, printer_name)
);

-- 52. Display Settings
CREATE TABLE metric_display_settings (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    monitor_name VARCHAR(255),
    resolution_width INTEGER,
    resolution_height INTEGER,
    refresh_rate INTEGER,
    color_depth INTEGER,
    is_primary BOOLEAN,
    orientation VARCHAR(50),
    scaling_percent INTEGER,
    PRIMARY KEY (computer_name, timestamp, monitor_name)
);

-- 53. Sound Devices
CREATE TABLE metric_sound_devices (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    device_name VARCHAR(255),
    device_type VARCHAR(50), -- Playback, Recording
    is_default BOOLEAN,
    device_status VARCHAR(50),
    driver_version VARCHAR(50),
    PRIMARY KEY (computer_name, timestamp, device_name, device_type)
);

-- 54. USB Devices
CREATE TABLE metric_usb_devices (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    device_name VARCHAR(255),
    device_id VARCHAR(500),
    device_class VARCHAR(100),
    manufacturer VARCHAR(100),
    device_status VARCHAR(50),
    is_present BOOLEAN,
    last_connected TIMESTAMP,
    PRIMARY KEY (computer_name, timestamp, device_id)
);

-- 55. Bluetooth Devices
CREATE TABLE metric_bluetooth_devices (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    device_name VARCHAR(255),
    device_address VARCHAR(17),
    device_type VARCHAR(100),
    paired BOOLEAN,
    connected BOOLEAN,
    device_class VARCHAR(100),
    last_seen TIMESTAMP,
    PRIMARY KEY (computer_name, timestamp, device_address)
);

-- ===================================
-- EVENT LOG METRICS (5 tables)
-- ===================================

-- 56. System Events (Partitioned by month)
CREATE TABLE metric_system_events (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    event_id INTEGER,
    level VARCHAR(50),
    source VARCHAR(255),
    message TEXT,
    user_name VARCHAR(255),
    PRIMARY KEY (computer_name, timestamp, event_id)
) PARTITION BY RANGE (timestamp);

-- Create initial partitions
CREATE TABLE metric_system_events_2025_12 PARTITION OF metric_system_events
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

CREATE TABLE metric_system_events_2026_01 PARTITION OF metric_system_events
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

-- 57. Application Events (Partitioned)
CREATE TABLE metric_application_events (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    event_id INTEGER,
    level VARCHAR(50),
    source VARCHAR(255),
    message TEXT,
    user_name VARCHAR(255),
    PRIMARY KEY (computer_name, timestamp, event_id)
) PARTITION BY RANGE (timestamp);

CREATE TABLE metric_application_events_2025_12 PARTITION OF metric_application_events
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

-- 58. Security Events (Partitioned)
CREATE TABLE metric_security_events (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    event_id INTEGER,
    level VARCHAR(50),
    source VARCHAR(255),
    message TEXT,
    user_name VARCHAR(255),
    logon_type INTEGER,
    logon_process VARCHAR(100),
    PRIMARY KEY (computer_name, timestamp, event_id)
) PARTITION BY RANGE (timestamp);

CREATE TABLE metric_security_events_2025_12 PARTITION OF metric_security_events
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

-- 59. Error Summary (Last 24h)
CREATE TABLE metric_error_summary (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    error_count_24h INTEGER,
    critical_count_24h INTEGER,
    most_common_error_id INTEGER,
    most_common_error_count INTEGER,
    most_common_error_source VARCHAR(255),
    PRIMARY KEY (computer_name, timestamp)
);

-- 60. Warning Summary (Last 24h)
CREATE TABLE metric_warning_summary (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    warning_count_24h INTEGER,
    most_common_warning_id INTEGER,
    most_common_warning_count INTEGER,
    most_common_warning_source VARCHAR(255),
    PRIMARY KEY (computer_name, timestamp)
);

-- ===================================
-- PERFORMANCE BASELINES (3 tables)
-- ===================================

-- 61. Performance Baseline (Historical averages)
CREATE TABLE metric_performance_baseline (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    metric_date DATE,
    avg_cpu_percent DECIMAL(5,2),
    avg_memory_percent DECIMAL(5,2),
    avg_disk_usage_percent DECIMAL(5,2),
    avg_network_mbps DECIMAL(10,2),
    peak_cpu_percent DECIMAL(5,2),
    peak_memory_percent DECIMAL(5,2),
    uptime_percent DECIMAL(5,2),
    PRIMARY KEY (computer_name, metric_date)
);

-- 62. Health Score History (Daily aggregation)
CREATE TABLE metric_health_score_history (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    score_date DATE,
    avg_health_score DECIMAL(5,2),
    min_health_score DECIMAL(5,2),
    max_health_score DECIMAL(5,2),
    critical_issues_count INTEGER,
    warning_issues_count INTEGER,
    scans_performed INTEGER,
    PRIMARY KEY (computer_name, score_date)
);

-- 63. Compliance Score (Daily)
CREATE TABLE metric_compliance_score (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    score_date DATE,
    compliance_score DECIMAL(5,2),
    security_score DECIMAL(5,2),
    patch_score DECIMAL(5,2),
    policy_score DECIMAL(5,2),
    failed_checks TEXT[],
    passed_checks INTEGER,
    total_checks INTEGER,
    PRIMARY KEY (computer_name, score_date)
);

-- ===================================
-- INDEXES FOR PERFORMANCE
-- ===================================

-- Time-series queries
CREATE INDEX idx_all_metrics_computer ON metric_cpu_usage(computer_name);
CREATE INDEX idx_all_metrics_timestamp ON metric_cpu_usage(timestamp DESC);

-- Create function to update computer last_seen automatically
CREATE OR REPLACE FUNCTION update_computer_last_seen()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE computers 
    SET last_seen = NEW.timestamp, 
        updated_at = NOW()
    WHERE computer_name = NEW.computer_name;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply trigger to key metric tables
CREATE TRIGGER tr_cpu_update_last_seen
    AFTER INSERT ON metric_cpu_usage
    FOR EACH ROW EXECUTE FUNCTION update_computer_last_seen();

CREATE TRIGGER tr_memory_update_last_seen
    AFTER INSERT ON metric_memory
    FOR EACH ROW EXECUTE FUNCTION update_computer_last_seen();

-- ===================================
-- MATERIALIZED VIEWS
-- ===================================

-- Computer Health Summary View
CREATE MATERIALIZED VIEW view_computer_health_summary AS
SELECT 
    c.computer_name,
    c.ip_address,
    c.operating_system,
    c.domain,
    c.computer_type,
    c.last_seen,
    c.is_active,
    COALESCE(cpu.usage_percent, 0) as current_cpu_usage,
    COALESCE(mem.usage_percent, 0) as current_memory_usage,
    COALESCE(disk.max_usage, 0) as max_disk_usage,
    COALESCE(wu.pending_updates, 0) as pending_updates,
    COALESCE(av.av_enabled, false) as antivirus_enabled,
    COALESCE(fw.domain_profile_enabled, false) as firewall_enabled,
    ARRAY_LENGTH(users.user_ids, 1) as user_count
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
LEFT JOIN LATERAL (
    SELECT MAX(usage_percent) as max_usage FROM metric_disk_space
    WHERE computer_name = c.computer_name 
    AND timestamp > NOW() - INTERVAL '1 hour'
) disk ON true
LEFT JOIN LATERAL (
    SELECT pending_updates FROM metric_windows_updates 
    WHERE computer_name = c.computer_name 
    ORDER BY timestamp DESC LIMIT 1
) wu ON true
LEFT JOIN LATERAL (
    SELECT av_enabled FROM metric_antivirus 
    WHERE computer_name = c.computer_name 
    ORDER BY timestamp DESC LIMIT 1
) av ON true
LEFT JOIN LATERAL (
    SELECT domain_profile_enabled FROM metric_firewall 
    WHERE computer_name = c.computer_name 
    ORDER BY timestamp DESC LIMIT 1
) fw ON true
LEFT JOIN LATERAL (
    SELECT ARRAY_AGG(DISTINCT user_id) as user_ids
    FROM computer_ad_users 
    WHERE computer_name = c.computer_name
) users ON true
WHERE c.is_active = true;

CREATE INDEX idx_health_summary_computer ON view_computer_ health_summary(computer_name);

-- Refresh function
CREATE OR REPLACE FUNCTION refresh_computer_health_summary()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW view_computer_health_summary;
END;
$$ LANGUAGE plpgsql;

-- Schema complete! 63 metric tables created.
