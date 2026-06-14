# MANUAL-WIN-001 Supplemental Evidence - 2026-06-14

Status: supplemental evidence only. Do not mark `MANUAL-WIN-001` passing from this run.

## Scope

This run verified a local server and Web Admin audit chain using the same Web Admin auth user:

- Created a task through the server API.
- Completed the task through the server API.
- Confirmed the completed task is visible through the server task query.
- Confirmed Web Admin shows both audit rows after filtering.

It does not satisfy the full manual row because the row requires a real non-admin Windows desktop client workflow with client screenshots or recording, standard-user account evidence, manifest `asInvoker` confirmation, and the real client save and complete controls.

## Evidence IDs

- Marker: `manual-win-001-webadmin-supplement-20260614005536`
- Device ID: `9fde55ef-57d8-49a7-9790-e41fdd35a3d3`
- Task ID: `056309da-f63e-44a4-8b26-bffdb2a519e7`
- Create audit ID: `dc5e375a-54ff-4c8a-a4d7-11dab7d6ad13`
- Complete audit ID: `c660af7a-70bc-4e6c-9510-d931a4908fa9`
- Create sync change ID: `303198`
- Complete sync change ID: `303199`

## Result

The API create and complete calls both returned canonical server items. The task query showed the completed task, and the Web Admin audit table displayed two matching rows: `web.task_item.create` and `web.task_item.update`.

An earlier probe in this evidence folder is intentionally diagnostic only: it created the task under the default request-context user, while Web Admin had auto-logged in as a different generated user. That explains the empty Web Admin table in `web-admin-audit-filtered.png` and prevents treating that probe as passing evidence.

## Files

- `api-summary-webadmin-user.json`: API-level create, complete, task query, sync change, and audit IDs for the successful same-auth-user run.
- `web-admin-dom-summary-webadmin-user.json`: DOM-visible Web Admin rows for the same task.
- `screenshots/web-admin-audit-filtered-webadmin-user.png`: Web Admin audit table showing both filtered rows.
- `web-admin-network-debug.json`: diagnostic explanation for the earlier mismatched-user probe.
- `logs/db-summary.json`: direct database summary for the earlier default-user probe.
- `windows-client/whoami.txt` and `windows-client/whoami-groups.txt`: local Windows account and medium-integrity, deny-only Administrators evidence captured on 2026-06-14.
- `windows-client/runner.exe.manifest`: Windows runner manifest captured on 2026-06-14, including `requestedExecutionLevel level="asInvoker"`.
- `windows-client/server-health.json`: local server `/api/health` response for the Windows client probe.
- `windows-client/process-launch.json`, `windows-client/visible-launch.json`, and `windows-client/window-capture.json`: diagnostic Windows client launch probes. These prove the built client process and a `flutter run -d windows` runner could start, but they are not passing UI evidence because the direct executable probe had no main window handle and the captured window image did not show the FlowPlanV2 task workflow.

## Remaining Gap

Keep `MANUAL-WIN-001` as `pending-user` until a real non-admin Windows desktop client run captures the create/save and complete workflow, standard-user evidence, manifest `asInvoker` evidence, task/sync mutation IDs, and Web Admin audit row IDs.
