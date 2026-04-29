# FlowPlan 未来开发计划（2026-04-26）

> 已整理归档：新的权威计划入口为 `docs/planning/master_priority_plan_260426.md`。本文保留为 2026-04-26 阶段性来源文件。

## 1. 总体判断

FlowPlan 现在已经不是一个简单日历应用，而是一个“日程 + 任务 + 追踪 + 同步 + 审计”的本地优先个人信息系统。未来不要继续把功能平铺堆在 Flutter 客户端里，而应逐步演进为：

```text
本地客户端
  负责采集、展示、离线可用、人工确认、原生系统集成

服务端
  负责跨端同步、文件存储、AI 任务队列、Web 端、备份与冲突协调

统一用户状态层
  汇总日程、任务、追踪、文件、位置、天气、聊天指令等上下文

AI / 算法层
  负责活动理解、任务归因、排程建议、文件推荐、自然语言交互
```

核心原则保持不变：

- 所有关键操作可查、可追溯。
- 所有自动操作必须先生成预案或回执，经人工确认后才真正写入。
- 各功能模块边界清晰，但统一进入用户上下文模型供综合判断。
- 服务端保存完整数据，本机同时保存本地缓存；网络差时允许本地继续写入，并标识“未与云端同步”。
- 大量统计信息由服务端查表聚合后返回最终结果，客户端避免为了热力图、趋势图等下载大量原始数据。
- 原始敏感数据即使同步到自有服务端，也必须与第三方 LLM API 严格隔离；外部 LLM API 只接收必要的脱敏结构化摘要。
- Windows/Android 主客户端继续使用 Flutter，不在当前阶段全量迁移到 Electron、Tauri 或 React Native。
- Web 管理面板独立建设，优先采用 Next.js 或 Vite React；Flutter Web 只作为未来轻量入口备选。

## 2. 当前项目现状

已具备的基础：

- Flutter + Riverpod + Drift/SQLite 架构已经成型。
- 日历、任务、时间轴、周视图、月视图、详情页、拖拽排程已可用。
- Outlook / iCalendar / FlowPlan 结构化归档 / 数据库备份恢复已有较完整基础。
- Windows 追踪已经能采集前台窗口、键鼠事件，并写入 SQLite 与 JSONL。
- Android 已接入 Usage Stats，但目前主要是打开应用或手动刷新时导入。
- `SchedulerEngine` 已支持多组工作时间、阻挡日程、锁定任务、可拆分任务、排程预案、人工确认和审计。
- `PlanFeedbackService` 已能根据当前计划与当前追踪活动发现偏离，并提示是否重排。

主要瓶颈：

- 追踪查询与筛选仍有较多页面层过滤和 Dart 侧聚合，数据多后必然变慢。
- `tracker_page.dart`、`outlook_settings_page.dart`、`ical_import_export_page.dart` 等文件过大，继续扩展风险很高。
- 活动理解仍偏规则型，还没有稳定的“活动片段 -> 任务状态 -> 排程输入”中间层。
- 客户端仍是单体本地应用，服务端、文件管理、Web 端、AI 聊天还没有统一底座。
- 日程和任务展示的地点信息没有充分利用现有空间。

## 3. P0：数据库与追踪查询性能优化

这是最高优先级。现在“追踪”中涉及查询筛选数据时加载较慢，根因应优先从数据库结构、查询下推、聚合缓存和分页解决。

### 3.1 目标

- 追踪页、输入历史、日志历史、区间分析、热力图筛选都应避免一次性加载大量原始数据。
- 日期、应用、分类、任务关联、输入类型、时间段筛选应尽量在 SQLite 层完成。
- 高频统计项应有按日/小时的预聚合表或缓存。

### 3.2 建议新增索引

重点覆盖：

- `activity_records(start_time, end_time)`
- `activity_records(category, start_time)`
- `activity_records(process_name, start_time)`
- `activity_records(linked_task_id, start_time)`
- `activity_records(device_id, platform, start_time)`
- `raw_activity_logs(day_key, occurred_at)`
- `raw_activity_logs(entry_type, occurred_at)`
- `raw_activity_logs(process_name, occurred_at)`
- `raw_activity_logs(category, occurred_at)`
- `tracked_input_events(day_key, occurred_at)`
- `tracked_input_events(event_kind, occurred_at)`
- `tracked_input_events(process_name, occurred_at)`
- `tracked_input_events(record_id, occurred_at)`
- `tracked_input_events(day_key, process_name, event_kind, occurred_at)`

### 3.3 建议新增聚合表

```text
activity_daily_stats
activity_hourly_stats
input_daily_stats
input_hourly_stats
work_session_cache
```

用途：

- 热力图默认读取聚合表，不再每次扫描原始记录。
- 输入分析优先读小时/日聚合，只有展开明细时再读原始事件。
- 工作会话合并结果缓存化；规则变更或原始数据变更时可按天重算。

### 3.4 查询层改造

- 为追踪记录、原始日志、输入事件分别提供分页 API。
- 页面筛选条件改为传入 Repository，由 SQL 查询承担过滤。
- 区间分析默认只读聚合和有限数量代表性明细。
- 历史页面采用游标加载，不在首屏渲染完整列表。
- 长查询增加加载状态、取消旧查询和结果缓存，避免用户连续切筛选时堆积。

## 4. P1：小而确定的体验修复

### 4.1 阻挡日程自动写入实际记录

对于设定了阻挡任务的日程，它们通常是课表、会议、考试、通勤等必须执行的事情。建议做成“自动候选实际记录”，而不是无条件静默写入。

规则：

- 日程 `isBlock = true` 且时间已结束。
- 对应时间段没有其他已确认的实际任务记录或强追踪证据。
- 日程状态不是取消。
- 生成一条“实际记录候选”：例如“14:00-15:40 上课：数据库系统”。
- 在日报或实际记录页中展示，用户可一键确认、改名、忽略。
- 用户确认后写入 `actual_activity_logs` 或等价任务/日程实际记录表，并写入审计日志。

后续可选：

- 对课表类日历本开启“低打扰自动确认”，但仍应可在日报中撤销。

### 4.2 日程与任务展示地点

现有 `calendar_events.location` 已存在，应在空间足够时展示。

建议：

- 时间轴事件块：标题下一行显示地点，空间不足时隐藏或截断。
- 周视图事件块：较高块显示地点，小块只显示标题。
- 月视图弹出详情或列表显示地点。
- 任务如果未来新增地点字段，与日程同样处理。

## 5. P2：追踪融合与活动理解模型

结合三份附件，未来不应把追踪记录先压缩成自然语言再排程，而应输出结构化活动理解结果。

推荐流水线：

```text
raw activity/input logs
  -> activity_segments
  -> activity_interpretations
  -> task_work_logs / actual_activity_logs
  -> user_context
  -> scheduler
  -> explanation / confirmation
```

### 5.1 新增核心表

```text
activity_segments
  start_at, end_at, dominant_apps, keywords_json, input_summary_json,
  interruption_count, focus_score, source_day, cache_version

activity_interpretations
  segment_id, activity_type, related_task_id, confidence,
  productive_minutes, progress_signal, evidence_json, natural_summary,
  interpreter_source

task_work_logs
  task_id, start_at, end_at, minutes, source, confidence,
  segment_id, confirmed_by_user

actual_activity_logs
  title, start_at, end_at, source_type, source_id, confidence,
  confirmed_by_user, evidence_json
```

### 5.2 AI 使用边界

- 规则与统计先做切片和候选任务召回。
- 只有低置信度、多候选接近、需要生成自然语言解释时调用 LLM。
- LLM 输入只能是脱敏后的结构化摘要。
- LLM 输出必须符合 JSON Schema。
- 原始键盘序列默认只留本地，外部 API 不接收。

## 6. P3：排程模型升级

当前排程器已经有预案确认、阻挡日程、锁定任务、多段任务，这是很好的底座。下一步重点是把排程输入模型规范化。

排程输入应包含：

- 固定日程：课表、会议、考试等硬约束。
- 已排任务：可移动或不可移动。
- 未排任务：待调度对象。
- 任务状态：剩余时间、实际投入、完成进度、置信度。
- 用户状态：疲劳、最近专注时长、偏离计划情况。
- 行为偏好：不同任务类型的高效时间段、常用软件。
- 外部上下文：地点、天气、通勤、文件上下文。

短期继续使用启发式/贪心算法；中期可以引入更明确的评分函数；长期再考虑 CP-SAT。

所有排程输出仍必须是：

```text
预案 -> 用户确认 -> 写入任务排程片段 -> 写审计日志
```

## 7. P4：服务端 / 客户端分离

这是未来架构主线。服务端不是简单备份，而是完整数据底座、统计聚合中心和 Web 管理入口；客户端是本地缓存、离线交互、原生采集和原生系统集成入口。

技术路线补充：

- 保留 Flutter 作为 Windows/Android 日常客户端。
- 不把复杂服务端管理后台放进 Flutter 客户端，也不优先用 Flutter Web 实现。
- 服务端独立建设，承担同步、统计、文件、报告和 AI 后台任务。
- Web 管理面板独立建设，承担管理、审计、统计、冲突处理和远程配置。
- Windows 文件能力、右键菜单、资源管理器联动、OneDrive 本地状态检测等通过 Flutter 插件或轻量 sidecar 补强。
- Electron/Tauri/React Native 只作为远期备选，不作为近期重构目标。

P0 已完成，后续服务端和同步开发应以以下交付物为准：

- `docs/architecture/p0_client_server_architecture_260426.md`
- `docs/architecture/p0_completion_report_260426.md`
- `docs/architecture/p0_p1_handoff_contract_260426.md`

### 7.1 服务端第一阶段

- 用户、设备、会话、令牌。
- 完整数据同步 API。
- 本地离线变更队列与同步状态。
- 文件元数据与对象存储接口。
- 操作审计同步。
- 设备心跳与在线状态。
- 服务端统计 API：热力图、输入统计、区间分析、趋势、任务实际投入。
- Web 管理面板：数据管理、同步状态、审计、统计图、冲突处理。

### 7.2 客户端职责

- 本地数据库继续作为离线主缓存。
- Windows 原生集成、Android 权限、文件打开、右键菜单、追踪采集仍在客户端。
- 自动操作确认仍优先在客户端完成。

### 7.3 同步原则

- 本地可用优先。
- 服务端作为跨端事实协调中心和完整事实库。
- 冲突必须可见、可解释、可人工解决。
- 所有信息最终同步到服务端；追踪原始高频数据可采用分批、压缩、后台上传，不要求实时阻塞。
- 热力图等统计默认由服务端聚合返回，客户端只在用户展开明细时分页拉取原始记录。

## 8. P5：文件管理与存储系统

文件管理应与日程、任务、追踪、AI 结合，而不是做成普通网盘壳。

### 8.1 基础能力

- 文件夹树、文件元数据、最近使用文件夹。
- 根据任务/日程推荐文件夹。
- 支持任务绑定文件夹、日程绑定文件夹、项目绑定文件夹。
- Windows 下支持在资源管理器打开对应文件夹。
- 文件双击调用系统默认打开；手机端长按替代双击。
- 单击文件右侧提供预览。
- 文本/Markdown/代码/JSON/CSV 等非二进制格式支持内置修改。

### 8.2 OneDrive 与服务器存储共存

建议抽象为统一 `FileProvider`：

```text
LocalProvider
ServerStorageProvider
OneDriveProvider
```

策略：

- 优先与服务端存储交互。
- 网络不佳或服务端不可用时可接入 OneDrive。
- 服务端后台与 OneDrive 同步。
- 同步冲突保留双版本，生成冲突候选，用户确认后合并。
- 云端目录树尽可能完整缓存，避免每次点击单独加载。
- 未在本地的 OneDrive 文件点击时提示是否下载。
- 已在本地的文件直接调用本地路径。

难点：

- OneDrive 云端文件和本地占位文件的一致性检测，需要使用 provider item id、drive id、eTag/cTag、文件大小、修改时间和本地占位状态综合判断，不能只靠路径。
- 手机端公共文件夹下载时，应保留云端文件夹层级结构。

## 9. P6：AI 聊天与自然语言控制

AI 聊天不应只是聊天窗口，而应成为 FlowPlan 的可审计操作入口。

### 9.1 能力范围

- 查询日程、任务、追踪、文件、实际记录。
- 创建/修改任务或日程的预案。
- 推荐排程。
- 总结当天/本周行为。
- 根据上下文推荐文件夹或资料。
- 解释为什么某个排程这样安排。

### 9.2 操作安全

所有 AI 动作遵循：

```text
自然语言请求
  -> 解析为结构化意图
  -> 生成操作预案
  -> 回传回执
  -> 用户确认
  -> 执行
  -> 写审计日志
```

AI 不直接静默执行关键写操作。

### 9.3 OpenClaw 类能力

可以考虑融入成熟方案或借鉴其“工具调用 / 计算机控制 / 代理执行”思路，但 FlowPlan 内部应先只开放受控工具：

- `create_task_draft`
- `create_event_draft`
- `reschedule_draft`
- `find_files`
- `open_folder`
- `summarize_tracking`
- `query_audit_logs`

不要一开始让 AI 任意控制整个系统。

## 10. P7：位置、蓝牙、天气与更多上下文

### 10.1 手机定位

可在手机端每隔一定时间采样位置，但必须非常谨慎：

- 默认关闭。
- 明确权限说明。
- 支持低频采样、省电模式和仅记录地点标签。
- 原始 GPS 可本地保留，服务端同步摘要。
- 可用于推断通勤、上课地点、外出活动和日程执行情况。

### 10.2 STM32 / 蓝牙长连接

可以作为未来实验能力：

- STM32 或独立设备记录存在性/运动。
- 与手机保持蓝牙连接。
- 记录“是否与手机连接”作为上下文信号。
- 解决设备易遗落的问题：若蓝牙断开，手机端提示。

短期不建议优先做硬件，先把手机定位和蓝牙设备状态抽象接口设计好。

### 10.3 天气信息

天气可作为排程与总结的低频上下文：

- 影响出行、户外任务、通勤缓冲。
- 在日报/周报中解释效率波动。
- 作为 AI 排程输入之一。

## 11. P8：聊天软件接入

QQ、微信、Telegram 等聊天接入应分层处理。

短期：

- 不直接控制聊天软件。
- 支持手动分享文本到 FlowPlan 创建任务/日程。
- Telegram 可优先考虑 Bot，因为开放程度较高。

中期：

- 使用受控 Bot / Webhook / 分享入口接收自然语言指令。
- 指令解析后只生成回执和预案。

长期：

- 对 Windows 端可研究辅助自动化，但必须保持人工确认。
- 不建议依赖不稳定或高风险的私有协议。

## 12. P9：模块化边界

建议未来顶层模块：

```text
calendar
task
scheduler
tracker
actuals
files
sync
ai
audit
settings
platform
server_api
```

共享的核心数据对象：

```text
UserContext
TaskState
ActivitySegment
ActualActivity
SchedulePlan
FileContext
OperationDraft
AuditLog
```

原则：

- 模块内部独立维护。
- 跨模块通过结构化上下文汇总。
- AI 与排程只读统一上下文，写入必须走操作预案。

## 13. 推荐执行顺序

### 近期 1：先解决慢和小体验

1. 追踪大表索引与查询下推。
2. 热力图、输入历史、日志历史分页/懒加载。
3. 工作会话缓存表。
4. 日程/任务展示地点。
5. 阻挡日程生成实际记录候选。

### 近期 2：追踪变成排程输入

1. 新增 `activity_segments`。
2. 新增 `activity_interpretations`。
3. 新增 `task_work_logs` / `actual_activity_logs`。
4. 做规则版活动理解与任务匹配。
5. 低置信度再接 LLM JSON 输出。

### 中期：服务端与文件

1. 设计服务端 API 与同步模型。
2. 客户端接入账号/设备/同步。
3. 先做服务器存储文件树。
4. 再接 OneDrive Provider。
5. Windows 文件夹打开、最近文件夹、任务推荐文件夹。

### 中长期：AI 与全上下文

1. AI 聊天窗口。
2. 受控工具调用。
3. 日程/任务/文件/追踪统一检索。
4. 自然语言创建预案。
5. 位置、天气、聊天入口等上下文逐步进入 `UserContext`。

## 14. 当前最建议立刻开发的任务

如果下一轮就开始动代码，建议从以下 5 项开始：

1. 为追踪三张大表补齐复合索引，并增加 Repository 层分页查询。
2. 把追踪页筛选从页面层 `.where(...)` 下推到数据库查询。
3. 在时间轴和周视图中补充日程地点展示。
4. 新增阻挡日程到实际记录候选的服务和确认入口。
5. 新增 `activity_segments` 表与首版按天重算服务。
