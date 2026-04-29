import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { QueryResultRow } from 'pg';
import { FlowPlanRequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';

const TASK_TYPES = ['task', 'task_item', 'task_items'];
const EVENT_TYPES = ['event', 'calendar_event', 'calendar_events'];

@Injectable()
export class WebService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
  ) {}

  async dashboard(context: FlowPlanRequestContext) {
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
      .filter((item) => this.futureTime(item.startAt ?? item.dueAt) !== null)
      .sort((a, b) => (this.futureTime(a.startAt ?? a.dueAt) ?? 0) - (this.futureTime(b.startAt ?? b.dueAt) ?? 0));
    return {
      ok: true,
      mode: 'user_web_client',
      generatedAt: new Date().toISOString(),
      profile: {
        userId,
        deviceId,
        note: 'Flutter Web 是 FlowPlan 日常使用端；全局数据、审计和运维操作请使用 web_admin。',
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

  async tasks(query: Record<string, unknown>, context: FlowPlanRequestContext) {
    return this.listObjects(query, context, TASK_TYPES, (row) => this.taskVm(row));
  }

  async events(query: Record<string, unknown>, context: FlowPlanRequestContext) {
    return this.listObjects(query, context, EVENT_TYPES, (row) => this.eventVm(row));
  }

  async createTask(body: Record<string, unknown>, context: FlowPlanRequestContext) {
    return this.createObject('task_item', this.normalizeTaskPayload(body), context);
  }

  async updateTask(id: string, body: Record<string, unknown>, context: FlowPlanRequestContext) {
    return this.updateObject(id, this.normalizeTaskPayload(body), context, this.taskVm);
  }

  async createEvent(body: Record<string, unknown>, context: FlowPlanRequestContext) {
    return this.createObject('calendar_event', this.normalizeEventPayload(body), context);
  }

  async updateEvent(id: string, body: Record<string, unknown>, context: FlowPlanRequestContext) {
    return this.updateObject(id, this.normalizeEventPayload(body), context, this.eventVm);
  }

  async actualRecords(query: Record<string, unknown>, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = this.readLimit(query.limit);
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
      ORDER BY start_at DESC
      LIMIT $2
      `,
      [userId, limit],
    );
    return { items: result.rows };
  }

  async reminders(context: FlowPlanRequestContext) {
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
      EVENT_TYPES.includes(String(row.objectType)) ? this.eventVm(row) : this.taskVm(row),
    ) as Array<Record<string, unknown>>;
    return {
      items: items.filter((item) => item.dueAt || item.startAt),
    };
  }

  async prepareOperation(
    operationKey: string,
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
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
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.recordAudit(this.database, userId, deviceId, `web.operation.${operationKey}.confirm`, {
      operationKey,
      confirmationToken: this.clean(body.confirmationToken),
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
    context: FlowPlanRequestContext,
    objectTypes: string[],
    mapper: (row: QueryResultRow) => Record<string, unknown>,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = this.readLimit(query.limit);
    const q = this.search(query.q);
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
        )
      ORDER BY updated_at DESC
      LIMIT $4
      `,
      [userId, objectTypes, q, limit],
    );
    return {
      limit,
      items: result.rows.map(mapper),
    };
  }

  private async createObject(
    objectType: string,
    payload: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const uid = this.clean(payload.uid) ?? `${objectType}:${randomUUID()}`;
    const result = await this.database.transaction(async (client) => {
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
      await this.recordChange(client, userId, deviceId, row.rows[0], 'create');
      await this.recordAudit(client, userId, deviceId, `web.${objectType}.create`, {
        objectId: row.rows[0]?.id,
        uid,
        payload,
      });
      return row.rows[0];
    });
    return { ok: true, item: objectType === 'calendar_event' ? this.eventVm(result) : this.taskVm(result) };
  }

  private async updateObject(
    id: string,
    payloadPatch: Record<string, unknown>,
    context: FlowPlanRequestContext,
    mapper: (row: QueryResultRow) => Record<string, unknown>,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.transaction(async (client) => {
      const before = await client.query(
        `SELECT payload FROM sync_objects WHERE user_id = $1 AND id = $2 LIMIT 1`,
        [userId, id],
      );
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
      await this.recordChange(client, userId, deviceId, updated, 'update');
      await this.recordAudit(client, userId, deviceId, `web.${updated.objectType}.update`, {
        objectId: id,
        before: before.rows[0]?.payload,
        after: updated.payload,
      });
      return updated;
    });
    return { ok: !!result, item: result ? mapper.call(this, result) : null };
  }

  private async recordChange(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    row: QueryResultRow,
    action: string,
  ) {
    await client.query(
      `
      INSERT INTO sync_changes (
        user_id, device_id, server_object_id, object_type, action, server_version, payload
      ) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)
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
  }

  private async recordAudit(
    client: TransactionClient | DatabaseService,
    userId: string,
    deviceId: string,
    action: string,
    metadata: Record<string, unknown>,
  ) {
    await client.query(
      `
      INSERT INTO audit_logs (
        user_id, device_id, actor, action, entity_type, entity_id, summary, metadata
      ) VALUES ($1, $2, 'web', $3, 'web', $4, $5, $6::jsonb)
      `,
      [
        userId,
        deviceId,
        action,
        this.clean(metadata.objectId) ?? this.clean(metadata.operationKey),
        action,
        JSON.stringify(metadata),
      ],
    );
  }

  private taskVm(row: QueryResultRow) {
    const payload = this.asRecord(row.payload);
    return {
      id: row.id,
      uid: row.uid,
      objectType: row.objectType,
      title: this.clean(payload.title) ?? this.clean(payload.summary) ?? this.clean(payload.name) ?? '未命名任务',
      status: this.clean(payload.status) ?? 'todo',
      dueAt: this.clean(payload.dueAt) ?? this.clean(payload.due_date) ?? this.clean(payload.dueDate),
      location: this.clean(payload.location) ?? '',
      syncStatus: 'server',
      serverVersion: row.serverVersion,
      updatedAt: row.updatedAt,
      payload,
    };
  }

  private eventVm(row: QueryResultRow) {
    const payload = this.asRecord(row.payload);
    return {
      id: row.id,
      uid: row.uid,
      objectType: row.objectType,
      title: this.clean(payload.title) ?? this.clean(payload.summary) ?? this.clean(payload.name) ?? '未命名日程',
      startAt: this.clean(payload.startAt) ?? this.clean(payload.start_at) ?? this.clean(payload.startTime),
      endAt: this.clean(payload.endAt) ?? this.clean(payload.end_at) ?? this.clean(payload.endTime),
      status: this.clean(payload.status) ?? 'confirmed',
      location: this.clean(payload.location) ?? '',
      syncStatus: 'server',
      serverVersion: row.serverVersion,
      updatedAt: row.updatedAt,
      payload,
    };
  }

  private normalizeTaskPayload(body: Record<string, unknown>) {
    return this.cleanRecord({
      title: this.clean(body.title) ?? this.clean(body.summary) ?? '未命名任务',
      status: this.clean(body.status) ?? 'todo',
      dueAt: this.clean(body.dueAt),
      location: this.clean(body.location),
      notes: this.clean(body.notes),
      updatedFrom: 'web',
      ...this.asRecord(body.payload),
    });
  }

  private normalizeEventPayload(body: Record<string, unknown>) {
    return this.cleanRecord({
      title: this.clean(body.title) ?? this.clean(body.summary) ?? '未命名日程',
      startAt: this.clean(body.startAt),
      endAt: this.clean(body.endAt),
      status: this.clean(body.status) ?? 'confirmed',
      location: this.clean(body.location),
      notes: this.clean(body.notes),
      updatedFrom: 'web',
      ...this.asRecord(body.payload),
    });
  }

  private cleanRecord(value: Record<string, unknown>) {
    return Object.fromEntries(
      Object.entries(value).filter(([, entry]) => entry !== undefined && entry !== null && entry !== ''),
    );
  }

  private asRecord(value: unknown): Record<string, unknown> {
    return value && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  }

  private clean(value: unknown) {
    return typeof value === 'string' && value.trim().length > 0 ? value.trim() : undefined;
  }

  private search(value: unknown) {
    const text = this.clean(value);
    return text ? `%${text}%` : null;
  }

  private readLimit(value: unknown) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed) || parsed <= 0) {
      return 100;
    }
    return Math.min(Math.floor(parsed), 500);
  }

  private isTodayLike(value: unknown) {
    const text = this.clean(value);
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
    const text = this.clean(value);
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
