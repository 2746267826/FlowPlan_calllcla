import { Button, Card, Empty, Space, Tag, Typography } from 'antd';
import type { ApiRecord, AuditEntry } from '../types';
import { auditActionLabel, displayValue, formatDate } from '../utils/format';
import { JsonBlock } from './JsonBlock';

export function AuditList({ rows, onOpen }: { rows: ApiRecord[]; onOpen?: (row: ApiRecord) => void }) {
  if (!rows.length) return <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="当前没有可显示的数据操作审计记录" />;
  return (
    <Space direction="vertical" size={12} className="full-width">
      {rows.map((row, index) => {
        const entry = row as AuditEntry;
        const metadata = entry.metadata ?? entry.metadataJson ?? row.payload;
        return (
          <Card
            size="small"
            key={displayValue(entry.id ?? index)}
            title={displayValue(entry.summary ?? auditActionLabel(entry.action) ?? '数据操作')}
            extra={
              onOpen ? (
                <Button size="small" onClick={() => onOpen(row)}>
                  详情
                </Button>
              ) : null
            }
          >
            <Space wrap size={[6, 6]}>
              <Tag>{formatDate(entry.occurredAt ?? entry.createdAt)}</Tag>
              <Tag>操作者：{displayValue(entry.actor ?? row.createdBy ?? 'admin')}</Tag>
              <Tag color="blue">动作：{auditActionLabel(entry.action)}</Tag>
              <Tag>类型：{displayValue(entry.entityType ?? entry.targetType ?? row.objectType ?? '对象')}</Tag>
              {entry.entityId || entry.targetId ? <Tag>ID：{displayValue(entry.entityId ?? entry.targetId)}</Tag> : null}
            </Space>
            <Typography.Paragraph type="secondary" className="audit-note">
              摘要优先展示；变更前后和原始记录只在需要核查时展开。
            </Typography.Paragraph>
            <div className="json-grid">
              <JsonBlock title="变更前" value={entry.beforeJson ?? row.before_json} />
              <JsonBlock title="变更后" value={entry.afterJson ?? row.after_json} />
              <JsonBlock title="附加信息" value={metadata} />
              <JsonBlock title="原始记录" value={row} />
            </div>
          </Card>
        );
      })}
    </Space>
  );
}
