import { Card, Col, Row, Tag, Empty } from 'antd';
import { WarningOutlined, SyncOutlined, MailOutlined, ToolOutlined, SendOutlined } from '@ant-design/icons';
import { PageContainer } from '@ant-design/pro-components';
import { useEffect, useState } from 'react';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord } from '../types';
import { asArray, asRecord, displayValue } from '../utils/format';

const alertSections = [
  { key: 'trackingFailures', title: '追踪采集失败', icon: <WarningOutlined />, color: 'orange' },
  { key: 'syncFailures', title: '同步写入失败', icon: <SyncOutlined />, color: 'red' },
  { key: 'outlookFailures', title: 'Outlook 同步失败', icon: <MailOutlined />, color: 'blue' },
  { key: 'jobFailures', title: '后台任务失败', icon: <ToolOutlined />, color: 'purple' },
  { key: 'pushFailures', title: '推送失败', icon: <SendOutlined />, color: 'volcano' },
];

export function AlertsPage(props: { api: AdminApiClient; onDataRefresh: () => void }) {
  const [data, setData] = useState<ApiRecord | null>(null);
  const [loading, setLoading] = useState(false);

  const load = async () => {
    setLoading(true);
    try {
      const result = await props.api.request<ApiRecord>('/api/admin/alerts');
      setData(result);
      props.onDataRefresh();
    } finally { setLoading(false); }
  };

  useEffect(() => { void load(); }, []);

  const totalIssues = data
    ? alertSections.reduce((sum, s) => sum + asArray((data as ApiRecord)[s.key]).length, 0)
    : 0;

  return (
    <PageContainer
      title={`异常告警${totalIssues > 0 ? ` (${totalIssues})` : ''}`}
      content="查看所有模块的失败记录和错误信息。推送通知暂缓。"
      loading={loading}
    >
      <Row gutter={[16, 16]}>
        {alertSections.map((section) => {
          const items = asArray((data as ApiRecord)?.[section.key]).map(asRecord);
          return (
            <Col xs={24} lg={12} key={section.key}>
              <Card
                title={<span>{section.icon} {section.title}</span>}
                extra={<Tag color={items.length > 0 ? section.color : 'green'}>{items.length}</Tag>}
                size="small"
              >
                {items.length === 0 ? (
                  <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="无异常" />
                ) : (
                  items.map((item, idx) => (
                    <Card.Grid key={idx} style={{ width: '100%' }} hoverable={false}>
                      <div style={{ fontSize: 13 }}>
                        <span style={{ color: '#888' }}>{displayValue(item.updatedAt ?? item.createdAt ?? item.finishedAt ?? item.lastFinishedAt, '未知时间')}</span>
                        <Tag color="red" style={{ marginLeft: 8 }}>{displayValue(item.status ?? item.result, 'unknown')}</Tag>
                        <div style={{ color: '#cf1322', marginTop: 4, wordBreak: 'break-all' }}>
                          {displayValue(item.errorMessage ?? item.lastError, '无详情')}
                        </div>
                      </div>
                    </Card.Grid>
                  ))
                )}
              </Card>
            </Col>
          );
        })}
      </Row>
    </PageContainer>
  );
}
