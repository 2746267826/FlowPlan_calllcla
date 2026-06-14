import { afterEach, describe, expect, it } from 'vitest';
import { collectProductionConfigWarnings, loadConfig } from './app-config';

const ENV_KEYS = [
  'FLOWPLANV2_DATABASE_URL',
  'DATABASE_URL',
  'PORT',
  'HOST',
  'FLOWPLANV2_BODY_LIMIT',
  'ADMIN_CORS_ORIGIN',
  'JWT_ACCESS_SECRET',
  'JWT_REFRESH_SECRET',
  'JWT_ACCESS_EXPIRES',
  'JWT_REFRESH_EXPIRES',
  'LOG_LEVEL',
  'LOG_FORMAT',
  'NODE_ENV',
  'FLOWPLANV2_ENCRYPTION_KEY',
] as const;

const originalEnv = Object.fromEntries(
  ENV_KEYS.map((key) => [key, process.env[key]]),
);

describe('loadConfig', () => {
  afterEach(() => {
    for (const key of ENV_KEYS) {
      const value = originalEnv[key];
      if (value === undefined) {
        delete process.env[key];
      } else {
        process.env[key] = value;
      }
    }
  });

  it('loads defaults from the database URL when specific overrides are absent', () => {
    for (const key of ENV_KEYS) {
      delete process.env[key];
    }
    process.env.DATABASE_URL = 'postgres://localhost/flowplantest';

    expect(loadConfig()).toMatchObject({
      port: 3202,
      host: '0.0.0.0',
      databaseUrl: 'postgres://localhost/flowplantest',
      bodyLimit: '50mb',
      corsOrigin: true,
      jwtAccessSecret: 'postgres://localhost/flowplantest',
      jwtRefreshSecret: 'postgres://localhost/flowplantest',
      jwtAccessExpires: '24h',
      jwtRefreshExpires: '7d',
      logLevel: 'debug',
      logFormat: 'dev',
    });
  });

  it('prefers explicit FlowPlanV2 environment overrides', () => {
    process.env.FLOWPLANV2_DATABASE_URL = 'postgres://flowplan';
    process.env.DATABASE_URL = 'postgres://legacy';
    process.env.PORT = '4310';
    process.env.HOST = '127.0.0.1';
    process.env.FLOWPLANV2_BODY_LIMIT = '5mb';
    process.env.ADMIN_CORS_ORIGIN = 'https://admin.example';
    process.env.JWT_ACCESS_SECRET = 'access-secret';
    process.env.JWT_REFRESH_SECRET = 'refresh-secret';
    process.env.JWT_ACCESS_EXPIRES = '15m';
    process.env.JWT_REFRESH_EXPIRES = '30d';
    process.env.LOG_LEVEL = 'warn';
    process.env.LOG_FORMAT = 'json';

    expect(loadConfig()).toEqual({
      port: 4310,
      host: '127.0.0.1',
      databaseUrl: 'postgres://flowplan',
      bodyLimit: '5mb',
      corsOrigin: 'https://admin.example',
      jwtAccessSecret: 'access-secret',
      jwtRefreshSecret: 'refresh-secret',
      jwtAccessExpires: '15m',
      jwtRefreshExpires: '30d',
      logLevel: 'warn',
      logFormat: 'json',
    });
  });

  it('keeps empty database-derived secrets when no database URL or JWT secret is configured', () => {
    for (const key of ENV_KEYS) {
      delete process.env[key];
    }

    expect(loadConfig()).toMatchObject({
      databaseUrl: '',
      jwtAccessSecret: '',
      jwtRefreshSecret: '',
    });
  });

  it('uses the access secret as the refresh secret fallback', () => {
    for (const key of ENV_KEYS) {
      delete process.env[key];
    }
    process.env.JWT_ACCESS_SECRET = 'access-only';

    expect(loadConfig()).toMatchObject({
      jwtAccessSecret: 'access-only',
      jwtRefreshSecret: 'access-only',
    });
  });

  it('does not report production warnings outside production mode', () => {
    for (const key of ENV_KEYS) {
      delete process.env[key];
    }
    process.env.NODE_ENV = 'development';

    expect(collectProductionConfigWarnings()).toEqual([]);
  });

  it('reports missing recommended production secrets and CORS origin', () => {
    for (const key of ENV_KEYS) {
      delete process.env[key];
    }
    process.env.NODE_ENV = 'production';

    expect(collectProductionConfigWarnings()).toEqual([
      'JWT_ACCESS_SECRET is not set in production; configure a dedicated access token secret.',
      'JWT_REFRESH_SECRET is not set in production; configure a dedicated refresh token secret.',
      'FLOWPLANV2_ENCRYPTION_KEY is not set in production; encrypted integrations may be unavailable.',
      'ADMIN_CORS_ORIGIN is not set in production; configure the expected admin origin.',
    ]);
  });

  it('accepts recommended production settings when all are configured', () => {
    process.env.NODE_ENV = 'production';
    process.env.JWT_ACCESS_SECRET = 'access-secret';
    process.env.JWT_REFRESH_SECRET = 'refresh-secret';
    process.env.FLOWPLANV2_ENCRYPTION_KEY = 'encryption-secret';
    process.env.ADMIN_CORS_ORIGIN = 'https://admin.example.com';

    expect(collectProductionConfigWarnings()).toEqual([]);
  });
});
