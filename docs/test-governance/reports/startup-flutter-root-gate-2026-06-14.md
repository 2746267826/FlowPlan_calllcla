# Startup and Flutter Root Gate Verification

Date: 2026-06-14
Executor: Codex
Workspace: `C:\Users\a2746\Desktop\calll260426`

## Scope

- Verify the user launcher: `start-flowplanv2-all.cmd`.
- Confirm the server startup error is no longer emitted by the default launcher path.
- Confirm Flutter Android compilation no longer fails on the removed `usage_stats` plugin registration.
- Re-run the root automated quality gate for the broadest machine-verifiable coverage.
- Confirm whether completion can be claimed under the project test-governance rules.

## Fixes Verified

| Area | Change | Evidence |
| --- | --- | --- |
| Flutter Android plugin registration | Removed unused `usage_stats` dependency; Android usage data uses the project `MethodChannel('com.flowplanv2.app/android_usage_stats')` instead. | `flutter build apk --debug --split-per-abi` passed and produced all debug APK variants. |
| Launcher warning behavior | `scripts/start-flowplanv2-all.ps1` hides Node warnings by default and exposes `-ShowNodeWarnings` for diagnostics. | Launcher log for `logs\20260614_030459` contains no `NativeCommandError`, `DEP0190`, `UsageStatsPlugin`, or `cannot find symbol` matches. |
| Date-sensitive Flutter tests | Stabilized tests that assumed a hard-coded future date or dense events on `today + 1 day`. | `flutter test --concurrency=1` passed with 1490 tests. |

## Direct Startup Evidence

| Command | Result | Notes |
| --- | --- | --- |
| `cmd /c start-flowplanv2-all.cmd -NoPause -SkipRunFlutterWeb` | PASS | Ran schema, reused healthy server/admin ports, built Flutter Windows, Flutter Web, and split debug APKs. Flutter Web runtime was skipped to avoid opening Chrome during verification. |
| `Invoke-RestMethod http://127.0.0.1:3202/api/health` | PASS | Returned `ok: true`; database check returned `connected: true`. |
| `Invoke-WebRequest http://127.0.0.1:5174` | PASS | Returned HTTP 200 and the admin HTML shell. |

## Focused Verification

| Command | Result |
| --- | --- |
| `cd client_flutter; flutter test test\web_app\flowplanv2_web_app_gap2_worker_web_test.dart --plain-name "events toolbar refreshes moves across ranges and renders dense week" --concurrency=1` | PASS |
| `cd client_flutter; flutter test test\widgets\calendar_gap9_worker_calendar_test.dart --plain-name "future manual schedule range can be rejected without applying" --concurrency=1` | PASS |
| `cd client_flutter; flutter test --concurrency=1` | PASS, 1490 tests |
| `cd client_flutter; flutter analyze` | PASS |
| `cd client_flutter; flutter build apk --debug --split-per-abi` | PASS |
| `cd server; npm run build` | PASS |
| `cd server; npm run test:unit` | PASS, 70 files / 868 tests |
| `cd server; npm start` after `npm run build`, with `PORT=3298` | PASS | Production entrypoint served `/api/health`; `server/package.json` and `server/Dockerfile` now point at `dist/src/main.js`. |
| `cd web_admin; npm run build` | PASS with existing Vite/AntD chunk warnings |
| `cd web_admin; npm test` | PASS, 17 files / 137 tests |
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -GovernanceOnly` | PASS |

## Root Gate Evidence

| Command | Result | Coverage |
| --- | --- | --- |
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800` | PASS | Governance, boundary scan, server install/build/unit/integration/API/coverage, web install/build/unit/coverage/e2e, Flutter pub/build_runner/analyze/unit-widget coverage, golden, and Windows integration gates. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -SkipInstall -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800` | PASS | Fresh 2026-06-14 08:23 run against the current worktree. Covered governance, boundary scan, server build/unit/integration/API/coverage, web build/unit/coverage/e2e, Flutter build_runner/analyze/unit-widget coverage, golden, and Windows integration gates. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -SkipInstall -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800` | PASS | Fresh 2026-06-14 09:13 run against the current worktree. Covered governance, boundary scan, server build/unit/integration/API/coverage, web build/unit/coverage/e2e, Flutter build_runner/analyze/unit-widget coverage, golden, and Windows integration gates. |

The root gate reported:

- Server coverage: 100% statements, branches, functions, and lines.
- Web admin coverage: 100% statements, branches, functions, and lines.
- Web e2e: 11/11 Playwright tests passed.
- Fresh 08:23 run also reported server coverage at 100%, web admin coverage at 100%, and Web e2e 11/11 passing.
- Fresh 09:13 run reported server unit 70 files / 868 tests, server integration 8 files / 70 tests, server API 3 files / 6 tests, server coverage 81 files / 944 tests at 100%, web unit and coverage 17 files / 137 tests at 100%, and Web e2e 11/11 passing.

## Completion Gate Status

| Command | Result |
| --- | --- |
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800` | FAIL, blocked by open manual acceptance rows only. |

Completion mode reported these open manual rows:

`MANUAL-WIN-001`, `MANUAL-WIN-002`, `MANUAL-WIN-003`, `MANUAL-ANDROID-001`, `MANUAL-ANDROID-002`, `MANUAL-OUTLOOK-001`, `MANUAL-OUTLOOK-002`, `MANUAL-AI-001`, `MANUAL-AI-002`, `MANUAL-FILE-002`, `MANUAL-LONGTRACK-001`, `MANUAL-AUDIT-001`, `MANUAL-ONLINE-PRIMARY-001`, `MANUAL-TRACK-ONLINE-001`, `MANUAL-FILE-ONLINE-001`.

Current manual acceptance counts: `passing=3`, `pending-user=15`.

## Conclusion

The startup-script error and Flutter compilation failure are fixed under current automated evidence. The broad automated root gate passes. The full thread goal cannot yet be marked complete because the project governance rules still require dated manual evidence for 15 real-device, real-credential, external-service, long-running, cleanup-audit, or interruption/resume workflows.
