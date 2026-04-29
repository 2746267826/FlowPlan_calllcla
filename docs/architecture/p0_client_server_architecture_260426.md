# FlowPlan P0 架构定调：客户端/服务端分离底座（2026-04-26）

## 1. P0 结论

FlowPlan 后续不再按“本地 Flutter 单体应用 + 少量云端功能”的方式扩展，而应重构为：

```text
Flutter 客户端
  本地缓存、离线交互、Windows/Android 原生采集、文件打开、人工确认

FlowPlan 服务端
  完整事实库、跨端同步、统计聚合、文件存储、AI 任务、Web 管理面板
```

服务端是完整数据底座，不只是备份；客户端是本地可用副本，不只是远程 UI。

### 1.1 技术路线定论

结合当前产品要求，P0 明确采用以下路线：

```text
保留 Flutter 作为 Windows / Android 主客户端
  -> 继续承载离线交互、原生采集、本地文件操作、人工确认 UI

新建独立 FlowPlan Server
  -> 承载完整事实库、同步、统计聚合、文件存储、报告、AI 后台任务

新建独立 Web 管理面板
  -> 承载服务端管理、数据查看、同步状态、审计、统计图和远程配置
```

不建议在当前阶段全量迁移到 Electron、Tauri、React Native 或 Flutter Web。原因不是这些技术不可用，而是当前系统已经有大量 Flutter/Riverpod/Drift 业务、Windows 原生插件和 Android Usage Stats 桥接；全量迁移会把 P0-P2 的核心问题从“同步、性能、服务端事实库”转移成“重写客户端”。

正确的重构方向是：把 Flutter 从“本地单体大脑”改造成“跨平台客户端外壳 + 本地缓存 + 原生能力入口 + 人工确认界面”，把重计算、跨端事实、长期存储和 AI 后台任务从客户端拆到服务端。

## 2. 架构原则

### 2.1 服务端完整存储

所有信息最终都应进入服务端：

- 日程、任务、任务本、日历本。
- 排程片段、实际记录、操作审计。
- 活动片段、追踪摘要、活动理解结果。
- 原始追踪日志、键鼠输入事件、位置采样等高频数据。
- 文件元数据、文件夹绑定、最近文件夹。
- AI 对话、操作预案、日报、日记、推送记录。

高频数据可以延迟、压缩、分批、后台同步，但架构上不应假设“只存在本机”。

### 2.2 客户端本地缓存

客户端继续保存本机数据，承担：

- 离线查看。
- 离线创建和修改。
- 原生平台采集。
- 本地文件打开与预览。
- 同步失败时的临时事实缓存。

所有本地变更都必须带同步状态。

### 2.3 服务端统计聚合

热力图、趋势图、输入统计、区间分析、日报统计等不能依赖客户端下载海量原始数据后本地计算。

正确方式：

```text
客户端请求统计条件
  -> 服务端查表、聚合、分页
  -> 返回 summary / buckets / topN / 少量代表性明细
```

只有用户展开明细时，客户端才分页拉取原始记录。

### 2.4 自动写操作确认

AI、自动排程、冲突处理、文件移动、批量清理、日报候选确认等，都必须：

```text
生成操作预案
  -> 展示给用户
  -> 用户确认
  -> 执行写入
  -> 写审计日志
```

### 2.5 隐私边界

原始键盘、聊天内容、位置轨迹等即使同步到自有服务端，也不能直接发送给第三方 LLM API。外部 AI 只能接收脱敏后的结构化摘要。

若未来同步原始敏感数据到服务端，需要 P1/P2 继续补充：

- 字段级加密。
- 服务端访问审计。
- 同步范围开关。
- 数据导出与删除。
- LLM 导出前隐私过滤。

## 3. 技术栈选择

### 3.1 推荐服务端技术栈

推荐方案：

```text
语言/框架：TypeScript + NestJS
数据库：PostgreSQL
缓存/队列：Redis
对象存储：S3 兼容接口，开发期可用本地 MinIO
搜索：PostgreSQL FTS 起步，后续可接 Meilisearch / OpenSearch
Web 管理面板：同仓库 Next.js 或独立 Vite React
API：REST 起步，未来关键订阅可加 WebSocket/SSE
```

选择理由：

- TypeScript 适合同时维护 API 类型、Web 管理面板和服务端业务模型。
- PostgreSQL 适合强一致业务数据、JSONB、全文检索、统计聚合。
- Redis 适合后台任务、推送、同步任务队列和频率控制。
- S3 兼容存储方便以后接服务器存储、对象版本和 OneDrive 同步。

备选方案：

```text
Dart Frog / Serverpod
  优点：Dart 技术栈一致。
  风险：生态、后台任务、管理面板、复杂服务端能力不如 Node/Postgres 组合成熟。

Python FastAPI
  优点：AI 与数据处理生态好。
  风险：与前端/Web 管理面板类型协作稍弱。
```

P0 决策：推荐先以 `TypeScript + NestJS + PostgreSQL` 作为服务端规划目标。P1 真正开工前可以再次确认，但后续文档先按此方案设计。

### 3.2 客户端技术栈保持

Flutter 客户端继续保留：

- Flutter + Riverpod。
- Drift/SQLite 作为本地缓存与离线数据库。
- Windows C++ 原生插件。
- Android Usage Stats 与权限桥接。

Flutter 客户端的定位需要从“承担全部业务闭环”调整为：

- 本地缓存：保存离线可用副本、同步状态、离线变更队列和近期统计缓存。
- 原生采集：Windows 前台窗口、键鼠输入、资源管理器打开；Android Usage Stats、定位权限、通知入口。
- 本地交互：日程、任务、追踪、文件、AI 回执、冲突候选的高频操作界面。
- 人工确认：所有自动排程、自动实际记录、AI 工具调用、文件移动、冲突合并都先在客户端展示预案。
- 轻量展示：热力图、趋势图、日报等优先展示服务端聚合结果，不默认下载海量原始记录。

新增客户端模块：

```text
client_flutter/lib/core/server_api/
client_flutter/lib/core/sync/
client_flutter/lib/core/offline_queue/
client_flutter/lib/core/sync_status/
```

### 3.3 Web 管理面板技术路线

Web 管理面板不建议优先使用 Flutter Web 承担。它更适合使用 `Next.js` 或 `Vite + React` 独立实现，原因是：

- 管理后台需要表格、筛选、审计、图表、权限、批量操作和调试入口，Web 生态更成熟。
- TypeScript 可与服务端共享 DTO、API 类型和管理后台模型。
- Web 管理面板未来可能部署在服务器上，供不同设备直接访问，不需要依赖 Flutter 客户端发布节奏。

Flutter Web 可以作为未来补充入口或轻量展示入口，但不作为复杂管理后台的 P0/P1 主路线。

### 3.4 桌面原生能力补强策略

Windows 文件管理、右键菜单、资源管理器联动、OneDrive 本地占位文件识别、前台窗口采集等能力，不需要为了这些点把整个客户端迁移到 Electron/Tauri。

推荐做法：

- 已有 Flutter Windows 客户端继续保留。
- 需要原生能力时优先扩展 Windows C++ 插件。
- 若某些能力长期难以通过 Flutter 插件稳定实现，再考虑增加小型 Rust/C++ sidecar。
- sidecar 只负责原生能力，不拥有业务事实库。
- sidecar 与 Flutter 客户端或服务端通过受控本地 API/IPC 交互，并写入审计。

Tauri 可作为长期备选：如果未来 Windows 文件系统、右键菜单、WebView 生态、系统托盘和后台常驻成为绝对主线，且 Android 端不再要求同一客户端框架，再评估 Windows 客户端迁移。但它不是 P0-P3 的目标。

### 3.5 技术选择矩阵

| 范围 | P0 决策 | 主要原因 | 暂不选择 |
| --- | --- | --- | --- |
| Windows/Android 主客户端 | Flutter + Riverpod + Drift | 已有代码资产大；跨端一致；本地离线和原生桥接已有基础 | Electron、Tauri、React Native 全量迁移 |
| 服务端 | TypeScript + NestJS + PostgreSQL | API、后台任务、权限、统计、Web 管理协作成熟 | 继续把复杂逻辑堆在 Flutter 本地 |
| Web 管理面板 | Next.js 或 Vite React | 管理后台生态成熟；便于和服务端共享类型 | Flutter Web 作为复杂管理后台主路线 |
| 本地数据库 | Drift/SQLite | 离线可用、现有迁移基础、适合本机缓存 | 只保留远程数据、不做本地副本 |
| 大数据统计 | 服务端 PostgreSQL 聚合 | 避免客户端下载海量追踪数据 | 客户端全量拉取后计算 |
| Windows 原生集成 | Flutter 插件 + 可选 sidecar | 控制迁移成本，保留现有客户端 | 为文件能力整体换壳 |

## 4. 服务端模块划分

```text
server/
├── auth                 用户、登录、令牌、会话
├── devices              设备注册、设备状态、设备密钥
├── sync                 增量同步、变更游标、离线队列确认
├── canonical_store      服务端完整事实库访问层
├── calendar             日程、日历本
├── task                 任务、任务本、任务状态
├── scheduler            排程片段、排程预案
├── actuals              实际记录
├── tracker              活动记录、活动片段、输入事件、工作会话
├── analytics            热力图、趋势、日报统计、聚合查询
├── files                文件元数据、文件绑定、最近文件夹
├── storage              对象存储、上传下载、版本
├── ai                   AI 对话、工具调用、操作预案
├── reports              日报、周报、自动日记、推送内容
├── notifications        Telegram、邮件、Webhook、系统推送
├── audit                操作审计、访问审计
├── conflict             冲突候选、字段差异、处理记录
├── rendezvous           设备发现、P2P 信令、多路径传输候选
└── admin_panel          Web 管理面板后端接口
```

## 5. 客户端模块划分

```text
client_flutter/lib/core/server_api/
  api_client.dart
  api_error.dart
  auth_token_store.dart
  request_context.dart

client_flutter/lib/core/sync/
  sync_engine.dart
  sync_object_registry.dart
  sync_cursor_store.dart
  sync_status.dart
  conflict_snapshot.dart

client_flutter/lib/core/offline_queue/
  offline_mutation.dart
  offline_mutation_store.dart
  offline_mutation_runner.dart

client_flutter/lib/core/sync_status/
  sync_badge.dart
  sync_state_mapper.dart

client_flutter/lib/features/*/sync/
  每个业务模块各自提供同步序列化、反序列化、冲突字段映射
```

客户端不直接把所有服务端字段散落到 UI 层，而应通过 Repository 或 Sync Adapter 接入。

## 6. API 分层草案

### 6.1 认证与设备

```text
POST /auth/login
POST /auth/refresh
POST /auth/logout

POST /devices/register
GET  /devices
PATCH /devices/{deviceId}
POST /devices/{deviceId}/heartbeat
```

### 6.2 同步 API

```text
POST /sync/push
  客户端上传本地变更批次

GET /sync/pull?cursor=...
  客户端按游标拉取服务端变更

POST /sync/ack
  客户端确认某批服务端变更已落地

GET /sync/status
  查看账号、设备、对象类型的同步健康状态

GET /sync/conflicts
  拉取冲突候选

POST /sync/conflicts/{id}/resolve
  用户确认冲突处理方案
```

### 6.3 业务数据 API

业务 API 用于 Web 管理面板、调试、明确的单对象操作；移动/桌面跨端一致性主要走同步 API。

```text
/calendar-books
/task-lists
/calendar-events
/tasks
/schedule-segments
/actual-activities
/activity-segments
/activity-interpretations
/task-work-logs
/files
/file-bindings
/operation-drafts
/reports
```

### 6.4 统计 API

```text
GET /analytics/activity-heatmap
GET /analytics/input-heatmap
GET /analytics/activity-range-summary
GET /analytics/top-apps
GET /analytics/top-categories
GET /analytics/task-work-summary
GET /analytics/focus-trends
GET /analytics/report-inputs/daily
GET /analytics/report-inputs/weekly
```

统计 API 返回聚合结果，不默认返回原始事件。

### 6.5 文件 API

```text
GET  /files/tree
GET  /files/recent-folders
POST /files/bindings
GET  /files/{id}/preview
POST /files/{id}/download-url
POST /files/upload-session
PATCH /files/{id}/metadata
GET  /files/conflicts
```

### 6.6 AI 与操作预案 API

```text
POST /ai/conversations
POST /ai/messages
POST /ai/tool-drafts
GET  /operation-drafts
POST /operation-drafts/{id}/confirm
POST /operation-drafts/{id}/reject
```

AI 不直接写业务表。写入通过 `operation-drafts` 确认后执行。

### 6.7 报告与推送 API

```text
GET  /reports/daily
GET  /reports/weekly
POST /reports/generate
PATCH /reports/{id}
POST /reports/{id}/deliver

POST /notification-channels/telegram/bind
PATCH /notification-channels/{id}
GET  /notification-deliveries
```

### 6.8 审计 API

```text
GET /audit/operation-logs
GET /audit/access-logs
GET /audit/entity/{type}/{id}
```

## 7. 同步对象清单

### 7.1 P1 第一批同步对象

| 对象 | 客户端表/来源 | 服务端职责 | 冲突策略 |
| --- | --- | --- | --- |
| 用户 | 新增 | 账号事实 | 服务端为准 |
| 设备 | device identity | 注册、心跳、密钥 | 服务端为准 |
| 日历本 | event_calendars | 完整事实 | 字段级冲突 |
| 任务本 | task_lists | 完整事实 | 字段级冲突 |
| 日程 | calendar_events | 完整事实 | 字段级冲突 |
| 任务 | task_items | 完整事实 | 字段级冲突 |
| 排程片段 | task_schedule_segments | 完整事实 | 后写入变冲突候选 |
| 实际记录 | 待新增 | 完整事实 | 字段级冲突 |
| 操作审计 | data_operation_logs | 追加事实 | 不合并，只追加 |
| 跨端设置 | app_settings 子集 | 完整事实 | 服务端或用户选择 |

### 7.2 P2/P5 第二批同步对象

| 对象 | 用途 | 同步策略 |
| --- | --- | --- |
| activity_segments | 活动片段 | 可重算，但同步确认结果 |
| activity_interpretations | 活动理解 | 同步结构化结果 |
| task_work_logs | 任务实际投入 | 完整同步 |
| work_session_cache | 展示缓存 | 可不全量同步，服务端可重算 |
| analytics aggregates | 统计缓存 | 服务端主导 |

### 7.3 高频数据同步对象

| 对象 | 特点 | 策略 |
| --- | --- | --- |
| raw_activity_logs | 高频但较小 | 后台分批上传 |
| tracked_input_events | 高频且敏感 | 压缩、分批、可配置 |
| activity_records | 中频核心证据 | 优先同步 |
| location_samples | 敏感 | 默认关闭或摘要优先 |

## 8. 本地/服务端字段映射策略

### 8.1 通用字段

每个需要同步的对象都应具备：

```text
local_id
server_id
uid
owner_user_id
origin_device_id
created_at
updated_at
deleted_at
local_version
server_version
sync_state
last_synced_at
last_sync_error
```

本地现有自增 `id` 不适合作为跨端主键。跨端应以 `uid` 或 `server_id` 作为稳定身份。

### 8.2 删除策略

不建议直接硬删除同步对象。应采用：

```text
deleted_at != null
```

客户端可本地隐藏，服务端保留一段时间用于同步删除和回滚。

### 8.3 版本策略

初期可使用：

```text
server_version: integer
updated_at: ISO timestamp
origin_device_id
```

字段级冲突需要保存：

```text
base_snapshot
local_snapshot
remote_snapshot
changed_fields
```

## 9. 客户端/服务端职责边界表

| 功能 | 客户端 | 服务端 | 两边都要 |
| --- | --- | --- | --- |
| Windows 前台窗口采集 | 是 | 否 | 否 |
| Windows 键鼠采集 | 是 | 否 | 否 |
| Android Usage Stats 导入 | 是 | 否 | 否 |
| 原始追踪长期保存 | 本地缓存 | 完整存储 | 是 |
| 日程/任务 CRUD | 离线可用 | 完整事实 | 是 |
| 自动排程预案 | 可本地生成 | 可服务端生成 | 是 |
| 排程写入确认 | 是 | 执行同步与审计 | 是 |
| 热力图统计 | 可做本日缓存 | 主统计聚合 | 是 |
| 长期趋势统计 | 少量缓存 | 是 | 是 |
| 文件原生打开 | 是 | 否 | 否 |
| 文件对象存储 | 本地缓存 | 是 | 是 |
| OneDrive 同步 | 令牌/入口 | 后台协调 | 是 |
| AI 聊天 | 展示与确认 | 推理与工具编排 | 是 |
| 日报生成 | 展示与编辑 | 定时生成与推送 | 是 |
| Telegram 推送 | 配置入口 | Bot 推送 | 是 |
| 审计日志 | 本地追加/缓存 | 完整存储 | 是 |
| Web 管理面板 | 否 | 是 | 否 |
| 冲突处理 | 展示和确认 | 生成候选和落库 | 是 |

## 10. Web 管理面板边界

P0 确认：服务端应提供完整管理面板，可以是 Web 端。

Web 管理面板至少覆盖：

- 日程、任务、实际记录管理。
- 同步状态、设备状态、冲突候选。
- 追踪统计、热力图、输入统计。
- 文件元数据、文件绑定、最近文件夹。
- 操作审计、访问审计。
- 日报/周报/日记。
- Telegram 推送配置。
- AI 操作预案查看与确认。

Web 端不直接承担 Windows/Android 原生采集。

## 11. P0 到 P1 的交接任务

P1 开始前必须完成以下设计确认：

1. 最终确认服务端技术栈。
2. 最终确认 Web 管理面板技术栈：Next.js 或 Vite React。
3. 建立服务端仓库或当前仓库内的 `server/` 目录。
4. 建立 Web 管理面板目录或仓库边界。
5. 定义第一批同步对象的数据 DTO。
6. 为客户端现有表设计 `uid/server_id/sync_state` 迁移方案。
7. 设计离线变更队列表。
8. 设计 `/sync/push` 与 `/sync/pull` 的最小协议。
9. 设计冲突候选结构。
10. 确定 Web 管理面板首版范围。
11. 确定 Windows 原生插件/sidecar 的边界，避免业务逻辑散落到原生层。

详细交接契约见：

- `docs/architecture/p0_completion_report_260426.md`
- `docs/architecture/p0_p1_handoff_contract_260426.md`

## 12. P0 完成判据

P0 视为完成，当且仅当以下问题都有明确答案：

- [x] 服务端是否是完整事实库？是。
- [x] 客户端是否保留本地缓存和离线写入？是。
- [x] 是否继续使用 Flutter 作为 Windows/Android 主客户端？是。
- [x] 是否把 Web 管理面板从 Flutter 客户端中独立出来？是。
- [x] 是否暂缓 Electron/Tauri/React Native 全量迁移？是。
- [x] 高频统计是否由服务端聚合？是。
- [x] 服务端技术栈是否有推荐方案？是，TypeScript + NestJS + PostgreSQL。
- [x] API 是否分层？是，认证/同步/业务/统计/文件/AI/报告/审计。
- [x] 同步对象是否有分批清单？是。
- [x] 客户端/服务端职责是否能判断？是，见边界表。
- [x] 下一阶段 P1 能否直接据此设计同步模型？是。
- [x] P0 代码底座是否已经落地？是，见 `client_flutter/lib/core/server_api/`、`client_flutter/lib/core/sync/`、`client_flutter/lib/core/offline_queue/`、`server/`、`web_admin/`。

## 13. P0 交付物清单

| 交付物 | 文件 | 状态 |
| --- | --- | --- |
| P0 主架构文档 | `docs/architecture/p0_client_server_architecture_260426.md` | [x] 完成 |
| P0 完成报告 | `docs/architecture/p0_completion_report_260426.md` | [x] 完成 |
| P1 交接契约 | `docs/architecture/p0_p1_handoff_contract_260426.md` | [x] 完成 |
| 开发约束 | `docs/development_constraints_260426.md` | [x] 完成 |
| 客户端 API 骨架 | `client_flutter/lib/core/server_api/` | [x] 完成 |
| 客户端同步骨架 | `client_flutter/lib/core/sync/` | [x] 完成 |
| 客户端离线队列骨架 | `client_flutter/lib/core/offline_queue/` | [x] 完成 |
| 服务端骨架 | `server/` | [x] 完成 |
| Web 管理面板骨架 | `web_admin/` | [x] 完成 |
| docs 权威计划体系 | `docs/planning/` | [x] 完成 |
| P0-P12 总计划 | `docs/archive/legacy-root-plans/priority_development_plan_260426.md` | [x] 已归档并更新 |
| 完整长期计划 | `docs/archive/legacy-root-plans/complete_development_plan_260426.md` | [x] 已归档并更新 |
| 未来开发计划 | `docs/archive/legacy-root-plans/future_development_plan_260426.md` | [x] 已归档并更新 |
