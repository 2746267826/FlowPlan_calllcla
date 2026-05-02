import dayjs from 'dayjs';
import type { ApiRecord, ManagementItem } from '../types';

export function asRecord(value: unknown): ApiRecord {
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as ApiRecord) : {};
}

export function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

export function extractRows(payload: unknown): ApiRecord[] {
  const record = asRecord(payload);
  const direct = [
    record.items,
    record.rows,
    record.data,
    record.devices,
    record.conflicts,
    record.auditLogs,
    record.jobs,
    record.configs,
    record.reports,
    record.deliveries,
    record.drafts,
    record.files,
    record.folders,
    record.history,
    record.runs,
    record.calendars,
  ].find(Array.isArray);
  if (Array.isArray(direct)) return direct.map(asRecord);
  if (Array.isArray(payload)) return payload.map(asRecord);
  return [];
}

export function displayValue(value: unknown, fallback = '无'): string {
  if (value === null || value === undefined || value === '') return fallback;
  if (typeof value === 'boolean') return value ? '是' : '否';
  if (typeof value === 'number') return Number.isFinite(value) ? String(value) : fallback;
  if (typeof value === 'string') return value;
  return shortJson(value);
}

export function shortJson(value: unknown): string {
  try {
    const text = JSON.stringify(value);
    return text.length > 140 ? `${text.slice(0, 137)}...` : text;
  } catch {
    return String(value);
  }
}

export function prettyJson(value: unknown): string {
  try {
    return JSON.stringify(value, null, 2);
  } catch {
    return String(value);
  }
}

export function parseJsonMaybe(value: unknown): unknown {
  if (typeof value !== 'string') return value;
  try {
    return JSON.parse(value);
  } catch {
    return value;
  }
}

export function parseJsonOrString(text: string): unknown {
  const trimmed = text.trim();
  if (!trimmed) return {};
  try {
    return JSON.parse(trimmed);
  } catch {
    return trimmed;
  }
}

export function formatDate(value: unknown): string {
  if (!value || value === '无') return '无';
  const parsed = dayjs(value instanceof Date ? value : String(value));
  return parsed.isValid() ? parsed.format('YYYY-MM-DD HH:mm:ss') : displayValue(value);
}

export function relativeDate(value: unknown): string {
  if (!value) return '无';
  const parsed = dayjs(String(value));
  if (!parsed.isValid()) return displayValue(value);
  return parsed.format('MM-DD HH:mm');
}

export function firstDate(...values: unknown[]): Date | undefined {
  for (const value of values) {
    if (!value) continue;
    const parsed = dayjs(String(value));
    if (parsed.isValid()) return parsed.toDate();
  }
  return undefined;
}

export function timeRangeLabel(start?: Date, end?: Date): string {
  if (!start) return '无时间';
  if (!end) return formatDate(start);
  return `${formatDate(start)} - ${formatDate(end)}`;
}

export function statusLabel(value: unknown): string {
  const raw = displayValue(value);
  const labels: Record<string, string> = {
    'NEEDS-ACTION': '待处理',
    'IN-PROCESS': '进行中',
    COMPLETED: '已完成',
    CONFIRMED: '已确认',
    TENTATIVE: '暂定',
    CANCELLED: '已取消',
    online: '在线',
    offline: '离线',
    degraded: '异常',
    failed: '失败',
    rejected: '已拒绝',
    pending: '待处理',
    open: '待处理',
    success: '成功',
    completed: '已完成',
    active: '启用',
    inactive: '停用',
    running: '运行中',
    idle: '空闲',
    ok: '正常',
  };
  return labels[raw] ?? labels[raw.toLowerCase()] ?? raw;
}

export function statusColor(value: unknown): string {
  const normalized = statusLabel(value).toLowerCase();
  if (['在线', '成功', '已完成', '已确认', '启用', '是', 'online', 'ok', 'success', 'completed', 'active'].some((item) => normalized.includes(item.toLowerCase()))) return 'success';
  if (['待处理', '进行中', '暂定', '异常', 'pending', 'draft', 'running', 'open', 'degraded'].some((item) => normalized.includes(item.toLowerCase()))) return 'warning';
  if (['失败', '离线', '错误', '冲突', '已取消', 'failed', 'offline', 'error', 'conflict', 'cancelled'].some((item) => normalized.includes(item.toLowerCase()))) return 'error';
  return 'default';
}

export function sourceLabel(value: unknown): string {
  const raw = displayValue(value);
  const normalized = raw.toLowerCase();
  if (normalized === 'outlook') return 'Outlook';
  if (normalized === 'local') return '本地';
  if (normalized === 'server') return '服务端';
  return raw === '无' ? '本地' : raw;
}

export function auditActionLabel(value: unknown): string {
  const raw = displayValue(value);
  const labels: Record<string, string> = {
    'admin.object.update': '更新对象',
    'admin.actual.update': '更新实际记录',
    'admin.file.update': '更新文件',
    'admin.remote_config.upsert': '保存远程设置',
    'admin.operation.prepare': '准备运维操作',
    'admin.operation.confirm': '确认运维操作',
    'admin.conflict.resolve': '处理同步冲突',
  };
  return labels[raw] ?? raw;
}

export function fieldLabel(key: string): string {
  const labels: Record<string, string> = {
    id: 'ID',
    uid: 'UID',
    title: '标题',
    summary: '标题',
    name: '名称',
    status: '状态',
    source: '来源',
    startAt: '开始时间',
    endAt: '结束时间',
    dueAt: '截止时间',
    createdAt: '创建时间',
    updatedAt: '更新时间',
    occurredAt: '发生时间',
    location: '地点',
    description: '描述',
    objectType: '对象类型',
    entityType: '对象类型',
    entityId: '对象 ID',
    version: '版本',
    deviceId: '设备 ID',
    deviceName: '设备名称',
    platform: '平台',
    clientDeviceId: '客户端 ID',
    runtimePlatform: '运行平台',
    appVersion: 'App 版本',
    networkType: '网络',
    lastSeenAt: '最近看见',
    lastHeartbeatAt: '最近心跳',
    lastConnectedAt: '最近连接',
    lastDisconnectedAt: '最近断开',
    lastConnectionError: '连接错误',
    syncPendingCount: '待同步',
    syncFailedCount: '失败写入',
    openConflictCount: '开放冲突',
    pullCursor: '拉取游标',
    cursorUpdatedAt: '游标更新',
  };
  return labels[key] ?? key;
}

export function formatFieldValue(key: string, value: unknown): string {
  if (key.toLowerCase().includes('at') || key.toLowerCase().includes('time')) return formatDate(value);
  if (key === 'status') return statusLabel(value);
  if (key === 'source') return sourceLabel(value);
  return typeof value === 'object' && value !== null ? shortJson(value) : displayValue(value);
}

export function pickId(row: ApiRecord): unknown {
  return row.id ?? row.uid ?? row.objectUid ?? row.deviceId ?? row.batchId ?? row.configKey ?? row.key;
}

export function getNestedValue(row: ApiRecord, key: string): unknown {
  const direct = row[key];
  if (direct !== undefined) return direct;
  const payload = asRecord(row.payload);
  const metadata = asRecord(row.metadata);
  return payload[key] ?? metadata[key] ?? row[toSnakeCase(key)] ?? payload[toSnakeCase(key)] ?? metadata[toSnakeCase(key)];
}

export function toSnakeCase(value: string): string {
  return value.replace(/[A-Z]/g, (match) => `_${match.toLowerCase()}`);
}

export function toCount(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.max(0, Math.trunc(parsed)) : 0;
}

export function toManagementItem(row: ApiRecord, domain: 'tasks' | 'schedules'): ManagementItem {
  const payload = asRecord(row.payload);
  const source = displayValue(row.source ?? payload.source ?? (domain === 'schedules' && String(row.uid ?? '').includes('outlook') ? 'outlook' : 'local'));
  const status = displayValue(row.status ?? payload.status ?? (domain === 'tasks' ? 'NEEDS-ACTION' : 'CONFIRMED'));
  const primary = firstDate(row.dueAt, row.dtstart, row.startAt, payload.due, payload.dtstart, payload.startAt, payload.dueAt);
  const end = firstDate(row.dtend, row.endAt, payload.dtend, payload.endAt);
  const title = displayValue(row.title ?? row.summary ?? row.name ?? payload.title ?? payload.summary ?? payload.name ?? row.uid);
  return {
    key: `${domain}:${displayValue(row.id ?? row.uid)}`,
    id: displayValue(row.id ?? row.uid),
    domain,
    type: domain === 'tasks' ? 'task' : 'schedule',
    typeLabel: domain === 'tasks' ? '任务' : '日程',
    title: title === '无' ? '未命名' : title,
    containerName: displayValue(row.calendarName ?? row.taskListName ?? payload.calendarName ?? payload.taskListName ?? payload.listName ?? (domain === 'tasks' ? '任务本' : '日历本')),
    source,
    sourceLabel: sourceLabel(source),
    status,
    statusLabel: statusLabel(status),
    primaryTime: primary,
    timeLabel: timeRangeLabel(primary, end),
    description: displayValue(row.description ?? payload.description ?? row.note ?? payload.note),
    location: displayValue(row.location ?? payload.location),
    raw: row,
  };
}

export function compareManagementItems(left: ManagementItem, right: ManagementItem): number {
  if (!left.primaryTime && !right.primaryTime) return left.title.localeCompare(right.title, 'zh-CN');
  if (!left.primaryTime) return 1;
  if (!right.primaryTime) return -1;
  return left.primaryTime.getTime() - right.primaryTime.getTime();
}

export function matchesManagementFilters(
  item: ManagementItem,
  filters: { query: string; typeFilter: string; sourceFilter: string; timeFilter: string; statusFilter: string },
): boolean {
  if (filters.typeFilter !== 'all' && item.type !== filters.typeFilter) return false;
  if (filters.sourceFilter !== 'all' && item.source.toLowerCase() !== filters.sourceFilter) return false;
  if (filters.statusFilter !== 'all' && item.status !== filters.statusFilter) return false;
  if (!matchesTimeFilter(item, filters.timeFilter)) return false;
  if (!filters.query.trim()) return true;
  const haystack = [item.title, item.containerName, item.description, item.location, item.statusLabel, item.sourceLabel].join(' ').toLowerCase();
  return haystack.includes(filters.query.trim().toLowerCase());
}

function matchesTimeFilter(item: ManagementItem, filter: string): boolean {
  if (filter === 'all') return true;
  const now = dayjs();
  const primary = item.primaryTime ? dayjs(item.primaryTime) : undefined;
  if (filter === 'none') return !primary;
  if (!primary) return false;
  if (filter === 'today') return primary.isSame(now, 'day');
  if (filter === 'next7') return primary.isAfter(now.startOf('day')) && primary.isBefore(now.startOf('day').add(7, 'day'));
  if (filter === 'overdue') return item.type === 'task' && item.status !== 'COMPLETED' && primary.isBefore(now);
  return true;
}
