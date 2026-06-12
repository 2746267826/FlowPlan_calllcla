# Future Development Rules

Every feature change, bug fix, refactor, and behavior change must update `docs/test-governance/feature-test-matrix.csv` before it is considered complete.

Every pull request must complete `.github/PULL_REQUEST_TEMPLATE.md`. The checklist is part of the development gate: authors must identify the changed controls or APIs, name the automated tests or manual evidence that cover them, and leave matrix rows open when evidence is still pending.

New product code requires an effective automated test first. The test must exercise the real behavior, fail for the missing behavior or reproduced defect before the fix, and pass after the implementation. Tests added only as documentation or broad smoke checks do not satisfy this rule.

User-facing flows must have automated coverage for:

- The visible button, menu item, form field, keyboard route, API command, or background trigger that starts the flow.
- Loading, empty, success, disabled, permission-denied, validation-error, network-error, API-error, duplicate-submission, and external-service-failure states that apply to the flow.
- Data integrity and side effects, including persistence, sync queues, audit rows, generated files, scheduled notifications, cleanup, redaction, and cross-end propagation.
- Accessibility or layout assertions through roles, stable selectors, golden tests, or explicit layout checks where the flow is visual.

Manual acceptance is allowed only when automation cannot drive the real environment, such as live credentials, real devices, notification permissions, long-running checks, or external providers. Each manual row in `manual-acceptance.csv` must name the buttons or controls, status states, error paths, side effects, exact steps, and evidence. A `passing` manual row must include dated evidence; pending or blocked rows cannot make a linked feature row `verified` or `implemented`.

Completion requires a passing `scripts/test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows` run. The GitHub Actions completion job runs the same gate and blocks release while any required evidence is still open.

- Root completion cannot use `-GovernanceOnly`, `-SkipInstall`, `-SkipWebE2E`, or `-SkipFlutterIntegration`.
- Flutter integration completion evidence must use `-FlutterIntegrationDevice windows`; Chrome and Edge runs are diagnostic only.
- Reviewed entries in `docs/test-governance/coverage-exclusions.csv` are required for every excluded file pattern.
- No open rows may remain in `feature-test-matrix.csv`. Open statuses are `missing`, `planned`, `pending-user`, `blocked-environment`, and `partial`.
- Manual acceptance rows must be `passing`.
- Coverage exclusion rows must be `reviewed`.
- No focused or skipped automated tests may be committed.
- The final report must name test files, coverage reports, the root gate result, Flutter/Dart gate results, the Flutter integration device used, and any open manual or blocked-environment acceptance rows.

Bug fixes require a regression test that fails before the fix. If automation cannot reproduce the defect, record a manual reproduction and evidence row, keep the feature row open, and do not mark it complete until evidence passes.
