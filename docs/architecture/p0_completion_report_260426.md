# FlowPlan P0 完成报告：架构定调与客户端/服务端分离底座（2026-04-26）

## 1. P0 状态

P0 已完成。

P0 的目标不是实现服务端代码，也不是迁移客户端，而是把后续开发必须依赖的架构方向、技术路线、职责边界、同步对象、API 分层和 P1 交接条件完整定下来。

当前 P0 的结论是：

```text
Flutter Windows/Android 客户端
  本地缓存、离线交互、原生采集、文件打开、人工确认

FlowPlan Server
  完整事实库、跨端同步、统计聚合、文件存储、报告、AI 后台任务、审计

Web 管理面板
  服务端管理、同步状态、冲突处理、审计、统计图、远程配置
```

## 2. P0 明确完成的决策

### 2.1 服务端地位

服务端是完整事实库，不是简单备份。

所有核心数据最终都应进入服务端：

- 日程、日历本。
- 任务、任务本。
- 排程片段。
- 实际记录。
- 操作审计。
- 活动片段、追踪摘要、活动理解结果。
- 文件元数据、文件夹绑定、最近文件夹。
- AI 对话、操作预案、日报、日记、推送记录。

高频原始数据可以分批、压缩、延迟上传，但架构上不再假设“只存在本机”。

### 2.2 客户端地位

客户端继续保留本地数据库和离线写入能力。

Flutter 客户端的长期职责是：

- 日常使用入口。
- 本地缓存和离线变更队列。
- Windows 前台窗口、键鼠输入、资源管理器打开等原生能力。
- Android Usage Stats、定位权限、通知等移动端能力。
- 自动操作、AI 工具调用、冲突处理、文件移动等人工确认 UI。
- 最近数据和轻量统计缓存。

客户端不是远程网页壳，也不应继续承担全部长期事实、跨端同步、重统计和后台 AI 任务。

### 2.3 技术路线

P0 确认：

- Windows/Android 主客户端继续使用 Flutter + Riverpod + Drift/SQLite。
- 服务端推荐 TypeScript + NestJS + PostgreSQL。
- Redis 用于后台任务、同步队列、通知、频率控制。
- S3 兼容对象存储用于服务端文件存储，开发期可用 MinIO。
- Web 管理面板优先使用 Next.js 或 Vite React。
- Flutter Web 只作为未来轻量入口，不作为复杂管理后台主路线。
- Electron、Tauri、React Native 不作为当前全量迁移目标。

### 2.4 原生能力策略

Windows 文件管理、右键菜单、资源管理器联动、OneDrive 本地占位文件检测等能力，不通过整体替换 Flutter 客户端解决。

推荐顺序：

1. 优先扩展 Flutter Windows 插件。
2. 插件难以稳定承载时，增加小型 Rust/C++ sidecar。
3. sidecar 只负责原生能力，不拥有业务事实库。
4. sidecar 产生的关键动作必须回写审计。
5. 远期如 Windows 原生能力成为绝对主线，再评估 Tauri/WinUI。

### 2.5 统计策略

热力图、趋势图、输入统计、区间分析、日报统计等大量数据统计由服务端聚合。

客户端默认请求：

```text
time_range + filters
  -> 服务端聚合
  -> summary / buckets / topN / 少量代表性明细
```

用户展开明细时，客户端再分页拉取原始记录。

## 3. 当前代码基础盘点

当前仓库是 Flutter 本地应用，已有以下基础：

| 能力 | 当前基础 | P0 判断 |
| --- | --- | --- |
| 本地数据库 | Drift/SQLite，`AppDatabase.schemaVersion = 10` | 保留，升级为本地缓存和离线事实副本 |
| 日程 | `calendar_events`，包含 `uid/location/isBlock/eventCalendarId` | P1 第一批同步对象 |
| 日历本 | `event_calendars` | P1 第一批同步对象 |
| 任务 | `task_items`，包含 `uid/duration/isLocked/taskListId` | P1 第一批同步对象 |
| 任务本 | `task_lists` | P1 第一批同步对象 |
| 排程片段 | `task_schedule_segments` 通过 custom table 创建 | P1 第一批同步对象 |
| 追踪记录 | `activity_records` | P2/P5 同步和统计对象 |
| 原始窗口日志 | `raw_activity_logs` | 高频后台同步对象 |
| 键鼠输入事件 | `tracked_input_events` | 高频、敏感、可配置同步对象 |
| 操作审计 | `data_operation_logs` | P1 第一批追加型同步对象 |
| 设置 | `app_settings` | 按范围拆分为本地设置和跨端设置 |

## 4. P0 已形成的交付物

| 交付物 | 文件 | 状态 |
| --- | --- | --- |
| P0 主架构文档 | `docs/architecture/p0_client_server_architecture_260426.md` | [x] 完成 |
| P0 完成报告 | `docs/architecture/p0_completion_report_260426.md` | [x] 完成 |
| P1 交接契约 | `docs/architecture/p0_p1_handoff_contract_260426.md` | [x] 完成 |
| 开发约束 | `docs/development_constraints_260426.md` | [x] 完成 |
| Flutter 客户端 API 骨架 | `client_flutter/lib/core/server_api/` | [x] 完成 |
| Flutter 客户端同步骨架 | `client_flutter/lib/core/sync/` | [x] 完成 |
| Flutter 客户端离线队列骨架 | `client_flutter/lib/core/offline_queue/` | [x] 完成 |
| 本地同步基础表 | `sync_object_states` / `offline_mutations` / `sync_conflicts` | [x] 完成 |
| 服务端骨架 | `server/` | [x] 完成 |
| Web 管理面板骨架 | `web_admin/` | [x] 完成 |
| docs 权威计划体系 | `docs/planning/` | [x] 完成 |
| P0-P12 总计划 | `docs/archive/legacy-root-plans/priority_development_plan_260426.md` | [x] 已归档并更新 |
| 完整长期计划 | `docs/archive/legacy-root-plans/complete_development_plan_260426.md` | [x] 已归档并更新 |
| 未来开发计划 | `docs/archive/legacy-root-plans/future_development_plan_260426.md` | [x] 已归档并更新 |
| 更新日志 | `docs/update.txt` | [x] 已更新 |

## 5. P0 非目标

以下内容不属于 P0，不能被视为 P0 未完成：

- 不创建生产服务端代码。
- 不实现账号登录。
- 不实现同步 API。
- 不迁移现有 Drift 表。
- 不实现 Web 管理面板。
- 不优化追踪查询性能。
- 不实现文件管理、OneDrive、AI 聊天、日报推送。

这些属于 P1 及之后阶段。

P0 代码部分只允许创建可编译的边界和骨架，包括 API 客户端、同步状态表、离线队列、冲突候选存储、服务端接口占位和 Web 管理入口占位。

## 6. P0 完成判据核对

| 判据 | 结论 |
| --- | --- |
| 服务端是否是完整事实库 | [x] 是 |
| 客户端是否保留本地缓存和离线写入 | [x] 是 |
| 是否继续使用 Flutter 主客户端 | [x] 是 |
| 是否明确服务端推荐技术栈 | [x] 是，TypeScript + NestJS + PostgreSQL |
| 是否明确 Web 管理面板路线 | [x] 是，Next.js 或 Vite React |
| 是否暂缓全量客户端迁移 | [x] 是 |
| 是否明确 API 分层 | [x] 是 |
| 是否明确同步对象分批 | [x] 是 |
| 是否明确本地/服务端字段映射方向 | [x] 是 |
| 是否明确客户端/服务端职责边界 | [x] 是 |
| 是否明确 P1 可以从哪里开始 | [x] 是 |
| 是否已有 P0 代码底座 | [x] 是 |
| 是否已将 P0 完成项在计划中勾选 | [x] 是 |

## 7. P1 启动条件

P1 可以从以下任务开始：

1. 在仓库内建立 `server/` 或确定独立服务端仓库。
2. 最终确认 NestJS/PostgreSQL/Redis/对象存储方案。
3. 定义用户、设备、认证、同步游标、离线变更队列表。
4. 为第一批同步对象增加本地同步元数据迁移草案。
5. 实现 `/sync/push`、`/sync/pull`、`/sync/ack` 的最小协议。
6. 先同步日历本、任务本、日程、任务、排程片段、操作审计。
7. 再接实际记录、活动片段和统计 API。

## 8. P0 最终结论

P0 已经把 FlowPlan 从“继续堆 Flutter 本地单体”的方向，收口到“Flutter 客户端 + 独立服务端 + 独立 Web 管理面板”的长期架构。

下一阶段不应再讨论是否整体换框架，而应进入 P1：同步状态、本地缓存、离线队列、冲突模型和最小服务端骨架。
