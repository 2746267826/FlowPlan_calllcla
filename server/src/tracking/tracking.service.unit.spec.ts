import { createHash } from 'node:crypto';
import { gzipSync } from 'node:zlib';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { ObjectType } from '../common/constants/object-types';
import { TrackingService } from './tracking.service';

const context = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};

const batchId = '00000000-0000-4000-8000-000000000201';

type QueryResult = { rows: unknown[] };

function batch(status = 'open', overrides: Record<string, unknown> = {}) {
  return {
    id: batchId,
    batch_uid: 'batch-unit',
    data_kind: 'mixed',
    status,
    compression: 'none',
    ...overrides,
  };
}

function makeHarness(options: {
  queryResults?: QueryResult[];
  clientQuery?: (sql: string, params: unknown[]) => QueryResult | Promise<QueryResult>;
} = {}) {
  const queryResults = [...(options.queryResults ?? [])];
  const query = vi.fn(async () => queryResults.shift() ?? { rows: [] });
  const client = {
    query: vi.fn(async (sql: unknown, params: unknown[]) => {
      if (options.clientQuery) {
        return options.clientQuery(String(sql), params);
      }
      return { rows: [] };
    }),
  };
  const transaction = vi.fn(async (callback: (client: typeof client) => unknown) =>
    callback(client),
  );
  const database = { query, transaction };
  const devices = {
    ensureUser: vi.fn(async (userId: string) => userId),
    ensureDevice: vi.fn(async () => context.deviceId),
  };
  const service = new TrackingService(database as never, devices as never);
  return { client, database, devices, service };
}

function privateApi(service: TrackingService) {
  return service as unknown as {
    countMap(rows: Record<string, unknown>[]): Record<string, number>;
    dateMap(rows: Record<string, unknown>[]): Record<string, string | null>;
    normalizeRecord(
      value: unknown,
      batchUid: string,
      dataKind: string,
      index: number,
    ): Record<string, unknown> | null;
    readRecordsFromChunk(row: Record<string, unknown>, compression: string): unknown[];
    readRecords(value: unknown): unknown[];
    recordAudit(
      client: { query: ReturnType<typeof vi.fn> },
      userId: string,
      deviceId: string,
      action: string,
      details: Record<string, unknown>,
    ): Promise<void>;
  };
}

describe('TrackingService unit branches', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('creates a batch and auto-appends inline records', async () => {
    const records = [
      { uid: 'input-1', kind: 'input', timestamp: '2026-01-01T00:00:00.000Z' },
    ];
    const { client, database, service } = makeHarness({
      queryResults: [{ rows: [batch('open')] }],
      clientQuery: (sql) => {
        if (sql.includes('INSERT INTO tracking_ingest_batches')) {
          return {
            rows: [
              {
                batchId,
                batchUid: 'batch-unit',
                dataKind: 'input',
                status: 'open',
                compression: 'none',
                rawEventCount: 1,
                acceptedEventCount: 0,
                rejectedEventCount: 0,
              },
            ],
          };
        }
        if (sql.includes('INSERT INTO tracking_ingest_chunks')) {
          return {
            rows: [
              {
                id: 'chunk-1',
                chunkIndex: 0,
                sizeBytes: 96,
                checksum: 'provided-by-create-batch',
                status: 'received',
              },
            ],
          };
        }
        return { rows: [] };
      },
    });

    const result = await service.createBatch(
      {
        batchUid: 'batch-unit',
        dataKind: 'input',
        records,
        startAt: '2026-01-01T00:00:00.000Z',
        endAt: '2026-01-01T00:05:00.000Z',
        metadata: { source: 'unit' },
      },
      context,
    );

    expect(result).toEqual({
      ok: true,
      batch: {
        batchId,
        batchUid: 'batch-unit',
        dataKind: 'input',
        status: 'open',
        compression: 'none',
        rawEventCount: 1,
        acceptedEventCount: 0,
        rejectedEventCount: 0,
      },
    });
    expect(database.transaction).toHaveBeenCalledTimes(2);
    expect(client.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('INSERT INTO tracking_ingest_batches'),
      [
        context.userId,
        context.deviceId,
        'batch-unit',
        'input',
        'none',
        expect.any(String),
        new Date('2026-01-01T00:00:00.000Z'),
        new Date('2026-01-01T00:05:00.000Z'),
        1,
        JSON.stringify({ source: 'unit' }),
      ],
    );
    expect(client.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO tracking_ingest_chunks'),
      expect.arrayContaining([context.userId, batchId, 0]),
    );
  });

  it('creates an empty default batch without appending a chunk', async () => {
    const { client, database, service } = makeHarness({
      clientQuery: (sql, params) => {
        if (sql.includes('INSERT INTO tracking_ingest_batches')) {
          return {
            rows: [
              {
                batchId,
                batchUid: params[2],
                dataKind: params[3],
                status: 'open',
                compression: params[4],
                rawEventCount: params[8],
              },
            ],
          };
        }
        return { rows: [] };
      },
    });

    const result = await service.createBatch({}, context);

    expect(result).toEqual({
      ok: true,
      batch: {
        batchId,
        batchUid: expect.any(String),
        dataKind: 'mixed',
        status: 'open',
        compression: 'none',
        rawEventCount: 0,
      },
    });
    expect(client.query).toHaveBeenCalledTimes(1);
    expect(client.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('INSERT INTO tracking_ingest_batches'),
      [
        context.userId,
        context.deviceId,
        expect.any(String),
        'mixed',
        'none',
        null,
        null,
        null,
        0,
        JSON.stringify({}),
      ],
    );
    expect(database.transaction).toHaveBeenCalledTimes(1);
  });

  it('appends a base64 chunk and calculates checksum and byte size', async () => {
    const payloadBase64 = Buffer.from(JSON.stringify({ records: [] }), 'utf8').toString(
      'base64',
    );
    const expectedChecksum = createHash('sha256').update(payloadBase64).digest('hex');
    const { client, service } = makeHarness({
      queryResults: [{ rows: [batch('receiving')] }],
      clientQuery: (sql) => {
        if (sql.includes('INSERT INTO tracking_ingest_chunks')) {
          return {
            rows: [
              {
                id: 'chunk-1',
                chunkIndex: 2,
                sizeBytes: Buffer.from(payloadBase64, 'base64').length,
                checksum: expectedChecksum,
                status: 'received',
              },
            ],
          };
        }
        return { rows: [] };
      },
    });

    const result = await service.appendChunk(
      batchId,
      { chunkIndex: '2', payloadBase64 },
      context,
    );

    expect(result).toEqual({
      ok: true,
      chunk: {
        id: 'chunk-1',
        chunkIndex: 2,
        sizeBytes: Buffer.from(payloadBase64, 'base64').length,
        checksum: expectedChecksum,
        status: 'received',
      },
    });
    expect(client.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('INSERT INTO tracking_ingest_chunks'),
      [
        context.userId,
        batchId,
        2,
        JSON.stringify({}),
        payloadBase64,
        expectedChecksum,
        Buffer.from(payloadBase64, 'base64').length,
      ],
    );
  });

  it('appends a json chunk and calculates checksum from the payload', async () => {
    const payload = { records: [{ uid: 'record-1' }] };
    const expectedChecksum = createHash('sha256')
      .update(JSON.stringify(payload))
      .digest('hex');
    const { client, service } = makeHarness({
      queryResults: [{ rows: [batch('open')] }],
      clientQuery: (sql) => {
        if (sql.includes('INSERT INTO tracking_ingest_chunks')) {
          return {
            rows: [
              {
                id: 'chunk-json',
                chunkIndex: 1,
                sizeBytes: Buffer.byteLength(JSON.stringify(payload)),
                checksum: expectedChecksum,
                status: 'received',
              },
            ],
          };
        }
        return { rows: [] };
      },
    });

    await expect(
      service.appendChunk(batchId, { chunkIndex: 1, payload }, context),
    ).resolves.toMatchObject({
      ok: true,
      chunk: {
        id: 'chunk-json',
        checksum: expectedChecksum,
      },
    });

    expect(client.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('INSERT INTO tracking_ingest_chunks'),
      [
        context.userId,
        batchId,
        1,
        JSON.stringify(payload),
        null,
        expectedChecksum,
        Buffer.byteLength(JSON.stringify(payload)),
      ],
    );
  });

  it('lists batches with query filters and hasMore based on the requested limit', async () => {
    const rows = [
      { id: 'batch-1', status: 'failed' },
      { id: 'batch-2', status: 'failed' },
    ];
    const { database, service } = makeHarness({
      queryResults: [{ rows }],
    });

    const result = await service.batches(
      { status: ' failed ', dataKind: 'input', limit: '2', offset: '3' },
      context,
    );

    expect(result).toEqual({
      limit: 2,
      offset: 3,
      hasMore: true,
      items: rows,
    });
    expect(database.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('FROM tracking_ingest_batches b'),
      [context.userId, 'failed', 'input', 2, 3],
    );
  });

  it('builds summary maps and recent batch data', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00.000Z'));
    const recentBatch = { id: 'recent-batch' };
    const { service } = makeHarness({
      queryResults: [
        { rows: [{ name: 'completed', count: '2' }, { count: '1' }] },
        { rows: [{ name: ObjectType.TRACKED_INPUT_EVENT, count: 3 }] },
        {
          rows: [
            {
              name: ObjectType.TRACKED_INPUT_EVENT,
              latestReceivedAt: new Date('2026-01-01T00:00:00.000Z'),
            },
            { name: ObjectType.RAW_ACTIVITY_LOG, latestReceivedAt: null },
          ],
        },
        { rows: [{ id: 'failed-batch', status: 'failed' }] },
        { rows: [recentBatch] },
      ],
    });

    const result = await service.summary(
      { start: '2026-01-01T00:00:00.000Z', end: '2026-01-02T00:00:00.000Z' },
      context,
    );

    expect(result).toEqual({
      generatedAt: '2026-01-01T00:00:00.000Z',
      batchStatus: { completed: 2, unknown: 1 },
      canonicalObjectCounts: { [ObjectType.TRACKED_INPUT_EVENT]: 3 },
      latestReceivedAtByKind: {
        [ObjectType.TRACKED_INPUT_EVENT]: '2026-01-01T00:00:00.000Z',
        [ObjectType.RAW_ACTIVITY_LOG]: null,
      },
      recentError: { id: 'failed-batch', status: 'failed' },
      recentBatches: [recentBatch],
    });
  });

  it('builds empty summary maps with null ranges and no recent error', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00.000Z'));
    const { database, service } = makeHarness({
      queryResults: [
        { rows: [] },
        { rows: [] },
        { rows: [{ latestReceivedAt: null }] },
        { rows: [] },
        { rows: [] },
      ],
    });

    await expect(service.summary({}, context)).resolves.toEqual({
      generatedAt: '2026-01-01T00:00:00.000Z',
      batchStatus: {},
      canonicalObjectCounts: {},
      latestReceivedAtByKind: { unknown: null },
      recentError: null,
      recentBatches: [],
    });

    expect(database.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('FROM sync_objects'),
      [
        context.userId,
        [
          ObjectType.RAW_ACTIVITY_LOG,
          ObjectType.ACTIVITY_RECORD,
          ObjectType.TRACKED_INPUT_EVENT,
        ],
        null,
        null,
      ],
    );
  });

  it('rejects appendChunk when chunkIndex is missing before reading a batch', async () => {
    const { database, service } = makeHarness();

    await expect(service.appendChunk(batchId, {}, context)).rejects.toThrow(
      'chunkIndex is required',
    );
    expect(database.query).not.toHaveBeenCalled();
  });

  it('rejects appendChunk when the batch cannot be found', async () => {
    const { database, service } = makeHarness({
      queryResults: [{ rows: [] }],
    });

    await expect(
      service.appendChunk(batchId, { chunkIndex: 0, payload: {} }, context),
    ).rejects.toThrow('tracking ingest batch not found');
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('FROM tracking_ingest_batches'),
      [context.userId, batchId],
    );
  });

  it('rejects appendChunk when the batch is closed', async () => {
    const { service } = makeHarness({
      queryResults: [{ rows: [batch('completed')] }],
    });

    await expect(
      service.appendChunk(batchId, { chunkIndex: 0, payload: {} }, context),
    ).rejects.toThrow("batch status 'completed' does not accept new chunks");
  });

  it('rejects completeBatch for invalid and missing batch ids', async () => {
    const invalid = makeHarness();
    await expect(invalid.service.completeBatch('not-a-uuid', {}, context)).rejects.toThrow(
      'tracking ingest batchId must be a uuid',
    );
    expect(invalid.database.query).not.toHaveBeenCalled();

    const missing = makeHarness({
      queryResults: [{ rows: [] }],
    });
    await expect(missing.service.completeBatch(batchId, {}, context)).rejects.toThrow(
      'tracking ingest batch not found',
    );
  });

  it.each([
    [
      'completed_with_rejections',
      { ok: true, batchId, message: 'batch already completed (status: completed_with_rejections)' },
    ],
    ['processing', { ok: false, batchId, reason: 'batch is already being processed' }],
    ['failed', { ok: false, batchId, reason: 'batch previously failed' }],
  ])('returns early when completeBatch sees %s status', async (status, expected) => {
    const { database, service } = makeHarness({
      queryResults: [{ rows: [batch(status)] }],
    });

    await expect(service.completeBatch(batchId, {}, context)).resolves.toEqual(expected);
    expect(database.query).toHaveBeenCalledTimes(1);
  });

  it('marks the batch failed and records audit metadata when chunk decoding fails', async () => {
    const invalidGzip = Buffer.from('not gzip json').toString('base64');
    const { client, database, service } = makeHarness({
      queryResults: [
        { rows: [batch('open', { compression: 'gzip' })] },
        { rows: [] },
        { rows: [{ payloadBase64: invalidGzip }] },
      ],
    });

    const result = await service.completeBatch(batchId, {}, context);

    expect(result).toMatchObject({
      ok: false,
      batchId,
      reason: 'chunk_decode_failed',
      error: expect.any(String),
    });
    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(client.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining("SET status = 'failed'"),
      [context.userId, batchId, result.error],
    );
    expect(client.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([
        context.userId,
        context.deviceId,
        'tracking.ingest.batch.failed',
        batchId,
      ]),
    );
  });

  it('marks the batch failed when chunk reading throws a non-error value', async () => {
    const { client, database, service } = makeHarness({
      queryResults: [
        { rows: [batch('open')] },
        { rows: [] },
        { rows: [{ payload: { records: [] } }] },
      ],
    });
    vi.spyOn(privateApi(service), 'readRecordsFromChunk').mockImplementation(() => {
      throw 'plain decode failure';
    });

    const result = await service.completeBatch(batchId, {}, context);

    expect(result).toEqual({
      ok: false,
      batchId,
      reason: 'chunk_decode_failed',
      error: 'plain decode failure',
    });
    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(client.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining("SET status = 'failed'"),
      [context.userId, batchId, 'plain decode failure'],
    );
  });

  it('normalizes gzip chunks, long uids, and tracking kind aliases', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00.000Z'));
    const longUid = 'tracking-event-'.repeat(20);
    const records = [
      {
        kind: 'input',
        uid: longUid,
        timestamp: '2026-01-01T00:00:00.000Z',
        durationSeconds: 15,
      },
      {
        kind: 'activity_records',
        id: 'activity-1',
        startAt: '2026-01-01T00:01:00.000Z',
        durationSeconds: '5',
      },
      {
        kind: 'window-sample',
        eventId: 'raw-1',
        occurredAt: '2026-01-01T00:02:00.000Z',
      },
    ];
    const payloadBase64 = gzipSync(
      Buffer.from(JSON.stringify({ records }), 'utf8'),
    ).toString('base64');
    let insertCount = 0;
    const { client, service } = makeHarness({
      queryResults: [
        { rows: [batch('open', { compression: 'gzip_base64' })] },
        { rows: [] },
        { rows: [{ payloadBase64 }] },
      ],
      clientQuery: (sql, params) => {
        if (sql.includes('SELECT id, server_version FROM sync_objects')) {
          return { rows: [] };
        }
        if (sql.includes('INSERT INTO sync_objects')) {
          insertCount += 1;
          return {
            rows: [
              {
                id: `object-${insertCount}`,
                object_type: params[1],
                payload: JSON.parse(String(params[3])),
                server_version: insertCount,
              },
            ],
          };
        }
        return { rows: [] };
      },
    });

    const result = await service.completeBatch(batchId, {}, context);

    expect(result).toEqual({
      ok: true,
      batchId,
      rawEventCount: 3,
      accepted: 3,
      rejected: 0,
      deduplicated: 0,
      rejectedSamples: [],
    });
    const syncObjectInserts = client.query.mock.calls.filter(([sql]) =>
      String(sql).includes('INSERT INTO sync_objects'),
    );
    expect(syncObjectInserts).toHaveLength(3);

    const longUidParams = syncObjectInserts[0][1] as unknown[];
    const expectedDigest = createHash('sha256').update(longUid).digest('hex').slice(0, 32);
    expect(longUidParams[1]).toBe(ObjectType.TRACKED_INPUT_EVENT);
    expect(longUidParams[2]).toBe(
      `tracking:${ObjectType.TRACKED_INPUT_EVENT}:${expectedDigest}`,
    );
    expect(JSON.parse(String(longUidParams[3]))).toMatchObject({
      sourceUid: longUid,
      endTime: '2026-01-01T00:01:00.000Z',
    });

    expect((syncObjectInserts[1][1] as unknown[])[1]).toBe(ObjectType.ACTIVITY_RECORD);
    expect((syncObjectInserts[2][1] as unknown[])[1]).toBe(ObjectType.RAW_ACTIVITY_LOG);
    const finalUpdate = client.query.mock.calls.find(([sql]) =>
      String(sql).includes('accepted_event_count'),
    );
    expect(finalUpdate?.[1]).toEqual([
      context.userId,
      batchId,
      3,
      3,
      0,
      'completed',
      JSON.stringify({ rejectedSamples: [], deduplicatedCount: 0 }),
    ]);
  });

  it('normalizes direct records with deduplication, rejections, and sample caps', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00.000Z'));
    const invalidRecords = Array.from({ length: 11 }, (_, index) => ({
      objectType: 'unsupported',
      index,
    }));
    const validRecord = {
      objectType: ObjectType.RAW_ACTIVITY_LOG,
      uid: 'duplicate-record',
      timestamp: '2026-01-01T00:00:00.000Z',
    };
    const { client, service } = makeHarness({
      queryResults: [
        { rows: [batch('open')] },
        { rows: [] },
        { rows: [] },
      ],
      clientQuery: (sql, params) => {
        if (sql.includes('SELECT id, server_version FROM sync_objects')) {
          return { rows: [{ id: 'existing-object', server_version: 7 }] };
        }
        if (sql.includes('INSERT INTO sync_objects')) {
          return {
            rows: [
              {
                id: 'object-duplicate',
                object_type: params[1],
                payload: JSON.parse(String(params[3])),
              },
            ],
          };
        }
        return { rows: [] };
      },
    });

    await expect(
      service.completeBatch(batchId, { records: [validRecord, ...invalidRecords] }, context),
    ).resolves.toEqual({
      ok: true,
      batchId,
      rawEventCount: 12,
      accepted: 1,
      rejected: 11,
      deduplicated: 1,
      rejectedSamples: invalidRecords.slice(0, 10),
    });

    const finalUpdate = client.query.mock.calls.find(([sql]) =>
      String(sql).includes('accepted_event_count'),
    );
    expect(finalUpdate?.[1]).toEqual([
      context.userId,
      batchId,
      12,
      1,
      11,
      'completed_with_rejections',
      JSON.stringify({
        rejectedSamples: invalidRecords.slice(0, 10),
        deduplicatedCount: 1,
      }),
    ]);
    expect(client.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO sync_changes'),
      [
        context.userId,
        context.deviceId,
        'object-duplicate',
        ObjectType.RAW_ACTIVITY_LOG,
        1,
        expect.any(String),
      ],
    );
  });

  it('reads tracking records from arrays, events collections, and item collections', () => {
    const { service } = makeHarness();
    const api = privateApi(service);
    const arrayRecords = [{ eventId: 'array-1' }];
    const objectRecords = [{ eventId: 'record-1' }];
    const eventRecords = [{ eventId: 'event-1' }];
    const itemRecords = [{ eventId: 'item-1' }];

    expect(api.readRecords(arrayRecords)).toBe(arrayRecords);
    expect(api.readRecords({ records: objectRecords })).toBe(objectRecords);
    expect(api.readRecords({ events: eventRecords })).toBe(eventRecords);
    expect(api.readRecords({ items: itemRecords })).toBe(itemRecords);
    expect(api.readRecords({ ignored: true })).toEqual([]);
  });

  it('reads chunk payload shapes and normalizes record defaults', async () => {
    const { client, service } = makeHarness();
    const api = privateApi(service);
    const base64Json = Buffer.from(JSON.stringify({ items: [{ uid: 'base64-item' }] }), 'utf8')
      .toString('base64');

    expect(api.readRecordsFromChunk({ payload: { events: [{ uid: 'event-item' }] } }, 'none')).toEqual([
      { uid: 'event-item' },
    ]);
    expect(api.readRecordsFromChunk({ payloadBase64: base64Json }, 'none')).toEqual([
      { uid: 'base64-item' },
    ]);

    expect(api.normalizeRecord({}, 'batch-unit', 'input', 0)).toBeNull();
    expect(
      api.normalizeRecord(
        {
          uid: 'invalid-type',
          objectType: 'not-tracking',
          timestamp: '2026-01-01T00:00:00.000Z',
        },
        'batch-unit',
        'mixed',
        1,
      ),
    ).toBeNull();
    expect(
      api.normalizeRecord(
        {
          id: 'id-record',
          startTime: 'not-a-date',
          endTime: 'also-not-a-date',
        },
        'batch-unit',
        ObjectType.ACTIVITY_RECORD,
        2,
      ),
    ).toMatchObject({
      uid: 'id-record',
      objectType: ObjectType.ACTIVITY_RECORD,
      startAt: null,
      endAt: null,
      payload: expect.objectContaining({
        startTime: 'not-a-date',
        endTime: 'also-not-a-date',
      }),
    });
    expect(
      api.normalizeRecord(
        {
          timestamp: 'bad-timestamp',
        },
        'batch-unit',
        'input',
        3,
      ),
    ).toMatchObject({
      uid: 'batch-unit:3',
      objectType: ObjectType.TRACKED_INPUT_EVENT,
      payload: expect.objectContaining({
        startTime: 'bad-timestamp',
      }),
    });

    expect(api.countMap([{ count: null }])).toEqual({ unknown: 0 });
    expect(api.dateMap([{ latestReceivedAt: null }])).toEqual({ unknown: null });
    await api.recordAudit(client, context.userId, context.deviceId, 'tracking.audit.no_batch', {});
    expect(client.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        context.userId,
        context.deviceId,
        'tracking.audit.no_batch',
        null,
        JSON.stringify({}),
      ],
    );
  });
});
