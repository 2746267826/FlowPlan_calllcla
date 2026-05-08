import { Button, Card, Col, Input, message, Row, Slider, Space, Table, Tabs, Tag, Popconfirm } from 'antd';
import { PlayCircleOutlined, BranchesOutlined, SettingOutlined } from '@ant-design/icons';
import { PageContainer } from '@ant-design/pro-components';
import { useEffect, useState } from 'react';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord } from '../types';
import { asArray, asRecord, displayValue } from '../utils/format';

export function SchedulePage(props: { api: AdminApiClient; onDataRefresh: () => void }) {
  const [topoResult, setTopoResult] = useState<ApiRecord | null>(null);
  const [geneticResult, setGenResult] = useState<ApiRecord | null>(null);
  const [jobs, setJobs] = useState<ApiRecord[]>([]);
  const [loading, setLoading] = useState(false);

  // Genetic params
  const [popSize, setPopSize] = useState(50);
  const [generations, setGenerations] = useState(100);
  const [mutationRate, setMutationRate] = useState(0.1);

  // Topology JSON input
  const [topoJson, setTopoJson] = useState(
    '[{"id":"A","title":"任务A","estimatedMinutes":60,"dependsOn":[]},{"id":"B","title":"任务B","estimatedMinutes":30,"dependsOn":["A"]}]'
  );

  const loadJobs = async () => {
    try {
      const res = await props.api.listJobs();
      setJobs(asArray((res as ApiRecord)?.jobs).map(asRecord));
    } catch { /* ignore */ }
  };

  useEffect(() => { void loadJobs(); }, []);

  const triggerJob = async (name: string) => {
    await props.api.triggerJob(name);
    message.success(`已触发 ${name}`);
    await loadJobs();
  };

  const runTopo = async () => {
    try {
      const tasks = JSON.parse(topoJson);
      const res = await props.api.topoSort({ tasks });
      setTopoResult(res);
      props.onDataRefresh();
    } catch (err) { message.error(err instanceof Error ? err.message : String(err)); }
  };

  const runGenetic = async () => {
    setLoading(true);
    try {
      const res = await props.api.geneticEvolve({
        tasks: [
          { id: 't1', title: '高优先级', estimatedMinutes: 60, priority: 'high', dependsOn: [] },
          { id: 't2', title: '普通任务', estimatedMinutes: 30, priority: 'normal', dependsOn: [] },
          { id: 't3', title: '紧急任务', estimatedMinutes: 45, priority: 'urgent', dependsOn: ['t1'], dueAt: new Date(Date.now() + 3600000).toISOString() },
        ],
        freeSlots: [
          { start: '2026-01-01T09:00:00Z', end: '2026-01-01T12:00:00Z' },
          { start: '2026-01-01T14:00:00Z', end: '2026-01-01T18:00:00Z' },
        ],
        topoOrder: ['t1', 't3', 't2'],
        config: { populationSize: popSize, generations, mutationRate },
      });
      setGenResult(res);
      props.onDataRefresh();
    } catch (err) { message.error(err instanceof Error ? err.message : String(err)); }
    finally { setLoading(false); }
  };

  const topoLayers = asArray(topoResult?.layers).map(asRecord);
  const topoCycles = asArray(topoResult?.cycles).map((c) => asArray(c));

  return (
    <PageContainer title="排程管理" content="拓扑排序、遗传算法调度、定时任务管理。">
      <Tabs items={[
        {
          key: 'topo', label: <span><BranchesOutlined /> 依赖拓扑排序</span>,
          children: (
            <Row gutter={[16, 16]}>
              <Col span={24}>
                <Card size="small" title="任务依赖 JSON">
                  <Input.TextArea rows={6} value={topoJson} onChange={(e) => setTopoJson(e.target.value)} />
                  <Button type="primary" onClick={runTopo} style={{ marginTop: 8 }}>拓扑排序</Button>
                </Card>
              </Col>
              {topoResult && (
                <Col span={24}>
                  <Card size="small" title="排序结果">
                    <Space direction="vertical">
                      <span><b>已排序:</b> {asArray(topoResult.sorted).join(' → ')}</span>
                      <span><b>有环:</b> {String(topoResult.hasCycle)}</span>
                      {topoLayers.map((layer, i) => (
                        <Tag key={i} color="blue">第{i + 1}层: {asArray(layer).join(', ')}</Tag>
                      ))}
                      {topoCycles.map((cycle, i) => (
                        <Tag key={`c${i}`} color="red">环: {cycle.join(' → ')}</Tag>
                      ))}
                    </Space>
                  </Card>
                </Col>
              )}
            </Row>
          ),
        },
        {
          key: 'genetic', label: <span><PlayCircleOutlined /> 遗传算法调度</span>,
          children: (
            <Row gutter={[16, 16]}>
              <Col span={8}><span>种群大小: {popSize}</span><Slider min={10} max={200} value={popSize} onChange={setPopSize} /></Col>
              <Col span={8}><span>代数: {generations}</span><Slider min={10} max={500} value={generations} onChange={setGenerations} /></Col>
              <Col span={8}><span>变异率: {mutationRate}</span><Slider min={0} max={1} step={0.05} value={mutationRate} onChange={setMutationRate} /></Col>
              <Col span={24}><Button type="primary" icon={<PlayCircleOutlined />} loading={loading} onClick={runGenetic}>进化</Button></Col>
              {geneticResult && (
                <Col span={24}>
                  <Card size="small" title={`最优适应度: ${String(asRecord(geneticResult.best).fitness)}`}>
                    <Table
                      rowKey="taskId"
                      dataSource={asArray((asRecord(geneticResult.best) as ApiRecord).genes).map(asRecord)}
                      columns={[
                        { title: '任务', dataIndex: 'taskId', width: 100 },
                        { title: '开始', dataIndex: 'start', width: 180, render: (v) => String(v).slice(0, 19) },
                        { title: '结束', dataIndex: 'end', width: 180, render: (v) => String(v).slice(0, 19) },
                        { title: '顺序', dataIndex: 'order', width: 60 },
                      ]}
                      pagination={false}
                      size="small"
                    />
                  </Card>
                </Col>
              )}
            </Row>
          ),
        },
        {
          key: 'jobs', label: <span><SettingOutlined /> 定时任务</span>,
          children: (
            <Card size="small" title="已注册任务">
              {jobs.map((job) => (
                <Card.Grid key={String(job.name)} style={{ width: '50%' }}>
                  <Space>
                    <Tag color={job.status === 'running' ? 'blue' : job.status === 'failed' ? 'red' : 'green'}>{String(job.status)}</Tag>
                    <strong>{String(job.description).slice(0, 40)}</strong>
                    <Popconfirm title="确认触发此任务？" onConfirm={() => triggerJob(String(job.name))}>
                      <Button size="small" icon={<PlayCircleOutlined />}>触发</Button>
                    </Popconfirm>
                  </Space>
                  <div style={{ fontSize: 12, color: '#888', marginTop: 4 }}>
                    Cron: {String(job.cron)} | 上次: {String(job.lastRun ?? '从未')}
                  </div>
                </Card.Grid>
              ))}
            </Card>
          ),
        },
      ]} />
    </PageContainer>
  );
}
