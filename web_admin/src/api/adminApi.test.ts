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
    expect(normalizeApiBase(' http://server.test/api/ ')).toBe(
      'http://server.test',
    );
    expect(buildApiUrl('http://server.test/api', 'api/admin/dashboard')).toBe(
      'http://server.test/api/admin/dashboard',
    );
  });

  it('sends auth, device, platform, and JSON headers for mutating requests', async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), {
        status: 200,
      }),
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
});
