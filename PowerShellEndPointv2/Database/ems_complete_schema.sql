-- =============================================================================
-- EMS Complete Database Schema (Consolidated)
-- Version: 4.0
-- Generated: 2026-05-11
-- Description: Single idempotent DDL file for the entire EMS database.
--              Run this file to create or upgrade the database from scratch.
--              Uses IF NOT EXISTS throughout for safe re-execution.
-- =============================================================================

-- ─── Core Tables ────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS computers (
    computer_id     SERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL UNIQUE,
    ip_address      INET,
    mac_address     VARCHAR(17),
    operating_system VARCHAR(500),
    os_version      VARCHAR(100),
    os_build        VARCHAR(50),
    domain          VARCHAR(255),
    is_domain_joined BOOLEAN DEFAULT false,
    computer_type   VARCHAR(50) DEFAULT 'Desktop',
    manufacturer    VARCHAR(255),
    model           VARCHAR(255),
    serial_number   VARCHAR(255),
    is_archived     BOOLEAN DEFAULT false,
    archived_at     TIMESTAMP,
    archived_by     VARCHAR(100),
    archive_reason  TEXT,
    first_seen      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS scans (
    scan_id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    target            VARCHAR(255) NOT NULL,
    status            VARCHAR(50) NOT NULL DEFAULT 'queued'
                      CHECK (status IN ('queued','running','completed','failed','archived')),
    health_score      INTEGER,
    execution_time_sec INTEGER,
    error_message     TEXT,
    started_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at      TIMESTAMP,
    is_archived       BOOLEAN DEFAULT false,
    archived_at       TIMESTAMP,
    archived_by       VARCHAR(100),
    archive_reason    TEXT
);

CREATE TABLE IF NOT EXISTS scan_inventory_results (
    scan_id         UUID PRIMARY KEY,
    computer_name   VARCHAR(255),
    manufacturer    VARCHAR(255),
    model           VARCHAR(255),
    os_edition      VARCHAR(500),
    os_version      VARCHAR(100),
    os_build        VARCHAR(50),
    lastchecked     TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ─── Scan Trace (Observability) ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS scan_trace (
    trace_id    BIGSERIAL PRIMARY KEY,
    scan_id     UUID NOT NULL,
    step_name   VARCHAR(100) NOT NULL,
    module_name VARCHAR(100) NOT NULL,
    status      VARCHAR(50) DEFAULT 'Info' CHECK (status IN ('Info','Success','Warning','Error')),
    message     TEXT,
    timestamp   TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_scan_trace_scan_id ON scan_trace(scan_id);
CREATE INDEX IF NOT EXISTS idx_scan_trace_timestamp ON scan_trace(timestamp DESC);

-- ─── Granular Metric Tables ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS metric_cpu_usage (
    id              BIGSERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL,
    processor_name  VARCHAR(500),
    core_count      INTEGER,
    usage_percent   NUMERIC(5,2),
    max_clock_mhz   INTEGER,
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_memory (
    id                  BIGSERIAL PRIMARY KEY,
    computer_name       VARCHAR(255) NOT NULL,
    total_gb            NUMERIC(10,2),
    used_gb             NUMERIC(10,2),
    free_gb             NUMERIC(10,2),
    usage_percent       NUMERIC(5,2),
    page_file_total_gb  NUMERIC(10,2),
    page_file_used_gb   NUMERIC(10,2),
    timestamp           TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_disk_space (
    id              BIGSERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL,
    drive_letter    VARCHAR(10),
    volume_label    VARCHAR(255),
    total_gb        NUMERIC(10,2),
    used_gb         NUMERIC(10,2),
    free_gb         NUMERIC(10,2),
    usage_percent   NUMERIC(5,2),
    file_system     VARCHAR(50),
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_network_adapters (
    id                  BIGSERIAL PRIMARY KEY,
    computer_name       VARCHAR(255) NOT NULL,
    adapter_name        VARCHAR(500),
    ip_address          VARCHAR(45),
    subnet_mask         VARCHAR(45),
    default_gateway     VARCHAR(45),
    mac_address         VARCHAR(17),
    dns_servers         TEXT,
    dhcp_enabled        BOOLEAN,
    connection_status   VARCHAR(100),
    speed_mbps          INTEGER,
    timestamp           TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_services (
    id              BIGSERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL,
    service_name    VARCHAR(500),
    display_name    VARCHAR(500),
    status          VARCHAR(50),
    start_type      VARCHAR(50),
    account         VARCHAR(255),
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_windows_updates (
    id              BIGSERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL,
    kb_id           VARCHAR(50),
    title           VARCHAR(1000),
    installed_on    TIMESTAMP,
    update_type     VARCHAR(100),
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_bitlocker (
    id                  BIGSERIAL PRIMARY KEY,
    computer_name       VARCHAR(255) NOT NULL,
    drive_letter        VARCHAR(10),
    protection_status   VARCHAR(100),
    encryption_method   VARCHAR(100),
    volume_type         VARCHAR(100),
    lock_status         VARCHAR(100),
    timestamp           TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_antivirus (
    id                      BIGSERIAL PRIMARY KEY,
    computer_name           VARCHAR(255) NOT NULL,
    product_name            VARCHAR(255),
    real_time_protection    BOOLEAN,
    definition_status       VARCHAR(100),
    definition_date         TIMESTAMP,
    engine_version          VARCHAR(50),
    last_scan_time          TIMESTAMP,
    last_scan_type          VARCHAR(50),
    timestamp               TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_firewall (
    id              BIGSERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL,
    profile_name    VARCHAR(100),
    enabled         BOOLEAN,
    default_inbound VARCHAR(50),
    default_outbound VARCHAR(50),
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_installed_software (
    id              BIGSERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL,
    software_name   VARCHAR(1000),
    version         VARCHAR(255),
    publisher       VARCHAR(500),
    install_date    VARCHAR(50),
    install_location TEXT,
    is_blacklisted  BOOLEAN DEFAULT false,
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_user_accounts (
    id              BIGSERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL,
    username        VARCHAR(255),
    full_name       VARCHAR(500),
    description     TEXT,
    enabled         BOOLEAN,
    is_admin        BOOLEAN DEFAULT false,
    last_logon      TIMESTAMP,
    password_expires BOOLEAN,
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_processes (
    id              BIGSERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL,
    process_name    VARCHAR(500),
    pid             INTEGER,
    cpu_percent     NUMERIC(5,2),
    memory_mb       NUMERIC(10,2),
    start_time      TIMESTAMP,
    path            TEXT,
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_startup_programs (
    id              BIGSERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL,
    program_name    VARCHAR(500),
    command         TEXT,
    location        VARCHAR(500),
    user_context    VARCHAR(255),
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_scheduled_tasks (
    id              BIGSERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL,
    task_name       VARCHAR(500),
    task_path       VARCHAR(500),
    state           VARCHAR(50),
    last_run_time   TIMESTAMP,
    next_run_time   TIMESTAMP,
    last_result     INTEGER,
    author          VARCHAR(255),
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_browser_extensions (
    id              BIGSERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL,
    browser         VARCHAR(100),
    extension_name  VARCHAR(500),
    extension_id    VARCHAR(255),
    version         VARCHAR(100),
    enabled         BOOLEAN DEFAULT true,
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_system_uptime (
    id              BIGSERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL,
    last_boot_time  TIMESTAMP,
    uptime_days     NUMERIC(10,2),
    uptime_hours    NUMERIC(10,2),
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_login_history (
    id              BIGSERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL,
    username        VARCHAR(255),
    logon_type      VARCHAR(50),
    logon_time      TIMESTAMP,
    session_id      INTEGER,
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS metric_reboot_tracking (
    id              BIGSERIAL PRIMARY KEY,
    computer_name   VARCHAR(255) NOT NULL,
    last_boot_time  TIMESTAMP,
    uptime_days     NUMERIC(10,2),
    uptime_status   VARCHAR(50) DEFAULT 'Normal',
    notified        BOOLEAN DEFAULT false,
    timestamp       TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ─── Authentication & Users ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS users (
    user_id         SERIAL PRIMARY KEY,
    username        VARCHAR(255) NOT NULL UNIQUE,
    display_name    VARCHAR(500),
    email           VARCHAR(500),
    role            VARCHAR(50) DEFAULT 'viewer',
    is_active       BOOLEAN DEFAULT true,
    password_hash   TEXT,
    auth_provider   VARCHAR(50) DEFAULT 'Standalone',
    last_login      TIMESTAMP,
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ─── Feature Toggles ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS feature_toggles (
    feature_key     VARCHAR(100) PRIMARY KEY,
    feature_name    VARCHAR(255) NOT NULL,
    description     TEXT,
    enabled         BOOLEAN DEFAULT false,
    category        VARCHAR(100) DEFAULT 'General',
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Insert default features if they don't exist
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
ON CONFLICT (feature_key) DO UPDATE SET 
    feature_name = EXCLUDED.feature_name,
    description = EXCLUDED.description,
    category = EXCLUDED.category;


-- ─── Audit & Compliance ──────────────────────────────────────────────────────

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
CREATE INDEX IF NOT EXISTS idx_audit_api_ts ON audit_api_requests(timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_audit_api_user ON audit_api_requests(username);

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

-- ─── Security: Encrypted Credentials & Environment Config ────────────────────

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

-- ─── Performance Indexes ─────────────────────────────────────────────────────

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='metric_installed_software' AND column_name='is_blacklisted') THEN ALTER TABLE metric_installed_software ADD COLUMN is_blacklisted BOOLEAN DEFAULT false; END IF; END $$;

CREATE INDEX IF NOT EXISTS idx_scans_target ON scans(target);
CREATE INDEX IF NOT EXISTS idx_scans_status ON scans(status);
CREATE INDEX IF NOT EXISTS idx_scans_started ON scans(started_at DESC);
CREATE INDEX IF NOT EXISTS idx_computers_name ON computers(computer_name);
CREATE INDEX IF NOT EXISTS idx_cpu_computer ON metric_cpu_usage(computer_name, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_mem_computer ON metric_memory(computer_name, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_disk_computer ON metric_disk_space(computer_name, timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_sw_computer ON metric_installed_software(computer_name);

CREATE INDEX IF NOT EXISTS idx_sw_blacklist ON metric_installed_software(is_blacklisted) WHERE is_blacklisted = true;
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_reboot_computer ON metric_reboot_tracking(computer_name, timestamp DESC);

-- ─── Schema Version ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS schema_version (
    version_id  SERIAL PRIMARY KEY,
    version     VARCHAR(50) NOT NULL,
    description TEXT,
    applied_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO schema_version (version, description)
VALUES ('4.0.0', 'Consolidated schema — scanning, metrics, auth, audit, credentials, env config')
ON CONFLICT DO NOTHING;
