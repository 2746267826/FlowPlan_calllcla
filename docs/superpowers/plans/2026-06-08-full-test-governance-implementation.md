# Full Test Governance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the A-level FlowPlanV2 test governance system: 100% coverage gates for included hand-written code, complete user interaction matrices, automated server/web tests, Flutter test assets with user-run validation commands, and cross-end acceptance evidence.

**Architecture:** Add a repository-level quality gate, shared deterministic test infrastructure, and per-end test suites. Use a feature-to-test matrix as the source of truth so code coverage and real user behavior coverage advance together.

**Tech Stack:** PowerShell, Vitest, NestJS testing, Supertest, PostgreSQL test database, React Testing Library, user-event, jest-dom, jsdom, MSW, Playwright, Flutter `flutter_test`, Flutter `integration_test`, mocktail, golden_toolkit, Drift in-memory database.

---

## Source Inputs

- Approved design: `docs/superpowers/specs/2026-06-08-full-test-governance-design.md`
- Existing constraint: `docs/development_constraints_260426.md` forbids Codex from running `flutter` or `dart` commands.
- Existing dirty worktree file: `client_flutter/windows/CMakeLists.txt`; do not stage or modify it for this initiative.
- Six subagent planning slices were used: server, web admin, Flutter client, root governance, cross-end workflows, and deterministic fixture/flake controls.

## Global Rules

- Never run `flutter` or `dart` commands as Codex. List them for the user.
- Never use `git add .` in this worktree.
- Before each commit, run `git status --short` and `git diff --cached --name-only`.
- Keep `client_flutter/windows/CMakeLists.txt` unstaged unless the user explicitly asks for it.
- Automated tests must mock AI, Microsoft Graph, Kopia, file picker, notification APIs, Windows shell/input, Android usage stats, and real external credentials.
- Integration/API tests must refuse non-test databases. Accepted test URLs must include `flowplantest` or `test`.
- Exclusions require a matrix row with file/pattern, reason, replacement verification, owner/module, and review condition.

## File Structure

Create repository governance files:

- `scripts/test-flowplanv2.ps1`: root quality gate.
- `docs/test-governance/quality-gates.md`: gate definitions and report locations.
- `docs/test-governance/future-development-rules.md`: required rules for future work.
- `docs/test-governance/feature-test-matrix.csv`: source of truth for feature/control/API coverage.
- `docs/test-governance/coverage-exclusions.csv`: reviewed exclusions.
- `docs/test-governance/manual-acceptance.csv`: manual and real-device validation records.
- `docs/test-governance/cross-end-workflow-matrix.md`: cross-end workflow coverage.
- `docs/test-governance/external-services-acceptance.md`: real credential/device validation.
- `docs/test-governance/flake-policy.md`: deterministic testing rules.
- `docs/test-governance/selector-policy.md`: web `data-testid` and Flutter `Key` rules.
- `docs/test-governance/reports/README.md`: generated report inventory.

Create/modify server testing files:

- Modify `server/package.json`, `server/package-lock.json`, `server/vitest.config.ts`, `server/src/test-setup.ts`, `server/src/common/test/test-utils.ts`, `server/src/main.ts`.
- Create `server/vitest.unit.config.ts`, `server/vitest.integration.config.ts`, `server/vitest.api.config.ts`, `server/vitest.coverage.config.ts`.
- Create `server/src/app.bootstrap.ts`.
- Create `server/src/common/test/api-test-app.ts`, `database-test-harness.ts`, `determinism.ts`, `fixtures.ts`, `external-mocks.ts`, `test-database.guard.ts`.
- Add `*.unit.spec.ts`, `*.integration.spec.ts`, and `*.api.spec.ts` across server modules.

Create/modify web admin testing files:

- Modify `web_admin/package.json`, `web_admin/package-lock.json`, `web_admin/tsconfig.json`.
- Create `web_admin/vitest.config.ts`, `web_admin/playwright.config.ts`, `web_admin/tsconfig.test.json`.
- Create `web_admin/src/test/setupTests.ts`, `render.tsx`, `mockAdminApi.ts`, `fixtures/adminData.ts`, `msw/handlers.ts`, `msw/server.ts`.
- Create `web_admin/e2e/fixtures/adminApiRoutes.ts`, `web_admin/e2e/support/stabilize.ts`, `web_admin/e2e/admin-auth-navigation.spec.ts`, `web_admin/e2e/page-workflows.spec.ts`.
- Add `*.test.ts` and `*.test.tsx` beside `web_admin/src/api`, `src/utils`, `src/components`, `src/pages`, and `src/app`.

Create/modify Flutter client testing files:

- Modify `client_flutter/pubspec.yaml`, `client_flutter/pubspec.lock` after user-run dependency resolution.
- Modify `client_flutter/lib/core/database/app_database.dart`, `client_flutter/lib/core/router/app_router.dart`, `client_flutter/lib/app.dart`.
- Create `client_flutter/lib/core/time/app_clock.dart`, `client_flutter/lib/core/ui/app_keys.dart`.
- Create `client_flutter/test/test_support/test_database.dart`, `provider_harness.dart`, `fake_api.dart`, `fixtures.dart`, `fake_clock.dart`, `mock_http.dart`, `golden_harness.dart`.
- Create Flutter tests under `client_flutter/test/core`, `test/features`, `test/widgets`, `test/goldens`, and `client_flutter/integration_test`.
- Create `client_flutter/docs/client_flutter_test_matrix.md` and `client_flutter/docs/manual_real_device_acceptance.md`.

## Task 1: Governance Documents And Matrices

**Files:**
- Create: `docs/test-governance/quality-gates.md`
- Create: `docs/test-governance/future-development-rules.md`
- Create: `docs/test-governance/feature-test-matrix.csv`
- Create: `docs/test-governance/coverage-exclusions.csv`
- Create: `docs/test-governance/manual-acceptance.csv`
- Create: `docs/test-governance/cross-end-workflow-matrix.md`
- Create: `docs/test-governance/external-services-acceptance.md`
- Create: `docs/test-governance/flake-policy.md`
- Create: `docs/test-governance/selector-policy.md`
- Create: `docs/test-governance/reports/README.md`

- [ ] **Step 1: Verify governance files are absent or incomplete**

Run:

```powershell
Test-Path docs\test-governance\feature-test-matrix.csv
Test-Path docs\test-governance\quality-gates.md
```

Expected before implementation: at least one command prints `False`.

- [ ] **Step 2: Create the feature matrix header and seed rows**

Write `docs/test-governance/feature-test-matrix.csv` with:

```csv
test_id,product_area,module_or_route,user_feature,control_or_api,happy_path_test,failure_path_test,data_integrity_assertion,accessibility_or_layout_assertion,automated_test_file,manual_acceptance_id,status,notes
SERVER-SYNC-001,server,sync,Push mutation,POST /api/sync/push,server/src/sync/sync.controller.api.spec.ts rejects and accepts deterministic mutations,server/src/sync/sync.controller.api.spec.ts covers stale version conflict,sync_objects and sync_changes remain consistent,not applicable,server/src/sync/sync.controller.api.spec.ts,,missing,foundation row
WEB-TASKS-001,web_admin,TasksSchedulesPage,Filter and complete task,search input and batch complete button,web_admin/src/pages/TasksSchedulesPage.test.tsx filters rows and completes selected task,web_admin/src/pages/TasksSchedulesPage.test.tsx shows API failure without mutation,patchAdminData called once for selected task,row checkbox and confirm dialog are reachable by role,web_admin/src/pages/TasksSchedulesPage.test.tsx,,missing,foundation row
CLIENT-TASK-001,client_flutter,/task/create,Create task,save button,client_flutter/integration_test/task_calendar_flow_test.dart creates visible task,client_flutter/test/features/task/task_repository_test.dart covers validation failure,offline mutation and audit row are recorded,save button has stable AppKeys.taskSaveButton,client_flutter/integration_test/task_calendar_flow_test.dart,MANUAL-WIN-001,missing,foundation row
CE-TASK-001,cross_end,task schedule audit,Create schedule complete and audit,multiple APIs and UI controls,server/src/cross-end/cross-end-workflows.api.spec.ts exercises workflow,server/src/cross-end/cross-end-workflows.api.spec.ts covers failed completion,audit and sync evidence exist,web and Flutter selectors recorded,server/src/cross-end/cross-end-workflows.api.spec.ts,MANUAL-CE-001,missing,foundation row
```

- [ ] **Step 3: Create the coverage exclusion ledger**

Write `docs/test-governance/coverage-exclusions.csv` with:

```csv
pattern,reason,replacement_verification,owner_or_module,review_condition,status
server/src/main.ts,bootstrap entrypoint only after logic moves to app.bootstrap.ts,server/src/app.bootstrap.ts unit and API app tests cover behavior,server,review whenever main.ts gains branches,missing
server/src/common/test/**,test helper infrastructure,test helper tests and consuming suites cover behavior,server,review when helpers contain branching production behavior,missing
web_admin/src/test/**,test helper infrastructure,component and e2e suites consume helpers,web_admin,review when helpers contain production behavior,missing
client_flutter/lib/core/database/app_database.g.dart,generated Drift code,repository and database behavior tests cover generated behavior,client_flutter,review after schema generation changes,missing
client_flutter/**.g.dart,generated source,provider/model behavior tests cover generated behavior,client_flutter,review after generator updates,missing
```

- [ ] **Step 4: Create manual acceptance records**

Write `docs/test-governance/manual-acceptance.csv` with:

```csv
manual_id,area,scenario,required_environment,steps,evidence,status
MANUAL-WIN-001,client_flutter,Windows task create complete sync audit,Windows desktop local server test database,"Create task in Windows client; complete it; open Web Admin; verify task status sync mutation and audit row","screenshots and audit row id",missing
MANUAL-ANDROID-001,client_flutter,Android usage stats import,Android device with usage access,"Grant usage access; import latest usage; verify tracker timeline and upload payload","device screenshot and test notes",missing
MANUAL-OUTLOOK-001,cross_end,Outlook OAuth and sync,Microsoft account test calendar,"Authorize Outlook; run read-only sync; verify diagnostics; reset connection","screenshots and run id",missing
MANUAL-AI-001,cross_end,Real AI provider draft approval,OpenAI-compatible test key,"Save provider; test connection; ask for a task draft; approve; verify task and audit","provider test id and audit row id",missing
MANUAL-FILE-001,cross_end,Real file transfer interruption recovery,Windows filesystem,"Upload 10MB file; interrupt; resume; download; compare hash","hashes and transfer session id",missing
```

- [ ] **Step 5: Create governance policy documents**

Write `docs/test-governance/quality-gates.md` with this content:

```markdown
# FlowPlanV2 Quality Gates

Every included hand-written production file must reach 100% lines, branches, functions, and statements. The root gate is `scripts/test-flowplanv2.ps1`.

Generated report locations:

- Server coverage: `server/coverage/index.html`
- Web admin coverage: `web_admin/coverage/index.html`
- Web admin E2E report: `web_admin/playwright-report/index.html`
- Flutter user-run coverage: `client_flutter/coverage/lcov.info`
- Root summaries: `docs/test-governance/reports/generated`

The root gate fails for automated server and web failures. Flutter commands are printed for user execution because `docs/development_constraints_260426.md` forbids Codex from running Flutter or Dart commands.
```

Write `docs/test-governance/future-development-rules.md` with:

```markdown
# Future Development Rules

Every feature change must update `docs/test-governance/feature-test-matrix.csv`.

Completion requires:

- Code tests for implementation behavior.
- User behavior tests or a manual acceptance record for every visible control.
- Failure-path tests for validation, empty states, API failure, permission failure, network failure, duplicate submission, and external-service failure.
- Reviewed entries in `docs/test-governance/coverage-exclusions.csv` for any excluded file pattern.
- A final report naming test files, coverage reports, root gate result, and user-run Flutter commands.

Bug fixes require a regression test or a manual reproduction record when automation cannot reproduce the defect.
```

Write `docs/test-governance/flake-policy.md` with:

```markdown
# Flake Policy

Automated tests must not use live external credentials, arbitrary sleeps, wall-clock assertions, committed `.only`, or unexplained `.skip`.

Tests must freeze time, use deterministic IDs and API responses, and isolate test data. Performance tests are outside the default gate unless they are deterministic and marked as such in the matrix.
```

Write `docs/test-governance/selector-policy.md` with:

```markdown
# Selector Policy

Web admin tests prefer accessible role and name selectors when they identify a target unambiguously. Use `data-testid` for duplicated Ant Design controls, icon-only controls, generated table actions, chart regions, modal confirmations, and drawer/tab content.

Flutter tests use stable `Key` constants from `client_flutter/lib/core/ui/app_keys.dart` and semantic labels when user accessibility also benefits.
```

Write `docs/test-governance/reports/README.md` with:

```markdown
# Test Governance Reports

Generated reports live under `docs/test-governance/reports/generated` and are ignored by Git. Commit stable governance files, matrices, and acceptance templates.
```

- [ ] **Step 6: Verify documents parse as plain text**

Run:

```powershell
Get-ChildItem docs\test-governance -File | Select-Object -ExpandProperty Name
Import-Csv docs\test-governance\feature-test-matrix.csv | Select-Object -First 1
Import-Csv docs\test-governance\coverage-exclusions.csv | Select-Object -First 1
Import-Csv docs\test-governance\manual-acceptance.csv | Select-Object -First 1
```

Expected: the three CSV commands print objects with named columns and no parser error.

- [ ] **Step 7: Commit governance documents**

Run:

```powershell
git status --short
git add -- docs/test-governance/quality-gates.md docs/test-governance/future-development-rules.md docs/test-governance/feature-test-matrix.csv docs/test-governance/coverage-exclusions.csv docs/test-governance/manual-acceptance.csv docs/test-governance/cross-end-workflow-matrix.md docs/test-governance/external-services-acceptance.md docs/test-governance/flake-policy.md docs/test-governance/selector-policy.md docs/test-governance/reports/README.md
git diff --cached --name-only
git commit -m "docs(test): add governance matrices and policies"
```

Expected: staged names include only `docs/test-governance/**`; `client_flutter/windows/CMakeLists.txt` remains unstaged.

## Task 2: Root Quality Gate Script

**Files:**
- Create: `scripts/test-flowplanv2.ps1`
- Modify: `.gitignore`

- [ ] **Step 1: Write the failing gate invocation**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1
```

Expected before implementation: PowerShell reports that `scripts\test-flowplanv2.ps1` does not exist.

- [ ] **Step 2: Add generated report ignore rule**

Add this line to `.gitignore`:

```gitignore
docs/test-governance/reports/generated/
```

- [ ] **Step 3: Create the root gate script**

Write `scripts/test-flowplanv2.ps1`:

```powershell
param(
  [switch]$SkipInstall,
  [switch]$SkipWebE2E,
  [switch]$Completion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$Results = New-Object System.Collections.Generic.List[object]

function Add-Result {
  param(
    [string]$Name,
    [string]$Status,
    [string]$Details
  )
  $Results.Add([PSCustomObject]@{
    Name = $Name
    Status = $Status
    Details = $Details
  })
}

function Invoke-Gate {
  param(
    [string]$Name,
    [string]$WorkingDirectory,
    [string]$Command,
    [string[]]$Arguments
  )

  Write-Host "== $Name =="
  Push-Location $WorkingDirectory
  try {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
      throw "$Command $($Arguments -join ' ') exited with $LASTEXITCODE"
    }
    Add-Result -Name $Name -Status 'PASS' -Details "$Command $($Arguments -join ' ')"
  } catch {
    Add-Result -Name $Name -Status 'FAIL' -Details $_.Exception.Message
    throw
  } finally {
    Pop-Location
  }
}

function Assert-RequiredFile {
  param([string]$Path)
  if (-not (Test-Path $Path)) {
    throw "Required file missing: $Path"
  }
}

function Assert-MatrixShape {
  param(
    [string]$Path,
    [switch]$Completion
  )

  $rows = Import-Csv $Path
  $requiredColumns = @(
    'test_id',
    'product_area',
    'module_or_route',
    'user_feature',
    'control_or_api',
    'happy_path_test',
    'failure_path_test',
    'data_integrity_assertion',
    'accessibility_or_layout_assertion',
    'automated_test_file',
    'manual_acceptance_id',
    'status',
    'notes'
  )
  foreach ($column in $requiredColumns) {
    if (-not ($rows | Get-Member -Name $column -MemberType NoteProperty)) {
      throw "Matrix missing column: $column"
    }
  }
  if ($Completion) {
    $openRows = $rows | Where-Object { $_.status -in @('missing', 'planned') }
    if ($openRows.Count -gt 0) {
      throw "Completion mode found open matrix rows: $($openRows.Count)"
    }
  }
}

function Write-FlutterManualReminder {
  Write-Host ''
  Write-Host '[MANUAL] Flutter commands were not run by Codex.'
  Write-Host 'Run these commands manually:'
  Write-Host 'cd client_flutter'
  Write-Host 'flutter pub get'
  Write-Host 'dart run build_runner build --delete-conflicting-outputs'
  Write-Host 'flutter analyze'
  Write-Host 'flutter test --coverage'
  Write-Host 'flutter test test/goldens'
  Write-Host 'flutter test integration_test'
}

Write-Host '== FlowPlanV2 root quality gate =='

$MatrixPath = Join-Path $RepoRoot 'docs\test-governance\feature-test-matrix.csv'
Assert-RequiredFile $MatrixPath
Assert-MatrixShape -Path $MatrixPath -Completion:$Completion

Invoke-Gate -Name 'boundary' -WorkingDirectory $RepoRoot -Command 'powershell' -Arguments @('-ExecutionPolicy', 'Bypass', '-File', 'scripts\check-client-server-boundary.ps1', '-FailOnViolation')

$ServerRoot = Join-Path $RepoRoot 'server'
if (-not $SkipInstall) {
  Invoke-Gate -Name 'server:install' -WorkingDirectory $ServerRoot -Command 'npm' -Arguments @('ci')
}
Invoke-Gate -Name 'server:build' -WorkingDirectory $ServerRoot -Command 'npm' -Arguments @('run', 'build')
Invoke-Gate -Name 'server:unit' -WorkingDirectory $ServerRoot -Command 'npm' -Arguments @('run', 'test:unit')
Invoke-Gate -Name 'server:integration' -WorkingDirectory $ServerRoot -Command 'npm' -Arguments @('run', 'test:integration')
Invoke-Gate -Name 'server:api' -WorkingDirectory $ServerRoot -Command 'npm' -Arguments @('run', 'test:api')
Invoke-Gate -Name 'server:coverage' -WorkingDirectory $ServerRoot -Command 'npm' -Arguments @('run', 'test:coverage')

$WebRoot = Join-Path $RepoRoot 'web_admin'
if (-not $SkipInstall) {
  Invoke-Gate -Name 'web:install' -WorkingDirectory $WebRoot -Command 'npm' -Arguments @('ci')
}
Invoke-Gate -Name 'web:build' -WorkingDirectory $WebRoot -Command 'npm' -Arguments @('run', 'build')
Invoke-Gate -Name 'web:unit' -WorkingDirectory $WebRoot -Command 'npm' -Arguments @('run', 'test')
Invoke-Gate -Name 'web:coverage' -WorkingDirectory $WebRoot -Command 'npm' -Arguments @('run', 'test:coverage')
if (-not $SkipWebE2E) {
  Invoke-Gate -Name 'web:e2e' -WorkingDirectory $WebRoot -Command 'npm' -Arguments @('run', 'test:e2e')
}

Write-FlutterManualReminder

Write-Host ''
Write-Host '== Gate Summary =='
$Results | ForEach-Object {
  Write-Host ("[{0}] {1} {2}" -f $_.Status, $_.Name, $_.Details)
}
Write-Host '[MANUAL] Flutter validation: PENDING USER RUN'
```

- [ ] **Step 4: Run the root gate to verify expected failing dependencies**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -SkipInstall -SkipWebE2E
```

Expected after only this task: the script starts, validates the matrix, then fails at a server or web script that is not yet defined. The failure proves the root gate is wired.

- [ ] **Step 5: Commit root gate**

Run:

```powershell
git status --short
git add -- scripts/test-flowplanv2.ps1 .gitignore
git diff --cached --name-only
git commit -m "chore(test): add root quality gate script"
```

Expected: staged names include only `scripts/test-flowplanv2.ps1` and `.gitignore`.

## Task 3: Shared Determinism And Server Test Harness

**Files:**
- Modify: `server/src/test-setup.ts`
- Modify: `server/src/common/test/test-utils.ts`
- Create: `server/src/common/test/determinism.ts`
- Create: `server/src/common/test/db-test-harness.ts`
- Create: `server/src/common/test/fixtures.ts`
- Create: `server/src/common/test/external-mocks.ts`
- Create: `server/src/common/test/api-test-app.ts`

- [ ] **Step 1: Write a failing safety test for non-test database refusal**

Create `server/src/common/test/db-test-harness.unit.spec.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { assertTestDatabaseUrl } from './db-test-harness';

describe('assertTestDatabaseUrl', () => {
  it('rejects production-looking database URLs', () => {
    expect(() => assertTestDatabaseUrl('postgres://user:pass@localhost:5432/flowplanv2')).toThrow(
      /Refusing to use non-test database/,
    );
  });

  it('accepts flowplantest database URLs', () => {
    expect(() => assertTestDatabaseUrl('postgres://user:pass@localhost:5432/flowplantest')).not.toThrow();
  });
});
```

Run:

```powershell
cd server
npx vitest run src/common/test/db-test-harness.unit.spec.ts
```

Expected: FAIL because `db-test-harness.ts` does not exist.

- [ ] **Step 2: Create deterministic helpers**

Create `server/src/common/test/determinism.ts`:

```ts
import { vi } from 'vitest';

export const TEST_NOW = new Date('2026-01-02T03:04:05.000Z');

export function installDeterminism() {
  vi.useFakeTimers();
  vi.setSystemTime(TEST_NOW);
  const randomSpy = vi.spyOn(Math, 'random').mockReturnValue(0.42);
  return () => {
    randomSpy.mockRestore();
    vi.useRealTimers();
    vi.restoreAllMocks();
  };
}
```

- [ ] **Step 3: Create database guard and reset helper**

Create `server/src/common/test/db-test-harness.ts`:

```ts
import { DatabaseService } from '../../database/database.service';

export function assertTestDatabaseUrl(url = process.env.FLOWPLANV2_DATABASE_URL ?? process.env.DATABASE_URL ?? '') {
  if (!/flowplantest|test/i.test(url)) {
    throw new Error(`Refusing to use non-test database: ${url}`);
  }
}

export async function assertActiveTestDatabase(db: DatabaseService) {
  const result = await db.query('SELECT current_database() AS name');
  const name = String(result.rows[0]?.name ?? '');
  if (!/flowplantest|test/i.test(name)) {
    throw new Error(`Refusing to clean non-test database: ${name}`);
  }
}

export async function resetTestDatabase(db: DatabaseService) {
  assertTestDatabaseUrl();
  await assertActiveTestDatabase(db);
  await db.query('TRUNCATE TABLE users RESTART IDENTITY CASCADE');
}
```

- [ ] **Step 4: Wire setup cleanup**

Modify `server/src/test-setup.ts` to:

```ts
// Test setup runs before each test file.
import { afterEach, beforeAll } from 'vitest';
import { assertTestDatabaseUrl } from './common/test/db-test-harness';

if (!process.env.FLOWPLANV2_DATABASE_URL && !process.env.DATABASE_URL) {
  process.env.DATABASE_URL = 'postgres://postgres:060331@localhost:5432/flowplantest';
}

beforeAll(() => {
  assertTestDatabaseUrl();
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});
```

- [ ] **Step 5: Replace test-utils cleanup**

Modify `cleanDatabase` in `server/src/common/test/test-utils.ts`:

```ts
import { resetTestDatabase } from './db-test-harness';

export async function cleanDatabase(db: DatabaseService): Promise<void> {
  await resetTestDatabase(db);
}
```

Keep existing `createTestUser` and `createTestDevice` helpers.

- [ ] **Step 6: Create API app helper**

Create `server/src/common/test/api-test-app.ts`:

```ts
import request from 'supertest';
import { Test } from '@nestjs/testing';
import { INestApplication } from '@nestjs/common';
import { AppModule } from '../../app.module';
import { DatabaseService } from '../../database/database.service';
import { configureApp } from '../../app.bootstrap';

export async function createApiTestApp() {
  const moduleRef = await Test.createTestingModule({
    imports: [AppModule],
  }).compile();

  const app = moduleRef.createNestApplication();
  configureApp(app);
  await app.init();

  const db = app.get(DatabaseService);
  return {
    app,
    db,
    request: request(app.getHttpServer()),
  };
}
```

- [ ] **Step 7: Verify harness tests pass**

Run:

```powershell
cd server
npx vitest run src/common/test/db-test-harness.unit.spec.ts
```

Expected: PASS.

- [ ] **Step 8: Commit shared server harness**

Run:

```powershell
git status --short
git add -- server/src/test-setup.ts server/src/common/test/test-utils.ts server/src/common/test/determinism.ts server/src/common/test/db-test-harness.ts server/src/common/test/db-test-harness.unit.spec.ts server/src/common/test/fixtures.ts server/src/common/test/external-mocks.ts server/src/common/test/api-test-app.ts
git diff --cached --name-only
git commit -m "test(server): add deterministic test harness"
```

Expected: staged names include only server test harness files.

## Task 4: Server Test Runners And Bootstrap Extraction

**Files:**
- Modify: `server/package.json`
- Modify: `server/package-lock.json`
- Modify: `server/vitest.config.ts`
- Create: `server/vitest.unit.config.ts`
- Create: `server/vitest.integration.config.ts`
- Create: `server/vitest.api.config.ts`
- Create: `server/vitest.coverage.config.ts`
- Create: `server/src/app.bootstrap.ts`
- Modify: `server/src/main.ts`
- Test: `server/src/app.bootstrap.unit.spec.ts`

- [ ] **Step 1: Write failing bootstrap test**

Create `server/src/app.bootstrap.unit.spec.ts`:

```ts
import { describe, expect, it, vi } from 'vitest';
import { configureApp } from './app.bootstrap';

describe('configureApp', () => {
  it('sets global prefix and enables shutdown hooks', () => {
    const app = {
      setGlobalPrefix: vi.fn(),
      enableShutdownHooks: vi.fn(),
      useGlobalFilters: vi.fn(),
      useGlobalInterceptors: vi.fn(),
      enableCors: vi.fn(),
    };

    configureApp(app as any);

    expect(app.setGlobalPrefix).toHaveBeenCalledWith('api');
    expect(app.enableShutdownHooks).toHaveBeenCalled();
  });
});
```

Run:

```powershell
cd server
npx vitest run src/app.bootstrap.unit.spec.ts
```

Expected: FAIL because `app.bootstrap.ts` does not exist.

- [ ] **Step 2: Extract bootstrap configuration**

Create `server/src/app.bootstrap.ts`:

```ts
import { INestApplication } from '@nestjs/common';

export function configureApp(app: INestApplication) {
  app.setGlobalPrefix('api');
  app.enableShutdownHooks();
  return app;
}
```

Modify `server/src/main.ts` so it imports and calls `configureApp(app)` before `listen`.

- [ ] **Step 3: Add split Vitest configs**

Create `server/vitest.unit.config.ts`:

```ts
import { defineConfig } from 'vitest/config';
import { resolve } from 'node:path';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    root: resolve(__dirname, 'src'),
    include: ['**/*.unit.spec.ts'],
    setupFiles: [resolve(__dirname, 'src/test-setup.ts')],
    testTimeout: 30000,
    hookTimeout: 15000,
  },
  resolve: { alias: { '@': resolve(__dirname, 'src') } },
});
```

Create `server/vitest.integration.config.ts`:

```ts
import { defineConfig } from 'vitest/config';
import { resolve } from 'node:path';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    fileParallelism: false,
    maxConcurrency: 1,
    root: resolve(__dirname, 'src'),
    include: ['**/*.integration.spec.ts'],
    setupFiles: [resolve(__dirname, 'src/test-setup.ts')],
    testTimeout: 30000,
    hookTimeout: 15000,
  },
  resolve: { alias: { '@': resolve(__dirname, 'src') } },
});
```

Create `server/vitest.api.config.ts`:

```ts
import { defineConfig } from 'vitest/config';
import { resolve } from 'node:path';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    fileParallelism: false,
    maxConcurrency: 1,
    root: resolve(__dirname, 'src'),
    include: ['**/*.api.spec.ts'],
    setupFiles: [resolve(__dirname, 'src/test-setup.ts')],
    testTimeout: 30000,
    hookTimeout: 15000,
  },
  resolve: { alias: { '@': resolve(__dirname, 'src') } },
});
```

Create `server/vitest.coverage.config.ts`:

```ts
import { defineConfig } from 'vitest/config';
import { resolve } from 'node:path';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    fileParallelism: false,
    maxConcurrency: 1,
    root: resolve(__dirname, 'src'),
    include: ['**/*.unit.spec.ts', '**/*.integration.spec.ts', '**/*.api.spec.ts'],
    setupFiles: [resolve(__dirname, 'src/test-setup.ts')],
    testTimeout: 30000,
    hookTimeout: 15000,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'text-summary', 'html', 'json-summary', 'lcov'],
      include: ['**/*.ts'],
      exclude: ['**/*.spec.ts', 'test-setup.ts', 'common/test/**', 'main.ts'],
      thresholds: { lines: 100, branches: 100, functions: 100, statements: 100 },
    },
  },
  resolve: { alias: { '@': resolve(__dirname, 'src') } },
});
```

- [ ] **Step 4: Add server scripts**

Modify `server/package.json` scripts:

```json
{
  "test": "vitest run",
  "test:watch": "vitest",
  "test:unit": "vitest run --config vitest.unit.config.ts",
  "test:integration": "vitest run --config vitest.integration.config.ts",
  "test:api": "vitest run --config vitest.api.config.ts",
  "test:coverage": "vitest run --config vitest.coverage.config.ts --coverage",
  "test:all": "npm run build && npm run test:unit && npm run test:integration && npm run test:api && npm run test:coverage"
}
```

Keep existing non-test scripts.

- [ ] **Step 5: Verify split runner behavior**

Run:

```powershell
cd server
npm run test:unit -- src/app.bootstrap.unit.spec.ts
npm run test:coverage
```

Expected: first command PASS. Coverage command may FAIL until all suites are added; record uncovered files in `docs/test-governance/feature-test-matrix.csv`.

- [ ] **Step 6: Commit server runners**

Run:

```powershell
git status --short
git add -- server/package.json server/package-lock.json server/vitest.config.ts server/vitest.unit.config.ts server/vitest.integration.config.ts server/vitest.api.config.ts server/vitest.coverage.config.ts server/src/app.bootstrap.ts server/src/app.bootstrap.unit.spec.ts server/src/main.ts
git diff --cached --name-only
git commit -m "test(server): split test runners and bootstrap coverage"
```

Expected: staged names include only server runner and bootstrap files.

## Task 5: Server Coverage Waves

**Files:**
- Create/rename tests under `server/src/**/*.unit.spec.ts`
- Create/rename tests under `server/src/**/*.integration.spec.ts`
- Create tests under `server/src/**/*.api.spec.ts`
- Modify production files only when tests expose inaccessible behavior or untestable bootstrap coupling.
- Update: `docs/test-governance/feature-test-matrix.csv`
- Update: `docs/test-governance/coverage-exclusions.csv`

- [ ] **Step 1: Rename existing DB-backed specs**

Rename DB-backed existing specs to `*.integration.spec.ts` and pure specs to `*.unit.spec.ts`. Use these initial mappings:

```text
server/src/auth/auth.service.spec.ts -> server/src/auth/auth.service.integration.spec.ts
server/src/database/database.service.spec.ts -> server/src/database/database.service.integration.spec.ts
server/src/sync/sync.service.spec.ts -> server/src/sync/sync.service.integration.spec.ts
server/src/tracking/tracking.service.spec.ts -> server/src/tracking/tracking.service.integration.spec.ts
server/src/analytics/analytics.service.spec.ts -> server/src/analytics/analytics.service.integration.spec.ts
server/src/activity-understanding/activity-understanding.service.spec.ts -> server/src/activity-understanding/activity-understanding.service.integration.spec.ts
server/src/files/local-object-storage.service.spec.ts -> server/src/files/local-object-storage.service.integration.spec.ts
server/src/ai/ai.service.spec.ts -> server/src/ai/ai.service.integration.spec.ts
server/src/reports/report-template.engine.spec.ts -> server/src/reports/report-template.engine.unit.spec.ts
server/src/scheduler/dependency-graph.service.spec.ts -> server/src/scheduler/dependency-graph.service.unit.spec.ts
server/src/scheduler/genetic-scheduler.service.spec.ts -> server/src/scheduler/genetic-scheduler.service.unit.spec.ts
```

Run:

```powershell
cd server
npm run test:unit
npm run test:integration
```

Expected: renamed suites are discovered by the split configs.

- [ ] **Step 2: Add common utility unit tests**

Create unit tests for:

```text
server/src/common/utils/crypto.unit.spec.ts
server/src/common/utils/dates.unit.spec.ts
server/src/common/utils/errors.unit.spec.ts
server/src/common/utils/numbers.unit.spec.ts
server/src/common/utils/objects.unit.spec.ts
server/src/common/utils/strings.unit.spec.ts
server/src/common/utils/tfidf.unit.spec.ts
server/src/common/errors/app-exception.unit.spec.ts
server/src/common/filters/global-exception.filter.unit.spec.ts
server/src/common/interceptors/request-log.interceptor.unit.spec.ts
server/src/common/logger/app-logger.service.unit.spec.ts
server/src/common/config/app-config.unit.spec.ts
server/src/common/schemas/task.schema.unit.spec.ts
server/src/common/schemas/event.schema.unit.spec.ts
```

Use this pattern:

```ts
import { describe, expect, it } from 'vitest';
import { normalizeWhitespace } from './strings';

describe('normalizeWhitespace', () => {
  it('collapses repeated whitespace and trims edges', () => {
    expect(normalizeWhitespace('  A   B \n C  ')).toBe('A B C');
  });

  it('returns an empty string for blank input', () => {
    expect(normalizeWhitespace('   ')).toBe('');
  });
});
```

Run:

```powershell
cd server
npm run test:unit
```

Expected: PASS for common utility tests.

- [ ] **Step 3: Add API tests for every controller**

Create API specs for:

```text
server/src/auth/auth.controller.api.spec.ts
server/src/devices/devices.controller.api.spec.ts
server/src/sync/sync.controller.api.spec.ts
server/src/files/files.controller.api.spec.ts
server/src/tracking/tracking.controller.api.spec.ts
server/src/analytics/analytics.controller.api.spec.ts
server/src/activity-understanding/activity-understanding.controller.api.spec.ts
server/src/scheduler/scheduler.controller.api.spec.ts
server/src/scheduler/cron-jobs.controller.api.spec.ts
server/src/reports/reports.controller.api.spec.ts
server/src/ai/ai.controller.api.spec.ts
server/src/models/models.controller.api.spec.ts
server/src/admin/admin.controller.api.spec.ts
server/src/client/client.controller.api.spec.ts
server/src/web/web.controller.api.spec.ts
server/src/health/health.controller.api.spec.ts
```

Use this controller pattern:

```ts
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApiTestApp } from '../common/test/api-test-app';
import { cleanDatabase, createTestDevice, createTestUser } from '../common/test/test-utils';

describe('SyncController API', () => {
  let h: Awaited<ReturnType<typeof createApiTestApp>>;
  const userId = '00000000-0000-4000-8000-000000000001';
  const deviceId = '00000000-0000-4000-8000-000000000101';

  beforeAll(async () => {
    h = await createApiTestApp();
  });

  afterAll(async () => {
    await h.app.close();
  });

  beforeEach(async () => {
    await cleanDatabase(h.db);
    await createTestUser(h.db, { id: userId });
    await createTestDevice(h.db, userId, { id: deviceId });
  });

  it('POST /api/sync/push persists a mutation and returns the contract shape', async () => {
    const res = await h.request
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
      accepted: [{ mutationUid: 'mut-api-1', objectType: 'task_item', serverVersion: 1 }],
      conflicts: [],
      rejected: [],
    });
  });
});
```

Run:

```powershell
cd server
npm run test:api
```

Expected: API suites pass once each controller fixture matches its DTO contract.

- [ ] **Step 4: Complete service integration modules in dependency order**

Add or expand integration tests in this order:

```text
auth -> devices -> sync -> tracking -> activity-understanding -> analytics -> client -> web -> scheduler -> reports -> files -> ai -> models -> outlook -> admin
```

For each module, add rows to `docs/test-governance/feature-test-matrix.csv` for:

```text
happy path
invalid input
empty data
permission or context failure
database failure or rejected operation
idempotency or duplicate submission when relevant
audit or sync mutation evidence when relevant
```

Run after each module:

```powershell
cd server
npm run test:unit
npm run test:integration
npm run test:api
```

Expected: targeted suites pass before moving to the next module.

- [ ] **Step 5: Make server coverage pass at 100%**

Run:

```powershell
cd server
npm run test:coverage
```

Expected at server completion: PASS with 100% lines, branches, functions, and statements for included files.

- [ ] **Step 6: Commit server coverage**

Run:

```powershell
git status --short
git add -- server docs/test-governance/feature-test-matrix.csv docs/test-governance/coverage-exclusions.csv
git diff --cached --name-only
git commit -m "test(server): complete A-level server coverage"
```

Expected: staged files include server tests/config and governance rows; unrelated dirty files remain unstaged.

## Task 6: Web Admin Test Tooling

**Files:**
- Modify: `web_admin/package.json`
- Modify: `web_admin/package-lock.json`
- Modify: `web_admin/tsconfig.json`
- Create: `web_admin/vitest.config.ts`
- Create: `web_admin/playwright.config.ts`
- Create: `web_admin/tsconfig.test.json`
- Create: `web_admin/src/test/setupTests.ts`
- Create: `web_admin/src/test/render.tsx`
- Create: `web_admin/src/test/mockAdminApi.ts`
- Create: `web_admin/src/test/fixtures/adminData.ts`
- Create: `web_admin/src/test/msw/handlers.ts`
- Create: `web_admin/src/test/msw/server.ts`
- Create: `web_admin/e2e/fixtures/adminApiRoutes.ts`
- Create: `web_admin/e2e/support/stabilize.ts`

- [ ] **Step 1: Install web test dependencies**

Run:

```powershell
cd web_admin
npm install -D vitest @vitest/coverage-v8 jsdom @testing-library/react @testing-library/user-event @testing-library/jest-dom msw @playwright/test
npx playwright install chromium
```

Expected: `web_admin/package.json` and `web_admin/package-lock.json` include the new dev dependencies.

- [ ] **Step 2: Add web test scripts**

Modify `web_admin/package.json` scripts:

```json
{
  "test": "vitest run",
  "test:watch": "vitest",
  "test:coverage": "vitest run --coverage",
  "test:e2e": "playwright test",
  "test:e2e:headed": "playwright test --headed",
  "test:all": "npm run build && npm run test:coverage && npm run test:e2e"
}
```

Keep existing `dev`, `vite:dev`, `build`, and `preview`.

- [ ] **Step 3: Add Vitest config**

Create `web_admin/vitest.config.ts`:

```ts
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vitest/config';

export default defineConfig({
  plugins: [react()],
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './src/test/setupTests.ts',
    css: true,
    include: ['src/**/*.{test,spec}.{ts,tsx}'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html', 'lcov', 'json-summary'],
      reportsDirectory: './coverage',
      include: ['src/**/*.{ts,tsx}'],
      exclude: ['src/test/**', 'src/**/*.test.*', 'src/main.tsx'],
      thresholds: { lines: 100, statements: 100, functions: 100, branches: 100 },
    },
  },
});
```

- [ ] **Step 4: Add test setup and render helper**

Create `web_admin/src/test/setupTests.ts`:

```ts
import '@testing-library/jest-dom/vitest';
import { afterAll, afterEach, beforeAll, vi } from 'vitest';
import { server } from './msw/server';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  vi.restoreAllMocks();
});
afterAll(() => server.close());
```

Create `web_admin/src/test/render.tsx`:

```tsx
import { ConfigProvider } from 'antd';
import zhCN from 'antd/locale/zh_CN';
import { ReactElement } from 'react';
import { render } from '@testing-library/react';

export function renderWithProviders(ui: ReactElement) {
  return render(<ConfigProvider locale={zhCN}>{ui}</ConfigProvider>);
}
```

Create `web_admin/src/test/mockAdminApi.ts`:

```ts
import { vi } from 'vitest';

export function createMockAdminApi(overrides: Record<string, unknown> = {}) {
  return {
    login: vi.fn().mockResolvedValue({ token: 'test-token', user: { id: 'admin' } }),
    health: vi.fn().mockResolvedValue({ ok: true }),
    dashboard: vi.fn().mockResolvedValue({}),
    adminData: vi.fn().mockResolvedValue({ items: [] }),
    patchAdminData: vi.fn().mockResolvedValue({ ok: true }),
    remoteConfig: vi.fn().mockResolvedValue({}),
    updateRemoteConfig: vi.fn().mockResolvedValue({ ok: true }),
    runOperation: vi.fn().mockResolvedValue({ ok: true }),
    uploadEnv: vi.fn().mockResolvedValue({ ok: true }),
    ...overrides,
  };
}
```

- [ ] **Step 5: Add MSW handlers**

Create `web_admin/src/test/msw/handlers.ts`:

```ts
import { http, HttpResponse } from 'msw';

export const adminApiHandlers = [
  http.post('*/api/auth/login', () => HttpResponse.json({ token: 'test-token' })),
  http.get('*/api/health', () => HttpResponse.json({ ok: true })),
  http.get('*/api/admin/dashboard', () => HttpResponse.json({ cards: [] })),
  http.get('*/api/admin/data/:domain', () => HttpResponse.json({ items: [] })),
];
```

Create `web_admin/src/test/msw/server.ts`:

```ts
import { setupServer } from 'msw/node';
import { adminApiHandlers } from './handlers';

export const server = setupServer(...adminApiHandlers);
```

- [ ] **Step 6: Add Playwright config**

Create `web_admin/playwright.config.ts`:

```ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  webServer: {
    command: 'npm run build && npm run dev',
    url: 'http://127.0.0.1:5174',
    reuseExistingServer: !process.env.CI,
    timeout: 120000,
  },
  use: {
    baseURL: 'http://127.0.0.1:5174',
    trace: 'on-first-retry',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
});
```

- [ ] **Step 7: Verify web tooling**

Run:

```powershell
cd web_admin
npm run test
npm run test:coverage
```

Expected after tooling only: tests run; coverage may fail until page/component suites are added.

- [ ] **Step 8: Commit web tooling**

Run:

```powershell
git status --short
git add -- web_admin/package.json web_admin/package-lock.json web_admin/tsconfig.json web_admin/vitest.config.ts web_admin/playwright.config.ts web_admin/tsconfig.test.json web_admin/src/test web_admin/e2e/fixtures web_admin/e2e/support
git diff --cached --name-only
git commit -m "test(web): add admin test tooling"
```

Expected: staged names include only web admin test tooling files.

## Task 7: Web Admin Component, Page, And E2E Coverage

**Files:**
- Create tests under `web_admin/src/api`, `src/utils`, `src/components`, `src/pages`, `src/app`
- Create E2E tests under `web_admin/e2e`
- Modify selectors in `web_admin/src/app/AdminApp.tsx`, `web_admin/src/pages/*.tsx`, `web_admin/src/components/*.tsx`
- Update: `docs/test-governance/feature-test-matrix.csv`

- [ ] **Step 1: Add pure API and utility tests**

Create:

```text
web_admin/src/api/adminApi.test.ts
web_admin/src/utils/format.test.ts
web_admin/src/utils/pageFormat.test.ts
```

Use this pattern for API failure assertions:

```ts
import { describe, expect, it, vi } from 'vitest';
import { requestJson } from './adminApi';

describe('requestJson', () => {
  it('throws an error with status text when response is not ok', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, status: 500, text: async () => 'boom' }));

    await expect(requestJson('/api/admin/dashboard')).rejects.toThrow(/500/);
  });
});
```

Run:

```powershell
cd web_admin
npm run test -- src/api/adminApi.test.ts src/utils/format.test.ts src/utils/pageFormat.test.ts
```

Expected: PASS.

- [ ] **Step 2: Add component tests**

Create:

```text
web_admin/src/components/StatusTag.test.tsx
web_admin/src/components/ServerIndicator.test.tsx
web_admin/src/components/AuditList.test.tsx
web_admin/src/components/RawDataCollapse.test.tsx
web_admin/src/components/DetailDrawer.test.tsx
web_admin/src/components/JsonBlock.test.tsx
web_admin/src/components/HumanDescriptions.test.tsx
```

Use this DetailDrawer skeleton:

```tsx
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { DetailDrawer } from './DetailDrawer';
import { renderWithProviders } from '../test/render';
import { createMockAdminApi } from '../test/mockAdminApi';

describe('DetailDrawer', () => {
  it('completes a task and refreshes dependent data', async () => {
    const api = createMockAdminApi({ patchAdminData: vi.fn().mockResolvedValue({ ok: true }) });
    const onChanged = vi.fn();

    renderWithProviders(
      <DetailDrawer
        api={api as any}
        detail={{
          title: '任务 / Plan review',
          dataset: { domain: 'tasks', title: '任务', description: '' },
          row: { id: 'task-1', title: 'Plan review' },
        }}
        onClose={vi.fn()}
        onChanged={onChanged}
      />,
    );

    await userEvent.click(screen.getByRole('button', { name: '标记任务完成' }));

    await waitFor(() => expect(api.patchAdminData).toHaveBeenCalled());
    expect(onChanged).toHaveBeenCalled();
  });
});
```

- [ ] **Step 3: Add read-only page tests**

Create tests for:

```text
web_admin/src/pages/AlertsPage.test.tsx
web_admin/src/pages/LogsPage.test.tsx
web_admin/src/pages/EnvPage.test.tsx
web_admin/src/pages/DashboardPage.test.tsx
web_admin/src/pages/AuditPage.test.tsx
web_admin/src/pages/DevicesPage.test.tsx
```

Each test file must cover:

```text
initial load
loading state
empty state
success state
API failure state
refresh action
drawer or detail action when present
```

- [ ] **Step 4: Add CRUD and confirmation page tests**

Create tests for:

```text
web_admin/src/pages/BusinessListPage.test.tsx
web_admin/src/pages/TasksSchedulesPage.test.tsx
web_admin/src/pages/DriveFilesPage.test.tsx
web_admin/src/pages/SettingsPage.test.tsx
web_admin/src/pages/JobsPage.test.tsx
web_admin/src/pages/SchedulePage.test.tsx
web_admin/src/pages/OperationsPage.test.tsx
web_admin/src/pages/OutlookPage.test.tsx
web_admin/src/app/AdminApp.test.tsx
```

Use this TasksSchedulesPage skeleton:

```tsx
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { TasksSchedulesPage } from './TasksSchedulesPage';
import { renderWithProviders } from '../test/render';
import { createMockAdminApi } from '../test/mockAdminApi';

describe('TasksSchedulesPage', () => {
  it('loads tasks and schedules, filters rows, opens detail, and batch completes selected tasks', async () => {
    const api = createMockAdminApi({
      adminData: vi
        .fn()
        .mockResolvedValueOnce({ items: [{ id: 'task-1', title: 'Plan review', status: 'open' }] })
        .mockResolvedValueOnce({ items: [{ id: 'schedule-1', summary: 'Daily sync', status: 'CONFIRMED' }] }),
      patchAdminData: vi.fn().mockResolvedValue({ ok: true }),
    });
    const onOpenDetail = vi.fn();

    renderWithProviders(<TasksSchedulesPage api={api as any} onDataRefresh={vi.fn()} onOpenDetail={onOpenDetail} />);

    expect(await screen.findByText('Plan review')).toBeInTheDocument();
    await userEvent.type(screen.getByPlaceholderText('搜索标题、备注、地点、所属本'), 'Plan');
    expect(screen.queryByText('Daily sync')).not.toBeInTheDocument();

    await userEvent.click(screen.getByRole('button', { name: 'Plan review' }));
    expect(onOpenDetail).toHaveBeenCalled();

    const row = screen.getByText('Plan review').closest('tr');
    expect(row).not.toBeNull();
    await userEvent.click(within(row as HTMLElement).getByRole('checkbox'));
    await userEvent.click(screen.getByRole('button', { name: '批量完成' }));
    await userEvent.click(screen.getByRole('button', { name: '确定' }));

    await waitFor(() => expect(api.patchAdminData).toHaveBeenCalled());
  });
});
```

- [ ] **Step 5: Add Playwright page workflows**

Create `web_admin/e2e/fixtures/adminApiRoutes.ts`:

```ts
import { Page } from '@playwright/test';

export async function installAdminApiRoutes(page: Page) {
  await page.route('**/api/health', route => route.fulfill({ json: { ok: true } }));
  await page.route('**/api/admin/dashboard', route => route.fulfill({ json: { cards: [] } }));
  await page.route('**/api/admin/data/**', route => route.fulfill({ json: { items: [{ id: 'task-1', title: 'Plan review' }] } }));
  await page.route('**/api/admin/**', route => route.fulfill({ json: { ok: true } }));
}
```

Create `web_admin/e2e/page-workflows.spec.ts`:

```ts
import { expect, test } from '@playwright/test';
import { installAdminApiRoutes } from './fixtures/adminApiRoutes';

test('admin can navigate pages and operate core controls against mocked API', async ({ page }) => {
  await installAdminApiRoutes(page);
  await page.goto('/');

  await expect(page.getByText('FlowPlanV2')).toBeVisible();

  await page.getByRole('menuitem', { name: /全部任务与日程/ }).click();
  await expect(page.getByText('Plan review')).toBeVisible();
  await page.getByPlaceholder('搜索标题、备注、地点、所属本').fill('Plan');
  await expect(page.getByText('Plan review')).toBeVisible();

  await page.getByRole('menuitem', { name: /文件资料/ }).click();
  await page.getByRole('button', { name: /保存|新增|添加/ }).click();

  await page.getByRole('menuitem', { name: /运维操作/ }).click();
  await page.getByRole('button', { name: /准备执行/ }).click();
  await expect(page.getByRole('button', { name: /确认执行/ })).toBeEnabled();
});
```

- [ ] **Step 6: Mark missing AI and Models admin pages as matrix gaps**

Add rows to `docs/test-governance/feature-test-matrix.csv`:

```csv
WEB-AI-000,web_admin,AI page,AI management page,route,not available in current AdminApp,not available in current AdminApp,no data mutation,not available,,MANUAL-AI-001,missing,current web_admin has no dedicated AI page
WEB-MODELS-000,web_admin,Models page,Models management page,route,not available in current AdminApp,not available in current AdminApp,no data mutation,not available,,MANUAL-AI-001,missing,current web_admin has no dedicated Models page
```

- [ ] **Step 7: Verify web coverage**

Run:

```powershell
cd web_admin
npm run build
npm run test:coverage
npm run test:e2e
```

Expected at web admin completion: build passes, unit/component coverage reaches 100% for included files, Playwright passes.

- [ ] **Step 8: Commit web coverage**

Run:

```powershell
git status --short
git add -- web_admin docs/test-governance/feature-test-matrix.csv
git diff --cached --name-only
git commit -m "test(web): complete admin interaction coverage"
```

Expected: staged files include web admin tests, selector updates, package files, and governance rows.

## Task 8: Flutter Testability Foundation

**Files:**
- Modify: `client_flutter/pubspec.yaml`
- Modify: `client_flutter/pubspec.lock` after user-run dependency resolution
- Modify: `client_flutter/lib/core/database/app_database.dart`
- Modify: `client_flutter/lib/core/router/app_router.dart`
- Modify: `client_flutter/lib/app.dart`
- Create: `client_flutter/lib/core/time/app_clock.dart`
- Create: `client_flutter/lib/core/ui/app_keys.dart`
- Create: `client_flutter/test/test_support/test_database.dart`
- Create: `client_flutter/test/test_support/provider_harness.dart`
- Create: `client_flutter/test/test_support/fake_api.dart`
- Create: `client_flutter/test/test_support/fixtures.dart`
- Create: `client_flutter/test/test_support/fake_clock.dart`
- Create: `client_flutter/test/test_support/mock_http.dart`
- Create: `client_flutter/test/test_support/golden_harness.dart`

- [ ] **Step 1: Add Flutter dev dependencies**

Modify `client_flutter/pubspec.yaml`:

```yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  build_runner: ^2.4.14
  drift_dev: ^2.22.1
  freezed: ^2.5.8
  json_serializable: ^6.9.4
  riverpod_generator: ^2.6.4
  mocktail: ^1.0.4
  golden_toolkit: ^0.15.0
  msix: ^3.16.1
```

User-run command:

```powershell
cd client_flutter
flutter pub get
```

Expected user result: `pubspec.lock` updates and dependency resolution succeeds.

- [ ] **Step 2: Add database injection**

Modify `client_flutter/lib/core/database/app_database.dart` constructor:

```dart
AppDatabase([QueryExecutor? executor])
    : super(executor ?? openAppDatabaseConnection());

factory AppDatabase.forTesting(QueryExecutor executor) {
  return AppDatabase(executor);
}
```

- [ ] **Step 3: Add router and app overrides**

Modify `client_flutter/lib/core/router/app_router.dart` with these exact text transformations.

Find:

```dart
final GoRouter appRouter = GoRouter(
```

Replace with:

```dart
GoRouter createAppRouter({String initialLocation = AppRoutes.timeline}) {
  return GoRouter(
```

Find:

```dart
  initialLocation: AppRoutes.timeline,
```

Replace with:

```dart
    initialLocation: initialLocation,
```

At the final closing of the current `GoRouter(...)` declaration, replace:

```dart
);
```

with:

```dart
  );
}

final GoRouter appRouter = createAppRouter();
```

Modify `client_flutter/lib/app.dart` to accept:

```dart
import 'package:go_router/go_router.dart';

class FlowPlanV2App extends ConsumerWidget {
  const FlowPlanV2App({super.key, this.routerOverride});

  final GoRouter? routerOverride;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final router = routerOverride ?? appRouter;
    return MaterialApp.router(routerConfig: router);
  }
}
```

Use the existing `title`, `debugShowCheckedModeBanner`, `theme`, `darkTheme`, and `themeMode` fields from the current `FlowPlanV2App` implementation in the returned `MaterialApp.router`.

- [ ] **Step 4: Add stable keys**

Create `client_flutter/lib/core/ui/app_keys.dart`:

```dart
import 'package:flutter/widgets.dart';

class AppKeys {
  const AppKeys._();

  static const shellCreateTask = Key('flowplan.shell.create_task');
  static const shellTimeline = Key('flowplan.shell.timeline');
  static const shellWeek = Key('flowplan.shell.week');
  static const shellMonth = Key('flowplan.shell.month');
  static const taskSummaryField = Key('flowplan.task.summary');
  static const taskSaveButton = Key('flowplan.task.save');
  static const taskCompleteButton = Key('flowplan.task.complete');
  static const eventSummaryField = Key('flowplan.event.summary');
  static const eventSaveButton = Key('flowplan.event.save');
  static const trackerStartButton = Key('flowplan.tracker.start');
  static const trackerReviewConfirmButton = Key('flowplan.tracker.review_confirm');
  static const reportGenerateButton = Key('flowplan.report.generate');
  static const fileTransferStartButton = Key('flowplan.file.transfer_start');
  static const syncRunButton = Key('flowplan.sync.run');
  static const settingsSaveButton = Key('flowplan.settings.save');
}
```

- [ ] **Step 5: Add Flutter test harness**

Create `client_flutter/test/test_support/test_database.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flowplanv2/core/database/app_database.dart';

AppDatabase createTestDatabase() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}
```

Create `client_flutter/test/test_support/provider_harness.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';

Future<void> pumpFlowPlanTestApp(
  WidgetTester tester, {
  required AppDatabase db,
  required Widget child,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: MaterialApp(home: child),
    ),
  );
}
```

- [ ] **Step 6: User-run Flutter foundation commands**

Ask the user to run:

```powershell
cd client_flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test test/widget_test.dart
```

Expected user result: dependency resolution, generated code, analyzer, and smoke widget test pass.

- [ ] **Step 7: Commit Flutter foundation**

Run:

```powershell
git status --short
git add -- client_flutter/pubspec.yaml client_flutter/pubspec.lock client_flutter/lib/core/database/app_database.dart client_flutter/lib/core/router/app_router.dart client_flutter/lib/app.dart client_flutter/lib/core/time/app_clock.dart client_flutter/lib/core/ui/app_keys.dart client_flutter/test/test_support
git diff --cached --name-only
git commit -m "test(client): add Flutter testability foundation"
```

Expected: staged names include Flutter foundation files only; `client_flutter/windows/CMakeLists.txt` remains unstaged unless the user-run Flutter tools changed it and the user approves staging it.

## Task 9: Flutter Business, Widget, Integration, Golden, And Manual Tests

**Files:**
- Create tests under `client_flutter/test/core`, `test/features`, `test/widgets`, `test/goldens`
- Create integration tests under `client_flutter/integration_test`
- Modify Flutter page files to add `AppKeys` and semantic labels
- Create: `client_flutter/docs/client_flutter_test_matrix.md`
- Create: `client_flutter/docs/manual_real_device_acceptance.md`
- Update: `docs/test-governance/feature-test-matrix.csv`
- Update: `docs/test-governance/manual-acceptance.csv`

- [ ] **Step 1: Add core API and sync tests**

Create:

```text
client_flutter/test/core/server_api/api_client_test.dart
client_flutter/test/core/server_api/client_api_test.dart
client_flutter/test/core/sync/server_sync_change_applier_test.dart
client_flutter/test/core/sync/sync_engine_test.dart
client_flutter/test/core/offline_queue/offline_mutation_runner_test.dart
client_flutter/test/core/offline_queue/offline_mutation_store_test.dart
client_flutter/test/core/utils/payload_utils_test.dart
```

Use this API client skeleton:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:drift/native.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/database/app_database.dart';

void main() {
  test('adds auth header and decodes JSON response', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final tokenStore = AuthTokenStore(db);
    await tokenStore.saveTokens(accessToken: 'token-1', refreshToken: 'refresh-1');

    final client = ApiClient(
      baseUri: Uri.parse('http://localhost:3202/api'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/client/tasks');
        expect(request.headers['authorization'], 'Bearer token-1');
        return http.Response('{"items":[]}', 200);
      }),
    );

    expect(await client.getJson('/client/tasks'), {'items': []});
  });
}
```


- [ ] **Step 2: Add repository and service tests**

Create tests under:

```text
client_flutter/test/features/calendar
client_flutter/test/features/task
client_flutter/test/features/tracker
client_flutter/test/features/files
client_flutter/test/features/reports
client_flutter/test/features/sync
client_flutter/test/features/ical
client_flutter/test/features/settings
```

Use this task repository skeleton:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import '../../test_support/test_database.dart';

void main() {
  test('creating a task records local state and sync evidence', () async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await db.into(db.taskItems).insert(
      TaskItemsCompanion.insert(
        uid: 'task-1',
        dtstamp: DateTime.utc(2026, 6, 8),
        summary: 'Write Flutter tests',
      ),
    );

    final rows = await db.select(db.taskItems).get();
    expect(rows.map((row) => row.summary), contains('Write Flutter tests'));
  });
}
```

Expand assertions to include audit and offline mutation rows once repository APIs are injected through the harness.

- [ ] **Step 3: Add page widget tests with keys**

Add `AppKeys` to these page files:

```text
client_flutter/lib/features/calendar/presentation/calendar_shell.dart
client_flutter/lib/features/calendar/presentation/timeline_view.dart
client_flutter/lib/features/calendar/presentation/week_view.dart
client_flutter/lib/features/calendar/presentation/month_view.dart
client_flutter/lib/features/calendar/presentation/event_detail_page.dart
client_flutter/lib/features/task/presentation/quick_add_bar.dart
client_flutter/lib/features/task/presentation/task_detail_page.dart
client_flutter/lib/features/tracker/presentation/tracker_page.dart
client_flutter/lib/features/reports/presentation/report_center_page.dart
client_flutter/lib/features/files/presentation/file_context_page.dart
client_flutter/lib/features/files/presentation/file_transfer_center_page.dart
client_flutter/lib/features/sync/server_sync_status_page.dart
client_flutter/lib/features/sync/outlook_settings_page.dart
client_flutter/lib/features/settings/presentation/settings_page.dart
client_flutter/lib/features/ical/ical_import_export_page.dart
client_flutter/lib/features/ai_chat/presentation/ai_chat_page.dart
```

Create widget tests for each page under `client_flutter/test/features/**`.

- [ ] **Step 4: Add integration flows**

Create:

```text
client_flutter/integration_test/task_calendar_flow_test.dart
client_flutter/integration_test/sync_offline_flow_test.dart
client_flutter/integration_test/tracker_review_flow_test.dart
client_flutter/integration_test/file_report_ai_flow_test.dart
```

Use this integration skeleton:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import '../test/test_support/test_database.dart';
import '../test/test_support/provider_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('create task, schedule it, and complete it', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      child: const FlowPlanV2App(),
    );

    await tester.tap(find.byKey(AppKeys.shellCreateTask));
    await tester.enterText(find.byKey(AppKeys.taskSummaryField), 'A-level tests');
    await tester.tap(find.byKey(AppKeys.taskSaveButton));
    await tester.pumpAndSettle();

    expect(find.text('A-level tests'), findsOneWidget);
  });
}
```

- [ ] **Step 5: Add golden/layout tests**

Create `client_flutter/test/goldens/client_layout_golden_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import '../test_support/golden_harness.dart';

void main() {
  testWidgets('timeline fits Android narrow layout', (tester) async {
    await pumpGoldenScenario(tester, route: '/timeline', size: const Size(360, 800));
    await expectLater(find.byType(FlowPlanV2App), matchesGoldenFile('goldens/timeline_android_360x800.png'));
  });

  testWidgets('settings fits Windows desktop layout', (tester) async {
    await pumpGoldenScenario(tester, route: '/settings', size: const Size(1280, 800));
    await expectLater(find.byType(FlowPlanV2App), matchesGoldenFile('goldens/settings_windows_1280x800.png'));
  });
}
```

Golden target sizes:

```text
Windows 1280x800
Windows 1920x1080
Android 360x800
Android 390x844
Tablet 800x1280
```

- [ ] **Step 6: Create Flutter manual acceptance docs**

Write `client_flutter/docs/manual_real_device_acceptance.md` with:

```markdown
# Flutter Real Device Acceptance

User-run validation covers:

- Windows tray and close-to-tray behavior.
- Windows launch and foreground tracking.
- RawInput sampling.
- File picker, open, reveal, and local identity hash.
- Notification and reminder delivery.
- Android usage-access permission and import.
- Android reminders.
- Outlook OAuth and sync with real credentials.
- AI provider call with a real key.
- Long-running tracker stability for at least 4 hours.

Each run records date, device, app version, scenario id, result, evidence path, and follow-up issue id when failing.
```

- [ ] **Step 7: User-run Flutter validation**

Ask the user to run:

```powershell
cd client_flutter
flutter analyze
flutter test --coverage
flutter test test/goldens
flutter test integration_test
flutter run -d windows
flutter devices
flutter run -d <android-device-id>
```

Expected user result: commands pass or produce failure logs that are recorded in `docs/test-governance/manual-acceptance.csv`.

- [ ] **Step 8: Commit Flutter tests**

Run:

```powershell
git status --short
git add -- client_flutter/lib client_flutter/test client_flutter/integration_test client_flutter/docs docs/test-governance/feature-test-matrix.csv docs/test-governance/manual-acceptance.csv
git diff --cached --name-only
git commit -m "test(client): add Flutter user workflow coverage"
```

Expected: staged files include Flutter tests, selector keys, docs, and governance rows. `client_flutter/windows/CMakeLists.txt` remains unstaged unless explicitly approved.

## Task 10: Cross-End Workflow Acceptance

**Files:**
- Create: `server/src/cross-end/cross-end-workflows.api.spec.ts`
- Create: `web_admin/e2e/cross-end/task-sync-audit.spec.ts`
- Create: `web_admin/e2e/cross-end/files-ai-ops.spec.ts`
- Create: `client_flutter/integration_test/cross_end_workflows_test.dart`
- Create/modify: `docs/test-governance/cross-end-workflow-matrix.md`
- Create/modify: `docs/test-governance/external-services-acceptance.md`
- Update: `docs/test-governance/feature-test-matrix.csv`
- Update: `docs/test-governance/manual-acceptance.csv`

- [ ] **Step 1: Write cross-end workflow matrix**

Write `docs/test-governance/cross-end-workflow-matrix.md`:

```markdown
# Cross-End Workflow Matrix

| Workflow | Test IDs | Automated Mock-Based Tests | Manual / Real Acceptance |
| --- | --- | --- | --- |
| Task schedule edit complete audit sync | CE-TASK-001 through CE-TASK-006 | Server API and Web Playwright with mocked API | Windows client creates and completes a task; Web Admin verifies status, sync mutation, and audit row |
| Calendar create edit delete views | CE-CAL-001 through CE-CAL-004 | Server API and Flutter fake API integration | Windows and Android event appears and disappears across timeline, week, and month |
| Offline sync conflict resolution | CE-SYNC-001 through CE-SYNC-006 | Server two-device stale version API tests | Real offline write, reconnect, Web Admin conflict resolution, no silent overwrite |
| Tracking activity report | CE-TRACK-001 through CE-TRACK-007 | Server ingest, understanding, report API tests | Windows tracking for 30 minutes, upload, confirm activity, generate report |
| Files transfer version recovery | CE-FILE-001 through CE-FILE-007 | Server file session API and Web mocked drive flow | Real 10MB transfer interruption and hash verification |
| AI draft approval audit | CE-AI-001 through CE-AI-007 | Server mocked AI response and Web mocked operation approval | Real AI provider creates task draft, user approves, audit row exists |
| Admin operations evidence | CE-ADMIN-001 through CE-ADMIN-008 | Web Playwright mocked dashboard, alerts, logs, jobs, settings, env, operations | Operator runs one safe operation, job trigger, and settings save |
| Outlook external services | CE-EXT-001 through CE-EXT-007 | Mocked Graph and diagnostics tests | Real Microsoft OAuth and read-only sync |
```

- [ ] **Step 2: Add server cross-end API test**

Create `server/src/cross-end/cross-end-workflows.api.spec.ts`:

```ts
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApiTestApp } from '../common/test/api-test-app';
import { cleanDatabase, createTestDevice, createTestUser } from '../common/test/test-utils';

describe('CE-TASK-001 task schedule completion workflow', () => {
  let h: Awaited<ReturnType<typeof createApiTestApp>>;
  const userId = '00000000-0000-4000-8000-000000000201';
  const deviceId = '00000000-0000-4000-8000-000000000202';

  beforeAll(async () => {
    h = await createApiTestApp();
  });

  afterAll(async () => {
    await h.app.close();
  });

  beforeEach(async () => {
    await cleanDatabase(h.db);
    await createTestUser(h.db, { id: userId });
    await createTestDevice(h.db, userId, { id: deviceId });
  });

  it('creates, schedules, completes, and exposes audit evidence', async () => {
    const headers = {
      'x-flowplanv2-user-id': userId,
      'x-flowplanv2-device-id': deviceId,
    };

    const task = await h.request
      .post('/api/client/tasks')
      .set(headers)
      .send({ uid: 'ce-task-001', title: 'Cross-end task', estimatedMinutes: 45 });

    expect([200, 201]).toContain(task.status);

    const run = await h.request
      .post('/api/scheduler/runs')
      .set(headers)
      .send({
        rangeStart: '2026-06-08T00:00:00.000Z',
        rangeEnd: '2026-06-09T00:00:00.000Z',
      });

    expect([200, 201]).toContain(run.status);

    const taskId = task.body?.item?.id ?? task.body?.id;
    await h.request
      .post(`/api/client/tasks/${taskId}/complete`)
      .set(headers)
      .send({ completedAt: '2026-06-08T09:00:00.000Z' })
      .expect(201);

    const audit = await h.request.get('/api/admin/data/audit-logs?limit=20').set(headers).expect(200);
    expect(JSON.stringify(audit.body)).toContain('task');
  });
});
```

- [ ] **Step 3: Add Web cross-end E2E tests**

Create `web_admin/e2e/cross-end/files-ai-ops.spec.ts`:

```ts
import { expect, test } from '@playwright/test';
import { installAdminApiRoutes } from '../fixtures/adminApiRoutes';

test('CE-FILE-001 mocked Drive root scan is visible and recoverable', async ({ page }) => {
  await installAdminApiRoutes(page);
  await page.goto('/');

  await page.getByRole('menuitem', { name: /文件资料|files/i }).click();
  await page.getByRole('button', { name: /扫描|scan/i }).click();

  await expect(page.getByText(/completed|扫描完成|ok/i)).toBeVisible();
});
```

- [ ] **Step 4: Add Flutter cross-end integration skeleton**

Create `client_flutter/integration_test/cross_end_workflows_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import '../test/test_support/test_database.dart';
import '../test/test_support/provider_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CE-CAL-001 event appears across timeline week and month with fake data', (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);

    await pumpFlowPlanTestApp(
      tester,
      db: db,
      child: const FlowPlanV2App(),
    );

    await tester.tap(find.byKey(AppKeys.shellTimeline));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.shellWeek));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(AppKeys.shellMonth));
    await tester.pumpAndSettle();

    expect(find.byKey(AppKeys.shellMonth), findsOneWidget);
  });
}
```

- [ ] **Step 5: Verify cross-end automated tests**

Run Codex-allowed commands:

```powershell
cd server
npm run test:api -- src/cross-end/cross-end-workflows.api.spec.ts

cd ..\web_admin
npm run test:e2e -- --grep "CE-"
```

Ask the user to run:

```powershell
cd client_flutter
flutter test integration_test\cross_end_workflows_test.dart
```

Expected: server and web tests pass; user records Flutter result.

- [ ] **Step 6: Commit cross-end tests**

Run:

```powershell
git status --short
git add -- server/src/cross-end web_admin/e2e/cross-end client_flutter/integration_test/cross_end_workflows_test.dart docs/test-governance/cross-end-workflow-matrix.md docs/test-governance/external-services-acceptance.md docs/test-governance/feature-test-matrix.csv docs/test-governance/manual-acceptance.csv
git diff --cached --name-only
git commit -m "test: add cross-end workflow acceptance coverage"
```

Expected: staged files include only cross-end test and governance artifacts.

## Task 11: Flake Controls, Search Gates, And Performance Suite Separation

**Files:**
- Modify: `scripts/test-flowplanv2.ps1`
- Modify: `server/vitest.coverage.config.ts`
- Modify: `web_admin/vitest.config.ts`
- Modify: `docs/test-governance/flake-policy.md`
- Update: `docs/test-governance/feature-test-matrix.csv`

- [ ] **Step 1: Add forbidden pattern scan to root gate**

Add this function to `scripts/test-flowplanv2.ps1`:

```powershell
function Assert-NoFocusedOrSkippedTests {
  $matches = rg -n "\.only|describe\.only|it\.only|test\.only|fit\(|xit\(|\.skip\(" server web_admin client_flutter
  if ($LASTEXITCODE -eq 0) {
    Write-Host $matches
    throw 'Focused or skipped tests found. Record reviewed skips in docs/test-governance/feature-test-matrix.csv before committing.'
  }
}
```

Call it after matrix validation:

```powershell
Assert-NoFocusedOrSkippedTests
```

- [ ] **Step 2: Move performance tests out of default gates**

Classify these existing tests as performance or deterministic default tests:

```text
server/src/tracking/tracking.service.integration.spec.ts
server/src/files/local-object-storage.service.integration.spec.ts
client_flutter/test/heatmap_perf_test.dart
```

If a test asserts elapsed time, rename it or move it so default coverage gates exclude it:

```text
server/src/tracking/tracking.service.perf.spec.ts
server/src/files/local-object-storage.service.perf.spec.ts
client_flutter/test/perf/heatmap_perf_test.dart
```

Add matrix rows documenting each performance suite and manual/explicit command.

- [ ] **Step 3: Add explicit perf commands to docs**

Append to `docs/test-governance/flake-policy.md`:

```markdown
## Performance Suites

Performance tests are explicit suites. They are not part of the default root gate unless they use deterministic data, fixed machine-independent thresholds, and no wall-clock timing. Run performance suites from a clean local machine and record results in `docs/test-governance/manual-acceptance.csv`.
```

- [ ] **Step 4: Verify forbidden scan**

Run:

```powershell
rg -n "\.only|describe\.only|it\.only|test\.only|fit\(|xit\(|\.skip\(" server web_admin client_flutter
powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -SkipInstall -SkipWebE2E
```

Expected at completion: `rg` finds no focused or unreviewed skipped tests. Root script reaches server/web gates.

- [ ] **Step 5: Commit flake controls**

Run:

```powershell
git status --short
git add -- scripts/test-flowplanv2.ps1 server/vitest.coverage.config.ts web_admin/vitest.config.ts docs/test-governance/flake-policy.md docs/test-governance/feature-test-matrix.csv
git diff --cached --name-only
git commit -m "chore(test): enforce flake control gates"
```

Expected: staged files include gate and flake policy changes only.

## Task 12: Final A-Level Closeout

**Files:**
- Update: `docs/test-governance/feature-test-matrix.csv`
- Update: `docs/test-governance/coverage-exclusions.csv`
- Update: `docs/test-governance/manual-acceptance.csv`
- Create: `docs/test-governance/reports/generated/<timestamp>-root-quality-gate.md` but do not commit generated reports.

- [ ] **Step 1: Complete matrix statuses**

Run:

```powershell
Import-Csv docs\test-governance\feature-test-matrix.csv | Group-Object status | Select-Object Name,Count
Import-Csv docs\test-governance\coverage-exclusions.csv | Group-Object status | Select-Object Name,Count
Import-Csv docs\test-governance\manual-acceptance.csv | Group-Object status | Select-Object Name,Count
```

Expected: no feature or exclusion row remains `missing` when claiming full completion. Manual rows may remain `pending-user` only when user-run external device/credential validation is not yet complete.

- [ ] **Step 2: Run full automated root gate**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -Completion
```

Expected: automated server and web gates pass. Output includes Flutter commands as manual pending or user-confirmed.

- [ ] **Step 3: Ask user for Flutter final validation results**

Ask the user to run:

```powershell
cd client_flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --coverage
flutter test test/goldens
flutter test integration_test
```

Expected user result: pass logs or failure logs. Record results in `docs/test-governance/manual-acceptance.csv`.

- [ ] **Step 4: Record final acceptance summary**

Create a generated report under `docs/test-governance/reports/generated` with this shape:

```markdown
# FlowPlanV2 Root Quality Gate Report

Date: 2026-06-08

## Automated Gates

- Boundary: PASS
- Server build: PASS
- Server unit: PASS
- Server integration: PASS
- Server API: PASS
- Server coverage: PASS
- Web build: PASS
- Web unit/component: PASS
- Web coverage: PASS
- Web E2E: PASS

## Manual Flutter Gates

- flutter pub get: USER RECORDED RESULT
- dart run build_runner build --delete-conflicting-outputs: USER RECORDED RESULT
- flutter analyze: USER RECORDED RESULT
- flutter test --coverage: USER RECORDED RESULT
- flutter test test/goldens: USER RECORDED RESULT
- flutter test integration_test: USER RECORDED RESULT

## Evidence

- Server coverage report: `server/coverage/index.html`
- Web coverage report: `web_admin/coverage/index.html`
- Web E2E report: `web_admin/playwright-report/index.html`
- Flutter coverage report: `client_flutter/coverage/lcov.info`
```

Do not commit generated reports because `.gitignore` excludes them.

- [ ] **Step 5: Commit final governance state**

Run:

```powershell
git status --short
git add -- docs/test-governance/feature-test-matrix.csv docs/test-governance/coverage-exclusions.csv docs/test-governance/manual-acceptance.csv docs/test-governance/quality-gates.md docs/test-governance/future-development-rules.md
git diff --cached --name-only
git commit -m "docs(test): record A-level governance closeout"
```

Expected: generated reports remain unstaged; unrelated dirty files remain unstaged.

## Execution Order

1. Task 1: Governance Documents And Matrices.
2. Task 2: Root Quality Gate Script.
3. Task 3: Shared Determinism And Server Test Harness.
4. Task 4: Server Test Runners And Bootstrap Extraction.
5. Task 5: Server Coverage Waves.
6. Task 6: Web Admin Test Tooling.
7. Task 7: Web Admin Component, Page, And E2E Coverage.
8. Task 8: Flutter Testability Foundation.
9. Task 9: Flutter Business, Widget, Integration, Golden, And Manual Tests.
10. Task 10: Cross-End Workflow Acceptance.
11. Task 11: Flake Controls, Search Gates, And Performance Suite Separation.
12. Task 12: Final A-Level Closeout.

## Verification Summary

Codex-run commands:

```powershell
cd server
npm run build
npm run test:all
npm run test:coverage

cd ..\web_admin
npm run build
npm run test
npm run test:coverage
npm run test:e2e

cd ..
powershell -ExecutionPolicy Bypass -File scripts\check-client-server-boundary.ps1 -FailOnViolation
powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -Completion
rg -n "\.only|describe\.only|it\.only|test\.only|fit\(|xit\(|\.skip\(" server web_admin client_flutter
```

User-run Flutter commands:

```powershell
cd client_flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --coverage
flutter test test/goldens
flutter test integration_test
flutter run -d windows
flutter devices
flutter run -d <android-device-id>
```

## Plan Self-Review

- Spec sections 5 through 15 map to tasks: coverage rule to Tasks 4, 5, 7, 9, and 12; server to Tasks 3 through 5; web admin to Tasks 6 and 7; Flutter to Tasks 8 and 9; matrix to Tasks 1 and 12; root gate to Task 2; cross-end acceptance to Task 10; future rules and risks to Tasks 1, 11, and 12.
- Flutter commands are labelled user-run and are never executed by Codex.
- Exclusion records include pattern, reason, replacement verification, owner/module, review condition, and status.
- Commit steps avoid `git add .` and keep `client_flutter/windows/CMakeLists.txt` out of staging.
