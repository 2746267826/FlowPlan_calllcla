import 'dart:convert';

import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/client_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  test('tasks forwards filters as client query parameters', () async {
    final db = createTestDatabase();
    addTearDown(db.close);

    final api = ClientApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/client/tasks');
          expect(request.url.queryParameters['q'], 'design');
          expect(request.url.queryParameters['limit'], '20');
          expect(request.url.queryParameters['from'], '2026-06-08T00:00:00.000Z');
          return http.Response('{"items":[]}', 200);
        }),
      ),
    );

    await api.tasks(
      from: DateTime.utc(2026, 6, 8),
      q: 'design',
      limit: 20,
    );
  });

  test('createTask posts the payload to the client task endpoint', () async {
    final db = createTestDatabase();
    addTearDown(db.close);

    final api = ClientApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/client/tasks');
          expect(jsonDecode(request.body), <String, Object?>{
            'uid': 'task-1',
            'summary': 'Write tests',
          });
          return http.Response('{"item":{"id":"task-1"}}', 201);
        }),
      ),
    );

    final response = await api.createTask(<String, Object?>{
      'uid': 'task-1',
      'summary': 'Write tests',
    });

    expect(response['item'], isA<Map<String, dynamic>>());
  });
}
