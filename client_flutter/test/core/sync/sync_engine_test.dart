import 'dart:convert';

import 'package:flowplanv2/core/offline_queue/offline_mutation_runner.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/sync/sync_cursor_store.dart';
import 'package:flowplanv2/core/sync/sync_engine.dart';
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
}
