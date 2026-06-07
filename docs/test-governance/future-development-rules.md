# Future Development Rules

Every feature change must update `docs/test-governance/feature-test-matrix.csv`.

Completion requires:

- Code tests for implementation behavior.
- User behavior tests or a manual acceptance record for every visible control.
- Failure-path tests for validation, empty states, API failure, permission failure, network failure, duplicate submission, and external-service failure.
- Reviewed entries in `docs/test-governance/coverage-exclusions.csv` for any excluded file pattern.
- A final report naming test files, coverage reports, root gate result, and user-run Flutter commands.

Bug fixes require a regression test or a manual reproduction record when automation cannot reproduce the defect.
