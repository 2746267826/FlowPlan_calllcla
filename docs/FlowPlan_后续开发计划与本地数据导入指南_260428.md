# FlowPlan 后续开发计划与本地数据导入指南 260428

## 一、当前未完全完成的内容

本文件用于在上下文失效后继续开发。当前架构已经确定为：

- 服务端是唯一长期事实源。
- 管理端是单事实库全局控制台。
- Flutter Windows / Android / Tablet / Web 是日常访问客户端。
- Flutter Web 不采集追踪。
- 云盘文件内容以服务端远程存储为事实源，客户端只缓存副本。

当前仍需继续完成的主要部分有两块：

1. 原生客户端自动把追踪缓冲上传到服务端。
2. 云盘本地绑定目录的 hash 检测、直接打开和下载闭环。

---

## 二、后续开发计划 A：原生客户端追踪缓冲自动上传

### 目标

Windows / Android 客户端采集追踪数据后，不再只留在本地数据库或日志文件中，而是按时间窗口压缩、分批、可重试地上传到服务端。

服务端收到后：

- 写入 `tracking_ingest_batches`。
- 写入 `tracking_ingest_chunks`。
- 完成批次后转换为 canonical `sync_objects`。
- 生成 `sync_changes`。
- 写入 `audit_logs`。
- 后续由服务端活动理解模块生成 `activity_segments`。

### 已有基础

服务端已有：

- `server/src/tracking/tracking.controller.ts`
- `server/src/tracking/tracking.service.ts`
- `POST /api/tracking/ingest/batches`
- `POST /api/tracking/ingest/batches/:batchId/chunks`
- `POST /api/tracking/ingest/batches/:batchId/complete`
- `GET /api/tracking/summary`

数据库已有：

- `tracking_ingest_batches`
- `tracking_ingest_chunks`

客户端已有：

- `client_flutter/lib/core/server_api/tracking_ingest_api.dart`

### 需要继续开发

#### A1. 客户端追踪上传缓冲状态

新增或扩展本地状态，用于记录哪些追踪数据已上传、上传中、失败、待重试。

建议本地表或本地设置：

- `tracking_upload_batches`
- `tracking_upload_batch_items`

最小字段：

- `batch_uid`
- `data_kind`
- `start_at`
- `end_at`
- `status`
- `record_count`
- `uploaded_count`
- `server_batch_id`
- `last_error`
- `created_at`
- `updated_at`

状态：

- `pending`
- `uploading`
- `uploaded`
- `failed`
- `retrying`

#### A2. 追踪数据归档为上传 batch

在原生客户端中读取：

- `activity_records`
- `tracked_input_events`
- `raw_activity_logs` 或现有日志归档文件

按时间窗口打包：

- 默认每 15 分钟或 30 分钟一个 batch。
- 网络差时允许延后。
- 单 batch 不超过预设记录数，例如 1000 条。
- 大 batch 拆成 chunk。

每条记录需要规范化为：

```json
{
  "uid": "client-stable-id",
  "kind": "activity_record | tracked_input_event | raw_activity_log",
  "startTime": "...",
  "endTime": "...",
  "timestamp": "...",
  "appName": "...",
  "processName": "...",
  "windowTitle": "...",
  "filePath": "...",
  "durationSeconds": 0,
  "metadata": {}
}
```

#### A3. 上传流程

客户端流程：

1. 创建本地 batch，状态 `pending`。
2. 调用 `TrackingIngestApi.createBatch()`。
3. 记录返回的 `serverBatchId`。
4. 分 chunk 调用 `uploadChunk()`。
5. 所有 chunk 成功后调用 `completeBatch()`。
6. 服务端返回 accepted / rejected 数量。
7. 本地 batch 标记 `uploaded` 或 `failed`。
8. 写入本地操作日志。

失败处理：

- 网络失败：保持 `pending` 或 `failed`，稍后重试。
- 服务端 5xx：指数退避。
- chunk 上传失败：只重传失败 chunk。
- complete 失败：保留 server batch id，重试 complete。
- 部分 rejected：展示摘要，但不阻塞其他记录。

#### A4. UI 与管理端

客户端同步页增加：

- 追踪上传待处理数量。
- 最近一次上传时间。
- 最近错误。
- 手动“上传追踪缓冲”按钮。

管理端已有入口，需要后续优化展示：

- 追踪上传批次。
- 追踪上传分块。
- 失败原因。
- accepted / rejected 数量。

#### A5. 验收标准

- Windows 客户端采集 10 分钟追踪后，能上传到服务端。
- Android 客户端导入 usage stats 后，能上传到服务端。
- 服务端 `tracking_ingest_batches` 出现 completed 批次。
- 服务端 `sync_objects` 出现 `activity_record` 或 `tracked_input_event`。
- 管理端能看到追踪批次。
- 服务端活动理解能基于上传数据生成 `activity_segments`。

---

## 三、后续开发计划 B：云盘本地绑定目录与 hash 直接打开

### 目标

客户端内文件中心就是云盘。

文件事实源：

- 逻辑树：服务端 `file_nodes`
- 文件内容：服务端 `file_storage_objects`
- 本地文件：某设备上的缓存或副本，不是事实源

用户访问文件时：

1. 客户端先只读取服务端文件树。
2. 用户点击文件时，客户端检查当前设备是否有本地副本。
3. 如果绑定目录中存在同名或映射文件，先计算 hash。
4. hash 与服务端一致，直接调用本地文件打开。
5. 本地不存在或 hash 不一致，提示是否下载。
6. 下载后保存到绑定目录或缓存目录。
7. 更新 `file_node_device_locations`。
8. 写入文件操作日志和审计。

### 已有基础

服务端已有：

- `file_nodes`
- `file_storage_objects`
- `file_node_device_locations`
- `file_identity_mappings`
- `GET /api/files/drive/roots`
- `GET /api/files/drive/nodes`
- `GET /api/files/drive/nodes/:nodeId`
- `POST /api/files/drive/nodes/:nodeId/open-plan`
- `POST /api/files/drive/nodes/:nodeId/device-location`
- `POST /api/files/drive/nodes/:nodeId/download-request`
- `POST /api/files/drive/nodes/:nodeId/relink`
- `GET /api/files/storage/:objectId/download`

客户端已有部分：

- 文件中心页面。
- 文件树展示。
- 文件传输中心。
- 服务端文件 API 封装。

### 需要继续开发

#### B1. 本地目录绑定模型

客户端需要保存“云盘目录 -> 本地目录”的绑定。

建议本地表或设置：

- `cloud_drive_local_bindings`

字段：

- `binding_uid`
- `root_id`
- `node_id`
- `local_root_path`
- `platform`
- `status`
- `created_at`
- `updated_at`

状态：

- `active`
- `missing`
- `permission_lost`
- `disabled`

Android 需要额外保存 SAF URI 和 persistable permission。

#### B2. 本地同一性检测

新增平台服务：

- `LocalFileIdentityService`

能力：

- 检查文件是否存在。
- 读取大小和修改时间。
- 计算 sha256。
- 大文件计算 hash 时显示进度，不能阻塞 UI。

判断优先级：

1. `sha256` 完全一致。
2. provider id / storage object id 一致。
3. `size + modifiedAt + relativePath` 低置信度匹配，只能提示用户确认，不能自动当成事实。

#### B3. 文件打开流程

原生客户端点击文件：

1. 调用 `/api/files/drive/nodes/:nodeId`。
2. 根据绑定目录推导候选本地路径。
3. 如果本地存在，计算 hash。
4. 调用 `/api/files/drive/nodes/:nodeId/open-plan`，带上本地 identity。
5. 服务端返回：
   - `open_local`
   - `download_then_open`
   - `needs_upload_or_relink`
6. `open_local`：调用平台打开服务。
7. `download_then_open`：弹窗确认下载。
8. `needs_upload_or_relink`：提示上传、重新定位或取消。

#### B4. 下载流程

客户端下载：

1. 调用 `/api/files/drive/nodes/:nodeId/download-request`。
2. 获得 download session 或 storage object。
3. 使用 range/chunk 下载。
4. 写入绑定目录，保留云盘相对路径。
5. 下载完成后计算本地 hash。
6. 与服务端 hash 比对。
7. 调用 `/api/files/drive/nodes/:nodeId/device-location` 登记本地副本。
8. 写本地操作日志。

#### B5. Web 端差异

Flutter Web：

- 不绑定本地目录。
- 不扫描本地文件。
- 不调用资源管理器。
- 只能浏览服务端文件树。
- 上传使用浏览器文件选择。
- 下载使用浏览器下载。
- 预览使用服务端内容或浏览器 URL。

#### B6. 验收标准

- 服务端文件树中 remote-only 文件能显示。
- 客户端只拉文件树，不自动下载内容。
- 绑定本地目录后，点击文件会先检测本地是否存在。
- hash 一致时不下载，直接打开。
- hash 不一致时不覆盖，必须提示确认。
- 本地不存在时提示下载。
- 下载完成后写入 `file_node_device_locations`。
- 管理端可看到本地副本状态和文件操作日志。

---

## 四、本地数据导入服务端指南

当前仓库已经有“本地快照导入服务端”的服务端接口和客户端服务代码。

### 1. 导入接口

服务端接口：

- `POST /api/client/import/local-snapshot`
- `GET /api/client/import/:importId`
- `POST /api/client/import/:importId/confirm`
- `POST /api/client/import/:importId/cancel`

客户端代码：

- `client_flutter/lib/core/bootstrap/client_bootstrap_service.dart`
- `client_flutter/lib/core/server_api/client_api.dart`

核心方法：

- `ClientBootstrapService.prepareLocalImport()`
- `ClientBootstrapService.confirmImport(importId)`
- `ClientBootstrapService.buildLocalSnapshot()`

### 2. 导入内容

当前客户端快照会尝试导出：

- `task_items`
- `task_lists`
- `calendar_events`
- `event_calendars`
- `task_schedule_segments`
- `actual_activity_logs`
- `activity_records`
- `file_folders`
- `file_items`
- `file_nodes`
- `file_context_links`
- `report_documents`
- `diary_entries`
- 服务端管理范围内的设置

服务端会写入：

- `client_import_sessions`
- `sync_objects`
- `sync_changes`
- `admin_remote_configs`
- `audit_logs`

### 3. 推荐导入方式

推荐优先使用客户端 UI 入口，如果设置页或同步页已经显示“导入到服务端 / 服务端接管本地数据”，按以下流程：

1. 确认服务端正在运行。
2. 确认客户端服务端地址正确。
3. 点击“准备导入”。
4. 查看服务端返回的摘要：
   - 对象数量
   - 设置数量
   - 冲突数量
   - 各表数量
5. 如果摘要合理，点击确认导入。
6. 导入完成后执行一次立即同步。
7. 打开管理端，检查任务、日程、实际记录、文件元数据是否出现。

### 4. 如果 UI 入口还没有暴露

当前代码里导入服务存在，但 UI 入口可能还不完整。此时建议后续开发一个“服务端接管向导”，不要直接手写数据库。

向导最小流程：

1. 设置服务端地址。
2. 调用 `/api/health`。
3. 调用 `/api/client/bootstrap`。
4. 调用 `buildLocalSnapshot()`。
5. 调用 `prepareLocalImport()`。
6. 展示摘要和冲突。
7. 用户确认后调用 `confirmImport(importId)`。
8. 自动执行 `bootstrapAndSync(source: 'import_confirmed')`。

### 5. PowerShell 手动测试接口示例

仅用于小样本测试，不建议拿完整真实本地库手写 JSON。

先准备一个极小 snapshot：

```powershell
$headers = @{
  "content-type" = "application/json"
  "x-flowplan-user-id" = "00000000-0000-4000-8000-000000000001"
  "x-flowplan-device-id" = "00000000-0000-4000-8000-000000000101"
  "x-flowplan-device-name" = "manual-import-test"
  "x-flowplan-platform" = "windows"
}

$body = @{
  snapshot = @{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    objects = @(
      @{
        objectType = "task_item"
        uid = "manual-task-001"
        localId = "manual-task-001"
        payload = @{
          title = "手动导入测试任务"
          status = "open"
        }
      }
    )
    settings = @()
  }
} | ConvertTo-Json -Depth 20

$prepare = Invoke-RestMethod `
  -Method Post `
  -Uri "http://localhost:3000/api/client/import/local-snapshot" `
  -Headers $headers `
  -Body $body

$prepare
```

确认导入：

```powershell
$importId = $prepare.importId

Invoke-RestMethod `
  -Method Post `
  -Uri "http://localhost:3000/api/client/import/$importId/confirm" `
  -Headers $headers
```

查看结果：

```powershell
Invoke-RestMethod `
  -Uri "http://localhost:3000/api/client/import/$importId" `
  -Headers $headers
```

### 6. 导入前注意事项

- 先备份本地客户端数据。
- 确认服务端已经执行最新 schema。
- 首次导入建议先用小样本测试。
- 完整导入必须经过摘要确认，不要静默执行。
- 如果出现冲突，不应覆盖，应进入冲突列表或人工确认。
- 导入完成后，客户端本地数据应标记为 synced，并进入服务端优先模式。

### 7. 用户现在应执行的服务端准备命令

```powershell
cd C:\Users\a2746\Desktop\calll260426\server
$env:DATABASE_URL="你的数据库连接串"
npm run db:schema
npm run build
npm run dev
```

然后检查：

```powershell
Invoke-RestMethod http://localhost:3000/api/health
Invoke-RestMethod http://localhost:3000/api/client/bootstrap
```

如果这两个都正常，再从客户端执行服务端接管导入。
