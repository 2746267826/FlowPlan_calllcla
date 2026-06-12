import { UnauthorizedException } from '@nestjs/common';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { AuthService } from './auth.service';

vi.mock('node:crypto', () => ({
  randomUUID: () => '00000000-0000-4000-8000-00000000auth',
}));

const originalEnv = { ...process.env };

function createService(rows: Record<string, unknown>[] = []) {
  const database = {
    query: vi.fn(async () => ({ rows })),
  };
  const jwt = {
    sign: vi.fn((payload: Record<string, unknown>, options?: Record<string, unknown>) =>
      options?.secret ? `refresh:${payload.sub}` : `access:${payload.sub}`,
    ),
    verify: vi.fn(() => ({ sub: '00000000-0000-4000-8000-000000000001' })),
  };
  return {
    service: new AuthService(database as never, jwt as never),
    database,
    jwt,
  };
}

function privateApi(service: AuthService) {
  return service as unknown as { refreshSecret(): string };
}

describe('AuthService', () => {
  afterEach(() => {
    vi.restoreAllMocks();
    for (const key of Object.keys(process.env)) {
      if (!(key in originalEnv)) {
        delete process.env[key];
      }
    }
    Object.assign(process.env, originalEnv);
  });

  it('logs in with a valid requested user id and the default display name', async () => {
    process.env.JWT_REFRESH_SECRET = 'refresh-secret';
    const { service, database, jwt } = createService();
    const userId = '00000000-0000-4000-8000-000000000001';

    await expect(service.login({ userId })).resolves.toEqual({
      accessToken: `access:${userId}`,
      refreshToken: `refresh:${userId}`,
      user: { id: userId, displayName: 'FlowPlanV2 User' },
    });

    expect(database.query).toHaveBeenCalledWith(expect.stringContaining('INSERT INTO users'), [
      userId,
      'FlowPlanV2 User',
    ]);
    expect(jwt.sign).toHaveBeenNthCalledWith(2, { sub: userId, displayName: 'FlowPlanV2 User' }, {
      secret: 'refresh-secret',
      expiresIn: '7d',
    });
  });

  it('generates a user id when the requested id is not a uuid', async () => {
    const { service, database } = createService();

    await expect(service.login({ userId: 'not-a-uuid', displayName: 'Local User' })).resolves.toMatchObject({
      user: { id: '00000000-0000-4000-8000-00000000auth', displayName: 'Local User' },
    });

    expect(database.query).toHaveBeenCalledWith(expect.any(String), [
      '00000000-0000-4000-8000-00000000auth',
      'Local User',
    ]);
  });

  it('acknowledges logout without server-side token state', () => {
    const { service } = createService();

    expect(service.logout()).toEqual({ ok: true });
  });

  it('rejects missing, invalid, and orphaned refresh tokens', async () => {
    const missing = createService();
    await expect(missing.service.refresh({ refreshToken: '' })).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(missing.jwt.verify).not.toHaveBeenCalled();

    const invalid = createService();
    invalid.jwt.verify.mockImplementationOnce(() => {
      throw new Error('expired');
    });
    await expect(invalid.service.refresh({ refreshToken: 'bad-token' })).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(invalid.database.query).not.toHaveBeenCalled();

    const orphaned = createService([]);
    await expect(orphaned.service.refresh({ refreshToken: 'valid-but-missing-user' })).rejects.toBeInstanceOf(
      UnauthorizedException,
    );
    expect(orphaned.database.query).toHaveBeenCalledWith(
      'SELECT id, display_name FROM users WHERE id = $1 LIMIT 1',
      ['00000000-0000-4000-8000-000000000001'],
    );
  });

  it('refreshes existing users and follows the refresh secret fallback order', async () => {
    const { service, jwt } = createService([{ id: 'user-1', display_name: 'Existing User' }]);

    delete process.env.JWT_REFRESH_SECRET;
    process.env.JWT_ACCESS_SECRET = 'access-secret';
    expect(privateApi(service).refreshSecret()).toBe('access-secret');

    delete process.env.JWT_ACCESS_SECRET;
    process.env.FLOWPLANV2_DATABASE_URL = 'postgres://flowplan';
    expect(privateApi(service).refreshSecret()).toBe('postgres://flowplan');

    delete process.env.FLOWPLANV2_DATABASE_URL;
    process.env.DATABASE_URL = 'postgres://database';
    expect(privateApi(service).refreshSecret()).toBe('postgres://database');

    delete process.env.DATABASE_URL;
    expect(privateApi(service).refreshSecret()).toBe('flowplanv2-jwt-refresh-secret');

    await expect(service.refresh({ refreshToken: 'valid-token' })).resolves.toEqual({
      accessToken: 'access:00000000-0000-4000-8000-000000000001',
      refreshToken: 'refresh:00000000-0000-4000-8000-000000000001',
      user: { id: '00000000-0000-4000-8000-000000000001', displayName: 'Existing User' },
    });
    expect(jwt.verify).toHaveBeenCalledWith('valid-token', {
      secret: 'flowplanv2-jwt-refresh-secret',
    });
  });
});
