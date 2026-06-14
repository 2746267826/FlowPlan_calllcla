# MANUAL-AUDIT-001 Supplemental Evidence - 2026-06-14

Status: supplemental evidence only. Do not mark `MANUAL-AUDIT-001` passing from this run.

## Scope

This run verified one real local-server audit chain across:

- Server API task creation and completion.
- Web Admin audit data API visibility.
- Direct PostgreSQL reads using the server `pg` client.
- Web Admin audit page DOM-visible rows.

It does not satisfy the full manual row because the row also asks for real client screenshots and a Windows/Android/Web Admin cross-end comparison. The in-app Browser screenshot call timed out twice during this run, then a separate local Playwright screenshot captured the Web Admin audit table.

## Evidence IDs

- Marker: `manual-audit-001-webadmin-20260614-061340`
- User ID: `085c6e69-289d-4d13-8e6f-96b24451546a`
- Device ID: `11111111-1111-4111-8111-111111111111`
- Task ID: `f8b271cf-f1d8-41b6-bea9-1829017628af`
- Create audit ID: `449ae504-a25e-4e08-b7c7-33c2e72fa035`
- Complete audit ID: `24c561a2-f9ab-4cc7-aa9f-9a85ee1064ff`
- Create sync change ID: `303191`
- Complete sync change ID: `303192`

## Result

The API and database agreed on actor `web`, actions `web.task_item.create` and `web.task_item.update`, entity ID `f8b271cf-f1d8-41b6-bea9-1829017628af`, and the Web Admin audit page displayed both rows.

The first probe was intentionally not used as Web Admin evidence because it was created under the default request-context user while Web Admin had auto-logged in as a different user. That explained the initial empty audit table and prevented a false bug report.

## Files

- `api-summary.json`: API-level IDs and counts.
- `db-audit-rows.json`: direct database audit rows.
- `web-admin-dom-visible-rows.json`: DOM-visible Web Admin table rows captured after filtering.
- `screenshots/web-admin-audit-filtered.png`: local Playwright screenshot of the Web Admin audit table showing the create and update rows.

## Remaining Gap

Keep `MANUAL-AUDIT-001` as `pending-user` until a real client action is captured with screenshots or screen recording and compared against API and database rows.
