# FlowPlanV2 Quality Gates

Every included hand-written production file must reach 100% lines, branches, functions, and statements. The root gate is `scripts/test-flowplanv2.ps1`.

Generated report locations:

- Server coverage: `server/coverage/index.html`
- Web admin coverage: `web_admin/coverage/index.html`
- Web admin E2E report: `web_admin/playwright-report/index.html`
- Flutter user-run coverage: `client_flutter/coverage/lcov.info`
- Root summaries: `docs/test-governance/reports/generated`

The root gate fails for automated server and web failures. Flutter commands are printed for user execution because `docs/development_constraints_260426.md` forbids Codex from running Flutter or Dart commands.
