import { http, HttpResponse } from 'msw';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { AdminApiClient, TokenExpiredError } from '../api/adminApi';
import { server } from '../test/msw/server';
import { AdminApp } from './AdminApp';

type ProLayoutExtraGlobal = typeof globalThis & {
  __webAdminProLayoutExtraMenuItems?: Array<{
    path?: string;
    name?: string;
  }>;
};

describe('AdminApp', () => {
  beforeEach(() => {
    localStorage.clear();
    delete (globalThis as ProLayoutExtraGlobal)
      .__webAdminProLayoutExtraMenuItems;
  });

  function useFullAdminAppRoutes() {
    server.use(
      http.get('*/api/admin/data/:domain/:id', ({ params }) =>
        HttpResponse.json({
          item: {
            id: params.id,
            title: `Detail ${String(params.id)}`,
            status: 'open',
          },
          auditTrail: [],
          relatedObjects: {},
        }),
      ),
      http.get('*/api/files/drive/roots', () =>
        HttpResponse.json({
          roots: [
            {
              id: 'root-1',
              name: 'Course files',
              rootUri: 'C:\\FlowPlanDrive\\Documents',
              scanStatus: 'idle',
              nodeCount: 3,
            },
          ],
        }),
      ),
      http.get('*/api/admin/settings', () =>
        HttpResponse.json({
          items: [
            {
              configKey: 'outlook.sync.enabled',
              value: { enabled: true },
              sensitive: false,
            },
          ],
        }),
      ),
      http.patch('*/api/admin/settings/:configKey', () =>
        HttpResponse.json({ ok: true }),
      ),
      http.get('*/api/admin/outlook/status', () =>
        HttpResponse.json({ connected: false, clientIdConfigured: false }),
      ),
      http.get('*/api/admin/outlook/calendars', () =>
        HttpResponse.json({ calendars: [] }),
      ),
      http.get('*/api/admin/outlook/runs', () =>
        HttpResponse.json({ runs: [] }),
      ),
      http.get('*/api/admin/outlook/diagnostics', () =>
        HttpResponse.json({ ok: true }),
      ),
      http.get('*/api/admin/jobs', () =>
        HttpResponse.json({
          jobs: [
            {
              name: 'auto-generate-reports',
              status: 'idle',
              description: 'Generate reports',
              cron: '0 * * * *',
            },
          ],
        }),
      ),
      http.get('*/api/admin/alerts', () =>
        HttpResponse.json({
          trackingFailures: [],
          syncFailures: [],
          outlookFailures: [],
          jobFailures: [],
          pushFailures: [],
        }),
      ),
      http.get('*/api/admin/env', () =>
        HttpResponse.json({
          generatedAt: '2026-06-08T08:00:00.000Z',
          database: {},
          encryption: {},
          jwt: {},
          service: {},
          storage: {},
          kopia: {},
        }),
      ),
    );
  }

  it('auto-authenticates, loads the dashboard, and switches modules from the side nav', async () => {
    useFullAdminAppRoutes();
    render(<AdminApp />);

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
    expect(screen.getByText('FlowPlanV2')).toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: /详\s*情/ }));
    expect(await screen.findByRole('dialog')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: '关闭' }));

    await userEvent.click(screen.getByTestId('nav-tasks'));
    expect(await screen.findByRole('button', { name: 'Plan review' }))
      .toBeInTheDocument();

    for (const moduleKey of [
      'actuals',
      'files',
      'reports',
      'outlook',
      'audit',
      'operations',
      'logs',
      'jobs',
      'schedule',
      'alerts',
      'env',
    ]) {
      await userEvent.click(screen.getByTestId(`nav-${moduleKey}`));
    }

    await userEvent.click(screen.getByTestId('nav-settings'));
    await screen.findByText('outlook.sync.enabled');
    await userEvent.click(
      screen.getByRole('button', { name: /保存连接设置/ }),
    );

    await userEvent.click(screen.getByTestId('nav-sync'));

    expect(await screen.findByText('device-1')).toBeInTheDocument();
  }, 30000);

  it('uses stored refresh tokens before falling back to login', async () => {
    useFullAdminAppRoutes();
    const refreshBodies: unknown[] = [];
    localStorage.setItem('flowplanv2.admin.accessToken', 'stale-access');
    localStorage.setItem('flowplanv2.admin.refreshToken', 'stored-refresh');
    server.use(
      http.post('*/api/auth/refresh', async ({ request }) => {
        refreshBodies.push(await request.json());
        return HttpResponse.json({
          accessToken: 'fresh-access',
          refreshToken: 'fresh-refresh',
          user: { id: 'admin', displayName: 'FlowPlanV2 Admin' },
        });
      }),
    );

    render(<AdminApp />);

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
    expect(refreshBodies).toEqual([{ refreshToken: 'stored-refresh' }]);
    expect(localStorage.getItem('flowplanv2.admin.accessToken')).toBe(
      'fresh-access',
    );
  });

  it('falls back to login when the stored refresh token is rejected on startup', async () => {
    useFullAdminAppRoutes();
    const refreshBodies: unknown[] = [];
    const loginBodies: unknown[] = [];
    localStorage.setItem('flowplanv2.admin.accessToken', 'stale-access');
    localStorage.setItem('flowplanv2.admin.refreshToken', 'expired-refresh');
    server.use(
      http.post('*/api/auth/refresh', async ({ request }) => {
        refreshBodies.push(await request.json());
        return HttpResponse.json(
          { message: 'refresh rejected' },
          { status: 401, statusText: 'Unauthorized' },
        );
      }),
      http.post('*/api/auth/login', async ({ request }) => {
        loginBodies.push(await request.json());
        return HttpResponse.json({
          accessToken: 'recovered-access',
          refreshToken: 'recovered-refresh',
          user: { id: 'admin', displayName: 'FlowPlanV2 Admin' },
        });
      }),
    );

    render(<AdminApp />);

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
    expect(refreshBodies).toEqual([{ refreshToken: 'expired-refresh' }]);
    expect(loginBodies).toEqual([{ displayName: 'FlowPlanV2 Admin' }]);
    expect(localStorage.getItem('flowplanv2.admin.accessToken')).toBe(
      'recovered-access',
    );
  });

  it('starts with defaults when local storage reads fail', async () => {
    useFullAdminAppRoutes();
    vi.spyOn(Storage.prototype, 'getItem').mockImplementation(() => {
      throw new Error('storage blocked');
    });

    render(<AdminApp />);

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
  });

  it('shows login errors, submits the edited display name, and recovers on retry', async () => {
    useFullAdminAppRoutes();
    const loginBodies: unknown[] = [];
    server.use(
      http.post('*/api/auth/login', async ({ request }) => {
        loginBodies.push(await request.json());
        if (loginBodies.length === 1) {
          return HttpResponse.json(
            { message: 'login unavailable' },
            { status: 503, statusText: 'Service Unavailable' },
          );
        }
        return HttpResponse.json({
          accessToken: 'manual-access',
          refreshToken: 'manual-refresh',
          user: { id: 'admin', displayName: 'Manual Admin' },
        });
      }),
    );

    render(<AdminApp />);

    expect(await screen.findByText(/login unavailable/)).toBeInTheDocument();
    await userEvent.clear(screen.getByPlaceholderText('显示名称'));
    await userEvent.type(screen.getByPlaceholderText('显示名称'), 'Manual Admin');
    await userEvent.click(screen.getByRole('button', { name: /登\s*录/ }));

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
    expect(loginBodies).toEqual([
      { displayName: 'FlowPlanV2 Admin' },
      { displayName: 'Manual Admin' },
    ]);
  });

  it('keeps the login form usable when login rejects with a non-error value', async () => {
    useFullAdminAppRoutes();
    vi.spyOn(AdminApiClient.prototype, 'login')
      .mockRejectedValueOnce('login-as-text')
      .mockResolvedValueOnce({
        accessToken: 'manual-access',
        refreshToken: 'manual-refresh',
        user: { id: 'admin', displayName: 'Manual Admin' },
      });

    render(<AdminApp />);

    expect(await screen.findByText('login-as-text')).toBeInTheDocument();
    await userEvent.click(screen.getByPlaceholderText('显示名称'));
    await userEvent.keyboard('{Enter}');

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
  });

  it('recovers the server indicator after a failed health check is refreshed', async () => {
    useFullAdminAppRoutes();
    let healthCalls = 0;
    let refreshCalls = 0;
    localStorage.setItem('flowplanv2.admin.accessToken', 'expired-access');
    localStorage.setItem('flowplanv2.admin.refreshToken', 'stored-refresh');
    server.use(
      http.post('*/api/auth/refresh', () => {
        refreshCalls += 1;
        return HttpResponse.json({
          accessToken: `fresh-access-${refreshCalls}`,
          refreshToken: `fresh-refresh-${refreshCalls}`,
          user: { id: 'admin', displayName: 'FlowPlanV2 Admin' },
        });
      }),
      http.get('*/api/health', () => {
        healthCalls += 1;
        if (healthCalls === 1) {
          return HttpResponse.json(
            { message: 'health unavailable' },
            { status: 503, statusText: 'Service Unavailable' },
          );
        }
        return HttpResponse.json({ service: 'FlowPlanV2', phase: 'test' });
      }),
    );

    render(<AdminApp />);

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
    await waitFor(() => expect(healthCalls).toBe(1));

    await userEvent.click(
      screen.getByRole('button', { name: /health unavailable/ }),
    );

    await waitFor(() => expect(healthCalls).toBeGreaterThanOrEqual(2));
    expect(refreshCalls).toBe(1);
  });

  it('refreshes the token and retries health when the server reports token expiry', async () => {
    useFullAdminAppRoutes();
    const refreshBodies: unknown[] = [];
    const healthSpy = vi.spyOn(AdminApiClient.prototype, 'health')
      .mockRejectedValueOnce(new TokenExpiredError('expired from health'))
      .mockResolvedValueOnce({ service: 'FlowPlanV2', phase: 'retry' });
    server.use(
      http.post('*/api/auth/refresh', async ({ request }) => {
        refreshBodies.push(await request.json());
        return HttpResponse.json({
          accessToken: 'health-refresh-access',
          refreshToken: 'health-refresh-token',
          user: { id: 'admin', displayName: 'FlowPlanV2 Admin' },
        });
      }),
    );

    render(<AdminApp />);

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
    await waitFor(() =>
      expect(refreshBodies).toEqual([{ refreshToken: 'refresh-token' }]),
    );
    await waitFor(() =>
      expect(healthSpy.mock.calls.length).toBeGreaterThanOrEqual(2),
    );
    expect(localStorage.getItem('flowplanv2.admin.accessToken')).toBe(
      'health-refresh-access',
    );
  });

  it('falls back to login when health-triggered token refresh is rejected', async () => {
    useFullAdminAppRoutes();
    const refreshBodies: unknown[] = [];
    const loginBodies: unknown[] = [];
    vi.spyOn(AdminApiClient.prototype, 'health')
      .mockRejectedValueOnce(new TokenExpiredError('expired from health'))
      .mockResolvedValueOnce({ service: 'FlowPlanV2', phase: 'fallback' });
    server.use(
      http.post('*/api/auth/login', async ({ request }) => {
        loginBodies.push(await request.json());
        return HttpResponse.json({
          accessToken: `fallback-access-${loginBodies.length}`,
          refreshToken: `fallback-refresh-${loginBodies.length}`,
          user: { id: 'admin', displayName: 'FlowPlanV2 Admin' },
        });
      }),
      http.post('*/api/auth/refresh', async ({ request }) => {
        refreshBodies.push(await request.json());
        return HttpResponse.json(
          { message: 'refresh rejected' },
          { status: 401, statusText: 'Unauthorized' },
        );
      }),
    );

    render(<AdminApp />);

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
    await waitFor(() => expect(refreshBodies).toHaveLength(1));
    await waitFor(() => expect(loginBodies).toHaveLength(2));
    expect(refreshBodies).toEqual([{ refreshToken: 'fallback-refresh-1' }]);
    expect(localStorage.getItem('flowplanv2.admin.accessToken')).toBe(
      'fallback-access-2',
    );
  });

  it('shows an offline server status when health rejects with a non-error value', async () => {
    useFullAdminAppRoutes();
    vi.spyOn(AdminApiClient.prototype, 'health').mockRejectedValueOnce(
      'offline-as-text',
    );

    render(<AdminApp />);

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
    expect(await screen.findByText(/offline-as-text/)).toBeInTheDocument();
  });

  it('keeps connection settings available when device refresh fails', async () => {
    useFullAdminAppRoutes();
    server.use(
      http.get('*/api/admin/sync-health', () =>
        HttpResponse.json(
          { message: 'sync health unavailable' },
          { status: 503, statusText: 'Service Unavailable' },
        ),
      ),
    );

    render(<AdminApp />);

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
    await userEvent.click(screen.getByTestId('nav-settings'));

    expect(await screen.findByText('outlook.sync.enabled')).toBeInTheDocument();
    expect(screen.queryByText('device-1')).not.toBeInTheDocument();
  });

  it('builds device filter options from id, client device id, and generic id fallbacks', async () => {
    useFullAdminAppRoutes();
    localStorage.setItem(
      'flowplanv2.admin.selectedDeviceId',
      'id-only-device',
    );
    server.use(
      http.get('*/api/admin/sync-health', () =>
        HttpResponse.json({
          devices: [
            {
              id: 'id-only-device',
              name: 'Laptop',
              runtimePlatform: 'win32',
              appVersion: '2.0',
            },
            {
              clientDeviceId: 'client-device',
              platform: 'android',
              appVersion: '3.0',
            },
            {
              uid: 'uid-device',
              name: 'UID Device',
              runtimePlatform: 'ios',
              appVersion: '4.0',
            },
          ],
        }),
      ),
    );

    render(<AdminApp />);

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
    await userEvent.click(screen.getByTestId('nav-settings'));

    expect(await screen.findByText(/Laptop - win32 \/ 2.0/))
      .toBeInTheDocument();
    await userEvent.click(screen.getByRole('combobox'));
    expect(await screen.findByText(/android - android \/ 3.0/))
      .toBeInTheDocument();
    expect(await screen.findByText(/UID Device - ios \/ 4.0/))
      .toBeInTheDocument();
  });

  it('opens detail drawers for rows without ids and keeps row details when loading detail fails', async () => {
    useFullAdminAppRoutes();
    let actualDetailRequests = 0;
    let taskDetailRequests = 0;
    server.use(
      http.get('*/api/admin/data/actuals', () =>
        HttpResponse.json({
          items: [
            {
              title: 'Actual without id',
              status: 'open',
              source: 'manual',
            },
          ],
        }),
      ),
      http.get('*/api/admin/data/actuals/:id', () => {
        actualDetailRequests += 1;
        return HttpResponse.json({ item: {} });
      }),
      http.get('*/api/admin/data/tasks/:id', () => {
        taskDetailRequests += 1;
        return HttpResponse.json(
          { message: 'detail unavailable' },
          { status: 500, statusText: 'Server Error' },
        );
      }),
    );

    render(<AdminApp />);

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();

    await userEvent.click(screen.getByTestId('nav-actuals'));
    expect(await screen.findByText('Actual without id')).toBeInTheDocument();
    const actualRow = screen.getByText('Actual without id').closest('tr');
    expect(actualRow).not.toBeNull();
    await userEvent.click(within(actualRow as HTMLElement).getByRole('button'));

    expect(await screen.findByRole('dialog')).toBeInTheDocument();
    expect(actualDetailRequests).toBe(0);
    await userEvent.click(screen.getByLabelText('关闭'));

    await userEvent.click(screen.getByTestId('nav-tasks'));
    await userEvent.click(
      await screen.findByRole('button', { name: 'Plan review' }),
    );

    const taskDialog = await screen.findByRole('dialog');
    await waitFor(() => expect(taskDetailRequests).toBe(1));
    expect(screen.getAllByText('Plan review').length).toBeGreaterThan(0);
    await userEvent.click(
      within(taskDialog).getByRole('button', { name: '标记任务完成' }),
    );
  }, 30000);

  it('keeps row details when the detail client rejects with a non-error value', async () => {
    useFullAdminAppRoutes();
    const detailSpy = vi
      .spyOn(AdminApiClient.prototype, 'adminDataDetail')
      .mockRejectedValueOnce('detail-as-text');

    render(<AdminApp />);

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
    await userEvent.click(screen.getByTestId('nav-tasks'));
    await userEvent.click(
      await screen.findByRole('button', { name: 'Plan review' }),
    );

    expect(await screen.findByRole('dialog')).toBeInTheDocument();
    await waitFor(() =>
      expect(detailSpy).toHaveBeenCalledWith('tasks', 'task-1'),
    );
    expect(screen.getAllByText('Plan review').length).toBeGreaterThan(0);
  });

  it('handles menu items without paths by falling back to an empty module', async () => {
    useFullAdminAppRoutes();
    (globalThis as ProLayoutExtraGlobal).__webAdminProLayoutExtraMenuItems = [
      { name: 'Missing path module' },
    ];

    render(<AdminApp />);

    expect(await screen.findByText('Updated Plan review')).toBeInTheDocument();
    expect(screen.getByTestId('nav-')).toHaveAttribute(
      'aria-label',
      'Open  page',
    );

    await userEvent.click(screen.getByText('Missing path module'));

    await waitFor(() =>
      expect(screen.queryByText('Updated Plan review')).not.toBeInTheDocument(),
    );
  });
});
