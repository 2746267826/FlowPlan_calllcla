# FlowPlanV2 Quality Gates

The root gate is `scripts/test-flowplanv2.ps1`. Server and Web Admin coverage gates enforce 100% lines, branches, functions, and statements through their package coverage commands. Flutter/Dart coverage is enforced from `client_flutter/coverage/lcov.info` as line coverage: the root gate parses real `DA`/`LH` and `LF` data, fails below 100% included-line coverage, and reports the actual covered/total line count instead of assuming a pass.

Every excluded file or pattern must have a reviewed row in `docs/test-governance/coverage-exclusions.csv` with `pattern`, `reason`, `replacement_verification`, `owner_or_module`, `review_condition`, and `status`. Rows left as `missing` are not accepted for completion closeout.

The root gate validates all governance CSV matrices before running product suites:

- `feature-test-matrix.csv` must have required columns, unique `test_id` values, supported statuses, and valid `manual_acceptance_id` references.
- `manual-acceptance.csv` must have required columns, including buttons or controls, status states, error paths, side effects, steps, and evidence; unique `manual_id` values; and one of `pending-user`, `passing`, `failed`, `blocked`, or `blocked-environment`. Passing manual rows must include a dated evidence note.
- `coverage-exclusions.csv` must have required columns, unique `pattern` values, and one of `reviewed`, `pending-review`, `planned`, or `missing`.
- Feature rows that reference a manual acceptance row can only be `verified` or `implemented` when that manual row is `passing`; rows with pending or blocked manual evidence must stay `partial`, `planned`, `pending-user`, or `blocked-environment`.
- Every actual exclusion pattern used by the root focused/skipped scan must have an exact reviewed row in `coverage-exclusions.csv`.

`-Completion` fails while any feature row remains `missing`, `planned`, `pending-user`, `blocked-environment`, or `partial`; any manual row remains anything other than `passing`; or any coverage exclusion row remains anything other than `reviewed`. Completion mode must run the full root gate and cannot be combined with `-GovernanceOnly`, `-SkipInstall`, `-SkipWebE2E`, or `-SkipFlutterIntegration`. Completion mode also requires `-FlutterIntegrationDevice windows`; Chrome and Edge runs are diagnostic only.

`.github/workflows/root-quality-gate.yml` runs the governance gate and the completion gate on Windows. The completion job is expected to fail while this repository still has open manual acceptance rows or Flutter LCOV below 100%; that failure is the release blocker, not a flaky CI condition.

Use `-GovernanceOnly` to run matrix validation and the focused/skipped scan without starting boundary, server, web, or Flutter product suites. Each product gate has a wall-clock timeout controlled by `-GateTimeoutSeconds`, defaulting to 900 seconds, so a hung build, browser, or Flutter device launch fails the gate instead of running indefinitely.

Generated report locations:

- Server coverage: `server/src/coverage/index.html`
- Web admin coverage: `web_admin/coverage/index.html`
- Web admin E2E report: `web_admin/playwright-report/index.html`
- Flutter coverage: `client_flutter/coverage/lcov.info`
- Root summaries: `docs/test-governance/reports/generated`

The root gate fails for automated server, web, and Flutter/Dart failures. After the latest user authorization on 2026-06-08, Codex may run Flutter and Dart validation in this repository.

Flutter gate stages:

- `flutter pub get`, unless `-SkipInstall` is passed.
- `dart run build_runner build --delete-conflicting-outputs`.
- `flutter analyze`.
- `flutter test --no-pub --coverage -x golden --concurrency=1`.
- `client_flutter/coverage/lcov.info` is parsed after the Flutter coverage run and must show 100% included Dart line coverage. Only reviewed `coverage-exclusions.csv` rows owned by `client_flutter` are excluded from the Flutter included-line denominator; root scan exclusions must not hide Flutter product code. Missing, empty, or all-excluded LCOV evidence fails.
- `flutter test --no-pub test/goldens/<file> -r expanded --concurrency=1`, once for each `client_flutter/test/goldens/*_golden_test.dart` file; golden tests are tagged `golden` and run outside the coverage suite.
- `flutter test --no-pub -d windows integration_test/<file> --concurrency=1`, once for each `client_flutter/integration_test/*_test.dart` file, using `-FlutterIntegrationDevice windows`. Chrome and Edge attempts are diagnostic only and are recorded as `blocked-environment`, not completion evidence.

`-SkipFlutterIntegration` records an explicit skipped gate and is not allowed with `-Completion`. Windows integration launch evidence passed after the desktop manifest was corrected to `asInvoker`; Chrome or Edge remain unsupported choices for Flutter integration tests. Real device, credential, external service, notification, long-running, and platform-blocked acceptance remains manual, `pending-user`, or `blocked-environment` evidence.

The focused/skipped scan runs before automated suites with `rg --no-ignore`, so exclusions come from the reviewed root gate ledger instead of implicit `.gitignore` behavior. It checks JS focused or skipped tests such as `test.only`, `describe.skip`, `fit`, and `xit`, plus Dart and Flutter skip markers such as `skip: true`, string skip reasons, `@Skip`, and `markTestSkipped`. Generated, dependency, cache, report, screenshot, and build artifacts such as `**/build/**`, `**/dist/**`, `**/coverage/**`, `**/coverage-*/**`, `**/.codex-tmp/**`, `**/node_modules/**`, `web_admin/playwright-report/**`, `web_admin/test-results/**`, and `docs/test-governance/reports/generated/**` stay out of that scan; broad `**/reports/**` and `**/report/**` exclusions are forbidden because they can hide product modules such as `client_flutter/lib/features/reports/**`. New generated or build output locations require a reviewed ledger row before they are treated as excluded.
