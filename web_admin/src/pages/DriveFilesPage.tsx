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
        throw new Error(String(result.message ?? result.reason ?? '云盘根目录保存失败。'));
      }
      messageApi.success('云盘根目录已保存。');
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
        throw new Error(String(result.error ?? result.reason ?? '云盘根目录扫描失败。'));
      }
      messageApi.success(`扫描完成：${String(result.scanned ?? result.applied ?? 0)} 个节点。`);
      await load();
    } finally {
      setScanningRootId(null);
    }
  };

  const columns = useMemo<ColumnsType<DriveRootRecord>>(
    () => [
      {
        title: '名称',
        dataIndex: 'name',
        width: 220,
        ellipsis: true,
      },
      {
        title: '服务器路径',
        dataIndex: 'rootUri',
        ellipsis: true,
        render: (value) => <Typography.Text copyable>{String(value ?? '')}</Typography.Text>,
      },
      {
        title: '状态',
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
        title: '节点数',
        dataIndex: 'nodeCount',
        width: 90,
        render: (value) => String(value ?? 0),
      },
      {
        title: '上次扫描',
        dataIndex: 'lastScanAt',
        width: 180,
        render: (value) => formatDate(value),
      },
      {
        title: '操作',
        width: 120,
        render: (_, row) => (
          <Button
            icon={<CloudSyncOutlined />}
            loading={scanningRootId === row.id}
            onClick={() => void scanRoot(row)}
          >
            扫描
          </Button>
        ),
      },
    ],
    [scanningRootId],
  );

  return (
    <PageContainer
      title="文件资料"
      content="配置服务器端的云盘根目录，扫描其文件树，然后让客户端从服务器浏览和下载文件。"
    >
      {contextHolder}
      <Space direction="vertical" size={16} className="full-width">
        <Alert
          type="info"
          showIcon
          message="服务器是数据的唯一来源"
          description="添加服务器进程可读取的绝对文件系统路径。客户端设备将浏览扫描的文件树，并通过可恢复的传输会话下载文件。"
        />

        <Card title="Add or Update Drive Root">
          <Form
            form={form}
            layout="vertical"
            initialValues={{ maxNodes: 5000 }}
            onFinish={(values) => void onSubmit(values)}
          >
            <Form.Item
              label="显示名称"
              name="name"
              rules={[{ required: true, message: '请输入云盘根目录名称。' }]}
            >
              <Input placeholder="课程文件、项目档案、文档..." />
            </Form.Item>
            <Form.Item
              label="服务器绝对路径"
              name="rootUri"
              rules={[{ required: true, message: '请输入服务器绝对路径。' }]}
              extra="示例：C:\\FlowPlanDrive\\Documents 或 /srv/flowplan-drive/documents"
            >
              <Input placeholder="C:\\FlowPlanDrive\\Documents" />
            </Form.Item>
            <Form.Item label="显示路径" name="rootDisplayPath">
              <Input placeholder="可选的友好路径，显示给客户端" />
            </Form.Item>
            <Form.Item label="扫描节点限制" name="maxNodes">
              <InputNumber min={1} max={200000} step={500} style={{ width: 220 }} />
            </Form.Item>
            <Button type="primary" htmlType="submit" icon={<FolderAddOutlined />} loading={saving}>
              保存云盘根目录
            </Button>
          </Form>
        </Card>

        <Card
          title="云盘根目录"
          extra={
            <Space>
              <Input.Search
                allowClear
                placeholder="搜索根目录"
                value={keyword}
                onChange={(event) => setKeyword(event.target.value)}
                onSearch={() => void load()}
                style={{ width: 240 }}
              />
              <Button icon={<ReloadOutlined />} onClick={() => void load()}>
                刷新
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
          <RawDataCollapse title="云盘根目录原始响应" value={payload} />
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
