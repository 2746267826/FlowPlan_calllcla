# MANUAL-FILE-ONLINE-001 Supplemental Evidence - 2026-06-14

Status: supplemental evidence only. Do not mark `MANUAL-FILE-ONLINE-001` passing from this run.

## Scope

This run verified the server-hosted upload/download part of the online-primary file contract against the real local server API at `http://127.0.0.1:3202/api`.

It does not satisfy the full manual row because the row still requires offline UI evidence that the file picker does not open when the server is unavailable, plus screenshots or recording from the real client workflow.

## Server Evidence

- Marker: `manual-file-online-001-20260614-063414`
- Upload session: `acc291d1-4ec0-449f-b827-5a45e1f33475`
- Storage object: `42b4dada-f546-4fb0-a2e6-5c0fbce99a6b`
- Download session: `143048b2-071d-4bde-af93-44c472fa515c`
- Source SHA-256: `f9eb03845ba9be71aa00894a98db215caad3a922e126c77b136925b56539defe`
- Downloaded SHA-256: `f9eb03845ba9be71aa00894a98db215caad3a922e126c77b136925b56539defe`
- Size: `10485760` bytes
- Chunk size: `4194304` bytes
- Expected chunks: `3`

The API run confirmed:

- No matching `file_storage_objects` row existed before upload-session creation.
- No matching storage object existed after upload-session creation.
- No matching storage object existed after all chunks were uploaded but before completion.
- The storage object became visible only after `completeUploadSession`.
- Downloaded bytes from the server-hosted storage object matched the source hash.

Direct database reads confirmed the completed transfer session, storage object metadata, and audit rows for `files.upload.create_session`, `files.upload.complete`, and `files.download.create_session`.

## Focused Flutter Coverage

Existing focused tests cover the client-side online-primary file restrictions:

- `test/features/files/file_transfer_service_test.dart`
  - offline policy rejects upload before creating a session or local job
  - upload session failure leaves no local job or audit entry
- `test/widgets/user_workflow_file_transfer_test.dart`
  - offline upload requires server before opening the file picker

## Files

- `api-summary.json`: real API upload/download timeline and hashes.
- `logs/db-summary.json`: direct database session, storage object, and audit rows.
- `logs/manual-file-online-001-20260614-063414.json`: timestamped API summary.
- `artifacts/manual-file-online-001-20260614-063414.bin`: source file.
- `artifacts/manual-file-online-001-20260614-063414.downloaded.bin`: downloaded file.

## Remaining Gap

Keep `MANUAL-FILE-ONLINE-001` as `pending-user` until a real client/manual run captures offline picker-blocking evidence, server restart, upload interruption/resume controls, and user-visible screenshots or recording.
