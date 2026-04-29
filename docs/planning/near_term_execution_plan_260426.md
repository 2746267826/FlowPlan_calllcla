# FlowPlan 近期执行清单（2026-04-26）

## 1. 当前状态

- [x] P0 已完成。下一步应进入 P1，并允许 P2/P3 中部分低风险任务并行推进。

- [x] 禁止 Codex 运行 `flutter` 或 `dart` 指令；需要验证时由用户手动执行。

## 2. 第一组：P1 同步底座

目标：让核心数据具备“本地可用 + 服务端完整存储 + 同步状态可见 + 冲突不静默覆盖”的最小闭环。

任务：

1. 服务端仓库/目录初始化  
   基于当前 `server/` 骨架，补齐真实 NestJS 工程依赖、启动配置、环境变量、数据库连接。

2. PostgreSQL 数据模型  
   建立用户、设备、同步游标、变更日志、日历本、任务本、日程、任务、排程片段、审计日志的服务端表。

3. 客户端同步元数据迁移  
   基于已新增的 `sync_object_states`、`offline_mutations`、`sync_conflicts`，接入日程/任务/日历本/任务本 Repository。

4. 最小 API  
   实现 `/auth/login`、`/devices/register`、`/sync/push`、`/sync/pull`、`/sync/ack`、`/sync/conflicts`。

5. 离线写入状态  
   客户端本地创建或修改日程/任务时写入离线队列，并在 UI 显示未同步、等待同步、同步失败、冲突。

6. 冲突候选  
   同一字段多端修改时生成冲突候选，不静默覆盖。

7. 审计同步  
   操作审计采用追加模式同步，不进行字段合并。

验收：

- 断网时可创建/修改日程和任务。
- 本地数据能明确显示同步状态。
- 恢复网络后可上传服务端。
- 另一个设备可拉取服务端变更。
- 冲突可见、可解释、可人工处理。

## 3. 第二组：P2 追踪查询性能

目标：解决当前“追踪”筛选和查询加载慢的问题。

任务：

1. 补复合索引  
   面向 `activity_records`、`raw_activity_logs`、`tracked_input_events` 的常见筛选路径补索引。

2. 查询下推  
   搜索、应用筛选、分类筛选、任务筛选、时间范围筛选必须下推到 SQL/Repository 层。

3. 分页  
   历史日志、输入事件、原始活动记录默认分页，不再一次性拉全量。

4. 聚合表  
   设计并逐步接入 `activity_hourly_stats`、`activity_daily_stats`、`input_hourly_stats`、`input_daily_stats`。

5. 服务端统计 API 形态  
   先设计接口，再在 P1 服务端可运行后接入。

验收：

- 热力图不再每次扫描全部原始数据。
- 最近 7 天、30 天统计加载可接受。
- 多条件筛选不长时间空白。
- 客户端默认只拿聚合结果。

## 4. 第三组：P3 客户端模块化

状态：代码部分已完成。

目标：避免巨型页面继续膨胀，让后续 P4-P12 能顺利落地。

优先拆分：

- [x] `tracker_page.dart`
- [x] `outlook_settings_page.dart`
- [x] `ical_import_export_page.dart`
- [x] `calendar_books_page.dart`
- [x] `settings_page.dart`
- [x] `app_providers.dart`

任务：

1. [x] 页面拆分为 page / section / widget。
2. [x] 共享空状态、错误状态、筛选工具条、同步状态标签、危险操作确认弹窗。
3. [x] Repository 与 UI 解耦。
4. [x] 追踪页主屏只保留摘要和入口，明细进入二级页。
5. [x] 新增同步状态 UI 组件，为 P1 提供入口。

验收：

- [x] 主页面首屏更轻。
- [x] 复杂页面支持懒加载。
- [x] 新功能能放入独立 section/widget。

## 5. 不要在近期做

- 全量迁移 Electron/Tauri/React Native。
- 用 Flutter Web 做复杂管理后台。
- 直接训练大模型。
- 一开始深度控制 QQ/微信。
- 一开始做 STM32 硬件。
- 一开始做完整 OneDrive 双向同步。
- 让 AI 或自动排程静默写库。
