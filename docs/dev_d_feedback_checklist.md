# FlowPlan D Feedback Loop Checklist

This checklist validates the D-stage loop: activity segments, human feedback,
actual work, scheduler drafts, deviations, reports, and admin visibility.

## Preconditions

- Apply schema first when PostgreSQL is available:
  - `cd server`
  - `npm run db:schema`
- Start server and web admin:
  - `cd server`
  - `npm run dev`
  - `cd web_admin`
  - `npm run dev`
- Use the same API base URL everywhere, for example `http://localhost:3200/api`.

## Activity Understanding

1. Upload or sync tracking records that cover a known time range.
2. Build server-side segments:
   - `POST /api/activity-understanding/build-segments`
   - Body example: `{"date":"2026-04-30","rebuild":true}`
3. Confirm the segments endpoint returns candidates:
   - `GET /api/activity-understanding/segments?start=2026-04-30T00:00:00.000Z&end=2026-05-01T00:00:00.000Z`
4. Confirm a segment with an edited title and optional `taskId`.
5. Re-submit the same confirmation and verify `actual_activity_logs` and
   `task_work_logs` do not accumulate duplicates.
6. Reject a different candidate and verify model feedback/audit rows are written.

## Scheduler

1. Create a draft run:
   - `POST /api/scheduler/runs`
   - Body example:
     `{"rangeStart":"2026-04-30T09:00:00.000Z","rangeEnd":"2026-04-30T18:00:00.000Z","strategy":"balanced"}`
2. Verify the run snapshot includes blocking events, work blocks, and actual
   work already applied to task remaining minutes.
3. Accept the draft and verify `task_schedule_segment` objects are written
   through `sync_objects`.
4. Reject another draft and verify no schedule segments are written.

## Deviations

1. Run detection:
   - `POST /api/scheduler/deviations/detect`
   - Body example:
     `{"rangeStart":"2026-04-30T00:00:00.000Z","rangeEnd":"2026-05-01T00:00:00.000Z"}`
2. Verify both deviation classes can appear:
   - `missed`: planned segment has no overlapping confirmed actual.
   - `actual_unplanned`: confirmed actual has no overlapping accepted schedule segment.
3. Run detection twice and verify repeated runs do not create duplicate open
   deviations for the same plan or actual log.

## Reports

1. Generate a report without configuring any external AI provider:
   - `POST /api/reports/generate`
   - Body example:
     `{"reportType":"daily","periodStart":"2026-04-30T00:00:00.000Z","periodEnd":"2026-05-01T00:00:00.000Z"}`
2. Verify the returned report contains template content and evidence links.
3. Verify source snapshot and metrics include actuals, task work, activity
   segments, schedule items, deviations, and file/weather context when present.
4. Edit the report with `PATCH /api/reports/:reportId`, then confirm it with
   `POST /api/reports/:reportId/confirm`.

## Web Admin

Open the following datasets and verify columns are populated instead of showing
only raw snake_case fields:

- `/api/admin/data/actuals`
- `/api/admin/data/activity-segments`
- `/api/admin/data/task-work-logs`
- `/api/admin/data/schedule-runs`
- `/api/admin/data/schedule-draft-items`
- `/api/admin/data/plan-deviations`
- `/api/admin/data/reports`
- `/api/admin/data/report-entries`
- `/api/admin/data/report-evidence`

## Build Verification

- `cd server && npm run build`
- `cd web_admin && npm run build`

Do not use Dart or Flutter commands for this checklist unless the user explicitly
allows them in a later instruction.
