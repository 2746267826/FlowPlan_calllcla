# FlowPlan 全功能实现索引（2026-04-28）

本文档用于完整整理当前 FlowPlan 仓库已经规划并实现到代码中的全部主要功能、端侧边界、实现方式、数据模型和关联文件。  
它不是未来计划，而是“当前软件能力与实现位置索引”。若某能力仍偏骨架或 MVP，文中会直接标注。

## 0. 标记说明

### 端侧标记

- `[服务端]`：NestJS 服务端，事实库、API、同步、审计、后台能力。
- `[管理端]`：`web_admin` React + Vite 管理控制台，面向全局数据、设置、监控、日志和运维。
- `[Flutter桌面]`：Flutter 原生客户端 Windows/桌面能力。
- `[Android]`：Flutter Android 客户端能力，部分原生权限/存储能力降级或待完善。
- `[Flutter Web]`：Flutter 浏览器版用户端，日常查看/编辑任务、日程、文件、追踪摘要、报告，不做原生采集。
- `[本地库]`：客户端 SQLite/Drift 本地缓存、离线写入、启动加速。
- `[外部系统]`：Outlook、OneDrive、Kopia、Telegram、天气、AI Provider 等外部依赖。

### 状态标记

- `[已实现]`：代码中存在完整接口、页面或主要流程。
- `[MVP]`：最小闭环可用，但仍缺少长期稳定性、完整异常处理或真实设备验证。
- `[骨架]`：表、接口、页面入口或 Provider 存在，但还不能等同完整功能。
- `[占位]`：为未来扩展预留结构，当前仅能展示或保存元数据。
- `[限制]`：当前实现存在明确边界或平台限制。

## 1. 当前整体架构

### 1.1 软件定位

FlowPlan 当前已经从单纯本地计划软件扩展为：

- 服务端事实库优先。
- Flutter 原生客户端保留本地数据库，用于离线缓存、断网写入、启动加速和本机能力。
- Flutter Web 是不安装客户端时使用的浏览器版用户端。
- Web Admin 是单事实库全局管理控制台，不做 SaaS 多用户后台。
- 所有高风险或自动写入能力原则上必须保留人工确认与审计。

### 1.2 模块目录

- `[服务端]` `server/src/`
  - `app.module.ts`：注册所有 Controller / Service。
  - `main.ts`：Nest 应用启动、CORS、全局 `/api` 前缀。
  - `database/p1_schema.sql`：PostgreSQL 主 schema。
  - `database/database.service.ts`：PG Pool 与事务封装。
- `[Flutter桌面][Android][Flutter Web]` `client_flutter/lib/`
  - `main.dart`：条件入口。
  - `core/platform/app_entry*.dart`：区分 IO 原生客户端与 Web 用户端。
  - `app.dart`：原生 Flutter 客户端主应用。
  - `web_app/`：Flutter Web 用户端。
- `[管理端]` `web_admin/src/`
  - `main.tsx`：单文件 React 管理控制台主逻辑。
  - `styles.css`：管理端样式。

### 1.3 端侧边界

#### Flutter 原生客户端

标记：`[Flutter桌面] [Android] [本地库]`

职责：

- 日常任务、日程、追踪、实际记录、排程、文件上下文、报告、设置。
- 本地 SQLite 保存缓存和离线写入。
- 写入时先本地落库，再生成 `offline_mutations`，再推送服务端。
- Windows 可使用原生窗口/RawInput/资源管理器等能力。
- Android 使用移动端权限、UsageStats、Scoped Storage 方向能力。

主要文件：

- `client_flutter/lib/app.dart`
- `client_flutter/lib/main.dart`
- `client_flutter/lib/core/platform/app_entry_io.dart`
- `client_flutter/lib/core/platform/platform_bootstrap_io.dart`
- `client_flutter/lib/core/database/app_database.dart`
- `client_flutter/lib/shared/providers/app_providers.dart`

#### Flutter Web 用户端

标记：`[Flutter Web] [服务端事实库客户端]`

职责：

- 像浏览器版 FlowPlan：查看今日、任务、日程、文件、追踪摘要、报告、设置。
- 不做原生追踪采集。
- 不使用本地 SQLite/Drift 作为事实库。
- 本地只保存服务端地址、token、设备 ID、最近 bootstrap、少量 UI 状态。
- 文件中心使用服务端云盘树，不扫描本地目录。

主要文件：

- `client_flutter/lib/core/platform/app_entry_web.dart`
- `client_flutter/lib/web_app/flowplan_web_app.dart`
- `client_flutter/lib/web_app/web_api_client.dart`
- `client_flutter/lib/web_app/web_local_store.dart`

#### Web Admin 管理端

标记：`[管理端] [单事实库全局控制台]`

职责：

- 管理所有数据、设置、同步、设备、冲突、日志、文件、报告、AI、运维操作。
- 不按多用户后台设计，而是“一个事实库 + 多客户端/多设备”的全局控制台。
- 默认只读，设置和受控操作通过明确按钮、prepare/confirm、审计链路完成。

主要文件：

- `web_admin/src/main.tsx`
- `web_admin/src/styles.css`

#### 服务端

标记：`[服务端] [事实库] [审计]`

职责：

- 用户、设备、同步、变更日志、冲突、审计。
- 远程设置、客户端 bootstrap、首次导入。
- 任务/日程等通用同步对象事实库。
- 活动理解、统计查询、智能排程、报告与日记、AI、文件云盘、传输、Kopia 历史版本。

主要文件：

- `server/src/app.module.ts`
- `server/src/main.ts`
- `server/src/database/p1_schema.sql`
- `server/src/common/request-context.ts`

## 2. 核心数据模型

### 2.1 用户与设备

标记：`[服务端] [管理端] [Flutter桌面] [Android] [Flutter Web]`

表：

- `users`：当前事实库用户。
- `devices`：客户端设备，含 `client_device_id`、平台、名称、心跳。

实现方式：

- 客户端请求通过 Header 携带 `x-flowplan-user-id` 和 `x-flowplan-device-id`。
- 如果 Header 缺失，服务端使用默认本地开发用户和默认设备。
- 设备注册与心跳由 `DevicesService` 维护。

关联文件：

- `server/src/common/request-context.ts`
- `server/src/devices/devices.controller.ts`
- `server/src/devices/devices.service.ts`
- `client_flutter/lib/core/platform/device_identity_service.dart`
- `client_flutter/lib/web_app/web_local_store.dart`
- `web_admin/src/main.tsx`

API：

- `POST /api/devices/register`
- `GET /api/devices`
- `PATCH /api/devices/:deviceId`
- `POST /api/devices/:deviceId/heartbeat`

### 2.2 服务端事实对象与同步日志

标记：`[服务端] [本地库] [管理端] [Flutter桌面] [Android]`

表：

- `sync_objects`：服务端事实对象，通用存储任务、日程、排程片段、报告、文件元数据等。
- `sync_mutations`：客户端上报的 mutation 结果。
- `sync_changes`：服务端全局变更日志。
- `sync_cursors`：客户端已消费变更游标。
- `sync_conflicts`：冲突候选与处理结果。

实现方式：

- 客户端本地写入后生成 `offline_mutations`。
- `SyncEngine` 将本地 mutation 推送到服务端。
- 服务端将成功写入对象记录到 `sync_objects`，同时写 `sync_changes`。
- 其他客户端通过 `pull` 按游标拉取 `sync_changes`。
- 冲突不静默覆盖，写入 `sync_conflicts`。

关联文件：

- `server/src/sync/sync.controller.ts`
- `server/src/sync/sync.service.ts`
- `server/src/sync/dto.ts`
- `client_flutter/lib/core/offline_queue/offline_mutation.dart`
- `client_flutter/lib/core/offline_queue/offline_mutation_store.dart`
- `client_flutter/lib/core/offline_queue/offline_mutation_runner.dart`
- `client_flutter/lib/core/sync/sync_engine.dart`
- `client_flutter/lib/core/sync/server_sync_change_applier.dart`
- `client_flutter/lib/core/sync/sync_object_registry.dart`
- `client_flutter/lib/core/sync/sync_object_state_store.dart`
- `client_flutter/lib/core/sync/sync_conflict_store.dart`
- `client_flutter/lib/core/sync/sync_write_recorder.dart`
- `client_flutter/lib/features/sync/server_sync_status_page.dart`
- `web_admin/src/main.tsx`

API：

- `POST /api/sync/push`
- `GET /api/sync/pull`
- `POST /api/sync/ack`
- `GET /api/sync/conflicts`
- `GET /api/sync/status`
- `POST /api/sync/conflicts/:conflictId/resolve`

状态：

- `[MVP]` 同步闭环已有主要代码：本地 mutation、push、pull、ack、冲突表、管理端查看。
- `[限制]` 仍需要真实多端长期验证、复杂冲突算法和更完整异常恢复。

### 2.3 审计日志

标记：`[服务端] [管理端] [Flutter桌面]`

表：

- `audit_logs`
- 客户端本地也有数据操作日志 Repository，用于本机操作记录。

实现方式：

- 服务端所有关键写操作记录 `audit_logs`。
- 管理端可查询审计日志、失败同步、冲突和监控日志。
- 客户端本地一些文件、数据库恢复、操作确认会写本地操作日志。

关联文件：

- `server/src/admin/admin.service.ts`
- `server/src/files/files.service.ts`
- `server/src/client/client.service.ts`
- `server/src/web/web.service.ts`
- `client_flutter/lib/features/audit/data_operation_log_repository.dart`
- `client_flutter/lib/features/audit/presentation/data_operation_log_page.dart`
- `web_admin/src/main.tsx`

API：

- `GET /api/admin/audit-logs`
- `GET /api/admin/monitoring/logs`

状态：

- `[MVP]` 关键服务端操作已写审计。
- `[限制]` 客户端所有本地操作还未完全统一为同一审计模型。

## 3. 启动、入口与平台隔离

### 3.1 Flutter 条件入口

标记：`[Flutter桌面] [Android] [Flutter Web]`

实现方式：

- `main.dart` 只做 Flutter 初始化、SharedPreferences 前缀、日期格式化，然后调用条件入口。
- IO 平台使用 `app_entry_io.dart`，创建 Drift 数据库，启动原生客户端。
- Web 平台使用 `app_entry_web.dart`，不创建 `AppDatabase`，只启动 `FlowPlanWebApp`。

关联文件：

- `client_flutter/lib/main.dart`
- `client_flutter/lib/core/platform/app_entry.dart`
- `client_flutter/lib/core/platform/app_entry_io.dart`
- `client_flutter/lib/core/platform/app_entry_web.dart`
- `client_flutter/lib/core/platform/platform_bootstrap_io.dart`
- `client_flutter/lib/web_app/flowplan_web_app.dart`

状态：

- `[已实现]` Web import 图已隔离原生数据库、RawInput、Windows shell、UsageStats。
- `[限制]` Flutter Web 构建仍需用户手动运行验证。

### 3.2 原生客户端启动

标记：`[Flutter桌面] [Android] [本地库]`

实现方式：

- 启动前执行待处理数据库恢复。
- 创建 `AppDatabase`。
- 确保任务本/日历本容器完整。
- Windows 启动 RawInput 采集。
- 启动追踪服务、提醒服务、服务端 bootstrap 同步服务。

关联文件：

- `client_flutter/lib/core/platform/platform_bootstrap_io.dart`
- `client_flutter/lib/core/storage/database_restore_service.dart`
- `client_flutter/lib/features/calendar/data/calendar_books_repository.dart`
- `client_flutter/lib/features/tracker/services/raw_input_service.dart`
- `client_flutter/lib/features/tracker/services/tracker_service.dart`
- `client_flutter/lib/features/reminders/reminder_service.dart`
- `client_flutter/lib/core/bootstrap/client_bootstrap_service.dart`

状态：

- `[MVP]` 启动链路可用。
- `[限制]` Android 平台原生能力与后台能力需要更多真实设备验证。

## 4. 认证、Bootstrap、远程设置与首次导入

### 4.1 登录与本地 token

标记：`[服务端] [Flutter桌面] [Android] [Flutter Web] [管理端]`

实现方式：

- 服务端当前是本地开发式 token，登录时可指定或生成 userId。
- 客户端保存 accessToken、refreshToken、服务端地址。
- 管理端和 Flutter Web 都可以配置服务端地址并登录。

关联文件：

- `server/src/auth/auth.controller.ts`
- `server/src/auth/auth.service.ts`
- `client_flutter/lib/core/server_api/auth_token_store.dart`
- `client_flutter/lib/core/server_api/server_config_store.dart`
- `client_flutter/lib/web_app/web_local_store.dart`
- `web_admin/src/main.tsx`

API：

- `POST /api/auth/login`
- `POST /api/auth/refresh`
- `POST /api/auth/logout`

状态：

- `[MVP]` 本地开发登录可用。
- `[限制]` 未实现生产级认证、权限、会话失效、用户体系。

### 4.2 Client Bootstrap

标记：`[服务端] [Flutter桌面] [Android] [Flutter Web]`

实现方式：

- 客户端启动后请求服务端上下文。
- 返回用户、设备、服务端时间、远程设置摘要、同步游标、功能开关、待处理事项。
- Flutter Web 用 bootstrap 判断服务端连接状态并缓存最近摘要。

关联文件：

- `server/src/client/client.controller.ts`
- `server/src/client/client.service.ts`
- `client_flutter/lib/core/bootstrap/client_bootstrap_service.dart`
- `client_flutter/lib/core/server_api/client_api.dart`
- `client_flutter/lib/web_app/web_local_store.dart`
- `client_flutter/lib/web_app/flowplan_web_app.dart`

API：

- `GET /api/client/bootstrap`

状态：

- `[MVP]` 可用。

### 4.3 远程设置

标记：`[服务端] [管理端] [Flutter桌面] [Android] [Flutter Web]`

表：

- `admin_remote_configs`

实现方式：

- 非设备级设置迁移到服务端。
- 设置按 key、scope、version、sensitive 标识管理。
- 修改远程设置写审计。
- 客户端读取远程设置，同时保留设备本地例外设置。
- 管理端提供完整编辑入口。
- Flutter Web 只展示用户端设置摘要和连接设置，不承担全局管理。

关联文件：

- `server/src/client/client.service.ts`
- `server/src/admin/admin.service.ts`
- `client_flutter/lib/core/server_api/remote_settings_repository.dart`
- `client_flutter/lib/shared/providers/settings_provider.dart`
- `client_flutter/lib/features/settings/presentation/settings_page.dart`
- `client_flutter/lib/web_app/flowplan_web_app.dart`
- `web_admin/src/main.tsx`

API：

- `GET /api/client/settings`
- `PATCH /api/client/settings/:key`
- `GET /api/client/settings-policy`
- `GET /api/admin/settings`
- `PATCH /api/admin/settings/:configKey`
- `GET /api/admin/remote-configs`
- `PATCH /api/admin/remote-configs/:configKey`

状态：

- `[MVP]` 远程设置表、读写、审计和管理端入口存在。
- `[限制]` 具体客户端 Provider 完整迁移程度仍需逐设置核对。

### 4.4 首次导入与服务端接管

标记：`[服务端] [Flutter桌面] [Android] [管理端]`

表：

- `client_import_sessions`

实现方式：

- 客户端可上传本地快照。
- 服务端 dry-run，统计对象、设置、冲突。
- 用户确认后导入 `sync_objects` 和远程设置。
- 重复导入通过 uid 去重。

关联文件：

- `server/src/client/client.controller.ts`
- `server/src/client/client.service.ts`
- `client_flutter/lib/core/server_api/client_api.dart`
- `client_flutter/lib/features/data_management/presentation/data_management_page.dart`

API：

- `POST /api/client/import/local-snapshot`
- `GET /api/client/import/:importId`
- `POST /api/client/import/:importId/confirm`
- `POST /api/client/import/:importId/cancel`

状态：

- `[MVP]` 服务端导入流程存在。
- `[限制]` 客户端向导体验和真实历史数据迁移需完整验收。

## 5. 任务功能

### 5.1 本地任务管理

标记：`[Flutter桌面] [Android] [本地库]`

本地表：

- `task_items`
- `task_lists`
- `projects`
- `tags`
- `task_schedule_segments` 相关逻辑在排程仓库中维护。

实现方式：

- Flutter 原生端使用 Drift 本地表保存任务。
- 任务详情页支持新建、编辑、查看任务。
- 未排任务面板供智能排程使用。
- 本地写入进入同步队列。

关联文件：

- `client_flutter/lib/core/database/tables/task_items_table.dart`
- `client_flutter/lib/core/database/tables/task_lists_table.dart`
- `client_flutter/lib/features/task/data/task_repository.dart`
- `client_flutter/lib/features/task/presentation/task_detail_page.dart`
- `client_flutter/lib/features/task/presentation/quick_add_bar.dart`
- `client_flutter/lib/features/task/presentation/unscheduled_task_panel.dart`
- `client_flutter/lib/features/task/presentation/widgets/task_tracker_evidence_section.dart`

状态：

- `[MVP]` 原生端任务管理可用。

### 5.2 服务端任务事实库

标记：`[服务端] [管理端] [Flutter Web]`

实现方式：

- 服务端任务以 `sync_objects` 通用对象存储，类型包含 `task`、`task_item`、`task_items` 等。
- `/api/web/tasks` 提供 Flutter Web 用户端任务 ViewModel。
- `/api/admin/data/tasks` 提供管理端全局数据视图。
- 创建/编辑任务写 `sync_objects`、`sync_changes` 和 `audit_logs`。

关联文件：

- `server/src/web/web.controller.ts`
- `server/src/web/web.service.ts`
- `server/src/admin/admin.service.ts`
- `client_flutter/lib/web_app/flowplan_web_app.dart`
- `web_admin/src/main.tsx`

API：

- `GET /api/web/tasks`
- `POST /api/web/tasks`
- `PATCH /api/web/tasks/:id`
- `GET /api/admin/data/tasks`
- `PATCH /api/admin/data/tasks/:id`

状态：

- `[MVP]` Web 用户端和管理端任务读写已具备。
- `[限制]` 服务端还未拆出独立 Task 专用表/专用业务模块，当前依赖 `sync_objects.payload`。

## 6. 日程与日历

### 6.1 原生日历视图

标记：`[Flutter桌面] [Android] [本地库]`

本地表：

- `calendar_events`
- `event_calendars`
- `time_blocks`

实现方式：

- Timeline、Week、Month 三种视图。
- 日程详情页支持新建、编辑。
- 日历本管理页维护日历容器。
- 日程中已支持地点字段展示和编辑方向。

关联文件：

- `client_flutter/lib/features/calendar/presentation/timeline_view.dart`
- `client_flutter/lib/features/calendar/presentation/week_view.dart`
- `client_flutter/lib/features/calendar/presentation/month_view.dart`
- `client_flutter/lib/features/calendar/presentation/event_detail_page.dart`
- `client_flutter/lib/features/calendar/presentation/calendar_shell.dart`
- `client_flutter/lib/features/calendar/presentation/calendar_books_page.dart`
- `client_flutter/lib/features/calendar/data/event_repository.dart`
- `client_flutter/lib/features/calendar/data/calendar_books_repository.dart`
- `client_flutter/lib/core/database/tables/calendar_events_table.dart`
- `client_flutter/lib/core/database/tables/event_calendars_table.dart`
- `client_flutter/lib/core/database/tables/time_blocks_table.dart`

状态：

- `[MVP]` 原生日程主流程可用。

### 6.2 服务端日程与 Flutter Web 日程

标记：`[服务端] [Flutter Web] [管理端]`

实现方式：

- 服务端日程以 `sync_objects` 存储，类型包含 `calendar_event`、`calendar_events`、`event` 等。
- `/api/web/events` 提供 Flutter Web 用户端日程 ViewModel。
- `/api/web/dashboard` 汇总今日日程、当前/下一项。
- 管理端通过 `/api/admin/data/schedules` 查看全局日程与排程对象。

关联文件：

- `server/src/web/web.controller.ts`
- `server/src/web/web.service.ts`
- `server/src/admin/admin.service.ts`
- `client_flutter/lib/web_app/flowplan_web_app.dart`
- `web_admin/src/main.tsx`

API：

- `GET /api/web/events`
- `POST /api/web/events`
- `PATCH /api/web/events/:id`
- `GET /api/admin/data/schedules`

状态：

- `[MVP]` Web 日程查看、新建、编辑可用。

## 7. 阻挡日程与实际记录自动候选

标记：`[服务端] [Flutter桌面] [Android] [管理端]`

表：

- `actual_activity_logs`
- `task_work_logs`
- `activity_segments`
- 本地实际记录仓库也有对应缓存。

实现方式：

- 阻挡日程可作为必须执行的日程。
- 若对应时间没有其他已记录事项，可生成实际记录候选。
- 活动片段确认后写 `actual_activity_logs` 和 `task_work_logs`。

关联文件：

- `client_flutter/lib/features/actual/services/blocking_event_actual_candidate_service.dart`
- `client_flutter/lib/features/actual/data/actual_activity_log_repository.dart`
- `server/src/activity-understanding/activity-understanding.service.ts`
- `server/src/activity-understanding/activity-understanding.controller.ts`
- `server/src/admin/admin.service.ts`
- `client_flutter/lib/features/tracker/presentation/activity_review_page.dart`
- `client_flutter/lib/features/task/presentation/widgets/task_tracker_evidence_section.dart`

API：

- `GET /api/web/actual-records`
- `GET /api/admin/actual-records`
- `PATCH /api/admin/actual-records/:actualId`
- `POST /api/activity-understanding/segments/:segmentId/confirm`
- `POST /api/activity-understanding/segments/:segmentId/reject`

状态：

- `[MVP]` 活动片段确认到实际记录/任务投入有最小闭环。
- `[限制]` 自动写入仍应保持人工确认，不应静默成为事实。

## 8. 追踪、活动记录与统计

### 8.1 原生追踪采集

标记：`[Flutter桌面] [Android] [本地库]`

本地表：

- `activity_records`
- `tracked_input_events`
- `app_usage_rules`

实现方式：

- Windows 通过 RawInput 和窗口传感器记录活动。
- Android 通过 UsageStats 导入应用使用记录。
- 输入事件、活动记录和工作会话在本地分析展示。
- 追踪页展示热力图、活动记录、输入行为、历史详情。

关联文件：

- `client_flutter/lib/features/tracker/services/tracker_service.dart`
- `client_flutter/lib/features/tracker/services/raw_input_service.dart`
- `client_flutter/lib/features/tracker/services/window_sensor.dart`
- `client_flutter/lib/features/tracker/services/android_usage_stats_service.dart`
- `client_flutter/lib/features/tracker/services/android_usage_import_service.dart`
- `client_flutter/lib/features/tracker/services/input_activity_event_service.dart`
- `client_flutter/lib/features/tracker/services/activity_log_service.dart`
- `client_flutter/lib/features/tracker/data/tracker_repository.dart`
- `client_flutter/lib/features/tracker/data/activity_record_repository.dart`
- `client_flutter/lib/features/tracker/presentation/tracker_page.dart`
- `client_flutter/lib/features/tracker/presentation/tracker_log_history_page.dart`
- `client_flutter/lib/features/tracker/presentation/tracker_input_history_page.dart`
- `client_flutter/lib/features/tracker/presentation/input_heatmap_page.dart`
- `client_flutter/lib/features/tracker/widgets/heatmap_widget.dart`

状态：

- `[MVP]` 本地追踪和展示已实现。
- `[限制]` Android 权限、后台采集和真实设备长期稳定性需要更多验证。

### 8.2 服务端活动统计

标记：`[服务端] [管理端] [Flutter Web]`

表：

- `activity_hourly_stats`
- `activity_daily_stats`
- `input_hourly_stats`
- `input_daily_stats`
- `activity_records`
- `tracked_input_events` 相关对象可同步到服务端事实库。

实现方式：

- 服务端提供聚合统计接口，避免客户端下载大量原始数据。
- Flutter Web 追踪页只展示服务端聚合，不采集。
- 管理端可查看追踪摘要和原始对象。

关联文件：

- `server/src/analytics/analytics.controller.ts`
- `server/src/analytics/analytics.service.ts`
- `client_flutter/lib/core/server_api/analytics_api.dart`
- `client_flutter/lib/web_app/flowplan_web_app.dart`
- `web_admin/src/main.tsx`

API：

- `GET /api/analytics/activity-heatmap`
- `GET /api/analytics/input-heatmap`
- `GET /api/analytics/activity-range-summary`
- `GET /api/analytics/top-apps`
- `GET /api/analytics/top-categories`
- `GET /api/analytics/task-work-summary`
- `GET /api/analytics/focus-trends`
- `GET /api/analytics/activity-records`
- `GET /api/analytics/input-events`

状态：

- `[MVP]` 聚合查询接口和 Web 展示存在。
- `[限制]` 统计结果质量依赖数据同步与聚合表填充。

## 9. 活动理解与实际记录确认

标记：`[服务端] [Flutter桌面] [管理端]`

表：

- `activity_segments`
- `activity_interpretations`
- `activity_segment_evidence`
- `actual_activity_logs`
- `task_work_logs`

实现方式：

- 服务端读取一天内 raw/activity/input/actual 数据。
- 按时间和应用规则合并为 `activity_segments`。
- 生成标题、时间范围、主要应用、主要窗口、证据、置信度。
- 根据任务标题、文件夹、窗口标题、文件路径尝试关联任务。
- 用户确认后写实际记录和任务投入。
- 管理端可查看活动片段、解释和任务投入。

关联文件：

- `server/src/activity-understanding/activity-understanding.controller.ts`
- `server/src/activity-understanding/activity-understanding.service.ts`
- `client_flutter/lib/core/server_api/activity_understanding_api.dart`
- `client_flutter/lib/features/tracker/data/activity_fusion_repository.dart`
- `client_flutter/lib/features/tracker/services/activity_fusion_service.dart`
- `client_flutter/lib/features/tracker/presentation/activity_review_page.dart`
- `client_flutter/lib/features/actual/data/actual_activity_log_repository.dart`
- `web_admin/src/main.tsx`

API：

- `POST /api/activity-understanding/build-segments`
- `GET /api/activity-understanding/segments`
- `POST /api/activity-understanding/segments/:segmentId/confirm`
- `POST /api/activity-understanding/segments/:segmentId/reject`
- `GET /api/admin/data/activity-segments`
- `GET /api/admin/data/activity-interpretations`
- `GET /api/admin/data/task-work-logs`

状态：

- `[MVP]` 规则合并、候选确认、实际记录生成已实现到代码。
- `[限制]` LLM 深度理解、长期模型训练和复杂语义合并仍未完成。

## 10. 智能排程

标记：`[服务端] [Flutter桌面] [管理端]`

表：

- `schedule_runs`
- `schedule_draft_items`
- `plan_deviations`
- `sync_objects` 中的 `task_schedule_segment`
- 本地 `task_schedule_segment_repository` 管理排程片段。

实现方式：

- 用户选择排程范围。
- 系统读取任务、日程、阻挡日程、已确认实际投入。
- 根据实际投入减少任务剩余时间。
- 生成排程草案，不直接写库。
- 用户确认后写入排程片段并进入同步队列。
- 拒绝草案不写入。
- 管理端查看排程运行、草案项、偏离记录。

关联文件：

- `server/src/scheduler/scheduler.controller.ts`
- `server/src/scheduler/scheduler.service.ts`
- `client_flutter/lib/core/server_api/scheduler_api.dart`
- `client_flutter/lib/features/scheduler/scheduler_engine.dart`
- `client_flutter/lib/features/scheduler/task_schedule_segment_repository.dart`
- `client_flutter/lib/features/scheduler/plan_feedback_service.dart`
- `client_flutter/lib/features/task/presentation/unscheduled_task_panel.dart`
- `client_flutter/lib/features/calendar/presentation/timeline_view.dart`
- `web_admin/src/main.tsx`

API：

- `POST /api/scheduler/runs`
- `GET /api/scheduler/runs/:runId`
- `POST /api/scheduler/runs/:runId/accept`
- `POST /api/scheduler/runs/:runId/reject`
- `POST /api/scheduler/deviations/detect`
- `GET /api/admin/data/schedule-runs`
- `GET /api/admin/data/schedule-draft-items`
- `GET /api/admin/data/plan-deviations`

状态：

- `[MVP]` 草案、确认、拒绝、写入排程片段的服务端闭环存在。
- `[限制]` 不是完整约束求解器，复杂重排和 Outlook 写入未完全纳入。

## 11. 文件上下文、本地文件中心与云盘化

### 11.1 本地文件上下文

标记：`[Flutter桌面] [Android] [本地库]`

本地/服务端模型：

- `file_folders`
- `file_items`
- `file_context_links`
- `file_folder_usages`
- `file_nodes`
- `file_roots`

实现方式：

- 用户添加资料库 Root。
- 原生客户端扫描本地 Root 生成文件树。
- 任务详情和日程详情可绑定文件/文件夹上下文。
- 支持打开文件、在资源管理器中显示、预览文本/Markdown/图片。
- 本地扫描结果可推送服务端，映射为逻辑云盘节点。

关联文件：

- `client_flutter/lib/features/files/data/file_context_repository.dart`
- `client_flutter/lib/features/files/presentation/file_context_page.dart`
- `client_flutter/lib/features/files/presentation/file_context_panel.dart`
- `client_flutter/lib/features/files/services/file_context_interaction_service.dart`
- `client_flutter/lib/core/platform/desktop_shell_service.dart`
- `client_flutter/lib/core/server_api/file_context_api.dart`
- `server/src/files/files.controller.ts`
- `server/src/files/files.service.ts`

状态：

- `[MVP]` 本地资料库、文件树、绑定、打开、预览、日志具备。
- `[限制]` Android SAF/URI 模型仍需进一步完善。

### 11.2 服务端逻辑云盘

标记：`[服务端] [Flutter Web] [管理端]`

表：

- `file_roots`
- `file_nodes`
- `file_node_device_locations`
- `file_identity_mappings`
- `file_recent_items`
- `file_recommendations`
- `file_operation_logs`

实现方式：

- `file_nodes` 是逻辑云盘主树。
- 本地路径只是某设备上的本地副本，不是文件本体。
- 服务端返回 Root、目录、文件、存储状态、当前设备可用状态、hash/identity 摘要。
- Flutter Web 文件页浏览服务端云盘树，不扫描本地目录。
- 上传文件后写入 `file_storage_objects`，并创建/更新 `file_nodes`。
- 下载通过 download session 和 range chunk 返回 base64 数据，Web 端组装 Blob 下载。

关联文件：

- `server/src/files/files.controller.ts`
- `server/src/files/files.service.ts`
- `server/src/files/local-object-storage.service.ts`
- `client_flutter/lib/web_app/flowplan_web_app.dart`
- `client_flutter/lib/core/server_api/file_context_api.dart`
- `client_flutter/lib/core/server_api/file_cloud_api.dart`
- `web_admin/src/main.tsx`

API：

- `GET /api/files/drive/roots`
- `GET /api/files/drive/nodes`
- `GET /api/files/drive/nodes/:nodeId`
- `POST /api/files/drive/nodes/:nodeId/open-plan`
- `POST /api/files/drive/nodes/:nodeId/device-location`
- `POST /api/files/drive/nodes/:nodeId/download-request`
- `POST /api/files/drive/roots/:rootId/scan`
- `POST /api/files/drive/nodes/:nodeId/relink`
- `POST /api/files/roots`
- `POST /api/files/nodes/snapshot`
- `POST /api/files/nodes/:nodeId/log`

状态：

- `[MVP]` 服务端逻辑云盘树、Web 云盘浏览、上传落节点、下载/预览已实现。
- `[限制]` OneDrive 双向同步、完整本地同一性检测、多端缓存策略还未完全生产化。

## 12. 多路径文件传输、服务端存储与断点续传

标记：`[服务端] [Flutter桌面] [Android] [Flutter Web] [管理端]`

表：

- `file_storage_objects`
- `file_transfer_sessions`
- `file_transfer_chunks`
- `file_transfer_candidates`
- `device_network_presence`
- `file_transfer_events`

实现方式：

- 上传创建 upload session。
- 小文件和大文件都可分块上传。
- 服务端记录每个 chunk。
- 客户端可查询 missing chunks 后续传。
- 上传完成后合并 chunk，写入 `server_storage`，计算 hash，生成 storage object。
- 下载创建 download session，通过 range 获取 chunk。
- 管理端查看传输会话、候选路径、事件和失败原因。
- 当前主路径是服务端中转，局域网/P2P 是候选与预留。

关联文件：

- `server/src/files/files.controller.ts`
- `server/src/files/files.service.ts`
- `server/src/files/local-object-storage.service.ts`
- `client_flutter/lib/features/files/services/file_transfer_service.dart`
- `client_flutter/lib/features/files/presentation/file_transfer_center_page.dart`
- `client_flutter/lib/core/server_api/file_cloud_api.dart`
- `client_flutter/lib/web_app/flowplan_web_app.dart`
- `web_admin/src/main.tsx`

API：

- `POST /api/files/upload-sessions`
- `PUT /api/files/upload-sessions/:sessionId/chunks/:chunkIndex`
- `GET /api/files/upload-sessions/:sessionId/missing-chunks`
- `POST /api/files/upload-sessions/:sessionId/complete`
- `POST /api/files/download-sessions`
- `GET /api/files/download-sessions/:sessionId/range`
- `GET /api/files/transfers`
- `POST /api/files/network-presence`
- `GET /api/files/network-presence`
- `GET /api/files/transfers/:sessionId/candidates`
- `POST /api/files/transfers/:sessionId/candidates`
- `POST /api/files/transfers/:sessionId/events`

状态：

- `[MVP]` 服务端中转、分块上传、分块下载、断点续传数据结构、进度 UI 存在。
- `[限制]` 不是完整多路径传输，P2P/WebRTC/TURN/真实局域网发现未实现。

## 13. Kopia 历史版本与云文件历史

标记：`[服务端] [Flutter桌面] [管理端] [外部系统]`

表：

- `file_version_records`
- `file_version_download_requests`
- `file_storage_objects`

实现方式：

- 服务端封装 Kopia CLI。
- 可为资料库 Root 创建 snapshot。
- 读取 Kopia snapshot 列表并映射为 file version metadata。
- 用户可选择历史版本下载为副本。
- 恢复旧版本只做 prepare，不应直接覆盖当前文件。
- 版本操作写审计。

关联文件：

- `server/src/files/kopia.service.ts`
- `server/src/files/files.service.ts`
- `server/src/files/files.controller.ts`
- `client_flutter/lib/core/server_api/file_cloud_api.dart`
- `client_flutter/lib/features/files/presentation/file_context_page.dart`
- `web_admin/src/main.tsx`

API：

- `POST /api/files/kopia/snapshots`
- `POST /api/files/kopia/versions/refresh`
- `GET /api/files/versions/:fileId`
- `POST /api/files/versions/:versionId/download-requests`
- `POST /api/files/versions/:versionId/download-copy`
- `POST /api/files/versions/:versionId/restore-prepare`

状态：

- `[MVP]` Kopia CLI 封装、snapshot、版本映射、下载副本、恢复 prepare 存在。
- `[限制]` 依赖用户安装/配置 Kopia；完整恢复覆盖仍需二次确认流程完善。

## 14. OneDrive 与 Outlook

### 14.1 Outlook 任务/日程同步

标记：`[Flutter桌面] [Android] [服务端] [外部系统]`

表：

- `outlook_object_mappings`
- 客户端有 Outlook binding/mirror 相关本地仓库。

实现方式：

- 当前客户端保留 Outlook OAuth、日历服务、任务镜像绑定、同步策略。
- 未来方向是服务端读取 Outlook 任务，服务端事实库为主，Outlook 作为可视化/外部映射。
- 写入 Outlook 必须严格审计和人工确认。

关联文件：

- `client_flutter/lib/features/sync/ms_graph_service.dart`
- `client_flutter/lib/features/sync/outlook_auth_service.dart`
- `client_flutter/lib/features/sync/outlook_calendar_service.dart`
- `client_flutter/lib/features/sync/outlook_diagnostics_service.dart`
- `client_flutter/lib/features/sync/outlook_managed_container_service.dart`
- `client_flutter/lib/features/sync/outlook_settings_page.dart`
- `client_flutter/lib/features/sync/outlook_task_mirror_sync_service.dart`
- `client_flutter/lib/features/sync/outlook_task_mirror_repository.dart`
- `server/src/admin/admin.service.ts`

API：

- `GET /api/admin/outlook`

状态：

- `[骨架/MVP混合]` 客户端 Outlook 能力存在，服务端同步治理仍偏管理视图和映射表。

### 14.2 OneDrive 文件

标记：`[服务端] [管理端] [外部系统]`

表：

- `file_providers`
- `cloud_file_tree_nodes`
- `file_conflict_candidates`

实现方式：

- 服务端文件 Provider 中预留 OneDrive。
- `cloud_file_tree_nodes` 可作为外部 provider staging 表。
- 当前客户端主文件树已改为 `file_nodes`，OneDrive 应映射到 `file_nodes` 后再展示。

关联文件：

- `server/src/files/files.service.ts`
- `server/src/files/files.controller.ts`
- `client_flutter/lib/features/sync/ms_graph_service.dart`
- `web_admin/src/main.tsx`

状态：

- `[骨架]` OneDrive 完整 OAuth/Graph 文件树双向同步未完成。

## 15. 报告、日报、日记、推送、天气

### 15.1 报告与日记

标记：`[服务端] [Flutter桌面] [Flutter Web] [管理端]`

表：

- `report_documents`
- `diary_entries`
- `report_entries`
- `report_evidence_links`
- `report_templates`

实现方式：

- 服务端生成日报/日记草稿。
- 用户可确认报告/日记。
- 报告条目可引用任务、实际记录、天气、文件、活动证据。
- Flutter 原生有报告中心。
- Flutter Web 可查看报告/日记并生成草稿。
- 管理端可查看报告、条目、证据和推送状态。

关联文件：

- `server/src/reports/reports.controller.ts`
- `server/src/reports/reports.service.ts`
- `client_flutter/lib/core/server_api/reports_api.dart`
- `client_flutter/lib/features/reports/data/report_repository.dart`
- `client_flutter/lib/features/reports/presentation/report_center_page.dart`
- `client_flutter/lib/features/reports/services/report_generation_service.dart`
- `client_flutter/lib/web_app/flowplan_web_app.dart`
- `web_admin/src/main.tsx`

API：

- `GET /api/reports`
- `GET /api/reports/:reportId`
- `POST /api/reports/generate`
- `PATCH /api/reports/:reportId`
- `POST /api/reports/:reportId/confirm`
- `POST /api/reports/:reportId/push`
- `GET /api/diary`
- `POST /api/diary/generate`
- `PATCH /api/diary/:diaryId`
- `POST /api/diary/:diaryId/confirm`
- `GET /api/report-templates`
- `POST /api/report-templates`

状态：

- `[MVP]` 报告/日记生成、确认、查询链路存在。
- `[限制]` 推送真实渠道、复杂报告质量、AI 深度总结仍待加强。

### 15.2 Telegram/Webhook 推送

标记：`[服务端] [管理端] [外部系统]`

表：

- `push_channels`
- `report_push_deliveries`

实现方式：

- 服务端保存推送渠道和投递记录。
- 报告推送生成 delivery。
- 管理端查看和重试投递。

关联文件：

- `server/src/reports/reports.controller.ts`
- `server/src/reports/reports.service.ts`
- `web_admin/src/main.tsx`

API：

- `GET /api/push/channels`
- `POST /api/push/channels`
- `GET /api/push/deliveries`
- `POST /api/push/deliveries/:deliveryId/retry`

状态：

- `[MVP/骨架]` 渠道和 delivery 数据结构存在。
- `[限制]` 真实 Telegram Bot 完整推送需配置和验证。

### 15.3 天气与现实上下文

标记：`[服务端] [管理端] [外部系统]`

表：

- `weather_locations`
- `weather_cache`
- `reality_context_sources`

实现方式：

- 服务端保存天气位置、刷新天气、查询天气摘要。
- 管理端查看天气缓存和现实上下文来源。
- 报告可引用天气和现实上下文。

关联文件：

- `server/src/reports/reports.controller.ts`
- `server/src/reports/reports.service.ts`
- `web_admin/src/main.tsx`

API：

- `GET /api/weather/locations`
- `POST /api/weather/locations`
- `POST /api/weather/locations/:locationId/refresh`
- `GET /api/weather/summary`
- `GET /api/admin/data/weather-cache`
- `GET /api/admin/data/reality-context`

状态：

- `[骨架/MVP]` 数据结构和接口存在，真实天气 Provider 依赖配置。

## 16. AI 聊天、AI 设置、工具策略与操作草案

标记：`[服务端] [Flutter桌面] [管理端] [外部系统]`

表：

- `ai_provider_configs`
- `ai_conversations`
- `ai_messages`
- `ai_operation_drafts`
- `ai_context_snapshots`
- `ai_tool_calls`
- `ai_tool_policies`

实现方式：

- 服务端保存 AI Provider 配置、模型、Base URL、API Key 引用。
- AI 会话和消息保存到服务端。
- AI 工具策略定义工具风险等级、是否需要人工确认。
- AI 操作草案必须人工确认后执行。
- 管理端查看 AI 草案、策略、工具调用。
- 客户端有 AI API 封装与策略 API。

关联文件：

- `server/src/ai/ai.controller.ts`
- `server/src/ai/ai.service.ts`
- `client_flutter/lib/core/server_api/ai_api.dart`
- `client_flutter/lib/core/server_api/ai_policy_api.dart`
- `web_admin/src/main.tsx`

API：

- `GET /api/ai/settings`
- `PATCH /api/ai/settings/:providerKey`
- `POST /api/ai/settings/:providerKey/test`
- `GET /api/ai/context`
- `POST /api/ai/context/snapshots`
- `GET /api/ai/tool-policies`
- `PATCH /api/ai/tool-policies/:toolName`
- `GET /api/ai/conversations`
- `POST /api/ai/conversations`
- `GET /api/ai/conversations/:conversationId/messages`
- `POST /api/ai/messages`
- `GET /api/ai/tool-drafts`
- `PATCH /api/ai/tool-drafts/:draftId`
- `POST /api/ai/tool-drafts/:draftId/confirm`

状态：

- `[MVP/骨架]` Provider 设置、聊天记录、上下文快照、工具策略、操作草案接口存在。
- `[限制]` “完整 AI Agent / OpenClaw 级能力”尚未完成，当前更接近受控 AI 接入底座。

## 17. 管理端全局控制台

标记：`[管理端] [服务端]`

实现方式：

- React + Vite 单页管理端。
- 通过本地保存服务端地址、userId、deviceId 连接服务端。
- 左侧导航按组组织：
  - 总览
  - 数据中心
  - 设置中心
  - 同步与设备
  - 文件与存储
  - 监控与日志
  - 运维操作
- 所有视图调用 `/api/admin/*`、`/api/files/*`。
- 详情面板显示业务字段和原始 JSON。
- 设置表单写远程设置。
- 运维操作需要 prepare/confirm。

关联文件：

- `web_admin/src/main.tsx`
- `web_admin/src/styles.css`
- `server/src/admin/admin.controller.ts`
- `server/src/admin/admin.service.ts`

主要视图：

- 运行总览：`/api/admin/dashboard`
- 任务：`/api/admin/data/tasks`
- 日程：`/api/admin/data/schedules`
- 实际记录：`/api/admin/data/actuals`
- 追踪摘要：`/api/admin/data/tracking`
- 文件元数据：`/api/admin/data/files`
- 报告与日记：`/api/admin/data/reports`
- 活动片段：`/api/admin/data/activity-segments`
- 排程运行：`/api/admin/data/schedule-runs`
- 资料库 Root：`/api/admin/data/file-roots`
- 文件节点：`/api/admin/data/file-nodes`
- 传输路径与事件：`/api/admin/data/transfer-events`
- AI 工具策略：`/api/admin/data/ai-policies`
- AI 草案：`/api/admin/data/ai-drafts`
- 同步健康：`/api/admin/sync-health`
- 服务端变更：`/api/admin/data/sync-changes`
- 客户端写入队列：`/api/admin/data/sync-mutations`
- 设备：`/api/admin/data/devices`
- 冲突：`/api/admin/conflicts`
- 服务端存储：`/api/files/dashboard`
- 存储对象：`/api/files/storage/objects`
- 文件操作日志：`/api/admin/data/file-operation-logs`
- 日志：`/api/admin/monitoring/logs`
- 后台任务：`/api/admin/monitoring/jobs`
- 受控操作：`/api/admin/operations/:operationKey/prepare` 与 `confirm`

状态：

- `[MVP]` 单事实库全局控制台已存在。
- `[限制]` UI 仍是单文件 React，未来可拆模块、详情抽屉、筛选器、编辑态和权限提示。

## 18. Flutter Web 用户端

标记：`[Flutter Web] [服务端事实库客户端]`

实现方式：

- 条件入口启动 `FlowPlanWebApp`。
- Web 不创建 `AppDatabase`。
- `WebLocalStore` 使用浏览器 localStorage/SharedPreferences 保存最小状态。
- `WebApiClient` 直接调用服务端 API。
- 主导航：
  - 今日
  - 日程
  - 任务
  - 文件
  - 追踪
  - 报告
  - 设置

关联文件：

- `client_flutter/lib/core/platform/app_entry_web.dart`
- `client_flutter/lib/web_app/flowplan_web_app.dart`
- `client_flutter/lib/web_app/web_api_client.dart`
- `client_flutter/lib/web_app/web_local_store.dart`
- `server/src/web/web.controller.ts`
- `server/src/web/web.service.ts`

页面功能：

- 今日：`GET /api/web/dashboard`，展示今日任务、日程、当前/下一项、实际记录、同步提示。
- 日程：`GET/POST/PATCH /api/web/events`。
- 任务：`GET/POST/PATCH /api/web/tasks`。
- 文件：`/api/files/drive/*`、upload/download session。
- 追踪：`/api/analytics/*` 只读聚合。
- 报告：`/api/reports`、`/api/diary`。
- 设置：服务端地址、登录、通知权限、远程设置摘要。

状态：

- `[MVP]` 用户端浏览器版已与管理端角色分离。
- `[限制]` 需要用户手动运行 `flutter analyze` 和 `flutter build web` 验证。

## 19. 原生客户端 UI 路由

标记：`[Flutter桌面] [Android]`

入口与路由：

- `/timeline`：时间线。
- `/week`：周视图。
- `/month`：月视图。
- `/task/create`、`/task/:id`：任务详情。
- `/event/create`、`/event/:id`：日程详情。
- `/tracker`：追踪页。
- `/tracker/activity-review`：活动片段确认。
- `/tracker/day-details`：追踪日详情。
- `/tracker/log-history`：活动日志历史。
- `/tracker/input-history`：输入事件历史。
- `/tracker/input-heatmap`：输入热力图。
- `/reports`：报告中心。
- `/files`：文件中心。
- `/files/transfers`：文件传输中心。
- `/audit-logs`：本地操作日志。
- `/data-management`：数据管理。
- `/settings`：设置。
- `/ical`：iCalendar 导入导出。
- `/outlook-sync`：Outlook 设置。
- `/server-sync`：服务端同步状态。

关联文件：

- `client_flutter/lib/core/router/app_router.dart`
- `client_flutter/lib/app.dart`
- `client_flutter/lib/features/calendar/presentation/calendar_shell.dart`

状态：

- `[MVP]` 原生客户端功能入口完整。

## 20. iCalendar 导入导出与数据管理

### 20.1 iCalendar

标记：`[Flutter桌面] [Android]`

实现方式：

- 支持 iCalendar 解析、导入、导出、归档。
- 页面用于导入/导出操作。

关联文件：

- `client_flutter/lib/features/ical/ical_parser.dart`
- `client_flutter/lib/features/ical/ical_exporter.dart`
- `client_flutter/lib/features/ical/flowplan_archive_service.dart`
- `client_flutter/lib/features/ical/ical_import_export_page.dart`
- `client_flutter/lib/features/ical/ical_import_export_page_body.dart`
- `client_flutter/lib/features/ical/ical_import_export_widgets.dart`

状态：

- `[MVP]` 本地 iCalendar 能力存在。

### 20.2 数据管理与数据库恢复

标记：`[Flutter桌面] [Android] [本地库]`

实现方式：

- 本地数据库导出/恢复。
- 启动时检测 pending restore。
- 恢复前备份旧数据库。
- 记录本地数据操作日志。

关联文件：

- `client_flutter/lib/features/data_management/presentation/data_management_page.dart`
- `client_flutter/lib/core/storage/database_restore_service.dart`
- `client_flutter/lib/core/database/app_database.dart`
- `client_flutter/lib/core/storage/app_storage.dart`
- `client_flutter/lib/features/audit/data_operation_log_repository.dart`

状态：

- `[MVP]` 本地数据管理存在。
- `[限制]` Web 不提供本地数据库恢复能力。

## 21. 提醒与通知

标记：`[Flutter桌面] [Android] [Flutter Web]`

实现方式：

- 原生端使用 `flutter_local_notifications`、Android alarm/workmanager 等能力。
- 提醒服务根据设置重建系统提醒计划。
- Web 端只申请浏览器通知权限和页面内提示，不做系统后台常驻。

关联文件：

- `client_flutter/lib/features/reminders/reminder_service.dart`
- `client_flutter/lib/shared/providers/settings_provider.dart`
- `client_flutter/lib/core/platform/platform_bootstrap_io.dart`
- `client_flutter/lib/web_app/flowplan_web_app.dart`

状态：

- `[MVP]` 原生提醒服务存在。
- `[限制]` Web 仅支持浏览器通知方向，不保证后台常驻。

## 22. Android 兼容性与平台能力

标记：`[Android] [Flutter桌面] [Flutter Web]`

实现方式：

- Android `minSdk` 已下调到 26，`compileSdk/targetSdk` 方向保留较新版本。
- Android 文件访问应走 Scoped Storage/SAF 方向。
- Android 使用 UsageStats 导入应用使用。
- Windows 使用 RawInput、窗口传感器、资源管理器打开/显示。
- Web 使用浏览器上传/下载，不使用本地文件夹扫描。

关联文件：

- `client_flutter/android/app/build.gradle.kts`
- `client_flutter/android/app/src/main/AndroidManifest.xml`
- `client_flutter/lib/features/tracker/services/android_usage_stats_service.dart`
- `client_flutter/lib/features/tracker/services/android_usage_import_service.dart`
- `client_flutter/lib/core/platform/desktop_shell_service.dart`
- `client_flutter/lib/features/tracker/services/window_sensor.dart`
- `client_flutter/lib/features/tracker/services/raw_input_service.dart`
- `client_flutter/lib/web_app/flowplan_web_app.dart`

状态：

- `[MVP/限制]` 平台隔离方向已建立；Android 文件和后台能力仍需要真实设备端到端验证。

## 23. 服务端健康、后台任务与运维

标记：`[服务端] [管理端]`

表：

- `server_jobs`

实现方式：

- 健康检查返回服务端状态。
- 管理端可看监控健康、后台任务、失败任务。
- 受控操作走 prepare/confirm。

关联文件：

- `server/src/health/health.controller.ts`
- `server/src/admin/admin.controller.ts`
- `server/src/admin/admin.service.ts`
- `web_admin/src/main.tsx`

API：

- `GET /api/health`
- `GET /api/admin/monitoring/health`
- `GET /api/admin/monitoring/jobs`
- `GET /api/admin/jobs`
- `PATCH /api/admin/jobs/:jobKey`
- `POST /api/admin/operations/:operationKey/prepare`
- `POST /api/admin/operations/:operationKey/confirm`

状态：

- `[MVP]` 运维入口、健康、后台任务表和操作审计存在。
- `[限制]` 具体后台任务调度执行器仍偏基础。

## 24. 当前数据库表总览

### 核心身份与同步

- `users`
- `devices`
- `sync_objects`
- `sync_mutations`
- `sync_changes`
- `sync_conflicts`
- `sync_cursors`
- `audit_logs`

### 活动与统计

- `activity_hourly_stats`
- `activity_daily_stats`
- `input_hourly_stats`
- `input_daily_stats`
- `actual_activity_logs`
- `activity_segments`
- `activity_interpretations`
- `activity_segment_evidence`
- `task_work_logs`

### 报告、日记、推送、天气

- `report_documents`
- `diary_entries`
- `report_push_deliveries`
- `report_entries`
- `report_evidence_links`
- `report_templates`
- `push_channels`
- `weather_locations`
- `weather_cache`
- `reality_context_sources`

### 文件、云盘、传输、版本

- `file_folders`
- `file_items`
- `file_context_links`
- `file_folder_usages`
- `file_version_records`
- `file_providers`
- `cloud_file_tree_nodes`
- `file_storage_objects`
- `file_transfer_sessions`
- `file_transfer_chunks`
- `file_conflict_candidates`
- `file_version_download_requests`
- `file_roots`
- `file_nodes`
- `file_node_device_locations`
- `file_identity_mappings`
- `file_recent_items`
- `file_recommendations`
- `file_operation_logs`
- `file_transfer_candidates`
- `device_network_presence`
- `file_transfer_events`

### 外部系统、AI、设置、导入、后台任务

- `outlook_object_mappings`
- `admin_remote_configs`
- `client_import_sessions`
- `server_jobs`
- `ai_operation_drafts`
- `ai_provider_configs`
- `ai_conversations`
- `ai_messages`
- `ai_context_snapshots`
- `ai_tool_calls`
- `ai_tool_policies`

## 25. 当前关键限制与注意事项

### 25.1 不应误解为完整完成的能力

- OneDrive 完整 OAuth/Graph 文件树同步：`[骨架]`
- P2P/WebRTC/TURN 多路径传输：`[占位]`
- 完整 AI Agent / OpenClaw 级自动操作：`[骨架]`
- 生产级身份认证与权限系统：`[占位]`
- Android 后台追踪长期稳定运行：`[需验证]`
- 文件历史版本覆盖恢复：`[prepare 已有，真实覆盖需二次确认完善]`
- Outlook 服务端主动同步和严格双向审计写入：`[部分客户端能力 + 服务端映射/管理]`

### 25.2 已经建立的核心闭环

- 本地写入 -> offline mutation -> 服务端 sync push -> sync_objects/sync_changes -> 其他端 pull。
- 服务端聚合统计 -> 客户端/Flutter Web 展示，避免下载大量原始追踪数据。
- 活动片段 -> 用户确认 -> actual_activity_logs/task_work_logs。
- 智能排程草案 -> 用户确认 -> task_schedule_segments/sync。
- 服务端云盘 Root/file_nodes -> Web/原生文件中心展示。
- 分块上传 -> storage object -> file_node -> 下载/预览。
- Kopia snapshot -> file version metadata -> 下载副本/恢复 prepare。
- 报告/日记生成 -> 用户确认 -> 推送 delivery。
- 管理端设置/操作 -> prepare/confirm 或 PATCH -> audit_logs。

## 26. 建议未来维护方式

- 每新增功能必须在本文档中添加：
  - 功能说明。
  - 端侧标记。
  - 状态标记。
  - 数据表。
  - API。
  - 主要文件。
  - 真实限制。
- 所有自动写入、外部系统写入、删除、恢复、冲突覆盖必须保留：
  - prepare。
  - 人工确认。
  - confirm。
  - audit_logs。
- Flutter Web 只做用户端。
- Web Admin 只做全局管理端。
- 服务端是事实库，客户端本地库是缓存和离线队列，不应长期成为事实孤岛。
