import { Tag } from 'antd';
import { statusColor, statusLabel } from '../utils/format';

export function StatusTag({ value }: { value: unknown }) {
  return <Tag color={statusColor(value)}>{statusLabel(value)}</Tag>;
}
