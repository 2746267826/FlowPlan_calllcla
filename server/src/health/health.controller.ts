import { Controller, Get } from '@nestjs/common';
import { DatabaseService } from '../database/database.service';

@Controller('health')
export class HealthController {
  constructor(private readonly database: DatabaseService) {}

  @Get()
  async check() {
    const startedAt = new Date();
    const checks: Record<string, unknown> = {
      config: this.configCheck(),
    };
    let ok = true;

    try {
      const db = await this.database.query<DatabaseHealthRow>(
        `
        SELECT
          now() AS now,
          current_database() AS database_name,
          current_schema() AS schema_name,
          to_regclass('public.users') IS NOT NULL AS users_table,
          to_regclass('public.devices') IS NOT NULL AS devices_table,
          to_regclass('public.device_connection_events') IS NOT NULL AS connection_events_table
        `,
      );
      const row = db.rows[0];
      const schemaReady = Boolean(
        row?.users_table &&
          row?.devices_table &&
          row?.connection_events_table,
      );
      checks.database = {
        ok: schemaReady,
        connected: true,
        serverTime: row?.now,
        databaseName: row?.database_name,
        schemaName: row?.schema_name,
        requiredTables: {
          users: Boolean(row?.users_table),
          devices: Boolean(row?.devices_table),
          deviceConnectionEvents: Boolean(row?.connection_events_table),
        },
        message: schemaReady
          ? 'PostgreSQL is reachable and A-stage core tables exist.'
          : 'PostgreSQL is reachable but core tables are missing. Run: cd server; npm run db:schema',
      };
      if (!schemaReady) {
        ok = false;
        checks.devices = {
          ok: false,
          reason: 'schema_not_applied',
        };
      } else {
        checks.devices = await this.devicesCheck();
      }
    } catch (error) {
      ok = false;
      checks.database = {
        ok: false,
        connected: false,
        error: this.errorMessage(error),
        message:
          'Check FLOWPLANV2_DATABASE_URL/DATABASE_URL, PostgreSQL availability, and run: cd server; npm run db:schema',
      };
      checks.devices = {
        ok: false,
        reason: 'database_unavailable',
      };
    }

    checks.optional = {
      storage: {
        optional: true,
        checked: false,
        message:
          'Object storage is not part of A-stage startup health and does not block /api/health.',
      },
      models: {
        optional: true,
        checked: false,
        message:
          'Model and AI checks are intentionally excluded from A-stage startup health.',
      },
    };

    return {
      ok,
      service: 'flowplanv2-server',
      phase: 'A-startup-connection',
      generatedAt: startedAt.toISOString(),
      checks,
    };
  }

  private async devicesCheck() {
    const counts = await this.database.query<{
      users: number;
      devices: number;
      online_devices: number;
      connection_events: number;
      recent_connection_events: number;
    }>(
      `
      SELECT
        (SELECT COUNT(*)::int FROM users) AS users,
        (SELECT COUNT(*)::int FROM devices) AS devices,
        (
          SELECT COUNT(*)::int
          FROM devices
          WHERE revoked_at IS NULL
            AND last_heartbeat_at > now() - interval '90 seconds'
        ) AS online_devices,
        (SELECT COUNT(*)::int FROM device_connection_events) AS connection_events,
        (
          SELECT COUNT(*)::int
          FROM device_connection_events
          WHERE server_time > now() - interval '24 hours'
        ) AS recent_connection_events
      `,
    );
    const row = counts.rows[0];
    return {
      ok: true,
      users: row?.users ?? 0,
      devices: row?.devices ?? 0,
      onlineDevices: row?.online_devices ?? 0,
      connectionEvents: row?.connection_events ?? 0,
      recentConnectionEvents24h: row?.recent_connection_events ?? 0,
    };
  }

  private configCheck() {
    return {
      ok: Boolean(process.env.FLOWPLANV2_DATABASE_URL ?? process.env.DATABASE_URL),
      databaseUrlPresent: Boolean(
        process.env.FLOWPLANV2_DATABASE_URL ?? process.env.DATABASE_URL,
      ),
      port: Number(process.env.PORT ?? 3202),
      host: process.env.HOST ?? '127.0.0.1',
      bodyLimit:
        process.env.FLOWPLANV2_BODY_LIMIT ?? '50mb',
      corsOrigin: process.env.ADMIN_CORS_ORIGIN ?? 'any',
    };
  }

  private errorMessage(error: unknown) {
    return error instanceof Error ? error.message : String(error);
  }
}

interface DatabaseHealthRow {
  now: Date;
  database_name: string;
  schema_name: string;
  users_table: boolean;
  devices_table: boolean;
  connection_events_table: boolean;
}
