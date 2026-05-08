# FlowPlan 全量功能真伪审计报告（2026-04-30）

## 0. 口径与结论

本报告按“源码/文档/脚本/配置为主，排除依赖缓存、构建产物和运行产物”的口径审计。需求来源包含 `docs/`、`docs/archive/`、`docs/flowplan_modules/`、`docs/update.txt`、README、源码注释和当前上下文中提到的任意功能；但实现状态只按当前代码判断。

状态定义：

| 状态 | 判定标准 |
| --- | --- |
| 已可用 | 有真实 UI/API 入口、持久化或调用链，可在当前架构下操作。外部凭据能力必须已具备真实调用条件。 |
| 代码级 MVP | 有真实服务/仓储/API/数据模型闭环，但缺真实设备、真实规模数据、外部凭据或长期运行验证。 |
| 只有接口/骨架 | 有表、接口、配置项、API client 或 UI 壳，但没有完整可用闭环。 |
| 未实现/缺口 | 需求中提到，当前源码没有可操作实现，或后续计划明确顺延。 |

总判断：

- 服务端和 Web 管理端不是骨架：`server/src` 已有完整 NestJS controller/service/schema，`web_admin/src/main.tsx` 已有多模块管理台，且本次复核 `server npm run build`、`web_admin npm run build` 均通过。
- Flutter 主客户端有真实本地数据库、路由、Repository、Provider、server API client、Windows/Android 原生通道；但本次按约束未运行 Flutter/Dart 命令，Flutter 层只能静态判定。
- 当前大量能力属于“代码级 MVP”，不是“已验证稳定可用”。最大风险集中在真实多端同步、真实追踪数据、真实外部凭据、真实设备长期运行。
- P12/P13/P14/P15 大多仍是未实现或骨架。文档中曾标记完成的 P7/P10/P11 等能力，也需要区分“服务端/管理端 MVP”和“外部系统真实可用”。

## 1. 验证记录

| 项 | 结果 | 说明 |
| --- | --- | --- |
| 服务端构建 | 通过 | 在 `server/` 执行 `npm run build`，Nest build 通过。 |
| Web 管理端构建 | 通过 | 在 `web_admin/` 执行 `npm run build`，`tsc && vite build` 通过。 |
| Flutter/Dart | 未运行 | 遵守 `docs/development_constraints_260426.md`，未执行 `flutter` 或 `dart`。 |
| 数据库写入/服务启动 | 未执行 | 本审计不写数据库、不启动长期服务。 |
| 工作区状态 | 有大量既有未提交改动 | 本报告只新增本文件，不回滚既有改动。 |

建议用户手动补验：

```powershell
cd client_flutter
flutter analyze
flutter test
flutter build windows --debug
flutter build web --debug
flutter build apk --debug --split-per-abi
```

## 2. 功能矩阵

### A. 基础架构、运行与配置

| 功能 | 需求来源 | 平台 | 当前状态 | 代码证据 | 实际入口 | 可用条件 | 缺口/风险 | 建议验证 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Flutter Windows/Android 主客户端保留 | 用户版计划 P0、架构文档 | Windows/Android Flutter | 已可用 | `client_flutter/pubspec.yaml`、`client_flutter/lib/main.dart`、`client_flutter/lib/core/router/app_router.dart` | Flutter 应用路由 `/timeline`、`/week`、`/month` 等 | Flutter SDK 与平台构建环境 | 本次未运行 Flutter 构建 | 用户手动 build Windows/APK |
| 独立 NestJS 服务端 | P0/P1 | 服务端 | 已可用 | `server/src/app.module.ts`、各 controller/service、`server/package.json` | `/api/health`、各 `/api/*` | `DATABASE_URL`、Node 依赖 | 未启动真实服务验证数据库连接 | `npm run db:schema` 后访问 health |
| 独立 Web 管理端 | P0/P9 | Web 管理端 | 已可用 | `web_admin/src/main.tsx`、`web_admin/package.json` | `npm run dev` 后浏览器访问管理台 | 服务端 API base URL | 静态服务可用，但需登录/数据接口验证 | 启动 server + web_admin |
| 一键启动脚本 | 启动脚本需求 | Windows 脚本 | 代码级 MVP | `start-flowplan-all.cmd`、`scripts/start-flowplan-all.ps1` | 双击 cmd 或 PowerShell 参数 | `DATABASE_URL`、npm、flutter 在 PATH | 脚本会运行 Flutter 命令，Codex 未执行；默认 `FlutterWebPort=0` 需实际检查 | 用户本机运行并看 logs |
| 本地环境配置 | README、脚本 | 服务端/脚本 | 已可用 | `flowplan.local.env.example`、启动脚本 env loader | `flowplan.local.env` | 填写真实 PostgreSQL URL | 示例不含外部 API key | 用真实 env 启动 |
| 服务端 health phase/状态 | P1-P11 文档 | 服务端 | 代码级 MVP | `server/src/health/health.controller.ts` | `/api/health` | 服务端启动 | phase 只能说明代码阶段，不等于端到端验收 | health + DB 检查 |

### B. 认证、设备与连接

| 功能 | 需求来源 | 平台 | 当前状态 | 代码证据 | 实际入口 | 可用条件 | 缺口/风险 | 建议验证 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 登录/刷新/登出 API | P1、P9 | 服务端/Web 管理端 | 代码级 MVP | `auth.controller.ts`、`auth.service.ts`、`web_admin/src/main.tsx` login | `/api/auth/login`、`/api/auth/refresh`、`/api/auth/logout` | DB 可用 | 不是生产级账号系统；客户端主要看到 login，refresh/logout 调用少 | 登录后访问受保护接口 |
| 管理端登录态保存 | P9 | Web 管理端 | 已可用 | `web_admin/src/main.tsx` localStorage token/userId/deviceId | 管理端顶部连接/登录区 | 浏览器 localStorage | 安全强度有限 | 刷新页面后检查 token |
| 设备注册、列表、撤销、心跳 | P1 | 服务端 | 代码级 MVP | `devices.controller.ts`、`devices.service.ts`、schema `devices`/`device_connection_events` | `/api/devices/*` | 客户端传 device context | 多真机在线状态未实测 | 两设备注册并发 heartbeat |
| 客户端 heartbeat/bootstrap | P1、P9 | Flutter/Web | 代码级 MVP | `client_api.dart`、`client_bootstrap_service.dart`、`flowplan_web_app.dart` | `/client/bootstrap`、heartbeat | 服务端在线 | Windows/Android 长期心跳未实测 | 启动客户端看管理端在线摘要 |
| 服务端连接指示器 | P1/P3 | Flutter | 代码级 MVP | `server_connection_indicator.dart`、`server_connection_service.dart` | Flutter UI 状态灯 | 服务端 base URL 配好 | 只静态检查，未运行 UI | Flutter 手测断网/恢复 |

### C. 任务、日程、日历与本地数据

| 功能 | 需求来源 | 平台 | 当前状态 | 代码证据 | 实际入口 | 可用条件 | 缺口/风险 | 建议验证 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 时间线/周/月视图 | 早期产品、P0-P3 | Flutter | 已可用 | `app_router.dart`、`calendar_shell.dart`、`timeline_view.dart`、`week_view.dart`、`month_view.dart` | `/timeline`、`/week`、`/month` | Flutter 本地 DB | 未运行 Flutter UI | 创建事件并切视图 |
| 任务创建/详情/完成/删除 | P1、历史计划 | Flutter/服务端/Web | 代码级 MVP | `task_repository.dart`、`task_detail_page.dart`、`client.service.ts`、`web.service.ts` | Flutter `/task/create`、`/task/:id`；API `/client/tasks`、`/web/tasks` | 服务端或本地 DB | 多端一致性未实测 | 离线创建后同步 |
| 日程创建/详情/删除 | P1、日历计划 | Flutter/服务端/Web | 代码级 MVP | `event_repository.dart`、`event_detail_page.dart`、`client.service.ts`、`web.service.ts` | Flutter `/event/create`、API `/client/events`、`/web/events` | 服务端或本地 DB | 复杂重复日程支持有限 | 创建/编辑/删除回归 |
| 日历本/任务本 | P1/P3 | Flutter/服务端 | 代码级 MVP | `calendar_books_repository.dart`、`calendar_books_page.dart`、schema `sync_objects` | Flutter 设置/管理入口、本地仓储 | 本地 DB | UI 与服务端对象映射需实测 | 多设备拉取日历本 |
| iCalendar 导入导出 | 历史计划、P3 | Flutter | 已可用 | `ical_parser.dart`、`ical_exporter.dart`、`ical_import_export_page.dart` | `/ical` | 本地文件访问权限 | 未校验复杂 ICS 兼容性 | 导入/导出样例 ICS |
| 数据导入/导出/恢复管理 | 历史计划、P1/P9 | Flutter/服务端 | 代码级 MVP | `data_management_page.dart`、`database_restore_service.dart`、`client.service.ts` import | `/data-management`、`/client/import/local-snapshot` | 本地 DB、服务端 | 真实快照冲突验收不足 | 准备/确认/取消导入 |
| 本地数据库迁移 | P0-P11 | Flutter | 代码级 MVP | `app_database.dart` schemaVersion 18、多张 ensure table | 应用启动 | Drift/SQLite | 未运行 migration；手写 SQL 多，需回归 | 从旧 DB 升级测试 |

### D. 离线同步、冲突与审计

| 功能 | 需求来源 | 平台 | 当前状态 | 代码证据 | 实际入口 | 可用条件 | 缺口/风险 | 建议验证 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 离线 mutation 队列 | P1、flowplan_modules D | Flutter/服务端 | 代码级 MVP | `offline_mutation_store.dart`、`offline_mutation_runner.dart`、`mutation_coordinator.dart`、`sync.service.ts` | 本地写入失败后入队，`/sync/push` | 服务端 base URL | 双端真实冲突未实测 | 断网建任务，恢复网络 |
| 同步 push/pull/ack/status | P1 | Flutter/服务端 | 代码级 MVP | `sync.controller.ts`、`sync.service.ts`、`sync_engine.dart`、`server_sync_change_applier.dart` | `/api/sync/push`、`pull`、`ack`、`status` | DB、设备上下文 | 服务端事实库可构建，但多设备未验收 | 两客户端同步同一对象 |
| 冲突生成与解决 | P1/P9 | Flutter/服务端/管理端 | 代码级 MVP | `sync_conflict_store.dart`、`sync.service.ts`、`admin.service.ts`、管理端 conflicts dataset | `/api/sync/conflicts`、`/api/admin/data/conflicts` | 多设备并发编辑 | 冲突 UI 细节需实测 | 同字段双端修改 |
| 审计日志 | 全阶段原则 | 服务端/Flutter/管理端 | 代码级 MVP | schema `audit_logs`、`data_operation_log_repository.dart`、`DataOperationLogPage`、各 service `recordAudit` | `/audit-logs`、`/api/admin/data/audit-logs` | 写操作经过服务/仓储 | 高频原始追踪不全审计是设计选择 | 查看一次 AI/同步/文件操作审计 |
| 管理端运维操作 prepare/confirm | P9、确认原则 | Web 管理端/服务端 | 代码级 MVP | `admin.controller.ts` operations、`web_admin/src/main.tsx` OperationsPage | `/api/admin/operations/:key/prepare/confirm` | 管理端登录 | 操作类型有限 | retry_sync/resolve_conflict smoke |

### E. 追踪采集、输入统计与历史日志

| 功能 | 需求来源 | 平台 | 当前状态 | 代码证据 | 实际入口 | 可用条件 | 缺口/风险 | 建议验证 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Windows 前台窗口采样 | CODEX、P2/P5 | Windows Flutter | 代码级 MVP | `window_sensor.dart`、`tracker_service.dart` | 追踪页开始采集 | Windows 桌面权限 | 未实际运行长期采样 | 开启追踪 1 小时 |
| Windows RawInput 键鼠统计 | CODEX、Telemetry V2 | Windows 原生/Flutter | 代码级 MVP | `raw_input_service.dart`、`raw_input_plugin.cpp` MethodChannel `com.flowplan/raw_input` | 追踪服务 `start/getStats/resetStats` | Windows RawInput 可注册 | 真实键鼠事件、权限、后台行为未验收 | 后台采样并查看输入事件 |
| Android UsageStats 导入 | Android 适配需求 | Android Flutter/原生 | 代码级 MVP | `android_usage_stats_service.dart`、`android_usage_import_service.dart`、`MainActivity.kt` | Usage 权限设置 + 导入 | 用户授权 Usage Access | Android 真机长期追踪未验证 | 真机授权后导入一天记录 |
| 当前会话/今日活动记录 | CODEX、P2/P3 | Flutter | 代码级 MVP | `tracker_page.dart`、`tracker_page_models.dart`、`activity_record_repository.dart` | `/tracker` | 本地追踪服务 | FlowPlan 自身污染外部会话的策略需实测 | 切换到 FlowPlan 时观察会话 |
| 原始日志 JSONL/按天归档 | CODEX P1 | Flutter | 代码级 MVP | `activity_log_service.dart`、`input_activity_event_service.dart` | 追踪页导出/历史日志 | 本地文件系统 | “永久保留”依赖磁盘策略，未做长期保留治理 | 查看 archive 文件 |
| 历史日志分页查询 | P2 | Flutter | 已可用 | `readEntriesPage`、`listEventsPage`、`tracker_log_history_page.dart`、`tracker_input_history_page.dart` | `/tracker/log-history`、`/tracker/input-history` | 本地 DB/归档 | 大数据量性能未压测 | 导入大样本后翻页 |
| 输入热力图 | CODEX P3/P2 | Flutter/服务端/Web | 代码级 MVP | `heatmap_widget.dart`、`input_heatmap_page.dart`、`analytics.service.ts` | `/tracker/input-heatmap`、`/analytics/input-heatmap` | 本地或服务端数据 | 小时/日/月/年完整尺度需实际确认 | 不同时间范围切换 |
| 热力图自适应时间尺度 | CODEX | Flutter | 代码级 MVP | `tracker_page.dart` heatmap scale override、providers | 追踪页 | 有多日数据 | 是否完整覆盖小时/日/月/年需 UI 实测 | 新用户/老用户对比 |
| 键盘分类、鼠标按钮、滚轮、移动距离 | Telemetry V2 | Windows/Flutter | 代码级 MVP | `raw_input_service.dart`、`tracked_input_event.dart`、`input_activity_event_service.dart` | 输入统计/历史 | RawInput 正常 | 鼠标移动距离校准、细粒度摘要仍需实测 | 对照系统输入行为 |
| 服务端追踪上传 | P5/P10 | Flutter/服务端 | 代码级 MVP | `tracking_upload_service.dart`、`tracking_ingest_api.dart`、`tracking.service.ts` | `/api/tracking/ingest/batches` | 服务端在线 | 压缩、断点、去重质量有限 | 上传真实一天数据 |

### F. 统计聚合与分析

| 功能 | 需求来源 | 平台 | 当前状态 | 代码证据 | 实际入口 | 可用条件 | 缺口/风险 | 建议验证 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 服务端追踪统计 API | P2 | 服务端/Web/Flutter API | 代码级 MVP | `analytics.controller.ts`、`analytics.service.ts`、`analytics_api.dart` | `/api/analytics/*` | 服务端已有追踪对象 | 真实 SQL 性能未压测 | 7/30 天真实数据查询 |
| tracker home/day/range/filter options | P2/P5 | 服务端/Flutter Web | 代码级 MVP | `analytics.controller.ts`、`flowplan_web_app.dart` | `/analytics/tracker-home`、`range-analysis` | 服务端数据 | 结果准确性依赖数据质量 | 与本地统计对比 |
| top apps/categories/task work/focus trends | P2/P7 | 服务端/Web | 代码级 MVP | `analytics.service.ts`、`flowplan_web_app.dart` | `/analytics/top-apps` 等 | 服务端数据 | 未验证大数据量和边界筛选 | 多条件筛选压测 |
| 客户端本地聚合表 | P2 | Flutter | 只有接口/骨架 | `app_database.dart` `activity_hourly_stats` 等 | 本地 DB | 需要写入聚合任务 | 看到建表，但未确认后台物化聚合写入完整 | 检查是否实际填表 |

### G. 实际记录、活动理解与任务投入

| 功能 | 需求来源 | 平台 | 当前状态 | 代码证据 | 实际入口 | 可用条件 | 缺口/风险 | 建议验证 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 实际记录表与候选/确认/拒绝 | P4 | Flutter/服务端/Web | 代码级 MVP | `actual_activity_log_repository.dart`、schema `actual_activity_logs`、`client.service.ts` | 任务/日程/活动审核、`/client/actual-records` | 本地或服务端数据 | 真实冲突/合并流程未全测 | 阻挡日程生成候选 |
| 阻挡日程自动候选 | P4 | Flutter | 代码级 MVP | `blocking_event_actual_candidate_service.dart` | 日程结束后候选服务 | 日程 `isBlock=true` | 自动触发链路需实测 | 创建已结束阻挡事件 |
| 活动片段构建 | P5 | 服务端/Flutter | 代码级 MVP | `activity-understanding.service.ts`、`activity_fusion_service.dart` | `/activity-understanding/build`、`/tracker/activity-review` | 有追踪数据 | 规则粗，真实数据校准不足 | 上传真实数据后 build |
| 活动确认生成实际记录/任务投入 | P5 | 服务端/Flutter | 代码级 MVP | `confirmSegment`、`task_work_logs`、`activity_review_page.dart` | 活动审核页和 API confirm | 有 segment | 人工修正体验需实测 | 确认低/高置信片段 |
| LLM 低频解释/摘要 | P5/P11 | 服务端 | 代码级 MVP | `ai.service.ts` `explainActivitySegment` | `/api/ai/activity-segments/:id/explain` | AI provider 配好 | 无真实 provider 时不可用 | 配 API key 后测试 |
| 工作会话合并/拆分/标注 | CODEX P2/P6 | Flutter/服务端 | 只有接口/骨架 | 有 fusion/segments；未见完整人工拆分 UI | 活动审核部分入口 | 有数据 | 人工拆分/合并交互不完整 | 设计专门拆分用例 |

### H. 智能排程与计划偏离

| 功能 | 需求来源 | 平台 | 当前状态 | 代码证据 | 实际入口 | 可用条件 | 缺口/风险 | 建议验证 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 排程草案生成 | P6、模块 G | 服务端/Flutter API | 代码级 MVP | `scheduler.controller.ts`、`scheduler.service.ts`、`scheduler_api.dart` | `/api/scheduler/runs` | 服务端任务/日程数据 | 算法是规则/贪心 MVP | 用课表+任务生成 run |
| 排程确认/拒绝写库与审计 | P6 | 服务端 | 代码级 MVP | `acceptRun`、`rejectRun`、`recordChange`、`recordAudit` | `/scheduler/runs/:runId/accept/reject` | run 存在 | 客户端完整确认 UI 需实测 | accept 后拉取 segments |
| 实际投入扣减剩余时间 | P6/260429 模型计划 | 服务端 | 代码级 MVP | `readTasks`、`task_work_logs` 读取逻辑 | 排程生成时 | 有 task_work_logs | 准确性依赖活动确认 | 有/无投入对比 |
| 任务锁定、自动排程开关、时间窗、拆分限制 | 260429 后续计划 | 服务端 | 代码级 MVP | `scheduler.service.ts` task constraints | 排程生成 | payload/远程设置正确 | schema 约定未完全标准化 | 构造锁定任务测试 |
| 基础周期阻挡日程展开 | 260429 | 服务端 | 代码级 MVP | `expandEventOccurrences` | 排程生成 | recurrence payload | 非完整 RFC RRULE | 周期课表回放 |
| 偏离检测 | P6/P15 | 服务端/Flutter API | 代码级 MVP | `/scheduler/deviations/detect`、`plan_deviations` | API | 有计划/实际数据 | 与报告/重排反馈串联不足 | 偏离后生成重排草案 |
| 全局优化/CP-SAT | 历史“不建议” | 服务端 | 未实现/缺口 | 未见优化求解器依赖 | 无 | 无 | 文档明确近期不建议 | 不作为当前目标 |

### I. 报告、日记、推送与天气

| 功能 | 需求来源 | 平台 | 当前状态 | 代码证据 | 实际入口 | 可用条件 | 缺口/风险 | 建议验证 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 日报/周报/月报/专项报告生成 | P7/L | 服务端/Flutter/Web | 代码级 MVP | `reports.service.ts`、`reports_api.dart`、`report_center_page.dart`、`flowplan_web_app.dart` | `/reports/generate`、Flutter `/reports` | 服务端数据 | 真实日报质量未验证 | 生成真实日报并看 entries |
| 报告确认/编辑/润色 | P7 | 服务端/Web/Flutter API | 代码级 MVP | `confirmReport`、`updateReport`、`polishReport` | `/reports/:id/confirm`、`polish` | AI 润色需 provider | 无 provider 时只能模板 | 编辑后确认 |
| 自动日记 | P7/L | 服务端/Web/Flutter API | 代码级 MVP | `diary_entries`、`generateDiary`、`confirmDiary` | `/diary/generate` | 实际记录/活动数据 | 写作偏好学习未完成 | 生成/编辑/确认日记 |
| 报告证据链接 | L 模块 | 服务端/管理端 | 代码级 MVP | `report_entries`、`report_evidence_links`、admin datasets | 管理端报告数据集 | 报告已生成 | 证据展示 UX 需实测 | 检查 report detail |
| Telegram 出站推送 | P7/P12 | 服务端/Web/Flutter API | 代码级 MVP | `push_channels`、`pushReport`、`trySendDelivery` | `/push/channels`、`/reports/:id/push` | 真实 bot token/chat id | 未验证真实 Telegram | 配 token 发一条 |
| Telegram 入站自然语言/回复确认 | P12 | 外部系统/服务端 | 未实现/缺口 | 未见 webhook/bot update receiver | 无 | 无 | 文档明确 P12 未完成 | 后续实现 webhook |
| Webhook 出站推送 | P7/P12 | 服务端 | 代码级 MVP | `push_channels`、`trySendDelivery` | `/push/channels`、报告 push | 真实 webhook URL | 未真实调用验证 | 用测试 webhook |
| Email 推送 | P7 | Flutter/服务端 | 只有接口/骨架 | 文档提到 mailto/队列；服务端 push channel 有通用逻辑 | push channel | 配置方式不完整 | 没有 SMTP 完整实现 | 明确邮件策略 |
| 系统通知 | P7/提醒 | Windows/Android Flutter | 代码级 MVP | Windows tray notification、Android notification receiver、Flutter report push service | 本地通知/提醒 | 平台权限 | Windows 通知依赖托盘；Android 权限未实测 | 触发本地通知 |
| 天气位置、刷新、缓存 | P13/L | 服务端/Web/Flutter API | 代码级 MVP | `weather_locations`、`weather_cache`、`refreshWeather` Open-Meteo | `/weather/locations`、`/weather/summary` | 网络可访问 Open-Meteo | 位置采集未实现；天气只服务端手配 | 配地点刷新天气 |
| 天气影响排程/报告 | P13 | 服务端 | 只有接口/骨架 | 报告可读 weather，排程解释有上下文接口 | 报告/排程 | 天气数据存在 | 深度评分未实现 | 下雨任务评分用例 |

### J. 文件上下文、本地文件、云文件与传输

| 功能 | 需求来源 | 平台 | 当前状态 | 代码证据 | 实际入口 | 可用条件 | 缺口/风险 | 建议验证 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 本地文件夹登记、扫描、文件树 | P8/H | Flutter/服务端 | 代码级 MVP | `file_context_repository.dart`、`file_context_page.dart`、`files.service.ts` roots/nodes | Flutter `/files`、`/api/files/roots/nodes` | 本地文件权限 | Android 本地文件能力弱于 Windows | 登记目录并扫描 |
| 任务/日程绑定文件夹/文件 | P8/H | Flutter/服务端 | 代码级 MVP | `file_context_panel.dart`、`linkNodeToEntity`、`file_context_links` | 任务/日程详情文件面板 | 有 indexed file | 多端路径差异需实测 | 绑定后同步到服务端 |
| 文件推荐 | P8/H/P15 | Flutter/服务端 | 代码级 MVP | `recommendations`、`reviewRecommendation`、本地 `recommendFolders` | 文件面板推荐 | 有任务/文件历史 | 推荐模型仍规则 MVP | 接受/拒绝推荐 |
| 最近/常驻文件夹 | P8 | Flutter | 已可用 | `file_folder_usages`、`FileContextPage` | `/files` | 本地 DB | 设备间同步策略需实测 | 打开文件夹后排序 |
| 文本预览/编辑/保存 | P8/H | Flutter Windows | 已可用 | `file_context_interaction_service.dart`、`file_context_page.dart` | 文件中心右侧预览 | 本地文本文件 | 大文件保护需实测 | 小文本编辑保存 |
| 系统默认打开/资源管理器定位 | P8/H | Windows Flutter/原生 | 已可用 | `desktop_shell_service.dart`、`desktop_shell_plugin.cpp` `openPath/revealPath` | 文件中心按钮/双击 | Windows Shell | Android 无等价原生实现 | 打开/定位真实文件 |
| Windows 系统级右键菜单 | P8/H | Windows | 未实现/缺口 | 未见安装器/注册表右键集成 | 无 | 无 | 文档明确后续阶段 | 后续安装器实现 |
| 手机端长按替代双击 | P8/H | Flutter Android | 只有接口/骨架 | Flutter 公共 UI 有长按交互基础 | 文件列表 | Android 文件访问 | 无 Android 原生 open/reveal 能力 | 真机文件操作 |
| 服务端文件 Provider | P10/J | 服务端/Web/Flutter API | 代码级 MVP | `file_providers`、`FileCloudApi`、`files.service.ts` | `/api/files/providers` | DB | provider 能力声明，不代表外部后端已接入 | upsert provider |
| 服务端对象存储/分块上传 | P10/I | 服务端/Web/Flutter API | 代码级 MVP | `local-object-storage.service.ts`、`createUploadSession`、`uploadChunk`、`completeUploadSession` | `/api/files/upload-sessions/*` | 本地 storage root/DB | 生产 S3/MinIO 未接入 | 上传大文件并校验 hash |
| 范围下载/断点下载 | P10/I | 服务端/Web | 代码级 MVP | `createDownloadSession`、`downloadRange`、`downloadStorageObject` | `/api/files/download-sessions/:id/range` | storage object 存在 | 开发期 JSON/base64，不是完整 HTTP Range 体验 | 中断后续传 |
| 多路径传输/LAN/P2P/TURN | I 模块 | 服务端/客户端 | 只有接口/骨架 | `device_network_presence`、`file_transfer_candidates/events` | transfer candidates/events API | 需要网络候选 | 没有真实 P2P/LAN 传输实现 | 后续实现 sidecar |
| 云端树快照 | P10/J | 服务端/Web/Flutter API | 代码级 MVP | `applyTreeSnapshot`、`cloud_file_tree_nodes` | `/api/files/tree/snapshot`、`/files/drive/nodes` | 外部同步器提供树 | OneDrive Graph 未真实拉取 | 导入模拟树 |
| OneDrive OAuth/Graph 文件下载/双向同步 | P10/J | 外部系统 | 未实现/缺口 | 只有 provider 类型和 tree/node 数据结构 | 无真实 OAuth 入口 | Microsoft 凭据/Graph | 文档明确不硬编码、不在本阶段 | 后续 OAuth 流程 |
| 本地/云端同一性、hash relink | P10/J/H | 服务端/Flutter | 代码级 MVP | `local_file_identity_service.dart`、`compareIdentity`、`relinkDriveNode` | `/files/drive/nodes/:id/relink` | hash 或路径数据 | 大文件 hash 成本/冲突需实测 | 同 hash 文件 relink |
| Kopia snapshot/version refresh | P8/P10/J | 服务端 | 代码级 MVP | `kopia.service.ts`、`createKopiaSnapshot`、`refreshKopiaVersions` | `/api/files/kopia/*` | 本机安装并配置 Kopia | 未用真实 Kopia 验证 | 配 Kopia repo 后跑 |
| 历史版本列表/下载副本/恢复准备 | P10/J | 服务端/Web/Flutter API | 代码级 MVP | `versions`、`createVersionDownloadRequest`、`downloadVersionCopy`、`prepareVersionRestore` | `/api/files/versions/*` | 有版本记录/storage | 覆盖恢复需二次确认流程继续完善 | 下载版本副本 |
| 文件冲突候选/解决 | P10/J | 服务端/管理端 | 代码级 MVP | `file_conflict_candidates`、`createConflict`、`resolveConflict` | `/api/files/conflicts` | 有冲突对象 | 真实双后端冲突未验证 | 构造服务端/云端冲突 |

### K. Web 管理端与运维

| 功能 | 需求来源 | 平台 | 当前状态 | 代码证据 | 实际入口 | 可用条件 | 缺口/风险 | 建议验证 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Dashboard/健康/对象总览 | P9 | Web 管理端/服务端 | 已可用 | `admin.controller.ts`、`admin.service.ts`、`DashboardPage` | `/api/admin/dashboard`、管理端 dashboard | 服务端在线 | 数据准确性依赖 DB | 启动后查看 metrics |
| 数据中心：任务、日程、实际记录、片段、追踪批次、排程 run | P9 | Web 管理端 | 代码级 MVP | `dataCenterDatasets`、`/api/admin/data/:domain` | 管理端数据中心 | 服务端数据 | 编辑能力按 domain 有限 | 点击详情和分页 |
| 同步中心：设备、changes、mutations、conflicts | P9 | Web 管理端 | 代码级 MVP | `syncDatasets`、`SyncPage` | 管理端同步 | 服务端数据 | 真实冲突处理需联调 | 双端冲突后管理端处理 |
| 文件中心管理 | P9/P10 | Web 管理端 | 代码级 MVP | `fileDatasets`、`/api/files/storage/objects` | 管理端文件模块 | 服务端数据 | 管理端不直接打开用户本地文件，符合设计 | 查看 storage object |
| 模型与 AI 管理 | P9/P11 | Web 管理端 | 代码级 MVP | `ModelsPage`、AI Provider save/test、model datasets | 管理端模型与 AI | API key/服务端 | test 需真实外部 API | 配测试 provider |
| 报告和推送管理 | P9/P7 | Web 管理端 | 代码级 MVP | `reportDatasets` | 管理端报告模块 | 报告数据 | 入站 Telegram 不在此 | 查看失败推送重试 |
| 设置/远程配置 | P9 | Web 管理端/服务端 | 代码级 MVP | `SettingsPage`、`admin_remote_configs` | `/api/admin/settings/:key` | 管理登录 | schema 需规范化 | 修改 scheduler.policy |
| 监控日志和 jobs | P9 | Web 管理端/服务端 | 代码级 MVP | `MonitoringPage`、`server_jobs` | `/api/admin/monitoring/*` | 服务端数据 | 没有完整后台队列系统 | 查看 logs/jobs |

### L. AI、模型中心与受控工具调用

| 功能 | 需求来源 | 平台 | 当前状态 | 代码证据 | 实际入口 | 可用条件 | 缺口/风险 | 建议验证 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| AI Provider 配置、加密保存、测试 | P11/K | 服务端/管理端/Flutter API | 代码级 MVP | `ai_provider_configs`、`AiService.upsertProvider/testProvider`、`AiApi`、`ModelsPage` | `/api/ai/settings/:providerKey` | 真实 API key/Base URL | 未真实外部调用 | 配 OpenAI-compatible 端点测试 |
| 只读上下文摘要 | P11/K | 服务端 | 代码级 MVP | `AiService.buildContext`、`/api/ai/context`、`ai_context_snapshots` | `/api/ai/context` | 服务端数据 | 脱敏策略需安全复核 | 检查上下文字段 |
| AI 会话/消息 | P11/K | 服务端/Flutter API/管理端 | 代码级 MVP | `ai_conversations`、`ai_messages`、`sendMessage`、`AiApi` | `/api/ai/conversations`、`/api/ai/messages` | provider 可用；无 provider 有 fallback | Flutter 客户端 UI 入口不完整，管理端更完整 | 发送 create task |
| 操作草案与人工确认 | P11/K | 服务端/管理端/Flutter API | 代码级 MVP | `ai_operation_drafts`、`reviewDraft`、`confirmDraft`、`executeDraft` | `/api/ai/tool-drafts/:id/confirm` | 草案合法 | 可执行工具范围有限 | 生成并确认 create_task |
| 任务/日程/实际记录受控写入 | P11 | 服务端 | 代码级 MVP | `executeDraft`、`createSyncObject` | AI draft confirm | draft type 支持 | 高风险工具仍队列/禁用 | 确认后查 sync_objects |
| 文件推荐、重排、服务器任务等高风险 AI 工具 | P11/P12/P15 | 服务端 | 只有接口/骨架 | tool policies/drafts 存在 | 草案审查 | 需执行器 | 未形成完整执行闭环 | 后续逐工具实现 |
| 模型定义/版本/运行/反馈/学习 | 260429/P15 | 服务端/管理端 | 代码级 MVP | `models.service.ts`、`model_*` tables、`ModelsApi` | `/api/models/*`、管理端模型数据集 | 服务端数据 | 学习是浅层规则权重，不是训练 | 提交反馈后 learn/evaluate |
| 端到端训练/微调大模型 | P15 不建议 | 外部系统 | 未实现/缺口 | 无训练 pipeline | 无 | 无 | 文档明确近期不建议 | 不作为当前验收 |

### M. Outlook、外部入口与生态

| 功能 | 需求来源 | 平台 | 当前状态 | 代码证据 | 实际入口 | 可用条件 | 缺口/风险 | 建议验证 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Outlook 本地设置页/Graph 服务边界 | 历史计划、P1 路线调整 | Flutter | 只有接口/骨架 | `outlook_settings_page.dart`、`ms_graph_service.dart`、`outlook_*` services | `/outlook-sync` | Microsoft OAuth 配置 | `ms_graph_service.dart` 多处返回空列表；不算真实同步 | 后续接 Graph |
| Outlook 对象映射/差异查看基础 | P1/P9 | 服务端/管理端 | 代码级 MVP | `outlook_object_mappings`、admin outlook endpoint | `/api/admin/outlook` | 有映射数据 | 不代表真实 Graph 读写 | 导入模拟映射 |
| Outlook 写入确认/镜像日历 | P1/P6 | 外部系统 | 未实现/缺口 | 有规划和映射表，未见真实写 Graph | 无真实写入入口 | Microsoft OAuth | 文档要求未来人工确认 | 后续实现 confirm write |
| 系统分享文本到 FlowPlan | P12/P14 | Android/Windows | 未实现/缺口 | 未见 share intent/协议处理 | 无 | 平台注册 | 文档明确 P12 未完成 | 后续 platform intent |
| Telegram Bot 入站自然语言 | P12/P14 | 外部系统/服务端 | 未实现/缺口 | 未见 webhook/update receiver | 无 | Bot token/webhook | 只有出站推送 MVP | 后续 Bot receiver |
| Webhook 入站自动化 | P12/P14 | 服务端 | 未实现/缺口 | 未见 inbound webhook controller | 无 | webhook auth | 出站 webhook 不等于入站 | 后续 `/api/integrations/webhook` |
| QQ/微信辅助入口 | P12/P14 | 外部系统 | 未实现/缺口 | 无 | 无 | 平台限制 | 文档明确后置 | 不作为近期 |
| 插件式文件后端/AI Provider/入口生态 | P14 | 服务端/外部 | 只有接口/骨架 | provider configs、file providers、tool policies | 配置表/API | 缺插件加载机制 | 没有真正插件 runtime/权限隔离 | 设计插件清单与沙箱 |
| 本地自动化入口 | P14 | Windows/服务端 | 未实现/缺口 | 无明确 automation API/协议 | 无 | OS 集成 | 未见实现 | 后续定义 CLI/protocol |

### N. 现实上下文、隐私治理与长期智能

| 功能 | 需求来源 | 平台 | 当前状态 | 代码证据 | 实际入口 | 可用条件 | 缺口/风险 | 建议验证 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 位置采样、地点别名 | P13/L | Android/服务端 | 未实现/缺口 | 未见 location permission/service；只有 `reality_context_sources` 表 | 无 | 用户授权 | 文档明确未完成 | 后续移动端位置服务 |
| 蓝牙连接/STM32 | P13 | Android/硬件 | 未实现/缺口 | 未见 Bluetooth/STM32 代码 | 无 | 硬件/权限 | 文档明确长期实验 | 不作为当前 |
| 现实上下文来源表 | P13/P15 | 服务端 | 只有接口/骨架 | `reality_context_sources` schema | 无明确 controller | DB | 表存在但无完整业务闭环 | 后续 API/UI |
| 隐私分层/第三方 LLM 脱敏 | 全阶段原则/P15 | 服务端 | 代码级 MVP | `AiService.buildContext`、报告 LLM 调用只读摘要 | AI 调用链 | provider 调用 | 需要安全审计；字段级策略未完整 | 人工审查 prompt/context |
| 字段级加密 | P15 | 服务端/客户端 | 只有接口/骨架 | AI key 加密；未见通用字段级加密 | AI provider key | secret key | 不覆盖全部敏感字段 | 后续加密方案 |
| 同步范围开关/敏感数据保留周期 | P15 | 服务端/客户端 | 只有接口/骨架 | remote settings/settings policy 存在 | 设置 API | 需策略定义 | 未见统一执行器 | 制定 retention job |
| 数据导出/删除 | P15/历史数据管理 | Flutter/服务端 | 代码级 MVP | 本地 DB 导出、管理端数据 API | `/data-management`、管理端 | 本地/服务端 | 服务端完整 GDPR 式删除未见 | 导出后恢复 |
| 长期趋势、任务耗时预测、个性化学习 | P15/CODEX | 服务端 | 只有接口/骨架 | `model_feedback_events`、`focus-trends`、模型学习浅层规则 | `/api/models/*` | 历史数据 | 不是真正长期智能 | 建立回放评估集 |

## 3. 需求总账摘要

### 已经有真实可操作入口的能力

- Flutter 基础日历/任务/追踪/文件/报告/设置/同步状态路由。
- 服务端 health、auth、devices、sync、client、analytics、tracking、activity-understanding、scheduler、reports、files、ai、models、admin、web API。
- Web 管理端登录、dashboard、数据中心、设置、同步、文件、模型与 AI、报告、监控、运维操作。
- Windows 原生 RawInput、托盘、开机启动、路径打开/定位。
- Android UsageStats 查询通道和 exact alarm 提醒通道。
- 服务端与管理端生产构建通过。

### 代码级 MVP，但不能当作“真实稳定可用”的能力

- 多端离线同步、冲突解决、真实双设备拉取/推送。
- Windows/Android 长期追踪采集、上传、服务端统计。
- 活动理解、任务实际投入、实际记录候选。
- 智能排程、偏离检测和 LLM 托底。
- 报告/日记/推送/天气。
- 文件上传下载、分块续传、历史版本、Kopia、云端树、同一性识别。
- AI Provider、聊天、操作草案、模型中心。
- Web 管理端大部分数据面板和运维操作。

### 只有接口/骨架，容易被误标为完成的能力

- 客户端本地聚合表物化任务。
- Outlook 真实 Graph 读取、写入和镜像日历。
- 多路径文件传输的 LAN/P2P/TURN。
- Email 完整 SMTP 推送。
- AI 高风险工具执行器。
- 插件式文件后端/AI Provider/外部入口生态。
- 现实上下文统一 API。
- 通用字段级加密、同步范围开关、保留周期执行。

### 当前未实现或明确顺延的能力

- Telegram 入站自然语言、Telegram 内确认操作。
- Webhook 入站自动化。
- 系统分享文本到 FlowPlan。
- QQ/微信深度或辅助入口。
- OneDrive OAuth/Graph 真实下载和双向同步。
- Windows 系统级资源管理器右键菜单。
- 位置采样、地点别名、蓝牙、STM32。
- 端到端模型训练/微调、完整长期智能。
- 完整 CP-SAT 或全局优化排程。

## 4. 平台差异

| 平台 | 当前真实能力 | 主要缺口 |
| --- | --- | --- |
| Windows Flutter | 本地 DB、日历任务、追踪、RawInput、托盘、路径打开/定位、文件中心、报告、同步/API 边界。 | 未运行 Flutter 构建；长期追踪、多端同步、文件大数据量、Kopia/外部服务需实测。 |
| Android Flutter | UsageStats、exact alarm 提醒、Flutter 公共 UI/Repository/API。 | 真机权限和后台行为未验证；本地文件打开/定位弱于 Windows；位置/蓝牙未实现。 |
| Flutter Web 客户端 | `/web/*` 任务/日程、文件浏览/上传下载、analytics、activity understanding、reports/weather/push、settings/bootstrap。 | 不做本地追踪、RawInput、托盘、本地 SQLite 事实缓存；与原生端功能一致性需补。 |
| Web 管理端 | 完整管理台模块、数据集、设置、AI Provider、操作 prepare/confirm，构建通过。 | 依赖服务端真实数据；部分操作仍是管理/审计层，不等于外部系统真实执行。 |
| 服务端 | API 和 schema 覆盖很广，核心 service 非骨架，构建通过。 | 需要真实 PostgreSQL、真实外部凭据、真实多端和长期数据验证。 |
| 外部系统 | OpenAI-compatible、Telegram 出站、Webhook 出站、Kopia、Open-Meteo 有调用代码或配置入口。 | 入站 Telegram/Webhook、OneDrive Graph、Outlook Graph、QQ/微信、插件生态未实现。 |

## 5. 高风险断言修正

- “P7 已完成”应理解为：报告/日记/推送的服务端和客户端代码级 MVP 已有；Telegram 出站需要真实 token 才可用，Telegram 回复触发操作草案未实现。
- “P10 已完成”应理解为：服务端文件 API、分块传输、版本元数据、冲突候选、管理端查看已成 MVP；OneDrive 真实 OAuth/Graph、真实多路径传输、生产对象存储未完成。
- “P11 已完成”应理解为：AI Provider、会话、上下文、草案、受控确认执行器已成 MVP；可执行工具范围有限，真实模型调用需要外部凭据。
- “P13 天气”只可算服务端天气配置/缓存 MVP；位置和蓝牙没有实现。
- “P14 插件体系”当前不是可用插件系统，只是若干 Provider/Policy 边界。
- “历史计划里的长期智能”多数没有真实模型训练或评估闭环，只能算模型中心和反馈表的基础。

## 6. 下一步最小验收清单

1. 启动 PostgreSQL，执行 `server npm run db:schema`，启动服务端并访问 `/api/health`、`/api/sync/status`。
2. 启动 Web 管理端，登录后检查 dashboard、settings、sync、files、models、reports。
3. Windows Flutter 手动构建并启动，创建任务/日程，断网修改后恢复网络同步。
4. 两个客户端修改同一任务字段，确认生成冲突而非静默覆盖。
5. Windows 追踪运行 1 天，上传到服务端，构建活动片段并确认任务投入。
6. 用真实任务/课表/阻挡日程生成排程草案，确认后检查 `task_schedule_segment` 与审计。
7. 生成真实日报/日记，检查 evidence links、推送失败重试。
8. 登记真实文件夹，扫描、预览、编辑小文本、打开/定位、绑定到任务。
9. 上传大文件，模拟中断后续传，下载 range，校验 hash。
10. 配置 OpenAI-compatible provider，发送创建任务请求，审核并确认草案。
11. 配置 Telegram/Webhook 出站，发送一条报告推送。
12. 若要提升 OneDrive/Outlook 状态，必须先实现并验证真实 OAuth/Graph 流程。
