# FlowPlan Codex MVP 收口执行指挥文件

> 文件用途：把本文件放到项目根目录。之后只需要按阶段对 Codex 说：
>
> `读取 FLOWPLAN_CODEX_MVP_EXECUTION_PLAN_260430.md，完整完成 A 部分。`
>
> `读取 FLOWPLAN_CODEX_MVP_EXECUTION_PLAN_260430.md，完整完成 B 部分。`
>
> `读取 FLOWPLAN_CODEX_MVP_EXECUTION_PLAN_260430.md，完整完成 C 部分。`
>
> `读取 FLOWPLAN_CODEX_MVP_EXECUTION_PLAN_260430.md，完整完成 D 部分。`
>
> 每次只让 Codex 做一个阶段。不要一次做多个阶段。

---

## 0. 总原则

### 0.1 当前项目判断

FlowPlan 目前不是空壳，但也不是可交付软件。

当前真实状态是：

- 服务端和 Web 管理端已有较完整的代码结构，并且曾经构建通过。
- Flutter 主客户端有本地数据库、路由、Repository、Provider、server API client、Windows/Android 原生通道。
- 但大量能力仍是“代码级 MVP”：看起来有接口、有 UI、有表、有服务，但没有经过真实设备、真实数据、长期运行、多端同步、外部凭据的端到端验收。
- 最大问题不是“缺功能”，而是“主流程没有被保护起来”。

因此从现在开始，Codex 的任务不是继续横向加功能，而是把已有功能收口成可用闭环。

---

## 1. Codex 必须遵守的硬约束

### 1.1 禁止继续新增大功能

在 A/B/C/D 阶段全部完成之前，禁止新增以下内容：

- Telegram 入站自然语言。
- Telegram 内确认操作。
- Webhook 入站自动化。
- QQ / 微信深度入口。
- 系统分享入口。
- OneDrive OAuth / Graph 真实读写。
- Outlook Graph 真实读写。
- 插件系统。
- AI 高风险工具执行器。
- 多路径文件传输、LAN、P2P、TURN。
- 完整 CP-SAT 或全局优化排程。
- 端到端模型训练、微调、长期智能。
- Windows 系统级资源管理器右键菜单。
- 大规模重构架构、重写数据库、替换状态管理框架。

如果 Codex 认为必须新增某个能力，必须先在输出中说明：

1. 为什么不新增就无法完成当前阶段验收；
2. 是否有更小的替代修复；
3. 修改范围；
4. 回滚方式。

没有满足以上说明，不允许新增。

### 1.2 不允许破坏已有主架构

不得删除或绕开以下架构：

- `server/src` NestJS 服务端。
- `client_flutter/lib` Flutter 主客户端。
- `web_admin/src` React 管理端。
- `server/src/database/p1_schema.sql` 业务 schema。
- Flutter 本地 Drift/SQLite 数据库。
- server-first 写入。
- 离线 mutation 队列。
- sync push/pull/ack/conflict 模型。
- Windows RawInput / WindowSensor 原生能力。

允许修复，但不允许推翻重写。

### 1.3 Flutter / Dart 运行约束

Codex 默认不具备稳定运行 Flutter / Dart 的条件。

因此：

- Codex 不应依赖自己执行 `flutter analyze`、`flutter test`、`flutter build` 才能判断完成。
- Codex 可以修改 Flutter 代码。
- Codex 必须输出用户可手动执行的 Flutter 验收命令。
- Codex 必须在不能运行 Flutter 时，提供静态检查依据和人工验证清单。

推荐用户手动执行：

```powershell
cd client_flutter
flutter analyze
flutter test
flutter build windows --debug
flutter build web --debug
flutter build apk --debug --split-per-abi
```

### 1.4 每阶段完成后必须输出

每次完成一个阶段，Codex 必须输出以下内容：

1. 修改了哪些文件。
2. 为什么修改这些文件。
3. 本阶段完成了哪些验收项。
4. 哪些验收项需要用户手动验证。
5. 用户应该执行的命令。
6. 预期结果。
7. 如果失败，应优先查看哪些日志或文件。
8. 没完成的内容和原因。
9. 不允许把“以后再做”伪装成“已完成”。

### 1.5 每次修改范围控制

每阶段只允许修复服务于该阶段闭环的问题。

例如：

- A 阶段只修启动、配置、连接、health、登录、heartbeat。
- B 阶段只修任务、日程、同步、离线队列、冲突。
- C 阶段只修 Windows 追踪、RawInput、前台窗口、日志、上传、analytics。
- D 阶段只修活动理解、实际记录、任务投入、排程、报告。

不得在 A 阶段顺手做 AI、文件、Telegram、OneDrive。
不得在 B 阶段顺手做报告润色。
不得在 C 阶段顺手做插件系统。
不得在 D 阶段顺手做外部平台入口。

---

## 2. 推荐使用方式

### 2.1 第一次给 Codex 的总提示

把本文件放到项目根目录后，先对 Codex 说：

```text
读取 FLOWPLAN_CODEX_MVP_EXECUTION_PLAN_260430.md。
从现在开始冻结新功能，只允许按该文件的 A/B/C/D 阶段收口 FlowPlan。
本次只完整完成 A 部分，不允许修改与 A 部分无关的功能。
完成后输出修改清单、验收清单、手动验证命令、失败排查表。
```

### 2.2 后续阶段提示

A 阶段完成并由用户手动验收后，再说：

```text
读取 FLOWPLAN_CODEX_MVP_EXECUTION_PLAN_260430.md。
A 部分已完成并通过人工验收。
本次只完整完成 B 部分，不允许修改与 B 部分无关的功能。
完成后输出修改清单、验收清单、手动验证命令、失败排查表。
```

B 阶段完成后：

```text
读取 FLOWPLAN_CODEX_MVP_EXECUTION_PLAN_260430.md。
A、B 部分已完成并通过人工验收。
本次只完整完成 C 部分，不允许修改与 C 部分无关的功能。
完成后输出修改清单、验收清单、手动验证命令、失败排查表。
```

C 阶段完成后：

```text
读取 FLOWPLAN_CODEX_MVP_EXECUTION_PLAN_260430.md。
A、B、C 部分已完成并通过人工验收。
本次只完整完成 D 部分，不允许修改与 D 部分无关的功能。
完成后输出修改清单、验收清单、手动验证命令、失败排查表。
```

---

# A 部分：启动、配置、服务端、Web 管理端、Windows 客户端连接闭环

## A.1 阶段目标

让 FlowPlan 在开发环境中具备稳定地基。

A 阶段不追求业务完整，只追求：

- 服务端能启动。
- 数据库能连接。
- schema 能初始化或校验。
- health 能访问。
- Web 管理端能连接服务端。
- 管理端能登录。
- Windows Flutter 客户端能配置服务端地址。
- Windows Flutter 客户端能 heartbeat / bootstrap。
- 管理端能看到设备在线或连接事件。
- 所有失败都有清晰错误提示。

## A.2 允许修改范围

只允许检查和修复：

- `server/src/health/*`
- `server/src/auth/*`
- `server/src/devices/*`
- `server/src/client/*` 中 bootstrap / heartbeat 相关部分
- `server/src/database/*`
- `server/src/app.module.ts`
- `server/package.json`
- `flowplan.local.env.example`
- `start-flowplan-all.cmd`
- `scripts/start-flowplan-all.ps1`
- `web_admin/src/main.tsx` 中连接、登录、health、dashboard 初始加载相关逻辑
- `client_flutter/lib/core/server_api/*`
- `client_flutter/lib/core/bootstrap/*`
- `client_flutter/lib/core/platform/*`
- `client_flutter/lib/shared/providers/*` 中连接状态相关 provider
- `client_flutter/lib/features/settings/*` 中服务端连接配置相关 UI
- README 或新增 `docs/dev_startup_checklist.md`

如果必须修改其他文件，Codex 必须说明原因。

## A.3 禁止事项

A 阶段禁止：

- 新增业务功能。
- 新增 AI 能力。
- 新增文件同步能力。
- 新增 Telegram / Outlook / OneDrive / Webhook。
- 重构整个 Flutter 路由。
- 重写数据库 schema。
- 修改任务/日程业务语义。
- 修改追踪采集逻辑。
- 修改报告生成逻辑。

## A.4 具体任务

### A.4.1 检查服务端启动链路

Codex 应检查：

- `server/package.json` 是否存在明确启动脚本。
- `server/src/app.module.ts` 是否正确加载核心 module。
- `DATABASE_URL` 缺失时是否有清晰报错。
- 数据库连接失败时是否有清晰报错。
- `/api/health` 是否不依赖复杂外部条件即可返回。
- health 返回内容是否包含足够定位信息。

最低要求：

- 服务端启动失败不能只显示无意义 stack trace。
- health 不能因为非核心外部功能缺配置而整体失败。

### A.4.2 检查数据库 schema 初始化/校验

Codex 应检查：

- 是否有清晰命令用于执行 `server/src/database/p1_schema.sql`。
- schema 初始化失败时是否能定位到具体 SQL 或连接错误。
- README / 文档 / 启动脚本是否说明 `DATABASE_URL` 格式。

如果缺少命令，允许新增或修复：

```bash
npm run db:schema
```

或同等脚本。

### A.4.3 检查 Web 管理端连接

Codex 应检查：

- 管理端是否能配置 API base URL。
- base URL 是否保存到 localStorage。
- token / userId / deviceId 是否保存和读取一致。
- `/api/health` 失败时 UI 是否明确显示原因。
- 登录失败时 UI 是否显示状态码和错误信息。
- dashboard 初始加载失败是否会导致白屏。

### A.4.4 检查 Flutter Windows 连接配置

Codex 应检查：

- Flutter 客户端是否能设置服务端 base URL。
- 启动时是否读取已有配置。
- 无服务端时是否进入可操作状态，而不是崩溃。
- 服务端在线时是否能执行 bootstrap。
- heartbeat 是否携带稳定 deviceId。
- heartbeat 失败是否有可见状态。

### A.4.5 检查设备在线链路

Codex 应检查：

- 服务端 heartbeat 是否写入 `devices`。
- 服务端 heartbeat 是否写入 `device_connection_events` 或等价连接日志。
- 管理端是否能看到设备摘要。
- 设备 ID 是否不会每次启动都随机变化，除非明确设计如此。

## A.5 A 阶段验收标准

A 阶段完成后，用户应能做到：

1. 配置 `flowplan.local.env`。
2. 初始化或校验数据库 schema。
3. 启动服务端。
4. 浏览器访问 `/api/health` 得到正常响应。
5. 启动 Web 管理端。
6. 在管理端配置 API base URL。
7. 登录管理端。
8. 管理端 dashboard 不白屏。
9. 启动 Windows Flutter 客户端。
10. 在 Flutter 客户端配置同一个 API base URL。
11. Flutter 客户端显示服务端已连接或可诊断状态。
12. 管理端能看到至少一个设备 heartbeat / online summary / connection event。

## A.6 A 阶段建议手动命令

Codex 完成后必须根据实际项目脚本调整以下命令。

服务端：

```powershell
cd server
npm install
npm run build
npm run db:schema
npm run start:dev
```

Web 管理端：

```powershell
cd web_admin
npm install
npm run build
npm run dev
```

Flutter Windows：

```powershell
cd client_flutter
flutter analyze
flutter build windows --debug
flutter run -d windows
```

健康检查：

```powershell
curl http://localhost:3000/api/health
```

如果端口不是 3000，应以项目实际配置为准。

## A.7 A 阶段失败排查表

| 现象 | 优先排查 |
| --- | --- |
| server 启动失败 | `DATABASE_URL`、依赖安装、端口占用、schema 是否存在 |
| `/api/health` 失败 | 服务端是否启动、全局 prefix 是否为 `/api`、数据库连接 |
| Web 管理端白屏 | 浏览器 console、API base URL、登录 token、dashboard 请求失败 |
| 管理端登录失败 | auth API、数据库 users、默认账号、请求路径 |
| Flutter 无法连接服务端 | base URL、Windows 防火墙、代理、localhost 与局域网地址差异 |
| 设备不在线 | heartbeat 是否调用、deviceId 是否稳定、服务端是否写 devices |

## A.8 A 阶段完成输出模板

Codex 完成 A 阶段后，必须按以下格式输出：

```text
A 部分完成报告

1. 修改文件：
- ...

2. 修复内容：
- ...

3. 已静态确认：
- ...

4. 已运行验证：
- ...

5. 需要用户手动验证：
- ...

6. 用户执行命令：
- ...

7. 预期结果：
- ...

8. 失败排查：
- ...

9. 未完成项：
- 无 / ...
```

---

# B 部分：任务、日程、server-first、离线同步、冲突闭环

## B.1 阶段目标

让 FlowPlan 成为一个可信的任务 / 日程软件。

B 阶段目标不是做复杂 UI，而是证明：

- Windows 客户端能创建任务。
- Windows 客户端能创建日程。
- 服务端能收到任务和日程。
- 管理端能查看任务和日程。
- 断网写入能进入离线队列。
- 恢复网络后能 push。
- 服务端变化能 pull 回客户端。
- 双端冲突不会静默覆盖。
- 冲突能被看见和处理。

## B.2 允许修改范围

只允许检查和修复：

- `server/src/client/*`
- `server/src/sync/*`
- `server/src/web/*` 中 tasks/events 相关部分
- `server/src/admin/*` 中 data/tasks/schedules/sync/conflicts 相关部分
- `client_flutter/lib/core/server_first/*`
- `client_flutter/lib/core/offline_queue/*`
- `client_flutter/lib/core/sync/*`
- `client_flutter/lib/core/server_api/*`
- `client_flutter/lib/features/task/*`
- `client_flutter/lib/features/calendar/*`
- `client_flutter/lib/core/database/*` 中任务、日程、同步状态、离线队列相关表
- `web_admin/src/main.tsx` 中任务、日程、同步、冲突数据查看相关部分
- 必要的测试脚本或验证文档

## B.3 禁止事项

B 阶段禁止：

- 做 AI 排程。
- 做报告。
- 做文件同步。
- 做 Telegram/OneDrive/Outlook。
- 做追踪采集。
- 改动 Windows 原生 RawInput。
- 重构整个 sync 模型。

## B.4 具体任务

### B.4.1 任务 CRUD 闭环

Codex 应检查：

- 任务创建 UI 是否调用正确 repository。
- repository 是否优先 server-first 写入。
- server-first 失败是否进入 offline mutation。
- 服务端 `/client/tasks` 是否写入 `sync_objects`。
- 服务端是否写 `sync_changes`。
- 管理端是否能通过 admin data 查看任务。
- 修改、完成、删除任务是否同样走一致链路。

验收必须覆盖：

- 创建任务。
- 修改标题。
- 修改时间或计划字段。
- 标记完成。
- 删除或归档。

### B.4.2 日程 CRUD 闭环

Codex 应检查：

- 日程创建 UI 是否调用正确 repository。
- 日程写入是否进入 `/client/events` 或等价 server-first 接口。
- 服务端是否写 `calendar_event` 类型对象。
- 管理端是否能查看日程。
- 删除日程是否同步到服务端。

验收必须覆盖：

- 创建普通日程。
- 创建阻挡日程，如果已有字段支持。
- 修改开始/结束时间。
- 删除日程。

### B.4.3 离线队列闭环

Codex 应检查：

- 网络失败时是否进入 `offline_mutations`。
- pending mutation 是否有明确状态。
- 恢复网络后是否自动或手动 push。
- push 成功后本地状态是否更新。
- push 失败是否保留错误原因，不得静默丢弃。

验收场景：

1. 断开服务端或填入错误 API base。
2. 创建一个任务。
3. 确认任务在本地存在。
4. 确认 offline mutation 产生。
5. 恢复正确 API base。
6. 执行同步。
7. 确认服务端和管理端能看到该任务。
8. 确认 offline mutation 不再 pending。

### B.4.4 Pull / Ack 闭环

Codex 应检查：

- 服务端 `/api/sync/pull` 是否返回客户端缺失变更。
- Flutter apply pull response 是否写入本地任务/日程表。
- apply 成功后是否 ack。
- ack 是否更新服务端 cursor。
- 重复 pull 不应重复创建对象。

验收场景：

1. 通过管理端或 API 修改任务。
2. Windows 客户端执行同步。
3. 本地 UI 显示更新。
4. 再次同步不重复生成对象。

### B.4.5 冲突闭环

Codex 应检查：

- 同一对象同一字段在两个端修改时，是否有冲突检测。
- 冲突不能被静默覆盖。
- 冲突应出现在服务端 `sync_conflicts` 或等价表。
- 管理端或客户端应能查看冲突。
- resolve 后对象状态应一致。

最低验收场景：

1. 客户端 A 创建任务并同步。
2. 客户端 B 拉取该任务。
3. A 离线修改标题为 `A 修改`。
4. B 在线修改标题为 `B 修改` 并同步。
5. A 恢复网络并同步。
6. 系统生成冲突，不能直接覆盖 B 修改。
7. 管理端能看到冲突。
8. 用户选择保留 A 或 B 后，最终对象一致。

如果当前项目没有两个真实客户端，Codex 应提供一个最小 API 级模拟脚本或手动 curl 流程。

## B.5 B 阶段验收标准

B 阶段完成后，用户应能做到：

1. Windows 客户端创建任务。
2. 管理端看到任务。
3. Windows 客户端创建日程。
4. 管理端看到日程。
5. 断网创建任务后恢复网络，任务同步成功。
6. 服务端修改任务后，客户端能拉回。
7. 双端同字段修改产生冲突。
8. 冲突能在管理端或客户端查看。
9. 冲突能解决。
10. 同步状态和错误能被用户看见。

## B.6 B 阶段建议手动命令

```powershell
cd server
npm run build
npm run start:dev
```

```powershell
cd web_admin
npm run build
npm run dev
```

```powershell
cd client_flutter
flutter analyze
flutter run -d windows
```

如果 Codex 新增了 API 级同步验证脚本，应同时给出命令，例如：

```powershell
cd server
npm run test:sync-smoke
```

或：

```powershell
node scripts/sync-smoke-test.js
```

具体以实际实现为准。

## B.7 B 阶段失败排查表

| 现象 | 优先排查 |
| --- | --- |
| 任务本地有、服务端没有 | server-first 是否失败、offline mutation 是否 pending、API base 是否正确 |
| 服务端有、客户端拉不回 | pull cursor、ack、applyPullResponse、本地 object state |
| 离线后任务丢失 | 本地事务、offline mutation 写入、错误处理 |
| 重复同步产生重复任务 | objectId 稳定性、idempotency key、pull apply 去重 |
| 冲突没生成 | version / updatedAt / deviceId / baseRevision 判断逻辑 |
| 冲突生成但看不到 | admin data conflicts、客户端 conflict store、权限或 query |

## B.8 B 阶段完成输出模板

```text
B 部分完成报告

1. 修改文件：
- ...

2. 任务/日程闭环：
- ...

3. 离线同步闭环：
- ...

4. 冲突闭环：
- ...

5. 已运行验证：
- ...

6. 用户手动验证步骤：
- ...

7. 预期结果：
- ...

8. 失败排查：
- ...

9. 未完成项：
- 无 / ...
```

---

# C 部分：Windows 追踪、RawInput、日志、上传、Analytics 闭环

## C.1 阶段目标

让 FlowPlan 真的能记录用户在 Windows 上做了什么。

C 阶段目标：

- Windows 前台窗口采样可用。
- RawInput 键鼠统计可用。
- TrackerService 能稳定运行。
- 本地产生 activity_records / raw_activity_logs / tracked_input_events。
- 本地历史日志可查看。
- 追踪数据可上传服务端。
- 管理端能看到 tracking ingest batch。
- Analytics API 能基于上传数据返回统计。
- 追踪错误不会导致客户端崩溃。

## C.2 允许修改范围

只允许检查和修复：

- `client_flutter/lib/features/tracker/*`
- `client_flutter/lib/core/platform/*`
- `client_flutter/lib/core/server_api/*` 中 tracking/analytics 相关部分
- `client_flutter/windows/runner/raw_input_plugin.cpp`
- `client_flutter/windows/runner/flutter_window.cpp`
- `client_flutter/windows/runner/desktop_shell_plugin.cpp` 中不影响 B 阶段的相关能力
- `server/src/tracking/*`
- `server/src/analytics/*`
- `server/src/admin/*` 中 tracking / analytics 数据查看相关部分
- `web_admin/src/main.tsx` 中 tracking batch、analytics、monitoring 相关部分
- 本地数据库中 activity / input / tracking 相关表和 repository
- 追踪 smoke test 或本地诊断页面

## C.3 禁止事项

C 阶段禁止：

- 做 Android 长期追踪优化。
- 做 AI 活动解释。
- 做报告。
- 做排程。
- 做文件同步。
- 做外部平台。
- 重写整个 tracker 架构。

Android 只允许保持不破坏，不作为本阶段验收核心。

## C.4 具体任务

### C.4.1 Windows 前台窗口采样

Codex 应检查：

- `WindowSensor` 是否能安全捕获前台窗口。
- 捕获失败时是否返回可诊断错误而不是崩溃。
- 标题、进程名、窗口路径等字段缺失时是否兼容。
- FlowPlan 自身窗口是否有污染策略或至少能被识别。

最低验收：

- 切换 VS Code、浏览器、资源管理器，追踪页能看到变化。

### C.4.2 RawInput 键鼠统计

Codex 应检查：

- MethodChannel 名称在 Dart 和 C++ 是否一致。
- `start`、`stop`、`getStats`、`resetStats` 是否可调用。
- RawInput 注册失败是否有错误提示。
- 键盘、鼠标按钮、滚轮、移动统计是否不会出现负数或异常跳变。
- 后台窗口采集是否不会阻塞 Flutter UI。

最低验收：

- 开启追踪后，敲键盘和移动鼠标，输入统计变化。

### C.4.3 TrackerService 稳定运行

Codex 应检查：

- 5 秒采样循环是否可能重复启动。
- stop 后是否真的停止。
- 异常是否被捕获并记录。
- 长时间运行是否导致内存或日志无控制增长。
- 本地写 DB 是否有事务保护。

最低验收：

- 追踪运行 30 分钟不崩。
- 推荐目标：运行 4 小时不崩。
- 最终人工验收：运行 1 天，数据量合理。

### C.4.4 本地日志和历史查看

Codex 应检查：

- activity_records 是否写入。
- raw_activity_logs 是否写入。
- tracked_input_events 是否写入。
- JSONL / 归档如果存在，路径清晰。
- 历史日志页面分页不白屏。
- 空数据状态友好。

### C.4.5 追踪上传

Codex 应检查：

- TrackingUploadService 是否读取 pending 数据。
- `/api/tracking/ingest/batches` 是否创建 batch。
- chunks 上传是否可重试。
- complete 后服务端是否写 tracking_ingest_batches / chunks / sync_objects。
- 上传失败是否保留错误。
- 重复上传是否尽量避免重复统计。

最低验收：

1. 本地采集 10 分钟数据。
2. 执行同步或上传。
3. 服务端创建 ingest batch。
4. 管理端能看到 batch。
5. Analytics 能看到当天数据。

### C.4.6 Analytics API

Codex 应检查：

- `/api/analytics/tracker-home`。
- `/api/analytics/activity-day-summary`。
- `/api/analytics/range-analysis`。
- `/api/analytics/top-apps`。
- `/api/analytics/input-heatmap`。

最低验收：

- 空数据时返回空结构，不报 500。
- 有数据时返回合理统计。
- 时间范围参数错误时返回清晰错误。

## C.5 C 阶段验收标准

C 阶段完成后，用户应能做到：

1. Windows 客户端开启追踪。
2. 切换应用时，前台应用记录变化。
3. 键鼠输入统计变化。
4. 追踪运行至少 30 分钟不崩。
5. 本地历史记录可查看。
6. 上传追踪数据到服务端。
7. 管理端看到 tracking ingest batch。
8. Analytics 页面或 API 返回当天统计。
9. 空数据、失败、无权限时有明确提示。

## C.6 C 阶段建议手动命令

```powershell
cd server
npm run build
npm run start:dev
```

```powershell
cd web_admin
npm run build
npm run dev
```

```powershell
cd client_flutter
flutter analyze
flutter run -d windows
```

可选 API 验证：

```powershell
curl "http://localhost:3000/api/analytics/tracker-home"
curl "http://localhost:3000/api/analytics/activity-day-summary?date=2026-04-30"
curl "http://localhost:3000/api/analytics/top-apps?range=day"
```

路径和参数以实际实现为准。

## C.7 C 阶段失败排查表

| 现象 | 优先排查 |
| --- | --- |
| RawInput 不工作 | MethodChannel 名称、C++ 插件注册、Windows 权限、后台窗口 |
| 前台窗口为空 | Win32 FFI、窗口权限、进程名获取、异常吞掉 |
| 追踪运行一会儿停了 | Timer 重复/取消、异常未捕获、DB 写入失败 |
| 本地有记录但上传失败 | API base、tracking upload service、batch/chunk/complete 接口 |
| 服务端有 batch 但 analytics 为空 | ingest complete 是否写 sync_objects、analytics SQL 时间范围 |
| 日志巨大 | 采样频率、归档策略、重复写入 |

## C.8 C 阶段完成输出模板

```text
C 部分完成报告

1. 修改文件：
- ...

2. Windows 追踪修复：
- ...

3. RawInput 修复：
- ...

4. 本地日志与上传修复：
- ...

5. Analytics 修复：
- ...

6. 已运行验证：
- ...

7. 用户手动验证步骤：
- ...

8. 预期结果：
- ...

9. 失败排查：
- ...

10. 未完成项：
- 无 / ...
```

---

# D 部分：活动理解、实际记录、任务投入、排程、报告闭环

## D.1 阶段目标

让 FlowPlan 从“能记录”变成“能反馈”。

D 阶段目标：

- 追踪数据能构建活动片段。
- 用户能确认 / 拒绝 / 修正活动片段。
- 确认后写入实际记录或任务投入。
- 任务剩余时间能受实际投入影响。
- 排程能基于任务、日程、实际投入生成草案。
- 用户能接受 / 拒绝排程草案。
- 偏离检测能识别计划与实际不一致。
- 报告能读取任务、日程、实际记录、活动片段。
- 用户能生成、编辑、确认日报。

D 阶段不追求“非常智能”，只追求规则 MVP 可用。

## D.2 允许修改范围

只允许检查和修复：

- `server/src/activity-understanding/*`
- `server/src/activity/*`
- `server/src/scheduler/*`
- `server/src/reports/*`
- `server/src/analytics/*` 中被活动理解/报告使用的只读查询
- `server/src/client/*` 中 actual-records 相关接口
- `client_flutter/lib/features/tracker/*` 中 activity review 相关页面
- `client_flutter/lib/features/reports/*`
- `client_flutter/lib/core/server_api/*` 中 activity/scheduler/reports 相关 API
- `client_flutter/lib/core/server_first/*` 中 activity/scheduler 相关 store
- `web_admin/src/main.tsx` 中 reports、actuals、activity、scheduler 数据查看相关部分
- 必要的 smoke test / 回放脚本 / 验证文档

## D.3 禁止事项

D 阶段禁止：

- 接入新的 LLM Provider。
- 做复杂 Agent。
- 做 AI 自动执行高风险操作。
- 做 Telegram / OneDrive / Outlook。
- 做完整 CP-SAT。
- 做模型训练。
- 重写 activity schema。
- 重写 scheduler 架构。

允许使用已有 AI Provider 配置做可选解释，但 D 阶段验收不得依赖外部 AI key。

## D.4 具体任务

### D.4.1 活动片段构建

Codex 应检查：

- `/api/activity-understanding/build-segments` 或等价接口是否能从 tracking 数据构建 segments。
- 空数据时是否返回空结果，不报 500。
- 低质量数据时是否有可解释状态。
- segment 是否包含时间范围、应用/标题、分类、置信度、来源证据。

最低验收：

1. C 阶段已有追踪数据。
2. 调用 build segments。
3. 服务端生成 activity_segments。
4. 客户端或管理端能看到 segments。

### D.4.2 活动确认 / 拒绝 / 反馈

Codex 应检查：

- 用户能确认 segment。
- 用户能拒绝 segment。
- 用户能修改分类或关联任务，如果已有字段支持。
- confirm 后状态更新。
- reject 后不再进入实际记录。
- feedback 能被保存，不得静默丢弃。

最低验收：

- 确认一个工作片段。
- 拒绝一个无关片段。
- 管理端能看到状态变化。

### D.4.3 实际记录和任务投入

Codex 应检查：

- confirmSegment 是否写入 `actual_activity_logs` 或等价实际记录。
- 如果 segment 关联任务，是否写入 `task_work_logs`。
- 重复确认是否幂等，不能重复累加。
- 删除/拒绝后是否避免错误统计。
- 任务详情或管理端能查看实际投入。

最低验收：

1. 创建任务 `写代码 2 小时`。
2. 追踪产生 VS Code 活动片段。
3. 关联并确认到该任务。
4. 任务投入时间增加。
5. 排程时剩余时间减少。

### D.4.4 排程草案生成

Codex 应检查：

- `/api/scheduler/runs` 是否能基于任务和日程生成 run。
- 阻挡日程是否占用时间。
- 已投入时间是否影响剩余工时。
- 锁定任务 / 时间窗 / 拆分限制如果已有字段，应不破坏。
- 无可排时间时返回清晰原因。
- acceptRun 是否写入计划段或日程对象。
- rejectRun 是否记录审计。

最低验收：

1. 有一个明天 1 小时的阻挡日程。
2. 有一个剩余 2 小时任务。
3. 生成排程草案。
4. 草案避开阻挡时间。
5. 接受草案。
6. 客户端或管理端能看到计划段。

### D.4.5 偏离检测

Codex 应检查：

- `/scheduler/deviations/detect` 或等价接口是否能运行。
- 有计划但无实际记录时能生成偏离。
- 实际做了未计划事项时能生成偏离或提示。
- 偏离记录能被报告读取或管理端查看。

最低验收：

- 创建一个计划段。
- 不产生对应实际投入。
- 执行偏离检测。
- 生成 deviation。

### D.4.6 报告 / 日报生成

Codex 应检查：

- 报告生成不依赖外部 AI key。
- 没有 AI key 时可以生成模板报告。
- 报告读取任务、日程、实际记录、活动片段、偏离。
- 报告内容能说明今天做了什么、计划完成如何、偏离在哪里。
- 用户能编辑报告。
- 用户能确认报告。
- 报告 evidence links 如果已有表，应尽量写入。

最低验收：

1. 创建任务和日程。
2. 有至少一个实际活动确认。
3. 有至少一个偏离或完成记录。
4. 生成日报。
5. 日报中包含任务、实际投入、日程、偏离摘要。
6. 编辑并确认日报。
7. 管理端能看到报告。

## D.5 D 阶段验收标准

D 阶段完成后，用户应能做到：

1. 从真实追踪数据构建活动片段。
2. 在 UI 或管理端查看活动片段。
3. 确认活动片段。
4. 拒绝活动片段。
5. 确认后生成实际记录。
6. 关联任务后生成任务投入。
7. 任务剩余时间受投入影响。
8. 生成排程草案。
9. 接受排程草案。
10. 检测计划偏离。
11. 生成日报。
12. 编辑并确认日报。
13. 管理端能查看 actuals、segments、schedule runs、reports。

## D.6 D 阶段建议手动命令

```powershell
cd server
npm run build
npm run start:dev
```

```powershell
cd web_admin
npm run build
npm run dev
```

```powershell
cd client_flutter
flutter analyze
flutter run -d windows
```

可选 API 验证，以实际接口参数为准：

```powershell
curl -X POST "http://localhost:3000/api/activity-understanding/build-segments"
curl "http://localhost:3000/api/activity-understanding/segments"
curl -X POST "http://localhost:3000/api/scheduler/runs"
curl -X POST "http://localhost:3000/api/reports/generate"
```

## D.7 D 阶段失败排查表

| 现象 | 优先排查 |
| --- | --- |
| 构建活动片段为空 | tracking 数据是否上传、时间范围、analytics 查询、segment 构建规则 |
| confirm 后没实际记录 | confirmSegment、actual_activity_logs、事务、幂等判断 |
| 任务投入不增加 | segment 是否关联任务、task_work_logs、任务剩余时间计算 |
| 排程不避开日程 | event recurrence 展开、阻挡字段、时间范围、时区 |
| 报告为空 | reports 查询来源、actuals 是否存在、任务/日程日期范围 |
| 没有 AI key 报告失败 | 报告生成是否强依赖 AI，必须降级模板 |
| 偏离检测无结果 | 计划段、实际记录、检测时间范围 |

## D.8 D 阶段完成输出模板

```text
D 部分完成报告

1. 修改文件：
- ...

2. 活动理解闭环：
- ...

3. 实际记录/任务投入闭环：
- ...

4. 排程闭环：
- ...

5. 报告闭环：
- ...

6. 已运行验证：
- ...

7. 用户手动验证步骤：
- ...

8. 预期结果：
- ...

9. 失败排查：
- ...

10. 未完成项：
- 无 / ...
```

---

# E 部分：A-D 全部完成后的暂缓功能清单

A-D 没完成前，不要碰 E 部分。

以下功能只能在主闭环稳定后再做：

## E.1 外部入口

- Telegram 入站自然语言。
- Telegram 内确认操作。
- Webhook 入站自动化。
- 系统分享入口。
- QQ / 微信辅助入口。

## E.2 外部平台同步

- OneDrive OAuth / Graph。
- Outlook Graph 日历读写。
- Google Calendar。
- 真实云盘双向同步。

## E.3 高级文件能力

- 多路径传输。
- LAN / P2P / TURN。
- 系统级右键菜单。
- 插件式文件后端。
- 生产级对象存储替换。

## E.4 高级 AI / 模型

- AI 高风险工具执行器。
- Agent 自动操作。
- 端到端模型训练。
- 长期个性化学习。
- 完整字段级隐私治理。

## E.5 高级排程

- CP-SAT。
- 全局优化。
- 多目标权重学习。
- 长期习惯预测。

---

# F 部分：Codex 每次动手前必须自查的问题

每次修改前，Codex 必须先在内部回答：

1. 这次修改属于 A/B/C/D 哪一阶段？
2. 是否服务于该阶段验收？
3. 是否会扩大功能面？
4. 是否会破坏之前阶段？
5. 有没有更小的修复方式？
6. 是否需要用户手动验证 Flutter？
7. 如果验证失败，用户应该看哪里？

如果无法回答，不要修改。

---

# G 部分：最终 MVP 定义

A-D 全部完成后，FlowPlan MVP 才算成立。

最终 MVP 是：

> Windows 桌面客户端 + 本地数据库 + 服务端 + Web 管理端，可以完成单用户真实使用闭环：计划任务和日程，离线同步，Windows 行为追踪，活动确认，实际投入，排程反馈，日报总结，管理端可观察。

最终 MVP 不包括：

- 多用户生产权限体系。
- 完整移动端体验。
- 完整 Web 客户端体验。
- 外部平台深度集成。
- 强 AI Agent。
- 云盘真实双向同步。
- 生产级安全合规。

---

# H 部分：一条最重要的规则

任何时候都不要再对 Codex 说：

```text
继续完善 FlowPlan。
```

这会让它继续横向铺功能。

应该说：

```text
读取 FLOWPLAN_CODEX_MVP_EXECUTION_PLAN_260430.md，完整完成 A/B/C/D 部分。只允许做该部分验收所需修改，不允许新增无关功能。完成后输出验收清单和失败排查表。
```

主流程没打穿之前，新增功能都是负债。
