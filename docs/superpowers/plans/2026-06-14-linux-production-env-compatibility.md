# Linux Production Env Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `server` and `web_admin` run predictably in Linux production while preserving the existing Windows development startup flow.

**Architecture:** Add one focused server env discovery/loading helper and wire both startup and Nest config through it. Keep server path handling portable, surface production weak-config warnings, and let the web admin choose its API base from local storage, `VITE_API_BASE_URL`, or the current dev fallback.

**Tech Stack:** Node.js, NestJS, `@nestjs/config`, `dotenv`, Vite, React, Vitest, MSW.

---

## Scope Check

This plan implements one cohesive compatibility pass for two production surfaces:

- `server`: env discovery/loading, startup wiring, production config warnings, and Linux executable defaults.
- `web_admin`: Vite-backed API base selection and same-origin `/api` handling.

It does not change the root Windows startup scripts. It does not rewrite old deployment docs.

## File Structure

- Create `server/src/common/config/env-files.ts`
  - Owns env candidate construction, explicit override handling, dotenv loading, and startup log message formatting.
- Create `server/src/common/config/env-files.unit.spec.ts`
  - Tests candidate order, explicit override success/failure, system-env-only behavior, and dotenv non-overwrite behavior.
- Modify `server/src/app.module.ts`
  - Replaces the hard-coded `ConfigModule` env path with the shared env helper.
  - Exports `resolveConfigModuleEnvOptions()` for unit coverage.
- Modify `server/src/app.module.unit.spec.ts`
  - Adds tests that Nest config uses the same env path decision as startup.
- Modify `server/src/main.ts`
  - Loads env through the shared helper before importing Nest modules.
  - Logs selected env source with plain ASCII text.
- Modify `server/src/common/config/app-config.ts`
  - Adds `collectProductionConfigWarnings()` for production-only weak config warnings.
- Modify `server/src/common/config/app-config.unit.spec.ts`
  - Covers production warning behavior.
- Modify `server/src/files/kopia.service.unit.spec.ts`
  - Keeps explicit coverage that Linux default executable is `kopia` and Windows `kopia.exe` remains opt-in through env.
- Create `web_admin/src/app/apiBase.ts`
  - Pure API base selection helper for local storage, Vite env, and fallback.
- Create `web_admin/src/app/apiBase.test.ts`
  - Covers fallback, Vite env, local storage precedence, normalization, and `/api` same-origin behavior.
- Create `web_admin/src/vite-env.d.ts`
  - Adds Vite env typing for `VITE_API_BASE_URL`.
- Modify `web_admin/src/app/AdminApp.tsx`
  - Uses the new API base resolver for initial state.
- Modify `web_admin/src/api/adminApi.ts`
  - Extends API base normalization and URL building to avoid `/api/api/...` when the configured base is `/api`.
- Modify `web_admin/src/api/adminApi.test.ts`
  - Adds direct coverage for relative `/api` base handling.

## Task 1: Server Env Discovery And Nest Config Wiring

**Files:**
- Create: `server/src/common/config/env-files.ts`
- Create: `server/src/common/config/env-files.unit.spec.ts`
- Modify: `server/src/app.module.ts`
- Modify: `server/src/app.module.unit.spec.ts`
- Modify: `server/src/main.ts`

- [ ] **Step 1: Write failing env discovery tests**

Create `server/src/common/config/env-files.unit.spec.ts`:

```ts
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

function writeEnvFile(path: string, body = 'FLOWPLANV2_DATABASE_URL=postgres://file-db\n') {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, body, 'utf8');
}

describe('env file discovery', () => {
  let tempRoot: string;

  beforeEach(() => {
    tempRoot = resolve(tmpdir(), `flowplan-env-${Date.now()}-${Math.random().toString(16).slice(2)}`);
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

    const sourceDir = join(tempRoot, 'server', 'dist', 'src', 'common', 'config');
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

    expect(resolveEnvFile({ cwd: tempRoot }).selectedPath).toBe(resolve(explicitPath));
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
    expect(formatEnvLoadMessage(result)).toContain('Using system environment variables only');
  });

  it('builds candidates from built dist source locations', () => {
    const sourceDir = join(tempRoot, 'server', 'dist', 'src', 'common', 'config');

    expect(buildEnvFileCandidates({ cwd: tempRoot, sourceDir })).toContain(
      resolve(tempRoot, 'server', '.env'),
    );
  });
});
```

- [ ] **Step 2: Run the failing env discovery tests**

Run:

```powershell
cd server
npm run test:unit -- common/config/env-files.unit.spec.ts
```

Expected: FAIL because `server/src/common/config/env-files.ts` does not exist.

- [ ] **Step 3: Implement the env discovery helper**

Create `server/src/common/config/env-files.ts`:

```ts
import { existsSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { config as loadDotenv } from 'dotenv';

export interface EnvFileDiscoveryOptions {
  cwd?: string;
  sourceDir?: string;
  explicitPath?: string;
  exists?: (path: string) => boolean;
}

export interface EnvFileDiscoveryResult {
  selectedPath?: string;
  candidates: string[];
  explicit: boolean;
}

export interface EnvFileLoadResult extends EnvFileDiscoveryResult {
  loadedVarCount: number;
}

function unique(paths: string[]): string[] {
  return Array.from(new Set(paths.map((path) => resolve(path))));
}

export function buildEnvFileCandidates(
  options: EnvFileDiscoveryOptions = {},
): string[] {
  const cwd = resolve(options.cwd ?? process.cwd());
  const sourceDir = resolve(options.sourceDir ?? __dirname);
  const roots = unique([
    cwd,
    resolve(cwd, 'server'),
    resolve(sourceDir, '..', '..', '..'),
    resolve(sourceDir, '..', '..', '..', '..'),
    resolve(sourceDir, '..', '..', '..', '..', '..'),
  ]);
  const serverDirs = unique([
    ...roots.filter((root) => basename(root).toLowerCase() === 'server'),
    ...roots.map((root) => resolve(root, 'server')),
  ]);
  const repoDirs = unique([
    ...serverDirs.map((serverDir) => resolve(serverDir, '..')),
    ...roots.filter((root) => basename(root).toLowerCase() !== 'dist'),
  ]);

  return unique([
    ...serverDirs.flatMap((serverDir) => [
      resolve(serverDir, '.env'),
      resolve(serverDir, 'flowplanv2.local.env'),
    ]),
    ...repoDirs.flatMap((repoDir) => [
      resolve(repoDir, 'flowplanv2.local.env'),
      resolve(repoDir, '.env'),
    ]),
  ]);
}

export function resolveEnvFile(
  options: EnvFileDiscoveryOptions = {},
): EnvFileDiscoveryResult {
  const exists = options.exists ?? existsSync;
  const explicitValue =
    options.explicitPath ?? process.env.FLOWPLANV2_ENV_FILE;
  const explicitPath = explicitValue?.trim();

  if (explicitPath) {
    const selectedPath = resolve(explicitPath);
    if (!exists(selectedPath)) {
      throw new Error(
        `FLOWPLANV2_ENV_FILE points to a missing file: ${selectedPath}`,
      );
    }
    return { selectedPath, candidates: [selectedPath], explicit: true };
  }

  const candidates = buildEnvFileCandidates(options);
  return {
    selectedPath: candidates.find((candidate) => exists(candidate)),
    candidates,
    explicit: false,
  };
}

export function loadEnvFile(
  options: EnvFileDiscoveryOptions = {},
): EnvFileLoadResult {
  const discovery = resolveEnvFile(options);
  if (!discovery.selectedPath) {
    return { ...discovery, loadedVarCount: 0 };
  }

  const result = loadDotenv({
    path: discovery.selectedPath,
    override: false,
  });
  if (result.error) {
    throw result.error;
  }

  return {
    ...discovery,
    loadedVarCount: Object.keys(result.parsed ?? {}).length,
  };
}

export function formatEnvLoadMessage(result: EnvFileLoadResult): string {
  if (result.selectedPath) {
    return `[Env] Loaded ${result.loadedVarCount} vars from ${result.selectedPath}`;
  }
  return `[Env] .env not found. Searched: ${result.candidates.join(', ')}. Using system environment variables only.`;
}
```

- [ ] **Step 4: Run env discovery tests again**

Run:

```powershell
cd server
npm run test:unit -- common/config/env-files.unit.spec.ts
```

Expected: PASS.

- [ ] **Step 5: Wire `ConfigModule` through the shared helper**

Modify the imports at the top of `server/src/app.module.ts`:

```ts
import { Module, ValidationPipe } from '@nestjs/common';
import { ConfigModule, ConfigService, type ConfigModuleOptions } from '@nestjs/config';
```

Remove this import because it will no longer be used:

```ts
import { resolve } from 'node:path';
```

Add this import:

```ts
import { resolveEnvFile, type EnvFileDiscoveryOptions } from './common/config/env-files';
```

Add this exported helper above `@Module`:

```ts
export function resolveConfigModuleEnvOptions(
  options: EnvFileDiscoveryOptions = {},
): Pick<ConfigModuleOptions, 'envFilePath' | 'ignoreEnvFile'> {
  const selectedPath = resolveEnvFile(options).selectedPath;
  return selectedPath
    ? { envFilePath: [selectedPath], ignoreEnvFile: false }
    : { envFilePath: [], ignoreEnvFile: true };
}
```

Replace the current `ConfigModule.forRoot(...)` entry with:

```ts
ConfigModule.forRoot({
  isGlobal: true,
  ...resolveConfigModuleEnvOptions(),
  load: [loadConfig],
}),
```

- [ ] **Step 6: Add failing AppModule env option tests**

Modify `server/src/app.module.unit.spec.ts`.

Change the imports:

```ts
import { mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { ValidationPipe } from '@nestjs/common';
import {
  createAppValidationPipe,
  resolveConfigModuleEnvOptions,
  resolveJwtModuleOptions,
} from './app.module';
```

Add these helpers and tests inside the existing `describe('AppModule helpers', ...)` block:

```ts
  it('points ConfigModule at the same explicit env file used by startup', () => {
    const tempRoot = resolve(tmpdir(), `flowplan-config-${Date.now()}-${Math.random().toString(16).slice(2)}`);
    const envPath = join(tempRoot, 'server', '.env');
    const previous = process.env.FLOWPLANV2_ENV_FILE;
    try {
      mkdirSync(dirname(envPath), { recursive: true });
      writeFileSync(envPath, 'FLOWPLANV2_DATABASE_URL=postgres://config\n', 'utf8');
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
    const tempRoot = resolve(tmpdir(), `flowplan-empty-config-${Date.now()}-${Math.random().toString(16).slice(2)}`);
    const previous = process.env.FLOWPLANV2_ENV_FILE;
    try {
      mkdirSync(join(tempRoot, 'server'), { recursive: true });
      delete process.env.FLOWPLANV2_ENV_FILE;
      expect(
        resolveConfigModuleEnvOptions({
          cwd: tempRoot,
          sourceDir: join(tempRoot, 'server', 'dist', 'src', 'common', 'config'),
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
```

- [ ] **Step 7: Run AppModule tests**

Run:

```powershell
cd server
npm run test:unit -- app.module.unit.spec.ts
```

Expected: PASS.

- [ ] **Step 8: Load env before Nest imports in `main.ts`**

Replace the imports and top-level env loading block in `server/src/main.ts` with:

```ts
import 'reflect-metadata';

import { formatEnvLoadMessage, loadEnvFile } from './common/config/env-files';

const loadedEnv = loadEnvFile();
console.log(formatEnvLoadMessage(loadedEnv));
```

Replace the static Nest imports:

```ts
import { NestFactory } from '@nestjs/core';
import { configureApp } from './app.bootstrap';
import { AppModule } from './app.module';
import { AppLogger } from './common/logger/app-logger.service';
```

with dynamic imports inside `bootstrap()`:

```ts
async function bootstrap() {
  const [{ NestFactory }, { configureApp }, { AppModule }, { AppLogger }] =
    await Promise.all([
    import('@nestjs/core'),
    import('./app.bootstrap'),
    import('./app.module'),
    import('./common/logger/app-logger.service'),
  ]);
  const app = await NestFactory.create(AppModule, { bodyParser: false });
  configureApp(app);

  const port = Number(process.env.PORT ?? 3202);
  const host = process.env.HOST ?? '0.0.0.0';

  await app.listen(port, host);

  const logger = app.get(AppLogger);
  logger.log(`FlowPlanV2 server listening on http://${host}:${port}/api`);
  logger.log(
    `Encryption key: ${
      process.env.FLOWPLANV2_ENCRYPTION_KEY
        ? 'configured'
        : 'NOT SET - set FLOWPLANV2_ENCRYPTION_KEY in the environment'
    }`,
  );
}
```

The resulting file must not import `dotenv`, `existsSync`, `resolve`, `@nestjs/core`, `./app.bootstrap`, `./app.module`, or `./common/logger/app-logger.service` through static imports.

- [ ] **Step 9: Verify server typecheck/build for Task 1**

Run:

```powershell
cd server
npm run build
```

Expected: PASS and `dist/src/main.js` builds without TypeScript errors.

- [ ] **Step 10: Commit Task 1**

Run:

```powershell
git add server/src/common/config/env-files.ts server/src/common/config/env-files.unit.spec.ts server/src/app.module.ts server/src/app.module.unit.spec.ts server/src/main.ts
git commit -m "fix: share server env discovery"
```

Expected: commit succeeds with only Task 1 files staged.

## Task 2: Production Config Warnings And Linux Executable Defaults

**Files:**
- Modify: `server/src/common/config/app-config.ts`
- Modify: `server/src/common/config/app-config.unit.spec.ts`
- Modify: `server/src/files/kopia.service.unit.spec.ts`
- Modify: `server/src/main.ts`

- [ ] **Step 1: Add failing production warning tests**

Modify `server/src/common/config/app-config.unit.spec.ts`.

Add `NODE_ENV`, `FLOWPLANV2_ENCRYPTION_KEY`, and `ADMIN_CORS_ORIGIN` to `ENV_KEYS`:

```ts
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
```

Change the import:

```ts
import { collectProductionConfigWarnings, loadConfig } from './app-config';
```

Add these tests inside `describe('loadConfig', ...)`:

```ts
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
```

- [ ] **Step 2: Run the failing production warning tests**

Run:

```powershell
cd server
npm run test:unit -- common/config/app-config.unit.spec.ts
```

Expected: FAIL because `collectProductionConfigWarnings` is not exported.

- [ ] **Step 3: Implement production warning collection**

Add this function at the bottom of `server/src/common/config/app-config.ts`:

```ts
export function collectProductionConfigWarnings(
  env: NodeJS.ProcessEnv = process.env,
): string[] {
  if (env.NODE_ENV !== 'production') {
    return [];
  }

  const warnings: string[] = [];
  if (!env.JWT_ACCESS_SECRET) {
    warnings.push(
      'JWT_ACCESS_SECRET is not set in production; configure a dedicated access token secret.',
    );
  }
  if (!env.JWT_REFRESH_SECRET) {
    warnings.push(
      'JWT_REFRESH_SECRET is not set in production; configure a dedicated refresh token secret.',
    );
  }
  if (!env.FLOWPLANV2_ENCRYPTION_KEY) {
    warnings.push(
      'FLOWPLANV2_ENCRYPTION_KEY is not set in production; encrypted integrations may be unavailable.',
    );
  }
  if (!env.ADMIN_CORS_ORIGIN) {
    warnings.push(
      'ADMIN_CORS_ORIGIN is not set in production; configure the expected admin origin.',
    );
  }
  return warnings;
}
```

- [ ] **Step 4: Run production warning tests again**

Run:

```powershell
cd server
npm run test:unit -- common/config/app-config.unit.spec.ts
```

Expected: PASS.

- [ ] **Step 5: Wire production warnings into server startup**

Modify `server/src/main.ts`.

Add this import near the other config imports:

```ts
import { collectProductionConfigWarnings } from './common/config/app-config';
```

Add this block after the encryption-key startup log:

```ts
  for (const warning of collectProductionConfigWarnings()) {
    logger.warn(warning);
  }
```

The file must still avoid static imports of `@nestjs/core`, `./app.bootstrap`, `./app.module`, and `./common/logger/app-logger.service`.

- [ ] **Step 6: Add explicit Kopia Linux-default regression coverage**

Modify `server/src/files/kopia.service.unit.spec.ts`.

Add this test after the `beforeEach` block:

```ts
  it('defaults to the Linux-friendly kopia executable unless overridden', async () => {
    statMock.mockResolvedValue({});
    execFileMock.mockImplementation((_exe, _args, _options, callback) =>
      callback(null, '[]', ''),
    );
    const { KopiaService } = await import('./kopia.service');

    await new KopiaService().listSnapshots('/data/project');

    expect(execFileMock).toHaveBeenCalledWith(
      'kopia',
      ['snapshot', 'list', '/data/project', '--json'],
      expect.any(Object),
      expect.any(Function),
    );
  });
```

This test should pass with the current implementation and documents the Linux default. The existing `prepareRestore` test with `process.env.KOPIA_EXE = 'kopia.exe'` continues to prove Windows opt-in behavior.

- [ ] **Step 7: Run focused Kopia tests**

Run:

```powershell
cd server
npm run test:unit -- files/kopia.service.unit.spec.ts
```

Expected: PASS.

- [ ] **Step 8: Run server build**

Run:

```powershell
cd server
npm run build
```

Expected: PASS.

- [ ] **Step 9: Commit Task 2**

Run:

```powershell
git add server/src/common/config/app-config.ts server/src/common/config/app-config.unit.spec.ts server/src/files/kopia.service.unit.spec.ts server/src/main.ts
git commit -m "fix: warn on weak production config"
```

Expected: commit succeeds with only Task 2 files staged.

## Task 3: Web Admin Vite API Base Selection

**Files:**
- Create: `web_admin/src/app/apiBase.ts`
- Create: `web_admin/src/app/apiBase.test.ts`
- Create: `web_admin/src/vite-env.d.ts`
- Modify: `web_admin/src/app/AdminApp.tsx`
- Modify: `web_admin/src/api/adminApi.ts`
- Modify: `web_admin/src/api/adminApi.test.ts`

- [ ] **Step 1: Add failing API base resolver tests**

Create `web_admin/src/app/apiBase.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { resolveInitialApiBase } from './apiBase';

describe('resolveInitialApiBase', () => {
  it('uses the development fallback when no stored or Vite value exists', () => {
    expect(resolveInitialApiBase({ storedValue: null, viteValue: undefined })).toBe(
      'http://localhost:3202',
    );
  });

  it('uses VITE_API_BASE_URL when local storage has no override', () => {
    expect(
      resolveInitialApiBase({
        storedValue: null,
        viteValue: 'https://flowplan.example.com/api',
      }),
    ).toBe('https://flowplan.example.com');
  });

  it('keeps local storage override ahead of VITE_API_BASE_URL', () => {
    expect(
      resolveInitialApiBase({
        storedValue: 'https://stored.example.com/api',
        viteValue: 'https://vite.example.com/api',
      }),
    ).toBe('https://stored.example.com');
  });

  it('supports same-origin reverse proxy configuration with /api', () => {
    expect(
      resolveInitialApiBase({
        storedValue: null,
        viteValue: '/api',
      }),
    ).toBe('');
  });
});
```

- [ ] **Step 2: Add failing admin API normalization tests**

Modify the first test in `web_admin/src/api/adminApi.test.ts` by adding these assertions:

```ts
    expect(normalizeApiBase('/api')).toBe('');
    expect(buildApiUrl('', '/api/health')).toBe('/api/health');
    expect(buildApiUrl('/api', '/api/health')).toBe('/api/health');
```

- [ ] **Step 3: Run failing web admin tests**

Run:

```powershell
cd web_admin
npm run test -- src/app/apiBase.test.ts src/api/adminApi.test.ts
```

Expected: FAIL because `apiBase.ts` does not exist and `/api` currently duplicates the prefix.

- [ ] **Step 4: Implement API base normalization for same-origin `/api`**

Modify `normalizeApiBase` and `buildApiUrl` in `web_admin/src/api/adminApi.ts`:

```ts
export function normalizeApiBase(value: string): string {
  const trimmed = value.trim().replace(/\/+$/, '');
  if (!trimmed) return defaultApiBase;
  if (trimmed === '/api') return '';
  if (trimmed.endsWith('/api') && trimmed.startsWith('/')) {
    return trimmed.slice(0, -4);
  }
  try {
    const url = new URL(trimmed);
    if (url.pathname === '/api') {
      url.pathname = '';
    } else if (url.pathname.endsWith('/api')) {
      url.pathname = url.pathname.slice(0, -4);
    }
    url.search = '';
    url.hash = '';
    return url.toString().replace(/\/$/, '');
  } catch {
    return trimmed;
  }
}

export function buildApiUrl(apiBase: string, path: string): string {
  if (path.startsWith('http')) return path;
  const base = apiBase === '' ? '' : normalizeApiBase(apiBase);
  const normalizedPath = path.startsWith('/') ? path : `/${path}`;
  return `${base}${normalizedPath}`;
}
```

- [ ] **Step 5: Create the API base resolver**

Create `web_admin/src/app/apiBase.ts`:

```ts
import { normalizeApiBase } from '../api/adminApi';
import { defaultApiBase } from './constants';

export interface ApiBaseSources {
  storedValue: string | null;
  viteValue?: string;
}

export function resolveInitialApiBase({
  storedValue,
  viteValue,
}: ApiBaseSources): string {
  const selected = storedValue !== null ? storedValue : viteValue;
  if (selected == null || selected.trim() === '') {
    return normalizeApiBase(defaultApiBase);
  }
  return normalizeApiBase(selected);
}
```

- [ ] **Step 6: Add Vite env typing**

Create `web_admin/src/vite-env.d.ts`:

```ts
/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_BASE_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
```

- [ ] **Step 7: Wire AdminApp initial state through the resolver**

Modify imports in `web_admin/src/app/AdminApp.tsx`.

Add:

```ts
import { resolveInitialApiBase } from './apiBase';
```

Change the constants import from:

```ts
import { defaultApiBase, datasets, modules } from './constants';
```

to:

```ts
import { datasets, modules } from './constants';
```

Replace the current `apiBase` state initializer:

```ts
  const [apiBase, setApiBase] = useState(() =>
    normalizeApiBase(
      loadStored('flowplanv2.admin.apiBase') ?? defaultApiBase,
    ),
  );
```

with:

```ts
  const [apiBase, setApiBase] = useState(() =>
    resolveInitialApiBase({
      storedValue: loadStored('flowplanv2.admin.apiBase'),
      viteValue: import.meta.env.VITE_API_BASE_URL,
    }),
  );
```

Keep the `normalizeApiBase` import because `saveConnection()` still uses it.

- [ ] **Step 8: Run focused web admin tests**

Run:

```powershell
cd web_admin
npm run test -- src/app/apiBase.test.ts src/api/adminApi.test.ts
```

Expected: PASS.

- [ ] **Step 9: Run web admin build**

Run:

```powershell
cd web_admin
npm run build
```

Expected: PASS.

- [ ] **Step 10: Commit Task 3**

Run:

```powershell
git add web_admin/src/app/apiBase.ts web_admin/src/app/apiBase.test.ts web_admin/src/vite-env.d.ts web_admin/src/app/AdminApp.tsx web_admin/src/api/adminApi.ts web_admin/src/api/adminApi.test.ts
git commit -m "fix: support production admin api base"
```

Expected: commit succeeds with only Task 3 files staged.

## Task 4: Final Linux Compatibility Verification

**Files:**
- No planned source edits.
- Read-only verification across server, web admin, and root startup script status.

- [ ] **Step 1: Confirm root Windows startup scripts were not modified**

Run:

```powershell
git diff --name-only HEAD~3..HEAD
```

Expected: output does not include:

```text
start-flowplanv2-all.cmd
scripts/start-flowplanv2-all.ps1
```

- [ ] **Step 2: Run focused server unit tests**

Run:

```powershell
cd server
npm run test:unit -- common/config/env-files.unit.spec.ts common/config/app-config.unit.spec.ts app.module.unit.spec.ts files/kopia.service.unit.spec.ts
```

Expected: PASS.

- [ ] **Step 3: Run server build**

Run:

```powershell
cd server
npm run build
```

Expected: PASS.

- [ ] **Step 4: Run focused web admin tests**

Run:

```powershell
cd web_admin
npm run test -- src/app/apiBase.test.ts src/api/adminApi.test.ts
```

Expected: PASS.

- [ ] **Step 5: Run web admin build**

Run:

```powershell
cd web_admin
npm run build
```

Expected: PASS.

- [ ] **Step 6: Inspect final worktree state**

Run:

```powershell
git status --short
```

Expected: clean working tree, or only unrelated user changes that are explicitly identified before final handoff.

- [ ] **Step 7: Commit final verification note only if a file was changed during verification**

If verification required no source changes, do not create another commit.

If a small correction was needed, run:

```powershell
git add <changed-files>
git commit -m "test: verify linux production compatibility"
```

Expected: commit succeeds with only the verification correction files staged.

## Self-Review Notes

- Spec coverage:
  - Shared server env discovery: Task 1.
  - `main.ts` and `ConfigModule` same decision: Task 1.
  - Explicit env override and missing override failure: Task 1.
  - System env vars remain authoritative: Task 1.
  - Production missing recommended values surfaced: Task 2.
  - Linux Kopia default: Task 2.
  - Web admin `VITE_API_BASE_URL`: Task 3.
  - Same-origin `/api` reverse proxy support: Task 3.
  - Root Windows startup scripts untouched: Task 4.
- Placeholder scan: no placeholder tasks remain.
- Type consistency:
  - `resolveEnvFile`, `loadEnvFile`, `formatEnvLoadMessage`, and `resolveConfigModuleEnvOptions` names match across tests and implementation steps.
  - `resolveInitialApiBase` receives `storedValue` and `viteValue`, matching `AdminApp.tsx`.
