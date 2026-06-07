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
}
