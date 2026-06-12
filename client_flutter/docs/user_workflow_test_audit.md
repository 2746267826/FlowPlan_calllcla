# User Workflow Widget Test Audit

Audit date: 2026-06-10

Scope: `test/widgets/user_workflow_*_test.dart`,
`client_flutter/docs/client_flutter_test_matrix.md`, and
`docs/test-governance/*`.

This audit is a low-conflict client-owned index for the current user workflow
widget suite. The central governance matrices currently track the same product
areas at a higher level through `CLIENT-*`, `CE-*`, and `MANUAL-*` rows, but do
not enumerate every workflow widget file.

## Coverage Matrix

| Area | Workflow tests | Automated coverage observed | Matrix alignment | Residual status |
| --- | --- | --- | --- | --- |
| Shell, task, and calendar flows | `user_workflow_controls_test.dart`; `user_workflow_calendar_shell_quick_add_test.dart`; `user_workflow_calendar_shell_additional_test.dart`; `user_workflow_calendar_quick_add_bar_test.dart`; `user_workflow_calendar_shell_full_task_editor_test.dart`; `user_workflow_calendar_shell_full_event_editor_test.dart`; `user_workflow_calendar_shell_auto_schedule_test.dart`; `user_workflow_calendar_books_test.dart`; `user_workflow_calendar_books_worker_f_test.dart`; `user_workflow_calendar_detail_test.dart`; `user_workflow_calendar_detail_worker_f_test.dart`; `user_workflow_calendar_month_view_test.dart`; `user_workflow_calendar_week_view_test.dart`; `user_workflow_task_controls_test.dart`; `user_workflow_task_detail_test.dart`; `user_workflow_task_detail_edit_test.dart`; `user_workflow_task_detail_delete_test.dart`; `user_workflow_task_detail_worker_j_test.dart` | Shell view switches, empty-state primary action/date navigation checks, quick-add task and event entry, quick add tracker start/elapsed/stop flow, full editor handoff, auto-schedule confirmation, calendar book/list actions, event create/edit/delete/save validation, month/week navigation, task create/detail/edit/delete with cancel and confirm paths, deadline/default/failure states. Stable keys cover shell week/month, task summary/save, and event summary/save. | Covered by high-level `CLIENT-TASK-001`, `CLIENT-CAL-001`, `CLIENT-INT-001`, and manual rows `MANUAL-WIN-001` / `MANUAL-ANDROID-001`. | Automated widget coverage is broad for local UI controls. Real device sync/audit confirmation, reminder notification paths, and deep conflict states remain manual or outside this widget slice. |
| Tracker and activity review flows | `user_workflow_tracker_page_test.dart`; `user_workflow_activity_review_test.dart`; `user_workflow_input_heatmap_test.dart` | Tracker start/stop/review flow, review confirm dialog, heatmap summary reload, selected-process filtering, and server heatmap error state. Stable keys cover tracker navigation, start, and review confirm controls. | Covered by `CLIENT-TRACK-001`, `CLIENT-INT-002`, `MANUAL-LONGTRACK-001`, and `MANUAL-ANDROID-001`. | Long-running continuity, Android usage access import, notification recovery, and duplicate checkpoint checks remain manual. |
| Reports and AI chat flows | `user_workflow_report_page_test.dart`; `user_workflow_ai_chat_test.dart` | Report generate, refresh, diary draft generation, weather location setup, push channel setup, report detail/evidence view, edit, confirm/push, AI polish, failed delivery retry, diary edit/confirm/polish, AI chat composer send, blank-message guard, provider-unavailable state, and send-failure state. Stable key covers report generate. | Covered by `CLIENT-REPORT-001`, `CE-REPORT-001`, `CE-AI-001`, and `MANUAL-AI-001` / `MANUAL-AI-002`. | Real provider credentials, provider redaction evidence, live model response quality, and cross-end audit rows remain manual. |
| Files and data management flows | `user_workflow_file_transfer_test.dart`; `user_workflow_file_context_page_deep_test.dart`; `user_workflow_file_context_additional_test.dart`; `user_workflow_data_management_test.dart` | File transfer start/progress/success/retry/cancel, cancellation without enqueueing, file root relocation, file context empty state, recommendation refresh/confirm, root selection and node binding, delete confirmation, read-error and empty-tree states, disabled actions, data-management filter, multi-select, and confirm delete. Stable key covers file transfer start. | Covered by `CLIENT-FILE-001`, `CE-FILE-001`, `MANUAL-FILE-001`, `MANUAL-FILE-002`, and `MANUAL-AUDIT-001`. | Real 10 MB interrupted transfer recovery, hash comparison, owner/audit verification, and filesystem permission edge cases remain manual. |
| Sync, settings, import/export, and external service setup | `user_workflow_server_sync_test.dart`; `user_workflow_settings_test.dart`; `user_workflow_outlook_settings_test.dart`; `user_workflow_outlook_settings_deep_test.dart`; `user_workflow_outlook_settings_additional_test.dart`; `user_workflow_ical_import_export_deep_test.dart` | Server sync queue replay and failure handling, settings schedule validation and database persistence, server-managed Outlook refresh success/failure, local Outlook config and auth failure flows, diagnostics export cancel/write/error paths, Outlook calendar visibility recovery and reset cancellation, iCal disabled state, selected/merged export scopes, smart merge, append-only import, replace confirmation, unreadable/empty/cancel import states, and structured archive preview. Stable keys cover sync run and settings save. | Covered by `CLIENT-SYNC-*`, `CLIENT-SETTINGS-001`, `CLIENT-ICAL-001`, `CE-EXT-001`, `MANUAL-OUTLOOK-*`, and `MANUAL-FLUTTER-001`. | Real Microsoft OAuth, read-only Graph sync evidence, credential revocation/reconnect, actual file picker behavior, and full external-service diagnostics remain manual. |

## Matrix Readout

- `client_flutter/docs/client_flutter_test_matrix.md` records the principal
  client feature rows and verification commands, but it does not yet list the
  widget workflow files individually.
- `docs/test-governance/feature-test-matrix.csv` maps the client areas to
  `CLIENT-*` and cross-end rows. It treats workflow coverage as area-level
  evidence rather than as a per-button inventory.
- `docs/test-governance/manual-acceptance.csv` is the right home for real
  device, credential, external-service, and long-running evidence. Its current
  columns already capture controls, states, error paths, and side effects.
- This document closes the local traceability gap between those high-level
  rows and the concrete `user_workflow_*_test.dart` files.

## Residual Coverage Gaps

- Route-level smoke coverage is uneven for audit-log and day-detail style
  pages that are not represented by a dedicated `user_workflow_*_test.dart`
  file in this slice.
- First-run, login, credential rotation, and protected-route behavior remain
  mostly manual or covered outside the workflow widget suite.
- External integrations still need real-service acceptance: Microsoft OAuth
  and Graph read-only sync, AI provider validation and redaction, file transfer
  interruption recovery, Android usage access, and notification permissions.
- Several widget tests cover happy-path edits plus selected failures, but
  cross-device stale-write conflicts, duplicate action idempotency, and audit
  row reconciliation remain outside this local widget layer.
- The central governance matrix should eventually add a compact row or
  evidence pointer for this audit document so future reviewers do not have to
  rediscover the user workflow file list manually.
