# EMS v2.1 Enhancement - Authentication Provider Guide

## Overview

EMS v2.1 introduces multi-provider authentication, allowing you to authenticate users through multiple systems beyond Active Directory.

##  Supported Providers

1. **Standalone** - Local database users
2. **Active Directory** - Windows AD (existing)
3. **LDAP** - Generic LDAP servers
4. **ADFS** - Active Directory Federation Services
5. **SSO** - OAuth2/SAML (future)

---

## Configuration

Edit `Config\EMSConfig.json`:

```json
{
  "Authentication": {
    "Providers": [
      {
        "Name": "Standalone",
        "Enabled": true,
        "Priority": 1,
        "AllowRegistration": false
      },
      {
        "Name": "ActiveDirectory",
        "Enabled": true,
        "Domain": "corp.local",
        "Priority": 2
      },
      {
        "Name": "LDAP",
        "Enabled": false,
        "Server": "ldap.company.com",
        "Port": 389,
        "BaseDN": "dc=company,dc=com",
        "BindDN": "cn=ems_svc,ou=services,dc=company,dc=com",
        "BindPassword": "SERVICE_PASSWORD",
        "Priority": 3
      }
    ],
    "FallbackChain": true,
    "SessionTimeoutMinutes": 480,
    "MaxFailedAttempts": 5,
    "LockoutDurationMinutes": 30
  }
}
```

---

## Provider Details

### 1. Standalone Authentication

**Use Case**: Testing, non-domain systems, special service accounts

**Setup**:

```powershell
# Create standalone user
Import-Module .\Modules\Authentication\StandaloneAuth.psm1
$pwd = ConvertTo-SecureString "SecurePassword123!" -AsPlainText -Force
New-StandaloneUser -Username "localadmin" -SecurePassword $pwd -DisplayName "Local Administrator" -Role "admin"
```

**Login**: Username: `localadmin`, Password: `SecurePassword123!`

**Features**:
- SHA256 + salt password hashing
- Account lockout after failed attempts
- Password change on next login (optional)

---

### 2. Active Directory

**Use Case**: Domain-joined environments

**Setup**: Already configured (existing functionality)

**Login**: Username: `DOMAIN\username`, Password: AD password

**Features**:
- Group-based authorization (`EMS_Admins` group)
- Automatic user provisioning
- Integration with existing AD infrastructure

---

### 3. LDAP Authentication

**Use Case**: OpenLDAP, other LDAP directories

**Setup**:

1. Enable LDAP provider in config
2. Set LDAP server details:
   - `Server`: LDAP server hostname
   - `BaseDN`: Base distinguished name
   - `BindDN`: Service account DN
   - `BindPassword`: Service account password

**Example**:
```json
{
  "Name": "LDAP",
  "Enabled": true,
  "Server": "ldap://ldap.company.com:389",
  "BaseDN": "ou=users,dc=company,dc=com",
  "BindDN": "cn=ems_readonly,ou=services,dc=company,dc=com",
  "BindPassword": "ReadOnlyPassword123"
}
```

**Login**: Username: `username` (uid), Password: LDAP password

**Attributes Retrieved**:
- `displayName`
- `mail` (email)
- `memberOf` (groups)

---

### 4. ADFS (Active Directory Federation Services)

**Use Case**: Federated authentication, SSO scenarios

**Setup**:

```json
{
  "Name": "ADFS",
  "Enabled": true,
  "ServerURL": "https://adfs.company.com",
  "RelyingPartyIdentifier": "urn:ems:application",
  "Priority": 4
}
```

**Login**: Username: domain\username, Password: AD password

**How It Works**:
1. User provides credentials
2. EMS requests SAML token from ADFS
3. ADFS validates against AD
4. Token returned and validated
5. User authenticated

---

## Authentication Flow

### Fallback Chain

When `FallbackChain: true`:

1. User submits credentials
2. System tries **Provider #1** (Priority 1)
3. If fails, tries **Provider #2** (Priority 2)
4. Continues through all enabled providers
5. First successful authentication wins

**Example Scenario**:
- Priority 1: Standalone (check local users first)
- Priority 2: ActiveDirectory (then try AD)
- Priority 3: LDAP (fallback to LDAP)

### Manual Provider Selection

Users can select specific provider via UI dropdown or API:

**API**:
```powershell
$body = @{
    username = "testuser"
    password = "password"
    provider = "Standalone"  # Force specific provider
} | ConvertTo-Json

Invoke-RestMethod -Uri "http://localhost:5000/api/auth/login" -Method POST -Body $body -ContentType "application/json"
```

**Web UI**: Dropdown shows enabled providers

---

## Account Lockout

After `MaxFailedAttempts` failed logins, account locks for `LockoutDurationMinutes`.

**Database**:
```sql
-- Check locked accounts
SELECT username, failed_login_attempts, account_locked_until 
FROM users 
WHERE account_locked_until > NOW();

-- Manually unlock
UPDATE users SET account_locked_until = NULL, failed_login_attempts = 0 
WHERE username = 'lockeduser';
```

---

## Security Best Practices

### 1. Standalone Users

✅ **DO**:
- Use strong passwords (12+ characters, mixed case, numbers, symbols)
- Limit standalone accounts to necessary cases
- Regularly rotate passwords
- Enable `require_password_change` for first login

❌ **DON'T**:
- Use standalone for domain users
- Share standalone credentials
- Disable account lockout

### 2. LDAP Configuration

✅ **DO**:
- Use TLS/SSL (`ldaps://` on port 636)
- Create dedicated read-only service account
- Limit BindDN permissions
- Regularly rotate BindPassword

❌ **DON'T**:
- Store passwords in plain text
- Use admin credentials for binding
- Disable certificate validation

### 3. General

- Audit logs track authentication provider used
- Review failed login attempts regularly
- Test each provider before enabling in production
- Document provider priority decisions

---

## Troubleshooting

### Issue: "Provider not found or not enabled"

**Cause**: Provider disabled or misconfigured

**Solution**:
```powershell
# Check enabled providers
$config = Get-Content .\Config\EMSConfig.json | ConvertFrom-Json
$config.Authentication.Providers | Where-Object { $_.Enabled }
```

### Issue: LDAP connection fails

**Cause**: Network, credentials, or DN issues

**Test**:
```powershell
Import-Module .\Modules\Authentication\LDAPAuth.psm1
$ldapConfig = @{
    Server = "ldap.company.com"
    BaseDN = "dc=company,dc=com"
    BindDN = "cn=test,dc=company,dc=com"
    BindPassword = "password"
}

# This will show exact error
Test-LDAPAuth -Username "testuser" -Password "testpass" -Config $ldapConfig
```

### Issue: Account locked out

**Check**:
```sql
SELECT username, failed_login_attempts, account_locked_until, last_failed_login
FROM users
WHERE username = 'problematic_user';
```

**Unlock**:
```sql
SELECT reset_failed_logins(user_id) FROM users WHERE username = 'problematic_user';
```

---

## Migration from AD-Only

**Before**: Only AD authentication

**After**: Multi-provider with AD as fallback

**Steps**:

1. **Backup** `EMSConfig.json`
2. **Update** config with Authentication section
3. **Test** existing AD auth still works
4. **Add** additional providers as needed
5. **Migrate** database:
   ```powershell
   psql -U postgres -d ems_production -f Database\migration_multi_auth.sql
   ```
6. **Restart** API service

**Rollback**: Restore backup config, existing AD auth continues to work

---

## API Reference

### Get Available Providers

```http
GET /api/auth/providers
```

**Response**:
```json
{
  "providers": [
    { "Name": "Standalone", "RequiresCredentials": true },
    { "Name": "ActiveDirectory", "RequiresCredentials": true }
  ]
}
```

### Login with Provider

```http
POST /api/auth/login
Content-Type: application/json

{
  "username": "testuser",
  "password": "password",
  "provider": "Standalone"  // Optional
}
```

**Response**:
```json
{
  "success": true,
  "token": "eyJ...",
  "provider": "Standalone",
  "user": {
    "id": 1,
    "username": "testuser",
    "role": "operator"
  }
}
```

---

**Version**: 2.1  
**Last Updated**: 2025-12-24
