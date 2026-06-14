# MANUAL-GEN-DRIFT-001 Evidence

Date: 2026-06-14
Executor: Codex
Workspace: `C:\Users\a2746\Desktop\calll260426`

## Scenario

Generated Drift churn audit.

## Commands And Evidence

1. Root automated gate ran the Flutter generator:

   `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800`

   Result: PASS.

   The gate executed:

   `cd client_flutter; dart run build_runner build --delete-conflicting-outputs`

2. Focused generated database diff check:

   `git diff --quiet -- client_flutter\lib\core\database\app_database.g.dart`

   Result: no diff.

3. Generated file diff review:

   `git diff -- client_flutter\lib\features\tracker\services\tracker_service.g.dart`

   Result: the only generated Dart diff in scope is a Riverpod hash update for
   `TrackerServiceNotifier`, tied to source changes in
   `client_flutter/lib/features/tracker/services/tracker_service.dart`.

## Review Result

No `client_flutter/lib/core/database/app_database.g.dart` churn exists in the
current worktree. No hand-edited Drift generated output was found. The generator
owner check is satisfied by the passing root gate build_runner transcript and
the focused generated-file diff review.
