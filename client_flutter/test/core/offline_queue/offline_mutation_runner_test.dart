import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_runner.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/request_context.dart';
import 'package:flowplanv2/core/sync/sync_conflict_store.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  test('pushPending is a no-op when there are no queued mutations', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    var requestCount = 0;
    final runner = OfflineMutationRunner(OfflineMutationStore(db));
    final client = _client(db, (request) async {
      requestCount++;
      return http.Response('{}', 500);
    });

    final result = await runner.pushPending(client);

    expect(result.acceptedCount, 0);
    expect(result.conflictCount, 0);
    expect(result.rejectedCount, 0);
    expect(result.pendingCount, 0);
    expect(requestCount, 0);
  });

  test('accepted server mutations are removed from the pending queue',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final store = OfflineMutationStore(db);
    final mutationUid = await store.enqueue(
      objectType: 'task_item',
      localId: 'local-task-1',
      action: OfflineMutationAction.create,
      payload: <String, Object?>{
        'uid': 'task-1',
        'summary': 'Write tests',
      },
    );

    final runner = OfflineMutationRunner(
      store,
      clientBatchIdFactory: () => 'batch-1',
    );
    final client = ApiClient(
      baseUri: Uri.parse('http://localhost:3202/api'),
      tokenStore: AuthTokenStore(db),
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/sync/push');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['clientBatchId'], 'batch-1');
        expect(body['mutations'], isA<List<dynamic>>());
        return http.Response(
          jsonEncode(<String, Object?>{
            'accepted': <Object?>[
              <String, Object?>{
                'mutationUid': mutationUid,
                'serverId': 'server-task-1',
                'serverVersion': 3,
              },
            ],
            'conflicts': <Object?>[],
            'rejected': <Object?>[],
          }),
          200,
        );
      }),
    );

    final result = await runner.pushPending(client);

    expect(result.acceptedCount, 1);
    expect(await store.listPending(), isEmpty);
  });

  test('accepted mutations mark the matching sync object as server synced',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final store = OfflineMutationStore(db);
    final stateStore = SyncObjectStateStore(db);
    final mutationUid = await store.enqueue(
      objectType: 'task_item',
      localId: 'local-task-accepted',
      action: OfflineMutationAction.update,
      payload: <String, Object?>{
        'uid': '  task-accepted  ',
        'summary': 'Accepted update',
      },
      changedFields: const <String>['summary', 'ignoredInt'],
    );
    await stateStore.markPending(
      objectType: 'task_item',
      localId: 'local-task-accepted',
      uid: 'task-accepted',
      state: SyncState.pendingUpdate,
    );
    Map<String, dynamic>? postedBody;
    final runner = OfflineMutationRunner(
      store,
      stateStore: stateStore,
      requestContext: const RequestContext(
        deviceId: 'device-1',
        platform: 'windows',
        userId: 'user-1',
      ),
      clientBatchIdFactory: () => 'batch-accepted',
    );
    final client = _client(db, (request) async {
      postedBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode(<String, Object?>{
          'accepted': <Object?>[
            <String, Object?>{
              'mutationUid': mutationUid,
              'serverId': 'server-task-accepted',
              'serverVersion': 5,
            },
          ],
        }),
        200,
      );
    });

    final result = await runner.pushPending(client);

    expect(result.acceptedCount, 1);
    expect(postedBody, isNotNull);
    expect(postedBody!['deviceId'], 'device-1');
    expect(postedBody!['platform'], 'windows');
    expect(postedBody!['userId'], 'user-1');
    expect(postedBody!['clientBatchId'], 'batch-accepted');
    final postedMutation =
        (postedBody!['mutations'] as List<dynamic>).single as Map;
    expect(postedMutation['uid'], 'task-accepted');
    expect(postedMutation['changedFields'], <String>['summary', 'ignoredInt']);
    expect(await store.listPending(), isEmpty);
    final state = await stateStore.getState(
      objectType: 'task_item',
      localId: 'local-task-accepted',
    );
    expect(state?.syncState, SyncState.synced);
    expect(state?.serverId, 'server-task-accepted');
    expect(state?.serverVersion, 5);
  });

  test('conflicted mutations are kept, stored, and mark object conflict',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final store = OfflineMutationStore(db);
    final stateStore = SyncObjectStateStore(db);
    final conflictStore = SyncConflictStore(db);
    final mutationUid = await store.enqueue(
      objectType: 'task_item',
      localId: 'local-task-conflict',
      serverId: 'server-task-conflict',
      action: OfflineMutationAction.update,
      baseServerVersion: 2,
      payload: const <String, Object?>{'summary': 'Local edit'},
    );
    await stateStore.markPending(
      objectType: 'task_item',
      localId: 'local-task-conflict',
      serverId: 'server-task-conflict',
      state: SyncState.pendingUpdate,
    );
    final runner = OfflineMutationRunner(
      store,
      stateStore: stateStore,
      conflictStore: conflictStore,
    );
    final client = _client(db, (_) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'conflicts': <Object?>[
            <String, Object?>{
              'mutationUid': mutationUid,
              'conflictId': 'conflict-1',
              'objectType': 'task_item',
              'serverId': 'server-task-conflict',
              'baseVersion': 2,
              'localVersion': 3,
              'serverVersion': 4,
              'fields': <Object?>[
                <String, Object?>{
                  'field': 'summary',
                  'base': 'Base',
                  'local': 'Local edit',
                  'server': 'Server edit',
                },
              ],
            },
          ],
        }),
        200,
      );
    });

    final result = await runner.pushPending(client);

    expect(result.conflictCount, 1);
    final mutationRows = await db.customSelect(
      'SELECT * FROM offline_mutations WHERE mutation_uid = ?',
      variables: [Variable<String>(mutationUid)],
    ).get();
    expect(mutationRows.single.read<String>('status'),
        OfflineMutationStatus.conflict.wireName);
    expect(mutationRows.single.read<String>('last_error'),
        'Server reported conflict');
    final conflicts = await conflictStore.listOpen();
    expect(conflicts.single.conflictUid, 'conflict-1');
    expect(conflicts.single.objectType, 'task_item');
    expect(conflicts.single.serverVersion, 4);
    expect(conflicts.single.fieldsJson, contains('"field":"summary"'));
    final state = await stateStore.getState(
      objectType: 'task_item',
      localId: 'local-task-conflict',
    );
    expect(state?.syncState, SyncState.conflict);
    expect(state?.lastSyncError, 'Server reported conflict');
  });

  test('rejected mutations are marked failed with server reason', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final store = OfflineMutationStore(db);
    final stateStore = SyncObjectStateStore(db);
    final mutationUid = await store.enqueue(
      objectType: 'task_item',
      localId: 'local-task-rejected',
      action: OfflineMutationAction.delete,
      payload: const <String, Object?>{'uid': 'task-rejected'},
    );
    await stateStore.markPending(
      objectType: 'task_item',
      localId: 'local-task-rejected',
      state: SyncState.pendingDelete,
    );
    final runner = OfflineMutationRunner(store, stateStore: stateStore);
    final client = _client(db, (_) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'rejected': <Object?>[
            <String, Object?>{
              'mutationUid': mutationUid,
              'reason': 'version too old',
            },
          ],
        }),
        200,
      );
    });

    final result = await runner.pushPending(client);

    expect(result.rejectedCount, 1);
    final pending = await store.listPending();
    expect(pending.single.status, OfflineMutationStatus.failed);
    expect(pending.single.lastError, 'version too old');
    final state = await stateStore.getState(
      objectType: 'task_item',
      localId: 'local-task-rejected',
    );
    expect(state?.syncState, SyncState.failed);
    expect(state?.lastSyncError, 'version too old');
  });

  test('transport failures mark every pending mutation failed then rethrow',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final store = OfflineMutationStore(db);
    final stateStore = SyncObjectStateStore(db);
    await store.enqueue(
      objectType: 'task_item',
      localId: 'local-task-failure',
      action: OfflineMutationAction.update,
      payload: const <String, Object?>{'summary': 'Retry later'},
    );
    await stateStore.markPending(
      objectType: 'task_item',
      localId: 'local-task-failure',
      state: SyncState.pendingUpdate,
    );
    final runner = OfflineMutationRunner(store, stateStore: stateStore);
    final client = _client(
      db,
      (_) async => http.Response('server down', 503),
    );

    await expectLater(
      runner.pushPending(client),
      throwsA(isA<Exception>()),
    );

    final pending = await store.listPending();
    expect(pending.single.status, OfflineMutationStatus.failed);
    expect(pending.single.attempts, 1);
    expect(pending.single.lastError, contains('Request failed'));
    final state = await stateStore.getState(
      objectType: 'task_item',
      localId: 'local-task-failure',
    );
    expect(state?.syncState, SyncState.failed);
    expect(state?.lastSyncError, contains('Request failed'));
  });
}

ApiClient _client(
  dynamic db,
  Future<http.Response> Function(http.Request request) handler,
) {
  return ApiClient(
    baseUri: Uri.parse('http://localhost:3202/api'),
    tokenStore: AuthTokenStore(db),
    httpClient: MockClient(handler),
  );
}
