import { Collapse, Typography } from 'antd';
import { parseJsonMaybe, prettyJson } from '../utils/format';

export function RawDataCollapse({ title = '原始数据', value }: { title?: string; value: unknown }) {
  if (value === null || value === undefined) return null;
  return (
    <Collapse
      ghost
      size="small"
      className="raw-collapse"
      items={[
        {
          key: 'raw',
          label: title,
          children: (
            <Typography.Text copyable>
              <pre className="json-pre">{prettyJson(parseJsonMaybe(value))}</pre>
            </Typography.Text>
          ),
        },
      ]}
    />
  );
}
