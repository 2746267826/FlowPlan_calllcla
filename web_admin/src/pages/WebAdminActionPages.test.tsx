import { Modal, message } from 'antd';
import type { ReactNode } from 'react';
import { fireEvent, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { createMockAdminApi } from '../test/mockAdminApi';
import { renderWithProviders } from '../test/render';
import { AlertsPage } from './AlertsPage';
import { JobsPage } from './JobsPage';
import { LogsPage } from './LogsPage';
import { OperationsPage } from './OperationsPage';
import { OutlookPage } from './OutlookPage';
import { SchedulePage } from './SchedulePage';
import { EnvPage } from './EnvPage';

async function confirmPopconfirm() {
  await waitFor(() => {
    expect(
      document.querySelector('.ant-popconfirm-buttons .ant-btn-primary'),
    ).toBeTruthy();
  });
  const buttons = document.querySelectorAll(
    '.ant-popconfirm-buttons .ant-btn-primary',
  );
  fireEvent.click(buttons[buttons.length - 1] as HTMLElement);
}

describe('OutlookPage', () => {
  it('loads integration data and runs auth, sync, reset, and refresh controls', async () => {
    const api = createMockAdminApi({
      outlookStatus: vi.fn().mockResolvedValue({
        connected: true,
        accountEmail: 'admin@example.com',
        clientIdConfigured: true,
        readOnly: true,
        scope: 'Calendars.Read',
      }),
      outlookCalendars: vi.fn().mockResolvedValue({
        calendars: [
          { id: 'calendar-1', name: 'Work', enabled: true, color: 'blue' },
          {
            calendarId: 'calendar-2',
            calendarName: 'Personal',
            selected: true,
            hexColor: '#ff9900',
          },
        ],
      }),
      outlookRuns: vi.fn().mockResolvedValue({
        runs: [
          {
            id: 'run-1',
            createdAt: '2026-06-08T08:00:00.000Z',
            status: 'success',
            scope: 'Calendars.Read',
            summary: 'Synced',
          },
          {
            id: 'run-2',
            startedAt: '2026-06-08T09:00:00.000Z',
            status: 'failed',
            mode: 'calendar pull',
            message: 'Retry later',
          },
          {
            id: 'run-3',
            status: 'failed',
            error: 'Token expired',
          },
        ],
      }),
      outlookDiagnostics: vi.fn().mockResolvedValue({ ok: true }),
      startOutlookAuth: vi
        .fn()
        .mockResolvedValue({ authorizeUrl: 'https://login.example.test/auth' }),
      completeOutlookAuth: vi.fn().mockResolvedValue({ ok: true }),
      syncOutlook: vi.fn().mockResolvedValue({ ok: true }),
      resetOutlook: vi.fn().mockResolvedValue({ ok: true }),
    });
    vi.spyOn(Modal, 'info').mockImplementation(
      () => ({ destroy: vi.fn(), update: vi.fn() }) as never,
    );
    vi.spyOn(Modal, 'confirm').mockImplementation((config) => {
      void config.onOk?.();
      return { destroy: vi.fn(), update: vi.fn() } as never;
    });

    renderWithProviders(
      <OutlookPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('admin@example.com')).toBeInTheDocument();
    expect(screen.getByText('Work')).toBeInTheDocument();
    expect(screen.getByText('Personal')).toBeInTheDocument();

    await userEvent.type(
      screen.getByPlaceholderText('输入 Microsoft 应用 Client ID'),
      'client-123',
    );
    await userEvent.click(screen.getByRole('button', { name: '开始授权' }));
    await waitFor(() =>
      expect(api.startOutlookAuth).toHaveBeenCalledWith('client-123'),
    );
    expect(Modal.info).toHaveBeenCalled();

    await userEvent.type(
      screen.getByPlaceholderText('粘贴 Microsoft 回调后的完整 URL'),
      'https://app.example.test/callback?code=ok',
    );
    await userEvent.click(screen.getByRole('button', { name: '完成授权' }));
    await waitFor(() =>
      expect(api.completeOutlookAuth).toHaveBeenCalledWith(
        'https://app.example.test/callback?code=ok',
      ),
    );

    await userEvent.click(screen.getByRole('button', { name: /立即同步/ }));
    await waitFor(() => expect(api.syncOutlook).toHaveBeenCalledTimes(1));

    await userEvent.click(screen.getByRole('button', { name: '重置集成' }));
    await waitFor(() => expect(api.resetOutlook).toHaveBeenCalledTimes(1));

    await userEvent.click(screen.getByRole('button', { name: /刷新/ }));
    await waitFor(() => expect(api.outlookStatus).toHaveBeenCalled());

    await userEvent.click(screen.getAllByRole('tab')[1]);
    expect(await screen.findByText('calendar pull')).toBeInTheDocument();
    expect(screen.getByText('Token expired')).toBeInTheDocument();
  }, 30000);

  it('shows auth errors returned by the server', async () => {
    const api = createMockAdminApi({
      outlookStatus: vi.fn().mockResolvedValue({ connected: false }),
      startOutlookAuth: vi.fn().mockRejectedValue(new Error('invalid client')),
    });
    vi.spyOn(Modal, 'error').mockImplementation(
      () => ({ destroy: vi.fn(), update: vi.fn() }) as never,
    );

    renderWithProviders(
      <OutlookPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    await screen.findByText(/未连接|鏈繛鎺?/);
    await userEvent.type(
      screen.getByPlaceholderText('输入 Microsoft 应用 Client ID'),
      'bad-client',
    );
    await userEvent.click(screen.getByRole('button', { name: '开始授权' }));

    await waitFor(() => expect(Modal.error).toHaveBeenCalled());
    expect(await screen.findByText('invalid client')).toBeInTheDocument();
  });

  it('guards empty auth inputs and keeps partial load failures visible', async () => {
    const api = createMockAdminApi({
      outlookStatus: vi.fn().mockRejectedValue('status offline'),
      outlookCalendars: vi.fn().mockRejectedValue(new Error('calendar offline')),
      outlookRuns: vi.fn().mockRejectedValue(new Error('runs offline')),
      outlookDiagnostics: vi.fn().mockRejectedValue(new Error('diag offline')),
    });
    const warningSpy = vi
      .spyOn(message, 'warning')
      .mockImplementation(() => undefined as never);

    renderWithProviders(
      <OutlookPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('status offline')).toBeInTheDocument();
    await userEvent.type(screen.getByPlaceholderText(/Client ID/), '{enter}');
    await userEvent.type(screen.getByPlaceholderText(/URL/), '{enter}');

    expect(warningSpy).toHaveBeenCalledTimes(2);
    expect(api.startOutlookAuth).not.toHaveBeenCalled();
    expect(api.completeOutlookAuth).not.toHaveBeenCalled();
  });

  it('uses fallback auth URLs, reports completion failures, and renders diagnostics branches', async () => {
    const api = createMockAdminApi({
      outlookStatus: vi.fn().mockResolvedValue({
        connected: false,
        status: 'degraded',
        accountDisplayName: 'Operations mailbox',
        clientIdConfigured: false,
        readOnly: false,
        scope: 'Calendars.ReadWrite',
        encryptionKeySecure: false,
        lastError: 'status stale',
      }),
      outlookDiagnostics: vi.fn().mockResolvedValue({
        transport: 'graph',
        nested: { ok: true },
      }),
      startOutlookAuth: vi.fn().mockResolvedValue({ raw: 'fallback-auth' }),
      completeOutlookAuth: vi.fn().mockRejectedValue('callback rejected'),
    });
    const writeText = vi.fn();
    let authModalContent: ReactNode;
    Object.defineProperty(navigator, 'clipboard', {
      configurable: true,
      value: { writeText },
    });
    vi.spyOn(Modal, 'info').mockImplementation((config) => {
      authModalContent = config.content;
      return { destroy: vi.fn(), update: vi.fn() } as never;
    });
    vi.spyOn(Modal, 'error').mockImplementation(
      () => ({ destroy: vi.fn(), update: vi.fn() }) as never,
    );

    renderWithProviders(
      <OutlookPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('Operations mailbox')).toBeInTheDocument();
    expect(screen.getByText('status stale')).toBeInTheDocument();

    await userEvent.type(
      screen.getByPlaceholderText(/Client ID/),
      ' client-from-form {enter}',
    );

    await waitFor(() =>
      expect(api.startOutlookAuth).toHaveBeenCalledWith('client-from-form'),
    );

    renderWithProviders(<>{authModalContent}</>);
    expect(screen.getByDisplayValue('{"raw":"fallback-auth"}')).toBeInTheDocument();
    const modalButtons = screen.getAllByRole('button');
    await userEvent.click(modalButtons[modalButtons.length - 1]);
    expect(writeText).toHaveBeenCalledWith('{"raw":"fallback-auth"}');

    await userEvent.type(
      screen.getByPlaceholderText(/URL/),
      ' https://app.example.test/callback?code=bad {enter}',
    );


    expect(await screen.findByText('callback rejected')).toBeInTheDocument();
    expect(Modal.error).toHaveBeenCalled();
    await userEvent.click(document.querySelector('.ant-alert-close-icon') as HTMLElement);
    await waitFor(() =>
      expect(screen.queryByText('callback rejected')).not.toBeInTheDocument(),
    );

    await userEvent.click(screen.getAllByRole('tab')[2]);
    expect(await screen.findByText('Calendars.ReadWrite')).toBeInTheDocument();
    expect(screen.getByText(/FLOWPLANV2_ENCRYPTION_KEY/)).toBeInTheDocument();
    await userEvent.click(
      document.querySelector('.raw-collapse .ant-collapse-header') as HTMLElement,
    );
    expect(screen.getByText(/graph/)).toBeInTheDocument();
  }, 30000);
});

describe('OperationsPage', () => {
  it('requires prepare before confirm and executes the confirmed operation', async () => {
    const api = createMockAdminApi({
      prepareOperation: vi.fn().mockResolvedValue({
        confirmationToken: 'confirm-token',
        affectedCount: 2,
      }),
      confirmOperation: vi.fn().mockResolvedValue({ ok: true, done: 2 }),
    });
    vi.spyOn(Modal, 'confirm').mockImplementation((config) => {
      void config.onOk?.();
      return { destroy: vi.fn(), update: vi.fn() } as never;
    });

    renderWithProviders(
      <OperationsPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(screen.getByRole('button', { name: '确认执行' })).toBeDisabled();

    await userEvent.click(screen.getByRole('button', { name: '准备执行' }));
    await waitFor(() =>
      expect(api.prepareOperation).toHaveBeenCalledWith(
        'rebuild-sync-index',
        { reason: 'web_admin operation' },
      ),
    );

    await userEvent.click(screen.getByRole('button', { name: '确认执行' }));
    await waitFor(() =>
      expect(api.confirmOperation).toHaveBeenCalledWith(
        'rebuild-sync-index',
        { reason: 'web_admin operation' },
        'confirm-token',
      ),
    );
  });

  it('shows prepare errors without enabling confirm', async () => {
    const api = createMockAdminApi({
      prepareOperation: vi.fn().mockRejectedValue(new Error('blocked')),
    });

    renderWithProviders(
      <OperationsPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    await userEvent.click(screen.getByRole('button', { name: '准备执行' }));

    expect(await screen.findByText('blocked')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: '确认执行' })).toBeDisabled();
  });
  it('sends edited string payloads and warns when the confirmation token is missing', async () => {
    const api = createMockAdminApi({
      prepareOperation: vi.fn().mockResolvedValue({ affectedCount: 0 }),
      confirmOperation: vi.fn().mockResolvedValue({ ok: true }),
    });
    const warningSpy = vi
      .spyOn(message, 'warning')
      .mockImplementation(() => undefined as never);
    vi.spyOn(Modal, 'confirm').mockImplementation((config) => {
      void config.onOk?.();
      return { destroy: vi.fn(), update: vi.fn() } as never;
    });

    renderWithProviders(
      <OperationsPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    fireEvent.change(screen.getByRole('textbox'), {
      target: { value: '{bad json' },
    });
    await userEvent.click(screen.getAllByRole('button')[0]);

    await waitFor(() =>
      expect(api.prepareOperation).toHaveBeenCalledWith(
        'rebuild-sync-index',
        '{bad json',
      ),
    );

    await userEvent.click(screen.getAllByRole('button')[1]);
    expect(warningSpy).toHaveBeenCalled();
    expect(api.confirmOperation).not.toHaveBeenCalled();
  });

  it('shows non-error prepare failures as text', async () => {
    const api = createMockAdminApi({
      prepareOperation: vi.fn().mockRejectedValue('plain blocked'),
    });

    renderWithProviders(
      <OperationsPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    await userEvent.click(screen.getAllByRole('button')[0]);

    expect(await screen.findByText('plain blocked')).toBeInTheDocument();
  });
});

describe('LogsPage', () => {
  it('loads audit logs and filters by action text', async () => {
    const api = createMockAdminApi({
      adminData: vi.fn().mockResolvedValue({
        items: [
          {
            id: 'log-1',
            actor: 'admin',
            action: 'task.update',
            summary: 'Task updated',
          },
          {
            id: 'log-2',
            actor: 'system',
            action: 'job.run',
            summary: 'Job ran',
          },
        ],
      }),
    });

    renderWithProviders(<LogsPage api={api as never} onDataRefresh={vi.fn()} />);

    expect(await screen.findByText('Task updated')).toBeInTheDocument();
    await userEvent.type(screen.getByPlaceholderText('搜索动作'), 'task');

    expect(screen.getByText('Task updated')).toBeInTheDocument();
    expect(screen.queryByText('Job ran')).not.toBeInTheDocument();
  });
});

describe('AlertsPage', () => {
  it('summarizes failures across alert sections and shows empty sections', async () => {
    const api = createMockAdminApi({
      request: vi.fn().mockResolvedValue({
        trackingFailures: [
          {
            status: 'failed',
            errorMessage: 'Tracker failed',
            updatedAt: '2026-06-08T08:00:00.000Z',
          },
        ],
        syncFailures: [],
        outlookFailures: [],
        jobFailures: [],
        pushFailures: [],
      }),
    });

    renderWithProviders(
      <AlertsPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('Tracker failed')).toBeInTheDocument();
    expect(api.request).toHaveBeenCalledWith('/api/admin/alerts');
    expect(screen.getAllByText(/无异常|鏃犲紓甯?/).length).toBeGreaterThan(0);
  });
  it('renders alert timestamp, status, and error fallbacks', async () => {
    const api = createMockAdminApi({
      request: vi.fn().mockResolvedValue({
        trackingFailures: [
          {
            result: 'retrying',
            lastError: 'Tracker retry pending',
            createdAt: '2026-06-08T09:00:00.000Z',
          },
        ],
        syncFailures: [
          {
            status: 'failed',
            lastError: 'Sync writer failed',
            finishedAt: '2026-06-08T10:00:00.000Z',
          },
        ],
        outlookFailures: [
          {
            result: 'failed',
            errorMessage: 'Outlook pull failed',
            lastFinishedAt: '2026-06-08T11:00:00.000Z',
          },
        ],
        jobFailures: [
          {
            status: 'failed',
          },
        ],
        pushFailures: [],
      }),
    });

    renderWithProviders(
      <AlertsPage api={api as never} onDataRefresh={vi.fn()} />,
    );

    expect(await screen.findByText('Tracker retry pending')).toBeInTheDocument();
    expect(screen.getByText('retrying')).toBeInTheDocument();
    expect(screen.getByText('Sync writer failed')).toBeInTheDocument();
    expect(screen.getByText('Outlook pull failed')).toBeInTheDocument();
  });
});

describe('EnvPage', () => {
  it('loads the service environment snapshot and uploads pasted env content', async () => {
    const request = vi.fn().mockImplementation((path: string) => {
      if (path === '/api/admin/env/upload') {
        return Promise.resolve({ message: 'env uploaded' });
      }
      return Promise.resolve({
        generatedAt: '2026-06-08T08:00:00.000Z',
        database: { urlPresent: true, poolMax: 20, slowQueryThresholdMs: 500 },
        encryption: { keySecure: true, source: 'env' },
        jwt: { accessExpires: '15m', refreshExpires: '7d' },
        service: { port: 3202, host: '127.0.0.1', bodyLimit: '2mb', corsOrigin: '*' },
        storage: { dir: 'C:\\FlowPlanStorage' },
        kopia: { exePath: 'kopia.exe', timeoutMs: 30000 },
      });
    });
    const api = createMockAdminApi({ request });

    renderWithProviders(<EnvPage api={api as never} onDataRefresh={vi.fn()} />);

    expect(await screen.findByText('3202')).toBeInTheDocument();
    expect(screen.getByText('15m')).toBeInTheDocument();

    await userEvent.type(
      screen.getByPlaceholderText('粘贴 .env 文件内容...'),
      'DATABASE_URL=postgres://example',
    );
    await userEvent.click(screen.getByRole('button', { name: /upload env content/i }));

    await waitFor(() =>
      expect(request).toHaveBeenCalledWith('/api/admin/env/upload', {
        method: 'POST',
        body: JSON.stringify({ content: 'DATABASE_URL=postgres://example' }),
      }),
    );
  });

  it('does not submit an empty env upload', async () => {
    const request = vi.fn().mockResolvedValue({
      generatedAt: '2026-06-08T08:00:00.000Z',
      database: {},
      encryption: {},
      jwt: {},
      service: {},
      storage: {},
      kopia: {},
    });
    const api = createMockAdminApi({ request });

    renderWithProviders(<EnvPage api={api as never} onDataRefresh={vi.fn()} />);

    await waitFor(() => expect(request).toHaveBeenCalledWith('/api/admin/env'));
    await userEvent.click(
      await screen.findByRole('button', { name: /upload env content/i }),
    );

    expect(request).toHaveBeenCalledTimes(1);
    expect(request).not.toHaveBeenCalledWith(
      '/api/admin/env/upload',
      expect.anything(),
    );
  });
});

describe('JobsPage', () => {
  it('refreshes jobs and confirms trigger, pause, and resume actions', async () => {
    const request = vi.fn().mockImplementation((path: string) => {
      if (path.includes('/trigger') || path.includes('/pause') || path.includes('/resume')) {
        return Promise.resolve({ ok: true });
      }
      return Promise.resolve({
        jobs: [
          {
            name: 'auto-generate-reports',
            status: 'idle',
            cron: '0 * * * *',
            description: 'Generate reports',
          },
        ],
      });
    });
    const api = createMockAdminApi({ request });

    renderWithProviders(<JobsPage api={api as never} onDataRefresh={vi.fn()} />);

    expect(await screen.findByText('Generate reports')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /刷新/ }));
    await waitFor(() => expect(request).toHaveBeenCalledWith('/api/admin/jobs'));

    await userEvent.click(
      screen.getByRole('button', { name: /trigger job auto-generate-reports/i }),
    );
    await confirmPopconfirm();
    await waitFor(() =>
      expect(request).toHaveBeenCalledWith(
        '/api/admin/jobs/auto-generate-reports/trigger',
        { method: 'POST' },
      ),
    );

    await userEvent.click(
      screen.getByRole('button', { name: /pause job auto-generate-reports/i }),
    );
    await confirmPopconfirm();
    await waitFor(() =>
      expect(request).toHaveBeenCalledWith(
        '/api/admin/jobs/auto-generate-reports/pause',
        { method: 'POST' },
      ),
    );

    await userEvent.click(
      screen.getByRole('button', { name: /resume job auto-generate-reports/i }),
    );
    await confirmPopconfirm();
    await waitFor(() =>
      expect(request).toHaveBeenCalledWith(
        '/api/admin/jobs/auto-generate-reports/resume',
        { method: 'POST' },
      ),
    );
  }, 30000);

  it('disables pause while a job is running and shows the latest error', async () => {
    const request = vi.fn().mockResolvedValue({
      jobs: [
        {
          name: 'running-job',
          status: 'running',
          running: true,
          cron: '* * * * *',
          description: 'Currently running',
        },
        {
          name: 'failed-job',
          status: 'failed',
          cron: '0 * * * *',
          description: 'Recently failed',
          lastError: 'queue crashed',
        },
      ],
    });
    const api = createMockAdminApi({ request });

    renderWithProviders(<JobsPage api={api as never} onDataRefresh={vi.fn()} />);

    expect(await screen.findByText('Currently running')).toBeInTheDocument();
    expect(screen.getByText('queue crashed')).toBeInTheDocument();
    expect(
      screen.getByRole('button', { name: /pause job running-job/i }),
    ).toBeDisabled();
  });
});

describe('SchedulePage', () => {
  it('runs topology sorting, genetic scheduling, and a registered job trigger', async () => {
    const api = createMockAdminApi({
      topoSort: vi.fn().mockResolvedValue({
        sorted: ['A', 'B'],
        hasCycle: false,
        layers: [['A'], ['B']],
      }),
      geneticEvolve: vi.fn().mockResolvedValue({
        best: {
          fitness: 0.98,
          genes: [
            {
              taskId: 't1',
              start: '2026-01-01T09:00:00Z',
              end: '2026-01-01T10:00:00Z',
              order: 1,
            },
          ],
        },
      }),
      listJobs: vi.fn().mockResolvedValue({
        jobs: [
          {
            name: 'refresh-materialized-views',
            status: 'idle',
            description: 'Refresh materialized views',
            cron: '* * * * *',
          },
        ],
      }),
      triggerJob: vi.fn().mockResolvedValue({ ok: true }),
    });

    renderWithProviders(
      <SchedulePage api={api as never} onDataRefresh={vi.fn()} />,
    );

    await userEvent.click(screen.getByRole('button', { name: /拓扑排序/ }));
    await waitFor(() => expect(api.topoSort).toHaveBeenCalled());
    expect(await screen.findByText(/A → B/)).toBeInTheDocument();

    await userEvent.click(screen.getByRole('tab', { name: /遗传算法调度/ }));
    await userEvent.click(screen.getByRole('button', { name: /进化/ }));
    await waitFor(() => expect(api.geneticEvolve).toHaveBeenCalled());
    expect(await screen.findByText('t1')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('tab', { name: /定时任务/ }));
    expect(await screen.findByText('Refresh materialized views')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /触发/ }));
    await confirmPopconfirm();

    await waitFor(() =>
      expect(api.triggerJob).toHaveBeenCalledWith('refresh-materialized-views'),
    );
  });

  it('reports topology and genetic errors while rendering dependency cycles', async () => {
    const api = createMockAdminApi({
      topoSort: vi
        .fn()
        .mockRejectedValueOnce('topology service offline')
        .mockResolvedValueOnce({
          sorted: ['A', 'B'],
          hasCycle: true,
          layers: [['A'], ['B']],
          cycles: [['A', 'B', 'A']],
        }),
      geneticEvolve: vi
        .fn()
        .mockRejectedValueOnce(new Error('genetic failed'))
        .mockRejectedValueOnce('genetic offline'),
      listJobs: vi.fn().mockResolvedValue({ jobs: [] }),
    });

    renderWithProviders(
      <SchedulePage api={api as never} onDataRefresh={vi.fn()} />,
    );

    fireEvent.change(screen.getByRole('textbox'), {
      target: { value: '{bad json' },
    });
    await userEvent.click(screen.getByRole('button'));
    expect(api.topoSort).not.toHaveBeenCalled();

    fireEvent.change(screen.getByRole('textbox'), {
      target: {
        value: '[{"id":"A","dependsOn":["B"]},{"id":"B","dependsOn":["A"]}]',
      },
    });
    await userEvent.click(screen.getByRole('button'));
    await waitFor(() => expect(api.topoSort).toHaveBeenCalledTimes(1));

    await userEvent.click(screen.getByRole('button'));
    await waitFor(() => expect(api.topoSort).toHaveBeenCalledTimes(2));
    expect(document.querySelector('.ant-tag-red')).not.toBeNull();

    await userEvent.click(screen.getAllByRole('tab')[1]);
    await userEvent.click(screen.getByRole('button'));
    await waitFor(() => expect(api.geneticEvolve).toHaveBeenCalledTimes(1));
    await userEvent.click(screen.getByRole('button'));
    await waitFor(() => expect(api.geneticEvolve).toHaveBeenCalledTimes(2));
  }, 30000);

  it('renders registered job status colors for running and failed jobs', async () => {
    const api = createMockAdminApi({
      listJobs: vi.fn().mockResolvedValue({
        jobs: [
          {
            name: 'running-job',
            status: 'running',
            description: 'Running schedule worker',
            cron: '* * * * *',
          },
          {
            name: 'failed-job',
            status: 'failed',
            description: 'Failed schedule worker',
            cron: '0 * * * *',
          },
        ],
      }),
    });

    renderWithProviders(
      <SchedulePage api={api as never} onDataRefresh={vi.fn()} />,
    );

    await userEvent.click(screen.getAllByRole('tab')[2]);

    expect(await screen.findByText('Running schedule worker')).toBeInTheDocument();
    expect(screen.getByText('Failed schedule worker')).toBeInTheDocument();
  });
});
