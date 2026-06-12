# FlowPlanV2 Online-Primary Read-Only Cache Design

Date: 2026-06-12
Status: Approved for planning
Owner: FlowPlanV2

## 1. Purpose

FlowPlanV2 will move away from local-first multi-device writes and adopt an
online-primary read-only cache model.

The goal is to reduce synchronization complexity and bug risk. The server is
the only source of truth for business facts. The Flutter client keeps a local
cache for offline reading and platform work, but it no longer creates ordinary
business facts while offline.

The guiding rule is:

```text
Users may read cached data offline.
Users may not change business facts offline.
Any accepted business write must already be persisted by the server.
```

## 2. Current Context

The current system is a hybrid:

- The server already acts as a canonical fact store through `sync_objects`,
  `sync_changes`, business APIs, file APIs, tracking ingest APIs, and admin
  APIs.
- The Flutter native client still has local Drift tables, `offline_mutations`,
  `sync_object_states`, `sync_conflicts`, push/pull/ack sync, and local write
  recording.
- Some task and event writes already use a server-first path and fall back to
  local queued writes when the server is unavailable.
- Flutter Web already behaves closer to online-primary: it calls service APIs
  directly and does not perform local offline fact writes.
- Tracking is special because Windows and Android collect raw events locally.
- Files are special because file content is large, has transfer state, and can
  have local device caches.

The main complexity to remove is not HTTP connectivity. It is local writable
state, replay, conflict detection, conflict resolution, remote change applying,
and multi-device identity mapping.

## 3. Scope

In scope:

- Product-level data ownership rules.
- Client/server responsibilities for online-primary business data.
- Read-only local cache behavior.
- Tracking upload behavior.
- File metadata, content, upload, download, and local cache rules.
- Offline and degraded network behavior.
- Migration principles from the current hybrid sync model.
- Testing and acceptance requirements for the architecture change.

Out of scope:

- Implementing the change in this design document.
- Choosing a production object storage provider.
- Rewriting the whole Flutter client UI.
- Designing future collaboration or real-time editing.
- Offline editing for ordinary business data.

## 4. Chosen Approach

Use the recommended approach: online-primary with read-only cache.

Alternatives considered:

- Strict online-only with no local read cache.
  This is conceptually simple, but it has worse user experience and requires
  more immediate UI rewiring because many Flutter native screens already read
  local Drift data.
- Keep local-first multi-device sync.
  This preserves offline editing, but it keeps the highest-risk parts of the
  current system: queued mutations, field conflicts, replay, local/server ID
  reconciliation, and pull application across many local tables.
- Online-primary with read-only cache.
  This keeps useful offline viewing and fits the existing Drift-based UI while
  removing offline business writes. It is the best balance of clarity, safety,
  and migration cost.

## 5. Architecture Principles

### 5.1 Single Fact Source

The server is the only source of truth for:

- Tasks.
- Calendar events and books.
- Schedule runs, segments, confirmations, and feedback.
- Actual records and activity understanding results.
- Reports, diary entries, templates, push settings, and delivery records.
- AI settings, conversations, tool drafts, and policy.
- User-visible settings, except device-local settings.
- File metadata, file content, versions, and file context links.
- Audit logs intended to survive across devices.

### 5.2 Read-Only Local Cache

The client may keep local copies for:

- Offline reading.
- Fast startup.
- Existing Drift-backed UI.
- Recently viewed data.
- Downloaded file content.
- Device-only settings and platform state.
- Tracking upload spool before server confirmation.

The local cache is not authoritative. It may be overwritten by a server refresh.
It must not be used to accept ordinary business writes while offline.

### 5.3 Online Writes Only

Ordinary business writes must call the server directly. If the server cannot be
reached, the write is rejected at the UX boundary and no business mutation is
queued.

The UI must clearly show that the app is in read-only offline mode.

### 5.4 Explicit Exceptions

Only these local write categories remain:

- Tracking upload spool.
- File transfer temporary state for an upload already started online.
- Downloaded file caches.
- Device-local settings and platform state.
- Local diagnostics and connection state.

These categories do not create server business facts until the server confirms
them.

## 6. Client Data Flow

### 6.1 Startup

On startup:

1. The client opens the local read cache.
2. Cached screens may render immediately.
3. The client checks server connection and authentication.
4. If online, the client refreshes server-managed settings and cached data.
5. If offline, the client enters read-only cache mode.

### 6.2 Reading Data

Client screens may read from:

- Server APIs when online and fresh data is needed.
- Local cache when offline or while waiting for refresh.

Each cached view must know whether it is showing fresh server data or cached
offline data.

### 6.3 Writing Data

For ordinary business data:

1. The user initiates a write.
2. The client verifies that the server is reachable and the user/session is
   authorized.
3. The client sends the write to the server API.
4. The server validates, persists, audits, and returns the canonical result.
5. The client updates the local read cache from the server result or a refresh.

If step 2 or step 3 fails before server acceptance, the local business data is
not changed. The UI shows a retryable error.

### 6.4 Removing Offline Mutations

Ordinary business writes must stop using `offline_mutations` as a fallback.

The table may remain during migration for diagnostics, cleanup, and legacy
readability, but the target behavior is:

- No new task/event/report/file metadata/settings writes enter
  `offline_mutations`.
- No ordinary business write is accepted with a pending local-only state.
- Existing pending local mutations must be resolved, imported, discarded, or
  surfaced for user review before the old path is disabled.

## 7. Server Data Flow

Server APIs own canonical writes.

For task and event data, the existing `/client/*` and `/web/*` server-first
APIs are the preferred direction because they already write `sync_objects`,
increment server versions, record sync changes, and audit writes.

The sync API may remain temporarily for:

- Legacy migration.
- Admin diagnostics.
- Server-to-client cache refresh while screens still depend on local Drift.

The long-term direction is to treat the pull/apply mechanism as cache refresh,
not as multi-master synchronization.

## 8. Tracking Design

Tracking is the primary exception to online writes.

### 8.1 Local Spool

Windows and Android clients collect tracking records locally into an upload
spool. This spool contains data that has not yet been accepted by the server.

The spool is not a long-term local history store.

### 8.2 Upload Cadence

The client uploads tracking data in batches every 60 seconds when online.

The batch may contain:

- Activity records.
- Raw activity logs.
- Tracked input events.
- Required device and time metadata.

The client should avoid real-time per-event upload.

### 8.3 Confirmation And Deletion

Tracking data is removed from local storage only after the server confirms that
the corresponding batch has completed successfully.

Required behavior:

- If batch creation, chunk upload, or completion fails, keep the affected local
  records for retry.
- If completion succeeds, delete the uploaded local records.
- If the server accepts some records and rejects others, delete only records
  that are safely acknowledged. Rejected records stay in a failed spool state or
  are moved to a small diagnostic quarantine according to implementation plan.
- The tracker UI reads historical analysis from the server. Local unuploaded
  records are shown only as upload status, not merged into canonical history.

### 8.4 Tracking UI

The tracking UI should show:

- Last successful upload time.
- Pending local upload count or size.
- Last upload error, if any.
- Server-side analytics and history as the canonical display.

## 9. File Design

Files use server-hosted content.

### 9.1 File Facts

The server is the source of truth for:

- File metadata.
- Folder/tree metadata.
- File content objects.
- Versions.
- Checksums.
- Context links to tasks, events, reports, or activity.
- Upload sessions and completed upload records.
- Download sessions and version restore records.

### 9.2 Local File State

The client may store:

- Downloaded file cache.
- Temporary upload chunks for an upload already started online.
- Open/recent local paths.
- Device-local preview state.

These are device-local facts. They do not define the cross-device file truth.

### 9.3 Upload Rules

File uploads require an online server connection before the user can select or
queue a file for upload.

Required behavior:

- If the client is offline, upload entry points are disabled or show an
  immediate "server connection required" message.
- The client must create an upload session on the server before upload starts.
- The client uploads file content through server-managed sessions and chunks.
- A file becomes a canonical server fact only after the server confirms upload
  completion.
- If an upload starts online and then fails, the failed session may be retained
  for retry.
- The client must not create an offline "pending file fact" before the server
  knows about the upload.

### 9.4 Download Rules

Downloads may create local cache files. Deleting local cached content does not
delete the server file. The user must use an explicit server delete action to
remove canonical file content.

### 9.5 Versioning

Replacing or restoring file content must be server-confirmed. Local cached
copies do not create new versions by themselves.

## 10. Offline Behavior

When offline:

- Users can open pages backed by local read cache.
- Users can view cached tasks, events, reports, file metadata, and previously
  downloaded files.
- Users cannot edit, delete, confirm, reject, schedule, generate, upload new
  files, or change server-managed settings.
- Tracking collection may continue locally.
- Tracking upload waits until online.
- File upload cannot be started.
- Previously started failed upload sessions may be retried only after the
  server is reachable.

The UI must avoid ambiguous pending states. A disabled write action is preferred
over accepting a local write that later needs reconciliation.

## 11. Device-Local Data

Device-local data remains outside the server fact model unless explicitly
uploaded:

- Server API base URL.
- Authentication tokens.
- Device identity.
- Window, tray, startup, and permission settings.
- Local cache paths.
- Downloaded file paths.
- Temporary transfer state.
- Sensor runtime state.

Device-local data can be backed up separately, but it does not participate in
business fact synchronization.

## 12. Conflict Handling

The target architecture avoids multi-master local conflicts by refusing offline
business writes.

Remaining conflicts are server-side optimistic concurrency cases:

- A client edits an old object version while online.
- Another client has already changed the object on the server.
- The server rejects the write with a version conflict.

The client response is:

- Refresh the object.
- Show the latest server state.
- Let the user reapply the change intentionally.

There is no local offline merge queue for ordinary business facts.

## 13. Migration Strategy

Migration should be phased.

Phase 1: Guardrails

- Add an architecture flag or policy for online-primary mode.
- Disable ordinary business offline fallback writes.
- Show read-only offline mode in the client.
- Keep existing sync diagnostics visible.

Phase 2: Task and event writes

- Ensure task and event create/update/delete/complete go through server APIs.
- Remove local fallback queuing for these writes.
- Update local cache only from canonical server responses or refreshes.

Phase 3: Settings, reports, scheduler, AI, and activity understanding

- Enforce online writes for these modules.
- Treat local data as cache or device-local state.

Phase 4: Tracking spool cleanup

- Convert local tracking history into upload spool semantics.
- Upload every 60 seconds.
- Delete locally confirmed uploaded records.
- Preserve only failed or unconfirmed records.

Phase 5: File server-hosted content

- Enforce online-only upload start.
- Confirm server-hosted content as the only file fact.
- Keep local downloads as cache.

Phase 6: Legacy sync cleanup

- Resolve or archive existing pending offline mutations.
- Stop creating new ordinary business mutations.
- Reclassify pull/apply as cache refresh or replace with direct API refresh.
- Keep admin visibility for migration residue until clean.

## 14. Error Handling

Required error behavior:

- Offline write attempt: no local fact change; show offline read-only message.
- Auth failure: show login/reauthorization state; do not queue writes.
- Server validation failure: show server message; do not change local fact.
- Version conflict: refresh canonical state; ask user to retry intentionally.
- Tracking upload failure: retain local unconfirmed records; show upload status.
- File upload start while offline: reject before file selection or before
  creating local queue state.
- File upload failure after session start: retain retryable session state and
  mark it as failed, without treating the file as canonical.

## 15. Testing Strategy

Tests must prove the new boundaries, not just that APIs return success.

Server tests:

- Business write APIs persist canonical objects and audit records.
- Version conflicts reject stale updates.
- File upload sessions only create canonical files on completion.
- Tracking batch completion writes canonical tracking objects.
- Tracking partial failure preserves clear accepted/rejected counts.

Flutter client tests:

- Offline mode renders cached data read-only.
- Offline write controls are disabled or reject before local mutation.
- Ordinary business writes no longer enqueue `offline_mutations`.
- Successful online writes update cache from canonical server responses.
- Tracking upload deletes only server-confirmed local records.
- Tracking upload failure preserves retryable records.
- Offline file upload cannot create a pending queue item.
- Failed online file upload remains retryable but non-canonical.

Web/admin tests:

- Admin sees server facts, not local pending facts.
- File and tracking status pages distinguish canonical data from failed or
  pending transfer/spool state.

Cross-end tests:

- Create a task online on one client, refresh another client, and see the
  server version without conflict flow.
- Attempt offline edit, reconnect, and confirm no unexpected server mutation
  was created.
- Upload tracking batch, verify client cleanup and server analytics.
- Upload file content, verify server metadata/content, then delete local cache
  and re-download from server.

## 16. Acceptance Criteria

This architecture is implemented when:

- Ordinary business data cannot be modified offline.
- Ordinary business writes do not create new `offline_mutations`.
- Offline screens clearly indicate read-only cached mode.
- Server APIs are the only acceptance point for business facts.
- Tracking uploads run in roughly 60-second batches while online.
- Tracking records are deleted locally after confirmed successful upload.
- Failed or unconfirmed tracking records remain locally retryable.
- File content is server-hosted.
- File upload cannot be started while offline.
- A file becomes canonical only after server upload completion.
- Local downloaded files are treated as cache.
- Existing pending legacy mutations have an explicit migration or cleanup path.

## 17. Open Implementation Notes

Implementation planning should decide:

- Whether cache refresh continues through `/sync/pull` temporarily or moves
  module by module to direct server API refresh.
- How to migrate or review existing `offline_mutations`.
- How to mark stale local tables as read-only caches in repository APIs.
- How to quarantine tracking records rejected by the server.
- How much failed file upload state should survive app restart.

These are implementation choices, not unresolved product rules. The product
rule is fixed: online-primary, read-only cache, tracking spool, server-hosted
files.
