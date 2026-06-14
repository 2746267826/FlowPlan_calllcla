# Online-Primary Read-Only Cache

## Runtime Rule

The server is the only acceptance point and business fact source for FlowPlanV2 business data. Native clients may read cached Drift data offline, but ordinary writes are disabled or rejected when the server is not reachable and authorized.

A client-side success state means the server accepted, validated, persisted, and returned the canonical result. Local cache writes are consequences of server acceptance, not independent facts.

## Business Fact Ownership

Server-owned business facts include tasks, events, calendar books, schedule runs, activity understanding results, reports, diary entries, AI settings, conversations, user-visible server settings, audit logs, file metadata, file content, versions, and file context links.

The client keeps Drift for:

- Offline reading.
- Fast startup.
- Existing Drift-backed UI surfaces.
- Recently viewed server data.
- Downloaded file cache records.
- Device-local settings and runtime state.

Drift rows for server-owned objects are read cache rows. They can be refreshed, replaced, or deleted by server refresh logic and must not be treated as cross-device truth.

## Ordinary Business Writes

Ordinary business writes must call a server API first. If the server is offline, unreachable, unauthorized, or rejects validation, the client must not create a local business fact, must not update the read cache as if the write succeeded, and must not enqueue an ordinary mutation for later replay.

This rule applies to create, update, delete, complete, confirm, reject, schedule, generate, server-managed setting, report, AI, file metadata, and file context operations.

## Tracking Spool Exception

Tracking collection is the explicit local-write exception. Windows and Android clients may collect raw tracking records locally while offline or degraded. Those rows are an upload spool, not canonical history.

Tracking upload runs in batches, with the implementation target of roughly 60 seconds while online. Local tracking source rows are deleted only after the server confirms successful batch completion for the matching records. If upload creation, chunk upload, completion, or partial acceptance fails, unconfirmed rows remain retryable. Rejected records with known local ids are retained in failed/quarantine diagnostic state instead of being silently merged into history.

Tracker history and analytics are read from the server. Local unuploaded rows may appear as upload status only.

## Server-Hosted Files

File metadata, content, checksums, versions, context links, upload sessions, and completed upload records are server facts. A file upload requires an online server connection and a server-created upload session before a local upload job exists.

If the client is offline, file upload entry points must be disabled or reject before opening the picker. If an upload starts online and later fails, the session/job may remain retryable, but the file is not canonical until the server confirms completion. Downloaded files are local cache copies; deleting a local download does not delete the server file.

## Legacy Offline Queue

Existing `offline_mutations` rows are retained only as migration residue, diagnostics, and user-review evidence. The legacy queue must not receive new ordinary business writes under online-primary behavior.

Startup and periodic cache refresh should not replay legacy ordinary mutations automatically. The old sync queue can remain visible in diagnostics and cleanup tooling until pending rows have been resolved, archived, discarded, or exported according to migration policy.

## Cross-End Boundary

Web/admin and server views present server facts, not local pending client facts. Cross-end acceptance must prove that offline client write attempts do not create unexpected server mutations after reconnect, while tracking spool upload and file transfer retry behavior remain visible as explicit exceptions.
