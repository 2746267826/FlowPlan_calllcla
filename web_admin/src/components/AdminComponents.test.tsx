import { Modal, message } from 'antd';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { datasets } from '../app/constants';
import { createMockAdminApi } from '../test/mockAdminApi';
import { renderWithProviders } from '../test/render';
import * as formatUtils from '../utils/format';
import { AuditList } from './AuditList';
import { DetailDrawer, readableTitle } from './DetailDrawer';
import { HumanDescriptions } from './HumanDescriptions';
import { ServerIndicator } from './ServerIndicator';

describe('HumanDescriptions', () => {
  it('renders business fields and hides empty values', () => {
    renderWithProviders(
      <HumanDescriptions
        value={{
          title: 'Quarterly review',
          status: 'open',
          description: '',
          location: null,
        }}
      />,
    );

    expect(screen.getByText('Quarterly review')).toBeInTheDocument();
    expect(screen.getByText('open')).toBeInTheDocument();
    expect(screen.queryByText('description')).not.toBeInTheDocument();
  });

  it('shows the empty state when there is nothing readable', () => {
    renderWithProviders(<HumanDescriptions value={{}} />);

    expect(screen.getByText(/没有可展示|没有可显示|娌℃湁/)).toBeInTheDocument();
  });
});

describe('ServerIndicator', () => {
  it('summarizes online state and refreshes on click', async () => {
    const onRefresh = vi.fn();

    renderWithProviders(
      <ServerIndicator
        apiBase="http://localhost:3202"
        connection="online"
        lastHealthAt="2026-06-08 10:00"
        lastHealthError=""
        newInfoCount={7}
        serverInfo={{ service: 'FlowPlanV2', phase: 'test' }}
        onRefresh={onRefresh}
      />,
    );

    expect(screen.getByText('FlowPlanV2 / test')).toBeInTheDocument();
    expect(screen.getByText('http://localhost:3202')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button'));

    expect(onRefresh).toHaveBeenCalledTimes(1);
  });

  it('shows the offline error reason', () => {
    renderWithProviders(
      <ServerIndicator
        apiBase="http://localhost:3202"
        connection="offline"
        lastHealthAt=""
        lastHealthError="ECONNREFUSED"
        newInfoCount={0}
        serverInfo={null}
        onRefresh={vi.fn()}
      />,
    );

    expect(screen.getByText(/ECONNREFUSED/)).toBeInTheDocument();
  });

  it('shows checking state while omitting an empty health timestamp', () => {
    renderWithProviders(
      <ServerIndicator
        apiBase="http://localhost:3202"
        connection="checking"
        lastHealthAt=""
        lastHealthError=""
        newInfoCount={0}
        serverInfo={null}
        onRefresh={vi.fn()}
      />,
    );

    expect(screen.getByText('正在检测服务端')).toBeInTheDocument();
    expect(screen.getByTitle('http://localhost:3202，无新信息')).toBeInTheDocument();
    expect(screen.queryByText(/2026-06-08/)).not.toBeInTheDocument();
  });

  it('uses fallback text for missing online info and unknown offline errors', () => {
    const { unmount } = renderWithProviders(
      <ServerIndicator
        apiBase="http://localhost:3202"
        connection="online"
        lastHealthAt=""
        lastHealthError=""
        newInfoCount={0}
        serverInfo={null}
        onRefresh={vi.fn()}
      />,
    );

    expect(screen.getByText('服务端在线 / phase')).toBeInTheDocument();
    unmount();

    renderWithProviders(
      <ServerIndicator
        apiBase="http://localhost:3202"
        connection="offline"
        lastHealthAt=""
        lastHealthError=""
        newInfoCount={0}
        serverInfo={null}
        onRefresh={vi.fn()}
      />,
    );

    expect(screen.getByText('不可达：未知错误')).toBeInTheDocument();
  });
});

describe('AuditList', () => {
  it('shows the empty state when there are no audit rows', () => {
    renderWithProviders(<AuditList rows={[]} />);

    expect(screen.getByText('当前没有可显示的数据操作审计记录')).toBeInTheDocument();
  });

  it('renders fallback audit fields and opens a row from the detail action', async () => {
    const row = {
      action: 'custom.action',
      createdAt: '2026-06-08T10:11:12',
      createdBy: 'system-worker',
      targetType: 'task',
      targetId: 'task-99',
      before_json: { status: 'open' },
      after_json: { status: 'done' },
      payload: { reason: 'payload metadata fallback' },
    };
    const onOpen = vi.fn();

    renderWithProviders(<AuditList rows={[row]} onOpen={onOpen} />);

    expect(screen.getAllByText('custom.action').length).toBeGreaterThan(0);
    expect(screen.getByText('2026-06-08 10:11:12')).toBeInTheDocument();
    expect(screen.getByText('操作者：system-worker')).toBeInTheDocument();
    expect(screen.getByText('类型：task')).toBeInTheDocument();
    expect(screen.getByText('ID：task-99')).toBeInTheDocument();
    expect(screen.getAllByText(/payload metadata fallback/).length).toBeGreaterThan(0);

    await userEvent.click(screen.getByRole('button', { name: /详\s*情/ }));

    expect(onOpen).toHaveBeenCalledWith(row);
  });

  it('renders direct audit fields without the optional detail action', () => {
    renderWithProviders(
      <AuditList
        rows={[
          {
            id: 'audit-1',
            summary: 'Manual audit summary',
            action: 'admin.object.update',
            occurredAt: '2026-06-08T09:00:00',
            actor: 'auditor',
            entityType: 'file',
            entityId: 'file-7',
            beforeJson: { name: 'before.txt' },
            afterJson: { name: 'after.txt' },
            metadataJson: { source: 'metadata json fallback' },
          },
        ]}
      />,
    );

    expect(screen.getByText('Manual audit summary')).toBeInTheDocument();
    expect(screen.getByText('操作者：auditor')).toBeInTheDocument();
    expect(screen.getByText('类型：file')).toBeInTheDocument();
    expect(screen.getByText('ID：file-7')).toBeInTheDocument();
    expect(screen.getAllByText(/metadata json fallback/).length).toBeGreaterThan(0);
    expect(screen.queryByRole('button', { name: /详\s*情/ })).not.toBeInTheDocument();
  });

  it('renders admin and object fallbacks when optional audit fields are missing', () => {
    renderWithProviders(
      <AuditList
        rows={[
          {
            occurredAt: 'not-a-date',
            metadata: { source: 'direct metadata fallback' },
          },
          {
            objectType: 'actual',
            metadata: { source: 'object type fallback' },
          },
        ]}
      />,
    );

    expect(screen.getByText('not-a-date')).toBeInTheDocument();
    expect(screen.getAllByText('操作者：admin').length).toBeGreaterThan(1);
    expect(screen.getByText('类型：对象')).toBeInTheDocument();
    expect(screen.getByText('类型：actual')).toBeInTheDocument();
    expect(screen.getAllByText(/direct metadata fallback/).length).toBeGreaterThan(0);
    expect(screen.queryByText(/ID：/)).not.toBeInTheDocument();
  });
  it('shows the default audit title when no summary or action label is available', () => {
    const labelSpy = vi.spyOn(formatUtils, 'auditActionLabel').mockReturnValueOnce(undefined as never).mockReturnValue('missing-action');

    try {
      renderWithProviders(<AuditList rows={[{ actor: 'fallback-auditor' }]} />);

      expect(screen.getByText('数据操作')).toBeInTheDocument();
      expect(screen.getAllByText(/fallback-auditor/).length).toBeGreaterThan(0);
      expect(screen.getAllByText(/missing-action/).length).toBeGreaterThan(0);
    } finally {
      labelSpy.mockRestore();
    }
  });
});

describe('DetailDrawer', () => {
  it('renders nothing when no detail is selected', () => {
    renderWithProviders(<DetailDrawer api={createMockAdminApi() as never} detail={null} onClose={vi.fn()} onChanged={vi.fn()} />);

    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('marks a task complete from the drawer action', async () => {
    const api = createMockAdminApi();
    const onChanged = vi.fn();

    renderWithProviders(
      <DetailDrawer
        api={api as never}
        detail={{
          title: readableTitle({ id: 'task-1', title: 'Plan review' }, 'tasks'),
          dataset: datasets.tasks,
          row: { id: 'task-1', title: 'Plan review', status: 'open' },
          detail: {
            item: { id: 'task-1', title: 'Plan review', status: 'open' },
            auditTrail: [],
            relatedObjects: {},
          },
        }}
        onClose={vi.fn()}
        onChanged={onChanged}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: '标记任务完成' }));

    await waitFor(() =>
      expect(api.patchAdminData).toHaveBeenCalledWith(
        'tasks',
        'task-1',
        expect.objectContaining({
          payload: expect.objectContaining({ status: 'COMPLETED' }),
        }),
      ),
    );
    expect(onChanged).toHaveBeenCalledTimes(1);
  });

  it('confirms destructive deletes before patching the object', async () => {
    const api = createMockAdminApi();
    vi.spyOn(Modal, 'confirm').mockImplementation((config) => {
      void config.onOk?.();
      return { destroy: vi.fn(), update: vi.fn() } as never;
    });

    renderWithProviders(
      <DetailDrawer
        api={api as never}
        detail={{
          title: 'Task / Plan review',
          dataset: datasets.tasks,
          row: { id: 'task-1', title: 'Plan review' },
          detail: { item: { id: 'task-1', title: 'Plan review' } },
        }}
        onClose={vi.fn()}
        onChanged={vi.fn()}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: '删除对象' }));

    await waitFor(() =>
      expect(api.patchAdminData).toHaveBeenCalledWith(
        'tasks',
        'task-1',
        expect.objectContaining({ deleted: true }),
      ),
    );
  });

  it('shows empty drawer tabs and closes from the drawer control', async () => {
    const onClose = vi.fn();

    renderWithProviders(
      <DetailDrawer
        api={createMockAdminApi() as never}
        detail={{
          title: 'Task / Plan review',
          dataset: datasets.tasks,
          row: { id: 'task-1', title: 'Plan review' },
          detail: { item: { id: 'task-1', title: 'Plan review' }, auditTrail: [], relatedObjects: {} },
        }}
        onClose={onClose}
        onChanged={vi.fn()}
      />,
    );

    await userEvent.click(screen.getByRole('tab', { name: '最近审计' }));
    expect(screen.getByText('没有返回与此对象相关的审计记录')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('tab', { name: '关联与同步' }));
    expect(screen.getByText('没有关联或同步信息')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: '关闭' }));

    expect(onClose).toHaveBeenCalledTimes(1);
  });

  it('renders fallback detail fields, audit logs, related sync state, and raw data tabs', async () => {
    renderWithProviders(
      <DetailDrawer
        api={createMockAdminApi() as never}
        detail={{
          title: 'Schedule / Sync review',
          dataset: datasets.schedules,
          row: {
            uid: 'row-schedule-id',
            status: 'CONFIRMED',
            payload: { title: 'Payload title backup' },
          },
          detail: {
            business: {
              summary: 'Business fallback summary',
              source: 'outlook',
              dtstart: '2026-06-10T09:00:00',
              dtend: '2026-06-10T10:00:00',
              due: '2026-06-11T12:00:00',
              location: 'Main office',
              payload: { location: 'Main office' },
              note: 'Business note fallback',
              serverVersion: 'server-v2',
              uid: 'business-uid',
            },
            auditLogs: [
              {
                action: 'admin.object.update',
                createdAt: '2026-06-08T01:02:03',
                createdBy: 'operator',
                targetType: 'schedule',
                targetId: 'business-uid',
                metadataJson: { source: 'auditLogs branch' },
              },
            ],
            syncState: { deviceName: 'Desktop client', syncPendingCount: 2 },
          },
        }}
        onClose={vi.fn()}
        onChanged={vi.fn()}
      />,
    );

    expect(screen.getByText('Business fallback summary')).toBeInTheDocument();
    expect(screen.getByText('Outlook')).toBeInTheDocument();
    expect(screen.getByText('2026-06-10 09:00:00')).toBeInTheDocument();
    expect(screen.getByText('Main office')).toBeInTheDocument();
    expect(screen.getByText('Business note fallback')).toBeInTheDocument();
    expect(screen.getByText('schedules')).toBeInTheDocument();
    expect(screen.getByText('server-v2')).toBeInTheDocument();
    expect(screen.getByText('business-uid')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('tab', { name: '最近审计' }));
    expect(screen.getAllByText(/更新对象|admin\.object\.update/).length).toBeGreaterThan(0);
    expect(screen.getAllByText(/auditLogs branch/).length).toBeGreaterThan(0);

    await userEvent.click(screen.getByRole('tab', { name: '关联与同步' }));
    expect(screen.getByText('Desktop client')).toBeInTheDocument();
    expect(screen.getByText('2')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('tab', { name: '原始数据' }));
    expect(screen.getByText('完整原始数据')).toBeInTheDocument();
  });

  it('falls back to row details and hides patch actions for read-only domains', async () => {
    renderWithProviders(
      <DetailDrawer
        api={createMockAdminApi() as never}
        detail={{
          title: 'Report / Weekly',
          dataset: datasets.reports,
          row: {
            uid: 'report-uid',
            displayName: 'Weekly display report',
            source: 'server',
            serverVersion: 'report-v1',
          },
        }}
        onClose={vi.fn()}
        onChanged={vi.fn()}
      />,
    );

    expect(screen.getByText('Weekly display report')).toBeInTheDocument();
    expect(screen.getByText('report-v1')).toBeInTheDocument();
    expect(screen.getByText('report-uid')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: '标记任务完成' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: '删除对象' })).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('tab', { name: '原始数据' }));

    expect(screen.getByText('完整原始数据')).toBeInTheDocument();
  });

  it('reports patch failures without marking the drawer as changed', async () => {
    const api = createMockAdminApi({
      patchAdminData: vi.fn().mockRejectedValueOnce(new Error('network down')).mockRejectedValueOnce('plain failure'),
    });
    const onChanged = vi.fn();
    const errorSpy = vi.spyOn(message, 'error').mockImplementation(() => undefined as never);

    renderWithProviders(
      <DetailDrawer
        api={api as never}
        detail={{
          title: 'Task / Plan review',
          dataset: datasets.tasks,
          row: { id: 'task-1', title: 'Plan review' },
          detail: { item: { id: 'task-1', title: 'Plan review' } },
        }}
        onClose={vi.fn()}
        onChanged={onChanged}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: '标记任务完成' }));
    await waitFor(() => expect(errorSpy).toHaveBeenCalledWith('操作失败：network down'));

    await userEvent.click(screen.getByRole('button', { name: '标记任务完成' }));
    await waitFor(() => expect(errorSpy).toHaveBeenCalledWith('操作失败：plain failure'));

    expect(onChanged).not.toHaveBeenCalled();
  });

  it('does not patch task actions when the selected row has no id', async () => {
    const api = createMockAdminApi();

    renderWithProviders(
      <DetailDrawer
        api={api as never}
        detail={{
          title: 'Task / Missing id',
          dataset: datasets.tasks,
          row: { title: 'Missing id task' },
          detail: { item: { title: 'Missing id task' } },
        }}
        onClose={vi.fn()}
        onChanged={vi.fn()}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: '标记任务完成' }));

    expect(api.patchAdminData).not.toHaveBeenCalled();
  });

  it('builds readable titles from payload and default dataset fallbacks', () => {
    expect(readableTitle({ name: 'Named task' }, 'tasks')).toMatch(/Named task$/);
    expect(readableTitle({ payload: { summary: 'Payload summary' } }, 'unknown-domain')).toBe('详情 / Payload summary');
    expect(readableTitle({ uid: 'fallback-uid' })).toBe('详情 / fallback-uid');
  });
});
