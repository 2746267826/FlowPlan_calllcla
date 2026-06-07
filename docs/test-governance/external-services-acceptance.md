# External Services Acceptance

Automated tests must not use live external credentials, production data, device-only APIs, or long-running platform integrations. These scenarios are accepted through manual evidence after deterministic server, web, or Flutter skeletons prove the local contract.

| Manual ID | Service / Capability | Required Environment | Acceptance Evidence | Reset / Cleanup |
| --- | --- | --- | --- | --- |
| MANUAL-OUTLOOK-001 | Outlook OAuth and read-only calendar sync | Microsoft account test calendar with non-production data | OAuth screenshots, sync run id, diagnostics response, created local event ids | Revoke test app consent and reset the local Outlook connection |
| MANUAL-OUTLOOK-002 | Outlook credential revocation and reconnect | Microsoft account test calendar with revocable app consent | Revocation screenshot, diagnostics response, reconnect run id, read-only sync result | Revoke test app consent again and reset the local Outlook connection |
| MANUAL-AI-001 | Real AI provider draft approval | OpenAI-compatible test key with spend limits | Provider test id, generated draft payload, user approval screenshot, audit row id | Delete provider key from local env and remove generated draft data |
| MANUAL-AI-002 | AI provider credential failure handling | OpenAI-compatible invalid and valid test keys | Redacted validation failure, provider test id, connection success result, validation notes | Delete provider keys from local env and remove generated draft data |
| MANUAL-FILE-001 | Real file transfer interruption recovery | Windows filesystem with a disposable 10 MB test file | Upload session id, interruption note, resumed download hash, source hash | Delete test file, storage object, and transfer session |
| MANUAL-FILE-002 | File transfer credential and cleanup audit | Windows filesystem with a disposable storage target | Source hash, transfer session id, owner audit row id, cleanup verification | Delete test file, storage object, transfer session, and audit fixture |
| MANUAL-WIN-001 | Windows task create complete sync audit | Windows desktop client, local server, test database | Client screenshots, Web Admin task status, sync mutation id, audit row id | Remove test task, schedule row, sync mutation, and audit fixture |
| MANUAL-WIN-002 | Windows reminder flow and notification handling | Windows desktop client, local server, notification permissions | Reminder screenshot, reminder id, schedule row id, audit row id | Remove test task, reminder, schedule row, and audit fixture |
| MANUAL-WIN-003 | Windows credential validation and redaction | Windows desktop client with disposable user credential set | Credential test notes, redacted screenshots, diagnostics id | Clear stored credentials and remove generated user/session fixtures |
| MANUAL-ANDROID-001 | Android usage stats import | Android test device with usage access enabled | Permission screenshot, imported timeline screenshot, upload payload id | Revoke usage access and delete imported records |
| MANUAL-ANDROID-002 | Android usage reminders and permission recovery | Android test device with usage access and notification permissions | Permission screenshots, notification screenshot, upload payload id, recovery notes | Revoke usage access, clear reminders, and delete imported records |
| MANUAL-LONGTRACK-001 | Long-running tracking continuity | Windows desktop or Android device with local server for extended run | Start/end timestamps, timeline screenshot, sync checkpoint ids, audit query result | Stop tracking session and delete timeline, checkpoint, and audit fixtures |
| MANUAL-AUDIT-001 | Cross-end audit verification | Windows desktop, Android device, Web Admin, and local server test database | Client screenshot, API response, database audit row id, actor/entity comparison notes | Remove created entities, sync rows, and audit fixtures |
| MANUAL-FLUTTER-001 | User-run Flutter command results | User workstation with Flutter SDK and repository checkout | Command transcript, exit code, build SHA, evidence path, skipped-test notes | Remove generated Flutter test artifacts only after evidence is captured |

## Evidence Rules

- Record the date, build or commit SHA, device, account type, scenario id, result, evidence path, and follow-up issue id for every run.
- Use only test credentials and disposable data. Do not record secrets in screenshots, logs, CSV rows, or issue bodies.
- A manual result can be `pending-user`, `passing`, `failed`, or `blocked`. Failed and blocked results need a short reproduction note and owner.
- Use `pending-user` for records that need user-run devices, credentials, external services, or Flutter commands that Codex cannot execute in this environment.
- External-service rows remain outside the automated root gate unless the service is mocked with deterministic responses.

## User-Run Flutter Command

Codex must not run Flutter or Dart commands in this repository. The user should run this validation when the Flutter harness is available:

```powershell
cd client_flutter
flutter test integration_test\cross_end_workflows_test.dart
```
