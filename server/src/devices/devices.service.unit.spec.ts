import { UnauthorizedException } from '@nestjs/common';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { DevicesService } from './devices.service';

const context = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};

function databaseMock(results: Array<{ rows: unknown[] }> = []) {
  const query = vi.fn(async () => ({ rows: [] as unknown[] }));
  for (const result of results) {
    query.mockResolvedValueOnce(result);
  }
  return { query };
}

describe('DevicesService', () => {
  afterEach(() => {
    vi.useRealTimers();
  });

  it('registers a new device and records a connect event', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00.000Z'));
    const database = databaseMock([
      { rows: [] },
      { rows: [] },
    ]);
    const service = new DevicesService(database as never);

    const result = await service.register(
      {
        deviceId: context.deviceId,
        deviceName: 'Workstation',
        platform: 'windows',
        appVersion: '1.2.3',
      },
      context,
    );

    expect(result).toEqual({
      deviceId: expect.stringMatching(
        /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      ),
      clientDeviceId: context.deviceId,
      deviceName: 'Workstation',
      platform: 'windows',
      connectionStatus: 'online',
      serverTime: '2026-01-01T00:00:00.000Z',
    });
    expect(database.query).toHaveBeenCalledTimes(4);
    expect(database.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining('INSERT INTO devices'),
      [
        result.deviceId,
        context.userId,
        'Workstation',
        'windows',
        context.deviceId,
        '1.2.3',
      ],
    );
    expect(database.query).toHaveBeenNthCalledWith(
      4,
      expect.stringContaining('INSERT INTO device_connection_events'),
      expect.arrayContaining([context.userId, result.deviceId, 'connect']),
    );
  });

  it('registers with context device id and default metadata when body fields are absent', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00.000Z'));
    const database = databaseMock([
      { rows: [] },
      { rows: [] },
    ]);
    const service = new DevicesService(database as never);

    const result = await service.register({}, context);

    expect(result).toEqual({
      deviceId: expect.any(String),
      clientDeviceId: context.deviceId,
      deviceName: 'Unknown device',
      platform: 'unknown',
      connectionStatus: 'online',
      serverTime: '2026-01-01T00:00:00.000Z',
    });
    expect(database.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining('INSERT INTO devices'),
      [
        result.deviceId,
        context.userId,
        'Unknown device',
        'unknown',
        context.deviceId,
        undefined,
      ],
    );
  });

  it('returns revoked registration status and records an error event', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00.000Z'));
    const database = databaseMock([
      { rows: [] },
      { rows: [{ id: 'device-db-id', revoked_at: new Date('2025-01-01T00:00:00Z') }] },
    ]);
    const service = new DevicesService(database as never);

    const result = await service.register(
      { deviceId: 'client-device', deviceName: 'Tablet', platform: 'android' },
      context,
    );

    expect(result).toEqual({
      deviceId: 'device-db-id',
      clientDeviceId: 'client-device',
      deviceName: 'Tablet',
      platform: 'android',
      connectionStatus: 'revoked',
      authRequired: true,
      reason: 'device_revoked',
      serverTime: '2026-01-01T00:00:00.000Z',
    });
    expect(database.query).toHaveBeenCalledTimes(3);
    expect(database.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining('INSERT INTO device_connection_events'),
      expect.arrayContaining([context.userId, 'device-db-id', 'error']),
    );
  });

  it('lists devices for the current user', async () => {
    const deviceRow = {
      id: 'device-db-id',
      deviceName: 'Workstation',
      connectionStatus: 'online',
    };
    const database = databaseMock([
      { rows: [] },
      { rows: [deviceRow] },
    ]);
    const service = new DevicesService(database as never);

    await expect(service.list(context)).resolves.toEqual({
      devices: [deviceRow],
    });
    expect(database.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('FROM devices'),
      [context.userId],
    );
  });

  it('updates mutable device fields', async () => {
    const database = databaseMock([
      { rows: [] },
      { rows: [] },
    ]);
    const service = new DevicesService(database as never);

    await expect(
      service.update('target-device', { deviceName: 'Desk', platform: 'linux' }, context),
    ).resolves.toEqual({ ok: true });
    expect(database.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('UPDATE devices'),
      [context.userId, 'target-device', 'Desk', 'linux'],
    );
  });

  it('updates heartbeat telemetry and reports pending server changes', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:10.000Z'));
    const database = databaseMock([
      { rows: [] },
      { rows: [{ revoked_at: null, revoked_reason: null }] },
      { rows: [] },
      { rows: [] },
      { rows: [] },
      {
        rows: [
          {
            latestChangeCursor: '12',
            clientPullCursor: '7',
            pendingOutlookChanges: '2',
            outlookCalendarBooks: '1',
            outlookCalendarEvents: '4',
          },
        ],
      },
    ]);
    const service = new DevicesService(database as never);

    const result = await service.heartbeat(
      context.deviceId,
      {
        clientTime: '2026-01-01T00:00:09.250Z',
        appVersion: '2.0.0',
        platform: 'windows',
        networkType: 'wifi',
        networkSummary: { ssid: 'office' },
        syncSummary: { pendingCount: '3', failedCount: 1.8, conflictCount: 'bad' },
        metadata: { source: 'unit' },
      },
      context,
    );

    expect(result).toEqual({
      ok: true,
      connectionStatus: 'online',
      serverTime: '2026-01-01T00:00:10.000Z',
      nextHeartbeatSeconds: 30,
      shouldPull: true,
      latestChangeCursor: '12',
      clientPullCursor: '7',
      pendingOutlookChanges: 2,
      outlookCalendarBooks: 1,
      outlookCalendarEvents: 4,
      hasServerChanges: true,
    });
    expect(database.query).toHaveBeenNthCalledWith(
      4,
      expect.stringContaining('UPDATE devices'),
      [
        context.userId,
        context.deviceId,
        'online',
        undefined,
        '2.0.0',
        'windows',
        'wifi',
        3,
        1,
        0,
      ],
    );
    expect(database.query).toHaveBeenNthCalledWith(
      5,
      expect.stringContaining('INSERT INTO device_connection_events'),
      expect.arrayContaining([context.userId, context.deviceId, 'heartbeat', '2026-01-01T00:00:09.250Z', 750]),
    );
  });

  it('records degraded heartbeats and falls back to an empty sync cursor summary', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:10.000Z'));
    const database = databaseMock([
      { rows: [] },
      { rows: [{ revoked_at: null, revoked_reason: null }] },
      { rows: [] },
      { rows: [] },
      { rows: [] },
      { rows: [] },
    ]);
    const service = new DevicesService(database as never);

    const result = await service.heartbeat(
      context.deviceId,
      {
        clientTime: '',
        errorMessage: 'sync_failed',
        syncSummary: { pendingCount: {}, failedCount: '2.9', conflictCount: null },
      },
      context,
    );

    expect(result).toEqual({
      ok: true,
      connectionStatus: 'degraded',
      serverTime: '2026-01-01T00:00:10.000Z',
      nextHeartbeatSeconds: 60,
      shouldPull: false,
      latestChangeCursor: '0',
      clientPullCursor: '0',
      pendingOutlookChanges: 0,
      outlookCalendarBooks: 0,
      outlookCalendarEvents: 0,
      hasServerChanges: false,
    });
    expect(database.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining('INSERT INTO devices'),
      [context.deviceId, context.userId, 'unknown'],
    );
    expect(database.query).toHaveBeenNthCalledWith(
      4,
      expect.stringContaining('UPDATE devices'),
      [
        context.userId,
        context.deviceId,
        'degraded',
        'sync_failed',
        undefined,
        undefined,
        'unknown',
        0,
        2,
        0,
      ],
    );
    expect(database.query).toHaveBeenNthCalledWith(
      5,
      expect.stringContaining('INSERT INTO device_connection_events'),
      expect.arrayContaining([
        context.userId,
        context.deviceId,
        'error',
        null,
        null,
        null,
        null,
        '{}',
        JSON.stringify({ pendingCount: {}, failedCount: '2.9', conflictCount: null }),
        'sync_failed',
      ]),
    );
  });

  it('rejects heartbeat for revoked devices', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00.000Z'));
    const database = databaseMock([
      { rows: [] },
      { rows: [{ revoked_at: new Date('2025-01-01T00:00:00Z'), revoked_reason: 'lost' }] },
    ]);
    const service = new DevicesService(database as never);

    const result = await service.heartbeat(context.deviceId, {}, context);

    expect(result).toEqual({
      ok: false,
      connectionStatus: 'revoked',
      authRequired: true,
      reason: 'device_revoked',
      serverTime: '2026-01-01T00:00:00.000Z',
      nextHeartbeatSeconds: 300,
      shouldPull: false,
    });
    expect(database.query).toHaveBeenCalledTimes(3);
    expect(database.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining('INSERT INTO device_connection_events'),
      expect.arrayContaining([context.userId, context.deviceId, 'error']),
    );
  });

  it('returns connection history with null device when the device is missing', async () => {
    const eventRow = {
      id: 'event-1',
      eventType: 'error',
      errorMessage: 'offline',
    };
    const database = databaseMock([
      { rows: [] },
      { rows: [] },
      { rows: [eventRow] },
    ]);
    const service = new DevicesService(database as never);

    await expect(service.connectionHistory('missing-device', context)).resolves.toEqual({
      device: null,
      events: [eventRow],
    });
    expect(database.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('FROM devices'),
      [context.userId, 'missing-device'],
    );
    expect(database.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining('FROM device_connection_events'),
      [context.userId, 'missing-device'],
    );
  });

  it('throws when ensureDevice finds a revoked device', async () => {
    const database = databaseMock([
      { rows: [] },
      { rows: [{ id: context.deviceId, revoked_at: new Date('2025-01-01T00:00:00Z') }] },
    ]);
    const service = new DevicesService(database as never);

    await expect(service.ensureDevice(context)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('creates an unregistered device when ensureDevice has no existing row', async () => {
    const database = databaseMock([
      { rows: [] },
      { rows: [] },
      { rows: [] },
    ]);
    const service = new DevicesService(database as never);

    await expect(service.ensureDevice(context)).resolves.toBe(context.deviceId);
    expect(database.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining('INSERT INTO devices'),
      [context.deviceId, context.userId, context.deviceId],
    );
  });

  it('revokes an existing device and records audit history', async () => {
    const database = databaseMock([
      { rows: [] },
      { rows: [] },
      { rows: [{ id: context.deviceId, revoked_at: null }] },
      { rows: [{ id: 'target-device' }] },
      { rows: [] },
      { rows: [] },
    ]);
    const service = new DevicesService(database as never);

    const result = await service.revoke('target-device', { reason: 'lost' }, context);

    expect(result).toEqual({
      ok: true,
      deviceId: 'target-device',
      connectionStatus: 'revoked',
      reason: 'lost',
    });
    expect(database.query).toHaveBeenNthCalledWith(
      4,
      expect.stringContaining('UPDATE devices'),
      [context.userId, 'target-device', 'lost'],
    );
    expect(database.query).toHaveBeenNthCalledWith(
      6,
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'device.revoke', 'target-device']),
    );
  });

  it('returns a not-found result when revoke updates no rows', async () => {
    const database = databaseMock([
      { rows: [] },
      { rows: [] },
      { rows: [{ id: context.deviceId, revoked_at: null }] },
      { rows: [] },
    ]);
    const service = new DevicesService(database as never);

    await expect(service.revoke('missing-device', {}, context)).resolves.toEqual({
      ok: false,
      reason: 'device_not_found',
    });
  });

  it('builds online summary counts and backlog totals', async () => {
    const database = databaseMock([
      { rows: [] },
      { rows: [{ name: 'online', count: 2 }, { name: 'degraded', count: 1 }] },
      { rows: [{ count: 8 }] },
      { rows: [{ pendingCount: 3, failedCount: 1, conflictCount: 2 }] },
    ]);
    const service = new DevicesService(database as never);

    const result = await service.onlineSummary(context);

    expect(result).toMatchObject({
      counts: { online: 2, degraded: 1 },
      last24hEventCount: 8,
      backlog: { pendingCount: 3, failedCount: 1, conflictCount: 2 },
    });
    expect(result.generatedAt).toEqual(expect.any(String));
  });

  it('uses empty online summary defaults when aggregate rows are absent', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:00.000Z'));
    const database = databaseMock([
      { rows: [] },
      { rows: [] },
      { rows: [] },
      { rows: [] },
    ]);
    const service = new DevicesService(database as never);

    await expect(service.onlineSummary(context)).resolves.toEqual({
      generatedAt: '2026-01-01T00:00:00.000Z',
      counts: {},
      last24hEventCount: 0,
      backlog: {
        pendingCount: 0,
        failedCount: 0,
        conflictCount: 0,
      },
    });
  });

  it('handles invalid heartbeat time, sparse sync summary, and sparse cursor rows', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-01T00:00:10.000Z'));
    const database = databaseMock([
      { rows: [] },
      { rows: [{ revoked_at: null, revoked_reason: null }] },
      { rows: [] },
      { rows: [] },
      { rows: [] },
      { rows: [{ latestChangeCursor: '5', clientPullCursor: '5' }] },
    ]);
    const service = new DevicesService(database as never);

    const result = await service.heartbeat(
      context.deviceId,
      {
        clientTime: 'not-a-date',
        syncSummary: { pendingCount: '4' },
      },
      context,
    );

    expect(result).toMatchObject({
      ok: true,
      connectionStatus: 'online',
      shouldPull: false,
      latestChangeCursor: '5',
      clientPullCursor: '5',
      pendingOutlookChanges: 0,
      outlookCalendarBooks: 0,
      outlookCalendarEvents: 0,
    });
    expect(database.query).toHaveBeenNthCalledWith(
      4,
      expect.stringContaining('UPDATE devices'),
      [
        context.userId,
        context.deviceId,
        'online',
        undefined,
        undefined,
        undefined,
        'unknown',
        4,
        0,
        0,
      ],
    );
    expect(database.query).toHaveBeenNthCalledWith(
      5,
      expect.stringContaining('INSERT INTO device_connection_events'),
      expect.arrayContaining([
        context.userId,
        context.deviceId,
        'heartbeat',
        null,
        null,
        null,
        null,
        '{}',
        JSON.stringify({ pendingCount: '4' }),
        null,
      ]),
    );
  });

  it('records connection events with empty optional telemetry defaults', async () => {
    const database = databaseMock();
    const service = new DevicesService(database as never);
    const connectionEvent = service as unknown as {
      recordConnectionEvent: (
        userId: string,
        deviceId: string,
        eventType: string,
        data: Record<string, unknown>,
      ) => Promise<void>;
    };

    await connectionEvent.recordConnectionEvent(context.userId, context.deviceId, 'heartbeat', {});

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO device_connection_events'),
      [
        context.userId,
        context.deviceId,
        'heartbeat',
        null,
        null,
        null,
        null,
        JSON.stringify({}),
        JSON.stringify({}),
        null,
        JSON.stringify({}),
      ],
    );
  });
});
