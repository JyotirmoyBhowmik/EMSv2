/**
 * EMS v5 — Shared Type Definitions: Scans
 */

/** Scan status lifecycle */
export type ScanStatus = 'queued' | 'running' | 'completed' | 'failed' | 'cancelled' | 'archived';

/** Transport protocol used for scan connection */
export type ScanProtocol = 'WinRM' | 'CIM' | 'DCOM' | 'Unknown';

/** Discovery mode for finding endpoints */
export type DiscoveryMode = 'ICMP' | 'ARP' | 'AD-OU' | 'DNS' | 'DHCP' | 'CSV' | 'Manual';

/** Scan record — maps to `scans` table */
export interface Scan {
  scanId: string;
  target: string;
  status: ScanStatus;
  healthScore: number | null;
  executionTimeSec: number | null;
  errorMessage: string | null;
  criticalAlerts: number;
  warningAlerts: number;
  infoAlerts: number;
  startedAt: string;
  completedAt: string | null;
  isArchived: boolean;
  initiatedBy: string | null;
}

/** Scan trace entry — observability per-step */
export interface ScanTraceEntry {
  traceId: number;
  scanId: string;
  stepName: string;
  moduleName: string;
  status: 'Info' | 'Success' | 'Warning' | 'Error';
  message: string;
  timestamp: string;
}

/** Batch scan request */
export interface BatchScanRequest {
  targets: string[];
  protocol?: ScanProtocol;
  credentialProfile?: string;
  dryRun?: boolean;
  priority?: 'low' | 'normal' | 'high';
}

/** Batch scan response */
export interface BatchScanResponse {
  targetCount: number;
  scanIds: string[];
  targets: string[];
}

/** Collector result from a scan */
export interface CollectorResult {
  name: string;
  success: boolean;
  metricCount: number;
  duration: number;
  errors: string[];
}

/** Credential profile for scan authentication */
export interface CredentialProfile {
  id: string;
  name: string;
  type: 'Domain-Admin' | 'Local-Service' | 'Workgroup';
  username: string;
  subnets: string[];
  lastRotated: string | null;
}
