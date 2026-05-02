import { Alert, Button, Card, Descriptions, Form, Input, Modal, Space, Steps, Switch, Tabs, Typography, message } from 'antd';
import { CloudSyncOutlined, KeyOutlined, ReloadOutlined } from '@ant-design/icons';
import { PageContainer, ProTable, StatisticCard, type ProColumns } from '@ant-design/pro-components';
import { useEffect, useMemo, useState } from 'react';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord, OutlookStatus } from '../types';
import { displayValue, extractRows, formatDate, pickId } from '../utils/format';
import { RawDataCollapse } from '../components/RawDataCollapse';
import { StatusTag } from '../components/StatusTag';

export function OutlookPage(props: { api: AdminApiClient; onDataRefresh: () => void }) {
  const [status, setStatus] = useState<OutlookStatus>({});
  const [calendars, setCalendars] = useState<ApiRecord[]>([]);
  const [runs, setRuns] = useState<ApiRecord[]>([]);
  const [diagnostics, setDiagnostics] = useState<ApiRecord>({});
  const [loading, setLoading] = useState(true);

  const load = async () => {
    setLoading(true);
    try {
      const [statusResult, calendarsResult, runsResult, diagnosticsResult] = await Promise.all([
        props.api.outlookStatus().catch((error) => ({ status: 'failed', lastError: String(error) })),
        props.api.outlookCalendars().catch(() => ({})),
        props.api.outlookRuns().catch(() => ({})),
        props.api.outlookDiagnostics().catch(() => ({})),
      ]);
      setStatus(statusResult as OutlookStatus);
      setCalendars(extractRows(calendarsResult));
      setRuns(extractRows(runsResult));
      setDiagnostics(diagnosticsResult);
      props.onDataRefresh();
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const runSync = () => {
    Modal.confirm({
      title: '确认启动 Outlook 同步',
      content: '将按当前授权与日历映射拉取 Outlook 日历事件，只读同步不会修改 Outlook 端数据。',
      okText: '启动同步',
      cancelText: '取消',
      onOk: async () => {
        await props.api.syncOutlook();
        message.success('已启动 Outlook 同步');
        await load();
      },
    });
  };

  const reset = () => {
    Modal.confirm({
      title: '确认重置 Outlook 集成',
      content: '会清理本地 Outlook 授权状态与同步状态，请确认已经评估影响范围。',
      okText: '确认重置',
      okButtonProps: { danger: true },
      cancelText: '取消',
      onOk: async () => {
        await props.api.resetOutlook();
        message.success('Outlook 集成已重置');
        await load();
      },
    });
  };

  const calendarColumns = useMemo<ProColumns<ApiRecord>[]>(
    () => [
      { title: '日历', dataIndex: 'name', ellipsis: true, render: (_, row) => displayValue(row.name ?? row.summary ?? row.calendarName) },
      { title: '日历 ID', dataIndex: 'id', ellipsis: true, render: (_, row) => displayValue(row.id ?? row.calendarId) },
      { title: '同步', dataIndex: 'enabled', width: 90, render: (_, row) => <Switch checked={Boolean(row.enabled ?? row.selected)} disabled /> },
      { title: '颜色', dataIndex: 'color', width: 100, render: (_, row) => displayValue(row.color ?? row.hexColor, '未上报') },
    ],
    [],
  );

  const runColumns: ProColumns<ApiRecord>[] = [
    { title: '时间', dataIndex: 'createdAt', width: 180, render: (_, row) => formatDate(row.createdAt ?? row.startedAt) },
    { title: '状态', dataIndex: 'status', width: 120, render: (_, row) => <StatusTag value={row.status} /> },
    { title: '范围', dataIndex: 'scope', width: 130, render: (_, row) => displayValue(row.scope ?? row.mode) },
    { title: '结果', dataIndex: 'summary', ellipsis: true, render: (_, row) => displayValue(row.summary ?? row.message ?? row.error) },
  ];

  return (
    <PageContainer title="Outlook 集成" content="授权、连接状态、同步控制、日历映射、同步历史和诊断信息。">
      <Space direction="vertical" size={16} className="full-width">
        <StatisticCard.Group>
          <StatisticCard statistic={{ title: '连接状态', value: status.connected ? '已连接' : displayValue(status.status, '未连接') }} />
          <StatisticCard statistic={{ title: '账号', value: displayValue(status.accountEmail ?? status.accountDisplayName, '未授权') }} />
          <StatisticCard statistic={{ title: '日历数', value: calendars.length }} />
          <StatisticCard statistic={{ title: '上次同步', value: formatDate(status.lastSyncAt) }} />
        </StatisticCard.Group>
        {status.lastError ? <Alert type="error" showIcon message="Outlook 最近错误" description={displayValue(status.lastError)} /> : null}
        <Card
          title="授权与同步控制"
          extra={
            <Space>
              <Button icon={<ReloadOutlined />} onClick={() => void load()}>刷新</Button>
              <Button icon={<CloudSyncOutlined />} onClick={runSync}>立即同步</Button>
              <Button danger onClick={reset}>重置集成</Button>
            </Space>
          }
          loading={loading}
        >
          <Steps
            current={status.connected ? 2 : status.clientIdConfigured ? 1 : 0}
            items={[
              { title: '授权配置', description: status.clientIdConfigured ? '客户端 ID 已配置' : '需要配置客户端 ID' },
              { title: '账户授权', description: status.connected ? '账号已连接' : '等待授权回调' },
              { title: '只读同步', description: status.readOnly === false ? '请确认权限范围' : '按只读流程同步' },
            ]}
          />
          <Form layout="vertical" className="outlook-form">
            <Form.Item label="客户端 ID">
              <Input.Search
                enterButton="开始授权"
                prefix={<KeyOutlined />}
                placeholder="输入 Microsoft 应用 Client ID"
                onSearch={async (clientId) => {
                  if (!clientId.trim()) return;
                  const result = await props.api.startOutlookAuth(clientId.trim());
                  const authorizeUrl = extractAuthorizeUrl(result);
                  message.success('已生成授权入口');
                  Modal.info({
                    title: '授权入口',
                    width: 760,
                    okText: '关闭',
                    content: (
                      <Space direction="vertical" size={12} className="full-width">
                        <Typography.Text type="secondary">
                          请打开下面的 Microsoft 授权链接，完成登录和授权后，把回调 URL 粘贴到“授权回调 URL”输入框。
                        </Typography.Text>
                        <Input.TextArea readOnly value={authorizeUrl} autoSize={{ minRows: 4, maxRows: 8 }} />
                        <Space>
                          <Button type="primary" href={authorizeUrl} target="_blank" rel="noreferrer">
                            打开授权页面
                          </Button>
                          <Button onClick={() => void navigator.clipboard?.writeText(authorizeUrl)}>复制链接</Button>
                        </Space>
                      </Space>
                    ),
                  });
                  await load();
                }}
              />
            </Form.Item>
            <Form.Item label="授权回调 URL">
              <Input.Search
                enterButton="完成授权"
                placeholder="粘贴 Microsoft 回调后的完整 URL"
                onSearch={async (callbackUrl) => {
                  if (!callbackUrl.trim()) return;
                  await props.api.completeOutlookAuth(callbackUrl.trim());
                  message.success('Outlook 授权已完成');
                  await load();
                }}
              />
            </Form.Item>
          </Form>
        </Card>
        <Tabs
          items={[
            {
              key: 'mapping',
              label: '日历映射',
              children: <ProTable<ApiRecord> rowKey={(row) => displayValue(pickId(row) ?? JSON.stringify(row))} search={false} options={false} columns={calendarColumns} dataSource={calendars} pagination={{ pageSize: 8 }} />,
            },
            {
              key: 'runs',
              label: '同步历史',
              children: <ProTable<ApiRecord> rowKey={(row) => displayValue(pickId(row) ?? JSON.stringify(row))} search={false} options={false} columns={runColumns} dataSource={runs} pagination={{ pageSize: 8 }} />,
            },
            {
              key: 'diagnostics',
              label: '诊断信息',
              children: (
                <Space direction="vertical" className="full-width">
                  <Descriptions bordered size="small" column={2}>
                    <Descriptions.Item label="令牌密钥">{status.tokenSecretConfigured ? '已配置' : '未配置'}</Descriptions.Item>
                    <Descriptions.Item label="密钥来源">{displayValue(status.tokenSecretSource)}</Descriptions.Item>
                    <Descriptions.Item label="权限范围">{displayValue(status.scope)}</Descriptions.Item>
                    <Descriptions.Item label="只读模式">{status.readOnly === false ? '否' : '是'}</Descriptions.Item>
                  </Descriptions>
                  <RawDataCollapse title="诊断原始响应" value={diagnostics} />
                </Space>
              ),
            },
          ]}
        />
      </Space>
    </PageContainer>
  );
}

function extractAuthorizeUrl(result: ApiRecord): string {
  const candidates = [result.authorizeUrl, result.authorizationUrl, result.authUrl, result.url];
  for (const value of candidates) {
    if (typeof value === 'string' && value.trim()) return value.trim();
  }
  return displayValue(result);
}
