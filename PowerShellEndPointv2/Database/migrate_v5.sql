-- =============================================================================
-- EMS v5.0 Database Migration
-- Additive-only. Safe to re-run (idempotent).
-- Extends computers table with §7.1–7.3 fields.
-- Adds settings, audit_events, compliance, lifecycle, and alert tables.
-- =============================================================================

-- ─── 1. Extend computers table (§7.3) ────────────────────────────────────────

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

  -- Uptime / Reboot (§7.2)
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

-- ─── 2. Settings table (replaces EMSConfig.json for dynamic settings) ────────

CREATE TABLE IF NOT EXISTS settings (
  setting_id    SERIAL PRIMARY KEY,
  category      VARCHAR(100) NOT NULL,
  setting_key   VARCHAR(200) NOT NULL,
  setting_value TEXT,
  value_type    VARCHAR(20) DEFAULT 'string' CHECK (value_type IN ('string','number','boolean','json')),
  description   TEXT,
  is_sensitive  BOOLEAN DEFAULT false,
  updated_by    VARCHAR(255),
  updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE(category, setting_key)
);

-- Seed core settings from EMSConfig.json structure
INSERT INTO settings (category, setting_key, setting_value, value_type, description) VALUES
  ('general',    'org_name',       'Surya Nepal Pvt. Ltd.',  'string',  'Organization display name'),
  ('general',    'timezone',       'Asia/Kathmandu',         'string',  'Default timezone'),
  ('general',    'date_format',    'yyyy-MM-dd',             'string',  'Default date format'),
  ('general',    'week_start',     '0',                      'number',  'Week start day (0=Sun)'),
  ('scan',       'ho_throttle',    '40',                     'number',  'HO parallel scan limit'),
  ('scan',       'remote_throttle','4',                      'number',  'Remote/MPLS parallel scan limit'),
  ('scan',       'remote_delay_s', '5',                      'number',  'Inter-batch delay for remote scans'),
  ('scan',       'cim_timeout',    '15',                     'number',  'CIM session timeout seconds'),
  ('scan',       'invoke_timeout', '30',                     'number',  'Invoke-Command timeout seconds'),
  ('compliance', 'reboot_warn_d',  '3',                      'number',  'Uptime days for Warning'),
  ('compliance', 'reboot_crit_d',  '7',                      'number',  'Uptime days for Critical'),
  ('compliance', 'pending_warn_h', '24',                     'number',  'Pending reboot hours for Warning'),
  ('compliance', 'pending_crit_h', '72',                     'number',  'Pending reboot hours for Critical'),
  ('compliance', 'kb_max_age_d',   '35',                     'number',  'Max days since last KB install'),
  ('compliance', 'laps_max_age_d', '30',                     'number',  'LAPS rotation max days')
ON CONFLICT (category, setting_key) DO NOTHING;

-- ─── 3. Unified audit events table (§15) ────────────────────────────────────

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
  severity      VARCHAR(20) DEFAULT 'Info' CHECK (severity IN ('Info','Warning','High','Critical')),
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_audit_events_actor ON audit_events(actor);
CREATE INDEX IF NOT EXISTS idx_audit_events_action ON audit_events(action);
CREATE INDEX IF NOT EXISTS idx_audit_events_created ON audit_events(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_events_resource ON audit_events(resource_type, resource_id);

-- ─── 4. Compliance rules table (§10) ────────────────────────────────────────

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

-- ─── 5. Compliance exceptions (§10) ────────────────────────────────────────

CREATE TABLE IF NOT EXISTS compliance_exceptions (
  exception_id  SERIAL PRIMARY KEY,
  rule_id       VARCHAR(100) REFERENCES compliance_rules(rule_id),
  computer_id   INTEGER REFERENCES computers(computer_id),
  justification TEXT NOT NULL,
  approved_by   VARCHAR(255),
  approved_at   TIMESTAMP,
  expires_at    TIMESTAMP NOT NULL,
  created_by    VARCHAR(255) NOT NULL,
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ─── 6. Alerts table (§16) ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS alerts (
  alert_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  event_type    VARCHAR(100) NOT NULL,
  severity      VARCHAR(20) NOT NULL CHECK (severity IN ('Info','Warning','High','Critical')),
  title         VARCHAR(500) NOT NULL,
  description   TEXT,
  affected_hosts TEXT[] DEFAULT '{}',
  host_count    INTEGER DEFAULT 0,
  acknowledged  BOOLEAN DEFAULT false,
  acknowledged_by VARCHAR(255),
  acknowledged_at TIMESTAMP,
  resolved_at   TIMESTAMP,
  dedup_key     VARCHAR(255),
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_alerts_severity ON alerts(severity);
CREATE INDEX IF NOT EXISTS idx_alerts_created ON alerts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_alerts_dedup ON alerts(dedup_key) WHERE resolved_at IS NULL;

-- ─── 7. Saved views table (§7.4) ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS saved_views (
  view_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  view_name     VARCHAR(255) NOT NULL,
  description   TEXT,
  table_name    VARCHAR(100) NOT NULL,
  columns       JSONB NOT NULL DEFAULT '[]',
  filters       JSONB NOT NULL DEFAULT '[]',
  sort_config   JSONB NOT NULL DEFAULT '[]',
  group_by      VARCHAR(100),
  is_default    BOOLEAN DEFAULT false,
  is_shared     BOOLEAN DEFAULT false,
  created_by    VARCHAR(255) NOT NULL,
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ─── 8. Lifecycle events (§13) ─────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS lifecycle_events (
  event_id      BIGSERIAL PRIMARY KEY,
  computer_id   INTEGER REFERENCES computers(computer_id),
  from_state    VARCHAR(50),
  to_state      VARCHAR(50) NOT NULL,
  reason_code   VARCHAR(100),
  notes         TEXT,
  performed_by  VARCHAR(255) NOT NULL,
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_lifecycle_computer ON lifecycle_events(computer_id, created_at DESC);

-- ─── 9. Credential profiles (§6) ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS credential_profiles (
  profile_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_name  VARCHAR(255) NOT NULL UNIQUE,
  profile_type  VARCHAR(50) NOT NULL CHECK (profile_type IN ('Domain-Admin','Local-Service','Workgroup')),
  username      VARCHAR(255) NOT NULL,
  encrypted_password TEXT NOT NULL,
  subnets       TEXT[] DEFAULT '{}',
  last_rotated  TIMESTAMP,
  created_by    VARCHAR(255),
  created_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ─── 10. Extend users table for v5 roles ──────────────────────────────────

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='ad_groups') THEN
    ALTER TABLE users ADD COLUMN ad_groups TEXT[] DEFAULT '{}';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='scoped_sites') THEN
    ALTER TABLE users ADD COLUMN scoped_sites TEXT[] DEFAULT '{}';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='scoped_departments') THEN
    ALTER TABLE users ADD COLUMN scoped_departments TEXT[] DEFAULT '{}';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='users' AND column_name='preferences') THEN
    ALTER TABLE users ADD COLUMN preferences JSONB DEFAULT '{}';
  END IF;
END $$;

-- ─── 11. Schema version ──────────────────────────────────────────────────

INSERT INTO schema_version (version, description)
VALUES ('5.0.0', 'v5 migration — extended endpoints, settings, unified audit, compliance, alerts, lifecycle, saved views, credential profiles')
ON CONFLICT DO NOTHING;
