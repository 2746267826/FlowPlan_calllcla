import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import {
  buildEnvFileCandidates,
  formatEnvLoadMessage,
  loadEnvFile,
  resolveEnvFile,
} from './env-files';

const ENV_KEYS = [
  'FLOWPLANV2_ENV_FILE',
  'FLOWPLANV2_DATABASE_URL',
] as const;

const originalEnv = Object.fromEntries(
  ENV_KEYS.map((key) => [key, process.env[key]]),
);

function writeEnvFile(
  path: string,
  body = 'FLOWPLANV2_DATABASE_URL=postgres://file-db\n',
) {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, body, 'utf8');
}

describe('env file discovery', () => {
  let tempRoot: string;

  beforeEach(() => {
    tempRoot = resolve(
      tmpdir(),
      `flowplan-env-${Date.now()}-${Math.random().toString(16).slice(2)}`,
    );
    mkdirSync(tempRoot, { recursive: true });
    for (const key of ENV_KEYS) {
      delete process.env[key];
    }
  });

  afterEach(() => {
    rmSync(tempRoot, { recursive: true, force: true });
    for (const key of ENV_KEYS) {
      const value = originalEnv[key];
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  });

  it('prefers server .env and lists all supported project conventions', () => {
    const serverEnv = join(tempRoot, 'server', '.env');
    const serverLocal = join(tempRoot, 'server', 'flowplanv2.local.env');
    const rootLocal = join(tempRoot, 'flowplanv2.local.env');
    const rootEnv = join(tempRoot, '.env');
    writeEnvFile(rootLocal);
    writeEnvFile(rootEnv);
    writeEnvFile(serverLocal);
    writeEnvFile(serverEnv);

    const sourceDir = join(
      tempRoot,
      'server',
      'dist',
      'src',
      'common',
      'config',
    );
    const result = resolveEnvFile({ cwd: tempRoot, sourceDir });

    expect(result.selectedPath).toBe(resolve(serverEnv));
    expect(result.explicit).toBe(false);
    expect(result.candidates).toEqual(
      expect.arrayContaining([
        resolve(serverEnv),
        resolve(serverLocal),
        resolve(rootLocal),
        resolve(rootEnv),
      ]),
    );
    expect(result.candidates.indexOf(resolve(serverEnv))).toBeLessThan(
      result.candidates.indexOf(resolve(rootLocal)),
    );
  });

  it('finds root flowplanv2.local.env when server env files are absent', () => {
    const rootLocal = join(tempRoot, 'flowplanv2.local.env');
    writeEnvFile(rootLocal);

    const result = resolveEnvFile({
      cwd: join(tempRoot, 'server'),
      sourceDir: join(tempRoot, 'server', 'src', 'common', 'config'),
    });

    expect(result.selectedPath).toBe(resolve(rootLocal));
  });

  it('uses an explicit FLOWPLANV2_ENV_FILE when it exists', () => {
    const explicitPath = join(tempRoot, 'ops', 'production.env');
    writeEnvFile(explicitPath);
    process.env.FLOWPLANV2_ENV_FILE = explicitPath;

    expect(resolveEnvFile({ cwd: tempRoot }).selectedPath).toBe(
      resolve(explicitPath),
    );
    expect(resolveEnvFile({ cwd: tempRoot }).explicit).toBe(true);
  });

  it('fails clearly when FLOWPLANV2_ENV_FILE points to a missing file', () => {
    process.env.FLOWPLANV2_ENV_FILE = join(tempRoot, 'missing.env');

    expect(() => resolveEnvFile({ cwd: tempRoot })).toThrow(
      /FLOWPLANV2_ENV_FILE points to a missing file/,
    );
  });

  it('loads dotenv values without overriding existing system env vars', () => {
    const envPath = join(tempRoot, 'server', '.env');
    writeEnvFile(envPath, 'FLOWPLANV2_DATABASE_URL=postgres://file-db\n');
    process.env.FLOWPLANV2_DATABASE_URL = 'postgres://system-db';

    const result = loadEnvFile({ cwd: tempRoot });

    expect(result.selectedPath).toBe(resolve(envPath));
    expect(result.loadedVarCount).toBe(1);
    expect(process.env.FLOWPLANV2_DATABASE_URL).toBe('postgres://system-db');
  });

  it('reports system-env-only mode when no env file exists', () => {
    const result = loadEnvFile({ cwd: tempRoot });

    expect(result.selectedPath).toBeUndefined();
    expect(result.loadedVarCount).toBe(0);
    expect(formatEnvLoadMessage(result)).toContain(
      'Using system environment variables only',
    );
  });

  it('builds candidates from built dist source locations', () => {
    const sourceDir = join(
      tempRoot,
      'server',
      'dist',
      'src',
      'common',
      'config',
    );

    expect(buildEnvFileCandidates({ cwd: tempRoot, sourceDir })).toContain(
      resolve(tempRoot, 'server', '.env'),
    );
  });
});
