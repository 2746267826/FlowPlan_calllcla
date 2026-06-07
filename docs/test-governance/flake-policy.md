# Flake Policy

Automated tests must not use live external credentials, arbitrary sleeps, wall-clock assertions, committed `.only`, or unexplained `.skip`.

Tests must freeze time, use deterministic IDs and API responses, and isolate test data. Performance tests are outside the default gate unless they are deterministic and marked as such in the matrix.

## Cross-End Skeleton Rules

- Server API cross-end tests use the planned API test app harness and must refuse non-test databases.
- Web Playwright cross-end tests install deterministic route mocks before navigation and avoid shared config changes from this worker.
- Flutter cross-end tests use stable `AppKeys` and fake providers once the Flutter test foundation lands.
- No test may depend on network timing, polling sleeps, real auth tokens, production credentials, or mutable external service state.

## Performance Suites

Performance tests are explicit suites. They are not part of the default root gate unless they use deterministic data, fixed machine-independent thresholds, and no wall-clock timing. Run performance suites from a clean local machine and record results in `docs/test-governance/manual-acceptance.csv`.
