-- Database Schema Updates for Multi-Auth Support
-- Adds authentication provider support to existing users table

-- Add auth-related columns to users table
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS auth_provider VARCHAR(50) DEFAULT 'ActiveDirectory',
ADD COLUMN IF NOT EXISTS external_id VARCHAR(255),
ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255),
ADD COLUMN IF NOT EXISTS require_password_change BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS failed_login_attempts INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS last_failed_login TIMESTAMP,
ADD COLUMN IF NOT EXISTS account_locked_until TIMESTAMP;

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_users_auth_provider ON users(auth_provider);
CREATE INDEX IF NOT EXISTS idx_users_external_id ON users(external_id);
CREATE INDEX IF NOT EXISTS idx_users_locked ON users(account_locked_until) WHERE account_locked_until IS NOT NULL;

-- Update existing users to have auth_provider set
UPDATE users SET auth_provider = 'ActiveDirectory' WHERE auth_provider IS NULL;

-- Function to check and unlock accounts
CREATE OR REPLACE FUNCTION check_unlock_account(p_user_id INTEGER)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE users
    SET account_locked_until = NULL
    WHERE user_id = p_user_id
    AND account_locked_until IS NOT NULL
    AND account_locked_until < NOW();
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function to lock account after failed attempts
CREATE OR REPLACE FUNCTION handle_failed_login(p_user_id INTEGER, p_max_attempts INTEGER, p_lockout_minutes INTEGER)
RETURNS BOOLEAN AS $$
DECLARE
    v_failed_attempts INTEGER;
BEGIN
    -- Increment failed attempts
    UPDATE users
    SET failed_login_attempts = failed_login_attempts + 1,
        last_failed_login = NOW()
    WHERE user_id = p_user_id
    RETURNING failed_login_attempts INTO v_failed_attempts;
    
    -- Lock account if threshold reached
    IF v_failed_attempts >= p_max_attempts THEN
        UPDATE users
        SET account_locked_until = NOW() + (p_lockout_minutes || ' minutes')::INTERVAL
        WHERE user_id = p_user_id;
        RETURN TRUE; -- Account locked
    END IF;
    
    RETURN FALSE; -- Not locked yet
END;
$$ LANGUAGE plpgsql;

-- Function to reset failed attempts (successful login)
CREATE OR REPLACE FUNCTION reset_failed_logins(p_user_id INTEGER)
RETURNS VOID AS $$
BEGIN
    UPDATE users
    SET failed_login_attempts = 0,
        last_failed_login = NULL
    WHERE user_id = p_user_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON COLUMN users.auth_provider IS 'Authentication provider: Standalone, ActiveDirectory, LDAP, ADFS, SSO';
COMMENT ON COLUMN users.external_id IS 'External identifier (LDAP DN, AD Object GUID, ADFS claim, SSO subject)';
COMMENT ON COLUMN users.password_hash IS 'Password hash for Standalone users only (format: salt:hash)';
