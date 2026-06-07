import {
  AuditOutlined,
  CalendarOutlined,
  CloudSyncOutlined,
  DashboardOutlined,
  DatabaseOutlined,
  FolderOpenOutlined,
  MailOutlined,
  NotificationOutlined,
  SettingOutlined,
  ToolOutlined,
  FileTextOutlined,
  ClockCircleOutlined,
  PlayCircleOutlined,
  WarningOutlined,
} from '@ant-design/icons';
import { ProLayout, type MenuDataItem } from '@ant-design/pro-components';
import { Alert, Button, ConfigProvider, Input, Space, theme } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import type { ReactNode } from 'react';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { AdminApiClient, normalizeApiBase, TokenExpiredError } from '../api/adminApi';
import { DetailDrawer, readableTitle } from '../components/DetailDrawer';
import { ServerIndicator } from '../components/ServerIndicator';
import { AuditPage } from '../pages/AuditPage';
import { BusinessListPage, type BusinessPanel } from '../pages/BusinessListPage';
import { DashboardPage } from '../pages/DashboardPage';
import { DevicesPage } from '../pages/DevicesPage';
import { DriveFilesPage } from '../pages/DriveFilesPage';
import { OperationsPage } from '../pages/OperationsPage';
import { SchedulePage } from '../pages/SchedulePage';
import { LogsPage } from '../pages/LogsPage';
import { JobsPage } from '../pages/JobsPage';
import { AlertsPage } from '../pages/AlertsPage';
import { EnvPage } from '../pages/EnvPage';
import { OutlookPage } from '../pages/OutlookPage';
import { SettingsPage } from '../pages/SettingsPage';
import { TasksSchedulesPage } from '../pages/TasksSchedulesPage';
import type {
  ApiRecord,
  ConnectionState,
  DetailState,
  DeviceOption,
  ModuleKey,
} from '../types';
import {
  displayValue,
  extractRows,
  formatDate,
  pickId,
} from '../utils/format';
import { defaultApiBase, datasets, modules } from './constants';
import { safeRandomId } from './hooks';

const iconMap: Record<ModuleKey, ReactNode> = {
  dashboard: <DashboardOutlined />,
  tasks: <CalendarOutlined />,
  actuals: <DatabaseOutlined />,
  files: <FolderOpenOutlined />,
  reports: <NotificationOutlined />,
  sync: <CloudSyncOutlined />,
  outlook: <MailOutlined />,
  audit: <AuditOutlined />,
  settings: <SettingOutlined />,
  operations: <ToolOutlined />,
  logs: <FileTextOutlined />,
  jobs: <ClockCircleOutlined />,
  schedule: <PlayCircleOutlined />,
  alerts: <WarningOutlined />,
  env: <SettingOutlined />,
};

const actualPanels: BusinessPanel[] = [
  {
    dataset: datasets.actuals,
    endpoint: '/api/admin/data/actuals',
    columns: [
      { key: 'title', label: '标题', width: 220 },
      { key: 'source', label: '来源', width: 110 },
      { key: 'startAt', label: '开始时间', width: 180, type: 'date' },
      { key: 'endAt', label: '结束时间', width: 180, type: 'date' },
      { key: 'confidence', label: '置信度', width: 100 },
      { key: 'status', label: '状态', width: 110, type: 'status' },
    ],
  },
];

const reportPanels: BusinessPanel[] = [
  {
    dataset: datasets.reports,
    endpoint: '/api/admin/data/reports',
    columns: [
      { key: 'title', label: '报告', width: 240 },
      { key: 'period', label: '周期', width: 120 },
      { key: 'status', label: '状态', width: 120, type: 'status' },
      { key: 'generatedAt', label: '生成时间', width: 180, type: 'date' },
      { key: 'summary', label: '摘要', width: 360 },
    ],
  },
  {
    dataset: datasets.pushDeliveries,
    endpoint: '/api/admin/data/push-deliveries',
    columns: [
      { key: 'channel', label: '渠道', width: 120 },
      { key: 'target', label: '目标', width: 220 },
      { key: 'status', label: '状态', width: 120, type: 'status' },
      { key: 'createdAt', label: '时间', width: 180, type: 'date' },
      { key: 'error', label: '错误原因', width: 320 },
    ],
  },
];

const TOKEN_KEY = 'flowplanv2.admin.accessToken';
const REFRESH_KEY = 'flowplanv2.admin.refreshToken';

function loadStored(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}

function saveStored(key: string, value: string): void {
  try {
    localStorage.setItem(key, value);
  } catch {
    // storage unavailable
  }
}

export function AdminApp() {
  const [apiBase, setApiBase] = useState(() =>
    normalizeApiBase(
      loadStored('flowplanv2.admin.apiBase') ?? defaultApiBase,
    ),
  );
  const [deviceId, setDeviceId] = useState(() =>
    loadStored('flowplanv2.admin.deviceId') ?? safeRandomId(),
  );
  const [selectedDeviceId, setSelectedDeviceId] = useState(() =>
    loadStored('flowplanv2.admin.selectedDeviceId') ?? 'all',
  );
  const [accessToken, setAccessToken] = useState(() =>
    loadStored(TOKEN_KEY) ?? '',
  );
  const [refreshToken, setRefreshToken] = useState(() =>
    loadStored(REFRESH_KEY) ?? '',
  );

  // Login flow state
  const [authLoading, setAuthLoading] = useState(true);
  const [authError, setAuthError] = useState('');
  const [displayName, setDisplayName] = useState('FlowPlanV2 Admin');

  const [activeModule, setActiveModule] = useState<ModuleKey>('dashboard');
  const [connection, setConnection] = useState<ConnectionState>('checking');
  const [serverInfo, setServerInfo] = useState<ApiRecord | null>(null);
  const [lastHealthAt, setLastHealthAt] = useState('');
  const [lastHealthError, setLastHealthError] = useState('');
  const [newInfoCount, setNewInfoCount] = useState(0);
  const [devices, setDevices] = useState<DeviceOption[]>([]);
  const [detail, setDetail] = useState<DetailState | null>(null);

  const api = useMemo(
    () => new AdminApiClient({ apiBase, accessToken, deviceId }),
    [apiBase, accessToken, deviceId],
  );

  // Auto-login on startup (or when apiBase changes)
  const doLogin = useCallback(
    async (name: string) => {
      setAuthLoading(true);
      setAuthError('');
      try {
        // Use a temporary unauthenticated client for login
        const loginClient = new AdminApiClient({
          apiBase,
          accessToken: '',
          deviceId,
        });
        const result = await loginClient.login(name);
        setAccessToken(result.accessToken);
        setRefreshToken(result.refreshToken);
        saveStored(TOKEN_KEY, result.accessToken);
        saveStored(REFRESH_KEY, result.refreshToken);
        saveStored('flowplanv2.admin.deviceId', deviceId);
        setAuthLoading(false);
        return true;
      } catch (err) {
        setAuthError(
          err instanceof Error ? err.message : String(err),
        );
        setAuthLoading(false);
        return false;
      }
    },
    [apiBase, deviceId],
  );

  // Try stored token first; if expired, re-login
  useEffect(() => {
    const init = async () => {
      const storedToken = loadStored(TOKEN_KEY);
      const storedRefresh = loadStored(REFRESH_KEY);
      if (storedToken && storedRefresh) {
        // Try refreshing to get a fresh token
        try {
          const loginClient = new AdminApiClient({
            apiBase,
            accessToken: '',
            deviceId,
          });
          const result = await loginClient.refreshToken(storedRefresh);
          setAccessToken(result.accessToken);
          setRefreshToken(result.refreshToken);
          saveStored(TOKEN_KEY, result.accessToken);
          saveStored(REFRESH_KEY, result.refreshToken);
          setAuthLoading(false);
          return;
        } catch {
          // Refresh failed — fall through to login
        }
      }
      await doLogin(displayName);
    };
    void init();
  }, [apiBase]);

  const onRefreshToken = useCallback(async () => {
    try {
      const loginClient = new AdminApiClient({
        apiBase,
        accessToken: '',
        deviceId,
      });
      const result = await loginClient.refreshToken(refreshToken);
      setAccessToken(result.accessToken);
      setRefreshToken(result.refreshToken);
      saveStored(TOKEN_KEY, result.accessToken);
      saveStored(REFRESH_KEY, result.refreshToken);
    } catch {
      await doLogin(displayName);
    }
  }, [apiBase, deviceId, refreshToken, displayName, doLogin]);

  const menuData = useMemo<MenuDataItem[]>(
    () =>
      modules.map((item) => ({
        path: `/${item.key}`,
        name: item.label,
        icon: iconMap[item.key],
        locale: false,
        pro_layout_parentKeys: [],
      })),
    [],
  );

  const refreshHealth = async () => {
    setConnection('checking');
    try {
      const health = await api.health();
      setServerInfo(health);
      setConnection('online');
      setLastHealthError('');
      setLastHealthAt(formatDate(new Date()));
    } catch (error) {
      if (error instanceof TokenExpiredError) {
        await onRefreshToken();
        return refreshHealth();
      }
      setConnection('offline');
      setLastHealthError(
        error instanceof Error ? error.message : String(error),
      );
    }
  };

  const refreshDevices = async () => {
    try {
      const result = await api.syncHealth();
      const rows = extractRows(result);
      setDevices(
        rows.map((row) => ({
          id: displayValue(
            row.deviceId ?? row.id ?? row.clientDeviceId ?? pickId(row),
          ),
          name: displayValue(
            row.deviceName ?? row.name ?? row.platform,
            '未注册设备',
          ),
          detail: `${displayValue(row.platform ?? row.runtimePlatform, '未上报')} / ${displayValue(row.appVersion, '无版本')}`,
        })),
      );
    } catch {
      setDevices([]);
    }
  };

  const onDataRefresh = () => {
    setNewInfoCount((value) => Math.min(99, value + 1));
  };

  const saveConnection = (
    nextApiBase: string,
    nextDeviceId: string,
    nextSelectedDeviceId: string,
  ) => {
    const normalized = normalizeApiBase(nextApiBase);
    setApiBase(normalized);
    setDeviceId(nextDeviceId);
    setSelectedDeviceId(nextSelectedDeviceId);
    saveStored('flowplanv2.admin.apiBase', normalized);
    saveStored('flowplanv2.admin.deviceId', nextDeviceId);
    saveStored('flowplanv2.admin.selectedDeviceId', nextSelectedDeviceId);
  };

  const openDetail = async (
    dataset: typeof datasets.tasks,
    row: ApiRecord,
  ) => {
    const title = readableTitle(row, dataset.domain);
    setDetail({ title, dataset, row, loading: true });
    const id = pickId(row);
    if (!id) {
      setDetail({ title, dataset, row, detail: row, loading: false });
      return;
    }
    try {
      const nextDetail = await api.adminDataDetail(
        dataset.domain,
        String(id),
      );
      setDetail({
        title,
        dataset,
        row,
        detail: nextDetail,
        loading: false,
      });
    } catch (error) {
      setDetail({
        title,
        dataset,
        row,
        detail: row,
        loading: false,
        error: error instanceof Error ? error.message : String(error),
      });
    }
  };

  useEffect(() => {
    if (accessToken) {
      void refreshHealth();
      void refreshDevices();
    }
  }, [accessToken]);

  // Show login form when not authenticated
  if (!accessToken) {
    return (
      <ConfigProvider
        locale={zhCN}
        theme={{
          algorithm: theme.defaultAlgorithm,
          token: { colorPrimary: '#1f6f78' },
        }}
      >
        <div
          style={{
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            minHeight: '100vh',
            background: '#f3f6fb',
          }}
        >
          <div
            style={{
              width: 400,
              padding: 32,
              background: '#fff',
              borderRadius: 8,
              boxShadow: '0 2px 12px rgba(0,0,0,0.08)',
            }}
          >
            <h2 style={{ marginBottom: 24 }}>FlowPlanV2 管理端</h2>
            {authError && (
              <Alert
                type="error"
                message={authError}
                style={{ marginBottom: 16 }}
                closable
              />
            )}
            <Space direction="vertical" style={{ width: '100%' }} size={16}>
              <Input
                placeholder="显示名称"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                onPressEnter={() => doLogin(displayName)}
              />
              <Button
                type="primary"
                block
                loading={authLoading}
                onClick={() => doLogin(displayName)}
              >
                登录
              </Button>
            </Space>
          </div>
        </div>
      </ConfigProvider>
    );
  }

  const currentModule =
    modules.find((item) => item.key === activeModule) ?? modules[0];

  const serverIndicator = (
    <ServerIndicator
      apiBase={apiBase}
      connection={connection}
      lastHealthAt={lastHealthAt}
      lastHealthError={lastHealthError}
      newInfoCount={newInfoCount}
      serverInfo={serverInfo}
      onRefresh={() => {
        setNewInfoCount(0);
        void refreshHealth();
      }}
    />
  );

  const page = (() => {
    switch (activeModule) {
      case 'dashboard':
        return (
          <DashboardPage
            api={api}
            onDataRefresh={onDataRefresh}
            onOpenDetail={(domain, row) =>
              openDetail(datasets[domain], row)
            }
          />
        );
      case 'tasks':
        return (
          <TasksSchedulesPage
            api={api}
            onDataRefresh={onDataRefresh}
            onOpenDetail={openDetail}
          />
        );
      case 'actuals':
        return (
          <BusinessListPage
            title="实际记录"
            description={currentModule.description}
            panels={actualPanels}
            api={api}
            onDataRefresh={onDataRefresh}
            onOpenDetail={openDetail}
          />
        );
      case 'files':
        return (
          <DriveFilesPage api={api} onDataRefresh={onDataRefresh} />
        );
      case 'reports':
        return (
          <BusinessListPage
            title="报告推送"
            description={currentModule.description}
            panels={reportPanels}
            api={api}
            onDataRefresh={onDataRefresh}
            onOpenDetail={openDetail}
          />
        );
      case 'sync':
        return (
          <DevicesPage api={api} onDataRefresh={onDataRefresh} />
        );
      case 'outlook':
        return (
          <OutlookPage api={api} onDataRefresh={onDataRefresh} />
        );
      case 'audit':
        return (
          <AuditPage
            api={api}
            onDataRefresh={onDataRefresh}
            onOpenDetail={openDetail}
          />
        );
      case 'settings':
        return (
          <SettingsPage
            api={api}
            apiBase={apiBase}
            deviceId={deviceId}
            devices={devices}
            selectedDeviceId={selectedDeviceId}
            onSaveConnection={saveConnection}
            onDataRefresh={onDataRefresh}
          />
        );
      case 'operations':
        return (
          <OperationsPage api={api} onDataRefresh={onDataRefresh} />
        );
      case 'logs':
        return (
          <LogsPage api={api} onDataRefresh={onDataRefresh} />
        );
      case 'jobs':
        return (
          <JobsPage api={api} onDataRefresh={onDataRefresh} />
        );
      case 'schedule':
        return (
          <SchedulePage api={api} onDataRefresh={onDataRefresh} />
        );
      case 'alerts':
        return (
          <AlertsPage api={api} onDataRefresh={onDataRefresh} />
        );
      case 'env':
        return (
          <EnvPage api={api} onDataRefresh={onDataRefresh} />
        );
      default:
        return null;
    }
  })();

  return (
    <ConfigProvider
      locale={zhCN}
      theme={{
        algorithm: theme.defaultAlgorithm,
        token: {
          colorPrimary: '#1f6f78',
          colorInfo: '#1f6f78',
          colorBgLayout: '#f3f6fb',
          colorBgContainer: '#ffffff',
          colorText: '#172033',
          borderRadius: 6,
          fontFamily:
            'Inter, "Microsoft YaHei", system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
        },
        components: {
          Layout: {
            bodyBg: '#f3f6fb',
            headerBg: '#ffffff',
            siderBg: '#ffffff',
          },
          Card: { borderRadiusLG: 8 },
          Menu: {
            itemBg: '#ffffff',
            itemSelectedBg: '#e7f3f4',
            itemSelectedColor: '#1f6f78',
            itemHoverBg: '#f2f6f8',
          },
        },
      }}
    >
      <ProLayout
        className="admin-pro-layout"
        title="FlowPlanV2"
        logo={false}
        navTheme="light"
        layout="side"
        fixSiderbar
        fixedHeader
        menuDataRender={() => menuData}
        location={{ pathname: `/${activeModule}` }}
        menuItemRender={(item, dom) => (
          <a
            aria-label={`Open ${String(item.path ?? '').replace(/^\//, '')} page`}
            data-testid={`nav-${String(item.path ?? '').replace(/^\//, '')}`}
            onClick={() => {
              const key = String(item.path ?? '')
                .replace(/^\//, '') as ModuleKey;
              setActiveModule(key);
            }}
          >
            {dom}
          </a>
        )}
        menuExtraRender={() => (
          <div className="sider-status-slot">{serverIndicator}</div>
        )}
        avatarProps={false}
      >
        {page}
      </ProLayout>
      <DetailDrawer
        api={api}
        detail={detail}
        onClose={() => setDetail(null)}
        onChanged={() => void refreshDevices()}
      />
    </ConfigProvider>
  );
}
