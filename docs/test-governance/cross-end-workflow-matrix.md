# Cross-End Workflow Matrix

| Workflow | Test IDs | Automated Mock-Based Tests | Manual / Real Acceptance |
| --- | --- | --- | --- |
| Task schedule edit complete audit sync | CE-TASK-001 through CE-TASK-006 | Server API and Web Playwright with mocked API | Windows client creates and completes a task; Web Admin verifies status, sync mutation, and audit row |
| Calendar create edit delete views | CE-CAL-001 through CE-CAL-004 | Server API and Flutter fake API integration | Windows and Android event appears and disappears across timeline, week, and month |
| Offline sync conflict resolution | CE-SYNC-001 through CE-SYNC-006 | Server two-device stale version API tests | Real offline write, reconnect, Web Admin conflict resolution, no silent overwrite |
| Tracking activity report | CE-TRACK-001 through CE-TRACK-007 | Server ingest, understanding, report API tests | Windows tracking for 30 minutes, upload, confirm activity, generate report |
| Files transfer version recovery | CE-FILE-001 through CE-FILE-007 | Server file session API and Web mocked drive flow | Real 10MB transfer interruption and hash verification |
| AI draft approval audit | CE-AI-001 through CE-AI-007 | Server mocked AI response and Web mocked operation approval | Real AI provider creates task draft, user approves, audit row exists |
| Admin operations evidence | CE-ADMIN-001 through CE-ADMIN-008 | Web Playwright mocked dashboard, alerts, logs, jobs, settings, env, operations | Operator runs one safe operation, job trigger, and settings save |
| Outlook external services | CE-EXT-001 through CE-EXT-007 | Mocked Graph and diagnostics tests | Real Microsoft OAuth and read-only sync |
