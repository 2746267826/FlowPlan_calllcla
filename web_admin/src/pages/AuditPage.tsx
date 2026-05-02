import { Button, Card, Input, Select, Space } from 'antd';
import { ReloadOutlined } from '@ant-design/icons';
import { PageContainer, ProTable, type ProColumns } from '@ant-design/pro-components';
import { useEffect, useMemo, useState } from 'react';
import { datasets } from '../app/constants';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord } from '../types';
import { auditActionLabel, displayValue, extractRows, formatDate, pickId } from '../utils/format';
import { AuditList } from '../components/AuditList';
import { RawDataCollapse } from '../components/RawDataCollapse';

export function AuditPage(props: {
  api: AdminApiClient;
  onDataRefresh: () => void;
  onOpenDetail: (dataset: typeof datasets.auditLogs, row: ApiRecord) => void;
}) {
  const [payload, setPayload] = useState<unknown>(null);
  const [rows, setRows] = useState<ApiRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [keyword, setKeyword] = useState('');
  const [action, setAction] = useState<string>();

  const load = async () => {
    setLoading(true);
    try {
      const result = await props.api.adminData('audit-logs', { limit: 200 });
      setPayload(result);
      setRows(extractRows(result));
      props.onDataRefresh();
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const filtered = useMemo(() => {
    const text = keyword.trim().toLowerCase();
    return rows.filter((row) => {
      const matchesKeyword = !text || JSON.stringify(row).toLowerCase().includes(text);
      const matchesAction = !action || String(row.action ?? '') === action;
      return matchesKeyword && matchesAction;
    });
  }, [action, keyword, rows]);

  const actionOptions = useMemo(
    () => Array.from(new Set(rows.map((row) => String(row.action ?? '')).filter(Boolean))).map((value) => ({ label: auditActionLabel(value), value })),
    [rows],
  );

  const columns: ProColumns<ApiRecord>[] = [
    { title: '时间', dataIndex: 'occurredAt', width: 180, render: (_, row) => formatDate(row.occurredAt ?? row.createdAt) },
    { title: '摘要', dataIndex: 'summary', ellipsis: true, render: (_, row) => displayValue(row.summary ?? auditActionLabel(row.action)) },
    { title: '操作者', dataIndex: 'actor', width: 150, render: (_, row) => displayValue(row.actor ?? row.createdBy ?? 'admin') },
    { title: '动作', dataIndex: 'action', width: 190, render: (_, row) => auditActionLabel(row.action) },
    { title: '对象类型', dataIndex: 'entityType', width: 150, render: (_, row) => displayValue(row.entityType ?? row.targetType ?? row.objectType) },
    { title: '对象 ID', dataIndex: 'entityId', width: 220, ellipsis: true, render: (_, row) => displayValue(row.entityId ?? row.targetId ?? pickId(row)) },
    { title: '详情', valueType: 'option', width: 90, render: (_, row) => <Button size="small" onClick={() => props.onOpenDetail(datasets.auditLogs, row)}>查看</Button> },
  ];

  return (
    <PageContainer title="数据操作审计" content="默认展示摘要、操作者、动作和对象；变更前后与原始记录在展开区保留。">
      <Space direction="vertical" size={16} className="full-width">
        <Card>
          <Space className="table-toolbar" wrap>
            <Input.Search placeholder="搜索摘要、对象、操作者" value={keyword} onChange={(event) => setKeyword(event.target.value)} allowClear style={{ width: 320 }} />
            <Select placeholder="动作筛选" allowClear value={action} onChange={setAction} options={actionOptions} style={{ width: 220 }} />
            <Button icon={<ReloadOutlined />} onClick={() => void load()}>刷新</Button>
          </Space>
          <ProTable<ApiRecord>
            rowKey={(row) => displayValue(pickId(row) ?? JSON.stringify(row))}
            loading={loading}
            search={false}
            options={false}
            columns={columns}
            dataSource={filtered}
            expandable={{ expandedRowRender: (row) => <AuditList rows={[row]} /> }}
            pagination={{ pageSize: 12, showSizeChanger: true }}
            scroll={{ x: 1200 }}
          />
        </Card>
        <RawDataCollapse title="审计原始响应" value={payload} />
      </Space>
    </PageContainer>
  );
}
