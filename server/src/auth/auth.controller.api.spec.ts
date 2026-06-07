import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApiTestApp } from '../common/test/api-test-app';
import { cleanDatabase } from '../common/test/test-utils';

describe('AuthController API', () => {
  let h: Awaited<ReturnType<typeof createApiTestApp>> | undefined;

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
  });

  it('POST /api/auth/login returns a token pair and user contract', async () => {
    const res = await api().request
      .post('/api/auth/login')
      .send({ displayName: 'API User' })
      .expect(201);

    expect(res.body).toMatchObject({
      user: { displayName: 'API User' },
      accessToken: expect.any(String),
      refreshToken: expect.any(String),
    });
    expect(res.body.accessToken.split('.')).toHaveLength(3);
    expect(res.body.refreshToken.split('.')).toHaveLength(3);
  });
});
