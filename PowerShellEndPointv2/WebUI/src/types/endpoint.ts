/**
 * EMS v5 — Shared Type Definitions: Endpoints
 */

/** Lifecycle states for endpoint management */
export type LifecycleState = 'Discovered' | 'Provisioned' | 'Active' | 'Stale' | 'Decommissioned' | 'Archived';

/** Reboot compliance severity */
export type RebootCompliance = 'Compliant' | 'Warning' | 'Critical';

/** Compliance severity levels */
export type ComplianceSeverity = 'Info' | 'Low' | 'Medium' | 'High' | 'Critical';

/** Endpoint tier classification */
export type EndpointTier = 1 | 2 | 3;

/** Topology classification */
export type TopologyType = 'HO' | 'Remote' | 'MPLS' | 'Unknown';

/**
 * Core endpoint record — maps to `computers` table + v5 extensions (§7.1-7.3)
 */
export interface Endpoint {
  computerId: number;
  computerName: string;
  hostname: string;
  ipAddress: string | null;
  macAddress: string | null;
  operatingSystem: string | null;
  osVersion: string | null;
  osBuild: string | null;
  domain: string | null;
  isDomainJoined: boolean;
  computerType: string;
  manufacturer: string | null;
  model: string | null;
  serialNumber: string | null;
  // v5 extensions (§7.3)
  assetTag: string | null;
  biosVersion: string | null;
  biosDate: string | null;
  secureBoot: boolean | null;
  tpmVersion: string | null;
  tpmEnabled: boolean | null;
  bitlockerStatus: string | null;
  bitlockerRecoveryEscrowed: boolean | null;
  lastLoggedOnUser: string | null;
  // Uptime / Reboot (§7.2)
  lastBootUpTime: string | null;
  uptimeDays: number | null;
  rebootCompliance: RebootCompliance | null;
  pendingReboot: boolean | null;
  // Network
  ipv4: string | null;
  ipv6: string | null;
  macs: string[];
  // Organization
  site: string | null;
  department: string | null;
  tier: EndpointTier | null;
  owner: string | null;
  tags: string[];
  // Lifecycle
  warrantyEnd: string | null;
  endOfSupport: string | null;
  lifecycleState: LifecycleState;
  riskScore: number | null;
  lastChangeHash: string | null;
  // Metadata
  comment: string | null;
  isActive: boolean;
  isArchived: boolean;
  firstSeen: string;
  lastSeen: string | null;
  updatedAt: string;
}

/** Compliance field rule — per-field compliance check (§10) */
export interface ComplianceRule {
  id: string;
  field: string;
  operator: 'equals' | 'notEquals' | 'contains' | 'greaterThan' | 'lessThan' | 'regex' | 'in' | 'notIn';
  expectedValue: unknown;
  severity: ComplianceSeverity;
  framework: string[];
  description: string;
  enabled: boolean;
  weight: number;
}

/** Compliance result for a single endpoint */
export interface ComplianceResult {
  endpointId: number;
  computerName: string;
  overallScore: number;
  passedRules: number;
  failedRules: number;
  waivedRules: number;
  findings: ComplianceFinding[];
}

export interface ComplianceFinding {
  ruleId: string;
  field: string;
  actualValue: unknown;
  expectedValue: unknown;
  severity: ComplianceSeverity;
  framework: string[];
  evidence: string;
  status: 'Pass' | 'Fail' | 'Waived' | 'Error';
}
