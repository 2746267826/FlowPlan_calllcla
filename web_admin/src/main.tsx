import React, { useEffect, useMemo, useState } from 'react';
import { createRoot } from 'react-dom/client';
import './styles.css';

type ApiRecord = Record<string, unknown>;

type ViewKey =
  | 'dashboard'
  | 'tasks'
  | 'schedules'
  | 'actuals'
  | 'tracking'
  | 'trackingIngestBatches'
  | 'trackingIngestChunks'
  | 'files'
  | 'reports'
  | 'activitySegments'
  | 'schedulerRuns'
  | 'fileRoots'
  | 'fileNodes'
  | 'fileTransfers'
  | 'aiAssistant'
  | 'aiPolicies'
  | 'modelCenter'
  | 'modelVersions'
  | 'modelRuns'
  | 'modelFeedback'
  | 'modelRuleDrafts'
  | 'reportEntries'
  | 'reportTemplates'
  | 'pushChannels'
  | 'pushDeliveries'
  | 'weather'
  | 'weatherLocations'
  | 'realityContext'
  | 'aiDrafts'
  | 'settings'
  | 'sync'
  | 'deviceConnections'
  | 'syncChanges'
  | 'syncMutations'
  | 'devices'
  | 'conflicts'
  | 'storage'
  | 'fileOperationLogs'
  | 'storageObjects'
  | 'logs'
  | 'jobs'
  | 'operations';

interface ViewDefinition {
  key: ViewKey;
  group: string;
  label: string;
  endpoint: string;
  description: string;
  domain?: string;
}

const views: ViewDefinition[] = [
  {
    key: 'dashboard',
    group: '总览',
    label: '运行总览',
    endpoint: '/api/admin/dashboard',
    description: '服务健康、数据规模、同步积压、近期错误和待处理事项。',
  },
  {
    key: 'tasks',
    group: '数据中心',
    label: '任务',
    endpoint: '/api/admin/data/tasks',
    domain: 'tasks',
    description: '服务端事实库中的任务、任务本和任务排程对象。',
  },
  {
    key: 'schedules',
    group: '数据中心',
    label: '日程',
    endpoint: '/api/admin/data/schedules',
    domain: 'schedules',
    description: '日程、阻挡日程、时间块和排程片段。',
  },
  {
    key: 'actuals',
    group: '数据中心',
    label: '实际记录',
    endpoint: '/api/admin/data/actuals',
    domain: 'actuals',
    description: '已确认或候选的实际活动记录。',
  },
  {
    key: 'tracking',
    group: '数据中心',
    label: '追踪摘要',
    endpoint: '/api/admin/data/tracking',
    domain: 'tracking',
    description: '追踪原始对象、活动记录和输入事件摘要。',
  },
  {
    key: 'trackingIngestBatches',
    group: '数据中心',
    label: '追踪上传批次',
    endpoint: '/api/admin/data/tracking-ingest-batches',
    domain: 'tracking-ingest-batches',
    description: '原生客户端分批/压缩上传追踪数据的批次状态、事件数量和失败原因。',
  },
  {
    key: 'trackingIngestChunks',
    group: '数据中心',
    label: '追踪上传分块',
    endpoint: '/api/admin/data/tracking-ingest-chunks',
    domain: 'tracking-ingest-chunks',
    description: '追踪上传批次中的 chunk 记录，用于排查断点续传和缺块问题。',
  },
  {
    key: 'files',
    group: '数据中心',
    label: '文件元数据',
    endpoint: '/api/admin/data/files',
    domain: 'files',
    description: '本地文件中心、资料库 Root、文件节点和上下文绑定。',
  },
  {
    key: 'reports',
    group: '数据中心',
    label: '报告与日记',
    endpoint: '/api/admin/data/reports',
    domain: 'reports',
    description: '日报、周报、自动日记和推送状态。',
  },
  {
    key: 'activitySegments',
    group: '数据中心',
    label: '活动片段',
    endpoint: '/api/admin/data/activity-segments',
    domain: 'activity-segments',
    description: '活动理解生成的片段、候选、确认状态和证据摘要。',
  },
  {
    key: 'schedulerRuns',
    group: '数据中心',
    label: '排程运行',
    endpoint: '/api/admin/data/schedule-runs',
    domain: 'schedule-runs',
    description: '排程草案运行、未排原因、确认/拒绝状态和偏离检测入口。',
  },
  {
    key: 'fileRoots',
    group: '文件与存储',
    label: '资料库 Root',
    endpoint: '/api/admin/data/file-roots',
    domain: 'file-roots',
    description: '本地资料库 Root、扫描状态、节点数量和失效路径排查。',
  },
  {
    key: 'fileNodes',
    group: '文件与存储',
    label: '文件节点',
    endpoint: '/api/admin/data/file-nodes',
    domain: 'file-nodes',
    description: '网盘式文件中心的文件夹/文件节点、路径、预览状态和缺失状态。',
  },
  {
    key: 'fileTransfers',
    group: '文件与存储',
    label: '传输路径与事件',
    endpoint: '/api/admin/data/transfer-events',
    domain: 'transfer-events',
    description: '分块传输事件、路径候选、速度状态和失败原因。',
  },
  {
    key: 'aiAssistant',
    group: '设置中心',
    label: 'AI 助手',
    endpoint: '/api/ai/settings',
    description: '配置 OpenAI-compatible API、测试连接、发送受控请求、审核 create_task 草案和活动解释建议。',
  },
  {
    key: 'aiPolicies',
    group: '设置中心',
    label: 'AI 工具策略',
    endpoint: '/api/admin/data/ai-policies',
    domain: 'ai-policies',
    description: 'AI 可用工具、风险等级、人工确认和二次确认策略。',
  },
  {
    key: 'modelCenter',
    group: '设置中心',
    label: '模型中心',
    endpoint: '/api/models',
    description: '服务端模型定义、启用版本、运行次数和反馈数量。',
  },
  {
    key: 'modelVersions',
    group: '设置中心',
    label: '模型版本',
    endpoint: '/api/admin/data/model-versions',
    domain: 'model-versions',
    description: '模型规则权重、学习生成版本、启用状态和回滚依据。',
  },
  {
    key: 'modelRuns',
    group: '监控与日志',
    label: '模型运行日志',
    endpoint: '/api/admin/data/model-runs',
    domain: 'model-runs',
    description: '模型运行输入摘要、输出摘要、置信度和 LLM 托底状态。',
  },
  {
    key: 'modelFeedback',
    group: '监控与日志',
    label: '模型反馈学习',
    endpoint: '/api/admin/data/model-feedback',
    domain: 'model-feedback',
    description: '用户确认、拒绝、修改、手动关联等反馈样本。',
  },
  {
    key: 'modelRuleDrafts',
    group: '运维操作',
    label: '模型规则变更草案',
    endpoint: '/api/admin/data/model-rule-change-drafts',
    domain: 'model-rule-change-drafts',
    description: '反馈学习或 LLM 分析提出的规则改动，启用前必须人工确认。',
  },
  {
    key: 'reportEntries',
    group: '数据中心',
    label: '报告条目',
    endpoint: '/api/admin/data/report-entries',
    domain: 'report-entries',
    description: '日报、日记、周报中的事实、推断和外部信息条目。',
  },
  {
    key: 'reportTemplates',
    group: '设置中心',
    label: '报告模板',
    endpoint: '/api/admin/data/report-templates',
    domain: 'report-templates',
    description: '日报、周报、月报、日记和推送摘要的模板配置。',
  },
  {
    key: 'pushChannels',
    group: '设置中心',
    label: '推送渠道',
    endpoint: '/api/admin/data/push-channels',
    domain: 'push-channels',
    description: 'Telegram、Webhook 等报告出站渠道配置。',
  },
  {
    key: 'pushDeliveries',
    group: '监控与日志',
    label: '报告推送记录',
    endpoint: '/api/admin/data/push-deliveries',
    domain: 'push-deliveries',
    description: '报告推送成功、失败、重试次数和错误原因。',
  },
  {
    key: 'weather',
    group: '监控与日志',
    label: '天气与现实上下文',
    endpoint: '/api/admin/data/weather-cache',
    domain: 'weather-cache',
    description: '天气缓存、现实上下文来源和报告引用状态。',
  },
  {
    key: 'weatherLocations',
    group: '设置中心',
    label: '天气地点',
    endpoint: '/api/admin/data/weather-locations',
    domain: 'weather-locations',
    description: '手动配置的默认天气地点；当前不采集 GPS。',
  },
  {
    key: 'realityContext',
    group: '设置中心',
    label: '现实上下文预留',
    endpoint: '/api/admin/data/reality-context',
    domain: 'reality-context',
    description: '位置、蓝牙、硬件上下文的未来占位状态；当前不采集。',
  },
  {
    key: 'aiDrafts',
    group: '数据中心',
    label: 'AI 草案',
    endpoint: '/api/admin/data/ai-drafts',
    domain: 'ai-drafts',
    description: 'AI 生成的操作草案，执行前必须人工确认。',
  },
  {
    key: 'settings',
    group: '设置中心',
    label: '远程设置',
    endpoint: '/api/admin/settings',
    domain: 'settings',
    description: '服务端管理的工作时间、同步策略、AI、文件、报告和活动规则。',
  },
  {
    key: 'sync',
    group: '同步与设备',
    label: '同步健康',
    endpoint: '/api/admin/sync-health',
    description: '同步游标、最近 mutation 结果和冲突状态。',
  },
  {
    key: 'deviceConnections',
    group: '同步与设备',
    label: '客户端在线',
    endpoint: '/api/admin/devices/online-summary',
    description: '所有客户端的在线、离线、异常和最近 24 小时连接事件概览。',
  },
  {
    key: 'syncChanges',
    group: '同步与设备',
    label: '服务端变更',
    endpoint: '/api/admin/data/sync-changes',
    domain: 'sync-changes',
    description: '服务端事实库变更日志，客户端通过游标消费这些变化。',
  },
  {
    key: 'syncMutations',
    group: '同步与设备',
    label: '客户端写入队列',
    endpoint: '/api/admin/data/sync-mutations',
    domain: 'sync-mutations',
    description: '各客户端上报的 pending、failed、rejected mutation 记录。',
  },
  {
    key: 'devices',
    group: '同步与设备',
    label: '设备',
    endpoint: '/api/admin/data/devices',
    domain: 'devices',
    description: '客户端设备、心跳、平台和在线状态。',
  },
  {
    key: 'conflicts',
    group: '同步与设备',
    label: '冲突',
    endpoint: '/api/admin/conflicts',
    description: '同步冲突候选。处理必须有人工确认和审计。',
  },
  {
    key: 'storage',
    group: '文件与存储',
    label: '服务端存储',
    endpoint: '/api/files/dashboard',
    description: 'server_storage、传输会话、Kopia 版本、下载请求和文件冲突。',
  },
  {
    key: 'storageObjects',
    group: '文件与存储',
    label: '存储对象',
    endpoint: '/api/files/storage/objects',
    description: '服务端真实保存的文件对象、hash、大小和状态。',
  },
  {
    key: 'fileOperationLogs',
    group: '文件与存储',
    label: '文件操作日志',
    endpoint: '/api/admin/data/file-operation-logs',
    domain: 'file-operation-logs',
    description: '文件打开、绑定、下载、重定位、版本操作的审计化日志。',
  },
  {
    key: 'logs',
    group: '监控与日志',
    label: '日志',
    endpoint: '/api/admin/monitoring/logs',
    description: '审计日志、失败同步、冲突和错误聚合。',
  },
  {
    key: 'jobs',
    group: '监控与日志',
    label: '后台任务',
    endpoint: '/api/admin/monitoring/jobs',
    description: '后台任务计划、状态、错误和下次运行时间。',
  },
  {
    key: 'operations',
    group: '运维操作',
    label: '受控操作',
    endpoint: '/api/admin/monitoring/health',
    description: '重试同步、运行任务、生成诊断包等操作必须 prepare 后 confirm。',
  },
];

const storage = {
  apiBase: 'flowplan.admin.apiBase',
  userId: 'flowplan.admin.userId',
  displayName: 'flowplan.admin.displayName',
  deviceId: 'flowplan.admin.deviceId',
};

const defaultApiBase = 'http://localhost:3200';
const reservedApiBase = 'http://localhost:3000';

const labels: Record<string, string> = {
  id: 'ID',
  title: '标题',
  name: '名称',
  status: '状态',
  objectType: '对象类型',
  uid: 'UID',
  deviceName: '设备名',
  platform: '平台',
  clientDeviceId: '客户端设备 ID',
  lastSeenAt: '最后心跳',
  pullCursor: '拉取游标',
  configKey: '设置键',
  configValue: '设置值',
  scope: '范围',
  version: '版本',
  updatedAt: '更新时间',
  createdAt: '创建时间',
  action: '动作',
  actor: '操作者',
  summary: '摘要',
  targetType: '目标类型',
  targetId: '目标 ID',
  localId: '本地 ID',
  mutationUid: 'Mutation UID',
  lastError: '最后错误',
  displayName: '显示名',
  localPath: '本地路径',
  provider: 'Provider',
  fileName: '文件名',
  sizeBytes: '大小',
  startAt: '开始',
  endAt: '结束',
};

const valueLabels: Record<string, string> = {
  online: '在线',
  recent: '最近在线',
  stale: '较久未同步',
  never_seen: '从未在线',
  open: '待处理',
  resolved: '已解决',
  failed: '失败',
  pending: '等待中',
  pending_review: '待审核',
  approved: '已批准',
  rejected: '已拒绝',
  synced: '已同步',
  conflict: '冲突',
  local: '本地',
  server_storage: '服务端存储',
  onedrive: 'OneDrive',
  running: '运行中',
  idle: '空闲',
  paused: '暂停',
  enabled: '启用',
  disabled: '停用',
};

function App() {
  const [apiBase, setApiBase] = useState(
    () => {
      const saved = localStorage.getItem(storage.apiBase);
      return saved === reservedApiBase ? defaultApiBase : saved ?? defaultApiBase;
    },
  );
  const [userId, setUserId] = useState(
    () => localStorage.getItem(storage.userId) ?? '',
  );
  const [displayName, setDisplayName] = useState(
    () => localStorage.getItem(storage.displayName) ?? 'FlowPlan 管理员',
  );
  const [deviceId] = useState(() => ensureDeviceId());
  const [view, setView] = useState<ViewKey>('dashboard');
  const [data, setData] = useState<ApiRecord>({});
  const [detail, setDetail] = useState<ApiRecord | null>(null);
  const [query, setQuery] = useState('');
  const [status, setStatus] = useState('未连接');
  const [loading, setLoading] = useState(false);
  const [settingsDraft, setSettingsDraft] = useState('{}');
  const [operationToken, setOperationToken] = useState('');
  const [operationKey, setOperationKey] = useState('retry_sync');
  const [revokeDeviceId, setRevokeDeviceId] = useState('');
  const [revokeReason, setRevokeReason] = useState('revoked_from_admin');

  const current = useMemo(
    () => views.find((item) => item.key === view) ?? views[0],
    [view],
  );
  const loggedIn = userId.trim().length > 0;
  const groupedViews = useMemo(() => groupViews(views), []);

  useEffect(() => {
    if (loggedIn) {
      void loadCurrent();
    }
  }, [view, loggedIn]);

  async function login(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    setStatus('正在登录');
    try {
      const response = await request('/api/auth/login', {
        method: 'POST',
        body: JSON.stringify({ userId: userId || undefined, displayName }),
      });
      const user = asRecord(response.user);
      const nextUserId = String(user.id ?? userId);
      localStorage.setItem(storage.apiBase, apiBase);
      localStorage.setItem(storage.userId, nextUserId);
      localStorage.setItem(storage.displayName, displayName);
      setUserId(nextUserId);
      setStatus('已登录');
    } catch (error) {
      setStatus(errorMessage(error));
    } finally {
      setLoading(false);
    }
  }

  async function loadCurrent() {
    setLoading(true);
    setDetail(null);
    setStatus(`正在加载：${current.label}`);
    try {
      const result = await request(buildEndpoint(current.endpoint));
      setData(asRecord(result));
      setStatus(`已加载：${current.label}`);
    } catch (error) {
      setData({});
      setStatus(errorMessage(error));
    } finally {
      setLoading(false);
    }
  }

  async function request(path: string, init: RequestInit = {}) {
    const response = await fetch(`${apiBase}${path}`, {
      ...init,
      headers: {
        accept: 'application/json',
        'content-type': 'application/json',
        'x-flowplan-user-id': userId || '00000000-0000-4000-8000-000000000001',
        'x-flowplan-device-id': deviceId,
        ...(init.headers ?? {}),
      },
    });
    if (!response.ok) {
      const body = await response.text();
      throw new Error(`${response.status} ${response.statusText}${body ? `：${body}` : ''}`);
    }
    return (await response.json()) as ApiRecord;
  }

  function buildEndpoint(endpoint: string) {
    const trimmed = query.trim();
    if (!trimmed) {
      return endpoint;
    }
    const separator = endpoint.includes('?') ? '&' : '?';
    return `${endpoint}${separator}q=${encodeURIComponent(trimmed)}`;
  }

  async function openDetail(row: ApiRecord) {
    setDetail(row);
    const id = row.id?.toString();
    if (!id || !current.domain) {
      return;
    }
    try {
      const response =
        current.key === 'devices'
          ? await request(
              `/api/admin/devices/${encodeURIComponent(id)}/connection-history`,
            )
          : await request(
              `/api/admin/data/${current.domain}/${encodeURIComponent(id)}`,
            );
      setDetail({ ...row, __detail: response });
    } catch {
      setDetail(row);
    }
  }

  async function upsertSetting(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const key = String(form.get('key') ?? '').trim();
    if (!key) {
      setStatus('请填写设置键');
      return;
    }
    setLoading(true);
    try {
      await request(`/api/admin/settings/${encodeURIComponent(key)}`, {
        method: 'PATCH',
        body: JSON.stringify({
          configValue: parseJsonObject(String(form.get('value') ?? '{}')),
          scope: String(form.get('scope') ?? 'user.preference'),
          description: String(form.get('description') ?? ''),
          isSensitive: form.get('sensitive') === 'on',
        }),
      });
      event.currentTarget.reset();
      setSettingsDraft('{}');
      setStatus('远程设置已保存，并已写入审计日志');
      await loadCurrent();
    } catch (error) {
      setStatus(errorMessage(error));
    } finally {
      setLoading(false);
    }
  }

  async function prepareOperation(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setLoading(true);
    try {
      const response = await request(
        `/api/admin/operations/${encodeURIComponent(operationKey)}/prepare`,
        {
          method: 'POST',
          body: JSON.stringify({
            dryRun: true,
            reason: 'admin-console-prepare',
            payload: parseJsonObject(settingsDraft),
          }),
        },
      );
      setOperationToken(String(response.confirmationToken ?? ''));
      setDetail(response);
      setStatus('已生成 prepare 结果，请核对影响范围后再确认');
    } catch (error) {
      setStatus(errorMessage(error));
    } finally {
      setLoading(false);
    }
  }

  async function confirmOperation() {
    if (!operationToken) {
      setStatus('请先执行 prepare，获得确认 token');
      return;
    }
    setLoading(true);
    try {
      const response = await request(
        `/api/admin/operations/${encodeURIComponent(operationKey)}/confirm`,
        {
          method: 'POST',
          body: JSON.stringify({
            confirmationToken: operationToken,
            reason: 'admin-console-confirm',
            payload: parseJsonObject(settingsDraft),
          }),
        },
      );
      setDetail(response);
      setStatus('操作已确认并写入审计');
    } catch (error) {
      setStatus(errorMessage(error));
    } finally {
      setLoading(false);
    }
  }

  async function revokeDevice(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const targetDeviceId = revokeDeviceId.trim();
    if (!targetDeviceId) {
      setStatus('请输入要撤销的设备 ID');
      return;
    }
    setLoading(true);
    try {
      const response = await request(
        `/api/devices/${encodeURIComponent(targetDeviceId)}/revoke`,
        {
          method: 'POST',
          body: JSON.stringify({
            reason: revokeReason || 'revoked_from_admin',
          }),
        },
      );
      setDetail(response);
      setStatus('设备已撤销，后续 heartbeat/sync 会返回 device_revoked。');
      setRevokeDeviceId('');
      await loadCurrent();
    } catch (error) {
      setStatus(errorMessage(error));
    } finally {
      setLoading(false);
    }
  }

  if (!loggedIn) {
    return (
      <main className="login-shell">
        <form className="login-panel" onSubmit={login}>
          <div>
            <h1>FlowPlan 管理控制台</h1>
            <p>单事实库全局控制台：管理所有客户端共享的数据、设置、监控、日志和受控操作。</p>
          </div>
          <label>
            服务端地址
            <input value={apiBase} onChange={(event) => setApiBase(event.target.value)} />
          </label>
          <label>
            用户 ID
            <input value={userId} onChange={(event) => setUserId(event.target.value)} />
          </label>
          <label>
            显示名称
            <input
              value={displayName}
              onChange={(event) => setDisplayName(event.target.value)}
            />
          </label>
          <button type="submit" disabled={loading}>登录</button>
          <span className="status-line">{status}</span>
        </form>
      </main>
    );
  }

  return (
    <main className="admin-shell">
      <aside className="sidebar">
        <div className="brand">
          <strong>FlowPlan</strong>
          <span>单事实库全局控制台</span>
        </div>
        <nav>
          {groupedViews.map(([group, items]) => (
            <section key={group} className="nav-group">
              <h2>{group}</h2>
              {items.map((item) => (
                <button
                  key={item.key}
                  className={item.key === view ? 'active' : ''}
                  onClick={() => setView(item.key)}
                >
                  {item.label}
                </button>
              ))}
            </section>
          ))}
        </nav>
      </aside>
      <section className="workspace">
        <header className="topbar">
          <div>
            <h1>{current.label}</h1>
            <p>{current.description}</p>
          </div>
          <div className="topbar-actions">
            <input
              value={query}
              onChange={(event) => setQuery(event.target.value)}
              placeholder="搜索标题、ID、路径或错误"
            />
            <button onClick={loadCurrent} disabled={loading}>刷新</button>
          </div>
        </header>
        <div className="status-ribbon">
          <span>{status}</span>
          <span>用户：{displayName}</span>
          <span>设备：{deviceId.slice(0, 8)}</span>
          <span>范围：全部数据与全部客户端</span>
        </div>
        <section className="content-grid">
          <article className="main-panel">{renderCurrent()}</article>
          <DetailPanel detail={detail} data={data} />
        </section>
      </section>
    </main>
  );

  function renderCurrent() {
    if (view === 'dashboard') {
      return <Dashboard data={data} onOpen={setDetail} />;
    }
    if (view === 'settings') {
      return (
        <>
          <SettingForm
            draft={settingsDraft}
            setDraft={setSettingsDraft}
            onSubmit={upsertSetting}
          />
          <DataSections data={data} onOpen={openDetail} />
        </>
      );
    }
    if (view === 'aiAssistant') {
      return (
        <AiAssistantPanel
          data={data}
          request={request}
          loading={loading}
          setStatus={setStatus}
          setDetail={setDetail}
          reload={loadCurrent}
        />
      );
    }
    if (view === 'devices') {
      return (
        <>
          <form className="operation-panel" onSubmit={revokeDevice}>
            <label>
              撤销设备 ID
              <input
                value={revokeDeviceId}
                onChange={(event) => setRevokeDeviceId(event.target.value)}
                placeholder="复制设备列表中的 id"
              />
            </label>
            <label>
              撤销原因
              <input
                value={revokeReason}
                onChange={(event) => setRevokeReason(event.target.value)}
              />
            </label>
            <button type="submit" disabled={loading}>撤销设备</button>
            <p>撤销会写入审计日志，并阻止该设备继续 heartbeat、push 和 pull。误撤销时需要客户端重新注册或重新登录。</p>
          </form>
          <DataSections data={data} onOpen={openDetail} />
        </>
      );
    }
    if (view === 'operations') {
      return (
        <>
          <form className="operation-panel" onSubmit={prepareOperation}>
            <label>
              操作类型
              <select value={operationKey} onChange={(event) => setOperationKey(event.target.value)}>
                <option value="retry_sync">重试同步</option>
                <option value="resolve_conflict">处理冲突</option>
                <option value="run_job">运行后台任务</option>
                <option value="export_diagnostics">生成诊断包</option>
                <option value="recompute_analytics">重新计算统计摘要</option>
                <option value="retry_report_push">重试报告推送</option>
                <option value="check_storage">检查服务端存储</option>
              </select>
            </label>
            <label>
              参数 JSON
              <textarea value={settingsDraft} onChange={(event) => setSettingsDraft(event.target.value)} />
            </label>
            <div className="inline-actions">
              <button type="submit" disabled={loading}>Prepare</button>
              <button type="button" onClick={confirmOperation} disabled={loading || !operationToken}>
                Confirm
              </button>
            </div>
            <p>管理端是全局操作面。删除、覆盖、冲突强制处理、外部系统写入和历史恢复都必须先 prepare、核对影响范围，再 confirm 并写入审计。</p>
          </form>
          <DataSections data={data} onOpen={openDetail} />
        </>
      );
    }
    return <DataSections data={data} onOpen={openDetail} />;
  }
}

function Dashboard({
  data,
  onOpen,
}: {
  data: ApiRecord;
  onOpen: (row: ApiRecord) => void;
}) {
  const overview = asRecord(data.overview);
  const pending = asRecord(data.pending);
  return (
    <>
      <section className="metric-grid">
        <MetricCard title="待处理" values={pending} tone="warning" />
        <MetricCard title="同步对象" values={asRecord(overview.objectCounts)} />
        <MetricCard title="设备" values={asRecord(overview.deviceCounts)} />
        <MetricCard title="冲突" values={asRecord(overview.conflictCounts)} tone="danger" />
        <MetricCard title="文件" values={asRecord(overview.fileCounts)} />
        <MetricCard title="AI 草案" values={asRecord(overview.draftCounts)} />
      </section>
      <DataSections data={data} onOpen={onOpen} />
    </>
  );
}

function AiAssistantPanel({
  data,
  request,
  loading,
  setStatus,
  setDetail,
  reload,
}: {
  data: ApiRecord;
  request: (path: string, init?: RequestInit) => Promise<ApiRecord>;
  loading: boolean;
  setStatus: (value: string) => void;
  setDetail: (value: ApiRecord | null) => void;
  reload: () => Promise<void>;
}) {
  const providers = Array.isArray(data.providers) ? data.providers as ApiRecord[] : [];
  const defaultProvider = asRecord(data.defaultProvider ?? providers[0]);
  const [providerKey, setProviderKey] = useState(String(defaultProvider.providerKey ?? 'default'));
  const [displayName, setDisplayName] = useState(String(defaultProvider.displayName ?? '默认 Provider'));
  const [baseUrl, setBaseUrl] = useState(String(defaultProvider.baseUrl ?? 'https://api.openai.com/v1'));
  const [model, setModel] = useState(String(defaultProvider.model ?? ''));
  const [apiKey, setApiKey] = useState('');
  const [message, setMessage] = useState('帮我创建一个明天截止的数据库作业任务');
  const [conversationId, setConversationId] = useState('');
  const [drafts, setDrafts] = useState<ApiRecord[]>([]);
  const [activitySegmentId, setActivitySegmentId] = useState('');
  const [confirmationPhrase, setConfirmationPhrase] = useState('');

  useEffect(() => {
    setProviderKey(String(defaultProvider.providerKey ?? 'default'));
    setDisplayName(String(defaultProvider.displayName ?? '默认 Provider'));
    setBaseUrl(String(defaultProvider.baseUrl ?? 'https://api.openai.com/v1'));
    setModel(String(defaultProvider.model ?? ''));
  }, [data]);

  async function saveProvider(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const response = await request(`/api/ai/settings/${encodeURIComponent(providerKey)}`, {
      method: 'PATCH',
      body: JSON.stringify({
        providerType: 'openai_compatible',
        displayName,
        baseUrl,
        model,
        apiKey: apiKey || undefined,
        status: 'enabled',
        isDefault: true,
      }),
    });
    setDetail(response);
    setStatus('AI Provider 已保存，API Key 只在服务端加密保存。');
    setApiKey('');
    await reload();
  }

  async function testProvider() {
    const response = await request(`/api/ai/settings/${encodeURIComponent(providerKey)}/test`, {
      method: 'POST',
    });
    setDetail(response);
    setStatus('AI Provider 连接测试成功。');
    await reload();
  }

  async function sendMessage(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const response = await request('/api/ai/messages', {
      method: 'POST',
      body: JSON.stringify({
        conversationId: conversationId || undefined,
        title: '管理端 AI 受控任务草案',
        source: 'web_admin',
        providerKey,
        content: message,
      }),
    });
    const nextConversationId = String(response.conversationId ?? conversationId);
    setConversationId(nextConversationId);
    setDetail(response);
    setStatus('AI 已返回。若涉及写入，只会生成 OperationDraft，不会直接写库。');
    await loadDrafts();
  }

  async function loadDrafts() {
    const response = await request('/api/ai/tool-drafts?limit=20');
    const nextDrafts = Array.isArray(response.drafts) ? response.drafts as ApiRecord[] : [];
    setDrafts(nextDrafts);
    setDetail(response);
  }

  async function rejectDraft(draftId: string) {
    const response = await request(`/api/ai/tool-drafts/${encodeURIComponent(draftId)}`, {
      method: 'PATCH',
      body: JSON.stringify({
        status: 'rejected',
        reviewNote: 'Rejected in Web Admin AI MVP panel.',
      }),
    });
    setDetail(response);
    setStatus('草案已拒绝，未写入服务端事实库。');
    await loadDrafts();
  }

  async function confirmDraft(draftId: string) {
    const response = await request(`/api/ai/tool-drafts/${encodeURIComponent(draftId)}/confirm`, {
      method: 'POST',
      body: JSON.stringify({
        reviewNote: 'Confirmed in Web Admin AI MVP panel.',
        confirmationPhrase: confirmationPhrase || undefined,
      }),
    });
    setDetail(response);
    setStatus('草案已确认，由受控执行器写入服务端事实库和变更日志。');
    await loadDrafts();
  }

  async function explainActivity(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!activitySegmentId.trim()) {
      setStatus('请先填写低置信度 activity segment ID。');
      return;
    }
    const response = await request(
      `/api/ai/activity-segments/${encodeURIComponent(activitySegmentId.trim())}/explain`,
      {
        method: 'POST',
        body: JSON.stringify({ providerKey }),
      },
    );
    setDetail(response);
    setStatus('已生成 LLM 活动解释建议；它只是建议，不会确认实际记录。');
    await loadDrafts();
  }

  return (
    <section className="ai-console">
      <form className="ai-card" onSubmit={saveProvider}>
        <header>
          <h2>OpenAI-compatible Provider</h2>
          <span>Base URL、模型名和 API Key 保存在服务端，修改会写入审计。</span>
        </header>
        <div className="ai-form-grid">
          <label>
            Provider Key
            <input value={providerKey} onChange={(event) => setProviderKey(event.target.value)} />
          </label>
          <label>
            显示名
            <input value={displayName} onChange={(event) => setDisplayName(event.target.value)} />
          </label>
          <label>
            Base URL
            <input value={baseUrl} onChange={(event) => setBaseUrl(event.target.value)} />
          </label>
          <label>
            模型名
            <input value={model} onChange={(event) => setModel(event.target.value)} />
          </label>
          <label>
            API Key
            <input
              value={apiKey}
              onChange={(event) => setApiKey(event.target.value)}
              placeholder={String(defaultProvider.apiKeyState ?? '保存后服务端加密')}
              type="password"
            />
          </label>
        </div>
        <div className="inline-actions">
          <button type="submit" disabled={loading}>保存 Provider</button>
          <button type="button" className="ghost" onClick={testProvider} disabled={loading}>
            测试连接
          </button>
        </div>
      </form>

      <form className="ai-card" onSubmit={sendMessage}>
        <header>
          <h2>受控 AI 聊天</h2>
          <span>当前 MVP 只允许 AI 生成 create_task 草案，不能直接写库。</span>
        </header>
        <textarea value={message} onChange={(event) => setMessage(event.target.value)} />
        <div className="inline-actions">
          <button type="submit" disabled={loading}>发送并生成草案</button>
          <button type="button" className="ghost" onClick={loadDrafts} disabled={loading}>
            刷新草案
          </button>
        </div>
      </form>

      <form className="ai-card" onSubmit={explainActivity}>
        <header>
          <h2>低置信活动片段解释建议</h2>
          <span>LLM 只生成解释建议，不确认 actual_activity_logs。</span>
        </header>
        <input
          value={activitySegmentId}
          onChange={(event) => setActivitySegmentId(event.target.value)}
          placeholder="activity_segments.id"
        />
        <button type="submit" disabled={loading}>生成解释建议</button>
      </form>

      <section className="ai-card">
        <header>
          <h2>OperationDraft 审核</h2>
          <span>拒绝不写库；确认后仅 create_task 由受控执行器执行。</span>
        </header>
        <label>
          高风险二次确认短语
          <input
            value={confirmationPhrase}
            onChange={(event) => setConfirmationPhrase(event.target.value)}
            placeholder="需要时输入 CONFIRM"
          />
        </label>
        <div className="draft-list">
          {drafts.length === 0 ? (
            <p className="hint">暂无草案。发送示例请求后点击刷新草案。</p>
          ) : (
            drafts.map((draft) => (
              <DraftCard
                key={String(draft.id)}
                draft={draft}
                onReject={rejectDraft}
                onConfirm={confirmDraft}
              />
            ))
          )}
        </div>
      </section>
    </section>
  );
}

function DraftCard({
  draft,
  onReject,
  onConfirm,
}: {
  draft: ApiRecord;
  onReject: (draftId: string) => Promise<void>;
  onConfirm: (draftId: string) => Promise<void>;
}) {
  const payload = asRecord(draft.proposedPayload ?? draft.proposed_payload);
  const draftId = String(draft.id ?? '');
  return (
    <article className="draft-card">
      <div>
        <strong>{String(draft.title ?? 'AI 草案')}</strong>
        <span>{String(draft.proposedAction ?? draft.proposed_action ?? '')}</span>
      </div>
      <dl>
        <dt>任务标题</dt>
        <dd>{String(payload.title ?? '-')}</dd>
        <dt>截止时间</dt>
        <dd>{String(payload.dueAt ?? payload.due_at ?? '-')}</dd>
        <dt>预计耗时</dt>
        <dd>{String(payload.estimatedMinutes ?? payload.estimated_minutes ?? '-')} 分钟</dd>
        <dt>任务本</dt>
        <dd>{String(payload.taskBookName ?? payload.taskBookId ?? '-')}</dd>
        <dt>风险等级</dt>
        <dd>{String(draft.riskLevel ?? draft.risk_level ?? '-')}</dd>
        <dt>执行状态</dt>
        <dd>{String(draft.executionStatus ?? draft.execution_status ?? draft.status ?? '-')}</dd>
      </dl>
      <div className="inline-actions">
        <button type="button" className="ghost" onClick={() => onReject(draftId)}>
          拒绝
        </button>
        <button type="button" onClick={() => onConfirm(draftId)}>
          确认执行
        </button>
      </div>
    </article>
  );
}

function SettingForm({
  draft,
  setDraft,
  onSubmit,
}: {
  draft: string;
  setDraft: (value: string) => void;
  onSubmit: (event: React.FormEvent<HTMLFormElement>) => void;
}) {
  return (
    <form className="setting-form" onSubmit={onSubmit}>
      <input name="key" placeholder="设置键，例如 sync.policy.auto_interval" />
      <select name="scope" defaultValue="sync.policy">
        <option value="user.preference">用户偏好</option>
        <option value="sync.policy">同步策略</option>
        <option value="ai.provider">AI Provider</option>
        <option value="file.provider">文件 Provider</option>
        <option value="report.push">报告推送</option>
        <option value="scheduler.policy">排程策略</option>
        <option value="activity.rules">活动规则</option>
      </select>
      <input name="description" placeholder="说明" />
      <textarea name="value" value={draft} onChange={(event) => setDraft(event.target.value)} />
      <label className="check">
        <input name="sensitive" type="checkbox" />
        敏感字段
      </label>
      <button type="submit">保存远程设置</button>
    </form>
  );
}

function DataSections({
  data,
  onOpen,
}: {
  data: ApiRecord;
  onOpen: (row: ApiRecord) => void;
}) {
  const sections = extractSections(data);
  if (sections.length === 0) {
    return <div className="empty">暂无数据</div>;
  }
  return (
    <>
      {sections.map(([name, rows]) => (
        <section key={name} className="data-section">
          <header>
            <h2>{sectionTitle(name)}</h2>
            <span>{rows.length} 条</span>
          </header>
          <DataTable rows={rows} onOpen={onOpen} />
        </section>
      ))}
    </>
  );
}

function DataTable({
  rows,
  onOpen,
}: {
  rows: ApiRecord[];
  onOpen: (row: ApiRecord) => void;
}) {
  const columns = preferredColumns(rows);
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            {columns.map((column) => (
              <th key={column}>{fieldLabel(column)}</th>
            ))}
            <th>操作</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row, index) => (
            <tr key={String(row.id ?? row.uid ?? row.configKey ?? index)}>
              {columns.map((column) => (
                <td key={column}>{cellText(row[column])}</td>
              ))}
              <td>
                <button className="ghost" onClick={() => onOpen(row)}>详情</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function DetailPanel({
  detail,
  data,
}: {
  detail: ApiRecord | null;
  data: ApiRecord;
}) {
  const target = detail ?? data;
  const business = detail ? stripRaw(detail) : {};
  const nestedSections = detail ? extractSections(asRecord(detail.__detail)) : [];
  return (
    <aside className="detail-panel">
      <header>
        <h2>{detail ? '详情' : '原始响应'}</h2>
        <span>原始 JSON 仅用于核对</span>
      </header>
      {detail ? (
        <>
          <section className="field-list">
            {Object.entries(business).map(([key, value]) => (
              <div key={key}>
                <strong>{fieldLabel(key)}</strong>
                <span>{cellText(value)}</span>
              </div>
            ))}
          </section>
          {nestedSections.map(([key, rows]) => (
            <section className="data-section compact" key={key}>
              <header>
                <h3>{sectionTitle(key)}</h3>
                <span>{rows.length} 条</span>
              </header>
              <DataTable rows={rows.slice(0, 20)} onOpen={() => undefined} />
            </section>
          ))}
        </>
      ) : (
        <p className="hint">选择表格中的一行查看业务字段、审计和原始数据。</p>
      )}
      <details open>
        <summary>原始数据</summary>
        <pre>{JSON.stringify(target, null, 2)}</pre>
      </details>
    </aside>
  );
}

function MetricCard({
  title,
  values,
  tone = 'normal',
}: {
  title: string;
  values: ApiRecord;
  tone?: 'normal' | 'warning' | 'danger';
}) {
  const entries = Object.entries(values);
  const total = entries.reduce((sum, [, value]) => sum + numberValue(value), 0);
  return (
    <article className={`metric-card ${tone}`}>
      <span>{title}</span>
      <strong>{total}</strong>
      <div>
        {entries.slice(0, 5).map(([key, value]) => (
          <em key={key}>{translateValue(key)}：{String(value)}</em>
        ))}
      </div>
    </article>
  );
}

function extractSections(data: ApiRecord): [string, ApiRecord[]][] {
  const sections: [string, ApiRecord[]][] = [];
  for (const [key, value] of Object.entries(data)) {
    if (Array.isArray(value)) {
      const rows = value.filter(isRecord);
      if (rows.length > 0) {
        sections.push([key, rows]);
      }
    } else if (isRecord(value)) {
      const nested = extractSections(value);
      for (const [nestedKey, nestedRows] of nested) {
        sections.push([`${key}.${nestedKey}`, nestedRows]);
      }
    }
  }
  return sections;
}

function preferredColumns(rows: ApiRecord[]) {
  const all = rows.length > 0 ? Object.keys(rows[0]) : [];
  const preferred = [
    'id',
    'title',
    'displayName',
    'objectType',
    'status',
    'connectionStatus',
    'scope',
    'version',
    'deviceName',
    'platform',
    'appVersion',
    'lastHeartbeatAt',
    'lastSeenAt',
    'syncPendingCount',
    'syncFailedCount',
    'openConflictCount',
    'updatedAt',
    'createdAt',
  ].filter((key) => all.includes(key));
  const rest = all.filter((key) => !preferred.includes(key)).slice(0, 5);
  return [...preferred, ...rest].slice(0, 8);
}

function groupViews(items: ViewDefinition[]) {
  const groups = new Map<string, ViewDefinition[]>();
  for (const item of items) {
    groups.set(item.group, [...(groups.get(item.group) ?? []), item]);
  }
  return Array.from(groups.entries());
}

function ensureDeviceId() {
  const existing = localStorage.getItem(storage.deviceId);
  if (existing) {
    return existing;
  }
  const next =
    typeof crypto !== 'undefined' && 'randomUUID' in crypto
      ? crypto.randomUUID()
      : '00000000-0000-4000-8000-000000000909';
  localStorage.setItem(storage.deviceId, next);
  return next;
}

function asRecord(value: unknown): ApiRecord {
  return isRecord(value) ? value : {};
}

function isRecord(value: unknown): value is ApiRecord {
  return !!value && typeof value === 'object' && !Array.isArray(value);
}

function parseJsonObject(value: string) {
  if (!value.trim()) {
    return {};
  }
  const parsed = JSON.parse(value);
  return isRecord(parsed) ? parsed : {};
}

function stripRaw(row: ApiRecord) {
  const result: ApiRecord = {};
  for (const [key, value] of Object.entries(row)) {
    if (key === 'payload' || key === 'metadata' || key === '__detail') {
      continue;
    }
    result[key] = value;
  }
  return result;
}

function cellText(value: unknown) {
  if (value == null) {
    return '';
  }
  if (typeof value === 'object') {
    return JSON.stringify(value).slice(0, 160);
  }
  return translateValue(String(value));
}

function numberValue(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}

function fieldLabel(field: string) {
  return labels[field] ? `${labels[field]}（${field}）` : field;
}

function sectionTitle(key: string) {
  const known: Record<string, string> = {
    items: '列表',
    devices: '设备',
    conflicts: '冲突',
    configs: '远程设置',
    jobs: '后台任务',
    auditLogs: '审计日志',
    failedMutations: '失败同步',
    storageObjects: '服务端对象',
    transfers: '传输会话',
    versionRecords: '历史版本',
    recentAuditLogs: '最近审计',
    events: '连接历史',
    device: '设备详情',
  };
  return known[key] ?? key;
}

function translateValue(value: string) {
  return valueLabels[value] ?? value;
}

createRoot(document.getElementById('root')!).render(<App />);
