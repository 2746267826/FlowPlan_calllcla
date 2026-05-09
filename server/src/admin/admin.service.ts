import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { QueryResultRow } from 'pg';
import { FlowPlanV2RequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import { LocalObjectStorageService } from '../files/local-object-storage.service';
import { clean, asRecord, readDate, readLimit, readOffset, toNumber, searchPattern } from '../common/utils';
import { LegacyTypeMap } from '../common/constants/object-types';

export interface AdminQuery {
  domain?: string;
  objectType?: string;
  status?: string;
  q?: string;
  limit?: string;
  offset?: string;
  includeDeleted?: string;
  deviceId?: string;
  since?: string;
}

type CountRow = QueryResultRow & { name: string; count: string | number };

const DOMAIN_OBJECT_TYPES: Record<string, string[]> = {
  schedules: ['calendar_event'],
  tasks: ['task_item', 'task_list', 'task_schedule_segment'],
  tracking: ['activity_record', 'tracked_input_event', 'raw_activity_log'],
  actuals: ['actual_activity_log', 'activity_record'],
  files: ['file_folder', 'file_item', 'file_context_link'],
  reports: ['report_document', 'diary_entry'],
  ai: ['ai_operation_draft'],
};

@Injectable()
export class AdminService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
    private readonly objectStorage: LocalObjectStorageService,
  ) {}

  async overview(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const [
      objectCounts,
      deviceCounts,
      conflictCounts,
      auditCounts,
      reportCounts,
      pushCounts,
      fileCounts,
      outlookCounts,
      jobCounts,
      configCounts,
      draftCounts,
    ] = await Promise.all([
      this.countByObjectType(userId),
      this.countByStatus(
        userId,
        `SELECT CASE
          WHEN last_heartbeat_at IS NULL THEN 'offline'
          WHEN last_heartbeat_at > now() - interval '90 seconds' THEN 'online'
          WHEN last_heartbeat_at > now() - interval '10 minutes' THEN 'degraded'
          ELSE 'offline'
        END AS name FROM devices WHERE user_id = $1`,
      ),
      this.countByStatus(
        userId,
        'SELECT status AS name FROM sync_conflicts WHERE user_id = $1',
      ),
      this.countByStatus(
        userId,
        `SELECT CASE WHEN occurred_at > now() - interval '24 hours' THEN 'last_24h' ELSE 'older' END AS name FROM audit_logs WHERE user_id = $1`,
      ),
      this.countByStatus(
        userId,
        'SELECT status AS name FROM report_documents WHERE user_id = $1',
      ),
      this.countByStatus(
        userId,
        'SELECT status AS name FROM report_push_deliveries WHERE user_id = $1',
      ),
      this.fileCounts(userId),
      this.countByStatus(
        userId,
        'SELECT sync_state AS name FROM outlook_object_mappings WHERE user_id = $1',
      ),
      this.countByStatus(
        userId,
        'SELECT status AS name FROM server_jobs WHERE user_id = $1',
      ),
      this.scalarCount(userId, 'admin_remote_configs'),
      this.countByStatus(
        userId,
        'SELECT status AS name FROM ai_operation_drafts WHERE user_id = $1',
      ),
    ]);

    const syncCursor = await this.database.query<QueryResultRow>(
      `
      SELECT COALESCE(MAX(id), 0)::text AS "latestChangeId"
      FROM sync_changes
      WHERE user_id = $1
      `,
      [userId],
    );

    return {
      phase: 'p11',
      generatedAt: new Date().toISOString(),
      objectCounts,
      deviceCounts,
      conflictCounts,
      auditCounts,
      reportCounts,
      pushCounts,
      fileCounts,
      outlookCounts,
      jobCounts,
      configCount: Number(configCounts),
      draftCounts,
      latestChangeId: syncCursor.rows[0]?.latestChangeId ?? '0',
    };
  }

  async syncHealth(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const devices = await this.database.query<QueryResultRow>(
      `
      SELECT
        d.id::text AS "deviceId",
        d.device_name AS "deviceName",
        d.platform,
        d.client_device_id AS "clientDeviceId",
        d.last_seen_at AS "lastSeenAt",
        d.last_heartbeat_at AS "lastHeartbeatAt",
        d.last_connected_at AS "lastConnectedAt",
        d.last_disconnected_at AS "lastDisconnectedAt",
        d.last_connection_error AS "lastConnectionError",
        d.app_version AS "appVersion",
        d.runtime_platform AS "runtimePlatform",
        d.network_type AS "networkType",
        d.sync_pending_count AS "syncPendingCount",
        d.sync_failed_count AS "syncFailedCount",
        d.open_conflict_count AS "openConflictCount",
        COALESCE(c.cursor_value, 0)::text AS "pullCursor",
        c.updated_at AS "cursorUpdatedAt",
        CASE
          WHEN d.last_heartbeat_at IS NULL THEN 'offline'
          WHEN d.last_heartbeat_at > now() - interval '90 seconds' THEN 'online'
          WHEN d.last_heartbeat_at > now() - interval '10 minutes' THEN 'degraded'
          ELSE 'offline'
        END AS status
      FROM devices d
      LEFT JOIN sync_cursors c
        ON c.user_id = d.user_id AND c.device_id = d.id
      WHERE d.user_id = $1
      ORDER BY d.last_seen_at DESC NULLS LAST, d.created_at DESC
      `,
      [userId],
    );
    const mutations = await this.countByStatus(
      userId,
      `SELECT result AS name FROM sync_mutations WHERE user_id = $1 AND created_at > now() - interval '7 days'`,
    );
    const conflicts = await this.countByStatus(
      userId,
      'SELECT status AS name FROM sync_conflicts WHERE user_id = $1',
    );
    return {
      devices: devices.rows,
      recentMutationResults: mutations,
      conflictStatus: conflicts,
    };
  }

  async deviceConnectionHistory(
    deviceId: string,
    context: FlowPlanV2RequestContext,
  ) {
    return this.devicesService.connectionHistory(deviceId, context);
  }

  async deviceOnlineSummary(context: FlowPlanV2RequestContext) {
    return this.devicesService.onlineSummary(context);
  }

  async newInfo(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const since = readDate(query.since) ?? new Date(Date.now() - 15 * 60 * 1000);
    const deviceId = this.readDeviceId(query.deviceId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        (SELECT COUNT(*)::int FROM sync_changes WHERE user_id = $1 AND created_at > $2 AND ($3::uuid IS NULL OR device_id = $3::uuid)) AS "syncChanges",
        (SELECT COUNT(*)::int FROM sync_mutations WHERE user_id = $1 AND created_at > $2 AND ($3::uuid IS NULL OR device_id = $3::uuid)) AS "syncMutations",
        (SELECT COUNT(*)::int FROM sync_conflicts WHERE user_id = $1 AND created_at > $2 AND ($3::uuid IS NULL OR device_id = $3::uuid)) AS "conflicts",
        (SELECT COUNT(*)::int FROM tracking_ingest_batches WHERE user_id = $1 AND created_at > $2 AND ($3::uuid IS NULL OR device_id = $3::uuid)) AS "trackingBatches",
        (SELECT COUNT(*)::int FROM file_operation_logs WHERE user_id = $1 AND created_at > $2 AND ($3::uuid IS NULL OR device_id = $3::uuid)) AS "fileOperations",
        (SELECT COUNT(*)::int FROM audit_logs WHERE user_id = $1 AND occurred_at > $2 AND ($3::uuid IS NULL OR device_id = $3::uuid)) AS "auditLogs"
      `,
      [userId, since, deviceId],
    );
    const row = result.rows[0] ?? {};
    const sections = {
      syncChanges: toNumber(row.syncChanges as string | number | undefined),
      syncMutations: toNumber(row.syncMutations as string | number | undefined),
      conflicts: toNumber(row.conflicts as string | number | undefined),
      trackingBatches: toNumber(row.trackingBatches as string | number | undefined),
      fileOperations: toNumber(row.fileOperations as string | number | undefined),
      auditLogs: toNumber(row.auditLogs as string | number | undefined),
    };
    const total = Object.values(sections).reduce((sum, count) => sum + count, 0);
    return {
      since: since.toISOString(),
      generatedAt: new Date().toISOString(),
      deviceId: deviceId ?? 'all',
      total,
      sections,
    };
  }

  async objects(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 80, 1, 200);
    const offset = readOffset(query.offset);
    const types = this.readObjectTypes(query);
    const search = searchPattern(query.q);
    const includeDeleted = query.includeDeleted === 'true';
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        object_type AS "objectType",
        uid,
        payload,
        server_version AS "serverVersion",
        deleted_at AS "deletedAt",
        created_at AS "createdAt",
        updated_at AS "updatedAt",
        COALESCE(
          payload->>'title',
          payload->>'name',
          payload->>'summary',
          payload->>'displayName',
          uid,
          id::text
        ) AS title
      FROM sync_objects
      WHERE user_id = $1
        AND ($2::text[] IS NULL OR object_type = ANY($2::text[]))
        AND ($3::text IS NULL OR object_type = $3)
        AND ($4::text IS NULL OR uid ILIKE $4 OR payload::text ILIKE $4)
        AND ($5::boolean OR deleted_at IS NULL)
      ORDER BY updated_at DESC, id DESC
      LIMIT $6 OFFSET $7
      `,
      [
        userId,
        types.length > 0 ? types : null,
        clean(query.objectType),
        search,
        includeDeleted,
        limit,
        offset,
      ],
    );
    return {
      domain: query.domain ?? 'all',
      objectTypes: types,
      limit,
      offset,
      hasMore: result.rows.length >= limit,
      items: result.rows,
    };
  }

  async updateObject(
    objectId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const payload = asRecord(body.payload);
    const replace = body.mode === 'replace';
    const deleted = typeof body.deleted === 'boolean' ? body.deleted : undefined;
    const result = await this.database.transaction(async (client) => {
      const updated = await client.query<QueryResultRow>(
        `
        UPDATE sync_objects
        SET
          payload = CASE WHEN $3::boolean THEN $4::jsonb ELSE payload || $4::jsonb END,
          deleted_at = CASE
            WHEN $5::boolean IS NULL THEN deleted_at
            WHEN $5::boolean THEN now()
            ELSE NULL
          END,
          server_version = server_version + 1,
          last_modified_device_id = $6,
          updated_at = now()
        WHERE user_id = $1 AND id = $2
        RETURNING id::text, object_type, payload, server_version
        `,
        [userId, objectId, replace, JSON.stringify(payload), deleted, deviceId],
      );
      const row = updated.rows[0];
      if (row) {
        await this.recordChange(
          client,
          userId,
          deviceId,
          row.id as string,
          row.object_type as string,
          deleted ? 'delete' : 'upsert',
          row.server_version as number,
          row.payload as Record<string, unknown>,
        );
        await this.recordAudit(client, userId, deviceId, 'admin', 'admin.object.update', {
          objectId,
          replace,
          deleted,
        });
      }
      return row;
    });
    return { ok: !!result, object: result ?? null };
  }

  async actualRecords(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 80, 1, 200);
    const offset = readOffset(query.offset);
    const status = clean(query.status);
    const search = searchPattern(query.q);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        actual_uid AS "actualUid",
        title,
        start_at AS "startAt",
        end_at AS "endAt",
        source_type AS "sourceType",
        source_id AS "sourceId",
        status,
        note,
        confidence,
        source_payload AS metadata,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM actual_activity_logs
      WHERE user_id = $1
        AND ($2::text IS NULL OR status = $2)
        AND ($3::text IS NULL OR title ILIKE $3 OR note ILIKE $3)
      ORDER BY start_at DESC
      LIMIT $4 OFFSET $5
      `,
      [userId, status, search, limit, offset],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  async updateActualRecord(
    actualId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const metadata = asRecord(body.metadata);
    const result = await this.database.transaction(async (client) => {
      const updated = await client.query<QueryResultRow>(
        `
        UPDATE actual_activity_logs
        SET
          title = COALESCE($3, title),
          status = COALESCE($4, status),
          note = COALESCE($5, note),
          source_payload = source_payload || $6::jsonb,
          updated_at = now()
        WHERE user_id = $1 AND id = $2
        RETURNING id::text AS id, title, status, note, source_payload AS metadata, updated_at AS "updatedAt"
        `,
        [
          userId,
          actualId,
          clean(body.title),
          clean(body.status),
          clean(body.note),
          JSON.stringify(metadata),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'admin', 'admin.actual.update', {
        actualId,
      });
      return updated.rows[0] ?? null;
    });
    return { ok: !!result, actualRecord: result };
  }

  async files(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const search = searchPattern(query.q);
    const folders = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        folder_uid AS "folderUid",
        provider,
        display_name AS "displayName",
        local_path AS "localPath",
        remote_id AS "remoteId",
        pinned,
        use_count AS "useCount",
        last_used_at AS "lastUsedAt",
        updated_at AS "updatedAt"
      FROM file_folders
      WHERE user_id = $1
        AND ($2::text IS NULL OR display_name ILIKE $2 OR local_path ILIKE $2)
      ORDER BY pinned DESC, last_used_at DESC NULLS LAST, display_name ASC
      LIMIT $3 OFFSET $4
      `,
      [userId, search, limit, offset],
    );
    const files = await this.database.query<QueryResultRow>(
      `
      SELECT
        fi.id::text AS id,
        fi.file_uid AS "fileUid",
        fi.provider,
        fi.display_name AS "displayName",
        fi.local_path AS "localPath",
        fi.remote_id AS "remoteId",
        fi.mime_type AS "mimeType",
        fi.size_bytes AS "sizeBytes",
        fi.modified_at AS "lastModifiedAt",
        ff.display_name AS "folderName",
        fi.updated_at AS "updatedAt"
      FROM file_items fi
      LEFT JOIN file_folders ff ON ff.id = fi.folder_id
      WHERE fi.user_id = $1
        AND ($2::text IS NULL OR fi.display_name ILIKE $2 OR fi.local_path ILIKE $2)
      ORDER BY fi.updated_at DESC
      LIMIT $3 OFFSET $4
      `,
      [userId, search, limit, offset],
    );
    return { limit, offset, folders: folders.rows, files: files.rows };
  }

  async updateFile(
    fileId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.transaction(async (client) => {
      const updated = await client.query<QueryResultRow>(
        `
        UPDATE file_items
        SET
          display_name = COALESCE($3, display_name),
          mime_type = COALESCE($4, mime_type),
          remote_id = COALESCE($5, remote_id),
          updated_at = now()
        WHERE user_id = $1 AND id = $2
        RETURNING id::text AS id, display_name AS "displayName", mime_type AS "mimeType", remote_id AS "remoteId"
        `,
        [
          userId,
          fileId,
          clean(body.displayName),
          clean(body.mimeType),
          clean(body.remoteId),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'admin', 'admin.file.update', {
        fileId,
      });
      return updated.rows[0] ?? null;
    });
    return { ok: !!result, file: result };
  }

  async conflicts(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = this.readDeviceId(query.deviceId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        c.id::text AS "conflictId",
        c.mutation_uid AS "mutationUid",
        c.object_type AS "objectType",
        c.local_id AS "localId",
        c.server_object_id::text AS "serverId",
        c.status,
        c.fields,
        c.created_at AS "createdAt",
        c.resolved_at AS "resolvedAt",
        c.device_id::text AS "deviceId",
        d.device_name AS "deviceName"
      FROM sync_conflicts c
      LEFT JOIN devices d ON d.id = c.device_id
      WHERE c.user_id = $1
        AND ($2::uuid IS NULL OR c.device_id = $2::uuid)
      ORDER BY c.created_at DESC
      LIMIT 200
      `,
      [userId, deviceId],
    );
    return { conflicts: result.rows };
  }

  async outlook(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const mappings = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        flowplanv2_object_type AS "flowplanV2ObjectType",
        flowplanv2_object_id::text AS "flowplanV2ObjectId",
        outlook_object_type AS "outlookObjectType",
        outlook_object_id AS "outlookObjectId",
        outlook_calendar_id AS "outlookCalendarId",
        sync_state AS "syncState",
        last_remote_etag AS "lastRemoteEtag",
        last_synced_at AS "lastSyncedAt",
        updated_at AS "updatedAt"
      FROM outlook_object_mappings
      WHERE user_id = $1
      ORDER BY updated_at DESC
      LIMIT 200
      `,
      [userId],
    );
    const summary = await this.countByStatus(
      userId,
      'SELECT sync_state AS name FROM outlook_object_mappings WHERE user_id = $1',
    );
    return { summary, mappings: mappings.rows };
  }

  async auditLogs(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const search = searchPattern(query.q);
    const deviceId = this.readDeviceId(query.deviceId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        a.id::text AS id,
        a.actor,
        a.action,
        a.entity_type AS "targetType",
        a.entity_id AS "targetId",
        a.summary,
        a.metadata AS details,
        a.occurred_at AS "occurredAt",
        a.occurred_at AS "createdAt",
        a.device_id::text AS "deviceId",
        d.device_name AS "deviceName"
      FROM audit_logs a
      LEFT JOIN devices d ON d.id = a.device_id
      WHERE a.user_id = $1
        AND ($2::text IS NULL OR a.actor ILIKE $2 OR a.action ILIKE $2 OR a.summary ILIKE $2 OR a.metadata::text ILIKE $2 OR COALESCE(d.device_name, '') ILIKE $2)
        AND ($3::uuid IS NULL OR a.device_id = $3::uuid)
      ORDER BY a.occurred_at DESC
      LIMIT $4 OFFSET $5
      `,
      [userId, search, deviceId, limit, offset],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  async reports(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 80, 1, 200);
    const offset = readOffset(query.offset);
    const status = clean(query.status);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        report_uid AS "reportUid",
        report_type AS "reportType",
        period_start AS "periodStart",
        period_end AS "periodEnd",
        title,
        summary_markdown AS summary,
        status,
        created_at AS "createdAt",
        created_at AS "generatedAt",
        updated_at AS "updatedAt"
      FROM report_documents
      WHERE user_id = $1 AND ($2::text IS NULL OR status = $2)
      ORDER BY period_start DESC
      LIMIT $3 OFFSET $4
      `,
      [userId, status, limit, offset],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  async pushDeliveries(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const status = clean(query.status);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        delivery_uid AS "deliveryUid",
        channel,
        target,
        status,
        scheduled_at AS "scheduledAt",
        sent_at AS "sentAt",
        last_error AS "errorMessage",
        attempts AS "retryCount",
        updated_at AS "updatedAt"
      FROM report_push_deliveries
      WHERE user_id = $1 AND ($2::text IS NULL OR status = $2)
      ORDER BY scheduled_at DESC
      LIMIT $3 OFFSET $4
      `,
      [userId, status, limit, offset],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  async aiDrafts(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 80, 1, 200);
    const offset = readOffset(query.offset);
    const status = clean(query.status);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        source,
        conversation_id AS "conversationId",
        title,
        summary,
        proposed_action AS "proposedAction",
        target_type AS "targetType",
        target_id AS "targetId",
        status,
        risk_level AS "riskLevel",
        request_payload AS "requestPayload",
        proposed_payload AS "proposedPayload",
        review_note AS "reviewNote",
        reviewed_at AS "reviewedAt",
        execution_status AS "executionStatus",
        execution_result AS "executionResult",
        executed_at AS "executedAt",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM ai_operation_drafts
      WHERE user_id = $1 AND ($2::text IS NULL OR status = $2)
      ORDER BY created_at DESC
      LIMIT $3 OFFSET $4
      `,
      [userId, status, limit, offset],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  async updateAiDraft(
    draftId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.transaction(async (client) => {
      const updated = await client.query<QueryResultRow>(
        `
        UPDATE ai_operation_drafts
        SET
          status = COALESCE($3, status),
          review_note = COALESCE($4, review_note),
          reviewed_at = CASE WHEN $3::text IS NULL THEN reviewed_at ELSE now() END,
          updated_at = now()
        WHERE user_id = $1 AND id = $2
        RETURNING id::text AS id, status, review_note AS "reviewNote", reviewed_at AS "reviewedAt"
        `,
        [userId, draftId, clean(body.status), clean(body.reviewNote)],
      );
      await this.recordAudit(client, userId, deviceId, 'admin', 'admin.ai_draft.review', {
        draftId,
        status: clean(body.status),
      });
      return updated.rows[0] ?? null;
    });
    return { ok: !!result, draft: result };
  }

  async jobs(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        job_key AS "jobKey",
        job_type AS "jobType",
        status,
        last_started_at AS "lastStartedAt",
        last_finished_at AS "lastFinishedAt",
        next_run_at AS "nextRunAt",
        last_error AS "lastError",
        metadata,
        updated_by AS "updatedBy",
        updated_at AS "updatedAt"
      FROM server_jobs
      WHERE user_id = $1
      ORDER BY next_run_at ASC NULLS LAST, updated_at DESC
      `,
      [userId],
    );
    return { jobs: result.rows };
  }

  async upsertJob(
    jobKey: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const metadata = asRecord(body.metadata);
    const result = await this.database.transaction(async (client) => {
      const upserted = await client.query<QueryResultRow>(
        `
        INSERT INTO server_jobs (
          user_id,
          job_key,
          job_type,
          status,
          next_run_at,
          last_error,
          metadata,
          updated_by
        ) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, 'admin')
        ON CONFLICT (user_id, job_key) DO UPDATE SET
          job_type = COALESCE(EXCLUDED.job_type, server_jobs.job_type),
          status = COALESCE(EXCLUDED.status, server_jobs.status),
          next_run_at = COALESCE(EXCLUDED.next_run_at, server_jobs.next_run_at),
          last_error = EXCLUDED.last_error,
          metadata = server_jobs.metadata || EXCLUDED.metadata,
          updated_by = 'admin',
          updated_at = now()
        RETURNING id::text AS id, job_key AS "jobKey", status, metadata
        `,
        [
          userId,
          jobKey,
          clean(body.jobType) ?? 'manual',
          clean(body.status) ?? 'idle',
          readDate(body.nextRunAt),
          clean(body.lastError),
          JSON.stringify(metadata),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'admin', 'admin.job.upsert', {
        jobKey,
      });
      return upserted.rows[0];
    });
    return { ok: true, job: result };
  }

  async remoteConfigs(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        config_key AS "configKey",
        CASE WHEN is_sensitive THEN '{"masked":true}'::jsonb ELSE config_value END AS "configValue",
        scope,
        description,
        is_sensitive AS "isSensitive",
        version,
        updated_by AS "updatedBy",
        updated_at AS "updatedAt"
      FROM admin_remote_configs
      WHERE user_id = $1
      ORDER BY config_key ASC
      `,
      [userId],
    );
    return { configs: result.rows };
  }

  async upsertRemoteConfig(
    configKey: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const value = asRecord(body.configValue ?? body.value);
    const result = await this.database.transaction(async (client) => {
      const upserted = await client.query<QueryResultRow>(
        `
        INSERT INTO admin_remote_configs (
          user_id,
          config_key,
          config_value,
          scope,
          description,
          is_sensitive,
          updated_by
        ) VALUES ($1, $2, $3::jsonb, $4, $5, $6, 'admin')
        ON CONFLICT (user_id, config_key) DO UPDATE SET
          config_value = EXCLUDED.config_value,
          scope = EXCLUDED.scope,
          description = COALESCE(EXCLUDED.description, admin_remote_configs.description),
          is_sensitive = EXCLUDED.is_sensitive,
          updated_by = 'admin',
          version = admin_remote_configs.version + 1,
          updated_at = now()
        RETURNING id::text AS id, config_key AS "configKey", scope, is_sensitive AS "isSensitive", version, updated_at AS "updatedAt"
        `,
        [
          userId,
          configKey,
          JSON.stringify(value),
          clean(body.scope) ?? 'user.preference',
          clean(body.description),
          Boolean(body.isSensitive),
        ],
      );
      await this.recordAudit(
        client,
        userId,
        deviceId,
        'admin',
        'admin.remote_config.upsert',
        { configKey, isSensitive: Boolean(body.isSensitive) },
      );
      return upserted.rows[0];
    });
    return { ok: true, config: result };
  }

  async dashboard(context: FlowPlanV2RequestContext) {
    const [overview, syncHealth, audit, jobs] = await Promise.all([
      this.overview(context),
      this.syncHealth(context),
      this.auditLogs({ limit: '8' }, context),
      this.jobs(context),
    ]);
    const failedJobs = (jobs.jobs as QueryResultRow[]).filter(
      (job) => job.status === 'failed',
    );
    return {
      generatedAt: new Date().toISOString(),
      overview,
      syncHealth,
      recentAuditLogs: audit.items,
      failedJobs,
      pending: {
        conflicts: overview.conflictCounts?.open ?? 0,
        aiDrafts: overview.draftCounts?.pending_review ?? 0,
        failedPushes: overview.pushCounts?.failed ?? 0,
        failedJobs: failedJobs.length,
      },
    };
  }

  async adminData(
    domain: string,
    query: AdminQuery,
    context: FlowPlanV2RequestContext,
  ) {
    switch (domain) {
      case 'tasks':
      case 'schedules':
      case 'tracking':
      case 'objects':
        return this.objects({ ...query, domain }, context);
      case 'actuals':
        return this.actualRecords(query, context);
      case 'files':
        return this.files(query, context);
      case 'reports':
        return this.reports(query, context);
      case 'push-deliveries':
        return this.pushDeliveries(query, context);
      case 'ai-drafts':
        return this.aiDrafts(query, context);
      case 'tracking-ingest-batches':
        return this.trackingIngestBatches(query, context);
      case 'activity-segments':
        return this.activitySegments(query, context);
      case 'task-work-logs':
        return this.taskWorkLogs(query, context);
      case 'schedule-runs':
        return this.scheduleRuns(query, context);
      case 'schedule-draft-items':
        return this.scheduleDraftItems(query, context);
      case 'plan-deviations':
        return this.planDeviations(query, context);
      case 'report-entries':
        return this.reportEntries(query, context);
      case 'report-evidence':
        return this.reportEvidence(query, context);
      case 'file-operation-logs':
        return this.fileOperationLogs(query, context);
      case 'activity-interpretations':
      case 'tracking-ingest-chunks':
      case 'models':
      case 'model-versions':
      case 'model-runs':
      case 'model-feedback':
      case 'model-rule-profiles':
      case 'model-eval-cases':
      case 'model-rule-change-drafts':
      case 'file-roots':
      case 'file-nodes':
      case 'file-recent-items':
      case 'file-recommendations':
      case 'transfer-candidates':
      case 'transfer-events':
      case 'network-presence':
      case 'ai-policies':
      case 'ai-tool-calls':
      case 'report-templates':
      case 'push-channels':
      case 'weather-locations':
      case 'weather-cache':
      case 'reality-context':
        return this.genericAdminTable(domain, query, context);
      case 'audit-logs':
        return this.auditLogs(query, context);
      case 'devices':
        return this.adminDevices(query, context);
      case 'sync-changes':
        return this.syncChanges(query, context);
      case 'sync-mutations':
        return this.syncMutations(query, context);
      case 'conflicts':
        return this.conflicts(query, context);
      case 'configs':
      case 'settings':
        return this.remoteConfigs(context);
      default:
        return {
          domain,
          items: [],
          error: 'Unknown admin data domain',
        };
    }
  }

  async adminDataDetail(
    domain: string,
    id: string,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const table = this.tableForDomain(domain);
    if (!table) {
      return { domain, id, item: null, error: 'Unknown admin data domain' };
    }
    const result = await this.database.query<QueryResultRow>(
      `SELECT * FROM ${table} WHERE user_id = $1 AND id::text = $2 LIMIT 1`,
      [userId, id],
    );
    const audit = await this.database.query<QueryResultRow>(
      `
      SELECT id::text AS id, actor, action, summary, metadata, occurred_at AS "occurredAt"
      FROM audit_logs
      WHERE user_id = $1 AND (entity_id = $2 OR metadata::text ILIKE $3)
      ORDER BY occurred_at DESC
      LIMIT 30
      `,
      [userId, id, `%${id}%`],
    );
    return { domain, id, item: result.rows[0] ?? null, auditLogs: audit.rows };
  }

  async updateAdminData(
    domain: string,
    id: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    if (domain === 'objects' || domain === 'tasks' || domain === 'schedules') {
      return this.updateObject(id, body, context);
    }
    if (domain === 'actuals') {
      return this.updateActualRecord(id, body, context);
    }
    if (domain === 'files') {
      return this.updateFile(id, body, context);
    }
    if (domain === 'settings' || domain === 'configs') {
      return this.upsertRemoteConfig(id, body, context);
    }
    await this.recordAdminAction(context, 'admin.data.update.rejected', {
      domain,
      targetId: id,
      reason: 'No controlled writer for this domain yet',
    });
    return {
      ok: false,
      domain,
      id,
      error: 'This domain is read-only in the current admin console.',
    };
  }

  async adminSettings(context: FlowPlanV2RequestContext) {
    const configs = await this.remoteConfigs(context);
    return {
      scopes: [
        'user.preference',
        'sync.policy',
        'ai.provider',
        'file.provider',
        'report.push',
        'scheduler.policy',
        'activity.rules',
      ],
      deviceLocalPrefixes: [
        'server.api.base_url',
        'auth.',
        'device.identity.',
        'window.',
        'tray.',
        'startup.',
        'permission.',
        'download.',
        'cache.',
        'kopia.local.',
      ],
      configs: configs.configs,
    };
  }

  async monitoringHealth(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const db = await this.database.query<{ now: Date }>('SELECT now() AS now');
    const counts = await this.database.query<QueryResultRow>(
      `
      SELECT
        (SELECT COUNT(*)::int FROM sync_changes WHERE user_id = $1) AS "syncChanges",
        (SELECT COUNT(*)::int FROM sync_conflicts WHERE user_id = $1 AND status = 'open') AS "openConflicts",
        (SELECT COUNT(*)::int FROM sync_mutations WHERE user_id = $1 AND result = 'rejected') AS "failedMutations",
        (SELECT COUNT(*)::int FROM file_transfer_sessions WHERE user_id = $1 AND status = 'failed') AS "failedTransfers",
        (SELECT COUNT(*)::int FROM server_jobs WHERE user_id = $1 AND status = 'failed') AS "failedJobs",
        (SELECT COUNT(*)::int FROM model_runs WHERE user_id = $1 AND status = 'failed') AS "failedModelRuns",
        (SELECT COUNT(*)::int FROM model_runs WHERE user_id = $1 AND started_at > now() - interval '24 hours') AS "modelRuns24h"
      `,
      [userId],
    );
    const storage = await this.safeStorageStatus();
    return {
      generatedAt: new Date().toISOString(),
      database: { ok: true, serverTime: db.rows[0]?.now },
      api: { ok: true, surface: 'admin' },
      storage,
      kopia: {
        executable: process.env.KOPIA_EXE ?? 'kopia',
        status: 'checked_when_snapshot_or_restore_is_requested',
      },
      counters: counts.rows[0] ?? {},
    };
  }

  async monitoringLogs(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const [audit, mutations, conflicts] = await Promise.all([
      this.auditLogs(query, context),
      this.syncMutations({ ...query, status: 'rejected', limit: query.limit ?? '50' }, context),
      this.conflicts(query, context),
    ]);
    return {
      auditLogs: audit.items,
      failedMutations: mutations.items,
      conflicts: conflicts.conflicts,
    };
  }

  async monitoringJobs(context: FlowPlanV2RequestContext) {
    return this.jobs(context);
  }

  async prepareOperation(
    operationKey: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const token = randomUUID();
    await this.recordAdminAction(context, 'admin.operation.prepare', {
      operationKey,
      targetType: 'admin_operation',
      targetId: operationKey,
      dryRun: body.dryRun !== false,
      confirmationToken: token,
      payload: asRecord(body),
    });
    return {
      operationKey,
      dryRun: body.dryRun !== false,
      confirmationToken: token,
      impact: this.operationImpact(operationKey, body),
      requiresConfirmation: true,
    };
  }

  async confirmOperation(
    operationKey: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const token = clean(body.confirmationToken);
    if (!token) {
      return {
        ok: false,
        operationKey,
        error: 'confirmationToken is required',
      };
    }
    await this.recordAdminAction(context, 'admin.operation.confirm', {
      operationKey,
      targetType: 'admin_operation',
      targetId: operationKey,
      confirmationToken: token,
      reason: clean(body.reason),
      payload: asRecord(body),
    });
    return {
      ok: true,
      operationKey,
      status: 'accepted_for_manual_or_background_execution',
    };
  }

  async recordAdminAction(
    context: FlowPlanV2RequestContext,
    action: string,
    details: Record<string, unknown>,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.database.query(
      `
      INSERT INTO audit_logs (
        user_id,
        device_id,
        actor,
        action,
        entity_type,
        entity_id,
        summary,
        metadata
      ) VALUES ($1, $2, 'admin', $3, $4, $5, $6, $7::jsonb)
      `,
      [
        userId,
        deviceId,
        action,
        String(details.targetType ?? 'admin'),
        details.targetId ? String(details.targetId) : null,
        action,
        JSON.stringify(details),
      ],
    );
  }

  private async adminDevices(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const search = searchPattern(query.q);
    const deviceId = this.readDeviceId(query.deviceId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        device_name AS "deviceName",
        platform,
        client_device_id AS "clientDeviceId",
        last_seen_at AS "lastSeenAt",
        last_heartbeat_at AS "lastHeartbeatAt",
        last_connected_at AS "lastConnectedAt",
        last_disconnected_at AS "lastDisconnectedAt",
        last_connection_error AS "lastConnectionError",
        app_version AS "appVersion",
        runtime_platform AS "runtimePlatform",
        network_type AS "networkType",
        sync_pending_count AS "syncPendingCount",
        sync_failed_count AS "syncFailedCount",
        open_conflict_count AS "openConflictCount",
        created_at AS "createdAt",
        updated_at AS "updatedAt",
        CASE
          WHEN last_heartbeat_at IS NULL THEN 'offline'
          WHEN last_heartbeat_at > now() - interval '90 seconds' THEN 'online'
          WHEN last_heartbeat_at > now() - interval '10 minutes' THEN 'degraded'
          ELSE 'offline'
        END AS status
      FROM devices
      WHERE user_id = $1
        AND ($2::text IS NULL OR device_name ILIKE $2 OR platform ILIKE $2 OR client_device_id ILIKE $2)
        AND ($3::uuid IS NULL OR id = $3::uuid)
      ORDER BY last_seen_at DESC NULLS LAST, created_at DESC
      LIMIT $4 OFFSET $5
      `,
      [userId, search, deviceId, limit, offset],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  private async syncChanges(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const objectType = clean(query.objectType);
    const deviceId = this.readDeviceId(query.deviceId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        c.id::text AS id,
        c.object_type AS "objectType",
        c.server_object_id::text AS "serverObjectId",
        c.action,
        c.server_version AS "serverVersion",
        c.payload,
        c.device_id::text AS "deviceId",
        d.device_name AS "deviceName",
        c.created_at AS "createdAt"
      FROM sync_changes c
      LEFT JOIN devices d ON d.id = c.device_id
      WHERE c.user_id = $1
        AND ($2::text IS NULL OR c.object_type = $2)
        AND ($3::uuid IS NULL OR c.device_id = $3::uuid)
      ORDER BY c.id DESC
      LIMIT $4 OFFSET $5
      `,
      [userId, objectType, deviceId, limit, offset],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  private async syncMutations(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const status = clean(query.status);
    const search = searchPattern(query.q);
    const deviceId = this.readDeviceId(query.deviceId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        m.mutation_uid AS id,
        m.mutation_uid AS "mutationUid",
        m.object_type AS "objectType",
        m.local_id AS "localId",
        m.action,
        m.result AS status,
        m.error_message AS "lastError",
        m.server_object_id::text AS "serverObjectId",
        m.base_server_version AS "baseServerVersion",
        m.device_id::text AS "deviceId",
        d.device_name AS "deviceName",
        m.created_at AS "createdAt"
      FROM sync_mutations m
      LEFT JOIN devices d ON d.id = m.device_id
      WHERE m.user_id = $1
        AND ($2::text IS NULL OR m.result = $2)
        AND ($3::text IS NULL OR m.mutation_uid ILIKE $3 OR m.object_type ILIKE $3 OR m.local_id ILIKE $3 OR m.error_message ILIKE $3 OR COALESCE(d.device_name, '') ILIKE $3)
        AND ($4::uuid IS NULL OR m.device_id = $4::uuid)
      ORDER BY m.created_at DESC
      LIMIT $5 OFFSET $6
      `,
      [userId, status, search, deviceId, limit, offset],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  private async trackingIngestBatches(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const status = clean(query.status);
    const search = searchPattern(query.q);
    const deviceId = this.readDeviceId(query.deviceId);
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
        b.device_id::text AS "deviceId",
        d.device_name AS "deviceName",
        d.platform
      FROM tracking_ingest_batches b
      LEFT JOIN devices d ON d.id = b.device_id
      WHERE b.user_id = $1
        AND ($2::text IS NULL OR b.status = $2)
        AND (
          $3::text IS NULL
          OR b.batch_uid ILIKE $3
          OR b.data_kind ILIKE $3
          OR COALESCE(b.error_message, '') ILIKE $3
          OR COALESCE(d.device_name, '') ILIKE $3
        )
        AND ($4::uuid IS NULL OR b.device_id = $4::uuid)
      ORDER BY b.created_at DESC
      LIMIT $5 OFFSET $6
      `,
      [userId, status, search, deviceId, limit, offset],
    );
    return { domain: 'tracking-ingest-batches', limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  private async activitySegments(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const status = clean(query.status);
    const search = searchPattern(query.q);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        s.id::text AS id,
        s.segment_uid AS "segmentUid",
        s.label AS title,
        s.status,
        s.start_at AS "startAt",
        s.end_at AS "endAt",
        s.duration_seconds AS "durationSeconds",
        s.primary_app AS "primaryApp",
        s.primary_process_name AS "primaryProcessName",
        s.primary_window_title AS "primaryWindowTitle",
        s.primary_file_path AS "primaryFilePath",
        s.category,
        s.confidence,
        s.matched_task_id AS "matchedTaskId",
        s.evidence,
        s.created_at AS "createdAt",
        s.updated_at AS "updatedAt"
      FROM activity_segments s
      WHERE s.user_id = $1
        AND ($2::text IS NULL OR s.status = $2)
        AND (
          $3::text IS NULL
          OR s.label ILIKE $3
          OR COALESCE(s.primary_app, '') ILIKE $3
          OR COALESCE(s.primary_window_title, '') ILIKE $3
          OR COALESCE(s.category, '') ILIKE $3
        )
      ORDER BY s.start_at DESC
      LIMIT $4 OFFSET $5
      `,
      [userId, status, search, limit, offset],
    );
    return { domain: 'activity-segments', limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  private async taskWorkLogs(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const status = clean(query.status);
    const search = searchPattern(query.q);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        w.id::text AS id,
        w.work_uid AS "workUid",
        w.task_id AS "taskId",
        COALESCE(t.payload->>'title', t.payload->>'summary', t.payload->>'name') AS "taskTitle",
        w.segment_id::text AS "segmentId",
        w.actual_id::text AS "actualId",
        w.start_at AS "startAt",
        w.end_at AS "endAt",
        w.duration_minutes AS "durationMinutes",
        w.confidence,
        w.source_type AS "sourceType",
        w.status,
        w.evidence,
        w.created_at AS "createdAt",
        w.updated_at AS "updatedAt"
      FROM task_work_logs w
      LEFT JOIN sync_objects t
        ON t.user_id = w.user_id
       AND t.deleted_at IS NULL
       AND t.uid = w.task_id
       AND t.object_type = ANY($6::text[])
      WHERE w.user_id = $1
        AND ($2::text IS NULL OR w.status = $2)
        AND (
          $3::text IS NULL
          OR w.task_id ILIKE $3
          OR w.work_uid ILIKE $3
          OR COALESCE(t.payload->>'title', t.payload->>'summary', t.payload->>'name', '') ILIKE $3
        )
      ORDER BY w.start_at DESC
      LIMIT $4 OFFSET $5
      `,
      [userId, status, search, limit, offset, ['task_item']],
    );
    return { domain: 'task-work-logs', limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  private async scheduleRuns(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const status = clean(query.status);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        range_start AS "rangeStart",
        range_end AS "rangeEnd",
        mode,
        strategy,
        status,
        COALESCE(risk_summary_json->>'modelUsed', risk_summary_json->>'generatedBy', 'rule') AS "modelUsed",
        risk_summary_json->>'modelVersion' AS "modelVersion",
        (output_summary_json->>'plannedCount')::int AS "plannedCount",
        output_summary_json->'unplanned' AS unplanned,
        input_snapshot_json AS "inputSnapshot",
        output_summary_json AS "outputSummary",
        risk_summary_json AS "riskSummary",
        created_at AS "createdAt",
        updated_at AS "updatedAt",
        confirmed_at AS "confirmedAt",
        rejected_at AS "rejectedAt"
      FROM schedule_runs
      WHERE user_id = $1 AND ($2::text IS NULL OR status = $2)
      ORDER BY created_at DESC
      LIMIT $3 OFFSET $4
      `,
      [userId, status, limit, offset],
    );
    return { domain: 'schedule-runs', limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  private async scheduleDraftItems(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const status = clean(query.status);
    const search = searchPattern(query.q);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        i.id::text AS id,
        i.schedule_run_id::text AS "scheduleRunId",
        i.task_id AS "taskId",
        i.task_title AS "taskTitle",
        i.proposed_start AS "proposedStart",
        i.proposed_end AS "proposedEnd",
        i.action,
        i.confidence,
        i.reason_json AS reason,
        i.risk_json AS risk,
        i.status,
        i.user_modified_start AS "userModifiedStart",
        i.user_modified_end AS "userModifiedEnd",
        i.user_reject_reason AS "rejectReason",
        i.created_at AS "createdAt",
        i.updated_at AS "updatedAt"
      FROM schedule_draft_items i
      WHERE i.user_id = $1
        AND ($2::text IS NULL OR i.status = $2)
        AND ($3::text IS NULL OR COALESCE(i.task_title, '') ILIKE $3 OR COALESCE(i.task_id, '') ILIKE $3)
      ORDER BY i.created_at DESC
      LIMIT $4 OFFSET $5
      `,
      [userId, status, search, limit, offset],
    );
    return { domain: 'schedule-draft-items', limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  private async planDeviations(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const status = clean(query.status);
    const search = searchPattern(query.q);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        schedule_segment_id AS "scheduleSegmentId",
        planned_task_id AS "plannedTaskId",
        planned_start AS "plannedStart",
        planned_end AS "plannedEnd",
        actual_log_id::text AS "actualLogId",
        actual_segment_id::text AS "actualSegmentId",
        actual_title AS "actualTitle",
        actual_start AS "actualStart",
        actual_end AS "actualEnd",
        deviation_type AS "deviationType",
        severity,
        confidence,
        status,
        evidence,
        created_at AS "createdAt",
        handled_at AS "handledAt"
      FROM plan_deviations
      WHERE user_id = $1
        AND ($2::text IS NULL OR status = $2)
        AND (
          $3::text IS NULL
          OR COALESCE(deviation_type, '') ILIKE $3
          OR COALESCE(actual_title, '') ILIKE $3
          OR COALESCE(planned_task_id, '') ILIKE $3
        )
      ORDER BY created_at DESC
      LIMIT $4 OFFSET $5
      `,
      [userId, status, search, limit, offset],
    );
    return { domain: 'plan-deviations', limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  private async reportEntries(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const search = searchPattern(query.q);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        e.id::text AS id,
        e.report_id::text AS "reportId",
        e.entry_type AS "entryType",
        e.title,
        e.body,
        e.order_index AS "orderIndex",
        e.payload_json AS payload,
        e.created_at AS "createdAt"
      FROM report_entries e
      WHERE e.user_id = $1
        AND ($2::text IS NULL OR e.entry_type ILIKE $2 OR e.title ILIKE $2 OR COALESCE(e.body, '') ILIKE $2)
      ORDER BY e.created_at DESC
      LIMIT $3 OFFSET $4
      `,
      [userId, search, limit, offset],
    );
    return { domain: 'report-entries', limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  private async reportEvidence(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const search = searchPattern(query.q);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        report_id::text AS "reportId",
        entry_id::text AS "entryId",
        source_type AS "sourceType",
        source_id AS "sourceId",
        evidence_type AS "evidenceType",
        summary,
        payload_json AS payload,
        created_at AS "createdAt"
      FROM report_evidence_links
      WHERE user_id = $1
        AND (
          $2::text IS NULL
          OR source_type ILIKE $2
          OR evidence_type ILIKE $2
          OR COALESCE(summary, '') ILIKE $2
        )
      ORDER BY created_at DESC
      LIMIT $3 OFFSET $4
      `,
      [userId, search, limit, offset],
    );
    return { domain: 'report-evidence', limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  private async fileOperationLogs(query: AdminQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const status = clean(query.status);
    const search = searchPattern(query.q);
    const deviceId = this.readDeviceId(query.deviceId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        l.id::text AS id,
        l.operation AS action,
        l.node_id::text AS "nodeId",
        l.source_path AS "sourcePath",
        l.target_path AS "targetPath",
        l.status,
        l.error_message AS "lastError",
        l.metadata AS details,
        l.device_id::text AS "deviceId",
        d.device_name AS "deviceName",
        l.created_at AS "createdAt"
      FROM file_operation_logs l
      LEFT JOIN devices d ON d.id = l.device_id
      WHERE l.user_id = $1
        AND ($2::text IS NULL OR l.status = $2)
        AND (
          $3::text IS NULL
          OR l.operation ILIKE $3
          OR COALESCE(l.source_path, '') ILIKE $3
          OR COALESCE(l.target_path, '') ILIKE $3
          OR COALESCE(l.error_message, '') ILIKE $3
          OR COALESCE(d.device_name, '') ILIKE $3
        )
        AND ($4::uuid IS NULL OR l.device_id = $4::uuid)
      ORDER BY l.created_at DESC
      LIMIT $5 OFFSET $6
      `,
      [userId, status, search, deviceId, limit, offset],
    );
    return { domain: 'file-operation-logs', limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  private async genericAdminTable(
    domain: string,
    query: AdminQuery,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const table = this.tableForDomain(domain);
    if (!table) {
      return { domain, items: [], error: 'Unknown admin data domain' };
    }
    const limit = readLimit(query.limit, 100, 1, 200);
    const offset = readOffset(query.offset);
    const status = clean(query.status);
    const search = searchPattern(query.q);
    const deviceId = this.readDeviceId(query.deviceId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        t.*,
        t.id::text AS id,
        COALESCE(
          to_jsonb(t)->>'title',
          to_jsonb(t)->>'name',
          to_jsonb(t)->>'display_name',
          to_jsonb(t)->>'operation',
          to_jsonb(t)->>'event_type',
          to_jsonb(t)->>'tool_name',
          t.id::text
        ) AS title,
        COALESCE(
          to_jsonb(t)->>'status',
          to_jsonb(t)->>'scan_status',
          to_jsonb(t)->>'permission_level',
          'record'
        ) AS status
      FROM ${table} t
      WHERE t.user_id = $1
        AND ($2::text IS NULL OR to_jsonb(t)::text ILIKE $2)
        AND (
          $3::text IS NULL OR
          COALESCE(
            to_jsonb(t)->>'status',
            to_jsonb(t)->>'scan_status',
            to_jsonb(t)->>'permission_level'
          ) = $3
        )
        AND ($4::text IS NULL OR to_jsonb(t)->>'device_id' = $4)
      ORDER BY COALESCE(
        (to_jsonb(t)->>'updated_at')::timestamptz,
        (to_jsonb(t)->>'created_at')::timestamptz,
        now()
      ) DESC
      LIMIT $5 OFFSET $6
      `,
      [userId, search, status, deviceId, limit, offset],
    );
    return { domain, table, limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  private tableForDomain(domain: string) {
    const tables: Record<string, string> = {
      objects: 'sync_objects',
      tasks: 'sync_objects',
      schedules: 'sync_objects',
      actuals: 'actual_activity_logs',
      files: 'file_items',
      reports: 'report_documents',
      'ai-drafts': 'ai_operation_drafts',
      models: 'model_definitions',
      'model-versions': 'model_versions',
      'model-runs': 'model_runs',
      'model-feedback': 'model_feedback_events',
      'model-rule-profiles': 'model_rule_profiles',
      'model-eval-cases': 'model_eval_cases',
      'model-rule-change-drafts': 'model_rule_change_drafts',
      'audit-logs': 'audit_logs',
      devices: 'devices',
      'sync-changes': 'sync_changes',
      'sync-mutations': 'sync_mutations',
      conflicts: 'sync_conflicts',
      settings: 'admin_remote_configs',
      configs: 'admin_remote_configs',
      'activity-segments': 'activity_segments',
      'activity-interpretations': 'activity_interpretations',
      'tracking-ingest-batches': 'tracking_ingest_batches',
      'tracking-ingest-chunks': 'tracking_ingest_chunks',
      'task-work-logs': 'task_work_logs',
      'schedule-runs': 'schedule_runs',
      'schedule-draft-items': 'schedule_draft_items',
      'plan-deviations': 'plan_deviations',
      'file-roots': 'file_roots',
      'file-nodes': 'file_nodes',
      'file-recent-items': 'file_recent_items',
      'file-recommendations': 'file_recommendations',
      'file-operation-logs': 'file_operation_logs',
      'transfer-candidates': 'file_transfer_candidates',
      'transfer-events': 'file_transfer_events',
      'network-presence': 'device_network_presence',
      'ai-policies': 'ai_tool_policies',
      'ai-tool-calls': 'ai_tool_calls',
      'report-entries': 'report_entries',
      'report-evidence': 'report_evidence_links',
      'report-templates': 'report_templates',
      'push-channels': 'push_channels',
      'push-deliveries': 'report_push_deliveries',
      'weather-locations': 'weather_locations',
      'weather-cache': 'weather_cache',
      'reality-context': 'reality_context_sources',
    };
    return tables[domain] ?? null;
  }

  private operationImpact(
    operationKey: string,
    body: Record<string, unknown>,
  ) {
    switch (operationKey) {
      case 'retry_sync':
        return {
          risk: 'medium',
          summary: '重新尝试失败同步，不直接覆盖业务数据。',
          target: body.targetId ?? body.deviceId ?? 'all',
        };
      case 'resolve_conflict':
        return {
          risk: 'high',
          summary: '冲突处理会改变服务端事实库，必须人工确认策略。',
          conflictId: body.conflictId,
        };
      case 'run_job':
        return {
          risk: 'medium',
          summary: '触发后台任务运行，任务自身仍需要记录审计。',
          jobKey: body.jobKey,
        };
      case 'export_diagnostics':
        return {
          risk: 'low',
          summary: '生成诊断数据包，不修改业务数据。',
        };
      default:
        return {
          risk: 'unknown',
          summary: '未知运维操作，仅记录 prepare/confirm 审计，不执行破坏性动作。',
        };
    }
  }

  private async countByObjectType(userId: string) {
    const result = await this.database.query<CountRow>(
      `
      SELECT object_type AS name, COUNT(*)::int AS count
      FROM sync_objects
      WHERE user_id = $1 AND deleted_at IS NULL
      GROUP BY object_type
      ORDER BY count DESC, object_type ASC
      `,
      [userId],
    );
    return this.countMap(result.rows);
  }

  private async countByStatus(userId: string, sourceSql: string) {
    const result = await this.database.query<CountRow>(
      `
      WITH source AS (${sourceSql})
      SELECT COALESCE(NULLIF(name, ''), 'unknown') AS name, COUNT(*)::int AS count
      FROM source
      GROUP BY name
      ORDER BY count DESC, name ASC
      `,
      [userId],
    );
    return this.countMap(result.rows);
  }

  private async scalarCount(userId: string, tableName: string) {
    const result = await this.database.query<{ count: string | number }>(
      `SELECT COUNT(*)::int AS count FROM ${tableName} WHERE user_id = $1`,
      [userId],
    );
    return toNumber(result.rows[0]?.count);
  }

  private async fileCounts(userId: string) {
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        (SELECT COUNT(*)::int FROM file_folders WHERE user_id = $1) AS folders,
        (SELECT COUNT(*)::int FROM file_items WHERE user_id = $1) AS files,
        (SELECT COUNT(*)::int FROM file_context_links WHERE user_id = $1) AS links,
        (SELECT COUNT(*)::int FROM file_version_records WHERE user_id = $1) AS versions,
        (SELECT COUNT(*)::int FROM file_roots WHERE user_id = $1) AS roots,
        (SELECT COUNT(*)::int FROM file_nodes WHERE user_id = $1) AS nodes,
        (SELECT COUNT(*)::int FROM file_transfer_sessions WHERE user_id = $1) AS transfers
      `,
      [userId],
    );
    const row = result.rows[0] ?? {};
    return {
      folders: toNumber(row.folders as string | number | undefined),
      files: toNumber(row.files as string | number | undefined),
      links: toNumber(row.links as string | number | undefined),
      versions: toNumber(row.versions as string | number | undefined),
      roots: toNumber(row.roots as string | number | undefined),
      nodes: toNumber(row.nodes as string | number | undefined),
      transfers: toNumber(row.transfers as string | number | undefined),
    };
  }

  private countMap(rows: CountRow[]) {
    return Object.fromEntries(
      rows.map((row) => [row.name ?? 'unknown', toNumber(row.count)]),
    );
  }

  private async recordChange(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    objectId: string,
    objectType: string,
    action: 'upsert' | 'delete',
    serverVersion: number,
    payload: Record<string, unknown>,
  ) {
    await client.query(
      `
      INSERT INTO sync_changes (
        user_id,
        device_id,
        server_object_id,
        object_type,
        action,
        server_version,
        payload
      ) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)
      `,
      [userId, deviceId, objectId, objectType, action, serverVersion, JSON.stringify(payload)],
    );
  }

  private async recordAudit(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    actor: string,
    action: string,
    details: Record<string, unknown>,
  ) {
    await client.query(
      `
      INSERT INTO audit_logs (
        user_id,
        device_id,
        actor,
        action,
        entity_type,
        entity_id,
        summary,
        metadata
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)
      `,
      [
        userId,
        deviceId,
        actor,
        action,
        String(details.targetType ?? 'admin'),
        details.targetId ? String(details.targetId) : null,
        action,
        JSON.stringify(details),
      ],
    );
  }

  private readObjectTypes(query: AdminQuery) {
    const domainTypes = query.domain ? DOMAIN_OBJECT_TYPES[query.domain] ?? [] : [];
    const explicitTypes = clean(query.objectType)
      ?.split(',')
      .map((item) => item.trim())
      .filter(Boolean);
    const selected = explicitTypes && explicitTypes.length > 0 ? explicitTypes : domainTypes;
    // Expand with legacy aliases for backward compatibility
    const expanded = new Set(selected);
    for (const key of Object.keys(LegacyTypeMap)) {
      if (expanded.has(LegacyTypeMap[key])) {
        expanded.add(key);
      }
    }
    return [...expanded];
  }

  // ---- D8: Alerts ----

  async alerts(userId: string) {
    const [tracking, sync, outlook, jobs, push] = await Promise.all([
      this.database.query(
        `SELECT id::text, batch_uid AS "batchUid", status, error_message AS "errorMessage", updated_at AS "updatedAt"
         FROM tracking_ingest_batches WHERE user_id=$1 AND status='failed'
         ORDER BY updated_at DESC LIMIT 5`, [userId]),
      this.database.query(
        `SELECT mutation_uid AS "mutationUid", object_type AS "objectType", result, error_message AS "errorMessage", created_at AS "createdAt"
         FROM sync_mutations WHERE user_id=$1 AND (result='failed' OR result='rejected') AND error_message IS NOT NULL
         ORDER BY created_at DESC LIMIT 10`, [userId]),
      this.database.query(
        `SELECT id::text, trigger_source AS "triggerSource", status, error_message AS "errorMessage", finished_at AS "finishedAt"
         FROM outlook_sync_runs WHERE user_id=$1 AND status='failed'
         ORDER BY finished_at DESC LIMIT 5`, [userId]),
      this.database.query(
        `SELECT id::text, job_key AS "jobKey", status, last_error AS "errorMessage", last_finished_at AS "lastFinishedAt"
         FROM server_jobs WHERE user_id=$1 AND (status='failed' OR last_error IS NOT NULL)
         ORDER BY last_finished_at DESC LIMIT 5`, [userId]),
      this.database.query(
        `SELECT id::text, channel, status, last_error AS "errorMessage", updated_at AS "updatedAt"
         FROM report_push_deliveries WHERE user_id=$1 AND status='failed'
         ORDER BY updated_at DESC LIMIT 5`, [userId]),
    ]);
    return {
      trackingFailures: tracking.rows,
      syncFailures: sync.rows,
      outlookFailures: outlook.rows,
      jobFailures: jobs.rows,
      pushFailures: push.rows,
      generatedAt: new Date().toISOString(),
    };
  }

  runtimeEnv() {
    return {
      database: { urlPresent: !!(process.env.FLOWPLANV2_DATABASE_URL ?? process.env.DATABASE_URL), poolMax: Number(process.env.DATABASE_POOL_MAX ?? 10), slowQueryThresholdMs: Number(process.env.SLOW_QUERY_THRESHOLD_MS ?? 1000) },
      encryption: { keySecure: !!(process.env.FLOWPLANV2_ENCRYPTION_KEY ?? process.env.OUTLOOK_CONFIG_SECRET ?? process.env.AI_CONFIG_SECRET), source: process.env.FLOWPLANV2_ENCRYPTION_KEY ? 'FLOWPLANV2_ENCRYPTION_KEY' : process.env.OUTLOOK_CONFIG_SECRET ? 'OUTLOOK_CONFIG_SECRET' : process.env.AI_CONFIG_SECRET ? 'AI_CONFIG_SECRET' : 'DATABASE_URL (fallback)' },
      jwt: { accessExpires: process.env.JWT_ACCESS_EXPIRES ?? '24h', refreshExpires: process.env.JWT_REFRESH_EXPIRES ?? '7d' },
      service: { port: Number(process.env.PORT ?? 3202), host: process.env.HOST ?? '0.0.0.0', bodyLimit: process.env.FLOWPLANV2_BODY_LIMIT ?? '50mb', corsOrigin: process.env.ADMIN_CORS_ORIGIN ?? '*' },
      storage: { dir: process.env.FLOWPLANV2_SERVER_STORAGE_DIR ?? null },
      kopia: { exePath: process.env.KOPIA_EXE ?? 'kopia', timeoutMs: Number(process.env.KOPIA_TIMEOUT_MS ?? 120000) },
      generatedAt: new Date().toISOString(),
    };
  }

  private readDeviceId(value: unknown) {
    const cleaned = clean(value);
    return cleaned && cleaned !== 'all' ? cleaned : null;
  }


  private async safeStorageStatus() {
    try {
      const status = await this.objectStorage.status();
      return { ok: true, ...status };
    } catch (error) {
      return {
        ok: false,
        error: error instanceof Error ? error.message : String(error),
      };
    }
  }

}
