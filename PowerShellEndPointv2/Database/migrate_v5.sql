-- =============================================================================
-- EMS v5.0 Database Migration (REVISED)
-- =============================================================================

-- ─── 1. Fix Permissions (Run as Superuser) ──────────────────────────────────
-- If running as postgres, ensure ems_service has rights
-- GRANT ALL PRIVILEGES ON TABLE computers TO ems_service;
-- GRANT ALL PRIVILEGES ON TABLE users TO ems_service;

-- ─── 2. Extend computers table ──────────────────────────────────────────────
DO $$ BEGIN
  -- Hardware extensions
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='asset_tag')       THEN ALTER TABLE computers ADD COLUMN asset_tag VARCHAR(255); END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='bios_version')    THEN ALTER TABLE computers ADD COLUMN bios_version VARCHAR(255); END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='bios_date')       THEN ALTER TABLE computers ADD COLUMN bios_date DATE; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='secure_boot')     THEN ALTER TABLE computers ADD COLUMN secure_boot BOOLEAN; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='tpm_version')     THEN ALTER TABLE computers ADD COLUMN tpm_version VARCHAR(50); END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='tpm_enabled')     THEN ALTER TABLE computers ADD COLUMN tpm_enabled BOOLEAN; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='bitlocker_status') THEN ALTER TABLE computers ADD COLUMN bitlocker_status VARCHAR(100); END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='bitlocker_recovery_escrowed') THEN ALTER TABLE computers ADD COLUMN bitlocker_recovery_escrowed BOOLEAN; END IF;

  -- User / session
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='last_logged_on_user') THEN ALTER TABLE computers ADD COLUMN last_logged_on_user VARCHAR(255); END IF;

  -- Uptime / Reboot
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='last_boot_up_time') THEN ALTER TABLE computers ADD COLUMN last_boot_up_time TIMESTAMP; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='uptime_days')      THEN ALTER TABLE computers ADD COLUMN uptime_days NUMERIC(10,2); END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='reboot_compliance') THEN ALTER TABLE computers ADD COLUMN reboot_compliance VARCHAR(20) DEFAULT 'Compliant'; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='pending_reboot')   THEN ALTER TABLE computers ADD COLUMN pending_reboot BOOLEAN DEFAULT false; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='pending_reboot_since') THEN ALTER TABLE computers ADD COLUMN pending_reboot_since TIMESTAMP; END IF;

  -- Network
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='ipv4')  THEN ALTER TABLE computers ADD COLUMN ipv4 INET; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='ipv6')  THEN ALTER TABLE computers ADD COLUMN ipv6 INET; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='macs')  THEN ALTER TABLE computers ADD COLUMN macs TEXT[]; END IF;

  -- Organization
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='site')       THEN ALTER TABLE computers ADD COLUMN site VARCHAR(255); END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='tier')       THEN ALTER TABLE computers ADD COLUMN tier SMALLINT CHECK (tier IN (1,2,3)); END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='owner')      THEN ALTER TABLE computers ADD COLUMN owner VARCHAR(255); END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='tags')       THEN ALTER TABLE computers ADD COLUMN tags TEXT[] DEFAULT '{}'; END IF;

  -- Lifecycle
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='warranty_end')    THEN ALTER TABLE computers ADD COLUMN warranty_end DATE; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='end_of_support')  THEN ALTER TABLE computers ADD COLUMN end_of_support DATE; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='lifecycle_state') THEN ALTER TABLE computers ADD COLUMN lifecycle_state VARCHAR(50) DEFAULT 'Active'; END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='risk_score')      THEN ALTER TABLE computers ADD COLUMN risk_score SMALLINT CHECK (risk_score BETWEEN 0 AND 100); END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='computers' AND column_name='last_change_hash') THEN ALTER TABLE computers ADD COLUMN last_change_hash VARCHAR(64); END IF;
END $$;

-- ─── 3. Core Tables ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS settings (
  setting_id    SERIAL PRIMARY KEY,
  category      VARCHAR(100) NOT NULL,
  setting_key   VARCHAR(200) NOT NULL,
  setting_value TEXT,
  value_type    VARCHAR(20) DEFAULT 'string',
  description   TEXT,
  is_sensitive  BOOLEAN DEFAULT false,
  updated_by    VARCHAR(255),
  updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(category, setting_key)
);

CREATE TABLE IF NOT EXISTS audit_events (
  event_id      BIGSERIAL PRIMARY KEY,
  actor         VARCHAR(255) NOT NULL,
  action        VARCHAR(100) NOT NULL,
  resource_type VARCHAR(100),
  resource_id   VARCHAR(255),
  before_state  JSONB,
  after_state   JSONB,
  ip_address    INET,
  user_agent    TEXT,
  request_id    VARCHAR(64),
  severity      VARCHAR(20) DEFAULT 'Info',
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS compliance_rules (
  rule_id       VARCHAR(100) PRIMARY KEY,
  field         VARCHAR(200) NOT NULL,
  operator      VARCHAR(50) NOT NULL,
  expected_value TEXT,
  severity      VARCHAR(20) DEFAULT 'Medium',
  frameworks    TEXT[] DEFAULT '{}',
  description   TEXT,
  enabled       BOOLEAN DEFAULT true,
  weight        NUMERIC(5,2) DEFAULT 1.0,
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Note: Using computer_id OR id based on table detection
DO $$ 
DECLARE 
    pk_col text;
BEGIN
    SELECT column_name INTO pk_col 
    FROM information_schema.key_column_usage 
    WHERE table_name = 'computers' AND constraint_name LIKE '%pkey%' LIMIT 1;

    EXECUTE 'CREATE TABLE IF NOT EXISTS compliance_exceptions (
      exception_id  SERIAL PRIMARY KEY,
      rule_id       VARCHAR(100) REFERENCES compliance_rules(rule_id),
      computer_id   INTEGER REFERENCES computers(' || pk_col || '),
      justification TEXT NOT NULL,
      approved_by   VARCHAR(255),
      approved_at   TIMESTAMP,
      expires_at    TIMESTAMP NOT NULL,
      created_by    VARCHAR(255) NOT NULL,
      created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )';

    EXECUTE 'CREATE TABLE IF NOT EXISTS lifecycle_events (
      event_id      BIGSERIAL PRIMARY KEY,
      computer_id   INTEGER REFERENCES computers(' || pk_col || '),
      from_state    VARCHAR(50),
      to_state      VARCHAR(50) NOT NULL,
      reason_code   VARCHAR(100),
      notes         TEXT,
      performed_by  VARCHAR(255) NOT NULL,
      created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )';
END $$;

CREATE TABLE IF NOT EXISTS alerts (
  alert_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type    VARCHAR(100) NOT NULL,
  severity      VARCHAR(20) NOT NULL,
  title         VARCHAR(500) NOT NULL,
  description   TEXT,
  affected_hosts TEXT[] DEFAULT '{}',
  host_count    INTEGER DEFAULT 0,
  acknowledged  BOOLEAN DEFAULT false,
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ─── 4. User Table Extensions ───────────────────────────────────────────────
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='ad_groups') THEN
    ALTER TABLE users ADD COLUMN ad_groups TEXT[] DEFAULT '{}';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='preferences') THEN
    ALTER TABLE users ADD COLUMN preferences JSONB DEFAULT '{}';
  END IF;
END $$;

INSERT INTO schema_version (version, description)
VALUES ('5.0.0', 'v5 migration — extended endpoints, settings, unified audit')
ON CONFLICT DO NOTHING;
