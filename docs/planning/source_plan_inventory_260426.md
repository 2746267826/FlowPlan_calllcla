# FlowPlan 历史计划来源映射（2026-04-26）

## 1. 文档定位

本文用于说明目前项目中散落的计划文件分别承担什么角色，以及它们的内容如何汇入新的 `docs/planning/` 权威计划体系。

## 2. 当前权威文档

| 文档 | 角色 |
| --- | --- |
| `docs/planning/master_priority_plan_260426.md` | 当前最完整的 P0-P14 总路线图 |
| `docs/planning/near_term_execution_plan_260426.md` | 近期 P1-P3 可执行清单 |
| `docs/architecture/p0_client_server_architecture_260426.md` | P0 架构主文档 |
| `docs/architecture/p0_completion_report_260426.md` | P0 完成报告 |
| `docs/architecture/p0_p1_handoff_contract_260426.md` | P1 同步开发交接契约 |
| `docs/development_constraints_260426.md` | 开发约束，尤其是禁止 Codex 运行 `flutter` / `dart` 指令 |

## 3. 历史计划文件

| 文件 | 内容状态 | 如何处理 |
| --- | --- | --- |
| `docs/archive/legacy-root-plans/CODEX.md` | 早期任务总表，包含追踪语义、原始日志、工作会话、Android 适配、历史更新记录 | 产品共识和历史背景已吸收入总计划；继续作为历史记录保留 |
| `docs/archive/legacy-root-plans/implementation_plan.md` | Auto AI Tracker / Telemetry V2 的实施计划和技术草案 | 追踪、输入事件、RawInput、洞察大盘相关内容已并入 P2/P5 |
| `docs/archive/legacy-root-plans/task.md` | 早期全新构建任务清单 | 已完成能力和待开发 Telemetry V2 内容已并入 P2/P5 |
| `docs/archive/legacy-root-plans/plan260422.txt` | 早期阶段计划和任务记录 | 作为历史来源保留，不再作为当前执行入口 |
| `docs/archive/legacy-root-plans/plan260424.md` | 2026-04-24 后续开发计划，含发布稳定、信息架构、模型补强、排程、提醒、追踪、Outlook、数据管理 | 相关内容已并入 P2/P3/P6/P13 与近期执行清单 |
| `docs/archive/legacy-root-plans/future_development_plan_260426.md` | 用户新增大量未来想法后的第一版未来计划 | 全部关键想法已并入当前 P0-P14 总计划 |
| `docs/archive/legacy-root-plans/complete_development_plan_260426.md` | 较完整的长期可执行开发蓝图 | 已作为当前总计划的主要来源之一 |
| `docs/archive/legacy-root-plans/priority_development_plan_260426.md` | P0-P12 优先级计划 | 已升级整理为 `master_priority_plan_260426.md` |
| `docs/update.txt` | 日常更新日志 | 继续保留，并记录阶段开发和目录整理 |
| `client_flutter/version.txt` | Flutter 客户端发布版本摘要 | 仍用于发布，不作为开发计划入口 |

## 4. 迁移原则

- 不删除历史文件，避免丢失上下文。
- 不把所有历史正文机械复制进新文档，只迁移仍然有效、未来需要执行或需要作为约束的内容。
- 后续新增计划优先写入 `docs/planning/`。
- 架构决策写入 `docs/architecture/`。
- 运行约束写入 `docs/development_constraints_260426.md`。
