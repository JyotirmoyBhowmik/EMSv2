/**
 * EMS v5 — Shared Type Definitions: Auth & RBAC
 */

/** User roles mapped to AD groups (§3) */
export type UserRole = 'senior_manager' | 'it_manager' | 'dc_officer' | 'auditor' | 'service_desk';

/** Permission flags per role */
export interface Permissions {
  canView: boolean;
  canScan: boolean;
  canArchive: boolean;
  canAdmin: boolean;
  canApprove: boolean;
  canOverrideCompliance: boolean;
  canExport: boolean;
  canRemediate: boolean;
  canManageUsers: boolean;
  canManageSettings: boolean;
}

/** Authenticated user context */
export interface AuthUser {
  username: string;
  displayName: string;
  email?: string;
  role: UserRole;
  permissions: Permissions;
  groups: string[];
  authProvider: 'Standalone' | 'ActiveDirectory' | 'LDAP' | 'AzureAD';
  lastLogin: string | null;
}

/** Login request */
export interface LoginRequest {
  username: string;
  password: string;
  provider?: string;
}

/** Login response */
export interface LoginResponse {
  success: boolean;
  message?: string;
  token?: string;
  user?: AuthUser;
}

/** Audit event — unified audit log (§15) */
export interface AuditEvent {
  eventId: number;
  actor: string;
  action: string;
  resource: string;
  resourceId?: string;
  beforeState?: Record<string, unknown>;
  afterState?: Record<string, unknown>;
  ipAddress: string;
  userAgent?: string;
  requestId?: string;
  severity: 'Info' | 'Warning' | 'High' | 'Critical';
  timestamp: string;
}

/** Alert event types (§16) */
export type AlertEventType =
  | 'CRITICAL_CVE'
  | 'MISSING_CRITICAL_KB'
  | 'COMPLIANCE_DRIFT'
  | 'SCAN_FAILURE_SPIKE'
  | 'SOFTWARE_POLICY_VIOLATION'
  | 'EOL_MILESTONE'
  | 'WARRANTY_EXPIRY'
  | 'HOST_STALE'
  | 'REBOOT_OVERDUE_WARNING'
  | 'REBOOT_OVERDUE_CRITICAL'
  | 'PENDING_REBOOT_72H';

/** Alert severity */
export type AlertSeverity = 'Info' | 'Warning' | 'High' | 'Critical';

/** Alert record */
export interface Alert {
  alertId: string;
  eventType: AlertEventType;
  severity: AlertSeverity;
  title: string;
  description: string;
  affectedHosts: string[];
  hostCount: number;
  acknowledged: boolean;
  acknowledgedBy?: string;
  acknowledgedAt?: string;
  createdAt: string;
  resolvedAt?: string;
}
