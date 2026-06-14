import 'dart:convert';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_runner.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/sync/sync_cursor_store.dart';
import 'package:flowplanv2/core/sync/sync_engine.dart';
import 'package:flowplanv2/core/sync/server_sync_change_applier.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  test('pullChanges acknowledges the returned cursor', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final cursorStore = SyncCursorStore(db);
    var acked = false;

    final engine = ServerSyncEngine(
      cursorStore: cursorStore,
      offlineMutationRunner: OfflineMutationRunner(OfflineMutationStore(db)),
      apiClient: ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            expect(request.url.path, '/api/sync/pull');
            expect(request.url.queryParameters['limit'], '1');
            return http.Response(
              jsonEncode(<String, Object?>{
                'changes': <Object?>[],
                'nextCursor': 'cursor-1',
              }),
              200,
            );
          }
          expect(request.method, 'POST');
          expect(request.url.path, '/api/sync/ack');
          acked = true;
          return http.Response('{}', 200);
        }),
      ),
    );

    final result = await engine.pullChanges(limit: 1);

    expect(result['pageCount'], 1);
    expect(result['pulledChanges'], 0);
    expect(acked, isTrue);
    expect(await cursorStore.readPullCursor(), 'cursor-1');
    expect(await cursorStore.readLastPullAt(), isNotNull);
  });

  test('pullChanges follows multiple pages and aggregates apply summaries',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final cursorStore = SyncCursorStore(db);
    final getQueries = <Map<String, String>>[];
    final ackBodies = <Map<String, dynamic>>[];
    final progress = <String>[];
    final applier = _FakeChangeApplier(
      db,
      results: <ServerSyncApplyResult>[
        const ServerSyncApplyResult(
          received: 2,
          applied: 2,
          skipped: 0,
          failed: 0,
          perType: <String, int>{'task_item': 2},
          appliedChangeIds: <String>['change-1', 'change-2'],
          errors: <String>[],
        ),
        const ServerSyncApplyResult(
          received: 1,
          applied: 1,
          skipped: 0,
          failed: 0,
          perType: <String, int>{'calendar_event': 1},
          appliedChangeIds: <String>['change-3'],
          errors: <String>[],
        ),
      ],
      repairCount: 2,
    );

    final engine = ServerSyncEngine(
      cursorStore: cursorStore,
      offlineMutationRunner: OfflineMutationRunner(OfflineMutationStore(db)),
      changeApplier: applier,
      apiClient: ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            getQueries
                .add(Map<String, String>.from(request.url.queryParameters));
            if (getQueries.length == 1) {
              return http.Response(
                jsonEncode(<String, Object?>{
                  'changes': <Object?>[
                    <String, Object?>{'changeId': 'change-1'},
                    <String, Object?>{'changeId': 'change-2'},
                  ],
                  'nextCursor': 'cursor-1',
                }),
                200,
              );
            }
            return http.Response(
              jsonEncode(<String, Object?>{
                'changes': <Object?>[
                  <String, Object?>{'changeId': 'change-3'},
                ],
                'nextCursor': 'cursor-2',
              }),
              200,
            );
          }

          expect(request.method, 'POST');
          expect(request.url.path, '/api/sync/ack');
          ackBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{}', 200);
        }),
      ),
    );

    final result = await engine.pullChanges(
      limit: 2,
      onProgress: (pulledChanges, pageCount) {
        progress.add('$pulledChanges/$pageCount');
      },
    );

    expect(getQueries, <Map<String, String>>[
      <String, String>{'limit': '2'},
      <String, String>{'limit': '2', 'cursor': 'cursor-1'},
    ]);
    expect(ackBodies, <Map<String, dynamic>>[
      <String, dynamic>{
        'cursor': 'cursor-1',
        'appliedChangeIds': <dynamic>['change-1', 'change-2'],
      },
      <String, dynamic>{
        'cursor': 'cursor-2',
        'appliedChangeIds': <dynamic>['change-3'],
      },
    ]);
    expect(progress, <String>['2/1', '3/2']);
    expect(result['pageCount'], 2);
    expect(result['pulledChanges'], 3);
    expect(result['appliedChanges'], 3);
    expect(result['perType'], <String, int>{
      'task_item': 2,
      'calendar_event': 1,
    });
    expect(result['orphanCalendarEvents'], 2);
    expect(result['changes'], hasLength(3));
    expect(await cursorStore.readPullCursor(), 'cursor-2');
    expect(await cursorStore.readLastPullAt(), isNotNull);
  });

  test('pullChanges stops after one full page when nextCursor is missing',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final cursorStore = SyncCursorStore(db);
    var getCount = 0;
    var ackCount = 0;

    final engine = ServerSyncEngine(
      cursorStore: cursorStore,
      offlineMutationRunner: OfflineMutationRunner(OfflineMutationStore(db)),
      apiClient: ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            getCount++;
            expect(request.url.queryParameters, <String, String>{'limit': '2'});
            return http.Response(
              jsonEncode(<String, Object?>{
                'changes': <Object?>[
                  <String, Object?>{'changeId': 'change-1'},
                  <String, Object?>{'changeId': 'change-2'},
                ],
              }),
              200,
            );
          }
          ackCount++;
          return http.Response('{}', 200);
        }),
      ),
    );

    final result = await engine.pullChanges(limit: 2);

    expect(getCount, 1);
    expect(ackCount, 0);
    expect(result['pageCount'], 1);
    expect(result['pulledChanges'], 2);
    expect(await cursorStore.readPullCursor(), isNull);
    expect(await cursorStore.readLastPullAt(), isNotNull);
  });

  test('pullChanges stops when the server repeats the current cursor',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final cursorStore = SyncCursorStore(db);
    await cursorStore.savePullCursor('cursor-1');
    var getCount = 0;
    var ackCount = 0;

    final engine = ServerSyncEngine(
      cursorStore: cursorStore,
      offlineMutationRunner: OfflineMutationRunner(OfflineMutationStore(db)),
      apiClient: ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          if (request.method == 'GET') {
            getCount++;
            expect(request.url.queryParameters, <String, String>{
              'limit': '1',
              'cursor': 'cursor-1',
            });
            return http.Response(
              jsonEncode(<String, Object?>{
                'changes': <Object?>[
                  <String, Object?>{'changeId': 'change-1'},
                ],
                'nextCursor': 'cursor-1',
              }),
              200,
            );
          }
          ackCount++;
          expect(jsonDecode(request.body), <String, Object?>{
            'cursor': 'cursor-1',
            'appliedChangeIds': <Object?>[],
          });
          return http.Response('{}', 200);
        }),
      ),
    );

    final result = await engine.pullChanges(limit: 1);

    expect(getCount, 1);
    expect(ackCount, 1);
    expect(result['pageCount'], 1);
    expect(result['pulledChanges'], 1);
    expect(await cursorStore.readPullCursor(), 'cursor-1');
  });

  test('pullChanges does not ack or save cursor when applying changes fails',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final cursorStore = SyncCursorStore(db);
    var ackCount = 0;
    final applier = _FakeChangeApplier(
      db,
      results: <ServerSyncApplyResult>[
        const ServerSyncApplyResult(
          received: 1,
          applied: 0,
          skipped: 0,
          failed: 1,
          perType: <String, int>{'task_item': 1},
          appliedChangeIds: <String>[],
          errors: <String>['boom'],
        ),
      ],
    );

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
                  <String, Object?>{'changeId': 'change-1'},
                ],
                'nextCursor': 'cursor-1',
              }),
              200,
            );
          }
          ackCount++;
          return http.Response('{}', 200);
        }),
      ),
    );

    await expectLater(
      engine.pullChanges(limit: 1),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('boom'),
        ),
      ),
    );

    expect(ackCount, 0);
    expect(await cursorStore.readPullCursor(), isNull);
    expect(await cursorStore.readLastPullAt(), isNull);
  });

  test('refreshCacheFromServer pulls changes without pushing pending mutations',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final cursorStore = SyncCursorStore(db);
    var pulled = false;

    final engine = ServerSyncEngine(
      cursorStore: cursorStore,
      offlineMutationRunner: _ThrowingOfflineMutationRunner(
        OfflineMutationStore(db),
      ),
      apiClient: ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/sync/pull');
          pulled = true;
          return http.Response(
            jsonEncode(<String, Object?>{
              'changes': <Object?>[
                <String, Object?>{'changeId': 'change-1'},
              ],
            }),
            200,
          );
        }),
      ),
    );

    final result = await engine.refreshCacheFromServer(limit: 1);

    expect(pulled, isTrue);
    expect(result['pulledChanges'], 1);
    expect(await cursorStore.readLastPullAt(), isNotNull);
  });

  test('pushPending returns acceptedCount and records a successful push time',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final cursorStore = SyncCursorStore(db);
    final mutationStore = OfflineMutationStore(db);
    final mutationUid = await mutationStore.enqueue(
      objectType: 'task_item',
      localId: 'local-task-1',
      action: OfflineMutationAction.create,
      payload: const <String, Object?>{
        'uid': 'task-1',
        'summary': 'Write tests',
      },
    );

    final engine = ServerSyncEngine(
      cursorStore: cursorStore,
      offlineMutationRunner: OfflineMutationRunner(mutationStore),
      apiClient: ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/sync/push');
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['mutations'], isA<List<dynamic>>());
          return http.Response(
            jsonEncode(<String, Object?>{
              'accepted': <Object?>[
                <String, Object?>{
                  'mutationUid': mutationUid,
                  'serverId': 'server-task-1',
                  'serverVersion': 2,
                },
              ],
              'conflicts': <Object?>[],
              'rejected': <Object?>[],
            }),
            200,
          );
        }),
      ),
    );

    final result = await engine.pushPending();

    expect(result.acceptedCount, 1);
    expect(result.conflictCount, 0);
    expect(result.rejectedCount, 0);
    expect(result.pendingCount, 1);
    expect(await mutationStore.listPending(), isEmpty);
    expect(await cursorStore.readLastPushAt(), isNotNull);
  });
}

class _FakeChangeApplier extends ServerSyncChangeApplier {
  _FakeChangeApplier(
    AppDatabase database, {
    required List<ServerSyncApplyResult> results,
    int repairCount = 0,
  })  : _results = List<ServerSyncApplyResult>.of(results),
        _repairCount = repairCount,
        super(database, SyncObjectStateStore(database));

  final List<ServerSyncApplyResult> _results;
  final int _repairCount;

  @override
  Future<ServerSyncApplyResult> applyPullResponse(
    Map<String, dynamic> response,
  ) async {
    if (_results.isEmpty) {
      return const ServerSyncApplyResult(
        received: 0,
        applied: 0,
        skipped: 0,
        failed: 0,
        perType: <String, int>{},
        appliedChangeIds: <String>[],
        errors: <String>[],
      );
    }
    return _results.removeAt(0);
  }

  @override
  Future<int> repairOutlookOrphanEvents() async => _repairCount;
}

class _ThrowingOfflineMutationRunner extends OfflineMutationRunner {
  _ThrowingOfflineMutationRunner(super.store);

  @override
  Future<ServerSyncResult> pushPending(ApiClient apiClient) {
    throw StateError('pushPending must not run during cache refresh');
  }
}
