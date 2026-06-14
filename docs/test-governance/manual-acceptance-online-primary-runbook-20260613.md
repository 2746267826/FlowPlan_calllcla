# Online-Primary Manual Acceptance Runbook - 2026-06-13

These rows were added by the online-primary read-only cache migration. Keep
them `pending-user` until a real user or device run records dated evidence in
`docs/test-governance/manual-acceptance.csv`.

## Evidence Folder

Recommended location:

`docs/test-governance/reports/manual-evidence/<manual_id>-YYYYMMDD/`

Each evidence folder should include:

- `notes.md`: date, executor, device, OS version, server URL, app build or commit, and result.
- `screenshots/`: key controls, blocked states, error states, and final success states.
- `logs/`: client logs, server logs, command output, or relevant database query output.
- `ids.md`: task ids, event ids, batch ids, upload session ids, local job ids, storage object ids, and row counts.

## MANUAL-ONLINE-PRIMARY-001 - Offline Read-Only Cache

Environment: Windows desktop client, local server, test database, and a way to
stop the server or block connectivity.

Steps:

1. Start the local server and Windows client.
2. Create or seed one task and one event while online.
3. Wait for the client cache to refresh from the server.
4. Stop the server or block the connection.
5. Reopen the task and event details and confirm cached values are readable.
6. Attempt task save, event save, timeline drag or resize, and data-management batch actions.
7. Verify each ordinary business write is blocked with a read-only cache message.
8. Query or inspect local state and confirm no ordinary `offline_mutations` row was created by the rejected writes.
9. Confirm rejected writes did not mutate the local business cache.
10. Restart the server, refresh, and verify server facts remain canonical.

Required evidence:

- Dated screenshots or screen recording for online, offline read-only, rejected write, and reconnected states.
- Server stop/start or network block notes.
- Task/event row ids and before/after values.
- `offline_mutations` query result showing no ordinary write replay row.
- Reconnect refresh evidence.

## MANUAL-TRACK-ONLINE-001 - Tracking Minute Batch Upload Cleanup

Environment: Windows desktop or Android device, local server, and at least five
minutes of real tracking data.

Steps:

1. Start tracking and generate at least five minutes of activity or input data.
2. Disconnect the server for one upload interval.
3. Verify local tracking source rows remain available while upload fails.
4. Reconnect the server and wait at least 60 seconds.
5. Verify the server accepts a tracking batch and records accepted/rejected counts.
6. Verify confirmed local source rows are deleted only after server confirmation.
7. Verify failed or rejected rows remain retryable or appear in quarantine.
8. Record tracker diagnostics counts before disconnect, while disconnected, and after reconnect.

Required evidence:

- Dated tracker diagnostics screenshots.
- Server batch id and accepted/rejected counts.
- Local source row counts before and after successful upload.
- Quarantine query result or retryable failed-row evidence.

## MANUAL-FILE-ONLINE-001 - Server-Hosted File Upload And Interruption Recovery

Environment: Windows filesystem, local server, and a disposable 10 MB test file.

Steps:

1. Stop the server and click the file transfer upload control.
2. Verify the file picker does not open while offline.
3. Restart the server and select the 10 MB test file.
4. Record the server upload session id and local job id after session creation.
5. Interrupt upload after the server session exists.
6. Resume upload and wait for completion.
7. Download the completed file.
8. Compare the downloaded hash with the source hash.
9. Verify the server storage object exists only after upload completion.

Required evidence:

- Dated screenshots for offline-blocked, session-created, uploading, interrupted, resumed, completed, downloaded, and verified states.
- Source and downloaded hashes.
- Upload session id, local job id, and storage object id.
- Interruption method and resume notes.
