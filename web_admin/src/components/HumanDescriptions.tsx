import { Descriptions, Empty } from 'antd';
import type { ApiRecord } from '../types';
import { fieldLabel, formatFieldValue } from '../utils/format';

export function HumanDescriptions({ value, columns = 2 }: { value: ApiRecord; columns?: number }) {
  const entries = Object.entries(value).filter(([, item]) => item !== undefined && item !== null && item !== '');
  if (!entries.length) return <Empty image={Empty.PRESENTED_IMAGE_SIMPLE} description="没有可展示的业务字段" />;
  return (
    <Descriptions size="small" bordered column={columns}>
      {entries.map(([key, item]) => (
        <Descriptions.Item key={key} label={fieldLabel(key)}>
          {formatFieldValue(key, item)}
        </Descriptions.Item>
      ))}
    </Descriptions>
  );
}
