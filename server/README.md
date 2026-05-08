# FlowPlanV2 Server v2.0.0

> 中文优先·本地优先·三端协同的个人数据管理系统 — 服务端

三层架构：
- **Server** (NestJS + PostgreSQL) — 本仓库
- **Web Admin** (React + Ant Design) — `../web_admin/`
- **Flutter Client** (Windows/Android/Web) — `../client_flutter/`

---

## 快速开始（开发环境）

```bash
# 1. 安装依赖
npm install

# 2. 配置数据库 URL（首次运行前）
# PowerShell:
$env:DATABASE_URL="postgres://postgres:password@localhost:5432/flowplanv2"
# bash:
# export DATABASE_URL="postgres://postgres:password@localhost:5432/flowplanv2"

# 3. 应用数据库 Schema
npm run db:schema

# 4. 启动开发服务器
npm run dev
# → http://localhost:3202/api/health

# 5. 管理端（另一个终端）
cd ../web_admin && npm install && npm run dev
# → http://localhost:5174
```

### 脚本

| 命令 | 说明 |
|------|------|
| `npm run dev` | 开发模式 (watch) |
| `npm run build` | 生产构建 |
| `npm start` | 启动生产服务 |
| `npm test` | 运行全部测试 (88 tests) |
| `npm run test:watch` | 测试 watch 模式 |
| `npm run db:schema` | 应用数据库 Schema |
| `npx vitest run --coverage` | 覆盖率报告 |

---

## API 概览

### 认证
| 端点 | 说明 |
|------|------|
| `POST /api/auth/login` | 登录 → JWT (access 24h + refresh 7d) |
| `POST /api/auth/refresh` | 刷新 Token |
| `POST /api/auth/logout` | 登出 |

### 同步
| 端点 | 说明 |
|------|------|
| `POST /api/sync/push` | 推送离线变更 (max 200/push) |
| `GET /api/sync/pull` | 拉取增量变更 |
| `POST /api/sync/ack` | 确认同步 |
| `GET /api/sync/conflicts` | 列出冲突 |
| `POST /api/sync/conflicts/:id/resolve` | 解决冲突 (4 策略) |
| `GET /api/sync/health` | 同步健康 |
| `POST /api/sync/purge-stale` | 清理旧 mutations |

### 任务与日程
`/api/client/` 和 `/api/web/` 均提供：
`GET/POST tasks` `PATCH/DELETE tasks/:id` `POST tasks/:id/complete`
`GET/POST events` `PATCH/DELETE events/:id`

### AI
| 端点 | 说明 |
|------|------|
| `GET /api/ai/settings` | AI 提供商配置 |
| `GET /api/ai/conversations` | 对话列表 |
| `POST /api/ai/messages` | 发送消息 (retry×3 + 30s timeout) |

### 排程
| 端点 | 说明 |
|------|------|
| `POST /api/scheduler/runs` | 创建排程 |
| `POST /api/scheduler/genetic/evolve` | 遗传算法调度 |
| `POST /api/scheduler/dependency/topo` | 拓扑排序 + 环检测 |

### 报告
| 端点 | 说明 |
|------|------|
| `POST /api/reports/generate` | 生成报告 |
| `GET /api/reports/:id/quality` | 质量评分 (4 维) |
| `GET /api/reports/:id/compare` | 历史对比 |

### 追踪
| 端点 | 说明 |
|------|------|
| `POST /api/tracking/ingest/batches` | 创建追踪批次 |
| `POST /api/tracking/ingest/batches/:id/chunks` | 追加 chunk |
| `POST /api/tracking/ingest/batches/:id/complete` | 完成写入 |

### 管理端
| 端点 | 说明 |
|------|------|
| `GET /api/admin/dashboard` | 总览 |
| `GET /api/admin/data/:domain` | 数据中心 |
| `GET /api/admin/alerts` | 异常告警 (5 模块) |
| `GET /api/admin/jobs` | 定时任务管理 |
| `GET /api/admin/outlook/*` | Outlook 管理 |

### 其他
| 端点 | 说明 |
|------|------|
| `GET /api/health` | 健康检查 (poolStats + encryptionKey) |
| `GET /api/docs` | Swagger API 文档 |
| `GET /api/analytics/export/csv` | 导出 CSV |

---

## 环境变量

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `FLOWPLANV2_DATABASE_URL` | — | PostgreSQL 连接 (**必需**) |
| `FLOWPLANV2_ENCRYPTION_KEY` | — | AES-256-GCM 加密密钥 (**生产必设**) |
| `JWT_ACCESS_SECRET` | — | JWT 签名密钥 |
| `JWT_REFRESH_SECRET` | — | Refresh Token 签名密钥 |
| `PORT` | 3202 | 服务端口 |
| `HOST` | 0.0.0.0 | 监听地址 |
| `DATABASE_POOL_MAX` | 10 | 连接池大小 |
| `DATABASE_POOL_IDLE_TIMEOUT` | 30000 | 空闲超时 (ms) |
| `SLOW_QUERY_THRESHOLD_MS` | 1000 | 慢查询阈值 (ms) |
| `AI_REQUEST_TIMEOUT_MS` | 30000 | AI API 超时 (ms) |
| `KOPIA_EXE` | kopia | Kopia CLI 路径 |
| `OUTLOOK_AUTHORITY` | login.microsoftonline.com/consumers | OAuth 端点 |

---

## 技术栈

NestJS 10.4 · TypeScript 5.6 · PostgreSQL 16 · pgvector (可选) · Vitest 4.1 · Winston · MS Graph SDK · @nestjs/schedule · Swagger

## 文档

- [CHANGELOG.md](../CHANGELOG.md) — 版本更新日志
- [docs/DEPLOYMENT.md](../docs/DEPLOYMENT.md) — 生产部署指南 (Ubuntu 从零开始)
- [FlowPlan_系统重构与未来开发路线_260507.md](../FlowPlan_系统重构与未来开发路线_260507.md) — 重构路线
- [Swagger](http://localhost:3202/api/docs) — 运行时 API 文档
