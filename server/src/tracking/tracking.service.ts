import { BadRequestException, Injectable } from '@nestjs/common';
import { createHash, randomUUID } from 'node:crypto';
import { gunzipSync } from 'node:zlib';
import { QueryResultRow } from 'pg';
import { FlowPlanV2RequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';

export interface TrackingIngestQuery {
  status?: string;
  dataKind?: string;
  start?: string;
  end?: string;
  limit?: string;
  offset?: string;
}

type BatchRow = QueryResultRow & {
  id: string;
  batch_uid: string;
  data_kind: string;
  status: string;
  compression: string;
};

type NormalizedTrackingEvent = {
  uid: string;
  objectType: string;
  payload: Record<string, unknown>;
  startAt: Date | null;
  endAt: Date | null;
};

const MAX_SYNC_UID_BYTES = 180;

@Injectable()
export class TrackingService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
  ) {}

  async createBatch(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const batchUid = this.clean(body.batchUid) ?? randomUUID();
    const dataKind = this.clean(body.dataKind) ?? 'mixed';
    const compression = this.clean(body.compression) ?? 'none';
    const records = this.readRecords(body);
    const payloadHash =
      this.clean(body.payloadHash) ?? (records.length > 0 ? this.hashJson(records) : null);
    const startAt = this.readDate(body.startAt);
    const endAt = this.readDate(body.endAt);

    const batch = await this.database.transaction(async (client) => {
      const result = await client.query<QueryResultRow>(
        `
        INSERT INTO tracking_ingest_batches (
          user_id,
          device_id,
          batch_uid,
          data_kind,
          status,
          compression,
          payload_hash,
          start_at,
          end_at,
          raw_event_count,
          metadata
        ) VALUES ($1, $2, $3, $4, 'open', $5, $6, $7, $8, $9, $10::jsonb)
        ON CONFLICT (user_id, device_id, batch_uid) DO UPDATE SET
          data_kind = EXCLUDED.data_kind,
          compression = EXCLUDED.compression,
          payload_hash = COALESCE(EXCLUDED.payload_hash, tracking_ingest_batches.payload_hash),
          start_at = COALESCE(EXCLUDED.start_at, tracking_ingest_batches.start_at),
          end_at = COALESCE(EXCLUDED.end_at, tracking_ingest_batches.end_at),
          raw_event_count = GREATEST(tracking_ingest_batches.raw_event_count, EXCLUDED.raw_event_count),
          metadata = tracking_ingest_batches.metadata || EXCLUDED.metadata,
          updated_at = now()
        RETURNING
          id::text AS "batchId",
          batch_uid AS "batchUid",
          data_kind AS "dataKind",
          status,
          compression,
          raw_event_count AS "rawEventCount",
          accepted_event_count AS "acceptedEventCount",
          rejected_event_count AS "rejectedEventCount",
          created_at AS "createdAt",
          updated_at AS "updatedAt"
        `,
        [
          userId,
          deviceId,
          batchUid,
          dataKind,
          compression,
          payloadHash,
          startAt,
          endAt,
          records.length,
          JSON.stringify(this.asRecord(body.metadata)),
        ],
      );
      const row = result.rows[0];
      await this.recordAudit(client, userId, deviceId, 'tracking.ingest.batch.create', {
        batchId: row?.batchId,
        batchUid,
        dataKind,
        rawEventCount: records.length,
      });
      return row;
    });

    if (records.length > 0) {
      await this.appendChunk(
        String(batch.batchId),
        {
          chunkIndex: 0,
          payload: { records },
          checksum: this.hashJson(records),
        },
        context,
      );
    }

    return { ok: true, batch };
  }

  async appendChunk(
    batchId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const chunkIndex = this.readNumber(body.chunkIndex, -1);
    if (chunkIndex < 0) {
      throw new BadRequestException('chunkIndex is required');
    }
    const batch = await this.findBatch(userId, batchId);
    if (!batch) {
      throw new BadRequestException('tracking ingest batch not found');
    }
    const payload = this.asRecord(body.payload);
    const payloadBase64 = this.clean(body.payloadBase64);
    const sizeBytes = payloadBase64
      ? Buffer.from(payloadBase64, 'base64').length
      : Buffer.byteLength(JSON.stringify(payload));
    const checksum =
      this.clean(body.checksum) ??
      createHash('sha256')
        .update(payloadBase64 ?? JSON.stringify(payload))
        .digest('hex');

    const chunk = await this.database.transaction(async (client) => {
      const result = await client.query<QueryResultRow>(
        `
        INSERT INTO tracking_ingest_chunks (
          user_id,
          batch_id,
          chunk_index,
          payload,
          payload_base64,
          checksum,
          size_bytes,
          status
        ) VALUES ($1, $2, $3, $4::jsonb, $5, $6, $7, 'received')
        ON CONFLICT (user_id, batch_id, chunk_index) DO UPDATE SET
          payload = EXCLUDED.payload,
          payload_base64 = EXCLUDED.payload_base64,
          checksum = EXCLUDED.checksum,
          size_bytes = EXCLUDED.size_bytes,
          status = 'received',
          created_at = now()
        RETURNING id::text AS id, chunk_index AS "chunkIndex", size_bytes AS "sizeBytes", checksum, status
        `,
        [
          userId,
          batchId,
          chunkIndex,
          JSON.stringify(payload),
          payloadBase64,
          checksum,
          sizeBytes,
        ],
      );
      await client.query(
        `
        UPDATE tracking_ingest_batches
        SET status = 'receiving', updated_at = now()
        WHERE user_id = $1 AND id = $2 AND status IN ('open', 'receiving')
        `,
        [userId, batchId],
      );
      await this.recordAudit(client, userId, deviceId, 'tracking.ingest.chunk.receive', {
        batchId,
        chunkIndex,
        sizeBytes,
      });
      return result.rows[0];
    });
    return { ok: true, chunk };
  }

  async completeBatch(
    batchId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const batch = await this.findBatch(userId, batchId);
    if (!batch) {
      throw new BadRequestException('tracking ingest batch not found');
    }

    const directRecords = this.readRecords(body);
    let chunkRecords: unknown[];
    try {
      chunkRecords = await this.readChunkRecords(userId, batchId, batch.compression);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.database.transaction(async (client) => {
        await client.query(
          `
          UPDATE tracking_ingest_batches
          SET status = 'failed', error_message = $3, updated_at = now()
          WHERE user_id = $1 AND id = $2
          `,
          [userId, batchId, message],
        );
        await this.recordAudit(client, userId, deviceId, 'tracking.ingest.batch.failed', {
          batchId,
          errorMessage: message,
        });
      });
      return { ok: false, batchId, reason: 'chunk_decode_failed', error: message };
    }
    const records = [...chunkRecords, ...directRecords];
    let accepted = 0;
    let rejected = 0;
    const rejectedSamples: Array<Record<string, unknown>> = [];

    await this.database.transaction(async (client) => {
      for (let index = 0; index < records.length; index += 1) {
        const normalized = this.normalizeRecord(
          records[index],
          batch.batch_uid,
          batch.data_kind,
          index,
        );
        if (!normalized) {
          rejected += 1;
          if (rejectedSamples.length < 10) {
            rejectedSamples.push(this.asRecord(records[index]));
          }
          continue;
        }
        const row = await client.query<QueryResultRow>(
          `
          INSERT INTO sync_objects (
            user_id,
            object_type,
            uid,
            payload,
            origin_device_id,
            last_modified_device_id
          ) VALUES ($1, $2, $3, $4::jsonb, $5, $5)
          ON CONFLICT (user_id, object_type, uid) WHERE uid IS NOT NULL AND deleted_at IS NULL DO UPDATE SET
            payload = sync_objects.payload || EXCLUDED.payload,
            server_version = sync_objects.server_version + 1,
            last_modified_device_id = EXCLUDED.last_modified_device_id,
            updated_at = now()
          RETURNING id::text AS id, object_type, payload, server_version
          `,
          [
            userId,
            normalized.objectType,
            normalized.uid,
            JSON.stringify({
              ...normalized.payload,
              ingestBatchId: batchId,
              sourceDeviceId: deviceId,
              serverIngestedAt: new Date().toISOString(),
            }),
            deviceId,
          ],
        );
        const syncObject = row.rows[0];
        await this.recordChange(
          client,
          userId,
          deviceId,
          String(syncObject.id),
          String(syncObject.object_type),
          Number(syncObject.server_version ?? 1),
          this.asRecord(syncObject.payload),
        );
        accepted += 1;
      }

      await client.query(
        `
        UPDATE tracking_ingest_batches
        SET
          status = CASE WHEN $5::int = 0 THEN 'completed' ELSE 'completed_with_rejections' END,
          raw_event_count = $3,
          accepted_event_count = $4,
          rejected_event_count = $5,
          error_message = CASE WHEN $5::int = 0 THEN NULL ELSE 'Some tracking records were rejected during normalization' END,
          metadata = metadata || $6::jsonb,
          updated_at = now(),
          completed_at = now()
        WHERE user_id = $1 AND id = $2
        `,
        [
          userId,
          batchId,
          records.length,
          accepted,
          rejected,
          JSON.stringify({ rejectedSamples }),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'tracking.ingest.batch.complete', {
        batchId,
        rawEventCount: records.length,
        accepted,
        rejected,
      });
    });

    return {
      ok: true,
      batchId,
      rawEventCount: records.length,
      accepted,
      rejected,
      rejectedSamples,
    };
  }

  async batches(query: TrackingIngestQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = this.readLimit(query.limit, 100);
    const offset = this.readOffset(query.offset);
    const status = this.clean(query.status);
    const dataKind = this.clean(query.dataKind);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        b.id::text AS id,
        b.batch_uid AS "batchUid",
        b.data_kind AS "dataKind",
        b.status,
        b.compression,
        b.raw_event_count AS "rawEventCount",
        b.accepted_event_count AS "acceptedEventCount",
        b.rejected_event_count AS "rejectedEventCount",
        b.error_message AS "errorMessage",
        b.start_at AS "startAt",
        b.end_at AS "endAt",
        b.created_at AS "createdAt",
        b.updated_at AS "updatedAt",
        b.completed_at AS "completedAt",
        d.device_name AS "deviceName",
        d.platform
      FROM tracking_ingest_batches b
      LEFT JOIN devices d ON d.id = b.device_id
      WHERE b.user_id = $1
        AND ($2::text IS NULL OR b.status = $2)
        AND ($3::text IS NULL OR b.data_kind = $3)
      ORDER BY b.created_at DESC
      LIMIT $4 OFFSET $5
      `,
      [userId, status, dataKind, limit, offset],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  async summary(query: TrackingIngestQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const start = this.readDate(query.start);
    const end = this.readDate(query.end);
    const trackingObjectTypes = [
      'raw_activity_log',
      'activity_record',
      'tracked_input_event',
      'activity_records',
      'tracked_input_events',
    ];
    const [batches, objects, latestObjects, recentError, recent] = await Promise.all([
      this.database.query<QueryResultRow>(
        `
        SELECT status AS name, COUNT(*)::int AS count
        FROM tracking_ingest_batches
        WHERE user_id = $1
        GROUP BY status
        ORDER BY status ASC
        `,
        [userId],
      ),
      this.database.query<QueryResultRow>(
        `
        SELECT object_type AS name, COUNT(*)::int AS count
        FROM sync_objects
        WHERE user_id = $1
          AND deleted_at IS NULL
          AND object_type = ANY($2::text[])
          AND ($3::timestamptz IS NULL OR updated_at >= $3)
          AND ($4::timestamptz IS NULL OR updated_at < $4)
        GROUP BY object_type
        ORDER BY count DESC
        `,
        [
          userId,
          trackingObjectTypes,
          start,
          end,
        ],
      ),
      this.database.query<QueryResultRow>(
        `
        SELECT object_type AS name, MAX(updated_at) AS "latestReceivedAt"
        FROM sync_objects
        WHERE user_id = $1
          AND deleted_at IS NULL
          AND object_type = ANY($2::text[])
        GROUP BY object_type
        ORDER BY object_type ASC
        `,
        [userId, trackingObjectTypes],
      ),
      this.database.query<QueryResultRow>(
        `
        SELECT
          id::text AS id,
          batch_uid AS "batchUid",
          data_kind AS "dataKind",
          status,
          error_message AS "errorMessage",
          updated_at AS "updatedAt"
        FROM tracking_ingest_batches
        WHERE user_id = $1
          AND (
            error_message IS NOT NULL
            OR status IN ('failed', 'completed_with_rejections')
          )
        ORDER BY updated_at DESC
        LIMIT 1
        `,
        [userId],
      ),
      this.batches({ limit: '10' }, context),
    ]);
    return {
      generatedAt: new Date().toISOString(),
      batchStatus: this.countMap(batches.rows),
      canonicalObjectCounts: this.countMap(objects.rows),
      latestReceivedAtByKind: this.dateMap(latestObjects.rows),
      recentError: recentError.rows[0] ?? null,
      recentBatches: recent.items,
    };
  }

  private async findBatch(userId: string, batchId: string) {
    if (!this.isUuid(batchId)) {
      throw new BadRequestException('tracking ingest batchId must be a uuid');
    }
    const result = await this.database.query<BatchRow>(
      `
      SELECT id::text, batch_uid, data_kind, status, compression
      FROM tracking_ingest_batches
      WHERE user_id = $1 AND id = $2
      LIMIT 1
      `,
      [userId, batchId],
    );
    return result.rows[0] ?? null;
  }

  private isUuid(value: string) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      value,
    );
  }

  private async readChunkRecords(
    userId: string,
    batchId: string,
    compression: string,
  ) {
    const chunks = await this.database.query<QueryResultRow>(
      `
      SELECT payload, payload_base64 AS "payloadBase64"
      FROM tracking_ingest_chunks
      WHERE user_id = $1 AND batch_id = $2 AND status = 'received'
      ORDER BY chunk_index ASC
      `,
      [userId, batchId],
    );
    const records: unknown[] = [];
    for (const chunk of chunks.rows) {
      records.push(...this.readRecordsFromChunk(chunk, compression));
    }
    return records;
  }

  private readRecordsFromChunk(row: QueryResultRow, compression: string) {
    const payloadBase64 = this.clean(row.payloadBase64);
    if (payloadBase64) {
      const buffer = Buffer.from(payloadBase64, 'base64');
      const jsonText =
        compression === 'gzip' || compression === 'gzip_base64'
          ? gunzipSync(buffer).toString('utf8')
          : buffer.toString('utf8');
      return this.readRecords(JSON.parse(jsonText));
    }
    return this.readRecords(row.payload);
  }

  private normalizeRecord(
    value: unknown,
    batchUid: string,
    dataKind: string,
    index: number,
  ): NormalizedTrackingEvent | null {
    const record = this.asRecord(value);
    if (Object.keys(record).length === 0) {
      return null;
    }
    const objectType =
      this.clean(record.objectType) ??
      this.objectTypeForKind(this.clean(record.kind) ?? dataKind);
    const startAt = this.readDate(
      record.startAt ??
        record.startTime ??
        record.startedAt ??
        record.timestamp ??
        record.occurredAt,
    );
    const endAt =
      this.readDate(record.endAt ?? record.endTime ?? record.endedAt) ??
      (startAt
        ? new Date(startAt.getTime() + Math.max(60, Number(record.durationSeconds ?? 60)) * 1000)
        : null);
    const rawUid =
      this.clean(record.uid) ??
      this.clean(record.id) ??
      this.clean(record.eventId) ??
      `${batchUid}:${index}`;
    const uid = this.normalizeSyncUid(objectType, rawUid);
    return {
      uid,
      objectType,
      startAt,
      endAt,
      payload: {
        ...record,
        uid,
        ...(uid !== rawUid ? { sourceUid: rawUid } : {}),
        startTime: startAt?.toISOString() ?? record.startTime ?? record.timestamp,
        endTime: endAt?.toISOString() ?? record.endTime,
      },
    };
  }

  private normalizeSyncUid(objectType: string, rawUid: string) {
    if (Buffer.byteLength(rawUid, 'utf8') <= MAX_SYNC_UID_BYTES) {
      return rawUid;
    }
    const digest = createHash('sha256').update(rawUid).digest('hex').slice(0, 32);
    return `tracking:${objectType}:${digest}`;
  }

  private objectTypeForKind(kind: string) {
    if (kind === 'input' || kind === 'input_event' || kind === 'tracked_input_event') {
      return 'tracked_input_event';
    }
    if (kind === 'activity_record' || kind === 'activity_records') {
      return 'activity_record';
    }
    return 'raw_activity_log';
  }

  private readRecords(value: unknown): unknown[] {
    if (Array.isArray(value)) {
      return value;
    }
    const record = this.asRecord(value);
    if (Array.isArray(record.records)) {
      return record.records;
    }
    if (Array.isArray(record.events)) {
      return record.events;
    }
    if (Array.isArray(record.items)) {
      return record.items;
    }
    return [];
  }

  private async recordChange(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    objectId: string,
    objectType: string,
    serverVersion: number,
    payload: Record<string, unknown>,
  ) {
    await client.query(
      `
      INSERT INTO sync_changes (
        user_id, device_id, server_object_id, object_type, action, server_version, payload
      ) VALUES ($1, $2, $3, $4, 'upsert', $5, $6::jsonb)
      `,
      [userId, deviceId, objectId, objectType, serverVersion, JSON.stringify(payload)],
    );
  }

  private async recordAudit(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    action: string,
    details: Record<string, unknown>,
  ) {
    await client.query(
      `
      INSERT INTO audit_logs (
        user_id, device_id, actor, action, entity_type, entity_id, summary, metadata
      ) VALUES ($1, $2, 'server', $3, 'tracking_ingest', $4, $3, $5::jsonb)
      `,
      [
        userId,
        deviceId,
        action,
        details.batchId ? String(details.batchId) : null,
        JSON.stringify(details),
      ],
    );
  }

  private countMap(rows: QueryResultRow[]) {
    return Object.fromEntries(
      rows.map((row) => [String(row.name ?? 'unknown'), this.toNumber(row.count)]),
    );
  }

  private dateMap(rows: QueryResultRow[]) {
    return Object.fromEntries(
      rows.map((row) => [
        String(row.name ?? 'unknown'),
        row.latestReceivedAt ? this.iso(row.latestReceivedAt) : null,
      ]),
    );
  }

  private hashJson(value: unknown) {
    return createHash('sha256').update(JSON.stringify(value)).digest('hex');
  }

  private clean(value: unknown) {
    return typeof value === 'string' && value.trim().length > 0
      ? value.trim()
      : null;
  }

  private asRecord(value: unknown): Record<string, unknown> {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      return value as Record<string, unknown>;
    }
    return {};
  }

  private readDate(value: unknown) {
    if (value instanceof Date) {
      return Number.isNaN(value.getTime()) ? null : value;
    }
    if (typeof value !== 'string') {
      return null;
    }
    const text = value.trim();
    if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(text)) {
      return null;
    }
    const parsed = new Date(text);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  private readNumber(value: unknown, fallback: number) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) {
      return fallback;
    }
    return Math.max(0, Math.trunc(parsed));
  }

  private readLimit(value: string | undefined, fallback: number) {
    const parsed = Number(value);
    return Number.isFinite(parsed)
      ? Math.max(1, Math.min(500, Math.trunc(parsed)))
      : fallback;
  }

  private readOffset(value: string | undefined) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? Math.max(0, Math.trunc(parsed)) : 0;
  }

  private iso(value: unknown) {
    if (value instanceof Date) {
      return value.toISOString();
    }
    const parsed = new Date(String(value));
    return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
  }

  private toNumber(value: unknown) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
}
