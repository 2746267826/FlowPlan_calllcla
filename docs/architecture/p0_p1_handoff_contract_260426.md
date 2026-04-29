# FlowPlan P0 -> P1 交接契约：同步、API 与数据映射草案（2026-04-26）

## 1. 文档定位

本文是 P0 的可执行交接件，用于指导 P1 开发。

它不实现代码，但把 P1 第一版服务端、客户端同步模块、DTO、同步元数据、冲突模型和 API 形态提前定清，避免进入开发后反复改方向。

## 2. P1 最小目标

P1 只做“能可信同步”的最小闭环：

```text
客户端本地写入
  -> 离线变更队列
  -> /sync/push 上传
  -> 服务端写完整事实库
  -> /sync/pull 拉取其他端变更
  -> 客户端落地并更新 sync_state
  -> 冲突进入候选，不静默覆盖
```

P1 不做复杂 AI、不做 OneDrive、不做完整统计、不做 Web 管理面板全功能。

## 3. 第一批同步对象

| 顺序 | 对象 | 本地来源 | 服务端对象名 | P1 策略 |
| --- | --- | --- | --- | --- |
| 1 | 用户 | 新增 | `User` | 服务端为准 |
| 2 | 设备 | 新增 device identity | `Device` | 服务端为准 |
| 3 | 日历本 | `event_calendars` | `CalendarBook` | 字段级冲突 |
| 4 | 任务本 | `task_lists` | `TaskList` | 字段级冲突 |
| 5 | 日程 | `calendar_events` | `CalendarEvent` | 字段级冲突 |
| 6 | 任务 | `task_items` | `TaskItem` | 字段级冲突 |
| 7 | 排程片段 | `task_schedule_segments` | `TaskScheduleSegment` | 字段级冲突 |
| 8 | 操作审计 | `data_operation_logs` | `AuditLog` | 只追加 |
| 9 | 跨端设置 | `app_settings` 子集 | `UserSetting` | 按 key 冲突 |

实际记录表尚未存在，应在 P4 正式实现；但 P1 的同步模型需要提前预留 `actual_activity_logs` 对象类型。

## 4. 本地同步元数据

每个需要同步的可变对象都应增加或通过旁表关联以下元数据：

```text
local_id             本地自增主键或本地标识
server_id            服务端 UUID
uid                  跨系统稳定业务 UID，已有 calendar_events/task_items 可复用
owner_user_id         服务端用户
origin_device_id      首次创建设备
last_modified_device_id 最近修改设备
created_at            创建时间
updated_at            更新时间
deleted_at            软删除时间
local_version         本地版本
server_version        服务端版本
sync_state            synced / pending_create / pending_update / pending_delete / conflict / failed
last_synced_at        最近同步完成时间
last_sync_error       最近同步错误
```

### 4.1 推荐实现方式

P1 推荐先使用旁表，降低对现有 Drift 表的侵入：

```sql
sync_object_states
  object_type TEXT NOT NULL
  local_id TEXT NOT NULL
  server_id TEXT
  uid TEXT
  sync_state TEXT NOT NULL
  local_version INTEGER NOT NULL DEFAULT 1
  server_version INTEGER
  origin_device_id TEXT
  last_modified_device_id TEXT
  created_at TEXT NOT NULL
  updated_at TEXT NOT NULL
  deleted_at TEXT
  last_synced_at TEXT
  last_sync_error TEXT
  PRIMARY KEY (object_type, local_id)
```

后续如果某些对象需要高频筛选，再把关键同步字段下沉到业务表。

## 5. 离线变更队列

客户端需要新增离线变更队列：

```sql
offline_mutations
  id INTEGER PRIMARY KEY AUTOINCREMENT
  mutation_uid TEXT NOT NULL UNIQUE
  object_type TEXT NOT NULL
  local_id TEXT NOT NULL
  server_id TEXT
  action TEXT NOT NULL              -- create / update / delete
  base_server_version INTEGER
  payload_json TEXT NOT NULL
  changed_fields_json TEXT
  created_at TEXT NOT NULL
  attempts INTEGER NOT NULL DEFAULT 0
  last_error TEXT
  status TEXT NOT NULL              -- pending / sending / acked / failed / conflict
```

原则：

- 本地写入先落本地库。
- 同步队列记录变更意图。
- 网络差时不阻塞用户。
- `pending_*` 状态必须在 UI 可见。
- 上传失败保留队列，不丢弃。

## 6. 最小 API 契约

### 6.1 认证与设备

```text
POST /auth/login
POST /auth/refresh
POST /auth/logout

POST /devices/register
GET  /devices
PATCH /devices/{deviceId}
POST /devices/{deviceId}/heartbeat
```

设备注册返回：

```json
{
  "deviceId": "uuid",
  "deviceName": "Windows Desktop",
  "platform": "windows",
  "serverTime": "2026-04-26T17:30:00+08:00"
}
```

### 6.2 推送本地变更

```text
POST /sync/push
```

请求：

```json
{
  "deviceId": "uuid",
  "clientBatchId": "uuid",
  "mutations": [
    {
      "mutationUid": "uuid",
      "objectType": "calendar_event",
      "localId": "12",
      "serverId": null,
      "uid": "event-uid",
      "action": "create",
      "baseServerVersion": null,
      "changedFields": ["summary", "dtstart", "dtend"],
      "payload": {
        "summary": "课程",
        "dtstart": "2026-04-27T08:00:00+08:00",
        "dtend": "2026-04-27T09:40:00+08:00"
      }
    }
  ]
}
```

响应：

```json
{
  "serverBatchId": "uuid",
  "accepted": [
    {
      "mutationUid": "uuid",
      "objectType": "calendar_event",
      "localId": "12",
      "serverId": "uuid",
      "serverVersion": 1
    }
  ],
  "conflicts": [],
  "rejected": []
}
```

### 6.3 拉取服务端变更

```text
GET /sync/pull?cursor=...
```

响应：

```json
{
  "nextCursor": "opaque-cursor",
  "serverTime": "2026-04-26T17:30:00+08:00",
  "changes": [
    {
      "changeId": "uuid",
      "objectType": "task_item",
      "serverId": "uuid",
      "uid": "task-uid",
      "action": "upsert",
      "serverVersion": 4,
      "updatedAt": "2026-04-26T17:20:00+08:00",
      "payload": {}
    }
  ]
}
```

### 6.4 确认已落地

```text
POST /sync/ack
```

请求：

```json
{
  "deviceId": "uuid",
  "cursor": "opaque-cursor",
  "appliedChangeIds": ["uuid"]
}
```

### 6.5 冲突处理

```text
GET  /sync/conflicts
POST /sync/conflicts/{conflictId}/resolve
```

冲突候选结构：

```json
{
  "conflictId": "uuid",
  "objectType": "task_item",
  "serverId": "uuid",
  "baseVersion": 3,
  "localVersion": 4,
  "serverVersion": 5,
  "fields": [
    {
      "field": "summary",
      "base": "旧标题",
      "local": "本机标题",
      "server": "手机标题"
    }
  ]
}
```

## 7. 对象 DTO 草案

### 7.1 CalendarBook

```json
{
  "id": "uuid",
  "name": "工作日历",
  "colorHex": "#6B5EE4",
  "description": null,
  "isVisible": true,
  "isDefault": false,
  "source": "local",
  "syncUrl": null,
  "createdAt": "2026-04-26T17:30:00+08:00",
  "updatedAt": "2026-04-26T17:30:00+08:00",
  "deletedAt": null
}
```

### 7.2 CalendarEvent

```json
{
  "id": "uuid",
  "uid": "event-uid",
  "calendarBookId": "uuid",
  "summary": "课程",
  "description": null,
  "location": "教学楼 A101",
  "dtstart": "2026-04-27T08:00:00+08:00",
  "dtend": "2026-04-27T09:40:00+08:00",
  "rrule": null,
  "status": "CONFIRMED",
  "transp": "OPAQUE",
  "source": "local",
  "colorHex": "#6B5EE4",
  "isBlock": true,
  "createdAt": "2026-04-26T17:30:00+08:00",
  "updatedAt": "2026-04-26T17:30:00+08:00",
  "deletedAt": null
}
```

### 7.3 TaskList

```json
{
  "id": "uuid",
  "name": "收件箱",
  "colorHex": "#0EA8A0",
  "emoji": "收",
  "isVisible": true,
  "isDefault": true,
  "isArchived": false,
  "createdAt": "2026-04-26T17:30:00+08:00",
  "updatedAt": "2026-04-26T17:30:00+08:00",
  "deletedAt": null
}
```

### 7.4 TaskItem

```json
{
  "id": "uuid",
  "uid": "task-uid",
  "taskListId": "uuid",
  "summary": "写报告",
  "description": null,
  "dtstart": null,
  "due": "2026-04-28T18:00:00+08:00",
  "completed": null,
  "priority": 0,
  "status": "NEEDS-ACTION",
  "percentComplete": 0,
  "categories": [],
  "rrule": null,
  "durationMinutes": 60,
  "isSplittable": false,
  "priorityLocal": 2,
  "isAutoScheduled": true,
  "tagId": null,
  "isLocked": false,
  "reminderMinutesBefore": 15,
  "createdAt": "2026-04-26T17:30:00+08:00",
  "updatedAt": "2026-04-26T17:30:00+08:00",
  "deletedAt": null
}
```

### 7.5 TaskScheduleSegment

```json
{
  "id": "uuid",
  "taskId": "uuid",
  "segmentIndex": 0,
  "startAt": "2026-04-27T10:00:00+08:00",
  "endAt": "2026-04-27T11:00:00+08:00",
  "source": "manual",
  "planRunId": null,
  "note": null,
  "createdAt": "2026-04-26T17:30:00+08:00",
  "updatedAt": "2026-04-26T17:30:00+08:00",
  "deletedAt": null
}
```

### 7.6 AuditLog

```json
{
  "id": "uuid",
  "occurredAt": "2026-04-26T17:30:00+08:00",
  "actor": "user",
  "action": "task.create",
  "entityType": "task_item",
  "entityId": "uuid",
  "summary": "创建任务",
  "before": null,
  "after": {},
  "metadata": {}
}
```

## 8. 服务端最小模块

P1 服务端只需要以下模块：

```text
server/
  auth/
  devices/
  sync/
  calendar/
  task/
  scheduler/
  audit/
  common/
```

P2 以后再加入：

```text
analytics/
tracker/
files/
storage/
reports/
notifications/
ai/
admin_panel/
```

## 9. 客户端最小模块

P1 Flutter 客户端新增：

```text
client_flutter/lib/core/server_api/
  api_client.dart
  api_error.dart
  auth_token_store.dart

client_flutter/lib/core/sync/
  sync_engine.dart
  sync_object_registry.dart
  sync_cursor_store.dart
  sync_status.dart
  conflict_snapshot.dart

client_flutter/lib/core/offline_queue/
  offline_mutation.dart
  offline_mutation_store.dart
  offline_mutation_runner.dart
```

业务模块新增各自的同步适配器：

```text
client_flutter/lib/features/calendar/sync/
client_flutter/lib/features/task/sync/
client_flutter/lib/features/scheduler/sync/
client_flutter/lib/features/audit/sync/
```

## 10. P1 验收口径

P1 完成时应满足：

- 断网时可以创建/修改日程和任务。
- 本地新建或修改对象显示未同步状态。
- 恢复网络后可以上传到服务端。
- 另一个设备可以拉取服务端变更。
- 同一字段多端修改进入冲突候选。
- 冲突不静默覆盖。
- 操作审计可以追加同步。
- 服务端能查看设备状态和同步游标。

## 11. P1 不应扩大到的范围

P1 不做：

- AI 聊天。
- Telegram 推送。
- OneDrive。
- 文件预览。
- 位置、天气、蓝牙。
- 完整 Web 管理面板。
- 追踪大数据统计全量重构。

P1 的成功标准是同步可信，而不是功能丰富。
