import { Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { FlowPlanV2RequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import {
  ResolveConflictDto,
  SyncAckDto,
  SyncChangeDto,
  SyncConflictDto,
  SyncMutationDto,
  SyncPullResponseDto,
  SyncPushDto,
  SyncPushResponseDto,
} from './dto';

type SyncObjectRow = {
  id: string;
  uid: string | null;
  payload: Record<string, unknown>;
  deleted_at: Date | string | null;
  server_version: number;
};

@Injectable()
export class SyncService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
  ) {}

  async push(
    dto: SyncPushDto,
    context: FlowPlanV2RequestContext,
  ): Promise<SyncPushResponseDto> {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const accepted: SyncPushResponseDto['accepted'] = [];
    const conflicts: SyncConflictDto[] = [];
    const rejected: SyncPushResponseDto['rejected'] = [];

    await this.database.transaction(async (client) => {
      for (const mutation of dto.mutations ?? []) {
        const replay = await this.findProcessedMutation(client, mutation.mutationUid);
        if (replay) {
          if (replay.result === 'accepted' && replay.server_object_id) {
            accepted.push({
              mutationUid: mutation.mutationUid,
              objectType: mutation.objectType,
              localId: mutation.localId,
              serverId: replay.server_object_id,
              serverVersion: replay.server_version ?? 1,
            });
          } else if (replay.result === 'conflict') {
            const existingConflict = await this.findConflictForMutation(
              client,
              mutation.mutationUid,
            );
            if (existingConflict) {
              conflicts.push(existingConflict);
            }
          } else {
            rejected.push({
              mutationUid: mutation.mutationUid,
              objectType: mutation.objectType,
              localId: mutation.localId,
              reason: replay.error_message ?? 'Previously rejected mutation',
            });
          }
          continue;
        }

        try {
          const result = await this.applyMutation(
            client,
            userId,
            deviceId,
            mutation,
          );
          if (result.kind === 'accepted') {
            accepted.push(result.accepted);
          } else if (result.kind === 'conflict') {
            conflicts.push(result.conflict);
          } else {
            rejected.push(result.rejected);
          }
        } catch (error) {
          const reason = error instanceof Error ? error.message : String(error);
          await this.recordMutation(client, {
            mutation,
            userId,
            deviceId,
            result: 'rejected',
            errorMessage: reason,
          });
          rejected.push({
            mutationUid: mutation.mutationUid,
            objectType: mutation.objectType,
            localId: mutation.localId,
            reason,
          });
        }
      }
    });

    return {
      serverBatchId: randomUUID(),
      accepted,
      conflicts,
      rejected,
    };
  }

  async pull(
    cursor: string | undefined,
    context: FlowPlanV2RequestContext,
    options: { objectType?: string; limit?: string } = {},
  ): Promise<SyncPullResponseDto> {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const cursorValue = this.parseCursor(cursor);
    const objectType = this.clean(options.objectType);
    const limit = this.readLimit(options.limit);

    const result = await this.database.query<{
      id: string;
      object_type: string;
      server_object_id: string;
      uid: string | null;
      action: 'upsert' | 'delete';
      server_version: number;
      created_at: Date;
      payload: Record<string, unknown>;
    }>(
      `
      SELECT
        c.id::text,
        c.object_type,
        c.server_object_id::text,
        o.uid,
        CASE WHEN c.action = 'delete' THEN 'delete' ELSE 'upsert' END AS action,
        c.server_version,
        c.created_at,
        c.payload
      FROM sync_changes c
      INNER JOIN sync_objects o ON o.id = c.server_object_id
      WHERE c.user_id = $1
        AND c.id > $2
        AND (c.device_id IS NULL OR c.device_id <> $3)
        AND ($4::text IS NULL OR c.object_type = $4)
      ORDER BY c.id ASC
      LIMIT $5
      `,
      [userId, cursorValue, deviceId, objectType, limit],
    );

    const changes: SyncChangeDto[] = result.rows.map((row) => ({
      changeId: row.id,
      objectType: row.object_type,
      serverId: row.server_object_id,
      uid: row.uid,
      action: row.action,
      serverVersion: row.server_version,
      updatedAt: row.created_at.toISOString(),
      payload: row.payload ?? {},
    }));

    const nextCursor =
      changes.length > 0 ? changes[changes.length - 1].changeId : String(cursorValue);

    return {
      nextCursor,
      serverTime: new Date().toISOString(),
      changes,
    };
  }

  async ack(dto: SyncAckDto, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const cursor = this.parseCursor(dto.cursor);

    await this.database.query(
      `
      INSERT INTO sync_cursors (user_id, device_id, cursor_value)
      VALUES ($1, $2, $3)
      ON CONFLICT (user_id, device_id) DO UPDATE SET
        cursor_value = GREATEST(sync_cursors.cursor_value, EXCLUDED.cursor_value),
        updated_at = now()
      `,
      [userId, deviceId, cursor],
    );

    return {
      ok: true,
      cursor: String(cursor),
      appliedChangeIds: dto.appliedChangeIds ?? [],
    };
  }

  async conflicts(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query<{
      conflict_id: string;
      mutation_uid: string | null;
      object_type: string;
      local_id: string | null;
      server_id: string | null;
      base_version: number | null;
      local_version: number;
      server_version: number;
      fields: SyncConflictDto['fields'];
    }>(
      `
      SELECT
        c.id::text AS conflict_id,
        c.mutation_uid,
        c.object_type,
        c.local_id,
        c.server_object_id::text AS server_id,
        c.base_version,
        c.local_version,
        c.server_version,
        c.fields
      FROM sync_conflicts c
      WHERE c.user_id = $1 AND c.status = 'open'
      ORDER BY c.created_at DESC
      LIMIT 100
      `,
      [userId],
    );
    return {
      conflicts: result.rows.map((row) => this.conflictFromRow(row)),
    };
  }

  async status(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query(
      `
      SELECT
        d.id::text AS "deviceId",
        d.device_name AS "deviceName",
        d.platform,
        d.client_device_id AS "clientDeviceId",
        d.last_seen_at AS "lastSeenAt",
        COALESCE(c.cursor_value, 0)::text AS "pullCursor",
        c.updated_at AS "cursorUpdatedAt"
      FROM devices d
      LEFT JOIN sync_cursors c
        ON c.user_id = d.user_id AND c.device_id = d.id
      WHERE d.user_id = $1
      ORDER BY d.last_seen_at DESC NULLS LAST, d.created_at DESC
      `,
      [userId],
    );
    return {
      devices: result.rows,
    };
  }

  async resolveConflict(
    conflictId: string,
    dto: ResolveConflictDto,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);

    await this.database.transaction(async (client) => {
      const conflict = await client.query<{
        server_object_id: string;
        object_type: string;
        server_version: number;
        fields: SyncConflictDto['fields'];
      }>(
        `
        SELECT server_object_id::text, object_type, server_version, fields
        FROM sync_conflicts
        WHERE id = $1 AND user_id = $2 AND status = 'open'
        LIMIT 1
        `,
        [conflictId, userId],
      );
      const row = conflict.rows[0];
      if (!row) {
        return;
      }

      if (dto.strategy === 'use_local' || dto.strategy === 'merge') {
        const payload = dto.payload ?? {};
        const updated = await client.query<SyncObjectRow>(
          `
          UPDATE sync_objects
          SET
            payload = payload || $3::jsonb,
            server_version = server_version + 1,
            last_modified_device_id = $4,
            updated_at = now()
          WHERE id = $1 AND user_id = $2
          RETURNING id::text, uid, payload, deleted_at, server_version
          `,
          [row.server_object_id, userId, JSON.stringify(payload), deviceId],
        );
        const object = updated.rows[0];
        if (object) {
          await this.recordChange(
            client,
            userId,
            deviceId,
            object.id,
            row.object_type,
            'upsert',
            object.server_version,
            object.payload,
          );
        }
      }

      await client.query(
        `
        UPDATE sync_conflicts
        SET status = 'resolved',
            resolution = $3::jsonb,
            resolved_at = now()
        WHERE id = $1 AND user_id = $2
        `,
        [conflictId, userId, JSON.stringify(dto)],
      );
      await this.recordAudit(client, userId, deviceId, 'sync.conflict.resolve', {
        conflictId,
        objectType: row.object_type,
        serverObjectId: row.server_object_id,
        strategy: dto.strategy,
        note: dto.note ?? null,
        fields: row.fields ?? [],
        payloadKeys: Object.keys(dto.payload ?? {}),
      });
    });

    return {
      ok: true,
      conflictId,
      strategy: dto.strategy,
    };
  }

  private async applyMutation(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    mutation: SyncMutationDto,
  ): Promise<
    | { kind: 'accepted'; accepted: SyncPushResponseDto['accepted'][number] }
    | { kind: 'conflict'; conflict: SyncConflictDto }
    | { kind: 'rejected'; rejected: SyncPushResponseDto['rejected'][number] }
  > {
    if (!mutation.mutationUid || !mutation.objectType || !mutation.localId) {
      return {
        kind: 'rejected',
        rejected: {
          mutationUid: mutation.mutationUid ?? randomUUID(),
          objectType: mutation.objectType ?? 'unknown',
          localId: mutation.localId ?? 'unknown',
          reason: 'mutationUid, objectType and localId are required',
        },
      };
    }

    const existing = await this.findTargetObject(client, userId, mutation);
    if (this.isOutlookReadOnlyMutation(mutation, existing)) {
      const reason =
        'Outlook synced calendar objects are read-only and must be refreshed from the server.';
      await this.recordMutation(client, {
        mutation,
        userId,
        deviceId,
        serverObjectId: existing?.id,
        serverVersion: existing?.server_version,
        result: 'rejected',
        errorMessage: reason,
      });
      return {
        kind: 'rejected',
        rejected: {
          mutationUid: mutation.mutationUid,
          objectType: mutation.objectType,
          localId: mutation.localId,
          reason,
        },
      };
    }
    if (
      existing &&
      mutation.baseServerVersion != null &&
      existing.server_version !== mutation.baseServerVersion
    ) {
      const conflict = await this.createConflict(
        client,
        userId,
        deviceId,
        mutation,
        existing,
      );
      await this.recordMutation(client, {
        mutation,
        userId,
        deviceId,
        serverObjectId: existing.id,
        result: 'conflict',
      });
      return { kind: 'conflict', conflict };
    }

    const object = await this.upsertObject(client, userId, deviceId, mutation, existing);
    await this.recordChange(
      client,
      userId,
      deviceId,
      object.id,
      mutation.objectType,
      mutation.action === 'delete' ? 'delete' : 'upsert',
      object.server_version,
      object.payload,
    );
    await this.recordMutation(client, {
      mutation,
      userId,
      deviceId,
      serverObjectId: object.id,
      serverVersion: object.server_version,
      result: 'accepted',
    });

    return {
      kind: 'accepted',
      accepted: {
        mutationUid: mutation.mutationUid,
        objectType: mutation.objectType,
        localId: mutation.localId,
        serverId: object.id,
        serverVersion: object.server_version,
      },
    };
  }

  private async findTargetObject(
    client: TransactionClient,
    userId: string,
    mutation: SyncMutationDto,
  ) {
    if (mutation.serverId) {
      const byId = await client.query<SyncObjectRow>(
        `
        SELECT id::text, uid, payload, deleted_at, server_version
        FROM sync_objects
        WHERE user_id = $1 AND id = $2
        LIMIT 1
        `,
        [userId, mutation.serverId],
      );
      if (byId.rows[0]) {
        return byId.rows[0];
      }
    }

    if (mutation.uid) {
      const byUid = await client.query<SyncObjectRow>(
        `
        SELECT id::text, uid, payload, deleted_at, server_version
        FROM sync_objects
        WHERE user_id = $1
          AND object_type = $2
          AND uid = $3
          AND deleted_at IS NULL
        LIMIT 1
        `,
        [userId, mutation.objectType, mutation.uid],
      );
      return byUid.rows[0] ?? null;
    }

    return null;
  }

  private async upsertObject(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    mutation: SyncMutationDto,
    existing: SyncObjectRow | null,
  ) {
    if (!existing) {
      const created = await client.query<SyncObjectRow>(
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
        RETURNING id::text, uid, payload, deleted_at, server_version
        `,
        [
          userId,
          mutation.objectType,
          mutation.uid ?? null,
          JSON.stringify(mutation.payload ?? {}),
          mutation.action === 'delete' ? new Date() : null,
          deviceId,
        ],
      );
      return created.rows[0];
    }

    if (mutation.action === 'delete') {
      const deleted = await client.query<SyncObjectRow>(
        `
        UPDATE sync_objects
        SET
          deleted_at = now(),
          server_version = server_version + 1,
          last_modified_device_id = $3,
          updated_at = now()
        WHERE id = $1 AND user_id = $2
        RETURNING id::text, uid, payload, deleted_at, server_version
        `,
        [existing.id, userId, deviceId],
      );
      return deleted.rows[0];
    }

    const updated = await client.query<SyncObjectRow>(
      `
      UPDATE sync_objects
      SET
        payload = payload || $3::jsonb,
        uid = COALESCE($4, uid),
        deleted_at = NULL,
        server_version = server_version + 1,
        last_modified_device_id = $5,
        updated_at = now()
      WHERE id = $1 AND user_id = $2
      RETURNING id::text, uid, payload, deleted_at, server_version
      `,
      [
        existing.id,
        userId,
        JSON.stringify(mutation.payload ?? {}),
        mutation.uid ?? null,
        deviceId,
      ],
    );
    return updated.rows[0];
  }

  private isOutlookReadOnlyMutation(
    mutation: SyncMutationDto,
    existing: SyncObjectRow | null,
  ) {
    if (!['calendar_book', 'calendar_event'].includes(mutation.objectType)) {
      return false;
    }
    const payload = mutation.payload ?? {};
    if (payload.source === 'outlook' || payload.readOnly === true) {
      return true;
    }
    const existingPayload = existing?.payload ?? {};
    return existingPayload.source === 'outlook' || existingPayload.readOnly === true;
  }

  private async createConflict(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    mutation: SyncMutationDto,
    existing: SyncObjectRow,
  ) {
    const fields = this.buildConflictFields(mutation, existing.payload);
    const conflict = await client.query<{
      conflict_id: string;
      mutation_uid: string;
      object_type: string;
      local_id: string;
      server_id: string;
      base_version: number | null;
      local_version: number;
      server_version: number;
      fields: SyncConflictDto['fields'];
    }>(
      `
      INSERT INTO sync_conflicts (
        user_id,
        device_id,
        mutation_uid,
        object_type,
        local_id,
        server_object_id,
        base_version,
        local_version,
        server_version,
        fields
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, 1, $8, $9::jsonb)
      RETURNING
        id::text AS conflict_id,
        mutation_uid,
        object_type,
        local_id,
        server_object_id::text AS server_id,
        base_version,
        local_version,
        server_version,
        fields
      `,
      [
        userId,
        deviceId,
        mutation.mutationUid,
        mutation.objectType,
        mutation.localId,
        existing.id,
        mutation.baseServerVersion ?? null,
        existing.server_version,
        JSON.stringify(fields),
      ],
    );
    return this.conflictFromRow(conflict.rows[0]);
  }

  private buildConflictFields(
    mutation: SyncMutationDto,
    serverPayload: Record<string, unknown>,
  ): SyncConflictDto['fields'] {
    const changedFields =
      mutation.changedFields && mutation.changedFields.length > 0
        ? mutation.changedFields
        : Object.keys(mutation.payload ?? {});

    return changedFields.map((field) => ({
      field,
      base: undefined,
      local: mutation.payload?.[field],
      server: serverPayload?.[field],
    }));
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

  private recordMutation(
    client: TransactionClient,
    args: {
      mutation: SyncMutationDto;
      userId: string;
      deviceId: string;
      serverObjectId?: string;
      serverVersion?: number;
      result: 'accepted' | 'conflict' | 'rejected';
      errorMessage?: string;
    },
  ) {
    return client.query(
      `
      INSERT INTO sync_mutations (
        mutation_uid,
        user_id,
        device_id,
        object_type,
        local_id,
        server_object_id,
        action,
        base_server_version,
        changed_fields,
        payload,
        result,
        error_message
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10::jsonb, $11, $12)
      ON CONFLICT (mutation_uid) DO NOTHING
      `,
      [
        args.mutation.mutationUid,
        args.userId,
        args.deviceId,
        args.mutation.objectType,
        args.mutation.localId,
        args.serverObjectId ?? null,
        args.mutation.action,
        args.mutation.baseServerVersion ?? null,
        JSON.stringify(args.mutation.changedFields ?? []),
        JSON.stringify(args.mutation.payload ?? {}),
        args.result,
        args.errorMessage ?? null,
      ],
    );
  }

  private recordAudit(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    action: string,
    details: Record<string, unknown>,
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
      ) VALUES ($1, $2, 'server', $3, 'sync_conflict', $4, $5, $6::jsonb)
      `,
      [
        userId,
        deviceId,
        action,
        details.conflictId ?? null,
        `${action}: ${details.conflictId ?? 'unknown'}`,
        JSON.stringify(details),
      ],
    );
  }

  private async findProcessedMutation(
    client: TransactionClient,
    mutationUid: string,
  ) {
    const result = await client.query<{
      result: 'accepted' | 'conflict' | 'rejected';
      server_object_id: string | null;
      server_version: number | null;
      error_message: string | null;
    }>(
      `
      SELECT
        m.result,
        m.server_object_id::text,
        o.server_version,
        m.error_message
      FROM sync_mutations m
      LEFT JOIN sync_objects o ON o.id = m.server_object_id
      WHERE m.mutation_uid = $1
      LIMIT 1
      `,
      [mutationUid],
    );
    return result.rows[0] ?? null;
  }

  private async findConflictForMutation(
    client: TransactionClient,
    mutationUid: string,
  ) {
    const result = await client.query<{
      conflict_id: string;
      mutation_uid: string;
      object_type: string;
      local_id: string | null;
      server_id: string | null;
      base_version: number | null;
      local_version: number;
      server_version: number;
      fields: SyncConflictDto['fields'];
    }>(
      `
      SELECT
        id::text AS conflict_id,
        mutation_uid,
        object_type,
        local_id,
        server_object_id::text AS server_id,
        base_version,
        local_version,
        server_version,
        fields
      FROM sync_conflicts
      WHERE mutation_uid = $1
      LIMIT 1
      `,
      [mutationUid],
    );
    return result.rows[0] ? this.conflictFromRow(result.rows[0]) : null;
  }

  private conflictFromRow(row: {
    conflict_id: string;
    mutation_uid?: string | null;
    object_type: string;
    local_id?: string | null;
    server_id?: string | null;
    base_version?: number | null;
    local_version: number;
    server_version: number;
    fields: SyncConflictDto['fields'];
  }): SyncConflictDto {
    return {
      conflictId: row.conflict_id,
      mutationUid: row.mutation_uid ?? undefined,
      objectType: row.object_type,
      localId: row.local_id ?? undefined,
      serverId: row.server_id ?? undefined,
      baseVersion: row.base_version ?? null,
      localVersion: row.local_version,
      serverVersion: row.server_version,
      fields: row.fields ?? [],
    };
  }

  private parseCursor(cursor?: string) {
    if (!cursor) {
      return 0;
    }
    const parsed = Number.parseInt(cursor, 10);
    return Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
  }

  private readLimit(value?: string) {
    const parsed = Number.parseInt(value ?? '', 10);
    if (!Number.isFinite(parsed)) {
      return 200;
    }
    return Math.max(1, Math.min(1000, parsed));
  }

  private clean(value: unknown) {
    return typeof value === 'string' && value.trim().length > 0
      ? value.trim()
      : null;
  }
}
