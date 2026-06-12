import {
  Alert,
  Button,
  Card,
  Descriptions,
  Form,
  Input,
  Popconfirm,
  Space,
  Statistic,
  Table,
  Tag,
  Typography,
  message,
} from 'antd';
import type { ColumnsType } from 'antd/es/table';
import {
  CloudSyncOutlined,
  DeleteOutlined,
  FolderAddOutlined,
  ReloadOutlined,
} from '@ant-design/icons';
import { PageContainer } from '@ant-design/pro-components';
import { useEffect, useMemo, useState } from 'react';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord } from '../types';
import { formatDate, prettyJson } from '../utils/format';
import { RawDataCollapse } from '../components/RawDataCollapse';

interface DriveRootRecord extends ApiRecord {
  id: string;
  rootUid?: string;
  name?: string;
  providerType?: string;
  rootUri?: string;
  rootDisplayPath?: string;
  scanStatus?: string;
  lastScanAt?: string;
  lastError?: string;
  syncPolicy?: string;
  nodeCount?: number;
  fileCount?: number;
  folderCount?: number;
  totalBytes?: number;
  lastNodeUpdateAt?: string;
  storageObjectCount?: number;
  storageTotalBytes?: number;
  lastOperation?: string;
  lastOperationStatus?: string;
  lastOperationError?: string;
  lastOperationAt?: string;
  updatedAt?: string;
  metadata?: ApiRecord;
}

interface DriveRootFormValues {
  name: string;
  rootUri: string;
  rootDisplayPath?: string;
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
  const [deletingRootId, setDeletingRootId] = useState<string | null>(null);
  const [keyword, setKeyword] = useState('');
  const [pageError, setPageError] = useState<string | null>(null);
  const [messageApi, contextHolder] = message.useMessage();

  const load = async (options: { silent?: boolean } = {}) => {
    if (!options.silent) {
      setLoading(true);
      setPageError(null);
    }
    try {
      const result = await props.api.driveRoots(keyword);
      setPayload(result);
      setRoots(readRoots(result));
      props.onDataRefresh();
    } catch (error) {
      const detail = errorMessage(error);
      if (!options.silent) {
        setPageError(`加载 Drive roots 失败：${detail}`);
        messageApi.error('加载 Drive roots 失败');
      }
    } finally {
      if (!options.silent) {
        setLoading(false);
      }
    }
  };

  useEffect(() => {
    void load();
  }, []);

  useEffect(() => {
    if (!scanningRootId) {
      return undefined;
    }
    const timer = window.setInterval(() => {
      void load({ silent: true });
    }, 2000);
    return () => window.clearInterval(timer);
  }, [scanningRootId, keyword]);

  const onSubmit = async (values: DriveRootFormValues) => {
    setSaving(true);
    setPageError(null);
    try {
      const result = await props.api.upsertDriveRoot({
        name: values.name.trim(),
        rootUri: values.rootUri.trim(),
        rootDisplayPath: values.rootDisplayPath?.trim(),
      });
      if (result.ok !== true) {
        throw new Error(String(result.message ?? result.reason ?? 'Drive root 保存失败'));
      }
      messageApi.success('Drive root 已保存');
      form.resetFields(['name', 'rootUri', 'rootDisplayPath']);
      await load();
    } catch (error) {
      const detail = errorMessage(error);
      setPageError(`保存 Drive root 失败：${detail}`);
      messageApi.error('保存 Drive root 失败');
    } finally {
      setSaving(false);
    }
  };

  const scanRoot = async (root: DriveRootRecord) => {
    const rootId = String(root.id);
    setScanningRootId(rootId);
    setPageError(null);
    try {
      const result = await props.api.scanDriveRoot(rootId);
      if (result.ok !== true) {
        throw new Error(String(result.error ?? result.reason ?? 'Drive root 扫描失败'));
      }
      messageApi.success(`扫描完成：${String(result.scanned ?? result.applied ?? 0)} 个节点`);
      await load();
    } catch (error) {
      const detail = errorMessage(error);
      setPageError(`扫描 Drive root 失败：${detail}`);
      messageApi.error('扫描 Drive root 失败');
      await load({ silent: true });
    } finally {
      setScanningRootId(null);
    }
  };

  const deleteRoot = async (root: DriveRootRecord) => {
    const rootId = String(root.id);
    setDeletingRootId(rootId);
    setPageError(null);
    try {
      const result = await props.api.deleteDriveRoot(rootId);
      if (result.ok !== true) {
        throw new Error(String(result.reason ?? result.message ?? 'Drive root 删除失败'));
      }
      const counts = asRecord(result.deletedCounts);
      messageApi.success(
        `已删除 root 索引：${String(counts.nodes ?? 0)} 个节点，服务器文件未删除`,
      );
      await load();
    } catch (error) {
      const detail = errorMessage(error);
      setPageError(`删除 Drive root 失败：${detail}`);
      messageApi.error('删除 Drive root 失败');
    } finally {
      setDeletingRootId(null);
    }
  };

  const columns = useMemo<ColumnsType<DriveRootRecord>>(
    () => [
      {
        title: '名称',
        dataIndex: 'name',
        width: 180,
        ellipsis: true,
        render: (value, row) => (
          <Space direction="vertical" size={0}>
            <Typography.Text strong>{String(value ?? '未命名 root')}</Typography.Text>
            <Typography.Text type="secondary" copyable={{ text: row.id }} style={{ fontSize: 12 }}>
              {row.id}
            </Typography.Text>
          </Space>
        ),
      },
      {
        title: '服务器路径',
        dataIndex: 'rootUri',
        ellipsis: true,
        render: (value) => <Typography.Text copyable>{String(value ?? '')}</Typography.Text>,
      },
      {
        title: '扫描状态',
        dataIndex: 'scanStatus',
        width: 170,
        render: (value, row) => (
          <Space direction="vertical" size={2}>
            <Tag color={scanStatusColor(String(value ?? 'idle'))}>{String(value ?? 'idle')}</Tag>
            {String(value ?? '') === 'scanning' ? (
              <Typography.Text type="secondary" ellipsis style={{ maxWidth: 240 }}>
                {String(asRecord(row.metadata?.lastScan).progressMessage ?? '正在扫描...')}
              </Typography.Text>
            ) : null}
            {row.lastError ? (
              <Typography.Text type="danger" copyable ellipsis style={{ maxWidth: 240 }}>
                {row.lastError}
              </Typography.Text>
            ) : (
              <Typography.Text type="secondary">无错误</Typography.Text>
            )}
          </Space>
        ),
      },
      {
        title: '规模',
        width: 170,
        render: (_, row) => (
          <Space direction="vertical" size={0}>
            <Typography.Text>{formatCount(row.nodeCount)} 节点</Typography.Text>
            <Typography.Text type="secondary">
              {formatCount(row.fileCount)} 文件 / {formatCount(row.folderCount)} 文件夹
            </Typography.Text>
            <Typography.Text type="secondary">{formatBytes(row.totalBytes)}</Typography.Text>
          </Space>
        ),
      },
      {
        title: '最近活动',
        width: 210,
        render: (_, row) => (
          <Space direction="vertical" size={0}>
            <Typography.Text>扫描：{formatDate(row.lastScanAt)}</Typography.Text>
            <Typography.Text type="secondary">节点：{formatDate(row.lastNodeUpdateAt)}</Typography.Text>
            <Typography.Text type="secondary">
              操作：{row.lastOperation ? `${row.lastOperation} / ${formatDate(row.lastOperationAt)}` : '无'}
            </Typography.Text>
          </Space>
        ),
      },
      {
        title: '操作',
        width: 190,
        render: (_, row) => (
          <Space>
            <Button
              aria-label={`Scan drive root ${displayRootName(row)}`}
              icon={<CloudSyncOutlined />}
              loading={scanningRootId === row.id}
              onClick={() => void scanRoot(row)}
            >
              扫描
            </Button>
            <Popconfirm
              title="删除这个 Drive root？"
              description="只删除 root 配置和文件树索引，不删除服务器真实目录和已保留的存储对象。"
              okText="删除索引"
              okButtonProps={{ danger: true }}
              cancelText="取消"
              onConfirm={() => void deleteRoot(row)}
            >
              <Button
                aria-label={`Delete drive root ${displayRootName(row)}`}
                danger
                icon={<DeleteOutlined />}
                loading={deletingRootId === row.id}
              >
                删除
              </Button>
            </Popconfirm>
          </Space>
        ),
      },
    ],
    [deletingRootId, scanningRootId],
  );

  return (
    <PageContainer
      title="文件资料"
      content="配置服务器端 Drive 根目录，扫描文件树，并为客户端提供只读浏览和下载入口。"
    >
      {contextHolder}
      <Space direction="vertical" size={16} className="full-width">
        <Alert
          type="info"
          showIcon
          message="服务器是文件资料的唯一来源"
          description="这里录入的是服务器进程可读取的绝对路径。客户端只浏览扫描后的文件树，并通过下载会话保存到本机。删除 root 只删除索引，不删除真实服务器目录。"
        />

        {pageError ? (
          <Alert
            type="error"
            showIcon
            message="操作失败"
            description={<Typography.Paragraph copyable>{pageError}</Typography.Paragraph>}
          />
        ) : null}

        <Card title="新增或更新 Drive Root">
          <Form
            form={form}
            layout="vertical"
            onFinish={(values) => void onSubmit(values)}
          >
            <Form.Item
              label="显示名称"
              name="name"
              rules={[{ required: true, message: '请输入 Drive root 名称。' }]}
            >
              <Input placeholder="课程文件、项目档案、文档库..." />
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
              <Input placeholder="可选：显示给客户端的友好路径" />
            </Form.Item>
            <Button type="primary" htmlType="submit" icon={<FolderAddOutlined />} loading={saving}>
              保存 Drive root
            </Button>
          </Form>
        </Card>

        <Card
          title="Drive Roots"
          extra={
            <Space>
              <Input.Search
                allowClear
                placeholder="搜索 root 名称或路径"
                value={keyword}
                onChange={(event) => setKeyword(event.target.value)}
                onSearch={() => void load()}
                style={{ width: 260 }}
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
            expandable={{
              expandedRowRender: (row) => <RootDiagnostics root={row} />,
            }}
          />
          <RawDataCollapse title="Drive roots 原始响应" value={payload} />
        </Card>
      </Space>
    </PageContainer>
  );
}

export function RootDiagnostics(props: { root: DriveRootRecord }) {
  const { root } = props;
  const lastScan = asRecord(root.metadata?.lastScan);
  return (
    <Space direction="vertical" size={16} className="full-width">
      <Card size="small" title="诊断摘要">
        <Space wrap size={16}>
          <Statistic title="节点" value={formatCount(root.nodeCount)} />
          <Statistic title="文件" value={formatCount(root.fileCount)} />
          <Statistic title="文件夹" value={formatCount(root.folderCount)} />
          <Statistic title="文件总量" value={formatBytes(root.totalBytes)} />
          <Statistic title="保留对象" value={formatCount(root.storageObjectCount)} />
          <Statistic title="对象容量" value={formatBytes(root.storageTotalBytes)} />
        </Space>
      </Card>

      <Descriptions size="small" bordered column={2}>
        <Descriptions.Item label="Root ID">{root.id}</Descriptions.Item>
        <Descriptions.Item label="Root UID">{root.rootUid ?? '无'}</Descriptions.Item>
        <Descriptions.Item label="Provider">{root.providerType ?? 'server_storage'}</Descriptions.Item>
        <Descriptions.Item label="Sync Policy">{root.syncPolicy ?? 'metadata_only'}</Descriptions.Item>
        <Descriptions.Item label="服务器路径">
          <Typography.Text copyable>{root.rootUri ?? '无'}</Typography.Text>
        </Descriptions.Item>
        <Descriptions.Item label="显示路径">{root.rootDisplayPath ?? '无'}</Descriptions.Item>
        <Descriptions.Item label="扫描状态">
          <Tag color={scanStatusColor(String(root.scanStatus ?? 'idle'))}>{root.scanStatus ?? 'idle'}</Tag>
        </Descriptions.Item>
        <Descriptions.Item label="最后扫描">{formatDate(root.lastScanAt)}</Descriptions.Item>
        <Descriptions.Item label="最后节点更新">{formatDate(root.lastNodeUpdateAt)}</Descriptions.Item>
        <Descriptions.Item label="最后操作">
          {root.lastOperation ? `${root.lastOperation} / ${root.lastOperationStatus ?? 'unknown'} / ${formatDate(root.lastOperationAt)}` : '无'}
        </Descriptions.Item>
      </Descriptions>

      {root.lastError ? (
        <Alert
          type="error"
          showIcon
          message="最近错误"
          description={<Typography.Paragraph copyable>{root.lastError}</Typography.Paragraph>}
        />
      ) : null}

      <Descriptions size="small" bordered column={2} title="最近扫描诊断">
        <Descriptions.Item label="状态">{String(lastScan.status ?? '无')}</Descriptions.Item>
        <Descriptions.Item label="耗时">{formatDuration(lastScan.durationMs)}</Descriptions.Item>
        <Descriptions.Item label="开始">{formatDate(lastScan.startedAt)}</Descriptions.Item>
        <Descriptions.Item label="结束">{formatDate(lastScan.finishedAt)}</Descriptions.Item>
        <Descriptions.Item label="扫描上限">{Number(lastScan.maxNodes) > 0 ? formatCount(lastScan.maxNodes) : '不限制'}</Descriptions.Item>
        <Descriptions.Item label="扫描数量">{formatCount(lastScan.scanned)}</Descriptions.Item>
        <Descriptions.Item label="应用数量">{formatCount(lastScan.applied)}</Descriptions.Item>
        <Descriptions.Item label="达到上限">{lastScan.reachedMaxNodes === true ? '是' : '否'}</Descriptions.Item>
        <Descriptions.Item label="最近进度">{formatDate(lastScan.lastProgressAt)}</Descriptions.Item>
        <Descriptions.Item label="扫描阶段">{String(lastScan.phase ?? '无')}</Descriptions.Item>
        <Descriptions.Item label="待扫文件夹">{formatCount(lastScan.queuedFolders)}</Descriptions.Item>
        <Descriptions.Item label="进度日志" span={2}>
          <Typography.Text copyable>{String(lastScan.progressMessage ?? '无')}</Typography.Text>
        </Descriptions.Item>
        <Descriptions.Item label="当前路径" span={2}>
          <Typography.Text copyable>{String(lastScan.currentPath ?? '无')}</Typography.Text>
        </Descriptions.Item>
        <Descriptions.Item label="扫描路径" span={2}>
          <Typography.Text copyable>{String(lastScan.rootPath ?? root.rootUri ?? '无')}</Typography.Text>
        </Descriptions.Item>
        {lastScan.error ? (
          <Descriptions.Item label="失败原因" span={2}>
            <Typography.Text type="danger" copyable>
              {String(lastScan.error)}
            </Typography.Text>
          </Descriptions.Item>
        ) : null}
      </Descriptions>

      <RawDataCollapse title="Root metadata" value={root.metadata ?? {}} />
      <Typography.Paragraph copyable={{ text: prettyJson(root) }} type="secondary">
        复制完整 root 诊断 JSON
      </Typography.Paragraph>
    </Space>
  );
}

export function readRoots(payload: unknown): DriveRootRecord[] {
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

export function asRecord(value: unknown): ApiRecord {
  return value && typeof value === 'object' && !Array.isArray(value) ? (value as ApiRecord) : {};
}

export function displayRootName(root: DriveRootRecord) {
  return String(root.name ?? root.rootDisplayPath ?? root.rootUri ?? root.id);
}

export function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error);
}

export function formatCount(value: unknown) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed).toLocaleString('zh-CN') : '0';
}

export function formatBytes(value: unknown) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    return '0 B';
  }
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let size = parsed;
  let unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }
  return `${size.toFixed(unitIndex === 0 ? 0 : 1)} ${units[unitIndex]}`;
}

export function formatDuration(value: unknown) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return '无';
  }
  if (parsed < 1000) {
    return `${Math.trunc(parsed)} ms`;
  }
  return `${(parsed / 1000).toFixed(2)} s`;
}

export function scanStatusColor(status: string) {
  if (status === 'completed') return 'green';
  if (status === 'failed') return 'red';
  if (status === 'scanning' || status === 'running') return 'blue';
  return 'default';
}
