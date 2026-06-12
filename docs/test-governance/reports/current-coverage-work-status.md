# 当前测试全覆盖长期任务状态报告

更新时间：2026-06-10 14:20，Asia/Shanghai

## 结论

当前任务**未完成，不能宣称全覆盖**。

已验证：

| 范围 | 状态 | 证据 |
| --- | --- | --- |
| server | 已达 100% 覆盖 | 旧 worker 验证 `npm run test:coverage`：80 files / 942 tests / 100% |
| web_admin | 已达 100% 覆盖 | 旧 worker 验证 `npm run test:coverage`：17 files / 137 tests / 100% |
| client_flutter 测试可运行性 | 已通过 | `flutter test --no-pub --coverage -x golden --concurrency=1`：660 tests / 0 skip |
| client_flutter 静态分析 | 已通过 | `flutter analyze`：No issues found |
| root governance | 已通过 | `scripts/test-flowplanv2.ps1 -GovernanceOnly -SkipInstall` 通过 |
| client_flutter LCOV | 未达标 | 87.63%（26512/30255），仍缺 3743 行 |

当前主要瓶颈是 Flutter/Dart LCOV。server 和 web_admin 的 100% 不能替代 Flutter 侧的 100%。

## 当前运行状态

| 项目 | 状态 |
| --- | --- |
| 主代理 | 已完成第二轮 worker 回收、focused 验证和全量 coverage 复跑，准备派发第三轮补测 |
| 文档 worker | 已完成，本文件已复核并修正为可读中文 |
| 第一轮测试 worker | 10 个已全部回收；Ptolemy、Helmholtz、Pauli 的剩余范围已在主工作区复验 |
| 第二轮测试 worker | 6 个已全部回收，主工作区合并 focused 96/96 通过 |
| 本地新增/修复 | Outlook diagnostics 导出测试改用 provider fake writer，避免 widget test 真实文件 IO hang |
| 遗留风险 | 第三轮 worker 回收后仍需 focused tests、analyze、governance 和 full coverage 复跑 |

## 从头开始的总任务列表

| 序号 | 总任务 | 当前状态 |
| --- | --- | --- |
| 1 | 明确“所有代码完整有效测试”的验收口径 | 进行中，当前以 server/web_admin/Flutter 覆盖率和 root gate 为主要证据 |
| 2 | 建立测试治理规范，禁止 `.only`、`.skip`、`@Skip`、`markTestSkipped` | 已实现并通过 governance-only 检查 |
| 3 | server 补齐单元/API/交叉端测试并达 100% 覆盖 | 已验证完成 |
| 4 | web_admin 补齐组件/页面/e2e/工具测试并达 100% 覆盖 | 已验证完成 |
| 5 | Flutter 全量测试跑通且无 skip | 已验证完成 |
| 6 | Flutter LCOV gap 梳理 | 已完成三次：77.60% 基线，第一轮后 83.16%，第二轮后 87.63% |
| 7 | 按 Flutter gap 派发并行 worker 补测试 | 第一轮、第二轮完成；第三轮准备中 |
| 8 | 回收 worker 改动，处理冲突并复核测试质量 | 第一轮、第二轮完成；第三轮待回收 |
| 9 | 重跑 Flutter full coverage，确认 LCOV 是否到 100% | 已重跑两次，最新 87.63%，未达 100% |
| 10 | 对剩余 Flutter gap 追加第二轮补测 | 已完成，需继续第三轮 |
| 11 | 最终重跑 server/web_admin/Flutter/analyze/governance | 未完成 |
| 12 | 写最终验收报告并更新状态文档 | 未完成 |

## 已处理任务和大致用时

时间为基于当前可见记录的估算，用于排期，不作为审计证据。

| 任务 | 结果 | 大致用时 |
| --- | --- | --- |
| server 覆盖率验证 | 100% 通过 | 约 0.5-1 小时验证，前置补测更久 |
| web_admin 覆盖率验证 | 100% 通过 | 约 0.5-1 小时验证，前置补测更久 |
| Flutter full coverage 基线 | 542 tests / 0 skip 通过 | 单次约 4-5 分钟，本轮曾因长命令策略产生等待 |
| 第一轮后 Flutter full coverage | 614 tests / 0 skip 通过 | 约 5 分钟 |
| 第二轮后 Flutter full coverage | 660 tests / 0 skip 通过 | 约 5 分钟 |
| Flutter analyze | 通过，当前 No issues found | 约 5-10 分钟 |
| root governance-only | 通过 | 约 1-5 分钟 |
| LCOV 汇总 | 从 77.60% 提升到 83.16%，再到 87.63% | 约 5-15 分钟 |
| web shell 测试修复 | 去掉不可执行 browser-only/skip 路径，改为 VM 可测条件导入 | 约 0.5-1 小时 |
| Android usage import/service 本地补测 | focused 8/8 通过 | 约 0.5-1 小时 |
| 第一轮并行 worker 派发 | 10 个测试补强 worker + 1 个文档 worker | 约 0.5 小时 |
| 第二轮并行 worker 派发 | 6 个测试补强 worker | 约 0.2 小时 |

## 并行 worker 列表

| Worker | 范围 | 当前状态 |
| --- | --- | --- |
| Ptolemy | `client_flutter/test/web_app/**` | 已完成；主工作区复跑 `test/web_app` 6/6 通过 |
| Helmholtz | Outlook settings widget/user-flow tests | 已完成并由主线程修复 hang；主工作区 9/9 通过 |
| Pauli | tracker page widget/user-flow tests | 已完成；主工作区 tracker focused 13/13 通过 |
| Fermat | iCal import/export widget tests | 已完成，focused `+15` 通过 |
| Dirac | file context page widget tests | 已完成，focused `+18` 通过 |
| Arendt | raw input / tracker service tests | 已完成，focused 14 tests 通过 |
| Turing | reports repository/page tests | 已完成，focused 51 tests 通过 |
| Carson | calendar books/shell tests | 已返回 partial；主线程已修复其失败并完成 focused 验证 |
| Maxwell | reminders / actual candidate service tests | 已完成，focused combined 30 tests 通过 |
| Lovelace | file repository/service tests | 已完成，focused 38 tests 通过 |
| Ramanujan | 本状态文档 | 已完成，本文档已复核修正 |

## 第二轮并行 worker 列表

| Worker | 范围 | 当前状态 |
| --- | --- | --- |
| Copernicus | Web App / `web_api_client` | 已完成；主线程修复 residual 定位后 focused 9/9 通过 |
| Gibbs | Outlook sync/settings/auth | 已完成；主工作区 focused 34/34 通过 |
| Socrates | Tracker service/provider/UI | 已完成；主工作区 focused 18/18 通过 |
| Aristotle | Calendar / Scheduling UI | 已完成；主工作区 focused 5/5 通过 |
| Copernicus the 2nd | Core Sync / Server-first / API | 已完成；主线程修复 conflict 断言/import 后 focused 20/20 通过 |
| Ramanujan the 2nd | Files / iCal / Settings / Data-management | 已完成；主工作区 focused 10/10 通过 |

## 第三轮并行 worker 列表

| Worker | 范围 | 当前状态 |
| --- | --- | --- |
| Chandrasekhar the 2nd | Web App residual | 已派出，等待回收 |
| Singer the 2nd | Tracker remaining | 已派出，等待回收 |
| Heisenberg the 2nd | Calendar/Scheduling remaining | 已派出，等待回收 |
| Pascal the 2nd | Outlook remaining | 已派出，等待回收 |
| Popper the 2nd | Core Sync / Scheduler / Reminders remaining | 已派出，等待回收 |
| Goodall the 2nd | Files / iCal / Settings / Misc remaining | 已派出，等待回收 |

## 还未处理或未完成任务

| 未完成项 | 说明 |
| --- | --- |
| 回收第三轮 worker | 第三轮 worker 尚未派出或待回收 |
| 复核第三轮 worker 改动 | 第二轮已复核并 full coverage 通过；第三轮待 focused 验证 |
| 处理并行冲突 | 多个 worker 可能同时改 test support 或同一测试文件，需要合并检查 |
| 重跑 Flutter full coverage | 第三轮合并后必须重新生成 `lcov.info` |
| 生成新 LCOV gap report | 当前 gap 已确认：87.63%，剩余 3743 行 |
| 第三轮补测 | 需要按最新 top gaps 继续补测 |
| 最终全仓验证 | server、web_admin、Flutter、analyze、governance 都需新鲜通过 |
| 最终验收文档 | 只有 Flutter LCOV 达 100% 后才能更新为完成态 |

## 后续时间预估

| 阶段 | 乐观估计 | 常规估计 |
| --- | --- | --- |
| 回收剩余 worker 并复核 | 0.5-1 小时 | 1-2 小时 |
| 合并冲突与 focused 验证 | 1-2 小时 | 2-6 小时 |
| 重跑 Flutter full coverage + LCOV 汇总 | 0.5 小时 | 1-2 小时 |
| 第二轮补测剩余 Flutter gap | 2-4 小时 | 4-16 小时 |
| 最终全仓验证 | 1-2 小时 | 2-4 小时 |
| 最终报告更新 | 0.5 小时 | 0.5-1 小时 |

整体估计：前两轮已把 Flutter LCOV 从 77.60% 推到 87.63%。若第三轮能继续吃掉 Web App、Tracker、Calendar、Outlook 和 Core Sync 的主要缺口，可能还需 4-12 小时；更现实是 1-3 个工作日。若剩余 gap 集中在平台通道、复杂 UI 或外部服务边界，可能超过 3 个工作日。

## 建议下一步顺序

1. 回收第二轮 worker 输出。
2. 先复核底层 service/repository 测试，再复核 UI/user-flow 测试。
3. 跑所有受影响 focused tests。
4. 跑 `flutter analyze` 和 governance-only。
5. 跑 Flutter full coverage 并计算新 LCOV。
6. 按新的 LCOV gap 再派下一轮 worker。
7. 达到 Flutter 100% 后，重跑 server/web_admin/Flutter 全部最终门禁。

## 当前可对外同步的一句话

Server 和 web_admin 已验证 100% coverage；Flutter 全量测试 660/660、analyze、governance 当前通过，但 Flutter LCOV 仍为 87.63%（26512/30255），距离 100% 还缺 3743 行。因此当前任务仍在进行中，不能宣称全覆盖完成。
