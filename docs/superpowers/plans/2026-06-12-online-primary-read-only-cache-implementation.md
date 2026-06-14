# Online Primary Read Only Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert FlowPlanV2 native client, web client, and server boundaries to online-primary writes with an offline read-only cache, batched tracking upload cleanup, and server-hosted file content.

**Architecture:** The server remains the only fact source for business data. Flutter native keeps Drift as a read cache and device-local store, but ordinary business writes must succeed on the server before local cache mutation. Tracking uses a local upload spool with 60-second batching and deletes only records confirmed by the server; files require an online server session before selection/upload work begins.

**Tech Stack:** Flutter, Riverpod, Drift, SharedPreferences, NestJS, PostgreSQL, Vitest, PowerShell, existing FlowPlanV2 server APIs, existing `/sync/pull` cache refresh path.

---

## Source Inputs

- Approved design: `docs/superpowers/specs/2026-06-12-online-primary-read-only-cache-design.md`
- Full test governance design: `docs/superpowers/specs/2026-06-08-full-test-governance-design.md`
- Quality gate policy: `docs/test-governance/quality-gates.md`
- Future development test rules: `docs/test-governance/future-development-rules.md`
- Flutter/Dart execution policy: user authorized Codex to run Flutter and Dart commands for this implementation on 2026-06-13; older `docs/development_constraints_260426.md` restrictions are superseded for this plan.
- Server scripts: `server/package.json`
- Flutter dependencies: `client_flutter/pubspec.yaml`

## Global Rules

- Codex may run `flutter`, `dart`, `dart format`, and `dart run build_runner` for this implementation. Run Flutter/Dart verification serially, avoid parallel Flutter test processes, and record command output or log paths in the closeout report.
- Keep `/sync/pull` and `ServerSyncChangeApplier` as the first cache-refresh path.
- Do not create new ordinary business entries in `offline_mutations`.
- Keep existing `offline_mutations` rows visible for migration and diagnostics.
- Do not delete tracking source rows until a server `completeBatch` response confirms the matching records.
- Do not let file upload entry points open `FilePicker` while the client is in read-only cache mode.
- Every behavior change must update `docs/test-governance/feature-test-matrix.csv`.
- Every real-device, real-network, long-running, or externally dependent acceptance path must update `docs/test-governance/manual-acceptance.csv`.
- Completion evidence must include governance matrix validation, focused tests, full root quality gate status, Flutter/Dart command results, coverage report references, and open manual acceptance rows.
- Do not mark a feature-test row `verified` or `implemented` when it references a manual acceptance row that is not `passing`; use `partial` until dated manual evidence exists.
- Commit after each task when executing this plan.

## Full Test Governance Requirements

This plan must satisfy the complete testing standard established in `docs/superpowers/specs/2026-06-08-full-test-governance-design.md`, `docs/test-governance/quality-gates.md`, and `docs/test-governance/future-development-rules.md`. Implementation is not complete just because focused tests pass.

- Write or update an effective automated test before each behavior change. The test must fail for the missing behavior or old bug before implementation and pass after implementation.
- Every changed user-facing flow must have coverage for the trigger control or background trigger, applicable loading/empty/success/disabled/permission-denied/validation-error/network-error/API-error/duplicate-submission/external-failure states, data integrity side effects, and accessibility/layout selectors where relevant.
- Every changed feature, control, API, data path, and workflow must be represented in `docs/test-governance/feature-test-matrix.csv`.
- Manual acceptance is allowed only for real-device, live-network, credential, long-running, platform-permission, or external-provider evidence that automation cannot reliably drive. Each such path must have a row in `docs/test-governance/manual-acceptance.csv` with controls, states, error paths, side effects, exact steps, and dated evidence requirements.
- Do not mark a matrix row `implemented`, `passing`, or `verified` when it links to manual acceptance that is still `pending-user`, `blocked`, or `blocked-environment`; keep it `partial` or another open status until dated passing evidence exists.
- Server and Web Admin included hand-written production code must satisfy their root-gate 100% coverage requirements for lines, branches, functions, and statements.
- Flutter included hand-written Dart code must satisfy root-gate 100% included-line LCOV coverage after reviewed `docs/test-governance/coverage-exclusions.csv` exclusions are applied.
- Any coverage exclusion must have a reviewed row in `docs/test-governance/coverage-exclusions.csv` with reason, replacement verification, owner/module, review condition, and status.
- No focused or skipped automated tests may be committed unless the skip is explicitly allowed by a reviewed governance exclusion.
- The final evidence must include focused feature tests, server focused tests, `flutter analyze`, Flutter coverage, golden tests, Windows Flutter integration tests, governance-only validation, the full root quality gate, and the completion gate status.
- `scripts/test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800` is the only completion gate. If it fails because manual acceptance rows remain open, record that blocker and do not claim full completion.

## Testing Completion Definition

Treat the full test governance rules as hard completion gates, not optional documentation work. A worker may report an implementation task as locally done after its focused red/green tests pass, but the feature may not be called complete until all of the following are true and recorded in `docs/test-governance/reports/online-primary-read-only-cache-closeout.md`:

- Focused automated tests for every changed behavior pass, including client policy, server-first business writes, bootstrap pull-only refresh, tracking batching/cleanup, file upload boundaries, UI read-only states, and server canonical boundaries.
- `flutter analyze` passes after the final client edits.
- Full Flutter coverage passes with 100% included-line LCOV after reviewed `docs/test-governance/coverage-exclusions.csv` exclusions are applied.
- Server and Web Admin root-gate coverage remains at 100% for included hand-written production code.
- `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -GovernanceOnly` passes.
- `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800` passes.
- `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800` either passes or fails only because documented manual acceptance rows are still `pending-user`; in the latter case, mark the implementation as blocked by manual evidence rather than complete.
- `docs/test-governance/feature-test-matrix.csv`, `docs/test-governance/manual-acceptance.csv`, and `docs/test-governance/cross-end-workflow-matrix.md` reflect every changed feature, control, API, data path, workflow, manual-only acceptance path, and dated evidence status.
- No focused or skipped tests, unreviewed coverage exclusions, or stale local-first/offline-queue success messages remain outside an explicit reviewed governance exception.

## File Structure

Create client policy and UI files:

- Create `client_flutter/lib/core/online/online_primary_policy.dart`: source of truth for read-only cache mode and write rejection errors.
- Create `client_flutter/lib/shared/widgets/offline_read_only_banner.dart`: compact offline/read-only state surface for write-heavy pages.
- Create `client_flutter/test/core/online/online_primary_policy_test.dart`: policy unit tests.
- Create `client_flutter/test/shared/widgets/offline_read_only_banner_test.dart`: widget tests.

Modify client wiring and sync files:

- Modify `client_flutter/lib/shared/providers/app_providers.dart`: add `serverConnectionStateProvider` and `onlinePrimaryPolicyProvider`, stop injecting `SyncWriteRecorder` into server-managed repositories, pass policy loader to file transfer service.
- Modify `client_flutter/lib/core/connection/server_connection_state.dart`: add read-only/cache convenience getters.
- Modify `client_flutter/lib/core/connection/server_connection_service.dart`: remove local-write push hook; keep periodic cache refresh and heartbeat.
- Modify `client_flutter/lib/core/bootstrap/client_bootstrap_service.dart`: stop automatic push of legacy ordinary mutations; pull server changes and run tracking upload only after server reachability is known.
- Modify `client_flutter/lib/core/sync/sync_engine.dart`: expose pull-only cache refresh and leave `pushPending()` as legacy manual API.
- Modify `client_flutter/lib/core/sync/sync_write_recorder.dart`: document and guard legacy-only queue behavior.

Modify client business write files:

- Modify `client_flutter/lib/core/server_first/server_first_repository.dart`: default writes to no queue fallback.
- Modify `client_flutter/lib/core/server_first/task_event_server_first_store.dart`: remove local fallback create/update/delete behavior for tasks and events.
- Modify `client_flutter/lib/features/task/presentation/task_detail_page.dart`: disable or reject save/delete in read-only cache mode.
- Modify `client_flutter/lib/features/calendar/presentation/event_detail_page.dart`: disable or reject save/delete in read-only cache mode.
- Modify `client_flutter/lib/features/calendar/presentation/timeline_view.dart`: block drag/drop and resize writes in read-only cache mode.
- Modify `client_flutter/lib/features/data_management/presentation/data_management_page.dart`: block complete/delete batch actions in read-only cache mode.

Modify tracking files:

- Modify `client_flutter/lib/core/database/app_database.dart`: add `tracking_upload_quarantine` table and schema version 20.
- Modify `client_flutter/lib/features/tracker/services/tracking_upload_service.dart`: load spool rows directly, upload in chunks, delete confirmed records, quarantine identified rejects.
- Modify `client_flutter/lib/features/tracker/services/tracker_service.dart`: set automatic tracking upload interval to 60 seconds.
- Modify `client_flutter/lib/features/tracker/presentation/tracker_page.dart`: refresh diagnostics after upload and show local pending/deleted counts.
- Modify `client_flutter/lib/shared/providers/tracker_providers.dart`: expose diagnostics fields backed by source row counts and quarantine counts.

Modify file upload files:

- Modify `client_flutter/lib/features/files/services/file_transfer_service.dart`: require online policy before creating an upload job; create server upload session before persisting the local job.
- Modify `client_flutter/lib/features/files/presentation/file_transfer_center_page.dart`: check policy before opening `FilePicker`.
- Modify `client_flutter/lib/features/files/presentation/file_context_page.dart`: check policy before server storage registration and upload-related actions.
- Modify `client_flutter/lib/web_app/flowplanv2_web_app.dart`: probe server before web file picker/upload starts.

Modify server test files:

- Modify `server/src/files/files.service.unit.spec.ts`: assert upload session creation does not create canonical storage objects and completion does.
- Modify `server/src/tracking/tracking.service.unit.spec.ts`: assert `completeBatch` returns accepted/rejected counts and rejected samples with local ids.
- Modify `server/src/web/web.service.unit.spec.ts`: assert stale server versions are rejected for canonical task/event writes.

Modify client tests:

- Modify `client_flutter/test/core/server_first/server_first_repository_test.dart`
- Modify `client_flutter/test/core/server_first/task_event_server_first_store_test.dart`
- Modify `client_flutter/test/core/bootstrap/client_bootstrap_service_test.dart`
- Modify `client_flutter/test/core/connection/server_connection_service_test.dart`
- Modify `client_flutter/test/features/tracker/tracking_upload_service_test.dart`
- Modify `client_flutter/test/features/files/file_transfer_service_test.dart`
- Modify existing widget tests for task, event, timeline, file transfer, and server indicator pages where assertions mention queued local writes.

Create migration and documentation files:

- Create `client_flutter/lib/core/offline_queue/legacy_offline_mutation_cleanup_service.dart`: explicit inspect/export/discard service for old queue rows.
- Create `client_flutter/test/core/offline_queue/legacy_offline_mutation_cleanup_service_test.dart`
- Create `docs/architecture/online-primary-read-only-cache.md`
- Create `docs/qa/online-primary-read-only-cache-test-matrix.md`

Modify full test governance files:

- Modify `docs/test-governance/feature-test-matrix.csv`: add online-primary behavior rows for client policy, task/event write rejection, tracking spool upload cleanup, server-hosted file upload, legacy queue cleanup, and cross-end online-primary workflow evidence.
- Modify `docs/test-governance/manual-acceptance.csv`: add manual rows for real offline read-only cache behavior, real tracking batching/cleanup, and real file upload interruption/retry under the new server-hosted rule.
- Modify `docs/test-governance/cross-end-workflow-matrix.md`: add online-primary cache, tracking, and file workflows to the representative cross-end matrix.
- Create `docs/test-governance/reports/online-primary-read-only-cache-closeout.md`: stable closeout report template that records focused tests, full gate results, coverage artifacts, Flutter/Dart command evidence, and open manual acceptance rows.

## Scope Check

This plan covers one coordinated architecture migration. It touches several subsystems because the product rule is cross-cutting: ordinary writes, tracking, and files must agree on the same online-primary boundary. Each task below has a focused pass condition and can be reviewed independently.

---

### Task 1: Add Online-Primary Policy

**Files:**
- Create: `client_flutter/lib/core/online/online_primary_policy.dart`
- Modify: `client_flutter/lib/core/connection/server_connection_state.dart`
- Create: `client_flutter/test/core/online/online_primary_policy_test.dart`
- Modify: `client_flutter/lib/shared/providers/app_providers.dart`

- [ ] **Step 1: Write the failing policy test**

Create `client_flutter/test/core/online/online_primary_policy_test.dart`:

```dart
import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/online/online_primary_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('online state allows ordinary server writes', () {
    final policy = OnlinePrimaryPolicy.fromConnectionState(
      const ServerConnectionState(level: ServerConnectionLevel.online),
    );

    expect(policy.readOnlyCache, isFalse);
    expect(policy.canAttemptServerWrite, isTrue);
    expect(() => policy.requireOnlineBusinessWrite('save task'), returnsNormally);
  });

  test('offline and auth states reject ordinary business writes', () {
    for (final state in const <ServerConnectionState>[
      ServerConnectionState(level: ServerConnectionLevel.offline),
      ServerConnectionState(level: ServerConnectionLevel.degraded),
      ServerConnectionState(level: ServerConnectionLevel.localCacheOnly),
      ServerConnectionState(level: ServerConnectionLevel.authRequired),
    ]) {
      final policy = OnlinePrimaryPolicy.fromConnectionState(state);

      expect(policy.readOnlyCache, isTrue);
      expect(policy.canAttemptServerWrite, isFalse);
      expect(
        () => policy.requireOnlineBusinessWrite('save task'),
        throwsA(isA<OnlinePrimaryWriteRejected>()),
      );
    }
  });

  test('tracking spool and device local state remain allowed offline', () {
    final policy = OnlinePrimaryPolicy.fromConnectionState(
      const ServerConnectionState(level: ServerConnectionLevel.offline),
    );

    expect(policy.allowsTrackingSpoolWrite, isTrue);
    expect(policy.allowsDeviceLocalWrite, isTrue);
    expect(
      () => policy.requireOnlineFileUploadStart('upload file'),
      throwsA(isA<OnlinePrimaryWriteRejected>()),
    );
  });
}
```

- [ ] **Step 2: Run the failing Flutter policy test**

Codex may run:

```powershell
cd client_flutter
flutter test test/core/online/online_primary_policy_test.dart
```

Expected before implementation: compile failure for `core/online/online_primary_policy.dart`.

- [ ] **Step 3: Add the policy implementation**

Create `client_flutter/lib/core/online/online_primary_policy.dart`:

```dart
import '../connection/server_connection_state.dart';

enum OnlinePrimaryWriteKind {
  businessFact,
  fileUploadStart,
  fileTransferRetry,
  trackingSpool,
  deviceLocal,
}

class OnlinePrimaryWriteRejected implements Exception {
  const OnlinePrimaryWriteRejected({
    required this.action,
    required this.kind,
    required this.reason,
  });

  final String action;
  final OnlinePrimaryWriteKind kind;
  final String reason;

  @override
  String toString() {
    return 'OnlinePrimaryWriteRejected($action, $kind, $reason)';
  }
}

class OnlinePrimaryPolicy {
  const OnlinePrimaryPolicy({
    required this.serverReachable,
    required this.authenticated,
    required this.level,
  });

  factory OnlinePrimaryPolicy.fromConnectionState(ServerConnectionState state) {
    final serverReachable = switch (state.level) {
      ServerConnectionLevel.online ||
      ServerConnectionLevel.syncing ||
      ServerConnectionLevel.conflicted => true,
      ServerConnectionLevel.unknown ||
      ServerConnectionLevel.degraded ||
      ServerConnectionLevel.offline ||
      ServerConnectionLevel.authRequired ||
      ServerConnectionLevel.localCacheOnly => false,
    };
    return OnlinePrimaryPolicy(
      serverReachable: serverReachable,
      authenticated: state.level != ServerConnectionLevel.authRequired,
      level: state.level,
    );
  }

  final bool serverReachable;
  final bool authenticated;
  final ServerConnectionLevel level;

  bool get readOnlyCache => !serverReachable || !authenticated;
  bool get canAttemptServerWrite => !readOnlyCache;
  bool get allowsTrackingSpoolWrite => true;
  bool get allowsDeviceLocalWrite => true;

  void requireOnlineBusinessWrite(String action) {
    _requireServerWrite(action, OnlinePrimaryWriteKind.businessFact);
  }

  void requireOnlineFileUploadStart(String action) {
    _requireServerWrite(action, OnlinePrimaryWriteKind.fileUploadStart);
  }

  void requireOnlineFileTransferRetry(String action) {
    _requireServerWrite(action, OnlinePrimaryWriteKind.fileTransferRetry);
  }

  void _requireServerWrite(String action, OnlinePrimaryWriteKind kind) {
    if (!authenticated) {
      throw OnlinePrimaryWriteRejected(
        action: action,
        kind: kind,
        reason: 'Authentication is required before this write can be accepted.',
      );
    }
    if (!serverReachable) {
      throw OnlinePrimaryWriteRejected(
        action: action,
        kind: kind,
        reason: 'Server connection is required before this write can be accepted.',
      );
    }
  }
}
```

- [ ] **Step 4: Add connection state getters**

Modify `client_flutter/lib/core/connection/server_connection_state.dart`:

```dart
  bool get isReadOnlyCache {
    return switch (level) {
      ServerConnectionLevel.online ||
      ServerConnectionLevel.syncing ||
      ServerConnectionLevel.conflicted => false,
      ServerConnectionLevel.unknown ||
      ServerConnectionLevel.degraded ||
      ServerConnectionLevel.offline ||
      ServerConnectionLevel.authRequired ||
      ServerConnectionLevel.localCacheOnly => true,
    };
  }

  bool get canAttemptServerWrite => !isReadOnlyCache;
```

Place these getters after `bool get hasConflict => conflictCount > 0;`.

- [ ] **Step 5: Add a Riverpod provider for policy**

Modify `client_flutter/lib/shared/providers/app_providers.dart`:

```dart
import 'dart:async';

import '../../core/connection/server_connection_state.dart';
import '../../core/online/online_primary_policy.dart';
```

Add after `serverConnectionServiceProvider`:

```dart
final serverConnectionStateProvider =
    StreamProvider<ServerConnectionState>((ref) async* {
  final service = await ref.watch(serverConnectionServiceProvider.future);
  yield service.state;
  final controller = StreamController<ServerConnectionState>();
  void listener() {
    controller.add(service.state);
  }

  service.addListener(listener);
  ref.onDispose(() {
    service.removeListener(listener);
    controller.close();
  });
  yield* controller.stream;
}, dependencies: [serverConnectionServiceProvider]);

final onlinePrimaryPolicyProvider = Provider<OnlinePrimaryPolicy>((ref) {
  final state = ref.watch(serverConnectionStateProvider).valueOrNull ??
      const ServerConnectionState(level: ServerConnectionLevel.localCacheOnly);
  return OnlinePrimaryPolicy.fromConnectionState(state);
}, dependencies: [serverConnectionStateProvider]);
```

- [ ] **Step 6: Run the passing policy test**

Codex may run:

```powershell
cd client_flutter
flutter test test/core/online/online_primary_policy_test.dart
```

Expected after implementation: all tests pass.

- [ ] **Step 7: Commit Task 1**

```powershell
git status --short
git add client_flutter/lib/core/online/online_primary_policy.dart client_flutter/lib/core/connection/server_connection_state.dart client_flutter/lib/shared/providers/app_providers.dart client_flutter/test/core/online/online_primary_policy_test.dart
git commit -m "feat: add online-primary write policy"
```

---

### Task 2: Remove Task/Event Offline Write Fallbacks

**Files:**
- Modify: `client_flutter/lib/core/server_first/server_first_repository.dart`
- Modify: `client_flutter/lib/core/server_first/task_event_server_first_store.dart`
- Modify: `client_flutter/test/core/server_first/server_first_repository_test.dart`
- Modify: `client_flutter/test/core/server_first/task_event_server_first_store_test.dart`
- Modify: `client_flutter/test/core/server_first/task_event_server_first_store_gap_worker_store_test.dart`
- Modify: `client_flutter/test/core/server_first/task_event_server_first_store_additional_test.dart`

- [ ] **Step 1: Rewrite repository failure tests**

In `client_flutter/test/core/server_first/server_first_repository_test.dart`, replace the two tests named `API failures queue task writes when queueOnFailure is enabled` and `generic transport failures queue event updates with sync metadata` with:

```dart
  test('API failures rethrow and do not create offline mutations by default',
      () async {
    final harness = _Harness((request) async {
      return http.Response('{"error":"offline"}', 503);
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.createTask(
        const <String, Object?>{
          'uid': 'task-offline',
          'summary': 'Offline task',
        },
      ),
      throwsA(isA<ApiError>()),
    );

    expect(await harness.store.listPending(), isEmpty);
  });

  test('transport failures rethrow and do not create offline mutations',
      () async {
    final harness = _Harness((request) async {
      throw StateError('socket closed');
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.updateEvent(
        id: 'event-server-1',
        patch: const <String, Object?>{'location': 'Room A'},
        baseServerVersion: 11,
        changedFields: const <String>['location'],
      ),
      throwsA(isA<StateError>()),
    );

    expect(await harness.store.listPending(), isEmpty);
  });
```

- [ ] **Step 2: Rewrite store failure tests**

In `client_flutter/test/core/server_first/task_event_server_first_store_test.dart`, replace pending-fallback assertions with server-rejection assertions. Use this exact test for failed create:

```dart
  test('createTask rejects server failure without local task or mutation',
      () async {
    final harness = _Harness((_) async => http.Response('server down', 503));
    await harness.setUp();
    addTearDown(harness.dispose);

    await expectLater(
      harness.store.createTask(<String, Object?>{
        'uid': 'task-uid-2',
        'summary': 'Offline draft',
        'taskListId': harness.taskListId,
      }),
      throwsA(isA<ApiError>()),
    );

    expect(await harness.db.select(harness.db.taskItems).get(), isEmpty);
    expect(await harness.mutationStore.listPending(), isEmpty);
  });
```

Use this exact test for failed update:

```dart
  test('updateLocalTask rejects server failure without changing cache',
      () async {
    final requests = <http.Request>[];
    final harness = _Harness((request) async {
      requests.add(request);
      return http.Response('conflict', 409);
    });
    await harness.setUp();
    addTearDown(harness.dispose);
    final localId = await harness.db.into(harness.db.taskItems).insert(
          fixtureTask(
            uid: 'task-uid-3',
            summary: 'Before server failure',
            taskListId: harness.taskListId,
          ),
        );
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
      serverId: 'server-task-3',
      serverVersion: 11,
      uid: 'task-uid-3',
    );

    await expectLater(
      harness.store.updateLocalTask(
        localId: localId,
        patch: const <String, Object?>{
          'summary': 'Rejected local edit',
          'status': 'done',
        },
        changedFields: const <String>['summary', 'status'],
      ),
      throwsA(isA<ApiError>()),
    );

    final task = await (harness.db.select(harness.db.taskItems)
          ..where((row) => row.id.equals(localId)))
        .getSingle();
    expect(requests, hasLength(1));
    expect(task.summary, 'Before server failure');
    expect(task.status, isNot('COMPLETED'));
    expect(await harness.mutationStore.listPending(), isEmpty);
  });
```

Add these three additional tests in the same file:

```dart
  test('updateLocalEvent rejects server failure without changing cache',
      () async {
    final requests = <http.Request>[];
    final harness = _Harness((request) async {
      requests.add(request);
      return http.Response('conflict', 409);
    });
    await harness.setUp();
    addTearDown(harness.dispose);
    final localId = await harness.db.into(harness.db.calendarEvents).insert(
          fixtureEvent(
            uid: 'event-uid-reject',
            summary: 'Before event failure',
            calendarId: harness.calendarId,
          ),
        );
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.calendarEvent.key,
      localId: localId.toString(),
      serverId: 'server-event-reject',
      serverVersion: 21,
      uid: 'event-uid-reject',
    );

    await expectLater(
      harness.store.updateLocalEvent(
        localId: localId,
        patch: const <String, Object?>{'summary': 'Rejected event edit'},
        changedFields: const <String>['summary'],
      ),
      throwsA(isA<ApiError>()),
    );

    final event = await (harness.db.select(harness.db.calendarEvents)
          ..where((row) => row.id.equals(localId)))
        .getSingle();
    expect(requests, hasLength(1));
    expect(event.summary, 'Before event failure');
    expect(await harness.mutationStore.listPending(), isEmpty);
  });

  test('deleteLocalTask rejects server failure without deleting cache row',
      () async {
    final harness = _Harness((_) async => http.Response('server down', 503));
    await harness.setUp();
    addTearDown(harness.dispose);
    final localId = await harness.db.into(harness.db.taskItems).insert(
          fixtureTask(
            uid: 'task-delete-reject',
            summary: 'Keep task',
            taskListId: harness.taskListId,
          ),
        );
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
      serverId: 'server-task-delete-reject',
      serverVersion: 22,
      uid: 'task-delete-reject',
    );

    await expectLater(
      harness.store.deleteLocalTask(localId: localId),
      throwsA(isA<ApiError>()),
    );

    final rows = await harness.db.select(harness.db.taskItems).get();
    expect(rows.where((task) => task.id == localId), hasLength(1));
    expect(await harness.mutationStore.listPending(), isEmpty);
  });

  test('deleteLocalEvent rejects server failure without deleting cache row',
      () async {
    final harness = _Harness((_) async => http.Response('server down', 503));
    await harness.setUp();
    addTearDown(harness.dispose);
    final localId = await harness.db.into(harness.db.calendarEvents).insert(
          fixtureEvent(
            uid: 'event-delete-reject',
            summary: 'Keep event',
            calendarId: harness.calendarId,
          ),
        );
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.calendarEvent.key,
      localId: localId.toString(),
      serverId: 'server-event-delete-reject',
      serverVersion: 23,
      uid: 'event-delete-reject',
    );

    await expectLater(
      harness.store.deleteLocalEvent(localId: localId),
      throwsA(isA<ApiError>()),
    );

    final rows = await harness.db.select(harness.db.calendarEvents).get();
    expect(rows.where((event) => event.id == localId), hasLength(1));
    expect(await harness.mutationStore.listPending(), isEmpty);
  });
```

- [ ] **Step 3: Run the failing server-first tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/core/server_first/server_first_repository_test.dart test/core/server_first/task_event_server_first_store_test.dart
```

Expected before implementation: old code returns `pending` and creates local rows, so the new tests fail.

- [ ] **Step 4: Disable queue defaults in the repository**

Modify `client_flutter/lib/core/server_first/server_first_repository.dart`:

```dart
  Future<ServerFirstWriteResult> createTask(
    Map<String, Object?> payload, {
    bool queueOnFailure = false,
  }) {
```

Set these method signatures in `server_first_repository.dart`:

```dart
Future<ServerFirstWriteResult> createEvent(
  Map<String, Object?> payload, {
  bool queueOnFailure = false,
})

Future<ServerFirstWriteResult> updateTask({
  required String id,
  required Map<String, Object?> patch,
  int? baseServerVersion,
  List<String>? changedFields,
  bool queueOnFailure = false,
})

Future<ServerFirstWriteResult> completeTask({
  required String id,
  Map<String, Object?> body = const <String, Object?>{},
  int? baseServerVersion,
  bool queueOnFailure = false,
})

Future<ServerFirstWriteResult> deleteTask({
  required String id,
  int? baseServerVersion,
  bool queueOnFailure = false,
})

Future<ServerFirstWriteResult> updateEvent({
  required String id,
  required Map<String, Object?> patch,
  int? baseServerVersion,
  List<String>? changedFields,
  bool queueOnFailure = false,
})

Future<ServerFirstWriteResult> deleteEvent({
  required String id,
  int? baseServerVersion,
  bool queueOnFailure = false,
})
```

Keep `_queue` for the legacy cleanup task and existing migration tooling.

- [ ] **Step 5: Remove local fallback writes from create methods**

In `client_flutter/lib/core/server_first/task_event_server_first_store.dart`, replace `createTask` with:

```dart
  Future<ServerFirstWriteResult> createTask(
      Map<String, Object?> payload) async {
    final writePayload = _ensureUid(payload);
    final result = await _repository.createTask(
      writePayload,
      queueOnFailure: false,
    );
    final localId =
        await _createLocalTask(_payloadForLocal(result, writePayload));
    await _markSyncedFromResult(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
      fallbackUid: stringFromMap(writePayload, 'uid'),
      result: result,
    );
    return result;
  }
```

Replace `createEvent` with:

```dart
  Future<ServerFirstWriteResult> createEvent(
    Map<String, Object?> payload,
  ) async {
    final writePayload = _ensureUid(payload);
    final result = await _repository.createEvent(
      writePayload,
      queueOnFailure: false,
    );
    final localId =
        await _createLocalEvent(_payloadForLocal(result, writePayload));
    await _markSyncedFromResult(
      objectType: SyncObjectType.calendarEvent.key,
      localId: localId.toString(),
      fallbackUid: stringFromMap(writePayload, 'uid'),
      result: result,
    );
    return result;
  }
```

- [ ] **Step 6: Remove local fallback writes from update/delete methods**

In `updateLocalTask`, keep the successful server path and replace both fallback branches with throws:

```dart
    if (serverId == null) {
      throw StateError(
        'Cannot update a cache-only task. Refresh from the server before editing.',
      );
    }
```

Inside the server-id branch, remove the `try/catch` fallback. The body should call `_repository.updateTask`, update local cache from the canonical result, mark synced, and return.

Make these concrete replacements:

- `updateLocalEvent`: throw `StateError('Cannot update a cache-only event. Refresh from the server before editing.')` when `serverId == null`; remove the catch block; update the local event only after `_repository.updateEvent(id: serverId, patch: patch, baseServerVersion: version, changedFields: changedFields, queueOnFailure: false)` succeeds.
- `deleteLocalTask`: throw `StateError('Cannot delete a cache-only task. Refresh from the server before editing.')` when `serverId == null`; remove the catch block; call `_taskRepository.delete(localId, audit: false)` only after `_repository.deleteTask(id: serverId, baseServerVersion: version, queueOnFailure: false)` succeeds.
- `deleteLocalEvent`: throw `StateError('Cannot delete a cache-only event. Refresh from the server before editing.')` when `serverId == null`; remove the catch block; call `_eventRepository.delete(localId, audit: false)` only after `_repository.deleteEvent(id: serverId, baseServerVersion: version, queueOnFailure: false)` succeeds.

For delete methods, do not delete the local Drift row until the server delete returns canonical success.

- [ ] **Step 7: Retain explicit legacy queue method only for migration**

Keep `queueLegacyCacheMutation` in `TaskEventServerFirstStore`, but add this comment above it:

```dart
  // Legacy migration hook only. Online-primary task/event write paths must not
  // call this method for user-initiated business writes.
```

- [ ] **Step 8: Run the passing server-first tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/core/server_first/server_first_repository_test.dart test/core/server_first/task_event_server_first_store_test.dart test/core/server_first/task_event_server_first_store_gap_worker_store_test.dart test/core/server_first/task_event_server_first_store_additional_test.dart
```

Expected after implementation: tests pass and no ordinary task/event write creates `offline_mutations`.

- [ ] **Step 9: Commit Task 2**

```powershell
git status --short
git add client_flutter/lib/core/server_first/server_first_repository.dart client_flutter/lib/core/server_first/task_event_server_first_store.dart client_flutter/test/core/server_first/server_first_repository_test.dart client_flutter/test/core/server_first/task_event_server_first_store_test.dart client_flutter/test/core/server_first/task_event_server_first_store_gap_worker_store_test.dart client_flutter/test/core/server_first/task_event_server_first_store_additional_test.dart
git commit -m "refactor: reject task event writes without server acceptance"
```

---

### Task 3: Stop Injecting Offline Mutation Recording Into Server-Managed Repositories

**Files:**
- Modify: `client_flutter/lib/shared/providers/app_providers.dart`
- Modify: `client_flutter/lib/core/sync/sync_write_recorder.dart`
- Create: `client_flutter/test/shared/providers/online_primary_provider_wiring_test.dart`
- Modify: repository tests that still assert provider-created `offline_mutations`

- [ ] **Step 1: Write a provider wiring test**

Create `client_flutter/test/shared/providers/online_primary_provider_wiring_test.dart`:

```dart
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test('server-managed repository providers do not enqueue offline mutations',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final container = ProviderContainer(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
      ],
    );
    addTearDown(container.dispose);
    final listId = await insertFixtureTaskList(db);
    final repo = container.read(taskRepositoryProvider);

    await repo.create(
      TaskItemsCompanion.insert(
        uid: 'provider-task-1',
        dtstamp: DateTime.utc(2026, 6, 12),
        summary: 'Provider local cache write',
        taskListId: Value(listId),
      ),
    );

    final rows = await db.customSelect('SELECT * FROM offline_mutations').get();
    expect(rows, isEmpty);
  });
}
```

- [ ] **Step 2: Run the failing provider wiring test**

Codex may run:

```powershell
cd client_flutter
flutter test test/shared/providers/online_primary_provider_wiring_test.dart
```

Expected before implementation: one `offline_mutations` row is created by injected `SyncWriteRecorder`.

- [ ] **Step 3: Stop passing sync recorders from normal providers**

Modify `client_flutter/lib/shared/providers/app_providers.dart` so these providers construct repositories without `syncWriteRecorderProvider`:

```dart
final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  return TaskRepository(db, operationLogs);
}, dependencies: [
  databaseProvider,
  dataOperationLogRepositoryProvider,
]);
```

Change these provider constructors explicitly:

```dart
return EventRepository(db, operationLogs);
return CalendarBooksRepository(db, operationLogs);
return ActualActivityLogRepository(db, operationLogs);
return ReportRepository(db, operationLogs);
return FileContextRepository(
  db,
  operationLogs,
  null,
  () => ref.read(fileContextApiProvider.future),
);
return DataOperationLogRepository(db);
```

Keep `syncWriteRecorderProvider`, `offlineMutationStoreProvider`, and `mutationCoordinatorProvider` for legacy diagnostics and migration.

- [ ] **Step 4: Add a legacy-only note to SyncWriteRecorder**

Modify `client_flutter/lib/core/sync/sync_write_recorder.dart`:

```dart
/// Legacy offline mutation recorder.
///
/// Online-primary production providers must not inject this into
/// server-managed repositories. It remains available for migration tools and
/// tests that inspect existing queued mutation behavior.
class SyncWriteRecorder {
```

- [ ] **Step 5: Update tests that use provider wiring**

For each test that expected provider-created mutations, replace the provider-read repository with a directly constructed repository using an explicit recorder:

```dart
final mutationStore = OfflineMutationStore(db);
final stateStore = SyncObjectStateStore(db);
final recorder = SyncWriteRecorder(
  mutationStore: mutationStore,
  stateStore: stateStore,
);
final repo = TaskRepository(
  db,
  DataOperationLogRepository(db),
  recorder,
);
```

Do not reintroduce recorder injection in `app_providers.dart`.

- [ ] **Step 6: Run focused provider and repository tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/shared/providers/online_primary_provider_wiring_test.dart test/features/task/task_repository_test.dart test/features/calendar/calendar_repository_test.dart test/features/files/file_context_repository_test.dart
```

Expected after implementation: provider wiring test passes; repository tests pass after direct recorder construction in the tests changed by Step 5.

- [ ] **Step 7: Commit Task 3**

```powershell
git status --short
git add client_flutter/lib/shared/providers/app_providers.dart client_flutter/lib/core/sync/sync_write_recorder.dart client_flutter/test/shared/providers/online_primary_provider_wiring_test.dart client_flutter/test/features/task/task_repository_test.dart client_flutter/test/features/calendar/calendar_repository_test.dart client_flutter/test/features/files/file_context_repository_test.dart
git commit -m "refactor: stop offline mutation recording in app providers"
```

---

### Task 4: Convert Bootstrap Sync To Pull-Only Cache Refresh

**Files:**
- Modify: `client_flutter/lib/core/bootstrap/client_bootstrap_service.dart`
- Modify: `client_flutter/lib/core/connection/server_connection_service.dart`
- Modify: `client_flutter/lib/core/sync/sync_engine.dart`
- Modify: `client_flutter/test/core/bootstrap/client_bootstrap_service_test.dart`
- Modify: `client_flutter/test/core/connection/server_connection_service_test.dart`
- Modify: `client_flutter/test/core/sync/sync_engine_test.dart`

- [ ] **Step 1: Rewrite bootstrap tests to expect no automatic push**

In `client_flutter/test/core/bootstrap/client_bootstrap_service_test.dart`, update the first test expectation:

```dart
    expect(harness.engine.pushSources, isEmpty);
    expect(harness.engine.pullSources, hasLength(1));
```

Update expected progress phases from:

```dart
<String>[
  'preparing',
  'pushing',
  'tracking_upload',
  'pulling',
  'applying',
  'completed',
]
```

to:

```dart
<String>[
  'preparing',
  'tracking_upload',
  'pulling',
  'applying',
  'completed',
]
```

Remove assertions for `accepted`, `conflicts`, `rejected`, and `pushed` from bootstrap summaries. Keep `trackingUpload`, `pulledChanges`, `appliedChanges`, `skippedChanges`, and `failedChanges`.

- [ ] **Step 2: Rewrite connection hook test**

In `client_flutter/test/core/connection/server_connection_service_test.dart`, change `start initializes once and dispose clears global hooks`:

```dart
    expect(SyncWriteRecorder.onMutationRecorded, isNull);
```

After dispose, keep:

```dart
    expect(SyncWriteRecorder.onMutationRecorded, isNull);
```

Remove the expectation that a hook is installed.

- [ ] **Step 3: Add a pull-only sync engine method test**

In `client_flutter/test/core/sync/sync_engine_test.dart`, add:

```dart
  test('refreshCacheFromServer pulls without pushing pending mutations',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final cursorStore = SyncCursorStore(db);
    final mutationStore = OfflineMutationStore(db);
    await mutationStore.enqueue(
      objectType: 'task_item',
      localId: 'legacy-local-task',
      action: OfflineMutationAction.create,
      payload: const <String, Object?>{'summary': 'Legacy queued task'},
    );
    var pushed = false;
    var pulled = false;

    final engine = ServerSyncEngine(
      cursorStore: cursorStore,
      offlineMutationRunner: _ThrowingPushRunner(mutationStore, () {
        pushed = true;
      }),
      apiClient: ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/sync/pull');
          pulled = true;
          return http.Response(
            jsonEncode(<String, Object?>{'changes': <Object?>[]}),
            200,
          );
        }),
      ),
    );

    await engine.refreshCacheFromServer();

    expect(pulled, isTrue);
    expect(pushed, isFalse);
    expect(await mutationStore.listPending(), hasLength(1));
  });
```

Add the test helper:

```dart
class _ThrowingPushRunner extends OfflineMutationRunner {
  _ThrowingPushRunner(OfflineMutationStore store, this.onPush) : super(store);

  final void Function() onPush;

  @override
  Future<ServerSyncResult> pushPending(ApiClient apiClient) async {
    onPush();
    throw StateError('push must not run');
  }
}
```

- [ ] **Step 4: Run failing bootstrap/sync tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/core/bootstrap/client_bootstrap_service_test.dart test/core/connection/server_connection_service_test.dart test/core/sync/sync_engine_test.dart
```

Expected before implementation: tests fail because bootstrap still calls `pushPending()` and connection still installs `SyncWriteRecorder.onMutationRecorded`.

- [ ] **Step 5: Add pull-only cache refresh API**

Modify `client_flutter/lib/core/sync/sync_engine.dart`:

```dart
  Future<Map<String, dynamic>> refreshCacheFromServer({
    int limit = 200,
    void Function(int pulledChanges, int pageCount)? onProgress,
  }) {
    return pullChanges(limit: limit, onProgress: onProgress);
  }
```

Place it after `pushPending()`.

- [ ] **Step 6: Remove automatic push from bootstrap**

In `client_flutter/lib/core/bootstrap/client_bootstrap_service.dart`, remove:

```dart
      _reportProgress('pushing', source: source, message: 'Pushing local changes');
      final push = await engine.pushPending();
```

from both `bootstrapAndSync` and `syncNow`.

Replace summary fields with:

```dart
          'legacyOfflineQueue': await _localStateSummary(),
```

and remove:

```dart
'accepted': push.acceptedCount,
'conflicts': push.conflictCount,
'rejected': push.rejectedCount,
'pushed': push.processedCount,
```

Use:

```dart
      final pull = await engine.refreshCacheFromServer(
        onProgress: (pulled, pages) {
          _reportProgress(
            'applying',
            source: source,
            current: pulled,
            message: 'Applying server changes',
          );
        },
      );
```

- [ ] **Step 7: Remove local mutation hook from connection service**

Modify `client_flutter/lib/core/connection/server_connection_service.dart`:

```dart
  void start() {
    if (_started) {
      return;
    }
    _started = true;
    unawaited(_initialize());
    _fullSyncTimer?.cancel();
    _fullSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      requestSync(source: 'timer', reason: 'periodic_cache_refresh');
    });
  }
```

In `dispose`, remove the block that clears `SyncWriteRecorder.onMutationRecorded`.

- [ ] **Step 8: Run passing bootstrap/sync tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/core/bootstrap/client_bootstrap_service_test.dart test/core/connection/server_connection_service_test.dart test/core/sync/sync_engine_test.dart
```

Expected after implementation: tests pass; legacy queued mutations are not pushed during startup, timer refresh, heartbeat-triggered refresh, or manual indicator refresh.

- [ ] **Step 9: Commit Task 4**

```powershell
git status --short
git add client_flutter/lib/core/bootstrap/client_bootstrap_service.dart client_flutter/lib/core/connection/server_connection_service.dart client_flutter/lib/core/sync/sync_engine.dart client_flutter/test/core/bootstrap/client_bootstrap_service_test.dart client_flutter/test/core/connection/server_connection_service_test.dart client_flutter/test/core/sync/sync_engine_test.dart
git commit -m "refactor: make client sync pull-only for cache refresh"
```

---

### Task 5: Tracking Upload Deletes Confirmed Local Records

**Files:**
- Modify: `client_flutter/lib/core/database/app_database.dart`
- Modify: `client_flutter/lib/features/tracker/services/tracking_upload_service.dart`
- Modify: `client_flutter/test/features/tracker/tracking_upload_service_test.dart`

- [ ] **Step 1: Rewrite tracking upload success test**

In `client_flutter/test/features/tracker/tracking_upload_service_test.dart`, rename `uploads each tracking kind in chunks and advances cursors` to:

```dart
  test('uploads each tracking kind in chunks and deletes confirmed rows',
      () async {
```

Replace cursor assertions with source row count assertions:

```dart
    Future<int> countRows(String table) async {
      final row = await db
          .customSelect('SELECT COUNT(*) AS count FROM $table')
          .getSingle();
      return row.read<int>('count');
    }

    expect(await countRows('activity_records'), 0);
    expect(await countRows('tracked_input_events'), 0);
    expect(await countRows('raw_activity_logs'), 0);
    final diagnostics = await service.buildUploadDiagnostics();
    expect(diagnostics['pendingActivityRecords'], 0);
    expect(diagnostics['pendingInputEvents'], 0);
    expect(diagnostics['pendingRawLogs'], 0);
    expect(diagnostics['quarantinedRecords'], 0);
    expect(diagnostics['lastCompletedAt'], isNotNull);
    expect(diagnostics['lastError'], isNull);
```

- [ ] **Step 2: Rewrite tracking failure tests**

For `preserves cursor and records last error when upload fails`, rename to:

```dart
  test('preserves source rows and records last error when upload fails',
      () async {
```

Replace cursor expectations with:

```dart
    final diagnostics = await service.buildUploadDiagnostics();
    expect(diagnostics['pendingActivityRecords'], 1);
    expect(
      diagnostics['lastError'].toString(),
      contains('server rejected batch'),
    );
    final rows =
        await db.customSelect('SELECT * FROM activity_records').get();
    expect(rows, hasLength(1));
```

For chunk failure, assert the successfully completed kind was deleted and the failing kind remains:

```dart
    expect(diagnostics['pendingActivityRecords'], 0);
    expect(diagnostics['pendingInputEvents'], 1);
```

- [ ] **Step 3: Add partial rejection test**

Add:

```dart
  test('partial rejection deletes accepted rows and quarantines rejected rows',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final api = FakeTrackingIngestApi(
      completeResponses: <String, Map<String, dynamic>>{
        'activity_record': <String, dynamic>{
          'ok': true,
          'accepted': 1,
          'rejected': 1,
          'rejectedSamples': <Map<String, Object?>>[
            <String, Object?>{'localId': '2', 'reason': 'bad payload'},
          ],
        },
      },
    );
    final service = serviceFor(db, api);
    final base = DateTime(2026, 6, 15, 13);

    await insertActivityRecord(db, start: base);
    await insertActivityRecord(
      db,
      start: base.add(const Duration(minutes: 5)),
    );

    final result = await service.uploadPending(limitPerKind: 10, chunkSize: 2);

    expect(result.uploadedRecords, 2);
    final remaining = await db
        .customSelect('SELECT id FROM activity_records ORDER BY id ASC')
        .get();
    expect(remaining.map((row) => row.read<int>('id')), <int>[2]);
    final quarantine = await db
        .customSelect('SELECT data_kind, local_id FROM tracking_upload_quarantine')
        .get();
    expect(quarantine.single.read<String>('data_kind'), 'activity_record');
    expect(quarantine.single.read<String>('local_id'), '2');
    final diagnostics = await service.buildUploadDiagnostics();
    expect(diagnostics['quarantinedRecords'], 1);
  });
```

- [ ] **Step 4: Run failing tracking tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/features/tracker/tracking_upload_service_test.dart
```

Expected before implementation: tests fail because the service advances cursor settings instead of deleting source rows.

- [ ] **Step 5: Add quarantine table migration**

Modify `client_flutter/lib/core/database/app_database.dart`:

```dart
  int get schemaVersion => 20;
```

In `onCreate`, after `_ensureTrackedInputEventsTable();`, add:

```dart
          await _ensureTrackingUploadQuarantineTable();
```

In `onUpgrade`, add:

```dart
          if (from < 20) {
            await _ensureTrackingUploadQuarantineTable();
          }
```

Add the helper:

```dart
  Future<void> _ensureTrackingUploadQuarantineTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS tracking_upload_quarantine (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        data_kind TEXT NOT NULL,
        local_id TEXT NOT NULL,
        reason TEXT NOT NULL,
        sample_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await customStatement(
      'CREATE UNIQUE INDEX IF NOT EXISTS tracking_upload_quarantine_kind_local_idx '
      'ON tracking_upload_quarantine(data_kind, local_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS tracking_upload_quarantine_created_idx '
      'ON tracking_upload_quarantine(created_at)',
    );
  }
```

- [ ] **Step 6: Load pending tracking rows without cursors**

Modify `_loadActivityRecords`, `_loadTrackedInputEvents`, and `_loadRawActivityLogs` in `tracking_upload_service.dart` so each query excludes quarantined records and does not read last-id settings.

For activity records:

```dart
      '''
      SELECT *
      FROM activity_records
      WHERE id NOT IN (
        SELECT CAST(local_id AS INTEGER)
        FROM tracking_upload_quarantine
        WHERE data_kind = 'activity_record'
      )
      ORDER BY id ASC
      LIMIT ?
      ''',
      variables: [Variable<int>(limit)],
```

Set `previousLastId: 0` for each export. Use these source-specific filters:

```sql
FROM tracked_input_events
WHERE id NOT IN (
  SELECT CAST(local_id AS INTEGER)
  FROM tracking_upload_quarantine
  WHERE data_kind = 'tracked_input_event'
)
ORDER BY id ASC
LIMIT ?
```

```sql
FROM raw_activity_logs
WHERE id NOT IN (
  SELECT CAST(local_id AS INTEGER)
  FROM tracking_upload_quarantine
  WHERE data_kind = 'raw_activity_log'
)
ORDER BY id ASC
LIMIT ?
```

- [ ] **Step 7: Delete only safely confirmed records**

In `_uploadKind`, after `completeBatch`, replace:

```dart
    await _database.setSetting(export.lastIdKey, export.maxId.toString());
```

with:

```dart
    await _applyCompletionCleanup(export, completed);
```

Add:

```dart
  Future<void> _applyCompletionCleanup(
    _TrackingKindExport export,
    Map<String, dynamic> completed,
  ) async {
    final accepted = _readInt(completed['accepted']) ?? 0;
    final rejected = _readInt(completed['rejected']) ?? 0;
    if (accepted <= 0 && rejected <= 0) {
      return;
    }

    final rejectedIds = _rejectedLocalIds(completed['rejectedSamples']);
    if (rejected > 0 && rejectedIds.length != rejected) {
      await _database.setSetting(
        lastErrorKey,
        'Tracking ingest did not return enough rejected local ids for ${export.dataKind}.',
      );
      return;
    }

    await _database.transaction(() async {
      if (rejectedIds.isNotEmpty) {
        await _quarantineRejected(export, rejectedIds, completed);
      }
      final acceptedIds = export.localIds
          .where((id) => !rejectedIds.contains(id.toString()))
          .toList(growable: false);
      if (acceptedIds.isNotEmpty) {
        await _deleteSourceRows(export, acceptedIds);
      }
    });
  }
```

Add these helpers:

```dart
  Set<String> _rejectedLocalIds(Object? rejectedSamples) {
    if (rejectedSamples is! List) {
      return const <String>{};
    }
    return rejectedSamples
        .whereType<Map>()
        .map((sample) => sample['localId']?.toString())
        .whereType<String>()
        .where((id) => id.trim().isNotEmpty)
        .toSet();
  }

  Future<void> _quarantineRejected(
    _TrackingKindExport export,
    Set<String> rejectedIds,
    Map<String, dynamic> completed,
  ) async {
    final now = DateTime.now().toIso8601String();
    for (final localId in rejectedIds) {
      await _database.customStatement(
        '''
        INSERT INTO tracking_upload_quarantine (
          data_kind, local_id, reason, sample_json, created_at
        ) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(data_kind, local_id) DO UPDATE SET
          reason = excluded.reason,
          sample_json = excluded.sample_json
        ''',
        <Object?>[
          export.dataKind,
          localId,
          'server_rejected_record',
          jsonEncode(completed),
          now,
        ],
      );
    }
  }

  Future<void> _deleteSourceRows(
    _TrackingKindExport export,
    List<int> acceptedIds,
  ) async {
    final parameterMarkers = List.filled(acceptedIds.length, '?').join(',');
    await _database.customStatement(
      'DELETE FROM ${export.sourceTable} WHERE id IN ($parameterMarkers)',
      acceptedIds,
    );
  }
```

- [ ] **Step 8: Extend export metadata**

Modify `_TrackingKindExport`:

```dart
  _TrackingKindExport({
    required this.dataKind,
    required this.sourceTable,
    required this.lastIdKey,
    required this.previousLastId,
    required this.rows,
    required this.records,
  });

  final String sourceTable;
```

Add:

```dart
  List<int> get localIds {
    return rows
        .map((row) => TrackingUploadService._readInt(row.data['id']))
        .whereType<int>()
        .toList(growable: false);
  }
```

Pass `sourceTable` in each loader:

```dart
sourceTable: 'activity_records',
```

- [ ] **Step 9: Update diagnostics**

In `buildUploadDiagnostics`, change pending counts to raw table counts excluding quarantine. Add:

```dart
    final quarantineRow = await _database.customSelect(
      'SELECT COUNT(*) AS count FROM tracking_upload_quarantine',
    ).getSingleOrNull();
```

Return:

```dart
      'quarantinedRecords': quarantineRow?.read<int?>('count') ?? 0,
```

Keep the last-id keys for read compatibility, but they no longer drive upload selection.

- [ ] **Step 10: Run passing tracking tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/features/tracker/tracking_upload_service_test.dart
```

Expected after implementation: all tracking upload tests pass.

- [ ] **Step 11: Commit Task 5**

```powershell
git status --short
git add client_flutter/lib/core/database/app_database.dart client_flutter/lib/features/tracker/services/tracking_upload_service.dart client_flutter/test/features/tracker/tracking_upload_service_test.dart
git commit -m "feat: delete confirmed tracking spool records"
```

---

### Task 6: Set Tracking Upload Cadence To 60 Seconds

**Files:**
- Modify: `client_flutter/lib/features/tracker/services/tracker_service.dart`
- Modify: `client_flutter/test/features/tracker/tracker_service_additional_test.dart`
- Modify: `client_flutter/test/features/tracker/tracker_service_deep_test.dart`
- Modify: `client_flutter/lib/shared/providers/tracker_providers.dart`

- [ ] **Step 1: Add a cadence test**

Add this test to the tracker service test file that already covers timers:

```dart
  test('default auto upload interval is sixty seconds', () {
    expect(TrackerService.defaultAutoUploadInterval, const Duration(seconds: 60));
  });
```

- [ ] **Step 2: Run the failing tracker service test**

Codex may run:

```powershell
cd client_flutter
flutter test test/features/tracker/tracker_service_additional_test.dart
```

Expected before implementation: interval is ten minutes.

- [ ] **Step 3: Add a public interval constant and use it**

Modify `client_flutter/lib/features/tracker/services/tracker_service.dart`:

```dart
  static const defaultAutoUploadInterval = Duration(seconds: 60);
```

Replace:

```dart
      debugTrackerAutoUploadIntervalOverride ?? const Duration(minutes: 10);
```

with:

```dart
      debugTrackerAutoUploadIntervalOverride ?? defaultAutoUploadInterval;
```

- [ ] **Step 4: Surface quarantine and pending counts in diagnostics provider**

Modify `client_flutter/lib/shared/providers/tracker_providers.dart` so `trackingUploadDiagnosticsProvider` passes through:

```dart
'pendingActivityRecords'
'pendingInputEvents'
'pendingRawLogs'
'quarantinedRecords'
'lastCompletedAt'
'lastError'
```

from `TrackingUploadService.buildUploadDiagnostics()`.

- [ ] **Step 5: Run focused tracker tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/features/tracker/tracker_service_additional_test.dart test/features/tracker/tracking_upload_service_test.dart test/features/tracker/tracker_providers_test.dart
```

Expected after implementation: timer and diagnostics tests pass.

- [ ] **Step 6: Commit Task 6**

```powershell
git status --short
git add client_flutter/lib/features/tracker/services/tracker_service.dart client_flutter/lib/shared/providers/tracker_providers.dart client_flutter/test/features/tracker/tracker_service_additional_test.dart client_flutter/test/features/tracker/tracker_service_deep_test.dart client_flutter/test/features/tracker/tracker_providers_test.dart
git commit -m "feat: upload tracking spool every minute"
```

---

### Task 7: Require Online Server Session Before File Upload Jobs

**Files:**
- Modify: `client_flutter/lib/features/files/services/file_transfer_service.dart`
- Modify: `client_flutter/lib/shared/providers/app_providers.dart`
- Modify: `client_flutter/test/features/files/file_transfer_service_test.dart`

- [ ] **Step 1: Add file transfer service policy tests**

In `client_flutter/test/features/files/file_transfer_service_test.dart`, add:

```dart
  test('upload rejects offline policy before creating a job or session',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-upload-offline-');
    final file = File('${tempDir.path}${Platform.pathSeparator}offline.txt');
    await file.writeAsString('offline');
    final api = FakeFileCloudApi();
    final service = _createService(
      db,
      api,
      policy: const OnlinePrimaryPolicy(
        serverReachable: false,
        authenticated: true,
        level: ServerConnectionLevel.offline,
      ),
    );
    addTearDown(service.dispose);

    await expectLater(
      service.uploadFile(file.path),
      throwsA(isA<OnlinePrimaryWriteRejected>()),
    );

    expect(service.jobs, isEmpty);
    expect(api.createdUploadSessions, isEmpty);
    expect(await _auditActions(db), isEmpty);
  });

  test('upload session creation failure leaves no local upload job',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir = await _createTempDir('flowplanv2-upload-no-session-');
    final file = File('${tempDir.path}${Platform.pathSeparator}denied.txt');
    await file.writeAsString('denied');
    final api = FakeFileCloudApi(failCreateUploadSession: true);
    final service = _createService(
      db,
      api,
      policy: const OnlinePrimaryPolicy(
        serverReachable: true,
        authenticated: true,
        level: ServerConnectionLevel.online,
      ),
    );
    addTearDown(service.dispose);

    await expectLater(service.uploadFile(file.path), throwsStateError);

    expect(service.jobs, isEmpty);
    expect(api.createdUploadSessions, hasLength(1));
    expect(await _auditActions(db), isEmpty);
  });
```

Update `_createService` helper:

```dart
FileTransferService _createService(
  AppDatabase db,
  FakeFileCloudApi api, {
  OnlinePrimaryPolicy policy = const OnlinePrimaryPolicy(
    serverReachable: true,
    authenticated: true,
    level: ServerConnectionLevel.online,
  ),
}) {
  return FileTransferService(
    apiLoader: () async => api,
    policyLoader: () async => policy,
    operationLogs: DataOperationLogRepository(db),
  );
}
```

Add imports:

```dart
import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/online/online_primary_policy.dart';
```

- [ ] **Step 2: Run failing file transfer tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/features/files/file_transfer_service_test.dart
```

Expected before implementation: offline upload inserts a job and session failure leaves a failed local job.

- [ ] **Step 3: Add policy loader to file transfer service**

Modify constructor in `client_flutter/lib/features/files/services/file_transfer_service.dart`:

```dart
import '../../../core/online/online_primary_policy.dart';
```

```dart
  FileTransferService({
    required Future<FileCloudApi> Function() apiLoader,
    required DataOperationLogRepository operationLogs,
    Future<OnlinePrimaryPolicy> Function()? policyLoader,
  })  : _apiLoader = apiLoader,
        _operationLogs = operationLogs,
        _policyLoader = policyLoader;
```

Add field:

```dart
  final Future<OnlinePrimaryPolicy> Function()? _policyLoader;
```

Add helper:

```dart
  Future<void> _requireOnlineUploadStart() async {
    final loader = _policyLoader;
    if (loader == null) {
      return;
    }
    final policy = await loader();
    policy.requireOnlineFileUploadStart('upload file');
  }
```

- [ ] **Step 4: Create server session before local upload job**

Replace the start of `uploadFile` with this sequence:

```dart
  Future<void> uploadFile(String path) async {
    await _requireOnlineUploadStart();
    await load();
    final file = File(path);
    if (!file.existsSync()) {
      throw StateError('File does not exist: $path');
    }
    final stat = await file.stat();
    final totalBytes = stat.size;
    final chunkSize = _chunkSizeFor(totalBytes);
    final expectedChunks =
        totalBytes <= 0 ? 0 : (totalBytes / chunkSize).ceil();
    final checksum = await _sha256File(path);
    final api = await _apiLoader();
    final sessionResult = await api.createUploadSession(
      fileName: _basename(path),
      totalBytes: totalBytes,
      chunkSize: chunkSize,
      checksum: checksum,
      localPath: path,
      metadata: <String, Object?>{
        'small_file_threshold_bytes':
            FileTransferConstants.smallFileThresholdBytes,
      },
    );
    final session = _asMap(sessionResult['uploadSession']);
    final sessionId = _readString(session['sessionId']);
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('Server did not return an upload session id.');
    }
    var job = FileTransferJob(
      id: _uuid.v4(),
      direction: FileTransferDirection.upload,
      fileName: _basename(path),
      localPath: path,
      totalBytes: totalBytes,
      chunkSize: chunkSize,
      expectedChunks: expectedChunks,
      transferredBytes: 0,
      status: FileTransferStatus.uploading,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      sessionId: sessionId,
      checksum: checksum,
    );
    _jobs.insert(0, job);
    await _save();
    notifyListeners();
    await _record('file_transfer.upload.start', job, 'Start file upload');
```

Keep the existing `_uploadMissingChunks(job)` try/catch after this point. Remove the old pre-session job insertion and hashing status.

- [ ] **Step 5: Wire policy provider into file transfer service**

Modify `fileTransferServiceProvider` in `client_flutter/lib/shared/providers/app_providers.dart`:

```dart
  final service = FileTransferService(
    apiLoader: () => ref.read(fileCloudApiProvider.future),
    policyLoader: () async => ref.read(onlinePrimaryPolicyProvider),
    operationLogs: ref.watch(dataOperationLogRepositoryProvider),
  );
```

Add `onlinePrimaryPolicyProvider` to dependencies.

- [ ] **Step 6: Run passing file transfer tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/features/files/file_transfer_service_test.dart
```

Expected after implementation: offline upload and create-session failure do not create local jobs; failures after a server session keep retryable failed jobs.

- [ ] **Step 7: Commit Task 7**

```powershell
git status --short
git add client_flutter/lib/features/files/services/file_transfer_service.dart client_flutter/lib/shared/providers/app_providers.dart client_flutter/test/features/files/file_transfer_service_test.dart
git commit -m "feat: require server session before file upload jobs"
```

---

### Task 8: Block File Picker Entry Points While Offline

**Files:**
- Modify: `client_flutter/lib/features/files/presentation/file_transfer_center_page.dart`
- Modify: `client_flutter/lib/features/files/presentation/file_context_page.dart`
- Modify: `client_flutter/lib/web_app/flowplanv2_web_app.dart`
- Modify: `client_flutter/test/widgets/user_workflow_file_transfer_test.dart`
- Modify: `client_flutter/test/widgets/files_gap9_worker_ui_test.dart`

- [ ] **Step 1: Add widget tests for the transfer center**

In `client_flutter/test/widgets/user_workflow_file_transfer_test.dart`, add these imports:

```dart
import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/online/online_primary_policy.dart';
```

Extend `FakeFilePicker` so picker calls can be asserted:

```dart
class FakeFilePicker extends FilePicker {
  FakeFilePicker(this.path);

  final String? path;
  final queuedSavePaths = <String?>[];
  final saveRequests = <Map<String, Object?>>[];
  int pickCalls = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    pickCalls++;
    if (path == null) {
      return null;
    }
    return FilePickerResult([
      PlatformFile(path: path, name: 'report.pdf', size: 1024),
    ]);
  }
}
```

Update `_pumpFileTransferCenter` to accept extra provider overrides:

```dart
Future<void> _pumpFileTransferCenter(
  WidgetTester tester, {
  required FakeFileTransferService service,
  List<Override> overrides = const [],
}) async {
  final previousFilePicker = FilePicker.platform;
  addTearDown(() {
    FilePicker.platform = previousFilePicker;
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fileTransferServiceProvider.overrideWith((ref) => service),
        ...overrides,
      ],
      child: const MaterialApp(
        home: FileTransferCenterPage(),
      ),
    ),
  );
  await tester.pump();
}
```

Add this test:

```dart
  testWidgets('file transfer upload blocks picker while offline read-only cache',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = FakeFileTransferService(db);
    final fakeFilePicker = FakeFilePicker('/virtual/report.pdf');
    FilePicker.platform = fakeFilePicker;

    await _pumpFileTransferCenter(
      tester,
      service: service,
      overrides: [
        onlinePrimaryPolicyProvider.overrideWith(
          (ref) => const OnlinePrimaryPolicy(
            serverReachable: false,
            authenticated: true,
            level: ServerConnectionLevel.offline,
          ),
        ),
      ],
    );

    await tester.tap(find.byKey(AppKeys.fileTransferStartButton));
    await tester.pump();

    expect(find.textContaining('Server connection is required'), findsOneWidget);
    expect(fakeFilePicker.pickCalls, 0);
    expect(service.uploadedPaths, isEmpty);
  });
```

- [ ] **Step 2: Run failing file widget tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/widgets/user_workflow_file_transfer_test.dart test/widgets/files_gap9_worker_ui_test.dart
```

Expected before implementation: upload button opens the picker even when policy is offline.

- [ ] **Step 3: Check policy before `FilePicker.platform.pickFiles`**

Modify `_pickAndUpload` in `file_transfer_center_page.dart`:

```dart
import '../../../core/online/online_primary_policy.dart';

  Future<void> _pickAndUpload(
    BuildContext context,
    WidgetRef ref,
    FileTransferService service,
  ) async {
    final policy = ref.read(onlinePrimaryPolicyProvider);
    try {
      policy.requireOnlineFileUploadStart('select file for upload');
    } on OnlinePrimaryWriteRejected catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.reason)),
      );
      return;
    }
    final result = await FilePicker.platform.pickFiles(withData: false);
```

Update the button:

```dart
onPressed: () => _pickAndUpload(context, ref, service),
```

- [ ] **Step 4: Check policy before upload-related file context actions**

In `file_context_page.dart`, guard `_registerStorageObject`:

```dart
    final policy = ref.read(onlinePrimaryPolicyProvider);
    policy.requireOnlineFileUploadStart('register file storage object');
```

Catch `OnlinePrimaryWriteRejected` at the action boundary and show `error.reason`.

- [ ] **Step 5: Check web server reachability before picker**

In `flowplanv2_web_app.dart`, add:

```dart
  Future<bool> _serverReachableForUpload() async {
    try {
      await widget.api.getJson('/client/bootstrap');
      return true;
    } catch (_) {
      setState(() {
        status = 'Server connection is required before upload.';
      });
      return false;
    }
  }
```

At the beginning of `_upload`, before `_createRoot()` and before `FilePicker.platform.pickFiles`, add:

```dart
    if (!await _serverReachableForUpload()) {
      return;
    }
```

- [ ] **Step 6: Run passing file widget tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/widgets/user_workflow_file_transfer_test.dart test/widgets/files_gap9_worker_ui_test.dart
```

Expected after implementation: offline state shows a server-required message and picker call count stays zero.

- [ ] **Step 7: Commit Task 8**

```powershell
git status --short
git add client_flutter/lib/features/files/presentation/file_transfer_center_page.dart client_flutter/lib/features/files/presentation/file_context_page.dart client_flutter/lib/web_app/flowplanv2_web_app.dart client_flutter/test/widgets/user_workflow_file_transfer_test.dart client_flutter/test/widgets/files_gap9_worker_ui_test.dart
git commit -m "feat: block offline file upload selection"
```

---

### Task 9: Add Offline Read-Only UI State For Business Writes

**Files:**
- Create: `client_flutter/lib/shared/widgets/offline_read_only_banner.dart`
- Create: `client_flutter/test/shared/widgets/offline_read_only_banner_test.dart`
- Modify: `client_flutter/lib/features/task/presentation/task_detail_page.dart`
- Modify: `client_flutter/lib/features/calendar/presentation/event_detail_page.dart`
- Modify: `client_flutter/lib/features/calendar/presentation/timeline_view.dart`
- Modify: `client_flutter/lib/features/data_management/presentation/data_management_page.dart`
- Modify: `client_flutter/test/widgets/user_workflow_task_detail_worker_j_test.dart`
- Modify: `client_flutter/test/widgets/calendar_event_detail_gap_worker_event_test.dart`
- Modify: `client_flutter/test/widgets/user_workflow_data_management_test.dart`
- Modify: `client_flutter/test/widgets/user_workflow_server_sync_test.dart`

- [ ] **Step 1: Write offline banner widget test**

Create `client_flutter/test/shared/widgets/offline_read_only_banner_test.dart`:

```dart
import 'package:flowplanv2/shared/widgets/offline_read_only_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders compact read-only cache state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: OfflineReadOnlyBanner(),
        ),
      ),
    );

    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.textContaining('Read-only cache'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run failing banner test**

Codex may run:

```powershell
cd client_flutter
flutter test test/shared/widgets/offline_read_only_banner_test.dart
```

Expected before implementation: missing widget file.

- [ ] **Step 3: Implement the banner**

Create `client_flutter/lib/shared/widgets/offline_read_only_banner.dart`:

```dart
import 'package:flutter/material.dart';

class OfflineReadOnlyBanner extends StatelessWidget {
  const OfflineReadOnlyBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(color: colors.outlineVariant),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.lock_outline, size: 18, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Read-only cache. Reconnect to save changes.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Disable task detail write controls in read-only cache mode**

In `task_detail_page.dart`, import:

```dart
import '../../../shared/widgets/offline_read_only_banner.dart';
```

Inside `build`, read:

```dart
final readOnlyCache = ref.watch(onlinePrimaryPolicyProvider).readOnlyCache;
```

Show the banner near the top of the page body:

```dart
if (readOnlyCache) const OfflineReadOnlyBanner(),
```

Disable save/delete buttons:

```dart
onPressed: _saving || readOnlyCache ? null : _save,
```

and:

```dart
onPressed: _saving || readOnlyCache ? null : _delete,
```

- [ ] **Step 5: Disable event detail, timeline, and data management writes**

In `event_detail_page.dart`, add the same import, read:

```dart
final readOnlyCache = ref.watch(onlinePrimaryPolicyProvider).readOnlyCache;
```

Show:

```dart
if (readOnlyCache) const OfflineReadOnlyBanner(),
```

Disable save and delete:

```dart
onPressed: _saving || readOnlyCache ? null : _save,
onPressed: _saving || readOnlyCache ? null : _delete,
```

In `timeline_view.dart`, set write callbacks to `null` when read-only:

```dart
final readOnlyCache = ref.watch(onlinePrimaryPolicyProvider).readOnlyCache;
```

Then:

```dart
isDraggable: !readOnlyCache && event.source != 'outlook',
```

Move the existing event `onDragEnd` async body into the non-null branch used when `readOnlyCache == false && event.source != 'outlook'`. Move the existing event `onResizeEnd` async body into the non-null branch used when `readOnlyCache == false && event.source != 'outlook'`.

For task blocks in `timeline_view.dart`, set:

```dart
isDraggable: !readOnlyCache,
```

Move the existing task `onDragEnd` async body into the non-null branch used when `readOnlyCache == false`. Move the existing task `onResizeEnd` async body into the non-null branch used when `readOnlyCache == false`.

In `data_management_page.dart`, read `onlinePrimaryPolicyProvider` in `build`, store `readOnlyCache`, and disable these action callbacks when `readOnlyCache == true`:

```dart
onPressed: _working || readOnlyCache ? null : _deleteSelected,
onPressed: _working || readOnlyCache ? null : _completeSelectedTasks,
```

- [ ] **Step 6: Update pending-success messages**

In task and event detail pages, remove branches that show:

```dart
result.isPending
```

Use canonical success text only:

```dart
content: Text('Saved on server.'),
```

The catch branch remains the only failed write message and must not close the page.

- [ ] **Step 7: Run focused widget tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/shared/widgets/offline_read_only_banner_test.dart test/widgets/user_workflow_task_detail_worker_j_test.dart test/widgets/calendar_event_detail_gap_worker_event_test.dart test/widgets/user_workflow_data_management_test.dart
```

Expected after implementation: read-only controls are disabled and failed writes keep the editor open.

- [ ] **Step 8: Commit Task 9**

```powershell
git status --short
git add client_flutter/lib/shared/widgets/offline_read_only_banner.dart client_flutter/test/shared/widgets/offline_read_only_banner_test.dart client_flutter/lib/features/task/presentation/task_detail_page.dart client_flutter/lib/features/calendar/presentation/event_detail_page.dart client_flutter/lib/features/calendar/presentation/timeline_view.dart client_flutter/lib/features/data_management/presentation/data_management_page.dart client_flutter/test/widgets/user_workflow_task_detail_worker_j_test.dart client_flutter/test/widgets/calendar_event_detail_gap_worker_event_test.dart client_flutter/test/widgets/user_workflow_data_management_test.dart
git commit -m "feat: show offline read-only cache state"
```

---

### Task 10: Add Legacy Offline Mutation Review And Cleanup

**Files:**
- Create: `client_flutter/lib/core/offline_queue/legacy_offline_mutation_cleanup_service.dart`
- Create: `client_flutter/test/core/offline_queue/legacy_offline_mutation_cleanup_service_test.dart`
- Modify: `client_flutter/lib/features/sync/server_sync_status_page.dart`
- Modify: `client_flutter/test/widgets/server_sync_status_page_gap_worker_sync_test.dart`
- Modify: `client_flutter/lib/shared/providers/app_providers.dart`

- [ ] **Step 1: Write cleanup service tests**

Create `client_flutter/test/core/offline_queue/legacy_offline_mutation_cleanup_service_test.dart`:

```dart
import 'dart:convert';

import 'package:flowplanv2/core/offline_queue/legacy_offline_mutation_cleanup_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('summarizes and exports legacy offline mutations', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await db.customStatement(
      '''
      INSERT INTO offline_mutations (
        mutation_uid, object_type, local_id, action, payload_json, created_at, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        'legacy-1',
        'task_item',
        'local-1',
        'create',
        '{"summary":"Legacy"}',
        DateTime.utc(2026, 6, 12).toIso8601String(),
        'pending',
      ],
    );
    final service = LegacyOfflineMutationCleanupService(db);

    final summary = await service.summary();
    final exported = await service.exportJson();

    expect(summary.totalCount, 1);
    expect(summary.pendingCount, 1);
    expect(jsonDecode(exported), isA<List<dynamic>>());
    expect(exported, contains('legacy-1'));
  });

  test('marks pending mutations as failed without deleting evidence', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await db.customStatement(
      '''
      INSERT INTO offline_mutations (
        mutation_uid, object_type, local_id, action, payload_json, created_at, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        'legacy-2',
        'calendar_event',
        'local-2',
        'update',
        '{}',
        DateTime.utc(2026, 6, 12).toIso8601String(),
        'pending',
      ],
    );
    final service = LegacyOfflineMutationCleanupService(db);

    final count = await service.markPendingAsLegacyFailed();

    expect(count, 1);
    final rows = await db.customSelect(
      'SELECT status, last_error FROM offline_mutations',
    ).get();
    expect(rows.single.read<String>('status'), 'failed');
    expect(rows.single.read<String>('last_error'), contains('online-primary'));
  });
}
```

- [ ] **Step 2: Run failing cleanup tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/core/offline_queue/legacy_offline_mutation_cleanup_service_test.dart
```

Expected before implementation: missing service file.

- [ ] **Step 3: Implement cleanup service**

Create `client_flutter/lib/core/offline_queue/legacy_offline_mutation_cleanup_service.dart`:

```dart
import 'dart:convert';

import '../database/app_database.dart';

class LegacyOfflineMutationSummary {
  const LegacyOfflineMutationSummary({
    required this.totalCount,
    required this.pendingCount,
    required this.failedCount,
    required this.conflictCount,
  });

  final int totalCount;
  final int pendingCount;
  final int failedCount;
  final int conflictCount;
}

class LegacyOfflineMutationCleanupService {
  const LegacyOfflineMutationCleanupService(this._database);

  final AppDatabase _database;

  Future<LegacyOfflineMutationSummary> summary() async {
    final row = await _database.customSelect(
      '''
      SELECT
        COUNT(*) AS total_count,
        COALESCE(SUM(CASE WHEN status IN ('pending', 'sending') THEN 1 ELSE 0 END), 0) AS pending_count,
        COALESCE(SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END), 0) AS failed_count,
        COALESCE(SUM(CASE WHEN status = 'conflict' THEN 1 ELSE 0 END), 0) AS conflict_count
      FROM offline_mutations
      ''',
    ).getSingle();
    return LegacyOfflineMutationSummary(
      totalCount: row.read<int>('total_count'),
      pendingCount: row.read<int>('pending_count'),
      failedCount: row.read<int>('failed_count'),
      conflictCount: row.read<int>('conflict_count'),
    );
  }

  Future<String> exportJson() async {
    final rows = await _database.customSelect(
      'SELECT * FROM offline_mutations ORDER BY id ASC',
    ).get();
    return const JsonEncoder.withIndent('  ').convert(
      rows.map((row) => row.data).toList(growable: false),
    );
  }

  Future<int> markPendingAsLegacyFailed() async {
    final before = await summary();
    await _database.customStatement(
      '''
      UPDATE offline_mutations
      SET status = 'failed',
          last_error = 'Legacy offline mutation retained after online-primary migration.',
          attempts = attempts + 1
      WHERE status IN ('pending', 'sending')
      ''',
    );
    final after = await summary();
    return before.pendingCount - after.pendingCount;
  }
}
```

- [ ] **Step 4: Wire provider**

Add to `app_providers.dart`:

```dart
final legacyOfflineMutationCleanupServiceProvider =
    Provider<LegacyOfflineMutationCleanupService>((ref) {
  return LegacyOfflineMutationCleanupService(ref.watch(databaseProvider));
}, dependencies: [databaseProvider]);
```

- [ ] **Step 5: Surface cleanup actions in sync status page**

In `server_sync_status_page.dart`, add a legacy queue panel that:

```dart
final cleanup = ref.watch(legacyOfflineMutationCleanupServiceProvider);
```

Displays:

```dart
FutureBuilder(
  future: cleanup.summary(),
  builder: (context, snapshot) {
    final summary = snapshot.data;
    return ListTile(
      leading: const Icon(Icons.inventory_2_outlined),
      title: const Text('Legacy offline queue'),
      subtitle: Text(
        summary == null
            ? 'Loading'
            : 'Total ${summary.totalCount}, pending ${summary.pendingCount}, failed ${summary.failedCount}, conflicts ${summary.conflictCount}',
      ),
      trailing: FilledButton.tonalIcon(
        onPressed: summary == null || summary.pendingCount == 0
            ? null
            : () async {
                await cleanup.markPendingAsLegacyFailed();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Legacy pending rows marked failed.'),
                    ),
                  );
                }
              },
        icon: const Icon(Icons.block_outlined),
        label: const Text('Stop replay'),
      ),
    );
  },
)
```

- [ ] **Step 6: Run focused cleanup tests**

Codex may run:

```powershell
cd client_flutter
flutter test test/core/offline_queue/legacy_offline_mutation_cleanup_service_test.dart test/widgets/server_sync_status_page_gap_worker_sync_test.dart
```

Expected after implementation: cleanup service and sync status UI tests pass.

- [ ] **Step 7: Commit Task 10**

```powershell
git status --short
git add client_flutter/lib/core/offline_queue/legacy_offline_mutation_cleanup_service.dart client_flutter/test/core/offline_queue/legacy_offline_mutation_cleanup_service_test.dart client_flutter/lib/features/sync/server_sync_status_page.dart client_flutter/test/widgets/server_sync_status_page_gap_worker_sync_test.dart client_flutter/lib/shared/providers/app_providers.dart
git commit -m "feat: add legacy offline queue cleanup path"
```

---

### Task 11: Lock Server Canonical Boundaries With Unit Tests

**Files:**
- Modify: `server/src/files/files.service.unit.spec.ts`
- Modify: `server/src/tracking/tracking.service.unit.spec.ts`
- Modify: `server/src/web/web.service.unit.spec.ts`

- [ ] **Step 1: Add file canonical boundary test**

In `server/src/files/files.service.unit.spec.ts`, add:

```ts
  it('does not create a storage object until upload completion', async () => {
    const database = createDatabase();
    const { service } = createService(database);

    await service.createUploadSession(
      {
        providerKey: 'server_storage',
        fileName: 'report.txt',
        totalBytes: 10,
        chunkSize: 5,
        objectKey: 'object-before-complete',
      },
      context,
    );

    const sessionCalls = database.query.mock.calls.filter(([sql]) =>
      String(sql).includes('INSERT INTO file_transfer_sessions'),
    );
    const storageCalls = database.query.mock.calls.filter(([sql]) =>
      String(sql).includes('INSERT INTO file_storage_objects'),
    );
    expect(sessionCalls).toHaveLength(1);
    expect(storageCalls).toHaveLength(0);
  });
```

- [ ] **Step 2: Add file completion creates canonical storage test**

Use existing `session` fixture and object storage fake:

```ts
  it('creates a storage object when upload completion succeeds', async () => {
    const database = createDatabase({
      sessions: [{ ...session, received_chunks: 3, expected_chunks: 3 }],
      payloadChunks: [
        { payload: Buffer.from('abc') },
      ],
    });
    const { service, objectStorage } = createService(database);

    await service.completeUploadSession('session-1', context);

    expect(objectStorage.writeObjectFromChunks).toHaveBeenCalledOnce();
    expect(database.query.mock.calls.some(([sql]) =>
      String(sql).includes('INSERT INTO file_storage_objects'),
    )).toBe(true);
  });
```

- [ ] **Step 3: Add tracking rejected sample local id assertion**

In `server/src/tracking/tracking.service.unit.spec.ts`, change the `invalidRecords` factory in `normalizes direct records with deduplication, rejections, and sample caps` to include `localId`:

```ts
    const invalidRecords = Array.from({ length: 11 }, (_, index) => ({
      localId: `local-invalid-${index}`,
      objectType: 'unsupported',
      index,
    }));
```

Extend the direct rejection expectation with:

```ts
    expect(result.rejectedSamples[0]).toMatchObject({
      localId: 'local-invalid-0',
      objectType: 'unsupported',
      index: 0,
    });
```

Add an accepted sample assertion:

```ts
    expect(result.accepted).toBe(1);
    expect(result.rejected).toBe(11);
```

- [ ] **Step 4: Add stale version write assertion**

In `server/src/web/web.service.unit.spec.ts`, extend `throws a ConflictException when baseServerVersion is stale` with this assertion:

```ts
    expect(
      transactionClient.query.mock.calls.some(([sql]) =>
        String(sql).includes('server_version = server_version + 1'),
      ),
    ).toBe(false);
```

The final test body should include:

```ts
await expect(
  service.updateTask('task-1', { title: 'Stale', baseServerVersion: '8' }, context),
).rejects.toBeInstanceOf(ConflictException);
expect(transactionClient.query).toHaveBeenCalledTimes(1);
expect(
  transactionClient.query.mock.calls.some(([sql]) =>
    String(sql).includes('server_version = server_version + 1'),
  ),
).toBe(false);
```

- [ ] **Step 5: Run server unit tests**

Codex may run this command:

```powershell
cd server
npm run test:unit -- src/files/files.service.unit.spec.ts src/tracking/tracking.service.unit.spec.ts src/web/web.service.unit.spec.ts
```

Expected after implementation: Vitest reports passing tests for those files.

- [ ] **Step 6: Commit Task 11**

```powershell
git status --short
git add server/src/files/files.service.unit.spec.ts server/src/tracking/tracking.service.unit.spec.ts server/src/web/web.service.unit.spec.ts
git commit -m "test: lock online-primary server boundaries"
```

---

### Task 12: Update Architecture And QA Documentation

**Files:**
- Create: `docs/architecture/online-primary-read-only-cache.md`
- Create: `docs/qa/online-primary-read-only-cache-test-matrix.md`
- Modify: `docs/superpowers/specs/2026-06-12-online-primary-read-only-cache-design.md`

- [ ] **Step 1: Create architecture note**

Create `docs/architecture/online-primary-read-only-cache.md`:

```markdown
# Online-Primary Read-Only Cache

## Runtime Rule

The server is the only acceptance point for business facts. Native clients may
read cached Drift data offline, but ordinary writes are disabled or rejected
when the server is not reachable.

## Ordinary Business Data

Task, event, report, scheduler, settings, AI, activity understanding, file
metadata, and file context writes must use server APIs. A failed server write
does not update the local business cache and does not create an offline
mutation.

## Tracking

Tracking collection may write local spool rows while offline. Upload runs in
batches and deletes only records confirmed by a successful server completion.
Rejected records with known local ids are retained in
`tracking_upload_quarantine`.

## Files

File upload entry points require a server connection before file selection.
The client creates a server upload session before it creates a local transfer
job. Failed uploads after session creation may remain retryable. Downloaded
files are local cache copies.

## Legacy Offline Queue

Existing `offline_mutations` rows are legacy migration evidence. Startup and
periodic cache refresh do not replay them automatically. The sync status page
surfaces counts and offers a stop-replay cleanup action.
```

- [ ] **Step 2: Create QA matrix**

Create `docs/qa/online-primary-read-only-cache-test-matrix.md`:

```markdown
# Online-Primary Read-Only Cache QA Matrix

| Area | Required Evidence | Automated Test | Manual Command |
| --- | --- | --- | --- |
| Task/event offline failure | No local cache change and no `offline_mutations` row | `client_flutter/test/core/server_first/task_event_server_first_store_test.dart` | `flutter test test/core/server_first/task_event_server_first_store_test.dart` |
| App provider wiring | Server-managed repositories do not receive the legacy recorder | `client_flutter/test/shared/providers/online_primary_provider_wiring_test.dart` | `flutter test test/shared/providers/online_primary_provider_wiring_test.dart` |
| Cache refresh | Startup and periodic sync pull only and do not push legacy rows | `client_flutter/test/core/bootstrap/client_bootstrap_service_test.dart` | `flutter test test/core/bootstrap/client_bootstrap_service_test.dart` |
| Tracking success | Confirmed rows are deleted locally | `client_flutter/test/features/tracker/tracking_upload_service_test.dart` | `flutter test test/features/tracker/tracking_upload_service_test.dart` |
| Tracking failure | Failed or unconfirmed rows remain local | `client_flutter/test/features/tracker/tracking_upload_service_test.dart` | `flutter test test/features/tracker/tracking_upload_service_test.dart` |
| Tracking cadence | Auto upload interval is 60 seconds | `client_flutter/test/features/tracker/tracker_service_additional_test.dart` | `flutter test test/features/tracker/tracker_service_additional_test.dart` |
| File offline start | File picker is not opened offline | `client_flutter/test/widgets/user_workflow_file_transfer_test.dart` | `flutter test test/widgets/user_workflow_file_transfer_test.dart` |
| File session boundary | Local upload job is created only after server session | `client_flutter/test/features/files/file_transfer_service_test.dart` | `flutter test test/features/files/file_transfer_service_test.dart` |
| Server file canonicality | Storage object exists only after upload completion | `server/src/files/files.service.unit.spec.ts` | `npm run test:unit -- src/files/files.service.unit.spec.ts` |
| Legacy queue cleanup | Existing queue rows are inspectable and not replayed automatically | `client_flutter/test/core/offline_queue/legacy_offline_mutation_cleanup_service_test.dart` | `flutter test test/core/offline_queue/legacy_offline_mutation_cleanup_service_test.dart` |
| Governance feature matrix | Online-primary rows exist for client policy, task/event writes, tracking, files, legacy queue, and cross-end behavior | `docs/test-governance/feature-test-matrix.csv` | `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -GovernanceOnly` |
| Manual acceptance matrix | Real offline cache, tracking cleanup, and file interruption rows exist and stay pending until dated evidence is recorded | `docs/test-governance/manual-acceptance.csv` | `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -GovernanceOnly` |
| Root quality gate | Governance, server, web, Flutter coverage, golden, and Windows integration gates are recorded | `scripts/test-flowplanv2.ps1` | `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800` |
```

- [ ] **Step 3: Mark implementation note in approved spec**

Append to `docs/superpowers/specs/2026-06-12-online-primary-read-only-cache-design.md`:

```markdown
## 18. Implementation Plan

Implementation tasks are tracked in
`docs/superpowers/plans/2026-06-12-online-primary-read-only-cache-implementation.md`.
```

- [ ] **Step 4: Commit Task 12**

```powershell
git status --short
git add docs/architecture/online-primary-read-only-cache.md docs/qa/online-primary-read-only-cache-test-matrix.md docs/superpowers/specs/2026-06-12-online-primary-read-only-cache-design.md
git commit -m "docs: document online-primary implementation evidence"
```

---

### Task 13: Add Full Test Governance Evidence

**Files:**
- Modify: `docs/test-governance/feature-test-matrix.csv`
- Modify: `docs/test-governance/manual-acceptance.csv`
- Modify: `docs/test-governance/cross-end-workflow-matrix.md`
- Create: `docs/test-governance/reports/online-primary-read-only-cache-closeout.md`

- [ ] **Step 1: Add feature-test matrix rows**

Append these rows to `docs/test-governance/feature-test-matrix.csv`:

```csv
CLIENT-ONLINE-PRIMARY-001,client_flutter,core online policy,Online-primary read-only cache policy,onlinePrimaryPolicyProvider and OnlinePrimaryPolicy,client_flutter/test/core/online/online_primary_policy_test.dart proves online states allow business writes and offline degraded local-cache auth-required states reject business writes,client_flutter/test/core/online/online_primary_policy_test.dart proves file upload start is rejected while tracking spool and device-local writes remain allowed offline,policy result controls ordinary write boundaries without mutating Drift or offline_mutations,not applicable,client_flutter/test/core/online/online_primary_policy_test.dart,,implemented,online-primary policy evidence added by 2026-06-12 implementation plan
CLIENT-ONLINE-PRIMARY-002,client_flutter,task and event server-first store,Task and event writes reject offline server failures,task and event create update delete controls,client_flutter/test/core/server_first/task_event_server_first_store_test.dart verifies successful server writes update local cache from canonical payload,client_flutter/test/core/server_first/task_event_server_first_store_test.dart verifies server failures and cache-only rows do not create local pending writes or offline_mutations,local Drift rows change only after canonical server success and offline_mutations stays unchanged,read-only UI controls are covered through task and calendar widget tests,client_flutter/test/core/server_first/task_event_server_first_store_test.dart,MANUAL-ONLINE-PRIMARY-001,partial,automated store and widget evidence is required; real disconnected Windows cache read-only acceptance remains pending-user until dated evidence is recorded
CLIENT-ONLINE-PRIMARY-003,client_flutter,bootstrap sync and legacy queue,Pull-only cache refresh and legacy offline queue cleanup,bootstrap refresh timer sync status cleanup action,client_flutter/test/core/bootstrap/client_bootstrap_service_test.dart and client_flutter/test/core/sync/sync_engine_test.dart verify startup and periodic refresh pull without pushPending,client_flutter/test/core/offline_queue/legacy_offline_mutation_cleanup_service_test.dart verifies pending legacy rows are retained inspectable and marked failed without deletion,legacy offline_mutations rows are not replayed automatically and cleanup preserves evidence,server sync status widget exposes the cleanup path with visible counts,client_flutter/test/core/offline_queue/legacy_offline_mutation_cleanup_service_test.dart,MANUAL-ONLINE-PRIMARY-001,partial,automated cleanup evidence is required; real user review of legacy queue on a migrated profile remains pending-user
CLIENT-TRACK-ONLINE-001,client_flutter,tracking upload spool,Tracking uploads batch every minute and delete only confirmed local rows,tracking auto upload timer and uploadPending,client_flutter/test/features/tracker/tracking_upload_service_test.dart verifies confirmed rows are deleted and rejected rows are quarantined,client_flutter/test/features/tracker/tracking_upload_service_test.dart verifies failed or unconfirmed rows remain retryable and tracker_service_additional_test verifies 60 second cadence,source row deletion happens only after server completeBatch confirms matching local ids; rejected ids are retained in tracking_upload_quarantine,tracker diagnostics expose pending and quarantine counts,client_flutter/test/features/tracker/tracking_upload_service_test.dart,MANUAL-TRACK-ONLINE-001,partial,automated tracking upload evidence is required; real minute-batched upload and cleanup acceptance remains pending-user
CLIENT-FILE-ONLINE-001,client_flutter,file transfer center and service,Server-hosted file upload starts only online and only after server session,fileTransferStartButton and FileTransferService.uploadFile,client_flutter/test/features/files/file_transfer_service_test.dart verifies server session is created before local upload job,client_flutter/test/widgets/user_workflow_file_transfer_test.dart verifies offline policy blocks picker and service tests verify create-session failure leaves no local job,local upload jobs exist only after server uploadSessionId is returned; failed post-session uploads remain retryable,file transfer start button uses AppKeys.fileTransferStartButton and offline message is visible,client_flutter/test/features/files/file_transfer_service_test.dart,MANUAL-FILE-ONLINE-001,partial,automated service and widget evidence is required; real interrupted upload resume and hash verification remains pending-user
SERVER-ONLINE-PRIMARY-001,server,server canonical boundaries,Server accepts canonical facts only at completion and rejects stale versions,file upload completion tracking completeBatch web task update,server/src/files/files.service.unit.spec.ts verifies upload session creation does not create storage object and completion does; server/src/tracking/tracking.service.unit.spec.ts verifies accepted rejected and localId samples; server/src/web/web.service.unit.spec.ts verifies stale baseServerVersion conflict,server unit specs verify incomplete upload sessions missing tracking records and stale writes do not mutate canonical rows,storage objects sync objects accepted counts rejected samples and server versions are asserted,not applicable,server/src/files/files.service.unit.spec.ts,,implemented,server canonical boundary evidence is automated and does not require manual acceptance
CE-ONLINE-PRIMARY-001,cross_end,online-primary cache workflow,Read cached data offline while ordinary writes are blocked and tracking/file exceptions behave by policy,Windows client offline cache task event tracker and file controls,client_flutter integration and widget tests cover mocked offline cache write rejection tracking exception and file picker block,real offline reconnect workflow must verify cached data remains readable ordinary writes are disabled tracking failed rows remain retryable and file upload picker stays closed,offline_mutations remains unchanged for ordinary writes while tracking spool behavior is observable,stable task event file and sync selectors are used in widget and integration tests,client_flutter/integration_test/sync_offline_flow_test.dart,MANUAL-ONLINE-PRIMARY-001,partial,cross-end online-primary workflow remains partial until real disconnected Windows acceptance is recorded
```

- [ ] **Step 2: Add manual acceptance rows**

Append these rows to `docs/test-governance/manual-acceptance.csv`:

```csv
MANUAL-ONLINE-PRIMARY-001,client_flutter,Online-primary offline read-only cache,Windows desktop client with local server and test database; network or server can be stopped and restarted,"task save button; event save button; timeline drag or resize; data-management batch action; server sync status navigation","online cached offline-read-only rejected-write reconnected refreshed states","server unavailable; auth required; stale cached row; attempted duplicate write","no ordinary offline_mutations row; no local business cache mutation after rejected write; pull refresh updates cache after reconnect","Start local server and Windows client; create or seed one task and one event while online; wait for cache; stop server or block connection; reopen task and event details and confirm cached values are readable; attempt task save event save timeline drag and data-management batch action; verify visible read-only message and no local business mutation or offline_mutations row; restart server; refresh and verify server facts remain canonical","dated screenshots or screen recording; server stop/start notes; offline_mutations query result; task/event row before-after ids; reconnect refresh evidence",pending-user
MANUAL-TRACK-ONLINE-001,client_flutter,Tracking minute batch upload cleanup,Windows desktop or Android device with local server for at least 5 minutes of tracking data,"start tracking button; stop tracking button; upload now action if available; tracker diagnostics navigation","tracking active local-spool pending-upload uploaded confirmed-deleted failed-retained states","server unavailable during upload; partial rejected batch; retry after reconnect","confirmed source rows deleted locally; failed or rejected rows retained or quarantined; server batch id and accepted/rejected counts recorded","Start tracking; generate at least 5 minutes of input or activity records; disconnect server for one upload interval and verify local rows remain; reconnect and wait at least 60 seconds; verify server batch accepted records; verify confirmed local source rows are deleted and rejected rows remain in quarantine; record diagnostics counts before and after","dated diagnostics screenshots; server batch id; accepted/rejected counts; local source row counts before-after; quarantine query result",pending-user
MANUAL-FILE-ONLINE-001,client_flutter,Online server-hosted file upload and interruption recovery,Windows filesystem with local server and a 10MB disposable file,"fileTransferStartButton; file picker; upload progress; interrupt action; resume button; download button","offline-blocked session-created uploading interrupted resumed completed downloaded verified states","offline before picker; create upload session failure; missing chunk; hash mismatch","no local upload job before server session; retryable job only after session; storage object created only after completion; downloaded hash matches source","Stop server and click upload; verify picker does not open; restart server; select 10MB file; capture server upload session id and local job id; interrupt during upload after session creation; resume upload; download completed file; compare hash; verify storage object exists only after completion","dated screenshots; source and downloaded hashes; upload session id; local job id; storage object id; interruption method and resume notes",pending-user
```

- [ ] **Step 3: Add cross-end workflow rows**

Append these rows to the table in `docs/test-governance/cross-end-workflow-matrix.md`:

```markdown
| Online-primary offline cache | CLIENT-ONLINE-PRIMARY-001, CLIENT-ONLINE-PRIMARY-002, CLIENT-ONLINE-PRIMARY-003, CE-ONLINE-PRIMARY-001 | Flutter policy, server-first store, bootstrap, sync engine, and legacy queue tests with deterministic fake connection states | Real Windows disconnected cache read-only workflow, reconnect pull refresh, and no ordinary offline mutation |
| Tracking minute batch cleanup | CLIENT-TRACK-ONLINE-001, SERVER-ONLINE-PRIMARY-001 | Flutter tracking upload service tests and server tracking completeBatch unit tests | Real 5-minute tracking run with one failed upload interval, reconnect, confirmed local deletion, and rejected-row quarantine evidence |
| Server-hosted file upload boundary | CLIENT-FILE-ONLINE-001, SERVER-ONLINE-PRIMARY-001, CE-FILE-001 | Flutter file transfer service/widget tests and server file completion unit tests | Real offline-before-picker block, interrupted post-session upload, resume, download, and hash verification |
```

- [ ] **Step 4: Create closeout report template**

Create `docs/test-governance/reports/online-primary-read-only-cache-closeout.md`:

```markdown
# Online-Primary Read-Only Cache Closeout

Date:
Executor:
Branch:
Commit range:

## Scope

- Online-primary read-only cache policy.
- Ordinary task/event/business writes require server success.
- Startup and periodic cache refresh are pull-only.
- Tracking uploads every 60 seconds, deletes confirmed rows, and retains failed or rejected rows.
- File uploads require online server session before local upload jobs.
- Legacy `offline_mutations` rows remain inspectable and are not replayed automatically.

## Automated Evidence

| Gate | Command | Result | Evidence |
| --- | --- | --- | --- |
| Governance-only | `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -GovernanceOnly` | pending | |
| Server focused | `npm run test:unit -- src/files/files.service.unit.spec.ts src/tracking/tracking.service.unit.spec.ts src/web/web.service.unit.spec.ts` | pending | |
| Flutter focused | focused Flutter command from implementation plan | pending | |
| Root full gate | `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800` | pending | |
| Completion gate | `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800` | pending | |

## Coverage Artifacts

- Server coverage:
- Web admin coverage:
- Flutter LCOV:
- Golden reports:
- Windows integration evidence:

## Matrix Updates

- `docs/test-governance/feature-test-matrix.csv`: rows added or updated:
- `docs/test-governance/manual-acceptance.csv`: rows added or updated:
- `docs/test-governance/cross-end-workflow-matrix.md`: rows added or updated:
- `docs/test-governance/coverage-exclusions.csv`: rows added or updated:

## Manual Acceptance

| Manual ID | Status | Evidence |
| --- | --- | --- |
| MANUAL-ONLINE-PRIMARY-001 | pending-user | |
| MANUAL-TRACK-ONLINE-001 | pending-user | |
| MANUAL-FILE-ONLINE-001 | pending-user | |

## Open Risks

- Completion cannot be claimed while linked manual rows are `pending-user`.
- Completion cannot be claimed while any coverage exclusion row is not `reviewed`.
- Completion cannot be claimed while root gate or Flutter/Dart command evidence is missing.
```

- [ ] **Step 5: Run governance-only validation**

Codex may run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -GovernanceOnly
```

Expected: governance matrix validation passes and the focused/skipped scan reports no committed focused or skipped tests.

- [ ] **Step 6: Commit Task 13**

```powershell
git status --short
git add docs/test-governance/feature-test-matrix.csv docs/test-governance/manual-acceptance.csv docs/test-governance/cross-end-workflow-matrix.md docs/test-governance/reports/online-primary-read-only-cache-closeout.md
git commit -m "test: register online-primary governance evidence"
```

---

### Task 14: Final Verification

**Files:**
- Modify: `docs/test-governance/reports/online-primary-read-only-cache-closeout.md`
- Read only verification across changed files.

- [ ] **Step 1: Run server verification**

Codex may run:

```powershell
cd server
npm run test:unit -- src/files/files.service.unit.spec.ts src/tracking/tracking.service.unit.spec.ts src/web/web.service.unit.spec.ts
```

Expected: Vitest reports all selected unit tests passing.

- [ ] **Step 2: Run governance-only verification**

Codex may run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -GovernanceOnly
```

Expected: feature-test, manual-acceptance, coverage-exclusions, actual gate exclusions, and focused/skipped scan checks pass.

- [ ] **Step 3: Run Flutter focused verification**

Codex may run:

```powershell
cd client_flutter
flutter test test/core/online/online_primary_policy_test.dart test/core/server_first/server_first_repository_test.dart test/core/server_first/task_event_server_first_store_test.dart test/core/bootstrap/client_bootstrap_service_test.dart test/core/connection/server_connection_service_test.dart test/features/tracker/tracking_upload_service_test.dart test/features/tracker/tracker_service_additional_test.dart test/features/files/file_transfer_service_test.dart test/shared/providers/online_primary_provider_wiring_test.dart test/shared/widgets/offline_read_only_banner_test.dart test/core/offline_queue/legacy_offline_mutation_cleanup_service_test.dart
```

Expected: all focused Flutter tests pass.

- [ ] **Step 4: Run full Flutter gate evidence**

Codex may run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800
```

Expected: root gate records governance validation, boundary checks, server, web admin, Flutter coverage, golden tests, and Windows integration evidence. If Flutter or Dart commands fail, copy the failing gate name and log path into `docs/test-governance/reports/online-primary-read-only-cache-closeout.md`.

- [ ] **Step 5: Run completion gate**

Codex may run:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800
```

Expected: completion gate passes only when every linked governance row is complete. If it fails because `MANUAL-ONLINE-PRIMARY-001`, `MANUAL-TRACK-ONLINE-001`, or `MANUAL-FILE-ONLINE-001` remains `pending-user`, keep the feature rows `partial` and record the blocker in the closeout report. Do not mark the implementation complete.

- [ ] **Step 6: Search for forbidden ordinary queue creation calls**

Codex may run:

```powershell
rg -n "queueLegacyCacheMutation|enqueueBusinessMutation|recordCreate\\(|recordUpdate\\(|recordDelete\\(" client_flutter/lib
```

Expected:

- `queueLegacyCacheMutation` only appears in the explicit legacy method and tests.
- `enqueueBusinessMutation` only appears in migration/legacy plumbing.
- `SyncWriteRecorder` calls are not reached through normal app providers for server-managed repositories.

- [ ] **Step 7: Search for old pending-success copy**

Codex may run:

```powershell
rg -n "等待同步|待同步|isPending|Saved to this device|pending local" client_flutter/lib
```

Expected:

- No task/event UI success message tells the user that an ordinary write was saved locally for replay.
- Remaining matches are legacy diagnostics or queue cleanup labels.

- [ ] **Step 8: Update closeout report with final evidence**

Modify `docs/test-governance/reports/online-primary-read-only-cache-closeout.md` so each table row has a dated result:

```markdown
| Governance-only | `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -GovernanceOnly` | PASS | 2026-06-13: console transcript or generated report path |
| Server focused | `npm run test:unit -- src/files/files.service.unit.spec.ts src/tracking/tracking.service.unit.spec.ts src/web/web.service.unit.spec.ts` | PASS | 2026-06-13: Vitest output |
| Flutter focused | focused Flutter command from implementation plan | PASS | 2026-06-13: console transcript or log path |
| Root full gate | `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800` | PASS | 2026-06-13: generated root report path |
| Completion gate | `powershell -ExecutionPolicy Bypass -File scripts\test-flowplanv2.ps1 -Completion -FlutterIntegrationDevice windows -GateTimeoutSeconds 1800` | PASS or BLOCKED | 2026-06-13: generated root report path or manual acceptance blocker |
```

If completion is blocked by manual rows, record:

```markdown
## Open Manual Acceptance

- `MANUAL-ONLINE-PRIMARY-001`: pending-user, real disconnected Windows cache workflow not yet executed.
- `MANUAL-TRACK-ONLINE-001`: pending-user, real tracking minute-batch cleanup not yet executed.
- `MANUAL-FILE-ONLINE-001`: pending-user, real file interruption and hash verification not yet executed.
```

- [ ] **Step 9: Confirm no unreviewed changes**

Codex may run:

```powershell
git status --short
git log --oneline -5
```

Expected: worktree is clean after commits, and recent commits include the task commits from this plan.

- [ ] **Step 10: Commit final verification evidence**

```powershell
git status --short
git add docs/test-governance/reports/online-primary-read-only-cache-closeout.md
git commit -m "test: record online-primary verification evidence"
```
