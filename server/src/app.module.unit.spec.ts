import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { ValidationPipe } from '@nestjs/common';
import {
  createAppValidationPipe,
  resolveConfigModuleEnvOptions,
  resolveJwtModuleOptions,
} from './app.module';

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

  it('points ConfigModule at the same explicit env file used by startup', () => {
    const tempRoot = resolve(
      tmpdir(),
      `flowplan-config-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    );
    const envPath = join(tempRoot, 'server', '.env');
    const previous = process.env.FLOWPLANV2_ENV_FILE;
    try {
      mkdirSync(dirname(envPath), { recursive: true });
      writeFileSync(
        envPath,
        'FLOWPLANV2_DATABASE_URL=postgres://config\n',
        'utf8',
      );
      process.env.FLOWPLANV2_ENV_FILE = envPath;

      expect(resolveConfigModuleEnvOptions()).toEqual({
        envFilePath: [resolve(envPath)],
        ignoreEnvFile: false,
      });
    } finally {
      rmSync(tempRoot, { recursive: true, force: true });
      if (previous === undefined) delete process.env.FLOWPLANV2_ENV_FILE;
      else process.env.FLOWPLANV2_ENV_FILE = previous;
    }
  });

  it('tells ConfigModule to skip env files when none are available', () => {
    const tempRoot = resolve(
      tmpdir(),
      `flowplan-empty-config-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    );
    const previous = process.env.FLOWPLANV2_ENV_FILE;
    try {
      mkdirSync(join(tempRoot, 'server'), { recursive: true });
      delete process.env.FLOWPLANV2_ENV_FILE;
      expect(
        resolveConfigModuleEnvOptions({
          cwd: tempRoot,
          sourceDir: join(
            tempRoot,
            'server',
            'dist',
            'src',
            'common',
            'config',
          ),
        }),
      ).toEqual({
        envFilePath: [],
        ignoreEnvFile: true,
      });
    } finally {
      rmSync(tempRoot, { recursive: true, force: true });
      if (previous === undefined) delete process.env.FLOWPLANV2_ENV_FILE;
      else process.env.FLOWPLANV2_ENV_FILE = previous;
    }
  });

  it('loads server env before dynamically importing Nest startup modules', () => {
    const source = readFileSync(resolve(__dirname, 'main.ts'), 'utf8');

    expect(source).toContain(
      "import { formatEnvLoadMessage, loadEnvFile } from './common/config/env-files';",
    );
    expect(source).toContain('const loadedEnv = loadEnvFile();');
    expect(source).toContain('console.log(formatEnvLoadMessage(loadedEnv));');
    expect(source).toContain("import('@nestjs/core')");
    expect(source).toContain("import('./app.bootstrap')");
    expect(source).toContain("import('./app.module')");
    expect(source).toContain("import('./common/logger/app-logger.service')");
  });

  it('does not statically import startup dependencies in main', () => {
    const source = readFileSync(resolve(__dirname, 'main.ts'), 'utf8');

    expect(source).not.toMatch(/from 'dotenv'/);
    expect(source).not.toMatch(/from 'node:fs'/);
    expect(source).not.toMatch(/from 'node:path'/);
    expect(source).not.toMatch(/from '@nestjs\/core'/);
    expect(source).not.toMatch(/from '\.\/app\.bootstrap'/);
    expect(source).not.toMatch(/from '\.\/app\.module'/);
    expect(source).not.toMatch(
      /from '\.\/common\/logger\/app-logger\.service'/,
    );
  });
});
