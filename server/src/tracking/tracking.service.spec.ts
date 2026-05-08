import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { DatabaseService } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import { TrackingService } from './tracking.service';
import { cleanDatabase, createTestUser, createTestDevice } from '../common/test/test-utils';
import type { FlowPlanV2RequestContext } from '../common/request-context';

describe('TrackingService', () => {
  let db: DatabaseService;
  let service: TrackingService;
  let devices: DevicesService;
  let ctx: FlowPlanV2RequestContext;

  beforeAll(async () => {
    db = new DatabaseService();
    await db.onModuleInit();
    devices = new DevicesService(db);
    service = new TrackingService(db, devices);
  });

  afterAll(async () => {
    await db.onModuleDestroy();
  });

  beforeEach(async () => {
    await cleanDatabase(db);
    const user = await createTestUser(db, { id: '00000000-0000-0000-0000-000000000001' });
    const dev = await createTestDevice(db, user.id, { id: '00000000-0000-0000-0000-000000000101' });
    ctx = { userId: user.id, deviceId: dev.id };
  });

  const makeRecords = (count: number) =>
    Array.from({ length: count }, (_, i) => ({
      uid: `track-event-${i}`,
      objectType: 'tracked_input_event',
      timestamp: new Date(Date.now() - i * 60000).toISOString(),
      eventKind: 'key_down',
      eventCount: 10 + i,
    }));

  // ====================================================================
  // createBatch
  // ====================================================================
  describe('createBatch', () => {
    it('creates a batch and auto-appends records', async () => {
      const records = makeRecords(5);
      const result = await service.createBatch(
        { dataKind: 'input', records },
        ctx,
      );
      expect(result.ok).toBe(true);
      // batch created with 'open', then appendChunk sets to 'receiving' in DB
      expect(['open', 'receiving']).toContain(result.batch.status);
      expect(result.batch.rawEventCount).toBe(5);
    });

    it('accepts batch with zero records', async () => {
      const result = await service.createBatch({ dataKind: 'input' }, ctx);
      expect(result.ok).toBe(true);
      expect(result.batch.rawEventCount).toBe(0);
      expect(result.batch.status).toBe('open');
    });

    it('idempotently re-creates same batch_uid', async () => {
      const first = await service.createBatch(
        { batchUid: 'batch-001', dataKind: 'input', records: makeRecords(2) },
        ctx,
      );
      const second = await service.createBatch(
        { batchUid: 'batch-001', dataKind: 'input', records: makeRecords(3) },
        ctx,
      );
      expect(second.batch.batchId).toBe(first.batch.batchId);
    });
  });

  // ====================================================================
  // appendChunk
  // ====================================================================
  describe('appendChunk', () => {
    it('appends a chunk to an existing batch', async () => {
      const batch = await service.createBatch(
        { batchUid: 'batch-chunk', dataKind: 'input', records: makeRecords(2) },
        ctx,
      );
      const chunk = await service.appendChunk(
        String(batch.batch.batchId),
        { chunkIndex: 1, payload: { records: makeRecords(3) }, checksum: 'abc' },
        ctx,
      );
      expect(chunk.ok).toBe(true);
      expect(chunk.chunk.chunkIndex).toBe(1);
    });

    it('rejects append to a completed batch', async () => {
      const batch = await service.createBatch(
        { batchUid: 'batch-done', dataKind: 'input', records: makeRecords(1) },
        ctx,
      );
      await service.completeBatch(String(batch.batch.batchId), {}, ctx);

      await expect(
        service.appendChunk(
          String(batch.batch.batchId),
          { chunkIndex: 1, payload: {} },
          ctx,
        ),
      ).rejects.toThrow(/does not accept new chunks/);
    });
  });

  // ====================================================================
  // completeBatch
  // ====================================================================
  describe('completeBatch', () => {
    it('completes a batch and writes sync_objects', async () => {
      const batch = await service.createBatch(
        { batchUid: 'batch-finish', dataKind: 'input', records: makeRecords(3) },
        ctx,
      );
      const result = await service.completeBatch(String(batch.batch.batchId), {}, ctx);
      expect(result.ok).toBe(true);
      expect(result.accepted).toBe(3);
      expect(result.rejected).toBe(0);
    });

    it('prevents double completion', async () => {
      const batch = await service.createBatch(
        { batchUid: 'batch-double', dataKind: 'input', records: makeRecords(1) },
        ctx,
      );
      await service.completeBatch(String(batch.batch.batchId), {}, ctx);
      const second = await service.completeBatch(String(batch.batch.batchId), {}, ctx);
      expect(second.ok).toBe(true);
      expect(second.message).toContain('already completed');
    });

    it('rejects invalid records during normalization', async () => {
      const batch = await service.createBatch(
        { batchUid: 'batch-mixed', dataKind: 'input', records: [
          makeRecords(1)[0],
          {},  // empty record → null
          { objectType: 'unknown_type' },  // invalid type → null
        ]},
        ctx,
      );
      const result = await service.completeBatch(String(batch.batch.batchId), {}, ctx);
      expect(result.ok).toBe(true);
      expect(result.accepted).toBe(1);
      expect(result.rejected).toBe(2);
      expect(result.rejectedSamples.length).toBe(2);
    });

    it('counts deduplication', async () => {
      // First batch
      const b1 = await service.createBatch(
        { batchUid: 'batch-a', dataKind: 'input', records: makeRecords(2) },
        ctx,
      );
      await service.completeBatch(String(b1.batch.batchId), {}, ctx);

      // Second batch with same UIDs
      const b2 = await service.createBatch(
        { batchUid: 'batch-b', dataKind: 'input', records: makeRecords(2) },
        ctx,
      );
      const result = await service.completeBatch(String(b2.batch.batchId), {}, ctx);
      expect(result.accepted).toBe(2);
      expect(result.deduplicated).toBe(2);
    });
  });

  // ====================================================================
  // batches / summary
  // ====================================================================
  describe('batches and summary', () => {
    it('lists batches', async () => {
      await service.createBatch({ dataKind: 'input', records: makeRecords(1) }, ctx);
      const result = await service.batches({}, ctx);
      expect(result.items.length).toBe(1);
      expect(result.items[0].dataKind).toBe('input');
    });

    it('returns tracking summary', async () => {
      const batch = await service.createBatch(
        { dataKind: 'input', records: makeRecords(3) },
        ctx,
      );
      await service.completeBatch(String(batch.batch.batchId), {}, ctx);

      const summary = await service.summary({}, ctx);
      expect(summary.batchStatus).toBeDefined();
      expect(summary.canonicalObjectCounts).toBeDefined();
    });
  });
});
