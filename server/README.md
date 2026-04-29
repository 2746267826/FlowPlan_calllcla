# FlowPlan Server

P1 server foundation for the FlowPlan client/server split.

This server is responsible for the complete server-side fact store, device scoped synchronization, conflict candidates, cursors, and audit-ready external mappings.

Recommended stack:

- TypeScript
- NestJS
- PostgreSQL
- Redis for background jobs and rate control
- S3-compatible object storage for files

## P1 Scope

Implemented P1 boundaries:

- PostgreSQL schema in `src/database/p1_schema.sql`
- auth login/refresh/logout boundary backed by the `users` table
- device registration, listing, update and heartbeat
- `/sync/push`
- `/sync/pull`
- `/sync/ack`
- `/sync/conflicts`
- `/sync/status`
- `/sync/conflicts/:conflictId/resolve`
- `outlook_object_mappings` table for the future Outlook task import and task schedule mirror model

## Setup

Install dependencies and apply the schema:

```text
npm install
$env:DATABASE_URL="postgres://user:password@localhost:5432/flowplan"
npm run db:schema
npm run dev
```

Codex must not run Flutter or Dart commands in this repository. Server-side `npm` commands are separate, but dependency installation may require network access.
