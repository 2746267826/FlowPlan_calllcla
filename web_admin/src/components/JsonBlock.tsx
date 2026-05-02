import { Card, Typography } from 'antd';
import { parseJsonMaybe, prettyJson } from '../utils/format';

export function JsonBlock({ title, value }: { title: string; value: unknown }) {
  if (value === null || value === undefined || value === '') return null;
  return (
    <Card size="small" title={title} className="json-card">
      <Typography.Text copyable>
        <pre className="json-pre compact">{prettyJson(parseJsonMaybe(value))}</pre>
      </Typography.Text>
    </Card>
  );
}
