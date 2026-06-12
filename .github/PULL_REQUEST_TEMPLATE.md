## Test Governance Checklist

- [ ] Product behavior changes update `docs/test-governance/feature-test-matrix.csv`.
- [ ] Every new or changed user-facing button, menu item, field, shortcut, background trigger, API command, and workflow has automated coverage for happy path, disabled/loading/empty states, relevant failures, and data side effects.
- [ ] Bug fixes include a regression test that would fail without the fix.
- [ ] Manual-only evidence is recorded in `docs/test-governance/manual-acceptance.csv` with dated proof, or the linked feature row remains open.
- [ ] New generated, platform, or untestable files are listed in `docs/test-governance/coverage-exclusions.csv` with `status=reviewed`; no testable product code is excluded.
- [ ] No focused or skipped tests are committed.
- [ ] Local evidence is attached below for the focused tests changed in this PR.

## Verification Evidence

List commands and log/report paths, including any Flutter/Dart focused tests, full coverage runs, root gate runs, manual acceptance evidence, and known open blockers.
