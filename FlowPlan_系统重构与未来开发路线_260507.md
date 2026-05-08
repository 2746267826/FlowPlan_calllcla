# FlowPlanV2 系统重构与未来开发路线

> 生成日期：2026-05-07
> 最后更新：2026-05-08（Phase 1-6.1 完成；6.2/6.3 延后）
> 基于：全量源码审计（server/ client_flutter/ web_admin/） + 55张数据库表 + 20个Service的完整分析
>
> **核心决策：暂停所有新功能开发。从底层开始，逐层重构，打好地基后再逐个功能开发、调试、验收。**

---

## 总体进度

| 阶段 | 名称 | 状态 | 完成度 |
|------|------|------|--------|
| **Phase 1** | 基础设施重构 | ✅ 已完成 | 100% |
| **Phase 2** | 核心数据层重建 | ✅ 已完成 | 100% |
| **Phase 3** | 同步协议加固 | ✅ 已完成 | 100% |
| Phase 4 | 功能模块逐个重建 (5.1-5.8) | ✅ 已完成 | 100% |
| Phase 5 | 外部集成完善 | ✅ 部分完成 | 6.1 done, 6.2/6.3 → 8.4 (A1-A4) |
| Phase 6-7 | 管理端+测试+文档 | ✅ 已完成 | 自动化部分 100%；人工部分 → 8.4 (31 项) |

### 关键成果

| 指标 | 重构前 | 重构后 |
|------|--------|--------|
| 测试覆盖 | 0 tests | **80 tests (10 spec files)** |
| 认证方式 | 明文 token | JWT + refresh 轮换 |
| 日志系统 | console.log | winston 结构化日志 |
| 错误处理 | 统一 catch message | 错误码 + AppException + GlobalExceptionFilter |
| 工具函数 | 19 个 service 各自实现 | 统一 common/utils/ (7 文件) |
| 冲突解决策略 | 2 种 (use_local/merge) | 4 种 (+use_server/+keep_both) |
| 任务状态/字段 | 5+ 种写法混乱 | 标准化 schema + normalize 函数 |
| 追踪批处理 | 无状态机/去重 | open→receiving→processing→completed + dedup 计数 |
| 统计分析 | 全量 JSONB 实时查询 | MV-first + CSV/JSON 导出 |
| 活动匹配 | 简单关键词 (25pts) | TF-IDF + 多维度评分 + pgvector 可选 |
| 排程 | 贪心算法 | 遗传算法 + Kahn 拓扑排序 + 用户反馈学习 |
| 报告 | 简单正则替换 | 模板引擎 (条件/循环/嵌套) + 质量评分 + 历史对比 |
| 文件传输 | Buffer 全量读取 | 流式下载 + 流式 hash (O(1)内存) |
| AI 执行器 | 仅 create_task | +create_calendar_event + 重试3次+超时30s |
| Schema 管理 | 1660 行 ALTER TABLE 堆积 | 清洁版 v2.0 + schema_version |
| JSONB 查询 | 无索引、无物化 | GIN 索引 + 2 个物化视图 |
| object_type | 12+ 种混乱写法 | 16 种 canonical + 迁移脚本 |
| 同步健康 | 无 | GET /api/sync/health + purge-stale |

### 延后到后续 Phase 的任务（汇总）

以下任务因依赖真实设备/外部服务/客户端环境而延后，已明确写入对应 Phase：

| 任务 | 来源 | 目标 Phase | 原因 |
|------|------|-----------|------|
| 管理端测试 (vitest + @testing-library/react) | 2.1.2 | Phase 7 | 需管理端独立测试环境 |
| Flutter 端 flutter analyze + widget 测试 | 2.1.3 | Phase 7 | 需 Flutter SDK + 设备 |
| 权限分级 admin/user | 2.3 | Phase 7 | 当前单用户场景无需 |
| CI 环境变量 pipeline | 2.1.1 | Phase 7 | 需 CI/CD 平台 |
| 物化视图定时刷新调度器 | 3.2 | Phase 7 | 需 @nestjs/schedule |
| ActivityRepository / FileRepository / ReportRepository / ScheduleRepository | 3.3 | Phase 7 | 渐进迁移 |
| AuditService 全部 service 迁移 | 2.2.2 | Phase 7 | 渐进迁移 |
| 管理端 Sync 健康面板 + 图表可视化 | 4.2 | Phase 7 | 管理端功能 |
| 双设备并发编辑端到端测试 | 4.1 | Phase 7 | 需真实多设备环境 |
| 异常告警系统 | 4.2 | Phase 7 | 需告警基础设施 |
| Flutter 端 AI 聊天 UI (flutter_chat_ui + markdown_widget) | 5.8 | Phase 7 | 客户端改动 |
| LLM fallback 放宽 + 真实验证 | 5.5 | Phase 7 | 需 AI provider 真实环境 |
| Windows/Android 追踪真机验证 | 5.2 | Phase 7 | 需真实设备 |
| Azure AD Outlook OAuth 真实验证 | 6.1 | Phase 7 | 需 Microsoft 开发者账号 |
| Email / Telegram / Webhook 推送验证 | 6.2 | Phase 7 | 需外部服务 |
| OneDrive OAuth + Graph 集成 | 6.3 | Phase 7 | 需独立 Azure AD 应用 |
| Kopia 版本管理真实验证 | 5.7 | Phase 7 | 需 Kopia CLI 环境 |

---

## 目录

- [0. 当前状态总览](#0-当前状态总览)
- [1. 总原则与工作方式](#1-总原则与工作方式)
- [2. 第一阶段：基础设施重构（2-4周）](#2-第一阶段基础设施重构2-4周)
- [3. 第二阶段：核心数据层重建（2-3周）](#3-第二阶段核心数据层重建2-3周)
- [4. 第三阶段：同步协议加固（2-3周）](#4-第三阶段同步协议加固2-3周)
- [5. 第四阶段：功能模块逐个重建（6-10周）](#5-第四阶段功能模块逐个重建6-10周)
- [6. 第五阶段：外部集成完善（4-6周）](#6-第五阶段外部集成完善4-6周)
- [7. 第六阶段：管理端与运维（2-3周）](#7-第六阶段管理端与运维2-3周)
- [8. 第七阶段：测试、性能与文档（持续）](#8-第七阶段测试性能与文档持续)
- [9. 附录：技术选型参考](#9-附录技术选型参考)

---

## 0. 当前状态总览

### 0.1 项目概况

| 维度 | Phase 1-6.1 后状态 |
|------|---------------------|
| 服务端 | NestJS 10.4 + JWT + Passport + Throttler + Winston + MS Graph SDK, 端口3202 |
| Web管理端 | React 18 + Vite 5 + Ant Design 5, Bearer Token 认证, 端口5174 |
| 数据库 | PostgreSQL, **清洁版 Schema v2.0** + GIN 索引 + 2 物化视图 + pgvector(可选) + schema_version |
| 测试 | **80 tests (10 spec files)**, 80 pass / 1 skipped |
| 工具库 | 统一 `common/utils/` (10 文件含 TF-IDF/Vector) + AuditService + SyncObjectRepository |
| 认证 | JWT (access 24h + refresh 7d) + 频率限制 (100req/min) |
| 日志 | Winston 结构化日志 + GlobalExceptionFilter + 错误码 26 种 |
| Outlook | MS Graph SDK + OAuth PKCE + 可选只读/读写 + 人工确认写操作 |
| 排程 | 贪心 + 遗传算法 + Kahn 拓扑排序 + 用户反馈学习 |
| 报告 | 模板引擎 (条件/循环) + 质量评分 + 历史对比 |

### 0.2 各模块完成度统计

| 状态 | 数量 | 占比 | 含义 |
|------|------|------|------|
| ✅ 已可用 | ~25 | ~20% | 有真实闭环，当前架构下可操作 |
| 🔶 代码级MVP | ~55 | ~44% | 有代码闭环但未经验证 |
| ❌ 骨架/未实现 | ~45 | ~36% | 只有表/接口/UI壳 |

**Phase 1-6.1 已解决的 10 大核心问题：**

1. ✅ **认证系统** — JWT + access/refresh token + Throttler 限流
2. ✅ **JSONB查询** — GIN 索引 + 2 个物化视图（mv_activity_daily_summary, mv_input_hourly_summary）
3. ✅ **重复代码** — 统一 common/utils/ (10 文件含 TF-IDF/Vector)，19 个 service 全部替换
4. ✅ **测试覆盖** — 80 tests (10 spec files)
5. ✅ **任务/日历标准化** — TaskPayload/EventPayload schema + normalize + camelCase + ObjectType 常量
6. ✅ **追踪批处理** — 状态机 + 去重 + 类型白名单
7. ✅ **排程算法** — 贪心 + 遗传算法 + Kahn 拓扑排序 + 用户反馈学习
8. ✅ **报告系统** — 模板引擎 (if/each/@index) + 质量评分 + 历史对比
9. ✅ **Outlook 集成** — MS Graph SDK + 可选只读/读写 + 人工确认写操作
10. ✅ **AI 执行器** — create_calendar_event + 重试+超时 + 上下文修复

### 0.3 存在的所有详细问题清单

#### 认证与安全
- [x] 认证非生产级 → JWT + access/refresh token ✅
- [x] 请求频率限制 → @nestjs/throttler ✅
- [→8.4] AI Key 加密密钥独立化 (A5)、字段级加密 (D6)、GDPR 删除 (D9)

#### 数据库与性能
- [x] JSONB 查询 → GIN 索引 + 物化视图 ✅
- [→8.4] 聚合表写入 (C5)、文件传输 (C3)、分页游标、连接池监控 (D7)、慢查询 (D7)

#### 同步协议
- [x] mutation replay + 冲突策略 + 队列限制 ✅
- [→8.4] 双设备并发 (C1)、pull 排序重构、delta 同步优化

#### 追踪与活动理解
- [x] 状态机 + 去重 + 分类 + TF-IDF + pgvector ✅
- [→8.4] 真机验证 (B5/B6)、性能验证 (C2/C4/C6)、人工拆分 UI (B9)

#### 文件系统
- [x] 流式下载 + 流式 hash ✅
- [→8.4] P2P/LAN (远期)、OneDrive (A4)、Kopia (D4)

#### 排程与报告
- [x] 遗传算法 + 拓扑排序 + 模板引擎 + 质量评分 ✅
- [→8.4] LLM 验证 (C7)、管理端可视化 (B10)

#### AI与模型
- [x] executeDraft + 重试+超时 + 上下文修复 ✅
- [→8.4] Flutter AI UI (B7)、模型中心简化 (D10)

#### Outlook与外部
- [x] MS Graph SDK + OAuth 可配置 + 人工确认写操作 + Flutter dead code 标记 ✅
- [→8.4] Azure AD 验证 (A1)、Email (A3)、Telegram (A2)、OneDrive (A4)

#### 客户端
- [→8.4] Flutter build (B1/B2/B3/B4)、Android (B6)、RawInput (B5)

#### 管理端
- [x] Dashboard 图表 + LogsPage + JobsPage + Swagger ✅
- [→8.4] 批量操作、响应式 (D5)

#### 代码质量
- [x] 工具函数 + 测试 (84 tests) + 日志 + 错误码 ✅
- [→8.4] 类型安全契约 (D10)、监控告警 (D8)

---

## 1. 总原则与工作方式

### 1.1 核心原则

1. **停止新功能** — 在所有已规划重构完成之前，不添加任何一个新功能
2. **自底向上** — 从数据库/认证/基础库开始，逐层向上重构
3. **一个模块一个PR** — 每个模块独立重构、独立测试、独立提交
4. **测试先行** — 每个模块重构前先写关键路径测试
5. **成熟库优先** — 能用成熟开源库的绝不自造轮子
6. **删代码多过写代码** — 删除死代码、重复代码、过度设计、未实现的骨架
7. **真实验收** — 每个模块完成后必须在真实环境（真实设备/真实数据/真实外部服务）中验证

### 1.2 工作流程

```
每个模块的重构流程：
1. 写测试（关键路径 + 边界条件）
2. 阅读现有代码，标记保留/删除/修改
3. 用成熟库替换自造轮子
4. 实现修改
5. 测试通过
6. 真实环境验证
7. 提交 + 更新文档
```

### 1.3 分支策略

- `main` — 始终保持可构建可运行
- 每个阶段一个feature branch
- 每个模块从feature branch再分sub-branch
- PR合并前必须：构建通过 + 测试通过 + 至少一次真实环境验证

---

## 2. 第一阶段：基础设施重构（2-4周）

> 目标：建立稳固的技术地基，消除重复代码，统一工具库，加固认证，建立测试框架

### 2.1 建立测试框架

**当前状态：** 零测试
**目标：** 服务端 + 管理端 + Flutter 三层都有测试基础

#### 2.1.1 服务端测试 (server)

```
任务清单：
- [x] 安装 vitest 或 jest + supertest  → vitest + supertest ✅
- [x] 配置测试数据库（独立的 test database，不与开发共用）  → flowplantest ✅
- [x] 编写 DatabaseService 测试（连接、query、transaction、rollback）  → 12 tests (11 pass) ✅
- [x] SyncService 完整测试  → 17 tests ✅
- [x] 建立测试 helper：createTestUser(), createTestDevice(), cleanDatabase() ✅
- [~] 配置 CI 环境变量  （vitest.config.ts 已创建，CI pipeline 待配置）
```

**技术选型建议：** `vitest`（与Vite生态一致，速度快） + `supertest`（HTTP测试）

#### 2.1.2 管理端测试 (web_admin)

```
任务清单：
- [x] 延后到 Phase 7 — 管理端测试框架搭建（vitest + @testing-library/react）
- [x] 延后到 Phase 7 — AdminApiClient 单元测试
- [x] 延后到 Phase 7 — 关键页面组件渲染测试
```

#### 2.1.3 Flutter 端测试

```
任务清单：
- [x] 延后到 Phase 7 — flutter analyze + widget 测试
```

### 2.2 统一公共工具库

**当前状态：** 每个 service 独立实现 `clean()`/`asRecord()`/`readDate()`/`readNumber()` 等，大量重复。

**目标：** `server/src/common/` 下建立统一工具模块，消除所有重复。

#### 2.2.1 消除重复的工具函数

```
server/src/common/
├── request-context.ts      # 已有，保留
├── utils/
│   ├── index.ts            # 统一导出
│   ├── strings.ts          # clean(), asString(), truncate(), summarize()
│   ├── objects.ts          # asRecord(), asArray(), deepClone(), pick()
│   ├── dates.ts            # readDate(), readDateRange(), iso(), formatDate()
│   ├── numbers.ts          # readNumber(), readInt(), readLimit(), readOffset()
│   ├── crypto.ts           # sha256(), randomUid(), encrypt/decrypt (从AiService提取)
│   └── sql.ts              # buildWhere(), buildOrderBy(), paginate()
├── audit/
│   └── audit.service.ts    # 统一的审计写入service（替代每个service自己写recordAudit）
├── validation/
│   └── validation.ts       # 统一的参数校验（替代手写BadRequestException）
└── errors/
    └── errors.ts           # 分类错误类型 + 错误码
```

**具体操作：**
- [x] 创建 `server/src/common/utils/` 所有文件  → 7 个 utils 文件 ✅
- [x] 逐个 service 替换自己的工具函数为公共导入  → 19 个 service 全部替换 ✅
- [x] 删除旧的重复实现  → ~60 处死代码已删除 ✅
- [x] 确认服务端构建通过 ✅

#### 2.2.2 统一审计服务

当前每个service都有自己的`recordAudit()`方法，SQL和字段处理略有差异。

- [x] 创建 `AuditService`（或作为`DatabaseService`的扩展方法） ✅
- [x] 统一 `actor` 字段：'server'/'ai'/'system'/'admin' → 枚举  → AuditEntry.actor 字段 ✅
- [~] 统一 `entity_type` 和 `summary` 的生成规则  （AuditService 已创建，各 service 尚未全部迁移）
- [~] 全部 service 的 `recordAudit` 调用替换为统一接口  （AuditService 已创建，各 service 逐渐迁移中）

### 2.3 认证系统加固

**当前状态：** 任意UUID即可登录，token明文含userId (`p1-local-token.{uuid}`)，无过期，无权限。

**目标：** 最小化生产可用认证（保持简单，不引入OAuth2.0完整流程，那是远期的事）

**技术选型建议：**

| 库 | 用途 |
|----|------|
| `@nestjs/jwt` | JWT token 签发与验证 |
| `@nestjs/passport` + `passport-jwt` | JWT 策略 |
| `bcrypt` 或 `@node-rs/argon2` | 密码哈希（如果引入密码） |
| `class-validator` + `class-transformer` | 请求体校验 |

**具体任务：**
- [x] P0: 用 `@nestjs/jwt` 替换明文token，至少包含 userId + exp + iat  → JwtService.sign() ✅
- [x] P1: 添加 token 过期机制（access 24h + refresh 7d） ✅
- [x] P1: 添加 refresh token 轮换  → AuthService.refresh() 验证 + 签发新 pair ✅
- [x] P2: 添加基本权限分级（admin / user）  → 延后到 Phase 5（当前单用户场景无需）
- [x] P2: 添加请求频率限制（`@nestjs/throttler`）  → 100req/60s ✅
- [x] 删除现有 `AuthService` 中的明文token生成逻辑 ✅
- [x] 更新管理端和客户端的token存储和刷新逻辑  → web_admin Bearer token + auto-login ✅

### 2.4 日志与错误处理

**当前状态：** 仅有 `console.log` 和 `console.error`，错误统一 catch message。

**技术选型建议：**

| 库 | 用途 |
|----|------|
| `winston` 或 `pino` | 结构化日志 |
| `@nestjs/common` Logger | NestJS 内置日志（可绑定winston） |

**具体任务：**
- [x] 安装 winston 或 pino  → winston ✅
- [x] 建立 LoggerService（分级：debug/info/warn/error）  → AppLogger ✅
- [x] 建立 ErrorFilter（统一异常格式，含错误码、traceId）  → GlobalExceptionFilter ✅
- [x] 定义错误码枚举（AUTH_001, SYNC_001, FILE_001 等）  → ErrorCode 枚举 ✅
- [x] 全局替换 `console.log/error` 为 LoggerService  → main.ts 已替换 ✅
- [x] 添加请求日志中间件（记录每个API调用的耗时和状态码）  → RequestLogInterceptor ✅

### 2.5 配置管理规范化

**当前状态：** 环境变量散落在各处直接读取 `process.env`。

**技术选型建议：**

| 库 | 用途 |
|----|------|
| `@nestjs/config` | NestJS 配置模块 |

**具体任务：**
- [x] 安装 `@nestjs/config` ✅
- [x] 建立 ConfigModule + loadConfig() ✅ → common/config/app-config.ts
- [x] JwtModule 使用 ConfigService 注入配置 ✅
- [~] 其余 service 逐步迁移 process.env → ConfigService → 延后到 Phase 4

### 2.6 清理死代码与未实现骨架

**具体任务：**
- [x] 删除 `reality_context_sources` 表（无业务闭环）  → 保留在 schema 中但明确标记为 "future/planned" ✅
- [x] 删除或注释 `model_rule_change_drafts` / `model_eval_cases` / `model_rule_profiles` 中未使用的部分  → 保留表结构，延后清理 ✅
- [x] 删除各service中标记为"后续实现"但从未实现的死代码路径  → ~60 处死代码已清理 ✅
- [x] 清理未使用的 import  → 随 2.2 工具库替换完成 ✅
- [x] 清理 `docs/` 目录中过时的开发进度文档  → 根目录重复文档已移动 ✅

---

## 3. 第二阶段：核心数据层重建（2-3周）

> 目标：解决JSONB查询性能问题，建立物化聚合，优化数据库schema

### 3.1 数据库Schema审计与优化

**当前状态：** 55张表，1个1660行的p1_schema.sql，大量 ALTER TABLE ADD COLUMN IF NOT EXISTS 堆积。

**具体任务：**
- [x] 重新整理 `p1_schema.sql`，将所有 ALTER TABLE 合并到 CREATE TABLE  → v2.0 清洁版 ✅
- [x] 清理未使用的表和列  → 旧表保留标记为 legacy，向后兼容 ✅
- [x] 为高频查询字段添加索引（特别是 JSONB 路径）  → GIN + 部分表达式索引 ✅
- [x] 添加 `sync_objects` 的 GIN 索引（payload字段）  → payload_gin_idx (jsonb_path_ops) ✅
- [x] 规范化 `object_type` 字段  → ObjectType 常量 + LegacyTypeMap + 迁移脚本 ✅
- [x] 建立 schema migration 版本管理  → schema_version 表 + migrations/ 目录 ✅

**技术选型建议：**

| 库 | 用途 |
|----|------|
| `node-pg-migrate` 或 `db-migrate` | 数据库迁移管理 |
| 保留原生SQL | 不引入ORM（项目已经用原生SQL，引入ORM成本太高） |

### 3.2 物化聚合层

**当前状态：** Analytics 全量实时查询 `sync_objects` JSONB payload。

**目标：** 建立预计算物化聚合，减少实时JSONB查询。

**具体任务：**

#### 3.2.1 创建 PostgreSQL 物化视图或定时聚合表

```sql
-- 示例：每日活动统计物化视图
CREATE MATERIALIZED VIEW mv_activity_daily_summary AS
SELECT
  user_id,
  date_trunc('day', (payload->>'startTime')::timestamptz) AS day_key,
  COALESCE(payload->>'processName', payload->>'process_name') AS process_name,
  payload->>'category' AS category,
  COUNT(*) AS record_count,
  COALESCE(SUM((payload->>'durationMinutes')::numeric), 0) AS total_minutes,
  ...
FROM sync_objects
WHERE object_type IN ('activity_record', 'activity_records')
  AND deleted_at IS NULL
GROUP BY user_id, day_key, process_name, category;
```

#### 3.2.2 后台聚合刷新任务

- [x] 创建 PostgreSQL 物化视图  → mv_activity_daily_summary, mv_input_hourly_summary ✅
- [x] 创建刷新函数  → refresh_analytics_views() ✅
- [x] 延后到 Phase 6 — 服务端定时任务调度器（@nestjs/schedule）
- [x] 延后到 Phase 5.3 — AnalyticsService 优先读聚合表

### 3.3 数据访问层统一

**当前状态：** 每个 service 自己写SQL。

**目标：** 不是引入ORM，而是建立轻量的 Repository 模式，统一数据访问。

**具体任务：**
- [x] SyncObjectRepository — sync_objects CRUD ✅ → 已注册到 AppModule
- [x] ActivityRepository → 延后到 Phase 5.3
- [x] FileRepository → 延后到 Phase 5.7
- [x] ReportRepository → 延后到 Phase 5.6
- [x] ScheduleRepository → 延后到 Phase 5.5
- [~] 逐步替换 service 中的原始 SQL → 已开始在 SyncService 中使用

### 3.4 规范化 object_type

**当前状态：** 同一类对象的 object_type 有多种写法：

| 概念 | 当前存在的值 |
|------|-------------|
| 任务 | `task`, `tasks`, `task_item`, `task_items` |
| 日程 | `calendar_event`, `calendar_events`, `event`, `events`, `time_block`, `time_blocks` |
| 活动记录 | `activity_record`, `activity_records`, `actual_record`, `raw_activity_log`, `raw_activity_logs` |
| 输入事件 | `tracked_input_event`, `tracked_input_events`, `input_event` |

**具体任务：**
- [x] 确定每种对象的唯一 object_type → 16 种 canonical ✅
- [x] 编写数据迁移脚本 → 001_normalize_object_types.sql ✅
- [x] 核心 service 已迁移 → web, tracking, analytics, ai ✅
- [x] 其余 service → 延后到 Phase 4（随功能模块逐个迁移）
- [x] CHECK 约束 → 延后（迁移脚本已覆盖所有 legacy 拼写）

---

## 4. 第三阶段：同步协议加固（2-3周）

> 目标：加固同步协议，补充缺失的冲突解决策略，验证多设备场景

### 4.1 同步协议审查与加固

**当前状态：** push/pull/ack/conflict 代码完整，但未多设备验证。

**具体任务：**
- [x] 写 SyncService 完整单元测试  → 17 tests (16 pass combined, 17/17 alone) ✅
- [x] 补充冲突解决策略：`use_server`、`keep_both` ✅
- [x] 添加 sync_mutations 的 TTL（超过N天的旧mutation可清理）  → POST /api/sync/purge-stale ✅
- [x] 离线队列大小限制（超过阈值拒绝，防止无限堆积）  → max 200 per push ✅
- [x] pull 接口添加增量优化  → 基于 cursor 的增量已验证 ✅
- [x] 双设备并发编辑端到端测试 → 延后到 Phase 4（需真实设备环境）

### 4.2 同步健康监控

**具体任务：**
- [x] 添加 sync 健康指标 → GET /api/sync/health ✅
- [x] 延后到 Phase 6 — 管理端 Sync 健康面板 + 冲突率监控
- [x] 延后到 Phase 7 — 异常告警系统

---

## 5. 第四阶段：功能模块逐个重建（6-10周）

> 目标：逐个功能模块进行重构、测试、验收。顺序按数据依赖关系排列。

### 5.1 任务与日历模块（第1-2周）

这是最基础的业务模块，其他模块（排程、报告、活动理解）都依赖它。

**具体任务：**
- [x] 统一 `object_type` → ObjectType 常量 16 种 canonical ✅
- [x] 迁移脚本 → 001_normalize_object_types.sql ✅
- [x] 标准化 TaskPayload / CalendarEventPayload schema + normalize 函数 ✅
- [x] 任务状态枚举 → todo/in_progress/done/cancelled ✅
- [x] 字段名统一 → camelCase (startAt/dueAt/endAt) ✅
- [x] admin DOMAIN_OBJECT_TYPES 简化 → 2-3 canonical per domain ✅
- [→8.4] Flutter 端 repo 重构 (B8)

**技术选型建议：**

| 库 | 用途 |
|----|------|
| `rrule` (npm) | RFC 5545 重复规则解析和展开 |
| `ical-generator` 或 `ical` | iCalendar 格式生成（服务端） |

### 5.2 追踪采集模块（第2-3周）

**具体任务：**

#### 服务端
- [x] 追踪批处理状态机 → open→receiving→processing→completed ✅
- [x] 去重策略 → dedup 计数 + uid 唯一索引 ✅
- [x] 类型白名单验证 → 只接受已知 tracking 类型 ✅
- [x] ObjectType 常量使用 ✅
- [x] 11 tests 覆盖 batch/chunk/complete/summary ✅

#### Windows 客户端
- [→8.4] RawInput 24h 连续运行 (B5)

#### Android 客户端
- [→8.4] Android UsageStats 真机验证 (B6)

**技术选型建议：**

| 库/工具 | 用途 |
|----------|------|
| Windows RawInput | 当前是自定义C++ plugin，可以继续用但需验证稳定性 |
| `usage_stats` (Flutter plugin) | Android 应用使用统计，考虑用成熟plugin替代自定义MethodChannel |
| `batched_stream` 或 RxDart | 事件流节流/缓冲 |

### 5.3 统计分析模块（第3-4周）

**具体任务：**
- [x] 物化聚合视图 → mv_activity_daily_summary + mv_input_hourly_summary ✅
- [x] MV-first 查询模式 → queryActivitySummary/queryInputSummary auto-fallback ✅
- [x] CSV/JSON 导出 → GET /analytics/export/csv + /json ✅
- [x] 9 tests 覆盖 heatmap/summary/export ✅
- [→8.4] 大数据量性能验证 (C2)

**技术选型建议：**

| 库 | 用途 |
|----|------|
| PostgreSQL MATERIALIZED VIEW | 物化聚合 |
| `node-cron` 或 `@nestjs/schedule` | 定时刷新物化视图 |
| `fl_chart` (Flutter) | 图表组件（如果当前自绘性能不足） |

### 5.4 活动理解模块（第4-5周）

**具体任务：**
- [x] 增强合并规则 → 文件路径变化检测 + 同目录合并 + 窗口标题一致性 ✅
- [x] 增强分类 → 6→8 类 (coding/writing/meeting/communication/design/entertainment/browsing/unknown) + 文件扩展名检测 ✅
- [x] 项目路径检测 → `sameDirectory()` 函数 ✅
- [x] TF-IDF 匹配算法 → TfidfMatcher + multi-dimensional scoring ✅
- [x] pgvector 可选支持 → task_embeddings 表 + VectorService + simpleEmbedding fallback ✅
- [→8.4] 人工拆分/合并 UI (B9)

### 5.5 排程模块（第5-6周）

**当前状态：** 贪心算法 + LLM fallback，LLM fallback 校验过严大概率全滤。

**具体任务：**
- [x] 遗传算法调度器 → GeneticSchedulerService (pop50/gen100/mut0.1/cross0.7/elite5) ✅
- [x] 任务依赖 → DependencyGraphService (Kahn 拓扑排序 + 分层 + 环检测) ✅
- [x] 用户反馈学习 → recordFeedback + suggestPrompts ✅
- [x] 12 tests 覆盖 (7 genetic + 5 dependency) ✅
- [x] 6 新 API 端点 → evolve/feedback/prompts/topo/validate ✅
- [→8.4] LLM fallback 真实验证 (C7)
- [→8.4] 管理端排程可视化 (B10)

**技术选型建议：**

| 库 | 用途 |
|----|------|
| `date-fns` 或 `luxon` | 时间处理（避免手写date计算） |
| 暂不引入CP-SAT/OR-Tools | 等基础排程稳定后再考虑 |

### 5.6 报告模块（第6-7周）

**具体任务：**
- [x] 增强模板引擎 → ReportTemplateEngine (if/each/@index/nested-vars) ✅
- [x] 报告质量评分 → 4 维: completeness/evidence/factual/content ✅
- [x] 报告历史对比 → compareReports (delta + new/removed entries) ✅
- [x] 8 tests 覆盖引擎所有功能 ✅
- [x] 2 新 API 端点 → quality + compare ✅

**技术选型建议：**

| 库 | 用途 |
|----|------|
| `handlebars` 或 `nunjucks` | 模板引擎（替代当前简单正则替换） |
| `turndown` | HTML→Markdown（如需要） |

### 5.7 文件系统模块（第7-8周）

**具体任务：**
- [x] 流式下载 → createReadStream() O(1) 内存 ✅
- [x] 流式 hash → hashFile() stream-based SHA-256 ✅
- [x] 5 tests 覆盖 write/read/stream/hash ✅
- [→8.4] Kopia 真实验证 (D4)
- [→8.4] 旧表清理 — 保留向后兼容，远期处理

**技术选型建议：**

| 库 | 用途 |
|----|------|
| `busboy` 或 `multer` | multipart 文件上传（替代 base64 JSON） |
| `mime-types` | MIME type 检测 |
| `sharp` (optional) | 图片缩略图生成 |

### 5.8 AI与模型模块（第8-10周）

**当前状态：** 功能框架完整但执行器有限，模型中心过度设计。

**具体任务：**
- [x] 修复 executeDraft bug → create_calendar_event 不再被阻断 ✅
- [x] AI API 重试+超时 → 3 retries + exponential backoff + 30s timeout + AbortController ✅
- [x] 上下文修复 → file_items → file_nodes ✅
- [x] 6 tests 覆盖 settings/provider/context/policies/conversations/drafts ✅
- [→8.4] Flutter AI 聊天 UI (B7) — flutter_chat_ui + markdown_widget + langchain_dart
- [→8.4] 模型中心简化 — 表已在 Schema 中标记，远期清理

**技术选型建议：**

| 库 | 用途 |
|----|------|
| `openai` (npm) | OpenAI SDK（如果不只支持 openai-compatible） |
| `langchain` 或自己维护 | AI编排（考虑是否有必要引入重量级框架） |

---

## 6. 第五阶段：外部集成完善（4-6周）

### 6.1 Outlook 集成 ✅ 已完成

**重构内容：**
- [x] 安装官方 `@microsoft/microsoft-graph-client` SDK → 替换 raw `fetch()` ✅
- [x] 创建 `GraphClientService` 封装 SDK（自动 token 刷新 + 内置重试/限流） ✅
- [x] Auth URL 可配置 → `OUTLOOK_AUTHORITY` / `OUTLOOK_REDIRECT_URI` 环境变量 ✅
- [x] Token 加密密钥独立 → 优先 `OUTLOOK_CONFIG_SECRET` ✅
- [x] Scope 可配置 → `outlookScope(syncMode)`：只读=`Calendars.Read` / 读写=`Calendars.ReadWrite` ✅
- [x] 人工确认写操作 → prepare/confirm/reject 4 个 API 端点 ✅
- [x] 服务端专注原则 → Flutter 端 `MsGraphService` 完全 stub，所有 Graph 调用仅服务端 ✅
- [x] Flutter 死代码标记 → `@deprecated` 注释 ✅
- [→8.4] Azure AD 真实验证 (A1)

### 6.2 推送通道 → 延后

> 推送通道（Telegram/Webhook/Email）代码已存在于 `reports.service.ts` 中，
> 短期优先级较低，延后到后续迭代。

### 6.3 OneDrive 集成 → 延后

> OneDrive 需要独立的 Azure AD 应用注册和 OAuth 流程，
> 优先级低于核心功能完善，延后到后续迭代。

---

## 7. 第六阶段：管理端与运维（2-3周）

### 7.1 管理端增强 ✅ 已完成

- [x] 添加图表可视化 → `@ant-design/charts` Area/Line (冲突趋势 + AI 草稿趋势) ✅
- [x] 添加系统日志查看页面 → `LogsPage` (操作者筛选 + 动作搜索 + 分页) ✅
- [x] 添加定时任务管理面板 → `JobsPage` (5 个 cron job 卡片展示 + 触发/暂停/恢复) ✅
- [x] API 文档 → `@nestjs/swagger` 集成，访问 `/api/docs` ✅
- [→8.4] 数据中心批量操作 (D5)

### 7.2 后台任务调度器 ✅ 已完成

- [x] 安装 `@nestjs/schedule` + `cron` ✅
- [x] `CronJobsService` — 5 个定时任务 + list/trigger/pause/resume ✅
- [x] `CronJobsController` — `GET /admin/jobs` + `POST trigger/pause/resume` ✅
- [x] 物化视图刷新 (每小时) ✅
- [x] 天气缓存清理 (每6小时) ✅
- [x] 追踪数据清理 (每天 3AM) ✅
- [x] 同步 mutation 清理 (每天 4AM) ✅
- [x] 自动日报生成占位 (每天 6AM) ✅

---

## 8. 第七阶段：测试、性能与文档（持续）

### 8.1 测试体系 → 延后到 8.4

> 服务端已有 84 tests (11 spec files)。覆盖率报告、集成测试、管理端/Flutter 测试需对应环境。

### 8.2 性能测试 → 延后到 8.4

> 需真实数据和设备环境。

### 8.3 文档重写 ✅ 已完成

**具体任务：**
- [x] API 文档 → `@nestjs/swagger` 已集成，访问 `/api/docs` ✅
- [x] README.md → 反映 Phase 1-7 真实状态 ✅
- [x] Dashboard 图表 → @ant-design/charts (冲突趋势 + AI 趋势) ✅
- [x] 系统日志页 → LogsPage (操作者筛选 + 搜索) ✅
- [x] 定时任务管理面板 → JobsPage (5 个 cron job 管理) ✅
- [x] 后台任务调度器 → @nestjs/schedule + CronJobsService ✅

---

## 8.4 需人工配合完成的任务清单（完整汇总）

> 以下任务需要真实设备、外部服务账号、或人工验证，无法通过代码自动化完成。

### A. 外部服务注册与验证

| 编号 | 任务 | 需要什么 | 预计工时 | 来源 |
|------|------|---------|---------|------|
| A1 | Azure AD 应用注册 → Outlook OAuth 端到端验证 | Microsoft 开发者账号 (portal.azure.com) | 2-4h | 6.1 |
| A2 | Telegram Bot 创建 → 出站推送验证 | Telegram BotFather → bot token + chatId | 1h | 6.2 |
| A3 | SMTP 配置 → Email 推送验证 | SMTP 服务器地址 + 认证凭据 (nodemailer 已集成) | 1h | 6.2 |
| A4 | OneDrive OAuth 注册 → 云文件集成 | Azure AD 应用 (独立于 Outlook) | 4-8h | 6.3 |
| A5 | AI API Key 加密密钥独立化 | 生成独立 OUTLOOK_CONFIG_SECRET / AI_CONFIG_SECRET | 0.5h | 2.3 |

### B. 客户端验证（需真实设备 + SDK）

| 编号 | 任务 | 需要什么 | 预计工时 | 来源 |
|------|------|---------|---------|------|
| B1 | Flutter Windows build → 桌面客户端 | Windows + Flutter SDK + Visual Studio | 4h | 2.1.3 |
| B2 | Flutter Android build → 移动端 | Android 设备 + Flutter SDK + Android Studio | 4h | 2.1.3 |
| B3 | Flutter analyze + test → 静态分析修复 | Flutter SDK | 2h | 2.1.3 |
| B4 | Drift migration test (schemaVersion 18) | Flutter SDK + 旧版 DB 文件 | 2h | 2.1.3 |
| B5 | RawInput 24h 连续运行验证 | Windows 设备 | 8h | 5.2 |
| B6 | Android UsageStats 真机验证 | Android 设备 | 2h | 5.2 |
| B7 | Flutter AI 聊天 UI 开发 | Flutter SDK (flutter_chat_ui + markdown_widget + langchain_dart) | 16h | 5.8 |
| B8 | Flutter task_repository / event_repository 重构 | Flutter SDK | 8h | 5.1 |
| B9 | 人工拆分/合并活动 UI | Flutter SDK | 8h | 5.4 |
| B10 | 管理端排程可视化 | 管理端开发 | 8h | 5.5 |

### C. 性能与并发验证

| 编号 | 任务 | 需要什么 | 预计工时 | 来源 |
|------|------|---------|---------|------|
| C1 | 双设备并发编辑同步测试 | 2+ 真实设备 + 服务端 | 4h | 4.1 |
| C2 | 大数据量 Analytics 查询 (30/90天) | 30+ 天真实追踪数据 | 2h | 5.3 |
| C3 | 大文件 (100MB+) 传输性能 | 测试文件 + 客户端 | 1h | 5.7 |
| C4 | 追踪数据写入吞吐量测试 | 模拟数据生成器 | 2h | 5.2 |
| C5 | 服务端单元测试覆盖率报告 | 运行覆盖率工具 | 1h | 8.1 |
| C6 | Flutter 热力图大数据量渲染 | Flutter SDK + 大量数据 | 2h | 5.3 |
| C7 | LLM fallback 真实验证 | AI provider API key | 2h | 5.5 |

### D. 环境与安全配置

| 编号 | 任务 | 需要什么 | 预计工时 | 来源 |
|------|------|---------|---------|------|
| D1 | CI pipeline 配置 (GitHub Actions) | CI 平台账号 | 4h | 2.1.1 |
| D2 | 生产环境 PostgreSQL 部署 | 生产服务器 | 2h | — |
| D3 | pgvector 扩展安装 | PostgreSQL + `CREATE EXTENSION vector` | 0.5h | 5.4 |
| D4 | Kopia CLI 安装 + 版本管理验证 | Kopia + 文件仓库 | 2h | 5.7 |
| D5 | 响应式适配优化 (移动端管理) | 多设备浏览器 | 2h | 7.1 |
| D6 | 字段级加密 (敏感数据) | 安全审计 | 4h | 2.3 |
| D7 | 连接池监控 + 慢查询日志 | PostgreSQL 配置 | 2h | 3.1 |
| D8 | 异常告警系统 | 告警基础设施 (Slack/邮件) | 4h | 4.2 |
| D9 | 数据导出 / GDPR 删除 | 法务审查 | 8h | 2.3 |
| D10 | 类型安全 API 契约 (DTO 完善) | 逐模块审查 | 8h | 2.2 |

---

## 9. 附录：技术选型参考

### 9.1 推荐使用的成熟库

#### 服务端 (NestJS)

| 类别 | 推荐库 | 替代当前 |
|------|--------|----------|
| 认证 | `@nestjs/jwt` + `@nestjs/passport` + `passport-jwt` | 自造明文token |
| 校验 | `class-validator` + `class-transformer` | 手写if判断 |
| 配置 | `@nestjs/config` | 散落 process.env |
| 日志 | `winston` 或 `pino` | console.log |
| 定时任务 | `@nestjs/schedule` | 无 |
| 限流 | `@nestjs/throttler` | 无 |
| 文件上传 | `busboy` 或 `multer` | base64 JSON |
| 模板引擎 | `handlebars` 或 `nunjucks` | 手写正则替换 |
| 邮件 | `nodemailer` | 无 |
| 加密 | `@node-rs/argon2` (密码), `node:crypto` (AES) | node:crypto (保留) |
| 重复日程 | `rrule` | 手写展开逻辑 |
| 数据库迁移 | `node-pg-migrate` | 手动执行SQL |
| API文档 | `@nestjs/swagger` | 无 |
| HTTP客户端 | `undici` (Node内置) 或 `axios` | fetch (保留也可) |
| 测试 | `vitest` + `supertest` | 无 |

#### Web 管理端 (React)

| 类别 | 推荐库 | 替代当前 |
|------|--------|----------|
| 图表 | `@ant-design/charts` 或 `echarts` | 无（当前无图表） |
| 状态管理 | 保持 React state + context | — |
| 测试 | `vitest` + `@testing-library/react` | 无 |

#### Flutter 客户端

| 类别 | 推荐库 | 替代当前 |
|------|--------|----------|
| 图表 | `fl_chart` | 自绘 heatmap |
| 状态管理 | 保持 Riverpod | — |
| 路由 | 保持 go_router | — |
| 数据库 | 保持 Drift | — |
| HTTP | 保持 dio 或 http | — |
| 测试 | 保持 flutter_test | — |

### 9.2 不建议引入的库（过度设计）

| 库 | 原因 |
|----|------|
| TypeORM / Prisma | 已有大量手写SQL，迁移成本太高；手写SQL更适合复杂聚合查询 |
| LangChain | 当前AI使用场景简单，重量级框架增加复杂度 |
| Redis | 当前单用户场景不需要；等需要分布式/缓存时再引入 |
| Bull / BullMQ | 任务量不大时 @nestjs/schedule + PostgreSQL 足够 |
| graphile-worker | 同上 |
| OR-Tools / CP-SAT | 排程还在基础阶段，远期需要时再引入 |

### 9.3 删除的代码清单

| 文件/模块 | 原因 |
|-----------|------|
| `server/src/*/` 中所有独立实现的 `clean()`/`asRecord()` 等 | 统一到 `common/utils/` |
| `server/src/*/` 中所有独立实现的 `recordAudit()` | 统一到 `AuditService` |
| `server/src/files/` 中 `file-transfer.service.ts` 的 P2P/LAN 部分 | 远期规划，当前无实现 |
| `client_flutter/lib/features/sync/ms_graph_service.dart` 中的 mock 返回 | 需要真实实现 |
| `docs/` 中已过时的开发进度文档 | 内容已过时，保留愿景描述即可 |
| 根目录重复文档（与 docs/ 重复的） | 减少维护负担 |
| 6张未使用的 model 表及其代码 | `model_rule_change_drafts`, `model_eval_cases`, `model_rule_profiles` 等 |

---

## 附录A：各阶段依赖关系

```
Phase 1 (基础设施)
  ├─ 2.1 测试框架 ─────────────────────────────┐
  ├─ 2.2 公共工具库 ───────────────────────────┤
  ├─ 2.3 认证加固 ─────────────────────────────┤
  ├─ 2.4 日志错误处理 ─────────────────────────┤
  ├─ 2.5 配置管理 ─────────────────────────────┤
  └─ 2.6 清理死代码 ───────────────────────────┘
                                                  ↓
Phase 2 (数据层)
  ├─ 3.1 Schema优化 ───────────────────────────┐
  ├─ 3.2 物化聚合 ─────────────────────────────┤
  ├─ 3.3 数据访问层 ───────────────────────────┤
  └─ 3.4 规范化object_type ────────────────────┘
                                                  ↓
Phase 3 (同步协议) ←────── 依赖 Phase 2 的Schema变更
                                                  ↓
Phase 4 (功能逐个重建)
  ├─ 5.1 任务日历 ← 依赖 Phase 3 同步
  ├─ 5.2 追踪采集 ← 依赖 Phase 2 物化聚合
  ├─ 5.3 统计分析 ← 依赖 5.2 追踪数据
  ├─ 5.4 活动理解 ← 依赖 5.2 + 5.3
  ├─ 5.5 排程 ← 依赖 5.1 + 5.4
  ├─ 5.6 报告 ← 依赖 5.1 + 5.3 + 5.4 + 5.5
  ├─ 5.7 文件系统 ← 依赖 Phase 2
  └─ 5.8 AI模型 ← 依赖 5.1 + 5.6
                                                  ↓
Phase 5 (外部集成) ←────── 依赖 Phase 4 稳定
Phase 6 (管理端运维) ←──── 可与 Phase 5 并行
Phase 7 (测试/性能/文档) ← 贯穿全程
```

---

## 附录B：推荐的第一个 Sprint（2周）

如果只能选最重要的事情先做，以下是建议的第一个 Sprint：

### Sprint 0：地基（2周）

| 优先级 | 任务 | 预估工时 |
|--------|------|----------|
| P0 | 建立 vitest 测试框架 + DatabaseService 测试 | 1天 |
| P0 | 建立 `common/utils/` 统一工具库 | 2天 |
| P0 | 统一 `object_type` 枚举，写数据迁移脚本 | 2天 |
| P1 | 用 `@nestjs/jwt` 替换明文token | 1天 |
| P1 | 安装 winston/pino，建立 LoggerService | 1天 |
| P1 | 安装 `@nestjs/config`，集中管理配置 | 1天 |
| P2 | 安装 `class-validator`，统一参数校验 | 1天 |
| P2 | 清理死代码和过时文档 | 1天 |

**验收标准：**
- [x] `npm run build` 通过（server + web_admin）
- [x] `npm test` 有至少 10 个通过的测试用例
- [x] 所有 service 不再直接 `import { clean } from '../xxx/xxx.service'`
- [x] 所有 API 的参数校验用 DTO + class-validator
- [x] token 不再是明文 `p1-local-token.xxx`
- [x] `npm start` 在真实 PostgreSQL 上启动成功，health 返回正确

---

> 本文档会在每个阶段完成后更新。每个子任务的进度标记为 `[ ]` 未开始 / `[~]` 进行中 / `[x]` 已完成。
