import { Button, Drawer, Empty, Modal, Space, Tabs, message } from 'antd';
import { datasets } from '../app/constants';
import type { AdminApiClient } from '../api/adminApi';
import type { ApiRecord, DetailState } from '../types';
import { asArray, asRecord, displayValue, pickId, sourceLabel, statusLabel } from '../utils/format';
import { AuditList } from './AuditList';
import { HumanDescriptions } from './HumanDescriptions';
import { RawDataCollapse } from './RawDataCollapse';

export function DetailDrawer(props: {
  api: AdminApiClient;
  detail: DetailState | null;
  onClose: () => void;
  onChanged: () => void;
}) {
  const { detail } = props;
  if (!detail) return null;
  const detailRecord = asRecord(detail.detail);
  const item = asRecord(detailRecord.item ?? detailRecord.business ?? detail.row);
  const auditTrail = asArray(detailRecord.auditTrail ?? detailRecord.auditLogs).map(asRecord);
  const related = asRecord(detailRecord.relatedObjects ?? detailRecord.syncState);
  const domain = detail.dataset?.domain;

  const patchObject = async (body: ApiRecord, success: string) => {
    const id = pickId(detail.row);
    if (!domain || !id) return;
    try {
      await props.api.patchAdminData(domain, String(id), body);
      message.success(success);
      props.onChanged();
    } catch (error) {
      message.error(`操作失败：${error instanceof Error ? error.message : String(error)}`);
    }
  };

  const completeTask = () => {
    void patchObject({ payload: { status: 'COMPLETED', completedAt: new Date().toISOString() }, reason: 'admin complete task in detail' }, '任务已完成');
  };

  const deleteObject = () => {
    Modal.confirm({
      title: '确认删除对象',
      content: `确认删除“${detail.title}”吗？此操作会写入审计日志。`,
      okText: '删除',
      okButtonProps: { danger: true },
      cancelText: '取消',
      onOk: () => patchObject({ deleted: true, reason: 'admin delete from detail drawer' }, '删除操作已提交'),
    });
  };

  return (
    <Drawer
      width={760}
      open
      destroyOnClose
      title={detail.title}
      onClose={props.onClose}
      extra={
        <Space>
          {domain === 'tasks' ? <Button onClick={completeTask}>标记任务完成</Button> : null}
          {domain && ['tasks', 'schedules', 'actuals', 'files'].includes(domain) ? (
            <Button danger onClick={deleteObject}>
              删除对象
            </Button>
          ) : null}
        </Space>
      }
    >
      <Tabs
        items={[
          {
            key: 'business',
            label: '业务详情',
            children: <HumanDescriptions value={humanReadableDetail(item, detail.row, domain)} />,
          },
          {
            key: 'audit',
            label: '最近审计',
            children: auditTrail.length ? (
              <AuditList rows={auditTrail} />
            ) : (
              <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="没有返回与此对象相关的审计记录" />
            ),
          },
          {
            key: 'related',
            label: '关联与同步',
            children: Object.keys(related).length ? (
              <HumanDescriptions value={related} />
            ) : (
              <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="没有关联或同步信息" />
            ),
          },
          {
            key: 'raw',
            label: '原始数据',
            children: <RawDataCollapse title="完整原始数据" value={detail.detail ?? detail.row} />,
          },
        ]}
      />
    </Drawer>
  );
}

export function readableTitle(row: ApiRecord, domain?: string): string {
  const payload = asRecord(row.payload);
  const label = displayValue(row.title ?? row.summary ?? row.name ?? row.displayName ?? payload.title ?? payload.summary ?? payload.name ?? pickId(row));
  const dataset = domain ? Object.values(datasets).find((item) => item.domain === domain) : undefined;
  return `${dataset?.title ?? '详情'} / ${label}`;
}

function humanReadableDetail(item: ApiRecord, fallback: ApiRecord, domain?: string): ApiRecord {
  const payload = asRecord(item.payload ?? fallback.payload);
  const merged = { ...payload, ...fallback, ...item };
  return {
    title: merged.title ?? merged.summary ?? merged.name ?? merged.displayName,
    status: statusLabel(merged.status),
    source: sourceLabel(merged.source),
    startAt: merged.startAt ?? merged.dtstart,
    endAt: merged.endAt ?? merged.dtend,
    dueAt: merged.dueAt ?? merged.due,
    location: merged.location,
    description: merged.description ?? merged.note,
    objectType: merged.objectType ?? domain,
    version: merged.version ?? merged.serverVersion,
    updatedAt: merged.updatedAt,
    id: merged.id ?? merged.uid,
  };
}
