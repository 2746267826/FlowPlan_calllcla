export type SyncAction = 'create' | 'update' | 'delete' | 'upsert';

export interface SyncMutationDto {
  mutationUid: string;
  objectType: string;
  localId: string;
  serverId?: string | null;
  uid?: string | null;
  action: SyncAction;
  baseServerVersion?: number | null;
  changedFields?: string[] | null;
  payload: Record<string, unknown>;
}

export interface SyncPushDto {
  deviceId?: string;
  clientBatchId?: string;
  mutations: SyncMutationDto[];
}

export interface SyncAcceptedDto {
  mutationUid: string;
  objectType: string;
  localId: string;
  serverId: string;
  serverVersion: number;
}

export interface SyncRejectedDto {
  mutationUid: string;
  objectType: string;
  localId: string;
  reason: string;
}

export interface SyncConflictFieldDto {
  field: string;
  base: unknown;
  local: unknown;
  server: unknown;
}

export interface SyncConflictDto {
  conflictId: string;
  mutationUid?: string;
  objectType: string;
  localId?: string;
  serverId?: string;
  baseVersion?: number | null;
  localVersion: number;
  serverVersion: number;
  fields: SyncConflictFieldDto[];
}

export interface SyncPushResponseDto {
  serverBatchId: string;
  accepted: SyncAcceptedDto[];
  conflicts: SyncConflictDto[];
  rejected: SyncRejectedDto[];
}

export interface SyncPullResponseDto {
  nextCursor: string;
  serverTime: string;
  changes: SyncChangeDto[];
}

export interface SyncChangeDto {
  changeId: string;
  objectType: string;
  serverId: string;
  uid?: string | null;
  action: 'upsert' | 'delete';
  serverVersion: number;
  updatedAt: string;
  payload: Record<string, unknown>;
}

export interface SyncAckDto {
  deviceId?: string;
  cursor: string;
  appliedChangeIds?: string[];
}

export interface ResolveConflictDto {
  strategy: 'use_local' | 'use_server' | 'merge' | 'keep_both' | 'ignore';
  payload?: Record<string, unknown>;
  note?: string;
}
