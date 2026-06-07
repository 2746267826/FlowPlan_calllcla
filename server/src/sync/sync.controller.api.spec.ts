import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApiTestApp } from '../common/test/api-test-app';
import {
  cleanDatabase,
  createTestDevice,
  createTestUser,
} from '../common/test/test-utils';

describe('SyncController API', () => {
  let h: Awaited<ReturnType<typeof createApiTestApp>> | undefined;
  const userId = '00000000-0000-4000-8000-000000000001';
  const deviceId = '00000000-0000-4000-8000-000000000101';

  function api() {
    if (!h) {
      throw new Error('createApiTestApp did not initialize');
    }
    return h;
  }

  beforeAll(async () => {
    h = await createApiTestApp();
  });

  afterAll(async () => {
    await h?.app.close();
  });

  beforeEach(async () => {
    await cleanDatabase(api().db);
    await createTestUser(api().db, { id: userId });
    await createTestDevice(api().db, userId, { id: deviceId });
  });

  it('POST /api/sync/push persists a mutation and returns the contract shape', async () => {
    const res = await api().request
      .post('/api/sync/push')
      .set('x-flowplanv2-user-id', userId)
      .set('x-flowplanv2-device-id', deviceId)
      .send({
        mutations: [
          {
            mutationUid: 'mut-api-1',
            objectType: 'task_item',
            localId: 'local-1',
            action: 'upsert',
            payload: { title: 'API task' },
          },
        ],
      })
      .expect(201);

    expect(res.body).toMatchObject({
      accepted: [
        {
          mutationUid: 'mut-api-1',
          objectType: 'task_item',
          localId: 'local-1',
          serverId: expect.any(String),
          serverVersion: 1,
        },
      ],
      conflicts: [],
      rejected: [],
      serverBatchId: expect.any(String),
    });
  });
});
