library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flowplanv2/web_app/web_api_client.dart';
import 'package:flowplanv2/web_app/web_local_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('getJson builds normalized URLs, query params, and web headers',
      () async {
    http.Request? captured;
    final client = await _clientFor(
      MockClient((request) async {
        captured = request;
        expect(request.method, 'GET');
        expect(request.url.path, '/api/web/tasks');
        expect(request.url.queryParameters, {'q': 'focus'});
        expect(request.headers['content-type'], 'application/json');
        expect(request.headers['x-flowplanv2-platform'], 'web');
        expect(request.headers['x-flowplanv2-user-id'], 'web-user');
        expect(request.headers['x-flowplanv2-device-id'], 'web-device');
        expect(request.headers['authorization'], 'Bearer access-token');
        return http.Response('{"items":[]}', 200);
      }),
    );

    final result = await client.getJson(
      '/web/tasks',
      query: {'q': 'focus', 'ignoredNull': null, 'ignoredEmpty': ''},
    );

    expect(result, {'items': const []});
    expect(captured?.url.toString(),
        'http://localhost:3202/api/web/tasks?q=focus');
  });

  test('post patch and put encode JSON request bodies and decode responses',
      () async {
    final bodies = <String, Map<String, dynamic>>{};
    final client = await _clientFor(
      MockClient((request) async {
        final raw = request.body;
        bodies['${request.method} ${request.url.path}'] =
            jsonDecode(raw) as Map<String, dynamic>;
        if (request.method == 'POST') {
          return http.Response(
            jsonEncode([
              {'ok': true}
            ]),
            200,
          );
        }
        if (request.method == 'PATCH') {
          return http.Response('{"patched":true}', 200);
        }
        return http.Response('', 204);
      }),
    );

    final post = await client.postJson('web/tasks', body: {'title': 'Draft'});
    final patch =
        await client.patchJson('/web/tasks/task-1', body: {'status': 'done'});
    final put = await client.putJson('/files/upload', body: {
      'payloadBase64': encodeBytes(Uint8List.fromList([1, 2, 3])),
    });

    expect(post, {
      'data': [
        {'ok': true}
      ]
    });
    expect(patch, {'patched': true});
    expect(put, isEmpty);
    expect(bodies['POST /api/web/tasks'], {'title': 'Draft'});
    expect(bodies['PATCH /api/web/tasks/task-1'], {'status': 'done'});
    expect(bodies['PUT /api/files/upload'], {
      'payloadBase64': 'AQID',
    });
    expect(decodeBytes('AQID'), Uint8List.fromList([1, 2, 3]));
  });

  test('non-success responses throw WebApiException with status and body',
      () async {
    final client = await _clientFor(
      MockClient((request) async => http.Response('nope', 418)),
    );

    await expectLater(
      client.getJson('/web/dashboard'),
      throwsA(
        isA<WebApiException>()
            .having((error) => error.statusCode, 'statusCode', 418)
            .having((error) => error.body, 'body', 'nope')
            .having((error) => error.toString(), 'toString', contains('418')),
      ),
    );
  });
}

Future<WebApiClient> _clientFor(http.Client httpClient) async {
  SharedPreferences.setMockInitialValues({
    'web.server.base_url': 'http://localhost:3202/api/',
    'web.user_id': 'web-user',
    'web.device_id': 'web-device',
    'web.auth.access_token': 'access-token',
  });
  final store = await WebLocalStore.load();
  return WebApiClient(store, httpClient: httpClient);
}
