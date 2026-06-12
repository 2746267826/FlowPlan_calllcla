# Runtime Regression Confirmation - 2026-06-12

本报告记录“停止继续追 100% LCOV，保留现有测试治理成果，并让开发回归正轨”之前的必要可运行性回归确认。

## 结论

当前回归确认通过了 Flutter 代表性用户主流程、Server 构建与单元测试、Web Admin 构建与单元测试。该结果说明项目主要开发面仍可继续推进。

这不是最终 completion gate，也不声明测试治理已完全完成。以下事项仍保留为后续治理 backlog：

- Flutter LCOV 仍以最近 summary 为准：`99.87% = 30237 / 30277`，missed 40，gap records 19。
- `docs/test-governance/feature-test-matrix.csv` 仍有 `partial` / `planned` 行。
- `docs/test-governance/manual-acceptance.csv` 仍有 14 条 `pending-user`。
- 完整 completion gate `scripts/test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows` 本轮未运行。

## 保留的治理成果

- `.github/PULL_REQUEST_TEMPLATE.md`
- `docs/test-governance/future-development-rules.md`
- `docs/test-governance/quality-gates.md`
- `docs/test-governance/flake-policy.md`
- `docs/test-governance/coverage-exclusions.csv`
- `docs/test-governance/feature-test-matrix.csv`
- `docs/test-governance/manual-acceptance.csv`
- `docs/test-governance/current-overall-status-20260612.md`
- `docs/test-governance/manual-acceptance-runbook-20260612.md`

## 本轮运行的可运行性回归

### Flutter smoke / user workflow

命令：

```powershell
& 'C:\ProgramLocal\FlutterSDK\flutter\bin\flutter.bat' test --no-pub --concurrency=1 `
  test\widget_test.dart `
  test\widgets\user_workflow_controls_test.dart `
  test\widgets\user_workflow_calendar_shell_quick_add_test.dart `
  test\widgets\user_workflow_task_detail_test.dart `
  test\widgets\user_workflow_tracker_page_test.dart `
  test\widgets\user_workflow_settings_test.dart `
  test\widgets\user_workflow_file_transfer_test.dart `
  test\widgets\user_workflow_server_sync_test.dart
```

结果：

- `00:17 +17: All tests passed!`
- 日志：`client_flutter/build/codex_logs/runtime-smoke-flutter-20260612-193211.out.log`

覆盖的主流程：

- App smoke render
- Shell navigation
- Quick add task/event
- Task detail create/save
- Tracker start/stop/review/upload failure
- Settings schedule/preferences/reminders
- File transfer upload/cancel/download/failure
- Server sync queue replay/failure

### Server build and unit tests

命令：

```powershell
npm run build
npm run test:unit
```

结果：

- `nest build` completed with exit code 0.
- `Test Files 69 passed (69)`
- `Tests 866 passed (866)`
- 日志：`logs/runtime-smoke-server-build-test-20260612-193247.out.log`

### Web Admin build

命令：

```powershell
npm run build
```

结果：

- Vite build completed with exit code 0.
- `12776 modules transformed`
- `built in 18.88s`
- 日志：`logs/runtime-smoke-web-admin-build-retry-20260612-193355.out.log`

说明：

Web Admin build 会输出来自 AntD/SWR 依赖的 `"use client" was ignored` 警告，以及 chunk size warning。这些警告没有导致本轮构建失败。

### Web Admin unit/component tests

命令：

```powershell
npm run test
```

结果：

- `Test Files 17 passed (17)`
- `Tests 137 passed (137)`
- 日志：`logs/runtime-smoke-web-admin-test-20260612-193515.out.log`

说明：

测试日志包含 Vite deprecation warning 和 jsdom `getComputedStyle()` pseudo-elements warning；本轮 Vitest exit code 为 0。

## 未继续推进的事项

根据本次收口策略，以下事项不再阻塞恢复正常产品开发，但保留为治理 backlog：

1. 不继续强追 Flutter LCOV 100%。
2. 不把 14 条 manual acceptance 用自动化或 mock 证据硬改为 passing。
3. 不运行完整 completion gate。
4. 不对大量既有工作区改动做回滚或归属整理。

## 手工验收处理

14 条 `pending-user` 已整理到：

`docs/test-governance/manual-acceptance-runbook-20260612.md`

该文档逐条说明了执行环境、按钮/流程、必须覆盖的状态、错误路径、需要保存的证据，以及完成后如何更新 `manual-acceptance.csv`。

## 后续开发基线

后续开发建议以以下规则为新基线：

1. 新功能、bug fix、行为变更必须继续更新 `feature-test-matrix.csv`。
2. 用户可见按钮、入口、后台触发、API 命令必须有有效自动化测试或明确 manual evidence。
3. PR 必须填写 `.github/PULL_REQUEST_TEMPLATE.md`。
4. 仍需人工配合的验收保持 `pending-user`，直到真实证据齐全。
5. 大型发布前再安排完整 `scripts/test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows`。
