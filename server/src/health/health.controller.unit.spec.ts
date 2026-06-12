import { afterEach, describe, expect, it, vi } from 'vitest';
import { HealthController } from './health.controller';

function databaseMock(rows: unknown[][] = []) {
  const query = vi.fn();
  for (const value of rows) {
    query.mockResolvedValueOnce({ rows: value });
  }
  return {
    query,
    poolStats: vi.fn(() => ({ total: 2, idle: 1, waiting: 0 })),
  };
}

describe('HealthController', () => {
  const originalEnv = {
    FLOWPLANV2_DATABASE_URL: process.env.FLOWPLANV2_DATABASE_URL,
    DATABASE_URL: process.env.DATABASE_URL,
    FLOWPLANV2_ENCRYPTION_KEY: process.env.FLOWPLANV2_ENCRYPTION_KEY,
    OUTLOOK_CONFIG_SECRET: process.env.OUTLOOK_CONFIG_SECRET,
    AI_CONFIG_SECRET: process.env.AI_CONFIG_SECRET,
  };

  afterEach(() => {
    for (const [key, value] of Object.entries(originalEnv)) {
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  });

  it('reports healthy database and device checks when required tables exist', async () => {
    const database = databaseMock([
      [
        {
          now: new Date('2026-01-01T00:00:00Z'),
          database_name: 'flowplantest',
          schema_name: 'public',
          users_table: true,
          devices_table: true,
          connection_events_table: true,
        },
      ],
      [
        {
          users: 2,
          devices: 3,
          online_devices: 1,
          connection_events: 9,
          recent_connection_events: 4,
        },
      ],
    ]);
    const controller = new HealthController(database as never);

    const result = await controller.check();

    expect(result.ok).toBe(true);
    expect(result.checks.database).toMatchObject({
      ok: true,
      connected: true,
      databaseName: 'flowplantest',
      requiredTables: {
        users: true,
        devices: true,
        deviceConnectionEvents: true,
      },
    });
    expect(result.checks.devices).toMatchObject({
      ok: true,
      users: 2,
      devices: 3,
      onlineDevices: 1,
      connectionEvents: 9,
      recentConnectionEvents24h: 4,
    });
  });

  it('marks startup unhealthy when schema tables are missing', async () => {
    const database = databaseMock([
      [
        {
          now: new Date('2026-01-01T00:00:00Z'),
          database_name: 'flowplantest',
          schema_name: 'public',
          users_table: true,
          devices_table: false,
          connection_events_table: false,
        },
      ],
    ]);
    const controller = new HealthController(database as never);

    const result = await controller.check();

    expect(result.ok).toBe(false);
    expect(result.checks.database).toMatchObject({
      ok: false,
      connected: true,
      requiredTables: {
        users: true,
        devices: false,
        deviceConnectionEvents: false,
      },
    });
    expect(result.checks.devices).toEqual({
      ok: false,
      reason: 'schema_not_applied',
    });
    expect(database.query).toHaveBeenCalledTimes(1);
  });

  it('reports database_unavailable when the health query fails', async () => {
    const database = {
      query: vi.fn().mockRejectedValueOnce(new Error('connection refused')),
      poolStats: vi.fn(() => ({ total: 0, idle: 0, waiting: 0 })),
    };
    const controller = new HealthController(database as never);

    const result = await controller.check();

    expect(result.ok).toBe(false);
    expect(result.checks.database).toMatchObject({
      ok: false,
      connected: false,
      error: 'connection refused',
    });
    expect(result.checks.devices).toEqual({
      ok: false,
      reason: 'database_unavailable',
    });
    expect(result.checks.optional).toMatchObject({
      storage: { optional: true, checked: false },
      models: { optional: true, checked: false },
    });
  });

  it('defaults missing device counts to zero and reports dedicated encryption key sources', async () => {
    delete process.env.FLOWPLANV2_DATABASE_URL;
    process.env.DATABASE_URL = 'postgres://localhost/flowplantest';
    delete process.env.FLOWPLANV2_ENCRYPTION_KEY;
    delete process.env.OUTLOOK_CONFIG_SECRET;
    process.env.AI_CONFIG_SECRET = 'ai-secret';
    const database = databaseMock([
      [
        {
          now: new Date('2026-01-01T00:00:00Z'),
          database_name: 'flowplantest',
          schema_name: 'public',
          users_table: true,
          devices_table: true,
          connection_events_table: true,
        },
      ],
      [{}],
    ]);
    const controller = new HealthController(database as never);

    const result = await controller.check();

    expect(result.checks.devices).toMatchObject({
      users: 0,
      devices: 0,
      onlineDevices: 0,
      connectionEvents: 0,
      recentConnectionEvents24h: 0,
    });
    expect(result.checks.config).toMatchObject({
      encryptionKeySecure: true,
      encryptionKeySource: 'AI_CONFIG_SECRET',
    });

    delete process.env.AI_CONFIG_SECRET;
    process.env.OUTLOOK_CONFIG_SECRET = 'outlook-secret';
    expect(
      (
        await new HealthController(
          databaseMock([
            [
              {
                now: new Date('2026-01-01T00:00:00Z'),
                database_name: 'flowplantest',
                schema_name: 'public',
                users_table: false,
                devices_table: false,
                connection_events_table: false,
              },
            ],
          ]) as never,
        ).check()
      ).checks.config,
    ).toMatchObject({
      encryptionKeySource: 'OUTLOOK_CONFIG_SECRET',
    });

    delete process.env.OUTLOOK_CONFIG_SECRET;
    process.env.FLOWPLANV2_ENCRYPTION_KEY = 'flowplan-secret';
    expect(
      (
        await new HealthController(
          databaseMock([
            [
              {
                now: new Date('2026-01-01T00:00:00Z'),
                database_name: 'flowplantest',
                schema_name: 'public',
                users_table: false,
                devices_table: false,
                connection_events_table: false,
              },
            ],
          ]) as never,
        ).check()
      ).checks.config,
    ).toMatchObject({
      encryptionKeySource: 'FLOWPLANV2_ENCRYPTION_KEY',
    });
  });
});
