# Manual Acceptance Gap Audit - 2026-06-14

Executor: Codex
Workspace: `C:\Users\a2746\Desktop\calll260426`

## Current Automated Baseline

Fresh command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -SkipInstall -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800
```

Result: PASS on 2026-06-14 08:23 local time and again on 2026-06-14 09:13 local time.

Covered server build/unit/integration/API/coverage, web admin build/unit/coverage/e2e, Flutter build_runner/analyze/unit-widget coverage, golden checks, Windows integration gates, governance validation, and boundary scan.

Completion mode still fails only because `docs/test-governance/manual-acceptance.csv` contains open manual rows.

## Manual Matrix Counts

- `passing`: 3
- `pending-user`: 15

Passing rows with dated evidence:

- `MANUAL-FILE-001`
- `MANUAL-FLUTTER-001`
- `MANUAL-GEN-DRIFT-001`

## Pending Rows By Blocker Type

### Needs Real Windows Client Evidence

These cannot be marked passing from API/unit/widget evidence alone because the rows require screenshots or recordings from the real Windows app.

- `MANUAL-WIN-001`: has supplemental server/API/Web Admin same-auth-user audit evidence, but still needs the standard non-admin Windows task create/complete/sync/audit workflow with real client screenshots and account evidence.
- `MANUAL-WIN-002`: Windows reminder notification delivery plus snooze or dismiss evidence.
- `MANUAL-WIN-003`: Windows credential validation, credential cleanup, and redacted diagnostics.
- `MANUAL-AUDIT-001`: has supplemental server/API/Web Admin evidence, but still needs a real Windows or Android client action with screenshots and API/database comparison.
- `MANUAL-ONLINE-PRIMARY-001`: has focused Flutter evidence, but still needs real disconnected Windows cache screenshots and local DB inspection.
- `MANUAL-FILE-ONLINE-001`: has real server-hosted upload/download API evidence and focused Flutter coverage, but still needs real client offline picker-blocking and interruption/resume screenshots or recording.

### Needs Android Device Or Android Permissions

- `MANUAL-ANDROID-001`: real Android Usage Access import workflow.
- `MANUAL-ANDROID-002`: real Android Usage Access recovery and notification workflow.

### Needs External Account Or Credential

- `MANUAL-OUTLOOK-001`: Microsoft test account OAuth, read-only sync, diagnostics, and reset.
- `MANUAL-OUTLOOK-002`: Microsoft consent revocation, reconnect, sync recovery, and cleanup.
- `MANUAL-AI-001`: OpenAI-compatible valid test key for provider test, draft request, approval, and audit.
- `MANUAL-AI-002`: OpenAI-compatible invalid and valid keys for failure redaction and recovery.

### Needs Duration-Based Real Tracking Run

- `MANUAL-LONGTRACK-001`: at least 2 hours of real tracking continuity.
- `MANUAL-TRACK-ONLINE-001`: has supplemental real server batch and focused Flutter cleanup evidence, but still needs at least 5 minutes of real tracking diagnostics, failed upload interval, reconnect, and local row before/after counts.

### Needs Product Decision Before Implementation

- `MANUAL-FILE-002`: current server APIs support storage object registration, listing, upload completion, download session/range, and direct storage-object download. A fresh 2026-06-14 code inspection of `server/src/files/files.controller.ts`, `server/src/files/files.service.ts`, `server/src/files/file-transfer.service.ts`, and `server/src/files/local-object-storage.service.ts` found no storage-object delete/cleanup endpoint or local object delete primitive. Implementing this should be treated as a behavior change, not just evidence collection.

Recommended minimal design for approval:

- Add `DELETE /api/files/storage/:objectId`.
- Scope deletion to the request user.
- Mark the storage object deleted or cleaned instead of hard-removing audit history.
- Detach or mark related identity mappings and transfer/session references so stale storage objects are not advertised as available.
- Delete the local object file best-effort and record the result in metadata.
- Record a `files.storage.delete` or `files.storage.cleanup` audit row with object id, object key, owner/user id, device id, file deletion result, and affected reference counts.
- Add server unit coverage and a real local API evidence run with a disposable file.

## Next Concrete Actions

1. Get approval for the `MANUAL-FILE-002` storage cleanup behavior change before editing production code.
2. Execute real Windows client runs for `MANUAL-WIN-001`, `MANUAL-AUDIT-001`, `MANUAL-ONLINE-PRIMARY-001`, and `MANUAL-FILE-ONLINE-001` when an interactive desktop session is available for screenshots or recording.
3. Execute Android, Outlook, and AI rows only when their external devices/accounts/keys are available.
4. Keep pending rows as `pending-user` until their dated evidence folders satisfy the row-specific runbooks.
