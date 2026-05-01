# FlowPlan A 部分开发启动验收清单

本清单只覆盖 A 部分：启动、配置、数据库连接、health、Web 管理端登录、Flutter Windows 服务端地址、bootstrap、heartbeat 和设备在线摘要。

## 1. 配置本地环境

在项目根目录复制并填写本地配置：

```powershell
Copy-Item flowplan.local.env.example flowplan.local.env
notepad flowplan.local.env
```

`DATABASE_URL` 格式：

```text
DATABASE_URL=postgres://USER:PASSWORD@HOST:5432/DATABASE
```

默认端口：

- server: `3200`
- web_admin: `5173`
- API base URL: `http://localhost:3200/api`

## 2. 初始化或校验数据库 schema

```powershell
cd server
npm install
npm run db:schema
```

预期结果：

- 输出 `FlowPlan P1 schema applied.`
- 如果失败，优先检查 `DATABASE_URL`、PostgreSQL 是否运行、数据库是否存在、当前用户是否有建表权限。

## 3. 启动服务端并检查 health

```powershell
cd server
npm run build
npm run dev
```

另开一个终端检查：

```powershell
curl http://localhost:3200/api/health
```

预期结果：

- 响应包含 `ok`、`service`、`generatedAt`、`checks.database`、`checks.config`、`checks.devices`。
- `checks.database.connected` 为 `true`。
- `checks.database.requiredTables.users/devices/deviceConnectionEvents` 均为 `true`。
- `checks.optional.storage` 和 `checks.optional.models` 标记为 optional，不阻塞 A 部分启动。

## 4. 启动 Web 管理端

```powershell
cd web_admin
npm install
npm run build
npm run dev
```

浏览器打开：

```text
http://localhost:5173
```

在管理端执行：

1. 服务端地址填写 `http://localhost:3200` 或 `http://localhost:3200/api`。
2. 点击保存连接设置。
3. 点击登录。
4. 刷新 dashboard。

预期结果：

- 两种 API base URL 写法都能访问服务端。
- health 失败时显示 HTTP 状态码和错误正文。
- 登录失败时显示 HTTP 状态码和错误正文。
- dashboard 初始加载失败时显示错误块，不白屏。

## 5. 启动 Flutter Windows 客户端

Codex 不依赖 Flutter 命令完成验收，请手动执行：

```powershell
cd client_flutter
flutter analyze
flutter build windows --debug
flutter run -d windows
```

在 Windows 客户端执行：

1. 打开 `设置 -> FlowPlan 服务端同步`。
2. 服务端 API 地址填写 `http://localhost:3200` 或 `http://localhost:3200/api`。
3. 点击保存地址。
4. 点击启动检查并同步，或观察顶部服务端连接指示器。

预期结果：

- 地址会规范化为 `http://localhost:3200/api`。
- 保存后立即重建连接并触发 bootstrap / sync / heartbeat。
- 连接正常时指示器显示在线。
- 连接失败、设备撤销或认证需要处理时，指示器或同步页显示明确错误。

## 6. 验证设备在线摘要

Web 管理端打开同步或设备相关区域，或调用：

```powershell
curl http://localhost:3200/api/health
```

预期结果：

- `checks.devices.devices` 大于等于 1，或管理端设备列表能看到 Windows 客户端。
- heartbeat 成功后，管理端能看到在线、最近心跳或 connection event。

## 7. 失败排查

| 现象 | 优先检查 |
| --- | --- |
| server 启动失败 | `DATABASE_URL`、PostgreSQL 是否运行、端口是否被占用、`npm run db:schema` 是否成功 |
| `/api/health` 中 schema 缺失 | 在 `server` 目录重新运行 `npm run db:schema` |
| Web 管理端不可达 | `web_admin` 是否已 `npm run build`，`npm run dev` 是否启动，5173 端口是否被占用 |
| Web 登录失败 | API base URL、浏览器 console、服务端日志、`/api/auth/login` 返回体 |
| Flutter 无法连接 | 服务端 API 地址、Windows 防火墙、localhost 与局域网地址差异、同步页最近错误 |
| 管理端看不到设备 | Flutter 是否保存了同一 API base URL、heartbeat 是否成功、`device.identity.id` 是否稳定 |
