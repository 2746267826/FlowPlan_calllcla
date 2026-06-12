import { afterEach, describe, expect, it, vi } from 'vitest';
import type { FlowPlanV2RequestContext } from '../common/request-context';
import { SyncService } from './sync.service';
import type { SyncMutationDto } from './dto';

const context: FlowPlanV2RequestContext = {
  userId: '11111111-1111-4111-8111-111111111111',
  deviceId: '22222222-2222-4222-8222-222222222222',
};
const resolvedUserId = 'resolved-user-id';
const resolvedDeviceId = 'resolved-device-id';

afterEach(() => {
  vi.useRealTimers();
});

function dbRows(rows: Record<string, unknown>[] = []) {
  return { rows };
}

function compactSql(sql: unknown) {
  return String(sql).replace(/\s+/g, ' ').trim();
}

type QueryMock = ReturnType<typeof vi.fn>;

function findQueryCall(query: QueryMock, fragment: string) {
  const call = query.mock.calls.find(([sql]) => compactSql(sql).includes(fragment));
  if (!call) {
    throw new Error(`Expected query containing: ${fragment}`);
  }
  return call;
}

function queryCalls(query: QueryMock, fragment: string) {
  return query.mock.calls.filter(([sql]) => compactSql(sql).includes(fragment));
}

function createHarness() {
  const query = vi.fn(async () => dbRows());
  const database = {
    query,
    transaction: vi.fn(async (callback: (client: { query: typeof query }) => unknown) =>
      callback({ query }),
    ),
  };
  const devices = {
    ensureUser: vi.fn(async () => resolvedUserId),
    ensureDevice: vi.fn(async () => resolvedDeviceId),
  };
  const service = new SyncService(database as never, devices as never);
  return { service, database, devices, query };
}

function makeMutation(overrides: Partial<SyncMutationDto> = {}): SyncMutationDto {
  return {
    mutationUid: 'mutation-1',
    objectType: 'task_item',
    localId: 'local-1',
    action: 'upsert',
    payload: { title: 'Test task' },
    ...overrides,
  };
}

describe('SyncService push', () => {
  it('accepts a new mutation and records the object, change, and mutation', async () => {
    const { service, database, devices, query } = createHarness();
    query
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-1',
            uid: null,
            payload: { title: 'Test task' },
            deleted_at: null,
            server_version: 1,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    const response = await service.push({ mutations: [makeMutation()] }, context);

    expect(response).toEqual({
      serverBatchId: expect.stringMatching(
        /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      ),
      accepted: [
        {
          mutationUid: 'mutation-1',
          objectType: 'task_item',
          localId: 'local-1',
          serverId: 'server-object-1',
          serverVersion: 1,
        },
      ],
      conflicts: [],
      rejected: [],
    });
    expect(devices.ensureUser).toHaveBeenCalledWith(context.userId);
    expect(devices.ensureDevice).toHaveBeenCalledWith(context);
    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_objects'), [
      resolvedUserId,
      'task_item',
      null,
      JSON.stringify({ title: 'Test task' }),
      null,
      resolvedDeviceId,
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_changes'), [
      resolvedUserId,
      resolvedDeviceId,
      'server-object-1',
      'task_item',
      'upsert',
      1,
      JSON.stringify({ title: 'Test task' }),
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_mutations'), [
      'mutation-1',
      resolvedUserId,
      resolvedDeviceId,
      'task_item',
      'local-1',
      'server-object-1',
      'upsert',
      null,
      JSON.stringify([]),
      JSON.stringify({ title: 'Test task' }),
      'accepted',
      null,
    ]);
  });

  it('replays already processed accepted, conflict, and rejected mutations', async () => {
    const { service, query } = createHarness();
    const conflictRow = {
      conflict_id: 'conflict-1',
      mutation_uid: 'mutation-replay-conflict',
      object_type: 'task_item',
      local_id: 'local-conflict',
      server_id: 'server-conflict',
      base_version: 2,
      local_version: 1,
      server_version: 3,
      fields: [{ field: 'title', base: 'Old', local: 'Local', server: 'Server' }],
    };
    query.mockImplementation(async (sql: string, params: unknown[]) => {
      const text = compactSql(sql);
      if (text.includes('FROM sync_mutations m')) {
        if (params[0] === 'mutation-replay-accepted') {
          return dbRows([
            {
              result: 'accepted',
              server_object_id: 'server-accepted',
              server_version: null,
              error_message: null,
            },
          ]);
        }
        if (params[0] === 'mutation-replay-conflict') {
          return dbRows([
            {
              result: 'conflict',
              server_object_id: 'server-conflict',
              server_version: 3,
              error_message: null,
            },
          ]);
        }
        if (params[0] === 'mutation-replay-rejected') {
          return dbRows([
            {
              result: 'rejected',
              server_object_id: null,
              server_version: null,
              error_message: null,
            },
          ]);
        }
      }
      if (text.includes('FROM sync_conflicts')) {
        return dbRows([conflictRow]);
      }
      return dbRows();
    });

    const response = await service.push(
      {
        mutations: [
          makeMutation({ mutationUid: 'mutation-replay-accepted', localId: 'local-accepted' }),
          makeMutation({ mutationUid: 'mutation-replay-conflict', localId: 'local-conflict' }),
          makeMutation({ mutationUid: 'mutation-replay-rejected', localId: 'local-rejected' }),
        ],
      },
      context,
    );

    expect(response.accepted).toEqual([
      {
        mutationUid: 'mutation-replay-accepted',
        objectType: 'task_item',
        localId: 'local-accepted',
        serverId: 'server-accepted',
        serverVersion: 1,
      },
    ]);
    expect(response.conflicts).toEqual([
      {
        conflictId: 'conflict-1',
        mutationUid: 'mutation-replay-conflict',
        objectType: 'task_item',
        localId: 'local-conflict',
        serverId: 'server-conflict',
        baseVersion: 2,
        localVersion: 1,
        serverVersion: 3,
        fields: [{ field: 'title', base: 'Old', local: 'Local', server: 'Server' }],
      },
    ]);
    expect(response.rejected).toEqual([
      {
        mutationUid: 'mutation-replay-rejected',
        objectType: 'task_item',
        localId: 'local-rejected',
        reason: 'Previously rejected mutation',
      },
    ]);
    expect(queryCalls(query, 'INSERT INTO sync_objects')).toHaveLength(0);
    expect(queryCalls(query, 'INSERT INTO sync_mutations')).toHaveLength(0);
  });

  it('treats replayed accepted mutations without a server object as rejected', async () => {
    const { service, query } = createHarness();
    query.mockImplementation(async (sql: string) => {
      const text = compactSql(sql);
      if (text.includes('FROM sync_mutations m')) {
        return dbRows([
          {
            result: 'accepted',
            server_object_id: null,
            server_version: 7,
            error_message: null,
          },
        ]);
      }
      return dbRows();
    });

    const response = await service.push(
      {
        mutations: [
          makeMutation({
            mutationUid: 'mutation-replay-missing-object',
            localId: 'local-missing-object',
          }),
        ],
      },
      context,
    );

    expect(response.accepted).toEqual([]);
    expect(response.conflicts).toEqual([]);
    expect(response.rejected).toEqual([
      {
        mutationUid: 'mutation-replay-missing-object',
        objectType: 'task_item',
        localId: 'local-missing-object',
        reason: 'Previously rejected mutation',
      },
    ]);
    expect(queryCalls(query, 'INSERT INTO sync_objects')).toHaveLength(0);
    expect(queryCalls(query, 'INSERT INTO sync_mutations')).toHaveLength(0);
  });

  it('ignores replayed conflicts when the conflict row is no longer available', async () => {
    const { service, query } = createHarness();
    query.mockImplementation(async (sql: string) => {
      const text = compactSql(sql);
      if (text.includes('FROM sync_mutations m')) {
        return dbRows([
          {
            result: 'conflict',
            server_object_id: 'server-conflict',
            server_version: 3,
            error_message: null,
          },
        ]);
      }
      return dbRows();
    });

    const response = await service.push(
      {
        mutations: [
          makeMutation({
            mutationUid: 'mutation-replay-stale-conflict',
            localId: 'local-conflict',
          }),
        ],
      },
      context,
    );

    expect(response.accepted).toEqual([]);
    expect(response.conflicts).toEqual([]);
    expect(response.rejected).toEqual([]);
    expect(queryCalls(query, 'INSERT INTO sync_objects')).toHaveLength(0);
    expect(queryCalls(query, 'INSERT INTO sync_mutations')).toHaveLength(0);
  });

  it('truncates oversized pushes and rejects invalid required fields without mutation writes', async () => {
    const { service, query } = createHarness();
    query.mockResolvedValue(dbRows());
    const dto = {
      mutations: Array.from({ length: 205 }, (_, index) =>
        makeMutation({
          mutationUid: `invalid-${index}`,
          objectType: '',
          localId: '',
        }),
      ),
    };

    const response = await service.push(dto, context);

    expect(dto.mutations).toHaveLength(200);
    expect(response.accepted).toEqual([]);
    expect(response.conflicts).toEqual([]);
    expect(response.rejected).toHaveLength(200);
    expect(response.rejected[0]).toEqual({
      mutationUid: 'invalid-0',
      objectType: '',
      localId: '',
      reason: 'mutationUid, objectType and localId are required',
    });
    expect(query).toHaveBeenCalledTimes(200);
    expect(queryCalls(query, 'INSERT INTO sync_mutations')).toHaveLength(0);
  });

  it('defaults rejected mutation identifiers when required fields are absent', async () => {
    const { service, query } = createHarness();
    query.mockResolvedValue(dbRows());

    const response = await service.push(
      {
        mutations: [
          {
            action: 'upsert',
            payload: {},
          } as unknown as SyncMutationDto,
        ],
      },
      context,
    );

    expect(response.accepted).toEqual([]);
    expect(response.conflicts).toEqual([]);
    expect(response.rejected).toEqual([
      {
        mutationUid: expect.stringMatching(
          /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
        ),
        objectType: 'unknown',
        localId: 'unknown',
        reason: 'mutationUid, objectType and localId are required',
      },
    ]);
    expect(queryCalls(query, 'INSERT INTO sync_mutations')).toHaveLength(0);
  });

  it('handles a push body with no mutations', async () => {
    const { service, database, query } = createHarness();

    await expect(service.push({} as never, context)).resolves.toMatchObject({
      accepted: [],
      conflicts: [],
      rejected: [],
    });
    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(query).not.toHaveBeenCalled();
  });

  it('records empty payload defaults for accepted mutations', async () => {
    const { service, query } = createHarness();
    query
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-empty',
            uid: null,
            payload: {},
            deleted_at: null,
            server_version: 1,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    const response = await service.push(
      {
        mutations: [
          makeMutation({
            mutationUid: 'mutation-empty-payload',
            payload: undefined as never,
            changedFields: null,
          }),
        ],
      },
      context,
    );

    expect(response.accepted).toEqual([
      {
        mutationUid: 'mutation-empty-payload',
        objectType: 'task_item',
        localId: 'local-1',
        serverId: 'server-object-empty',
        serverVersion: 1,
      },
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_objects'), [
      resolvedUserId,
      'task_item',
      null,
      JSON.stringify({}),
      null,
      resolvedDeviceId,
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_changes'), [
      resolvedUserId,
      resolvedDeviceId,
      'server-object-empty',
      'task_item',
      'upsert',
      1,
      JSON.stringify({}),
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_mutations'), [
      'mutation-empty-payload',
      resolvedUserId,
      resolvedDeviceId,
      'task_item',
      'local-1',
      'server-object-empty',
      'upsert',
      null,
      JSON.stringify([]),
      JSON.stringify({}),
      'accepted',
      null,
    ]);
  });

  it('accepts empty non-Outlook calendar mutations when no uid match exists', async () => {
    const { service, query } = createHarness();
    query
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'calendar-object-new',
            uid: 'event-uid',
            payload: {},
            deleted_at: null,
            server_version: 1,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    const response = await service.push(
      {
        mutations: [
          makeMutation({
            mutationUid: 'mutation-calendar-empty',
            objectType: 'calendar_event',
            uid: 'event-uid',
            payload: undefined as never,
          }),
        ],
      },
      context,
    );

    expect(response.accepted).toEqual([
      {
        mutationUid: 'mutation-calendar-empty',
        objectType: 'calendar_event',
        localId: 'local-1',
        serverId: 'calendar-object-new',
        serverVersion: 1,
      },
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_objects'), [
      resolvedUserId,
      'calendar_event',
      'event-uid',
      JSON.stringify({}),
      null,
      resolvedDeviceId,
    ]);
  });

  it('rejects read-only Outlook calendar objects and records the rejection', async () => {
    const { service, query } = createHarness();
    const reason =
      'Outlook synced calendar objects are read-only and must be refreshed from the server.';
    query
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'calendar-object-1',
            uid: 'event-uid',
            payload: { source: 'outlook', title: 'Server event' },
            deleted_at: null,
            server_version: 6,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    const response = await service.push(
      {
        mutations: [
          makeMutation({
            mutationUid: 'mutation-readonly',
            objectType: 'calendar_event',
            serverId: 'calendar-object-1',
            payload: { title: 'Client edit' },
          }),
        ],
      },
      context,
    );

    expect(response.rejected).toEqual([
      {
        mutationUid: 'mutation-readonly',
        objectType: 'calendar_event',
        localId: 'local-1',
        reason,
      },
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_mutations'), [
      'mutation-readonly',
      resolvedUserId,
      resolvedDeviceId,
      'calendar_event',
      'local-1',
      'calendar-object-1',
      'upsert',
      null,
      JSON.stringify([]),
      JSON.stringify({ title: 'Client edit' }),
      'rejected',
      reason,
    ]);
    expect(queryCalls(query, 'INSERT INTO sync_changes')).toHaveLength(0);
  });

  it('rejects client payloads that mark Outlook calendar data as read-only', async () => {
    const { service, query } = createHarness();
    const reason =
      'Outlook synced calendar objects are read-only and must be refreshed from the server.';
    query.mockResolvedValue(dbRows());

    const response = await service.push(
      {
        mutations: [
          makeMutation({
            mutationUid: 'mutation-client-readonly',
            objectType: 'calendar_book',
            payload: { name: 'Outlook calendar', readOnly: true },
          }),
        ],
      },
      context,
    );

    expect(response.rejected).toEqual([
      {
        mutationUid: 'mutation-client-readonly',
        objectType: 'calendar_book',
        localId: 'local-1',
        reason,
      },
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_mutations'), [
      'mutation-client-readonly',
      resolvedUserId,
      resolvedDeviceId,
      'calendar_book',
      'local-1',
      null,
      'upsert',
      null,
      JSON.stringify([]),
      JSON.stringify({ name: 'Outlook calendar', readOnly: true }),
      'rejected',
      reason,
    ]);
  });

  it('creates a conflict when the base server version is stale', async () => {
    const { service, query } = createHarness();
    const expectedFields = [
      {
        field: 'title',
        base: undefined,
        local: 'Local title',
        server: 'Server title',
      },
      {
        field: 'priority',
        base: undefined,
        local: 'high',
        server: 'low',
      },
    ];
    query
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-1',
            uid: 'task-uid',
            payload: { title: 'Server title', priority: 'low' },
            deleted_at: null,
            server_version: 3,
          },
        ]),
      )
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(
        dbRows([
          {
            conflict_id: 'conflict-1',
            mutation_uid: 'mutation-conflict',
            object_type: 'task_item',
            local_id: 'local-1',
            server_id: 'server-object-1',
            base_version: 1,
            local_version: 1,
            server_version: 3,
            fields: expectedFields,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    const response = await service.push(
      {
        mutations: [
          makeMutation({
            mutationUid: 'mutation-conflict',
            serverId: 'server-object-1',
            baseServerVersion: 1,
            changedFields: ['title', 'priority'],
            payload: { title: 'Local title', priority: 'high' },
          }),
        ],
      },
      context,
    );

    expect(response.conflicts).toEqual([
      {
        conflictId: 'conflict-1',
        mutationUid: 'mutation-conflict',
        objectType: 'task_item',
        localId: 'local-1',
        serverId: 'server-object-1',
        baseVersion: 1,
        localVersion: 1,
        serverVersion: 3,
        fields: expectedFields,
      },
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_mutations'), [
      'mutation-conflict',
      resolvedUserId,
      resolvedDeviceId,
      'task_item',
      'local-1',
      'server-object-1',
      'upsert',
      1,
      JSON.stringify(['title', 'priority']),
      JSON.stringify({ title: 'Local title', priority: 'high' }),
      'conflict',
      null,
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_conflicts'), [
      resolvedUserId,
      resolvedDeviceId,
      'mutation-conflict',
      'task_item',
      'local-1',
      'server-object-1',
      1,
      3,
      JSON.stringify(expectedFields),
    ]);
    const conflictInsert = findQueryCall(query, 'INSERT INTO sync_conflicts');
    expect(conflictInsert[1]).toEqual([
      resolvedUserId,
      resolvedDeviceId,
      'mutation-conflict',
      'task_item',
      'local-1',
      'server-object-1',
      1,
      3,
      JSON.stringify(expectedFields),
    ]);
  });

  it('builds conflict fields from payload keys when changed fields are empty', async () => {
    const { service, query } = createHarness();
    const expectedFields = [
      {
        field: 'title',
        base: undefined,
        local: 'Local title',
        server: 'Server title',
      },
    ];
    query
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-1',
            uid: 'task-uid',
            payload: { title: 'Server title' },
            deleted_at: null,
            server_version: 3,
          },
        ]),
      )
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(
        dbRows([
          {
            conflict_id: 'conflict-payload-fields',
            mutation_uid: 'mutation-conflict-payload-fields',
            object_type: 'task_item',
            local_id: 'local-1',
            server_id: 'server-object-1',
            base_version: 1,
            local_version: 1,
            server_version: 3,
            fields: expectedFields,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    const response = await service.push(
      {
        mutations: [
          makeMutation({
            mutationUid: 'mutation-conflict-payload-fields',
            serverId: 'server-object-1',
            baseServerVersion: 1,
            changedFields: [],
            payload: { title: 'Local title' },
          }),
        ],
      },
      context,
    );

    expect(response.conflicts[0].fields).toEqual(expectedFields);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_conflicts'), [
      resolvedUserId,
      resolvedDeviceId,
      'mutation-conflict-payload-fields',
      'task_item',
      'local-1',
      'server-object-1',
      1,
      3,
      JSON.stringify(expectedFields),
    ]);
  });

  it('builds empty conflict fields when changed fields and payload are absent', async () => {
    const { service, query } = createHarness();
    query
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-1',
            uid: 'task-uid',
            payload: { title: 'Server title' },
            deleted_at: null,
            server_version: 3,
          },
        ]),
      )
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(
        dbRows([
          {
            conflict_id: 'conflict-empty-fields',
            mutation_uid: 'mutation-conflict-empty-fields',
            object_type: 'task_item',
            local_id: 'local-1',
            server_id: 'server-object-1',
            base_version: 1,
            local_version: 1,
            server_version: 3,
            fields: [],
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    const response = await service.push(
      {
        mutations: [
          makeMutation({
            mutationUid: 'mutation-conflict-empty-fields',
            serverId: 'server-object-1',
            baseServerVersion: 1,
            payload: undefined as never,
          }),
        ],
      },
      context,
    );

    expect(response.conflicts[0].fields).toEqual([]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_conflicts'), [
      resolvedUserId,
      resolvedDeviceId,
      'mutation-conflict-empty-fields',
      'task_item',
      'local-1',
      'server-object-1',
      1,
      3,
      JSON.stringify([]),
    ]);
  });

  it('deletes an existing object and records a delete change', async () => {
    const { service, query } = createHarness();
    query
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-1',
            uid: 'task-uid',
            payload: { title: 'Server title' },
            deleted_at: null,
            server_version: 2,
          },
        ]),
      )
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-1',
            uid: 'task-uid',
            payload: { title: 'Server title' },
            deleted_at: '2026-01-01T00:00:00.000Z',
            server_version: 3,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    const response = await service.push(
      {
        mutations: [
          makeMutation({
            mutationUid: 'mutation-delete',
            serverId: 'server-object-1',
            action: 'delete',
            payload: {},
          }),
        ],
      },
      context,
    );

    expect(response.accepted).toEqual([
      {
        mutationUid: 'mutation-delete',
        objectType: 'task_item',
        localId: 'local-1',
        serverId: 'server-object-1',
        serverVersion: 3,
      },
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('UPDATE sync_objects'), [
      'server-object-1',
      resolvedUserId,
      resolvedDeviceId,
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_changes'), [
      resolvedUserId,
      resolvedDeviceId,
      'server-object-1',
      'task_item',
      'delete',
      3,
      JSON.stringify({ title: 'Server title' }),
    ]);
  });

  it('creates a deleted tombstone when a delete mutation has no existing object', async () => {
    const { service, query } = createHarness();
    query
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-tombstone',
            uid: null,
            payload: undefined,
            deleted_at: '2026-01-01T00:00:00.000Z',
            server_version: 1,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    const response = await service.push(
      {
        mutations: [
          makeMutation({
            mutationUid: 'mutation-delete-new',
            action: 'delete',
            payload: {},
          }),
        ],
      },
      context,
    );

    expect(response.accepted).toEqual([
      {
        mutationUid: 'mutation-delete-new',
        objectType: 'task_item',
        localId: 'local-1',
        serverId: 'server-object-tombstone',
        serverVersion: 1,
      },
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_objects'), [
      resolvedUserId,
      'task_item',
      null,
      JSON.stringify({}),
      expect.any(Date),
      resolvedDeviceId,
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_changes'), [
      resolvedUserId,
      resolvedDeviceId,
      'server-object-tombstone',
      'task_item',
      'delete',
      1,
      JSON.stringify({}),
    ]);
  });

  it('restores a deleted object found by uid and removes stale deleted duplicates', async () => {
    const { service, query } = createHarness();
    query
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-2',
            uid: 'task-uid',
            payload: { title: 'Deleted title' },
            deleted_at: '2025-12-01T00:00:00.000Z',
            server_version: 4,
          },
        ]),
      )
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-2',
            uid: 'task-uid',
            payload: { title: 'Restored title' },
            deleted_at: null,
            server_version: 5,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    const response = await service.push(
      {
        mutations: [
          makeMutation({
            mutationUid: 'mutation-restore',
            serverId: 'missing-server-object',
            uid: 'task-uid',
            payload: { title: 'Restored title' },
          }),
        ],
      },
      context,
    );

    expect(response.accepted[0]).toMatchObject({
      mutationUid: 'mutation-restore',
      serverId: 'server-object-2',
      serverVersion: 5,
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('DELETE FROM sync_objects'), [
      resolvedUserId,
      'task_item',
      'task-uid',
      'server-object-2',
    ]);
  });

  it('updates an existing non-deleted object with default payload and uid values', async () => {
    const { service, query } = createHarness();
    query
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-1',
            uid: 'task-uid',
            payload: { title: 'Server title' },
            deleted_at: null,
            server_version: 2,
          },
        ]),
      )
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-1',
            uid: 'task-uid',
            payload: {},
            deleted_at: null,
            server_version: 3,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    const response = await service.push(
      {
        mutations: [
          makeMutation({
            mutationUid: 'mutation-update-defaults',
            serverId: 'server-object-1',
            payload: undefined as never,
          }),
        ],
      },
      context,
    );

    expect(response.accepted[0]).toMatchObject({
      mutationUid: 'mutation-update-defaults',
      serverId: 'server-object-1',
      serverVersion: 3,
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('UPDATE sync_objects'), [
      'server-object-1',
      resolvedUserId,
      JSON.stringify({}),
      null,
      resolvedDeviceId,
    ]);
    expect(queryCalls(query, 'DELETE FROM sync_objects')).toHaveLength(0);
  });

  it('records unexpected mutation application errors as rejected mutations', async () => {
    const { service, query } = createHarness();
    query.mockImplementation(async (sql: string) => {
      const text = compactSql(sql);
      if (text.includes('FROM sync_mutations m')) {
        return dbRows();
      }
      if (text.includes('INSERT INTO sync_objects')) {
        throw new Error('insert failed');
      }
      return dbRows();
    });

    const response = await service.push(
      { mutations: [makeMutation({ mutationUid: 'mutation-error' })] },
      context,
    );

    expect(response.rejected).toEqual([
      {
        mutationUid: 'mutation-error',
        objectType: 'task_item',
        localId: 'local-1',
        reason: 'insert failed',
      },
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_mutations'), [
      'mutation-error',
      resolvedUserId,
      resolvedDeviceId,
      'task_item',
      'local-1',
      null,
      'upsert',
      null,
      JSON.stringify([]),
      JSON.stringify({ title: 'Test task' }),
      'rejected',
      'insert failed',
    ]);
  });

  it('records thrown non-Error mutation failures as rejected mutations', async () => {
    const { service, query } = createHarness();
    query.mockImplementation(async (sql: string) => {
      const text = compactSql(sql);
      if (text.includes('FROM sync_mutations m')) {
        return dbRows();
      }
      if (text.includes('INSERT INTO sync_objects')) {
        throw 'plain failure';
      }
      return dbRows();
    });

    const response = await service.push(
      { mutations: [makeMutation({ mutationUid: 'mutation-string-error' })] },
      context,
    );

    expect(response.rejected).toEqual([
      {
        mutationUid: 'mutation-string-error',
        objectType: 'task_item',
        localId: 'local-1',
        reason: 'plain failure',
      },
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_mutations'), [
      'mutation-string-error',
      resolvedUserId,
      resolvedDeviceId,
      'task_item',
      'local-1',
      null,
      'upsert',
      null,
      JSON.stringify([]),
      JSON.stringify({ title: 'Test task' }),
      'rejected',
      'plain failure',
    ]);
  });
});

describe('SyncService pull and ack', () => {
  it('pulls, filters, clamps limit, sorts by sync priority, and maps changes', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00.000Z'));
    const { service, query } = createHarness();
    query.mockResolvedValue(
      dbRows([
        {
          id: '9',
          object_type: 'file_item',
          server_object_id: 'file-1',
          uid: null,
          action: 'upsert',
          server_version: 1,
          created_at: new Date('2026-01-01T00:00:09.000Z'),
          payload: null,
        },
        {
          id: '8',
          object_type: 'calendar_event',
          server_object_id: 'event-1',
          uid: 'event-uid',
          action: 'delete',
          server_version: 4,
          created_at: new Date('2026-01-01T00:00:08.000Z'),
          payload: { title: 'Event' },
        },
        {
          id: '6',
          object_type: 'calendar_book',
          server_object_id: 'book-1',
          uid: 'book-uid',
          action: 'upsert',
          server_version: 2,
          created_at: new Date('2026-01-01T00:00:06.000Z'),
          payload: { name: 'Book' },
        },
        {
          id: '7',
          object_type: 'task_item',
          server_object_id: 'task-1',
          uid: 'task-uid',
          action: 'upsert',
          server_version: 3,
          created_at: new Date('2026-01-01T00:00:07.000Z'),
          payload: { title: 'Task' },
        },
        {
          id: '5',
          object_type: 'task_schedule_segment',
          server_object_id: 'segment-1',
          uid: null,
          action: 'upsert',
          server_version: 1,
          created_at: new Date('2026-01-01T00:00:05.000Z'),
          payload: { taskId: 'task-1' },
        },
      ]),
    );

    const response = await service.pull('-7', context, {
      objectType: ' task_item ',
      limit: '5000',
    });

    expect(query).toHaveBeenCalledWith(expect.stringContaining('FROM sync_changes c'), [
      resolvedUserId,
      0,
      resolvedDeviceId,
      'task_item',
      1000,
    ]);
    expect(response.serverTime).toBe('2026-01-01T00:00:00.000Z');
    expect(response.nextCursor).toBe('9');
    expect(response.changes.map((change) => change.changeId)).toEqual([
      '6',
      '7',
      '8',
      '5',
      '9',
    ]);
    expect(response.changes[0]).toEqual({
      changeId: '6',
      objectType: 'calendar_book',
      serverId: 'book-1',
      uid: 'book-uid',
      action: 'upsert',
      serverVersion: 2,
      updatedAt: '2026-01-01T00:00:06.000Z',
      payload: { name: 'Book' },
    });
    expect(response.changes[4].payload).toEqual({});
    const [pullSql] = findQueryCall(query, 'FROM sync_changes c');
    expect(compactSql(pullSql)).toContain(
      'AND (c.device_id IS NULL OR c.device_id <> $3)',
    );
    expect(compactSql(pullSql)).toContain(
      'AND ($4::text IS NULL OR c.object_type = $4)',
    );
  });

  it('sorts unknown-priority pull changes by numeric id including equal ids', async () => {
    const { service, query } = createHarness();
    const rows = [
      { id: '10', object_type: 'file_item', server_object_id: 'file-10' },
      { id: '12', object_type: 'file_item', server_object_id: 'file-12' },
      { id: '11', object_type: 'file_item', server_object_id: 'file-11a' },
      { id: '11', object_type: 'file_item', server_object_id: 'file-11b' },
    ].map((row) => ({
      ...row,
      uid: null,
      action: 'upsert',
      server_version: 1,
      created_at: new Date(`2026-01-01T00:00:${row.id.padStart(2, '0')}.000Z`),
      payload: {},
    }));
    query.mockResolvedValue(dbRows(rows));

    const response = await service.pull('0', context, { limit: '10' });

    expect(response.changes.map((change) => change.changeId)).toEqual(['10', '11', '11', '12']);
    expect(response.nextCursor).toBe('12');
  });

  it('pull returns an empty page with the parsed cursor when there are no changes', async () => {
    const { service, query } = createHarness();
    query.mockResolvedValue(dbRows());

    const response = await service.pull('12', context, {
      objectType: '   ',
      limit: '0',
    });

    expect(query).toHaveBeenCalledWith(expect.stringContaining('FROM sync_changes c'), [
      resolvedUserId,
      12,
      resolvedDeviceId,
      null,
      1,
    ]);
    expect(response.nextCursor).toBe('12');
    expect(response.changes).toEqual([]);
  });

  it('pull defaults a missing cursor to zero and uses default limit', async () => {
    const { service, query } = createHarness();
    query.mockResolvedValue(dbRows());

    const response = await service.pull(undefined, context);

    expect(query).toHaveBeenCalledWith(expect.stringContaining('FROM sync_changes c'), [
      resolvedUserId,
      0,
      resolvedDeviceId,
      null,
      200,
    ]);
    expect(response.nextCursor).toBe('0');
    expect(response.changes).toEqual([]);
  });

  it('pull defaults invalid cursor and limit values', async () => {
    const { service, query } = createHarness();
    query.mockResolvedValue(dbRows());

    const response = await service.pull('not-a-cursor', context, {
      objectType: 'calendar_event',
      limit: 'not-a-limit',
    });

    expect(query).toHaveBeenCalledWith(expect.stringContaining('FROM sync_changes c'), [
      resolvedUserId,
      0,
      resolvedDeviceId,
      'calendar_event',
      200,
    ]);
    expect(response.nextCursor).toBe('0');
    expect(response.changes).toEqual([]);
  });

  it('ack stores a sanitized cursor and defaults applied change ids', async () => {
    const { service, query } = createHarness();
    query.mockResolvedValue(dbRows());

    await expect(service.ack({ cursor: 'not-a-cursor' }, context)).resolves.toEqual({
      ok: true,
      cursor: '0',
      appliedChangeIds: [],
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_cursors'), [
      resolvedUserId,
      resolvedDeviceId,
      0,
    ]);
  });
});

describe('SyncService conflict, status, health, and purge summaries', () => {
  it('lists open conflicts and normalizes nullable row fields', async () => {
    const { service, devices, query } = createHarness();
    query.mockResolvedValue(
      dbRows([
        {
          conflict_id: 'conflict-1',
          mutation_uid: null,
          object_type: 'task_item',
          local_id: null,
          server_id: null,
          base_version: null,
          local_version: 1,
          server_version: 2,
          fields: null,
        },
      ]),
    );

    await expect(service.conflicts(context)).resolves.toEqual({
      conflicts: [
        {
          conflictId: 'conflict-1',
          objectType: 'task_item',
          baseVersion: null,
          localVersion: 1,
          serverVersion: 2,
          fields: [],
        },
      ],
    });
    expect(devices.ensureDevice).not.toHaveBeenCalled();
    expect(query).toHaveBeenCalledWith(expect.stringContaining('FROM sync_conflicts c'), [
      resolvedUserId,
    ]);
  });

  it('returns device status with Outlook object counts', async () => {
    const { service, devices, query } = createHarness();
    const deviceRow = {
      deviceId: 'device-1',
      deviceName: 'Laptop',
      platform: 'windows',
      pullCursor: '4',
      latestChangeId: '9',
      pendingOutlookChanges: 2,
    };
    const outlookRow = { objectType: 'calendar_event', count: 3 };
    query.mockResolvedValueOnce(dbRows([deviceRow])).mockResolvedValueOnce(dbRows([outlookRow]));

    await expect(service.status(context)).resolves.toEqual({
      devices: [deviceRow],
      outlookObjects: [outlookRow],
    });
    expect(devices.ensureDevice).not.toHaveBeenCalled();
    expect(query).toHaveBeenNthCalledWith(1, expect.stringContaining('FROM devices d'), [
      resolvedUserId,
    ]);
    expect(query).toHaveBeenNthCalledWith(2, expect.stringContaining('FROM sync_objects'), [
      resolvedUserId,
    ]);
  });

  it('returns sync health metrics with generated timestamp', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-02T03:04:05.000Z'));
    const { service, devices, query } = createHarness();
    query
      .mockResolvedValueOnce(dbRows([{ count: '2' }]))
      .mockResolvedValueOnce(dbRows([{ recentAccepted: '4', failed: '1', rejected: '3' }]))
      .mockResolvedValueOnce(dbRows([{ count: '5' }]))
      .mockResolvedValueOnce(dbRows([{ at: '2026-01-02T03:00:00.000Z' }]));

    await expect(service.health(context)).resolves.toEqual({
      openConflicts: 2,
      mutationStats: { recentAccepted: '4', failed: '1', rejected: '3' },
      orphanedMutations: 5,
      lastChangeAt: '2026-01-02T03:00:00.000Z',
      generatedAt: '2026-01-02T03:04:05.000Z',
    });
    expect(devices.ensureDevice).not.toHaveBeenCalled();
    expect(query).toHaveBeenCalledTimes(4);
  });

  it('defaults sync health metrics when aggregate rows are absent', async () => {
    const { service, query } = createHarness();
    query.mockResolvedValue(dbRows());

    await expect(service.health(context)).resolves.toMatchObject({
      openConflicts: 0,
      mutationStats: undefined,
      orphanedMutations: 0,
      lastChangeAt: null,
    });
  });

  it('purges stale mutations with explicit and default retention windows', async () => {
    const { service, devices, query } = createHarness();
    query.mockResolvedValueOnce(dbRows([{ count: '7' }])).mockResolvedValueOnce(dbRows());

    await expect(service.purgeStaleMutations(context, 45)).resolves.toEqual({
      ok: true,
      purgedCount: 7,
      olderThanDays: 45,
    });
    await expect(service.purgeStaleMutations(context)).resolves.toEqual({
      ok: true,
      purgedCount: 0,
      olderThanDays: 30,
    });
    expect(devices.ensureDevice).not.toHaveBeenCalled();
    expect(query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('DELETE FROM sync_mutations'),
      [resolvedUserId, '45'],
    );
    expect(query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('DELETE FROM sync_mutations'),
      [resolvedUserId, '30'],
    );
  });
});

describe('SyncService resolveConflict', () => {
  const conflictRow = {
    server_object_id: 'server-object-1',
    object_type: 'task_item',
    server_version: 3,
    fields: [{ field: 'title', base: 'Old', local: 'Local', server: 'Server' }],
  };

  it('resolves merge conflicts by applying payload, recording change, and auditing', async () => {
    const { service, database, query } = createHarness();
    const dto = {
      strategy: 'merge' as const,
      payload: { title: 'Merged title', priority: 'high' },
      note: 'Manual merge',
    };
    query
      .mockResolvedValueOnce(dbRows([conflictRow]))
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-1',
            uid: 'task-uid',
            payload: { title: 'Merged title', priority: 'high' },
            deleted_at: null,
            server_version: 4,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    await expect(service.resolveConflict('conflict-1', dto, context)).resolves.toEqual({
      ok: true,
      conflictId: 'conflict-1',
      strategy: 'merge',
    });

    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('UPDATE sync_objects'), [
      'server-object-1',
      resolvedUserId,
      JSON.stringify({ title: 'Merged title', priority: 'high' }),
      resolvedDeviceId,
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_changes'), [
      resolvedUserId,
      resolvedDeviceId,
      'server-object-1',
      'task_item',
      'upsert',
      4,
      JSON.stringify({ title: 'Merged title', priority: 'high' }),
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('UPDATE sync_conflicts'), [
      'conflict-1',
      resolvedUserId,
      JSON.stringify(dto),
    ]);
    const auditCall = findQueryCall(query, 'INSERT INTO audit_logs');
    expect(auditCall[1]).toEqual([
      resolvedUserId,
      resolvedDeviceId,
      'sync.conflict.resolve',
      'conflict-1',
      'sync.conflict.resolve: conflict-1',
      expect.any(String),
    ]);
    expect(JSON.parse(String((auditCall[1] as unknown[])[5]))).toMatchObject({
      conflictId: 'conflict-1',
      objectType: 'task_item',
      serverObjectId: 'server-object-1',
      strategy: 'merge',
      note: 'Manual merge',
      payloadKeys: ['title', 'priority'],
    });
  });

  it('resolves merge conflicts without a change row when the update returns no object', async () => {
    const { service, query } = createHarness();
    query
      .mockResolvedValueOnce(dbRows([conflictRow]))
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValue(dbRows());

    await expect(
      service.resolveConflict('conflict-1', { strategy: 'merge', payload: { title: 'Merged title' } }, context),
    ).resolves.toEqual({
      ok: true,
      conflictId: 'conflict-1',
      strategy: 'merge',
    });

    expect(queryCalls(query, 'INSERT INTO sync_changes')).toHaveLength(0);
    expect(queryCalls(query, 'UPDATE sync_conflicts')).toHaveLength(1);
    expect(queryCalls(query, 'INSERT INTO audit_logs')).toHaveLength(1);
  });

  it('resolves use_local conflicts with default payload and audit metadata', async () => {
    const { service, query } = createHarness();
    query
      .mockResolvedValueOnce(
        dbRows([
          {
            ...conflictRow,
            fields: null,
          },
        ]),
      )
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-1',
            uid: 'task-uid',
            payload: { title: 'Server title' },
            deleted_at: null,
            server_version: 4,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    await expect(
      service.resolveConflict('conflict-1', { strategy: 'use_local' }, context),
    ).resolves.toEqual({
      ok: true,
      conflictId: 'conflict-1',
      strategy: 'use_local',
    });

    expect(query).toHaveBeenCalledWith(expect.stringContaining('UPDATE sync_objects'), [
      'server-object-1',
      resolvedUserId,
      JSON.stringify({}),
      resolvedDeviceId,
    ]);
    const auditCall = findQueryCall(query, 'INSERT INTO audit_logs');
    expect(JSON.parse(String((auditCall[1] as unknown[])[5]))).toMatchObject({
      strategy: 'use_local',
      note: null,
      fields: [],
      payloadKeys: [],
    });
  });

  it('resolves use_server conflicts by bumping the server object version', async () => {
    const { service, query } = createHarness();
    query
      .mockResolvedValueOnce(dbRows([conflictRow]))
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-1',
            uid: 'task-uid',
            payload: { title: 'Server title' },
            deleted_at: null,
            server_version: 4,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    await expect(
      service.resolveConflict('conflict-1', { strategy: 'use_server' }, context),
    ).resolves.toEqual({
      ok: true,
      conflictId: 'conflict-1',
      strategy: 'use_server',
    });

    expect(query).toHaveBeenCalledWith(expect.stringContaining('UPDATE sync_objects'), [
      'server-object-1',
      resolvedUserId,
      resolvedDeviceId,
    ]);
    expect(queryCalls(query, 'INSERT INTO sync_changes')).toHaveLength(1);
  });

  it('resolves use_server conflicts without change rows when no object row is returned', async () => {
    const { service, query } = createHarness();
    query.mockResolvedValueOnce(dbRows([conflictRow])).mockResolvedValue(dbRows());

    await expect(
      service.resolveConflict('conflict-1', { strategy: 'use_server' }, context),
    ).resolves.toEqual({
      ok: true,
      conflictId: 'conflict-1',
      strategy: 'use_server',
    });

    expect(queryCalls(query, 'INSERT INTO sync_changes')).toHaveLength(0);
    expect(queryCalls(query, 'UPDATE sync_conflicts')).toHaveLength(1);
    expect(queryCalls(query, 'INSERT INTO audit_logs')).toHaveLength(1);
  });

  it('resolves keep_both conflicts by creating a local copy with resolution metadata', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-02T03:04:05.000Z'));
    const { service, query } = createHarness();
    const dto = {
      strategy: 'keep_both' as const,
      payload: { uid: 'client-copy', title: 'Client copy' },
    };
    query
      .mockResolvedValueOnce(dbRows([conflictRow]))
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-copy',
            uid: 'client-copy-1767323045000',
            payload: {
              uid: 'client-copy',
              title: 'Client copy',
              _conflictResolution: 'keep_both_local_copy',
              _resolvedAt: '2026-01-02T03:04:05.000Z',
            },
            deleted_at: null,
            server_version: 1,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    await expect(service.resolveConflict('conflict-1', dto, context)).resolves.toEqual({
      ok: true,
      conflictId: 'conflict-1',
      strategy: 'keep_both',
    });

    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_objects'), [
      resolvedUserId,
      'task_item',
      'client-copy-1767323045000',
      JSON.stringify({
        uid: 'client-copy',
        title: 'Client copy',
        _conflictResolution: 'keep_both_local_copy',
        _resolvedAt: '2026-01-02T03:04:05.000Z',
      }),
      resolvedDeviceId,
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_changes'), [
      resolvedUserId,
      resolvedDeviceId,
      'server-object-copy',
      'task_item',
      'upsert',
      1,
      JSON.stringify({
        uid: 'client-copy',
        title: 'Client copy',
        _conflictResolution: 'keep_both_local_copy',
        _resolvedAt: '2026-01-02T03:04:05.000Z',
      }),
    ]);
  });

  it('resolves keep_both conflicts with default uid and empty payload metadata', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-02T03:04:05.000Z'));
    const { service, query } = createHarness();
    query
      .mockResolvedValueOnce(dbRows([conflictRow]))
      .mockResolvedValueOnce(
        dbRows([
          {
            id: 'server-object-copy',
            uid: 'keep-both-1767323045000',
            payload: {
              _conflictResolution: 'keep_both_local_copy',
              _resolvedAt: '2026-01-02T03:04:05.000Z',
            },
            deleted_at: null,
            server_version: 1,
          },
        ]),
      )
      .mockResolvedValue(dbRows());

    await expect(
      service.resolveConflict('conflict-1', { strategy: 'keep_both' }, context),
    ).resolves.toEqual({
      ok: true,
      conflictId: 'conflict-1',
      strategy: 'keep_both',
    });

    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_objects'), [
      resolvedUserId,
      'task_item',
      'keep-both-1767323045000',
      JSON.stringify({
        _conflictResolution: 'keep_both_local_copy',
        _resolvedAt: '2026-01-02T03:04:05.000Z',
      }),
      resolvedDeviceId,
    ]);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_changes'), [
      resolvedUserId,
      resolvedDeviceId,
      'server-object-copy',
      'task_item',
      'upsert',
      1,
      JSON.stringify({
        _conflictResolution: 'keep_both_local_copy',
        _resolvedAt: '2026-01-02T03:04:05.000Z',
      }),
    ]);
  });

  it('resolves keep_both conflicts without a change row when the insert returns no object', async () => {
    const { service, query } = createHarness();
    query
      .mockResolvedValueOnce(dbRows([conflictRow]))
      .mockResolvedValueOnce(dbRows())
      .mockResolvedValue(dbRows());

    await expect(
      service.resolveConflict('conflict-1', { strategy: 'keep_both', payload: { title: 'Client copy' } }, context),
    ).resolves.toEqual({
      ok: true,
      conflictId: 'conflict-1',
      strategy: 'keep_both',
    });

    expect(queryCalls(query, 'INSERT INTO sync_changes')).toHaveLength(0);
    expect(queryCalls(query, 'UPDATE sync_conflicts')).toHaveLength(1);
    expect(queryCalls(query, 'INSERT INTO audit_logs')).toHaveLength(1);
  });

  it('resolves ignore conflicts without touching sync objects', async () => {
    const { service, query } = createHarness();
    query.mockResolvedValueOnce(dbRows([conflictRow])).mockResolvedValue(dbRows());

    await expect(
      service.resolveConflict('conflict-1', { strategy: 'ignore' }, context),
    ).resolves.toEqual({
      ok: true,
      conflictId: 'conflict-1',
      strategy: 'ignore',
    });

    expect(queryCalls(query, 'INSERT INTO sync_objects')).toHaveLength(0);
    expect(queryCalls(query, 'UPDATE sync_objects')).toHaveLength(0);
    expect(queryCalls(query, 'INSERT INTO sync_changes')).toHaveLength(0);
    expect(queryCalls(query, 'UPDATE sync_conflicts')).toHaveLength(1);
    expect(queryCalls(query, 'INSERT INTO audit_logs')).toHaveLength(1);
  });

  it('returns ok without resolution writes when the conflict is not open', async () => {
    const { service, query } = createHarness();
    query.mockResolvedValue(dbRows());

    await expect(
      service.resolveConflict('missing-conflict', { strategy: 'use_local' }, context),
    ).resolves.toEqual({
      ok: true,
      conflictId: 'missing-conflict',
      strategy: 'use_local',
    });

    expect(query).toHaveBeenCalledTimes(1);
    expect(queryCalls(query, 'UPDATE sync_conflicts')).toHaveLength(0);
    expect(queryCalls(query, 'INSERT INTO audit_logs')).toHaveLength(0);
  });
});
