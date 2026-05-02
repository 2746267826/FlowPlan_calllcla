import { Alert, Button, Card, Form, Input, Modal, Select, Space, message } from 'antd';
import { PageContainer } from '@ant-design/pro-components';
import { useState } from 'react';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord, OperationState } from '../types';
import { parseJsonOrString } from '../utils/format';
import { JsonBlock } from '../components/JsonBlock';
import { RawDataCollapse } from '../components/RawDataCollapse';

const operationOptions = [
  { label: '重建同步索引', value: 'rebuild-sync-index' },
  { label: '重试失败推送', value: 'retry-failed-pushes' },
  { label: '清理过期会话', value: 'cleanup-expired-sessions' },
  { label: '重算报告摘要', value: 'recompute-report-summary' },
];

export function OperationsPage(props: { api: AdminApiClient; onDataRefresh: () => void }) {
  const [state, setState] = useState<OperationState>({
    operationKey: operationOptions[0].value,
    payload: '{\n  "reason": "web_admin operation"\n}',
  });
  const [loading, setLoading] = useState(false);

  const prepare = async () => {
    setLoading(true);
    try {
      const prepared = await props.api.prepareOperation(state.operationKey, parseJsonOrString(state.payload));
      setState((prev) => ({ ...prev, prepared, result: undefined, error: undefined }));
      props.onDataRefresh();
      message.success('已完成准备检查，请确认影响范围后再执行');
    } catch (error) {
      setState((prev) => ({ ...prev, error: error instanceof Error ? error.message : String(error) }));
    } finally {
      setLoading(false);
    }
  };

  const confirm = () => {
    const token = String((state.prepared as ApiRecord | undefined)?.confirmationToken ?? '');
    if (!token) {
      message.warning('请先执行准备检查，拿到确认令牌后才能执行');
      return;
    }
    Modal.confirm({
      title: '确认执行高风险运维操作',
      content: '该动作会修改服务端状态，并写入审计。请确认准备结果中的影响范围、对象数量和风险提示。',
      okText: '确认执行',
      okButtonProps: { danger: true },
      cancelText: '取消',
      onOk: async () => {
        const result = await props.api.confirmOperation(state.operationKey, parseJsonOrString(state.payload), token);
        setState((prev) => ({ ...prev, result, error: undefined }));
        props.onDataRefresh();
        message.success('运维操作已执行');
      },
    });
  };

  return (
    <PageContainer title="运维操作" content="高风险动作必须先 prepare 查看影响范围，再 confirm 执行；结果与审计保留。">
      <Space direction="vertical" size={16} className="full-width">
        <Alert type="warning" showIcon message="这里不再把 JSON 表单当主界面，准备结果、影响范围和确认动作才是主要工作流。" />
        <Card title="准备与确认">
          <Form layout="vertical">
            <Form.Item label="操作 Key">
              <Select value={state.operationKey} onChange={(operationKey) => setState((prev) => ({ ...prev, operationKey }))} options={operationOptions} />
            </Form.Item>
            <Form.Item label="参数 JSON">
              <Input.TextArea rows={8} value={state.payload} onChange={(event) => setState((prev) => ({ ...prev, payload: event.target.value }))} />
            </Form.Item>
            <Space>
              <Button type="primary" loading={loading} onClick={prepare}>准备执行</Button>
              <Button danger disabled={!state.prepared} onClick={confirm}>确认执行</Button>
            </Space>
          </Form>
        </Card>
        {state.error ? <Alert type="error" showIcon message="操作失败" description={state.error} /> : null}
        <JsonBlock title="准备结果与影响范围" value={state.prepared} />
        <JsonBlock title="执行结果" value={state.result} />
        <RawDataCollapse title="当前运维表单原始数据" value={state} />
      </Space>
    </PageContainer>
  );
}
