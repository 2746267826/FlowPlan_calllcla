import 'package:flowplanv2/core/server_api/api_error.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  test('adds auth header and decodes JSON response', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tokenStore = AuthTokenStore(db);
    await tokenStore.saveTokens(
      accessToken: 'token-1',
      refreshToken: 'refresh-1',
    );

    final client = ApiClient(
      baseUri: Uri.parse('http://localhost:3202/api'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        expect(request.url.path, '/api/client/tasks');
        expect(request.headers['authorization'], 'Bearer token-1');
        expect(request.headers['accept'], 'application/json');
        return http.Response('{"items":[]}', 200);
      }),
    );

    expect(await client.getJson('/client/tasks'), <String, Object?>{
      'items': <Object?>[],
    });
  });

  test('throws ApiError for non-object JSON response', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final client = ApiClient(
      baseUri: Uri.parse('http://localhost:3202/api'),
      tokenStore: AuthTokenStore(db),
      httpClient: MockClient((_) async => http.Response('[]', 200)),
    );

    await expectLater(
      client.getJson('/client/tasks'),
      throwsA(isA<ApiError>()),
    );
  });

  test('normalizes decoded map-like objects', () {
    final payload = ApiClient.decodeObjectForTesting(
      <Object?, Object?>{
        'ok': true,
        'count': 2,
      },
      statusCode: 200,
      body: '{"ok":true,"count":2}',
    );

    expect(payload, <String, Object?>{
      'ok': true,
      'count': 2,
    });
  });

  test('returns an empty object for an empty response body', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final client = ApiClient(
      baseUri: Uri.parse('http://localhost:3202/api'),
      tokenStore: AuthTokenStore(db),
      httpClient: MockClient(
        (_) async => http.Response('', 204),
      ),
    );

    expect(await client.getJson('/client/bootstrap'), isEmpty);
  });

  test('throws ApiError with response details for non-2xx responses', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final client = ApiClient(
      baseUri: Uri.parse('http://localhost:3202/api'),
      tokenStore: AuthTokenStore(db),
      httpClient: MockClient(
        (_) async => http.Response('{"message":"down"}', 503),
      ),
    );

    await expectLater(
      client.getJson('/client/bootstrap'),
      throwsA(
        isA<ApiError>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having((error) => error.body, 'body', '{"message":"down"}'),
      ),
    );
  });

  test('does not add authorization header when token is blank', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tokenStore = AuthTokenStore(db);
    await tokenStore.saveTokens(accessToken: '  ', refreshToken: 'refresh-1');

    final client = ApiClient(
      baseUri: Uri.parse('http://localhost:3202/api'),
      tokenStore: tokenStore,
      httpClient: MockClient((request) async {
        expect(request.headers.containsKey('authorization'), isFalse);
        return http.Response('{}', 200);
      }),
    );

    await client.getJson('/client/bootstrap');
  });

  test('merges default headers with auth and JSON content headers', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tokenStore = AuthTokenStore(db);
    await tokenStore.saveTokens(
      accessToken: ' token-2 ',
      refreshToken: 'refresh-2',
    );

    final client = ApiClient(
      baseUri: Uri.parse('http://localhost:3202/api'),
      tokenStore: tokenStore,
      defaultHeaders: const <String, String>{
        'x-device-id': 'device-1',
      },
      httpClient: MockClient((request) async {
        expect(request.headers['accept'], 'application/json');
        expect(request.headers['authorization'], 'Bearer token-2');
        expect(request.headers['content-type'], 'application/json');
        expect(request.headers['x-device-id'], 'device-1');
        return http.Response('{"ok":true}', 200);
      }),
    );

    await client.postJson(
      '/client/tasks',
      body: <String, Object?>{'summary': 'Merge headers'},
    );
  });

  test('normalizes base path, request path, query, and JSON methods', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final requests = <String>[];
    final client = ApiClient(
      baseUri: Uri.parse('http://localhost:3202/api/'),
      tokenStore: AuthTokenStore(db),
      httpClient: MockClient((request) async {
        requests
            .add('${request.method} ${request.url.path}?${request.url.query}');
        return http.Response('{"ok":true}', 200);
      }),
    );

    await client.postJson(
      'client/tasks',
      query: const <String, String>{'source': 'post'},
      body: const <String, Object?>{'summary': 'Post'},
    );
    await client.patchJson(
      '/client/tasks/task-1',
      query: const <String, String>{'source': 'patch'},
      body: const <String, Object?>{'summary': 'Patch'},
    );
    await client.putJson(
      'client/settings/theme',
      query: const <String, String>{'source': 'put'},
      body: const <String, Object?>{'value': 'dark'},
    );
    await client.deleteJson(
      '/client/tasks/task-1',
      query: const <String, String>{'source': 'delete'},
    );

    expect(requests, <String>[
      'POST /api/client/tasks?source=post',
      'PATCH /api/client/tasks/task-1?source=patch',
      'PUT /api/client/settings/theme?source=put',
      'DELETE /api/client/tasks/task-1?source=delete',
    ]);
  });
}
