/**
 * EMS v5 — Shared Type Definitions: Common
 */

/** API response wrapper */
export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
  message?: string;
  meta?: PaginationMeta;
}

/** Pagination metadata */
export interface PaginationMeta {
  page: number;
  pageSize: number;
  totalCount: number;
  totalPages: number;
}

/** Sort direction */
export type SortDirection = 'asc' | 'desc';

/** Generic filter parameter */
export interface FilterParam {
  field: string;
  operator: 'eq' | 'neq' | 'gt' | 'gte' | 'lt' | 'lte' | 'contains' | 'in';
  value: unknown;
}

/** Saved view — per-user table configuration (§7.4) */
export interface SavedView {
  id: string;
  name: string;
  description?: string;
  columns: string[];
  filters: FilterParam[];
  sort: { field: string; direction: SortDirection }[];
  groupBy?: string;
  isDefault: boolean;
  isShared: boolean;
  createdBy: string;
  createdAt: string;
}

/** Dashboard KPI tile */
export interface KpiTile {
  id: string;
  label: string;
  value: number;
  unit?: string;
  delta: number;
  deltaLabel: string;
  sparklineData: number[];
  severity: 'success' | 'warning' | 'error' | 'info';
  drillLink: string;
}

/** Time range selector options */
export type TimeRange = '7d' | '30d' | '90d' | 'QTD' | 'YTD';

/** Density preference */
export type DensityMode = 'compact' | 'cozy' | 'comfortable';

/** Theme mode */
export type ThemeMode = 'light' | 'dark' | 'high-contrast' | 'system';

/** Feature toggle */
export interface FeatureToggle {
  featureKey: string;
  featureName: string;
  description: string;
  enabled: boolean;
  category: string;
  updatedAt: string;
}

/** Connector health status */
export interface ConnectorHealth {
  name: string;
  type: 'Database' | 'ActiveDirectory' | 'SMTP' | 'WinRM' | 'CIM' | 'Redis' | 'SIEM';
  status: 'healthy' | 'degraded' | 'down' | 'unknown';
  latencyMs: number | null;
  lastChecked: string;
  errorMessage?: string;
}
