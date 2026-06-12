import { describe, expect, it, vi } from 'vitest';
import { SyncObjectRepository, type SyncObjectRow } from './sync-object.repository';
import type { DatabaseService, TransactionClient } from '../../database/database.service';

function queryResult<T>(rows: T[]) {
  return { rows };
}

function makeDatabase(rows: unknown[] = []) {
  return {
    query: vi.fn(async () => queryResult(rows)),
  };
}

describe('SyncObjectRepository', () => {
  const row: SyncObjectRow = {
    id: 'object-1',
    objectType: 'task_item',
    uid: 'uid-1',
    payload: { title: 'Task' },
    deletedAt: null,
    serverVersion: 7,
    updatedAt: new Date('2026-01-01T00:00:00.000Z'),
  };

  it('finds a non-deleted object by uid using an explicit transaction client', async () => {
    const database = makeDatabase();
    const client = {
      query: vi.fn(async () => queryResult([row])),
    };
    const repository = new SyncObjectRepository(database as unknown as DatabaseService);

    await expect(
      repository.findByUid('user-1', 'task_item', 'uid-1', client as unknown as TransactionClient),
    ).resolves.toEqual(row);

    expect(client.query).toHaveBeenCalledWith(expect.stringContaining('deleted_at IS NULL'), [
      'user-1',
      'task_item',
      'uid-1',
    ]);
    expect(database.query).not.toHaveBeenCalled();
  });

  it('returns null when findByUid has no matching rows', async () => {
    const database = makeDatabase([]);
    const repository = new SyncObjectRepository(database as unknown as DatabaseService);

    await expect(repository.findByUid('user-1', 'task_item', 'missing')).resolves.toBeNull();
  });

  it('finds by server id through the default database connection', async () => {
    const database = makeDatabase([row]);
    const repository = new SyncObjectRepository(database as unknown as DatabaseService);

    await expect(repository.findById('user-1', 'object-1')).resolves.toEqual(row);

    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('WHERE user_id = $1 AND id = $2'), [
      'user-1',
      'object-1',
    ]);
  });

  it('returns null when findById has no rows', async () => {
    const database = makeDatabase([]);
    const repository = new SyncObjectRepository(database as unknown as DatabaseService);

    await expect(repository.findById('user-1', 'missing')).resolves.toBeNull();
  });

  it('lists non-deleted objects by type with default pagination', async () => {
    const database = makeDatabase([row]);
    const repository = new SyncObjectRepository(database as unknown as DatabaseService);

    await expect(repository.listByType('user-1', ['task_item', 'calendar_event'])).resolves.toEqual([
      row,
    ]);

    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('ORDER BY updated_at DESC'), [
      'user-1',
      ['task_item', 'calendar_event'],
      200,
      0,
    ]);
  });

  it('lists objects with caller-provided limit and offset', async () => {
    const database = makeDatabase([row]);
    const repository = new SyncObjectRepository(database as unknown as DatabaseService);

    await repository.listByType('user-1', ['task_item'], 25, 50);

    expect(database.query).toHaveBeenCalledWith(expect.any(String), [
      'user-1',
      ['task_item'],
      25,
      50,
    ]);
  });

  it('records sync changes with JSON payloads', async () => {
    const client = {
      query: vi.fn(async () => queryResult([])),
    };
    const repository = new SyncObjectRepository(makeDatabase() as unknown as DatabaseService);

    await repository.recordChange(
      client as unknown as TransactionClient,
      'user-1',
      'device-1',
      'object-1',
      'task_item',
      'update',
      8,
      { title: 'Updated' },
    );

    expect(client.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO sync_changes'), [
      'user-1',
      'device-1',
      'object-1',
      'task_item',
      'update',
      8,
      JSON.stringify({ title: 'Updated' }),
    ]);
  });

  it('records an empty JSON object when recordChange receives a nullish payload', async () => {
    const client = {
      query: vi.fn(async () => queryResult([])),
    };
    const repository = new SyncObjectRepository(makeDatabase() as unknown as DatabaseService);

    await repository.recordChange(
      client as unknown as TransactionClient,
      'user-1',
      'device-1',
      'object-1',
      'task_item',
      'delete',
      9,
      null as unknown as Record<string, unknown>,
    );

    expect(client.query).toHaveBeenCalledWith(expect.any(String), [
      'user-1',
      'device-1',
      'object-1',
      'task_item',
      'delete',
      9,
      '{}',
    ]);
  });

  it('parses countByType counts and defaults missing counts to zero', async () => {
    const countedDatabase = makeDatabase([{ count: '12' }]);
    const countedRepository = new SyncObjectRepository(
      countedDatabase as unknown as DatabaseService,
    );

    await expect(countedRepository.countByType('user-1', ['task_item'])).resolves.toBe(12);
    expect(countedDatabase.query).toHaveBeenCalledWith(expect.stringContaining('COUNT(*)::int AS count'), [
      'user-1',
      ['task_item'],
    ]);

    const emptyRepository = new SyncObjectRepository(
      makeDatabase([]) as unknown as DatabaseService,
    );

    await expect(emptyRepository.countByType('user-1', ['task_item'])).resolves.toBe(0);
  });
});
