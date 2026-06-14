# Online-Primary Read-Only Cache Closeout

Date: 2026-06-14
Executor: Codex with four focused coverage workers
Branch: codex/online-primary-read-only-cache
Commit range: pending final commits

## Scope

- Online-primary read-only cache policy.
- Ordinary task, event, and business writes require server success before local cache mutation.
- Startup and periodic cache refresh are pull-only for server-owned facts.
- Tracking uploads every 60 seconds, deletes confirmed rows, and retains failed or rejected rows.
- File uploads require an online server session before local upload jobs.
- Legacy `offline_mutations` rows remain inspectable and are not replayed automatically.

## Automated Evidence

| Gate | Command | Result | Evidence |
| --- | --- | --- | --- |
| Focused LCOV gap batch | `cd client_flutter; flutter test test/features/calendar/calendar_books_repository_calendar_ui_test.dart test/features/calendar/calendar_gap8_worker_repository_test.dart test/features/files/file_context_repository_test.dart test/widgets/tracker_presentation_remaining_gaps_test.dart --concurrency=1` | PASS | 2026-06-13: 51 focused tests passed. Covered runtime calendar fallback, file no-sync folder preservation, tracker task anchor tie-breaker, and default process starter provider. |
| Tracker timer regression | `cd client_flutter; flutter test test/features/tracker/tracker_gap6_worker_service_test.dart --concurrency=1` | PASS | 2026-06-13: 4 tests passed after stabilizing the auto-upload in-flight assertion. |
| Flutter analyze | `cd client_flutter; flutter analyze` | PASS | 2026-06-13: no issues found after final client edits. |
| Flutter full coverage | `cd client_flutter; flutter test --no-pub --coverage -x golden --concurrency=1 --file-reporter json:.codex-tmp\flutter-full-current-5.jsonl` | PASS | 2026-06-13: 1488 tests passed; refreshed `client_flutter/coverage/lcov.info`. |
| Flutter LCOV included-line parse | reviewed `docs/test-governance/coverage-exclusions.csv` applied to `client_flutter/coverage/lcov.info` | PASS | 2026-06-13: 100% included-line coverage, 30587/30587 covered, 0 missing; 11 reviewed exclusion records / 3642 excluded generated or DSL lines. |
| Governance-only | `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -GovernanceOnly` | PASS | 2026-06-13: governance matrix validation, focused/skipped test scan, root gate timeout unit, timeout probe, Flutter LCOV threshold, exclusion alignment, and manual-pending matrix behavior passed. |
| Server focused | `cd server; npm run test:unit -- src/files/files.service.unit.spec.ts src/tracking/tracking.service.unit.spec.ts src/web/web.service.unit.spec.ts` | PASS | 2026-06-13: 3 test files passed, 83 tests passed. |
| Root full gate | `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800` | PASS | 2026-06-13: exit code 0. Governance, boundary scan, server build/unit/integration/API/coverage, web build/unit/coverage/e2e, Flutter pub/build_runner/analyze/unit-widget coverage, golden, and Windows integration gates completed under the root gate. Server coverage 100%; web coverage 100%; Playwright e2e 11/11 passed. |
| Completion gate | `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800` | BLOCKED | 2026-06-14: completion mode remains blocked by open manual-acceptance rows. Online-primary blockers: `MANUAL-ONLINE-PRIMARY-001`, `MANUAL-TRACK-ONLINE-001`, `MANUAL-FILE-ONLINE-001`. The global matrix also still has earlier pending manual rows. |

## Coverage Artifacts

- Server coverage: PASS in root full gate, 100% statements/branches/functions/lines.
- Web admin coverage: PASS in root full gate, 100% statements/branches/functions/lines.
- Flutter LCOV: PASS, 100% included-line coverage after reviewed exclusions, `client_flutter/coverage/lcov.info`.
- Flutter JSONL reporter: `client_flutter/.codex-tmp/flutter-full-current-5.jsonl`.
- Golden reports: exercised by the passing root full gate.
- Windows integration evidence: exercised by the passing root full gate with `-FlutterIntegrationDevice windows`.

## Matrix Updates

- `docs/test-governance/feature-test-matrix.csv`: rows added or updated: `CLIENT-ONLINE-PRIMARY-001`, `CLIENT-ONLINE-PRIMARY-002`, `CLIENT-ONLINE-PRIMARY-003`, `CLIENT-TRACK-ONLINE-001`, `CLIENT-FILE-ONLINE-001`, `SERVER-ONLINE-PRIMARY-001`, `CE-ONLINE-PRIMARY-001`.
- `docs/test-governance/manual-acceptance.csv`: rows added or updated: `MANUAL-ONLINE-PRIMARY-001`, `MANUAL-TRACK-ONLINE-001`, `MANUAL-FILE-ONLINE-001`.
- `docs/test-governance/cross-end-workflow-matrix.md`: rows added or updated: Online-primary offline cache; Tracking minute batch cleanup; Server-hosted file upload boundary.
- `docs/test-governance/coverage-exclusions.csv`: no new exclusions added for this feature; existing reviewed Flutter exclusions were applied when calculating included-line coverage.

## Source Scans

- Ordinary queue search: `rg -n "queueLegacyCacheMutation|enqueueBusinessMutation|recordCreate\(|recordUpdate\(|recordDelete\(" client_flutter/lib`
- Result: normal app providers no longer inject `SyncWriteRecorder` into server-managed task/event/file context repositories. Remaining matches are legacy/cache repository implementations, audit/device-local paths, and the explicit `queueLegacyCacheMutation` migration hook.
- Pending-success copy search: `rg -n "<legacy pending-sync mojibake strings>|isPending|Saved to this device|pending local" client_flutter/lib`
- Result: no stale ordinary-write pending-success copy found.

## Manual Acceptance

Detailed execution steps for the three online-primary manual rows are recorded
in `docs/test-governance/manual-acceptance-online-primary-runbook-20260613.md`.

| Manual ID | Status | Evidence |
| --- | --- | --- |
| MANUAL-ONLINE-PRIMARY-001 | pending-user | Real disconnected Windows cache workflow not yet executed. |
| MANUAL-TRACK-ONLINE-001 | pending-user | Real tracking minute-batch cleanup not yet executed. |
| MANUAL-FILE-ONLINE-001 | pending-user | Real file interruption, resume, and hash verification not yet executed. |

## Completion Gate Blocker

Completion cannot be claimed while manual acceptance rows remain `pending-user`. Current open manual rows:

`MANUAL-WIN-001`, `MANUAL-WIN-002`, `MANUAL-WIN-003`, `MANUAL-ANDROID-001`, `MANUAL-ANDROID-002`, `MANUAL-OUTLOOK-001`, `MANUAL-OUTLOOK-002`, `MANUAL-AI-001`, `MANUAL-AI-002`, `MANUAL-FILE-002`, `MANUAL-LONGTRACK-001`, `MANUAL-AUDIT-001`, `MANUAL-ONLINE-PRIMARY-001`, `MANUAL-TRACK-ONLINE-001`, `MANUAL-FILE-ONLINE-001`.

Current manual acceptance counts: `passing=3`, `pending-user=15`. `MANUAL-FILE-001` and `MANUAL-GEN-DRIFT-001` now have dated passing evidence and are no longer completion blockers.

## Open Risks

- Completion cannot be claimed while linked online-primary manual rows are `pending-user`.
- Completion cannot be claimed while the broader governance matrix still has open manual acceptance rows.
- `CLIENT-ONLINE-PRIMARY-*`, `CLIENT-TRACK-ONLINE-001`, `CLIENT-FILE-ONLINE-001`, and `CE-ONLINE-PRIMARY-001` must remain `partial` until dated manual evidence is recorded.
