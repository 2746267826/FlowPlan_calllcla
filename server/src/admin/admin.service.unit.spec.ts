import { mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { AdminService } from './admin.service';

vi.mock('node:crypto', () => ({
  randomUUID: () => '00000000-0000-4000-8000-00000000feed',
}));

const context = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};
const originalEnv = { ...process.env };
const originalCwd = process.cwd();
const tempDirs: string[] = [];

type QueryResult = { rows: Record<string, unknown>[] };

function createService(
  queryImpl: (sql: string, params?: unknown[]) => Promise<QueryResult> = async () => ({ rows: [] }),
) {
  const transactionClient = {
    query: vi.fn(async () => ({ rows: [] as Record<string, unknown>[] })),
  };
  const database = {
    query: vi.fn(queryImpl),
    transaction: vi.fn(async (callback: (client: typeof transactionClient) => unknown) =>
      callback(transactionClient),
    ),
  };
  const devices = {
    ensureUser: vi.fn(async (userId: string) => userId),
    ensureDevice: vi.fn(async () => context.deviceId),
    connectionHistory: vi.fn(),
    onlineSummary: vi.fn(),
  };
  const storage = {
    status: vi.fn(async () => ({ rootDir: 'C:/flowplan/storage', writable: true })),
  };
  const service = new AdminService(database as never, devices as never, storage as never);
  return { service, database, devices, storage, transactionClient };
}

function privateApi(service: AdminService) {
  return service as unknown as {
    genericAdminTable(
      domain: string,
      query: Record<string, unknown>,
      context: typeof context,
    ): Promise<Record<string, unknown>>;
    recordAudit(
      client: { query: ReturnType<typeof vi.fn> },
      userId: string,
      deviceId: string,
      actor: string,
      action: string,
      details: Record<string, unknown>,
    ): Promise<void>;
  };
}

describe('AdminService', () => {
  afterEach(() => {
    process.chdir(originalCwd);
    for (const dir of tempDirs.splice(0)) {
      rmSync(dir, { recursive: true, force: true });
    }
    vi.restoreAllMocks();
    vi.useRealTimers();
    for (const key of Object.keys(process.env)) {
      if (!(key in originalEnv)) {
        delete process.env[key];
      }
    }
    Object.assign(process.env, originalEnv);
  });

  it('filters audit logs by search and normalizes pagination/device parameters', async () => {
    const rows = Array.from({ length: 200 }, (_, index) => ({ id: `audit-${index}` }));
    const { service, database } = createService(async (sql) => {
      expect(sql).toContain('FROM audit_logs a');
      expect(sql).toContain('LEFT JOIN devices d');
      return { rows };
    });

    const result = await service.auditLogs(
      { q: '  login ', deviceId: 'all', limit: '999', offset: '-7' },
      context,
    );

    expect(result).toEqual({ limit: 200, offset: 0, hasMore: true, items: rows });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('a.metadata::text ILIKE $2'),
      [context.userId, '%login%', null, 200, 0],
    );
  });

  it('lists reports with status filter and hasMore derived from the normalized limit', async () => {
    const rows = [
      { id: 'report-1', status: 'ready' },
      { id: 'report-2', status: 'ready' },
    ];
    const { service, database } = createService(async () => ({ rows }));

    await expect(
      service.reports({ status: ' ready ', limit: '2', offset: '4' }, context),
    ).resolves.toEqual({ limit: 2, offset: 4, hasMore: true, items: rows });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('FROM report_documents'),
      [context.userId, 'ready', 2, 4],
    );
  });

  it('routes adminData devices to the device table with search and device filters', async () => {
    const rows = [{ id: 'device-1', deviceName: 'Workstation', status: 'online' }];
    const { service, database } = createService(async (sql) => {
      expect(sql).toContain('FROM devices');
      expect(sql).toContain('client_device_id ILIKE $2');
      return { rows };
    });

    const result = await service.adminData(
      'devices',
      { q: 'work', deviceId: context.deviceId, limit: '1', offset: '3' },
      context,
    );

    expect(result).toEqual({ limit: 1, offset: 3, hasMore: true, items: rows });
    expect(database.query).toHaveBeenCalledWith(expect.any(String), [
      context.userId,
      '%work%',
      context.deviceId,
      1,
      3,
    ]);
  });

  it('queries folders and files with the same search and pagination inputs', async () => {
    const folders = [{ id: 'folder-1', displayName: 'Specs' }];
    const files = [{ id: 'file-1', displayName: 'Plan.pdf' }];
    const { service, database } = createService(async (sql) => {
      if (sql.includes('FROM file_folders')) {
        return { rows: folders };
      }
      if (sql.includes('FROM file_items fi')) {
        return { rows: files };
      }
      return { rows: [] };
    });

    await expect(service.files({ q: ' plan ', limit: '5', offset: '10' }, context)).resolves.toEqual({
      limit: 5,
      offset: 10,
      folders,
      files,
    });
    expect(database.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('FROM file_folders'),
      [context.userId, '%plan%', 5, 10],
    );
    expect(database.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('FROM file_items fi'),
      [context.userId, '%plan%', 5, 10],
    );
  });

  it('returns settings metadata around remote configs', async () => {
    const configs = [{ configKey: 'sync.maxBatch', configValue: { size: 50 } }];
    const { service, database } = createService(async () => ({ rows: configs }));

    const result = await service.adminSettings(context);

    expect(result.configs).toEqual(configs);
    expect(result.scopes).toContain('sync.policy');
    expect(result.deviceLocalPrefixes).toContain('kopia.local.');
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('FROM admin_remote_configs'),
      [context.userId],
    );
  });

  it('upserts jobs in a transaction and records an admin audit entry', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-02-03T04:05:06.000Z'));
    const { service, database, transactionClient } = createService();
    transactionClient.query.mockResolvedValueOnce({
      rows: [{ id: 'job-row', jobKey: 'sync.retry', status: 'queued', metadata: { priority: 'high' } }],
    });

    const result = await service.upsertJob(
      'sync.retry',
      {
        jobType: ' maintenance ',
        status: ' queued ',
        nextRunAt: '2026-03-04T05:06:07.000Z',
        lastError: ' previous failure ',
        metadata: { priority: 'high' },
      },
      context,
    );

    expect(result).toEqual({
      ok: true,
      job: { id: 'job-row', jobKey: 'sync.retry', status: 'queued', metadata: { priority: 'high' } },
    });
    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('INSERT INTO server_jobs'),
      [
        context.userId,
        'sync.retry',
        'maintenance',
        'queued',
        new Date('2026-03-04T05:06:07.000Z'),
        'previous failure',
        JSON.stringify({ priority: 'high' }),
      ],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        context.userId,
        context.deviceId,
        'admin',
        'admin.job.upsert',
        'admin',
        null,
        'admin.job.upsert',
        JSON.stringify({ jobKey: 'sync.retry' }),
      ],
    );
  });

  it('uses default job status and remote config values when optional admin inputs are blank', async () => {
    const job = { id: 'job-default', jobKey: 'manual.cleanup', status: 'idle', metadata: {} };
    const config = {
      id: 'config-default',
      configKey: 'display.theme',
      scope: 'user.preference',
      isSensitive: false,
      version: 1,
    };
    const { service, transactionClient } = createService();
    transactionClient.query.mockResolvedValueOnce({ rows: [job] });

    await expect(service.upsertJob('manual.cleanup', {}, context)).resolves.toEqual({
      ok: true,
      job,
    });
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('INSERT INTO server_jobs'),
      [
        context.userId,
        'manual.cleanup',
        'manual',
        'idle',
        null,
        null,
        JSON.stringify({}),
      ],
    );

    transactionClient.query.mockResolvedValueOnce({ rows: [config] });
    await expect(service.upsertRemoteConfig('display.theme', {}, context)).resolves.toEqual({
      ok: true,
      config,
    });
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining('INSERT INTO admin_remote_configs'),
      [
        context.userId,
        'display.theme',
        JSON.stringify({}),
        'user.preference',
        null,
        false,
      ],
    );
  });

  it('does not record object change or audit rows when updateObject finds no object', async () => {
    const { service, transactionClient } = createService();
    transactionClient.query.mockResolvedValueOnce({ rows: [] });

    await expect(
      service.updateObject('missing-object', { payload: { title: 'Draft' }, deleted: false }, context),
    ).resolves.toEqual({ ok: false, object: null });
    expect(transactionClient.query).toHaveBeenCalledTimes(1);
    expect(transactionClient.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE sync_objects'),
      [
        context.userId,
        'missing-object',
        false,
        JSON.stringify({ title: 'Draft' }),
        false,
        context.deviceId,
      ],
    );
  });

  it('records sync_changes and audit metadata for deleted object updates', async () => {
    const { service, transactionClient } = createService();
    transactionClient.query.mockResolvedValueOnce({
      rows: [
        {
          id: 'object-1',
          object_type: 'task_item',
          payload: { title: 'Done' },
          server_version: 12,
        },
      ],
    });

    const result = await service.updateObject(
      'object-1',
      { mode: 'replace', payload: { title: 'Done' }, deleted: true },
      context,
    );

    expect(result.ok).toBe(true);
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO sync_changes'),
      [
        context.userId,
        context.deviceId,
        'object-1',
        'task_item',
        'delete',
        12,
        JSON.stringify({ title: 'Done' }),
      ],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([
        context.userId,
        context.deviceId,
        'admin',
        'admin.object.update',
        JSON.stringify({ objectId: 'object-1', replace: true, deleted: true }),
      ]),
    );
  });

  it('records object upserts when deleted is omitted', async () => {
    const { service, transactionClient } = createService();
    transactionClient.query.mockResolvedValueOnce({
      rows: [
        {
          id: 'object-2',
          object_type: 'task_item',
          payload: { title: 'Open' },
          server_version: 13,
        },
      ],
    });

    await expect(
      service.updateObject('object-2', { payload: { title: 'Open' } }, context),
    ).resolves.toMatchObject({
      ok: true,
      object: { id: 'object-2' },
    });
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('UPDATE sync_objects'),
      [
        context.userId,
        'object-2',
        false,
        JSON.stringify({ title: 'Open' }),
        undefined,
        context.deviceId,
      ],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO sync_changes'),
      [
        context.userId,
        context.deviceId,
        'object-2',
        'task_item',
        'upsert',
        13,
        JSON.stringify({ title: 'Open' }),
      ],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      3,
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([
        'admin.object.update',
        JSON.stringify({ objectId: 'object-2', replace: false }),
      ]),
    );
  });

  it('rejects read-only adminData updates and audits the attempt', async () => {
    const { service, database } = createService();

    await expect(
      service.updateAdminData('model-runs', 'run-1', { status: 'archived' }, context),
    ).resolves.toEqual({
      ok: false,
      domain: 'model-runs',
      id: 'run-1',
      error: 'This domain is read-only in the current admin console.',
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        context.userId,
        context.deviceId,
        'admin.data.update.rejected',
        'admin',
        'run-1',
        'admin.data.update.rejected',
        JSON.stringify({
          domain: 'model-runs',
          targetId: 'run-1',
          reason: 'No controlled writer for this domain yet',
        }),
      ],
    );
  });

  it('prepares operations with an audit token and validates confirmation tokens', async () => {
    const { service, database } = createService();

    const prepared = await service.prepareOperation(
      'run_job',
      { jobKey: 'daily-report', dryRun: false },
      context,
    );
    const rejected = await service.confirmOperation('run_job', {}, context);
    const confirmed = await service.confirmOperation(
      'run_job',
      { confirmationToken: ' confirm-123 ', reason: 'operator requested' },
      context,
    );

    expect(prepared).toEqual({
      operationKey: 'run_job',
      dryRun: false,
      confirmationToken: '00000000-0000-4000-8000-00000000feed',
      impact: {
        risk: 'medium',
        summary: expect.any(String),
        jobKey: 'daily-report',
      },
      requiresConfirmation: true,
    });
    expect(rejected).toEqual({
      ok: false,
      operationKey: 'run_job',
      error: 'confirmationToken is required',
    });
    expect(confirmed).toEqual({
      ok: true,
      operationKey: 'run_job',
      status: 'accepted_for_manual_or_background_execution',
    });
    expect(database.query).toHaveBeenCalledTimes(2);
    expect(database.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([
        'admin.operation.prepare',
        'admin_operation',
        'run_job',
        expect.stringContaining('"confirmationToken":"00000000-0000-4000-8000-00000000feed"'),
      ]),
    );
    expect(database.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([
        'admin.operation.confirm',
        'admin_operation',
        'run_job',
        expect.stringContaining('"confirmationToken":"confirm-123"'),
      ]),
    );
  });

  it('aggregates dashboard pending counts from overview, audit logs, and failed jobs', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-04-05T06:07:08.000Z'));
    const { service } = createService();
    vi.spyOn(service, 'overview').mockResolvedValue({
      conflictCounts: { open: 3 },
      draftCounts: { pending_review: 2 },
      pushCounts: { failed: 1 },
    } as never);
    vi.spyOn(service, 'syncHealth').mockResolvedValue({ devices: [] } as never);
    vi.spyOn(service, 'auditLogs').mockResolvedValue({
      items: [{ id: 'audit-1' }],
    } as never);
    vi.spyOn(service, 'jobs').mockResolvedValue({
      jobs: [
        { id: 'job-1', status: 'failed' },
        { id: 'job-2', status: 'idle' },
      ],
    } as never);

    await expect(service.dashboard(context)).resolves.toEqual({
      generatedAt: '2026-04-05T06:07:08.000Z',
      overview: {
        conflictCounts: { open: 3 },
        draftCounts: { pending_review: 2 },
        pushCounts: { failed: 1 },
      },
      syncHealth: { devices: [] },
      recentAuditLogs: [{ id: 'audit-1' }],
      failedJobs: [{ id: 'job-1', status: 'failed' }],
      pending: {
        conflicts: 3,
        aiDrafts: 2,
        failedPushes: 1,
        failedJobs: 1,
      },
    });
    expect(service.auditLogs).toHaveBeenCalledWith({ limit: '8' }, context);
  });

  it('defaults dashboard pending counts when overview buckets are absent', async () => {
    const { service } = createService();
    vi.spyOn(service, 'overview').mockResolvedValue({} as never);
    vi.spyOn(service, 'syncHealth').mockResolvedValue({ devices: [] } as never);
    vi.spyOn(service, 'auditLogs').mockResolvedValue({ items: [] } as never);
    vi.spyOn(service, 'jobs').mockResolvedValue({ jobs: [] } as never);

    await expect(service.dashboard(context)).resolves.toMatchObject({
      failedJobs: [],
      pending: {
        conflicts: 0,
        aiDrafts: 0,
        failedPushes: 0,
        failedJobs: 0,
      },
    });
  });

  it('returns an error shape for unknown adminData domains without querying tables', async () => {
    const { service, database, devices } = createService();

    await expect(service.adminData('not-a-domain', {}, context)).resolves.toEqual({
      domain: 'not-a-domain',
      items: [],
      error: 'Unknown admin data domain',
    });
    expect(devices.ensureUser).not.toHaveBeenCalled();
    expect(database.query).not.toHaveBeenCalled();
  });

  it('aggregates overview counts and falls back to a zero sync cursor', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-02T03:04:05.000Z'));
    const { service, database } = createService(async (sql) => {
      if (sql.includes('FROM sync_objects') && sql.includes('GROUP BY object_type')) {
        return { rows: [{ name: 'task_item', count: '2' }] };
      }
      if (sql.includes('CASE') && sql.includes('FROM devices')) {
        return {
          rows: [
            { name: 'online', count: '1' },
            { name: 'offline', count: 3 },
          ],
        };
      }
      if (sql.includes('FROM sync_conflicts')) {
        return { rows: [{ name: 'open', count: '4' }] };
      }
      if (sql.includes('FROM audit_logs') && sql.includes('last_24h')) {
        return { rows: [{ name: 'last_24h', count: '5' }] };
      }
      if (sql.includes('FROM report_documents')) {
        return { rows: [{ name: 'ready', count: '6' }] };
      }
      if (sql.includes('FROM report_push_deliveries')) {
        return { rows: [{ name: 'failed', count: '7' }] };
      }
      if (sql.includes('FROM file_folders') && sql.includes('file_transfer_sessions')) {
        return {
          rows: [
            {
              folders: '1',
              files: 2,
              links: '3',
              versions: '4',
              roots: '5',
              nodes: '6',
              transfers: '7',
            },
          ],
        };
      }
      if (sql.includes('FROM outlook_object_mappings')) {
        return { rows: [{ name: 'synced', count: '8' }] };
      }
      if (sql.includes('FROM server_jobs')) {
        return { rows: [{ name: 'failed', count: '9' }] };
      }
      if (sql.includes('COUNT(*)::int AS count FROM admin_remote_configs')) {
        return { rows: [{ count: '10' }] };
      }
      if (sql.includes('FROM ai_operation_drafts')) {
        return { rows: [{ name: 'pending_review', count: '11' }] };
      }
      if (sql.includes('MAX(id)')) {
        return { rows: [] };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    });

    await expect(service.overview(context)).resolves.toEqual({
      phase: 'p11',
      generatedAt: '2026-01-02T03:04:05.000Z',
      objectCounts: { task_item: 2 },
      deviceCounts: { online: 1, offline: 3 },
      conflictCounts: { open: 4 },
      auditCounts: { last_24h: 5 },
      reportCounts: { ready: 6 },
      pushCounts: { failed: 7 },
      fileCounts: {
        folders: 1,
        files: 2,
        links: 3,
        versions: 4,
        roots: 5,
        nodes: 6,
        transfers: 7,
      },
      outlookCounts: { synced: 8 },
      jobCounts: { failed: 9 },
      configCount: 10,
      draftCounts: { pending_review: 11 },
      latestChangeId: '0',
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('COUNT(*)::int AS count FROM admin_remote_configs'),
      [context.userId],
    );
  });

  it('defaults overview aggregate buckets when count queries return no rows', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-01-02T03:04:05.000Z'));
    const { service } = createService(async () => ({ rows: [] }));

    await expect(service.overview(context)).resolves.toMatchObject({
      objectCounts: {},
      deviceCounts: {},
      conflictCounts: {},
      auditCounts: {},
      reportCounts: {},
      pushCounts: {},
      fileCounts: {
        folders: 0,
        files: 0,
        links: 0,
        versions: 0,
        roots: 0,
        nodes: 0,
        transfers: 0,
      },
      outlookCounts: {},
      jobCounts: {},
      configCount: 0,
      draftCounts: {},
      latestChangeId: '0',
    });
  });

  it('returns sync health devices plus mutation and conflict count maps', async () => {
    const devices = [{ deviceId: context.deviceId, deviceName: 'Desktop', status: 'online' }];
    const { service, database } = createService(async (sql) => {
      if (sql.includes('FROM devices d') && sql.includes('LEFT JOIN sync_cursors')) {
        return { rows: devices };
      }
      if (sql.includes('FROM sync_mutations')) {
        return {
          rows: [
            { name: 'applied', count: '3' },
            { name: 'unknown', count: '2' },
          ],
        };
      }
      if (sql.includes('FROM sync_conflicts')) {
        return { rows: [{ name: null, count: '1' }] };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    });

    await expect(service.syncHealth(context)).resolves.toEqual({
      devices,
      recentMutationResults: { applied: 3, unknown: 2 },
      conflictStatus: { unknown: 1 },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('LEFT JOIN sync_cursors'),
      [context.userId],
    );
  });

  it('delegates device history and online summary to DevicesService', async () => {
    const { service, devices } = createService();
    devices.connectionHistory.mockResolvedValue({ events: [{ status: 'connected' }] });
    devices.onlineSummary.mockResolvedValue({ online: 1, total: 2 });

    await expect(service.deviceConnectionHistory(context.deviceId, context)).resolves.toEqual({
      events: [{ status: 'connected' }],
    });
    await expect(service.deviceOnlineSummary(context)).resolves.toEqual({ online: 1, total: 2 });
    expect(devices.connectionHistory).toHaveBeenCalledWith(context.deviceId, context);
    expect(devices.onlineSummary).toHaveBeenCalledWith(context);
  });

  it('summarizes newInfo using a parsed since date and filtered device id', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-05-01T12:00:00.000Z'));
    const { service, database } = createService(async (sql) => {
      expect(sql).toContain('FROM sync_changes');
      return {
        rows: [
          {
            syncChanges: '2',
            syncMutations: 3,
            conflicts: '4',
            trackingBatches: '0',
            fileOperations: '5',
            auditLogs: undefined,
          },
        ],
      };
    });

    await expect(
      service.newInfo(
        { since: '2026-05-01T11:30:00.000Z', deviceId: context.deviceId },
        context,
      ),
    ).resolves.toEqual({
      since: '2026-05-01T11:30:00.000Z',
      generatedAt: '2026-05-01T12:00:00.000Z',
      deviceId: context.deviceId,
      total: 14,
      sections: {
        syncChanges: 2,
        syncMutations: 3,
        conflicts: 4,
        trackingBatches: 0,
        fileOperations: 5,
        auditLogs: 0,
      },
    });
    expect(database.query).toHaveBeenCalledWith(expect.any(String), [
      context.userId,
      new Date('2026-05-01T11:30:00.000Z'),
      context.deviceId,
    ]);
  });

  it('defaults newInfo to a fifteen minute all-device window when since is invalid', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-05-01T12:00:00.000Z'));
    const { service, database } = createService(async () => ({ rows: [{}] }));

    await expect(service.newInfo({ since: 'not-a-date', deviceId: 'all' }, context)).resolves.toMatchObject({
      since: '2026-05-01T11:45:00.000Z',
      deviceId: 'all',
      total: 0,
    });
    expect(database.query).toHaveBeenCalledWith(expect.any(String), [
      context.userId,
      new Date('2026-05-01T11:45:00.000Z'),
      null,
    ]);
  });

  it('summarizes empty newInfo query results as zero sections', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-05-01T12:00:00.000Z'));
    const { service } = createService(async () => ({ rows: [] }));

    await expect(service.newInfo({ since: '2026-05-01T11:50:00.000Z' }, context)).resolves.toMatchObject({
      since: '2026-05-01T11:50:00.000Z',
      deviceId: 'all',
      total: 0,
      sections: {
        syncChanges: 0,
        syncMutations: 0,
        conflicts: 0,
        trackingBatches: 0,
        fileOperations: 0,
        auditLogs: 0,
      },
    });
  });

  it('lists objects with domain type aliases, explicit filter, search, deleted flag, and pagination', async () => {
    const rows = [{ id: 'object-1', objectType: 'task_item' }];
    const { service, database } = createService(async (sql) => {
      expect(sql).toContain('FROM sync_objects');
      return { rows };
    });

    await expect(
      service.objects(
        {
          domain: 'tasks',
          objectType: 'task_item',
          q: ' alpha ',
          includeDeleted: 'true',
          limit: '1',
          offset: '2',
        },
        context,
      ),
    ).resolves.toEqual({
      domain: 'tasks',
      objectTypes: expect.arrayContaining(['task_item', 'task', 'tasks', 'task_items']),
      limit: 1,
      offset: 2,
      hasMore: true,
      items: rows,
    });
    expect(database.query).toHaveBeenCalledWith(expect.any(String), [
      context.userId,
      expect.arrayContaining(['task_item', 'task', 'tasks', 'task_items']),
      'task_item',
      '%alpha%',
      true,
      1,
      2,
    ]);
  });

  it('uses null filters and excludes deleted rows for all-domain object listings', async () => {
    const { service, database } = createService();

    await expect(service.objects({ q: '   ' }, context)).resolves.toMatchObject({
      domain: 'all',
      objectTypes: [],
      limit: 80,
      offset: 0,
      hasMore: false,
      items: [],
    });
    expect(database.query).toHaveBeenCalledWith(expect.any(String), [
      context.userId,
      null,
      null,
      null,
      false,
      80,
      0,
    ]);
  });

  it('uses null object filters for unknown object-listing domains', async () => {
    const { service, database } = createService();

    await expect(service.objects({ domain: 'legacy-custom' }, context)).resolves.toMatchObject({
      domain: 'legacy-custom',
      objectTypes: [],
      items: [],
    });
    expect(database.query).toHaveBeenCalledWith(expect.any(String), [
      context.userId,
      null,
      null,
      null,
      false,
      80,
      0,
    ]);
  });

  it('lists actual records with normalized status search and pagination', async () => {
    const rows = [
      { id: 'actual-1', title: 'Review notes', status: 'confirmed' },
      { id: 'actual-2', title: 'Review notes 2', status: 'confirmed' },
      { id: 'actual-3', title: 'Review notes 3', status: 'confirmed' },
    ];
    const { service, database } = createService(async (sql) => {
      expect(sql).toContain('FROM actual_activity_logs');
      return { rows };
    });

    await expect(
      service.actualRecords({ status: ' confirmed ', q: ' review ', limit: '3', offset: '1' }, context),
    ).resolves.toEqual({ limit: 3, offset: 1, hasMore: true, items: rows });
    expect(database.query).toHaveBeenCalledWith(expect.any(String), [
      context.userId,
      'confirmed',
      '%review%',
      3,
      1,
    ]);
  });

  it('updates actual records and records an audit entry even when no row is returned', async () => {
    const { service, transactionClient } = createService();
    transactionClient.query.mockResolvedValueOnce({ rows: [] });

    await expect(
      service.updateActualRecord(
        'actual-missing',
        { title: '  Focus ', status: ' confirmed ', note: ' kept ', metadata: { source: 'admin' } },
        context,
      ),
    ).resolves.toEqual({ ok: false, actualRecord: null });
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('UPDATE actual_activity_logs'),
      [
        context.userId,
        'actual-missing',
        'Focus',
        'confirmed',
        'kept',
        JSON.stringify({ source: 'admin' }),
      ],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        context.userId,
        context.deviceId,
        'admin',
        'admin.actual.update',
        'admin',
        null,
        'admin.actual.update',
        JSON.stringify({ actualId: 'actual-missing' }),
      ],
    );
  });

  it('updates files with cleaned editable fields and audits the change', async () => {
    const row = {
      id: 'file-1',
      displayName: 'Plan.md',
      mimeType: 'text/markdown',
      remoteId: 'remote-1',
    };
    const { service, transactionClient } = createService();
    transactionClient.query.mockResolvedValueOnce({ rows: [row] });

    await expect(
      service.updateFile(
        'file-1',
        { displayName: ' Plan.md ', mimeType: ' text/markdown ', remoteId: ' remote-1 ' },
        context,
      ),
    ).resolves.toEqual({ ok: true, file: row });
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('UPDATE file_items'),
      [context.userId, 'file-1', 'Plan.md', 'text/markdown', 'remote-1'],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining(['admin.file.update', JSON.stringify({ fileId: 'file-1' })]),
    );
  });

  it('filters conflicts by a concrete device id and treats all as no device filter', async () => {
    const rows = [{ conflictId: 'conflict-1', status: 'open' }];
    const { service, database } = createService(async (sql) => {
      expect(sql).toContain('FROM sync_conflicts c');
      return { rows };
    });

    await expect(service.conflicts({ deviceId: context.deviceId }, context)).resolves.toEqual({
      conflicts: rows,
    });
    await expect(service.conflicts({ deviceId: 'all' }, context)).resolves.toEqual({
      conflicts: rows,
    });
    expect(database.query).toHaveBeenNthCalledWith(1, expect.any(String), [
      context.userId,
      context.deviceId,
    ]);
    expect(database.query).toHaveBeenNthCalledWith(2, expect.any(String), [context.userId, null]);
  });

  it('returns outlook mappings with status summary counts', async () => {
    const mappings = [{ id: 'map-1', syncState: 'synced' }];
    const { service, database } = createService(async (sql) => {
      if (sql.includes('SELECT') && sql.includes('id::text AS id') && sql.includes('FROM outlook_object_mappings')) {
        return { rows: mappings };
      }
      if (sql.includes('WITH source') && sql.includes('outlook_object_mappings')) {
        return { rows: [{ name: 'synced', count: '2' }] };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    });

    await expect(service.outlook(context)).resolves.toEqual({
      summary: { synced: 2 },
      mappings,
    });
    expect(database.query).toHaveBeenCalledTimes(2);
  });

  it('lists push deliveries and AI drafts with status filters and hasMore', async () => {
    const pushRows = [{ id: 'push-1', status: 'failed' }];
    const draftRows = [
      { id: 'draft-1', status: 'pending_review' },
      { id: 'draft-2', status: 'pending_review' },
    ];
    const { service, database } = createService(async (sql) => {
      if (sql.includes('FROM report_push_deliveries')) {
        return { rows: pushRows };
      }
      if (sql.includes('FROM ai_operation_drafts')) {
        return { rows: draftRows };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    });

    await expect(service.pushDeliveries({ status: ' failed ', limit: '1' }, context)).resolves.toEqual({
      limit: 1,
      offset: 0,
      hasMore: true,
      items: pushRows,
    });
    await expect(service.aiDrafts({ status: ' pending_review ', limit: '2', offset: '9' }, context)).resolves.toEqual({
      limit: 2,
      offset: 9,
      hasMore: true,
      items: draftRows,
    });
    expect(database.query).toHaveBeenNthCalledWith(1, expect.stringContaining('FROM report_push_deliveries'), [
      context.userId,
      'failed',
      1,
      0,
    ]);
    expect(database.query).toHaveBeenNthCalledWith(2, expect.stringContaining('FROM ai_operation_drafts'), [
      context.userId,
      'pending_review',
      2,
      9,
    ]);
  });

  it('reviews AI drafts transactionally and records status in audit details', async () => {
    const row = { id: 'draft-1', status: 'approved', reviewNote: 'looks good' };
    const { service, transactionClient } = createService();
    transactionClient.query.mockResolvedValueOnce({ rows: [row] });

    await expect(
      service.updateAiDraft('draft-1', { status: ' approved ', reviewNote: ' looks good ' }, context),
    ).resolves.toEqual({ ok: true, draft: row });
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('UPDATE ai_operation_drafts'),
      [context.userId, 'draft-1', 'approved', 'looks good'],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([
        'admin.ai_draft.review',
        JSON.stringify({ draftId: 'draft-1', status: 'approved' }),
      ]),
    );
  });

  it('returns a false AI draft review when the update returns no row', async () => {
    const { service, transactionClient } = createService();
    transactionClient.query.mockResolvedValueOnce({ rows: [] });

    await expect(service.updateAiDraft('missing-draft', { status: ' approved ' }, context)).resolves.toEqual({
      ok: false,
      draft: null,
    });
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('UPDATE ai_operation_drafts'),
      [context.userId, 'missing-draft', 'approved', null],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining(['admin.ai_draft.review']),
    );
  });

  it('lists jobs and remote configs for the current user', async () => {
    const jobs = [{ id: 'job-1', jobKey: 'nightly', status: 'idle' }];
    const configs = [{ id: 'config-1', configKey: 'sync.maxBatch', configValue: { value: 20 } }];
    const { service, database } = createService(async (sql) => {
      if (sql.includes('FROM server_jobs')) {
        return { rows: jobs };
      }
      if (sql.includes('FROM admin_remote_configs')) {
        return { rows: configs };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    });

    await expect(service.jobs(context)).resolves.toEqual({ jobs });
    await expect(service.remoteConfigs(context)).resolves.toEqual({ configs });
    expect(database.query).toHaveBeenNthCalledWith(1, expect.stringContaining('FROM server_jobs'), [
      context.userId,
    ]);
    expect(database.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('CASE WHEN is_sensitive'),
      [context.userId],
    );
  });

  it('upserts remote config values using configValue or value payloads and audits sensitivity', async () => {
    const row = {
      id: 'config-1',
      configKey: 'sync.policy',
      scope: 'sync.policy',
      isSensitive: true,
      version: 3,
    };
    const { service, transactionClient } = createService();
    transactionClient.query.mockResolvedValueOnce({ rows: [row] });

    await expect(
      service.upsertRemoteConfig(
        'sync.policy',
        {
          value: { retry: 3 },
          scope: ' sync.policy ',
          description: ' retry settings ',
          isSensitive: true,
        },
        context,
      ),
    ).resolves.toEqual({ ok: true, config: row });
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('INSERT INTO admin_remote_configs'),
      [
        context.userId,
        'sync.policy',
        JSON.stringify({ retry: 3 }),
        'sync.policy',
        'retry settings',
        true,
      ],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([
        'admin.remote_config.upsert',
        JSON.stringify({ configKey: 'sync.policy', isSensitive: true }),
      ]),
    );
  });

  it('returns admin data details with item row and related audit log lookup', async () => {
    const item = { id: 'object-1', payload: { title: 'Plan' } };
    const auditRows = [{ id: 'audit-1', action: 'admin.object.update' }];
    const { service, database } = createService(async (sql) => {
      if (sql.includes('FROM sync_objects')) {
        return { rows: [item] };
      }
      if (sql.includes('FROM audit_logs')) {
        return { rows: auditRows };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    });

    await expect(service.adminDataDetail('objects', 'object-1', context)).resolves.toEqual({
      domain: 'objects',
      id: 'object-1',
      item,
      auditLogs: auditRows,
    });
    expect(database.query).toHaveBeenNthCalledWith(
      1,
      'SELECT * FROM sync_objects WHERE user_id = $1 AND id::text = $2 LIMIT 1',
      [context.userId, 'object-1'],
    );
    expect(database.query).toHaveBeenNthCalledWith(2, expect.stringContaining('metadata::text ILIKE $3'), [
      context.userId,
      'object-1',
      '%object-1%',
    ]);
  });

  it('returns null item details for known domains when no row exists', async () => {
    const auditRows = [{ id: 'audit-1', action: 'admin.object.update' }];
    const { service, database } = createService(async (sql) => {
      if (sql.includes('FROM sync_objects')) {
        return { rows: [] };
      }
      if (sql.includes('FROM audit_logs')) {
        return { rows: auditRows };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    });

    await expect(service.adminDataDetail('objects', 'missing-object', context)).resolves.toEqual({
      domain: 'objects',
      id: 'missing-object',
      item: null,
      auditLogs: auditRows,
    });
    expect(database.query).toHaveBeenCalledTimes(2);
  });

  it('returns an unknown-domain detail error without querying tables', async () => {
    const { service, database } = createService();

    await expect(service.adminDataDetail('nope', 'id-1', context)).resolves.toEqual({
      domain: 'nope',
      id: 'id-1',
      item: null,
      error: 'Unknown admin data domain',
    });
    expect(database.query).not.toHaveBeenCalled();
  });

  it('routes writable adminData updates to their controlled writer methods', async () => {
    const { service } = createService();
    const objectSpy = vi.spyOn(service, 'updateObject').mockResolvedValue({ ok: true, object: { id: 'obj' } } as never);
    const actualSpy = vi
      .spyOn(service, 'updateActualRecord')
      .mockResolvedValue({ ok: true, actualRecord: { id: 'actual' } } as never);
    const fileSpy = vi.spyOn(service, 'updateFile').mockResolvedValue({ ok: true, file: { id: 'file' } } as never);
    const configSpy = vi
      .spyOn(service, 'upsertRemoteConfig')
      .mockResolvedValue({ ok: true, config: { id: 'config' } } as never);

    await expect(service.updateAdminData('tasks', 'obj', { payload: { title: 'Task' } }, context)).resolves.toEqual({
      ok: true,
      object: { id: 'obj' },
    });
    await expect(service.updateAdminData('actuals', 'actual', { title: 'Actual' }, context)).resolves.toEqual({
      ok: true,
      actualRecord: { id: 'actual' },
    });
    await expect(service.updateAdminData('files', 'file', { displayName: 'File' }, context)).resolves.toEqual({
      ok: true,
      file: { id: 'file' },
    });
    await expect(service.updateAdminData('settings', 'config', { value: { x: 1 } }, context)).resolves.toEqual({
      ok: true,
      config: { id: 'config' },
    });
    expect(objectSpy).toHaveBeenCalledWith('obj', { payload: { title: 'Task' } }, context);
    expect(actualSpy).toHaveBeenCalledWith('actual', { title: 'Actual' }, context);
    expect(fileSpy).toHaveBeenCalledWith('file', { displayName: 'File' }, context);
    expect(configSpy).toHaveBeenCalledWith('config', { value: { x: 1 } }, context);
  });

  it('returns false update shapes when file updates and generic admin tables find no row or table', async () => {
    const { service, transactionClient, devices, database } = createService();
    transactionClient.query.mockResolvedValueOnce({ rows: [] });

    await expect(service.updateFile('missing-file', { displayName: ' Missing ' }, context)).resolves.toEqual({
      ok: false,
      file: null,
    });
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('UPDATE file_items'),
      [context.userId, 'missing-file', 'Missing', null, null],
    );
    expect(transactionClient.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining(['admin.file.update']),
    );

    await expect(privateApi(service).genericAdminTable('unknown-table', {}, context)).resolves.toEqual({
      domain: 'unknown-table',
      items: [],
      error: 'Unknown admin data domain',
    });
    expect(devices.ensureUser).toHaveBeenCalledWith(context.userId);
    expect(database.query).not.toHaveBeenCalled();
  });

  it('routes adminData known domains to their public listing methods', async () => {
    const { service } = createService();
    const objectsSpy = vi.spyOn(service, 'objects').mockResolvedValue({ domain: 'tasks', items: [] } as never);
    const actualSpy = vi.spyOn(service, 'actualRecords').mockResolvedValue({ items: [] } as never);
    const filesSpy = vi.spyOn(service, 'files').mockResolvedValue({ files: [], folders: [] } as never);
    const reportsSpy = vi.spyOn(service, 'reports').mockResolvedValue({ items: [] } as never);
    const pushSpy = vi.spyOn(service, 'pushDeliveries').mockResolvedValue({ items: [] } as never);
    const draftsSpy = vi.spyOn(service, 'aiDrafts').mockResolvedValue({ items: [] } as never);
    const auditSpy = vi.spyOn(service, 'auditLogs').mockResolvedValue({ items: [] } as never);
    const conflictsSpy = vi.spyOn(service, 'conflicts').mockResolvedValue({ conflicts: [] } as never);
    const configsSpy = vi.spyOn(service, 'remoteConfigs').mockResolvedValue({ configs: [] } as never);

    await expect(service.adminData('tasks', { limit: '1' }, context)).resolves.toEqual({
      domain: 'tasks',
      items: [],
    });
    await service.adminData('actuals', {}, context);
    await service.adminData('files', {}, context);
    await service.adminData('reports', {}, context);
    await service.adminData('push-deliveries', {}, context);
    await service.adminData('ai-drafts', {}, context);
    await service.adminData('audit-logs', {}, context);
    await service.adminData('conflicts', {}, context);
    await service.adminData('configs', {}, context);

    expect(objectsSpy).toHaveBeenCalledWith({ limit: '1', domain: 'tasks' }, context);
    expect(actualSpy).toHaveBeenCalledWith({}, context);
    expect(filesSpy).toHaveBeenCalledWith({}, context);
    expect(reportsSpy).toHaveBeenCalledWith({}, context);
    expect(pushSpy).toHaveBeenCalledWith({}, context);
    expect(draftsSpy).toHaveBeenCalledWith({}, context);
    expect(auditSpy).toHaveBeenCalledWith({}, context);
    expect(conflictsSpy).toHaveBeenCalledWith({}, context);
    expect(configsSpy).toHaveBeenCalledWith(context);
  });

  it('queries adminData device, sync-change, sync-mutation, and generic table domains', async () => {
    const { service, database } = createService(async (sql) => {
      if (sql.includes('FROM devices')) {
        return { rows: [{ id: 'device-1' }] };
      }
      if (sql.includes('FROM sync_changes')) {
        return { rows: [{ id: 'change-1' }] };
      }
      if (sql.includes('FROM sync_mutations')) {
        return { rows: [{ id: 'mutation-1' }] };
      }
      if (sql.includes('FROM model_runs t')) {
        return { rows: [{ id: 'run-1', status: 'failed' }] };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    });

    await expect(
      service.adminData('devices', { q: 'desk', deviceId: context.deviceId, limit: '2', offset: '1' }, context),
    ).resolves.toEqual({ limit: 2, offset: 1, hasMore: false, items: [{ id: 'device-1' }] });
    await expect(
      service.adminData('sync-changes', { objectType: ' task_item ', deviceId: 'all', limit: '2' }, context),
    ).resolves.toEqual({ limit: 2, offset: 0, hasMore: false, items: [{ id: 'change-1' }] });
    await expect(
      service.adminData('sync-mutations', { status: ' rejected ', q: 'bad', deviceId: context.deviceId }, context),
    ).resolves.toMatchObject({ items: [{ id: 'mutation-1' }] });
    await expect(
      service.adminData(
        'model-runs',
        { status: ' failed ', q: 'case', deviceId: context.deviceId, limit: '1' },
        context,
      ),
    ).resolves.toEqual({
      domain: 'model-runs',
      table: 'model_runs',
      limit: 1,
      offset: 0,
      hasMore: true,
      items: [{ id: 'run-1', status: 'failed' }],
    });
    expect(database.query).toHaveBeenNthCalledWith(1, expect.stringContaining('FROM devices'), [
      context.userId,
      '%desk%',
      context.deviceId,
      2,
      1,
    ]);
    expect(database.query).toHaveBeenNthCalledWith(2, expect.stringContaining('FROM sync_changes c'), [
      context.userId,
      'task_item',
      null,
      2,
      0,
    ]);
    expect(database.query).toHaveBeenNthCalledWith(3, expect.stringContaining('FROM sync_mutations m'), [
      context.userId,
      'rejected',
      '%bad%',
      context.deviceId,
      100,
      0,
    ]);
    expect(database.query).toHaveBeenNthCalledWith(4, expect.stringContaining('FROM model_runs t'), [
      context.userId,
      '%case%',
      'failed',
      context.deviceId,
      1,
      0,
    ]);
  });

  it('routes the first generic adminData domain labels through generic tables', async () => {
    const { service, database } = createService(async (sql) => {
      if (sql.includes('FROM activity_interpretations t')) return { rows: [{ id: 'interpretation-1' }] };
      if (sql.includes('FROM tracking_ingest_chunks t')) return { rows: [{ id: 'chunk-1' }] };
      if (sql.includes('FROM model_definitions t')) return { rows: [{ id: 'model-1' }] };
      if (sql.includes('FROM model_versions t')) return { rows: [{ id: 'version-1' }] };
      throw new Error(`Unexpected SQL: ${sql}`);
    });

    await expect(service.adminData('activity-interpretations', { limit: '1' }, context)).resolves.toMatchObject({
      domain: 'activity-interpretations',
      table: 'activity_interpretations',
      hasMore: true,
    });
    await expect(service.adminData('tracking-ingest-chunks', { limit: '1' }, context)).resolves.toMatchObject({
      domain: 'tracking-ingest-chunks',
      table: 'tracking_ingest_chunks',
      hasMore: true,
    });
    await expect(service.adminData('models', { limit: '1' }, context)).resolves.toMatchObject({
      domain: 'models',
      table: 'model_definitions',
      hasMore: true,
    });
    await expect(service.adminData('model-versions', { limit: '1' }, context)).resolves.toMatchObject({
      domain: 'model-versions',
      table: 'model_versions',
      hasMore: true,
    });
    expect(database.query).toHaveBeenCalledTimes(4);
  });

  it('queries specialized adminData operational domains with normalized filters', async () => {
    const { service, database } = createService(async (sql) => {
      if (sql.includes('FROM tracking_ingest_batches b')) return { rows: [{ id: 'batch-1' }] };
      if (sql.includes('FROM activity_segments s')) return { rows: [{ id: 'segment-1' }] };
      if (sql.includes('FROM task_work_logs w')) return { rows: [{ id: 'work-1' }] };
      if (sql.includes('FROM schedule_runs')) return { rows: [{ id: 'run-1' }] };
      if (sql.includes('FROM schedule_draft_items i')) return { rows: [{ id: 'draft-item-1' }] };
      if (sql.includes('FROM plan_deviations')) return { rows: [{ id: 'deviation-1' }] };
      if (sql.includes('FROM report_entries e')) return { rows: [{ id: 'entry-1' }] };
      if (sql.includes('FROM report_evidence_links')) return { rows: [{ id: 'evidence-1' }] };
      if (sql.includes('FROM file_operation_logs l')) return { rows: [{ id: 'operation-1' }] };
      throw new Error(`Unexpected SQL: ${sql}`);
    });

    await expect(
      service.adminData(
        'tracking-ingest-batches',
        { status: ' failed ', q: 'import', deviceId: context.deviceId, limit: '1' },
        context,
      ),
    ).resolves.toMatchObject({ domain: 'tracking-ingest-batches', hasMore: true });
    await expect(service.adminData('activity-segments', { status: ' ready ', q: 'code' }, context)).resolves.toMatchObject({
      domain: 'activity-segments',
    });
    await expect(service.adminData('task-work-logs', { status: ' accepted ', q: 'task' }, context)).resolves.toMatchObject({
      domain: 'task-work-logs',
    });
    await expect(service.adminData('schedule-runs', { status: ' confirmed ', limit: '1' }, context)).resolves.toMatchObject({
      domain: 'schedule-runs',
      hasMore: true,
    });
    await expect(service.adminData('schedule-draft-items', { status: ' pending ', q: 'Task' }, context)).resolves.toMatchObject({
      domain: 'schedule-draft-items',
    });
    await expect(service.adminData('plan-deviations', { status: ' open ', q: 'late' }, context)).resolves.toMatchObject({
      domain: 'plan-deviations',
    });
    await expect(service.adminData('report-entries', { q: 'summary' }, context)).resolves.toMatchObject({
      domain: 'report-entries',
    });
    await expect(service.adminData('report-evidence', { q: 'source' }, context)).resolves.toMatchObject({
      domain: 'report-evidence',
    });
    await expect(
      service.adminData(
        'file-operation-logs',
        { status: ' failed ', q: 'move', deviceId: context.deviceId, limit: '1' },
        context,
      ),
    ).resolves.toMatchObject({ domain: 'file-operation-logs', hasMore: true });

    expect(database.query).toHaveBeenNthCalledWith(1, expect.stringContaining('FROM tracking_ingest_batches b'), [
      context.userId,
      'failed',
      '%import%',
      context.deviceId,
      1,
      0,
    ]);
    expect(database.query).toHaveBeenNthCalledWith(3, expect.stringContaining('FROM task_work_logs w'), [
      context.userId,
      'accepted',
      '%task%',
      100,
      0,
      ['task_item'],
    ]);
    expect(database.query).toHaveBeenNthCalledWith(9, expect.stringContaining('FROM file_operation_logs l'), [
      context.userId,
      'failed',
      '%move%',
      context.deviceId,
      1,
      0,
    ]);
  });

  it('reports monitoring health with storage success and failed storage status', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-01T00:00:00.000Z'));
    process.env.KOPIA_EXE = 'kopia-test';
    const counters = { syncChanges: '2', openConflicts: '1' };
    const { service, database, storage } = createService(async (sql) => {
      if (sql === 'SELECT now() AS now') {
        return { rows: [{ now: new Date('2026-06-01T00:00:01.000Z') }] };
      }
      if (sql.includes('file_transfer_sessions')) {
        return { rows: [counters] };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    });

    await expect(service.monitoringHealth(context)).resolves.toEqual({
      generatedAt: '2026-06-01T00:00:00.000Z',
      database: { ok: true, serverTime: new Date('2026-06-01T00:00:01.000Z') },
      api: { ok: true, surface: 'admin' },
      storage: { ok: true, rootDir: 'C:/flowplan/storage', writable: true },
      kopia: {
        executable: 'kopia-test',
        status: 'checked_when_snapshot_or_restore_is_requested',
      },
      counters,
    });

    storage.status.mockRejectedValueOnce(new Error('disk unavailable'));
    await expect(service.monitoringHealth(context)).resolves.toMatchObject({
      storage: { ok: false, error: 'disk unavailable' },
    });
  });

  it('reports monitoring health defaults for optional env, empty counters, and non-error storage failures', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-01T00:00:00.000Z'));
    delete process.env.KOPIA_EXE;
    const { service, storage } = createService(async (sql) => {
      if (sql === 'SELECT now() AS now') {
        return { rows: [{ now: new Date('2026-06-01T00:00:01.000Z') }] };
      }
      if (sql.includes('file_transfer_sessions')) {
        return { rows: [] };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    });

    await expect(service.monitoringHealth(context)).resolves.toMatchObject({
      kopia: {
        executable: 'kopia',
        status: 'checked_when_snapshot_or_restore_is_requested',
      },
      counters: {},
    });

    storage.status.mockRejectedValueOnce('storage offline');
    await expect(service.monitoringHealth(context)).resolves.toMatchObject({
      storage: { ok: false, error: 'storage offline' },
    });
  });

  it('combines monitoring logs from audit, rejected mutations, and conflicts', async () => {
    const { service, database } = createService(async (sql) => {
      if (sql.includes('FROM sync_mutations m')) {
        return { rows: [{ id: 'mutation-1' }] };
      }
      return { rows: [] };
    });
    const auditSpy = vi.spyOn(service, 'auditLogs').mockResolvedValue({ items: [{ id: 'audit-1' }] } as never);
    const conflictsSpy = vi.spyOn(service, 'conflicts').mockResolvedValue({ conflicts: [{ conflictId: 'c1' }] } as never);

    await expect(service.monitoringLogs({ q: 'oops', limit: '10' }, context)).resolves.toEqual({
      auditLogs: [{ id: 'audit-1' }],
      failedMutations: [{ id: 'mutation-1' }],
      conflicts: [{ conflictId: 'c1' }],
    });
    expect(auditSpy).toHaveBeenCalledWith({ q: 'oops', limit: '10' }, context);
    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('FROM sync_mutations m'), [
      context.userId,
      'rejected',
      '%oops%',
      null,
      10,
      0,
    ]);
    expect(conflictsSpy).toHaveBeenCalledWith({ q: 'oops', limit: '10' }, context);
  });

  it('uses the default failed mutation limit for monitoring logs', async () => {
    const { service, database } = createService(async (sql) => {
      if (sql.includes('FROM sync_mutations m')) {
        return { rows: [] };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    });
    vi.spyOn(service, 'auditLogs').mockResolvedValue({ items: [] } as never);
    vi.spyOn(service, 'conflicts').mockResolvedValue({ conflicts: [] } as never);

    await expect(service.monitoringLogs({ q: 'oops' }, context)).resolves.toEqual({
      auditLogs: [],
      failedMutations: [],
      conflicts: [],
    });
    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('FROM sync_mutations m'), [
      context.userId,
      'rejected',
      '%oops%',
      null,
      50,
      0,
    ]);
  });

  it('monitoringJobs delegates to jobs', async () => {
    const { service } = createService();
    const jobsSpy = vi.spyOn(service, 'jobs').mockResolvedValue({ jobs: [{ id: 'job-1' }] } as never);

    await expect(service.monitoringJobs(context)).resolves.toEqual({ jobs: [{ id: 'job-1' }] });
    expect(jobsSpy).toHaveBeenCalledWith(context);
  });

  it('records admin actions with default and explicit audit targets', async () => {
    const { service, database } = createService();

    await service.recordAdminAction(context, 'admin.note', { message: 'hello' });
    await service.recordAdminAction(context, 'admin.targeted', {
      targetType: 'server_job',
      targetId: 42,
      extra: true,
    });

    expect(database.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining("VALUES ($1, $2, 'admin', $3, $4, $5, $6, $7::jsonb)"),
      [
        context.userId,
        context.deviceId,
        'admin.note',
        'admin',
        null,
        'admin.note',
        JSON.stringify({ message: 'hello' }),
      ],
    );
    expect(database.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        context.userId,
        context.deviceId,
        'admin.targeted',
        'server_job',
        '42',
        'admin.targeted',
        JSON.stringify({ targetType: 'server_job', targetId: 42, extra: true }),
      ],
    );
  });

  it('records private audit rows with explicit target metadata', async () => {
    const { service, transactionClient } = createService();

    await privateApi(service).recordAudit(
      transactionClient,
      context.userId,
      context.deviceId,
      'admin',
      'admin.targeted.private',
      { targetType: 'sync_object', targetId: 77, note: 'kept' },
    );

    expect(transactionClient.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        context.userId,
        context.deviceId,
        'admin',
        'admin.targeted.private',
        'sync_object',
        '77',
        'admin.targeted.private',
        JSON.stringify({ targetType: 'sync_object', targetId: 77, note: 'kept' }),
      ],
    );
  });

  it('returns operation impact metadata for the non-default operation types', async () => {
    const { service } = createService();

    await expect(service.prepareOperation('retry_sync', { targetId: 'device-a' }, context)).resolves.toMatchObject({
      dryRun: true,
      impact: { risk: 'medium', target: 'device-a' },
    });
    await expect(service.prepareOperation('retry_sync', { deviceId: 'device-b' }, context)).resolves.toMatchObject({
      impact: { target: 'device-b' },
    });
    await expect(service.prepareOperation('retry_sync', {}, context)).resolves.toMatchObject({
      impact: { target: 'all' },
    });
    await expect(
      service.prepareOperation('resolve_conflict', { conflictId: 'conflict-1' }, context),
    ).resolves.toMatchObject({
      impact: { risk: 'high', conflictId: 'conflict-1' },
    });
    await expect(service.prepareOperation('export_diagnostics', {}, context)).resolves.toMatchObject({
      impact: { risk: 'low' },
    });
    await expect(service.prepareOperation('unknown_op', {}, context)).resolves.toMatchObject({
      impact: { risk: 'unknown' },
    });
  });

  it('collects alert buckets from failed operational queries', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-02T03:04:05.000Z'));
    const rowsBySql = new Map<string, Record<string, unknown>[]>([
      ['tracking_ingest_batches', [{ id: 'batch-1' }]],
      ['sync_mutations', [{ mutationUid: 'mutation-1' }]],
      ['outlook_sync_runs', [{ id: 'outlook-1' }]],
      ['server_jobs', [{ id: 'job-1' }]],
      ['report_push_deliveries', [{ id: 'push-1' }]],
    ]);
    const { service, database } = createService(async (sql, params) => {
      expect(params).toEqual(['user-alerts']);
      for (const [needle, rows] of rowsBySql) {
        if (sql.includes(needle)) return { rows };
      }
      throw new Error(`Unexpected SQL: ${sql}`);
    });

    await expect(service.alerts('user-alerts')).resolves.toEqual({
      trackingFailures: [{ id: 'batch-1' }],
      syncFailures: [{ mutationUid: 'mutation-1' }],
      outlookFailures: [{ id: 'outlook-1' }],
      jobFailures: [{ id: 'job-1' }],
      pushFailures: [{ id: 'push-1' }],
      generatedAt: '2026-06-02T03:04:05.000Z',
    });
    expect(database.query).toHaveBeenCalledTimes(5);
  });

  it('rejects short env uploads before touching the filesystem', async () => {
    const { service } = createService();

    await expect(service.uploadEnv(' tiny ')).resolves.toEqual({
      ok: false,
      reason: 'Content too short',
    });
  });

  it('writes env uploads to the current working directory and backs up existing content', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-03T04:05:06.789Z'));
    const tempDir = mkdtempSync(join(tmpdir(), 'admin-service-env-'));
    tempDirs.push(tempDir);
    process.chdir(tempDir);
    writeFileSync(join(tempDir, '.env'), 'OLD_VALUE=1\n');
    const { service } = createService();

    await expect(service.uploadEnv('FLOWPLANV2_TEST_ALPHA=one\nFLOWPLANV2_TEST_BETA=two\n')).resolves.toEqual({
      ok: true,
      path: resolve(tempDir, '.env'),
      varsLoaded: 2,
      message: 'Written and 2 vars loaded. Restart server for full effect.',
    });

    expect(readFileSync(join(tempDir, '.env'), 'utf8')).toBe(
      'FLOWPLANV2_TEST_ALPHA=one\nFLOWPLANV2_TEST_BETA=two\n',
    );
    expect(process.env.FLOWPLANV2_TEST_ALPHA).toBe('one');
    expect(process.env.FLOWPLANV2_TEST_BETA).toBe('two');
    const backupName = readdirSync(tempDir).find((name) => name.startsWith('.env.backup.'));
    expect(backupName).toBeDefined();
    expect(readFileSync(join(tempDir, backupName as string), 'utf8')).toBe('OLD_VALUE=1\n');
  });

  it('writes env uploads without a backup when dotenv returns no parsed values', async () => {
    const tempDir = mkdtempSync(join(tmpdir(), 'admin-service-env-empty-'));
    tempDirs.push(tempDir);
    process.chdir(tempDir);
    const dotenv = require('dotenv') as {
      config: (options: Record<string, unknown>) => { parsed?: Record<string, string> };
    };
    const configSpy = vi.spyOn(dotenv, 'config').mockReturnValue({});
    const { service } = createService();

    await expect(service.uploadEnv('FLOWPLANV2_TEST_GAMMA=three\n')).resolves.toEqual({
      ok: true,
      path: resolve(tempDir, '.env'),
      varsLoaded: 0,
      message: 'Written and 0 vars loaded. Restart server for full effect.',
    });

    expect(readFileSync(join(tempDir, '.env'), 'utf8')).toBe('FLOWPLANV2_TEST_GAMMA=three\n');
    expect(readdirSync(tempDir).some((name) => name.startsWith('.env.backup.'))).toBe(false);
    expect(configSpy).toHaveBeenCalledWith({ path: resolve(tempDir, '.env'), override: true });
  });

  it('reports runtime environment defaults and configured env sources without leaking secrets', () => {
    const { service } = createService();
    delete process.env.FLOWPLANV2_DATABASE_URL;
    delete process.env.DATABASE_URL;
    delete process.env.FLOWPLANV2_ENCRYPTION_KEY;
    delete process.env.OUTLOOK_CONFIG_SECRET;
    delete process.env.AI_CONFIG_SECRET;
    delete process.env.DATABASE_POOL_MAX;
    delete process.env.SLOW_QUERY_THRESHOLD_MS;
    delete process.env.PORT;
    delete process.env.HOST;
    delete process.env.FLOWPLANV2_BODY_LIMIT;
    delete process.env.ADMIN_CORS_ORIGIN;
    delete process.env.FLOWPLANV2_SERVER_STORAGE_DIR;
    delete process.env.KOPIA_EXE;
    delete process.env.KOPIA_TIMEOUT_MS;

    expect(service.runtimeEnv()).toMatchObject({
      database: { urlPresent: false, poolMax: 10, slowQueryThresholdMs: 1000 },
      encryption: { keySecure: false, source: 'DATABASE_URL (fallback)' },
      jwt: { accessExpires: '24h', refreshExpires: '7d' },
      service: { port: 3202, host: '0.0.0.0', bodyLimit: '50mb', corsOrigin: '*' },
      storage: { dir: null },
      kopia: { exePath: 'kopia', timeoutMs: 120000 },
      generatedAt: expect.any(String),
    });

    process.env.FLOWPLANV2_DATABASE_URL = 'postgres://example/test';
    process.env.FLOWPLANV2_ENCRYPTION_KEY = 'secret-key';
    process.env.DATABASE_POOL_MAX = '20';
    process.env.SLOW_QUERY_THRESHOLD_MS = '2500';
    process.env.JWT_ACCESS_EXPIRES = '1h';
    process.env.JWT_REFRESH_EXPIRES = '14d';
    process.env.PORT = '3333';
    process.env.HOST = '127.0.0.1';
    process.env.FLOWPLANV2_BODY_LIMIT = '5mb';
    process.env.ADMIN_CORS_ORIGIN = 'https://admin.example';
    process.env.FLOWPLANV2_SERVER_STORAGE_DIR = 'D:/storage';
    process.env.KOPIA_EXE = 'kopia-custom';
    process.env.KOPIA_TIMEOUT_MS = '1500';

    expect(service.runtimeEnv()).toMatchObject({
      database: { urlPresent: true, poolMax: 20, slowQueryThresholdMs: 2500 },
      encryption: { keySecure: true, source: 'FLOWPLANV2_ENCRYPTION_KEY' },
      jwt: { accessExpires: '1h', refreshExpires: '14d' },
      service: { port: 3333, host: '127.0.0.1', bodyLimit: '5mb', corsOrigin: 'https://admin.example' },
      storage: { dir: 'D:/storage' },
      kopia: { exePath: 'kopia-custom', timeoutMs: 1500 },
    });

    delete process.env.FLOWPLANV2_ENCRYPTION_KEY;
    process.env.OUTLOOK_CONFIG_SECRET = 'outlook-secret';
    expect(service.runtimeEnv().encryption).toMatchObject({
      keySecure: true,
      source: 'OUTLOOK_CONFIG_SECRET',
    });

    delete process.env.OUTLOOK_CONFIG_SECRET;
    process.env.AI_CONFIG_SECRET = 'ai-secret';
    expect(service.runtimeEnv().encryption).toMatchObject({
      keySecure: true,
      source: 'AI_CONFIG_SECRET',
    });
  });
});
