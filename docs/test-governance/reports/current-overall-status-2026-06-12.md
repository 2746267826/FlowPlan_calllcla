# 当前完整测试治理总体状态

更新时间：2026-06-12 00:40 左右（Asia/Shanghai）
仓库：`C:\Users\a2746\Desktop\calll260426`
用途：帮助用户了解“为全部代码和用户使用流程建立完整有效测试”的整体情况。本文只整理状态，不代表最终验收完成。

## 1. 当前运行状态

- 本次仅执行短命令核对日志、CSV 和进程；未运行长时间 Flutter 测试，未修改代码、测试、治理 CSV。
- 进程核对：`Get-Process` / `Get-CimInstance Win32_Process` 未发现正在运行的 `flutter` 或 `dart` 进程；可见的 PowerShell 进程主要是 Codex/命令执行基础进程或本次短命令。结论：当前未确认有长时间 Flutter/Dart 测试仍在跑。
- 当前阻塞点：最近一次 gap7/gap8 integrated 测试失败，需要先修复 `AndroidUsageImportService` gap7 覆盖测试的跨日时间窗口问题。
- 最近失败项：
  - 日志：`client_flutter/build/codex_logs/gap7-gap8-integrated-20260612-002809.out.log`
  - 失败测试：`client_flutter/test/features/tracker/tracker_gap7_worker_services_test.dart`
  - 测试名：`AndroidUsageImportService gap7 coverage opens a new package by closing the previous session at the boundary`
  - 断言：`expected importedRecordCount 2`，实际 `0`
  - integrated 日志尾部：`00:16 +59 -1: Some tests failed.`
- 最近非失败但需注意的输出：integrated 日志里出现 Drift debug warning，提示同一 `QueryExecutor` 上多次创建 `AppDatabase` 可能有 race/corruption 风险；该 warning 当前不是失败原因，但应在后续稳定性梳理中留意。

## 2. 已核对文件和事实

| 项目 | 核对结果 |
| --- | --- |
| 完整 Flutter coverage 日志 | 存在：`client_flutter/build/codex_logs/flutter-coverage-20260611-224105.out.log`；尾部为 `09:58 +1246: All tests passed!` |
| coverage 当前 JSON | 存在：`client_flutter/build/codex_logs/flutter-coverage-current.json`；命令为 `flutter test --no-pub --coverage -x golden --concurrency=1`，开始 `2026-06-11T22:41:05.7499172+08:00`，结束 `2026-06-11T22:51:09.6336976+08:00`，`exitCode=0` |
| LCOV gap summary | 存在：`client_flutter/build/codex_logs/flutter-lcov-line-gap-summary-20260611-225228.csv`；前排缺口包括 files、tracker、calendar、reports 等模块 |
| LCOV gate 等价统计 | 按已知记录为 99.03% = 29870/30162，未覆盖 292 行；本次未重算 LCOV |
| feature matrix | 存在：`docs/test-governance/feature-test-matrix.csv`；共 43 行，`verified=8`、`implemented=14`、`partial=19`、`planned=2` |
| manual acceptance | 存在：`docs/test-governance/manual-acceptance.csv`；共 15 行，`passing=1`、`pending-user=14` |
| focused 日志 | 已核对 task-settings-gap7、files-gap7、calendar-gap7、calendar-gap8、reports-settings-scheduler、tracker-gap7 的近期 focused 日志均有 `All tests passed!` |
| integrated gap7/gap8 日志 | 存在：`client_flutter/build/codex_logs/gap7-gap8-integrated-20260612-002809.out.log`；当前最近失败证据 |

## 3. 当前整体任务进度

当前结论：任务已明显推进，但未完成。完整 Flutter 测试已经有一次 1246 个测试全部通过的记录，LCOV 已接近门禁目标，但仍未到 100%；治理矩阵仍有 `partial` / `planned` 项，manual acceptance 仍有 14 项 `pending-user`，最后的 completion gate 尚未通过。

| 维度 | 当前状态 | 说明 |
| --- | --- | --- |
| Flutter 测试可运行性 | 已有通过记录 | 2026-06-11 22:41 full coverage run 通过，1246 tests passed |
| Flutter LCOV | 未达最终目标 | 99.03%，仍缺 292 行；需修复 integrated 失败后重跑 full coverage 并重算 |
| focused tests | 多批通过 | task/settings、files、calendar、reports/settings/scheduler、tracker focused 已通过 |
| integrated gap7/gap8 | 未通过 | 1 个 tracker service 测试失败，是当前自动化侧 P0 |
| feature-test-matrix | 未完成 | 43 行中 `verified=8`，`implemented=14`，`partial=19`，`planned=2` |
| manual acceptance | 未完成 | 15 行中仅 1 行 `passing`，14 行仍需用户/真实设备/外部服务证据 |
| 最终 completion gate | 未运行/未通过 | 下一步链路尚未走到 `scripts\test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows` |

## 4. 从头开始的总任务列表

### 阶段 0：规则、口径与安全边界

- 已做：建立/维护测试治理文档、质量门禁、future rules、flake policy、selector policy、coverage exclusions、feature matrix、manual acceptance 等治理文件。
- 已做：确认 completion gate 必须区分自动化 evidence 和 manual acceptance，不能用 mock 或局部测试替代真实用户/设备/服务验收。
- 待做：最终交付前重新跑 governance/completion 口径验证，确保矩阵状态、manual 状态和 coverage threshold 一致。

### 阶段 1：Server / Web Admin 自动化覆盖

- 已做：历史报告记录 server 与 web_admin 已达 100% coverage，并已有相应测试治理记录。
- 待做：最终交付前需要 fresh gate 复验；当前文档未重跑 server/web_admin。

### 阶段 2：Flutter 基线与 full coverage

- 已做：多轮 Flutter full coverage 运行，最近可确认通过为 `flutter-coverage-20260611-224105.out.log`，1246 个测试全部通过。
- 已做：生成 LCOV gap summary，当前 gate 等价口径为 99.03%，未覆盖 292 行。
- 待做：修复 integrated 失败后重新跑完整 coverage，确认测试数量、LCOV 分子/分母和未覆盖行是否变化。

### 阶段 3：按 LCOV gap 补齐 Flutter 测试

- 已做：近期 focused 测试覆盖 task/settings、files、calendar、reports/settings/scheduler、tracker 等 gap7/gap8 方向。
- 已做：多个 focused run 已通过，说明单模块补测大多可单独成立。
- 待做：修复 integrated 后继续按 `flutter-lcov-line-gap-summary-20260611-225228.csv` 前排缺口补测，尤其 files、tracker、calendar、reports、Android usage import 等仍有未覆盖行。

### 阶段 4：集成验证与稳定性

- 已做：运行 gap7/gap8 integrated bundle，发现 1 个跨日时间窗口失败。
- 待做：修复 `AndroidUsageImportService` 测试时间窗口，重新跑 targeted analyze/test、gap7/gap8 integrated、完整 full coverage。
- 待做：关注 Drift 多数据库 warning、进程树残留、Flutter 测试串行约束。

### 阶段 5：治理矩阵和人工验收

- 已做：feature matrix 当前 43 行可解析，状态分布已核对。
- 已做：manual acceptance 当前 15 行可解析，`passing=1`、`pending-user=14` 已核对。
- 待做：把新的自动化测试证据回填到矩阵，但不能把需要真实设备/用户/外部服务的 manual 行随意标为 `passing`。
- 待做：组织 14 个 `pending-user` manual acceptance 的真实执行或证据收集。

### 阶段 6：最终 completion

- 待做：自动化侧修复并 LCOV 达标后，运行 `scripts\test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows`。
- 待做：若 completion 失败，按 gate 输出逐项修复；若通过，再更新最终完成态报告。

## 5. 已处理任务用时

以下耗时基于日志时间戳、已有报告和可见事实估算；没有完整项目工时系统，无法精确确认人工开发/调试耗时。

| 任务 | 已知或估算耗时 | 依据与精确度 |
| --- | --- | --- |
| 最新完整 Flutter coverage | 约 10 分 04 秒；日志内进度约 9 分 58 秒 | `flutter-coverage-current.json` 开始/结束时间；`out.log` 尾部 `09:58 +1246`，较精确 |
| LCOV gap summary 生成 | 约 1 分 19 秒以内 | coverage 结束于 22:51:09，gap 文件写入 22:52:28；估算 |
| 2026-06-11/12 focused 验证窗口 | 约 42 分钟墙钟时间 | 从 23:45:27 task-settings 首个日志到 00:27:28 tracker 最后 focused 日志；包含等待、编辑、重跑，估算 |
| task-settings-gap7 最近 focused | 约 1 秒日志进度，墙钟约 5 秒 | `task-settings-gap7-20260611-235407.out.log` 尾部 `00:01 +5: All tests passed!` |
| files-gap7 focused | 约 2 秒日志进度，墙钟约 5 秒 | `files-gap7-focused-20260611-235516.out.log` 尾部 `00:02 +10: All tests passed!` |
| calendar-gap7 最近 focused | 约 2 秒日志进度，墙钟约 6 秒 | `calendar-gap7-focused-20260612-001101.out.log` 尾部 `00:02 +4: All tests passed!` |
| calendar-gap8 最近 focused | 约 2 秒日志进度，墙钟约 6 秒 | `calendar-gap8-focused-20260612-001715.out.log` 尾部 `00:02 +9: All tests passed!` |
| reports-settings-scheduler 最近 focused | 约 6 秒日志进度，墙钟约 10 秒 | `reports-settings-scheduler-focused-20260612-002533.out.log` 尾部 `00:06 +31: All tests passed!` |
| tracker-gap7 最近 focused | 约 7 秒日志进度，墙钟约 11 秒 | `tracker-gap7-focused-20260612-002717.out.log` 尾部 `00:07 +17: All tests passed!` |
| gap7/gap8 integrated 最近失败 run | 约 16 秒日志进度，墙钟约 20 秒 | `gap7-gap8-integrated-20260612-002809.out.log` 结尾 `00:16 +59 -1` |
| 历史 server / web_admin 100% 覆盖 | 无法精确确认 | 旧报告记录已达 100%，但本次未追溯完整命令日志 |
| 治理矩阵建设与多轮 Flutter 补测 | 无法精确确认，历史报告估算为多小时到数个工作日 | 只能基于现有报告和日志演进估算 |

## 6. 还未处理的任务列表

| 优先级 | 任务 | 原因 |
| --- | --- | --- |
| P0 | 修复 `tracker_gap7_worker_services_test.dart` 中 Android usage import 跨日时间窗口失败 | 当前 integrated bundle 直接失败，阻断后续可信 full coverage |
| P0 | 重新跑 targeted analyze/test 和 gap7/gap8 integrated | 验证修复没有引入新失败 |
| P0 | 重新跑完整 Flutter coverage 并重算 LCOV | 当前 LCOV 99.03% 是修复前口径，必须刷新 |
| P0 | 继续补齐剩余 292 行 LCOV gap | completion gate 目标仍是 100% |
| P0 | 更新 feature matrix 中自动化证据映射 | 当前仍有 19 个 `partial`、2 个 `planned` |
| P0 | 不误标 manual acceptance；推动真实验收 | 14 个 `pending-user` 需要用户、真实设备、真实服务或外部凭证证据 |
| P1 | 清理/记录 Drift 多数据库 warning 的影响 | 虽非当前失败项，但可能影响稳定性 |
| P1 | 最终运行 `scripts\test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows` | 这是最终 completion gate |
| P1 | 更新最终完成态报告 | 只有 completion 通过后才能写成完成 |

## 7. 未来预估梳理时间

前提：不并行运行 Flutter 测试；每次大命令前确认无残留 Flutter/Dart 进程；只在 targeted 测试稳定后跑 full coverage；manual acceptance 需要用户/设备/服务配合。

| 估计 | 自动化侧剩余时间 | 人工验收时间 | 前提 |
| --- | --- | --- | --- |
| 乐观 | 2-4 小时 | 另计，至少半天到 1 天分批收证 | 跨日窗口修复很小，LCOV 剩余 292 行大多可用现有 harness 覆盖，completion 一次通过 |
| 基准 | 4-8 小时 | 1-3 天分批执行 | 需要 2-3 轮 targeted/full coverage，矩阵回填需要逐项核对，manual 需要真实设备和凭证安排 |
| 保守 | 1-3 个工作日以上 | 3 个工作日以上或取决于外部条件 | 剩余 gap 涉及平台通道、复杂 UI、时间边界、真实服务，completion gate 暴露新的 server/web/Flutter 或治理问题 |

无法精确确认的部分：历史 server/web_admin 补测开发耗时、早期 worker 实际人工耗时、用户提到的长命令是否对应某个已归档日志、manual acceptance 的真实执行排期。

## 8. 风险和注意事项

- Flutter 测试不应并行跑。尤其 full coverage、integrated bundle、Windows integration 容易争用缓存、设备、临时目录和数据库资源。
- 跑长命令前应检查并清理进程树，确认没有残留 `flutter`、`dart`、Windows app 实例或旧 PowerShell gate。
- manual acceptance 不能随意标 `passing`。需要真实设备、真实凭证、外部服务、通知权限、长时间运行或用户操作证据的项目，必须保留 `pending-user`，直到有带日期的证据。
- 当前工作区很脏，不应回滚、清理或覆盖他人/其他代理改动；修复时需要小范围读取并只改必要文件。
- LCOV 口径必须使用 gate 等价逻辑；不能用旧手算口径或未经治理排除对齐的统计替代。
- focused 通过不等于 integrated 或 full coverage 通过；当前 integrated 已证明存在跨文件/跨场景问题。
- Drift debug warning 需要谨慎对待；即使不导致当前失败，也可能掩盖测试隔离或数据库生命周期问题。
- 最终 completion 必须使用 `-FlutterIntegrationDevice windows`；Chrome/Edge 作为 Flutter integration device 不应视为等价完成证据。

## 9. 建议下一步顺序

1. 修复 `AndroidUsageImportService` gap7 测试的跨日时间窗口，使 `importedRecordCount` 稳定为预期值。
2. 跑最小 targeted test，确认该单测通过。
3. 跑相关 `flutter analyze` / targeted bundle，确认没有新 analyzer 或测试失败。
4. 重新跑 gap7/gap8 integrated bundle。
5. 跑完整 `flutter test --no-pub --coverage -x golden --concurrency=1`。
6. 重算 LCOV，更新 gap summary。
7. 按新的前排 gap 继续补测或确认合理治理排除。
8. 更新 feature matrix 与报告，但保持 manual acceptance 规则严格。
9. 自动化和矩阵条件满足后，运行 `scripts\test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows`。
