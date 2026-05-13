BEGIN;

-- 0. Make schema_version idempotent (H13).
CREATE TABLE IF NOT EXISTS schema_version (
    version     INTEGER PRIMARY KEY,
    applied_at  TIMESTAMPTZ DEFAULT now(),
    description TEXT
);

-- 1. Drop dual soft-delete; standardize on is_deleted (M8).
UPDATE scans SET is_deleted = TRUE,
                 deleted_at = COALESCE(deleted_at, archived_at),
                 deleted_by = COALESCE(deleted_by, archived_by),
                 delete_reason = COALESCE(delete_reason, archive_reason)
 WHERE is_archived = TRUE AND is_deleted IS DISTINCT FROM TRUE;
ALTER TABLE scans DROP COLUMN IF EXISTS is_archived;
ALTER TABLE scans DROP COLUMN IF EXISTS archived_at;
ALTER TABLE scans DROP COLUMN IF EXISTS archived_by;
ALTER TABLE scans DROP COLUMN IF EXISTS archive_reason;

-- 2. JSON -> JSONB (M9).
ALTER TABLE scans
    ALTER COLUMN result_json TYPE JSONB USING result_json::jsonb;
CREATE INDEX IF NOT EXISTS idx_scans_result_json ON scans USING GIN (result_json);

-- 3. FKs on scan_trace + metric_* (H11).
ALTER TABLE scan_trace
    ADD CONSTRAINT fk_scan_trace_scan
    FOREIGN KEY (scan_id) REFERENCES scans(scan_id) ON DELETE CASCADE;

DO $$
DECLARE t text;
BEGIN
    FOR t IN
        SELECT table_name FROM information_schema.columns
         WHERE table_schema='public' AND table_name LIKE 'metric_%'
           AND column_name='computer_name'
    LOOP
        EXECUTE format(
            'ALTER TABLE %I ADD CONSTRAINT fk_%I_computer
             FOREIGN KEY (computer_name) REFERENCES computers(computer_name)
             ON DELETE CASCADE', t, t);
    END LOOP;
END$$;

-- 4. Encrypted settings column + CHECK (H12).
ALTER TABLE settings ADD COLUMN IF NOT EXISTS encrypted_value TEXT;
ALTER TABLE settings
    ADD CONSTRAINT chk_sensitive_encrypted
    CHECK (NOT is_sensitive OR encrypted_value IS NOT NULL);

-- 5. TIMESTAMPTZ for every audit column (H14).
ALTER TABLE audit_api_requests    ALTER COLUMN ts          TYPE TIMESTAMPTZ USING ts AT TIME ZONE 'UTC';
ALTER TABLE audit_auth_events     ALTER COLUMN ts          TYPE TIMESTAMPTZ USING ts AT TIME ZONE 'UTC';
ALTER TABLE audit_config_changes  ALTER COLUMN ts          TYPE TIMESTAMPTZ USING ts AT TIME ZONE 'UTC';
ALTER TABLE audit_feature_toggles ALTER COLUMN ts          TYPE TIMESTAMPTZ USING ts AT TIME ZONE 'UTC';
ALTER TABLE audit_events          ALTER COLUMN created_at  TYPE TIMESTAMPTZ USING created_at AT TIME ZONE 'UTC';

-- 6. Audit indexes (H15).
CREATE INDEX IF NOT EXISTS idx_auth_events_user_ts ON audit_auth_events(username, ts DESC);
CREATE INDEX IF NOT EXISTS idx_auth_events_ts      ON audit_auth_events(ts DESC);
CREATE INDEX IF NOT EXISTS idx_cfg_changes_ts      ON audit_config_changes(ts DESC);
CREATE INDEX IF NOT EXISTS idx_cfg_changes_actor   ON audit_config_changes(changed_by);
CREATE INDEX IF NOT EXISTS idx_feat_toggles_ts     ON audit_feature_toggles(ts DESC);
CREATE INDEX IF NOT EXISTS idx_audit_events_actor  ON audit_events(actor);
CREATE INDEX IF NOT EXISTS idx_audit_events_res    ON audit_events(resource_type, resource_id);

-- 7. Users / password hash (H16, M4).
ALTER TABLE users
    ADD COLUMN IF NOT EXISTS pwd_algorithm  TEXT,
    ADD COLUMN IF NOT EXISTS pwd_iterations INTEGER;
UPDATE users SET pwd_algorithm='PBKDF2-SHA1', pwd_iterations=100000
 WHERE pwd_algorithm IS NULL AND password_hash IS NOT NULL;
ALTER TABLE users
    ALTER COLUMN password_hash SET NOT NULL,
    ADD CONSTRAINT chk_password_hash_len CHECK (char_length(password_hash) >= 32);

-- 8. Feature toggles: off by default for integrations (H17).
UPDATE feature_toggles SET is_enabled = FALSE
 WHERE feature_key IN ('ad_integration','adfs_integration','ldap_integration')
   AND NOT EXISTS (SELECT 1 FROM service_credentials WHERE provider = feature_key);

-- 9. Stamp version.
INSERT INTO schema_version (version, description)
VALUES (6, 'Hardening: FKs, TIMESTAMPTZ, indexes, JSONB, soft-delete consolidation, password algo metadata')
ON CONFLICT (version) DO NOTHING;

COMMIT;
