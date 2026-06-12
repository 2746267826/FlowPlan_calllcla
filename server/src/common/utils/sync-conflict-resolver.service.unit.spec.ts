import { describe, expect, it, vi } from 'vitest';
import { SyncService } from '../../sync/sync.service';
import type { DatabaseService, TransactionClient } from '../../database/database.service';
import type { DevicesService } from '../../devices/devices.service';

type QueryCall = [string, unknown[] | undefined];

const conflictFields = [
  { field: 'title', base: 'Old', local: 'Local', server: 'Server' },
  { field: 'done', base: false, local: true, server: false },
];

const openConflict = {
  server_object_id: 'object-1',
  object_type: 'task_item',
  server_version: 7,
  fields: conflictFields,
};

const updatedObject = {
  id: 'object-1',
  uid: 'uid-1',
  payload: { title: 'Local', done: true },
  deleted_at: null,
  server_version: 8,
};

function queryResult(rows: unknown[]) {
  return { rows };
}

function normalize(sql: unknown) {
  return String(sql).replace(/\s+/g, ' ');
}

function callsContaining(query: ReturnType<typeof vi.fn>, snippet: string): QueryCall[] {
  return query.mock.calls.filter(([sql]) => normalize(sql).includes(snippet)) as QueryCall[];
}

function firstCall(query: ReturnType<typeof vi.fn>, snippet: string): QueryCall {
  const call = callsContaining(query, snippet)[0];
  if (!call) {
    throw new Error(`Expected query containing ${snippet}`);
  }
  return call;
}

function makeService(options: {
  conflict?: typeof openConflict | null;
  updatedRows?: unknown[];
  createdRows?: unknown[];
} = {}) {
  const conflict = options.conflict === undefined ? openConflict : options.conflict;
  const client = {
    query: vi.fn(async (sql: string) => {
      const text = normalize(sql);
      if (text.includes('FROM sync_conflicts')) {
        return queryResult(conflict ? [conflict] : []);
      }
      if (text.includes('UPDATE sync_objects')) {
        return queryResult(options.updatedRows ?? [updatedObject]);
      }
      if (text.includes('INSERT INTO sync_objects')) {
        return queryResult(
          options.createdRows ?? [
            {
              id: 'object-copy-1',
              uid: 'uid-copy',
              payload: { title: 'Copy' },
              deleted_at: null,
              server_version: 1,
            },
          ],
        );
      }
      return queryResult([]);
    }),
  };
  const database = {
    transaction: vi.fn(async (callback: (client: TransactionClient) => Promise<unknown>) =>
      callback(client as unknown as TransactionClient),
    ),
  };
  const devices = {
    ensureUser: vi.fn(async () => 'user-1'),
    ensureDevice: vi.fn(async () => 'device-1'),
  };

  return {
    service: new SyncService(
      database as unknown as DatabaseService,
      devices as unknown as DevicesService,
    ),
    client,
    database,
    devices,
  };
}

describe('SyncService conflict resolution', () => {
  const context = { userId: 'request-user', deviceId: 'request-device' };

  it('applies local payload, records a sync change, resolves the conflict, and audits use_local', async () => {
    const { service, client, database, devices } = makeService();
    const dto = {
      strategy: 'use_local' as const,
      payload: { title: 'Local', done: true },
      note: 'accept local edit',
    };

    await expect(service.resolveConflict('conflict-1', dto, context)).resolves.toEqual({
      ok: true,
      conflictId: 'conflict-1',
      strategy: 'use_local',
    });

    expect(devices.ensureUser).toHaveBeenCalledWith('request-user');
    expect(devices.ensureDevice).toHaveBeenCalledWith(context);
    expect(database.transaction).toHaveBeenCalledTimes(1);

    expect(firstCall(client.query, 'UPDATE sync_objects')[1]).toEqual([
      'object-1',
      'user-1',
      JSON.stringify({ title: 'Local', done: true }),
      'device-1',
    ]);
    expect(firstCall(client.query, 'INSERT INTO sync_changes')[1]).toEqual([
      'user-1',
      'device-1',
      'object-1',
      'task_item',
      'upsert',
      8,
      JSON.stringify({ title: 'Local', done: true }),
    ]);
    expect(firstCall(client.query, 'UPDATE sync_conflicts')[1]).toEqual([
      'conflict-1',
      'user-1',
      JSON.stringify(dto),
    ]);

    const auditParams = firstCall(client.query, 'INSERT INTO audit_logs')[1] ?? [];
    expect(auditParams.slice(0, 5)).toEqual([
      'user-1',
      'device-1',
      'sync.conflict.resolve',
      'conflict-1',
      'sync.conflict.resolve: conflict-1',
    ]);
    expect(JSON.parse(auditParams[5] as string)).toEqual({
      conflictId: 'conflict-1',
      objectType: 'task_item',
      serverObjectId: 'object-1',
      strategy: 'use_local',
      note: 'accept local edit',
      fields: conflictFields,
      payloadKeys: ['title', 'done'],
    });
  });

  it('treats merge as a payload merge and records the merged object version', async () => {
    const { service, client } = makeService({
      updatedRows: [{ ...updatedObject, payload: { title: 'Merged', priority: 3 }, server_version: 9 }],
    });

    await service.resolveConflict(
      'conflict-1',
      { strategy: 'merge', payload: { title: 'Merged', priority: 3 } },
      context,
    );

    expect(firstCall(client.query, 'UPDATE sync_objects')[1]).toEqual([
      'object-1',
      'user-1',
      JSON.stringify({ title: 'Merged', priority: 3 }),
      'device-1',
    ]);
    expect(firstCall(client.query, 'INSERT INTO sync_changes')[1]).toEqual([
      'user-1',
      'device-1',
      'object-1',
      'task_item',
      'upsert',
      9,
      JSON.stringify({ title: 'Merged', priority: 3 }),
    ]);
  });

  it('bumps the server object version without merging payload for use_server', async () => {
    const { service, client } = makeService({
      updatedRows: [
        {
          ...updatedObject,
          payload: { title: 'Server', done: false },
          server_version: 8,
        },
      ],
    });

    await service.resolveConflict('conflict-1', { strategy: 'use_server' }, context);

    const [updateSql, updateParams] = firstCall(client.query, 'UPDATE sync_objects');
    expect(normalize(updateSql)).not.toContain('payload = payload ||');
    expect(updateParams).toEqual(['object-1', 'user-1', 'device-1']);
    expect(firstCall(client.query, 'INSERT INTO sync_changes')[1]).toEqual([
      'user-1',
      'device-1',
      'object-1',
      'task_item',
      'upsert',
      8,
      JSON.stringify({ title: 'Server', done: false }),
    ]);
  });

  it('creates a local copy for keep_both with conflict resolution metadata', async () => {
    const now = new Date('2026-01-02T03:04:05.006Z');
    vi.useFakeTimers();
    vi.setSystemTime(now);
    const createdPayload = {
      uid: 'local-uid',
      title: 'Copy',
      _conflictResolution: 'keep_both_local_copy',
      _resolvedAt: now.toISOString(),
    };
    const { service, client } = makeService({
      createdRows: [
        {
          id: 'object-copy-1',
          uid: 'local-uid',
          payload: createdPayload,
          deleted_at: null,
          server_version: 1,
        },
      ],
    });

    await service.resolveConflict(
      'conflict-1',
      { strategy: 'keep_both', payload: { uid: 'local-uid', title: 'Copy' } },
      context,
    );

    const insertParams = firstCall(client.query, 'INSERT INTO sync_objects')[1] ?? [];
    expect(insertParams).toEqual([
      'user-1',
      'task_item',
      `local-uid-${now.getTime()}`,
      JSON.stringify(createdPayload),
      'device-1',
    ]);
    expect(firstCall(client.query, 'INSERT INTO sync_changes')[1]).toEqual([
      'user-1',
      'device-1',
      'object-copy-1',
      'task_item',
      'upsert',
      1,
      JSON.stringify(createdPayload),
    ]);
  });

  it('can ignore a conflict without changing sync objects or recording sync changes', async () => {
    const { service, client } = makeService({
      conflict: { ...openConflict, fields: null as unknown as typeof conflictFields },
    });

    await service.resolveConflict('conflict-1', { strategy: 'ignore' }, context);

    expect(callsContaining(client.query, 'UPDATE sync_objects')).toHaveLength(0);
    expect(callsContaining(client.query, 'INSERT INTO sync_objects')).toHaveLength(0);
    expect(callsContaining(client.query, 'INSERT INTO sync_changes')).toHaveLength(0);
    expect(callsContaining(client.query, 'UPDATE sync_conflicts')).toHaveLength(1);

    const auditParams = firstCall(client.query, 'INSERT INTO audit_logs')[1] ?? [];
    expect(JSON.parse(auditParams[5] as string)).toEqual({
      conflictId: 'conflict-1',
      objectType: 'task_item',
      serverObjectId: 'object-1',
      strategy: 'ignore',
      note: null,
      fields: [],
      payloadKeys: [],
    });
  });

  it('returns ok without writes when the open conflict no longer exists', async () => {
    const { service, client } = makeService({ conflict: null });

    await expect(
      service.resolveConflict('missing-conflict', { strategy: 'use_local', payload: { title: 'Local' } }, context),
    ).resolves.toEqual({
      ok: true,
      conflictId: 'missing-conflict',
      strategy: 'use_local',
    });

    expect(callsContaining(client.query, 'UPDATE sync_objects')).toHaveLength(0);
    expect(callsContaining(client.query, 'INSERT INTO sync_changes')).toHaveLength(0);
    expect(callsContaining(client.query, 'UPDATE sync_conflicts')).toHaveLength(0);
    expect(callsContaining(client.query, 'INSERT INTO audit_logs')).toHaveLength(0);
  });
});
