import { Badge, Button, Card, Descriptions, message, Row, Col, Tag, Popconfirm } from 'antd';
import { PlayCircleOutlined, PauseCircleOutlined, ReloadOutlined, CaretRightOutlined } from '@ant-design/icons';
import { PageContainer, ProCard } from '@ant-design/pro-components';
import { useEffect, useState } from 'react';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord } from '../types';
import { asArray, asRecord } from '../utils/format';

const statusColors: Record<string, string> = { idle: 'green', running: 'blue', failed: 'red' };
const cronLabels: Record<string, string> = {
  'refresh-materialized-views': '物化视图刷新',
  'refresh-weather-cache': '天气缓存清理',
  'clean-tracking-data': '追踪数据清理',
  'purge-sync-mutations': '同步Mutation清理',
  'auto-generate-reports': '自动生成日报',
};

export function JobsPage(props: { api: AdminApiClient; onDataRefresh: () => void }) {
  const [jobs, setJobs] = useState<ApiRecord[]>([]);
  const [loading, setLoading] = useState(false);

  const load = async () => {
    setLoading(true);
    try {
      const result = await props.api.request<ApiRecord>('/api/admin/jobs');
      setJobs(asArray((result as ApiRecord)?.jobs).map(asRecord));
      props.onDataRefresh();
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => { void load(); }, []);

  const action = async (jobName: string, op: 'trigger' | 'pause' | 'resume') => {
    try {
      const res = await props.api.request<ApiRecord>(`/api/admin/jobs/${jobName}/${op}`, { method: 'POST' });
      if (res.ok) message.success(`${op} ${jobName} 成功`);
      else message.error(String(res.error ?? '操作失败'));
      await load();
    } catch (err) {
      message.error(err instanceof Error ? err.message : String(err));
    }
  };

  return (
    <PageContainer
      title="定时任务管理"
      content="管理后台定时任务：查看状态、手动触发、暂停/恢复。"
      extra={<Button icon={<ReloadOutlined />} onClick={load} loading={loading}>刷新</Button>}
    >
      <Row gutter={[16, 16]}>
        {jobs.map((job) => {
          const status = String(job.status ?? 'idle');
          return (
            <Col xs={24} md={12} key={String(job.name)}>
              <Card
                title={cronLabels[String(job.name)] ?? String(job.name)}
                extra={<Tag color={statusColors[status] ?? 'default'}>{status}</Tag>}
                actions={[
                  <Popconfirm key="trigger" title="确认手动触发此任务？" onConfirm={() => action(String(job.name), 'trigger')}>
                    <Button type="link" icon={<CaretRightOutlined />} size="small">触发</Button>
                  </Popconfirm>,
                  job.running
                    ? <Button key="pause" type="link" icon={<PauseCircleOutlined />} size="small" disabled>运行中</Button>
                    : <Popconfirm key="pause" title="确认暂停此任务？" onConfirm={() => action(String(job.name), 'pause')}>
                        <Button type="link" icon={<PauseCircleOutlined />} size="small">暂停</Button>
                      </Popconfirm>,
                  <Popconfirm key="resume" title="确认恢复此任务？" onConfirm={() => action(String(job.name), 'resume')}>
                    <Button type="link" icon={<PlayCircleOutlined />} size="small">恢复</Button>
                  </Popconfirm>,
                ]}
              >
                <Descriptions column={1} size="small">
                  <Descriptions.Item label="Cron">{String(job.cron ?? '')}</Descriptions.Item>
                  <Descriptions.Item label="描述">{String(job.description ?? '')}</Descriptions.Item>
                  <Descriptions.Item label="上次运行">{String(job.lastRun ?? '从未')}</Descriptions.Item>
                  <Descriptions.Item label="下次运行">{String(job.nextRun ?? '未知')}</Descriptions.Item>
                  {Boolean(job.lastError) && (
                    <Descriptions.Item label="错误"><Tag color="red">{String(job.lastError).slice(0, 80)}</Tag></Descriptions.Item>
                  )}
                </Descriptions>
              </Card>
            </Col>
          );
        })}
      </Row>
    </PageContainer>
  );
}
