import { BadRequestException } from '@nestjs/common';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { decrypt, encrypt, encryptionKey } from '../common/utils';
import { OutlookService } from './outlook.service';

const userId = '00000000-0000-4000-8000-000000000001';
const deviceId = '00000000-0000-4000-8000-000000000101';
const context = { userId, deviceId };

type QueryResult = { rows: any[]; rowCount?: number };

function result(rows: any[] = [], rowCount = rows.length): QueryResult {
  return { rows, rowCount };
}

function makeDatabase(
  handler: (sql: string, params?: unknown[]) => QueryResult | Promise<QueryResult>,
) {
  const query = vi.fn(async (sql: string, params?: unknown[]) => handler(sql, params));
  return {
    query,
    transaction: vi.fn(async (callback: (client: { query: typeof query }) => unknown) =>
      callback({ query }),
    ),
  };
}

function makeService(database: ReturnType<typeof makeDatabase>) {
  const devices = {
    ensureUser: vi.fn(async (id: string) => id),
    ensureDevice: vi.fn(async () => deviceId),
  };
  const graphClient = { createClient: vi.fn() };
  return {
    service: new OutlookService(database as never, devices as never, graphClient as never),
    devices,
    graphClient,
  };
}

function jsonResponse(ok: boolean, body: unknown, status = ok ? 200 : 500) {
  return {
    ok,
    status,
    json: vi.fn(async () => body),
    text: vi.fn(async () => (typeof body === 'string' ? body : JSON.stringify(body))),
  };
}

describe('OutlookService unit coverage', () => {
  const oldEnv = { ...process.env };

  beforeEach(() => {
    process.env = { ...oldEnv, FLOWPLANV2_ENCRYPTION_KEY: 'unit-test-outlook-secret' };
    vi.stubGlobal('fetch', vi.fn());
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
    process.env = oldEnv;
  });

  it('reports read-only OAuth config and disconnected status from database state', async () => {
    const latestRun = {
      id: 'run-1',
      triggerSource: 'admin',
      status: 'succeeded',
      startedAt: new Date('2026-01-01T00:00:00Z'),
      finishedAt: null,
      calendarCount: 2,
      eventUpserts: 3,
      eventDeletes: 0,
      errorMessage: null,
    };
    const database = makeDatabase((sql) => {
      if (sql.includes('FROM outlook_connections')) {
        return result([]);
      }
      if (sql.includes('FROM outlook_calendar_states')) {
        return result([{ count: 0 }]);
      }
      if (sql.includes('FROM outlook_sync_runs')) {
        return result([latestRun]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service, devices } = makeService(database);

    await expect(service.status(context)).resolves.toMatchObject({
      readOnly: true,
      graphHttpMethodsAllowed: ['GET'],
      scope: 'openid profile offline_access User.Read Calendars.Read',
      syncMode: 'server_pull_only',
      connected: false,
      status: 'disconnected',
      clientIdConfigured: false,
      calendars: 0,
      lastRun: latestRun,
    });
    expect(devices.ensureUser).toHaveBeenCalledWith(userId);
  });

  it('uses disconnected status defaults when connection, calendar count, and latest run rows are missing', async () => {
    const database = makeDatabase((sql) => {
      if (sql.includes('FROM outlook_connections')) {
        return result([]);
      }
      if (sql.includes('FROM outlook_calendar_states')) {
        return result([]);
      }
      if (sql.includes('FROM outlook_sync_runs')) {
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(service.status(context)).resolves.toMatchObject({
      connected: false,
      status: 'disconnected',
      accountEmail: null,
      accountDisplayName: null,
      clientIdConfigured: false,
      lastSyncAt: null,
      lastError: null,
      calendars: 0,
      lastRun: null,
    });
  });

  it('starts OAuth with readonly scope, PKCE state, and pending connection rows', async () => {
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);

    const response = await service.startAuth({ clientId: ' client-id ' }, context);

    expect(response).toMatchObject({
      state: expect.any(String),
      redirectUri: 'https://login.microsoftonline.com/common/oauth2/nativeclient',
      scope: 'openid profile offline_access User.Read Calendars.Read',
      readOnly: true,
    });
    expect(response.authorizeUrl).toContain('/oauth2/v2.0/authorize?');
    expect(response.authorizeUrl).toContain('client_id=client-id');
    expect(response.authorizeUrl).toContain('code_challenge_method=S256');
    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO outlook_connections'),
      expect.arrayContaining([
        userId,
        'client-id',
        'https://login.microsoftonline.com/consumers',
        'https://login.microsoftonline.com/common/oauth2/nativeclient',
        'openid profile offline_access User.Read Calendars.Read',
      ]),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO outlook_auth_sessions'),
      expect.arrayContaining([userId, response.state, expect.any(String), 'client-id']),
    );
  });

  it('rejects OAuth start without external client credentials', async () => {
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);

    await expect(service.startAuth({ clientId: '   ' }, context)).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(database.transaction).not.toHaveBeenCalled();
  });

  it('completes OAuth callback without touching real Graph and stores encrypted tokens', async () => {
    const fetchMock = vi.mocked(global.fetch);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse(true, {
          access_token: 'access-token',
          refresh_token: 'refresh-token',
          expires_in: 1800,
        }) as never,
      )
      .mockResolvedValueOnce(
        jsonResponse(true, {
          displayName: 'Outlook User',
          mail: '',
          userPrincipalName: 'user@example.com',
        }) as never,
      );
    const database = makeDatabase((sql) => {
      if (sql.includes('FROM outlook_auth_sessions')) {
        return result([
          {
            state: 'state-1',
            code_verifier: 'verifier-1',
            client_id: 'client-id',
            redirect_uri: 'https://redirect.test/callback',
            scope: 'openid profile offline_access User.Read Calendars.Read',
          },
        ]);
      }
      return result([]);
    });
    const { service } = makeService(database);

    await expect(
      service.completeAuth(
        { callbackUrl: 'https://login.test/callback?code=code-1&state=state-1' },
        context,
      ),
    ).resolves.toMatchObject({
      ok: true,
      readOnly: true,
      accountEmail: 'user@example.com',
      accountDisplayName: 'Outlook User',
    });

    expect(fetchMock).toHaveBeenNthCalledWith(
      1,
      'https://login.microsoftonline.com/consumers/oauth2/v2.0/token',
      expect.objectContaining({ method: 'POST' }),
    );
    expect(fetchMock).toHaveBeenNthCalledWith(
      2,
      'https://graph.microsoft.com/v1.0/me?$select=displayName,mail,userPrincipalName',
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({ Authorization: 'Bearer access-token' }),
      }),
    );
    const updateConnection = database.query.mock.calls.find(([sql]) =>
      String(sql).includes('UPDATE outlook_connections'),
    );
    expect(updateConnection?.[1]).toEqual(
      expect.arrayContaining([
        userId,
        'client-id',
        expect.not.stringMatching('refresh-token'),
        expect.not.stringMatching('access-token'),
        expect.any(Date),
        'user@example.com',
        'Outlook User',
      ]),
    );
  });

  it('rejects OAuth callback when token response omits refresh token', async () => {
    vi.mocked(global.fetch).mockResolvedValueOnce(
      jsonResponse(true, { access_token: 'access-token' }) as never,
    );
    const database = makeDatabase((sql) => {
      if (sql.includes('FROM outlook_auth_sessions')) {
        return result([
          {
            state: 'state-1',
            code_verifier: 'verifier-1',
            client_id: 'client-id',
            redirect_uri: 'https://redirect.test/callback',
            scope: 'openid profile offline_access User.Read Calendars.Read',
          },
        ]);
      }
      return result([]);
    });
    const { service } = makeService(database);

    await expect(
      service.completeAuth({ code: 'code-1', state: 'state-1' }, context),
    ).rejects.toThrow('refresh token');
  });

  it('defaults OAuth access token expiry to one hour when expires_in is omitted', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-02-01T00:00:00.000Z'));
    const fetchMock = vi.mocked(global.fetch);
    fetchMock
      .mockResolvedValueOnce(
        jsonResponse(true, {
          access_token: 'access-token',
          refresh_token: 'refresh-token',
        }) as never,
      )
      .mockResolvedValueOnce(
        jsonResponse(true, {
          displayName: 'Outlook User',
          mail: 'user@example.com',
        }) as never,
      );
    let connectionUpdateParams: unknown[] | undefined;
    const database = makeDatabase((sql, params) => {
      if (sql.includes('FROM outlook_auth_sessions')) {
        return result([
          {
            state: 'state-1',
            code_verifier: 'verifier-1',
            client_id: 'client-id',
            redirect_uri: 'https://redirect.test/callback',
            scope: 'openid profile offline_access User.Read Calendars.Read',
          },
        ]);
      }
      if (sql.includes('UPDATE outlook_connections')) {
        connectionUpdateParams = params;
      }
      return result([]);
    });
    const { service } = makeService(database);

    await expect(
      service.completeAuth({ code: 'code-1', state: 'state-1' }, context),
    ).resolves.toMatchObject({ ok: true });

    expect(connectionUpdateParams?.[4]).toEqual(new Date('2026-02-01T01:00:00.000Z'));
  });

  it('syncs calendars/events through mocked Microsoft Graph GET and records read-only payloads', async () => {
    const refreshEncrypted = encrypt('refresh-token', encryptionKey());
    const fetchMock = vi.mocked(global.fetch);
    fetchMock.mockImplementation(async (url: string, init?: RequestInit) => {
      expect(init?.method).toBe(url.includes('/token') ? 'POST' : 'GET');
      if (url.includes('/token')) {
        return jsonResponse(true, { access_token: 'new-access-token', expires_in: 3600 }) as never;
      }
      if (url.includes('/me/calendars?')) {
        return jsonResponse(true, {
          value: [{ id: 'cal-1', name: 'Work', hexColor: '#00aa88', isDefaultCalendar: true }],
        }) as never;
      }
      if (url.includes('/calendarView/delta?')) {
        return jsonResponse(true, {
          value: [
            {
              id: 'event-1',
              subject: 'Planning',
              bodyPreview: 'Room agenda',
              location: { displayName: 'Room 4' },
              organizer: { emailAddress: { name: 'Lead', address: 'lead@example.com' } },
              attendees: [{ emailAddress: { address: 'a@example.com' } }],
              start: { dateTime: '2026-02-01T10:00:00', timeZone: 'UTC' },
              end: { dateTime: '2026-02-01T11:00:00', timeZone: 'UTC' },
              showAs: 'busy',
              sensitivity: 'normal',
              type: 'singleInstance',
              '@odata.etag': 'etag-1',
            },
            { id: 'event-deleted', '@removed': { reason: 'deleted' } },
          ],
          '@odata.deltaLink': 'https://graph.microsoft.com/v1.0/delta-token',
        }) as never;
      }
      throw new Error(`Unexpected fetch: ${url}`);
    });
    const payloads: Record<string, unknown>[] = [];
    const database = makeDatabase((sql, params) => {
      if (sql.includes('INSERT INTO outlook_sync_runs') && sql.includes('RETURNING')) {
        return result([{ id: 'run-1' }]);
      }
      if (sql.includes('SELECT * FROM outlook_connections')) {
        return result([
          {
            user_id: userId,
            client_id: 'client-id',
            redirect_uri: 'https://redirect.test/callback',
            scope: 'openid profile offline_access User.Read Calendars.Read',
            status: 'connected',
            refresh_token_encrypted: refreshEncrypted,
            access_token_encrypted: null,
            access_token_expires_at: null,
          },
        ]);
      }
      if (sql.includes('SELECT delta_link')) {
        return result([{ delta_link: null }]);
      }
      if (sql.includes('SELECT id::text') && sql.includes('FROM sync_objects')) {
        return result([]);
      }
      if (sql.includes('INSERT INTO sync_objects')) {
        payloads.push(JSON.parse(String(params?.[3])));
        return result([{ id: `object-${payloads.length}`, server_version: 1, payload: payloads.at(-1) }]);
      }
      if (sql.includes('UPDATE sync_objects') && sql.includes('RETURNING')) {
        return result([{ id: 'deleted-object', server_version: 2, payload: { source: 'outlook' } }]);
      }
      if (sql.includes('SELECT o.id::text')) {
        return result([]);
      }
      return result([]);
    });
    const { service, graphClient } = makeService(database);

    await expect(service.syncNow(context, 'client')).resolves.toMatchObject({
      ok: true,
      status: 'succeeded',
      calendarCount: 1,
      eventUpserts: 1,
      eventDeletes: 1,
      replayedChanges: 0,
    });

    expect(graphClient.createClient).not.toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledWith(
      expect.stringContaining('https://graph.microsoft.com/v1.0/me/calendars'),
      expect.objectContaining({
        method: 'GET',
        headers: expect.objectContaining({ Authorization: 'Bearer new-access-token' }),
      }),
    );
    expect(payloads).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          source: 'outlook',
          readOnly: true,
          remoteCalendarId: 'cal-1',
        }),
        expect.objectContaining({
          title: 'Planning',
          location: 'Room 4',
          source: 'outlook',
          readOnly: true,
          remoteEventId: 'event-1',
        }),
      ]),
    );
  });

  it('records a failed sync when Graph returns an error', async () => {
    const accessEncrypted = encrypt('access-token', encryptionKey());
    vi.mocked(global.fetch).mockResolvedValueOnce(
      jsonResponse(false, 'rate limited by Graph', 429) as never,
    );
    const database = makeDatabase((sql) => {
      if (sql.includes('INSERT INTO outlook_sync_runs') && sql.includes('RETURNING')) {
        return result([{ id: 'run-failed' }]);
      }
      if (sql.includes('SELECT * FROM outlook_connections')) {
        return result([
          {
            user_id: userId,
            client_id: 'client-id',
            redirect_uri: 'https://redirect.test/callback',
            scope: 'openid profile offline_access User.Read Calendars.Read',
            status: 'connected',
            refresh_token_encrypted: encrypt('refresh-token', encryptionKey()),
            access_token_encrypted: accessEncrypted,
            access_token_expires_at: new Date(Date.now() + 600_000),
          },
        ]);
      }
      return result([]);
    });
    const { service } = makeService(database);

    await expect(service.syncNow(context, 'admin')).resolves.toMatchObject({
      ok: false,
      runId: 'run-failed',
      status: 'failed',
      errorMessage: expect.stringContaining('Outlook Graph GET failed (429)'),
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE outlook_connections'),
      [userId, expect.stringContaining('Outlook Graph GET failed (429)')],
    );
  });

  it('returns failed sync when connected account is missing all usable tokens', async () => {
    const database = makeDatabase((sql) => {
      if (sql.includes('INSERT INTO outlook_sync_runs') && sql.includes('RETURNING')) {
        return result([{ id: 'run-tokenless' }]);
      }
      if (sql.includes('SELECT * FROM outlook_connections')) {
        return result([
          {
            user_id: userId,
            client_id: 'client-id',
            redirect_uri: 'https://redirect.test/callback',
            scope: 'openid profile offline_access User.Read Calendars.Read',
            status: 'connected',
            refresh_token_encrypted: null,
            access_token_encrypted: null,
            access_token_expires_at: null,
          },
        ]);
      }
      return result([]);
    });
    const { service } = makeService(database);

    await expect(service.syncNow(context)).resolves.toMatchObject({
      ok: false,
      status: 'failed',
      errorMessage: 'Outlook refresh token is missing',
    });
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('records non-Error sync failures as string messages', async () => {
    const database = makeDatabase((sql, params) => {
      if (sql.includes('INSERT INTO outlook_sync_runs') && sql.includes('RETURNING')) {
        return result([{ id: 'run-string-failure' }]);
      }
      if (sql.includes('SELECT * FROM outlook_connections')) {
        throw 'plain string sync failure';
      }
      if (sql.includes('UPDATE outlook_connections')) {
        expect(params).toEqual([userId, 'plain string sync failure']);
        return result([]);
      }
      if (sql.includes('UPDATE outlook_sync_runs')) {
        const metadata = JSON.parse(String(params?.[5]));
        expect(metadata.errors).toEqual([
          expect.objectContaining({ message: 'plain string sync failure' }),
        ]);
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect((service as any).syncUser(userId, 'client')).resolves.toMatchObject({
      ok: false,
      runId: 'run-string-failure',
      status: 'failed',
      errorMessage: 'plain string sync failure',
    });
  });

  it('builds diagnostics from status, object counts, mappings, recent runs, and field coverage', async () => {
    const database = makeDatabase((sql) => {
      if (sql.includes('SELECT * FROM outlook_connections')) {
        return result([
          {
            status: 'connected',
            client_id: 'client-id',
            account_email: 'user@example.com',
            account_display_name: 'Outlook User',
            last_sync_at: '2026-01-01T00:00:00.000Z',
            last_error: null,
          },
        ]);
      }
      if (sql.includes('SELECT count(*)::int AS count') && sql.includes('FROM outlook_calendar_states')) {
        return result([{ count: 2 }]);
      }
      if (sql.includes('GROUP BY object_type')) {
        return result([{ objectType: 'calendar_event', count: 7 }]);
      }
      if (sql.includes('GROUP BY sync_state')) {
        return result([{ syncState: 'synced', count: 7 }]);
      }
      if (sql.includes('LIMIT 10')) {
        return result([{ id: 'run-1', status: 'succeeded' }]);
      }
      if (sql.includes('ORDER BY started_at DESC') && sql.includes('LIMIT 1')) {
        return result([{ id: 'latest-run', status: 'succeeded' }]);
      }
      if (sql.includes('COUNT(*)::int AS "eventCount"')) {
        return result([{ eventCount: 7, missingTitle: 1 }]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(service.diagnostics(context)).resolves.toMatchObject({
      connected: true,
      objectCounts: [{ objectType: 'calendar_event', count: 7 }],
      mappings: [{ syncState: 'synced', count: 7 }],
      recentRuns: [{ id: 'run-1', status: 'succeeded' }],
      fieldCoverage: { eventCount: 7, missingTitle: 1 },
      writeBackEnabled: false,
      graphWriteMethodsAllowed: [],
    });
  });

  it('uses empty diagnostics rows and null field coverage when no Outlook data exists', async () => {
    const database = makeDatabase((sql) => {
      if (sql.includes('SELECT * FROM outlook_connections')) {
        return result([]);
      }
      if (sql.includes('SELECT count(*)::int AS count') && sql.includes('FROM outlook_calendar_states')) {
        return result([]);
      }
      if (sql.includes('GROUP BY object_type')) {
        return result([]);
      }
      if (sql.includes('GROUP BY sync_state')) {
        return result([]);
      }
      if (sql.includes('LIMIT 10')) {
        return result([]);
      }
      if (sql.includes('ORDER BY started_at DESC') && sql.includes('LIMIT 1')) {
        return result([]);
      }
      if (sql.includes('COUNT(*)::int AS "eventCount"')) {
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(service.diagnostics(context)).resolves.toMatchObject({
      connected: false,
      status: 'disconnected',
      calendars: 0,
      lastRun: null,
      objectCounts: [],
      mappings: [],
      recentRuns: [],
      fieldCoverage: null,
    });
  });

  it('reset tombstones local Outlook objects without deleting remote Outlook data', async () => {
    const database = makeDatabase((sql) => {
      if (sql.includes('UPDATE sync_objects') && sql.includes('RETURNING')) {
        return result(
          [
            {
              id: 'object-1',
              object_type: 'calendar_event',
              server_version: 4,
              payload: { source: 'outlook', title: 'Old event' },
            },
          ],
          1,
        );
      }
      return result([]);
    });
    const { service } = makeService(database);

    await expect(service.reset(context)).resolves.toEqual({
      ok: true,
      readOnly: true,
      remoteOutlookDataDeleted: false,
      deletedObjects: 1,
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO outlook_sync_runs'),
      [userId, 1, JSON.stringify({ remoteOutlookDataDeleted: false })],
    );
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('starts and clears the automatic sync timer without running immediately', () => {
    vi.useFakeTimers();
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);
    const setIntervalSpy = vi.spyOn(global, 'setInterval');
    const clearIntervalSpy = vi.spyOn(global, 'clearInterval');

    service.onModuleInit();
    service.onModuleDestroy();

    expect(setIntervalSpy).toHaveBeenCalledWith(expect.any(Function), 60_000);
    expect(clearIntervalSpy).toHaveBeenCalledTimes(1);
    expect(database.query).not.toHaveBeenCalled();
  });

  it('does not clear a timer when module destroy runs before module init', () => {
    vi.useFakeTimers();
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);
    const clearIntervalSpy = vi.spyOn(global, 'clearInterval');

    service.onModuleDestroy();

    expect(clearIntervalSpy).not.toHaveBeenCalled();
  });

  it('lists synced calendars, recent runs, and pending write drafts for the ensured user', async () => {
    const calendars = [
      {
        remoteCalendarId: 'cal-1',
        name: 'Work',
        colorHex: '#00aa88',
        isVisible: true,
        lastSyncedAt: '2026-02-01T00:00:00.000Z',
        updatedAt: '2026-02-01T00:01:00.000Z',
      },
    ];
    const runs = [
      {
        id: 'run-1',
        triggerSource: 'client',
        status: 'succeeded',
        calendarCount: 1,
        eventUpserts: 2,
        eventDeletes: 0,
      },
    ];
    const drafts = [
      {
        id: 'draft-1',
        title: 'Create planning event',
        proposedAction: 'outlook_create_event',
        riskLevel: 'normal',
        status: 'pending_review',
      },
    ];
    const database = makeDatabase((sql, params) => {
      expect(params).toEqual([userId]);
      if (sql.includes('FROM outlook_calendar_states') && sql.includes('remote_calendar_id')) {
        return result(calendars);
      }
      if (sql.includes('FROM outlook_sync_runs')) {
        return result(runs);
      }
      if (sql.includes('FROM ai_operation_drafts')) {
        return result(drafts);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service, devices } = makeService(database);

    await expect(service.calendars(context)).resolves.toEqual({ calendars });
    await expect(service.runs(context)).resolves.toEqual({ runs });
    await expect(service.drafts(context)).resolves.toEqual({ drafts });
    expect(devices.ensureUser).toHaveBeenCalledTimes(3);
  });

  it('replays current Outlook objects in stable order and records server-side upsert changes', async () => {
    const rows = [
      {
        id: 'calendar-object',
        object_type: 'calendar_book',
        server_version: 3,
        payload: { source: 'outlook', name: 'Work' },
      },
      {
        id: 'event-object',
        object_type: 'calendar_event',
        server_version: 7,
        payload: { source: 'outlook', title: 'Planning' },
      },
    ];
    const database = makeDatabase((sql) => {
      if (sql.includes('SELECT o.id::text')) {
        return result(rows);
      }
      if (sql.includes('INSERT INTO sync_changes')) {
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(service.replayCurrentOutlookObjects(userId, 'manual_repair')).resolves.toEqual({
      calendarBooks: 1,
      calendarEvents: 1,
      changes: 2,
      reason: 'manual_repair',
    });
    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO sync_changes'),
      [
        userId,
        'calendar-object',
        'calendar_book',
        'upsert',
        3,
        JSON.stringify({ source: 'outlook', name: 'Work' }),
      ],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO sync_changes'),
      [
        userId,
        'event-object',
        'calendar_event',
        'upsert',
        7,
        JSON.stringify({ source: 'outlook', title: 'Planning' }),
      ],
    );
  });

  it('replays defensive non-calendar rows without counting them as Outlook objects', async () => {
    const rows = [
      {
        id: 'defensive-object',
        object_type: 'unexpected_outlook_object',
        server_version: 9,
        payload: { source: 'outlook', title: 'Unexpected' },
      },
    ];
    const changeParams: unknown[][] = [];
    const database = makeDatabase((sql, params) => {
      if (sql.includes('SELECT o.id::text')) {
        return result(rows);
      }
      if (sql.includes('INSERT INTO sync_changes')) {
        changeParams.push(params ?? []);
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(service.replayCurrentOutlookObjects(userId, 'defensive_replay')).resolves.toEqual({
      calendarBooks: 0,
      calendarEvents: 0,
      changes: 1,
      reason: 'defensive_replay',
    });
    expect(changeParams).toEqual([
      [
        userId,
        'defensive-object',
        'unexpected_outlook_object',
        'upsert',
        9,
        JSON.stringify({ source: 'outlook', title: 'Unexpected' }),
      ],
    ]);
  });

  it('prepares high-risk delete write drafts and records an audit entry', async () => {
    const draft = {
      id: 'draft-delete',
      title: 'Delete stale event',
      risk_level: 'high',
      status: 'pending_review',
      createdAt: '2026-02-01T00:00:00.000Z',
    };
    const database = makeDatabase((sql) => {
      if (sql.includes('INSERT INTO ai_operation_drafts')) {
        return result([draft]);
      }
      if (sql.includes('INSERT INTO audit_logs')) {
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service, devices } = makeService(database);

    await expect(
      service.prepareWrite(
        {
          action: 'delete_event',
          title: ' Delete stale event ',
          summary: '',
          reason: 'duplicate',
          proposedPayload: { remoteEventId: 'event-1' },
        },
        context,
      ),
    ).resolves.toEqual({ ok: true, draft });

    expect(devices.ensureDevice).toHaveBeenCalledWith(context);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO ai_operation_drafts'),
      [
        userId,
        'Delete stale event',
        'Proposed Outlook delete_event operation',
        'outlook_delete_event',
        'high',
        JSON.stringify({ action: 'delete_event', reason: 'duplicate', source: 'outlook_write' }),
        JSON.stringify({ remoteEventId: 'event-1' }),
      ],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        userId,
        deviceId,
        'outlook.write.prepared',
        'draft-delete',
        JSON.stringify({ draftId: 'draft-delete', action: 'delete_event' }),
      ],
    );
  });

  it('rejects unsupported write draft actions before opening a transaction', async () => {
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);

    await expect(
      service.prepareWrite({ action: 'send_email' }, context),
    ).rejects.toThrow('action must be create_event, update_event, or delete_event');
    expect(database.transaction).not.toHaveBeenCalled();
  });

  it('confirms readwrite drafts and persists the approval audit trail', async () => {
    const database = makeDatabase((sql, params) => {
      if (sql.includes('SELECT * FROM ai_operation_drafts')) {
        expect(params).toEqual([userId, 'draft-1']);
        return result([{ id: 'draft-1', proposed_action: 'outlook_update_event' }]);
      }
      if (sql.includes('COALESCE(sync_mode')) {
        expect(params).toEqual([userId]);
        return result([{ id: 'conn-1', status: 'connected', sync_mode: 'readwrite' }]);
      }
      if (sql.includes('UPDATE ai_operation_drafts')) {
        expect(params).toEqual([userId, 'draft-1', 'looks good']);
        return result([]);
      }
      if (sql.includes('INSERT INTO audit_logs')) {
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(
      service.confirmWrite(
        'draft-1',
        { confirmationPhrase: 'CONFIRM', reviewNote: ' looks good ' },
        context,
      ),
    ).resolves.toEqual({ ok: true, draftId: 'draft-1', status: 'executed' });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        userId,
        deviceId,
        'outlook.write.confirmed',
        'draft-1',
        JSON.stringify({ draftId: 'draft-1', action: 'outlook_update_event' }),
      ],
    );
  });

  it('rejects write confirmation unless the exact confirmation phrase is supplied', async () => {
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);

    await expect(
      service.confirmWrite('draft-1', { confirmationPhrase: 'confirm' }, context),
    ).rejects.toThrow('confirmationPhrase must be "CONFIRM"');
    expect(database.transaction).not.toHaveBeenCalled();
  });

  it('blocks write confirmation for readonly Outlook connections', async () => {
    const database = makeDatabase((sql) => {
      if (sql.includes('SELECT * FROM ai_operation_drafts')) {
        return result([{ id: 'draft-1', proposed_action: 'outlook_create_event' }]);
      }
      if (sql.includes('COALESCE(sync_mode')) {
        return result([{ id: 'conn-1', status: 'connected', sync_mode: 'readonly' }]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(
      service.confirmWrite('draft-1', { confirmationPhrase: 'CONFIRM' }, context),
    ).rejects.toThrow('sync mode must be "readwrite"');
    expect(database.query).not.toHaveBeenCalledWith(
      expect.stringContaining('UPDATE ai_operation_drafts'),
      expect.any(Array),
    );
  });

  it('treats connected Outlook rows without sync_mode as readonly for write confirmation', async () => {
    const database = makeDatabase((sql) => {
      if (sql.includes('SELECT * FROM ai_operation_drafts')) {
        return result([{ id: 'draft-1', proposed_action: 'outlook_create_event' }]);
      }
      if (sql.includes('COALESCE(sync_mode')) {
        return result([{ id: 'conn-1', status: 'connected' }]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(
      service.confirmWrite('draft-1', { confirmationPhrase: 'CONFIRM' }, context),
    ).rejects.toThrow('sync mode must be "readwrite"');
    expect(database.query).not.toHaveBeenCalledWith(
      expect.stringContaining('UPDATE ai_operation_drafts'),
      expect.any(Array),
    );
  });

  it('rejects pending write drafts and stores a review audit note', async () => {
    const database = makeDatabase((sql, params) => {
      if (sql.includes('UPDATE ai_operation_drafts')) {
        expect(params).toEqual([userId, 'draft-1', 'too risky']);
        return result([]);
      }
      if (sql.includes('INSERT INTO audit_logs')) {
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(
      service.rejectWrite('draft-1', { reviewNote: ' too risky ' }, context),
    ).resolves.toEqual({ ok: true, draftId: 'draft-1', status: 'rejected' });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        userId,
        deviceId,
        'outlook.write.rejected',
        'draft-1',
        JSON.stringify({ draftId: 'draft-1' }),
      ],
    );
  });

  it('rejects malformed OAuth completion payloads before token exchange', async () => {
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);

    await expect(
      service.completeAuth({ callbackUrl: 'not a url' }, context),
    ).rejects.toThrow('callbackUrl must be the full Microsoft redirect URL');
    await expect(
      service.completeAuth({ callbackUrl: 'https://login.test/callback?code=only-code' }, context),
    ).rejects.toThrow('callbackUrl must include both code and state query parameters');
    await expect(
      service.completeAuth({ callbackUrl: 'https://login.test/callback?state=only-state' }, context),
    ).rejects.toThrow('callbackUrl must include both code and state query parameters');
    await expect(service.completeAuth({}, context)).rejects.toThrow(
      'requires callbackUrl or both code and state',
    );
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('rejects expired OAuth authorization sessions before token exchange', async () => {
    const database = makeDatabase((sql, params) => {
      if (sql.includes('FROM outlook_auth_sessions')) {
        expect(params).toEqual([userId, 'state-1']);
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(
      service.completeAuth({ code: 'code-1', state: 'state-1' }, context),
    ).rejects.toThrow('authorization state is invalid or expired');
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('fails OAuth completion when the token endpoint rejects the code', async () => {
    vi.mocked(global.fetch).mockResolvedValueOnce(
      jsonResponse(false, { error: 'invalid_grant' }, 400) as never,
    );
    const database = makeDatabase((sql) => {
      if (sql.includes('FROM outlook_auth_sessions')) {
        return result([
          {
            state: 'state-1',
            code_verifier: 'verifier-1',
            client_id: 'client-id',
            redirect_uri: 'https://redirect.test/callback',
            scope: 'openid profile offline_access User.Read Calendars.Read',
          },
        ]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(
      service.completeAuth({ code: 'code-1', state: 'state-1' }, context),
    ).rejects.toThrow('Outlook OAuth token request failed (400)');
  });

  it('uses paginated calendar and delta links without rewriting unchanged sync objects', async () => {
    const accessEncrypted = encrypt('access-token', encryptionKey());
    const fetchMock = vi.mocked(global.fetch);
    fetchMock.mockImplementation(async (url: string) => {
      if (url.includes('/me/calendars?page=2')) {
        return jsonResponse(true, {
          value: [{ id: 'cal-2', name: 'Home', hexColor: '#ff00aa' }],
        }) as never;
      }
      if (url.includes('/me/calendars?$top=')) {
        return jsonResponse(true, {
          value: [{ id: 'cal-1', name: 'Work' }],
          '@odata.nextLink': 'https://graph.microsoft.com/v1.0/me/calendars?page=2',
        }) as never;
      }
      if (url.includes('/me/calendars/cal-1/calendarView/delta?')) {
        return jsonResponse(true, {
          value: [
            {
              id: 'event-unchanged',
              subject: '',
              bodyPreview: 'Fallback title',
              locations: [{ displayName: 'Room A' }, { displayName: 'Room B' }],
              start: { dateTime: 'invalid-date', timeZone: 'UTC' },
              end: {},
              showAs: 'free',
              isCancelled: true,
            },
          ],
          '@odata.deltaLink': 'https://graph.microsoft.com/v1.0/delta-cal-1',
        }) as never;
      }
      if (url === 'https://graph.microsoft.com/v1.0/existing-delta') {
        return jsonResponse(true, {
          value: [],
          '@odata.deltaLink': 'https://graph.microsoft.com/v1.0/delta-cal-2',
        }) as never;
      }
      throw new Error(`Unexpected fetch: ${url}`);
    });
    const payloads: Record<string, unknown>[] = [];
    const database = makeDatabase((sql, params) => {
      if (sql.includes('INSERT INTO outlook_sync_runs') && sql.includes('RETURNING')) {
        return result([{ id: 'run-paged' }]);
      }
      if (sql.includes('SELECT * FROM outlook_connections')) {
        return result([
          {
            user_id: userId,
            client_id: 'client-id',
            redirect_uri: 'https://redirect.test/callback',
            scope: 'openid profile offline_access User.Read Calendars.Read',
            status: 'connected',
            refresh_token_encrypted: encrypt('refresh-token', encryptionKey()),
            access_token_encrypted: accessEncrypted,
            access_token_expires_at: new Date(Date.now() + 600_000),
          },
        ]);
      }
      if (sql.includes('SELECT delta_link')) {
        return result([
          {
            delta_link: params?.[1] === 'cal-2'
              ? 'https://graph.microsoft.com/v1.0/existing-delta'
              : null,
          },
        ]);
      }
      if (sql.includes('SELECT id::text') && sql.includes('FROM sync_objects')) {
        return result([{ id: `existing-${params?.[2]}` }]);
      }
      if (sql.includes('UPDATE sync_objects') && sql.includes('RETURNING')) {
        payloads.push(JSON.parse(String(params?.[3])));
        if (params?.[2] === 'outlook_event:cal-1:event-unchanged') {
          return result([]);
        }
        return result([
          {
            id: `updated-${params?.[2]}`,
            server_version: 5,
            payload: payloads.at(-1),
          },
        ]);
      }
      if (sql.includes('SELECT o.id::text')) {
        return result([]);
      }
      return result([]);
    });
    const { service } = makeService(database);

    await expect(service.syncNow(context, 'admin')).resolves.toMatchObject({
      ok: true,
      runId: 'run-paged',
      status: 'succeeded',
      calendarCount: 2,
      eventUpserts: 0,
      eventDeletes: 0,
    });
    expect(fetchMock).toHaveBeenCalledWith(
      'https://graph.microsoft.com/v1.0/me/calendars?page=2',
      expect.objectContaining({ method: 'GET' }),
    );
    expect(fetchMock).toHaveBeenCalledWith(
      'https://graph.microsoft.com/v1.0/existing-delta',
      expect.objectContaining({ method: 'GET' }),
    );
    expect(payloads).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          title: 'Fallback title',
          description: 'Fallback title',
          location: 'Room A, Room B',
          dtstart: 'invalid-date',
          dtend: null,
          status: 'CANCELLED',
          transp: 'TRANSPARENT',
          isBlock: false,
        }),
      ]),
    );
    const succeededRun = database.query.mock.calls.find(
      ([sql, params]) =>
        String(sql).includes('UPDATE outlook_sync_runs') &&
        Array.isArray(params) &&
        params[0] === 'run-paged',
    );
    const diagnostics = JSON.parse(String((succeededRun?.[1] as unknown[])[4]));
    expect(diagnostics.calendars).toEqual([
      expect.objectContaining({ remoteCalendarId: 'cal-1', deltaMode: false, pageCount: 1 }),
      expect.objectContaining({ remoteCalendarId: 'cal-2', deltaMode: true, pageCount: 1 }),
    ]);
    expect(diagnostics.fieldStats).toMatchObject({
      totalEvents: 1,
      missingSubject: 1,
      missingOrganizer: 1,
      missingAttendees: 1,
    });
  });

  it('syncs nameless calendars through pages that omit values while retaining the last delta link', async () => {
    const accessEncrypted = encrypt('access-token', encryptionKey());
    const fetchMock = vi.mocked(global.fetch);
    fetchMock.mockImplementation(async (url: string) => {
      if (url.includes('/me/calendars?page=2')) {
        return jsonResponse(true, {
          value: [{ id: 'cal-nameless' }],
        }) as never;
      }
      if (url.includes('/me/calendars?$top=')) {
        return jsonResponse(true, {
          '@odata.nextLink': 'https://graph.microsoft.com/v1.0/me/calendars?page=2',
        }) as never;
      }
      if (url.includes('/me/calendars/cal-nameless/calendarView/delta?page=2')) {
        return jsonResponse(true, {}) as never;
      }
      if (url.includes('/me/calendars/cal-nameless/calendarView/delta?')) {
        return jsonResponse(true, {
          '@odata.nextLink':
            'https://graph.microsoft.com/v1.0/me/calendars/cal-nameless/calendarView/delta?page=2',
          '@odata.deltaLink': 'https://graph.microsoft.com/v1.0/delta-retained',
        }) as never;
      }
      throw new Error(`Unexpected fetch: ${url}`);
    });
    const syncPayloads: Record<string, unknown>[] = [];
    let calendarStateParams: unknown[] | undefined;
    const database = makeDatabase((sql, params) => {
      if (sql.includes('INSERT INTO outlook_sync_runs') && sql.includes('RETURNING')) {
        return result([{ id: 'run-nameless' }]);
      }
      if (sql.includes('SELECT * FROM outlook_connections')) {
        return result([
          {
            user_id: userId,
            client_id: 'client-id',
            redirect_uri: 'https://redirect.test/callback',
            scope: 'openid profile offline_access User.Read Calendars.Read',
            status: 'connected',
            refresh_token_encrypted: encrypt('refresh-token', encryptionKey()),
            access_token_encrypted: accessEncrypted,
            access_token_expires_at: new Date(Date.now() + 600_000),
          },
        ]);
      }
      if (sql.includes('SELECT delta_link')) {
        return result([{ delta_link: null }]);
      }
      if (sql.includes('SELECT id::text') && sql.includes('FROM sync_objects')) {
        return result([{ id: `existing-${params?.[2]}` }]);
      }
      if (sql.includes('UPDATE sync_objects') && sql.includes('RETURNING')) {
        syncPayloads.push(JSON.parse(String(params?.[3])));
        return result([]);
      }
      if (sql.includes('INSERT INTO outlook_calendar_states')) {
        calendarStateParams = params;
        return result([]);
      }
      if (sql.includes('SELECT o.id::text')) {
        return result([]);
      }
      return result([]);
    });
    const { service } = makeService(database);

    await expect(service.syncNow(context, 'admin')).resolves.toMatchObject({
      ok: true,
      runId: 'run-nameless',
      status: 'succeeded',
      calendarCount: 1,
      eventUpserts: 0,
      eventDeletes: 0,
    });

    expect(fetchMock).toHaveBeenCalledWith(
      'https://graph.microsoft.com/v1.0/me/calendars?page=2',
      expect.objectContaining({ method: 'GET' }),
    );
    expect(syncPayloads).toEqual([
      expect.objectContaining({
        uid: 'outlook_calendar:cal-nameless',
        name: 'Outlook',
        colorHex: '#2563eb',
      }),
    ]);
    expect(calendarStateParams).toEqual([
      userId,
      'cal-nameless',
      'Outlook',
      '#2563eb',
      'https://graph.microsoft.com/v1.0/delta-retained',
    ]);
    const succeededRun = database.query.mock.calls.find(
      ([sql, params]) =>
        String(sql).includes('UPDATE outlook_sync_runs') &&
        Array.isArray(params) &&
        params[0] === 'run-nameless',
    );
    const diagnostics = JSON.parse(String((succeededRun?.[1] as unknown[])[4]));
    expect(diagnostics.calendars).toEqual([
      expect.objectContaining({
        remoteCalendarId: 'cal-nameless',
        name: 'Outlook',
        deltaMode: false,
        pageCount: 2,
        eventCount: 0,
      }),
    ]);
  });

  it('invokes due sync scanning from the module timer callback', async () => {
    vi.useFakeTimers();
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);
    const runDueSyncs = vi
      .spyOn(service as any, 'runDueSyncs')
      .mockResolvedValue(undefined);

    service.onModuleInit();
    await vi.advanceTimersByTimeAsync(60_000);
    service.onModuleDestroy();

    expect(runDueSyncs).toHaveBeenCalledTimes(1);
  });

  it('skips automatic due sync rows that are already active', async () => {
    const otherUserId = '00000000-0000-4000-8000-000000000002';
    const database = makeDatabase((sql) => {
      if (sql.includes('FROM outlook_connections') && sql.includes("WHERE status = 'connected'")) {
        return result([
          { user_id: userId },
          { user_id: otherUserId },
        ]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);
    (service as any).activeRuns.add(userId);
    const syncUser = vi.spyOn(service as any, 'syncUser').mockResolvedValue({ ok: true });

    await (service as any).runDueSyncs();

    expect(syncUser).toHaveBeenCalledTimes(1);
    expect(syncUser).toHaveBeenCalledWith(otherUserId, 'automatic');
  });

  it('swallows background automatic sync failures after scheduling due rows', async () => {
    const dueUserId = '00000000-0000-4000-8000-000000000003';
    const database = makeDatabase((sql) => {
      if (sql.includes('FROM outlook_connections') && sql.includes("WHERE status = 'connected'")) {
        return result([{ user_id: dueUserId }]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);
    const syncUser = vi
      .spyOn(service as any, 'syncUser')
      .mockImplementation(async () => {
        await Promise.resolve();
        throw new Error('background sync failed');
      });

    await (service as any).runDueSyncs();
    await Promise.resolve();
    await Promise.resolve();

    expect(syncUser).toHaveBeenCalledWith(dueUserId, 'automatic');
  });

  it('returns already_running with the latest run while a sync is active', async () => {
    const latestRun = {
      id: 'run-latest',
      triggerSource: 'automatic',
      status: 'succeeded',
      startedAt: new Date('2026-03-01T10:00:00.000Z'),
      finishedAt: null,
      calendarCount: 3,
      eventUpserts: 4,
      eventDeletes: 5,
      errorMessage: null,
    };
    const database = makeDatabase((sql, params) => {
      expect(params).toEqual([userId]);
      if (sql.includes('FROM outlook_sync_runs') && sql.includes('LIMIT 1')) {
        return result([latestRun]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);
    (service as any).activeRuns.add(userId);

    await expect((service as any).syncUser(userId, 'client')).resolves.toMatchObject({
      ok: true,
      runId: 'run-latest',
      triggerSource: 'client',
      status: 'already_running',
      calendarCount: 3,
      eventUpserts: 4,
      eventDeletes: 5,
      startedAt: '2026-03-01T10:00:00.000Z',
      errorMessage: null,
    });
    expect(database.query).toHaveBeenCalledTimes(1);
  });

  it('returns already_running default values when no latest run exists', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-03-01T11:00:00.000Z'));
    const database = makeDatabase((sql, params) => {
      expect(params).toEqual([userId]);
      if (sql.includes('FROM outlook_sync_runs') && sql.includes('LIMIT 1')) {
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);
    (service as any).activeRuns.add(userId);

    await expect((service as any).syncUser(userId, 'automatic')).resolves.toEqual({
      ok: true,
      runId: 'already-running',
      triggerSource: 'automatic',
      status: 'already_running',
      calendarCount: 0,
      eventUpserts: 0,
      eventDeletes: 0,
      startedAt: '2026-03-01T11:00:00.000Z',
      finishedAt: '2026-03-01T11:00:00.000Z',
      errorMessage: null,
    });
    expect(database.query).toHaveBeenCalledTimes(1);
  });

  it('records a failed sync when no connected Outlook account exists', async () => {
    const database = makeDatabase((sql) => {
      if (sql.includes('INSERT INTO outlook_sync_runs') && sql.includes('RETURNING')) {
        return result([{ id: 'run-disconnected' }]);
      }
      if (sql.includes('SELECT * FROM outlook_connections')) {
        return result([]);
      }
      if (sql.includes('UPDATE outlook_connections')) {
        return result([]);
      }
      if (sql.includes('UPDATE outlook_sync_runs')) {
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(service.syncNow(context, 'client')).resolves.toMatchObject({
      ok: false,
      runId: 'run-disconnected',
      triggerSource: 'client',
      status: 'failed',
      errorMessage: 'Outlook is not connected on the server',
    });
  });

  it('refreshes expired access tokens, stores rotated refresh tokens, and then syncs', async () => {
    const fetchMock = vi.mocked(global.fetch);
    let tokenBody: URLSearchParams | undefined;
    fetchMock.mockImplementation(async (url: string, init?: RequestInit) => {
      if (url.includes('/oauth2/v2.0/token')) {
        tokenBody = init?.body as URLSearchParams;
        return jsonResponse(true, {
          access_token: 'rotated-access-token',
          refresh_token: 'rotated-refresh-token',
        }) as never;
      }
      if (url.includes('/me/calendars?')) {
        expect(init?.headers).toEqual(
          expect.objectContaining({ Authorization: 'Bearer rotated-access-token' }),
        );
        return jsonResponse(true, { value: [] }) as never;
      }
      throw new Error(`Unexpected fetch: ${url}`);
    });
    let tokenUpdateParams: unknown[] | undefined;
    const database = makeDatabase((sql, params) => {
      if (sql.includes('INSERT INTO outlook_sync_runs') && sql.includes('RETURNING')) {
        return result([{ id: 'run-refresh' }]);
      }
      if (sql.includes('SELECT * FROM outlook_connections')) {
        return result([
          {
            user_id: userId,
            client_id: 'client-id',
            redirect_uri: 'https://redirect.test/callback',
            scope: 'openid profile offline_access User.Read Calendars.Read',
            status: 'connected',
            refresh_token_encrypted: encrypt('old-refresh-token', encryptionKey()),
            access_token_encrypted: encrypt('expired-access-token', encryptionKey()),
            access_token_expires_at: new Date(Date.now() - 60_000),
          },
        ]);
      }
      if (sql.includes('UPDATE outlook_connections') && sql.includes('access_token_encrypted')) {
        tokenUpdateParams = params;
        return result([]);
      }
      if (sql.includes('UPDATE outlook_connections')) {
        return result([]);
      }
      if (sql.includes('SELECT o.id::text')) {
        return result([]);
      }
      if (sql.includes('UPDATE outlook_sync_runs')) {
        return result([]);
      }
      return result([]);
    });
    const { service } = makeService(database);

    await expect(service.syncNow(context, 'admin')).resolves.toMatchObject({
      ok: true,
      runId: 'run-refresh',
      status: 'succeeded',
      calendarCount: 0,
    });
    expect(tokenBody?.get('grant_type')).toBe('refresh_token');
    expect(tokenBody?.get('refresh_token')).toBe('old-refresh-token');
    expect(decrypt(String(tokenUpdateParams?.[1]), encryptionKey())).toBe('rotated-access-token');
    expect(decrypt(String(tokenUpdateParams?.[2]), encryptionKey())).toBe('rotated-refresh-token');
    expect(tokenUpdateParams?.[3]).toBeInstanceOf(Date);
  });

  it('records token refresh failures before calling Microsoft Graph calendars', async () => {
    vi.mocked(global.fetch).mockResolvedValueOnce(
      jsonResponse(true, { refresh_token: 'new-refresh-without-access' }) as never,
    );
    const database = makeDatabase((sql) => {
      if (sql.includes('INSERT INTO outlook_sync_runs') && sql.includes('RETURNING')) {
        return result([{ id: 'run-refresh-failed' }]);
      }
      if (sql.includes('SELECT * FROM outlook_connections')) {
        return result([
          {
            user_id: userId,
            client_id: 'client-id',
            redirect_uri: 'https://redirect.test/callback',
            scope: 'openid profile offline_access User.Read Calendars.Read',
            status: 'connected',
            refresh_token_encrypted: encrypt('old-refresh-token', encryptionKey()),
            access_token_encrypted: null,
            access_token_expires_at: null,
          },
        ]);
      }
      if (sql.includes('UPDATE outlook_connections')) {
        return result([]);
      }
      if (sql.includes('UPDATE outlook_sync_runs')) {
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(service.syncNow(context, 'admin')).resolves.toMatchObject({
      ok: false,
      runId: 'run-refresh-failed',
      status: 'failed',
      errorMessage: 'Outlook OAuth response did not include an access token',
    });
    expect(global.fetch).toHaveBeenCalledTimes(1);
  });

  it('rejects OAuth completion before session lookup when encryption key is missing', async () => {
    delete process.env.FLOWPLANV2_ENCRYPTION_KEY;
    delete process.env.OUTLOOK_CONFIG_SECRET;
    delete process.env.AI_CONFIG_SECRET;
    process.env.DATABASE_URL = 'postgres://localhost/flowplantest';
    const database = makeDatabase(() => {
      throw new Error('database should not be queried without a secure encryption key');
    });
    const { service } = makeService(database);

    await expect(
      service.completeAuth({ code: 'code-1', state: 'state-1' }, context),
    ).rejects.toThrow('Encryption key is not configured');
    expect(database.query).not.toHaveBeenCalled();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('guards Graph GET helpers against non-v1 Microsoft Graph URLs', async () => {
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);

    await expect(
      (service as any).graphGet('https://graph.microsoft.com/beta/me', 'access-token'),
    ).rejects.toThrow('Only Microsoft Graph v1.0 GET requests are allowed');
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('merges recurring occurrences from cached and stored masters and records lookup failures', async () => {
    const accessEncrypted = encrypt('access-token', encryptionKey());
    const fetchMock = vi.mocked(global.fetch);
    fetchMock.mockImplementation(async (url: string) => {
      if (url.includes('/me/calendars?')) {
        return jsonResponse(true, {
          value: [{ id: 'cal-1', name: 'Recurring', hexColor: '#123456' }],
        }) as never;
      }
      if (url.includes('/calendarView/delta?')) {
        return jsonResponse(true, {
          value: [
            {
              id: 'master-cached',
              subject: 'Cached Master',
              bodyPreview: 'Cached body',
              location: { displayName: 'Cached Room' },
              organizer: {
                emailAddress: { name: 'Cached Owner', address: 'cached@example.com' },
              },
              attendees: [{ emailAddress: { address: 'attendee@example.com' } }],
              showAs: 'busy',
              isAllDay: true,
              sensitivity: 'private',
              type: 'seriesMaster',
              webLink: 'https://cached.example',
            },
            {
              id: 'occ-cached',
              type: 'occurrence',
              seriesMasterId: 'master-cached',
              start: { dateTime: '2026-04-01T12:00:00', timeZone: 'UTC' },
              end: { dateTime: '2026-04-01T13:00:00', timeZone: 'UTC' },
            },
            {
              id: 'occ-db',
              type: 'exception',
              seriesMasterId: 'master-db',
              start: { dateTime: '2026-04-02T12:00:00', timeZone: 'UTC' },
              end: { dateTime: '2026-04-02T13:00:00', timeZone: 'UTC' },
            },
            {
              id: 'occ-missing',
              type: 'occurrence',
              seriesMasterId: 'master-missing',
            },
            { id: 'removed-event', '@removed': { reason: 'deleted' } },
          ],
          '@odata.deltaLink': 'https://graph.microsoft.com/v1.0/delta-recurring',
        }) as never;
      }
      if (url.includes('/events/master-missing')) {
        return jsonResponse(false, 'missing master', 404) as never;
      }
      throw new Error(`Unexpected fetch: ${url}`);
    });
    const payloads: Array<{ objectType: string; uid: string; payload: Record<string, unknown> }> = [];
    const database = makeDatabase((sql, params) => {
      if (sql.includes('INSERT INTO outlook_sync_runs') && sql.includes('RETURNING')) {
        return result([{ id: 'run-recurring' }]);
      }
      if (sql.includes('SELECT * FROM outlook_connections')) {
        return result([
          {
            user_id: userId,
            client_id: 'client-id',
            redirect_uri: 'https://redirect.test/callback',
            scope: 'openid profile offline_access User.Read Calendars.Read',
            status: 'connected',
            refresh_token_encrypted: encrypt('refresh-token', encryptionKey()),
            access_token_encrypted: accessEncrypted,
            access_token_expires_at: new Date(Date.now() + 600_000),
          },
        ]);
      }
      if (sql.includes('SELECT delta_link')) {
        return result([{ delta_link: null }]);
      }
      if (sql.includes('SELECT payload')) {
        if (params?.[1] === 'outlook_event:cal-1:master-db') {
          return result([
            {
              payload: {
                remoteEventId: 'master-db',
                title: 'DB Master',
                description: 'DB body',
                location: 'DB Room',
                organizerName: 'DB Owner',
                organizerEmail: 'db@example.com',
                sensitivity: 'normal',
                showAs: 'busy',
                type: 'seriesMaster',
                webLink: 'https://db.example',
              },
            },
          ]);
        }
        return result([]);
      }
      if (sql.includes('SELECT id::text') && sql.includes('FROM sync_objects')) {
        return result([]);
      }
      if (sql.includes('INSERT INTO sync_objects')) {
        const payload = JSON.parse(String(params?.[3])) as Record<string, unknown>;
        payloads.push({
          objectType: String(params?.[1]),
          uid: String(params?.[2]),
          payload,
        });
        return result([
          {
            id: `object-${payloads.length}`,
            server_version: 1,
            payload,
          },
        ]);
      }
      if (sql.includes('UPDATE sync_objects') && sql.includes('SET deleted_at')) {
        return result([]);
      }
      if (sql.includes('SELECT o.id::text')) {
        return result([]);
      }
      return result([]);
    });
    const { service } = makeService(database);

    await expect(service.syncNow(context, 'admin')).resolves.toMatchObject({
      ok: true,
      runId: 'run-recurring',
      status: 'succeeded',
      calendarCount: 1,
      eventUpserts: 4,
      eventDeletes: 0,
    });
    expect(payloads).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          uid: 'outlook_event:cal-1:occ-cached',
          payload: expect.objectContaining({
            title: 'Cached Master',
            description: 'Cached body',
            location: 'Cached Room',
            organizerEmail: 'cached@example.com',
            attendeeCount: 1,
            sensitivity: 'private',
            showAs: 'busy',
            webLink: 'https://cached.example',
            isAllDay: true,
          }),
        }),
        expect.objectContaining({
          uid: 'outlook_event:cal-1:occ-db',
          payload: expect.objectContaining({
            title: 'DB Master',
            description: 'DB body',
            location: 'DB Room',
            organizerName: 'DB Owner',
            organizerEmail: 'db@example.com',
            webLink: 'https://db.example',
          }),
        }),
        expect.objectContaining({
          uid: 'outlook_event:cal-1:occ-missing',
          payload: expect.objectContaining({
            title: '(No title)',
            organizerEmail: null,
          }),
        }),
      ]),
    );
    const succeededRun = database.query.mock.calls.find(
      ([sql, params]) =>
        String(sql).includes('UPDATE outlook_sync_runs') &&
        Array.isArray(params) &&
        params[0] === 'run-recurring',
    );
    const diagnostics = JSON.parse(String((succeededRun?.[1] as unknown[])[4]));
    expect(diagnostics.fieldStats).toMatchObject({
      totalEvents: 5,
      removedEvents: 1,
      privateEvents: 1,
      recurrenceFallbacks: 2,
      masterLookupFailures: 1,
    });
    expect(diagnostics.recurrenceFallbackSamples).toEqual([
      expect.objectContaining({
        id: 'occ-cached',
        mappedPayload: expect.objectContaining({
          title: 'Cached Master',
          location: 'Cached Room',
        }),
      }),
      expect.objectContaining({
        id: 'occ-db',
        mappedPayload: expect.objectContaining({
          title: 'DB Master',
          location: 'DB Room',
        }),
      }),
    ]);
  });

  it('loads a remote series master fallback and caches the fetched master', async () => {
    vi.mocked(global.fetch).mockResolvedValueOnce(
      jsonResponse(true, {
        id: 'master-remote',
        subject: 'Remote Master',
        bodyPreview: 'Remote body',
        location: { displayName: 'Remote Room' },
        organizer: { emailAddress: { name: 'Remote Owner', address: 'remote@example.com' } },
        attendees: [{ emailAddress: { address: 'guest@example.com' } }],
        sensitivity: 'normal',
        showAs: 'busy',
        webLink: 'https://remote.example',
      }) as never,
    );
    const database = makeDatabase((sql, params) => {
      if (sql.includes('SELECT payload')) {
        expect(params).toEqual([userId, 'outlook_event:cal-1:master-remote']);
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);
    const diagnostics = (service as any).createRunDiagnostics('admin');
    const cache = new Map();

    const merged = await (service as any).withSeriesMasterFallback(
      userId,
      'access-token',
      { id: 'cal-1', name: 'Work' },
      {
        id: 'occ-remote',
        type: 'occurrence',
        seriesMasterId: 'master-remote',
      },
      cache,
      diagnostics,
    );

    expect(merged).toEqual(
      expect.objectContaining({
        id: 'occ-remote',
        subject: 'Remote Master',
        bodyPreview: 'Remote body',
        location: { displayName: 'Remote Room' },
        organizer: { emailAddress: { name: 'Remote Owner', address: 'remote@example.com' } },
      }),
    );
    expect(cache.get('cal-1:master-remote')).toEqual(expect.objectContaining({ id: 'master-remote' }));
    expect(diagnostics.fieldStats.recurrenceFallbacks).toBe(1);
    expect(global.fetch).toHaveBeenCalledWith(
      'https://graph.microsoft.com/v1.0/me/calendars/cal-1/events/master-remote',
      expect.objectContaining({ method: 'GET' }),
    );
  });

  it('hydrates stored Outlook events from payload fallback fields', () => {
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);

    expect(
      (service as any).outlookEventFromPayload(
        {
          location: ' Stored Room ',
          summary: 'Summary title',
          description: 'Description body',
          organizerEmail: 'only-email@example.com',
          showAs: 'tentative',
          type: 'seriesMaster',
        },
        'fallback-master',
      ),
    ).toEqual({
      id: 'fallback-master',
      subject: 'Summary title',
      bodyPreview: 'Description body',
      location: { displayName: 'Stored Room' },
      organizer: {
        emailAddress: { address: 'only-email@example.com' },
      },
      sensitivity: undefined,
      showAs: 'tentative',
      type: 'seriesMaster',
      seriesMasterId: undefined,
      webLink: undefined,
    });
    expect(
      (service as any).outlookEventFromPayload(
        {
          remoteEventId: 'remote-1',
          subject: 'Subject title',
          bodyPreview: 'Preview body',
          organizerName: 'Name Only',
          sensitivity: 'private',
          seriesMasterId: 'master-1',
          webLink: 'https://stored.example',
        },
        'unused-fallback',
      ),
    ).toEqual(
      expect.objectContaining({
        id: 'remote-1',
        subject: 'Subject title',
        bodyPreview: 'Preview body',
        organizer: {
          emailAddress: { name: 'Name Only' },
        },
        sensitivity: 'private',
        seriesMasterId: 'master-1',
        webLink: 'https://stored.example',
      }),
    );
    expect((service as any).outlookEventFromPayload({}, 'empty-fallback')).toEqual({
      id: 'empty-fallback',
      subject: undefined,
      bodyPreview: undefined,
      location: undefined,
      organizer: undefined,
      sensitivity: undefined,
      showAs: undefined,
      type: undefined,
      seriesMasterId: undefined,
      webLink: undefined,
    });
  });

  it('returns recurring events unchanged when fallback is not applicable or lacks a master id', async () => {
    const database = makeDatabase(() => {
      throw new Error('database should not be queried for non-applicable recurrence fallback');
    });
    const { service } = makeService(database);
    const diagnostics = (service as any).createRunDiagnostics('admin');
    const noMasterIdEvent = {
      id: 'occ-no-master',
      type: 'occurrence',
      seriesMasterId: ' ',
    };
    const defensiveEvent = {
      id: 'occ-defensive',
      type: 'occurrence',
    };

    expect((service as any).needsSeriesMasterFallback(noMasterIdEvent)).toBe(false);

    const needsFallbackSpy = vi
      .spyOn(service as any, 'needsSeriesMasterFallback')
      .mockReturnValueOnce(true);
    await expect(
      (service as any).withSeriesMasterFallback(
        userId,
        'access-token',
        { id: 'cal-1' },
        defensiveEvent,
        new Map(),
        diagnostics,
      ),
    ).resolves.toBe(defensiveEvent);

    expect(needsFallbackSpy).toHaveBeenCalledWith(defensiveEvent);
    expect(database.query).not.toHaveBeenCalled();
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('requests series master fallback only when recurring event details are incomplete', () => {
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);
    const completeOccurrence = {
      id: 'occ-complete',
      type: 'occurrence',
      seriesMasterId: 'master-1',
      subject: 'Occurrence subject',
      bodyPreview: 'Occurrence preview',
      location: { displayName: 'Occurrence room' },
      organizer: { emailAddress: { address: 'owner@example.com' } },
    };

    expect((service as any).needsSeriesMasterFallback(completeOccurrence)).toBe(false);
    expect(
      (service as any).needsSeriesMasterFallback({
        ...completeOccurrence,
        subject: ' ',
      }),
    ).toBe(true);
    expect(
      (service as any).needsSeriesMasterFallback({
        ...completeOccurrence,
        location: { displayName: ' ' },
        locations: [],
      }),
    ).toBe(true);
    expect(
      (service as any).needsSeriesMasterFallback({
        ...completeOccurrence,
        bodyPreview: '',
      }),
    ).toBe(true);
    expect(
      (service as any).needsSeriesMasterFallback({
        ...completeOccurrence,
        organizer: {},
      }),
    ).toBe(true);
  });

  it('fills recurring occurrence fields from the master when occurrence values are blank', () => {
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);

    const merged = (service as any).mergeOccurrenceWithMaster(
      {
        id: 'occ-blank',
        subject: ' ',
        bodyPreview: '',
        body: { content: '' },
        location: { displayName: ' ' },
        locations: [],
        organizer: {},
        attendees: [],
        type: 'occurrence',
        seriesMasterId: 'master-1',
      },
      {
        id: 'master-1',
        subject: 'Master subject',
        bodyPreview: 'Master preview',
        body: { content: 'Master body' },
        location: { displayName: 'Master room' },
        locations: [{ displayName: 'Overflow room' }],
        organizer: { emailAddress: { name: 'Master Owner', address: 'owner@example.com' } },
        attendees: [{ emailAddress: { address: 'guest@example.com' } }],
        sensitivity: 'private',
        showAs: 'busy',
        webLink: 'https://master.example',
        isAllDay: true,
      },
    );

    expect(merged).toEqual(
      expect.objectContaining({
        id: 'occ-blank',
        subject: 'Master subject',
        bodyPreview: 'Master preview',
        body: { content: 'Master body' },
        location: { displayName: 'Master room' },
        locations: [{ displayName: 'Overflow room' }],
        organizer: { emailAddress: { name: 'Master Owner', address: 'owner@example.com' } },
        attendees: [{ emailAddress: { address: 'guest@example.com' } }],
        sensitivity: 'private',
        showAs: 'busy',
        webLink: 'https://master.example',
        isAllDay: true,
      }),
    );
  });

  it('preserves recurring occurrence fields when they are already present', () => {
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);

    const merged = (service as any).mergeOccurrenceWithMaster(
      {
        id: 'occ-complete',
        subject: 'Occurrence subject',
        bodyPreview: 'Occurrence preview',
        body: { content: 'Occurrence body' },
        location: { displayName: 'Occurrence room' },
        locations: [{ displayName: 'Occurrence overflow' }],
        organizer: { emailAddress: { name: 'Occurrence Owner', address: 'occ@example.com' } },
        attendees: [{ emailAddress: { address: 'occ-guest@example.com' } }],
        sensitivity: 'normal',
        showAs: 'free',
        webLink: 'https://occurrence.example',
        isAllDay: false,
        type: 'exception',
        seriesMasterId: 'master-1',
      },
      {
        id: 'master-1',
        subject: 'Master subject',
        bodyPreview: 'Master preview',
        body: { content: 'Master body' },
        location: { displayName: 'Master room' },
        locations: [{ displayName: 'Master overflow' }],
        organizer: { emailAddress: { name: 'Master Owner', address: 'master@example.com' } },
        attendees: [{ emailAddress: { address: 'master-guest@example.com' } }],
        sensitivity: 'private',
        showAs: 'busy',
        webLink: 'https://master.example',
        isAllDay: true,
      },
    );

    expect(merged).toEqual(
      expect.objectContaining({
        subject: 'Occurrence subject',
        bodyPreview: 'Occurrence preview',
        body: { content: 'Occurrence body' },
        location: { displayName: 'Occurrence room' },
        locations: [{ displayName: 'Occurrence overflow' }],
        organizer: { emailAddress: { name: 'Occurrence Owner', address: 'occ@example.com' } },
        attendees: [{ emailAddress: { address: 'occ-guest@example.com' } }],
        sensitivity: 'normal',
        showAs: 'free',
        webLink: 'https://occurrence.example',
        isAllDay: false,
      }),
    );
  });

  it('leaves recurring text fields undefined when neither occurrence nor master has values', () => {
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);

    const merged = (service as any).mergeOccurrenceWithMaster(
      {
        id: 'occ-empty-text',
        subject: ' ',
        bodyPreview: '',
        type: 'occurrence',
        seriesMasterId: 'master-empty-text',
      },
      {
        id: 'master-empty-text',
        subject: '',
        bodyPreview: ' ',
      },
    );

    expect(merged).toEqual(
      expect.objectContaining({
        id: 'occ-empty-text',
        subject: undefined,
        bodyPreview: undefined,
      }),
    );
  });

  it('defaults calendar and event payload fields and skips mappings for unchanged upserts', async () => {
    const database = makeDatabase(() => {
      throw new Error('database should not be queried when sync object upserts are mocked');
    });
    const { service } = makeService(database);
    const upsertSyncObject = vi
      .spyOn(service as any, 'upsertSyncObject')
      .mockResolvedValueOnce({ id: 'calendar-object', changed: false })
      .mockResolvedValueOnce(undefined);
    const upsertMapping = vi
      .spyOn(service as any, 'upsertMapping')
      .mockResolvedValue(undefined);

    await expect((service as any).upsertCalendarBook(userId, { id: 'cal-empty' })).resolves.toBe(
      false,
    );
    await expect(
      (service as any).upsertCalendarEvent(
        userId,
        { id: 'cal-empty' },
        { id: 'event-empty' },
      ),
    ).resolves.toBe(false);

    expect(upsertMapping).not.toHaveBeenCalled();
    expect(upsertSyncObject).toHaveBeenNthCalledWith(
      1,
      userId,
      'calendar_book',
      'outlook_calendar:cal-empty',
      expect.objectContaining({
        name: 'Outlook',
        colorHex: '#2563eb',
      }),
    );
    const eventPayload = upsertSyncObject.mock.calls[1][3] as Record<string, unknown>;
    expect(eventPayload).toEqual(
      expect.objectContaining({
        uid: 'outlook_event:cal-empty:event-empty',
        subject: '(No title)',
        title: '(No title)',
        summary: '(No title)',
        description: '',
        bodyPreview: null,
        location: '',
        dtstart: null,
        dtend: null,
        status: 'CONFIRMED',
        transp: 'OPAQUE',
        isBlock: true,
        isAllDay: false,
        sensitivity: null,
        showAs: null,
        type: null,
        seriesMasterId: null,
        organizerName: null,
        organizerEmail: null,
        attendeeCount: 0,
        calendarName: 'Outlook',
        colorHex: '#2563eb',
        webLink: null,
      }),
    );
  });

  it('treats missing upsert results as unchanged and preserves Z-suffixed event times', async () => {
    const database = makeDatabase(() => {
      throw new Error('database should not be queried when sync object upserts are mocked');
    });
    const { service } = makeService(database);
    const upsertSyncObject = vi
      .spyOn(service as any, 'upsertSyncObject')
      .mockResolvedValueOnce(undefined)
      .mockResolvedValueOnce({ id: 'event-object', changed: false });
    const upsertMapping = vi
      .spyOn(service as any, 'upsertMapping')
      .mockResolvedValue(undefined);

    await expect((service as any).upsertCalendarBook(userId, { id: 'cal-z' })).resolves.toBe(
      false,
    );
    await expect(
      (service as any).upsertCalendarEvent(
        userId,
        { id: 'cal-z', name: 'Z Calendar' },
        {
          id: 'event-z',
          subject: 'Z Event',
          start: { dateTime: '2026-02-01T10:00:00Z', timeZone: 'UTC' },
          end: { dateTime: '2026-02-01T11:00:00Z', timeZone: 'UTC' },
          showAs: 'free',
          isCancelled: true,
        },
      ),
    ).resolves.toBe(false);

    const eventPayload = upsertSyncObject.mock.calls[1][3] as Record<string, unknown>;
    expect(eventPayload).toEqual(
      expect.objectContaining({
        dtstart: '2026-02-01T10:00:00.000Z',
        dtend: '2026-02-01T11:00:00.000Z',
        status: 'CANCELLED',
        transp: 'TRANSPARENT',
        isBlock: false,
      }),
    );
    expect(upsertMapping).not.toHaveBeenCalled();
  });

  it('fails sync token access before decrypting when no secure encryption key is configured', async () => {
    delete process.env.FLOWPLANV2_ENCRYPTION_KEY;
    delete process.env.OUTLOOK_CONFIG_SECRET;
    delete process.env.AI_CONFIG_SECRET;
    process.env.DATABASE_URL = 'postgres://localhost/flowplantest';
    const database = makeDatabase((sql) => {
      if (sql.includes('INSERT INTO outlook_sync_runs') && sql.includes('RETURNING')) {
        return result([{ id: 'run-insecure-key' }]);
      }
      if (sql.includes('SELECT * FROM outlook_connections')) {
        return result([
          {
            user_id: userId,
            client_id: 'client-id',
            redirect_uri: 'https://redirect.test/callback',
            scope: 'openid profile offline_access User.Read Calendars.Read',
            status: 'connected',
            refresh_token_encrypted: 'not-decrypted-without-secure-key',
            access_token_encrypted: 'not-decrypted-without-secure-key',
            access_token_expires_at: new Date(Date.now() + 600_000),
          },
        ]);
      }
      if (sql.includes('UPDATE outlook_connections')) {
        return result([]);
      }
      if (sql.includes('UPDATE outlook_sync_runs')) {
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(service.syncNow(context, 'admin')).resolves.toMatchObject({
      ok: false,
      runId: 'run-insecure-key',
      status: 'failed',
      errorMessage: 'Encryption key not configured. Set FLOWPLANV2_ENCRYPTION_KEY in .env',
    });
    expect(global.fetch).not.toHaveBeenCalled();
  });

  it('samples default diagnostics for nameless calendars and sparse recurrence fallbacks', () => {
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);
    const diagnostics = (service as any).createRunDiagnostics('admin');

    (service as any).recordGraphEventDiagnostics(
      diagnostics,
      { id: 'cal-nameless' },
      {
        id: 'event-sparse',
        locations: [{ displayName: 'Room A' }, { displayName: 'Room B' }],
      },
    );
    (service as any).recordRecurrenceFallbackSample(
      diagnostics,
      { id: 'raw-sparse' },
      { id: 'merged-sparse', subject: 'Merged sparse' },
    );

    expect(diagnostics.graphEventSamples[0]).toEqual(
      expect.objectContaining({
        calendarId: 'cal-nameless',
        calendarName: 'Outlook',
        id: 'event-sparse',
        locations: [{ displayName: 'Room A' }, { displayName: 'Room B' }],
        mappedPayload: expect.objectContaining({
          title: '(No title)',
          location: 'Room A, Room B',
          attendeeCount: 0,
        }),
      }),
    );
    expect(diagnostics.recurrenceFallbackSamples[0]).toEqual(
      expect.objectContaining({
        id: 'raw-sparse',
        type: null,
        seriesMasterId: null,
        mappedPayload: expect.objectContaining({
          title: 'Merged sparse',
        }),
      }),
    );
  });

  it('caps graph event and recurrence diagnostics samples at fifty entries', () => {
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);
    const diagnostics = (service as any).createRunDiagnostics('admin');
    diagnostics.graphEventSamples = Array.from({ length: 50 }, (_, index) => ({ index }));
    diagnostics.recurrenceFallbackSamples = Array.from({ length: 50 }, (_, index) => ({ index }));

    (service as any).recordGraphEventDiagnostics(
      diagnostics,
      { id: 'cal-1', name: 'Work' },
      { id: 'event-private', sensitivity: 'private' },
    );
    (service as any).recordRecurrenceFallbackSample(
      diagnostics,
      { id: 'raw-occurrence', type: 'occurrence', seriesMasterId: 'master-1' },
      { id: 'merged-occurrence', subject: 'Merged title' },
    );

    expect(diagnostics.graphEventSamples).toHaveLength(50);
    expect(diagnostics.recurrenceFallbackSamples).toHaveLength(50);
    expect(diagnostics.fieldStats).toMatchObject({
      totalEvents: 1,
      privateEvents: 1,
    });
  });

  it('logs Graph event snapshots only when debug event logging is enabled', () => {
    process.env.FLOWPLANV2_OUTLOOK_DEBUG_EVENTS = '1';
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => undefined);

    (service as any).logGraphEventSnapshot(
      { id: 'cal-1' },
      {
        id: 'event-1',
        subject: 'Debug me',
        bodyPreview: 'preview',
        organizer: { emailAddress: { address: 'debug@example.com' } },
        attendees: [{ emailAddress: { address: 'guest@example.com' } }],
        showAs: 'busy',
        sensitivity: 'normal',
        type: 'singleInstance',
      },
    );

    expect(logSpy).toHaveBeenCalledWith(
      '[outlook.graph.event]',
      expect.stringContaining('"calendarId":"cal-1"'),
    );
  });

  it('logs sparse Graph event snapshots with null and default debug fields', () => {
    process.env.FLOWPLANV2_OUTLOOK_DEBUG_EVENTS = '1';
    const database = makeDatabase(() => result([]));
    const { service } = makeService(database);
    const logSpy = vi.spyOn(console, 'log').mockImplementation(() => undefined);

    (service as any).logGraphEventSnapshot({ id: 'cal-1' }, { id: 'event-sparse' });

    const payload = JSON.parse(String(logSpy.mock.calls[0][1]));
    expect(payload).toEqual(
      expect.objectContaining({
        calendarId: 'cal-1',
        id: 'event-sparse',
        subject: null,
        attendeeCount: 0,
        isAllDay: null,
        sensitivity: null,
        showAs: null,
        type: null,
      }),
    );
  });

  it('prepares default create-event write drafts using payload fallback values', async () => {
    const draft = {
      id: 'draft-create',
      title: 'Outlook write: create_event',
      risk_level: 'normal',
      status: 'pending_review',
    };
    const database = makeDatabase((sql, params) => {
      if (sql.includes('INSERT INTO ai_operation_drafts')) {
        expect(params).toEqual([
          userId,
          'Outlook write: create_event',
          'Proposed Outlook create_event operation',
          'outlook_create_event',
          'normal',
          JSON.stringify({ action: 'create_event', reason: null, source: 'outlook_write' }),
          JSON.stringify({ subject: 'Planning' }),
        ]);
        return result([draft]);
      }
      if (sql.includes('INSERT INTO audit_logs')) {
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(
      service.prepareWrite({ payload: { subject: 'Planning' } }, context),
    ).resolves.toEqual({ ok: true, draft });
  });

  it('prepares write drafts with empty proposed payloads and null audit draft ids', async () => {
    const draft = {
      id: null,
      title: 'Outlook write: update_event',
      risk_level: 'normal',
      status: 'pending_review',
    };
    const database = makeDatabase((sql, params) => {
      if (sql.includes('INSERT INTO ai_operation_drafts')) {
        expect(params).toEqual([
          userId,
          'Outlook write: update_event',
          'Proposed Outlook update_event operation',
          'outlook_update_event',
          'normal',
          JSON.stringify({ action: 'update_event', reason: null, source: 'outlook_write' }),
          JSON.stringify({}),
        ]);
        return result([draft]);
      }
      if (sql.includes('INSERT INTO audit_logs')) {
        expect(params).toEqual([
          userId,
          deviceId,
          'outlook.write.prepared',
          null,
          JSON.stringify({ draftId: null, action: 'update_event' }),
        ]);
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(service.prepareWrite({ action: 'update_event' }, context)).resolves.toEqual({
      ok: true,
      draft,
    });
  });

  it('rejects write confirmation when the pending draft cannot be found', async () => {
    const database = makeDatabase((sql) => {
      if (sql.includes('SELECT * FROM ai_operation_drafts')) {
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(
      service.confirmWrite('missing-draft', { confirmationPhrase: 'CONFIRM' }, context),
    ).rejects.toThrow('draft not found or already processed');
    expect(database.query).not.toHaveBeenCalledWith(
      expect.stringContaining('UPDATE ai_operation_drafts'),
      expect.any(Array),
    );
  });

  it('rejects write confirmation when Outlook is not connected', async () => {
    const database = makeDatabase((sql) => {
      if (sql.includes('SELECT * FROM ai_operation_drafts')) {
        return result([{ id: 'draft-1', proposed_action: 'outlook_update_event' }]);
      }
      if (sql.includes('COALESCE(sync_mode')) {
        return result([]);
      }
      throw new Error(`Unexpected query: ${sql}`);
    });
    const { service } = makeService(database);

    await expect(
      service.confirmWrite('draft-1', { confirmationPhrase: 'CONFIRM' }, context),
    ).rejects.toThrow('Outlook is not connected');
    expect(database.query).not.toHaveBeenCalledWith(
      expect.stringContaining('UPDATE ai_operation_drafts'),
      expect.any(Array),
    );
  });
});
