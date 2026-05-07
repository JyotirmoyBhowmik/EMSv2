-- =====================================================
-- EMS v3.0 — Comprehensive Audit & Feature Toggle Schema
-- =====================================================

-- 1. API Request Audit Log
CREATE TABLE IF NOT EXISTS audit_api_requests (
    request_id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT NOW(),
    username VARCHAR(255),
    method VARCHAR(10) NOT NULL,
    path VARCHAR(500) NOT NULL,
    status_code INTEGER,
    response_time_ms INTEGER,
    ip_address INET,
    user_agent TEXT,
    request_body_preview TEXT,
    error_message TEXT
);
CREATE INDEX IF NOT EXISTS idx_api_audit_ts ON audit_api_requests(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_api_audit_user ON audit_api_requests(username);
CREATE INDEX IF NOT EXISTS idx_api_audit_path ON audit_api_requests(path);

-- 2. Authentication Event Audit
CREATE TABLE IF NOT EXISTS audit_auth_events (
    event_id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT NOW(),
    username VARCHAR(255) NOT NULL,
    event_type VARCHAR(50) NOT NULL, -- 'login_success','login_failed','logout','lockout','password_change','session_expired'
    provider VARCHAR(50),            -- 'ActiveDirectory','Standalone','LDAP'
    ip_address INET,
    user_agent TEXT,
    failure_reason TEXT,
    risk_level VARCHAR(20) DEFAULT 'Low' CHECK (risk_level IN ('Low','Medium','High','Critical'))
);
CREATE INDEX IF NOT EXISTS idx_auth_audit_ts ON audit_auth_events(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_auth_audit_user ON audit_auth_events(username);
CREATE INDEX IF NOT EXISTS idx_auth_audit_type ON audit_auth_events(event_type);

-- 3. Configuration Change Audit
CREATE TABLE IF NOT EXISTS audit_config_changes (
    change_id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT NOW(),
    changed_by VARCHAR(255) NOT NULL,
    config_section VARCHAR(100) NOT NULL,
    config_key VARCHAR(255) NOT NULL,
    old_value TEXT,
    new_value TEXT,
    change_reason TEXT
);
CREATE INDEX IF NOT EXISTS idx_config_audit_ts ON audit_config_changes(timestamp DESC);

-- 4. Data Access Audit
CREATE TABLE IF NOT EXISTS audit_data_access (
    access_id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT NOW(),
    username VARCHAR(255),
    action VARCHAR(50) NOT NULL,  -- 'view_scan','export_csv','view_computer','view_audit'
    resource_type VARCHAR(100),
    resource_id VARCHAR(255),
    ip_address INET
);
CREATE INDEX IF NOT EXISTS idx_data_access_ts ON audit_data_access(timestamp DESC);

-- 5. Feature Toggles
CREATE TABLE IF NOT EXISTS feature_toggles (
    feature_key VARCHAR(100) PRIMARY KEY,
    feature_name VARCHAR(255) NOT NULL,
    description TEXT,
    enabled BOOLEAN DEFAULT true,
    category VARCHAR(50) NOT NULL, -- 'Scanning','Security','Reporting','Notifications','Administration'
    changed_by VARCHAR(255),
    changed_at TIMESTAMP DEFAULT NOW()
);

-- Insert default feature toggles
INSERT INTO feature_toggles (feature_key, feature_name, description, enabled, category) VALUES
('scan_single',         'Single Endpoint Scan',        'Allow scanning individual endpoints',                    true,  'Scanning'),
('scan_bulk',           'Bulk/CIDR Scan',              'Allow bulk scanning with CIDR range expansion',          true,  'Scanning'),
('scan_scheduled',      'Scheduled Scans',             'Enable cron-based recurring scans',                      false, 'Scanning'),
('scan_auto_discovery', 'Auto-Discovery',              'Discover endpoints from Active Directory automatically',  false, 'Scanning'),
('security_bitlocker',  'BitLocker Check',             'Check BitLocker encryption status on endpoints',          true,  'Security'),
('security_firewall',   'Firewall Check',              'Validate Windows Firewall profiles',                     true,  'Security'),
('security_antivirus',  'Antivirus Check',             'Check antivirus status and definitions',                 true,  'Security'),
('security_updates',    'Windows Update Check',        'Check pending Windows Updates',                          true,  'Security'),
('remediation_service', 'Service Remediation',         'Allow restarting critical services remotely',             true,  'Security'),
('remediation_reboot',  'Remote Reboot',               'Allow sending reboot commands to endpoints',             false, 'Security'),
('report_csv_export',   'CSV Export',                  'Allow exporting scan results to CSV',                    true,  'Reporting'),
('report_compliance',   'Compliance Report',           'Generate compliance classification reports',             true,  'Reporting'),
('report_scheduled',    'Scheduled Reports',           'Send automated reports via email',                       false, 'Reporting'),
('notify_smtp',         'SMTP Notifications',          'Send email notifications for alerts and reboots',        false, 'Notifications'),
('notify_reboot_mail',  'Reboot Notification Mail',    'Send custom reboot reminder emails to users',            false, 'Notifications'),
('admin_user_mgmt',     'User Management',             'Enable user lifecycle management (create/edit/deactivate)', true, 'Administration'),
('admin_audit_log',     'Audit Log Viewer',            'View comprehensive audit logs in the admin console',     true,  'Administration'),
('admin_connector_health','Connector Health',          'Monitor health of system connectors (DB, AD, SMTP)',     true,  'Administration'),
('endpoint_lifecycle',  'Endpoint Lifecycle',          'Track endpoint lifecycle states and tagging',             true,  'Administration'),
('endpoint_reboot_mon', 'Reboot Monitoring',           'Track last restart times and uptime for all endpoints',  true,  'Administration')
ON CONFLICT (feature_key) DO NOTHING;

-- 6. Feature Toggle Change History
CREATE TABLE IF NOT EXISTS audit_feature_toggles (
    change_id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT NOW(),
    feature_key VARCHAR(100) REFERENCES feature_toggles(feature_key),
    old_value BOOLEAN,
    new_value BOOLEAN,
    changed_by VARCHAR(255)
);

-- 7. User Lifecycle Events
CREATE TABLE IF NOT EXISTS user_lifecycle_events (
    event_id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT NOW(),
    user_id INTEGER,
    username VARCHAR(255) NOT NULL,
    event_type VARCHAR(50) NOT NULL, -- 'created','role_changed','deactivated','reactivated','locked','unlocked'
    old_value TEXT,
    new_value TEXT,
    performed_by VARCHAR(255),
    notes TEXT
);
CREATE INDEX IF NOT EXISTS idx_user_lifecycle_ts ON user_lifecycle_events(timestamp DESC);

-- 8. User Sessions
CREATE TABLE IF NOT EXISTS user_sessions (
    session_id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id INTEGER REFERENCES users(user_id),
    username VARCHAR(255),
    login_time TIMESTAMP DEFAULT NOW(),
    last_activity TIMESTAMP DEFAULT NOW(),
    ip_address INET,
    user_agent TEXT,
    is_active BOOLEAN DEFAULT true
);
CREATE INDEX IF NOT EXISTS idx_sessions_active ON user_sessions(is_active) WHERE is_active = true;

-- 9. Endpoint Lifecycle
CREATE TABLE IF NOT EXISTS endpoint_lifecycle_events (
    event_id BIGSERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT NOW(),
    computer_name VARCHAR(255) NOT NULL,
    lifecycle_state VARCHAR(50) NOT NULL, -- 'Discovered','Provisioned','Active','Maintenance','Decommissioned'
    previous_state VARCHAR(50),
    changed_by VARCHAR(255),
    notes TEXT
);
CREATE INDEX IF NOT EXISTS idx_endpoint_lifecycle_ts ON endpoint_lifecycle_events(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_endpoint_lifecycle_computer ON endpoint_lifecycle_events(computer_name);

-- 10. Endpoint Tags
CREATE TABLE IF NOT EXISTS endpoint_tags (
    tag_id SERIAL PRIMARY KEY,
    computer_name VARCHAR(255) NOT NULL,
    tag_key VARCHAR(100) NOT NULL,
    tag_value VARCHAR(255),
    created_by VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW(),
    UNIQUE(computer_name, tag_key)
);

-- 11. Endpoint Notes
CREATE TABLE IF NOT EXISTS endpoint_notes (
    note_id BIGSERIAL PRIMARY KEY,
    computer_name VARCHAR(255) NOT NULL,
    note_text TEXT NOT NULL,
    created_by VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_endpoint_notes_computer ON endpoint_notes(computer_name);

-- 12. Reboot Tracking
CREATE TABLE IF NOT EXISTS metric_reboot_tracking (
    computer_name VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP DEFAULT NOW(),
    last_boot_time TIMESTAMP,
    uptime_days INTEGER,
    uptime_status VARCHAR(20), -- 'Normal','Warning','Critical'
    notified BOOLEAN DEFAULT false,
    notified_at TIMESTAMP,
    PRIMARY KEY (computer_name, timestamp)
);
CREATE INDEX IF NOT EXISTS idx_reboot_status ON metric_reboot_tracking(uptime_status);

-- 13. Mail Log
CREATE TABLE IF NOT EXISTS mail_log (
    mail_id BIGSERIAL PRIMARY KEY,
    sent_at TIMESTAMP DEFAULT NOW(),
    sent_by VARCHAR(255),
    recipient_email VARCHAR(255),
    recipient_name VARCHAR(255),
    subject VARCHAR(500),
    template_name VARCHAR(100),
    computer_name VARCHAR(255),
    status VARCHAR(50), -- 'sent','failed','queued'
    error_message TEXT
);

-- Schema v3.0 complete!
