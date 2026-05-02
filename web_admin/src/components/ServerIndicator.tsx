import { Badge, Button, Tooltip } from 'antd';
import { ReloadOutlined } from '@ant-design/icons';
import type { ApiRecord, ConnectionState } from '../types';
import { displayValue } from '../utils/format';

export function ServerIndicator(props: {
  apiBase: string;
  connection: ConnectionState;
  lastHealthAt: string;
  lastHealthError: string;
  newInfoCount: number;
  serverInfo: ApiRecord | null;
  onRefresh: () => void;
}) {
  const status = props.connection === 'online' ? 'success' : props.connection === 'checking' ? 'processing' : 'error';
  const message =
    props.connection === 'online'
      ? `${displayValue(props.serverInfo?.service ?? '服务端在线')} / ${displayValue(props.serverInfo?.phase ?? 'phase')}`
      : props.connection === 'checking'
        ? '正在检测服务端'
        : `不可达：${props.lastHealthError || '未知错误'}`;
  const infoText = props.newInfoCount > 0 ? `新信息 ${props.newInfoCount}` : '无新信息';
  const meta = [props.apiBase, props.lastHealthAt || null, infoText].filter(Boolean).join('，');

  return (
    <Tooltip title={`${message}；${meta}`}>
      <Button className="server-button" onClick={props.onRefresh}>
        <span className="server-content">
          <span className="server-main-row">
            <Badge status={status} />
            <span className="server-title" title={message}>
              {message}
            </span>
          </span>
          <span className="server-meta-row" title={meta}>
            <span className="server-url">{props.apiBase}</span>
            {props.lastHealthAt ? <span className="server-separator">，{props.lastHealthAt}</span> : null}
            <span className="server-separator">，{infoText}</span>
          </span>
        </span>
        <ReloadOutlined className="server-refresh-icon" />
      </Button>
    </Tooltip>
  );
}
