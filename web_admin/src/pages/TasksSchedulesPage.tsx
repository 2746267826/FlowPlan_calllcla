import { Button, Card, Input, Modal, Select, Space, Tag, message } from 'antd';
import { CheckCircleOutlined, DeleteOutlined, ReloadOutlined } from '@ant-design/icons';
import { PageContainer, ProTable, StatisticCard, type ProColumns } from '@ant-design/pro-components';
import { useEffect, useMemo, useState } from 'react';
import { datasets } from '../app/constants';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord, ManagementItem } from '../types';
import { compareManagementItems, displayValue, extractRows, matchesManagementFilters, statusLabel, toManagementItem } from '../utils/format';
import { StatusTag } from '../components/StatusTag';
import { RawDataCollapse } from '../components/RawDataCollapse';

export function TasksSchedulesPage(props: {
  api: AdminApiClient;
  onDataRefresh: () => void;
  onOpenDetail: (dataset: typeof datasets.tasks, row: ApiRecord) => void;
}) {
  const [tasksPayload, setTasksPayload] = useState<unknown>(null);
  const [schedulesPayload, setSchedulesPayload] = useState<unknown>(null);
  const [items, setItems] = useState<ManagementItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedKeys, setSelectedKeys] = useState<React.Key[]>([]);
  const [query, setQuery] = useState('');
  const [typeFilter, setTypeFilter] = useState('all');
  const [sourceFilter, setSourceFilter] = useState('all');
  const [timeFilter, setTimeFilter] = useState('all');
  const [statusFilter, setStatusFilter] = useState('all');

  const load = async () => {
    setLoading(true);
    try {
      const [tasks, schedules] = await Promise.all([
        props.api.adminData('tasks', { limit: 200 }),
        props.api.adminData('schedules', { limit: 200 }),
      ]);
      setTasksPayload(tasks);
      setSchedulesPayload(schedules);
      setItems([
        ...extractRows(tasks).map((row) => toManagementItem(row, 'tasks')),
        ...extractRows(schedules).map((row) => toManagementItem(row, 'schedules')),
      ].sort(compareManagementItems));
      props.onDataRefresh();
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const filtered = useMemo(
    () => items.filter((item) => matchesManagementFilters(item, { query, typeFilter, sourceFilter, timeFilter, statusFilter })),
    [items, query, sourceFilter, statusFilter, timeFilter, typeFilter],
  );

  const selectedItems = filtered.filter((item) => selectedKeys.includes(item.key));
  const statusOptions = useMemo(
    () => Array.from(new Set(items.map((item) => item.status))).map((value) => ({ label: statusLabel(value), value })),
    [items],
  );

  const patchSelected = async (body: ApiRecord, success: string) => {
    await Promise.all(selectedItems.map((item) => props.api.patchAdminData(item.domain, item.id, body)));
    message.success(success);
    setSelectedKeys([]);
    await load();
  };

  const batchComplete = () => {
    const taskItems = selectedItems.filter((item) => item.domain === 'tasks');
    if (!taskItems.length) {
      message.warning('请选择至少一个任务');
      return;
    }
    Modal.confirm({
      title: `确认完成 ${taskItems.length} 个任务`,
      content: '会把所选任务标记为已完成，并写入管理审计。日程不会被完成操作影响。',
      okText: '确认完成',
      cancelText: '取消',
      onOk: () => patchSelected({ payload: { status: 'done', completedAt: new Date().toISOString() }, reason: 'admin batch complete' }, '批量完成已提交'),
    });
  };

  const batchDelete = () => {
    Modal.confirm({
      title: `确认删除 ${selectedItems.length} 个对象`,
      content: '这是高风险动作，会把对象标记为删除并写入审计。请确认影响范围无误。',
      okText: '确认删除',
      okButtonProps: { danger: true },
      cancelText: '取消',
      onOk: () => patchSelected({ deleted: true, reason: 'admin batch delete' }, '批量删除已提交'),
    });
  };

  const columns: ProColumns<ManagementItem>[] = [
    { title: '类型', dataIndex: 'typeLabel', width: 90, render: (_, row) => <Tag color={row.type === 'task' ? 'cyan' : 'blue'}>{row.typeLabel}</Tag> },
    { title: '标题', dataIndex: 'title', ellipsis: true, render: (_, row) => <Button type="link" onClick={() => props.onOpenDetail(row.domain === 'tasks' ? datasets.tasks : datasets.schedules, row.raw)}>{row.title}</Button> },
    { title: '所属本', dataIndex: 'containerName', width: 160, ellipsis: true },
    { title: '来源', dataIndex: 'sourceLabel', width: 110 },
    { title: '状态', dataIndex: 'statusLabel', width: 120, render: (_, row) => <StatusTag value={row.status} /> },
    { title: '时间', dataIndex: 'timeLabel', width: 230 },
    { title: '地点', dataIndex: 'location', width: 150, ellipsis: true },
    { title: '备注', dataIndex: 'description', ellipsis: true },
  ];

  return (
    <PageContainer title="全部任务与日程" content="搜索、筛选、批量选择和业务动作优先；原始数据保留在底部折叠区。">
      <Space direction="vertical" size={16} className="full-width">
        <StatisticCard.Group>
          <StatisticCard statistic={{ title: '总数', value: items.length }} />
          <StatisticCard statistic={{ title: '当前显示', value: filtered.length }} />
          <StatisticCard statistic={{ title: '已选择', value: selectedKeys.length }} />
          <StatisticCard statistic={{ title: '逾期任务', value: items.filter((item) => matchesManagementFilters(item, { query: '', typeFilter: 'all', sourceFilter: 'all', timeFilter: 'overdue', statusFilter: 'all' })).length, status: 'warning' as const }} />
        </StatisticCard.Group>
        <Card>
          <Space className="table-toolbar" wrap>
            <Input.Search aria-label="Search tasks and schedules" placeholder="搜索标题、备注、地点、所属本" allowClear value={query} onChange={(event) => setQuery(event.target.value)} style={{ width: 320 }} />
            <Select value={typeFilter} onChange={setTypeFilter} style={{ width: 140 }} options={[{ label: '全部类型', value: 'all' }, { label: '任务', value: 'task' }, { label: '日程', value: 'schedule' }]} />
            <Select value={sourceFilter} onChange={setSourceFilter} style={{ width: 140 }} options={[{ label: '全部来源', value: 'all' }, { label: '本地', value: 'local' }, { label: 'Outlook', value: 'outlook' }]} />
            <Select value={timeFilter} onChange={setTimeFilter} style={{ width: 150 }} options={[{ label: '全部时间', value: 'all' }, { label: '今天', value: 'today' }, { label: '未来 7 天', value: 'next7' }, { label: '已逾期', value: 'overdue' }, { label: '无时间', value: 'none' }]} />
            <Select allowClear placeholder="状态筛选" value={statusFilter === 'all' ? undefined : statusFilter} onChange={(value) => setStatusFilter(value ?? 'all')} style={{ width: 160 }} options={statusOptions} />
            <Button aria-label="Refresh tasks and schedules" icon={<ReloadOutlined />} onClick={() => void load()}>刷新</Button>
            <Button aria-label="Batch complete selected tasks" icon={<CheckCircleOutlined />} disabled={!selectedKeys.length} onClick={batchComplete}>批量完成</Button>
            <Button aria-label="Batch delete selected items" danger icon={<DeleteOutlined />} disabled={!selectedKeys.length} onClick={batchDelete}>批量删除</Button>
          </Space>
          <ProTable<ManagementItem>
            rowKey="key"
            loading={loading}
            search={false}
            options={false}
            dataSource={filtered}
            columns={columns}
            pagination={{ pageSize: 12, showSizeChanger: true }}
            scroll={{ x: 1100 }}
            rowSelection={{ selectedRowKeys: selectedKeys, onChange: setSelectedKeys }}
            tableAlertRender={() => `已选择 ${selectedKeys.length} 项`}
          />
        </Card>
        <RawDataCollapse title="任务原始响应" value={tasksPayload} />
        <RawDataCollapse title="日程原始响应" value={schedulesPayload} />
      </Space>
    </PageContainer>
  );
}
