import { Alert, Button, Card, Col, Row, Space } from 'antd';
import { ReloadOutlined } from '@ant-design/icons';
import { PageContainer, ProCard, StatisticCard, ProTable, type ProColumns } from '@ant-design/pro-components';
import { Area, Line } from '@ant-design/charts';
import { useEffect, useMemo, useState } from 'react';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord } from '../types';
import { asArray, asRecord, formatDate } from '../utils/format';
import { flattenHealth } from '../utils/pageFormat';
import { AuditList } from '../components/AuditList';
import { StatusTag } from '../components/StatusTag';

/** Simple mock trend data — in production this would come from a trends API. */
function mockTrendData(days: number, base: number, label: string) {
  return Array.from({ length: days }, (_, i) => ({
    date: new Date(Date.now() - (days - 1 - i) * 86400000).toISOString().slice(0, 10),
    value: Math.max(0, base + Math.round((Math.random() - 0.5) * base * 0.6)),
    type: label,
  }));
}

export function DashboardPage(props: {
  api: AdminApiClient;
  onDataRefresh: () => void;
  onOpenDetail: (domain: string, row: ApiRecord) => void;
}) {
  const [dashboard, setDashboard] = useState<ApiRecord | null>(null);
  const [health, setHealth] = useState<ApiRecord | null>(null);
  const [syncHealth, setSyncHealth] = useState<ApiRecord | null>(null);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    setLoading(true);
    try {
      const [dashboardResult, healthResult, syncResult] = await Promise.all([
        props.api.dashboard(),
        props.api.monitoringHealth(),
        props.api.syncHealth().catch(() => null),
      ]);
      setDashboard(dashboardResult);
      setHealth(healthResult);
      setSyncHealth(syncResult ?? { devices: [] });
      props.onDataRefresh();
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void load(); }, [props.api]);

  const overview = asRecord(dashboard?.overview);
  const pending = asRecord(dashboard?.pending);
  const recentAuditLogs = asArray(dashboard?.recentAuditLogs).map(asRecord);
  const healthCards = flattenHealth(health);

  const healthColumns = useMemo<ProColumns<ApiRecord>[]>(
    () => [
      { title: '项目', dataIndex: 'label' },
      { title: '状态', dataIndex: 'value', render: (_, row) => <StatusTag value={row.value} /> },
      { title: '详情', dataIndex: 'detail', ellipsis: true, render: (_, row) => String(row.detail ?? '') },
    ],
    [],
  );

  const conflictTrend = useMemo(() => mockTrendData(14, Number(pending.conflicts ?? 2), '冲突'), [pending.conflicts]);
  const aiDraftTrend = useMemo(() => mockTrendData(14, Number(pending.aiDrafts ?? 1), 'AI草稿'), [pending.aiDrafts]);

  const syncConfig = {
    data: conflictTrend,
    xField: 'date',
    yField: 'value',
    smooth: true,
    height: 180,
    color: '#fa8c16',
    point: { size: 2 },
  };

  return (
    <PageContainer
      title="总览"
      content="健康、风险、待处理事项、趋势图表和最近审计。"
      extra={
        <Button
          aria-label="Refresh dashboard"
          icon={<ReloadOutlined />}
          onClick={() => void load()}
        >
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
          <Col xs={24} lg={12}>
            <Card title="同步冲突趋势 (14天)" size="small">
              <Area {...syncConfig} />
            </Card>
          </Col>
          <Col xs={24} lg={12}>
            <Card title="AI 草稿趋势 (14天)" size="small">
              <Line
                data={aiDraftTrend}
                xField="date"
                yField="value"
                smooth
                height={180}
                color="#1f6f78"
                point={{ size: 2 }}
              />
            </Card>
          </Col>
        </Row>

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
                <Alert
                  type={syncHealth && asArray((syncHealth as ApiRecord).devices).length > 0 ? 'success' : 'warning'}
                  showIcon
                  message={`在线设备：${asArray((syncHealth as ApiRecord)?.devices).length}`}
                />
                <Alert type="info" showIcon message={`API 文档：/api/docs (Swagger)`} />
              </ProCard>
            </Card>
          </Col>
        </Row>

        <Card title="最近审计">
          <AuditList rows={recentAuditLogs} onOpen={(row) => props.onOpenDetail('auditLogs', row)} />
        </Card>
      </Space>
    </PageContainer>
  );
}
