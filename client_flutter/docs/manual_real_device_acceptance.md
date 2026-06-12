# Flutter Real Device Acceptance

User-run validation covers:

- Windows tray and close-to-tray behavior.
- Windows launch and foreground tracking.
- RawInput sampling.
- File picker, open, reveal, and local identity hash.
- Notification and reminder delivery.
- Android usage-access permission and import.
- Android reminders.
- Outlook OAuth and sync with real credentials.
- AI provider call with a real key.
- Long-running tracker stability for at least 2 hours.

Each run records date, device, app version, scenario id, result, evidence path,
and follow-up issue id when failing.

| Manual ID | Scenario | Required Environment | Evidence |
| --- | --- | --- | --- |
| MANUAL-WIN-001 | Create, edit, complete, and sync a task | Windows desktop client with test server | screenshots, task id, sync mutation id, audit row id |
| MANUAL-WIN-002 | Create reminder flow and verify notification handling | Windows desktop with notification permissions | desktop screenshots, reminder id, schedule row id, audit row id |
| MANUAL-WIN-003 | Validate credentials and redaction | Windows desktop with disposable test credentials | redacted screenshots and diagnostics id |
| MANUAL-ANDROID-001 | Grant usage access, import usage, and verify tracker timeline | Android real device | permission screenshot and imported activity id |
| MANUAL-ANDROID-002 | Verify Android usage reminders and permission recovery | Android real device with notification permissions | permission screenshots, notification screenshot, upload payload id |
| MANUAL-OUTLOOK-001 | Authorize Outlook and run read-only sync | Microsoft test account | OAuth result, run id, diagnostics screenshot |
| MANUAL-OUTLOOK-002 | Revoke Outlook consent and reconnect | Microsoft test account | revocation screenshot, diagnostics response, reconnect run id |
| MANUAL-AI-001 | Save real AI provider, create draft, approve operation | OpenAI-compatible test key | provider test id, approved object id, audit row id |
| MANUAL-AI-002 | Validate AI provider credential failure handling | OpenAI-compatible invalid and valid test keys | redacted error screenshot, provider test id |
| MANUAL-FILE-001 | Upload, interrupt, resume, and hash-check a file | Windows filesystem and test file at least 10 MB | transfer session id and before/after hashes |
| MANUAL-FILE-002 | Verify file transfer credential and cleanup audit | Windows filesystem with disposable storage target | owner, audit row id, cleanup notes |
| MANUAL-LONGTRACK-001 | Verify long-running tracking continuity | Windows desktop or Android device with local server | start/end timestamps, sync checkpoint ids, audit query result |
| MANUAL-AUDIT-001 | Verify cross-end audit consistency | Windows desktop, Android device, Web Admin, local server | client screenshot, API response, database audit row id |

After user authorization on 2026-06-08, Codex may run Flutter and Dart validation in this repository. The current automated gate runs:

```powershell
cd client_flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --no-pub --coverage -x golden
flutter test --no-pub test/goldens/client_layout_golden_test.dart -r expanded
flutter test --no-pub test/goldens/settings_layout_golden_test.dart -r expanded
flutter test --no-pub -d windows integration_test/cross_end_workflows_test.dart
flutter test --no-pub -d windows integration_test/file_report_ai_flow_test.dart
flutter test --no-pub -d windows integration_test/sync_offline_flow_test.dart
flutter test --no-pub -d windows integration_test/task_calendar_flow_test.dart
flutter test --no-pub -d windows integration_test/tracker_review_flow_test.dart
```

Device discovery and real-device smoke commands remain manual diagnostics:

```powershell
cd client_flutter
flutter devices
flutter run -d <android-device-id>
```

Windows integration launch evidence is automated and currently passing when run per file. The latest automated client evidence is 32 non-golden Flutter coverage tests, 2 golden tests run per file, and 5 Windows integration files containing 6 total tests. The full `integration_test` directory invocation is not used as completion evidence on Windows because it can hang after launching multiple desktop runner processes.

Manual acceptance still requires user-operated real devices, credentials, notification permissions, and long-running sessions where listed above.
