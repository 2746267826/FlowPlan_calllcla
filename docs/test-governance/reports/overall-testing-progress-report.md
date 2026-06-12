# 完整测试治理与覆盖率补齐总览报告

更新时间：2026-06-10
工作目录：`C:\Users\a2746\Desktop\calll260426`

## 一句话结论

当前任务仍未完成。Server 与 Web Admin 覆盖率已达 100%，Flutter 测试最新通过 660/660，但治理排除后的 Flutter LCOV 仍为 87.63%（26512/30255），距离 100% 仍缺 3743 行。

## 当前运行状态

按当前主线程可见进程检查，暂未看到 Flutter/Dart 长时间测试或构建命令在运行；可见的相关进程主要是 Codex、codex-plus-plus、node、node_repl 等 Codex/Node 进程。

因此，目前不应假定后台仍有长跑测试会自动产出新结果。后续若要继续补齐覆盖率，建议以小批次、可观察、有超时策略的 focused tests 为主，避免再次启动超长无反馈命令。

## 当前整体进度

| 范围 | 当前状态 | 说明 |
| --- | --- | --- |
| Server | 已达 100% | 已有覆盖率补齐与验证记录。 |
| Web Admin | 已达 100% | 已有覆盖率补齐与验证记录。 |
| Flutter 测试可运行性 | 最新 660/660 通过 | 最新记录为 `flutter test --no-pub --coverage -x golden --concurrency=1` 全部通过。 |
| Flutter 静态分析 | 已通过 | 最新记录为 `flutter analyze` 无问题。 |
| 治理脚本 | 已通过 | 最新记录为 root governance-only 检查通过。 |
| Flutter LCOV | 未达标 | 治理排除后为 87.63% = 26512/30255，仍缺 3743 行。 |
| 最终全量验收 | 未完成 | 需要 Flutter LCOV 达标后再重跑全仓最终验证。 |

## 从头开始的总任务列表

| 序号 | 总任务 | 当前状态 |
| --- | --- | --- |
| 1 | 建立测试治理规范 | 已基本完成，包含 skip/only 等治理规则与质量门禁文档。 |
| 2 | Server 测试补齐 | 已达 100%，但最终验收阶段仍需重跑确认。 |
| 3 | Web Admin 测试补齐 | 已达 100%，但最终验收阶段仍需重跑确认。 |
| 4 | Flutter 单元测试补齐 | 进行中，测试可运行性已通过，但 LCOV 未达标。 |
| 5 | Flutter 组件测试补齐 | 进行中，剩余缺口集中在多个 UI 大文件。 |
| 6 | Flutter 用户流程测试补齐 | 进行中，已有多批 user-flow/widget 测试，但仍不足以覆盖全部 LCOV gap。 |
| 7 | 治理脚本与文档整理 | 已基本完成，本报告属于面向用户的状态整理。 |
| 8 | 覆盖率门禁 | 已建立并可运行，但 Flutter LCOV 仍未满足最终目标。 |
| 9 | 剩余 Flutter LCOV 补齐 | 未完成，当前仍缺 3743 行。 |
| 10 | 最终全量验证 | 未完成，需在剩余 LCOV 补齐后执行。 |

## 已处理任务与粗估用时

以下用时没有可靠的独立计时日志支撑，按会话记录粗估，不可作为精确工时或审计时间戳。

| 任务 | 结果 | 粗估用时 |
| --- | --- | --- |
| 测试治理规范梳理 | 已形成治理规则、质量门禁、排除规则与相关文档 | 2-6 小时 |
| Server 覆盖率补齐与验证 | 已达 100% | 4-12 小时 |
| Web Admin 覆盖率补齐与验证 | 已达 100% | 4-12 小时 |
| Flutter 基线覆盖率梳理 | 从早期基线推进到当前 87.63% | 2-6 小时 |
| Flutter 第一轮补测 | 覆盖率提升至约 83.16% | 4-12 小时 |
| Flutter 第二轮补测 | 测试数增至 660/660，覆盖率提升至 87.63% | 4-16 小时 |
| focused tests 合并验证 | 多批模块级 focused tests 已通过 | 2-8 小时 |
| `flutter analyze` 与 governance-only 验证 | 最新记录为通过 | 0.5-2 小时 |
| 状态文档整理 | 已有当前状态文档，本报告进一步整理为用户总览 | 0.5-1 小时 |

整体看，Server/Web Admin 已进入“等待最终复验”状态；主要剩余工作量集中在 Flutter LCOV 的最后 12.37 个百分点。

## 未完成任务与剩余缺口

当前最大未完成项是 Flutter LCOV。治理排除后，Flutter 覆盖率为 87.63% = 26512/30255，仍缺 3743 行。

主要热点文件包括：

| 文件 | 当前剩余未覆盖行数 |
| --- | ---: |
| `client_flutter/lib/web_app/flowplanv2_web_app.dart` | 266 |
| `client_flutter/lib/features/tracker/presentation/tracker_page.dart` | 185 |
| `client_flutter/lib/features/sync/outlook_settings_page_body.dart` | 134 |
| `client_flutter/lib/features/calendar/presentation/calendar_shell.dart` | 117 |
| `client_flutter/lib/core/server_first/task_event_server_first_store.dart` | 104 |
| `client_flutter/lib/core/sync/sync_engine.dart` | 102 |

仍需处理的任务：

| 未完成项 | 说明 |
| --- | --- |
| Flutter LCOV 补齐 | 继续针对 3743 行缺口补测试或调整合理治理排除。 |
| UI 大文件测试 | Web App、Tracker、Outlook Settings、Calendar Shell 等文件需要更系统的 widget/user-flow 测试。 |
| Store/Service 测试 | server-first store、sync engine 等低层逻辑仍有可优先补齐空间。 |
| 覆盖率排除规则复核 | 只能排除确实不可测、生成物、平台桥接或合理声明的代码，不应用排除代替测试。 |
| 最终 full coverage | 补齐后必须重新生成 LCOV，确认治理排除后的最终比例。 |
| 全仓最终验证 | Server、Web Admin、Flutter、analyze、governance-only 均需要新鲜通过。 |

## 后续补齐时间预估

以下仍为保守估算，实际用时取决于 UI 测试可测性、平台 mock 难度、现有 test harness 是否足够、覆盖率排除规则是否需要调整。

| 模块 | 建议处理方式 | 保守估算 |
| --- | --- | --- |
| 低耦合 API/store/service | 优先补单元测试，mock 外部依赖，通常收益稳定 | 4-10 小时 |
| Core Sync / Server-first | 覆盖 sync engine、store、冲突/边界路径 | 4-12 小时 |
| Tracker UI 与服务 | 先 service/provider，后页面交互 | 6-16 小时 |
| Outlook Settings / Sync | 需要平台与 Graph/Auth mock，注意避免真实 IO 或网络 | 6-16 小时 |
| Calendar Shell / Scheduling UI | 需要构造稳定 harness，覆盖编辑、视图切换、边界状态 | 6-18 小时 |
| Web App 大文件 | 可能涉及浏览器 facade、平台分支、入口组装 | 6-18 小时 |
| LCOV 汇总与治理排除复核 | 每批补齐后重新计算 gap | 1-3 小时 |
| 最终全量验证与报告 | 所有门禁重跑并更新验收文档 | 2-5 小时 |

整体估算：若剩余缺口多为可测的 service/store 分支，可能还需要 1-2 个工作日；若主要卡在复杂 UI、平台通道、浏览器/文件系统 mock 或排除规则争议，可能需要 3-5 个工作日甚至更久。

## 风险

| 风险 | 影响 |
| --- | --- |
| 再次启动超长无反馈命令 | 容易造成状态不透明，难以及时判断卡死、hang 或环境问题。 |
| UI 大文件先行 | 复杂 widget/user-flow 测试调试成本高，可能消耗大量时间但覆盖率收益不稳定。 |
| 平台依赖 mock 不完整 | Outlook、文件、浏览器、系统能力相关测试可能出现 hang、真实 IO 或环境差异。 |
| 覆盖率排除滥用 | 会削弱“完整测试治理”的可信度，最终验收解释成本变高。 |
| 脏工作区范围很大 | 多批并行改动容易产生合并冲突或互相覆盖，需要分批复核。 |

## 建议下一步

1. 不要再启动超长无反馈命令；所有长命令都应有日志、超时、阶段性输出或明确观察点。
2. 优先补低耦合 API/store/service 测试，尤其是 `task_event_server_first_store.dart`、`sync_engine.dart` 这类逻辑文件。
3. 再处理 UI 大文件：先拆可控 harness 与 mock，再覆盖高收益用户路径。
4. 每一小批补齐后运行对应 focused tests，避免把失败积累到 full coverage 阶段。
5. 每一批通过后再运行 `flutter analyze`、governance-only、full coverage，并重新生成 LCOV gap。
6. 只有当 Flutter LCOV 达到目标后，再重跑 Server、Web Admin、Flutter、analyze、governance 的最终全量验证。
7. 最终报告应明确列出命令、时间、结果与覆盖率分母分子，避免只写“已完成”。

## 当前可对外同步

Server 与 Web Admin 已达到 100% coverage；Flutter 最新测试记录为 660/660 通过，`flutter analyze` 与 governance-only 也有通过记录。但治理排除后的 Flutter LCOV 仍为 87.63%（26512/30255），距离 100% 还缺 3743 行。因此，“完整测试治理/覆盖率补齐”仍处于进行中，不能宣称全覆盖完成。
