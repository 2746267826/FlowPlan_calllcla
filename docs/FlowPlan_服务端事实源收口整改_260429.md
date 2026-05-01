# FlowPlan 服务端事实源收口整改记录 260429

## 本次收口原则

- 服务端是任务、日程、实际记录、排程、报告、文件、AI、设置和模型结果的最终事实源。
- Flutter 原生客户端保留 SQLite，但只作为本地缓存、离线变更队列、追踪临时缓冲、设备级设置和本机文件副本索引。
- Flutter Web 不使用本地业务数据库，不采集追踪，只作为服务端事实库的浏览器客户端。
- 所有普通业务写入应通过服务端 API 或离线 mutation 进入服务端；服务端成功接收后才成为 canonical object。
- 所有自动操作、冲突解决、AI 工具执行、文件覆盖、外部系统写入继续要求人工确认和审计。

## 本次已完成的代码收口

### 服务端客户端业务 API

新增正式客户端路径，复用已有服务端事实库逻辑：

- `GET /api/client/tasks`
- `POST /api/client/tasks`
- `PATCH /api/client/tasks/:id`
- `GET /api/client/events`
- `POST /api/client/events`
- `PATCH /api/client/events/:id`
- `GET /api/client/actual-records`
- `GET /api/client/settings/effective`
- `POST /api/client/mutations`

这些接口用于让 Windows、Android、Flutter Web 使用同一组服务端 ViewModel 与写入路径，不再只能依赖本地 Drift 表或 sync raw payload。

### 服务端写入回执增强

任务和日程通过服务端创建或更新时，现在返回：

- `canonical`
- `serverVersion`
- `syncChangeId`
- `auditId`
- `item`

这让客户端可以明确区分“服务端已接管的事实”和“本地 pending mutation”。

### Flutter 服务端优先边界

新增：

- `client_flutter/lib/core/server_first/mutation_coordinator.dart`
- `client_flutter/lib/core/server_first/server_first_repository.dart`

职责：

- 普通任务/日程读写优先调用 `/api/client/*`。
- 服务端不可用或写入失败时，写入 `offline_mutations`，并保留 pending 状态。
- 恢复网络后由已有 `ServerSyncEngine.pushPending()` 推送。
- 页面后续应迁移到 `serverFirstRepositoryProvider`，旧本地仓库只作为缓存、迁移、离线队列或 legacy/offline-preview 使用。

### 防回退扫描

新增：

- `scripts/check-client-server-boundary.ps1`

用途：

- 扫描 UI 和 feature provider 中直接依赖本地事实仓库的代码。
- 默认报告未登记违规和已登记过渡项。
- 加 `-FailOnViolation` 会阻断未登记违规；已登记过渡项仍会完整显示，不能被当作“已经迁移完成”。

### 260429 第二轮补充

- 服务端补齐 `DELETE /api/client/tasks/:id`、`DELETE /api/client/events/:id`、`POST /api/client/tasks/:id/complete`。
- 服务端删除任务/日程使用软删除 `deleted_at`，并写入 `sync_changes(action=delete)` 与 `audit_logs`。
- Flutter API 层补齐 `deleteJson`、任务完成、任务删除、日程删除。
- 新增 `TaskEventServerFirstStore`、`CloudDriveServerFirstStore`、`SchedulerServerFirstStore`、`ActivityUnderstandingServerFirstStore`。
- 扫描脚本新增明确 waiver 分类：`task_event_ui_cache_transition`、`cloud_drive_ui_cache_transition`、`legacy_offline_preview_model`、`external_integration_device_cache` 等。
- 当前扫描结果：0 个未登记违规，62 个已登记过渡项。它们必须继续可见，后续逐步迁移到 server-first stores。

### 260429 第三轮补充

- 快速创建任务/日程已改为调用 `TaskEventServerFirstStore.createTask/createEvent`。
- 任务详情保存、删除已改为调用 `TaskEventServerFirstStore.createTask/updateLocalTask/deleteLocalTask`。
- 日程详情保存、删除已改为调用 `TaskEventServerFirstStore.createEvent/updateLocalEvent/deleteLocalEvent`。
- 时间轴拖拽任务/日程、调整任务/日程时长已改为调用 `updateLocalTask/updateLocalEvent`。
- 未排任务面板退回收集箱已改为调用 `updateLocalTask({'dtstart': null})`。
- `TaskEventServerFirstStore` 已补齐本地 int id 到服务端 `serverId` 的映射；没有 serverId 的对象会进入 `offline_mutations`。
- 服务端任务/日程 payload 规范化已补齐 `description/dtstart/durationMinutes/priorityLocal/isBlock/eventCalendarId` 等字段，并允许显式 `null` 用于清空字段。
- 当前扫描结果：0 个未登记违规，50 个已登记过渡项。`task_event_ui_cache_transition` 已从 17 项降到 5 项，剩余主要是详情页读取 cache 和周/月视图 cache watch。

## 仍然没有彻底完成的部分

这些不能虚假宣称完成：

- 任务、日程的所有 Flutter 页面还没有全部迁移到 `serverFirstRepositoryProvider`。
- 当前 62 个扫描点已被登记为 cache/legacy transition，不等于功能迁移完成。
- `tracker_providers.dart` 中仍有大量本地统计与本地追踪仓库路径，需要继续迁移到服务端 analytics/activity-understanding。
- 排程 UI 仍需逐页确认是否只调用服务端 scheduler run，而不是本地 `scheduler_engine.dart`。
- 报告生成页面仍需迁移到服务端 reports/diary API，旧 `report_generation_service.dart` 应降级为 legacy。
- 文件中心仍需继续确保所有逻辑文件树来自服务端 `file_nodes`，本地路径只作为设备副本。
- 管理端写入、AI 执行器、排程确认、报告推送等路径需要继续检查是否全部产生 `sync_changes` 和 `audit_logs`。

## 下一步最小整改顺序

1. 将任务首页、任务详情、新建/编辑任务页面改为使用 `serverFirstRepositoryProvider`。
2. 将日程时间轴、周视图、月视图、日程详情、新建/编辑日程改为使用 `serverFirstRepositoryProvider`。
3. 本地 Drift 任务/日程表只接收服务端 pull 的 canonical 数据，以及本机 pending overlay。
4. 将追踪主页热力图、历史统计、区间分析改为使用服务端 analytics。
5. 将活动理解确认入口改为只调用服务端 activity-understanding。
6. 将排程页默认调用服务端 scheduler run/accept/reject。
7. 将报告和日记生成、确认、推送全部迁到服务端 reports/diary。
8. 将文件中心进一步固定为服务端 `file_nodes` 树。
9. 将 `scripts/check-client-server-boundary.ps1 -FailOnViolation` 纳入发版前检查。

## 验证方式

服务端：

```powershell
cd C:\Users\a2746\Desktop\calll260426\server
npm run build
```

边界扫描：

```powershell
cd C:\Users\a2746\Desktop\calll260426
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\check-client-server-boundary.ps1
```

Flutter 由用户手动执行：

```powershell
cd C:\Users\a2746\Desktop\calll260426\client_flutter
flutter analyze
flutter build windows --debug
flutter build web
flutter build apk --debug
```

真实验收：

- Windows 创建任务，服务端返回 canonical，Web 端刷新可见。
- 停止服务端后创建任务，客户端显示 pending；恢复服务端后自动 push 并变 synced。
- Windows 修改日程后，Web 时间轴、周视图、月视图看到同一条服务端数据。
- 管理端能看到对应 `sync_changes` 和 `audit_logs`。

### 260429 第六轮补充：追踪数据服务端汇总收口

- 修正 `ActivityUnderstandingApi`：客户端查询活动片段时改用服务端实际读取的 `start/end` 参数；按天整理片段时只提交 `yyyy-MM-dd`，避免服务端拼接日期得到非法时间。
- 新增 `TrackingServerFirstStore`，统一封装服务端 `analytics`、`tracking ingest summary`、`activity-understanding`。追踪展示入口不再直接面向本地追踪仓库。
- 追踪主页热力图、今日活动记录、输入行为摘要、区间分析记录改为读取服务端 `/api/analytics/*` 返回的汇总数据。
- 活动理解复核页改为读取服务端 `/api/activity-understanding/segments`，整理按钮调用服务端 build，确认/拒绝调用服务端 confirm/reject；确认后由服务端写入 `actual_activity_logs`、`task_work_logs`、`audit_logs` 和模型反馈。
- 本地 `activity_records`、`raw_activity_logs`、`tracked_input_events` 继续作为原生采集缓冲和诊断来源，但不再作为追踪主页、活动理解、报告、排程的主事实来源。
- 服务端 `/api/tracking/summary` 增加最近错误、各类 canonical 追踪事实的最新接收时间，便于管理端/客户端判断上传是否真正进入服务端。
- 边界扫描新增追踪 presentation 严格规则：追踪页面不得直接读取 `activityRecordRepositoryProvider`、`trackerRepositoryProvider`、`activityFusionServiceProvider`、`activityFusionRepositoryProvider`、`inputActivityEventServiceProvider`。
- 当前扫描结果：0 个未登记违规；追踪 presentation 已无直接本地追踪事实仓库依赖。`shared/providers/tracker_providers.dart` 仍保留 local spool/legacy fusion provider 的登记 waiver，因为采集缓冲和离线预览尚未删除。

### 260429 第四轮补充

- 全部数据管理页的批量删除任务/日程、批量完成任务已改为调用 `TaskEventServerFirstStore.deleteLocalTask/deleteLocalEvent/completeLocalTask`。
- `calendar_shell.dart` 清理了快速创建迁移后不再需要的 Drift import。
- 当前扫描结果：0 个未登记违规，47 个已登记过渡项。
- 剩余 `task_event_ui_cache_transition` 只包括详情页读取 cache，以及周/月视图 cache watch；这些是本轮明确保留的读取过渡项，不再包含任务/日程 UI 写入入口。

### 260429 第五轮复核

- `scripts/check-client-server-boundary.ps1` 增加了任务/日程 UI 写操作的严格扫描。
- 现在即使某个页面仍处于 `task_event_ui_cache_transition` 读取过渡期，只要出现直接调用本地 `taskRepositoryProvider/eventRepositoryProvider` 的 `create/update/delete/markCompleted/clearDtstart/updateDtstart/updateDuration`，或直接构造 `TaskItemsCompanion.insert/CalendarEventsCompanion.insert`，扫描都会作为违规失败。
- 严格扫描结果：0 个直接任务/日程 UI 写入违规。
- 当前结论：任务/日程的用户写入口已经迁到 `TaskEventServerFirstStore`；本地任务/日程仓库只剩 cache watch、详情页加载已有对象、导入导出/Outlook 设备缓存、legacy/offline-preview 等已登记过渡用途。
