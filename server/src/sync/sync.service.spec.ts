import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { DatabaseService } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import { SyncService } from './sync.service';
import { cleanDatabase, createTestUser, createTestDevice } from '../common/test/test-utils';
import type { FlowPlanV2RequestContext } from '../common/request-context';
import type { SyncMutationDto } from './dto';

describe('SyncService', () => {
  let db: DatabaseService;
  let sync: SyncService;
  let devices: DevicesService;

  let ctxA: FlowPlanV2RequestContext;
  let ctxB: FlowPlanV2RequestContext;

  beforeAll(async () => {
    db = new DatabaseService();
    await db.onModuleInit();
    devices = new DevicesService(db);
    sync = new SyncService(db, devices);
  });

  afterAll(async () => {
    await db.onModuleDestroy();
  });

  beforeEach(async () => {
    await cleanDatabase(db);
    const user = await createTestUser(db, {
      id: '00000000-0000-0000-0000-000000000001',
    });
    const devA = await createTestDevice(db, user.id, {
      id: '00000000-0000-0000-0000-000000000101',
    });
    const devB = await createTestDevice(db, user.id, {
      id: '00000000-0000-0000-0000-000000000102',
    });
    ctxA = { userId: user.id, deviceId: devA.id };
    ctxB = { userId: user.id, deviceId: devB.id };
  });

  // ---- helpers ----

  const makeMutation = (overrides: Partial<SyncMutationDto> = {}): SyncMutationDto => ({
    mutationUid: 'mut-001',
    objectType: 'task_item',
    localId: 'local-1',
    action: 'upsert',
    payload: { title: 'Test task' },
    ...overrides,
  });

  // ========================================================================
  // push
  // ========================================================================
  describe('push', () => {
    it('accepts a new mutation and records it', async () => {
      const result = await sync.push(
        { mutations: [makeMutation()] },
        ctxA,
      );
      expect(result.accepted).toHaveLength(1);
      expect(result.accepted[0].mutationUid).toBe('mut-001');
      expect(result.accepted[0].objectType).toBe('task_item');
      expect(result.accepted[0].serverVersion).toBe(1);
    });

    it('is idempotent — replay returns accepted without change', async () => {
      const first = await sync.push(
        { mutations: [makeMutation()] },
        ctxA,
      );
      const second = await sync.push(
        { mutations: [makeMutation()] },
        ctxA,
      );
      expect(second.accepted).toHaveLength(1);
      // Same server version as before — nothing changed
      expect(second.accepted[0].serverVersion).toBe(
        first.accepted[0].serverVersion,
      );
    });

    it('rejects mutations missing required fields', async () => {
      const result = await sync.push(
        { mutations: [{ mutationUid: '', objectType: '', localId: '', action: 'upsert', payload: {} }] },
        ctxA,
      );
      expect(result.rejected).toHaveLength(1);
      expect(result.rejected[0].reason).toContain('required');
    });

    it('creates a conflict when baseServerVersion is stale', async () => {
      // Device A creates an object
      const created = await sync.push(
        { mutations: [makeMutation({ mutationUid: 'mut-create' })] },
        ctxA,
      );

      // Device B also modifies the same object with a stale version
      const result = await sync.push(
        {
          mutations: [
            makeMutation({
              mutationUid: 'mut-conflict',
              localId: 'local-2',
              serverId: created.accepted[0].serverId,
              baseServerVersion: 0, // stale
              payload: { title: 'Conflicting title' },
            }),
          ],
        },
        ctxB,
      );
      expect(result.conflicts).toHaveLength(1);
      expect(result.conflicts[0].objectType).toBe('task_item');
      expect(result.conflicts[0].serverVersion).toBe(1);
    });

    it('rejects outlook read-only calendar events', async () => {
      const result = await sync.push(
        {
          mutations: [
            makeMutation({
              mutationUid: 'mut-outlook',
              objectType: 'calendar_event',
              payload: { title: 'Outlook event', source: 'outlook' },
            }),
          ],
        },
        ctxA,
      );
      expect(result.rejected).toHaveLength(1);
      expect(result.rejected[0].reason).toContain('read-only');
    });

    it('deletes an existing object', async () => {
      const created = await sync.push(
        { mutations: [makeMutation({ mutationUid: 'mut-create' })] },
        ctxA,
      );
      const result = await sync.push(
        {
          mutations: [
            makeMutation({
              mutationUid: 'mut-delete',
              serverId: created.accepted[0].serverId,
              action: 'delete',
              payload: {},
            }),
          ],
        },
        ctxA,
      );
      expect(result.accepted).toHaveLength(1);

      // Verify it's deleted in the database
      const obj = await db.query(
        'SELECT deleted_at FROM sync_objects WHERE id = $1',
        [created.accepted[0].serverId],
      );
      expect(obj.rows[0].deleted_at).toBeTruthy();
    });

    it('restores a deleted object when upserted again', async () => {
      const created = await sync.push(
        { mutations: [makeMutation({ mutationUid: 'mut-create' })] },
        ctxA,
      );
      // Delete it
      await sync.push(
        {
          mutations: [
            makeMutation({
              mutationUid: 'mut-delete',
              serverId: created.accepted[0].serverId,
              action: 'delete',
              payload: {},
            }),
          ],
        },
        ctxA,
      );
      // Restore it
      const result = await sync.push(
        {
          mutations: [
            makeMutation({
              mutationUid: 'mut-restore',
              serverId: created.accepted[0].serverId,
              uid: 'task-uid-restore',
              action: 'upsert',
              payload: { title: 'Restored' },
            }),
          ],
        },
        ctxA,
      );
      expect(result.accepted).toHaveLength(1);
      const obj = await db.query(
        'SELECT deleted_at, payload FROM sync_objects WHERE id = $1',
        [created.accepted[0].serverId],
      );
      expect(obj.rows[0].deleted_at).toBeNull();
    });
  });

  // ========================================================================
  // pull
  // ========================================================================
  describe('pull', () => {
    it('returns changes after a given cursor', async () => {
      // Push 3 mutations
      for (let i = 1; i <= 3; i++) {
        await sync.push(
          { mutations: [makeMutation({ mutationUid: `mut-00${i}`, localId: `local-${i}` })] },
          ctxA,
        );
      }

      // Pull with cursor 0 — should get all 3
      const pull1 = await sync.pull(undefined, ctxB);
      expect(pull1.changes).toHaveLength(3);
      expect(pull1.nextCursor).toBeTruthy();

      // Pull again with cursor — should be empty
      const pull2 = await sync.pull(pull1.nextCursor, ctxB);
      expect(pull2.changes).toHaveLength(0);
    });

    it('filters by objectType', async () => {
      await sync.push(
        {
          mutations: [
            makeMutation({ mutationUid: 'mut-task', objectType: 'task_item' }),
            makeMutation({
              mutationUid: 'mut-event',
              objectType: 'calendar_event',
              payload: { title: 'Event' },
            }),
          ],
        },
        ctxA,
      );

      const result = await sync.pull(undefined, ctxB, { objectType: 'task_item' });
      expect(result.changes).toHaveLength(1);
      expect(result.changes[0].objectType).toBe('task_item');
    });

    it('excludes changes originating from the pulling device', async () => {
      // Device A pushes
      await sync.push(
        { mutations: [makeMutation({ mutationUid: 'mut-by-a' })] },
        ctxA,
      );
      // Device B pushes
      await sync.push(
        {
          mutations: [
            makeMutation({ mutationUid: 'mut-by-b', localId: 'b-local', payload: { title: 'By B' } }),
          ],
        },
        ctxB,
      );

      // Device B pulls — should only see A's change
      const result = await sync.pull(undefined, ctxB);
      const changes = result.changes;
      expect(changes.every((c) => !c.payload || c.payload.title !== 'By B')).toBe(true);
    });
  });

  // ========================================================================
  // ack
  // ========================================================================
  describe('ack', () => {
    it('updates the cursor for a device', async () => {
      await sync.push(
        { mutations: [makeMutation()] },
        ctxA,
      );
      const pull = await sync.pull(undefined, ctxB);

      const ackResult = await sync.ack(
        { cursor: pull.nextCursor, appliedChangeIds: [] },
        ctxB,
      );
      expect(ackResult.ok).toBe(true);

      // Pull again — should be empty because cursor advanced
      const pull2 = await sync.pull(pull.nextCursor, ctxB);
      expect(pull2.changes).toHaveLength(0);
    });
  });

  // ========================================================================
  // conflicts
  // ========================================================================
  describe('conflicts', () => {
    it('lists open conflicts', async () => {
      // Create a conflict
      const created = await sync.push(
        { mutations: [makeMutation({ mutationUid: 'mut-create' })] },
        ctxA,
      );
      await sync.push(
        {
          mutations: [
            makeMutation({
              mutationUid: 'mut-conflict',
              serverId: created.accepted[0].serverId,
              baseServerVersion: 0,
              payload: { title: 'Changed' },
            }),
          ],
        },
        ctxB,
      );

      const conflicts = await sync.conflicts(ctxA);
      expect(conflicts.conflicts).toHaveLength(1);
      expect(conflicts.conflicts[0].objectType).toBe('task_item');
    });
  });

  // ========================================================================
  // resolveConflict
  // ========================================================================
  describe('resolveConflict', () => {
    let conflictId: string;

    beforeEach(async () => {
      const created = await sync.push(
        { mutations: [makeMutation({ mutationUid: 'mut-for-resolve' })] },
        ctxA,
      );
      const result = await sync.push(
        {
          mutations: [
            makeMutation({
              mutationUid: 'mut-conflict-resolve',
              serverId: created.accepted[0].serverId,
              baseServerVersion: 0,
              payload: { title: 'Changed', priority: 'high' },
              changedFields: ['title', 'priority'],
            }),
          ],
        },
        ctxB,
      );
      conflictId = result.conflicts[0].conflictId;
    });

    it('resolves with use_local strategy', async () => {
      const result = await sync.resolveConflict(
        conflictId,
        { strategy: 'use_local', payload: { title: 'Local wins', priority: 'high' } },
        ctxA,
      );
      expect(result.ok).toBe(true);
    });

    it('resolves with use_server strategy — keeps server version', async () => {
      const result = await sync.resolveConflict(
        conflictId,
        { strategy: 'use_server' },
        ctxA,
      );
      expect(result.ok).toBe(true);
    });

    it('resolves with merge strategy', async () => {
      const result = await sync.resolveConflict(
        conflictId,
        { strategy: 'merge', payload: { title: 'Merged title' } },
        ctxA,
      );
      expect(result.ok).toBe(true);
    });
  });

  // ========================================================================
  // status
  // ========================================================================
  describe('status', () => {
    it('returns device sync status', async () => {
      const stat = await sync.status(ctxA);
      expect(Array.isArray(stat.devices)).toBe(true);
      expect(stat.devices.length).toBeGreaterThanOrEqual(1);
      expect(stat.devices[0].deviceName).toBeTruthy();
    });
  });

  // ========================================================================
  // sync health
  // ========================================================================
  describe('syncHealth', () => {
    it('returns metrics for admin dashboard', async () => {
      // Push some mutations to create data
      await sync.push(
        {
          mutations: [
            makeMutation({ mutationUid: 'mut-h1' }),
            makeMutation({ mutationUid: 'mut-h2' }),
          ],
        },
        ctxA,
      );

      const status = await sync.status(ctxA);
      expect(status.devices[0].pullCursor).toBeDefined();
      expect(status.devices[0].latestChangeId).toBeDefined();
      expect(status.devices[0].pendingOutlookChanges).toBeGreaterThanOrEqual(0);
    });
  });
});
