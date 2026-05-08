# Changelog

## [2.0.0+200] — 2026-05-08

### 🔄 全量重构 — 从 1.5.0 到 2.0.0

本次发布是 FlowPlanV2 历史上最大规模的一次重构。从底层基础设施到上层功能模块，所有核心系统均被重新设计和加固。

---

### 基础设施 (Phase 1)

| 变更 | 说明 |
|------|------|
| **测试框架** | 引入 vitest + supertest，从 0 tests → 88 tests (11 spec files) |
| **公共工具库** | 统一 `common/utils/` (10 文件)，消除 19 个 service 的 ~60 处重复代码 |
| **JWT 认证** | 明文 token → `@nestjs/jwt` + Passport + access(24h)/refresh(7d) 轮换 |
| **请求限流** | `@nestjs/throttler` 100req/60s |
| **日志系统** | console.log → winston 结构化日志 (AppLogger) |
| **错误处理** | 统一 catch message → ErrorCode 枚举 (26 种) + AppException + GlobalExceptionFilter |
| **配置管理** | `@nestjs/config` + `ConfigModule` + `JwtModule.registerAsync()` |
| **请求日志** | `RequestLogInterceptor` — method/path/statusCode/duration |

### 核心数据层 (Phase 2)

| 变更 | 说明 |
|------|------|
| **Schema v2.0** | 合并所有 ALTER TABLE → 清洁版 p1_schema.sql |
| **GIN 索引** | `sync_objects_payload_gin_idx` (jsonb_path_ops) |
| **物化视图** | `mv_activity_daily_summary` + `mv_input_hourly_summary` |
| **ObjectType 规范** | 16 种 canonical 类型 + LegacyTypeMap 迁移脚本 |
| **Repository 层** | `SyncObjectRepository` (findByUid/findById/listByType/countByType/recordChange) |

### 同步协议 (Phase 3)

| 变更 | 说明 |
|------|------|
| **冲突策略** | 2→4 种 (use_local/use_server/merge/keep_both) |
| **Mutation TTL** | `purgeStaleMutations()` + POST /api/sync/purge-stale |
| **队列限制** | max 200 mutations per push |
| **健康监控** | GET /api/sync/health + openConflicts/mutationStats/lastChangeAt |

### 功能模块 (Phase 4)

#### 任务与日历 (5.1)
- 标准化 `TaskPayload` / `CalendarEventPayload` schema + normalize 函数
- 状态枚举：todo/in_progress/done/cancelled
- 字段名统一：camelCase (startAt/dueAt/endAt)
- admin DOMAIN_OBJECT_TYPES 简化 + 向后兼容
- web/web.controller 添加 DELETE 和 complete 端点

#### 追踪采集 (5.2)
- 批处理状态机：open → receiving → processing → completed
- 去重计数 + 类型白名单验证
- 11 tests (batch/chunk/complete/throughput)

#### 统计分析 (5.3)
- MV-first 查询模式 (auto-fallback to live query)
- CSV/JSON 导出 (GET /analytics/export/csv + /json)
- 9 tests (heatmap/summary/export)

#### 活动理解 (5.4)
- TF-IDF 任务匹配算法 (TfidfMatcher — zero-dependency)
- pgvector 可选支持 (task_embeddings 表 + match_tasks() 函数 + simpleEmbedding fallback)
- 合并规则增强：文件路径 + 窗口标题 + 同目录
- 分类扩展：6→8 类 (coding/writing/meeting/communication/design/entertainment/browsing)
- 活动拆分/合并端点 (POST split + POST merge)

#### 智能排程 (5.5)
- 遗传算法调度器 (pop50/gen100/mutation0.1/crossover0.7/elite5)
- Kahn 拓扑排序 + 分层 + 环检测 (DependencyGraphService)
- 用户反馈学习 (recordFeedback + suggestPrompts)
- 12 tests (7 genetic + 5 dependency)

#### 报告模块 (5.6)
- 模板引擎 (条件/循环/嵌套变量/点号路径)
- 质量评分 (4维：completeness/evidenceCoverage/contentRichness/factualAccuracy)
- 历史对比 (delta + 新增/移除条目)
- 8 tests

#### 文件系统 (5.7)
- 流式下载 (createReadStream — O(1) 内存)
- 流式 SHA-256 (hashFile — stream-based)
- 5 tests (write/read/stream/hash/performance)

#### AI 与模型 (5.8)
- executeDraft bug 修复：create_calendar_event 不再被阻断
- AI API 重试 + 超时 (3 retries + exponential backoff + AbortController + 30s timeout)
- 上下文修复：file_items → file_nodes
- Flutter AI 聊天 UI (flutter_chat_ui + markdown_widget)
- 6 tests

### 外部集成 (Phase 5)

#### Outlook (6.1)
- 安装官方 `@microsoft/microsoft-graph-client` SDK
- OAuth URL / Scope / Token密钥 → 全部可配置
- 可选只读/读写 sync_mode
- 人工确认写操作 (prepare → confirm/reject)
- Flutter 死代码标记 `@deprecated`

### 管理端增强 (Phase 6-7)

| 变更 | 说明 |
|------|------|
| Dashboard | `@ant-design/charts` Area/Line 图表 (冲突趋势 + AI 草稿趋势) |
| LogsPage | 系统日志查看 (操作者筛选 + 动作搜索) |
| JobsPage | 定时任务管理 (5 个 cron job: 物化视图/天气/追踪/mutation/日报) |
| SchedulePage | 智能排程管理 (拓扑排序 + 遗传算法 + 定时任务) |
| AlertsPage | 异常告警 (5 模块错误聚合: tracking/sync/outlook/jobs/push) |
| Swagger | `@nestjs/swagger` → GET /api/docs |

### 后台任务 (Phase 7.2)

| 任务 | Cron | 功能 |
|------|------|------|
| refresh-materialized-views | 每小时 | 刷新物化聚合视图 |
| refresh-weather-cache | 每6小时 | 清理过期天气缓存 |
| clean-tracking-data | 每天 3AM | 清理 90 天前追踪数据 |
| purge-sync-mutations | 每天 4AM | 清理 30 天前旧 mutations |
| auto-generate-reports | 每天 6AM | 自动日报生成 |

### Flutter 客户端

| 变更 | 说明 |
|------|------|
| B3 静态分析 | 0 TODO/FIXME，已知 deprecated outlook import |
| B7 AI 聊天 UI | flutter_chat_ui + markdown_widget 集成 |
| B8 任务仓库重构 | payload_utils.dart 共享工具 + 状态对齐 |
| B9 活动拆分/合并 | splitSegment + mergeSegments API + UI |
| B1/B2 | Windows/Android 构建通过 |

### 安全加固

| 变更 | 说明 |
|------|------|
| **加密密钥统一** | `encryptionKey()` (优先级: FLOWPLANV2_ENCRYPTION_KEY → OUTLOOK_CONFIG_SECRET → AI_CONFIG_SECRET) |
| **4× secretKey() 删除** | ai/models/reports/outlook 全部改用统一密钥 |
| **健康检查** | `isEncryptionKeySecure()` + encryptionKeySource |
| **连接池监控** | Pool 事件监听 + poolStats() + SLOW_QUERY_THRESHOLD_MS |

### 关键指标对比

| 指标 | 1.5.0 | 2.0.0 |
|------|-------|-------|
| 测试数 | 0 | **88 passed** (11 spec files) |
| 覆盖率 | 0% | **45.25%** |
| Service 重复代码 | 19 个各自实现 | 统一 common/utils/ |
| 认证 | 明文 token | JWT + refresh 轮换 |
| 冲突策略 | 2 种 | 4 种 |
| 排程算法 | 贪心 | 遗传算法 + 拓扑排序 |
| 报告模板 | 简单正则替换 | 条件/循环/嵌套 |
| 任务状态 | 5+ 种写法 | 4 种枚举 (英存中显) |
| object_type | 12+ 种混乱 | 16 种 canonical |
| 管理端页面 | 9 | **14** (+Dashboard图表 +Logs +Jobs +Schedule +Alerts) |
| Flutter analyze | 未运行 | 0 errors |
| API 文档 | 无 | Swagger /api/docs |

---

## [1.5.0+150] — 2026-04-26

- 初始 client/server 分离
- PostgreSQL schema 55 表
- 同步协议 (push/pull/ack/conflict)
- Outlook OAuth + 日历同步
- AI 对话 + 操作草案
- 追踪采集 + 活动理解
- 报告生成 + 推送
- 文件系统 + 版本管理
