import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApiTestApp } from '../common/test/api-test-app';
import {
  cleanDatabase,
  createTestDevice,
  createTestUser,
} from '../common/test/test-utils';

describe('CE-TASK-001 task schedule completion workflow', () => {
  let h: Awaited<ReturnType<typeof createApiTestApp>>;
  const userId = '00000000-0000-4000-8000-000000000201';
  const deviceId = '00000000-0000-4000-8000-000000000202';
  const mobileDeviceId = '00000000-0000-4000-8000-000000000203';

  const headersFor = (id: string, platform: string) => ({
    'x-flowplanv2-user-id': userId,
    'x-flowplanv2-device-id': id,
    'x-flowplanv2-platform': platform,
  });

  const headers = headersFor(deviceId, 'cross-end-api');
  const mobileHeaders = headersFor(mobileDeviceId, 'flutter-integration');

  beforeAll(async () => {
    h = await createApiTestApp();
  });

  afterAll(async () => {
    await h.app.close();
  });

  beforeEach(async () => {
    await cleanDatabase(h.db);
    await createTestUser(h.db, { id: userId });
    await createTestDevice(h.db, userId, { id: deviceId });
    await createTestDevice(h.db, userId, {
      id: mobileDeviceId,
      deviceName: 'Cross-end mobile device',
      platform: 'flutter',
    });
  });

  it('creates, schedules, completes, and exposes audit evidence', async () => {
    const task = await h.request
      .post('/api/client/tasks')
      .set(headers)
      .send({
        uid: 'ce-task-001',
        title: 'Cross-end task',
        estimatedMinutes: 45,
      });

    expect([200, 201]).toContain(task.status);
    const taskId = task.body?.item?.id ?? task.body?.id;
    expect(taskId).toBeTruthy();

    const run = await h.request
      .post('/api/scheduler/runs')
      .set(headers)
      .send({
        rangeStart: '2026-06-08T00:00:00.000Z',
        rangeEnd: '2026-06-09T00:00:00.000Z',
      });

    expect([200, 201]).toContain(run.status);

    const completion = await h.request
      .post(`/api/client/tasks/${taskId}/complete`)
      .set(headers)
      .send({ completedAt: '2026-06-08T09:00:00.000Z' });

    expect([200, 201]).toContain(completion.status);

    const audit = await h.request
      .get('/api/admin/data/audit-logs?limit=20')
      .set(headers);

    expect(audit.status).toBe(200);
    expect(JSON.stringify(audit.body).toLowerCase()).toContain('task');
  });

  it('detects and resolves an offline stale-version conflict with audit evidence', async () => {
    const created = await h.request
      .post('/api/sync/push')
      .set(headers)
      .send({
        clientBatchId: 'ce-sync-create',
        mutations: [
          {
            mutationUid: 'ce-sync-create-001',
            objectType: 'task_item',
            localId: 'local-task-ce-sync',
            uid: 'ce-sync-task',
            action: 'create',
            payload: { title: 'Cross-end task', status: 'todo' },
          },
        ],
      });

    expect(created.status).toBe(201);
    const accepted = created.body.accepted[0];
    expect(accepted.serverVersion).toBe(1);

    const serverEdit = await h.request
      .post('/api/sync/push')
      .set(headers)
      .send({
        clientBatchId: 'ce-sync-server-edit',
        mutations: [
          {
            mutationUid: 'ce-sync-server-edit-001',
            objectType: 'task_item',
            localId: 'local-task-ce-sync',
            serverId: accepted.serverId,
            uid: 'ce-sync-task',
            action: 'update',
            baseServerVersion: accepted.serverVersion,
            changedFields: ['title'],
            payload: { title: 'Cross-end task from web' },
          },
        ],
      });

    expect(serverEdit.status).toBe(201);
    expect(serverEdit.body.accepted[0].serverVersion).toBe(2);

    const staleMobileEdit = await h.request
      .post('/api/sync/push')
      .set(mobileHeaders)
      .send({
        clientBatchId: 'ce-sync-mobile-offline-edit',
        mutations: [
          {
            mutationUid: 'ce-sync-mobile-offline-001',
            objectType: 'task_item',
            localId: 'mobile-local-task-ce-sync',
            serverId: accepted.serverId,
            uid: 'ce-sync-task',
            action: 'update',
            baseServerVersion: 1,
            changedFields: ['title'],
            payload: { title: 'Cross-end task from mobile offline' },
          },
        ],
      });

    expect(staleMobileEdit.status).toBe(201);
    expect(staleMobileEdit.body.conflicts).toHaveLength(1);
    expect(staleMobileEdit.body.conflicts[0]).toMatchObject({
      mutationUid: 'ce-sync-mobile-offline-001',
      objectType: 'task_item',
      serverVersion: 2,
      fields: [
        {
          field: 'title',
          local: 'Cross-end task from mobile offline',
          server: 'Cross-end task from web',
        },
      ],
    });

    const conflictId = staleMobileEdit.body.conflicts[0].conflictId;
    const listed = await h.request.get('/api/sync/conflicts').set(mobileHeaders);
    expect(listed.status).toBe(200);
    expect(JSON.stringify(listed.body)).toContain(conflictId);

    const resolved = await h.request
      .post(`/api/sync/conflicts/${conflictId}/resolve`)
      .set(mobileHeaders)
      .send({
        strategy: 'merge',
        payload: { title: 'Cross-end task merged after offline edit' },
        note: 'CE-SYNC-001 automated merge',
      });

    expect(resolved.status).toBe(201);
    expect(resolved.body).toMatchObject({ ok: true, conflictId, strategy: 'merge' });

    const audit = await h.request
      .get('/api/admin/data/audit-logs?limit=50')
      .set(headers);

    expect(audit.status).toBe(200);
    expect(JSON.stringify(audit.body)).toContain('sync.conflict.resolve');
    expect(JSON.stringify(audit.body)).toContain(conflictId);
  });

  it('generates a report with evidence links and exposes report audit records', async () => {
    const report = await h.request
      .post('/api/reports/generate')
      .set(headers)
      .send({
        reportType: 'daily',
        date: '2026-06-08',
      });

    expect([200, 201]).toContain(report.status);
    const reportId = report.body?.report?.id;
    expect(reportId).toBeTruthy();
    expect(report.body.entries.length).toBeGreaterThan(0);
    expect(report.body.evidence.length).toBeGreaterThan(0);

    const evidence = await h.request
      .get('/api/admin/data/report-evidence?limit=20')
      .set(headers);

    expect(evidence.status).toBe(200);
    expect(JSON.stringify(evidence.body)).toContain(reportId);

    const audit = await h.request
      .get('/api/admin/data/audit-logs?limit=50')
      .set(headers);

    expect(audit.status).toBe(200);
    expect(JSON.stringify(audit.body)).toContain('report.generated');
    expect(JSON.stringify(audit.body)).toContain(reportId);
  });

  it('registers Drive root evidence and records controlled admin operation audit', async () => {
    const root = await h.request
      .post('/api/files/roots')
      .set(headers)
      .send({
        name: 'Cross End Drive Root',
        rootUri: 'C:\\FlowPlanDrive\\CrossEnd',
        providerType: 'server_storage',
        isManaged: true,
        syncPolicy: 'metadata_only',
        metadata: { acceptanceId: 'CE-FILE-001' },
      });

    expect(root.status).toBe(201);
    expect(root.body).toMatchObject({
      ok: true,
      root: {
        name: 'Cross End Drive Root',
        rootUri: 'C:\\FlowPlanDrive\\CrossEnd',
      },
    });

    const roots = await h.request.get('/api/files/drive/roots').set(headers);
    expect(roots.status).toBe(200);
    expect(JSON.stringify(roots.body)).toContain('Cross End Drive Root');

    const prepare = await h.request
      .post('/api/admin/operations/recompute-report-summary/prepare')
      .set(headers)
      .send({ dryRun: true, payload: { reportId: 'report-ce-001' } });

    expect(prepare.status).toBe(201);
    expect(prepare.body.confirmationToken).toBeTruthy();

    const confirm = await h.request
      .post('/api/admin/operations/recompute-report-summary/confirm')
      .set(headers)
      .send({
        confirmationToken: prepare.body.confirmationToken,
        reason: 'CE-AI-001 controlled acceptance operation',
      });

    expect(confirm.status).toBe(201);
    expect(confirm.body).toMatchObject({
      ok: true,
      operationKey: 'recompute-report-summary',
    });

    const audit = await h.request
      .get('/api/admin/data/audit-logs?limit=50')
      .set(headers);

    expect(audit.status).toBe(200);
    expect(JSON.stringify(audit.body)).toContain('file.root.upsert');
    expect(JSON.stringify(audit.body)).toContain('admin.operation.prepare');
    expect(JSON.stringify(audit.body)).toContain('admin.operation.confirm');
  });
});
