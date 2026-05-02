import { Button, Card, Input, Select, Space } from 'antd';
import { ReloadOutlined } from '@ant-design/icons';
import { PageContainer, ProTable, type ProColumns } from '@ant-design/pro-components';
import { useEffect, useMemo, useState } from 'react';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord, DatasetDefinition } from '../types';
import { displayValue, extractRows, formatDate, getNestedValue, statusLabel } from '../utils/format';
import { RawDataCollapse } from '../components/RawDataCollapse';
import { StatusTag } from '../components/StatusTag';

export interface BusinessPanel {
  dataset: DatasetDefinition;
  endpoint: string;
  columns: Array<{ key: string; label: string; width?: number; type?: 'status' | 'date' | 'number' | 'json' }>;
}

export function BusinessListPage(props: {
  title: string;
  description: string;
  panels: BusinessPanel[];
  api: AdminApiClient;
  onDataRefresh: () => void;
  onOpenDetail: (dataset: DatasetDefinition, row: ApiRecord) => void;
}) {
  return (
    <PageContainer title={props.title} content={props.description}>
      <Space direction="vertical" size={16} className="full-width">
        {props.panels.map((panel) => (
          <ReadablePanel
            api={props.api}
            key={panel.dataset.domain}
            panel={panel}
            onDataRefresh={props.onDataRefresh}
            onOpenDetail={(row) => props.onOpenDetail(panel.dataset, row)}
          />
        ))}
      </Space>
    </PageContainer>
  );
}

function ReadablePanel(props: {
  api: AdminApiClient;
  panel: BusinessPanel;
  onDataRefresh: () => void;
  onOpenDetail: (row: ApiRecord) => void;
}) {
  const [rows, setRows] = useState<ApiRecord[]>([]);
  const [payload, setPayload] = useState<unknown>(null);
  const [loading, setLoading] = useState(true);
  const [keyword, setKeyword] = useState('');
  const [status, setStatus] = useState<string>();

  const load = async () => {
    setLoading(true);
    try {
      const search = new URLSearchParams({ limit: '100' });
      const joiner = props.panel.endpoint.includes('?') ? '&' : '?';
      const result = await props.api.request<unknown>(`${props.panel.endpoint}${joiner}${search.toString()}`);
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

  const filteredRows = useMemo(() => {
    const keywordText = keyword.trim().toLowerCase();
    return rows.filter((row) => {
      const matchesKeyword =
        !keywordText ||
        JSON.stringify(row)
          .toLowerCase()
          .includes(keywordText);
      const rowStatus = String(row.status ?? row.state ?? row.syncStatus ?? '');
      const matchesStatus = !status || rowStatus === status;
      return matchesKeyword && matchesStatus;
    });
  }, [keyword, rows, status]);

  const statusOptions = useMemo(
    () =>
      Array.from(new Set(rows.map((row) => String(row.status ?? row.state ?? row.syncStatus ?? '')).filter(Boolean))).map(
        (value) => ({ label: statusLabel(value), value }),
      ),
    [rows],
  );

  const columns = useMemo<ProColumns<ApiRecord>[]>(
    () => [
      ...props.panel.columns.map<ProColumns<ApiRecord>>((column) => ({
        title: column.label,
        dataIndex: column.key,
        width: column.width,
        ellipsis: true,
        render: (_, row) => {
          const value = getNestedValue(row, column.key);
          if (column.type === 'status') return <StatusTag value={value} />;
          if (column.type === 'date') return formatDate(value);
          return displayValue(value);
        },
      })),
      {
        title: '操作',
        valueType: 'option',
        width: 90,
        render: (_, row) => (
          <Button size="small" onClick={() => props.onOpenDetail(row)}>
            详情
          </Button>
        ),
      },
    ],
    [props],
  );

  return (
    <Card
      title={props.panel.dataset.title}
      extra={
        <Button icon={<ReloadOutlined />} onClick={() => void load()}>
          刷新
        </Button>
      }
    >
      <Space className="table-toolbar" wrap>
        <Input.Search
          allowClear
          placeholder="搜索当前列表"
          value={keyword}
          onChange={(event) => setKeyword(event.target.value)}
          style={{ width: 280 }}
        />
        <Select
          allowClear
          placeholder="状态筛选"
          value={status}
          options={statusOptions}
          onChange={setStatus}
          style={{ width: 180 }}
        />
      </Space>
      <ProTable<ApiRecord>
        rowKey={(row) => displayValue(row.id ?? row.uid ?? row.key ?? JSON.stringify(row).slice(0, 80))}
        loading={loading}
        dataSource={filteredRows}
        columns={columns}
        search={false}
        options={false}
        pagination={{ pageSize: 10, showSizeChanger: true }}
        scroll={{ x: 'max-content' }}
      />
      <RawDataCollapse title={`${props.panel.dataset.title}原始响应`} value={payload} />
    </Card>
  );
}
