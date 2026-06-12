# Cross-End Workflow Matrix

This matrix records representative flows that cross the server, web admin, and Flutter client boundaries. Automated coverage uses deterministic mocks and test databases; real credentials, real devices, and long-running platform checks stay in manual acceptance.

| Workflow | Test IDs | Automated Mock-Based Tests | Manual / Real Acceptance |
| --- | --- | --- | --- |
| Task schedule edit complete audit sync | CE-TASK-001 | Server API skeleton and Web Playwright skeleton with mocked API | Windows client creates and completes a task; Web Admin verifies status, sync mutation, and audit row |
| Calendar create edit delete views | CE-CAL-001 | Server API and Flutter fake API integration skeletons | Windows and Android event appears and disappears across timeline, week, and month |
| Offline sync conflict resolution | CE-SYNC-001 | Server two-device stale version API tests | Real offline write, reconnect, Web Admin conflict resolution, no silent overwrite |
| Tracking activity report | SERVER-TRACKING-001, CLIENT-TRACK-001 | Server ingest, understanding, report API tests, and Flutter tracker integration | Windows tracking for 30 minutes, upload, confirm activity, generate report |
| Files transfer version recovery | CE-FILE-001 | Server file session API and Web mocked drive flow | Real 10 MB transfer interruption and hash verification |
| AI draft approval audit | CE-AI-001 | Server mocked AI response and Web mocked operation approval | Real AI provider creates task draft, user approves, audit row exists |
| Report generation audit evidence | CE-REPORT-001 | Web mocked report workflow and audit visibility | Real AI-backed report generation and audit row verification |
| Admin operations evidence | WEB-E2E-001, WEB-DASHBOARD-001, WEB-TASKS-001 | Web Playwright mocked dashboard, alerts, logs, jobs, settings, env, operations | Operator runs one safe operation, job trigger, and settings save |
| Outlook external services | CE-EXT-001 | Web mocked Outlook auth, sync, reset, and diagnostics flows | Real Microsoft OAuth and read-only sync |

## Coverage Notes

- Central matrix CSV rows now record Flutter/Dart command evidence where available and keep real device or credential acceptance as `pending-user` or `blocked-environment`. This matrix lists representative CSV row IDs; it does not imply unexpanded `*-002` through `*-00N` rows exist unless they are present in `feature-test-matrix.csv`.
- The server API skeleton uses the Worker 2 `createApiTestApp` harness now present in `server/src/common/test/api-test-app.ts`.
- The web Playwright skeleton keeps its route mocks local to `web_admin/e2e/cross-end`.
- The Flutter skeleton uses test support and `AppKeys`; Flutter unit/widget coverage and golden tests are verified, and Windows desktop integration now passes when each `integration_test/*_test.dart` file runs individually with the desktop runner manifest set to `asInvoker`. Real devices, real credentials, external services, notifications, and long-running checks remain manual acceptance.
