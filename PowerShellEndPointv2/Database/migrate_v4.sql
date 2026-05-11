-- =============================================================================
-- EMS v4.0 Quick Fix Migration
-- Run this against your production database to add missing tables and seed data.
-- This is safe to run multiple times (idempotent).
-- =============================================================================

-- 1. Add missing columns to scans if needed (production uses is_deleted, not is_archived)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='scans' AND column_name='is_deleted') THEN
        ALTER TABLE scans ADD COLUMN is_deleted BOOLEAN DEFAULT false;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='scans' AND column_name='deleted_at') THEN
        ALTER TABLE scans ADD COLUMN deleted_at TIMESTAMP;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='scans' AND column_name='deleted_by') THEN
        ALTER TABLE scans ADD COLUMN deleted_by VARCHAR(100);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='scans' AND column_name='delete_reason') THEN
        ALTER TABLE scans ADD COLUMN delete_reason TEXT;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='scans' AND column_name='critical_alerts') THEN
        ALTER TABLE scans ADD COLUMN critical_alerts INTEGER DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='scans' AND column_name='warning_alerts') THEN
        ALTER TABLE scans ADD COLUMN warning_alerts INTEGER DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='scans' AND column_name='info_alerts') THEN
        ALTER TABLE scans ADD COLUMN info_alerts INTEGER DEFAULT 0;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='scans' AND column_name='result_json') THEN
        ALTER TABLE scans ADD COLUMN result_json TEXT;
    END IF;
END $$;

-- 2. Add missing columns to computers if needed
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='is_active') THEN
        ALTER TABLE computers ADD COLUMN is_active BOOLEAN DEFAULT true;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='last_seen') THEN
        ALTER TABLE computers ADD COLUMN last_seen TIMESTAMP;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='location') THEN
        ALTER TABLE computers ADD COLUMN location VARCHAR(255);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='department') THEN
        ALTER TABLE computers ADD COLUMN department VARCHAR(255);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='asset_tag') THEN
        ALTER TABLE computers ADD COLUMN asset_tag VARCHAR(255);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='notes') THEN
        ALTER TABLE computers ADD COLUMN notes TEXT;
    END IF;
END $$;

-- 3. Create scan_trace table if missing
CREATE TABLE IF NOT EXISTS scan_trace (
    trace_id    BIGSERIAL PRIMARY KEY,
    scan_id     UUID NOT NULL,
    step_name   VARCHAR(100) NOT NULL,
    module_name VARCHAR(100) NOT NULL,
    status      VARCHAR(50) DEFAULT 'Info',
    message     TEXT,
    timestamp   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_scan_trace_scan_id ON scan_trace(scan_id);

-- 4. Create scan_actions_audit table if missing (used by archive/restore)
CREATE TABLE IF NOT EXISTS scan_actions_audit (
    audit_id        BIGSERIAL PRIMARY KEY,
    scan_id         UUID NOT NULL,
    action_type     VARCHAR(50),
    performed_by    VARCHAR(255),
    reason          TEXT,
    old_status      VARCHAR(50),
    target          VARCHAR(255),
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 5. Create feature_toggles and seed data
CREATE TABLE IF NOT EXISTS feature_toggles (
    feature_key     VARCHAR(100) PRIMARY KEY,
    feature_name    VARCHAR(255) NOT NULL,
    description     TEXT,
    enabled         BOOLEAN DEFAULT false,
    category        VARCHAR(100) DEFAULT 'General',
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO feature_toggles (feature_key, feature_name, description, enabled, category)
VALUES
    ('auto_scan',        'Auto Scan',              'Automatically scan endpoints on a schedule',              false, 'Scanning'),
    ('bulk_scan',        'Bulk Scan',              'Enable scanning multiple endpoints at once',              true,  'Scanning'),
    ('scan_scheduling',  'Scan Scheduling',        'Allow scheduling scans at specific times',                false, 'Scanning'),
    ('deep_scan',        'Deep Scan',              'Enable extended collector modules for thorough analysis',  false, 'Scanning'),
    ('realtime_alerts',  'Real-time Alerts',       'Push notifications for critical events',                  false, 'Notifications'),
    ('email_reports',    'Email Reports',          'Send scheduled compliance reports via email',              false, 'Notifications'),
    ('slack_integration', 'Slack Integration',     'Send alerts and summaries to Slack channels',              false, 'Notifications'),
    ('ad_integration',   'AD Integration',         'Active Directory authentication and group sync',          true,  'Authentication'),
    ('mfa_enforcement',  'MFA Enforcement',        'Require multi-factor authentication for admin access',    false, 'Security'),
    ('api_rate_limiting', 'API Rate Limiting',     'Limit API requests per IP address',                       true,  'Security'),
    ('audit_logging',    'Audit Logging',          'Track all API requests and admin actions',                 true,  'Security'),
    ('ip_allowlisting',  'IP Allowlisting',        'Restrict API access to approved IP ranges',               false, 'Security'),
    ('remediation',      'Remediation',            'Allow automated remediation actions on endpoints',        false, 'Administration'),
    ('data_retention',   'Data Retention Policy',  'Automatically purge old scan data after N days',          false, 'Administration'),
    ('export_reports',   'Export Reports',          'Enable CSV/PDF export of scan results and compliance',    true,  'Reporting'),
    ('compliance_dashboard', 'Compliance Dashboard', 'Show compliance status and trend analysis',             true,  'Reporting')
ON CONFLICT (feature_key) DO NOTHING;

-- 6. Create security tables
CREATE TABLE IF NOT EXISTS service_credentials (
    credential_id       SERIAL PRIMARY KEY,
    credential_type     VARCHAR(50) NOT NULL UNIQUE,
    username            VARCHAR(255),
    encrypted_password  TEXT NOT NULL,
    encryption_method   VARCHAR(50) DEFAULT 'DPAPI',
    created_by          VARCHAR(100),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS environment_config (
    config_key          VARCHAR(100) PRIMARY KEY,
    encrypted_value     TEXT NOT NULL,
    is_sensitive        BOOLEAN DEFAULT true,
    description         TEXT,
    updated_by          VARCHAR(100),
    updated_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 7. Create audit tables if missing
CREATE TABLE IF NOT EXISTS audit_api_requests (
    request_id      BIGSERIAL PRIMARY KEY,
    method          VARCHAR(10),
    path            TEXT,
    username        VARCHAR(255),
    ip_address      INET,
    status_code     INTEGER,
    response_time_ms NUMERIC(10,2),
    error_message   TEXT,
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS audit_auth_events (
    event_id        BIGSERIAL PRIMARY KEY,
    username        VARCHAR(255),
    event_type      VARCHAR(50),
    provider        VARCHAR(100),
    risk_level      VARCHAR(50) DEFAULT 'Low',
    ip_address      INET,
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS audit_config_changes (
    change_id       BIGSERIAL PRIMARY KEY,
    changed_by      VARCHAR(255),
    config_section  VARCHAR(100),
    config_key      VARCHAR(255),
    old_value       TEXT,
    new_value       TEXT,
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS audit_feature_toggles (
    toggle_id       BIGSERIAL PRIMARY KEY,
    feature_key     VARCHAR(100),
    old_value       BOOLEAN,
    new_value       BOOLEAN,
    changed_by      VARCHAR(255),
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Done
SELECT 'Migration complete! Feature toggles seeded: ' || COUNT(*)::text FROM feature_toggles;
