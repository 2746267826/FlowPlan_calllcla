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
} from '@ant-design/icons';
import { ProLayout, type MenuDataItem } from '@ant-design/pro-components';
import { ConfigProvider, theme } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import type { ReactNode } from 'react';
import { useEffect, useMemo, useState } from 'react';
import { AdminApiClient, normalizeApiBase } from '../api/adminApi';
import { DetailDrawer, readableTitle } from '../components/DetailDrawer';
import { ServerIndicator } from '../components/ServerIndicator';
import { AuditPage } from '../pages/AuditPage';
import { BusinessListPage, type BusinessPanel } from '../pages/BusinessListPage';
import { DashboardPage } from '../pages/DashboardPage';
import { DevicesPage } from '../pages/DevicesPage';
import { DriveFilesPage } from '../pages/DriveFilesPage';
import { OperationsPage } from '../pages/OperationsPage';
import { OutlookPage } from '../pages/OutlookPage';
import { SettingsPage } from '../pages/SettingsPage';
import { TasksSchedulesPage } from '../pages/TasksSchedulesPage';
import type { ApiRecord, ConnectionState, DetailState, DeviceOption, ModuleKey } from '../types';
import { displayValue, extractRows, formatDate, pickId } from '../utils/format';
import { defaultApiBase, defaultUserId, datasets, modules } from './constants';
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

export function AdminApp() {
  const [apiBase, setApiBase] = useState(() => normalizeApiBase(localStorage.getItem('flowplanv2.admin.apiBase') ?? defaultApiBase));
  const [deviceId, setDeviceId] = useState(() => localStorage.getItem('flowplanv2.admin.deviceId') ?? safeRandomId());
  const [selectedDeviceId, setSelectedDeviceId] = useState(() => localStorage.getItem('flowplanv2.admin.selectedDeviceId') ?? 'all');
  const [activeModule, setActiveModule] = useState<ModuleKey>('dashboard');
  const [connection, setConnection] = useState<ConnectionState>('checking');
  const [serverInfo, setServerInfo] = useState<ApiRecord | null>(null);
  const [lastHealthAt, setLastHealthAt] = useState('');
  const [lastHealthError, setLastHealthError] = useState('');
  const [newInfoCount, setNewInfoCount] = useState(0);
  const [devices, setDevices] = useState<DeviceOption[]>([]);
  const [detail, setDetail] = useState<DetailState | null>(null);

  const api = useMemo(() => new AdminApiClient({ apiBase, userId: defaultUserId, deviceId }), [apiBase, deviceId]);

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
      setConnection('offline');
      setLastHealthError(error instanceof Error ? error.message : String(error));
    }
  };

  const refreshDevices = async () => {
    try {
      const result = await api.syncHealth();
      const rows = extractRows(result);
      setDevices(
        rows.map((row) => ({
          id: displayValue(row.deviceId ?? row.id ?? row.clientDeviceId ?? pickId(row)),
          name: displayValue(row.deviceName ?? row.name ?? row.platform, '未注册设备'),
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

  const saveConnection = (nextApiBase: string, nextDeviceId: string, nextSelectedDeviceId: string) => {
    const normalized = normalizeApiBase(nextApiBase);
    setApiBase(normalized);
    setDeviceId(nextDeviceId);
    setSelectedDeviceId(nextSelectedDeviceId);
    localStorage.setItem('flowplanv2.admin.apiBase', normalized);
    localStorage.setItem('flowplanv2.admin.deviceId', nextDeviceId);
    localStorage.setItem('flowplanv2.admin.selectedDeviceId', nextSelectedDeviceId);
  };

  const openDetail = async (dataset: typeof datasets.tasks, row: ApiRecord) => {
    const title = readableTitle(row, dataset.domain);
    setDetail({ title, dataset, row, loading: true });
    const id = pickId(row);
    if (!id) {
      setDetail({ title, dataset, row, detail: row, loading: false });
      return;
    }
    try {
      const nextDetail = await api.adminDataDetail(dataset.domain, String(id));
      setDetail({ title, dataset, row, detail: nextDetail, loading: false });
    } catch (error) {
      setDetail({ title, dataset, row, detail: row, loading: false, error: error instanceof Error ? error.message : String(error) });
    }
  };

  useEffect(() => {
    void refreshHealth();
    void refreshDevices();
  }, [api]);

  const currentModule = modules.find((item) => item.key === activeModule) ?? modules[0];

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
        return <DashboardPage api={api} onDataRefresh={onDataRefresh} onOpenDetail={(domain, row) => openDetail(datasets[domain], row)} />;
      case 'tasks':
        return <TasksSchedulesPage api={api} onDataRefresh={onDataRefresh} onOpenDetail={openDetail} />;
      case 'actuals':
        return <BusinessListPage title="实际记录" description={currentModule.description} panels={actualPanels} api={api} onDataRefresh={onDataRefresh} onOpenDetail={openDetail} />;
      case 'files':
        return <DriveFilesPage api={api} onDataRefresh={onDataRefresh} />;
      case 'reports':
        return <BusinessListPage title="报告推送" description={currentModule.description} panels={reportPanels} api={api} onDataRefresh={onDataRefresh} onOpenDetail={openDetail} />;
      case 'sync':
        return <DevicesPage api={api} onDataRefresh={onDataRefresh} />;
      case 'outlook':
        return <OutlookPage api={api} onDataRefresh={onDataRefresh} />;
      case 'audit':
        return <AuditPage api={api} onDataRefresh={onDataRefresh} onOpenDetail={openDetail} />;
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
        return <OperationsPage api={api} onDataRefresh={onDataRefresh} />;
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
          fontFamily: 'Inter, "Microsoft YaHei", system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
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
            onClick={() => {
              const key = String(item.path ?? '').replace(/^\//, '') as ModuleKey;
              setActiveModule(key);
            }}
          >
            {dom}
          </a>
        )}
        menuExtraRender={() => <div className="sider-status-slot">{serverIndicator}</div>}
        avatarProps={false}
      >
        {page}
      </ProLayout>
      <DetailDrawer api={api} detail={detail} onClose={() => setDetail(null)} onChanged={() => void refreshDevices()} />
    </ConfigProvider>
  );
}
