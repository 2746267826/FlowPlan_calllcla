import 'dart:async';
import 'dart:convert';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_runner.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/sync/conflict_snapshot.dart';
import 'package:flowplanv2/core/sync/server_sync_change_applier.dart';
import 'package:flowplanv2/core/sync/sync_cursor_store.dart';
import 'package:flowplanv2/core/sync/sync_engine.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_result.dart';
import 'package:flowplanv2/core/sync/sync_status.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  tearDown(() {
    SyncWriteRecorder.onMutationRecorded = null;
  });

  test('pullChanges returns apply errors when applier reports nonfatal skips',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final cursorStore = SyncCursorStore(db);
    final applier = _FakeChangeApplier(
      db,
      results: const <ServerSyncApplyResult>[
        ServerSyncApplyResult(
          received: 2,
          applied: 1,
          skipped: 1,
          failed: 0,
          perType: <String, int>{'task_item': 2},
          appliedChangeIds: <String>['change-applied'],
          errors: <String>['task_item:change-skipped: stale dependency'],
        ),
      ],
    );
    final ackBodies = <Map<String, dynamic>>[];

    final engine = ServerSyncEngine(
      cursorStore: cursorStore,
      offlineMutationRunner: OfflineMutationRunner(OfflineMutationStore(db)),
      changeApplier: applier,
      apiClient: ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode(<String, Object?>{
                'changes': <Object?>[
                  <String, Object?>{'changeId': 'change-applied'},
                  <String, Object?>{'changeId': 'change-skipped'},
                ],
                'nextCursor': 'cursor-nonfatal',
              }),
              200,
            );
          }
          ackBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{}', 200);
        }),
      ),
    );

    final result = await engine.pullChanges(limit: 5);

    expect(result['appliedChanges'], 1);
    expect(result['skippedChanges'], 1);
    expect(result['failedChanges'], 0);
    expect(result['applyErrors'], <String>[
      'task_item:change-skipped: stale dependency',
    ]);
    expect(ackBodies.single['appliedChangeIds'], <dynamic>['change-applied']);
    expect(await cursorStore.readPullCursor(), 'cursor-nonfatal');
    expect(await cursorStore.readLastPullAt(), isNotNull);
  });

  test('pushPending with an empty queue leaves last push time untouched',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final cursorStore = SyncCursorStore(db);
    var requestCount = 0;

    final engine = ServerSyncEngine(
      cursorStore: cursorStore,
      offlineMutationRunner: OfflineMutationRunner(OfflineMutationStore(db)),
      apiClient: ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          requestCount++;
          return http.Response('{}', 500);
        }),
      ),
    );

    final result = await engine.pushPending();

    expect(result.acceptedCount, 0);
    expect(result.pendingCount, 0);
    expect(requestCount, 0);
    expect(await cursorStore.readLastPushAt(), isNull);
  });

  test('ServerSyncResult processedCount excludes still-pending mutations', () {
    const result = ServerSyncResult(
      acceptedCount: 2,
      conflictCount: 3,
      rejectedCount: 4,
      pendingCount: 9,
    );

    expect(result.processedCount, 9);
  });

  test(
      'applier skips malformed and unsupported changes while applying valid ones',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);
    final applier = ServerSyncChangeApplier(db, stateStore);

    final result = await applier.applyPullResponse(<String, dynamic>{
      'changes': <Object?>[
        'not-a-map',
        <String, Object?>{
          'changeId': '',
          'objectType': 'task_list',
          'serverId': 'missing-change-id',
        },
        <String, Object?>{
          'changeId': 'unsupported-change',
          'objectType': 'unknown_type',
          'serverId': 'server-unsupported',
        },
        <String, Object?>{
          'changeId': 'setting-without-value',
          'objectType': 'user_setting',
          'serverId': 'server-setting-missing-value',
          'payload': <String, Object?>{'settingKey': 'client.locale'},
        },
        <String, Object?>{
          'changeId': 'setting-valid',
          'objectType': 'user_setting',
          'serverId': 'server-setting-valid',
          'serverVersion': 4,
          'payload': <String, Object?>{
            'settingKey': 'client.locale',
            'settingValue': 'zh-CN',
          },
        },
      ],
    });

    expect(result.received, 5);
    expect(result.applied, 1);
    expect(result.skipped, 4);
    expect(result.failed, 0);
    expect(result.perType, <String, int>{
      'task_list': 1,
      'unknown_type': 1,
      'user_setting': 2,
    });
    expect(result.appliedChangeIds, <String>['setting-valid']);
    expect(await db.getSetting('client.locale'), 'zh-CN');
  });

  test('state store lists failed objects oldest first with a limit', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    await stateStore.markPending(
      objectType: 'task_item',
      localId: 'task-1',
      state: SyncState.pendingCreate,
    );
    await stateStore.markPending(
      objectType: 'task_item',
      localId: 'task-2',
      state: SyncState.pendingUpdate,
    );
    await stateStore.markFailed(
      objectType: 'task_item',
      localId: 'task-1',
      error: StateError('first failure'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await stateStore.markFailed(
      objectType: 'task_item',
      localId: 'task-2',
      error: StateError('second failure'),
    );

    final failed = await stateStore.listByState(SyncState.failed, limit: 1);

    expect(failed, hasLength(1));
    expect(failed.single.localId, 'task-1');
    expect(failed.single.lastSyncError, contains('first failure'));
  });

  test(
      'write recorder records pending update metadata and suppresses audit hook',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);
    final mutationStore = OfflineMutationStore(db);
    final recorder = SyncWriteRecorder(
      mutationStore: mutationStore,
      stateStore: stateStore,
    );
    var hookCalls = 0;
    final hookCompleter = Completer<void>();
    SyncWriteRecorder.onMutationRecorded = () {
      hookCalls++;
      hookCompleter.complete();
      return Future<void>.value();
    };

    await stateStore.markSynced(
      objectType: 'task_item',
      localId: 'task-remote',
      serverId: 'server-task-remote',
      serverVersion: 7,
      uid: 'task-uid',
    );
    await recorder.recordUpdate(
      objectType: 'task_item',
      localId: 'task-remote',
      payload: const <String, Object?>{'summary': 'Updated'},
      changedFields: const <String>['summary'],
    );
    await hookCompleter.future;
    await recorder.recordDelete(
      objectType: 'audit_log',
      localId: 'audit-1',
      payload: const <String, Object?>{'deleted_at': 'now'},
    );

    final taskState = await stateStore.getState(
      objectType: 'task_item',
      localId: 'task-remote',
    );
    final auditState = await stateStore.getState(
      objectType: 'audit_log',
      localId: 'audit-1',
    );
    final mutations = await mutationStore.listPending();

    expect(taskState!.syncState, SyncState.pendingUpdate);
    expect(taskState.serverId, 'server-task-remote');
    expect(auditState!.syncState, SyncState.pendingDelete);
    expect(hookCalls, 1);
    expect(mutations, hasLength(2));
    expect(mutations.first.action, OfflineMutationAction.update);
    expect(mutations.first.serverId, 'server-task-remote');
    expect(mutations.first.baseServerVersion, 7);
    expect(jsonDecode(mutations.first.changedFieldsJson!), <String>['summary']);
  });

  test('conflict snapshots serialize nested field snapshots', () {
    final snapshot = ConflictSnapshot(
      conflictId: 'conflict-1',
      objectType: 'task_item',
      serverId: 'server-task-1',
      baseVersion: 1,
      localVersion: 2,
      serverVersion: 3,
      fields: const <ConflictFieldSnapshot>[
        ConflictFieldSnapshot(
          field: 'summary',
          base: 'Old',
          local: 'Local',
          server: 'Remote',
        ),
      ],
    );

    expect(snapshot.toJson(), <String, Object?>{
      'conflictId': 'conflict-1',
      'objectType': 'task_item',
      'serverId': 'server-task-1',
      'baseVersion': 1,
      'localVersion': 2,
      'serverVersion': 3,
      'fields': <Map<String, Object?>>[
        <String, Object?>{
          'field': 'summary',
          'base': 'Old',
          'local': 'Local',
          'server': 'Remote',
        },
      ],
    });
  });
}

class _FakeChangeApplier extends ServerSyncChangeApplier {
  _FakeChangeApplier(
    AppDatabase database, {
    required List<ServerSyncApplyResult> results,
  })  : _results = List<ServerSyncApplyResult>.of(results),
        super(database, SyncObjectStateStore(database));

  final List<ServerSyncApplyResult> _results;

  @override
  Future<ServerSyncApplyResult> applyPullResponse(
    Map<String, dynamic> response,
  ) async {
    return _results.removeAt(0);
  }
}
