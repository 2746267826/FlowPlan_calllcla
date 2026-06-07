# FlowPlanV2 Full Test Governance Design

Date: 2026-06-08
Status: Approved for planning
Owner: FlowPlanV2

## 1. Purpose

FlowPlanV2 has grown into a three-end product with a NestJS server, React web admin, and Flutter client. Current testing is incomplete: the server has a small Vitest base, the web admin has no dedicated test runner, and the Flutter client only has minimal smoke/performance tests.

This design establishes an A-level test governance system:

- Every hand-written production code path must target 100% line, branch, function, and statement coverage.
- Every user-visible feature, button, input, menu, dialog, drawer, table action, route, state, and workflow must have an automated test or a recorded manual/real-device acceptance item.
- Future development is incomplete unless it updates tests, coverage evidence, and the feature-to-test matrix.

The goal is not cosmetic coverage. Tests must prove that behavior works for real users, that failure states are handled, and that data is not corrupted.

## 2. Current Context

The repository contains:

- `server`: NestJS, PostgreSQL, Vitest, and some existing service/database tests.
- `web_admin`: React, Vite, Ant Design, and build scripts, but no test scripts.
- `client_flutter`: Flutter, Riverpod, go_router, Drift/SQLite, and minimal `flutter_test` tests.

Important existing constraint:

- `docs/development_constraints_260426.md` says Codex must not run `flutter` or `dart` commands in this repository. Flutter validation commands must be listed for the user to run manually.

Existing dirty worktree note:

- `client_flutter/windows/CMakeLists.txt` was already modified before this design work. This design does not rely on or change that file.

## 3. Scope

In scope:

- Repository-level test governance and quality gates.
- Server unit, integration, database, API, and error-path tests.
- Web admin component tests and browser-level user workflow tests.
- Flutter logic, widget, page, integration, golden/layout, and manual real-device validation.
- Cross-end workflows that represent real use: tasks, schedules, tracking, files, sync, conflicts, reports, AI drafts, audits, admin operations, and settings.
- A mandatory feature-to-test matrix.
- A future development rule that no feature is complete without tests and evidence.

Out of scope:

- Testing third-party package internals.
- Testing generated source text directly, such as Drift generated files. Generated behavior must still be validated through repository/database/API tests.
- Replacing manual real-device validation for platform capabilities that cannot be reliably automated in this environment.

## 4. Testing Strategy

Use the recommended approach: coverage gates and user behavior matrices advance together.

Each feature must be represented by:

- Code tests: unit, integration, or API tests covering implementation behavior.
- User behavior tests: UI or workflow tests proving that users can operate the feature.
- Failure tests: validation, empty state, loading state, permission failure, network/API failure, duplicate submission, timeout, and unavailable external service behavior.
- Acceptance evidence: automated report or manual/real-device checklist entry.

Coverage alone is insufficient. A line can be covered while the user flow remains broken, so every page and workflow also needs user-level assertions.

## 5. Coverage Rule

Hand-written production code must target:

- Lines: 100%
- Branches: 100%
- Functions: 100%
- Statements: 100%

Allowed exclusions must be explicit and reviewed:

- Third-party packages.
- Generated code text.
- Build artifacts.
- Platform glue that cannot run in the current automation environment, if covered through higher-level behavior tests or manual real-device acceptance.

Every exclusion must appear in the test matrix with:

- File or pattern.
- Reason for exclusion.
- Replacement verification method.
- Owner or module.
- Expiry or review condition.

## 6. Server Test Design

The server keeps Vitest as the primary runner and expands into distinct suites:

- Unit tests for pure services, utilities, validation, mappers, schedulers, report templates, and policy logic.
- Database integration tests against the isolated `flowplantest` database.
- API/controller tests with `supertest`.
- Error handling tests for filters, guards, interceptors, DTO validation, auth failures, database failures, and external dependency failures.
- Contract-like tests for client-facing and admin-facing response shapes.

Required server module coverage:

- `auth`
- `devices`
- `sync`
- `files`
- `tracking`
- `analytics`
- `activity-understanding`
- `scheduler`
- `reports`
- `ai`
- `models`
- `admin`
- `client`
- `web`
- `outlook`
- `database`
- `common` utilities, errors, config, audit, schemas, constants, logger, request context

Server scripts must include:

- `test:unit`
- `test:integration`
- `test:api`
- `test:coverage`
- `test:all`

Database tests must:

- Use a test database only.
- Clean test data between tests.
- Avoid production credentials and production data.
- Fix time, random IDs, and external responses where deterministic assertions are needed.

## 7. Web Admin Test Design

The web admin needs a dedicated automated test stack:

- Vitest for component/page tests.
- React Testing Library for DOM assertions.
- `@testing-library/user-event` for user interactions.
- `@testing-library/jest-dom` for readable matchers.
- jsdom for component tests.
- MSW or an equivalent API mock layer for deterministic server responses.
- Playwright for browser-level end-to-end workflows.

Every page must have tests for:

- Initial load.
- Loading state.
- Empty state.
- Successful data rendering.
- API failure state.
- Refresh action.
- Navigation entry.
- Every button, menu item, tab, table operation, filter, search box, form input, switch, confirmation dialog, cancel action, submit action, drawer, modal, pagination control, and export/download action when present.

Required web admin page coverage:

- Dashboard
- Business/data list pages
- Tasks and schedules
- Devices
- Drive/files
- Sync/conflicts
- Outlook
- Audit
- Reports
- AI
- Models
- Jobs
- Logs
- Alerts
- Settings
- Environment variables
- Operations

Stable selectors are required:

- Add `data-testid` for controls that cannot be selected robustly by accessible role/name.
- Prefer accessible role/name queries when they identify the target unambiguously.
- Tests must assert behavior, not just that a button exists.

Browser tests must cover complete user workflows such as:

- Login or saved admin context.
- Open a page.
- Interact with controls.
- Verify requests or mocked responses.
- Verify state changes in the UI.
- Verify error handling.
- Verify cancellation leaves data unchanged.

## 8. Flutter Client Test Design

The Flutter client needs layered tests:

- Business logic tests for repositories, services, sync engines, API clients, parsers, schedulers, classifiers, and data transformation.
- Widget tests for reusable components and pages.
- Page flow tests for navigation and user interaction.
- Golden/layout tests for key screens and common Windows/Android dimensions.
- `integration_test` flows for real user journeys.
- Manual/real-device acceptance for platform features that cannot be reliably automated by Codex in this repository.

Required Flutter areas:

- Calendar: timeline, week, month, event detail, calendar books.
- Task: quick add, detail, unscheduled panel, task evidence.
- Tracking: tracker page, activity review, day details, log history, input history, input heatmap.
- Reports: report center and generation behavior.
- Files: file context, transfer center, local identity, transfer service.
- Sync: server sync, Outlook sync, offline queue, conflict handling.
- iCalendar import/export.
- Audit and data management.
- AI chat and controlled operations.
- Settings.
- Platform bootstrap and server connection state.
- Database tables/repositories and migrations through behavior tests.

Stable Flutter selectors are required:

- Add `Key` values for controls and page regions that need reliable test targeting.
- Prefer semantic labels where user-facing accessibility also benefits.

Codex execution limitation:

- Codex must not run `flutter analyze`, `flutter test`, `flutter pub get`, `dart format`, `dart run build_runner build`, or similar commands.
- The implementation must provide exact commands for the user to run manually.
- The acceptance report must distinguish Codex-run checks from user-run Flutter checks.

## 9. User Interaction Matrix

A required matrix file will map each feature and control to tests.

Each row must contain:

- Test ID.
- Product area: server, web admin, Flutter client, cross-end.
- Module/page/route.
- User-facing feature.
- Control or API.
- Happy-path test.
- Failure-path test.
- Data integrity assertion.
- Accessibility or layout assertion when relevant.
- Automated test file.
- Manual/real-device acceptance item if needed.
- Status: missing, planned, implemented, passing, blocked, excluded.
- Notes and exclusion reason if any.

Example:

```text
WEB-AUDIT-001 | web_admin | AuditPage | Load audit list | route load | component + Playwright | API failure | no data mutation | src/pages/AuditPage.test.tsx | none | planned
WEB-AUDIT-002 | web_admin | AuditPage | Refresh audit list | refresh button | user-event + mocked API assertion | API timeout | no data mutation | src/pages/AuditPage.test.tsx | none | planned
CLIENT-TASK-001 | client_flutter | Task detail | Complete task | complete button | widget + integration | duplicate tap/network fail | task state and audit/sync mutation recorded | test/features/task/task_detail_test.dart | Windows/Android smoke | planned
SERVER-SYNC-001 | server | SyncService/API | Push mutation | POST /sync/push | service + API + DB | conflict/idempotency failure | sync_objects/sync_changes consistent | src/sync/*.spec.ts | none | planned
```

The matrix is a gate. A feature without a matrix row is not considered tested.

## 10. Root Quality Gate

Add this repository-level test command:

- `scripts/test-flowplanv2.ps1`

The script must:

- Run server install/build/test/coverage checks, failing with a clear setup error if required local services are unavailable.
- Run web admin install/build/unit/component/E2E/coverage checks, failing with a clear setup error if required local services are unavailable.
- Run existing boundary checks.
- Print Flutter commands that the user must run manually.
- Fail when any automated non-Flutter gate fails.
- Produce or point to coverage reports.

Flutter commands to list for manual execution include:

```powershell
cd client_flutter
flutter analyze
flutter test --coverage
flutter test integration_test
```

Additional manual commands may be added for golden tests, build runner, Windows desktop smoke, Android device smoke, and release validation when those suites are introduced.

## 11. Cross-End Workflow Acceptance

Cross-end tests and acceptance scenarios must cover:

- Create task, schedule it, edit it, complete it, and observe audit/sync effects.
- Create calendar event, edit it, delete it, and verify calendar views update.
- Offline mutation push/pull/ack and conflict resolution.
- Tracking ingest, activity understanding, actual record creation, and report evidence use.
- File context, upload/download session behavior, version/history behavior, and failure recovery.
- AI provider test, chat, operation draft creation, reject, approve, execute, and audit.
- Admin review flows for dashboard, alerts, logs, jobs, settings, environment, and operations.
- Outlook configuration and sync, with real external credentials covered by manual acceptance.

External services default to mock in automated tests. Real AI provider, Outlook, notification, file picker, Windows shell, Android usage stats, and long-running tracking scenarios require manual/real-device acceptance entries.

## 12. Execution Phases

The implementation must be split into phases, but each phase must leave verifiable artifacts.

Phase 1: Test foundation

- Add test scripts and dependencies.
- Add coverage gates.
- Add shared fixtures/mocks.
- Add matrix template and documentation.

Phase 2: Full function inventory

- Scan server modules, web pages, Flutter routes/widgets/services.
- Create the first complete matrix of features, controls, tests, and gaps.

Phase 3: Server coverage completion

- Fill unit, integration, database, API, and failure tests until coverage gates pass.

Phase 4: Web admin coverage completion

- Fill component tests and Playwright user workflow tests for every page and control.

Phase 5: Flutter coverage completion

- Fill logic, widget, page, integration, golden/layout tests.
- Provide manual command list and real-device acceptance scripts.

Phase 6: Cross-end workflow completion

- Validate representative real workflows across API, admin, and client boundaries.

Phase 7: Governance closeout

- Publish coverage reports.
- Publish missing/excluded/blocked list.
- Publish manual acceptance report.
- Make the future development rule visible in developer documentation.

## 13. Future Development Rule

All future development must follow these rules:

- Register impacted features, controls, APIs, data, and workflows in the test matrix before completion.
- Add or update tests with the feature change.
- Bug fixes require a regression test that fails before the fix or a clear explanation when reproduction is only manual.
- Hand-written production code must meet 100% coverage gates.
- User-visible behavior must have automated user tests or a manual/real-device acceptance item.
- Failure states must be tested, not only happy paths.
- Exclusions must be documented with replacement verification.
- Completion reports must include test files changed, coverage results, user-flow validation, and manual commands the user still needs to run.

Development is not complete when code compiles. Development is complete only when behavior is verified and the verification is repeatable.

## 14. Risks And Controls

Risk: 100% coverage can create brittle tests.

Control: Tests must assert meaningful behavior, not implementation details. Snapshot and golden tests should be used deliberately, not as a substitute for interaction assertions.

Risk: UI tests become flaky.

Control: Use stable selectors, fixed clocks, deterministic API mocks, and limited reliance on animations/timing.

Risk: External services make tests unreliable.

Control: Automated tests mock external services by default. Real credentials and real devices are manual acceptance.

Risk: The full scope is large.

Control: Use phases and matrix statuses. A phase is complete only when its artifacts and gates are present.

Risk: Generated code affects behavior but is excluded from coverage.

Control: Test generated-code usage through repository, database, API, widget, or workflow behavior.

## 15. Acceptance Criteria

The full initiative is complete only when:

- Server automated coverage reaches 100% for included hand-written production code.
- Web admin automated coverage reaches 100% for included hand-written production code.
- Flutter tests are written for all included hand-written code, widgets, pages, and flows, and the user-run command results are recorded.
- Every web admin page and Flutter page has a user interaction matrix.
- Every button/control/flow has an automated test or manual/real-device acceptance entry.
- Failure states are covered for every high-risk feature.
- Cross-end workflows have repeatable tests or acceptance scripts.
- Exclusions are documented and justified.
- Future development documentation requires tests before completion.
- The root quality gate can be run and produces clear pass/fail output.
