-- =====================================================
-- Enterprise Endpoint Monitoring System (EMS)
-- PostgreSQL Database Schema
-- Version: 1.0
-- Date: 2025-12-23
-- =====================================================

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; -- For fuzzy text search

-- =====================================================
-- TABLE: users
-- Stores admin users and their authentication info
-- =====================================================
CREATE TABLE users (
    user_id SERIAL PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    domain VARCHAR(100),
    display_name VARCHAR(255),
    email VARCHAR(255),
    role VARCHAR(50) DEFAULT 'viewer' CHECK (role IN ('admin', 'operator', 'viewer')),
    is_active BOOLEAN DEFAULT true,
    last_login TIMESTAMP,
    failed_login_attempts INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_active ON users(is_active) WHERE is_active = true;

-- =====================================================
-- TABLE: scan_results (Partitioned by month)
-- Main table for endpoint scan results
-- =====================================================
CREATE TABLE scan_results (
    scan_id BIGSERIAL,
    hostname VARCHAR(255) NOT NULL,
    ip_address INET,
    user_id_resolved VARCHAR(255),
    initiated_by INTEGER REFERENCES users(user_id),
    scan_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    health_score INTEGER CHECK (health_score BETWEEN 0 AND 100),
    topology VARCHAR(50) CHECK (topology IN ('HO', 'Remote')),
    status VARCHAR(50) DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'completed', 'failed', 'timeout')),
    execution_time_seconds NUMERIC(10,2),
    error_message TEXT,
    
    -- Diagnostic summary counts
    critical_count INTEGER DEFAULT 0,
    warning_count INTEGER DEFAULT 0,
    info_count INTEGER DEFAULT 0,
    
    -- Metadata
    scan_type VARCHAR(50) DEFAULT 'full', -- 'full', 'quick', 'targeted'
    triggered_by VARCHAR(50) DEFAULT 'manual', -- 'manual', 'scheduled', 'alert'
    
    PRIMARY KEY (scan_id, scan_timestamp)
) PARTITION BY RANGE (scan_timestamp);

-- Create partitions for current and next 3 months
CREATE TABLE scan_results_2025_12 PARTITION OF scan_results
    FOR VALUES FROM ('2025-12-01') TO ('2026-01-01');

CREATE TABLE scan_results_2026_01 PARTITION OF scan_results
    FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');

CREATE TABLE scan_results_2026_02 PARTITION OF scan_results
    FOR VALUES FROM ('2026-02-01') TO ('2026-03-01');

CREATE TABLE scan_results_2026_03 PARTITION OF scan_results
    FOR VALUES FROM ('2026-03-01') TO ('2026-04-01');

-- Indexes on partitioned table
CREATE INDEX idx_scan_hostname ON scan_results(hostname);
CREATE INDEX idx_scan_timestamp ON scan_results(scan_timestamp DESC);
CREATE INDEX idx_scan_status ON scan_results(status);
CREATE INDEX idx_scan_health ON scan_results(health_score);
CREATE INDEX idx_scan_user ON scan_results(user_id_resolved);

-- Full-text search index for hostname
CREATE INDEX idx_scan_hostname_trgm ON scan_results USING GIN (hostname gin_trgm_ops);

-- =====================================================
-- TABLE: diagnostic_details
-- Stores individual diagnostic check results
-- =====================================================
CREATE TABLE diagnostic_details (
    detail_id BIGSERIAL PRIMARY KEY,
    scan_id BIGINT NOT NULL,
    scan_timestamp TIMESTAMP NOT NULL, -- Needed for partition routing
    
    -- Diagnostic categorization
    category VARCHAR(100) NOT NULL, -- 'SystemHealth', 'Security', 'Network', 'Software', 'UserExperience'
    subcategory VARCHAR(100),
    severity VARCHAR(20) NOT NULL CHECK (severity IN ('Info', 'Warning', 'Critical')),
    
    -- Check details
    check_name VARCHAR(255) NOT NULL,
    status VARCHAR(50) NOT NULL, -- 'Pass', 'Fail', 'Warning', 'NotApplicable'
    message TEXT,
    details JSONB, -- Flexible storage for check-specific data
    
    -- Remediation
    remediation_available BOOLEAN DEFAULT false,
    remediation_command TEXT,
    remediation_applied BOOLEAN DEFAULT false,
    remediation_timestamp TIMESTAMP,
    
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    FOREIGN KEY (scan_id, scan_timestamp) REFERENCES scan_results(scan_id, scan_timestamp) ON DELETE CASCADE
);

CREATE INDEX idx_diagnostic_scan ON diagnostic_details(scan_id);
CREATE INDEX idx_diagnostic_category ON diagnostic_details(category);
CREATE INDEX idx_diagnostic_severity ON diagnostic_details(severity);
CREATE INDEX idx_diagnostic_status ON diagnostic_details(status);

-- GIN index for JSONB queries
CREATE INDEX idx_diagnostic_details_gin ON diagnostic_details USING GIN (details);

-- =====================================================
-- TABLE: audit_logs
-- Comprehensive audit trail for all system actions
-- =====================================================
CREATE TABLE audit_logs (
    log_id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    user_id INTEGER REFERENCES users(user_id),
    username VARCHAR(255), -- Denormalized for performance
    
    -- Action details
    action VARCHAR(100) NOT NULL, -- 'Login', 'Logout', 'ScanInitiated', 'RemediationExecuted', etc.
    target VARCHAR(255), -- Hostname or resource affected
    result VARCHAR(50) NOT NULL, -- 'Success', 'Failed', 'Unauthorized'
    
    -- Technical details
    ip_address INET,
    user_agent TEXT,
    details JSONB,
    
    -- Security
    risk_level VARCHAR(20) DEFAULT 'Low' CHECK (risk_level IN ('Low', 'Medium', 'High', 'Critical'))
);

CREATE INDEX idx_audit_timestamp ON audit_logs(timestamp DESC);
CREATE INDEX idx_audit_user ON audit_logs(user_id);
CREATE INDEX idx_audit_action ON audit_logs(action);
CREATE INDEX idx_audit_result ON audit_logs(result);
CREATE INDEX idx_audit_risk ON audit_logs(risk_level) WHERE risk_level IN ('High', 'Critical');

-- =====================================================
-- TABLE: remediation_history
-- Tracks all remediation actions executed
-- =====================================================
CREATE TABLE remediation_history (
    remediation_id BIGSERIAL PRIMARY KEY,
    scan_id BIGINT,
    diagnostic_detail_id BIGINT REFERENCES diagnostic_details(detail_id),
    
    hostname VARCHAR(255) NOT NULL,
    remediation_type VARCHAR(100) NOT NULL, -- 'ServiceRestart', 'ProcessKill', 'DiskCleanup', etc.
    remediation_command TEXT NOT NULL,
    
    executed_by INTEGER REFERENCES users(user_id),
    executed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    
    status VARCHAR(50) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'success', 'failed', 'rolled_back')),
    result_message TEXT,
    execution_time_seconds NUMERIC(10,2),
    
    -- Approval workflow
    requires_approval BOOLEAN DEFAULT true,
    approved_by INTEGER REFERENCES users(user_id),
    approved_at TIMESTAMP,
    
    -- Rollback capability
    rollback_command TEXT,
    rolled_back_at TIMESTAMP,
    rolled_back_by INTEGER REFERENCES users(user_id)
);

CREATE INDEX idx_remediation_scan ON remediation_history(scan_id);
CREATE INDEX idx_remediation_hostname ON remediation_history(hostname);
CREATE INDEX idx_remediation_executed ON remediation_history(executed_at DESC);
CREATE INDEX idx_remediation_status ON remediation_history(status);

-- =====================================================
-- TABLE: configurations
-- System configuration versioning
-- =====================================================
CREATE TABLE configurations (
    config_id SERIAL PRIMARY KEY,
    config_version VARCHAR(50) NOT NULL,
    config_data JSONB NOT NULL,
    is_active BOOLEAN DEFAULT false,
    created_by INTEGER REFERENCES users(user_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    activated_at TIMESTAMP,
    description TEXT
);

CREATE INDEX idx_config_active ON configurations(is_active) WHERE is_active = true;
CREATE INDEX idx_config_version ON configurations(config_version);

-- =====================================================
-- TABLE: scheduled_scans
-- Scheduled scan jobs configuration
-- =====================================================
CREATE TABLE scheduled_scans (
    schedule_id SERIAL PRIMARY KEY,
    schedule_name VARCHAR(255) NOT NULL,
    target_list TEXT[], -- Array of hostnames or user IDs
    target_csv_path TEXT,
    
    -- Scheduling
    cron_expression VARCHAR(100), -- '0 0 * * *' for daily at midnight
    enabled BOOLEAN DEFAULT true,
    
    -- Scan configuration
    scan_type VARCHAR(50) DEFAULT 'full',
    topology_filter VARCHAR(50), -- 'HO', 'Remote', or NULL for all
    
    created_by INTEGER REFERENCES users(user_id),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_run TIMESTAMP,
    next_run TIMESTAMP
);

CREATE INDEX idx_schedule_enabled ON scheduled_scans(enabled) WHERE enabled = true;
CREATE INDEX idx_schedule_next_run ON scheduled_scans(next_run);

-- =====================================================
-- MATERIALIZED VIEW: dashboard_statistics
-- Pre-computed dashboard stats for performance
-- =====================================================
CREATE MATERIALIZED VIEW dashboard_statistics AS
SELECT
    COUNT(*) AS total_scans,
    COUNT(*) FILTER (WHERE scan_timestamp > NOW() - INTERVAL '24 hours') AS scans_last_24h,
    COUNT(*) FILTER (WHERE scan_timestamp > NOW() - INTERVAL '7 days') AS scans_last_7d,
    COUNT(DISTINCT hostname) AS unique_endpoints,
    
    -- Health distribution
    COUNT(*) FILTER (WHERE health_score >= 90) AS excellent_health,
    COUNT(*) FILTER (WHERE health_score BETWEEN 70 AND 89) AS good_health,
    COUNT(*) FILTER (WHERE health_score BETWEEN 50 AND 69) AS fair_health,
    COUNT(*) FILTER (WHERE health_score < 50) AS poor_health,
    
    -- Status counts
    COUNT(*) FILTER (WHERE status = 'completed') AS completed_scans,
    COUNT(*) FILTER (WHERE status = 'failed') AS failed_scans,
    COUNT(*) FILTER (WHERE status = 'in_progress') AS in_progress_scans,
    
    -- Critical alerts
    SUM(critical_count) AS total_critical_alerts,
    SUM(warning_count) AS total_warnings,
    
    -- Performance metrics
    AVG(execution_time_seconds) AS avg_scan_time,
    MAX(scan_timestamp) AS last_scan_time
FROM scan_results
WHERE scan_timestamp > NOW() - INTERVAL '30 days';

-- Create index for materialized view refresh
CREATE UNIQUE INDEX ON dashboard_statistics ((true));

-- =====================================================
-- FUNCTIONS & TRIGGERS
-- =====================================================

-- Function: Update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger: Auto-update users.updated_at
CREATE TRIGGER trigger_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Function: Refresh dashboard statistics (called by scheduled job)
CREATE OR REPLACE FUNCTION refresh_dashboard_stats()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY dashboard_statistics;
END;
$$ LANGUAGE plpgsql;

-- Function: Auto-create monthly partitions
CREATE OR REPLACE FUNCTION create_monthly_partition(target_date DATE)
RETURNS void AS $$
DECLARE
    partition_name TEXT;
    start_date DATE;
    end_date DATE;
BEGIN
    start_date := DATE_TRUNC('month', target_date);
    end_date := start_date + INTERVAL '1 month';
    partition_name := 'scan_results_' || TO_CHAR(start_date, 'YYYY_MM');
    
    EXECUTE format('CREATE TABLE IF NOT EXISTS %I PARTITION OF scan_results FOR VALUES FROM (%L) TO (%L)',
                   partition_name, start_date, end_date);
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- INITIAL DATA
-- =====================================================

-- Insert default admin user (password auth via AD, this is just for tracking)
INSERT INTO users (username, domain, display_name, role, is_active) 
VALUES 
    ('Administrator', 'CORP', 'System Administrator', 'admin', true),
    ('ems_service', 'CORP', 'EMS Service Account', 'admin', true)
ON CONFLICT (username) DO NOTHING;

-- Insert default configuration
INSERT INTO configurations (config_version, config_data, is_active, description)
VALUES (
    '1.0',
    '{
        "Topology": {
            "HOSubnets": ["10.192.10.0/23", "10.192.15.0/24"],
            "RemoteSubnets": ["10.192.13.0/24", "10.192.20.0/24"],
            "HOThrottleLimit": 40,
            "RemoteThrottleLimit": 4
        },
        "Security": {
            "AdminGroup": "EMS_Admins",
            "EnableRemediation": true,
            "RequireConfirmation": true
        },
        "Database": {
            "Provider": "PostgreSQL",
            "Host": "localhost",
            "Port": 5432,
            "DatabaseName": "ems_production"
        }
    }'::jsonb,
    true,
    'Initial production configuration'
);

-- =====================================================
-- GRANTS & PERMISSIONS
-- =====================================================

-- Create EMS application role
CREATE ROLE ems_app_role;

-- Grant permissions
GRANT CONNECT ON DATABASE ems_production TO ems_app_role;
GRANT USAGE ON SCHEMA public TO ems_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO ems_app_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO ems_app_role;

-- Create service account user (replace with your actual service account)
-- CREATE USER ems_service WITH PASSWORD 'CHANGE_ME_SECURE_PASSWORD';
-- GRANT ems_app_role TO ems_service;

-- =====================================================
-- MAINTENANCE TASKS
-- =====================================================

-- Schedule: Refresh materialized view every 5 minutes (requires pg_cron extension)
-- SELECT cron.schedule('refresh-dashboard-stats', '*/5 * * * *', 'SELECT refresh_dashboard_stats()');

-- Schedule: Auto-create next month's partition (first day of each month)
-- SELECT cron.schedule('create-next-partition', '0 0 1 * *', 
--     'SELECT create_monthly_partition(CURRENT_DATE + INTERVAL ''1 month'')');

-- =====================================================
-- SCHEMA VERSION
-- =====================================================
CREATE TABLE schema_version (
    version VARCHAR(20) PRIMARY KEY,
    applied_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    description TEXT
);

INSERT INTO schema_version (version, description) 
VALUES ('1.0.0', 'Initial schema creation with partitioned scan_results and diagnostic tracking');

-- =====================================================
-- END OF SCHEMA
-- =====================================================
