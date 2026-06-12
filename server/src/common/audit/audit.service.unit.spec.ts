import { describe, expect, it, vi } from 'vitest';
import { AuditService } from './audit.service';
import type { DatabaseService, TransactionClient } from '../../database/database.service';

function makeDatabase() {
  return {
    query: vi.fn(async () => ({ rows: [] })),
  };
}

function makeClient() {
  return {
    query: vi.fn(async () => ({ rows: [] })),
  };
}

describe('AuditService', () => {
  it('writes a transactional audit entry with explicit summary, entity id, and metadata', async () => {
    const database = makeDatabase();
    const client = makeClient();
    const service = new AuditService(database as unknown as DatabaseService);

    await service.write(client as unknown as TransactionClient, {
      userId: 'user-1',
      deviceId: 'device-1',
      actor: 'server',
      action: 'task.update',
      entityType: 'task',
      entityId: 'task-1',
      summary: 'Task updated',
      metadata: { changed: ['title'], nested: { ok: true } },
    });

    expect(client.query).toHaveBeenCalledTimes(1);
    expect(client.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO audit_logs'), [
      'user-1',
      'device-1',
      'server',
      'task.update',
      'task',
      'task-1',
      'Task updated',
      JSON.stringify({ changed: ['title'], nested: { ok: true } }),
    ]);
    expect(database.query).not.toHaveBeenCalled();
  });

  it('defaults nullable fields when writing inside a transaction', async () => {
    const client = makeClient();
    const service = new AuditService(makeDatabase() as unknown as DatabaseService);

    await service.write(client as unknown as TransactionClient, {
      userId: 'user-2',
      deviceId: 'device-2',
      actor: 'client',
      action: 'task.create',
      entityType: 'task',
    });

    expect(client.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO audit_logs'), [
      'user-2',
      'device-2',
      'client',
      'task.create',
      'task',
      null,
      'task.create',
      '{}',
    ]);
  });

  it('writes standalone audit rows through DatabaseService', async () => {
    const database = makeDatabase();
    const service = new AuditService(database as unknown as DatabaseService);

    await service.writeStandalone({
      userId: 'user-3',
      deviceId: 'device-3',
      actor: 'admin',
      action: 'report.export',
      entityType: 'report',
      entityId: null,
      summary: null,
      metadata: { format: 'csv' },
    });

    expect(database.query).toHaveBeenCalledTimes(1);
    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO audit_logs'), [
      'user-3',
      'device-3',
      'admin',
      'report.export',
      'report',
      null,
      'report.export',
      JSON.stringify({ format: 'csv' }),
    ]);
  });

  it('propagates database errors from standalone writes', async () => {
    const error = new Error('database unavailable');
    const database = {
      query: vi.fn(async () => {
        throw error;
      }),
    };
    const service = new AuditService(database as unknown as DatabaseService);

    await expect(
      service.writeStandalone({
        userId: 'user-4',
        deviceId: 'device-4',
        actor: 'server',
        action: 'task.delete',
        entityType: 'task',
      }),
    ).rejects.toBe(error);
  });
});
