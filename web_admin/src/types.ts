export type ApiRecord = Record<string, unknown>;

export type ConnectionState = 'checking' | 'online' | 'offline';

export type ModuleKey =
  | 'dashboard'
  | 'tasks'
  | 'actuals'
  | 'files'
  | 'reports'
  | 'sync'
  | 'outlook'
  | 'audit'
  | 'settings'
  | 'operations'
  | 'logs'
  | 'jobs'
  | 'schedule'
  | 'alerts';

export type DatasetDomain =
  | 'tasks'
  | 'schedules'
  | 'actuals'
  | 'files'
  | 'reports'
  | 'push-deliveries'
  | 'devices'
  | 'conflicts'
  | 'sync-mutations'
  | 'audit-logs'
  | 'settings'
  | 'file-operation-logs';

export interface AdminContext {
  apiBase: string;
  accessToken: string;
  deviceId: string;
}

export interface DeviceOption {
  id: string;
  name: string;
  detail: string;
}

export interface DatasetDefinition {
  domain: DatasetDomain;
  title: string;
  description: string;
}

export interface DetailState {
  title: string;
  dataset?: DatasetDefinition;
  row: ApiRecord;
  detail?: unknown;
  loading?: boolean;
  error?: string;
}

export interface DeviceSummary extends ApiRecord {
  deviceId?: string;
  id?: string;
  deviceName?: string;
  platform?: string;
  clientDeviceId?: string;
  lastSeenAt?: string;
  lastHeartbeatAt?: string;
  lastConnectedAt?: string;
  lastDisconnectedAt?: string;
  lastConnectionError?: string;
  appVersion?: string;
  runtimePlatform?: string;
  networkType?: string;
  syncPendingCount?: number;
  syncFailedCount?: number;
  openConflictCount?: number;
  pullCursor?: string;
  cursorUpdatedAt?: string;
  status?: string;
}

export interface ManagementItem {
  key: string;
  id: string;
  domain: 'tasks' | 'schedules';
  type: 'task' | 'schedule';
  typeLabel: string;
  title: string;
  containerName: string;
  source: string;
  sourceLabel: string;
  status: string;
  statusLabel: string;
  primaryTime?: Date;
  timeLabel: string;
  description: string;
  location: string;
  raw: ApiRecord;
}

export interface AuditEntry extends ApiRecord {
  id?: string;
  actor?: string;
  action?: string;
  entityType?: string;
  entityId?: string;
  targetType?: string;
  targetId?: string;
  summary?: string;
  occurredAt?: string;
  createdAt?: string;
  beforeJson?: string;
  afterJson?: string;
  metadataJson?: string;
  metadata?: unknown;
}

export interface OutlookStatus extends ApiRecord {
  connected?: boolean;
  status?: string;
  accountEmail?: string;
  accountDisplayName?: string;
  readOnly?: boolean;
  scope?: string;
  lastSyncAt?: string;
  calendars?: number;
  clientIdConfigured?: boolean;
  lastError?: string;
}

export interface OperationState {
  operationKey: string;
  payload: string;
  prepared?: ApiRecord;
  result?: ApiRecord;
  error?: string;
}
