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

  const headers = {
    'x-flowplanv2-user-id': userId,
    'x-flowplanv2-device-id': deviceId,
    'x-flowplanv2-platform': 'cross-end-api',
  };

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
});
