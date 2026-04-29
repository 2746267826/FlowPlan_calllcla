<!--
Codex 阅读说明：
1. 本文件是实现规格参考。
2. 本次只处理用户明确指定的模块和任务。
3. 文中的“给 Codex 的提示词”只是可复制模板，不要自动执行。
4. 严禁运行 flutter / dart 命令。
-->

# FlowPlan 01：详细实现方式讨论稿 v2

> 用途：这份文档负责讨论每个模块到底怎么做。  
> `00_progress_plan.md` 负责看进度；本文件负责写实现细节。  
> 建议每次只细化一个模块，确认后再进入下一个模块。

## Codex 阅读说明

本文档正文是“实现规格”，不是要求 Codex 自动一次性执行所有内容。

每个模块末尾的“给 Codex 的提示词”应视为可复制的任务模板。让 Codex 自主读取本文档时，应该明确告诉它：

```text
请把本文档作为实现规格参考，不要自动执行所有提示词。
本次只处理我指定的一个模块和一个任务。
模块末尾的 Codex 提示词只是可复制模板，除非我明确指定，否则不要逐条执行。
```

建议长期做法：

- `00_progress_plan.md`：给 Codex 作为进度和状态规则参考。
- `01_detailed_implementation_spec.md`：给 Codex 作为实现规格参考。
- 每次单独发一条明确提示词：指定模块、目标状态、是否允许改代码、是否允许运行命令。

---

## 0. 每个模块固定讨论格式

后续每一部分都按这个结构讨论，避免变成泛泛而谈。

```md
## 模块名称

### 1. 目标
这个模块最终要解决什么问题，给用户什么能力。

### 2. 用户流程
用户具体怎么点、怎么输入、怎么看到结果，失败时怎么处理。

### 3. 数据模型
本地数据库、服务端数据库、关键字段、状态枚举、同步标记。

### 4. 服务端实现
NestJS 模块、Controller、Service、Repository、后台任务、审计日志。

### 5. Flutter 客户端实现
页面、Provider、Repository、本地数据库、离线队列、状态展示。

### 6. Web 管理端实现
管理端能看什么、查什么、修什么、审计什么。

### 7. 同步、离线与冲突
断网如何处理，多端如何同步，冲突如何产生和解决。

### 8. 异常与边界情况
网络错误、数据损坏、重复提交、权限失败、服务端不可用等。

### 9. 安全与隐私
哪些数据敏感，哪些操作必须确认，哪些内容不能发给第三方 AI。

### 10. 验收标准
从骨架到 MVP、验证可用、稳定可用的标准。

### 11. 给 Codex 的提示词
拆成可执行的小任务，让 Codex 不要乱做。
```

---
---

## 建议给 Codex 的使用方式

每次只发一个模块文件，并额外附上一条明确任务，例如：

```text
请只阅读 docs/flowplan_modules/03_G_智能排程.md。
本次只复核当前代码真实状态，不要开发新功能，不要运行 flutter 或 dart 指令。
请按文档末尾的“复核当前智能排程真实状态”格式输出。
```

推荐文件职责：

- `00_README_FOR_CODEX.md`：长期公共说明、阅读规则、固定模块格式。
- `01_D_离线同步与冲突处理.md` 等：每次只给 Codex 当前要处理的模块。
- 原始总文档可以保留，但不要每次都喂给 Codex。

---

# 第六部分：J 云文件、OneDrive 与历史版本

## 1. 目标

J 模块的目标是让 FlowPlan 文件中心不仅能管理本地资料，还能统一接入服务端存储、OneDrive 和历史版本系统。

它解决的问题不是“怎么在设备之间传文件”，那是 I 模块；也不是“怎么像网盘一样浏览本地资料”，那是 H 模块。J 负责的是：

```text
本地文件中心
  + 服务端对象存储
  + OneDrive 文件树
  + Kopia 历史版本
  + 云端冲突处理
  + 旧版本下载/恢复
  -> 统一云文件和版本能力
```

最终用户应该能做到：

1. 在 FlowPlan 文件中心看到本地文件、服务端文件、OneDrive 文件。
2. 未下载的云端文件点击时提示下载。
3. 下载到手机或电脑时保留目录层级。
4. 同一个任务能看到相关的本地资料、服务端资料、OneDrive 资料。
5. 文件冲突时保留双版本，不静默覆盖。
6. 文件详情中能看到历史版本列表。
7. 历史版本由 Kopia 作为底层软件生成和管理。
8. 用户可以下载某个历史版本为副本。
9. 用户可以恢复旧版本，但必须二次确认，并且恢复前保留当前版本。
10. 所有云文件和版本操作都写入审计。

一句话目标：

```text
FlowPlan 统一管理文件在哪、云端有没有、历史版本有哪些，但不静默覆盖用户文件。
```

---

## 2. 与 H/I 模块的边界

### 2.1 H 负责什么

H 负责文件中心体验：

```text
资料库 Root
文件树索引
文件元数据
任务/日程关联
最近使用
推荐
预览
打开
路径失效修复
```

### 2.2 I 负责什么

I 负责传输过程：

```text
服务端中转
局域网直连
P2P
分块上传
断点续传
传输进度
hash 校验
```

### 2.3 J 负责什么

J 负责文件后端和版本能力：

```text
服务端对象存储
OneDrive OAuth 和文件树同步
云端文件下载状态
云端和本地同一性判断
文件冲突候选
Kopia 历史版本
旧版本下载为副本
旧版本恢复确认
```

不要把三者混在一起。J 可以调用 I 的传输能力，也可以向 H 提供文件树和版本信息。

---

## 3. 用户流程

### 3.1 添加服务端文件后端

```text
用户打开文件中心设置
  -> 选择“服务端存储”
  -> 系统显示服务端对象存储状态
  -> 用户选择一个资料库 Root 开启服务端同步
  -> FlowPlan 将本地文件元数据同步到服务端
  -> 需要上传内容时调用 I 模块传输
  -> 服务端生成 file_storage_objects
```

用户看到：

```text
课程资料
  本地：可用
  服务端：已同步
  历史版本：已启用 Kopia 快照
```

### 3.2 添加 OneDrive 后端

```text
用户打开文件中心设置
  -> 选择“连接 OneDrive”
  -> 进入 Microsoft 登录授权
  -> 授权成功后服务端保存 token
  -> 服务端拉取 OneDrive 文件树
  -> 文件中心出现 OneDrive 资料库
```

用户看到：

```text
OneDrive
  学校
  文档
  课程资料
  项目资料
```

注意：

- OneDrive 连接是 J 的能力。
- OneDrive 文件内容下载时调用 I 的下载能力。
- OneDrive 文件树进入 H 的 file_nodes 统一展示。

### 3.3 点击未下载云端文件

```text
用户点击 OneDrive/report.docx
  -> 系统发现本地没有缓存
  -> 提示“该文件仅在云端，是否下载？”
  -> 用户确认
  -> 创建下载任务
  -> 下载到本地资料库缓存目录
  -> 保留 OneDrive 相对路径
  -> 更新 file_node_device_locations
  -> 调系统默认程序打开
```

### 3.4 服务端和 OneDrive 同一文件冲突

```text
本地 report.md 修改后上传到服务端
OneDrive 上 report.md 也被修改
服务端同步时发现 hash / mtime / version 不一致
  -> 不覆盖
  -> 生成 file_conflict_candidates
  -> 用户看到两个版本
  -> 用户选择保留本地、保留 OneDrive、另存双版本、手动合并
```

### 3.5 查看历史版本

```text
用户打开文件详情
  -> 点击“历史版本”
  -> FlowPlan 查询 Kopia 快照映射
  -> 显示该文件的历史版本列表
  -> 每个版本显示时间、来源设备、大小、快照 ID、备注
```

用户看到：

```text
report.md 历史版本
- 2026-04-27 22:30  Windows 主机  34KB  Kopia snapshot: kxxxx
- 2026-04-26 19:15  Windows 主机  31KB  Kopia snapshot: kyyyy
- 2026-04-25 11:08  Android 手机  29KB  服务端版本
```

### 3.6 下载旧版本为副本

```text
用户选择 2026-04-26 版本
  -> 点击“下载副本”
  -> FlowPlan 调用 Kopia restore 或 mount 读取该版本
  -> 保存为 report_2026-04-26.md
  -> 不覆盖当前 report.md
  -> 写入 file_version_download_requests 和审计
```

这是默认策略。

### 3.7 恢复旧版本覆盖当前版本

这是高风险操作，必须二次确认。

```text
用户选择旧版本
  -> 点击“恢复为当前版本”
  -> 系统提示：这会用旧版本替换当前文件
  -> 系统先为当前版本创建新快照或备份副本
  -> 用户二次确认
  -> 执行恢复
  -> 当前版本被替换
  -> 原当前版本仍可在历史版本中找到
  -> 写入严格审计
```

恢复旧版本永远不能静默覆盖。

---

## 4. 后端选择和复用软件

### 4.1 服务端对象存储

推荐：

```text
开发期：本机目录或 MinIO
生产期：S3 兼容对象存储，例如 MinIO / S3
```

不要把文件内容长期存 PostgreSQL。PostgreSQL 保存文件元数据、对象 ID、hash、版本、状态；文件内容进入对象存储。

### 4.2 OneDrive

OneDrive 使用 Microsoft Graph。

关键能力：

```text
OAuth 授权
driveItem 文件树读取
delta 增量同步
createUploadSession 大文件上传
下载云端文件
删除/移动/重命名检测
```

原则：

- OneDrive 文件树不要每次点击才一级一级加载。
- 首次同步应尽量建立完整树快照。
- 后续使用 delta 增量同步。
- 大文件上传使用 upload session 思路。
- 写入 OneDrive 属于外部系统写入，必须确认和审计。

### 4.3 Kopia 历史版本

Kopia 是 J 模块历史版本能力的核心底层软件。

FlowPlan 不应该自己从零实现完整版本备份系统，而应调用 Kopia 负责：

```text
创建快照 snapshot
列出快照 snapshot list
浏览快照内容
挂载快照 mount
恢复文件 snapshot restore
保存到本地或对象存储仓库
加密和压缩历史版本数据
```

FlowPlan 自己负责：

```text
把 Kopia snapshot 映射到 file_node
在文件详情中展示历史版本
记录版本来源、时间、设备、备注
触发下载旧版本为副本
触发恢复旧版本前的二次确认
写入审计
```

### 4.4 rclone 的定位

rclone 可以作为未来云盘后端适配层候选。

它适合：

```text
统一接入 OneDrive、WebDAV、S3、Google Drive 等云盘
命令行复制、同步、挂载
服务端批量迁移或后台任务
```

但首版不建议把 FlowPlan 核心文件逻辑绑定死到 rclone。OneDrive 首版可以优先使用 Microsoft Graph 原生接口；rclone 作为高级后端或运维工具保留。

---

## 5. 数据模型

### 5.1 文件后端：`file_providers`

```text
id
user_id
provider_type           local / server_storage / onedrive / webdav / rclone
name
status                  disconnected / connected / error / disabled
auth_status             none / valid / expired / revoked / error
capabilities_json       upload / download / delta / versioning / range / thumbnail
priority
sync_mode               metadata_only / on_demand / full_mirror
config_json             不保存明文密钥
created_at
updated_at
last_sync_at
last_error
```

### 5.2 云端文件树：`cloud_file_tree_nodes`

```text
id
user_id
provider_id
parent_id
provider_file_id        OneDrive driveItemId / object key / rclone path
node_type               folder / file
name
path
mime_type
size_bytes
mtime
ctime
etag
c_tag
sha256
quick_xor_hash          OneDrive 可用时保存
is_deleted
is_remote_only
created_at
updated_at
```

### 5.3 服务端存储对象：`file_storage_objects`

```text
id
user_id
provider_id
node_id
object_key
bucket
size_bytes
sha256
content_type
storage_status          pending / available / failed / deleted
created_from_session_id
created_at
updated_at
```

### 5.4 文件同一性映射：`file_identity_mappings`

用于判断本地、服务端、OneDrive 是否是同一个逻辑文件。

```text
id
user_id
logical_file_id
local_node_id
cloud_node_id
storage_object_id
provider_type
identity_method         provider_id / hash / path_size_mtime / manual
confidence
status                  active / conflict / stale / rejected
created_at
updated_at
```

### 5.5 文件冲突候选：`file_conflict_candidates`

```text
id
user_id
logical_file_id
base_version_id
local_version_id
remote_version_id
conflict_type           content_changed / deleted_vs_modified / rename_conflict / path_conflict
local_summary_json
remote_summary_json
status                  open / resolved / ignored
resolution              keep_local / keep_remote / keep_both / manual_merge
created_at
resolved_at
```

### 5.6 Kopia 仓库配置：`kopia_repositories`

```text
id
user_id
name
repository_type         local / filesystem / s3 / server_storage
repository_uri
status                  uninitialized / connected / error / disabled
is_encrypted            true / false
last_snapshot_at
last_check_at
last_error
created_at
updated_at
```

注意：

- 不在普通配置表里保存 Kopia 明文密码。
- 密钥应进入安全存储或服务端加密配置。

### 5.7 Kopia 快照记录：`kopia_snapshots`

```text
id
user_id
repository_id
snapshot_id
source_root_id
source_path
hostname
device_id
started_at
completed_at
status                  completed / partial / failed
description
raw_metadata_json
created_at
```

### 5.8 文件历史版本：`file_versions`

```text
id
user_id
logical_file_id
node_id
version_source          kopia / server_storage / onedrive / manual_backup
kopia_snapshot_id
kopia_object_id
provider_version_id
size_bytes
sha256
mtime
created_by_device_id
version_time
notes
status                  available / missing / corrupted / downloading / restored
created_at
```

### 5.9 历史版本下载请求：`file_version_download_requests`

```text
id
user_id
file_version_id
target_device_id
target_mode             copy / restore_preview / replace_current
output_path
status                  pending / running / completed / failed / cancelled
requires_confirmation   true / false
confirmed_at
error_message
created_at
completed_at
```

---

## 6. 服务端实现

建议 NestJS 模块：

```text
server/src/modules/cloud-files/
  cloud-files.module.ts
  cloud-files.controller.ts
  cloud-files.service.ts
  file-provider.service.ts
  onedrive.service.ts
  object-storage.service.ts
  file-identity.service.ts
  file-conflict.service.ts
  cloud-files.repository.ts
  cloud-files.types.ts

server/src/modules/file-versioning/
  file-versioning.module.ts
  file-versioning.controller.ts
  kopia.service.ts
  file-version.service.ts
  version-restore.service.ts
  file-versioning.repository.ts
  file-versioning.types.ts
```

### 6.1 云文件 API

#### 文件后端列表

```text
GET /cloud-files/providers
POST /cloud-files/providers
PATCH /cloud-files/providers/:id
DELETE /cloud-files/providers/:id
```

#### OneDrive 授权

```text
POST /cloud-files/onedrive/auth/start
POST /cloud-files/onedrive/auth/callback
POST /cloud-files/onedrive/auth/refresh
POST /cloud-files/onedrive/disconnect
```

#### 云端文件树

```text
POST /cloud-files/providers/:id/sync-tree
GET /cloud-files/providers/:id/tree?parentId=...
GET /cloud-files/nodes/:id
```

#### 文件下载到本地设备

```text
POST /cloud-files/nodes/:id/download-request
```

实际下载由 I 模块执行。

#### 文件冲突

```text
GET /cloud-files/conflicts
POST /cloud-files/conflicts/:id/resolve
POST /cloud-files/conflicts/:id/ignore
```

### 6.2 历史版本 API

#### Kopia 仓库

```text
GET /file-versioning/kopia/repositories
POST /file-versioning/kopia/repositories
POST /file-versioning/kopia/repositories/:id/check
POST /file-versioning/kopia/repositories/:id/snapshot
```

#### 快照和版本

```text
GET /file-versioning/snapshots
GET /file-versioning/files/:nodeId/versions
POST /file-versioning/files/:nodeId/snapshot-now
```

#### 下载旧版本

```text
POST /file-versioning/versions/:versionId/download-copy
```

#### 恢复旧版本

```text
POST /file-versioning/versions/:versionId/prepare-restore
POST /file-versioning/restore-requests/:id/confirm
POST /file-versioning/restore-requests/:id/cancel
```

恢复必须拆成 prepare 和 confirm 两步。

---

## 7. OneDrive 实现策略

### 7.1 授权和 token

OneDrive 需要 OAuth 授权。

要求：

- token 服务端加密保存。
- 管理端只显示连接状态，不显示 token。
- token 过期时自动 refresh。
- refresh 失败时标记 auth_status = expired。
- 用户可以断开连接。

### 7.2 文件树首次同步

```text
调用 OneDrive root children / delta
  -> 分页拉取完整树
  -> 写入 cloud_file_tree_nodes
  -> 保存 deltaLink
```

### 7.3 增量同步

```text
定期或手动调用 deltaLink
  -> 获取新增、修改、删除项
  -> 更新 cloud_file_tree_nodes
  -> 删除项标记 is_deleted
  -> 检查本地映射和冲突
```

### 7.4 大文件上传

使用 upload session 思路。

```text
创建 OneDrive upload session
  -> 按 range 上传字节
  -> 失败后根据 session 状态继续
  -> 完成后更新 driveItem
```

注意：写入 OneDrive 属于外部系统写操作，必须用户确认。

### 7.5 OneDrive 占位文件

如果本地 OneDrive 客户端存在占位文件：

```text
FlowPlan 识别 remote_only
  -> 点击时提示下载
  -> 可调用系统/OneDrive 下载，也可通过 Graph 下载到 FlowPlan 缓存
```

---

## 8. 服务端对象存储实现策略

### 8.1 开发期

开发期可以先用：

```text
server_storage/objects/
server_storage/tmp/
```

但要抽象成 ObjectStorageService，避免后续难迁移。

### 8.2 生产期

生产期建议使用 S3 兼容对象存储，例如 MinIO。

对象 key 建议：

```text
users/{user_id}/files/{logical_file_id}/versions/{version_id}/content
users/{user_id}/tmp_transfers/{session_id}/{chunk_index}.part
```

### 8.3 对象存储不等于历史版本

服务端对象存储可以保存当前文件或某些版本，但历史版本策略应该主要交给 Kopia。

区别：

```text
对象存储：保存文件内容和云端可用副本
Kopia：保存快照、版本历史、恢复点
```

---

## 9. Kopia 历史版本设计

### 9.1 Kopia 的定位

Kopia 是 FlowPlan 历史版本的底层软件。

FlowPlan 不直接实现完整备份算法，而是：

```text
调用 Kopia 创建 snapshot
调用 Kopia 查询 snapshot
调用 Kopia mount 或 restore 读取旧版本
把 Kopia 结果映射成 FlowPlan 文件版本
在 UI 中展示给用户
```

### 9.2 快照策略

推荐三类快照：

| 类型 | 触发条件 | 说明 |
|---|---|---|
| 定时快照 | 每天/每几小时 | 保护资料库整体历史 |
| 操作前快照 | 覆盖、恢复、批量移动前 | 防止误操作 |
| 手动快照 | 用户点击“创建历史版本” | 用户主动保存当前状态 |

### 9.3 快照范围

Kopia 快照对象应该主要是资料库 Root，而不是每个文件都单独配置一个备份任务。

```text
file_root: 课程资料
  -> Kopia snapshot D:/课程资料
```

FlowPlan 再通过相对路径把某个 file_node 映射到快照中的文件版本。

### 9.4 历史版本列表生成

```text
用户打开 report.md 历史版本
  -> 找到所属 file_root
  -> 查询该 root 的 Kopia snapshots
  -> 在每个 snapshot 中检查 report.md 相对路径是否存在
  -> 读取 size、mtime、hash 或 metadata
  -> 生成 file_versions
  -> 展示给用户
```

### 9.5 下载旧版本为副本

默认操作。

```text
用户选择版本
  -> FlowPlan 调 Kopia restore 到临时目录或目标副本路径
  -> 输出文件名带时间戳
  -> 不覆盖当前文件
  -> 更新 file_nodes 或 recent_items
  -> 写入审计
```

### 9.6 预览旧版本

可选增强：

```text
Kopia mount snapshot
  -> 从挂载目录读取旧版本文件
  -> FlowPlan 预览
  -> 用户决定是否下载或恢复
```

### 9.7 恢复旧版本

高风险流程：

```text
用户点击“恢复此版本”
  -> 系统显示当前版本和旧版本对比
  -> 系统先为当前文件创建操作前快照
  -> 用户二次确认
  -> Kopia restore 旧版本到当前路径
  -> 更新 file_nodes hash/mtime
  -> 写入 file_versions 和 audit_log
```

恢复要求：

- 必须二次确认。
- 必须保留当前版本。
- 必须写审计。
- 必须处理文件被占用、权限不足、路径失效。

### 9.8 Kopia 命令封装

不要让业务代码到处直接拼命令。

封装为：

```text
KopiaService
  connectRepository()
  checkRepository()
  createSnapshot(rootPath)
  listSnapshots(rootPath)
  listFiles(snapshotId, relativePath)
  restoreFile(snapshotId, relativePath, targetPath)
  mountSnapshot(snapshotId)
  unmountSnapshot(mountId)
```

KopiaService 负责：

- 命令执行。
- 超时控制。
- stdout/stderr 解析。
- 错误码转换。
- 审计事件。

---

## 10. Flutter 客户端实现

建议目录：

```text
client_flutter/lib/features/cloud_files/
  data/
    cloud_file_provider_repository.dart
    cloud_file_tree_repository.dart
    file_conflict_repository.dart
  services/
    cloud_file_api.dart
    onedrive_download_service.dart
    cloud_file_sync_service.dart
  presentation/
    cloud_file_center_section.dart
    cloud_provider_settings_page.dart
    onedrive_connect_page.dart
    cloud_file_tree_view.dart
    cloud_download_dialog.dart
    file_conflict_page.dart

client_flutter/lib/features/file_versions/
  data/
    file_version_repository.dart
    file_version_download_repository.dart
  services/
    file_version_api.dart
    local_version_preview_service.dart
  presentation/
    file_version_panel.dart
    file_version_detail_dialog.dart
    file_version_restore_confirm_dialog.dart
```

### 10.1 文件详情中的云状态

文件详情页显示：

```text
本地状态：可用 / 缺失 / 路径失效
服务端状态：未上传 / 已同步 / 上传中 / 冲突
OneDrive 状态：未连接 / 云端存在 / 仅云端 / 冲突
历史版本：3 个版本
```

### 10.2 历史版本面板

显示：

```text
版本时间
来源：Kopia / 服务端 / OneDrive
设备
大小
备注
操作：预览 / 下载副本 / 恢复
```

默认突出“下载副本”，弱化“覆盖恢复”。

### 10.3 恢复确认弹窗

必须显示：

```text
你将用 2026-04-26 19:15 的旧版本替换当前文件。
当前版本会先保存为新的历史版本。
此操作会修改本地文件，并可能同步到服务端或 OneDrive。
```

按钮：

```text
取消
下载副本
确认恢复
```

---

## 11. Web 管理端实现

建议页面：

```text
/admin/cloud-files/providers
/admin/cloud-files/tree
/admin/cloud-files/conflicts
/admin/file-versioning/kopia
/admin/file-versioning/snapshots
/admin/file-versioning/versions
/admin/file-versioning/restore-requests
```

管理端显示：

- 文件 Provider 状态。
- OneDrive 授权状态。
- 最近文件树同步时间。
- 云端节点数量。
- 冲突候选。
- Kopia 仓库状态。
- 最近快照。
- 历史版本下载请求。
- 恢复请求和确认状态。
- 错误日志。

管理端可以触发：

- 检查 Kopia 仓库。
- 手动创建快照。
- 刷新 OneDrive 文件树。
- 查看冲突。
- 标记恢复请求取消。

管理端不应默认直接恢复覆盖文件，除非有明确权限和二次确认。

---

## 12. 同步、离线与冲突

### 12.1 哪些数据同步

| 数据 | 同步策略 |
|---|---|
| file_providers | 同步配置摘要，密钥不下发明文 |
| cloud_file_tree_nodes | 同步元数据 |
| file_storage_objects | 服务端权威 |
| file_identity_mappings | 同步 |
| file_conflict_candidates | 同步 |
| kopia_repositories | 同步摘要和状态，不同步明文密钥 |
| kopia_snapshots | 同步元数据 |
| file_versions | 同步元数据 |
| file_version_download_requests | 同步请求状态 |
| 文件内容 | 通过 I 或后端 API 传输，不走普通对象同步 |

### 12.2 离线规则

| 场景 | 处理 |
|---|---|
| 离线查看历史版本列表 | 只能看已缓存元数据 |
| 离线下载旧版本 | 不可执行，进入待处理 |
| 离线恢复旧版本 | 不建议允许，除非旧版本副本已本地缓存 |
| 离线编辑本地文件 | 正常编辑，联网后进行云端冲突检测 |
| OneDrive token 过期 | 云端同步暂停，本地文件中心继续可用 |

### 12.3 冲突策略

| 场景 | 处理 |
|---|---|
| 本地修改，OneDrive 也修改 | 保留双版本，生成冲突 |
| 本地删除，云端修改 | 高风险冲突，人工确认 |
| 云端删除，本地仍存在 | 不自动删本地，生成候选 |
| 恢复旧版本后云端已有新版本 | 恢复生成新版本，不直接覆盖云端 |
| Kopia 快照缺失 | 标记版本 missing，不删除历史记录 |

---

## 13. 异常与边界情况

必须考虑：

1. OneDrive token 过期。
2. OneDrive 权限被撤销。
3. OneDrive 文件被移动或删除。
4. OneDrive deltaLink 失效，需要全量重扫。
5. 文件名在不同后端不兼容。
6. 本地文件和云端文件 hash 不一致。
7. 服务端对象存储不可用。
8. 对象存储上传成功但数据库写入失败。
9. Kopia 仓库不可访问。
10. Kopia 快照失败。
11. Kopia restore 失败。
12. 恢复旧版本时目标文件被占用。
13. 恢复旧版本时权限不足。
14. 历史版本太多导致 UI 卡顿。
15. 用户误操作恢复旧版本。
16. 同一个文件在多个后端出现不同版本。
17. 云端下载到一半中断。
18. 云文件元数据和本地缓存不一致。

处理原则：

- 不静默覆盖。
- 不删除仍有可能恢复的数据。
- 云端失败不影响本地文件中心基本可用。
- 历史版本恢复必须可撤销或至少保留恢复前版本。
- 所有高风险操作写审计。

---

## 14. 安全与隐私

云文件和历史版本涉及完整文件内容，必须保守。

规则：

- OneDrive token 加密保存。
- Kopia 仓库密码或密钥不能明文保存。
- 管理端只显示连接状态和遮罩信息。
- 文件内容默认不发给第三方 AI。
- 历史版本可能包含已删除的敏感内容，删除策略要单独设计。
- 用户可以关闭某个资料库的云同步和历史版本。
- 高敏感目录默认不启用全文索引。
- 恢复旧版本、覆盖云端文件、删除云端文件必须二次确认。
- 所有云端写入和版本恢复都写审计。

---

## 15. 验收标准

### `[B] 骨架完成`

满足：

- 有 file_providers。
- 有 cloud_file_tree_nodes。
- 有 file_storage_objects。
- 有 file_conflict_candidates。
- 有 file_versions 或历史版本元数据。
- 有历史版本下载请求表。
- 管理端能看到部分云文件状态。

### `[M] MVP 可用`

必须实测：

- 配置一个服务端存储后端。
- 本地文件能上传为服务端对象。
- 文件中心能显示服务端状态。
- Kopia 能对一个资料库 Root 创建快照。
- 文件详情能列出 Kopia 生成的历史版本。
- 用户能下载一个旧版本为副本。
- 下载副本不覆盖当前文件。
- 所有操作写入日志或审计。

### `[V] 已验证可用`

必须实测：

- OneDrive OAuth 真实连接成功。
- OneDrive 文件树能首次同步。
- OneDrive delta 增量同步可用。
- 未本地化文件点击时能下载。
- 下载后保留目录结构。
- 本地与 OneDrive 冲突不会覆盖任一版本。
- Kopia restore 可恢复旧版本。
- 恢复前能保留当前版本。
- 管理端能查看 Kopia 快照和恢复请求。

### `[S] 稳定可用`

必须具备：

- OneDrive token 过期和刷新测试。
- 对象存储故障测试。
- Kopia 仓库检查和恢复演练。
- 历史版本数量较大时性能可接受。
- 版本恢复有回滚方案。
- 云端冲突处理有完整测试。
- 多周真实使用未出现静默覆盖和版本丢失。

---

## 16. 给 Codex 的提示词：复核当前云文件与历史版本真实状态

```text
请阅读 docs/00_progress_plan.md 和 docs/01_detailed_implementation_spec.md，并重点复核 J：云文件、OneDrive 与历史版本。

本次任务只做复核，不要开发新功能，不要大范围修改代码。
不要运行 flutter 或 dart 指令。

请检查当前仓库中与云文件和历史版本相关的代码，包括但不限于：
- server/src/files/files.controller.ts
- server/src/files/files.service.ts
- server/src/database/p1_schema.sql 中的 file_providers、cloud_file_tree_nodes、file_storage_objects、file_conflict_candidates、file_version_download_requests
- client_flutter/lib/core/server_api/file_cloud_api.dart
- client_flutter/lib/features/files/ 中的 Kopia 历史版本元数据、文件详情、文件操作
- client_flutter/lib/features/sync/ms_graph_service.dart 是否只覆盖 Outlook，是否已有 OneDrive 文件树能力
- web_admin/src/main.tsx 中的云文件、历史版本、冲突和下载请求视图

请按以下格式输出：

1. 当前涉及的主要文件和目录。
2. 已经存在的能力。
3. 只是骨架、还不能算可用的能力。
4. OneDrive 是否真实 OAuth 和 Graph 文件树同步可用。
5. 服务端对象存储是否是真实 MinIO/S3/文件系统，还是只有数据库/接口骨架。
6. Kopia 是否已经作为历史版本底层软件接入，还是只有元数据占位。
7. 历史版本是否能真实下载副本、预览和恢复。
8. 缺失的用户流程。
9. 缺失的异常处理。
10. 缺失的 UI 或管理端入口。
11. 建议当前状态标记：[ ] / [~] / [B] / [M] / [V] / [S]。
12. 如果要推进到下一级状态，需要做哪些最小任务。
13. 用户需要手动验证的步骤。

注意：
- 不要把“有 file_versions 表”说成“历史版本完成”。
- 历史版本必须明确以 Kopia 为底层能力，并验证 snapshot、list、download copy、restore confirm 的闭环。
- OneDrive 文件树、服务端对象存储、Kopia 历史版本是三个不同能力，不要混为一谈。
```

---

## 17. 给 Codex 的提示词：把云文件与 Kopia 历史版本从 B 推进到 M

只有完成复核后，才使用这个提示词。

```text
请基于刚才对 J：云文件、OneDrive 与历史版本的复核结果 和 \docs\flowplan_modules\06_J_J_云文件、OneDrive_与历史版本.md，只把该模块从 [B] 骨架完成推进到 [M] MVP 可用。

本次不要做完整 OneDrive 双向同步，不要做复杂云端冲突合并，不要做 P2P，不要做 AI 文件理解。
只完成最小闭环：服务端存储 + Kopia 历史版本。

必须完成：

1. 明确服务端文件对象存储位置，开发期可以使用本机 server_storage 目录。
2. 本地文件能上传或登记为服务端存储对象。
3. 文件详情能显示服务端存储状态。
4. 接入 Kopia CLI，封装 KopiaService。
5. 用户能为一个资料库 Root 创建 Kopia 快照。
6. 系统能读取 Kopia snapshot 列表并映射到 file_versions。
7. 文件详情能显示该文件的历史版本列表。
8. 用户能选择某个历史版本下载为副本。
9. 下载副本不能覆盖当前文件。
10. 恢复旧版本只做 prepare，不直接覆盖；恢复覆盖必须二次确认，若本次来不及可先留为不可执行按钮。
11. 所有服务端存储、快照、下载副本操作写入日志或审计。

输出必须包含：
- 修改文件列表。
- 每个文件改了什么。
- Kopia CLI 调用方式和封装边界。
- 文件版本元数据如何从 Kopia snapshot 映射而来。
- 为什么本次仍然不是完整 OneDrive 可用。
- 用户需要手动安装或配置 Kopia 的步骤。
- 用户需要手动验证的步骤。
- 当前仍然不是 [V] 的原因。

不要运行 flutter 或 dart 指令，除非用户明确允许。
```



---
