import type { DatasetDefinition, ModuleKey } from '../types';

export const defaultApiBase = 'http://localhost:3202';
export const defaultUserId = '00000000-0000-4000-8000-000000000001';

export const modules: Array<{ key: ModuleKey; label: string; description: string }> = [
  { key: 'dashboard', label: '总览', description: '健康、风险、待处理事项和最近审计。' },
  { key: 'tasks', label: '全部任务与日程', description: '集中管理任务、日程、来源、状态和批量操作。' },
  { key: 'actuals', label: '实际记录', description: '查看和修正用户确认后的实际活动记录。' },
  { key: 'files', label: '文件资料', description: '管理文件、文件夹、传输和文件操作记录。' },
  { key: 'reports', label: '报告推送', description: '管理报告、日记、推送结果和失败重试线索。' },
  { key: 'sync', label: '同步与设备', description: '查看设备在线、冲突、失败写入和同步风险。' },
  { key: 'outlook', label: 'Outlook 集成', description: '管理 Outlook 授权、只读同步、日历映射和诊断。' },
  { key: 'audit', label: '数据操作审计', description: '按人类可读摘要查看关键数据操作和变更详情。' },
  { key: 'settings', label: '系统设置', description: '服务端连接、设备筛选和远程配置。' },
  { key: 'operations', label: '运维操作', description: '执行需要 prepare/confirm 的受控管理动作。' },
];

export const datasets: Record<string, DatasetDefinition> = {
  tasks: { domain: 'tasks', title: '任务', description: '任务事实对象、状态、截止时间、所属任务本和同步状态。' },
  schedules: { domain: 'schedules', title: '日程', description: '日程、时间块、Outlook 只读事件和本地事件。' },
  actuals: { domain: 'actuals', title: '实际记录', description: '用户确认后的活动投入、来源、时段和置信度。' },
  files: { domain: 'files', title: '文件资料', description: '服务端文件夹、文件条目和最近使用状态。' },
  reports: { domain: 'reports', title: '报告', description: '报告、日记、生成状态和证据来源。' },
  pushDeliveries: { domain: 'push-deliveries', title: '推送记录', description: '推送渠道、目标、状态和错误原因。' },
  devices: { domain: 'devices', title: '设备', description: '客户端设备、平台、心跳、同步积压和冲突。' },
  conflicts: { domain: 'conflicts', title: '同步冲突', description: '需要人工判断的多端写入冲突。' },
  syncMutations: { domain: 'sync-mutations', title: '失败写入', description: '客户端离线写入、重试和失败原因。' },
  auditLogs: { domain: 'audit-logs', title: '审计记录', description: '关键管理动作和数据变更记录。' },
  settings: { domain: 'settings', title: '远程设置', description: '服务端同步的配置项和敏感字段。' },
  fileOperationLogs: { domain: 'file-operation-logs', title: '文件操作记录', description: '文件打开、下载、绑定、恢复和冲突处理。' },
};
