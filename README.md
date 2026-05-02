# FlowPlanV2

> 中文优先 · 本地优先 · 三端协同的个人数据管理系统

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/Version-v1.5.0%2B150-blue" />
  <img alt="Build" src="https://img.shields.io/badge/Build-150-6b7280" />
  <img alt="Platform" src="https://img.shields.io/badge/Platform-Windows%20%7C%20Android-green" />
  <img alt="Storage" src="https://img.shields.io/badge/Storage-Local--first-orange" />
  <img alt="License" src="https://img.shields.io/badge/License-Private-red" />
</p>

## 一句话概览

FlowPlanV2 是一个面向个人数据长期管理的本地优先系统，把日历、任务、追踪、文件、报告、同步、审计和管理后台整合到同一套产品里。仓库当前包含三个主要端：

- `server`：后端服务与事实数据中心
- `web_admin`：Web 管理后台
- `client_flutter`：Flutter 客户端

这套仓库的目标不是只做一个日程工具，而是把“我做了什么、文件在哪里、数据如何流转、哪些操作可以追溯”放进同一个系统里。

## 版本信息

当前版本链路已经统一到：

- 产品版本：`v1.5.0+150`
- Flutter 版本号：`1.5.0+150`
- MSIX 版本号：`1.5.0.150`
- Node 包版本：`1.5.0`
- 发布日期：`2026-05-02`

对应的关键版本文件：

- [client_flutter/pubspec.yaml](client_flutter/pubspec.yaml)
- [client_flutter/lib/core/app/app_release.dart](client_flutter/lib/core/app/app_release.dart)
- [client_flutter/windows/runner/Runner.rc](client_flutter/windows/runner/Runner.rc)
- [client_flutter/version.txt](client_flutter/version.txt)
- [server/package.json](server/package.json)
- [web_admin/package.json](web_admin/package.json)

## 仓库结构

```text
.
├─ server/                 # NestJS 后端、PostgreSQL、同步与管理接口
├─ web_admin/              # React + Vite 管理后台
├─ client_flutter/         # Flutter 客户端
├─ scripts/                # 启动脚本、边界检查脚本
├─ docs/                   # 设计文档与说明资料
├─ logs/                   # 启动与运行日志
└─ README.md               # 仓库总说明
```

### 三端职责

| 目录 | 角色 | 主要职责 |
| --- | --- | --- |
| `server/` | 服务端 | 提供认证、同步、设备、文件、追踪、报告、AI、模型、管理与 Web 接口 |
| `web_admin/` | 管理端 | 提供数据查看、配置管理、同步健康、冲突处理、审计与运营操作 |
| `client_flutter/` | 客户端 | 提供本地优先的日历、任务、追踪、文件、报告、同步和设置入口 |

## 核心能力

### 1. 日历与任务

- 时间线、周视图、月视图三种主视角
- 任务详情、日程详情、快速新增和未排程任务面板
- 任务与日程在同一工作台中协同查看
- 支持基础的本地编辑、确认和重排流程

### 2. 追踪与行为分析

- 输入热力图、活动回顾、追踪日志、输入历史
- 活动记录、工作会话和输入事件的结构化沉淀
- 支持从原始行为中提炼工作会话与输入强度
- 兼顾桌面端输入采样与 Android 使用时长导入

### 3. 文件与上下文

- 文件上下文、文件传输中心、文件树和节点管理
- 本地目录与服务端 Root 的关联、扫描和刷新
- 上传会话、分块上传、下载会话、缺失分块补传
- 支持文件上下文与任务/日程/数据流的关联

### 4. 报告与审计

- 日报、日报草稿、报告模板、推送通道、推送记录
- 操作审计日志、数据操作日志、批量修改痕迹
- 可回看高风险数据变更与同步相关操作

### 5. 同步与导入导出

- Outlook 日历同步
- iCalendar 导入与导出
- 服务端同步状态、冲突列表和冲突处理
- 本地优先的数据结构化迁移与恢复

### 6. 数据管理与后台

- 统一的数据管理页
- 同步健康、设备状态、运行监控、作业状态
- 管理端配置、远程配置、对象管理、AI 草稿管理
- 支持按域查看和维护核心事实数据

## 各端说明

### `server`

后端使用 NestJS 构建，默认通过 `http://localhost:3202/api` 提供接口。它承担的是“事实数据中心”的职责，核心关注点包括：

- PostgreSQL 连接与核心 schema 初始化
- 用户认证与设备注册
- 同步推拉、ACK、冲突列表与冲突解决
- 文件、报告、追踪、调度、AI、模型与管理接口

#### 服务入口

- 启动入口：`server/src/main.ts`
- 模块入口：`server/src/app.module.ts`
- 健康检查：`GET /api/health`

健康检查会验证 PostgreSQL 是否可达，并检查核心表是否存在。当前最基础的表包括：

- `users`
- `devices`
- `device_connection_events`

#### 主要 API 分组

| 分组 | 说明 |
| --- | --- |
| `/api/auth` | 登录、刷新、退出 |
| `/api/devices` | 设备注册、列表、更新、心跳、吊销 |
| `/api/sync` | 推送、拉取、确认、冲突、状态、冲突解决 |
| `/api/files` | 文件树、对象、上传会话、下载会话、存储、版本、冲突 |
| `/api/reports` | 报告、日报、模板、推送、天气摘要 |
| `/api/tracking` | 追踪批次、摘要、缓冲状态 |
| `/api/analytics` | 热力图、输入事件、活动统计 |
| `/api/admin` | 管理总览、数据管理、配置、监控、作业、冲突处理 |
| `/api/client` | 客户端启动、任务、日程、导入、变更流 |
| `/api/web` | Web 端任务、日程、提醒、操作确认 |
| `/api/models` | 模型版本、运行、反馈、激活 |
| `/api/ai` | AI 设置、上下文、草稿与会话 |
| `/api/scheduler` | 调度运行、偏差检测 |
| `/api/activity` | 活动片段与确认流程 |
| `/api/activity-understanding` | 活动理解与反馈闭环 |

#### 后端脚本

`server/package.json` 提供的常用脚本：

- `npm run db:schema`：应用数据库 schema
- `npm run dev`：开发模式启动
- `npm run build`：构建
- `npm run start`：运行构建产物

### `web_admin`

管理后台使用 Vite + React 实现，定位是“操作台”和“审计台”，默认由静态服务器对外提供构建后的 `dist` 内容。

#### 管理端能力

- 总览、数据中心、设置中心
- 同步健康、设备在线状态、冲突回顾
- 文件与存储、模型与 AI、报告与推送
- 监控、日志、作业、远程配置、运营操作

#### 入口与脚本

- 静态服务入口：`web_admin/scripts/static-server.mjs`
- 应用入口：`web_admin/src/main.tsx`
- 样式入口：`web_admin/src/styles.css`

常用脚本：

- `npm run dev`：启动静态服务，面向稳定运行
- `npm run vite:dev`：需要热更新时使用 Vite 开发服务
- `npm run build`：构建管理后台
- `npm run preview`：预览构建结果

### `client_flutter`

Flutter 客户端是仓库的主交互端，强调本地优先和跨平台一致性。它以 `Riverpod + go_router + Drift + SQLite` 为主要组合，面向 Windows 桌面与 Android 移动端，同时保留 Web 入口用于预览和联调。

#### 主要特征

- 本地优先的数据模型
- 本地数据库为核心事实源
- 可追溯的同步、导入、导出和恢复流程
- 桌面端和移动端共享同一套业务域

#### 关键入口

- 应用入口：`client_flutter/lib/main.dart`
- 应用壳：`client_flutter/lib/app.dart`
- 路由：`client_flutter/lib/core/router/app_router.dart`

#### 主要路由

| 路由 | 说明 |
| --- | --- |
| `/timeline` | 时间线主视图 |
| `/week` | 周视图 |
| `/month` | 月视图 |
| `/task/create` | 新建任务 |
| `/task/:id` | 任务详情 |
| `/event/create` | 新建日程 |
| `/event/:id` | 日程详情 |
| `/tracker` | 追踪主页 |
| `/tracker/activity-review` | 活动回顾 |
| `/tracker/day-details` | 追踪日详情 |
| `/tracker/log-history` | 追踪日志历史 |
| `/tracker/input-history` | 输入历史 |
| `/tracker/input-heatmap` | 输入热力图 |
| `/reports` | 报告中心 |
| `/files` | 文件上下文 |
| `/files/transfers` | 文件传输中心 |
| `/audit-logs` | 数据操作审计 |
| `/data-management` | 数据管理 |
| `/ical` | iCalendar 导入导出 |
| `/outlook-sync` | Outlook 同步设置 |
| `/server-sync` | 服务端同步状态 |
| `/settings` | 应用设置 |

#### 关键模块

| 模块 | 内容 |
| --- | --- |
| `core/` | 数据库、路由、主题、存储、平台启动与同步基础设施 |
| `shared/` | 全局状态、通用组件、设置与追踪相关 provider |
| `features/calendar/` | 日历壳、时间线、周视图、月视图、日程详情 |
| `features/task/` | 任务详情、快速新增、未排程任务 |
| `features/tracker/` | 追踪主页、热力图、日志、输入历史、行为分析 |
| `features/files/` | 文件上下文、传输中心、文件操作服务 |
| `features/reports/` | 报告中心与推送相关功能 |
| `features/sync/` | Outlook 登录、日历同步、服务端同步状态 |
| `features/ical/` | 导入导出和归档辅助 |
| `features/settings/` | 应用设置与同步相关设置 |
| `features/audit/` | 数据操作日志查看 |
| `features/data_management/` | 统一数据管理页 |

## 启动与配置

### 根目录一键启动

仓库提供根目录启动脚本：

- `start-flowplanv2-all.cmd`
- `scripts/start-flowplanv2-all.ps1`

它会按需启动服务端、管理端，并统一处理客户端相关构建和运行入口。脚本默认会读取以下本地环境文件，按顺序加载：

1. `flowplanv2.local.env`
2. `server/flowplanv2.local.env`
3. `server/.env`

脚本和后端默认约定的关键配置包括：

- `FLOWPLANV2_DATABASE_URL`
- `DATABASE_URL`
- `PORT`
- `HOST`
- `ADMIN_CORS_ORIGIN`
- `FLOWPLANV2_BODY_LIMIT`

默认端口：

- 后端服务：`3202`
- 管理后台：`5174`

### 后端配置

后端启动前需要准备 PostgreSQL 连接串。推荐放在根目录 `flowplanv2.local.env`，示例格式如下：

```text
FLOWPLANV2_DATABASE_URL=postgres://USER:PASSWORD@HOST:5432/DATABASE
```

后端启动后，`/api/health` 会先确认数据库可达和核心 schema 是否已应用。如果 schema 未准备好，需要先应用数据库结构。

### 管理端配置

管理端静态服务默认从 `dist` 提供内容，并通过环境变量把 API 地址指向后端：

- `VITE_API_BASE_URL=http://localhost:3202/api`

如果需要调整端口，可以通过启动脚本参数或环境变量覆盖。

### 客户端说明

客户端发布版本、桌面资源、包版本和安装包版本已经统一同步。仓库里保留了客户端运行、发布和检查相关的版本文件，但根 README 不再展开相关构建命令；客户端相关入口和路由请直接参考 `client_flutter/` 目录。

## 数据与同步边界

FlowPlanV2 的默认策略是“先把数据握在自己手里”：

- 核心事实优先落在本地数据库
- 外部同步是显式边界，不是默认依赖
- 导入、导出和恢复尽量保留结构化数据
- 行为追踪、文件上下文、审计日志都保留可回看痕迹
- 服务端同步状态、冲突和设备心跳都有独立入口

## 维护约定

- 版本更新时，优先同步 `pubspec.yaml`、`app_release.dart`、`Runner.rc`、`version.txt`、`server/package.json`、`web_admin/package.json`
- 如果接口、路由、目录结构或启动方式发生变化，要同步更新本 README
- 根 README 以产品总览为主，不写成细碎的开发笔记
- 不在本文件中写入客户端构建命令

## 参考入口

- [server/README.md](server/README.md)
- [web_admin/README.md](web_admin/README.md)
- [client_flutter/RELEASE_CHECKLIST.md](client_flutter/RELEASE_CHECKLIST.md)
