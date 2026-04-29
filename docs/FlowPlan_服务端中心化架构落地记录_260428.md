# FlowPlan 服务端中心化架构落地记录 260428

## 本次落地目标

本次将软件架构进一步收口为：

- 服务端是业务数据、文件数据、追踪处理和审计的唯一长期事实源。
- 管理端是单事实库的全局 Web 控制台。
- Flutter Windows / Android / Web 都是日常访问客户端。
- Flutter Web 不采集追踪，只展示服务端汇总数据。
- 云盘以服务端 `file_nodes` 和 `file_storage_objects` 为主，本地文件只作为设备副本。

## 已完成的代码收口

### 服务端追踪批量上传入口

新增：

- `server/src/tracking/tracking.controller.ts`
- `server/src/tracking/tracking.service.ts`

新增 API：

- `POST /api/tracking/ingest/batches`
- `GET /api/tracking/ingest/batches`
- `POST /api/tracking/ingest/batches/:batchId/chunks`
- `POST /api/tracking/ingest/batches/:batchId/complete`
- `GET /api/tracking/summary`

实现方式：

- 原生客户端先创建 tracking ingest batch。
- 追踪原始数据可以直接放在 batch，也可以按 chunk 上传。
- chunk 支持普通 JSON payload，也预留 `payloadBase64` 和 `gzip_base64`/`gzip` 解包边界。
- complete 时服务端把 records 规范化为 canonical `sync_objects`：
  - `raw_activity_log`
  - `activity_record`
  - `tracked_input_event`
- 每个写入都会生成 `sync_changes`。
- 每个关键动作都会写入 `audit_logs`。
- 批次状态写入 `tracking_ingest_batches`，chunk 写入 `tracking_ingest_chunks`。

### 活动理解 API 别名

新增：

- `server/src/activity/activity.controller.ts`

新增兼容 API：

- `GET /api/activity/segments`
- `POST /api/activity/segments/:segmentId/confirm`
- `POST /api/activity/segments/:segmentId/reject`

说明：

- 这些接口复用现有 `ActivityUnderstandingService`。
- 目的是让未来客户端和 Web 使用更稳定的 `/activity/*` 业务语义入口。

### 文件云盘 API 收口

补充兼容接口：

- `POST /api/files/transfers/upload-session`
- `POST /api/files/transfers/:sessionId/chunks/:chunkIndex`
- `GET /api/files/transfers/:sessionId/missing-chunks`
- `POST /api/files/transfers/:sessionId/complete`
- `GET /api/files/storage/:objectId/download`

实现方式：

- 新接口复用已有 upload session、chunk、missing chunks、complete 逻辑。
- `storage/:objectId/download` 可按 range 返回服务端对象内容的 base64 payload。
- 下载 range 会写入文件操作日志和审计。

### 数据库结构

在 `server/src/database/p1_schema.sql` 中新增：

- `tracking_ingest_batches`
- `tracking_ingest_chunks`

用途：

- 记录客户端追踪数据批量上传状态。
- 支持后续断点续传、缺块排查、失败重试、压缩包传输。

### 管理端入口

更新：

- `web_admin/src/main.tsx`
- `server/src/admin/admin.service.ts`

新增管理端数据域：

- `tracking-ingest-batches`
- `tracking-ingest-chunks`

管理端现在可以查看：

- 追踪上传批次状态。
- 每个批次的 chunk 记录。
- 上传数量、成功数量、失败数量、错误原因。

### Flutter 客户端 API 封装

新增：

- `client_flutter/lib/core/server_api/tracking_ingest_api.dart`

提供：

- 创建追踪上传批次。
- 上传追踪 chunk。
- 完成批次。
- 读取追踪上传摘要。

说明：

- 本次没有运行 Flutter/Dart 命令。
- 该 API 封装用于后续 Windows/Android 原生追踪模块接入。
- Flutter Web 不应调用该追踪采集上传 API。

## 当前仍未完全完成的部分

### 原生客户端追踪自动上传

服务端入口和客户端 API 封装已存在，但 Windows/Android 追踪采集服务还没有真正自动调用 `TrackingIngestApi`。

后续最小任务：

- 在原生追踪服务中增加本地 spool 状态。
- 定时把 raw activity / input events 压缩成 batch。
- 网络可用时调用 tracking ingest API 上传。
- 上传成功后标记本地缓冲已提交。

### 云盘本地绑定自动哈希检测

服务端已有 open-plan、device-location、download-request、storage range 下载能力，但原生客户端仍需要继续补：

- 本地绑定目录扫描。
- 下载前 hash 检查。
- hash 一致直接打开。
- hash 不一致显示确认提示。
- 下载后写入 `file_node_device_locations`。

### Flutter Web 文件体验

Flutter Web 已经定位为普通用户浏览器客户端，但仍需要用户手动执行：

- `flutter analyze`
- `flutter build web`

本次没有运行 Flutter/Dart 命令。

## 已验证

已执行：

- `server`：`npm run build` 通过。
- `web_admin`：`npm run build` 通过。

未执行：

- `npm run db:schema`，需要用户本机提供 `DATABASE_URL`。
- Flutter/Dart 相关命令，遵守用户约束。

## 用户需要手动执行

在服务端目录：

```powershell
cd C:\Users\a2746\Desktop\calll260426\server
$env:DATABASE_URL="你的数据库连接串"
npm run db:schema
npm run build
```

在管理端目录：

```powershell
cd C:\Users\a2746\Desktop\calll260426\web_admin
npm run build
```

Flutter 由用户自行验证：

```powershell
cd C:\Users\a2746\Desktop\calll260426\client_flutter
flutter analyze
flutter build web
```
