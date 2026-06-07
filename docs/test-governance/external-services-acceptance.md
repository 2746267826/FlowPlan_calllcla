# External Services Acceptance

Automated tests must not use live external credentials, production data, device-only APIs, or long-running platform integrations. These scenarios are accepted through manual evidence after deterministic server, web, or Flutter skeletons prove the local contract.

| Manual ID | Service / Capability | Required Environment | Acceptance Evidence | Reset / Cleanup |
| --- | --- | --- | --- | --- |
| MANUAL-OUTLOOK-001 | Outlook OAuth and read-only calendar sync | Microsoft account test calendar with non-production data | OAuth screenshots, sync run id, diagnostics response, created local event ids | Revoke test app consent and reset the local Outlook connection |
| MANUAL-AI-001 | Real AI provider draft approval | OpenAI-compatible test key with spend limits | Provider test id, generated draft payload, user approval screenshot, audit row id | Delete provider key from local env and remove generated draft data |
| MANUAL-FILE-001 | Real file transfer interruption recovery | Windows filesystem with a disposable 10 MB test file | Upload session id, interruption note, resumed download hash, source hash | Delete test file, storage object, and transfer session |
| MANUAL-WIN-001 | Windows task create complete sync audit | Windows desktop client, local server, test database | Client screenshots, Web Admin task status, sync mutation id, audit row id | Remove test task, schedule row, sync mutation, and audit fixture |
| MANUAL-ANDROID-001 | Android usage stats import | Android test device with usage access enabled | Permission screenshot, imported timeline screenshot, upload payload id | Revoke usage access and delete imported records |

## Evidence Rules

- Record the date, build or commit SHA, device, account type, scenario id, result, evidence path, and follow-up issue id for every run.
- Use only test credentials and disposable data. Do not record secrets in screenshots, logs, CSV rows, or issue bodies.
- A manual result can be `pending-user`, `passing`, `failed`, or `blocked`. Failed and blocked results need a short reproduction note and owner.
- External-service rows remain outside the automated root gate unless the service is mocked with deterministic responses.

## User-Run Flutter Command

Codex must not run Flutter or Dart commands in this repository. The user should run this validation when the Flutter harness is available:

```powershell
cd client_flutter
flutter test integration_test\cross_end_workflows_test.dart
```
