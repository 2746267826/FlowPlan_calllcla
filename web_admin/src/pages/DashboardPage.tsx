import { Alert, Button, Card, Col, Row, Space } from 'antd';
import { ReloadOutlined } from '@ant-design/icons';
import { PageContainer, ProCard, StatisticCard, ProTable, type ProColumns } from '@ant-design/pro-components';
import { useEffect, useMemo, useState } from 'react';
import { datasets } from '../app/constants';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord } from '../types';
import { asArray, asRecord, displayValue, formatDate } from '../utils/format';
import { flattenHealth } from '../utils/pageFormat';
import { AuditList } from '../components/AuditList';
import { RawDataCollapse } from '../components/RawDataCollapse';
import { StatusTag } from '../components/StatusTag';

export function DashboardPage(props: {
  api: AdminApiClient;
  onDataRefresh: () => void;
  onOpenDetail: (domain: string, row: ApiRecord) => void;
}) {
  const [dashboard, setDashboard] = useState<ApiRecord | null>(null);
  const [health, setHealth] = useState<ApiRecord | null>(null);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    setLoading(true);
    try {
      const [dashboardResult, healthResult] = await Promise.all([props.api.dashboard(), props.api.monitoringHealth()]);
      setDashboard(dashboardResult);
      setHealth(healthResult);
      props.onDataRefresh();
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
  }, []);

  const overview = asRecord(dashboard?.overview);
  const pending = asRecord(dashboard?.pending);
  const recentAuditLogs = asArray(dashboard?.recentAuditLogs).map(asRecord);
  const healthCards = flattenHealth(health);
  const healthColumns = useMemo<ProColumns<ApiRecord>[]>(
    () => [
      { title: '项目', dataIndex: 'label' },
      { title: '状态', dataIndex: 'value', render: (_, row) => <StatusTag value={row.value} /> },
      { title: '详情', dataIndex: 'detail', ellipsis: true, render: (_, row) => displayValue(row.detail) },
    ],
    [],
  );

  return (
    <PageContainer
      title="总览"
      content="健康、风险、待处理事项和最近审计。"
      extra={
        <Button icon={<ReloadOutlined />} onClick={() => void load()}>
          刷新总览
        </Button>
      }
      loading={loading}
    >
      <Space direction="vertical" size={16} className="full-width">
        <StatisticCard.Group>
          <StatisticCard statistic={{ title: '同步冲突', value: Number(pending.conflicts ?? 0), status: 'warning' as const }} />
          <StatisticCard statistic={{ title: 'AI 待审草稿', value: Number(pending.aiDrafts ?? 0) }} />
          <StatisticCard statistic={{ title: '失败推送', value: Number(pending.failedPushes ?? 0), status: 'error' as const }} />
          <StatisticCard statistic={{ title: '失败后台任务', value: Number(pending.failedJobs ?? 0), status: 'error' as const }} />
        </StatisticCard.Group>

        <Row gutter={[16, 16]}>
          <Col xs={24} xl={12}>
            <Card title="服务健康">
              <ProTable<ApiRecord>
                rowKey="key"
                search={false}
                options={false}
                pagination={false}
                columns={healthColumns}
                dataSource={healthCards}
              />
            </Card>
          </Col>
          <Col xs={24} xl={12}>
            <Card title="运行信息">
              <ProCard ghost direction="column" gutter={[0, 12]}>
                <Alert type="info" showIcon message={`生成时间：${formatDate(dashboard?.generatedAt)}`} />
                <RawDataCollapse title="总览计数原始数据" value={overview} />
              </ProCard>
            </Card>
          </Col>
        </Row>

        <Card title="最近审计">
          <AuditList rows={recentAuditLogs} onOpen={(row) => props.onOpenDetail(datasets.auditLogs.domain, row)} />
        </Card>
      </Space>
    </PageContainer>
  );
}
