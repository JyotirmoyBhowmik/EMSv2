-- =====================================================
-- EMS Production Patch: v3.0 Schema Alignment
-- Purpose: Fix missing 'is_deleted' columns and compliance views
-- =====================================================

-- 1. Hardening 'scans' table
-- If table doesn't exist, create it (UUID based for v3 compatibility)
CREATE TABLE IF NOT EXISTS scans (
    scan_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    target VARCHAR(255) NOT NULL,
    ip_address INET,
    status VARCHAR(50) DEFAULT 'queued',
    health_score INTEGER,
    critical_alerts INTEGER DEFAULT 0,
    warning_alerts INTEGER DEFAULT 0,
    info_alerts INTEGER DEFAULT 0,
    execution_time_sec NUMERIC(10,2),
    result_json JSONB,
    error_message TEXT,
    started_at TIMESTAMP DEFAULT NOW(),
    completed_at TIMESTAMP,
    scan_timestamp TIMESTAMP DEFAULT NOW()
);

-- Add soft-delete and audit columns if missing
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='scans' AND column_name='is_deleted') THEN
        ALTER TABLE scans ADD COLUMN is_deleted BOOLEAN DEFAULT false;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='scans' AND column_name='deleted_at') THEN
        ALTER TABLE scans ADD COLUMN deleted_at TIMESTAMP;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='scans' AND column_name='deleted_by') THEN
        ALTER TABLE scans ADD COLUMN deleted_by VARCHAR(255);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='scans' AND column_name='delete_reason') THEN
        ALTER TABLE scans ADD COLUMN delete_reason TEXT;
    END IF;
END $$;

-- 2. Create 'scan_inventory_results' for detailed endpoint metadata
CREATE TABLE IF NOT EXISTS scan_inventory_results (
    scan_id UUID PRIMARY KEY REFERENCES scans(scan_id) ON DELETE CASCADE,
    computer_name VARCHAR(255),
    manufacturer VARCHAR(100),
    model VARCHAR(100),
    domain_user VARCHAR(255),
    screensaver_policy VARCHAR(100),
    restrict_software_installation_policy VARCHAR(100),
    lastpolicy_checked TIMESTAMP,
    enabled_local_user_account BOOLEAN,
    all_security_kbs TEXT,
    all_security_kbs_installedon TIMESTAMP,
    os_edition VARCHAR(100),
    os_version VARCHAR(100),
    os_build VARCHAR(100),
    symantec_management_agent VARCHAR(100),
    readonly_usb VARCHAR(100),
    poweron_password VARCHAR(100),
    admin_password VARCHAR(100),
    timesync_with_ntp VARCHAR(100),
    lastchecked TIMESTAMP,
    comments TEXT
);

-- 3. Create 'v_ems_latest_compliance_classified' view for Dashboard
CREATE OR REPLACE VIEW v_ems_latest_compliance_classified AS
WITH latest_scans AS (
    SELECT DISTINCT ON (target) 
        scan_id, target, status, health_score, completed_at, result_json
    FROM scans
    WHERE COALESCE(is_deleted, false) = false
    ORDER BY target, completed_at DESC
)
SELECT 
    ls.scan_id,
    ls.target,
    ls.status,
    ls.health_score,
    ls.completed_at,
    ir.manufacturer,
    ir.model,
    ir.poweron_password,
    ir.admin_password,
    ir.lastchecked,
    CASE 
        WHEN ls.health_score >= 90 THEN 'Compliant'
        WHEN ls.health_score >= 70 THEN 'Partial Compliant'
        ELSE 'Non-Compliant'
    END AS compliance_bucket,
    COALESCE(ls.result_json->>'compliance_issues', '') AS compliance_issues,
    COALESCE(ls.result_json->>'compliance_warnings', '') AS compliance_warnings
FROM latest_scans ls
LEFT JOIN scan_inventory_results ir ON ls.scan_id = ir.scan_id;

-- 4. Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON scans TO ems_app_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON scan_inventory_results TO ems_app_role;
GRANT SELECT ON v_ems_latest_compliance_classified TO ems_app_role;

-- Grant to ems_service directly as well
GRANT SELECT, INSERT, UPDATE, DELETE ON scans TO ems_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON scan_inventory_results TO ems_service;
GRANT SELECT ON v_ems_latest_compliance_classified TO ems_service;

COMMENT ON VIEW v_ems_latest_compliance_classified IS 'Classifies the most recent scan result for each target into compliance buckets.';
