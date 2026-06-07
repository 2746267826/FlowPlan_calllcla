# Client Flutter Test Matrix

This local matrix tracks the first client-owned FlowPlanV2 A-level test slice.
Central governance CSV updates are suggested in the worker summary and must be
applied by the central-governance owner.

| Test ID | Area | Feature Or Control | Automated Test | Manual Acceptance | Status |
| --- | --- | --- | --- | --- | --- |
| CLIENT-FOUND-001 | app | In-memory database injection | `test/test_support/test_database.dart`, `test/features/task/task_repository_test.dart` | none | implemented-pending-user-run |
| CLIENT-FOUND-002 | app | Router factory and app router override | `test/widgets/app_router_override_test.dart` | none | implemented-pending-user-run |
| CLIENT-FOUND-003 | app | Stable Flutter keys | `lib/core/ui/app_keys.dart`, `test/widgets/app_keys_contract_test.dart` | selector review during manual smoke | implemented-pending-user-run |
| CLIENT-API-001 | core/server_api | Authenticated JSON client | `test/core/server_api/api_client_test.dart` | none | implemented-pending-user-run |
| CLIENT-API-002 | core/server_api | Client task endpoint paths and query filters | `test/core/server_api/client_api_test.dart` | none | implemented-pending-user-run |
| CLIENT-SYNC-001 | core/sync | Pull response applies user settings and sync state | `test/core/sync/server_sync_change_applier_test.dart` | none | implemented-pending-user-run |
| CLIENT-SYNC-002 | core/sync | Pull cursor ack and local cursor persistence | `test/core/sync/sync_engine_test.dart` | none | implemented-pending-user-run |
| CLIENT-OFFLINE-001 | core/offline_queue | Offline mutation persistence and ack handling | `test/core/offline_queue/*_test.dart` | Windows offline/reconnect smoke | implemented-pending-user-run |
| CLIENT-TASK-001 | features/task | Create task records task, audit, and sync evidence | `test/features/task/task_repository_test.dart` | `CLIENT-MANUAL-WIN-001` | implemented-pending-user-run |
| CLIENT-CAL-001 | features/calendar | Calendar event appears for selected day | `test/features/calendar/calendar_repository_test.dart` | `CLIENT-MANUAL-WIN-002` | implemented-pending-user-run |
| CLIENT-TRACK-001 | features/tracker | Manual tracking records duration and device context | `test/features/tracker/activity_record_repository_test.dart` | `CLIENT-MANUAL-WIN-003`, `CLIENT-MANUAL-ANDROID-001` | implemented-pending-user-run |
| CLIENT-FILE-001 | features/files | Local folder upsert is idempotent | `test/features/files/file_context_repository_test.dart`, `integration_test/file_report_ai_flow_test.dart` | `CLIENT-MANUAL-WIN-004` | implemented-pending-user-run |
| CLIENT-REPORT-001 | features/reports | Report draft upsert replaces same period | `test/features/reports/report_repository_test.dart`, `test/goldens/client_layout_golden_test.dart` | `CLIENT-MANUAL-AI-001` | implemented-pending-user-run |
| CLIENT-ICAL-001 | features/ical | VEVENT parsing preserves escaped text | `test/features/ical/ical_parser_test.dart` | export/import spot check | implemented-pending-user-run |
| CLIENT-SETTINGS-001 | features/settings | Work schedule normalization and save selector | `test/features/settings/work_schedule_test.dart` | `CLIENT-MANUAL-WIN-005` | implemented-pending-user-run |
| CLIENT-GOLDEN-001 | layout | Timeline and settings responsive baselines | `test/goldens/client_layout_golden_test.dart` | visual review after golden generation | skeleton-pending-user-baselines |
| CLIENT-INT-001 | integration | Task quick create flow | `integration_test/task_calendar_flow_test.dart` | Windows and Android smoke | skeleton-pending-user-run |
| CLIENT-INT-002 | integration | Server sync, tracker, and file routes expose stable controls | `integration_test/sync_offline_flow_test.dart`, `integration_test/tracker_review_flow_test.dart`, `integration_test/file_report_ai_flow_test.dart` | real sync/tracker/file validation | skeleton-pending-user-run |

User-run commands:

```powershell
cd client_flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --coverage
flutter test test/goldens
flutter test integration_test
```
