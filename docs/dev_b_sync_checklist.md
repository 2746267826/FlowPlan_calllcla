# FlowPlan B sync checklist

Scope: B only. This checklist verifies task/event server-first writes, offline mutation push, pull/ack, and conflict visibility.

## Preconditions

- `server` is running with a valid `DATABASE_URL`.
- `web_admin` points to the same API base URL, for example `http://localhost:3200/api`.
- Windows client uses the same API base URL on the server sync page.
- Do not use this checklist for AI, files, reports, tracking, Outlook, or OneDrive validation.

## Server and web build checks

```powershell
cd server
npm run build
```

```powershell
cd web_admin
npm run build
```

## Task/event server-first checks

1. In the Windows client, create a task with a unique title.
2. Open Web Admin -> Tasks and refresh.
3. Expected: the task appears with a stable server id, uid, server version, and payload.
4. In the Windows client, create an event with a unique title and time.
5. Open Web Admin -> Schedules and refresh.
6. Expected: the event appears with a stable server id, uid, server version, and payload.

## Offline queue checks

1. Temporarily set the Windows client API base URL to an unreachable local URL.
2. Create a task.
3. Expected: the task remains visible locally and the UI reports pending sync.
4. Restore the API base URL.
5. Trigger sync from the server sync page.
6. Expected: Web Admin -> Tasks shows the task, and Web Admin -> Sync -> Mutations no longer shows that mutation as pending.

## Pull / ack checks

1. Change a task through Web Admin or the client API.
2. Trigger sync in the Windows client.
3. Expected: the local task reflects the server change.
4. Trigger sync again.
5. Expected: the local database does not create a duplicate task or event.
6. Web Admin -> Sync -> Changes and Devices should show the cursor advancing.

## Conflict checks

Minimum API-level simulation when two real clients are not available:

1. Client A creates and syncs a task.
2. Client B pulls the task.
3. Client A edits the same field while offline.
4. Client B edits and syncs the same field online.
5. Client A restores network and pushes.
6. Expected: the server returns a conflict instead of silently overwriting Client B.
7. Web Admin -> Sync -> Conflicts shows the conflict.
8. Resolve the conflict through the existing admin conflict flow.

PowerShell API smoke flow:

```powershell
$base = 'http://localhost:3200/api'
$user = '00000000-0000-4000-8000-000000000001'
$headersA = @{
  'Content-Type' = 'application/json'
  'x-flowplan-user-id' = $user
  'x-flowplan-device-id' = '00000000-0000-4000-8000-000000000101'
}
$headersB = @{
  'Content-Type' = 'application/json'
  'x-flowplan-user-id' = $user
  'x-flowplan-device-id' = '00000000-0000-4000-8000-000000000102'
}

$uid = [guid]::NewGuid().ToString()
$created = Invoke-RestMethod -Method Post -Uri "$base/client/tasks" -Headers $headersA -Body (@{
  uid = $uid
  title = 'B conflict base'
  summary = 'B conflict base'
} | ConvertTo-Json)

$serverId = $created.item.id
$serverVersion = [int]$created.serverVersion

Invoke-RestMethod -Method Patch -Uri "$base/client/tasks/$serverId" -Headers $headersB -Body (@{
  title = 'B edit'
  summary = 'B edit'
  baseServerVersion = $serverVersion
} | ConvertTo-Json)

$push = Invoke-RestMethod -Method Post -Uri "$base/sync/push" -Headers $headersA -Body (@{
  clientBatchId = [guid]::NewGuid().ToString()
  mutations = @(@{
    mutationUid = [guid]::NewGuid().ToString()
    objectType = 'task_item'
    localId = 'api-local-a'
    serverId = $serverId
    uid = $uid
    action = 'update'
    baseServerVersion = $serverVersion
    changedFields = @('title', 'summary')
    payload = @{
      title = 'A offline edit'
      summary = 'A offline edit'
    }
  })
} | ConvertTo-Json -Depth 6)

$push.conflicts
Invoke-RestMethod -Method Get -Uri "$base/admin/data/conflicts" -Headers $headersA
```

Expected: `$push.conflicts` contains one conflict, and Web Admin -> Sync -> Conflicts shows the same conflict.

## Failure table

| Symptom | Check first |
| --- | --- |
| Local task exists but server does not | API base URL, offline mutation status, push error reason |
| Server object exists but client does not update | Pull cursor, ack, change applier, object state |
| Offline task disappears | Local repository insert, server-first fallback, offline mutation enqueue |
| Duplicate task after retry | uid stability, create idempotency, pull apply upsert |
| Conflict not generated | base server version, server object version, mutation payload |
| Conflict not visible | `/api/admin/data/conflicts`, Web Admin Sync page, `sync_conflicts` status |
