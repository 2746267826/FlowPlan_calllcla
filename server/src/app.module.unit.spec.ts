import { describe, expect, it } from 'vitest';
import { ValidationPipe } from '@nestjs/common';
import { createAppValidationPipe, resolveJwtModuleOptions } from './app.module';

describe('AppModule helpers', () => {
  it('creates the global validation pipe used by the Nest module', () => {
    expect(createAppValidationPipe()).toBeInstanceOf(ValidationPipe);
  });

  it('prefers configured JWT secret and expiry values', () => {
    const config = {
      get: (key: string, fallback?: string) =>
        key === 'jwtAccessSecret' ? 'configured-secret' : fallback,
    };

    expect(resolveJwtModuleOptions(config).secret).toBe('configured-secret');
    expect(resolveJwtModuleOptions(config).signOptions.expiresIn).toBe('24h');
  });

  it('falls back through environment secrets when config is absent', () => {
    const config = { get: (_key: string, fallback?: string) => fallback };
    const previous = {
      jwt: process.env.JWT_ACCESS_SECRET,
      flowplan: process.env.FLOWPLANV2_DATABASE_URL,
      database: process.env.DATABASE_URL,
    };
    try {
      delete process.env.JWT_ACCESS_SECRET;
      process.env.FLOWPLANV2_DATABASE_URL = 'flowplan-url';
      process.env.DATABASE_URL = 'database-url';

      expect(resolveJwtModuleOptions(config).secret).toBe('flowplan-url');

      process.env.JWT_ACCESS_SECRET = 'env-secret';
      expect(resolveJwtModuleOptions(config).secret).toBe('env-secret');

      delete process.env.JWT_ACCESS_SECRET;
      delete process.env.FLOWPLANV2_DATABASE_URL;
      expect(resolveJwtModuleOptions(config).secret).toBe('database-url');

      delete process.env.DATABASE_URL;
      expect(resolveJwtModuleOptions(config).secret).toBe('flowplanv2-jwt-access-secret');
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
