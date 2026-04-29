import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { FlowPlanRequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';

type SnapshotObject = {
  objectType: string;
  uid: string;
  localId: string;
  payload: Record<string, unknown>;
  deletedAt?: string | null;
  updatedAt?: string | null;
};

const SERVER_MANAGED_SETTING_SCOPES = [
  'user.preference',
  'sync.policy',
  'ai.provider',
  'file.provider',
  'report.push',
  'scheduler.policy',
  'activity.rules',
];

const DEVICE_LOCAL_SETTING_KEYS = [
  'server.api.base_url',
  'auth.access_token',
  'auth.refresh_token',
  'device.identity.id',
  'window.',
  'tray.',
  'startup.',
  'permission.',
  'sensor.',
  'download.',
  'cache.',
  'kopia.local.',
  'file.local.',
];

const TABLE_OBJECT_TYPES: Record<string, string> = {
  task_items: 'task_item',
  task_lists: 'task_list',
  calendar_events: 'calendar_event',
  event_calendars: 'event_calendar',
  task_schedule_segments: 'task_schedule_segment',
  actual_activity_logs: 'actual_activity_log',
  activity_records: 'activity_record',
  raw_activity_logs: 'raw_activity_log',
  tracked_input_events: 'tracked_input_event',
  file_folders: 'file_folder',
  file_items: 'file_item',
  file_nodes: 'file_node',
  file_context_links: 'file_context_link',
  report_documents: 'report_document',
  diary_entries: 'diary_entry',
  ai_conversations: 'ai_conversation',
};

@Injectable()
export class ClientService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
  ) {}

  async bootstrap(context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.touchDevice(userId, deviceId);

    const [user, device, settingsSummary, syncSummary, pendingActions] =
      await Promise.all([
        this.database.query(
          'SELECT id::text AS id, display_name AS "displayName", updated_at AS "updatedAt" FROM users WHERE id = $1',
          [userId],
        ),
        this.database.query(
          `SELECT id::text AS id, device_name AS "deviceName", platform, client_device_id AS "clientDeviceId", last_seen_at AS "lastSeenAt"
           FROM devices WHERE user_id = $1 AND id = $2 LIMIT 1`,
          [userId, deviceId],
        ),
        this.settingsSummary(userId),
        this.syncSummary(userId, deviceId),
        this.pendingActions(userId),
      ]);

    return {
      user: user.rows[0] ?? { id: userId, displayName: 'FlowPlan User' },
      device: device.rows[0] ?? { id: deviceId },
      serverTime: new Date().toISOString(),
      settingsVersion: settingsSummary.version,
      settingsUpdatedAt: settingsSummary.updatedAt,
      syncCursor: syncSummary.pullCursor,
      featureFlags: {
        serverFirstData: true,
        remoteSettings: true,
        initialImport: true,
        adminConsole: true,
      },
      serverHealth: {
        ok: true,
        database: 'ok',
        syncBacklog: syncSummary.backlog,
        failedMutations: pendingActions.failedMutations,
        openConflicts: pendingActions.openConflicts,
      },
      pendingActions,
    };
  }

  async settings(context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query(
      `
      SELECT
        config_key AS "key",
        scope,
        CASE WHEN is_sensitive THEN '{"masked":true}'::jsonb ELSE config_value END AS value,
        is_sensitive AS "isSensitive",
        version,
        description,
        updated_at AS "updatedAt"
      FROM admin_remote_configs
      WHERE user_id = $1
      ORDER BY scope ASC, config_key ASC
      `,
      [userId],
    );
    const summary = await this.settingsSummary(userId);
    return {
      version: summary.version,
      updatedAt: summary.updatedAt,
      settings: result.rows,
      policy: this.settingsPolicy(),
    };
  }

  async updateSetting(
    key: string,
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const value = this.asRecord(body.value ?? body.configValue);
    const scope = this.readScope(body.scope);
    const isSensitive = Boolean(body.isSensitive);
    const description = this.clean(body.description);

    const result = await this.database.transaction(async (client) => {
      const upserted = await client.query(
        `
        INSERT INTO admin_remote_configs (
          user_id,
          config_key,
          config_value,
          scope,
          is_sensitive,
          description,
          updated_by,
          version
        ) VALUES ($1, $2, $3::jsonb, $4, $5, $6, 'client', 1)
        ON CONFLICT (user_id, config_key) DO UPDATE SET
          config_value = EXCLUDED.config_value,
          scope = EXCLUDED.scope,
          is_sensitive = EXCLUDED.is_sensitive,
          description = COALESCE(EXCLUDED.description, admin_remote_configs.description),
          updated_by = 'client',
          version = admin_remote_configs.version + 1,
          updated_at = now()
        RETURNING config_key AS "key", scope, is_sensitive AS "isSensitive", version, updated_at AS "updatedAt"
        `,
        [
          userId,
          key,
          JSON.stringify(value),
          scope,
          isSensitive,
          description,
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'client.remote_setting.update', {
        key,
        scope,
        isSensitive,
      });
      return upserted.rows[0];
    });

    return { ok: true, setting: result };
  }

  settingsPolicy() {
    return {
      serverManagedScopes: SERVER_MANAGED_SETTING_SCOPES,
      deviceLocalKeyPrefixes: DEVICE_LOCAL_SETTING_KEYS,
      note:
        '设备级设置留在本机；工作时间、同步策略、AI、报告、文件 Provider、排程和活动规则由服务端管理。',
    };
  }

  async createLocalSnapshotImport(
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const snapshot = this.asRecord(body.snapshot ?? body);
    const objects = this.extractSnapshotObjects(snapshot);
    const conflicts = await this.detectImportConflicts(userId, objects);
    const settings = this.extractSettings(snapshot);
    const summary = {
      objectCount: objects.length,
      settingCount: settings.length,
      conflictCount: conflicts.length,
      conflicts,
      tables: this.snapshotTableCounts(snapshot),
    };

    const session = await this.database.transaction(async (client) => {
      const inserted = await client.query(
        `
        INSERT INTO client_import_sessions (
          user_id,
          device_id,
          import_uid,
          status,
          summary,
          snapshot
        ) VALUES ($1, $2, $3, 'needs_confirmation', $4::jsonb, $5::jsonb)
        RETURNING id::text AS id, status, summary, created_at AS "createdAt"
        `,
        [
          userId,
          deviceId,
          this.clean(body.importUid) ?? randomUUID(),
          JSON.stringify(summary),
          JSON.stringify(snapshot),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'client.import.prepare', {
        objectCount: objects.length,
        settingCount: settings.length,
        conflictCount: conflicts.length,
      });
      return inserted.rows[0];
    });

    return {
      importId: session.id,
      status: session.status,
      summary,
      requiresConfirmation: true,
    };
  }

  async importStatus(importId: string, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query(
      `
      SELECT
        id::text AS id,
        status,
        summary,
        result,
        error_message AS "errorMessage",
        created_at AS "createdAt",
        updated_at AS "updatedAt",
        confirmed_at AS "confirmedAt",
        cancelled_at AS "cancelledAt"
      FROM client_import_sessions
      WHERE user_id = $1 AND id = $2
      LIMIT 1
      `,
      [userId, importId],
    );
    return result.rows[0] ?? { id: importId, status: 'not_found' };
  }

  async confirmImport(importId: string, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);

    const result = await this.database.transaction(async (client) => {
      const session = await client.query<{
        snapshot: Record<string, unknown>;
        status: string;
      }>(
        `
        SELECT snapshot, status
        FROM client_import_sessions
        WHERE user_id = $1 AND id = $2
        FOR UPDATE
        `,
        [userId, importId],
      );
      const row = session.rows[0];
      if (!row) {
        return { ok: false, status: 'not_found' };
      }
      if (row.status === 'completed') {
        return { ok: true, status: 'completed', alreadyCompleted: true };
      }
      if (row.status === 'cancelled') {
        return { ok: false, status: 'cancelled' };
      }

      await client.query(
        `UPDATE client_import_sessions SET status = 'importing', updated_at = now() WHERE user_id = $1 AND id = $2`,
        [userId, importId],
      );

      const objects = this.extractSnapshotObjects(row.snapshot);
      const settings = this.extractSettings(row.snapshot);
      let inserted = 0;
      let updated = 0;
      let skipped = 0;

      for (const object of objects) {
        const imported = await this.importObject(client, userId, deviceId, object);
        if (imported === 'inserted') {
          inserted += 1;
        } else if (imported === 'updated') {
          updated += 1;
        } else {
          skipped += 1;
        }
      }

      for (const setting of settings) {
        await this.importSetting(client, userId, setting);
      }

      const importResult = {
        inserted,
        updated,
        skipped,
        importedSettings: settings.length,
        completedAt: new Date().toISOString(),
      };
      await client.query(
        `
        UPDATE client_import_sessions
        SET status = 'completed',
            result = $3::jsonb,
            updated_at = now(),
            confirmed_at = now()
        WHERE user_id = $1 AND id = $2
        `,
        [userId, importId, JSON.stringify(importResult)],
      );
      await this.recordAudit(client, userId, deviceId, 'client.import.confirm', {
        importId,
        ...importResult,
      });
      return { ok: true, status: 'completed', result: importResult };
    });

    return result;
  }

  async cancelImport(
    importId: string,
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.database.transaction(async (client) => {
      await client.query(
        `
        UPDATE client_import_sessions
        SET status = 'cancelled',
            error_message = $3,
            updated_at = now(),
            cancelled_at = now()
        WHERE user_id = $1 AND id = $2 AND status <> 'completed'
        `,
        [userId, importId, this.clean(body.reason)],
      );
      await this.recordAudit(client, userId, deviceId, 'client.import.cancel', {
        importId,
        reason: this.clean(body.reason),
      });
    });
    return { ok: true, status: 'cancelled' };
  }

  private async touchDevice(userId: string, deviceId: string) {
    await this.database.query(
      `UPDATE devices SET last_seen_at = now(), updated_at = now() WHERE user_id = $1 AND id = $2`,
      [userId, deviceId],
    );
  }

  private async settingsSummary(userId: string) {
    const result = await this.database.query<{
      version: string | number | null;
      updatedAt: Date | string | null;
    }>(
      `
      SELECT
        COALESCE(MAX(version), 0) AS version,
        MAX(updated_at) AS "updatedAt"
      FROM admin_remote_configs
      WHERE user_id = $1
      `,
      [userId],
    );
    const row = result.rows[0];
    return {
      version: Number(row?.version ?? 0),
      updatedAt: row?.updatedAt ?? null,
    };
  }

  private async syncSummary(userId: string, deviceId: string) {
    const result = await this.database.query<{
      pullCursor: string | number | null;
      latestChangeId: string | number | null;
      backlog: string | number | null;
    }>(
      `
      SELECT
        COALESCE(c.cursor_value, 0) AS "pullCursor",
        COALESCE((SELECT MAX(id) FROM sync_changes WHERE user_id = $1), 0) AS "latestChangeId",
        GREATEST(
          COALESCE((SELECT MAX(id) FROM sync_changes WHERE user_id = $1), 0) - COALESCE(c.cursor_value, 0),
          0
        ) AS backlog
      FROM devices d
      LEFT JOIN sync_cursors c ON c.user_id = d.user_id AND c.device_id = d.id
      WHERE d.user_id = $1 AND d.id = $2
      LIMIT 1
      `,
      [userId, deviceId],
    );
    const row = result.rows[0] ?? {};
    return {
      pullCursor: String(row.pullCursor ?? '0'),
      latestChangeId: String(row.latestChangeId ?? '0'),
      backlog: Number(row.backlog ?? 0),
    };
  }

  private async pendingActions(userId: string) {
    const result = await this.database.query<{
      open_conflicts: string | number;
      failed_mutations: string | number;
      pending_ai_drafts: string | number;
      failed_pushes: string | number;
    }>(
      `
      SELECT
        (SELECT COUNT(*) FROM sync_conflicts WHERE user_id = $1 AND status = 'open') AS open_conflicts,
        (SELECT COUNT(*) FROM sync_mutations WHERE user_id = $1 AND result = 'rejected') AS failed_mutations,
        (SELECT COUNT(*) FROM ai_operation_drafts WHERE user_id = $1 AND status = 'pending_review') AS pending_ai_drafts,
        (SELECT COUNT(*) FROM report_push_deliveries WHERE user_id = $1 AND status = 'failed') AS failed_pushes
      `,
      [userId],
    );
    const row = result.rows[0];
    return {
      openConflicts: Number(row?.open_conflicts ?? 0),
      failedMutations: Number(row?.failed_mutations ?? 0),
      pendingAiDrafts: Number(row?.pending_ai_drafts ?? 0),
      failedPushes: Number(row?.failed_pushes ?? 0),
    };
  }

  private async detectImportConflicts(userId: string, objects: SnapshotObject[]) {
    const conflicts = [];
    for (const object of objects) {
      const existing = await this.database.query(
        `
        SELECT id::text AS id, server_version AS "serverVersion", updated_at AS "updatedAt"
        FROM sync_objects
        WHERE user_id = $1 AND object_type = $2 AND uid = $3 AND deleted_at IS NULL
        LIMIT 1
        `,
        [userId, object.objectType, object.uid],
      );
      if (existing.rows[0]) {
        conflicts.push({
          objectType: object.objectType,
          uid: object.uid,
          localId: object.localId,
          server: existing.rows[0],
        });
      }
    }
    return conflicts.slice(0, 200);
  }

  private async importObject(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    object: SnapshotObject,
  ): Promise<'inserted' | 'updated' | 'skipped'> {
    const existing = await client.query<{ id: string; server_version: number }>(
      `
      SELECT id::text, server_version
      FROM sync_objects
      WHERE user_id = $1 AND object_type = $2 AND uid = $3 AND deleted_at IS NULL
      LIMIT 1
      `,
      [userId, object.objectType, object.uid],
    );
    if (existing.rows[0]) {
      const updated = await client.query<{
        id: string;
        server_version: number;
        payload: Record<string, unknown>;
      }>(
        `
        UPDATE sync_objects
        SET payload = payload || $4::jsonb,
            server_version = server_version + 1,
            last_modified_device_id = $5,
            updated_at = now()
        WHERE user_id = $1 AND object_type = $2 AND uid = $3 AND deleted_at IS NULL
        RETURNING id::text, server_version, payload
        `,
        [
          userId,
          object.objectType,
          object.uid,
          JSON.stringify(object.payload),
          deviceId,
        ],
      );
      const row = updated.rows[0];
      if (row) {
        await this.recordChange(
          client,
          userId,
          deviceId,
          row.id,
          object.objectType,
          'upsert',
          row.server_version,
          row.payload,
        );
        return 'updated';
      }
      return 'skipped';
    }

    const inserted = await client.query<{
      id: string;
      server_version: number;
      payload: Record<string, unknown>;
    }>(
      `
      INSERT INTO sync_objects (
        user_id,
        object_type,
        uid,
        payload,
        deleted_at,
        origin_device_id,
        last_modified_device_id
      ) VALUES ($1, $2, $3, $4::jsonb, $5, $6, $6)
      RETURNING id::text, server_version, payload
      `,
      [
        userId,
        object.objectType,
        object.uid,
        JSON.stringify(object.payload),
        object.deletedAt ?? null,
        deviceId,
      ],
    );
    const row = inserted.rows[0];
    if (row) {
      await this.recordChange(
        client,
        userId,
        deviceId,
        row.id,
        object.objectType,
        object.deletedAt ? 'delete' : 'upsert',
        row.server_version,
        row.payload,
      );
      return 'inserted';
    }
    return 'skipped';
  }

  private importSetting(
    client: TransactionClient,
    userId: string,
    setting: { key: string; value: unknown },
  ) {
    if (this.isDeviceLocalSetting(setting.key)) {
      return Promise.resolve();
    }
    return client.query(
      `
      INSERT INTO admin_remote_configs (
        user_id,
        config_key,
        config_value,
        scope,
        updated_by,
        version
      ) VALUES ($1, $2, $3::jsonb, 'user.preference', 'client-import', 1)
      ON CONFLICT (user_id, config_key) DO UPDATE SET
        config_value = EXCLUDED.config_value,
        version = admin_remote_configs.version + 1,
        updated_by = 'client-import',
        updated_at = now()
      `,
      [userId, setting.key, JSON.stringify({ value: setting.value })],
    );
  }

  private extractSnapshotObjects(snapshot: Record<string, unknown>) {
    const objects: SnapshotObject[] = [];
    const rawObjects = snapshot.objects;
    if (Array.isArray(rawObjects)) {
      for (const item of rawObjects) {
        const normalized = this.normalizeObject(item);
        if (normalized) {
          objects.push(normalized);
        }
      }
      return objects;
    }
    if (this.isRecord(rawObjects)) {
      for (const [tableName, value] of Object.entries(rawObjects)) {
        if (!Array.isArray(value)) {
          continue;
        }
        const objectType = TABLE_OBJECT_TYPES[tableName] ?? tableName;
        for (const row of value) {
          const normalized = this.normalizeObject(row, objectType);
          if (normalized) {
            objects.push(normalized);
          }
        }
      }
    }
    return objects;
  }

  private normalizeObject(value: unknown, fallbackType?: string): SnapshotObject | null {
    if (!this.isRecord(value)) {
      return null;
    }
    const objectType =
      this.clean(value.objectType) ??
      this.clean(value.object_type) ??
      fallbackType ??
      'unknown';
    const uid =
      this.clean(value.uid) ??
      this.clean(value.task_uid) ??
      this.clean(value.event_uid) ??
      this.clean(value.segment_uid) ??
      this.clean(value.actual_uid) ??
      this.clean(value.folder_uid) ??
      this.clean(value.file_uid) ??
      this.clean(value.node_uid) ??
      this.clean(value.report_uid) ??
      this.clean(value.diary_uid) ??
      this.clean(value.link_uid) ??
      (value.id == null ? undefined : `${objectType}:${String(value.id)}`);
    if (!uid || objectType === 'unknown') {
      return null;
    }
    return {
      objectType,
      uid,
      localId: value.id == null ? uid : String(value.id),
      payload: { ...value, uid },
      deletedAt: this.clean(value.deleted_at) ?? this.clean(value.deletedAt),
      updatedAt: this.clean(value.updated_at) ?? this.clean(value.updatedAt),
    };
  }

  private extractSettings(snapshot: Record<string, unknown>) {
    const settings = snapshot.settings;
    if (!Array.isArray(settings)) {
      return [];
    }
    return settings
      .filter(this.isRecord)
      .map((setting) => ({
        key: String(setting.key ?? setting.setting_key ?? ''),
        value: setting.value ?? setting.setting_value ?? null,
      }))
      .filter((setting) => setting.key.trim().length > 0);
  }

  private snapshotTableCounts(snapshot: Record<string, unknown>) {
    if (!this.isRecord(snapshot.objects)) {
      return {};
    }
    return Object.fromEntries(
      Object.entries(snapshot.objects).map(([key, value]) => [
        key,
        Array.isArray(value) ? value.length : 0,
      ]),
    );
  }

  private recordChange(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    serverObjectId: string,
    objectType: string,
    action: 'upsert' | 'delete',
    serverVersion: number,
    payload: Record<string, unknown>,
  ) {
    return client.query(
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
      [
        userId,
        deviceId,
        serverObjectId,
        objectType,
        action,
        serverVersion,
        JSON.stringify(payload ?? {}),
      ],
    );
  }

  private recordAudit(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    action: string,
    metadata: Record<string, unknown>,
  ) {
    return client.query(
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
      ) VALUES ($1, $2, 'client', $3, 'client', $4, $3, $5::jsonb)
      `,
      [
        userId,
        deviceId,
        action,
        this.clean(metadata.importId) ?? this.clean(metadata.key),
        JSON.stringify(metadata),
      ],
    );
  }

  private readScope(value: unknown) {
    const scope = this.clean(value);
    return scope && SERVER_MANAGED_SETTING_SCOPES.includes(scope)
      ? scope
      : 'user.preference';
  }

  private isDeviceLocalSetting(key: string) {
    return DEVICE_LOCAL_SETTING_KEYS.some((prefix) => key.startsWith(prefix));
  }

  private asRecord(value: unknown): Record<string, unknown> {
    return this.isRecord(value) ? value : {};
  }

  private isRecord(value: unknown): value is Record<string, unknown> {
    return !!value && typeof value === 'object' && !Array.isArray(value);
  }

  private clean(value: unknown) {
    return typeof value === 'string' && value.trim().length > 0
      ? value.trim()
      : undefined;
  }
}
