# MANUAL-TRACK-ONLINE-001 Supplemental Evidence - 2026-06-14

Status: supplemental evidence only. Do not mark `MANUAL-TRACK-ONLINE-001` passing from this run.

## Scope

This run verified two pieces of the tracking upload cleanup contract:

- A real local server tracking ingest batch with one accepted record and one rejected record.
- The focused Flutter cleanup tests that delete confirmed local rows and preserve or quarantine failed/rejected rows.

It does not satisfy the full manual row because the row requires at least five minutes of real Windows or Android tracking data, one failed upload interval, reconnect, diagnostics screenshots, and local source row counts before and after the successful upload.

## Server Evidence

- Marker: `manual-track-online-supplement-20260614-062130`
- Batch ID: `ab53c16a-07ad-4c3f-89be-c9aeefeb5ea4`
- Accepted: `1`
- Rejected: `1`
- Batch status: `completed_with_rejections`
- Accepted sync object: `91f4d3f6-c060-4c59-b1c3-666b7f9d07c6`
- Sync change: `303193`
- Audit row: `8fff3cec-c619-48e3-8767-f487cd7cf6c2`

Direct database reads confirmed the batch, chunk, accepted canonical `sync_objects` row, `sync_changes` row, and `tracking.ingest.batch.complete` audit row all refer to the same batch ID.

## Flutter Cleanup Evidence

Focused command:

```powershell
cd client_flutter
flutter test test\features\tracker\tracking_upload_service_test.dart --concurrency=1
```

Result: `+7: All tests passed`.

The passing tests cover:

- Accepted tracking rows are deleted locally after server confirmation.
- Upload failure preserves source rows and records an error.
- Chunk upload failure preserves unconfirmed rows.
- Quarantined rows are excluded from future uploads and pending counts.
- Partial rejection deletes accepted rows and quarantines known rejected local IDs.

## Files

- `api-summary.json`: API-level batch completion result.
- `db-summary.json`: direct database row IDs and counts.
- `focused-test-output.txt`: focused Flutter test command and passing output.

## Remaining Gap

Keep `MANUAL-TRACK-ONLINE-001` as `pending-user` until a real five-minute tracking run captures diagnostics screenshots, failed-interval retention, reconnect acceptance, local row counts before/after, and quarantine evidence.
