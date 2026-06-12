import { Button, Card, Col, Descriptions, Input, message, Row, Tag, Upload } from 'antd';
import { CheckCircleOutlined, CloseCircleOutlined, UploadOutlined } from '@ant-design/icons';
import { PageContainer } from '@ant-design/pro-components';
import { useEffect, useState } from 'react';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord } from '../types';
import { asRecord } from '../utils/format';

export function EnvPage(props: { api: AdminApiClient; onDataRefresh: () => void }) {
  const [env, setEnv] = useState<ApiRecord | null>(null);
  const [envContent, setEnvContent] = useState('');

  const load = async () => {
    try {
      const result = await props.api.request<ApiRecord>('/api/admin/env');
      setEnv(result);
      props.onDataRefresh();
    } catch { /* ignore */ }
  };

  useEffect(() => { void load(); }, []);

  const db = asRecord(env?.database);
  const enc = asRecord(env?.encryption);
  const jwt = asRecord(env?.jwt);
  const svc = asRecord(env?.service);
  const stor = asRecord(env?.storage);
  const kopia = asRecord(env?.kopia);

  const uploadEnv = async () => {
    if (!envContent.trim()) { message.warning('请先粘贴 .env 文件内容'); return; }
    try {
      const res = await props.api.request<ApiRecord>('/api/admin/env/upload', {
        method: 'POST', body: JSON.stringify({ content: envContent }),
      });
      message.success(String((res as ApiRecord).message ?? '已上传'));
      setEnvContent('');
      await load();
    } catch (e) { message.error(e instanceof Error ? e.message : String(e)); }
  };

  return (
    <PageContainer title="运行时环境" content={`当前服务端运行环境快照 · 生成时间: ${String(env?.generatedAt ?? '未加载')}`}>
      <Row gutter={[16, 16]}>
        <Col span={24}>
          <Card title="上传 .env 文件（内容粘贴 → 服务端写入 + 立即加载）" size="small">
            <Input.TextArea
              rows={6}
              value={envContent}
              onChange={(e) => setEnvContent(e.target.value)}
              placeholder="粘贴 .env 文件内容..."
            />
            <Button aria-label="Upload env content" type="primary" icon={<UploadOutlined />} onClick={uploadEnv} style={{ marginTop: 8 }}>
              上传到服务端
            </Button>
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <Card title="数据库" size="small">
            <Descriptions column={1} size="small">
              <Descriptions.Item label="连接状态"><Tag color={db.urlPresent ? 'green' : 'red'}>{(db.urlPresent ? '已配置' : '未配置')}</Tag></Descriptions.Item>
              <Descriptions.Item label="连接池上限">{String(db.poolMax)}</Descriptions.Item>
              <Descriptions.Item label="慢查询阈值">{String(db.slowQueryThresholdMs)}ms</Descriptions.Item>
            </Descriptions>
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <Card title="加密" size="small">
            <Descriptions column={1} size="small">
              <Descriptions.Item label="密钥状态">{enc.keySecure ? <Tag color="green" icon={<CheckCircleOutlined />}>已配置</Tag> : <Tag color="red" icon={<CloseCircleOutlined />}>未配置</Tag>}</Descriptions.Item>
              <Descriptions.Item label="密钥来源">{String(enc.source)}</Descriptions.Item>
            </Descriptions>
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <Card title="JWT" size="small">
            <Descriptions column={1} size="small">
              <Descriptions.Item label="Access Token 过期">{String(jwt.accessExpires)}</Descriptions.Item>
              <Descriptions.Item label="Refresh Token 过期">{String(jwt.refreshExpires)}</Descriptions.Item>
            </Descriptions>
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <Card title="服务" size="small">
            <Descriptions column={1} size="small">
              <Descriptions.Item label="端口">{String(svc.port)}</Descriptions.Item>
              <Descriptions.Item label="监听地址">{String(svc.host)}</Descriptions.Item>
              <Descriptions.Item label="Body 限制">{String(svc.bodyLimit)}</Descriptions.Item>
              <Descriptions.Item label="CORS 来源">{String(svc.corsOrigin)}</Descriptions.Item>
            </Descriptions>
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <Card title="存储" size="small">
            <Descriptions column={1} size="small">
              <Descriptions.Item label="存储目录">{String(stor.dir ?? '未设置')}</Descriptions.Item>
            </Descriptions>
          </Card>
        </Col>
        <Col xs={24} lg={12}>
          <Card title="Kopia" size="small">
            <Descriptions column={1} size="small">
              <Descriptions.Item label="可执行路径">{String(kopia.exePath)}</Descriptions.Item>
              <Descriptions.Item label="超时">{String(kopia.timeoutMs)}ms</Descriptions.Item>
            </Descriptions>
          </Card>
        </Col>
      </Row>
    </PageContainer>
  );
}
