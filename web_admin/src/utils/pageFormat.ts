export {
  asArray,
  asRecord,
  displayValue,
  formatDate,
  statusLabel,
  statusColor,
  sourceLabel,
  extractRows,
  getNestedValue,
  toCount,
} from './format';

import type { ApiRecord } from '../types';
import { asRecord, displayValue, shortJson } from './format';

export function flattenHealth(health: ApiRecord | null): ApiRecord[] {
  const record = asRecord(health);
  const labels: Record<string, string> = {
    database: '数据库',
    api: 'API',
    storage: '对象存储',
    kopia: 'Kopia',
    sync: '同步积压',
    jobs: '后台任务',
  };
  const rows = Object.keys(labels).map((key) => {
    const value = asRecord(record[key]);
    return {
      key,
      label: labels[key],
      value: value.status ?? value.ok ?? value.available ?? record[key] ?? 'unknown',
      detail: displayValue(value.message ?? value.error ?? value.path ?? ''),
    };
  });
  if (rows.every((row) => row.value === 'unknown')) {
    return Object.entries(record).slice(0, 8).map(([key, value]) => ({
      key,
      label: key,
      value: typeof value === 'object' ? shortJson(value) : value,
    }));
  }
  return rows;
}
