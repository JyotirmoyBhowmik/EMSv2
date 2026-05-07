-- Application-Specific Metric Tables
-- Add to existing schema for Zscaler, Seclore, and OneDrive monitoring

-- Zscaler Security Client Monitoring
CREATE TABLE IF NOT EXISTS metric_app_zscaler (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    installed BOOLEAN NOT NULL,
    version VARCHAR(100),
    service_running BOOLEAN,
    app_running BOOLEAN,
    service_status VARCHAR(50),
    PRIMARY KEY (computer_name, timestamp)
);

CREATE INDEX idx_zscaler_computer ON metric_app_zscaler(computer_name);
CREATE INDEX idx_zscaler_time ON metric_app_zscaler(timestamp DESC);
CREATE INDEX idx_zscaler_status ON metric_app_zscaler(installed, service_running);

COMMENT ON TABLE metric_app_zscaler IS 'Zscaler security client monitoring';

-- Seclore DRM Client Monitoring
CREATE TABLE IF NOT EXISTS metric_app_seclore (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    installed BOOLEAN NOT NULL,
    version VARCHAR(100),
    service_running BOOLEAN,
    app_running BOOLEAN,
    office_plugins_installed JSONB,
    install_location VARCHAR(500),
    PRIMARY KEY (computer_name, timestamp)
);

CREATE INDEX idx_seclore_computer ON metric_app_seclore(computer_name);
CREATE INDEX idx_seclore_time ON metric_app_seclore(timestamp DESC);
CREATE INDEX idx_seclore_status ON metric_app_seclore(installed, service_running);

COMMENT ON TABLE metric_app_seclore IS 'Seclore DRM client and Office plugin monitoring';

-- OneDrive Sync Monitoring
CREATE TABLE IF NOT EXISTS metric_app_onedrive (
    computer_name VARCHAR(255) REFERENCES computers(computer_name) ON DELETE CASCADE,
    timestamp TIMESTAMP DEFAULT NOW(),
    installed BOOLEAN NOT NULL,
    version VARCHAR(100),
    running BOOLEAN,
    sync_status VARCHAR(50),
    sync_location VARCHAR(500),
    sync_errors INTEGER DEFAULT 0,
    storage_used_gb DECIMAL(10,2),
    business_configured BOOLEAN,
    PRIMARY KEY (computer_name, timestamp)
);

CREATE INDEX idx_onedrive_computer ON metric_app_onedrive(computer_name);
CREATE INDEX idx_onedrive_time ON metric_app_onedrive(timestamp DESC);
CREATE INDEX idx_onedrive_sync ON metric_app_onedrive(sync_status);
CREATE INDEX idx_onedrive_errors ON metric_app_onedrive(sync_errors) WHERE sync_errors > 0;

COMMENT ON TABLE metric_app_onedrive IS 'OneDrive installation and sync status monitoring';

-- Update materialized view to include app metrics
DROP MATERIALIZED VIEW IF EXISTS view_computer_health_summary CASCADE;

CREATE MATERIALIZED VIEW view_computer_health_summary AS
SELECT 
    c.computer_name,
    c.ip_address,
    c.operating_system,
    c.domain,
    c.is_active,
    c.last_seen,
    
    -- Latest CPU
    (SELECT usage_percent FROM metric_cpu_usage WHERE computer_name = c.computer_name ORDER BY timestamp DESC LIMIT 1) as cpu_usage,
    
    -- Latest Memory
    (SELECT usage_percent FROM metric_memory WHERE computer_name = c.computer_name ORDER BY timestamp DESC LIMIT 1) as memory_usage,
    
    -- Pending Updates
    (SELECT pending_updates FROM metric_windows_updates WHERE computer_name = c.computer_name ORDER BY timestamp DESC LIMIT 1) as pending_updates,
    
    -- Antivirus Status
    (SELECT real_time_protection FROM metric_antivirus WHERE computer_name = c.computer_name ORDER BY timestamp DESC LIMIT 1) as av_enabled,
    
    -- Application Status
    (SELECT service_running FROM metric_app_zscaler WHERE computer_name = c.computer_name ORDER BY timestamp DESC LIMIT 1) as zscaler_running,
    (SELECT service_running FROM metric_app_seclore WHERE computer_name = c.computer_name ORDER BY timestamp DESC LIMIT 1) as seclore_running,
    (SELECT sync_status FROM metric_app_onedrive WHERE computer_name = c.computer_name ORDER BY timestamp DESC LIMIT 1) as onedrive_status

FROM computers c
WHERE c.is_active = true;

CREATE UNIQUE INDEX idx_health_summary_computer ON view_computer_health_summary(computer_name);

-- Refresh command (run after data updates)
-- REFRESH MATERIALIZED VIEW CONCURRENTLY view_computer_health_summary;

COMMENT ON MATERIALIZED VIEW view_computer_health_summary IS 'Pre-aggregated computer health data including application status';
