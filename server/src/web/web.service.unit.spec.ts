import { ConflictException } from '@nestjs/common';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { WebService } from './web.service';

vi.mock('node:crypto', () => ({
  randomUUID: () => '00000000-0000-4000-8000-00000000feed',
}));

const context = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};

type Row = Record<string, unknown>;
type QueryResult = { rows: Row[] };
type QueryHandler = (sql: string, params?: unknown[]) => Promise<QueryResult>;

function rows(rows: Row[] = []): QueryResult {
  return { rows };
}

function createService(
  queryImpl: QueryHandler = async () => rows(),
  transactionQueryImpl?: QueryHandler,
) {
  const transactionClient = {
    query: vi.fn(transactionQueryImpl ?? queryImpl),
  };
  const database = {
    query: vi.fn(queryImpl),
    transaction: vi.fn(async (callback: (client: typeof transactionClient) => unknown) =>
      callback(transactionClient),
    ),
  };
  const devices = {
    ensureUser: vi.fn(async (userId: string) => userId),
    ensureDevice: vi.fn(async () => context.deviceId),
  };
  return {
    service: new WebService(database as never, devices as never),
    database,
    devices,
    transactionClient,
  };
}

function taskRow(overrides: Row = {}): Row {
  return {
    id: 'task-1',
    objectType: 'task_item',
    uid: 'task-uid-1',
    payload: {
      title: 'Plan sprint',
      status: 'todo',
      priority: 'high',
      dueAt: '2026-06-08T09:30:00.000Z',
      location: 'Desk',
    },
    serverVersion: 3,
    updatedAt: '2026-06-07T12:00:00.000Z',
    ...overrides,
  };
}

function eventRow(overrides: Row = {}): Row {
  return {
    id: 'event-1',
    objectType: 'calendar_event',
    uid: 'event-uid-1',
    payload: {
      title: 'Design review',
      startAt: '2026-06-08T08:00:00.000Z',
      endAt: '2026-06-08T09:00:00.000Z',
      status: 'confirmed',
      isBlock: true,
      location: 'Room A',
      notes: 'Bring notes',
    },
    serverVersion: 4,
    updatedAt: '2026-06-07T12:00:00.000Z',
    ...overrides,
  };
}

describe('WebService', () => {
  afterEach(() => {
    vi.useRealTimers();
    vi.restoreAllMocks();
  });

  it('lists tasks with normalized filters and task view models', async () => {
    const task = taskRow({
      payload: {
        name: '  Legacy task  ',
        status: 'completed',
        due: '2026-06-09T10:00:00.000Z',
        place: 'Office',
      },
    });
    const { service, database, devices } = createService(async (sql) => {
      expect(sql).toContain('FROM sync_objects');
      expect(sql).toContain("payload->>'notes' ILIKE $3");
      return rows([task]);
    });

    await expect(
      service.tasks(
        {
          q: '  legacy  ',
          from: '2026-06-01T00:00:00.000Z',
          to: 'not-a-date',
          limit: '0',
        },
        context,
      ),
    ).resolves.toEqual({
      limit: 1,
      items: [
        {
          id: 'task-1',
          uid: 'task-uid-1',
          objectType: 'task_item',
          title: 'Legacy task',
          status: 'done',
          dueAt: '2026-06-09T10:00:00.000Z',
          location: 'Office',
          syncStatus: 'server',
          serverVersion: 3,
          updatedAt: '2026-06-07T12:00:00.000Z',
          payload: expect.objectContaining({
            title: 'Legacy task',
            status: 'done',
            priority: 'normal',
          }),
        },
      ],
    });
    expect(devices.ensureDevice).not.toHaveBeenCalled();
    expect(database.query).toHaveBeenCalledWith(expect.any(String), [
      context.userId,
      ['task_item'],
      '%legacy%',
      new Date('2026-06-01T00:00:00.000Z'),
      null,
      1,
    ]);
  });

  it('lists objects with default pagination and schema fallbacks for blank titles and statuses', async () => {
    const task = taskRow({
      payload: { title: null, summary: '   ', name: '', status: 'unknown', priority: 'bad' },
    });
    const event = eventRow({
      payload: { title: null, summary: '', name: '   ', status: 'unknown', isBlock: false },
    });
    const { service, database } = createService(async (_sql, params) => {
      const objectTypes = params?.[1];
      return rows(Array.isArray(objectTypes) && objectTypes.includes('calendar_event') ? [event] : [task]);
    });

    const taskResult = await service.tasks({}, context);
    const eventResult = await service.events({}, context);

    expect(taskResult.limit).toBe(20);
    expect(taskResult.items[0]).toMatchObject({
      title: expect.any(String),
      status: 'todo',
      location: '',
      payload: expect.objectContaining({
        title: expect.any(String),
        status: 'todo',
        priority: 'normal',
      }),
    });
    expect(String(taskResult.items[0].title).length).toBeGreaterThan(0);
    expect(eventResult.limit).toBe(20);
    expect(eventResult.items[0]).toMatchObject({
      title: expect.any(String),
      status: 'confirmed',
      location: '',
      notes: '',
      description: '',
      isBlock: false,
    });
    expect(String(eventResult.items[0].title).length).toBeGreaterThan(0);
    expect(database.query).toHaveBeenNthCalledWith(1, expect.any(String), [
      context.userId,
      ['task_item'],
      null,
      null,
      null,
      20,
    ]);
    expect(database.query).toHaveBeenNthCalledWith(2, expect.any(String), [
      context.userId,
      ['calendar_event'],
      null,
      null,
      null,
      20,
    ]);
  });

  it('lists events with date filters and event view models', async () => {
    const event = eventRow({
      payload: {
        summary: 'Team sync',
        dtstart: '2026-06-08T10:00:00.000Z',
        dtend: '2026-06-08T11:00:00.000Z',
        status: 'canceled',
        blocking: 'true',
        description: 'Agenda',
      },
    });
    const { service, database } = createService(async () => rows([event]));

    const result = await service.events(
      { from: '2026-06-08', to: '2026-06-09', limit: '3.9' },
      context,
    );

    expect(result).toEqual({
      limit: 3,
      items: [
        {
          id: 'event-1',
          uid: 'event-uid-1',
          objectType: 'calendar_event',
          title: 'Team sync',
          startAt: '2026-06-08T10:00:00.000Z',
          endAt: '2026-06-08T11:00:00.000Z',
          status: 'cancelled',
          location: '',
          notes: 'Agenda',
          description: 'Agenda',
          isBlock: true,
          syncStatus: 'server',
          serverVersion: 4,
          updatedAt: '2026-06-07T12:00:00.000Z',
          payload: expect.objectContaining({
            title: 'Team sync',
            status: 'cancelled',
          }),
        },
      ],
    });
    expect(database.query).toHaveBeenCalledWith(expect.any(String), [
      context.userId,
      ['calendar_event'],
      null,
      new Date('2026-06-08'),
      new Date('2026-06-09'),
      3,
    ]);
  });

  it('creates tasks with generated uid, sync change, audit metadata and canonical response', async () => {
    const inserted = taskRow({
      id: 'task-new',
      uid: 'task_item:00000000-0000-4000-8000-00000000feed',
      payload: {
        title: 'New task',
        status: 'todo',
        priority: 'normal',
        dueAt: '2026-06-08T12:00:00.000Z',
        source: 'web',
      },
      serverVersion: 1,
    });
    const { service, database, transactionClient } = createService(
      async () => rows(),
      async (sql) => {
        if (sql.includes('SELECT id::text') && sql.includes('AND uid = $3')) {
          return rows();
        }
        if (sql.includes('INSERT INTO sync_objects')) {
          return rows([inserted]);
        }
        if (sql.includes('INSERT INTO sync_changes')) {
          return rows([{ id: 'change-create' }]);
        }
        if (sql.includes('INSERT INTO audit_logs')) {
          return rows([{ id: 'audit-create' }]);
        }
        return rows();
      },
    );

    const result = await service.createTask(
      {
        title: ' New task ',
        status: 'pending',
        due: '2026-06-08T12:00:00.000Z',
        updatedFrom: 'web',
      },
      context,
    );

    expect(result).toEqual({
      ok: true,
      canonical: true,
      item: expect.objectContaining({
        id: 'task-new',
        uid: 'task_item:00000000-0000-4000-8000-00000000feed',
        title: 'New task',
        status: 'todo',
        dueAt: '2026-06-08T12:00:00.000Z',
      }),
      serverVersion: 1,
      syncChangeId: 'change-create',
      auditId: 'audit-create',
      replayed: false,
    });
    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO sync_objects'),
      [
        context.userId,
        'task_item',
        'task_item:00000000-0000-4000-8000-00000000feed',
        expect.stringContaining('"title":"New task"'),
        context.deviceId,
      ],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining('INSERT INTO sync_changes'),
      [
        context.userId,
        context.deviceId,
        'task-new',
        'task_item',
        'create',
        1,
        JSON.stringify(inserted.payload),
      ],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      4,
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([
        context.userId,
        context.deviceId,
        'web.task_item.create',
        'task-new',
        expect.stringContaining('"uid":"task_item:00000000-0000-4000-8000-00000000feed"'),
      ]),
    );
  });

  it('replays createTask when a matching live uid already exists', async () => {
    const existing = taskRow({
      id: 'task-existing',
      uid: 'task_item:00000000-0000-4000-8000-00000000feed',
      payload: { title: 'Existing task', status: 'todo' },
      serverVersion: 8,
    });
    const { service, transactionClient } = createService(
      async () => rows(),
      async (sql) => {
        if (sql.includes('AND uid = $3')) {
          return rows([existing]);
        }
        return rows();
      },
    );

    await expect(
      service.createTask({ title: 'Ignored duplicate' }, context),
    ).resolves.toEqual({
      ok: true,
      canonical: true,
      item: expect.objectContaining({
        id: 'task-existing',
        uid: 'task_item:00000000-0000-4000-8000-00000000feed',
        title: 'Existing task',
      }),
      serverVersion: 8,
      syncChangeId: null,
      auditId: null,
      replayed: true,
    });
    expect(transactionClient.query).toHaveBeenCalledTimes(1);
    expect(transactionClient.query).toHaveBeenCalledWith(
      expect.stringContaining('AND uid = $3'),
      [context.userId, 'task_item', 'task_item:00000000-0000-4000-8000-00000000feed'],
    );
  });

  it('creates events with normalized payload and event audit action', async () => {
    const inserted = eventRow({
      id: 'event-new',
      uid: 'calendar_event:00000000-0000-4000-8000-00000000feed',
      payload: {
        title: 'Planning block',
        startAt: '2026-06-08T13:00:00.000Z',
        endAt: '2026-06-08T14:00:00.000Z',
        status: 'confirmed',
        isBlock: true,
      },
      serverVersion: 2,
    });
    const { service, transactionClient } = createService(
      async () => rows(),
      async (sql) => {
        if (sql.includes('SELECT id::text') && sql.includes('AND uid = $3')) {
          return rows();
        }
        if (sql.includes('INSERT INTO sync_objects')) {
          return rows([inserted]);
        }
        if (sql.includes('INSERT INTO sync_changes')) {
          return rows([{ id: 'change-event-create' }]);
        }
        if (sql.includes('INSERT INTO audit_logs')) {
          return rows([{ id: 'audit-event-create' }]);
        }
        return rows();
      },
    );

    const result = await service.createEvent(
      {
        uid: 'event-uid-new',
        name: 'Planning block',
        dtstart: '2026-06-08T13:00:00.000Z',
        dtend: '2026-06-08T14:00:00.000Z',
        kind: 'blocking',
      },
      context,
    );

    expect(result).toEqual({
      ok: true,
      canonical: true,
      item: expect.objectContaining({
        id: 'event-new',
        objectType: 'calendar_event',
        title: 'Planning block',
        isBlock: true,
      }),
      serverVersion: 2,
      syncChangeId: 'change-event-create',
      auditId: 'audit-event-create',
      replayed: false,
    });
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO sync_objects'),
      [
        context.userId,
        'calendar_event',
        'calendar_event:00000000-0000-4000-8000-00000000feed',
        expect.stringContaining('"startAt":"2026-06-08T13:00:00.000Z"'),
        context.deviceId,
      ],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      4,
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining(['web.calendar_event.create', 'event-new']),
    );
  });

  it('updates tasks with optimistic version checks, change rows and before/after audit metadata', async () => {
    const beforePayload = { title: 'Before', status: 'todo', priority: 'normal' };
    const updated = taskRow({
      id: 'task-1',
      payload: { title: 'After', status: 'in_progress', priority: 'urgent' },
      serverVersion: 6,
    });
    const { service, transactionClient } = createService(
      async () => rows(),
      async (sql) => {
        if (sql.includes('SELECT payload, server_version')) {
          return rows([{ payload: beforePayload, serverVersion: 5 }]);
        }
        if (sql.includes('UPDATE sync_objects')) {
          return rows([updated]);
        }
        if (sql.includes('INSERT INTO sync_changes')) {
          return rows([{ id: 'change-update' }]);
        }
        if (sql.includes('INSERT INTO audit_logs')) {
          return rows([{ id: 'audit-update' }]);
        }
        return rows();
      },
    );

    const result = await service.updateTask(
      'task-1',
      { title: ' After ', status: 'doing', priority: 'urgent', baseServerVersion: '5' },
      context,
    );

    expect(result).toEqual({
      ok: true,
      canonical: true,
      item: expect.objectContaining({
        id: 'task-1',
        title: 'After',
        status: 'in_progress',
        serverVersion: 6,
      }),
      serverVersion: 6,
      syncChangeId: 'change-update',
      auditId: 'audit-update',
    });
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('SET payload = payload || $3::jsonb'),
      [
        context.userId,
        'task-1',
        expect.stringContaining('"status":"in_progress"'),
        context.deviceId,
      ],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      4,
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([
        'web.task_item.update',
        'task-1',
        expect.stringContaining('"before":{"title":"Before","status":"todo","priority":"normal"}'),
      ]),
    );
  });

  it('returns a non-canonical update response when the object is missing', async () => {
    const { service, transactionClient } = createService(
      async () => rows(),
      async (sql) => {
        if (sql.includes('SELECT payload, server_version')) {
          return rows();
        }
        throw new Error(`unexpected query: ${sql}`);
      },
    );

    await expect(service.updateEvent('missing-event', { title: 'Missing' }, context)).resolves.toEqual({
      ok: false,
      canonical: false,
      item: null,
      serverVersion: null,
      syncChangeId: null,
      auditId: null,
    });
    expect(transactionClient.query).toHaveBeenCalledTimes(1);
  });

  it('returns a non-canonical update response when the update returns no row', async () => {
    const { service, transactionClient } = createService(
      async () => rows(),
      async (sql) => {
        if (sql.includes('SELECT payload, server_version')) {
          return rows([{ payload: { title: 'Existing' }, serverVersion: 2 }]);
        }
        if (sql.includes('UPDATE sync_objects')) {
          return rows();
        }
        throw new Error(`unexpected query: ${sql}`);
      },
    );

    await expect(service.updateTask('task-1', { title: 'Changed' }, context)).resolves.toEqual({
      ok: false,
      canonical: false,
      item: null,
      serverVersion: null,
      syncChangeId: null,
      auditId: null,
    });
    expect(transactionClient.query).toHaveBeenCalledTimes(2);
  });

  it('throws a ConflictException when baseServerVersion is stale', async () => {
    const { service, transactionClient } = createService(
      async () => rows(),
      async (sql) => {
        if (sql.includes('SELECT payload, server_version')) {
          return rows([{ payload: { title: 'Current' }, serverVersion: 9 }]);
        }
        throw new Error(`unexpected query: ${sql}`);
      },
    );

    await expect(
      service.updateTask('task-1', { title: 'Stale', baseServerVersion: '8' }, context),
    ).rejects.toBeInstanceOf(ConflictException);
    expect(transactionClient.query).toHaveBeenCalledTimes(1);
  });

  it('completes tasks using explicit completion time and merges payload overrides', async () => {
    const beforePayload = { title: 'Task', status: 'todo' };
    const updated = taskRow({
      id: 'task-1',
      payload: {
        title: 'Task',
        status: 'done',
        completedAt: '2026-06-08T15:00:00.000Z',
        notes: 'Wrapped up',
      },
      serverVersion: 7,
    });
    const { service, transactionClient } = createService(
      async () => rows(),
      async (sql) => {
        if (sql.includes('SELECT payload, server_version')) {
          return rows([{ payload: beforePayload, serverVersion: 6 }]);
        }
        if (sql.includes('UPDATE sync_objects')) {
          return rows([updated]);
        }
        if (sql.includes('INSERT INTO sync_changes')) {
          return rows([{ id: 'change-complete' }]);
        }
        if (sql.includes('INSERT INTO audit_logs')) {
          return rows([{ id: 'audit-complete' }]);
        }
        return rows();
      },
    );

    const result = await service.completeTask(
      'task-1',
      {
        completedAt: '2026-06-08T15:00:00.000Z',
        baseServerVersion: '6',
        payload: { notes: 'Wrapped up' },
      },
      context,
    );

    expect(result.item).toEqual(
      expect.objectContaining({
        status: 'done',
        payload: expect.objectContaining({
          notes: 'Wrapped up',
        }),
      }),
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('UPDATE sync_objects'),
      [
        context.userId,
        'task-1',
        expect.stringContaining('"completedAt":"2026-06-08T15:00:00.000Z"'),
        context.deviceId,
      ],
    );
    expect(transactionClient.query.mock.calls[1][1][2]).toContain('"notes":"Wrapped up"');
  });

  it('uses the current time when completeTask has no completion timestamp', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-08T16:17:18.000Z'));
    const updated = taskRow({
      payload: { title: 'Task', status: 'done', completedAt: '2026-06-08T16:17:18.000Z' },
      serverVersion: 2,
    });
    const { service, transactionClient } = createService(
      async () => rows(),
      async (sql) => {
        if (sql.includes('SELECT payload, server_version')) {
          return rows([{ payload: { title: 'Task' }, serverVersion: 1 }]);
        }
        if (sql.includes('UPDATE sync_objects')) {
          return rows([updated]);
        }
        if (sql.includes('INSERT INTO sync_changes')) {
          return rows([{ id: 'change-complete-now' }]);
        }
        if (sql.includes('INSERT INTO audit_logs')) {
          return rows([{ id: 'audit-complete-now' }]);
        }
        return rows();
      },
    );

    await service.completeTask('task-1', {}, context);

    expect(transactionClient.query.mock.calls[1][1][2]).toContain(
      '"completedAt":"2026-06-08T16:17:18.000Z"',
    );
  });

  it('soft deletes tasks and emits delete sync/audit rows', async () => {
    const deleted = taskRow({
      id: 'task-delete',
      payload: { title: 'Delete me', status: 'todo' },
      serverVersion: 10,
    });
    const { service, transactionClient } = createService(
      async () => rows(),
      async (sql) => {
        if (sql.includes('UPDATE sync_objects')) {
          return rows([deleted]);
        }
        if (sql.includes('INSERT INTO sync_changes')) {
          return rows([{ id: 'change-delete' }]);
        }
        if (sql.includes('INSERT INTO audit_logs')) {
          return rows([{ id: 'audit-delete' }]);
        }
        return rows();
      },
    );

    await expect(service.deleteTask('task-delete', context)).resolves.toEqual({
      ok: true,
      canonical: true,
      deleted: true,
      id: 'task-delete',
      serverVersion: 10,
      syncChangeId: 'change-delete',
      auditId: 'audit-delete',
    });
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('AND object_type = $3'),
      [context.userId, 'task-delete', 'task_item', context.deviceId],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO sync_changes'),
      [
        context.userId,
        context.deviceId,
        'task-delete',
        'task_item',
        'delete',
        10,
        JSON.stringify(deleted.payload),
      ],
    );
  });

  it('returns a false delete response when event deletion finds no row', async () => {
    const { service, transactionClient } = createService(async () => rows());

    await expect(service.deleteEvent('event-missing', context)).resolves.toEqual({
      ok: false,
      canonical: false,
      deleted: false,
      id: 'event-missing',
      serverVersion: null,
      syncChangeId: null,
      auditId: null,
    });
    expect(transactionClient.query).toHaveBeenCalledTimes(1);
    expect(transactionClient.query).toHaveBeenCalledWith(
      expect.stringContaining('AND object_type = $3'),
      [context.userId, 'event-missing', 'calendar_event', context.deviceId],
    );
  });

  it('lists actual activity records with clamped limit and nullable date filters', async () => {
    const actuals = [
      {
        id: 'actual-1',
        actualUid: 'actual-uid-1',
        title: 'Coding',
        startAt: '2026-06-08T09:00:00.000Z',
      },
    ];
    const { service, database, devices } = createService(async (sql) => {
      expect(sql).toContain('FROM actual_activity_logs');
      return rows(actuals);
    });

    await expect(
      service.actualRecords({ from: 'bad-date', to: '2026-06-09T00:00:00.000Z', limit: '-5' }, context),
    ).resolves.toEqual({ items: actuals });
    expect(devices.ensureDevice).not.toHaveBeenCalled();
    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('FROM actual_activity_logs'), [
      context.userId,
      null,
      new Date('2026-06-09T00:00:00.000Z'),
      1,
    ]);
  });

  it('returns reminders for dated tasks and events only', async () => {
    const { service, database } = createService(async (sql) => {
      expect(sql).toContain('object_type = ANY($2::text[])');
      return rows([
        taskRow({
          id: 'task-dated',
          payload: { title: 'Dated task', dueAt: '2026-06-08T18:00:00.000Z' },
        }),
        taskRow({
          id: 'task-undated',
          uid: 'task-undated',
          payload: { title: 'Undated task' },
        }),
        eventRow({
          id: 'event-dated',
          payload: {
            title: 'Dated event',
            startAt: '2026-06-08T19:00:00.000Z',
            endAt: '2026-06-08T20:00:00.000Z',
          },
        }),
      ]);
    });

    const result = await service.reminders(context);

    expect(result.items).toEqual([
      expect.objectContaining({ id: 'task-dated', dueAt: '2026-06-08T18:00:00.000Z' }),
      expect.objectContaining({ id: 'event-dated', startAt: '2026-06-08T19:00:00.000Z' }),
    ]);
    expect(database.query).toHaveBeenCalledWith(expect.any(String), [
      context.userId,
      ['task_item', 'calendar_event'],
    ]);
  });

  it('audits prepareOperation with generated confirmation token', async () => {
    const { service, database } = createService(async (sql) => {
      expect(sql).toContain('INSERT INTO audit_logs');
      return rows([{ id: 'audit-prepare' }]);
    });

    await expect(
      service.prepareOperation('dangerous', { dryRun: false, targetId: 'job-1' }, context),
    ).resolves.toEqual({
      ok: true,
      operationKey: 'dangerous',
      confirmationToken: '00000000-0000-4000-8000-00000000feed',
      dryRun: true,
      impact: expect.any(String),
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        context.userId,
        context.deviceId,
        'web.operation.dangerous.prepare',
        'dangerous',
        'web.operation.dangerous.prepare',
        expect.stringContaining('"confirmationToken":"00000000-0000-4000-8000-00000000feed"'),
      ],
    );
  });

  it('audits confirmOperation with a cleaned confirmation token', async () => {
    const { service, database } = createService(async () => rows([{ id: 'audit-confirm' }]));

    await expect(
      service.confirmOperation('dangerous', { confirmationToken: ' token-123 ', reason: 'operator' }, context),
    ).resolves.toEqual({
      ok: true,
      operationKey: 'dangerous',
      status: 'confirmed_audited',
      note: expect.any(String),
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        context.userId,
        context.deviceId,
        'web.operation.dangerous.confirm',
        'dangerous',
        'web.operation.dangerous.confirm',
        expect.stringContaining('"confirmationToken":"token-123"'),
      ],
    );
  });

  it('builds dashboard summaries from today objects, reminders, and sync counters', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-08T08:30:00.000Z'));
    const openTask = {
      id: 'task-today',
      uid: 'task-today',
      objectType: 'task_item',
      title: 'Today task',
      status: 'todo',
      dueAt: '2026-06-08T10:00:00.000Z',
      location: '',
      syncStatus: 'server',
      serverVersion: 1,
      updatedAt: '2026-06-08T01:00:00.000Z',
      payload: { title: 'Today task', status: 'todo' },
    };
    const doneTask = {
      ...openTask,
      id: 'task-done',
      status: 'done',
      dueAt: '2026-06-08T11:00:00.000Z',
    };
    const currentEvent = {
      id: 'event-current',
      title: 'Current event',
      startAt: '2026-06-08T08:00:00.000Z',
      endAt: '2026-06-08T09:00:00.000Z',
    };
    const futureEvent = {
      id: 'event-future',
      title: 'Future event',
      startAt: '2026-06-08T09:30:00.000Z',
      endAt: '2026-06-08T10:30:00.000Z',
    };
    const previousActual = {
      id: 'actual-today',
      title: 'Focus',
      startAt: '2026-06-08T07:00:00.000Z',
    };
    const { service, database } = createService(async (sql) => {
      if (sql.includes('FROM sync_conflicts')) {
        return rows([{ count: '2' }]);
      }
      if (sql.includes('FROM sync_mutations')) {
        return rows([{ failedMutations: '3', pendingMutations: '4' }]);
      }
      return rows();
    });
    vi.spyOn(service, 'tasks').mockResolvedValue({
      items: [
        openTask,
        doneTask,
        {
          ...openTask,
          id: 'task-old',
          dueAt: '2026-06-07T10:00:00.000Z',
        },
      ],
    } as never);
    vi.spyOn(service, 'events').mockResolvedValue({
      items: [
        currentEvent,
        futureEvent,
        {
          id: 'event-tomorrow',
          startAt: '2026-06-09T08:00:00.000Z',
          endAt: '2026-06-09T09:00:00.000Z',
        },
      ],
    } as never);
    vi.spyOn(service, 'actualRecords').mockResolvedValue({
      items: [
        previousActual,
        {
          id: 'actual-old',
          startAt: 'not-a-date',
        },
      ],
    } as never);
    vi.spyOn(service, 'reminders').mockResolvedValue({
      items: [{ id: 'reminder-1', dueAt: '2026-06-08T10:00:00.000Z' }],
    } as never);

    const result = await service.dashboard(context);

    expect(result).toEqual({
      ok: true,
      mode: 'user_web_client',
      generatedAt: '2026-06-08T08:30:00.000Z',
      profile: {
        userId: context.userId,
        deviceId: context.deviceId,
        note: expect.any(String),
      },
      today: {
        date: '2026-06-08',
        tasks: [openTask],
        events: [currentEvent, futureEvent],
        actualRecords: [previousActual],
        current: currentEvent,
        next: futureEvent,
      },
      lists: {
        openTasks: [
          openTask,
          {
            ...openTask,
            id: 'task-old',
            dueAt: '2026-06-07T10:00:00.000Z',
          },
        ],
        reminders: [{ id: 'reminder-1', dueAt: '2026-06-08T10:00:00.000Z' }],
      },
      sync: {
        openConflicts: 2,
        failedMutations: 3,
        pendingMutations: 4,
      },
    });
    expect(service.tasks).toHaveBeenCalledWith({ limit: '80' }, context);
    expect(service.events).toHaveBeenCalledWith({ limit: '80' }, context);
    expect(service.actualRecords).toHaveBeenCalledWith({ limit: '40' }, context);
    expect(database.query).toHaveBeenCalledTimes(2);
  });

  it('falls back dashboard counters to zero and next/current to null when nothing is scheduled', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-08T08:30:00.000Z'));
    const { service } = createService(async () => rows([{}]));
    vi.spyOn(service, 'tasks').mockResolvedValue({ items: [] } as never);
    vi.spyOn(service, 'events').mockResolvedValue({
      items: [
        {
          id: 'event-yesterday-text',
          startAt: '2026-06-07',
          endAt: '2026-06-07',
        },
      ],
    } as never);
    vi.spyOn(service, 'actualRecords').mockResolvedValue({ items: [] } as never);
    vi.spyOn(service, 'reminders').mockResolvedValue({ items: [] } as never);

    const result = await service.dashboard(context);

    expect(result.today).toEqual({
      date: '2026-06-08',
      tasks: [],
      events: [],
      actualRecords: [],
      current: null,
      next: null,
    });
    expect(result.sync).toEqual({
      openConflicts: 0,
      failedMutations: 0,
      pendingMutations: 0,
    });
  });

  it('ignores blank dashboard dates when computing today and upcoming lists', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-08T08:30:00.000Z'));
    const { service } = createService(async () => rows([{}]));
    vi.spyOn(service, 'tasks').mockResolvedValue({
      items: [{ id: 'task-empty-due', dueAt: '' }],
    } as never);
    vi.spyOn(service, 'events').mockResolvedValue({
      items: [{ id: 'event-empty-start', startAt: '', endAt: '' }],
    } as never);
    vi.spyOn(service, 'actualRecords').mockResolvedValue({
      items: [{ id: 'actual-empty-start', startAt: null }],
    } as never);
    vi.spyOn(service, 'reminders').mockResolvedValue({ items: [] } as never);

    const result = await service.dashboard(context);

    expect(result.today).toMatchObject({
      tasks: [],
      events: [],
      actualRecords: [],
      current: null,
      next: null,
    });
    expect(result.lists.openTasks).toEqual([{ id: 'task-empty-due', dueAt: '' }]);
  });

  it('creates tasks with defensive persistence fallbacks when insert helpers return sparse rows', async () => {
    const inserted = taskRow({
      id: 'task-sparse',
      uid: 'task_item:00000000-0000-4000-8000-00000000feed',
      payload: undefined,
      serverVersion: undefined,
    });
    const { service, transactionClient } = createService(
      async () => rows(),
      async (sql) => {
        if (sql.includes('SELECT id::text') && sql.includes('AND uid = $3')) {
          return rows();
        }
        if (sql.includes('INSERT INTO sync_objects')) {
          return rows([inserted]);
        }
        if (sql.includes('INSERT INTO sync_changes')) {
          return rows();
        }
        if (sql.includes('INSERT INTO audit_logs')) {
          return rows();
        }
        return rows();
      },
    );

    const result = await service.createTask({ title: 'Sparse task' }, context);

    expect(result).toMatchObject({
      ok: true,
      canonical: true,
      serverVersion: 1,
      syncChangeId: null,
      auditId: null,
      replayed: false,
    });
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining('INSERT INTO sync_changes'),
      [
        context.userId,
        context.deviceId,
        'task-sparse',
        'task_item',
        'create',
        1,
        JSON.stringify({}),
      ],
    );
  });

  it('ignores sparse event windows when finding the current event', () => {
    const { service } = createService();
    const currentEvent = (
      service as unknown as {
        currentEvent: (items: Array<Record<string, unknown>>) => Record<string, unknown> | null;
      }
    ).currentEvent([
      { id: 'missing-start' },
      { id: 'missing-end', startAt: '2026-06-08T08:00:00.000Z' },
    ]);

    expect(currentEvent).toBeNull();
  });
});
