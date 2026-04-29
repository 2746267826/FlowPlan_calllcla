# FlowPlan 客户端追踪上传与云盘本地同一性落地记录 260428

## 本次继续开发完成内容

本次围绕此前计划中尚未完全做完的两项继续推进：

1. 原生客户端自动把追踪缓冲上传到服务端。
2. 云盘本地绑定目录的 hash 检测与直接打开流程。

本次仍然没有运行 Flutter / Dart 命令，需由用户手动执行 Flutter 侧验证。

---

## A. 原生客户端追踪缓冲上传

### 已完成

新增客户端追踪上传服务：

- `client_flutter/lib/features/tracker/services/tracking_upload_service.dart`

能力：

- 从本地 SQLite 读取待上传追踪缓冲：
  - `activity_records`
  - `tracked_input_events`
  - `raw_activity_logs`
- 使用本地 `app_settings` 记录各类数据最后上传到的自增 ID：
  - `tracking.upload.last_activity_record_id`
  - `tracking.upload.last_input_event_id`
  - `tracking.upload.last_raw_log_id`
- 将本地记录规范化为服务端 ingest payload。
- 按类型创建服务端 ingest batch。
- 按 chunk 上传 records。
- complete 成功后推进本地游标。
- 上传成功写入本地操作日志。
- 上传失败不推进游标，保留等待下次重试。

接入现有同步节奏：

- `client_flutter/lib/core/bootstrap/client_bootstrap_service.dart`
- `client_flutter/lib/shared/providers/app_providers.dart`

现在客户端在以下时机会尝试上传追踪缓冲：

- 启动后 bootstrap + sync。
- 手动“立即同步”。
- 写入触发同步。
- 5 分钟定时同步。

失败处理：

- 追踪上传失败不会打断任务/日程等普通同步。
- 失败会写入：
  - `tracking.upload.last_error`
  - 本地 `data_operation_logs`

### 仍需后续增强

当前是最小可用上传闭环，还不是最终稳定版：

- 还没有独立 `tracking_upload_batches` / `tracking_upload_batch_items` 本地表。
- 还没有 chunk 级本地状态恢复，只以“最后成功 ID”做重试。
- 还没有 gzip/压缩传输。
- 还没有根据网络状态动态限流。
- 还没有 UI 展示追踪上传待处理数量、最近上传时间、最近错误。
- Android 侧 UsageStats 的长期后台采集、前台服务、权限恢复仍需单独验证。

---

## B. 云盘本地 hash 同一性与直接打开

### 已完成

新增本地文件身份识别服务：

- `client_flutter/lib/features/files/services/local_file_identity_service.dart`

能力：

- 检查本地文件是否存在。
- 读取本地文件大小、修改时间。
- 计算真实 `sha256`。
- 返回用于服务端 `open-plan` 的 identity：
  - `localPath`
  - `hashSha256`
  - `sizeBytes`
  - `modifiedAt`
  - `storageObjectId`

增强文件打开服务：

- `client_flutter/lib/features/files/services/file_context_interaction_service.dart`

现在点击文件节点时：

1. 先根据 `node.localPath` 识别本地文件。
2. 如果 `node.localPath` 不可用，则尝试用 Root 本地目录 + `relativePath` 推导候选路径。
3. 对候选本地文件计算真实 sha256。
4. 将本地 identity 传给服务端：
   - `POST /api/files/drive/nodes/:nodeId/open-plan`
5. 服务端返回 `open_local` 时，客户端登记当前设备本地副本：
   - `POST /api/files/drive/nodes/:nodeId/device-location`
6. 然后调用本机默认程序打开。
7. 如果服务端要求下载或重新定位，当前不会自动打开，会写入操作日志并返回失败。
8. 如果服务端不可用但本地文件确实存在，仍允许本地打开，保证原生客户端可用性。

增强文件中心 UI：

- `client_flutter/lib/features/files/presentation/file_context_page.dart`

现在 remote-only 文件只要有 `remoteId`，打开按钮也可点击，用于触发服务端 open-plan；不再因为 `localPath` 为空就完全禁止用户操作。
如果不能直接打开，页面会提示“可能需要下载、重新定位或处理 hash 不一致”，避免用户点击后没有反馈。
服务端返回 `download_then_open` 时，文件中心现在会弹出人工确认框；用户确认后选择保存位置，客户端创建服务端下载请求，并把下载任务交给传输中心执行。

增强传输中心：

- `client_flutter/lib/features/files/services/file_transfer_service.dart`

新增能力：

- 支持接收已经由 `download-request` 创建好的 download session。
- 下载完成后返回 `FileTransferJob`，便于调用方继续登记本地副本。
- 文件中心在下载完成后重新计算本地 hash，并调用 `device-location` 登记为本设备副本。

收紧服务端 open-plan 判断：

- `server/src/files/files.service.ts`

现在只有以下情况才允许 `open_local`：

- 当前客户端提供了本地路径，并且
- hash 完全匹配，或 provider id 完全匹配。

不再因为 `size + modifiedAt` 这种低置信度匹配就直接打开本地文件，避免误把不同内容当成同一文件。

### 仍需后续增强

当前已经具备“本地文件存在且 hash 一致则直接打开”的核心逻辑，但仍未完成完整用户体验：

- `download_then_open` 已经具备人工确认、保存位置选择、创建 download-request、进入传输中心、下载完成后登记本地副本的最小闭环。
- 仍未完成“下载完成后自动再打开文件”的体验；当前下载后可在传输中心或文件中心再次打开。
- 还没有云盘 Root 到本地目录的正式绑定表：
  - 建议后续增加 `cloud_drive_local_bindings`
- 当前候选路径主要来自 `file_folders.local_path + file_nodes.relative_path`，还不是完整多 Root / 多绑定策略。
- Android SAF URI、本地 persistable permission、Web 下载差异仍需按平台继续拆分。
- 大文件 hash 计算还没有 UI 进度条。
- hash 不一致时还没有“保留本地 / 下载为副本 / 覆盖需二次确认”的完整交互。

---

## 修改文件列表

### 客户端

- `client_flutter/lib/features/tracker/services/tracking_upload_service.dart`
  - 新增追踪缓冲上传服务。

- `client_flutter/lib/core/bootstrap/client_bootstrap_service.dart`
  - 在 bootstrap/syncNow 中挂接追踪上传 runner。
  - 追踪上传失败不阻断普通同步。

- `client_flutter/lib/shared/providers/app_providers.dart`
  - 新增 `TrackingIngestApi` Provider。
  - 新增 `TrackingUploadService` Provider。
  - 将追踪上传接入 `ClientBootstrapService`。

- `client_flutter/lib/features/files/services/local_file_identity_service.dart`
  - 新增本地文件 sha256 身份识别服务。

- `client_flutter/lib/features/files/services/file_context_interaction_service.dart`
  - 打开文件前计算真实本地 hash。
  - 调用服务端 open-plan。
  - hash 匹配后登记 device-location 并打开本地文件。
  - remote-only / missing local copy 写入操作日志。

- `client_flutter/lib/features/files/services/file_transfer_service.dart`
  - 新增 `downloadPreparedSession()`，支持从云盘 download-request 返回的 session 直接进入传输下载。
  - 下载方法返回完成后的 `FileTransferJob`，供文件中心登记本地副本。

- `client_flutter/lib/features/files/presentation/file_context_page.dart`
  - remote-only 文件允许点击打开按钮触发 open-plan。
  - `download_then_open` 时弹出确认框，选择保存位置，创建下载请求，进入传输中心。

### 服务端

- `server/src/files/files.service.ts`
  - 收紧 `driveOpenPlan` 的本地打开判断，只允许 hash/provider id 高置信度匹配直接打开。

---

## 手动验证建议

### 服务端

```powershell
cd C:\Users\a2746\Desktop\calll260426\server
npm run build
npm run db:schema
npm run dev
```

### 客户端

由用户手动执行：

```powershell
cd C:\Users\a2746\Desktop\calll260426\client_flutter
flutter analyze
flutter build windows
flutter build apk --debug
flutter build web
```

### 追踪上传验证

1. 启动服务端。
2. 启动 Windows 客户端。
3. 保持追踪采集一段时间，生成 `activity_records` / `tracked_input_events`。
4. 在同步页点击“立即同步全部”。
5. 检查服务端：
   - `tracking_ingest_batches` 出现 `completed` 批次。
   - `tracking_ingest_chunks` 出现对应分块。
   - `sync_objects` 出现追踪对象。
   - 管理端能看到 tracking ingest batch/chunk。

### 云盘 hash 打开验证

1. 服务端存在一个 `file_node` 和对应 `file_storage_object`。
2. 客户端本地 Root 目录存在同相对路径文件。
3. 文件内容与服务端 hash 一致。
4. 点击文件中心中的该文件。
5. 预期：
   - 客户端计算本地 sha256。
   - 服务端 open-plan 返回 `open_local`。
   - 客户端登记 `file_node_device_locations`。
   - 客户端直接调用本地默认程序打开。
6. 修改本地文件内容后再次点击。
7. 预期：
   - 服务端不返回 `open_local`。
   - 客户端不自动覆盖、不直接打开。
   - 后续应进入下载/重新定位确认流程。

---

## 下一步最小任务

1. 在文件中心增加“需要下载 / hash 不一致 / 需要重新定位”的弹窗。
2. 弹窗确认后调用 `createDownloadRequest` 并交给 `FileTransferService` 下载。
3. 下载完成后再次计算 hash，登记 `device-location`。
4. 增加 `cloud_drive_local_bindings` 本地绑定模型。
5. 同步页展示追踪上传状态：
   - 待上传数量
   - 最近上传时间
   - 最近错误
6. Android 端补 SAF Root 绑定和后台上传策略。
