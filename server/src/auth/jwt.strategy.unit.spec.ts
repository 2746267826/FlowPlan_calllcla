import { describe, expect, it } from 'vitest';
import { JwtPayload, JwtStrategy, resolveJwtStrategySecret } from './jwt.strategy';

describe('JwtStrategy', () => {
  it('returns the validated payload unchanged', () => {
    const payload: JwtPayload = {
      sub: 'user-1',
      deviceId: 'device-1',
      displayName: 'User One',
      iat: 1,
      exp: 2,
    };

    expect(new JwtStrategy().validate(payload)).toBe(payload);
  });

  it('falls back through configured environment secrets', () => {
    const previous = {
      jwt: process.env.JWT_ACCESS_SECRET,
      flowplan: process.env.FLOWPLANV2_DATABASE_URL,
      database: process.env.DATABASE_URL,
    };
    try {
      delete process.env.JWT_ACCESS_SECRET;
      process.env.FLOWPLANV2_DATABASE_URL = 'flowplan-url';
      process.env.DATABASE_URL = 'database-url';

      expect(resolveJwtStrategySecret()).toBe('flowplan-url');

      process.env.JWT_ACCESS_SECRET = 'env-secret';
      expect(resolveJwtStrategySecret()).toBe('env-secret');

      delete process.env.JWT_ACCESS_SECRET;
      delete process.env.FLOWPLANV2_DATABASE_URL;
      expect(resolveJwtStrategySecret()).toBe('database-url');

      delete process.env.DATABASE_URL;
      expect(resolveJwtStrategySecret()).toBe('flowplanv2-jwt-access-secret');
    } finally {
      if (previous.jwt === undefined) delete process.env.JWT_ACCESS_SECRET;
      else process.env.JWT_ACCESS_SECRET = previous.jwt;
      if (previous.flowplan === undefined) delete process.env.FLOWPLANV2_DATABASE_URL;
      else process.env.FLOWPLANV2_DATABASE_URL = previous.flowplan;
      if (previous.database === undefined) delete process.env.DATABASE_URL;
      else process.env.DATABASE_URL = previous.database;
    }
  });
});
