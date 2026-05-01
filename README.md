# FlowPlanV2 Workspace

FlowPlanV2 is now organized as a multi-module workspace. Each runtime module owns its own files and commands.

## Modules

- `client_flutter/`：Windows / Android Flutter client. Contains `pubspec.yaml`, `lib/`, `android/`, `windows/`, assets, release notes, and Flutter-local build/cache files.
- `server/`：NestJS + PostgreSQL service. Contains API, sync, analytics, schema scripts, and server dependencies.
- `web_admin/`：independent web admin frontend.
- `docs/`：product plans, architecture notes, update log, and archived legacy planning files.

## Common Commands

Server:

```powershell
cd server
npm run db:schema
npm run dev
npm run build
```

Web admin:

```powershell
cd web_admin
npm run dev
npm run build
```

Flutter client commands should be run inside `client_flutter/` when needed. Codex must not run Flutter or Dart commands in this project.

## Main Plan

Read the user-facing plan here:

- `docs/FlowPlanV2_用户版完整开发计划_260426.md`

Daily update log:

- `docs/update.txt`
