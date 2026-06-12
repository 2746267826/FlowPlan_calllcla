import { ConflictException, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { QueryResultRow } from 'pg';
import { FlowPlanV2RequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import { clean, asRecord, readDate, readInt, searchPattern } from '../common/utils';
import { ObjectType } from '../common/constants/object-types';
import { normalizeTaskPayload } from '../common/schemas/task.schema';
import { normalizeEventPayload } from '../common/schemas/event.schema';

const TASK_TYPES = [ObjectType.TASK];
const EVENT_TYPES = [ObjectType.CALENDAR_EVENT];

@Injectable()
export class WebService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
  ) {}

  async dashboard(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const [
      conflicts,
      mutations,
      tasks,
      events,
      actuals,
      reminders,
    ] = await Promise.all([
      this.database.query(
        `SELECT COUNT(*)::int AS count FROM sync_conflicts WHERE user_id = $1 AND status = 'open'`,
        [userId],
      ),
      this.database.query(
        `
        SELECT
          COUNT(*) FILTER (WHERE result = 'failed')::int AS "failedMutations",
          COUNT(*) FILTER (WHERE result = 'pending')::int AS "pendingMutations"
        FROM sync_mutations
        WHERE user_id = $1
        `,
        [userId],
      ),
      this.tasks({ limit: '80' }, context),
      this.events({ limit: '80' }, context),
      this.actualRecords({ limit: '40' }, context),
      this.reminders(context),
    ]);
    const taskItems = (tasks.items as Array<Record<string, unknown>>).filter(
      (item) => !['done', 'completed', 'cancelled'].includes(String(item.status ?? '')),
    );
    const eventItems = events.items as Array<Record<string, unknown>>;
    const actualItems = actuals.items as Array<Record<string, unknown>>;
    const todayTasks = taskItems.filter((item) => this.isTodayLike(item.dueAt));
    const todayEvents = eventItems.filter((item) => this.isTodayLike(item.startAt));
    const todayActuals = actualItems.filter((item) => this.isTodayLike(item.startAt));
    const upcoming = [...todayEvents, ...taskItems]
      .map((item) => ({ item, time: this.futureTime(item.startAt ?? item.dueAt) }))
      .filter((entry): entry is { item: Record<string, unknown>; time: number } => entry.time !== null)
      .sort((a, b) => a.time - b.time)
      .map((entry) => entry.item);
    return {
      ok: true,
      mode: 'user_web_client',
      generatedAt: new Date().toISOString(),
      profile: {
        userId,
        deviceId,
        note: 'Flutter Web 是 FlowPlanV2 日常使用端；全局数据、审计和运维操作请使用 web_admin。',
      },
      today: {
        date: this.localDateKey(),
        tasks: todayTasks,
        events: todayEvents,
        actualRecords: todayActuals,
        current: this.currentEvent(todayEvents),
        next: upcoming[0] ?? null,
      },
      lists: {
        openTasks: taskItems.slice(0, 12),
        reminders: reminders.items,
      },
      sync: {
        openConflicts: Number(conflicts.rows[0]?.count ?? 0),
        failedMutations: Number(mutations.rows[0]?.failedMutations ?? 0),
        pendingMutations: Number(mutations.rows[0]?.pendingMutations ?? 0),
      },
    };
  }

  async tasks(query: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    return this.listObjects(query, context, TASK_TYPES, (row) => this.taskVm(row));
  }

  async events(query: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    return this.listObjects(query, context, EVENT_TYPES, (row) => this.eventVm(row));
  }

  async createTask(body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    return this.createObject('task_item', normalizeTaskPayload(body) as unknown as Record<string, unknown>, context);
  }

  async updateTask(id: string, body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    return this.updateObject(id, normalizeTaskPayload(body) as unknown as Record<string, unknown>, context, this.taskVm, this.numberValue(body.baseServerVersion));
  }

  async completeTask(id: string, body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    const payload = {
      status: 'done',
      completedAt: clean(body.completedAt) ?? new Date().toISOString(),
      updatedFrom: 'client',
      ...asRecord(body.payload),
    };
    return this.updateObject(
      id,
      payload,
      context,
      this.taskVm,
      this.numberValue(body.baseServerVersion),
    );
  }

  async deleteTask(id: string, context: FlowPlanV2RequestContext) {
    return this.deleteObject(id, 'task_item', context);
  }

  async createEvent(body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    return this.createObject('calendar_event', normalizeEventPayload(body) as unknown as Record<string, unknown>, context);
  }

  async updateEvent(id: string, body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    return this.updateObject(
      id,
      normalizeEventPayload(body) as unknown as Record<string, unknown>,
      context,
      this.eventVm,
      this.numberValue(body.baseServerVersion),
    );
  }

  async deleteEvent(id: string, context: FlowPlanV2RequestContext) {
    return this.deleteObject(id, 'calendar_event', context);
  }

  async actualRecords(query: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readInt(query.limit, 20, 1);
    const from = readDate(query.from);
    const to = readDate(query.to);
    const result = await this.database.query(
      `
      SELECT
        id::text,
        actual_uid AS "actualUid",
        title,
        start_at AS "startAt",
        end_at AS "endAt",
        source_type AS "sourceType",
        confidence,
        status,
        note,
        confirmed_at AS "confirmedAt"
      FROM actual_activity_logs
      WHERE user_id = $1
        AND ($2::timestamptz IS NULL OR start_at >= $2::timestamptz)
        AND ($3::timestamptz IS NULL OR start_at < $3::timestamptz)
      ORDER BY start_at DESC
      LIMIT $4
      `,
      [userId, from, to, limit],
    );
    return { items: result.rows };
  }

  async reminders(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query(
      `
      SELECT id::text, object_type AS "objectType", payload, updated_at AS "updatedAt"
      FROM sync_objects
      WHERE user_id = $1
        AND deleted_at IS NULL
        AND object_type = ANY($2::text[])
      ORDER BY updated_at DESC
      LIMIT 40
      `,
      [userId, [...TASK_TYPES, ...EVENT_TYPES]],
    );
    const items = result.rows.map((row) =>
      (EVENT_TYPES as readonly string[]).includes(String(row.objectType)) ? this.eventVm(row) : this.taskVm(row),
    ) as Array<Record<string, unknown>>;
    return {
      items: items.filter((item) => item.dueAt || item.startAt),
    };
  }

  async prepareOperation(
    operationKey: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const token = randomUUID();
    await this.recordAudit(this.database, userId, deviceId, `web.operation.${operationKey}.prepare`, {
      operationKey,
      confirmationToken: token,
      body,
    });
    return {
      ok: true,
      operationKey,
      confirmationToken: token,
      dryRun: true,
      impact: 'Web 端只完成准备和审计；高风险操作必须 confirm 后由对应模块执行。',
    };
  }

  async confirmOperation(
    operationKey: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.recordAudit(this.database, userId, deviceId, `web.operation.${operationKey}.confirm`, {
      operationKey,
      confirmationToken: clean(body.confirmationToken),
      body,
    });
    return {
      ok: true,
      operationKey,
      status: 'confirmed_audited',
      note: '具体高风险动作仍由对应业务接口执行，不能绕过人工确认和审计。',
    };
  }

  private async listObjects(
    query: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
    objectTypes: string[],
    mapper: (row: QueryResultRow) => Record<string, unknown>,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = readInt(query.limit, 20, 1);
    const q = searchPattern(query.q as string | undefined);
    const from = readDate(query.from);
    const to = readDate(query.to);
    const result = await this.database.query(
      `
      SELECT id::text, object_type AS "objectType", uid, payload, server_version AS "serverVersion",
             origin_device_id::text AS "originDeviceId", last_modified_device_id::text AS "lastModifiedDeviceId",
             created_at AS "createdAt", updated_at AS "updatedAt"
      FROM sync_objects
      WHERE user_id = $1
        AND deleted_at IS NULL
        AND object_type = ANY($2::text[])
        AND (
          $3::text IS NULL
          OR payload->>'title' ILIKE $3
          OR payload->>'summary' ILIKE $3
          OR payload->>'name' ILIKE $3
          OR payload->>'location' ILIKE $3
          OR payload->>'description' ILIKE $3
          OR payload->>'notes' ILIKE $3
        )
        AND (
          $4::text IS NULL
          OR COALESCE(
            NULLIF(payload->>'startAt', ''),
            NULLIF(payload->>'dueAt', ''),
            updated_at::text
          ) >= $4::text
        )
        AND (
          $5::text IS NULL
          OR COALESCE(
            NULLIF(payload->>'startAt', ''),
            NULLIF(payload->>'dueAt', ''),
            updated_at::text
          ) < $5::text
        )
      ORDER BY COALESCE(
        NULLIF(payload->>'startAt', ''),
        NULLIF(payload->>'dueAt', ''),
        updated_at::text
      ) ASC, updated_at DESC
      LIMIT $6
      `,
      [userId, objectTypes, q, from, to, limit],
    );
    return {
      limit,
      items: result.rows.map(mapper),
    };
  }

  private async createObject(
    objectType: string,
    payload: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const uid = clean(payload.uid) ?? `${objectType}:${randomUUID()}`;
    const result = await this.database.transaction(async (client) => {
      const existing = await client.query(
        `
        SELECT id::text, object_type AS "objectType", uid, payload,
               server_version AS "serverVersion", created_at AS "createdAt", updated_at AS "updatedAt"
        FROM sync_objects
        WHERE user_id = $1
          AND object_type = $2
          AND uid = $3
          AND deleted_at IS NULL
        LIMIT 1
        `,
        [userId, objectType, uid],
      );
      if (existing.rows[0]) {
        return { row: existing.rows[0], syncChangeId: null, auditId: null, replayed: true };
      }
      const row = await client.query(
        `
        INSERT INTO sync_objects (
          user_id, object_type, uid, payload, origin_device_id, last_modified_device_id
        ) VALUES ($1, $2, $3, $4::jsonb, $5, $5)
        RETURNING id::text, object_type AS "objectType", uid, payload,
                  server_version AS "serverVersion", created_at AS "createdAt", updated_at AS "updatedAt"
        `,
        [userId, objectType, uid, JSON.stringify(payload), deviceId],
      );
      const syncChangeId = await this.recordChange(client, userId, deviceId, row.rows[0], 'create');
      const auditId = await this.recordAudit(client, userId, deviceId, `web.${objectType}.create`, {
        objectId: row.rows[0]?.id,
        uid,
        payload,
      });
      return { row: row.rows[0], syncChangeId, auditId, replayed: false };
    });
    const item = objectType === 'calendar_event' ? this.eventVm(result.row) : this.taskVm(result.row);
    return {
      ok: true,
      canonical: true,
      item,
      serverVersion: result.row.serverVersion ?? 1,
      syncChangeId: result.syncChangeId,
      auditId: result.auditId,
      replayed: result.replayed,
    };
  }

  private async updateObject(
    id: string,
    payloadPatch: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
    mapper: (row: QueryResultRow) => Record<string, unknown>,
    baseServerVersion?: number,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.transaction(async (client) => {
      const before = await client.query(
        `
        SELECT payload, server_version AS "serverVersion"
        FROM sync_objects
        WHERE user_id = $1 AND id = $2 AND deleted_at IS NULL
        LIMIT 1
        `,
        [userId, id],
      );
      const beforeRow = before.rows[0];
      if (!beforeRow) {
        return null;
      }
      if (baseServerVersion != null && Number(beforeRow.serverVersion) !== baseServerVersion) {
        throw new ConflictException({
          ok: false,
          code: 'version_conflict',
          message: 'Object has changed on the server. Pull latest state before overwriting.',
          serverVersion: Number(beforeRow.serverVersion),
          baseServerVersion,
        });
      }
      const row = await client.query(
        `
        UPDATE sync_objects
        SET payload = payload || $3::jsonb,
            server_version = server_version + 1,
            last_modified_device_id = $4,
            updated_at = now()
        WHERE user_id = $1 AND id = $2 AND deleted_at IS NULL
        RETURNING id::text, object_type AS "objectType", uid, payload,
                  server_version AS "serverVersion", created_at AS "createdAt", updated_at AS "updatedAt"
        `,
        [userId, id, JSON.stringify(payloadPatch), deviceId],
      );
      const updated = row.rows[0];
      if (!updated) {
        return null;
      }
      const syncChangeId = await this.recordChange(client, userId, deviceId, updated, 'update');
      const auditId = await this.recordAudit(client, userId, deviceId, `web.${updated.objectType}.update`, {
        objectId: id,
        before: beforeRow.payload,
        after: updated.payload,
      });
      return { row: updated, syncChangeId, auditId };
    });
    return {
      ok: !!result,
      canonical: !!result,
      item: result ? mapper.call(this, result.row) : null,
      serverVersion: result?.row.serverVersion ?? null,
      syncChangeId: result?.syncChangeId ?? null,
      auditId: result?.auditId ?? null,
    };
  }

  private async deleteObject(
    id: string,
    expectedObjectType: string,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.transaction(async (client) => {
      const row = await client.query(
        `
        UPDATE sync_objects
        SET deleted_at = now(),
            server_version = server_version + 1,
            last_modified_device_id = $4,
            updated_at = now()
        WHERE user_id = $1
          AND id = $2
          AND deleted_at IS NULL
          AND object_type = $3
        RETURNING id::text, object_type AS "objectType", uid, payload,
                  server_version AS "serverVersion", created_at AS "createdAt", updated_at AS "updatedAt"
        `,
        [userId, id, expectedObjectType, deviceId],
      );
      const deleted = row.rows[0];
      if (!deleted) {
        return null;
      }
      const syncChangeId = await this.recordChange(client, userId, deviceId, deleted, 'delete');
      const auditId = await this.recordAudit(client, userId, deviceId, `web.${deleted.objectType}.delete`, {
        objectId: id,
        payload: deleted.payload,
      });
      return { row: deleted, syncChangeId, auditId };
    });
    return {
      ok: !!result,
      canonical: !!result,
      deleted: !!result,
      id,
      serverVersion: result?.row.serverVersion ?? null,
      syncChangeId: result?.syncChangeId ?? null,
      auditId: result?.auditId ?? null,
    };
  }

  private async recordChange(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    row: QueryResultRow,
    action: string,
  ): Promise<string | null> {
    const inserted = await client.query(
      `
      INSERT INTO sync_changes (
        user_id, device_id, server_object_id, object_type, action, server_version, payload
      ) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)
      RETURNING id::text AS id
      `,
      [
        userId,
        deviceId,
        row.id,
        row.objectType,
        action,
        row.serverVersion ?? 1,
        JSON.stringify(row.payload ?? {}),
      ],
    );
    return inserted.rows[0]?.id ?? null;
  }

  private async recordAudit(
    client: TransactionClient | DatabaseService,
    userId: string,
    deviceId: string,
    action: string,
    metadata: Record<string, unknown>,
  ): Promise<string | null> {
    const inserted = await client.query(
      `
      INSERT INTO audit_logs (
        user_id, device_id, actor, action, entity_type, entity_id, summary, metadata
      ) VALUES ($1, $2, 'web', $3, 'web', $4, $5, $6::jsonb)
      RETURNING id::text AS id
      `,
      [
        userId,
        deviceId,
        action,
        clean(metadata.objectId) ?? clean(metadata.operationKey),
        action,
        JSON.stringify(metadata),
      ],
    );
    return inserted.rows[0]?.id ?? null;
  }

  private taskVm(row: QueryResultRow) {
    const normalized = normalizeTaskPayload(asRecord(row.payload));
    return {
      id: row.id,
      uid: row.uid,
      objectType: row.objectType,
      title: normalized.title,
      status: normalized.status,
      dueAt: normalized.dueAt,
      location: normalized.location ?? '',
      syncStatus: 'server',
      serverVersion: row.serverVersion,
      updatedAt: row.updatedAt,
      payload: normalized as unknown as Record<string, unknown>,
    };
  }

  private eventVm(row: QueryResultRow) {
    const normalized = normalizeEventPayload(asRecord(row.payload));
    return {
      id: row.id,
      uid: row.uid,
      objectType: row.objectType,
      title: normalized.title,
      startAt: normalized.startAt,
      endAt: normalized.endAt,
      status: normalized.status,
      location: normalized.location ?? '',
      notes: normalized.notes ?? '',
      description: normalized.description ?? normalized.notes ?? '',
      isBlock: normalized.isBlock,
      syncStatus: 'server',
      serverVersion: row.serverVersion,
      updatedAt: row.updatedAt,
      payload: normalized as unknown as Record<string, unknown>,
    };
  }

  private numberValue(value: unknown) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : undefined;
  }

  private isTodayLike(value: unknown) {
    const text = clean(value);
    if (!text) {
      return false;
    }
    const parsed = new Date(text);
    if (Number.isNaN(parsed.getTime())) {
      return text.slice(0, 10) === this.localDateKey();
    }
    return this.localDateKey(parsed) === this.localDateKey();
  }

  private futureTime(value: unknown) {
    const text = clean(value);
    if (!text) {
      return null;
    }
    const time = Date.parse(text);
    if (!Number.isFinite(time) || time < Date.now()) {
      return null;
    }
    return time;
  }

  private currentEvent(items: Array<Record<string, unknown>>) {
    const now = Date.now();
    return items.find((item) => {
      const start = Date.parse(String(item.startAt ?? ''));
      const end = Date.parse(String(item.endAt ?? ''));
      return Number.isFinite(start) && Number.isFinite(end) && start <= now && now <= end;
    }) ?? null;
  }

  private localDateKey(date = new Date()) {
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }
}
