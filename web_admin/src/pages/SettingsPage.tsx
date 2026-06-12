import { Alert, Button, Card, Form, Input, Select, Space, Switch, message } from 'antd';
import { SaveOutlined } from '@ant-design/icons';
import { PageContainer, ProTable, type ProColumns } from '@ant-design/pro-components';
import { useEffect, useState } from 'react';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord, DeviceOption } from '../types';
import { displayValue, extractRows, formatDate, pickId, prettyJson, parseJsonOrString } from '../utils/format';
import { RawDataCollapse } from '../components/RawDataCollapse';
import { JsonBlock } from '../components/JsonBlock';

export function SettingsPage(props: {
  api: AdminApiClient;
  apiBase: string;
  deviceId: string;
  devices: DeviceOption[];
  selectedDeviceId: string;
  onSaveConnection: (apiBase: string, deviceId: string, selectedDeviceId: string) => void;
  onDataRefresh: () => void;
}) {
  const [settings, setSettings] = useState<ApiRecord[]>([]);
  const [payload, setPayload] = useState<unknown>(null);
  const [loading, setLoading] = useState(true);
  const [configKey, setConfigKey] = useState('');
  const [configValue, setConfigValue] = useState('{}');
  const [sensitive, setSensitive] = useState(false);
  const [connectionForm] = Form.useForm();

  const load = async () => {
    setLoading(true);
    try {
      const result = await props.api.settings();
      setPayload(result);
      setSettings(extractRows(result));
      props.onDataRefresh();
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    connectionForm.setFieldsValue({ apiBase: props.apiBase, deviceId: props.deviceId, selectedDeviceId: props.selectedDeviceId });
  }, [props.apiBase, props.deviceId, props.selectedDeviceId]);

  useEffect(() => {
    void load();
  }, []);

  const saveSetting = async () => {
    if (!configKey.trim()) {
      message.warning('请填写配置 Key');
      return;
    }
    await props.api.patchSetting(configKey.trim(), {
      value: parseJsonOrString(configValue),
      sensitive,
      reason: 'web admin setting update',
    });
    message.success('远程配置已保存');
    await load();
  };

  const columns: ProColumns<ApiRecord>[] = [
    { title: '配置 Key', dataIndex: 'configKey', ellipsis: true, render: (_, row) => displayValue(row.configKey ?? row.key ?? pickId(row)) },
    { title: '范围', dataIndex: 'scope', width: 140, render: (_, row) => displayValue(row.scope ?? row.group, '全局') },
    { title: '敏感', dataIndex: 'sensitive', width: 90, render: (_, row) => (row.sensitive ? '是' : '否') },
    { title: '更新时间', dataIndex: 'updatedAt', width: 180, render: (_, row) => formatDate(row.updatedAt) },
    { title: '值', dataIndex: 'value', ellipsis: true, render: (_, row) => displayValue(row.value ?? row.configValue) },
    {
      title: '操作',
      valueType: 'option',
      width: 90,
      render: (_, row) => (
        <Button
          size="small"
          onClick={() => {
            setConfigKey(displayValue(row.configKey ?? row.key ?? pickId(row)));
            setConfigValue(prettyJson(row.value ?? row.configValue ?? {}));
            setSensitive(Boolean(row.sensitive));
          }}
        >
          编辑
        </Button>
      ),
    },
  ];

  return (
    <PageContainer title="系统设置" content="连接设置、设备上下文和服务端远程配置。">
      <Space direction="vertical" size={16} className="full-width">
        <Card title="管理端连接">
          <Form
            form={connectionForm}
            layout="vertical"
            onFinish={(values) => props.onSaveConnection(values.apiBase, values.deviceId, values.selectedDeviceId)}
          >
            <Form.Item label="服务端地址" name="apiBase" rules={[{ required: true }]}>
              <Input placeholder="http://localhost:3202" />
            </Form.Item>
            <Form.Item label="本管理端设备 ID" name="deviceId" rules={[{ required: true }]}>
              <Input />
            </Form.Item>
            <Form.Item label="查看设备上下文" name="selectedDeviceId">
              <Select
                options={[{ label: '全部设备', value: 'all' }, ...props.devices.map((item) => ({ label: `${item.name} - ${item.detail}`, value: item.id }))]}
              />
            </Form.Item>
            <Button type="primary" icon={<SaveOutlined />} htmlType="submit">
              保存连接设置
            </Button>
          </Form>
        </Card>
        <Alert type="info" showIcon message="远程配置会影响客户端或服务端行为，保存前请确认配置 Key、值类型和敏感字段标记。" />
        <Card title="远程配置编辑">
          <Form layout="vertical">
            <Form.Item label="配置 Key">
              <Input aria-label="Remote config key" value={configKey} onChange={(event) => setConfigKey(event.target.value)} placeholder="例如 outlook.sync.enabled" />
            </Form.Item>
            <Form.Item label="配置值 JSON 或文本">
              <Input.TextArea aria-label="Remote config value" value={configValue} onChange={(event) => setConfigValue(event.target.value)} rows={8} />
            </Form.Item>
            <Form.Item label="敏感配置">
              <Switch aria-label="Sensitive remote config" checked={sensitive} onChange={setSensitive} checkedChildren="是" unCheckedChildren="否" />
            </Form.Item>
            <Button aria-label="Save remote config" type="primary" onClick={saveSetting}>保存远程配置</Button>
          </Form>
        </Card>
        <Card title="配置列表">
          <ProTable<ApiRecord>
            rowKey={(row) => displayValue(pickId(row) ?? JSON.stringify(row))}
            loading={loading}
            search={false}
            options={false}
            columns={columns}
            dataSource={settings}
            pagination={{ pageSize: 10, showSizeChanger: true }}
            expandable={{ expandedRowRender: (row) => <JsonBlock title="配置原始记录" value={row} /> }}
            scroll={{ x: 1000 }}
          />
        </Card>
        <RawDataCollapse title="设置原始响应" value={payload} />
      </Space>
    </PageContainer>
  );
}
