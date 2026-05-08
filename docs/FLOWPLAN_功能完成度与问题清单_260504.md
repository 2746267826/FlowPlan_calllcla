# FlowPlan 功能完成度与问题清单（2026-05-04）

## 0. 项目概况

| 项目 | 详情 |
|---|---|
| 名称 | FlowPlanV2 |
| 版本 | v1.5.0+150 |
| 架构 | 三层：NestJS 服务端 + React 管理端 + Flutter 客户端 |
| 服务端 | NestJS 10.4, TypeScript 5.6, PostgreSQL, 端口 3202 |
| 管理端 | React 18, Vite 5, Ant Design 5, 端口 5174 |
| 客户端 | Flutter 3.5+, Riverpod, Drift/SQLite, Windows/Android/Web |
| 数据库 | PostgreSQL, 40+ 张表 |

---

## 1. 本次代码审查发现并修复的问题

### 1.1 🔴 关键 Bug：`dashboard()` 解构顺序错误

**文件**: `server/src/files/files.service.ts:94`

**问题**: `Promise.all` 返回数组的第 2-4 项与解构变量名不匹配，导致 dashboard API 返回错误数据：

| 解构位置 | 解构名 | 实际查询 | 应该是 |
|---|---|---|---|
| [2] | `transfers` | `file_storage_objects` | ❌ 应为 `storageObjects` |
| [3] | `storageObjects` | `file_version_records` | ❌ 应为 `versionRecords` |
| [4] | `versionRecords` | `file_transfer_sessions` | ❌ 应为 `transfers` |

**修复**: 将解构顺序改为 `storageObjects, versionRecords, transfers` 以匹配查询顺序。

### 1.2 🔴 关键 Bug：缺失方法导致运行时崩溃

**文件**: `server/src/files/files.service.ts:944`

**问题**: Codex 在 `downloadRange` 方法中调用了 `this.resolveSharedDownloadPath()` 和 `this.readLocalFileRange()`，但这两个方法完全不存在，会导致运行时 `TypeError`。

**修复**:
- 新增 `resolveSharedDownloadPath` 方法 — 从 session metadata 解析共享路径，并校验路径属于已注册 root（防路径穿越）
- 新增 `readLocalFileRange` 方法 — 直接从服务器文件系统读取字节范围

### 1.3 🟡 清理死代码

**文件**: `server/src/files/files.service.ts`

**删除的方法**:
- `collectLocalNodesForRoot` — 已迁移到 `file-tree.service.ts`
- `createScannedRootNode` — 已迁移到 `file-tree.service.ts`
- `createScannedNode` — 已迁移到 `file-tree.service.ts`
- `storeScannedFileObject` — 不再需要（共享模式不复制文件）
- `ensureServerRelayCandidate` — 从未被调用
- `appendTransferEventWithClient` — 从未被调用

**清理的 import**: `readdir`, `extname`, `join`, `relative` 不再使用。

---

## 2. 功能完成度矩阵

### A. 基础架构、运行与配置

| 功能 | 平台 | 状态 | 说明 |
|---|---|---|---|
| Flutter Windows/Android 客户端 | Flutter | ✅ 已可用 | 有完整路由、本地 DB、原生通道 |
| NestJS 服务端 | 服务端 | ✅ 已可用 | 16 个 controller、20 个 service、构建通过 |
| Web 管理端 | Web | ✅ 已可用 | 9 个页面、构建通过 |
| 一键启动脚本 | Windows | 🔶 代码级 MVP | cmd/ps1 脚本存在，需实际环境验证 |
| 本地环境配置 | 服务端 | ✅ 已可用 | .env.example + 启动脚本加载 |
| health 接口 | 服务端 | 🔶 代码级 MVP | `/api/health` 可用，phase 只反映代码阶段 |

### B. 认证、设备与连接

| 功能 | 平台 | 状态 | 说明 |
|---|---|---|---|
| 登录/刷新/登出 API | 服务端 | 🔶 代码级 MVP | 非生产级账号系统 |
| 管理端登录态保存 | Web | ✅ 已可用 | localStorage token |
| 设备注册/列表/心跳 | 服务端 | 🔶 代码级 MVP | 多真机未实测 |
| 客户端 heartbeat/bootstrap | Flutter | 🔶 代码级 MVP | 长期心跳未实测 |
| 服务端连接指示器 | Flutter | 🔶 代码级 MVP | 未运行 UI 验证 |

### C. 任务、日程、日历与本地数据

| 功能 | 平台 | 状态 | 说明 |
|---|---|---|---|
| 时间线/周/月视图 | Flutter | ✅ 已可用 | 完整路由和视图组件 |
| 任务 CRUD | Flutter/服务端 | 🔶 代码级 MVP | 多端一致性未实测 |
| 日程 CRUD | Flutter/服务端 | 🔶 代码级 MVP | 复杂重复日程支持有限 |
| 日历本/任务本 | Flutter | 🔶 代码级 MVP | UI 与服务端映射需实测 |
| iCalendar 导入导出 | Flutter | ✅ 已可用 | 有解析器和 UI |
| 数据导入/导出/恢复 | Flutter | 🔶 代码级 MVP | 真实快照冲突未验收 |
| 本地数据库迁移 | Flutter | 🔶 代码级 MVP | schemaVersion 18，未运行迁移 |

### D. 离线同步、冲突与审计

| 功能 | 平台 | 状态 | 说明 |
|---|---|---|---|
| 离线 mutation 队列 | Flutter/服务端 | 🔶 代码级 MVP | 双端真实冲突未实测 |
| 同步 push/pull/ack/status | Flutter/服务端 | 🔶 代码级 MVP | 多设备未验收 |
| 冲突生成与解决 | 全平台 | 🔶 代码级 MVP | 冲突 UI 细节需实测 |
| 审计日志 | 全平台 | 🔶 代码级 MVP | 高频追踪不全审计是设计选择 |
| 管理端运维操作 | Web/服务端 | 🔶 代码级 MVP | 操作类型有限 |

### E. 追踪采集、输入统计与历史日志

| 功能 | 平台 | 状态 | 说明 |
|---|---|---|---|
| Windows 前台窗口采样 | Windows | 🔶 代码级 MVP | 未实际运行长期采样 |
| Windows RawInput 键鼠统计 | Windows | 🔶 代码级 MVP | 真实事件未验收 |
| Android UsageStats 导入 | Android | 🔶 代码级 MVP | 真机长期追踪未验证 |
| 当前会话/今日活动记录 | Flutter | 🔶 代码级 MVP | FlowPlan 自身污染策略需实测 |
| 原始日志 JSONL/按天归档 | Flutter | 🔶 代码级 MVP | 长期保留策略未治理 |
| 历史日志分页查询 | Flutter | ✅ 已可用 | 有分页 UI |
| 输入热力图 | Flutter/服务端 | 🔶 代码级 MVP | 完整尺度需实际确认 |
| 服务端追踪上传 | Flutter/服务端 | 🔶 代码级 MVP | 压缩/断点/去重质量有限 |

### F. 统计聚合与分析

| 功能 | 平台 | 状态 | 说明 |
|---|---|---|---|
| 服务端追踪统计 API | 服务端 | 🔶 代码级 MVP | 真实 SQL 性能未压测 |
| tracker home/day/range/filter | 服务端 | 🔶 代码级 MVP | 结果准确性依赖数据质量 |
| top apps/categories/trends | 服务端 | 🔶 代码级 MVP | 大数据量边界未验证 |
| 客户端本地聚合表 | Flutter | ❌ 只有接口/骨架 | 建表存在但未确认物化聚合 |

### G. 实际记录、活动理解与任务投入

| 功能 | 平台 | 状态 | 说明 |
|---|---|---|---|
| 实际记录表与候选/确认/拒绝 | 全平台 | 🔶 代码级 MVP | 真实冲突流程未全测 |
| 阻挡日程自动候选 | Flutter | 🔶 代码级 MVP | 自动触发链路需实测 |
| 活动片段构建 | 服务端/Flutter | 🔶 代码级 MVP | 规则粗，真实数据校准不足 |
| 活动确认生成实际记录 | 服务端/Flutter | 🔶 代码级 MVP | 人工修正体验需实测 |
| LLM 低频解释/摘要 | 服务端 | 🔶 代码级 MVP | 无真实 provider 时不可用 |
| 工作会话合并/拆分/标注 | Flutter/服务端 | ❌ 只有接口/骨架 | 人工拆分/合并交互不完整 |

### H. 智能排程与计划偏离

| 功能 | 平台 | 状态 | 说明 |
|---|---|---|---|
| 排程草案生成 | 服务端 | 🔶 代码级 MVP | 算法是规则/贪心 MVP |
| 排程确认/拒绝写库与审计 | 服务端 | 🔶 代码级 MVP | 客户端确认 UI 需实测 |
| 实际投入扣减剩余时间 | 服务端 | 🔶 代码级 MVP | 准确性依赖活动确认 |
| 任务锁定/自动排程开关/时间窗 | 服务端 | 🔶 代码级 MVP | schema 约定未完全标准化 |
| 基础周期阻挡日程展开 | 服务端 | 🔶 代码级 MVP | 非完整 RFC RRULE |
| 偏离检测 | 服务端 | 🔶 代码级 MVP | 与报告/重排反馈串联不足 |
| 全局优化/CP-SAT | 服务端 | ❌ 未实现 | 文档明确近期不建议 |

### I. 报告、日记、推送与天气

| 功能 | 平台 | 状态 | 说明 |
|---|---|---|---|
| 日报/周报/月报/专项报告生成 | 全平台 | 🔶 代码级 MVP | 真实日报质量未验证 |
| 报告确认/编辑/润色 | 全平台 | 🔶 代码级 MVP | 无 provider 时只能模板 |
| 自动日记 | 全平台 | 🔶 代码级 MVP | 写作偏好学习未完成 |
| 报告证据链接 | 服务端 | 🔶 代码级 MVP | 证据展示 UX 需实测 |
| Telegram 出站推送 | 服务端 | 🔶 代码级 MVP | 未验证真实 Telegram |
| Telegram 入站自然语言 | 外部 | ❌ 未实现 | 文档明确 P12 未完成 |
| Webhook 出站推送 | 服务端 | 🔶 代码级 MVP | 未真实调用验证 |
| Email 推送 | 服务端 | ❌ 只有接口/骨架 | 没有 SMTP 完整实现 |
| 系统通知 | Flutter | 🔶 代码级 MVP | Windows/Android 权限未实测 |
| 天气位置/刷新/缓存 | 服务端 | 🔶 代码级 MVP | 位置采集未实现 |
| 天气影响排程/报告 | 服务端 | ❌ 只有接口/骨架 | 深度评分未实现 |

### J. 文件上下文、本地文件、云文件与传输

| 功能 | 平台 | 状态 | 说明 |
|---|---|---|---|
| 本地文件夹登记/扫描/文件树 | Flutter/服务端 | 🔶 代码级 MVP | Android 能力弱于 Windows |
| 任务/日程绑定文件夹/文件 | Flutter/服务端 | 🔶 代码级 MVP | 多端路径差异需实测 |
| 文件推荐 | Flutter/服务端 | 🔶 代码级 MVP | 推荐模型仍规则 MVP |
| 最近/常驻文件夹 | Flutter | ✅ 已可用 | 有 UI 和排序逻辑 |
| 文本预览/编辑/保存 | Flutter | ✅ 已可用 | 有交互服务 |
| 系统默认打开/资源管理器定位 | Windows | ✅ 已可用 | 有原生插件 |
| Windows 系统级右键菜单 | Windows | ❌ 未实现 | 文档明确后续阶段 |
| 服务端文件 Provider | 服务端 | 🔶 代码级 MVP | provider 能力声明 |
| 服务端对象存储/分块上传 | 服务端 | 🔶 代码级 MVP | 生产 S3/MinIO 未接入 |
| 范围下载/断点下载 | 服务端 | 🔶 代码级 MVP | 开发期 JSON/base64 |
| **服务端 Drive Root 共享扫描** | **服务端** | **🔶 代码级 MVP** | **本次改进：不再复制文件，直接共享原始路径** |
| 多路径传输/LAN/P2P/TURN | 服务端 | ❌ 只有接口/骨架 | 没有真实 P2P 实现 |
| 云端树快照 | 服务端 | 🔶 代码级 MVP | OneDrive Graph 未真实拉取 |
| OneDrive OAuth/Graph | 外部 | ❌ 未实现 | 文档明确不在本阶段 |
| 本地/云端同一性/hash relink | 全平台 | 🔶 代码级 MVP | 大文件 hash 成本需实测 |
| Kopia snapshot/version refresh | 服务端 | 🔶 代码级 MVP | 未用真实 Kopia 验证 |
| 历史版本列表/下载/恢复 | 服务端 | 🔶 代码级 MVP | 覆盖恢复需二次确认 |
| 文件冲突候选/解决 | 服务端 | 🔶 代码级 MVP | 真实双后端冲突未验证 |

### K. Web 管理端与运维

| 功能 | 平台 | 状态 | 说明 |
|---|---|---|---|
| Dashboard/健康/对象总览 | Web | ✅ 已可用 | **已修复解构顺序 bug** |
| 数据中心 | Web | 🔶 代码级 MVP | 编辑能力按 domain 有限 |
| 同步中心 | Web | 🔶 代码级 MVP | 真实冲突处理需联调 |
| 文件中心管理 | Web | 🔶 代码级 MVP | 管理端不直接打开用户文件 |
| 模型与 AI 管理 | Web | 🔶 代码级 MVP | test 需真实外部 API |
| 报告和推送管理 | Web | 🔶 代码级 MVP | 入站 Telegram 不在此 |
| 设置/远程配置 | Web | 🔶 代码级 MVP | schema 需规范化 |
| 监控日志和 jobs | Web | 🔶 代码级 MVP | 没有完整后台队列系统 |

### L. AI、模型中心与受控工具调用

| 功能 | 平台 | 状态 | 说明 |
|---|---|---|---|
| AI Provider 配置/加密保存/测试 | 全平台 | 🔶 代码级 MVP | 未真实外部调用 |
| 只读上下文摘要 | 服务端 | 🔶 代码级 MVP | 脱敏策略需安全复核 |
| AI 会话/消息 | 全平台 | 🔶 代码级 MVP | Flutter UI 入口不完整 |
| 操作草案与人工确认 | 全平台 | 🔶 代码级 MVP | 可执行工具范围有限 |
| 任务/日程受控写入 | 服务端 | 🔶 代码级 MVP | 高风险工具仍队列/禁用 |
| 文件推荐/重排等高风险 AI 工具 | 服务端 | ❌ 只有接口/骨架 | 未形成完整执行闭环 |
| 模型定义/版本/运行/反馈/学习 | 服务端 | 🔶 代码级 MVP | 学习是浅层规则权重 |
| 端到端训练/微调大模型 | 外部 | ❌ 未实现 | 文档明确近期不建议 |

### M. Outlook、外部入口与生态

| 功能 | 平台 | 状态 | 说明 |
|---|---|---|---|
| Outlook 本地设置页 | Flutter | ❌ 只有接口/骨架 | ms_graph_service 多处返回空 |
| Outlook 对象映射 | 服务端 | 🔶 代码级 MVP | 不代表真实 Graph 读写 |
| Outlook 写入确认/镜像日历 | 外部 | ❌ 未实现 | 未见真实写 Graph |
| 系统分享文本到 FlowPlan | 平台 | ❌ 未实现 | 未见 share intent |
| Telegram Bot 入站 | 外部 | ❌ 未实现 | 只有出站推送 MVP |
| Webhook 入站自动化 | 服务端 | ❌ 未实现 | 出站不等于入站 |
| QQ/微信辅助入口 | 外部 | ❌ 未实现 | 文档明确后置 |
| 插件式文件后端/AI Provider | 服务端 | ❌ 只有接口/骨架 | 没有插件 runtime |
| 本地自动化入口 | Windows | ❌ 未实现 | 未见 automation API |

### N. 现实上下文、隐私治理与长期智能

| 功能 | 平台 | 状态 | 说明 |
|---|---|---|---|
| 位置采样/地点别名 | Android | ❌ 未实现 | 文档明确未完成 |
| 蓝牙连接/STM32 | Android | ❌ 未实现 | 文档明确长期实验 |
| 现实上下文来源表 | 服务端 | ❌ 只有接口/骨架 | 表存在但无业务闭环 |
| 隐私分层/脱敏 | 服务端 | 🔶 代码级 MVP | 需安全审计 |
| 字段级加密 | 全平台 | ❌ 只有接口/骨架 | 不覆盖全部敏感字段 |
| 同步范围开关/保留周期 | 全平台 | ❌ 只有接口/骨架 | 未见统一执行器 |
| 数据导出/删除 | 全平台 | 🔶 代码级 MVP | 服务端完整 GDPR 删除未见 |
| 长期趋势/任务耗时预测 | 服务端 | ❌ 只有接口/骨架 | 不是真正长期智能 |

---

## 3. 状态统计

| 状态 | 数量 | 占比 |
|---|---|---|
| ✅ 已可用 | 12 | ~14% |
| 🔶 代码级 MVP | 50 | ~59% |
| ❌ 只有接口/骨架 | 12 | ~14% |
| ❌ 未实现 | 11 | ~13% |
| **总计** | **85** | **100%** |

---

## 4. 本次改进内容（Drive Root 共享功能）

### 改动文件

| 文件 | 改动说明 |
|---|---|
| `server/src/files/file-tree.service.ts` | 扫描时不再复制文件到 server storage，改为记录原始路径元数据 |
| `server/src/files/files.service.ts` | 新增共享路径下载方法，修复 dashboard bug，清理死代码 |
| `web_admin/src/pages/DriveFilesPage.tsx` | 添加扫描进度轮询和实时展示 |

### 核心变更

1. **扫描不再复制文件** — `file-tree.service.ts` 移除了 `LocalObjectStorageService` 依赖和 `storeScannedFileObject` 方法，扫描结果元数据改为 `source: 'server_shared_root'`, `storageMode: 'shared_server_path'`

2. **下载直接读取原始文件** — `files.service.ts` 新增 `resolveSharedDownloadPath`（含路径穿越校验）和 `readLocalFileRange`，下载时直接从服务器原始路径读取字节范围

3. **修复 dashboard 数据错位** — `Promise.all` 解构顺序与查询不匹配，导致 transfers/storageObjects/versionRecords 三项数据互串

---

## 5. MVP 执行阶段进度（基于 FLOWPLAN_CODEX_MVP_EXECUTION_PLAN）

| 阶段 | 目标 | 当前状态 |
|---|---|---|
| A: 启动/配置/连接闭环 | 服务端启动、管理端登录、Flutter 连接 | 🔶 代码级 MVP，需实际环境验证 |
| B: 任务/日程/同步/冲突闭环 | CRUD + 离线同步 + 冲突检测 | 🔶 代码级 MVP，多设备未验收 |
| C: Windows 追踪/RawInput/上传/Analytics | 采集 + 上传 + 统计 | 🔶 代码级 MVP，长期运行未验证 |
| D: 活动理解/排程/报告 | 片段构建 + 排程 + 日报 | 🔶 代码级 MVP，真实数据未验收 |

---

## 6. 建议下一步验证命令

```powershell
# 服务端
cd server
npm install
npm run build
npm run db:schema
npm run dev

# Web 管理端
cd web_admin
npm install
npm run build
npm run dev

# Flutter 客户端
cd client_flutter
flutter analyze
flutter test
flutter build windows --debug
flutter build web --debug
flutter build apk --debug --split-per-abi
```

---

## 7. 高风险项提醒

1. **多端同步** — 代码级 MVP，未经过真实双设备并发编辑验证
2. **Windows 长期追踪** — 未经过 24 小时连续运行验证
3. **文件共享路径安全** — 本次新增的 `resolveSharedDownloadPath` 含路径穿越校验，但需实际测试
4. **AI Provider** — 无真实外部 API key 时不可用
5. **OneDrive/Outlook** — 未实现真实 OAuth/Graph 流程
6. **Telegram 入站** — 未实现，只有出站推送
