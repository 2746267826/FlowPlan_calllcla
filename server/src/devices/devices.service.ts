import { Injectable, UnauthorizedException } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../database/database.service';
import { FlowPlanV2RequestContext } from '../common/request-context';

@Injectable()
export class DevicesService {
  constructor(private readonly database: DatabaseService) {}

  async register(body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    const userId = await this.ensureUser(context.userId);
    const clientDeviceId = this.asString(body.deviceId) ?? context.deviceId;
    const deviceName = this.asString(body.deviceName) ?? 'Unknown device';
    const platform = this.asString(body.platform) ?? 'unknown';
    const appVersion = this.asString(body.appVersion);

    const existing = await this.database.query<{ id: string; revoked_at: Date | null }>(
      `
      SELECT id, revoked_at
      FROM devices
      WHERE user_id = $1 AND client_device_id = $2
      LIMIT 1
      `,
      [userId, clientDeviceId],
    );

    const existingDevice = existing.rows[0];
    if (existingDevice?.revoked_at) {
      await this.recordConnectionEvent(userId, existingDevice.id, 'error', {
        platform,
        appVersion,
        errorMessage: 'device_revoked',
        metadata: { clientDeviceId, deviceName },
      });
      return {
        deviceId: existingDevice.id,
        clientDeviceId,
        deviceName,
        platform,
        connectionStatus: 'revoked',
        authRequired: true,
        reason: 'device_revoked',
        serverTime: new Date().toISOString(),
      };
    }

    const deviceId = existingDevice?.id ?? randomUUID();
    await this.database.query(
      `
      INSERT INTO devices (
        id,
        user_id,
        device_name,
        platform,
        client_device_id,
        last_seen_at,
        last_heartbeat_at,
        last_connected_at,
        connection_status,
        app_version,
        runtime_platform
      ) VALUES ($1, $2, $3, $4, $5, now(), now(), now(), 'online', $6, $4)
      ON CONFLICT (user_id, client_device_id) DO UPDATE SET
        device_name = EXCLUDED.device_name,
        platform = EXCLUDED.platform,
        runtime_platform = EXCLUDED.runtime_platform,
        app_version = COALESCE(EXCLUDED.app_version, devices.app_version),
        last_seen_at = now(),
        last_heartbeat_at = now(),
        last_connected_at = CASE
          WHEN devices.connection_status = 'offline' THEN now()
          ELSE devices.last_connected_at
        END,
        connection_status = 'online',
        last_connection_error = NULL,
        updated_at = now()
      `,
      [deviceId, userId, deviceName, platform, clientDeviceId, appVersion],
    );

    await this.recordConnectionEvent(userId, deviceId, 'connect', {
      platform,
      appVersion,
      metadata: { clientDeviceId, deviceName },
    });

    return {
      deviceId,
      clientDeviceId,
      deviceName,
      platform,
      connectionStatus: 'online',
      serverTime: new Date().toISOString(),
    };
  }

  async list(context: FlowPlanV2RequestContext) {
    const userId = await this.ensureUser(context.userId);
    const result = await this.database.query(
      `
      SELECT
        id,
        device_name AS "deviceName",
        platform,
        client_device_id AS "clientDeviceId",
        last_seen_at AS "lastSeenAt",
        last_heartbeat_at AS "lastHeartbeatAt",
        last_connected_at AS "lastConnectedAt",
        last_disconnected_at AS "lastDisconnectedAt",
        connection_status AS "storedConnectionStatus",
        CASE
          WHEN revoked_at IS NOT NULL THEN 'revoked'
          WHEN last_heartbeat_at IS NULL THEN 'offline'
          WHEN last_heartbeat_at > now() - interval '90 seconds' THEN 'online'
          WHEN last_heartbeat_at > now() - interval '10 minutes' THEN 'degraded'
          ELSE 'offline'
        END AS "connectionStatus",
        last_connection_error AS "lastConnectionError",
        app_version AS "appVersion",
        runtime_platform AS "runtimePlatform",
        network_type AS "networkType",
        sync_pending_count AS "syncPendingCount",
        sync_failed_count AS "syncFailedCount",
        open_conflict_count AS "openConflictCount",
        revoked_at AS "revokedAt",
        revoked_reason AS "revokedReason",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM devices
      WHERE user_id = $1
      ORDER BY last_seen_at DESC NULLS LAST, created_at DESC
      `,
      [userId],
    );
    return {
      devices: result.rows,
    };
  }

  async update(
    deviceId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.ensureUser(context.userId);
    await this.database.query(
      `
      UPDATE devices
      SET
        device_name = COALESCE($3, device_name),
        platform = COALESCE($4, platform),
        updated_at = now()
      WHERE user_id = $1 AND id = $2
      `,
      [
        userId,
        deviceId,
        this.asString(body.deviceName),
        this.asString(body.platform),
      ],
    );
    return { ok: true };
  }

  async revoke(
    deviceId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.ensureUser(context.userId);
    const actorDeviceId = await this.ensureDevice(context);
    const reason = this.asString(body.reason) ?? 'revoked_from_admin';
    const result = await this.database.query<{ id: string }>(
      `
      UPDATE devices
      SET
        connection_status = 'revoked',
        last_disconnected_at = now(),
        last_connection_error = $3,
        revoked_at = COALESCE(revoked_at, now()),
        revoked_reason = $3,
        updated_at = now()
      WHERE user_id = $1 AND id = $2
      RETURNING id::text
      `,
      [userId, deviceId, reason],
    );
    if (!result.rows[0]) {
      return { ok: false, reason: 'device_not_found' };
    }

    await this.recordConnectionEvent(userId, deviceId, 'revoke', {
      errorMessage: reason,
      metadata: {
        actorDeviceId,
        reason,
      },
    });
    await this.recordAudit(userId, actorDeviceId, 'device.revoke', deviceId, {
      reason,
      targetDeviceId: deviceId,
    });

    return {
      ok: true,
      deviceId,
      connectionStatus: 'revoked',
      reason,
    };
  }

  async heartbeat(
    deviceId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.ensureUser(context.userId);
    const revoked = await this.database.query<{ revoked_at: Date | null; revoked_reason: string | null }>(
      `
      SELECT revoked_at, revoked_reason
      FROM devices
      WHERE user_id = $1 AND id = $2
      LIMIT 1
      `,
      [userId, deviceId],
    );
    if (revoked.rows[0]?.revoked_at) {
      await this.recordConnectionEvent(userId, deviceId, 'error', {
        errorMessage: 'device_revoked',
        metadata: { reason: revoked.rows[0].revoked_reason },
      });
      return {
        ok: false,
        connectionStatus: 'revoked',
        authRequired: true,
        reason: 'device_revoked',
        serverTime: new Date().toISOString(),
        nextHeartbeatSeconds: 300,
        shouldPull: false,
      };
    }

    const now = new Date();
    const clientTime = this.asDate(body.clientTime);
    const latencyMs =
      clientTime == null ? undefined : Math.max(0, now.getTime() - clientTime.getTime());
    const appVersion = this.asString(body.appVersion);
    const platform = this.asString(body.platform);
    const networkType = this.asString(body.networkType) ?? 'unknown';
    const networkSummary = this.asRecord(body.networkSummary);
    const syncSummary = this.asRecord(body.syncSummary);
    const errorMessage = this.asString(body.errorMessage);
    const pendingCount = this.asNumber(syncSummary.pendingCount) ?? 0;
    const failedCount = this.asNumber(syncSummary.failedCount) ?? 0;
    const conflictCount = this.asNumber(syncSummary.conflictCount) ?? 0;
    const nextStatus = errorMessage ? 'degraded' : 'online';

    await this.database.query(
      `
      INSERT INTO devices (
        id,
        user_id,
        device_name,
        platform,
        client_device_id,
        last_seen_at
      ) VALUES ($1::uuid, $2::uuid, 'Unregistered device', $3, $1::text, now())
      ON CONFLICT (id) DO NOTHING
      `,
      [deviceId, userId, platform ?? 'unknown'],
    );

    await this.database.query(
      `
      UPDATE devices
      SET
        last_seen_at = now(),
        last_heartbeat_at = now(),
        last_connected_at = CASE
          WHEN connection_status = 'offline' THEN now()
          ELSE COALESCE(last_connected_at, now())
        END,
        connection_status = $3,
        last_connection_error = $4,
        app_version = COALESCE($5, app_version),
        runtime_platform = COALESCE($6, runtime_platform, platform),
        network_type = $7,
        sync_pending_count = $8,
        sync_failed_count = $9,
        open_conflict_count = $10,
        updated_at = now()
      WHERE user_id = $1 AND id = $2
      `,
      [
        userId,
        deviceId,
        nextStatus,
        errorMessage,
        appVersion,
        platform,
        networkType,
        pendingCount,
        failedCount,
        conflictCount,
      ],
    );

    await this.recordConnectionEvent(userId, deviceId, errorMessage ? 'error' : 'heartbeat', {
      clientTime,
      latencyMs,
      appVersion,
      platform,
      networkSummary,
      syncSummary,
      errorMessage,
      metadata: this.asRecord(body.metadata),
    });

    return {
      ok: true,
      connectionStatus: nextStatus,
      serverTime: new Date().toISOString(),
      nextHeartbeatSeconds: errorMessage ? 60 : 30,
      shouldPull: true,
    };
  }

  async connectionHistory(deviceId: string, context: FlowPlanV2RequestContext) {
    const userId = await this.ensureUser(context.userId);
    const device = await this.database.query(
      `
      SELECT
        id::text AS "deviceId",
        device_name AS "deviceName",
        platform,
        client_device_id AS "clientDeviceId",
        connection_status AS "storedConnectionStatus",
        CASE
          WHEN revoked_at IS NOT NULL THEN 'revoked'
          WHEN last_heartbeat_at IS NULL THEN 'offline'
          WHEN last_heartbeat_at > now() - interval '90 seconds' THEN 'online'
          WHEN last_heartbeat_at > now() - interval '10 minutes' THEN 'degraded'
          ELSE 'offline'
        END AS "connectionStatus",
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
        revoked_at AS "revokedAt",
        revoked_reason AS "revokedReason",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM devices
      WHERE user_id = $1 AND id = $2
      LIMIT 1
      `,
      [userId, deviceId],
    );
    const events = await this.database.query(
      `
      SELECT
        id::text AS id,
        event_type AS "eventType",
        client_time AS "clientTime",
        server_time AS "serverTime",
        latency_ms AS "latencyMs",
        app_version AS "appVersion",
        platform,
        network_summary AS "networkSummary",
        sync_summary AS "syncSummary",
        error_message AS "errorMessage",
        metadata
      FROM device_connection_events
      WHERE user_id = $1 AND device_id = $2
      ORDER BY server_time DESC
      LIMIT 200
      `,
      [userId, deviceId],
    );
    return {
      device: device.rows[0] ?? null,
      events: events.rows,
    };
  }

  async onlineSummary(context: FlowPlanV2RequestContext) {
    const userId = await this.ensureUser(context.userId);
    const counts = await this.database.query(
      `
      SELECT status AS name, COUNT(*)::int AS count
      FROM (
        SELECT CASE
          WHEN revoked_at IS NOT NULL THEN 'revoked'
          WHEN last_heartbeat_at IS NULL THEN 'offline'
          WHEN last_heartbeat_at > now() - interval '90 seconds' THEN 'online'
          WHEN last_heartbeat_at > now() - interval '10 minutes' THEN 'degraded'
          ELSE 'offline'
        END AS status
        FROM devices
        WHERE user_id = $1
      ) s
      GROUP BY status
      `,
      [userId],
    );
    const events = await this.database.query(
      `
      SELECT COUNT(*)::int AS count
      FROM device_connection_events
      WHERE user_id = $1 AND server_time > now() - interval '24 hours'
      `,
      [userId],
    );
    const backlog = await this.database.query(
      `
      SELECT
        COALESCE(SUM(sync_pending_count), 0)::int AS "pendingCount",
        COALESCE(SUM(sync_failed_count), 0)::int AS "failedCount",
        COALESCE(SUM(open_conflict_count), 0)::int AS "conflictCount"
      FROM devices
      WHERE user_id = $1
      `,
      [userId],
    );
    return {
      generatedAt: new Date().toISOString(),
      counts: Object.fromEntries(counts.rows.map((row) => [row.name, row.count])),
      last24hEventCount: events.rows[0]?.count ?? 0,
      backlog: backlog.rows[0] ?? {
        pendingCount: 0,
        failedCount: 0,
        conflictCount: 0,
      },
    };
  }

  async ensureUser(userId: string) {
    await this.database.query(
      `
      INSERT INTO users (id, display_name)
      VALUES ($1, 'FlowPlanV2 User')
      ON CONFLICT (id) DO NOTHING
      `,
      [userId],
    );
    return userId;
  }

  async ensureDevice(context: FlowPlanV2RequestContext) {
    const userId = await this.ensureUser(context.userId);
    const existing = await this.database.query<{ id: string; revoked_at: Date | null }>(
      `
      SELECT id, revoked_at
      FROM devices
      WHERE user_id = $1 AND id = $2
      LIMIT 1
      `,
      [userId, context.deviceId],
    );
    if (existing.rows[0]?.id) {
      if (existing.rows[0].revoked_at) {
        throw new UnauthorizedException('device_revoked');
      }
      return existing.rows[0].id;
    }

    await this.database.query(
      `
      INSERT INTO devices (
        id,
        user_id,
        device_name,
        platform,
        client_device_id,
        last_seen_at
      ) VALUES ($1::uuid, $2::uuid, 'Unregistered device', 'unknown', $3::text, now())
      ON CONFLICT (id) DO NOTHING
      `,
      [context.deviceId, userId, context.deviceId],
    );
    return context.deviceId;
  }

  private asString(value: unknown) {
    return typeof value === 'string' && value.trim().length > 0
      ? value.trim()
      : undefined;
  }

  private asNumber(value: unknown) {
    if (typeof value === 'number' && Number.isFinite(value)) {
      return Math.trunc(value);
    }
    if (typeof value === 'string' && value.trim().length > 0) {
      const parsed = Number(value);
      return Number.isFinite(parsed) ? Math.trunc(parsed) : undefined;
    }
    return undefined;
  }

  private asDate(value: unknown) {
    if (typeof value !== 'string' || value.trim().length === 0) {
      return undefined;
    }
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? undefined : parsed;
  }

  private asRecord(value: unknown) {
    return value && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  }

  private async recordConnectionEvent(
    userId: string,
    deviceId: string,
    eventType: string,
    data: {
      clientTime?: Date;
      latencyMs?: number;
      appVersion?: string;
      platform?: string;
      networkSummary?: Record<string, unknown>;
      syncSummary?: Record<string, unknown>;
      errorMessage?: string;
      metadata?: Record<string, unknown>;
    },
  ) {
    await this.database.query(
      `
      INSERT INTO device_connection_events (
        user_id,
        device_id,
        event_type,
        client_time,
        latency_ms,
        app_version,
        platform,
        network_summary,
        sync_summary,
        error_message,
        metadata
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9::jsonb, $10, $11::jsonb)
      `,
      [
        userId,
        deviceId,
        eventType,
        data.clientTime?.toISOString() ?? null,
        data.latencyMs ?? null,
        data.appVersion ?? null,
        data.platform ?? null,
        JSON.stringify(data.networkSummary ?? {}),
        JSON.stringify(data.syncSummary ?? {}),
        data.errorMessage ?? null,
        JSON.stringify(data.metadata ?? {}),
      ],
    );
  }

  private async recordAudit(
    userId: string,
    actorDeviceId: string,
    action: string,
    entityId: string,
    metadata: Record<string, unknown>,
  ) {
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
      ) VALUES ($1, $2, 'admin', $3, 'device', $4, $5, $6::jsonb)
      `,
      [
        userId,
        actorDeviceId,
        action,
        entityId,
        `${action}: ${entityId}`,
        JSON.stringify(metadata),
      ],
    );
  }
}
