import { describe, expect, it, vi } from 'vitest';
import { ClientService } from './client.service';

const context = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};

function databaseMock(rows: Record<string, unknown[]> = {}) {
  const query = vi.fn(async (sql: string, params?: unknown[]) => {
    if (sql.includes('UPDATE devices SET last_seen_at')) {
      return { rows: rows.touchedDevices ?? [] };
    }
    if (sql.includes('SELECT id::text AS id, display_name')) {
      return { rows: rows.user ?? [] };
    }
    if (sql.includes('FROM devices WHERE user_id = $1 AND id = $2')) {
      return { rows: rows.device ?? [] };
    }
    if (sql.includes('LEFT JOIN sync_cursors')) {
      return { rows: rows.syncSummary ?? [] };
    }
    if (sql.includes('FROM sync_conflicts') && sql.includes('FROM sync_mutations')) {
      return { rows: rows.pendingActions ?? [] };
    }
    if (sql.includes('FROM admin_remote_configs') && sql.includes('ORDER BY scope')) {
      return {
        rows: rows.settings ?? [
          { key: 'work.hours', scope: 'user.preference', value: { start: '09:00' }, version: 3 },
          { key: 'secret', scope: 'ai.provider', value: { masked: true }, isSensitive: true, version: 2 },
        ],
      };
    }
    if (sql.includes('MAX(version)')) {
      return { rows: rows.settingsSummary ?? [{ version: '3', updatedAt: '2026-01-01T00:00:00Z' }] };
    }
    if (sql.includes('FROM sync_objects') && sql.includes('object_type = $2')) {
      return { rows: rows.conflicts ?? [] };
    }
    if (sql.includes('FROM client_import_sessions') && sql.includes('FOR UPDATE')) {
      return { rows: rows.importSession ?? [] };
    }
    if (sql.includes('FROM client_import_sessions')) {
      return { rows: rows.importStatus ?? [] };
    }
    if (sql.includes('INSERT INTO admin_remote_configs')) {
      return { rows: rows.upsertedSettings ?? [{ key: params?.[1], scope: params?.[3], isSensitive: false, version: 1 }] };
    }
    if (sql.includes('INSERT INTO client_import_sessions')) {
      return { rows: rows.insertedImports ?? [{ id: 'import-1', status: 'needs_confirmation' }] };
    }
    if (sql.includes('INSERT INTO sync_objects')) {
      return { rows: rows.insertedObjects ?? [{ id: 'object-1', server_version: 1, payload: { uid: 'task-1' } }] };
    }
    return { rows: [] };
  });
  return {
    query,
    transaction: vi.fn(async (callback: (client: { query: typeof query }) => unknown) => callback({ query })),
  };
}

function callsContaining(query: ReturnType<typeof vi.fn>, snippet: string) {
  return query.mock.calls.filter(([sql]) => String(sql).includes(snippet));
}

function createService(database = databaseMock()) {
  const devices = {
    ensureUser: vi.fn(async (userId: string) => userId),
    ensureDevice: vi.fn(async () => context.deviceId),
  };
  return {
    service: new ClientService(database as never, devices as never),
    database,
    devices,
  };
}

describe('ClientService', () => {
  it('bootstraps ensured identity with persisted user/device rows and sync health', async () => {
    const database = databaseMock({
      user: [
        {
          id: context.userId,
          displayName: 'FlowPlan User',
          updatedAt: '2026-01-02T00:00:00Z',
        },
      ],
      device: [
        {
          id: context.deviceId,
          deviceName: 'Workstation',
          platform: 'windows',
          clientDeviceId: 'desktop-local',
          lastSeenAt: '2026-01-02T00:01:00Z',
        },
      ],
      settingsSummary: [{ version: '9', updatedAt: '2026-01-02T00:02:00Z' }],
      syncSummary: [{ pullCursor: 4, latestChangeId: 10, backlog: '6' }],
      pendingActions: [
        {
          open_conflicts: '2',
          failed_mutations: 1,
          pending_ai_drafts: '3',
          failed_pushes: 4,
        },
      ],
    });
    const { service, devices } = createService(database);

    const result = await service.bootstrap(context);

    expect(devices.ensureUser).toHaveBeenCalledWith(context.userId);
    expect(devices.ensureDevice).toHaveBeenCalledWith(context);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE devices SET last_seen_at'),
      [context.userId, context.deviceId],
    );
    expect(result).toMatchObject({
      user: { id: context.userId, displayName: 'FlowPlan User' },
      device: { id: context.deviceId, deviceName: 'Workstation', platform: 'windows' },
      settingsVersion: 9,
      settingsUpdatedAt: '2026-01-02T00:02:00Z',
      syncCursor: '4',
      featureFlags: {
        serverFirstData: true,
        remoteSettings: true,
        initialImport: true,
        adminConsole: true,
      },
      serverHealth: {
        ok: true,
        database: 'ok',
        syncBacklog: 6,
        failedMutations: 1,
        openConflicts: 2,
      },
      pendingActions: {
        openConflicts: 2,
        failedMutations: 1,
        pendingAiDrafts: 3,
        failedPushes: 4,
      },
    });
    expect(Number.isNaN(Date.parse(result.serverTime))).toBe(false);
  });

  it('bootstraps fallback identity and zero summaries when optional rows are absent', async () => {
    const { service } = createService(
      databaseMock({
        user: [],
        device: [],
        settingsSummary: [],
        syncSummary: [],
        pendingActions: [],
      }),
    );

    const result = await service.bootstrap(context);

    expect(result).toMatchObject({
      user: { id: context.userId, displayName: 'FlowPlanV2 User' },
      device: { id: context.deviceId },
      settingsVersion: 0,
      settingsUpdatedAt: null,
      syncCursor: '0',
      serverHealth: {
        syncBacklog: 0,
        failedMutations: 0,
        openConflicts: 0,
      },
      pendingActions: {
        openConflicts: 0,
        failedMutations: 0,
        pendingAiDrafts: 0,
        failedPushes: 0,
      },
    });
  });

  it('returns settings with summary and policy metadata', async () => {
    const { service } = createService();

    const result = await service.settings(context);

    expect(result).toMatchObject({
      version: 3,
      updatedAt: '2026-01-01T00:00:00Z',
      settings: [
        { key: 'work.hours', value: { start: '09:00' } },
        { key: 'secret', value: { masked: true } },
      ],
      policy: {
        serverManagedScopes: expect.arrayContaining(['user.preference', 'sync.policy']),
        deviceLocalKeyPrefixes: expect.arrayContaining(['server.api.base_url', 'auth.access_token']),
      },
    });
  });

  it('builds effective settings keyed by config key', async () => {
    const { service } = createService();

    const result = await service.effectiveSettings(context);

    expect(result).toMatchObject({
      ok: true,
      mode: 'server_fact_source',
      version: 3,
      effective: {
        'work.hours': { start: '09:00' },
        secret: { masked: true },
      },
      deviceLocalOnly: expect.arrayContaining(['server.api.base_url', 'device.window']),
    });
  });

  it('exposes the remote settings policy contract', () => {
    const { service } = createService();

    expect(service.settingsPolicy()).toEqual({
      serverManagedScopes: [
        'user.preference',
        'sync.policy',
        'ai.provider',
        'file.provider',
        'report.push',
        'scheduler.policy',
        'activity.rules',
      ],
      deviceLocalKeyPrefixes: [
        'server.api.base_url',
        'auth.access_token',
        'auth.refresh_token',
        'device.identity.id',
        'window.',
        'tray.',
        'startup.',
        'permission.',
        'sensor.',
        'download.',
        'cache.',
        'kopia.local.',
        'file.local.',
      ],
      note: expect.any(String),
    });
  });

  it('upserts settings with supported scopes and audit metadata', async () => {
    const database = databaseMock({
      upsertedSettings: [{ key: 'sync.window', scope: 'sync.policy', isSensitive: true, version: 2 }],
    });
    const { service } = createService(database);

    await expect(
      service.updateSetting(
        'sync.window',
        { value: { minutes: 15 }, scope: 'sync.policy', isSensitive: true, description: 'Sync cadence' },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      setting: { key: 'sync.window', scope: 'sync.policy', isSensitive: true, version: 2 },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO admin_remote_configs'),
      [
        context.userId,
        'sync.window',
        JSON.stringify({ minutes: 15 }),
        'sync.policy',
        true,
        'Sync cadence',
      ],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'client.remote_setting.update', 'sync.window']),
    );
  });

  it('defaults unsupported setting updates to user preference and sanitized object values', async () => {
    const database = databaseMock({
      upsertedSettings: [{ key: 'custom.setting', scope: 'user.preference', isSensitive: false, version: 1 }],
    });
    const { service } = createService(database);

    await expect(
      service.updateSetting(
        'custom.setting',
        { configValue: 'not-a-record', scope: 'device.local', description: '   ' },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      setting: { key: 'custom.setting', scope: 'user.preference', isSensitive: false, version: 1 },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO admin_remote_configs'),
      [context.userId, 'custom.setting', JSON.stringify({}), 'user.preference', false, null],
    );
    const auditCall = callsContaining(database.query, 'INSERT INTO audit_logs')[0];
    expect(JSON.parse(String((auditCall[1] as unknown[])[4]))).toEqual({
      key: 'custom.setting',
      scope: 'user.preference',
      isSensitive: false,
    });
  });

  it('prepares local snapshot imports with normalized objects, settings and conflict summary', async () => {
    const database = databaseMock({
      conflicts: [{ id: 'server-object-1', serverVersion: 5, updatedAt: '2026-01-01T00:00:00Z' }],
      insertedImports: [{ id: 'import-1', status: 'needs_confirmation' }],
    });
    const { service } = createService(database);

    const result = await service.createLocalSnapshotImport(
      {
        importUid: 'import-uid-1',
        snapshot: {
          objects: {
            task_items: [
              { id: 'local-task-1', task_uid: 'task-1', title: 'Task one' },
              { id: 'fallback-id' },
            ],
          },
          settings: [
            { key: 'work.hours', value: { start: '09:00' } },
            { setting_key: 'server.api.base_url', setting_value: 'http://localhost' },
            { key: '' },
          ],
        },
      },
      context,
    );

    expect(result).toEqual({
      importId: 'import-1',
      status: 'needs_confirmation',
      summary: {
        objectCount: 2,
        settingCount: 2,
        conflictCount: 2,
        conflicts: [
          {
            objectType: 'task_item',
            uid: 'task-1',
            localId: 'local-task-1',
            server: { id: 'server-object-1', serverVersion: 5, updatedAt: '2026-01-01T00:00:00Z' },
          },
          {
            objectType: 'task_item',
            uid: 'task_item:fallback-id',
            localId: 'fallback-id',
            server: { id: 'server-object-1', serverVersion: 5, updatedAt: '2026-01-01T00:00:00Z' },
          },
        ],
        tables: { task_items: 2 },
      },
      requiresConfirmation: true,
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO client_import_sessions'),
      [
        context.userId,
        context.deviceId,
        'import-uid-1',
        expect.stringContaining('"objectCount":2'),
        expect.stringContaining('"task_items"'),
      ],
    );
  });

  it('prepares body-level snapshot arrays, filters invalid entries, and generates missing import uids', async () => {
    const database = databaseMock({
      insertedImports: [{ id: 'generated-import', status: 'needs_confirmation' }],
    });
    const { service } = createService(database);

    const result = await service.createLocalSnapshotImport(
      {
        objects: [
          {
            id: 77,
            object_type: 'calendar_event',
            event_uid: 'event-1',
            title: 'Planning',
            deletedAt: '2026-01-03T00:00:00Z',
          },
          { id: 'missing-type' },
          'not-an-object',
        ],
        settings: [{ setting_key: '   ', setting_value: 'ignored' }, 'not-a-setting'],
      },
      context,
    );

    expect(result).toMatchObject({
      importId: 'generated-import',
      status: 'needs_confirmation',
      summary: {
        objectCount: 1,
        settingCount: 0,
        conflictCount: 0,
        conflicts: [],
        tables: {},
      },
      requiresConfirmation: true,
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('FROM sync_objects'),
      [context.userId, 'calendar_event', 'event-1'],
    );
    const importCall = callsContaining(database.query, 'INSERT INTO client_import_sessions')[0];
    const importParams = importCall[1] as unknown[];
    expect(importParams[2]).toEqual(expect.stringMatching(/^[0-9a-f-]{36}$/));
    expect(JSON.parse(String(importParams[3]))).toMatchObject({
      objectCount: 1,
      settingCount: 0,
      tables: {},
    });
    expect(JSON.parse(String(importParams[4]))).toMatchObject({
      objects: expect.any(Array),
      settings: expect.any(Array),
    });
  });

  it('returns import status or not_found fallback', async () => {
    const { service } = createService(databaseMock({ importStatus: [] }));

    await expect(service.importStatus('missing', context)).resolves.toEqual({
      id: 'missing',
      status: 'not_found',
    });
  });

  it('returns persisted import status rows when found', async () => {
    const row = {
      id: 'import-1',
      status: 'completed',
      summary: { objectCount: 1 },
      result: { inserted: 1 },
      errorMessage: null,
      createdAt: '2026-01-04T00:00:00Z',
      updatedAt: '2026-01-04T00:01:00Z',
      confirmedAt: '2026-01-04T00:01:00Z',
      cancelledAt: null,
    };
    const { service } = createService(databaseMock({ importStatus: [row] }));

    await expect(service.importStatus('import-1', context)).resolves.toEqual(row);
  });

  it('short-circuits confirmImport for missing, completed, and cancelled sessions', async () => {
    const missing = createService(databaseMock({ importSession: [] })).service;
    await expect(missing.confirmImport('missing', context)).resolves.toEqual({
      ok: false,
      status: 'not_found',
    });

    const completed = createService(databaseMock({ importSession: [{ snapshot: {}, status: 'completed' }] })).service;
    await expect(completed.confirmImport('import-1', context)).resolves.toEqual({
      ok: true,
      status: 'completed',
      alreadyCompleted: true,
    });

    const cancelled = createService(databaseMock({ importSession: [{ snapshot: {}, status: 'cancelled' }] })).service;
    await expect(cancelled.confirmImport('import-1', context)).resolves.toEqual({
      ok: false,
      status: 'cancelled',
    });
  });

  it('confirms pending imports with object insert, update, skip, settings import, and audit result', async () => {
    const snapshot = {
      objects: [
        { id: 'local-update', objectType: 'task_item', uid: 'update-1', title: 'Updated' },
        { id: 'local-skip-update', objectType: 'task_item', uid: 'skip-update', title: 'Skipped update' },
        {
          id: 'local-delete',
          objectType: 'file_item',
          uid: 'delete-1',
          title: 'Deleted',
          deleted_at: '2026-01-05T00:00:00Z',
        },
        { id: 'local-skip-insert', objectType: 'diary_entry', uid: 'skip-insert', title: 'Skipped insert' },
      ],
      settings: [
        { key: 'work.hours', value: { start: '10:00' } },
        { setting_key: 'server.api.base_url', setting_value: 'http://localhost:3000' },
      ],
    };
    const existingByUid = new Map<string, unknown[]>([
      ['update-1', [{ id: 'server-update', server_version: 5 }]],
      ['skip-update', [{ id: 'server-skip-update', server_version: 2 }]],
    ]);
    const updatedByUid = new Map<string, unknown[]>([
      ['update-1', [{ id: 'server-update', server_version: 6, payload: { uid: 'update-1', title: 'Updated on server' } }]],
      ['skip-update', []],
    ]);
    const insertedByUid = new Map<string, unknown[]>([
      ['delete-1', [{ id: 'server-delete', server_version: 1, payload: { uid: 'delete-1', title: 'Deleted row' } }]],
      ['skip-insert', []],
    ]);
    const query = vi.fn(async (sql: string, params?: unknown[]) => {
      const uid = String(params?.[2] ?? '');
      if (sql.includes('FROM client_import_sessions') && sql.includes('FOR UPDATE')) {
        return { rows: [{ snapshot, status: 'needs_confirmation' }] };
      }
      if (sql.includes('SELECT id::text, server_version') && sql.includes('FROM sync_objects')) {
        return { rows: existingByUid.get(uid) ?? [] };
      }
      if (sql.includes('UPDATE sync_objects')) {
        return { rows: updatedByUid.get(uid) ?? [] };
      }
      if (sql.includes('INSERT INTO sync_objects')) {
        return { rows: insertedByUid.get(uid) ?? [] };
      }
      return { rows: [] };
    });
    const database = {
      query,
      transaction: vi.fn(async (callback: (client: { query: typeof query }) => unknown) => callback({ query })),
    };
    const { service } = createService(database);

    const result = await service.confirmImport('import-1', context);

    expect(result).toMatchObject({
      ok: true,
      status: 'completed',
      result: {
        inserted: 1,
        updated: 1,
        skipped: 2,
        importedSettings: 2,
      },
    });
    expect(Number.isNaN(Date.parse((result as { result: { completedAt: string } }).result.completedAt))).toBe(false);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'importing'"),
      [context.userId, 'import-1'],
    );

    const updateObjectCall = callsContaining(query, 'UPDATE sync_objects')[0];
    expect(updateObjectCall[1]).toEqual([
      context.userId,
      'task_item',
      'update-1',
      JSON.stringify({ id: 'local-update', objectType: 'task_item', uid: 'update-1', title: 'Updated' }),
      context.deviceId,
    ]);
    const insertObjectCalls = callsContaining(query, 'INSERT INTO sync_objects');
    expect(insertObjectCalls[0][1]).toEqual([
      context.userId,
      'file_item',
      'delete-1',
      JSON.stringify({
        id: 'local-delete',
        objectType: 'file_item',
        uid: 'delete-1',
        title: 'Deleted',
        deleted_at: '2026-01-05T00:00:00Z',
      }),
      '2026-01-05T00:00:00Z',
      context.deviceId,
    ]);
    expect(insertObjectCalls[1][1]).toEqual([
      context.userId,
      'diary_entry',
      'skip-insert',
      JSON.stringify({
        id: 'local-skip-insert',
        objectType: 'diary_entry',
        uid: 'skip-insert',
        title: 'Skipped insert',
      }),
      null,
      context.deviceId,
    ]);

    const syncChangeCalls = callsContaining(query, 'INSERT INTO sync_changes');
    expect(syncChangeCalls).toHaveLength(2);
    expect(syncChangeCalls[0][1]).toEqual([
      context.userId,
      context.deviceId,
      'server-update',
      'task_item',
      'upsert',
      6,
      JSON.stringify({ uid: 'update-1', title: 'Updated on server' }),
    ]);
    expect(syncChangeCalls[1][1]).toEqual([
      context.userId,
      context.deviceId,
      'server-delete',
      'file_item',
      'delete',
      1,
      JSON.stringify({ uid: 'delete-1', title: 'Deleted row' }),
    ]);

    const importedSettings = callsContaining(query, 'INSERT INTO admin_remote_configs');
    expect(importedSettings).toHaveLength(1);
    expect(importedSettings[0][1]).toEqual([
      context.userId,
      'work.hours',
      JSON.stringify({ value: { start: '10:00' } }),
    ]);

    const completeCall = query.mock.calls.find(([sql]) => String(sql).includes("SET status = 'completed'"));
    const completeResult = JSON.parse(String(((completeCall as unknown[])[1] as unknown[])[2]));
    expect(completeResult).toMatchObject({
      inserted: 1,
      updated: 1,
      skipped: 2,
      importedSettings: 2,
    });
    const auditCall = callsContaining(query, 'INSERT INTO audit_logs')[0];
    expect((auditCall[1] as unknown[]).slice(0, 4)).toEqual([
      context.userId,
      context.deviceId,
      'client.import.confirm',
      'import-1',
    ]);
    expect(JSON.parse(String((auditCall[1] as unknown[])[4]))).toMatchObject({
      importId: 'import-1',
      inserted: 1,
      updated: 1,
      skipped: 2,
      importedSettings: 2,
    });
  });

  it('imports table-shaped snapshot objects while ignoring non-array tables and non-array settings', async () => {
    const snapshot = {
      objects: {
        ignored_table: { id: 'not-an-array' },
        actual_activity_logs: [{ id: 42, title: 'Focus block' }],
        custom_records: [{ title: 'missing uid and id' }],
      },
      settings: { work: 'hours' },
    };
    const query = vi.fn(async (sql: string, params?: unknown[]) => {
      if (sql.includes('FROM client_import_sessions') && sql.includes('FOR UPDATE')) {
        return { rows: [{ snapshot, status: 'needs_confirmation' }] };
      }
      if (sql.includes('SELECT id::text, server_version') && sql.includes('FROM sync_objects')) {
        return { rows: [] };
      }
      if (sql.includes('INSERT INTO sync_objects')) {
        return {
          rows: [
            {
              id: 'server-actual',
              server_version: 1,
              payload: JSON.parse(String(params?.[3])),
            },
          ],
        };
      }
      return { rows: [] };
    });
    const database = {
      query,
      transaction: vi.fn(async (callback: (client: { query: typeof query }) => unknown) => callback({ query })),
    };
    const { service } = createService(database);

    await expect(service.confirmImport('import-table', context)).resolves.toMatchObject({
      ok: true,
      status: 'completed',
      result: {
        inserted: 1,
        updated: 0,
        skipped: 0,
        importedSettings: 0,
      },
    });

    const insertObjectCall = callsContaining(query, 'INSERT INTO sync_objects')[0];
    expect(insertObjectCall[1]).toEqual([
      context.userId,
      'actual_activity_log',
      'actual_activity_log:42',
      JSON.stringify({ id: 42, title: 'Focus block', uid: 'actual_activity_log:42' }),
      null,
      context.deviceId,
    ]);
    expect(callsContaining(query, 'INSERT INTO admin_remote_configs')).toHaveLength(0);
  });

  it('cancels pending imports with an audit reason', async () => {
    const database = databaseMock();
    const { service } = createService(database);

    await expect(service.cancelImport('import-1', { reason: 'duplicate' }, context)).resolves.toEqual({
      ok: true,
      status: 'cancelled',
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE client_import_sessions'),
      [context.userId, 'import-1', 'duplicate'],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'client.import.cancel', 'import-1']),
    );
  });

  it('cancels imports with blank reasons cleaned to null', async () => {
    const database = databaseMock();
    const { service } = createService(database);

    await expect(service.cancelImport('import-1', { reason: '   ' }, context)).resolves.toEqual({
      ok: true,
      status: 'cancelled',
    });

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE client_import_sessions'),
      [context.userId, 'import-1', null],
    );
    const auditCall = callsContaining(database.query, 'INSERT INTO audit_logs')[0];
    expect(JSON.parse(String((auditCall[1] as unknown[])[4]))).toEqual({
      importId: 'import-1',
      reason: null,
    });
  });

  it('normalizes snapshot helpers for table objects, fallback ids, settings aliases and table counts', async () => {
    const { service } = createService();
    const internal = service as never as {
      extractSnapshotObjects: (snapshot: Record<string, unknown>) => Array<{
        objectType: string;
        uid: string;
        localId: string;
        payload: Record<string, unknown>;
      }>;
      extractSettings: (snapshot: Record<string, unknown>) => Array<{ key: string; value: unknown }>;
      snapshotTableCounts: (snapshot: Record<string, unknown>) => Record<string, number>;
    };

    expect(internal.extractSnapshotObjects({ objects: 'not-a-record' })).toEqual([]);
    expect(
      internal.extractSnapshotObjects({
        objects: {
          task_items: [
            { id: 'task-row-1', title: 'Fallback uid task' },
            { uid: 'explicit-task', id: 'task-row-2', title: 'Explicit uid task' },
            { objectType: 'task_item', uid: 'uid-without-id', title: 'No local id' },
          ],
          custom_table: [{ id: 42, title: 'Custom fallback type' }],
          ignored_table: { id: 'not-array' },
        },
      }),
    ).toEqual([
      {
        objectType: 'task_item',
        uid: 'task_item:task-row-1',
        localId: 'task-row-1',
        payload: { id: 'task-row-1', title: 'Fallback uid task', uid: 'task_item:task-row-1' },
        deletedAt: null,
        updatedAt: null,
      },
      {
        objectType: 'task_item',
        uid: 'explicit-task',
        localId: 'task-row-2',
        payload: { uid: 'explicit-task', id: 'task-row-2', title: 'Explicit uid task' },
        deletedAt: null,
        updatedAt: null,
      },
      {
        objectType: 'task_item',
        uid: 'uid-without-id',
        localId: 'uid-without-id',
        payload: { objectType: 'task_item', uid: 'uid-without-id', title: 'No local id' },
        deletedAt: null,
        updatedAt: null,
      },
      {
        objectType: 'custom_table',
        uid: 'custom_table:42',
        localId: '42',
        payload: { id: 42, title: 'Custom fallback type', uid: 'custom_table:42' },
        deletedAt: null,
        updatedAt: null,
      },
    ]);

    expect(
      internal.extractSettings({
        settings: [
          { setting_key: 'work.hours', setting_value: { start: '08:00' } },
          { key: 'theme', value: 'dark' },
          { key: '   ', value: 'ignored' },
          { value: 'missing-key' },
          'not-a-record',
        ],
      }),
    ).toEqual([
      { key: 'work.hours', value: { start: '08:00' } },
      { key: 'theme', value: 'dark' },
    ]);

    expect(
      internal.snapshotTableCounts({
        objects: {
          task_items: [{ id: 1 }, { id: 2 }],
          ignored_table: { id: 'not-array' },
        },
      }),
    ).toEqual({ task_items: 2, ignored_table: 0 });
  });

  it('records sync changes with empty object payloads when no payload is supplied', async () => {
    const database = databaseMock();
    const { service } = createService(database);
    const internal = service as never as {
      recordChange: (
        client: { query: typeof database.query },
        userId: string,
        deviceId: string,
        serverObjectId: string,
        objectType: string,
        action: 'upsert' | 'delete',
        serverVersion: number,
        payload?: Record<string, unknown> | null,
      ) => Promise<unknown>;
    };

    await internal.recordChange(
      { query: database.query },
      context.userId,
      context.deviceId,
      'server-object-1',
      'task_item',
      'upsert',
      7,
      null,
    );

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO sync_changes'),
      [
        context.userId,
        context.deviceId,
        'server-object-1',
        'task_item',
        'upsert',
        7,
        '{}',
      ],
    );
  });
});
