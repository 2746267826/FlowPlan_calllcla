# FlowPlanV2 Linux Production Environment Compatibility Design

Date: 2026-06-14
Status: Approved for planning
Owner: FlowPlanV2

## 1. Purpose

FlowPlanV2 server and web admin are developed on Windows, but production runs
on Linux. The goal of this work is to remove production startup risk caused by
environment loading, working-directory assumptions, path handling, and
Windows-only defaults.

The guiding rule is:

```text
The server and web admin must run predictably on Linux without breaking the
existing Windows development startup flow.
```

## 2. Current Context

The repository has three main app areas:

- `server`: NestJS API server with PostgreSQL, file storage, Kopia integration,
  auth, admin APIs, and scheduled jobs.
- `web_admin`: Vite/React admin frontend that talks to the server API.
- `client_flutter`: Flutter client. It is not the focus of this production
  Linux pass unless a server or admin contract requires it.

The Windows development path currently works through the root startup scripts.
Those scripts are not part of this change.

The current server has two environment-loading paths:

- `server/src/main.ts` manually searches for `.env` in several locations.
- `server/src/app.module.ts` configures `ConfigModule` with one path based on
  `__dirname`.

This split can behave differently depending on whether Linux starts the process
from the repository root, the `server` directory, a built `dist` directory, or a
systemd working directory. It also makes it harder to reason about which env
file was actually loaded.

The web admin currently defaults to `http://localhost:3202` and stores the API
base in browser local storage. That is useful during development, but Linux
production needs a clear build-time or runtime way to target the real server
origin.

## 3. Scope

In scope:

- Server env file discovery and loading.
- Server config values that affect production startup.
- Server working-directory and path assumptions.
- Linux defaults for external executables such as Kopia.
- Web admin API base configuration for Linux production builds.
- Tests or verification commands that prove the Linux-safe behavior without
  needing an actual Linux host.

Out of scope:

- Changing the root Windows startup scripts.
- Reworking old deployment documentation as an authoritative source.
- Creating a full deployment platform, systemd unit, nginx config, Docker
  image, or CI pipeline.
- Rewriting unrelated frontend text, layout, or product behavior.
- Changing Flutter client behavior except where a server/admin contract forces
  a narrow adjustment.

## 4. Chosen Approach

Use a focused compatibility remediation.

Alternatives considered:

- Audit only. This is fast, but it leaves known Linux startup risk in the code.
- Full deployment rebuild. This could include systemd, nginx, Docker, and new
  docs, but it is too broad for the current request and would be anchored on
  stale deployment notes.
- Focused remediation. This keeps the working Windows flow intact while fixing
  the actual server/admin production assumptions. This is the recommended
  approach.

## 5. Server Design

### 5.1 Single Env Discovery Helper

Create a small server-side helper that owns env file discovery.

It should:

- Prefer system environment variables when already present.
- Support explicit env file override through a variable such as
  `FLOWPLANV2_ENV_FILE`.
- Search stable candidate files relative to both `process.cwd()` and the
  compiled source location.
- Cover the known project conventions:
  - `server/.env`
  - `server/flowplanv2.local.env`
  - root `flowplanv2.local.env`
  - root `.env` if present
- Return the selected path and candidate list for startup logging and tests.

The helper must use `node:path` and `node:fs`, not string-built path logic.

### 5.2 One Loading Path

Use the env discovery helper from both:

- `main.ts`, before Nest starts.
- `ConfigModule.forRoot`, so Nest config and manually-read process env values
  see the same env source.

This removes the current split between manual dotenv loading and a separate
`ConfigModule` path.

### 5.3 Production Validation

Server startup should fail fast with actionable messages when required
production values are missing.

Minimum required server values:

- `FLOWPLANV2_DATABASE_URL` or `DATABASE_URL`.

Strongly recommended production values should be surfaced in logs or health
diagnostics without blocking development startup:

- `JWT_ACCESS_SECRET`
- `JWT_REFRESH_SECRET`
- `FLOWPLANV2_ENCRYPTION_KEY`
- `ADMIN_CORS_ORIGIN`

Existing development defaults can remain, but production mode should make weak
defaults visible.

### 5.4 Linux Path And Executable Defaults

Server file paths should remain portable by using `path.resolve`, `path.join`,
and `path.relative`.

Kopia should default to `kopia`, not `kopia.exe`. Windows users can still set
`KOPIA_EXE=kopia.exe` or an absolute path. Linux users can rely on `PATH` or set
an absolute Linux path.

The implementation should audit code for Windows drive letters, backslash-only
splitting, and `win32` assumptions in production paths. Test fixtures may keep
Windows paths when they intentionally verify path normalization.

## 6. Web Admin Design

### 6.1 Build-Time API Base

The web admin should read a Vite-exposed variable such as
`VITE_API_BASE_URL`.

Resolution order:

1. Stored browser override from `localStorage`.
2. `import.meta.env.VITE_API_BASE_URL`, normalized by existing admin API
   helpers.
3. Existing development fallback `http://localhost:3202`.

This keeps local development simple while allowing Linux production builds to
point at `/api`, `https://example.com/api`, or another deployment-specific
origin.

### 6.2 Static Hosting Compatibility

The admin code should not assume Windows paths at runtime. Its Linux production
artifact is static HTML/CSS/JS. Any server routing or reverse proxy setup is
outside this change, but the built app must not bake in an unusable Windows-only
API base.

## 7. Error Handling

Required behavior:

- If no env file exists but system env vars are present, the server starts and
  logs that it is using system environment variables.
- If no database URL is available, startup fails with a clear message that works
  on Linux and Windows.
- If an explicit env file override points to a missing file, startup fails
  clearly instead of silently choosing another file.
- If web admin API base is unset, it keeps the current development fallback.
- If web admin API base is set, it is normalized consistently with the existing
  API client behavior.

## 8. Testing Strategy

Server tests:

- Env discovery returns the expected candidate order for root, server, and
  built `dist`-style locations.
- Explicit env file override succeeds when the file exists.
- Explicit env file override fails clearly when the file does not exist.
- `ConfigModule` uses the same env file path as startup.
- Database startup still accepts either `FLOWPLANV2_DATABASE_URL` or
  `DATABASE_URL`.

Web admin tests:

- Default API base still falls back to `http://localhost:3202`.
- `VITE_API_BASE_URL` is used when no local storage override exists.
- Local storage override still wins.
- API base normalization remains unchanged.

Verification commands:

- `cd server; npm run build`
- Focused server unit tests for env/config.
- `cd web_admin; npm run build`
- Focused web admin unit tests for API base selection.

## 9. Acceptance Criteria

This work is complete when:

- Server env discovery has one shared implementation.
- `main.ts` and Nest `ConfigModule` use the same env file decision.
- Linux production can run from `server/`, repository root, or a service working
  directory when system env vars or an explicit env file are provided.
- Missing required database config fails with a useful message.
- Linux Kopia default is `kopia`.
- Web admin can be built with `VITE_API_BASE_URL` and still preserves the
  browser override behavior.
- The root Windows startup scripts are untouched.
- Focused tests and builds pass.

## 10. Implementation Notes

Implementation planning should decide exact file names and helper boundaries.
The preferred shape is a small `server/src/common/config/env-files.ts` helper
plus focused unit tests.

The production deployment document can be refreshed later, but it should not be
treated as authoritative for this pass.
