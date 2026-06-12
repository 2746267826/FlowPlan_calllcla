# Flutter/Dart 测试补齐状态报告（2026-06-12）

生成时间：2026-06-12 16:30:47 +08:00（Asia/Shanghai）
工作目录：`C:\Users\a2746\Desktop\calll260426`
分支：`main-before-f031649`

## 资料来源与可信度说明

本报告是轻量级状态整理，只读取了当前仓库状态、`client_flutter/build/codex_logs` 下的近期日志、既有测试治理文档和用户提供的上下文事实。未运行 `flutter test`、`dart test`、root gate 或其他长耗时测试命令；未清理、回滚、重置任何工作区改动。

可信度分级：

- 高可信：来自本次实际查看的 `git status --short --branch`、近期日志文件名、日志关键行、`flutter-lcov-summary-20260612-145946.json`、`docs/test-governance/future-development-rules.md`、`docs/test-governance/quality-gates.md`。
- 中可信：来自用户提供的本轮工作上下文和其他子代理报告。
- 估算：人工处理耗时、整体进度百分比、未来剩余时间。基于当前可见日志/上下文，部分耗时为估算。

## 当前运行状态

| 项目 | 当前状态 |
| --- | --- |
| 工作区 | 很脏，存在大量既有/其他代理修改和未跟踪文件；本报告不判断归属，不回滚。 |
| Git 分支 | `main-before-f031649...origin/main-before-f031649 [ahead 9]`。 |
| 本报告任务执行边界 | 只写 `docs/testing-status-report-2026-06-12.md`，不修改业务代码或测试代码。 |
| Flutter 命令约束 | Flutter 可执行路径为 `C:\ProgramLocal\FlutterSDK\flutter\bin\flutter.bat`；后续测试通常应通过 `cmd.exe /d /c` 执行。 |
| Flutter 测试并发约束 | 后续 Flutter 测试不要并行，必须使用 `--concurrency=1`。 |
| 最近可验证通过的全量 Flutter coverage | `flutter-coverage-round2-rerun-20260612-144725.out.log`：`11:19 +1383: All tests passed!`。 |
| 最近可验证 LCOV 汇总 | `flutter-lcov-summary-20260612-145946.json`：99.68% = 30146/30242，missed 96，gap records 35。 |
| 最近全量回归尝试 | `flutter-coverage-post-gap-workers-rerun-20260612-160112.out.log`：全量跑完但 `14:50 +1406 -5: Some tests failed.` |
| 最近 focused 修复回归 | `focused-failure-fixes-20260612-162634.out.log`：组合 focused 约 `+39 -1`，仍有 1 个 tracker UI 测试失败。 |

## 当前整体任务进度

工程判断估算：约 82%。

依据：

- 测试基线已经很高：较早全量 Flutter coverage 已通过，LCOV 达到 99.68%，只剩 96 行、35 个 gap record。
- 用户使用流程测试已大量存在，`user_workflow_*`、files、tracker、sync、reports、settings 等测试已形成规模。
- 测试治理规则文件已经存在，包括 `docs/test-governance/future-development-rules.md` 和 `docs/test-governance/quality-gates.md`，其中明确了未来开发必须补测试、100% included Dart line coverage、manual acceptance、completion gate 等规则。
- 但当前不是绿色状态：最新 post-gap full coverage 仍失败，focused 修复组合仍有 `tracker_aux_ui_gap3_worker_tracker_test.dart` 1 个失败，且 full coverage 与 LCOV summary/gap CSV 尚未在本轮修复后重新生成。
- 仍需复验 tracker UI 子代理相关测试、继续清剩余 LCOV gap，并最终跑完整 completion gate。

## 从头开始的总任务列表

### 阶段 1：测试治理目标与规则

1. 明确总目标：为 Flutter/Dart 项目补齐严格、有效、完整的自动化测试，尤其是用户使用流程测试。
2. 制定未来开发规则：所有功能、修复、重构、行为变更必须配套有效测试，并更新治理矩阵。
3. 定义质量门禁：Flutter coverage、golden、integration、manual acceptance、coverage exclusions、completion gate。
4. 固化治理文档：`feature-test-matrix.csv`、`manual-acceptance.csv`、`coverage-exclusions.csv`、`cross-end-workflow-matrix.md`、`future-development-rules.md`、`quality-gates.md`。

### 阶段 2：建立可验证测试基线

1. 串行运行 Flutter coverage：`flutter test --no-pub --coverage -x golden --concurrency=1`。
2. 生成 LCOV summary、gap CSV、line gap summary。
3. 记录全量通过日志和覆盖率指标。
4. 将 full coverage、focused rerun、LCOV 文件作为后续变更的证据链。

### 阶段 3：按 gap 补测试/修可测性

1. 按 LCOV gap 文件逐个定位未覆盖行。
2. 对 sync、tracker services、tracker UI、files UI、calendar/ical、reports、settings 等模块补足 focused 测试。
3. 在必要时做小范围可测试性改造，例如平台判断注入、null override 语义修正、数据库 schema 升级。
4. 每项改动后先 focused 验证，再纳入 full coverage。

### 阶段 4：修复集成失败并复验

1. 修复全量编译失败或非法 import 等结构性问题。
2. 修复 post-gap full coverage 中的失败测试。
3. 复验其他子代理提交的 focused 测试。
4. 全量重跑 Flutter coverage，确认测试全绿。

### 阶段 5：覆盖率归零与治理闭环

1. 重新生成 LCOV summary/gap CSV。
2. 确认 missed lines 是否降到 0。
3. 如有不可自动化项，必须进入 reviewed exclusion 或 manual acceptance，并给出替代验证。
4. 更新验收矩阵、测试规范和最终报告。

### 阶段 6：最终门禁

1. 串行运行 root completion gate。
2. 保存日志、覆盖率报告、manual evidence、CI evidence。
3. 确认无 focused/skip 测试、无 open governance rows、无未解释 exclusion。
4. 给出最终交付结论。

## 已处理任务列表及耗时

说明：能从日志 elapsed 读出的写日志耗时；不能精确反推人工开发耗时的标为估算。

| 已处理任务 | 证据 | 耗时 |
| --- | --- | --- |
| 较早全量 Flutter coverage 通过 | `flutter-coverage-round2-rerun-20260612-144725.out.log`：`11:19 +1383: All tests passed!` | 测试运行 11 分 19 秒 |
| 较早 LCOV summary/gap 生成 | `flutter-lcov-summary-20260612-145946.json`：99.68%，30146/30242，missed 96，gaps 35 | 生成时间 14:59:47；后处理耗时未单独记录 |
| 新增/验证 sync applier fallback 测试 | `sync-applier-gap9-focused-20260612-151616.out.log`：`00:00 +5: All tests passed!` | focused runner 小于 1 秒；人工耗时估算 10-25 分钟 |
| `tracker_platform_source` 支持注入平台判断 | `tracker-platform-gap9-green-20260612-153108.out.log`：`00:00 +10: All tests passed!` | focused runner 小于 1 秒；人工耗时估算 15-35 分钟 |
| `tracker_service` 修复平台注入和 null override 语义 | `tracker-gap4-import-fix-green-20260612-155649.out.log`：`00:00 +9: All tests passed!` | focused runner 小于 1 秒；人工耗时估算 20-45 分钟 |
| 修复 `tracker_gap4_worker_tracker_test` 非法直接 import part 文件 | 同上 green 日志；此前 `flutter-coverage-post-gap-workers-20260612-153839.out.log` 编译失败 | 人工耗时估算 10-20 分钟 |
| `activity_record_repository.insertImportedRecord` 支持 `className` 并补 SQL 写入 `class_name` | 用户上下文；`android-usage-import-classname-green-20260612-162219.out.log`：`+11: All tests passed!` | focused runner 小于 1 秒；人工耗时估算 20-45 分钟 |
| `android_usage_import_service` 传入 `session.className` | 同上 green 日志 | 包含在上一项估算内 |
| `app_database` schemaVersion 18 -> 19，并升级补 `activity_records.class_name TEXT` | 用户上下文；相关 Android usage focused 已通过 | 人工耗时估算 15-35 分钟 |
| 修复 `files_gap9_worker_ui_test` 预览 Future 过早断言 | `focused-failure-fixes-20260612-162634.out.log` 中 files gap9 3 个测试通过 | 组合 focused 约 14 秒内完成 files/user workflow 部分；人工耗时估算 10-30 分钟 |
| 修复 `user_workflow_file_context_page_deep_test` snapshot 按钮期望 | `focused-failure-fixes-20260612-162634.out.log` 中 user workflow file context 多项通过 | 包含在组合 focused；人工耗时估算 10-30 分钟 |
| sync/scheduler 子代理完成 focused 修复 | 用户上下文：`server_sync_status_page_gap_worker_sync_test.dart`、`scheduler_gap3_worker_scheduler_test.dart` focused passed | 耗时未见本次可读日志；估算 30-90 分钟 |
| core long-tail 子代理完成多个 core/provider/report push gaps | 用户上下文：api_client、report_push_service、app_providers 等相关测试完成 | 耗时未见本次可读日志；估算 1-3 小时 |
| tracker UI 子代理完成若干 UI/Provider 修改 | 用户上下文：当时被 `className` 编译问题阻断；现需复验 | 耗时未见本次可读日志；估算 1-2 小时 |

## 最近失败与当前剩余问题

1. `flutter-coverage-post-gap-workers-20260612-153839.out.log`：全量 coverage 编译失败，原因是 `tracker_gap4_worker_tracker_test.dart` 非法直接 import part 文件。当前已修复，并有 focused green 日志。
2. `flutter-coverage-post-gap-workers-rerun-20260612-160112.out.log`：全量跑完但 5 个测试失败，日志尾部为 `14:50 +1406 -5: Some tests failed.`。
3. 已修复并 focused 通过的失败包括 `android_usage_import_service`、`files_gap9`、`user_workflow_file_context_page_deep`。
4. 当前仍未修复的直接失败：`client_flutter/test/widgets/tracker_aux_ui_gap3_worker_tracker_test.dart` 中 `activity review parses edge server data and closes with go`。
5. 该失败在 `focused-failure-fixes-20260612-162634.out.log` 中表现为 `_pumpUntilFound` 找不到预期内容，异常位置为测试文件第 589、756、775 行；用户上下文指出具体表现为找不到 `Code.exe`。

## 未处理/待复验任务列表

| 优先级 | 任务 | 当前状态 | 完成条件 |
| --- | --- | --- | --- |
| P0 | 调试并修复 `tracker_aux_ui_gap3_worker_tracker_test.dart` 中 `activity review parses edge server data and closes with go` | focused 仍失败 | 该测试 focused 通过，且不靠放宽断言掩盖真实 UI 行为 |
| P0 | 复验 tracker UI 子代理相关测试 | 待复验 | `tracker_ui_presentation_gap_worker_d_test.dart`、`tracker_app_providers_deep_test.dart`、`tracker_aux_ui_gap3_worker_tracker_test.dart` focused 全绿 |
| P0 | 重跑全量 Flutter coverage | 待本轮失败修复后执行 | `flutter test --no-pub --coverage -x golden --concurrency=1` 全绿 |
| P0 | 重新生成 LCOV summary/gap CSV | 待 full coverage 后执行 | 确认 missed lines 是否为 0；若不为 0，给出剩余 gap 清单 |
| P1 | 继续覆盖剩余 gaps | 待新 LCOV 结果 | 重点 file UI、tracker UI、calendar/ical 等剩余区域 |
| P1 | 复验其他子代理修改 | 部分仅有上下文报告 | sync/scheduler、core long-tail、tracker services、files UI、calendar/ical 等 focused/full 纳入统一证据 |
| P1 | 补齐测试规范/治理文档 | 已有基础文档，待最终更新 | 最终规范、验收矩阵、质量门禁与本轮证据一致 |
| P2 | root completion gate | 未到执行窗口 | 自动化、LCOV、manual/governance 准备完成后再执行 |

## 风险和阻塞点

1. 当前工作区非常脏，且有多个代理并行修改。任何修复前都必须先读目标文件和 diff，避免覆盖他人工作。
2. 最新可见 full coverage 不是绿色；不能把 14:47 的较早全绿结果当作当前完成状态。
3. `tracker_aux_ui_gap3_worker_tracker_test.dart` 是直接阻塞：它会影响 tracker UI focused 复验和下一轮 full coverage。
4. `className` 相关数据库/schema/service 修改已经有 focused 证据，但仍需纳入 full coverage 验证。
5. LCOV 99.68% 离 100% 很近，但最后 96 行可能集中在异步 UI、平台分支、外部服务或复杂导航上，单位修复成本可能较高。
6. 测试治理文档已存在，但最终闭环必须以实际 full coverage、LCOV gap、manual evidence、completion gate 结果为准。
7. 后续 Flutter 测试必须串行，避免 coverage 文件、build cache、日志和设备状态互相污染。

## 未来预估梳理时间

| 情景 | 自动化修复与复验 | LCOV/gap 梳理 | 治理文档与矩阵 | completion gate | 总体预估 |
| --- | ---: | ---: | ---: | ---: | ---: |
| 乐观 | 1-2 小时 | 0.5-1 小时 | 0.5-1 小时 | 1-2 小时 | 3-6 小时 |
| 正常 | 3-5 小时 | 1-3 小时 | 1-2 小时 | 2-4 小时 | 1-2 个工作日 |
| 保守 | 1-2 个工作日 | 0.5-1 个工作日 | 0.5 个工作日 | 0.5-1 个工作日 | 3-5 个工作日 |

估算前提：

- 乐观：`Code.exe` 查找失败只是测试 fixture/断言同步问题，修复后 full coverage 基本恢复绿色，LCOV gap 明显下降。
- 正常：tracker UI 修复后仍有少量 file UI、calendar/ical、tracker UI gap，需要多轮 focused/full。
- 保守：最后 gap 涉及真实平台分支、不可注入依赖、复杂导航或外部服务，需要小范围生产代码可测试性改造和更多 manual evidence。

## 给用户看的简短结论

当前不是“已完成”，而是“接近完成但仍有明确阻塞”。较早全量 Flutter coverage 已经通过且 LCOV 达到 99.68%，说明基础测试建设非常接近目标；但最新一轮整合后 full coverage 失败，当前直接阻塞是 `tracker_aux_ui_gap3_worker_tracker_test.dart` 的 activity review 测试仍有 1 个 focused 失败。下一步应先修这个失败，再复验 tracker UI 相关测试，然后串行重跑 full coverage 和 LCOV summary。只有 full coverage、LCOV gap、治理矩阵、manual evidence 和 completion gate 全部闭环后，才能宣告测试补齐任务完成。
