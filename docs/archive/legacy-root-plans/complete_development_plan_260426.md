# FlowPlan 完整可执行开发计划（2026-04-26）

> 已整理归档：新的权威计划入口为 `docs/planning/master_priority_plan_260426.md`。本文保留为 2026-04-26 阶段性来源文件。

## 0. 文档定位

本文用于把当前所有想法整理成一份可落地的长期开发计划。它不替代现有 `CODEX.md`、`plan260424.md` 和 `future_development_plan_260426.md`，而是作为后续拆任务、排优先级、设计架构时的完整蓝图。

当前目标不是一次性做完所有功能，而是让 FlowPlan 从“本地智能日程与追踪工具”逐步演进为：

```text
本地优先的个人信息操作系统
= 日程 + 任务 + 追踪 + 实际记录 + 文件 + AI 聊天 + 服务端同步 + 多端入口
```

2026-04-26 补充原则：未来架构应以服务端完整存储为同步底座。所有信息最终都应同步到服务端存储；客户端同时保留本机数据作为离线缓存和本地可用副本。网络环境差时，客户端允许继续写入本地，并清晰标识“未与云端同步”的数据。大量统计信息由服务端查表聚合后返回最终统计结果，客户端不应为了热力图、趋势图、输入统计等功能下载大量原始数据。

核心判断：

- 追踪数据、日程、任务、文件、位置、天气、聊天指令都不应孤立存在。
- 它们应统一进入一个结构化的 `UserContext`，再服务于排程、总结、推荐和 AI 交互。
- AI 不应直接接管数据库写操作，而应生成可审计、可确认的操作预案。

## 1. 总原则

### 1.1 产品原则

1. 中文优先。所有用户可见文案默认使用简体中文。
2. 服务端完整存储 + 本地离线缓存。所有信息最终同步到服务端；本机保留完整或按策略裁剪的本地副本，离线可用。
3. 人工确认。所有自动写入、自动修改、自动删除、自动同步冲突处理，都必须先生成预案或回执。
4. 全部可追溯。关键数据操作必须写入审计日志。
5. 模块独立，信息综合。模块边界清晰，但上层统一汇总到用户上下文。
6. 先可用，再智能。优先规则、索引、缓存、预案机制，后接 LLM 和复杂模型。
7. 隐私分层。原始键盘输入、聊天内容、位置轨迹等敏感数据即使同步到自有服务端，也必须与第三方 LLM API 严格隔离；外部 LLM 只接收脱敏摘要。

说明：如果后续明确要求“原始敏感数据也同步到自有服务端”，则必须增加端到端加密、字段级加密、同步范围开关、服务端访问审计和数据导出/删除能力。

### 1.2 工程原则

1. 先修性能瓶颈，再扩展大功能。
2. 大页面拆小，避免继续向巨型文件追加逻辑。
3. 所有新能力先沉入数据模型和服务层，再接 UI。
4. 高频数据写入和普通审计日志分开，避免审计表爆炸。
5. 当前重构主线调整为客户端/服务端分离。服务端成为完整数据底座，客户端成为本地缓存、采集、原生集成和离线交互入口。
6. 继续保留 Flutter 作为 Windows/Android 主客户端。当前不做 Electron、Tauri、React Native 全量迁移。
7. Web 管理面板独立建设，优先使用 Next.js 或 Vite React，不把 Flutter Web 作为复杂管理后台主路线。

## 2. 当前项目基础与问题

### 2.1 已有基础

FlowPlan 当前已经具备：

- Flutter + Riverpod + Drift/SQLite 本地应用架构。
- 日历三视图：时间轴、周视图、月视图。
- 任务管理、未排程任务面板、任务详情、任务本。
- Outlook 日历同步、任务镜像、冲突处理、诊断报告。
- iCalendar 导入导出、结构化归档、完整数据库备份恢复。
- Windows 前台窗口追踪、全局键鼠事件追踪、JSONL + SQLite 双写。
- Android Usage Stats 导入。
- 工作会话合并、输入热力图、历史日志、区间分析。
- 多组工作时间、阻挡日程、任务锁定、可拆分任务、多段排程。
- 自动排程预案、人工确认、操作审计。
- 计划偏离检测与重排提示。

### 2.2 当前主要问题

1. 追踪查询慢  
   筛选、热力图、输入分析、区间分析中仍存在大量页面层过滤和 Dart 侧聚合。

2. 页面和 Provider 过大  
   `tracker_page.dart`、`outlook_settings_page.dart`、`ical_import_export_page.dart`、`app_providers.dart` 已经不适合继续堆逻辑。

3. 追踪还没有稳定进入排程输入模型  
   当前已经有计划偏离检测，但还缺少“活动片段 -> 任务实际投入 -> 剩余时间修正”的正式链路。

4. “实际记录”概念不够独立  
   日程是计划，任务是待办，追踪是证据，但用户最终需要的是“实际发生了什么”。

5. 文件系统尚未接入  
   任务、日程、项目和文件夹之间还没有结构化关系。

6. 服务端尚未成为同步和多端协作底座。

7. AI 还没有安全的工具调用层。

## 3. 总体目标架构

### 3.0 技术路线决策

当前最稳妥的路线是：

```text
Flutter 客户端
  日常使用、离线缓存、原生采集、文件打开、人工确认

FlowPlan Server
  完整事实库、同步、统计聚合、文件存储、报告、AI 后台任务

Web 管理面板
  服务端管理、审计、统计图、同步状态、冲突处理、远程配置
```

因此后续开发不以“换掉 Flutter”为目标，而是把 Flutter 从本地单体重构为服务端体系下的客户端。Windows 文件管理、右键菜单、资源管理器调用、OneDrive 本地占位文件识别等原生能力，优先通过 Flutter Windows 插件或轻量 sidecar 补强；只有当这些能力长期成为 Flutter 的结构性障碍时，才在远期评估 Tauri/WinUI 等 Windows 专用客户端。

Web 管理面板不应和 Flutter 客户端绑在一起发布。它面向服务端管理和远程访问，适合独立 Web 技术栈；Flutter Web 可以作为轻量展示入口或备用入口，但不是复杂管理后台的主实现。

P0 已完成并形成三份架构交付物：

- `docs/architecture/p0_client_server_architecture_260426.md`
- `docs/architecture/p0_completion_report_260426.md`
- `docs/architecture/p0_p1_handoff_contract_260426.md`

### 3.1 客户端架构

```text
FlowPlan Client
├── calendar       日程、日历本、课表、阻挡时间
├── task           任务、任务本、任务状态
├── tracker        原始活动、输入事件、工作会话
├── actuals        实际记录、实际耗时、活动确认
├── scheduler      排程预案、排程片段、重排
├── files          文件树、文件夹推荐、预览、打开
├── ai             聊天、意图解析、工具预案
├── sync           服务端同步、OneDrive/Outlook 等外部同步
├── sync_cache     本地缓存、离线队列、同步状态标识
├── audit          操作审计、回滚线索
├── settings       权限、隐私、同步、AI 配置
└── platform       Windows/Android 原生能力
```

### 3.2 服务端架构

```text
FlowPlan Server
├── auth                 用户、设备、令牌
├── sync                 全量业务数据同步、离线变更合并、同步状态
├── canonical_store      服务端完整事实库
├── storage              服务端文件存储
├── file_index           文件树、最近文件夹、搜索索引
├── analytics            热力图、趋势、输入统计、追踪聚合
├── ai_jobs              AI 异步任务、日报周报、低频分析
├── audit                跨端操作审计
├── conflict             多端冲突检测与候选合并
├── rendezvous           设备发现、局域网候选、P2P 信令
├── admin_panel          服务端完整管理面板
└── web                  Web 端 API 与页面
```

### 3.3 统一上下文模型

未来所有智能能力围绕 `UserContext` 工作：

```text
UserContext
├── today_calendar_blocks
├── active_tasks
├── unscheduled_tasks
├── task_states
├── recent_activity_segments
├── actual_activity_logs
├── user_patterns
├── file_context
├── location_context
├── weather_context
├── device_context
└── pending_operation_drafts
```

它不是一个大模型，而是一套结构化状态。LLM、排程器、文件推荐器、日报生成器都读取它。

## 4. 开发阶段总览

```text
Phase 0  性能与稳定性整理
Phase 1  小体验修复与实际记录候选
Phase 2  追踪融合模型
Phase 3  排程模型升级
Phase 4  文件管理本地版
Phase 5  客户端/服务端分离与完整同步底座
Phase 6  文件云存储与 OneDrive 共存
Phase 7  AI 聊天与受控工具调用
Phase 8  位置/蓝牙/天气上下文
Phase 9  聊天软件入口与外部自动化
Phase 10 Web 端与长期智能
```

## 5. Phase 0：数据库与追踪查询性能优化

### 5.1 目标

解决当前“追踪”筛选和查询加载时间长的问题。此阶段是所有后续智能分析的基础。

同时需要提前适配未来前后端分离：客户端本地数据库可以继续支撑离线与当前设备视图，但长期统计、跨设备统计、热力图、输入强度排行、趋势图等大数据查询，应由服务端数据库完成聚合，只把最终统计结果返回客户端。

### 5.2 具体任务

1. 补充索引  
   为 `activity_records`、`raw_activity_logs`、`tracked_input_events` 增加面向查询路径的复合索引。

2. 查询下推  
   把页面层的搜索、应用筛选、分类筛选、任务筛选、时间段筛选移动到 Repository SQL 查询。

3. 分页加载  
   历史日志、输入事件、原始活动记录默认分页读取。

4. 聚合表  
   新增按日/小时统计表，热力图和输入分析默认读取聚合结果。

5. 工作会话缓存  
   新增 `work_session_cache`，按天缓存合并后的工作会话，规则变更时可重算。

6. 服务端统计接口预留  
   为热力图、输入统计、区间分析设计服务端 API 形态：客户端传时间范围、设备、应用、分类等筛选条件，服务端返回 bucket、topN、summary 等聚合结果。

7. 查询取消与缓存  
   用户快速切换筛选条件时，旧查询不应继续阻塞 UI；最近查询结果可缓存。

### 5.3 建议新增表

```sql
activity_hourly_stats
activity_daily_stats
input_hourly_stats
input_daily_stats
work_session_cache
```

### 5.4 验收标准

- 打开追踪主页不因历史数据多而明显卡顿。
- 当天、最近 7 天、最近 30 天查询均可接受。
- 输入历史和日志历史首屏只加载第一页。
- 热力图不再每次扫描全部原始数据。
- 未来接入服务端后，热力图和趋势统计不需要下载原始追踪事件即可渲染。

## 6. Phase 1：小体验修复与“实际记录”基础

### 6.1 日程/任务展示地点

现状：`calendar_events.location` 已存在，但视图中展示不足。

任务：

- 时间轴事件块在空间足够时显示地点。
- 周视图较高块显示地点。
- 详情页保持完整地点字段。
- 任务未来可新增地点字段，当前先处理日程。

验收：

- 空间足够时能看到地点。
- 小块不会文字溢出。
- 手机端不挤压布局。

### 6.2 阻挡日程生成实际记录候选

背景：设定阻挡的日程通常是课表、会议、考试、通勤等必须执行的事情。如果对应时间内没有其他实际记录，可以生成候选实际记录。

规则：

```text
日程 isBlock = true
且时间已结束
且状态不是 CANCELLED
且该时间段没有其他已确认 actual
且没有明显冲突的追踪任务证据
=> 生成 actual 候选
```

注意：不是直接静默写入最终实际记录。

建议新增表：

```sql
actual_activity_logs
  id
  title
  start_at
  end_at
  source_type        -- calendar_event / activity_segment / manual / ai
  source_id
  confidence
  confirmed_by_user
  evidence_json
  created_at
  updated_at
```

交互：

- 日报或“实际记录”页展示候选。
- 用户可确认、改名、忽略。
- 确认/忽略都写审计。

验收：

- 课表类阻挡日程结束后能生成候选。
- 有其他已确认实际记录时不重复生成。
- 用户确认后才成为正式实际记录。

## 7. Phase 2：追踪融合模型

### 7.1 目标

让追踪不只是展示数据，而是成为任务状态和排程的输入。

### 7.2 数据流

```text
activity_records + tracked_input_events + raw_activity_logs
  -> activity_segments
  -> activity_interpretations
  -> task_work_logs / actual_activity_logs
  -> task_states
  -> scheduler
```

### 7.3 活动片段

新增 `activity_segments`：

```sql
id
start_at
end_at
dominant_apps_json
dominant_categories_json
window_keywords_json
input_summary_json
interruption_count
focus_score
source_day
cache_version
created_at
updated_at
```

规则：

- 空闲超过阈值切段。
- 短暂切到资源管理器、浏览器、通讯工具可吸收为插曲。
- FlowPlan 自身默认不打断外部工作段。
- 同类应用、相似标题、相近文件路径倾向合并。

### 7.4 活动理解

新增 `activity_interpretations`：

```sql
id
segment_id
activity_type
related_task_id
confidence
productive_minutes
progress_signal
evidence_json
natural_summary
interpreter_source   -- rule / llm / user
confirmed_by_user
created_at
updated_at
```

早期规则：

- VS Code / Android Studio / GitHub / Terminal -> 编程。
- Word / PDF / 学校系统 -> 作业/写作。
- PowerPoint / WPS 演示 -> PPT。
- 微信 / QQ / Telegram -> 通讯。
- Steam / 游戏 / 视频 -> 娱乐。

任务匹配得分：

```text
score =
  任务标题/描述关键词
+ 应用类型匹配
+ 时间接近计划
+ 截止日期紧迫
+ 历史任务常用应用
- 娱乐/社交长打断
```

### 7.5 LLM 参与方式

LLM 只在以下情况调用：

- 规则置信度低。
- 多个候选任务得分接近。
- 需要生成自然语言说明。
- 用户主动要求 AI 分析。

LLM 输入：

- 活动片段摘要。
- 候选任务。
- 附近日程。
- 脱敏关键词。

LLM 不接收：

- 原始键盘完整文本。
- 密码/验证码/API key。
- 完整聊天原文。
- 不必要的完整文件路径。

LLM 输出必须是 JSON：

```json
{
  "activity_type": "coding",
  "related_task_id": 123,
  "confidence": 0.82,
  "productive_minutes": 95,
  "progress_signal": "likely_progress",
  "reason": "主要应用和任务关键词匹配",
  "summary": "你大概率在处理 FlowPlan 的排程功能。"
}
```

### 7.6 任务实际投入

新增 `task_work_logs`：

```sql
id
task_id
segment_id
start_at
end_at
minutes
source
confidence
confirmed_by_user
created_at
updated_at
```

用途：

- 统计任务已投入时间。
- 修正任务剩余时间。
- 支持排程器理解“这个任务已经完成了多少”。

验收：

- 一天追踪可被整理为 5-20 个活动片段。
- 高置信度片段可关联到任务。
- 任务详情能看到实际投入证据。
- 低置信度片段不会强行写入任务。

## 8. Phase 3：排程模型升级

### 8.1 目标

从“能排进去”升级为“根据真实状态合理排，并能解释”。

### 8.2 排程输入模型

排程器输入应明确包含：

- 固定日程：上课、会议、考试。
- 阻挡日程：不能安排其他任务。
- 可移动任务：自动排期且未锁定。
- 未排任务：待调度。
- 任务剩余时间：来自用户设置 + 实际投入修正。
- 用户状态：最近工作时长、疲劳、偏离情况。
- 用户习惯：不同任务类型适合时间段。
- 文件上下文：任务相关文件夹是否最近使用。
- 地点/天气：影响通勤和户外任务。

### 8.3 短期算法

继续用启发式评分：

```text
score =
  priority_score
+ urgency_score
+ time_block_fit_score
+ habit_match_score
+ context_continuity_score
- fatigue_penalty
- switch_cost
- lateness_risk
```

### 8.4 中期算法

引入更明确的候选槽评估：

```text
for each task:
  for each available slot:
    calculate placement_score(task, slot, user_context)
choose best placements with conflict checks
```

### 8.5 长期算法

在任务数量和约束复杂后考虑 CP-SAT，但不作为近期优先级。

### 8.6 操作边界

所有排程变更：

```text
生成预案
-> 展示原因、冲突、影响任务
-> 用户确认
-> 写入 task_schedule_segments
-> 写入 data_operation_logs
```

验收：

- 排程预案中能解释为什么这么排。
- 自动重排不静默修改。
- 实际投入会影响剩余时间和后续排程。

## 9. Phase 4：本地文件管理

### 9.1 目标

让文件成为任务、日程、项目的一等上下文。

### 9.2 本地文件能力

任务：

- 新增文件夹绑定：任务、日程、项目均可绑定文件夹。
- 最近使用文件夹常驻。
- 根据当前任务/日程推荐文件夹。
- Windows 支持“在资源管理器中打开”。
- 文件双击调用系统默认打开。
- 手机端长按替代双击。
- 单击文件在右侧预览。
- 文本、Markdown、代码、JSON、CSV 支持内置编辑。

建议新增表：

```sql
file_providers
file_items
file_bindings
recent_folders
file_open_logs
```

### 9.3 文件夹推荐规则

推荐依据：

- 任务标题和文件夹名匹配。
- 最近处理该任务时打开过的文件夹。
- 日程地点/课程名与文件夹匹配。
- 项目绑定。
- AI 可辅助给出候选，但打开前由用户选择。

验收：

- 打开任务详情时能看到推荐文件夹。
- 最近文件夹可快速进入。
- Windows 能调用资源管理器打开目录和文件。

## 10. Phase 5：客户端/服务端分离与完整同步底座

### 10.1 目标

这是当前新增要求下的主线阶段。目标不是只做“备份”，而是把 FlowPlan 重构为客户端/服务端分离架构：

- 服务端保存完整数据，是跨端同步、Web 管理、统计聚合和未来 AI 任务的核心底座。
- 客户端继续保存本机数据，负责离线可用、原生采集、原生文件操作和本地缓存。
- 网络环境差时，客户端允许继续创建、修改和查看本地数据，并明确展示哪些数据尚未与云端同步。
- 热力图、输入分析、长期趋势等大量数据统计由服务端查表聚合后返回结果，客户端不下载海量原始事件。

技术路线补充：

- Windows/Android 主客户端继续使用 Flutter。
- P5 的重构目标是拆分 Flutter 客户端职责，不是全量重写客户端。
- 服务端独立建设，不使用 Flutter 客户端承担服务端职责。
- Web 管理面板独立建设，优先使用 Next.js 或 Vite React。
- Windows 原生能力优先通过插件/sidecar 增强，不因为文件管理能力整体替换客户端框架。

### 10.2 服务端第一版功能

- 用户登录。
- 设备注册。
- 客户端全量业务数据增量上传。
- 服务端变更增量拉取。
- 本地未同步数据状态管理。
- 操作审计同步。
- 基础冲突检测。
- 服务端完整管理面板，可以先用 Web 端实现。
- Web 端查看和管理日程、任务、实际记录、追踪摘要、文件元数据、同步状态和审计记录。
- 服务端统计 API：热力图、输入统计、区间分析、任务实际投入、应用使用排行。

### 10.3 同步对象

第一批必须同步：

- 日历本、任务本。
- 日程、任务。
- 排程片段。
- 实际记录。
- 操作审计。
- 设置项中与跨端一致性有关的部分。

第二批必须同步：

- 活动片段。
- 活动理解结果。
- 文件元数据。
- 文件绑定关系。
- 最近文件夹。

第三批必须同步，但可采用后台、分批、压缩或延迟策略：

- 高频原始追踪数据。
- 输入事件。
- 原始活动日志。
- 位置采样。
- AI 对话和工具调用记录。

说明：这里的“必须同步”指最终进入服务端完整存储；不要求所有高频数据都实时阻塞上传。高频数据可以先写本地队列，再按网络情况后台上传。

### 10.4 客户端本地缓存与未同步标识

客户端所有可变数据建议统一增加同步元数据：

```text
sync_state        synced / pending_create / pending_update / pending_delete / conflict / failed
local_version
server_version
last_synced_at
last_sync_error
origin_device_id
```

UI 要求：

- 本地新建但未上传的数据显示“未同步”。
- 本地修改但服务端未确认的数据显示“等待同步”。
- 同步失败显示原因和重试入口。
- 冲突数据显示“需要处理”，不能静默覆盖。
- 网络差时仍可继续编辑，但要知道这些修改尚未进云端。

### 10.5 服务端统计 API

大量统计功能应改为服务端聚合：

```text
GET /analytics/activity-heatmap
GET /analytics/input-heatmap
GET /analytics/activity-range-summary
GET /analytics/top-apps
GET /analytics/task-work-summary
GET /analytics/focus-trends
```

客户端请求参数：

```text
time_range
scale: hour/day/month/year
device_ids
platforms
process_name
category
task_id
include_ignored
```

服务端返回：

```text
summary
buckets
top_apps
top_categories
representative_sessions
pagination_cursor_for_details
```

原则：

- 默认只返回统计结果和少量代表性明细。
- 用户展开明细时再分页拉取原始记录。
- 手机端默认不下载电脑端完整键鼠事件。
- Web 管理面板同样通过统计 API 渲染图表。

### 10.6 冲突策略

- 同一字段多端修改 -> 冲突候选。
- 服务端不自动覆盖本地。
- 客户端展示冲突，用户选择本地、远端或手动合并。
- 所有冲突处理写审计。

验收：

- Windows 和手机能看到同一任务/日程数据。
- 离线修改后联网能同步。
- 冲突不会静默覆盖。
- Web 管理面板能查看同步状态、审计记录和服务端统计。
- 热力图等统计图可以由服务端返回聚合结果渲染，不需要客户端下载原始追踪表。

## 11. Phase 6：云文件与 OneDrive 共存

### 11.1 统一 FileProvider

```text
FileProvider
├── LocalProvider
├── ServerStorageProvider
└── OneDriveProvider
```

### 11.2 优先策略

- 默认优先服务端存储。
- 网络不好时可读取本地缓存或 OneDrive。
- 服务端后台与 OneDrive 同步。
- 两者可共存，保证多端备份。

### 11.3 OneDrive 关键问题

不能只用路径判断云端文件和本地文件是否相同，应综合：

- driveId
- itemId
- eTag / cTag
- size
- modifiedTime
- file hash 如果可用
- 本地占位状态

### 11.4 云文件树

原则：

- 尽量缓存完整云盘文件树。
- 后台增量刷新。
- 点击目录优先读缓存，避免每次点击都请求网络。
- 未在本地的文件点击时提示下载。
- 手机端下载保留文件夹层级。

### 11.5 冲突策略

- 同名同路径不同内容 -> 保留双版本。
- 本地改、云端也改 -> 冲突候选。
- 用户确认合并/覆盖/保留副本。

验收：

- 同一任务可同时看到服务端文件和 OneDrive 文件。
- 未下载文件点击时有明确提示。
- 本地存在文件可直接原生打开。
- 冲突不静默覆盖。

## 12. Phase 7：AI 聊天与受控工具调用

### 12.1 目标

AI 聊天成为 FlowPlan 的自然语言入口，但所有操作都必须可确认、可审计。

### 12.2 聊天能力

第一版：

- 查询今天日程。
- 查询未完成任务。
- 总结追踪记录。
- 解释排程原因。
- 生成任务/日程草稿。
- 生成重排预案。

第二版：

- 查询文件。
- 推荐文件夹。
- 总结某个项目进展。
- 根据实际记录修正任务剩余时间。

第三版：

- 跨端设备/文件/日程/追踪综合分析。
- 类 OpenClaw 的受控代理能力。

### 12.3 工具调用安全模型

AI 只能调用受控工具：

```text
query_calendar
query_tasks
query_tracking_summary
query_files
create_task_draft
create_event_draft
reschedule_draft
bind_file_folder_draft
open_folder_request
summarize_day
```

写操作流程：

```text
用户自然语言
-> AI 解析意图
-> 生成 OperationDraft
-> 用户确认
-> 执行 Repository 操作
-> 写审计
```

建议新增表：

```sql
ai_conversations
ai_messages
operation_drafts
ai_tool_calls
```

验收：

- AI 创建任务时先展示草稿。
- AI 重排时只生成预案。
- 用户确认前数据库不变。
- 每次执行有审计记录。

## 13. Phase 8：位置、蓝牙、天气上下文

### 13.1 手机定位

用途：

- 判断是否到达上课/会议地点。
- 辅助生成实际记录。
- 识别通勤、外出、运动。
- 优化提醒和排程缓冲。

边界：

- 默认关闭。
- 明确权限说明。
- 支持低频采样。
- 支持只保留地点标签，不上传原始轨迹。
- 原始 GPS 优先本地存储。

建议新增：

```sql
location_samples
place_aliases
location_activity_candidates
```

### 13.2 蓝牙 / STM32

定位：

- 长期实验能力，不作为近期主线。
- 可记录“硬件是否与手机连接”。
- 可用于防遗落提醒和存在性记录。

先做抽象接口：

```text
CompanionDeviceProvider
  scan()
  connect()
  connectionState()
  lastSeen()
```

### 13.3 天气

用途：

- 出行任务缓冲。
- 户外任务建议。
- 日报解释效率波动。

原则：

- 低频更新。
- 服务端可缓存天气。
- 不作为硬约束，只作为软约束。

验收：

- 位置/天气只进入排程解释和建议，不静默改日程。

## 14. Phase 9：聊天软件入口

### 14.1 分层策略

不要一开始直接控制 QQ / 微信。

第一阶段：

- 支持系统分享文本到 FlowPlan。
- 支持 Telegram Bot，因为它开放程度高。
- Bot 收到自然语言后生成 FlowPlan 操作草稿。

第二阶段：

- 微信/QQ 先考虑手动复制或分享入口。
- Windows 端可研究窗口辅助，但必须人工确认。

第三阶段：

- 受控代理模式：可以选择“操作 FlowPlan”或“操作服务器”，但所有写操作仍需回执确认。

### 14.2 验收

- 外部聊天指令不会直接写库。
- 用户能看到“将要创建/修改什么”。
- 确认后才执行。

## 15. Phase 10：Web 端与长期智能

### 15.1 Web 端第一版

Web 端第一版定位为服务端管理面板和远程访问入口，不是 Flutter 客户端的简单网页复制。优先采用 Next.js 或 Vite React，以便复用 TypeScript DTO、表格、权限、图表和管理后台生态。

- 登录。
- 查看日程。
- 查看任务。
- 查看实际记录。
- 查看文件树。
- 简单编辑任务/日程。
- 查看审计记录。

### 15.2 Web 端第二版

- AI 聊天。
- 文件预览。
- 排程预案确认。
- 冲突处理。

### 15.3 长期智能

- 每日/每周总结。
- 任务耗时预测。
- 文件夹推荐。
- 自动生成活动片段解释。
- 个性化排程参数学习。

仍不建议：

- 训练端到端大模型。
- 让 LLM 直接生成最终数据库变更。
- 实时调用 LLM 分析每个窗口切换。

## 16. 数据模型总览

建议未来核心数据对象：

```text
CalendarEvent        计划日程
TaskItem             待办任务
TaskScheduleSegment  任务排程片段
ActivityRecord       原始活动记录
TrackedInputEvent    原始输入事件
WorkSessionCache     工作会话缓存
ActivitySegment      活动片段
ActivityInterpretation 活动理解
TaskWorkLog          任务实际投入
ActualActivityLog    实际发生记录
FileItem             文件/文件夹元数据
FileBinding          文件与任务/日程/项目绑定
UserContextSnapshot  用户上下文快照
OperationDraft       操作预案
DataOperationLog     审计日志
```

## 17. 推荐近期执行清单

### 第一批：最值得马上做

1. 为追踪大表补复合索引。
2. 追踪筛选查询下推到 Repository。
3. 追踪历史页分页。
4. 热力图读取聚合表。
5. 时间轴/周视图显示地点。
6. 阻挡日程生成实际记录候选。

### 第二批：追踪进入排程

1. 新增 `activity_segments`。
2. 新增按天重算活动片段服务。
3. 新增 `activity_interpretations`。
4. 新增规则版活动类型识别。
5. 新增 `task_work_logs`。
6. 任务详情显示实际投入。

### 第三批：文件本地版

1. 新增文件元数据表。
2. 本地文件夹绑定任务/日程。
3. 最近使用文件夹。
4. Windows 资源管理器打开。
5. 文件预览。

### 第四批：服务端

1. 确定服务端技术栈和数据库方案。
2. 用户和设备模型。
3. 设计客户端同步元数据与离线队列。
4. 同步 API：上传本地变更、拉取服务端变更、确认同步状态。
5. 服务端审计。
6. 冲突候选。
7. 服务端统计 API：热力图、输入统计、区间分析。
8. Web 管理面板：数据概览、同步状态、审计、统计图。

### 第五批：AI

1. AI 聊天页面。
2. OperationDraft 表。
3. 查询工具。
4. 创建任务草稿。
5. 重排预案工具。

## 18. 风险与取舍

### 18.1 最大风险

- 功能太多导致项目继续膨胀。
- 服务端、文件、AI、追踪智能同时开工会失控。
- 追踪隐私边界如果设计不好，后期很难补救。

### 18.2 取舍建议

近期只做：

- 性能。
- 实际记录。
- 追踪融合。
- 小体验。

暂缓：

- STM32。
- 深度聊天软件控制。
- 完整 OneDrive 双向同步。
- CP-SAT。
- 端到端模型训练。
- 全量迁移到 Electron/Tauri/React Native。
- 用 Flutter Web 承担复杂管理后台。
- 为 Windows 文件能力整体替换现有 Flutter 客户端。

### 18.3 正确节奏

```text
先让数据快
再确定前后端分离和同步协议
再让所有数据可同步、可标识状态
再让服务端承担统计聚合
再让数据可信并进入排程
再让文件进入上下文
最后让 AI 综合操作
```

## 19. 最终目标形态

理想中的 FlowPlan 应该做到：

- 它知道今天计划做什么。
- 它能根据追踪和阻挡日程推断实际做了什么。
- 它能把实际投入回填到任务状态。
- 它能根据剩余时间、地点、文件、习惯、天气重新生成排程预案。
- 它能推荐当前任务相关文件夹和文件。
- 它能通过聊天理解自然语言请求。
- 它不会擅自修改关键数据。
- 它做过的每个关键动作都能查到。

一句话总结：

```text
FlowPlan 不应只是日历，而应成为一个以时间为主轴、以任务为目标、以追踪为证据、以文件为工作材料、以 AI 为交互层的个人执行系统。
```
