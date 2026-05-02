import { Button, Card, Drawer, Empty, Space, Tabs, Tag } from 'antd';
import { ReloadOutlined } from '@ant-design/icons';
import { PageContainer, ProTable, StatisticCard, type ProColumns } from '@ant-design/pro-components';
import { useEffect, useMemo, useState } from 'react';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord, DeviceSummary } from '../types';
import { asRecord, displayValue, extractRows, formatDate, pickId, toCount } from '../utils/format';
import { HumanDescriptions } from '../components/HumanDescriptions';
import { RawDataCollapse } from '../components/RawDataCollapse';
import { StatusTag } from '../components/StatusTag';

export function DevicesPage(props: { api: AdminApiClient; onDataRefresh: () => void }) {
  const [payload, setPayload] = useState<unknown>(null);
  const [devices, setDevices] = useState<DeviceSummary[]>([]);
  const [loading, setLoading] = useState(true);
  const [active, setActive] = useState<DeviceSummary | null>(null);

  const load = async () => {
    setLoading(true);
    try {
      const result = await props.api.syncHealth();
      setPayload(result);
      setDevices(extractRows(result) as DeviceSummary[]);
      props.onDataRefresh();
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const columns = useMemo<ProColumns<DeviceSummary>[]>(
    () => [
      { title: '设备', dataIndex: 'deviceName', width: 180, ellipsis: true, render: (_, row) => displayValue(row.deviceName ?? row.id ?? row.deviceId, '未注册设备') },
      { title: '平台', dataIndex: 'platform', width: 110, render: (_, row) => <Tag>{displayValue(row.platform ?? row.runtimePlatform, '未上报')}</Tag> },
      { title: '状态', dataIndex: 'status', width: 100, render: (_, row) => <StatusTag value={row.status ?? (row.lastHeartbeatAt ? 'online' : 'offline')} /> },
      { title: '最近心跳', dataIndex: 'lastHeartbeatAt', width: 180, render: (_, row) => formatDate(row.lastHeartbeatAt ?? row.lastSeenAt) },
      { title: '最近连接', dataIndex: 'lastConnectedAt', width: 180, render: (_, row) => formatDate(row.lastConnectedAt) },
      { title: '版本', dataIndex: 'appVersion', width: 110, render: (_, row) => displayValue(row.appVersion, '未上报') },
      { title: '网络', dataIndex: 'networkType', width: 110, render: (_, row) => displayValue(row.networkType, '未上报') },
      { title: '待同步', dataIndex: 'syncPendingCount', width: 90 },
      { title: '失败写入', dataIndex: 'syncFailedCount', width: 100 },
      { title: '冲突', dataIndex: 'openConflictCount', width: 80 },
      { title: '游标', dataIndex: 'pullCursor', width: 220, ellipsis: true, render: (_, row) => displayValue(row.pullCursor, '未上报') },
      { title: '详情', valueType: 'option', width: 90, render: (_, row) => <Button size="small" onClick={() => setActive(row)}>查看</Button> },
    ],
    [],
  );

  return (
    <PageContainer title="同步与设备" content="设备画像、连接、心跳、同步积压、失败、冲突和游标统一展示。">
      <Space direction="vertical" size={16} className="full-width">
        <StatisticCard.Group>
          <StatisticCard statistic={{ title: '设备数', value: devices.length }} />
          <StatisticCard statistic={{ title: '在线或有心跳', value: devices.filter((item) => item.status === 'online' || item.lastHeartbeatAt).length }} />
          <StatisticCard statistic={{ title: '待同步', value: devices.reduce((sum, item) => sum + toCount(item.syncPendingCount), 0), status: 'warning' as const }} />
          <StatisticCard statistic={{ title: '开放冲突', value: devices.reduce((sum, item) => sum + toCount(item.openConflictCount), 0), status: 'error' as const }} />
        </StatisticCard.Group>
        <Card title="设备画像" extra={<Button icon={<ReloadOutlined />} onClick={() => void load()}>刷新</Button>}>
          <ProTable<DeviceSummary>
            rowKey={(row) => displayValue(row.deviceId ?? row.id ?? row.clientDeviceId)}
            loading={loading}
            search={{ labelWidth: 80 }}
            options={false}
            columns={columns}
            dataSource={devices}
            pagination={{ pageSize: 10, showSizeChanger: true }}
            scroll={{ x: 1500 }}
          />
        </Card>
        <RawDataCollapse title="设备同步健康原始响应" value={payload} />
      </Space>
      <DeviceDetailDrawer api={props.api} device={active} onClose={() => setActive(null)} />
    </PageContainer>
  );
}

function DeviceDetailDrawer(props: { api: AdminApiClient; device: DeviceSummary | null; onClose: () => void }) {
  const [history, setHistory] = useState<ApiRecord[]>([]);
  const [failures, setFailures] = useState<ApiRecord[]>([]);
  const [conflicts, setConflicts] = useState<ApiRecord[]>([]);
  const [loading, setLoading] = useState(false);
  const deviceId = props.device ? displayValue(props.device.deviceId ?? props.device.id ?? props.device.clientDeviceId) : '';

  useEffect(() => {
    if (!props.device || !deviceId) return;
    setLoading(true);
    Promise.all([
      props.api.deviceConnectionHistory(deviceId).then(extractRows).catch(() => []),
      props.api.adminRows('sync-mutations', { deviceId, limit: 50 }).catch(() => []),
      props.api.adminRows('conflicts', { deviceId, limit: 50 }).catch(() => []),
    ])
      .then(([nextHistory, nextFailures, nextConflicts]) => {
        setHistory(nextHistory);
        setFailures(nextFailures);
        setConflicts(nextConflicts);
      })
      .finally(() => setLoading(false));
  }, [deviceId, props.device]);

  if (!props.device) return null;
  const identity = {
    deviceName: props.device.deviceName ?? '未注册设备',
    deviceId,
    clientDeviceId: props.device.clientDeviceId,
    platform: props.device.platform,
    runtimePlatform: props.device.runtimePlatform,
    appVersion: props.device.appVersion,
    networkType: props.device.networkType,
  };
  const sync = {
    status: props.device.status,
    lastSeenAt: props.device.lastSeenAt,
    lastHeartbeatAt: props.device.lastHeartbeatAt,
    lastConnectedAt: props.device.lastConnectedAt,
    lastDisconnectedAt: props.device.lastDisconnectedAt,
    lastConnectionError: props.device.lastConnectionError,
    syncPendingCount: props.device.syncPendingCount,
    syncFailedCount: props.device.syncFailedCount,
    openConflictCount: props.device.openConflictCount,
    pullCursor: props.device.pullCursor,
    cursorUpdatedAt: props.device.cursorUpdatedAt,
  };

  const compactColumns: ProColumns<ApiRecord>[] = [
    { title: '时间', dataIndex: 'createdAt', render: (_, row) => formatDate(row.createdAt ?? row.occurredAt ?? row.updatedAt), width: 180 },
    { title: '类型', dataIndex: 'type', render: (_, row) => displayValue(row.type ?? row.action ?? row.status), width: 140 },
    { title: '摘要', dataIndex: 'summary', ellipsis: true, render: (_, row) => displayValue(row.summary ?? row.message ?? row.error ?? row.reason ?? pickId(row)) },
  ];

  return (
    <Drawer width={860} open title={`设备详情 / ${displayValue(props.device.deviceName ?? deviceId, '未注册设备')}`} onClose={props.onClose} loading={loading}>
      <Tabs
        items={[
          { key: 'identity', label: '身份与环境', children: <HumanDescriptions value={identity} /> },
          { key: 'sync', label: '同步状态', children: <HumanDescriptions value={sync} /> },
          {
            key: 'history',
            label: '连接历史',
            children: history.length ? <ProTable<ApiRecord> rowKey={(row) => displayValue(pickId(row) ?? JSON.stringify(row))} search={false} options={false} pagination={{ pageSize: 8 }} columns={compactColumns} dataSource={history} /> : <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="没有连接历史" />,
          },
          {
            key: 'failures',
            label: '失败写入',
            children: failures.length ? <ProTable<ApiRecord> rowKey={(row) => displayValue(pickId(row) ?? JSON.stringify(row))} search={false} options={false} pagination={{ pageSize: 8 }} columns={compactColumns} dataSource={failures} /> : <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="没有失败写入" />,
          },
          {
            key: 'conflicts',
            label: '冲突',
            children: conflicts.length ? <ProTable<ApiRecord> rowKey={(row) => displayValue(pickId(row) ?? JSON.stringify(row))} search={false} options={false} pagination={{ pageSize: 8 }} columns={compactColumns} dataSource={conflicts} /> : <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="没有开放冲突" />,
          },
          { key: 'raw', label: '原始响应', children: <RawDataCollapse title="设备原始记录" value={asRecord(props.device)} /> },
        ]}
      />
    </Drawer>
  );
}
