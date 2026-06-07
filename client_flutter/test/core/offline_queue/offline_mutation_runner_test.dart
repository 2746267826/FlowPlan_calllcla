import 'dart:convert';

import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_runner.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  test('accepted server mutations are removed from the pending queue', () async {
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
}
