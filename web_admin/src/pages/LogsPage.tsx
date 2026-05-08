import { Input, Select, Space, Tag } from 'antd';
import { SearchOutlined } from '@ant-design/icons';
import { PageContainer, ProTable, type ProColumns } from '@ant-design/pro-components';
import { useEffect, useMemo, useState } from 'react';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord } from '../types';
import { asArray, asRecord, displayValue, formatDate } from '../utils/format';

const actorColors: Record<string, string> = {
  server: 'blue', ai: 'purple', system: 'cyan', admin: 'orange',
  web: 'green', client: 'geekblue', model: 'magenta', outlook: 'volcano',
};

export function LogsPage(props: { api: AdminApiClient; onDataRefresh: () => void }) {
  const [loading, setLoading] = useState(false);
  const [data, setData] = useState<ApiRecord[]>([]);
  const [actorFilter, setActorFilter] = useState<string>('');
  const [actionFilter, setActionFilter] = useState('');

  const load = async () => {
    setLoading(true);
    try {
      const result = await props.api.adminData('audit-logs', { limit: 500 });
      const rows = asArray((result as ApiRecord)?.items ?? (result as ApiRecord)?.rows);
      setData(rows.map(asRecord));
      props.onDataRefresh();
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void load(); }, []);

  const filtered = useMemo(() => {
    return data.filter((row) => {
      if (actorFilter && String(row.actor ?? '') !== actorFilter) return false;
      if (actionFilter && !String(row.action ?? '').includes(actionFilter)) return false;
      return true;
    });
  }, [data, actorFilter, actionFilter]);

  const actors = useMemo(() => [...new Set(data.map((r) => String(r.actor ?? 'unknown')))], [data]);

  const columns: ProColumns<ApiRecord>[] = [
    { title: '时间', dataIndex: 'occurredAt', width: 180, render: (_, row) => formatDate(row.occurredAt ?? row.createdAt) },
    {
      title: '操作者', dataIndex: 'actor', width: 100,
      render: (_, row) => {
        const actor = String(row.actor ?? 'unknown');
        return <Tag color={actorColors[actor] ?? 'default'}>{actor}</Tag>;
      },
    },
    { title: '动作', dataIndex: 'action', width: 220, ellipsis: true },
    { title: '实体类型', dataIndex: 'entityType', width: 120 },
    { title: '摘要', dataIndex: 'summary', ellipsis: true },
    {
      title: '详情', dataIndex: 'metadata', width: 80,
      render: (_, row) => {
        const meta = asRecord(row.metadata ?? row.metadataJson);
        const keys = Object.keys(meta).slice(0, 3);
        return <span title={JSON.stringify(meta)}>{keys.join(', ') || '-'}</span>;
      },
    },
  ];

  return (
    <PageContainer
      title="系统日志"
      content="审计日志：所有关键操作和变更记录的集中查看。"
      loading={loading}
    >
      <Space style={{ marginBottom: 16 }}>
        <Select
          placeholder="操作者"
          allowClear
          style={{ width: 140 }}
          value={actorFilter || undefined}
          onChange={(v) => setActorFilter(v ?? '')}
          options={actors.map((a) => ({ label: a, value: a }))}
        />
        <Input
          placeholder="搜索动作"
          prefix={<SearchOutlined />}
          style={{ width: 240 }}
          value={actionFilter}
          onChange={(e) => setActionFilter(e.target.value)}
          allowClear
        />
      </Space>

      <ProTable<ApiRecord>
        rowKey="id"
        search={false}
        options={{ reload: load }}
        pagination={{ defaultPageSize: 50, showSizeChanger: true }}
        columns={columns}
        dataSource={filtered}
        scroll={{ x: 900 }}
      />
    </PageContainer>
  );
}
