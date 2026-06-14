import { describe, expect, it, vi } from 'vitest';
import {
  AdminApiClient,
  buildApiUrl,
  normalizeApiBase,
  TokenExpiredError,
} from './adminApi';

function createClient() {
  return new AdminApiClient({
    apiBase: 'http://server.test/api',
    accessToken: 'access-token',
    deviceId: 'device-1',
  });
}

describe('AdminApiClient', () => {
  it('normalizes API bases before building endpoint URLs', () => {
    expect(normalizeApiBase('   ')).toBe('http://localhost:3202');
    expect(normalizeApiBase('not a url/api/')).toBe('not a url/api');
    expect(normalizeApiBase('http://server.test/v1/api?debug=1#hash')).toBe(
      'http://server.test/v1',
    );
    expect(normalizeApiBase('http://server.test/v1?debug=1#hash')).toBe(
      'http://server.test/v1',
    );
    expect(normalizeApiBase(' http://server.test/api/ ')).toBe(
      'http://server.test',
    );
    expect(normalizeApiBase('/api')).toBe('');
    expect(buildApiUrl('', '/api/health')).toBe('/api/health');
    expect(buildApiUrl('/api', '/api/health')).toBe('/api/health');
    expect(buildApiUrl('http://server.test/api', 'https://other.test/x')).toBe(
      'https://other.test/x',
    );
    expect(buildApiUrl('http://server.test/api', 'api/admin/dashboard')).toBe(
      'http://server.test/api/admin/dashboard',
    );
  });

  it('logs in with default display name, refreshes tokens, and reports unauthenticated request errors', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            accessToken: 'access-1',
            refreshToken: 'refresh-1',
            user: { id: 'admin', displayName: 'FlowPlanV2 Admin' },
          }),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({
            accessToken: 'access-2',
            refreshToken: 'refresh-2',
            user: { id: 'admin', displayName: 'FlowPlanV2 Admin' },
          }),
          { status: 200 },
        ),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ error: 'health blocked' }), {
          status: 503,
          statusText: 'Service Unavailable',
        }),
      );
    vi.stubGlobal('fetch', fetchMock);
    const client = createClient();

    await expect(client.login()).resolves.toMatchObject({
      accessToken: 'access-1',
    });
    await expect(client.refreshToken('refresh-1')).resolves.toMatchObject({
      accessToken: 'access-2',
    });
    await expect(client.health()).rejects.toThrow(
      '503 Service Unavailable: health blocked',
    );

    expect(JSON.parse(fetchMock.mock.calls[0][1].body as string)).toEqual({
      displayName: 'FlowPlanV2 Admin',
    });
    expect(JSON.parse(fetchMock.mock.calls[1][1].body as string)).toEqual({
      refreshToken: 'refresh-1',
    });
  });

  it('sends auth, device, platform, and JSON headers for mutating requests', async () => {
    const fetchMock = vi.fn().mockImplementation(() =>
      Promise.resolve(
        new Response(JSON.stringify({ ok: true }), {
          status: 200,
        }),
      ),
    );
    vi.stubGlobal('fetch', fetchMock);

    await createClient().patchAdminData('tasks', 'task 1', {
      title: 'Plan review',
    });

    const [url, init] = fetchMock.mock.calls[0];
    const headers = new Headers(init.headers);
    expect(url).toBe('http://server.test/api/admin/data/tasks/task%201');
    expect(init.method).toBe('PATCH');
    expect(headers.get('authorization')).toBe('Bearer access-token');
    expect(headers.get('x-flowplanv2-device-id')).toBe('device-1');
    expect(headers.get('x-flowplanv2-platform')).toBe('web-admin');
    expect(headers.get('content-type')).toBe('application/json');
  });

  it('throws token-expired errors before parsing a 401 response body', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response('not json', {
          status: 401,
          statusText: 'Unauthorized',
        }),
      ),
    );

    await expect(createClient().dashboard()).rejects.toBeInstanceOf(
      TokenExpiredError,
    );
  });

  it('includes server error details when a request fails', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ message: ['first', 'second'] }), {
          status: 422,
          statusText: 'Unprocessable Entity',
        }),
      ),
    );

    await expect(createClient().dashboard()).rejects.toThrow(
      /422 Unprocessable Entity: first; second/,
    );
  });

  it('builds query strings only from present admin data filters', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ items: [] }), {
        status: 200,
      }),
    );
    vi.stubGlobal('fetch', fetchMock);

    await createClient().adminData('tasks', {
      limit: 50,
      cursor: '',
      source: 'outlook',
      skip: undefined,
    });

    expect(fetchMock.mock.calls[0][0]).toBe(
      'http://server.test/api/admin/data/tasks?limit=50&source=outlook',
    );
  });

  it('extracts admin rows and maps read endpoint helpers to encoded URLs', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ items: [{ id: 'row-1' }] }), {
          status: 200,
        }),
      )
      .mockImplementation(() =>
        Promise.resolve(
          new Response(JSON.stringify({ ok: true }), {
            status: 200,
          }),
        ),
      );
    vi.stubGlobal('fetch', fetchMock);
    const client = createClient();

    await expect(client.adminRows('tasks')).resolves.toEqual([{ id: 'row-1' }]);
    await client.monitoringHealth();
    await client.syncHealth();
    await client.deviceConnectionHistory('device/one');
    await client.adminDataDetail('tasks', 'task/one');
    await client.scanDriveRoot('root/one');
    await client.deleteDriveRoot('root/one');
    await client.settings();
    await client.patchSetting('setting/one', { value: true });
    await client.outlookStatus();
    await client.outlookCalendars();
    await client.outlookRuns();
    await client.outlookDiagnostics();
    await client.startOutlookAuth('client-1');
    await client.syncOutlook();
    await client.resetOutlook();
    await client.geneticEvolve({ population: 4 });
    await client.geneticPrompts({ promptSet: 'default' });
    await client.topoSort({ nodes: [] });
    await client.validateDependencies({ edges: [] });
    await client.listJobs();
    await client.triggerJob('job/one');

    expect(fetchMock.mock.calls.map((call) => call[0])).toEqual([
      'http://server.test/api/admin/data/tasks',
      'http://server.test/api/admin/monitoring/health',
      'http://server.test/api/admin/sync-health',
      'http://server.test/api/admin/devices/device%2Fone/connection-history',
      'http://server.test/api/admin/data/tasks/task%2Fone',
      'http://server.test/api/files/drive/roots/root%2Fone/scan',
      'http://server.test/api/files/drive/roots/root%2Fone',
      'http://server.test/api/admin/settings',
      'http://server.test/api/admin/settings/setting%2Fone',
      'http://server.test/api/admin/outlook/status',
      'http://server.test/api/admin/outlook/calendars',
      'http://server.test/api/admin/outlook/runs',
      'http://server.test/api/admin/outlook/diagnostics',
      'http://server.test/api/admin/outlook/auth/start',
      'http://server.test/api/admin/outlook/sync',
      'http://server.test/api/admin/outlook/reset',
      'http://server.test/api/scheduler/genetic/evolve',
      'http://server.test/api/scheduler/genetic/prompts',
      'http://server.test/api/scheduler/dependency/topo',
      'http://server.test/api/scheduler/dependency/validate',
      'http://server.test/api/admin/jobs',
      'http://server.test/api/admin/jobs/job/one/trigger',
    ]);
  });

  it('omits the device filter for all devices and includes it for a single device', async () => {
    const fetchMock = vi.fn().mockImplementation(() =>
      Promise.resolve(
        new Response(JSON.stringify({ ok: true }), {
          status: 200,
        }),
      ),
    );
    vi.stubGlobal('fetch', fetchMock);
    const client = createClient();

    await client.deviceOnlineSummary('all');
    await client.deviceOnlineSummary('device 2');

    expect(fetchMock.mock.calls[0][0]).toBe(
      'http://server.test/api/admin/devices/online-summary',
    );
    expect(fetchMock.mock.calls[1][0]).toBe(
      'http://server.test/api/admin/devices/online-summary?deviceId=device+2',
    );
  });

  it('trims drive searches and sends the managed root defaults', async () => {
    const fetchMock = vi.fn().mockImplementation(() =>
      Promise.resolve(
        new Response(JSON.stringify({ ok: true }), {
          status: 200,
        }),
      ),
    );
    vi.stubGlobal('fetch', fetchMock);
    const client = createClient();

    await client.driveRoots('  course docs  ');
    await client.upsertDriveRoot({
      name: 'Course',
      rootUri: 'C:\\Course',
    });

    expect(fetchMock.mock.calls[0][0]).toBe(
      'http://server.test/api/files/drive/roots?q=course+docs',
    );
    expect(JSON.parse(fetchMock.mock.calls[1][1].body as string)).toEqual({
      name: 'Course',
      rootUri: 'C:\\Course',
      providerType: 'server_storage',
      isManaged: true,
      syncPolicy: 'metadata_only',
      metadata: { source: 'web_admin_drive_root' },
    });
  });

  it('omits optional drive query and keeps explicit drive root options', async () => {
    const fetchMock = vi.fn().mockImplementation(() =>
      Promise.resolve(
        new Response(JSON.stringify({ ok: true }), {
          status: 200,
        }),
      ),
    );
    vi.stubGlobal('fetch', fetchMock);
    const client = createClient();

    await client.driveRoots('   ');
    await client.upsertDriveRoot({
      name: 'Managed',
      rootUri: 'D:\\Managed',
      rootDisplayPath: 'Managed files',
      syncPolicy: 'full',
    });

    expect(fetchMock.mock.calls[0][0]).toBe(
      'http://server.test/api/files/drive/roots',
    );
    expect(JSON.parse(fetchMock.mock.calls[1][1].body as string)).toEqual({
      name: 'Managed',
      rootUri: 'D:\\Managed',
      rootDisplayPath: 'Managed files',
      providerType: 'server_storage',
      isManaged: true,
      syncPolicy: 'full',
      metadata: { source: 'web_admin_drive_root' },
    });
  });

  it('posts operation, scheduler, and outlook action payloads to encoded endpoints', async () => {
    const fetchMock = vi.fn().mockImplementation(() =>
      Promise.resolve(
        new Response(null, {
          status: 204,
        }),
      ),
    );
    vi.stubGlobal('fetch', fetchMock);
    const client = createClient();

    await client.prepareOperation('reset/index', { dryRun: true });
    await client.confirmOperation('reset/index', { dryRun: false }, 'token-1');
    await client.completeOutlookAuth('https://app/callback?code=1', {
      expectedState: true,
    });
    await client.geneticFeedback({ rating: 5 });

    expect(fetchMock.mock.calls[0][0]).toBe(
      'http://server.test/api/admin/operations/reset%2Findex/prepare',
    );
    expect(JSON.parse(fetchMock.mock.calls[0][1].body as string)).toEqual({
      payload: { dryRun: true },
      reason: 'web_admin prepare',
    });
    expect(fetchMock.mock.calls[1][0]).toBe(
      'http://server.test/api/admin/operations/reset%2Findex/confirm',
    );
    expect(JSON.parse(fetchMock.mock.calls[1][1].body as string)).toEqual({
      payload: { dryRun: false },
      confirmationToken: 'token-1',
      reason: 'web_admin confirm',
    });
    expect(JSON.parse(fetchMock.mock.calls[2][1].body as string)).toEqual({
      callbackUrl: 'https://app/callback?code=1',
      state: { expectedState: true },
    });
    expect(fetchMock.mock.calls[3][0]).toBe(
      'http://server.test/api/scheduler/genetic/feedback',
    );
  });

  it('parses empty responses and reports text, error, and non-json bodies', async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(new Response(null, { status: 204 }))
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ message: 'plain detail' }), {
          status: 400,
          statusText: 'Bad Request',
        }),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ error: 'error detail' }), {
          status: 500,
          statusText: 'Server Error',
        }),
      )
      .mockResolvedValueOnce(
        new Response('<html>oops</html>', {
          status: 502,
          statusText: 'Bad Gateway',
        }),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ code: 'UNKNOWN' }), {
          status: 500,
          statusText: 'Server Error',
        }),
      )
      .mockResolvedValueOnce(
        new Response('not json success', {
          status: 200,
        }),
      );
    vi.stubGlobal('fetch', fetchMock);
    const client = createClient();

    await expect(client.health()).resolves.toEqual({});
    await expect(client.dashboard()).rejects.toThrow(
      '400 Bad Request: plain detail',
    );
    await expect(client.dashboard()).rejects.toThrow(
      '500 Server Error: error detail',
    );
    await expect(client.dashboard()).rejects.toThrow(
      '502 Bad Gateway: <html>oops</html>',
    );
    await expect(client.dashboard()).rejects.toThrow(
      '500 Server Error: {"code":"UNKNOWN"}',
    );
    await expect(client.dashboard()).rejects.toThrow(
      /not json success/,
    );
  });

  it('reports only the HTTP status when an error response has no detail body', async () => {
    vi.stubGlobal(
      'fetch',
      vi.fn().mockResolvedValue(
        new Response('   ', {
          status: 503,
          statusText: 'Service Unavailable',
        }),
      ),
    );

    await expect(createClient().dashboard()).rejects.toThrow(
      '503 Service Unavailable',
    );
  });
});
