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
- Long-running tracker stability for at least 4 hours.

Each run records date, device, app version, scenario id, result, evidence path,
and follow-up issue id when failing.

| Manual ID | Scenario | Required Environment | Evidence |
| --- | --- | --- | --- |
| CLIENT-MANUAL-WIN-001 | Create, edit, complete, and sync a task | Windows desktop client with test server | screenshots, task id, sync mutation id, audit row id |
| CLIENT-MANUAL-WIN-002 | Create calendar event and verify timeline/week/month visibility | Windows desktop client | screenshots for each view |
| CLIENT-MANUAL-WIN-003 | Track a 30 minute session and confirm activity review evidence | Windows desktop with foreground tracking enabled | tracker screenshots and activity record id |
| CLIENT-MANUAL-WIN-004 | Upload, reveal, interrupt, resume, and hash-check a file | Windows filesystem and test file at least 10 MB | transfer session id and before/after hashes |
| CLIENT-MANUAL-WIN-005 | Change settings, restart, and verify persistence | Windows desktop client | settings screenshot before/after restart |
| CLIENT-MANUAL-ANDROID-001 | Grant usage access, import usage, and verify tracker timeline | Android real device | permission screenshot and imported activity id |
| CLIENT-MANUAL-OUTLOOK-001 | Authorize Outlook and run read-only sync | Microsoft test account | OAuth result, run id, diagnostics screenshot |
| CLIENT-MANUAL-AI-001 | Save real AI provider, create draft, approve operation | OpenAI-compatible test key | provider test id, approved object id, audit row id |

Codex did not run Flutter or Dart commands. The user should run:

```powershell
cd client_flutter
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --coverage
flutter test test/goldens
flutter test integration_test
flutter run -d windows
flutter devices
flutter run -d <android-device-id>
```
