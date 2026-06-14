# MANUAL-ONLINE-PRIMARY-001 Supplemental Evidence - 2026-06-14

Status: supplemental evidence only. Do not mark `MANUAL-ONLINE-PRIMARY-001` passing from this run.

## Scope

This run verified the online-primary cache policy and the server-first store behavior with focused Flutter tests.

It does not satisfy the full manual row because the row still requires a real disconnected Windows client run with dated screenshots or screen recording, task/event reopen evidence, and local offline_mutations inspection from the manual workflow.

## Focused Flutter Evidence

Commands:

```powershell
flutter test test\core\online\online_primary_policy_test.dart --concurrency=1
flutter test test\core\server_first\task_event_server_first_store_test.dart --concurrency=1
flutter test test\core\bootstrap\client_bootstrap_service_test.dart --concurrency=1
flutter test test\shared\widgets\offline_read_only_banner_test.dart --concurrency=1
flutter test test\widgets\user_workflow_task_detail_worker_j_test.dart --concurrency=1
flutter test test\widgets\user_workflow_data_management_test.dart --concurrency=1
```

All six commands exited `0`.

## What the tests prove

- Ordinary business writes are rejected when the connection is offline or auth-restricted.
- Tracking spool and device-local writes remain allowed offline.
- Task and event server-first stores keep local cache unchanged when the server rejects or fails.
- Bootstrap and periodic sync keep server-first mode on success and fall back to local cache on unreachable server states.
- The offline read-only banner renders the expected UI copy.
- Task detail and data management surfaces respect the read-only cache policy.

## Files

- `focused-test-summary.json`
- `online-primary-policy-output.txt`
- `task-event-server-first-store-output.txt`
- `client-bootstrap-service-output.txt`
- `offline-read-only-banner-output.txt`
- `task-detail-read-only-output.txt`
- `data-management-read-only-output.txt`

## Remaining Gap

Keep `MANUAL-ONLINE-PRIMARY-001` as `pending-user` until the real Windows disconnected workflow is captured with dated evidence and local database inspection.
