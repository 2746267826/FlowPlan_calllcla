# FlowPlan C tracking checklist

Scope: C only. This verifies Windows foreground tracking, RawInput telemetry, local logs, tracking upload, admin visibility, and analytics APIs.

## Build checks

```powershell
cd server
npm run build
```

```powershell
cd web_admin
npm run build
```

Flutter and Windows runtime checks are manual for this stage.

## Windows tracking checks

1. Start the Windows client.
2. Open the tracking page.
3. Switch between VS Code, a browser, and File Explorer.
4. Expected: the current session panel updates process name, title, category, and last sample time.
5. Keep tracking enabled for at least 30 minutes.
6. Expected: the page keeps updating, no duplicate timer symptoms appear, and the app does not crash.

## RawInput checks

1. With tracking enabled, type in a non-FlowPlan window.
2. Move the mouse, click buttons, and scroll.
3. Expected: key count, click count, movement, and scroll metrics increase.
4. If native registration fails, the tracking panel should show a diagnostic message instead of silently staying empty.

## Local log checks

1. Open tracking history and input history.
2. Expected: `activity_records`, `raw_activity_logs`, and `tracked_input_events` have visible entries.
3. Open the local log directory from the tracking page.
4. Expected: daily archive files are discoverable and malformed rows do not blank the page.

## Upload checks

1. Trigger normal server sync from the server sync page.
2. Expected: tracking upload runs as part of sync.
3. Open Web Admin -> tracking ingest batches.
4. Expected: at least one batch appears with `dataKind`, `rawEventCount`, `acceptedEventCount`, and status.
5. If upload fails, `tracking.upload.last_error` remains set and local upload cursors are not advanced for the failed kind.

## Analytics API checks

Use the configured server port, normally `3200`:

```powershell
curl "http://localhost:3200/api/analytics/tracker-home"
curl "http://localhost:3200/api/analytics/activity-day-summary?date=2026-04-30"
curl "http://localhost:3200/api/analytics/top-apps?start=2026-04-30T00:00:00Z&end=2026-05-01T00:00:00Z"
curl "http://localhost:3200/api/analytics/input-heatmap?bucket=hour"
```

Expected:

- Empty data returns empty arrays and zero counts, not HTTP 500.
- Invalid date ranges return HTTP 400 with a clear message.
- After upload, tracker-home and top-apps reflect the uploaded activity records.

## Failure table

| Symptom | Check first |
| --- | --- |
| RawInput does not move | Native channel `com.flowplan/raw_input`, registration diagnostic, Windows focus permissions |
| Foreground window is empty | Win32 foreground handle, process query permission, tracking diagnostic message |
| Tracking stops after a while | Sampling re-entry guard, local DB write errors, last sample time |
| Local data exists but upload fails | API base URL, tracking upload last error, batch/chunk/complete responses |
| Admin cannot see batches | `/api/admin/data/tracking-ingest-batches`, `tracking_ingest_batches` rows |
| Analytics is empty after upload | Batch completion status, accepted count, `sync_objects` tracking object rows |
