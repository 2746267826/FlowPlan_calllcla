import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

type ApiRecord = Record<string, unknown>;
type ConnectionState = 'checking' | 'online' | 'offline';
type ModuleKey =
  | 'dashboard'
  | 'data'
  | 'settings'
  | 'sync'
  | 'files'
  | 'models'
  | 'reports'
  | 'monitoring'
  | 'operations';

interface AdminContext {
  apiBase: string;
  userId: string;
  deviceId: string;
}

interface DeviceOption {
  id: string;
  name: string;
  detail: string;
}

interface DatasetColumn {
  key: string;
  label: string;
  width?: number;
  type?: 'status' | 'date' | 'json' | 'number';
}

interface DatasetDefinition {
  key: string;
  title: string;
  description: string;
  endpoint: string;
  domain?: string;
  columns: DatasetColumn[];
  defaultLimit?: number;
  tags?: string[];
}

interface DetailState {
  title: string;
  dataset?: DatasetDefinition;
  row: ApiRecord;
  detail?: unknown;
  loading?: boolean;
  error?: string;
}

interface OperationState {
  operationKey: string;
  payload: string;
  prepared?: ApiRecord;
  result?: ApiRecord;
  error?: string;
}

const defaultApiBase = 'http://localhost:3200';
const defaultUserId = '00000000-0000-4000-8000-000000000001';
const deviceFilterDatasets = new Set([
  'devices',
  'sync-changes',
  'sync-mutations',
  'conflicts',
  'tracking-ingest-batches',
  'file-operation-logs',
  'audit-logs',
]);

const modules: Array<{
  key: ModuleKey;
  label: string;
  description: string;
}> = [
  {
    key: 'dashboard',
    label: '总览',
    description: '服务健康、数据规模、风险队列和最近事件。',
  },
  {
    key: 'data',
    label: '数据中心',
    description: '任务、日程、实际记录、活动片段、追踪批次和核心事实数据。',
  },
  {
    key: 'settings',
    label: '设置中心',
    description: '远程设置、AI、同步、报告、文件、Outlook 和模型策略。',
  },
  {
    key: 'sync',
    label: '同步与客户端',
    description: '设备在线、心跳、同步游标、失败 mutation 和冲突。',
  },
  {
    key: 'files',
    label: '文件与存储',
    description: '服务端云盘树、对象存储、传输会话、设备副本和文件日志。',
  },
  {
    key: 'models',
    label: '模型与 AI',
    description: '模型运行、反馈学习、AI Provider、草案审核和受控执行。',
  },
  {
    key: 'reports',
    label: '报告与推送',
    description: '日报、日记、证据、天气、推送渠道和投递记录。',
  },
  {
    key: 'monitoring',
    label: '监控与日志',
    description: '审计、同步、文件、AI、推送、后台任务和错误聚合。',
  },
  {
    key: 'operations',
    label: '运维操作',
    description: '重试、重算、诊断、导出和高风险操作 prepare/confirm。',
  },
];

const dataCenterDatasets: DatasetDefinition[] = [
  {
    key: 'tasks',
    title: '任务',
    description: '服务端事实库中的任务、状态、时间、地点和同步版本。',
    endpoint: '/api/admin/data/tasks',
    domain: 'tasks',
    columns: [
      { key: 'title', label: '标题', width: 240 },
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'dueAt', label: '截止', type: 'date', width: 150 },
      { key: 'dtstart', label: '计划开始', type: 'date', width: 150 },
      { key: 'durationMinutes', label: '时长', type: 'number', width: 82 },
      { key: 'location', label: '地点', width: 140 },
      { key: 'version', label: '版本', type: 'number', width: 72 },
      { key: 'updatedAt', label: '更新', type: 'date', width: 150 },
    ],
  },
  {
    key: 'schedules',
    title: '日程',
    description: '日程、阻挡块、课表和时间轴事实数据。',
    endpoint: '/api/admin/data/schedules',
    domain: 'schedules',
    columns: [
      { key: 'title', label: '标题', width: 240 },
      { key: 'startAt', label: '开始', type: 'date', width: 150 },
      { key: 'endAt', label: '结束', type: 'date', width: 150 },
      { key: 'location', label: '地点', width: 140 },
      { key: 'isBlock', label: '阻挡', type: 'status', width: 76 },
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'updatedAt', label: '更新', type: 'date', width: 150 },
    ],
  },
  {
    key: 'actuals',
    title: '实际记录',
    description: '用户确认后的实际活动和任务投入事实。',
    endpoint: '/api/admin/data/actuals',
    domain: 'actuals',
    columns: [
      { key: 'title', label: '标题', width: 220 },
      { key: 'taskTitle', label: '关联任务', width: 180 },
      { key: 'startAt', label: '开始', type: 'date', width: 150 },
      { key: 'endAt', label: '结束', type: 'date', width: 150 },
      { key: 'durationMinutes', label: '分钟', type: 'number', width: 80 },
      { key: 'confidence', label: '置信度', type: 'number', width: 86 },
    ],
  },
  {
    key: 'activity-segments',
    title: '活动片段',
    description: '服务端活动理解模型生成的候选片段、证据和确认状态。',
    endpoint: '/api/admin/data/activity-segments',
    domain: 'activity-segments',
    columns: [
      { key: 'title', label: '标题', width: 220 },
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'startAt', label: '开始', type: 'date', width: 150 },
      { key: 'endAt', label: '结束', type: 'date', width: 150 },
      { key: 'primaryApp', label: '主要应用', width: 140 },
      { key: 'confidence', label: '置信度', type: 'number', width: 86 },
    ],
  },
  {
    key: 'tracking-ingest-batches',
    title: '追踪上传批次',
    description: '原生客户端上传到服务端的追踪批次和处理状态。',
    endpoint: '/api/admin/data/tracking-ingest-batches',
    domain: 'tracking-ingest-batches',
    columns: [
      { key: 'batchUid', label: '批次', width: 260 },
      { key: 'dataKind', label: '类型', width: 130 },
      { key: 'status', label: '状态', type: 'status', width: 96 },
      { key: 'rawEventCount', label: '原始数', type: 'number', width: 86 },
      { key: 'acceptedEventCount', label: '接收数', type: 'number', width: 86 },
      { key: 'createdAt', label: '创建', type: 'date', width: 150 },
    ],
  },
  {
    key: 'scheduler-runs',
    title: '排程运行',
    description: '服务端排程模型运行记录、草案、失败原因和模型来源。',
    endpoint: '/api/admin/data/schedule-runs',
    domain: 'schedule-runs',
    columns: [
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'modelUsed', label: '模型', width: 120 },
      { key: 'confidence', label: '置信度', type: 'number', width: 86 },
      { key: 'rangeStart', label: '范围开始', type: 'date', width: 150 },
      { key: 'rangeEnd', label: '范围结束', type: 'date', width: 150 },
      { key: 'createdAt', label: '创建', type: 'date', width: 150 },
    ],
  },
];

const syncDatasets: DatasetDefinition[] = [
  {
    key: 'devices',
    title: '客户端设备',
    description: '多端设备、在线状态、心跳、平台、版本和同步积压。',
    endpoint: '/api/admin/data/devices',
    domain: 'devices',
    columns: [
      { key: 'deviceName', label: '设备', width: 180 },
      { key: 'platform', label: '平台', width: 100 },
      { key: 'connectionStatus', label: '在线', type: 'status', width: 92 },
      { key: 'lastHeartbeatAt', label: '最近心跳', type: 'date', width: 150 },
      { key: 'syncPendingCount', label: '待同步', type: 'number', width: 82 },
      { key: 'syncFailedCount', label: '失败', type: 'number', width: 72 },
      { key: 'openConflictCount', label: '冲突', type: 'number', width: 72 },
    ],
  },
  {
    key: 'sync-changes',
    title: '服务端变更日志',
    description: '服务端 canonical 数据产生的增量变更。',
    endpoint: '/api/admin/data/sync-changes',
    domain: 'sync-changes',
    columns: [
      { key: 'objectType', label: '对象类型', width: 130 },
      { key: 'objectUid', label: '对象 UID', width: 230 },
      { key: 'changeType', label: '动作', type: 'status', width: 92 },
      { key: 'serverVersion', label: '版本', type: 'number', width: 72 },
      { key: 'createdAt', label: '时间', type: 'date', width: 150 },
    ],
  },
  {
    key: 'sync-mutations',
    title: '客户端 mutation',
    description: '客户端离线写入、失败队列、重试和错误信息。',
    endpoint: '/api/admin/data/sync-mutations',
    domain: 'sync-mutations',
    columns: [
      { key: 'objectType', label: '对象类型', width: 130 },
      { key: 'mutationType', label: '动作', type: 'status', width: 96 },
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'deviceName', label: '设备', width: 180 },
      { key: 'lastError', label: '最近错误', width: 240 },
      { key: 'updatedAt', label: '更新', type: 'date', width: 150 },
    ],
  },
  {
    key: 'conflicts',
    title: '同步冲突',
    description: '不能静默覆盖的多端冲突候选和处理结果。',
    endpoint: '/api/admin/data/conflicts',
    domain: 'conflicts',
    columns: [
      { key: 'objectType', label: '对象类型', width: 130 },
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'conflictKind', label: '类型', width: 120 },
      { key: 'deviceName', label: '设备', width: 180 },
      { key: 'createdAt', label: '创建', type: 'date', width: 150 },
      { key: 'resolvedAt', label: '解决', type: 'date', width: 150 },
    ],
  },
];

const fileDatasets: DatasetDefinition[] = [
  {
    key: 'file-roots',
    title: '服务端 Root',
    description: '服务端可访问的云盘根目录和扫描状态。',
    endpoint: '/api/admin/data/file-roots',
    domain: 'file-roots',
    columns: [
      { key: 'name', label: '名称', width: 180 },
      { key: 'rootPath', label: '服务端路径', width: 260 },
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'lastScannedAt', label: '最近扫描', type: 'date', width: 150 },
      { key: 'nodeCount', label: '节点数', type: 'number', width: 82 },
    ],
  },
  {
    key: 'file-nodes',
    title: '文件树节点',
    description: '唯一逻辑文件树，包含文件夹和文件节点。',
    endpoint: '/api/admin/data/file-nodes',
    domain: 'file-nodes',
    columns: [
      { key: 'name', label: '名称', width: 220 },
      { key: 'nodeType', label: '类型', type: 'status', width: 82 },
      { key: 'relativePath', label: '相对路径', width: 260 },
      { key: 'sizeBytes', label: '大小', type: 'number', width: 96 },
      { key: 'storageStatus', label: '存储', type: 'status', width: 96 },
      { key: 'updatedAt', label: '更新', type: 'date', width: 150 },
    ],
  },
  {
    key: 'storage-objects',
    title: '对象存储',
    description: '服务端保存的文件内容对象、hash 和大小。',
    endpoint: '/api/files/storage/objects',
    columns: [
      { key: 'objectKey', label: '对象', width: 260 },
      { key: 'checksumSha256', label: 'SHA256', width: 260 },
      { key: 'sizeBytes', label: '大小', type: 'number', width: 96 },
      { key: 'provider', label: 'Provider', width: 120 },
      { key: 'createdAt', label: '创建', type: 'date', width: 150 },
    ],
  },
  {
    key: 'file-transfers',
    title: '传输会话',
    description: '上传、下载、分块、续传、失败和校验记录。',
    endpoint: '/api/admin/data/transfer-events',
    domain: 'transfer-events',
    columns: [
      { key: 'direction', label: '方向', type: 'status', width: 82 },
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'fileName', label: '文件', width: 220 },
      { key: 'uploadedChunks', label: '已传块', type: 'number', width: 86 },
      { key: 'totalChunks', label: '总块', type: 'number', width: 86 },
      { key: 'lastError', label: '错误', width: 220 },
    ],
  },
  {
    key: 'file-operation-logs',
    title: '文件操作日志',
    description: '打开、下载、绑定、重定位、冲突和历史版本操作。',
    endpoint: '/api/admin/data/file-operation-logs',
    domain: 'file-operation-logs',
    columns: [
      { key: 'action', label: '动作', type: 'status', width: 110 },
      { key: 'nodeId', label: '节点', width: 180 },
      { key: 'deviceName', label: '设备', width: 180 },
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'createdAt', label: '时间', type: 'date', width: 150 },
    ],
  },
];

const modelDatasets: DatasetDefinition[] = [
  {
    key: 'ai-drafts',
    title: 'AI 草案',
    description: '受控工具调用生成的 OperationDraft，确认前不能写事实库。',
    endpoint: '/api/admin/data/ai-drafts',
    domain: 'ai-drafts',
    columns: [
      { key: 'draftType', label: '类型', width: 130 },
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'riskLevel', label: '风险', type: 'status', width: 82 },
      { key: 'createdBy', label: '创建者', width: 140 },
      { key: 'createdAt', label: '创建', type: 'date', width: 150 },
    ],
  },
  {
    key: 'model-runs',
    title: '模型运行',
    description: '排程、活动理解、报告、文件推荐等模型运行日志。',
    endpoint: '/api/admin/data/model-runs',
    domain: 'model-runs',
    columns: [
      { key: 'modelKey', label: '模型', width: 160 },
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'confidence', label: '置信度', type: 'number', width: 86 },
      { key: 'usedLlm', label: 'LLM', type: 'status', width: 72 },
      { key: 'failureReason', label: '失败原因', width: 220 },
      { key: 'createdAt', label: '时间', type: 'date', width: 150 },
    ],
  },
  {
    key: 'model-versions',
    title: '模型版本',
    description: '规则参数、权重、启用状态和回滚依据。',
    endpoint: '/api/admin/data/model-versions',
    domain: 'model-versions',
    columns: [
      { key: 'modelKey', label: '模型', width: 160 },
      { key: 'versionLabel', label: '版本', width: 120 },
      { key: 'isActive', label: '启用', type: 'status', width: 72 },
      { key: 'createdAt', label: '创建', type: 'date', width: 150 },
    ],
  },
  {
    key: 'model-feedback',
    title: '模型反馈',
    description: '确认、拒绝、修改和学习样本。',
    endpoint: '/api/admin/data/model-feedback',
    domain: 'model-feedback',
    columns: [
      { key: 'modelKey', label: '模型', width: 160 },
      { key: 'feedbackType', label: '反馈', type: 'status', width: 110 },
      { key: 'outcome', label: '结果', type: 'status', width: 92 },
      { key: 'createdAt', label: '时间', type: 'date', width: 150 },
    ],
  },
  {
    key: 'model-rule-drafts',
    title: '规则变更草案',
    description: 'LLM 或反馈学习提出的规则调整，必须人工确认。',
    endpoint: '/api/admin/data/model-rule-change-drafts',
    domain: 'model-rule-change-drafts',
    columns: [
      { key: 'modelKey', label: '模型', width: 160 },
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'riskLevel', label: '风险', type: 'status', width: 82 },
      { key: 'createdAt', label: '创建', type: 'date', width: 150 },
    ],
  },
];

const reportDatasets: DatasetDefinition[] = [
  {
    key: 'reports',
    title: '报告与日记',
    description: '日报、日记、模板结果、确认状态和 LLM 润色状态。',
    endpoint: '/api/admin/data/reports',
    domain: 'reports',
    columns: [
      { key: 'title', label: '标题', width: 240 },
      { key: 'reportType', label: '类型', type: 'status', width: 92 },
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'periodStart', label: '开始', type: 'date', width: 150 },
      { key: 'periodEnd', label: '结束', type: 'date', width: 150 },
      { key: 'createdAt', label: '创建', type: 'date', width: 150 },
    ],
  },
  {
    key: 'report-entries',
    title: '报告条目',
    description: 'fact、inferred、ai_summary、user_note 和 evidence links。',
    endpoint: '/api/admin/data/report-entries',
    domain: 'report-entries',
    columns: [
      { key: 'entryType', label: '类型', type: 'status', width: 110 },
      { key: 'title', label: '标题', width: 240 },
      { key: 'importance', label: '重要性', type: 'number', width: 82 },
      { key: 'source', label: '来源', width: 120 },
      { key: 'createdAt', label: '创建', type: 'date', width: 150 },
    ],
  },
  {
    key: 'push-deliveries',
    title: '推送记录',
    description: 'Telegram、Webhook、系统通知等出站推送结果和失败重试。',
    endpoint: '/api/admin/data/push-deliveries',
    domain: 'push-deliveries',
    columns: [
      { key: 'channelType', label: '渠道', width: 120 },
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'target', label: '目标', width: 180 },
      { key: 'lastError', label: '错误', width: 240 },
      { key: 'createdAt', label: '创建', type: 'date', width: 150 },
    ],
  },
  {
    key: 'weather-locations',
    title: '天气地点',
    description: '默认天气地点、Provider 和报告接入状态。',
    endpoint: '/api/admin/data/weather-locations',
    domain: 'weather-locations',
    columns: [
      { key: 'label', label: '名称', width: 180 },
      { key: 'provider', label: 'Provider', width: 120 },
      { key: 'latitude', label: '纬度', type: 'number', width: 96 },
      { key: 'longitude', label: '经度', type: 'number', width: 96 },
      { key: 'updatedAt', label: '更新', type: 'date', width: 150 },
    ],
  },
];

const monitoringDatasets: DatasetDefinition[] = [
  {
    key: 'audit-logs',
    title: '审计日志',
    description: '所有设置修改、受控执行、冲突处理、文件操作和外部写入审计。',
    endpoint: '/api/admin/data/audit-logs',
    domain: 'audit-logs',
    columns: [
      { key: 'action', label: '动作', width: 180 },
      { key: 'actor', label: '操作者', width: 150 },
      { key: 'targetType', label: '目标类型', width: 120 },
      { key: 'targetId', label: '目标', width: 180 },
      { key: 'createdAt', label: '时间', type: 'date', width: 150 },
    ],
  },
  {
    key: 'jobs',
    title: '后台任务',
    description: '模型、报告、同步、文件、推送等后台任务运行状态。',
    endpoint: '/api/admin/monitoring/jobs',
    columns: [
      { key: 'jobKey', label: '任务', width: 180 },
      { key: 'status', label: '状态', type: 'status', width: 92 },
      { key: 'lastRunAt', label: '最近运行', type: 'date', width: 150 },
      { key: 'lastError', label: '错误', width: 240 },
    ],
  },
];

function App() {
  const [apiBase, setApiBase] = useState(() => localStorage.getItem('flowplan.admin.apiBase') ?? defaultApiBase);
  const [deviceId] = useState(() => {
    const cached = localStorage.getItem('flowplan.admin.deviceId');
    if (cached) return cached;
    const next = safeRandomId();
    localStorage.setItem('flowplan.admin.deviceId', next);
    return next;
  });
  const [activeModule, setActiveModule] = useState<ModuleKey>('dashboard');
  const [selectedDeviceId, setSelectedDeviceId] = useState('all');
  const [devices, setDevices] = useState<DeviceOption[]>([]);
  const [connection, setConnection] = useState<ConnectionState>('checking');
  const [serverInfo, setServerInfo] = useState<ApiRecord | null>(null);
  const [lastHealthError, setLastHealthError] = useState('');
  const [lastHealthAt, setLastHealthAt] = useState('');
  const [infoBaseline, setInfoBaseline] = useState(() => new Date().toISOString());
  const [newInfoCount, setNewInfoCount] = useState(0);
  const [detail, setDetail] = useState<DetailState | null>(null);
  const [toast, setToast] = useState('');

  const context = useMemo<AdminContext>(
    () => ({
      apiBase: normalizeApiBase(apiBase),
      userId: defaultUserId,
      deviceId,
    }),
    [apiBase, deviceId],
  );

  const request = useCallback(
    async <T,>(path: string, options: RequestInit = {}): Promise<T> => {
      const headers = new Headers(options.headers);
      if (!headers.has('content-type') && options.body) headers.set('content-type', 'application/json');
      headers.set('x-flowplan-user-id', context.userId);
      headers.set('x-flowplan-device-id', context.deviceId);
      headers.set('x-flowplan-platform', 'web-admin');
      const url = buildApiUrl(context.apiBase, path);
      const response = await fetch(url, { ...options, headers });
      const text = await response.text();
      if (!response.ok) {
        throw new Error(formatHttpError(response, text));
      }
      return parseApiResponse<T>(text);
    },
    [context],
  );

  const checkHealth = useCallback(async () => {
    setConnection('checking');
    try {
      const info = await request<ApiRecord>('/api/health');
      setServerInfo(info);
      setConnection('online');
      setLastHealthError('');
      setLastHealthAt(new Date().toLocaleTimeString());
    } catch (error) {
      setConnection('offline');
      setLastHealthError(errorMessage(error));
      setLastHealthAt(new Date().toLocaleTimeString());
    }
  }, [request]);

  const loadDevices = useCallback(async () => {
    try {
      const result = await request<unknown>('/api/admin/data/devices?limit=200');
      const nextDevices = extractRows(result)
        .map((row) => {
          const id = displayValue(row.id ?? row.deviceId);
          if (!id || id === '无') return null;
          const name = displayValue(row.deviceName ?? row.name ?? '未命名设备');
          const detail = [row.platform, row.connectionStatus ?? row.status].map(displayValue).filter((item) => item !== '无').join(' / ');
          return { id, name, detail };
        })
        .filter((item): item is DeviceOption => Boolean(item));
      setDevices(nextDevices);
      setSelectedDeviceId((current) => (current === 'all' || nextDevices.some((device) => device.id === current) ? current : 'all'));
    } catch {
      setDevices([]);
    }
  }, [request]);

  const pollNewInfo = useCallback(async () => {
    try {
      const search = new URLSearchParams({ since: infoBaseline });
      if (selectedDeviceId !== 'all') search.set('deviceId', selectedDeviceId);
      const result = await request<ApiRecord>(`/api/admin/new-info?${search.toString()}`);
      setNewInfoCount(toCount(result.total ?? result.count));
    } catch {
      setNewInfoCount(0);
    }
  }, [infoBaseline, request, selectedDeviceId]);

  const markDataRefreshed = useCallback(() => {
    setInfoBaseline(new Date().toISOString());
    setNewInfoCount(0);
  }, []);

  useEffect(() => {
    void checkHealth();
    void loadDevices();
  }, [checkHealth, loadDevices]);

  useEffect(() => {
    void pollNewInfo();
    const timer = window.setInterval(() => void pollNewInfo(), 15000);
    return () => window.clearInterval(timer);
  }, [pollNewInfo]);

  const saveConnectionSettings = () => {
    const normalized = normalizeApiBase(apiBase);
    setApiBase(normalized);
    localStorage.setItem('flowplan.admin.apiBase', normalized);
    setToast('连接设置已保存');
    void checkHealth();
    void loadDevices();
  };

  const openDetail = async (dataset: DatasetDefinition | undefined, row: ApiRecord) => {
    const title = `${dataset?.title ?? '详情'} / ${displayValue(pickId(row) ?? row.title ?? row.name ?? row.uid ?? '')}`;
    setDetail({ title, dataset, row, loading: Boolean(dataset?.domain) });
    if (!dataset?.domain) return;
    const id = pickId(row);
    if (!id) return;
    try {
      const loaded = await request<unknown>(`/api/admin/data/${dataset.domain}/${encodeURIComponent(String(id))}`);
      setDetail({ title, dataset, row, detail: loaded, loading: false });
    } catch (error) {
      setDetail({ title, dataset, row, loading: false, error: errorMessage(error) });
    }
  };

  const moduleDescription = modules.find((item) => item.key === activeModule)?.description;

  return (
    <div className="admin-shell">
      <aside className="sidebar">
        <div className="brand">
          <div>
            <strong>FlowPlan</strong>
            <span>全局管理控制台</span>
          </div>
        </div>
        <nav className="module-nav">
          {modules.map((item) => (
            <button
              className={item.key === activeModule ? 'active' : ''}
              key={item.key}
              onClick={() => setActiveModule(item.key)}
              type="button"
            >
              <span>{item.label}</span>
              <small>{item.description}</small>
            </button>
          ))}
        </nav>
      </aside>

      <main className="main-pane">
        <header className="topbar">
          <div>
            <h1>{modules.find((item) => item.key === activeModule)?.label}</h1>
            <p>{moduleDescription}</p>
          </div>
          <ServerIndicator
            apiBase={context.apiBase}
            connection={connection}
            lastHealthAt={lastHealthAt}
            lastHealthError={lastHealthError}
            newInfoCount={newInfoCount}
            serverInfo={serverInfo}
            onRefresh={checkHealth}
          />
        </header>

        <ConnectionPanel
          apiBase={apiBase}
          devices={devices}
          selectedDeviceId={selectedDeviceId}
          setApiBase={setApiBase}
          setSelectedDeviceId={setSelectedDeviceId}
          onSave={saveConnectionSettings}
        />

        {toast ? (
          <div className="toast" role="status">
            {toast}
            <button className="plain" onClick={() => setToast('')} type="button">
              关闭
            </button>
          </div>
        ) : null}

        {activeModule === 'dashboard' ? (
          <DashboardPage request={request} onDataRefresh={markDataRefreshed} onOpenDetail={openDetail} />
        ) : null}
        {activeModule === 'data' ? (
          <ModulePage
            datasets={dataCenterDatasets}
            intro="这里是服务端事实库的业务数据入口。表格展示业务字段，点击任意行查看审计、关联对象和原始 JSON。"
            selectedDeviceId={selectedDeviceId}
            request={request}
            onDataRefresh={markDataRefreshed}
            onOpenDetail={openDetail}
          />
        ) : null}
        {activeModule === 'settings' ? (
          <SettingsPage request={request} onDataRefresh={markDataRefreshed} onToast={setToast} />
        ) : null}
        {activeModule === 'sync' ? (
          <SyncPage request={request} selectedDeviceId={selectedDeviceId} onDataRefresh={markDataRefreshed} onOpenDetail={openDetail} onToast={setToast} />
        ) : null}
        {activeModule === 'files' ? (
          <ModulePage
            datasets={fileDatasets}
            intro="文件中心只展示服务端云盘事实树和服务端存储状态。本地路径只表示某个设备的副本。"
            selectedDeviceId={selectedDeviceId}
            request={request}
            onDataRefresh={markDataRefreshed}
            onOpenDetail={openDetail}
          />
        ) : null}
        {activeModule === 'models' ? (
          <ModelsPage request={request} onDataRefresh={markDataRefreshed} onOpenDetail={openDetail} onToast={setToast} />
        ) : null}
        {activeModule === 'reports' ? (
          <ModulePage
            datasets={reportDatasets}
            intro="报告与日记必须保留证据来源，推送失败可在这里追踪并重试。"
            selectedDeviceId={selectedDeviceId}
            request={request}
            onDataRefresh={markDataRefreshed}
            onOpenDetail={openDetail}
          />
        ) : null}
        {activeModule === 'monitoring' ? (
          <MonitoringPage request={request} selectedDeviceId={selectedDeviceId} onDataRefresh={markDataRefreshed} onOpenDetail={openDetail} />
        ) : null}
        {activeModule === 'operations' ? (
          <OperationsPage request={request} onToast={setToast} />
        ) : null}
      </main>

      {detail ? <DetailDrawer detail={detail} onClose={() => setDetail(null)} /> : null}
    </div>
  );
}

function ConnectionPanel(props: {
  apiBase: string;
  devices: DeviceOption[];
  selectedDeviceId: string;
  setApiBase: (value: string) => void;
  setSelectedDeviceId: (value: string) => void;
  onSave: () => void;
}) {
  return (
    <section className="connection-strip">
      <label>
        服务端地址
        <input value={props.apiBase} onChange={(event) => props.setApiBase(event.target.value)} />
      </label>
      <label>
        设备
        <select value={props.selectedDeviceId} onChange={(event) => props.setSelectedDeviceId(event.target.value)}>
          <option value="all">全部设备</option>
          {props.devices.map((device) => (
            <option key={device.id} value={device.id}>
              {device.detail ? `${device.name}（${device.detail}）` : device.name}
            </option>
          ))}
        </select>
      </label>
      <div className="connection-actions">
        <button className="secondary" onClick={props.onSave} type="button">
          保存并刷新连接
        </button>
      </div>
    </section>
  );
}

function ServerIndicator(props: {
  apiBase: string;
  connection: ConnectionState;
  lastHealthAt: string;
  lastHealthError: string;
  newInfoCount: number;
  serverInfo: ApiRecord | null;
  onRefresh: () => void;
}) {
  const text =
    props.connection === 'online'
      ? `${displayValue(props.serverInfo?.service ?? '服务端在线')} / ${displayValue(props.serverInfo?.phase ?? 'phase')}`
      : props.connection === 'checking'
        ? '正在检测服务端'
        : `不可达：${props.lastHealthError || '未知错误'}`;
  return (
    <button className={`server-indicator ${props.connection}`} onClick={props.onRefresh} type="button">
      <span className={`server-dot ${props.connection}`} />
      <span>
        <strong>{text}</strong>
        <small>
          {props.apiBase}
          {props.lastHealthAt ? `，${props.lastHealthAt}` : ''}
          {props.newInfoCount > 0 ? `，新信息 ${props.newInfoCount}` : '，无新信息'}
        </small>
      </span>
    </button>
  );
}

function DashboardPage(props: {
  request: <T,>(path: string, options?: RequestInit) => Promise<T>;
  onDataRefresh: () => void;
  onOpenDetail: (dataset: DatasetDefinition | undefined, row: ApiRecord) => void;
}) {
  const { onDataRefresh, request } = props;
  const [dashboard, setDashboard] = useState<ApiRecord | null>(null);
  const [health, setHealth] = useState<ApiRecord | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const [dashboardResult, healthResult] = await Promise.all([
        request<ApiRecord>('/api/admin/dashboard'),
        request<ApiRecord>('/api/admin/monitoring/health'),
      ]);
      setDashboard(dashboardResult);
      setHealth(healthResult);
      onDataRefresh();
    } catch (loadError) {
      setError(errorMessage(loadError));
    } finally {
      setLoading(false);
    }
  }, [onDataRefresh, request]);

  useEffect(() => {
    void load();
  }, [load]);

  if (loading) return <LoadingBlock label="正在加载全局状态" />;
  if (error) return <ErrorBlock message={error} onRetry={load} />;

  const overview = asRecord(dashboard?.overview);
  const syncHealth = asRecord(dashboard?.syncHealth);
  const pending = asRecord(dashboard?.pending);
  const objectCounts = asArray(overview?.objectCounts ?? overview?.counts);
  const recentAuditLogs = asArray(dashboard?.recentAuditLogs);
  const healthCards = flattenHealth(health);

  return (
    <div className="page-grid">
      <section className="hero-panel">
        <div>
          <h2>系统总览</h2>
          <p>这里汇总服务健康、事实库规模、同步风险、最近审计和后台任务状态。</p>
        </div>
        <button className="secondary" onClick={load} type="button">
          刷新总览
        </button>
      </section>

      <div className="metric-grid">
        <MetricCard label="同步冲突" value={pending?.conflicts ?? syncHealth?.conflicts ?? 0} tone="warn" />
        <MetricCard label="AI 待审草案" value={pending?.aiDrafts ?? 0} tone="info" />
        <MetricCard label="失败推送" value={pending?.failedPushes ?? 0} tone="danger" />
        <MetricCard label="失败后台任务" value={pending?.failedJobs ?? 0} tone="danger" />
      </div>

      <section className="console-panel">
        <PanelHeader title="健康检查" description="数据库、API、对象存储、Kopia、同步积压和失败任务。" />
        <div className="health-grid">
          {healthCards.map((item) => (
            <StatusSummary key={item.key} label={item.label} value={item.value} detail={item.detail} />
          ))}
        </div>
      </section>

      <section className="console-panel">
        <PanelHeader title="数据规模" description="服务端事实库中主要对象数量。" />
        <div className="metric-grid compact">
          {objectCounts.length ? (
            objectCounts.slice(0, 12).map((item, index) => {
              const record = asRecord(item);
              return (
                <MetricCard
                  key={`${displayValue(record.type ?? record.objectType ?? index)}`}
                  label={displayValue(record.type ?? record.objectType ?? record.label ?? `对象 ${index + 1}`)}
                  value={record.count ?? record.total ?? 0}
                />
              );
            })
          ) : (
            <EmptyState text="服务端没有返回对象数量。请检查 /api/admin/dashboard 的 overview.objectCounts。" />
          )}
        </div>
      </section>

      <section className="console-panel">
        <PanelHeader title="最近审计" description="所有高风险操作、设置修改和受控执行都应在这里留下痕迹。" />
        <MiniTable
          columns={[
            { key: 'action', label: '动作', width: 180 },
            { key: 'actor', label: '操作者', width: 140 },
            { key: 'targetType', label: '目标', width: 120 },
            { key: 'createdAt', label: '时间', type: 'date', width: 150 },
          ]}
          rows={recentAuditLogs.map(asRecord)}
          onOpen={(row) => props.onOpenDetail(undefined, row)}
        />
      </section>
    </div>
  );
}

function ModulePage(props: {
  datasets: DatasetDefinition[];
  intro: string;
  selectedDeviceId: string;
  request: <T,>(path: string, options?: RequestInit) => Promise<T>;
  onDataRefresh: () => void;
  onOpenDetail: (dataset: DatasetDefinition | undefined, row: ApiRecord) => void;
}) {
  return (
    <div className="page-grid">
      <section className="hero-panel">
        <div>
          <h2>模块控制台</h2>
          <p>{props.intro}</p>
        </div>
      </section>
      {props.datasets.map((dataset) => (
        <DatasetPanel
          dataset={dataset}
          key={dataset.key}
          selectedDeviceId={props.selectedDeviceId}
          request={props.request}
          onDataRefresh={props.onDataRefresh}
          onOpenDetail={(row) => props.onOpenDetail(dataset, row)}
        />
      ))}
    </div>
  );
}

function DatasetPanel(props: {
  dataset: DatasetDefinition;
  selectedDeviceId: string;
  request: <T,>(path: string, options?: RequestInit) => Promise<T>;
  onDataRefresh: () => void;
  onOpenDetail: (row: ApiRecord) => void;
}) {
  const { dataset, onDataRefresh, request, selectedDeviceId } = props;
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('');
  const [limit, setLimit] = useState(dataset.defaultLimit ?? 50);
  const [payload, setPayload] = useState<unknown>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const search = new URLSearchParams();
      if (query.trim()) search.set('q', query.trim());
      if (status.trim()) search.set('status', status.trim());
      if (selectedDeviceId !== 'all' && deviceFilterDatasets.has(dataset.key)) search.set('deviceId', selectedDeviceId);
      search.set('limit', String(limit));
      const joiner = dataset.endpoint.includes('?') ? '&' : '?';
      const result = await request<unknown>(`${dataset.endpoint}${joiner}${search.toString()}`);
      setPayload(result);
      onDataRefresh();
    } catch (loadError) {
      setError(errorMessage(loadError));
    } finally {
      setLoading(false);
    }
  }, [dataset.endpoint, limit, onDataRefresh, query, request, selectedDeviceId, status]);

  useEffect(() => {
    void load();
  }, [load]);

  const rows = extractRows(payload);
  const sections = extractSections(payload);

  return (
    <section className="console-panel">
      <PanelHeader title={props.dataset.title} description={props.dataset.description}>
        <button className="secondary" onClick={load} type="button">
          刷新
        </button>
      </PanelHeader>
      <div className="filter-row">
        <input placeholder="关键字" value={query} onChange={(event) => setQuery(event.target.value)} />
        <input placeholder="状态过滤" value={status} onChange={(event) => setStatus(event.target.value)} />
        <select value={limit} onChange={(event) => setLimit(Number(event.target.value))}>
          <option value={20}>20 条</option>
          <option value={50}>50 条</option>
          <option value={100}>100 条</option>
          <option value={200}>200 条</option>
        </select>
        <button onClick={load} type="button">
          查询
        </button>
      </div>
      {loading ? <LoadingBlock label={`正在加载${props.dataset.title}`} /> : null}
      {error ? <ErrorBlock message={error} onRetry={load} /> : null}
      {!loading && !error ? (
        <>
          <MiniTable columns={props.dataset.columns} rows={rows} onOpen={props.onOpenDetail} />
          {sections.length > 1 ? (
            <details className="raw-sections">
              <summary>返回数据分区</summary>
              <div className="section-list">
                {sections.map((section) => (
                  <span key={section.name}>
                    {section.name}: {section.rows.length}
                  </span>
                ))}
              </div>
            </details>
          ) : null}
        </>
      ) : null}
    </section>
  );
}

function SettingsPage(props: {
  request: <T,>(path: string, options?: RequestInit) => Promise<T>;
  onDataRefresh: () => void;
  onToast: (message: string) => void;
}) {
  const { onDataRefresh, request } = props;
  const [settings, setSettings] = useState<ApiRecord | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [editingKey, setEditingKey] = useState('');
  const [editingScope, setEditingScope] = useState('user.preference');
  const [editingValue, setEditingValue] = useState('{}');
  const [isSensitive, setIsSensitive] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      const result = await request<ApiRecord>('/api/admin/settings');
      setSettings(result);
      onDataRefresh();
    } catch (loadError) {
      setError(errorMessage(loadError));
    } finally {
      setLoading(false);
    }
  }, [onDataRefresh, request]);

  useEffect(() => {
    void load();
  }, [load]);

  const save = async () => {
    if (!editingKey.trim()) {
      props.onToast('请输入设置 key');
      return;
    }
    try {
      const parsed = parseJsonOrString(editingValue);
      await request(`/api/admin/settings/${encodeURIComponent(editingKey.trim())}`, {
        method: 'PATCH',
        body: JSON.stringify({
          value: parsed,
          scope: editingScope,
          isSensitive,
          reason: 'web_admin settings update',
        }),
      });
      props.onToast(`已保存设置：${editingKey}`);
      void load();
    } catch (saveError) {
      props.onToast(`保存失败：${errorMessage(saveError)}`);
    }
  };

  const grouped = settingGroups(settings);

  return (
    <div className="page-grid">
      <section className="hero-panel">
        <div>
          <h2>远程设置中心</h2>
          <p>通用设置应存放在服务端并由所有客户端同步。设备本地设置只保留窗口、权限、本机路径和 token。</p>
        </div>
        <button className="secondary" onClick={load} type="button">
          刷新设置
        </button>
      </section>

      <section className="console-panel">
        <PanelHeader title="编辑远程设置" description="敏感字段只允许更新，不应在管理端明文回显。" />
        <div className="settings-editor">
          <label>
            设置 Key
            <input placeholder="例如 scheduler.policy.work_hours" value={editingKey} onChange={(event) => setEditingKey(event.target.value)} />
          </label>
          <label>
            Scope
            <select value={editingScope} onChange={(event) => setEditingScope(event.target.value)}>
              <option value="user.preference">user.preference</option>
              <option value="sync.policy">sync.policy</option>
              <option value="ai.provider">ai.provider</option>
              <option value="file.provider">file.provider</option>
              <option value="report.push">report.push</option>
              <option value="scheduler.policy">scheduler.policy</option>
              <option value="activity.rules">activity.rules</option>
              <option value="outlook.connection">outlook.connection</option>
            </select>
          </label>
          <label className="checkbox-row">
            <input checked={isSensitive} type="checkbox" onChange={(event) => setIsSensitive(event.target.checked)} />
            敏感字段
          </label>
          <label className="span-all">
            值 JSON
            <textarea value={editingValue} onChange={(event) => setEditingValue(event.target.value)} />
          </label>
          <button onClick={save} type="button">
            保存并审计
          </button>
        </div>
      </section>

      {loading ? <LoadingBlock label="正在加载远程设置" /> : null}
      {error ? <ErrorBlock message={error} onRetry={load} /> : null}
      {!loading && !error
        ? grouped.map((group) => (
            <section className="console-panel" key={group.scope}>
              <PanelHeader title={group.scope} description={`${group.items.length} 个设置项`} />
              <MiniTable
                columns={[
                  { key: 'configKey', label: 'Key', width: 280 },
                  { key: 'isSensitive', label: '敏感', type: 'status', width: 76 },
                  { key: 'version', label: '版本', type: 'number', width: 72 },
                  { key: 'updatedAt', label: '更新', type: 'date', width: 150 },
                  { key: 'valuePreview', label: '值预览', width: 320 },
                ]}
                rows={group.items}
                onOpen={(row) => {
                  setEditingKey(displayValue(row.configKey ?? row.key));
                  setEditingScope(displayValue(row.scope ?? group.scope));
                  setIsSensitive(Boolean(row.isSensitive));
                  setEditingValue(JSON.stringify(row.configValue ?? row.value ?? {}, null, 2));
                }}
              />
            </section>
          ))
        : null}
    </div>
  );
}

function SyncPage(props: {
  request: <T,>(path: string, options?: RequestInit) => Promise<T>;
  selectedDeviceId: string;
  onDataRefresh: () => void;
  onOpenDetail: (dataset: DatasetDefinition | undefined, row: ApiRecord) => void;
  onToast: (message: string) => void;
}) {
  const { onDataRefresh, request, selectedDeviceId } = props;
  const [summary, setSummary] = useState<ApiRecord | null>(null);

  const loadSummary = useCallback(async () => {
    try {
      const search = new URLSearchParams();
      if (selectedDeviceId !== 'all') search.set('deviceId', selectedDeviceId);
      const suffix = search.toString() ? `?${search.toString()}` : '';
      const result = await request<ApiRecord>(`/api/admin/devices/online-summary${suffix}`);
      setSummary(result);
      onDataRefresh();
    } catch {
      setSummary(null);
    }
  }, [onDataRefresh, request, selectedDeviceId]);

  useEffect(() => {
    void loadSummary();
  }, [loadSummary]);

  return (
    <div className="page-grid">
      <section className="hero-panel">
        <div>
          <h2>同步与客户端</h2>
          <p>每个客户端都应持续心跳、自动同步。冲突和失败不能被静默覆盖。</p>
        </div>
        <button className="secondary" onClick={loadSummary} type="button">
          刷新在线状态
        </button>
      </section>
      <div className="metric-grid">
        <MetricCard label="在线设备" value={summary?.online ?? summary?.onlineCount ?? 0} tone="good" />
        <MetricCard label="异常设备" value={summary?.degraded ?? summary?.degradedCount ?? 0} tone="warn" />
        <MetricCard label="离线设备" value={summary?.offline ?? summary?.offlineCount ?? 0} tone="danger" />
        <MetricCard label="最近事件" value={summary?.recentEvents ?? summary?.eventCount ?? 0} />
      </div>
      <ModulePage
        datasets={syncDatasets}
        intro="设备、心跳、同步变更、客户端 mutation 和冲突处理全部集中在这里。"
        selectedDeviceId={props.selectedDeviceId}
        request={props.request}
        onDataRefresh={props.onDataRefresh}
        onOpenDetail={props.onOpenDetail}
      />
    </div>
  );
}

function ModelsPage(props: {
  request: <T,>(path: string, options?: RequestInit) => Promise<T>;
  onDataRefresh: () => void;
  onOpenDetail: (dataset: DatasetDefinition | undefined, row: ApiRecord) => void;
  onToast: (message: string) => void;
}) {
  const [provider, setProvider] = useState('openai-compatible');
  const [baseUrl, setBaseUrl] = useState('');
  const [modelName, setModelName] = useState('');
  const [apiKey, setApiKey] = useState('');
  const [testResult, setTestResult] = useState('');

  const saveProvider = async () => {
    try {
      await props.request(`/api/ai/settings/${encodeURIComponent(provider || 'openai-compatible')}`, {
        method: 'PATCH',
        body: JSON.stringify({ baseUrl, modelName, apiKey }),
      });
      props.onToast('AI Provider 已保存，审计记录由服务端生成');
    } catch (error) {
      props.onToast(`AI Provider 保存失败：${errorMessage(error)}`);
    }
  };

  const testProvider = async () => {
    setTestResult('正在测试...');
    try {
      const result = await props.request<ApiRecord>(`/api/ai/settings/${encodeURIComponent(provider || 'openai-compatible')}/test`, {
        method: 'POST',
      });
      setTestResult(JSON.stringify(result, null, 2));
    } catch (error) {
      setTestResult(errorMessage(error));
    }
  };

  return (
    <div className="page-grid">
      <section className="hero-panel">
        <div>
          <h2>模型与 AI</h2>
          <p>AI 只能生成草案，受控执行器确认后才写事实库。高风险工具默认禁用。</p>
        </div>
      </section>
      <section className="console-panel">
        <PanelHeader title="AI Provider" description="配置 OpenAI-compatible Base URL、模型和 API Key。API Key 不应明文回显。" />
        <div className="settings-editor">
          <label>
            Provider
            <input value={provider} onChange={(event) => setProvider(event.target.value)} />
          </label>
          <label>
            Base URL
            <input value={baseUrl} onChange={(event) => setBaseUrl(event.target.value)} />
          </label>
          <label>
            模型
            <input value={modelName} onChange={(event) => setModelName(event.target.value)} />
          </label>
          <label>
            API Key
            <input type="password" value={apiKey} onChange={(event) => setApiKey(event.target.value)} />
          </label>
          <div className="button-row span-all">
            <button onClick={saveProvider} type="button">
              保存 Provider
            </button>
            <button className="secondary" onClick={testProvider} type="button">
              测试连接
            </button>
          </div>
          {testResult ? <pre className="span-all">{testResult}</pre> : null}
        </div>
      </section>
      <ModulePage
        datasets={modelDatasets}
        intro="模型运行、反馈、规则版本、AI 草案和权限边界都在这里集中审查。"
        selectedDeviceId="all"
        request={props.request}
        onDataRefresh={props.onDataRefresh}
        onOpenDetail={props.onOpenDetail}
      />
    </div>
  );
}

function MonitoringPage(props: {
  request: <T,>(path: string, options?: RequestInit) => Promise<T>;
  selectedDeviceId: string;
  onDataRefresh: () => void;
  onOpenDetail: (dataset: DatasetDefinition | undefined, row: ApiRecord) => void;
}) {
  const { onDataRefresh, request, selectedDeviceId } = props;
  const [health, setHealth] = useState<ApiRecord | null>(null);
  const [logs, setLogs] = useState<ApiRecord | null>(null);

  const load = useCallback(async () => {
    const search = new URLSearchParams();
    if (selectedDeviceId !== 'all') search.set('deviceId', selectedDeviceId);
    const suffix = search.toString() ? `?${search.toString()}` : '';
    const [healthResult, logsResult] = await Promise.all([
      request<ApiRecord>('/api/admin/monitoring/health'),
      request<ApiRecord>(`/api/admin/monitoring/logs${suffix}`),
    ]);
    setHealth(healthResult);
    setLogs(logsResult);
    onDataRefresh();
  }, [onDataRefresh, request, selectedDeviceId]);

  useEffect(() => {
    void load();
  }, [load]);

  return (
    <div className="page-grid">
      <section className="hero-panel">
        <div>
          <h2>监控与日志</h2>
          <p>这里用于排查服务端运行状态、失败队列、错误聚合和审计链路。</p>
        </div>
        <button className="secondary" onClick={load} type="button">
          刷新监控
        </button>
      </section>
      <section className="console-panel">
        <PanelHeader title="健康详情" description="接口返回的结构化监控信息。" />
        <pre>{JSON.stringify(health ?? {}, null, 2)}</pre>
      </section>
      <section className="console-panel">
        <PanelHeader title="错误与队列摘要" description="失败 mutation、冲突、审计和服务端日志摘要。" />
        <pre>{JSON.stringify(logs ?? {}, null, 2)}</pre>
      </section>
      <ModulePage
        datasets={monitoringDatasets}
        intro="日志表支持点击行查看原始 JSON。后续可以继续扩展同步日志、文件日志、AI 日志和推送日志。"
        selectedDeviceId={selectedDeviceId}
        request={props.request}
        onDataRefresh={onDataRefresh}
        onOpenDetail={props.onOpenDetail}
      />
    </div>
  );
}

function OperationsPage(props: {
  request: <T,>(path: string, options?: RequestInit) => Promise<T>;
  onToast: (message: string) => void;
}) {
  const [state, setState] = useState<OperationState>({
    operationKey: 'retry_sync',
    payload: '{\n  "reason": "web_admin operation"\n}',
  });

  const prepare = async () => {
    try {
      const payload = parseJsonOrString(state.payload);
      const prepared = await props.request<ApiRecord>(`/api/admin/operations/${encodeURIComponent(state.operationKey)}/prepare`, {
        method: 'POST',
        body: JSON.stringify({ payload, reason: 'web_admin prepare' }),
      });
      setState((current) => ({ ...current, prepared, result: undefined, error: undefined }));
    } catch (error) {
      setState((current) => ({ ...current, error: errorMessage(error) }));
    }
  };

  const confirm = async () => {
    try {
      const confirmationToken =
        displayValue(state.prepared?.confirmationToken) ||
        displayValue(asRecord(state.prepared?.operation)?.confirmationToken) ||
        'manual-confirm';
      const payload = parseJsonOrString(state.payload);
      const result = await props.request<ApiRecord>(`/api/admin/operations/${encodeURIComponent(state.operationKey)}/confirm`, {
        method: 'POST',
        body: JSON.stringify({
          payload,
          confirmationToken,
          reason: 'web_admin confirm',
        }),
      });
      setState((current) => ({ ...current, result, error: undefined }));
      props.onToast('操作已提交，服务端已写入审计或返回执行结果');
    } catch (error) {
      setState((current) => ({ ...current, error: errorMessage(error) }));
    }
  };

  return (
    <div className="page-grid">
      <section className="hero-panel">
        <div>
          <h2>受控运维操作</h2>
          <p>删除、覆盖、冲突强制处理、历史恢复、外部系统写入和批量修改必须先 prepare，再 confirm。</p>
        </div>
      </section>
      <section className="console-panel">
        <PanelHeader title="Prepare / Confirm" description="默认不直接执行高风险操作，先展示影响范围和确认令牌。" />
        <div className="operation-grid">
          <label>
            操作 Key
            <select value={state.operationKey} onChange={(event) => setState((current) => ({ ...current, operationKey: event.target.value }))}>
              <option value="retry_sync">retry_sync</option>
              <option value="resolve_conflict">resolve_conflict</option>
              <option value="retry_report_push">retry_report_push</option>
              <option value="run_job">run_job</option>
              <option value="recompute_analytics">recompute_analytics</option>
              <option value="check_storage">check_storage</option>
              <option value="export_diagnostics">export_diagnostics</option>
              <option value="restore_file_version">restore_file_version</option>
            </select>
          </label>
          <label>
            Payload JSON
            <textarea value={state.payload} onChange={(event) => setState((current) => ({ ...current, payload: event.target.value }))} />
          </label>
          <div className="button-row">
            <button onClick={prepare} type="button">
              Prepare
            </button>
            <button className="danger" disabled={!state.prepared} onClick={confirm} type="button">
              Confirm
            </button>
          </div>
          {state.error ? <ErrorBlock message={state.error} /> : null}
          {state.prepared ? (
            <div>
              <h3>Prepare 结果</h3>
              <pre>{JSON.stringify(state.prepared, null, 2)}</pre>
            </div>
          ) : null}
          {state.result ? (
            <div>
              <h3>Confirm 结果</h3>
              <pre>{JSON.stringify(state.result, null, 2)}</pre>
            </div>
          ) : null}
        </div>
      </section>
    </div>
  );
}

function PanelHeader(props: { title: string; description: string; children?: React.ReactNode }) {
  return (
    <div className="panel-header">
      <div>
        <h2>{props.title}</h2>
        <p>{props.description}</p>
      </div>
      {props.children ? <div className="panel-actions">{props.children}</div> : null}
    </div>
  );
}

function MetricCard(props: { label: string; value: unknown; tone?: 'good' | 'warn' | 'danger' | 'info' }) {
  return (
    <div className={`metric-card ${props.tone ?? ''}`}>
      <span>{props.label}</span>
      <strong>{displayValue(props.value)}</strong>
    </div>
  );
}

function StatusSummary(props: { label: string; value: unknown; detail?: string }) {
  return (
    <div className="status-summary">
      <span>{props.label}</span>
      <strong>{displayValue(props.value)}</strong>
      {props.detail ? <small>{props.detail}</small> : null}
    </div>
  );
}

function MiniTable(props: {
  columns: DatasetColumn[];
  rows: ApiRecord[];
  onOpen?: (row: ApiRecord) => void;
}) {
  if (!props.rows.length) return <EmptyState text="没有可展示的数据。" />;
  return (
    <div className="table-wrap">
      <table className="admin-table">
        <thead>
          <tr>
            {props.columns.map((column) => (
              <th key={column.key} style={{ minWidth: column.width }}>
                {column.label}
              </th>
            ))}
            <th className="action-col">详情</th>
          </tr>
        </thead>
        <tbody>
          {props.rows.map((row, index) => (
            <tr key={`${pickId(row) ?? index}`}>
              {props.columns.map((column) => (
                <td key={column.key} style={{ minWidth: column.width }}>
                  <CellValue column={column} row={row} />
                </td>
              ))}
              <td className="action-col">
                <button className="secondary small" onClick={() => props.onOpen?.(row)} type="button">
                  查看
                </button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function CellValue(props: { column: DatasetColumn; row: ApiRecord }) {
  const value = getNestedValue(props.row, props.column.key);
  if (props.column.type === 'status') return <StatusBadge value={value} />;
  if (props.column.type === 'date') return <span className="cell-muted">{formatDate(value)}</span>;
  if (props.column.type === 'json') return <code>{shortJson(value)}</code>;
  return <span title={displayValue(value)}>{displayValue(value)}</span>;
}

function StatusBadge(props: { value: unknown }) {
  const value = displayValue(props.value || 'unknown');
  const tone = statusTone(value);
  return <span className={`status-badge ${tone}`}>{value}</span>;
}

function DetailDrawer(props: { detail: DetailState; onClose: () => void }) {
  const detailRecord = asRecord(props.detail.detail);
  const business = detailRecord.business ?? detailRecord.item ?? props.detail.row;
  const auditTrail = asArray(detailRecord.auditTrail ?? detailRecord.auditLogs);
  const related = detailRecord.relatedObjects ?? detailRecord.syncState ?? {};
  return (
    <aside className="detail-drawer">
      <div className="drawer-header">
        <div>
          <h2>{props.detail.title}</h2>
          <p>{props.detail.dataset?.description ?? '原始对象详情'}</p>
        </div>
        <button className="secondary" onClick={props.onClose} type="button">
          关闭
        </button>
      </div>
      {props.detail.loading ? <LoadingBlock label="正在加载详情" /> : null}
      {props.detail.error ? <ErrorBlock message={props.detail.error} /> : null}
      <div className="drawer-tabs">
        <section>
          <h3>业务字段</h3>
          <KeyValueGrid value={business} />
        </section>
        <section>
          <h3>审计链路</h3>
          {auditTrail.length ? (
            <MiniTable
              columns={[
                { key: 'action', label: '动作', width: 160 },
                { key: 'actor', label: '操作者', width: 140 },
                { key: 'createdAt', label: '时间', type: 'date', width: 150 },
              ]}
              rows={auditTrail.map(asRecord)}
            />
          ) : (
            <EmptyState text="没有返回审计记录。" />
          )}
        </section>
        <section>
          <h3>关联与同步</h3>
          <pre>{JSON.stringify(related, null, 2)}</pre>
        </section>
        <section>
          <h3>原始 JSON</h3>
          <pre>{JSON.stringify(props.detail.detail ?? props.detail.row, null, 2)}</pre>
        </section>
      </div>
    </aside>
  );
}

function KeyValueGrid(props: { value: unknown }) {
  const record = asRecord(props.value);
  const entries = Object.entries(record).slice(0, 80);
  if (!entries.length) return <EmptyState text="没有业务字段。" />;
  return (
    <div className="kv-grid">
      {entries.map(([key, value]) => (
        <React.Fragment key={key}>
          <span>{key}</span>
          <strong>{typeof value === 'object' && value !== null ? shortJson(value) : displayValue(value)}</strong>
        </React.Fragment>
      ))}
    </div>
  );
}

function LoadingBlock(props: { label: string }) {
  return <div className="state-block">{props.label}...</div>;
}

function ErrorBlock(props: { message: string; onRetry?: () => void }) {
  return (
    <div className="state-block error">
      <span>{props.message}</span>
      {props.onRetry ? (
        <button className="secondary small" onClick={props.onRetry} type="button">
          重试
        </button>
      ) : null}
    </div>
  );
}

function EmptyState(props: { text: string }) {
  return <div className="empty-state">{props.text}</div>;
}

function asRecord(value: unknown): ApiRecord {
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as ApiRecord) : {};
}

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function extractRows(payload: unknown): ApiRecord[] {
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
  ].find((value) => Array.isArray(value));
  if (Array.isArray(direct)) return direct.map(asRecord);
  if (Array.isArray(payload)) return payload.map(asRecord);
  const sections = extractSections(payload);
  return sections[0]?.rows ?? [];
}

function extractSections(payload: unknown): Array<{ name: string; rows: ApiRecord[] }> {
  const record = asRecord(payload);
  const sections: Array<{ name: string; rows: ApiRecord[] }> = [];
  Object.entries(record).forEach(([key, value]) => {
    if (Array.isArray(value)) sections.push({ name: key, rows: value.map(asRecord) });
    const nested = asRecord(value);
    Object.entries(nested).forEach(([nestedKey, nestedValue]) => {
      if (Array.isArray(nestedValue)) sections.push({ name: `${key}.${nestedKey}`, rows: nestedValue.map(asRecord) });
    });
  });
  return sections;
}

function settingGroups(settings: ApiRecord | null): Array<{ scope: string; items: ApiRecord[] }> {
  const configs = extractRows(settings);
  const byScope = new Map<string, ApiRecord[]>();
  configs.forEach((item) => {
    const scope = displayValue(item.scope ?? 'default');
    const configValue = item.configValue ?? item.value;
    const valuePreview = Boolean(item.isSensitive) ? '********' : shortJson(configValue);
    const normalized = { ...item, valuePreview };
    byScope.set(scope, [...(byScope.get(scope) ?? []), normalized]);
  });
  return Array.from(byScope.entries()).map(([scope, items]) => ({ scope, items }));
}

function flattenHealth(health: ApiRecord | null): Array<{ key: string; label: string; value: unknown; detail?: string }> {
  const record = asRecord(health);
  const keys = ['database', 'api', 'storage', 'kopia', 'sync', 'jobs'];
  const rows = keys.map((key) => {
    const value = asRecord(record[key]);
    return {
      key,
      label: healthLabel(key),
      value: value.status ?? value.ok ?? value.available ?? record[key] ?? 'unknown',
      detail: displayValue(value.message ?? value.error ?? value.path ?? ''),
    };
  });
  if (rows.every((row) => row.value === 'unknown')) {
    return Object.entries(record).slice(0, 8).map(([key, value]) => ({
      key,
      label: key,
      value: typeof value === 'object' ? shortJson(value) : value,
    }));
  }
  return rows;
}

function healthLabel(key: string): string {
  const labels: Record<string, string> = {
    database: '数据库',
    api: 'API',
    storage: '对象存储',
    kopia: 'Kopia',
    sync: '同步积压',
    jobs: '后台任务',
  };
  return labels[key] ?? key;
}

function pickId(row: ApiRecord): unknown {
  return row.id ?? row.uid ?? row.objectUid ?? row.deviceId ?? row.batchId ?? row.configKey ?? row.key;
}

function getNestedValue(row: ApiRecord, key: string): unknown {
  const direct = row[key];
  if (direct !== undefined) return direct;
  const payload = asRecord(row.payload);
  const metadata = asRecord(row.metadata);
  return payload[key] ?? metadata[key] ?? row[toSnakeCase(key)] ?? payload[toSnakeCase(key)] ?? metadata[toSnakeCase(key)];
}

function toSnakeCase(value: string): string {
  return value.replace(/[A-Z]/g, (match) => `_${match.toLowerCase()}`);
}

function displayValue(value: unknown): string {
  if (value === null || value === undefined || value === '') return '无';
  if (typeof value === 'boolean') return value ? '是' : '否';
  if (typeof value === 'number') return Number.isFinite(value) ? String(value) : '无';
  if (typeof value === 'string') return value;
  return shortJson(value);
}

function toCount(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.max(0, Math.trunc(parsed)) : 0;
}

function shortJson(value: unknown): string {
  try {
    const text = JSON.stringify(value);
    return text.length > 140 ? `${text.slice(0, 137)}...` : text;
  } catch {
    return String(value);
  }
}

function formatDate(value: unknown): string {
  if (!value) return '无';
  const date = new Date(String(value));
  if (Number.isNaN(date.getTime())) return displayValue(value);
  return date.toLocaleString();
}

function statusTone(value: string): string {
  const normalized = value.toLowerCase();
  if (['online', 'ok', 'synced', 'completed', 'success', 'active', '是'].some((item) => normalized.includes(item))) return 'good';
  if (['pending', 'draft', 'checking', 'running', 'syncing', 'open'].some((item) => normalized.includes(item))) return 'warn';
  if (['failed', 'offline', 'error', 'conflict', 'revoked', 'deleted'].some((item) => normalized.includes(item))) return 'danger';
  return 'neutral';
}

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

function normalizeApiBase(value: string): string {
  const trimmed = value.trim().replace(/\/+$/, '');
  if (!trimmed) return defaultApiBase;
  try {
    const url = new URL(trimmed);
    if (url.pathname === '/api') {
      url.pathname = '';
    } else if (url.pathname.endsWith('/api')) {
      url.pathname = url.pathname.slice(0, -4);
    }
    url.search = '';
    url.hash = '';
    return url.toString().replace(/\/$/, '');
  } catch {
    return trimmed;
  }
}

function buildApiUrl(apiBase: string, path: string): string {
  if (path.startsWith('http')) return path;
  const base = normalizeApiBase(apiBase);
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  return `${base}${normalizedPath}`;
}

function formatHttpError(response: Response, text: string): string {
  const detail = extractErrorDetail(text);
  const status = `${response.status} ${response.statusText}`.trim();
  return detail ? `${status}: ${detail}` : status;
}

function extractErrorDetail(text: string): string {
  const trimmed = text.trim();
  if (!trimmed) return '';
  try {
    const parsed = JSON.parse(trimmed) as ApiRecord;
    const message = parsed.message;
    if (Array.isArray(message)) return message.join('; ');
    if (typeof message === 'string') return message;
    if (typeof parsed.error === 'string') return parsed.error;
    return JSON.stringify(parsed);
  } catch {
    return trimmed;
  }
}

function parseApiResponse<T>(text: string): T {
  const trimmed = text.trim();
  if (!trimmed) return {} as T;
  try {
    return JSON.parse(trimmed) as T;
  } catch {
    throw new Error(`服务端返回了非 JSON 响应：${trimmed.slice(0, 200)}`);
  }
}

function parseJsonOrString(text: string): unknown {
  const trimmed = text.trim();
  if (!trimmed) return {};
  try {
    return JSON.parse(trimmed);
  } catch {
    return trimmed;
  }
}

function safeRandomId(): string {
  if ('crypto' in window && typeof window.crypto.randomUUID === 'function') return window.crypto.randomUUID();
  return `web-admin-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

const root = createRoot(document.getElementById('root') as HTMLElement);
root.render(<App />);
