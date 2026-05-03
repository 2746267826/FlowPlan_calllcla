import { Alert, Button, Card, Form, Input, InputNumber, Space, Table, Tag, Typography, message } from 'antd';
import type { ColumnsType } from 'antd/es/table';
import { CloudSyncOutlined, FolderAddOutlined, ReloadOutlined } from '@ant-design/icons';
import { PageContainer } from '@ant-design/pro-components';
import { useEffect, useMemo, useState } from 'react';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord } from '../types';
import { formatDate } from '../utils/format';
import { RawDataCollapse } from '../components/RawDataCollapse';

interface DriveRootRecord extends ApiRecord {
  id: string;
  rootUid?: string;
  name?: string;
  rootUri?: string;
  rootDisplayPath?: string;
  scanStatus?: string;
  lastScanAt?: string;
  lastError?: string;
  nodeCount?: number;
  updatedAt?: string;
  metadata?: ApiRecord;
}

interface DriveRootFormValues {
  name: string;
  rootUri: string;
  rootDisplayPath?: string;
  maxNodes?: number;
}

export function DriveFilesPage(props: {
  api: AdminApiClient;
  onDataRefresh: () => void;
}) {
  const [form] = Form.useForm<DriveRootFormValues>();
  const [roots, setRoots] = useState<DriveRootRecord[]>([]);
  const [payload, setPayload] = useState<unknown>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [scanningRootId, setScanningRootId] = useState<string | null>(null);
  const [keyword, setKeyword] = useState('');
  const [messageApi, contextHolder] = message.useMessage();

  const load = async () => {
    setLoading(true);
    try {
      const result = await props.api.driveRoots(keyword);
      setPayload(result);
      setRoots(readRoots(result));
      props.onDataRefresh();
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const onSubmit = async (values: DriveRootFormValues) => {
    setSaving(true);
    try {
      const result = await props.api.upsertDriveRoot({
        name: values.name.trim(),
        rootUri: values.rootUri.trim(),
        rootDisplayPath: values.rootDisplayPath?.trim(),
        maxNodes: values.maxNodes,
      });
      if (result.ok !== true) {
        throw new Error(String(result.message ?? result.reason ?? 'Drive root save failed.'));
      }
      messageApi.success('Drive root saved.');
      form.resetFields(['name', 'rootUri', 'rootDisplayPath']);
      await load();
    } finally {
      setSaving(false);
    }
  };

  const scanRoot = async (root: DriveRootRecord) => {
    const rootId = String(root.id);
    setScanningRootId(rootId);
    try {
      const maxNodes = readMaxNodes(root) ?? form.getFieldValue('maxNodes') ?? 5000;
      const result = await props.api.scanDriveRoot(rootId, { maxNodes });
      if (result.ok !== true) {
        throw new Error(String(result.error ?? result.reason ?? 'Drive root scan failed.'));
      }
      messageApi.success(`Scan completed: ${String(result.scanned ?? result.applied ?? 0)} nodes.`);
      await load();
    } finally {
      setScanningRootId(null);
    }
  };

  const columns = useMemo<ColumnsType<DriveRootRecord>>(
    () => [
      {
        title: 'Name',
        dataIndex: 'name',
        width: 220,
        ellipsis: true,
      },
      {
        title: 'Server Path',
        dataIndex: 'rootUri',
        ellipsis: true,
        render: (value) => <Typography.Text copyable>{String(value ?? '')}</Typography.Text>,
      },
      {
        title: 'Status',
        dataIndex: 'scanStatus',
        width: 130,
        render: (value, row) => (
          <Space direction="vertical" size={2}>
            <Tag color={statusColor(String(value ?? 'idle'))}>{String(value ?? 'idle')}</Tag>
            {row.lastError ? (
              <Typography.Text type="danger" ellipsis style={{ maxWidth: 220 }}>
                {row.lastError}
              </Typography.Text>
            ) : null}
          </Space>
        ),
      },
      {
        title: 'Nodes',
        dataIndex: 'nodeCount',
        width: 90,
        render: (value) => String(value ?? 0),
      },
      {
        title: 'Last Scan',
        dataIndex: 'lastScanAt',
        width: 180,
        render: (value) => formatDate(value),
      },
      {
        title: 'Action',
        width: 120,
        render: (_, row) => (
          <Button
            icon={<CloudSyncOutlined />}
            loading={scanningRootId === row.id}
            onClick={() => void scanRoot(row)}
          >
            Scan
          </Button>
        ),
      },
    ],
    [scanningRootId],
  );

  return (
    <PageContainer
      title="Drive Files"
      content="Configure server-side Drive roots, scan their file trees, then let clients browse and download files from the server."
    >
      {contextHolder}
      <Space direction="vertical" size={16} className="full-width">
        <Alert
          type="info"
          showIcon
          message="Server is the source of truth"
          description="Add absolute filesystem paths that are readable by the server process. Client devices will browse the scanned tree and download files through resumable transfer sessions."
        />

        <Card title="Add or Update Drive Root">
          <Form
            form={form}
            layout="vertical"
            initialValues={{ maxNodes: 5000 }}
            onFinish={(values) => void onSubmit(values)}
          >
            <Form.Item
              label="Display name"
              name="name"
              rules={[{ required: true, message: 'Please enter a Drive root name.' }]}
            >
              <Input placeholder="Course files, Project archive, Documents..." />
            </Form.Item>
            <Form.Item
              label="Server absolute path"
              name="rootUri"
              rules={[{ required: true, message: 'Please enter an absolute server path.' }]}
              extra="Examples: C:\\FlowPlanDrive\\Documents or /srv/flowplan-drive/documents"
            >
              <Input placeholder="C:\\FlowPlanDrive\\Documents" />
            </Form.Item>
            <Form.Item label="Display path" name="rootDisplayPath">
              <Input placeholder="Optional friendly path shown to clients" />
            </Form.Item>
            <Form.Item label="Scan node limit" name="maxNodes">
              <InputNumber min={1} max={200000} step={500} style={{ width: 220 }} />
            </Form.Item>
            <Button type="primary" htmlType="submit" icon={<FolderAddOutlined />} loading={saving}>
              Save Drive Root
            </Button>
          </Form>
        </Card>

        <Card
          title="Drive Roots"
          extra={
            <Space>
              <Input.Search
                allowClear
                placeholder="Search roots"
                value={keyword}
                onChange={(event) => setKeyword(event.target.value)}
                onSearch={() => void load()}
                style={{ width: 240 }}
              />
              <Button icon={<ReloadOutlined />} onClick={() => void load()}>
                Refresh
              </Button>
            </Space>
          }
        >
          <Table<DriveRootRecord>
            rowKey="id"
            loading={loading}
            dataSource={roots}
            columns={columns}
            pagination={{ pageSize: 8, showSizeChanger: true }}
          />
          <RawDataCollapse title="Drive roots raw response" value={payload} />
        </Card>
      </Space>
    </PageContainer>
  );
}

function readRoots(payload: unknown): DriveRootRecord[] {
  if (!payload || typeof payload !== 'object' || !('roots' in payload)) {
    return [];
  }
  const roots = (payload as { roots?: unknown }).roots;
  if (!Array.isArray(roots)) {
    return [];
  }
  return roots
    .filter((item): item is ApiRecord => Boolean(item) && typeof item === 'object' && !Array.isArray(item))
    .map((item) => ({
      ...item,
      id: String(item.id ?? item.rootId ?? item.rootUid ?? ''),
    }))
    .filter((item) => item.id.length > 0);
}

function readMaxNodes(root: DriveRootRecord) {
  const value = root.metadata?.maxNodes;
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? Math.trunc(parsed) : null;
}

function statusColor(status: string) {
  if (status === 'completed') return 'green';
  if (status === 'failed') return 'red';
  if (status === 'scanning' || status === 'running') return 'blue';
  return 'default';
}
