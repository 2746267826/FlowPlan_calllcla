import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest';
import { JwtService } from '@nestjs/jwt';
import { DatabaseService } from '../database/database.service';
import { AuthService } from './auth.service';
import { cleanDatabase } from '../common/test/test-utils';

describe('AuthService', () => {
  let db: DatabaseService;
  let service: AuthService;

  beforeAll(async () => {
    db = new DatabaseService();
    await db.onModuleInit();
    service = new AuthService(db, new JwtService({ secret: 'test-secret' }));
  });

  afterAll(async () => { await db.onModuleDestroy(); });
  beforeEach(async () => { await cleanDatabase(db); });

  it('login creates a user and returns JWT token pair', async () => {
    const result = await service.login({ displayName: 'Test' });
    expect(result.accessToken).toBeTruthy();
    expect(result.refreshToken).toBeTruthy();
    expect(result.user.displayName).toBe('Test');
    expect(result.accessToken.split('.')).toHaveLength(3); // JWT format
  });

  it('login with userId reuses existing user', async () => {
    const uuid = '10000000-2000-3000-8000-0000000000a1';
    const first = await service.login({ userId: uuid, displayName: 'Alice' });
    const second = await service.login({ userId: uuid, displayName: 'Alice2' });
    expect(second.user.id).toBe(first.user.id);
  });

  it('refresh returns valid token pair', async () => {
    const login = await service.login({ displayName: 'Refresher' });
    const result = await service.refresh({ refreshToken: login.refreshToken });
    expect(result.accessToken).toBeTruthy();
    expect(result.accessToken.split('.')).toHaveLength(3);
    expect(result.user.displayName).toBe('Refresher');
  });

  it('logout returns ok', () => {
    const result = service.logout();
    expect(result.ok).toBe(true);
  });
});
