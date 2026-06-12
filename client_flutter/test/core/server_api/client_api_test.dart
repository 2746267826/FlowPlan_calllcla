import 'dart:convert';

import 'package:flowplanv2/core/server_api/api_error.dart';
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
          expect(
              request.url.queryParameters['from'], '2026-06-08T00:00:00.000Z');
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

  test('tasks omits blank filters from client query parameters', () async {
    final db = createTestDatabase();
    addTearDown(db.close);

    final api = ClientApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/client/tasks');
          expect(request.url.query, isEmpty);
          return http.Response('{"items":[]}', 200);
        }),
      ),
    );

    await api.tasks(q: '   ');
  });

  test('task commands use encoded ids and expected HTTP methods', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final requests = <String>[];
    final bodies = <Map<String, dynamic>>[];

    final api = ClientApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.body.isNotEmpty) {
            bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          }
          return http.Response('{}', 200);
        }),
      ),
    );

    await api.updateTask(
      id: 'server task/1',
      patch: const <String, Object?>{'summary': 'Updated'},
    );
    await api.completeTask(
      id: 'server task/1',
      body: const <String, Object?>{'completedAt': '2026-06-08T00:00:00Z'},
    );
    await api.deleteTask('server task/1');

    expect(requests, <String>[
      'PATCH /api/client/tasks/server%20task%2F1',
      'POST /api/client/tasks/server%20task%2F1/complete',
      'DELETE /api/client/tasks/server%20task%2F1',
    ]);
    expect(bodies, <Map<String, dynamic>>[
      <String, dynamic>{'summary': 'Updated'},
      <String, dynamic>{'completedAt': '2026-06-08T00:00:00Z'},
    ]);
  });

  test('pushMutations posts batch metadata and mutations', () async {
    final db = createTestDatabase();
    addTearDown(db.close);

    final api = ClientApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/client/mutations');
          expect(jsonDecode(request.body), <String, Object?>{
            'clientBatchId': 'batch-1',
            'deviceId': 'device-1',
            'mutations': <Object?>[
              <String, Object?>{
                'mutationUid': 'mutation-1',
                'action': 'create',
              },
            ],
          });
          return http.Response('{"accepted":[]}', 200);
        }),
      ),
    );

    await api.pushMutations(
      clientBatchId: 'batch-1',
      deviceId: 'device-1',
      mutations: const <Map<String, Object?>>[
        <String, Object?>{
          'mutationUid': 'mutation-1',
          'action': 'create',
        },
      ],
    );
  });

  test('client read endpoints use expected paths and range query filters',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final requests = <String>[];
    final queries = <Map<String, String>>[];
    final api = ClientApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          queries.add(Map<String, String>.from(request.url.queryParameters));
          return http.Response('{}', 200);
        }),
      ),
    );

    await api.bootstrap();
    await api.settings();
    await api.settingsPolicy();
    await api.effectiveSettings();
    await api.events(
      from: DateTime.utc(2026, 6, 9),
      to: DateTime.utc(2026, 6, 10),
      q: '  planning  ',
      limit: 10,
    );
    await api.actualRecords(
      from: DateTime.utc(2026, 6, 1),
      to: DateTime.utc(2026, 6, 2),
      limit: 5,
    );
    await api.adminOutlookRuns();
    await api.adminOutlookDiagnostics();

    expect(requests, <String>[
      'GET /api/client/bootstrap',
      'GET /api/client/settings',
      'GET /api/client/settings-policy',
      'GET /api/client/settings/effective',
      'GET /api/client/events',
      'GET /api/client/actual-records',
      'GET /api/admin/outlook/runs',
      'GET /api/admin/outlook/diagnostics',
    ]);
    expect(queries[4], <String, String>{
      'from': '2026-06-09T00:00:00.000Z',
      'to': '2026-06-10T00:00:00.000Z',
      'q': '  planning  ',
      'limit': '10',
    });
    expect(queries[5], <String, String>{
      'from': '2026-06-01T00:00:00.000Z',
      'to': '2026-06-02T00:00:00.000Z',
      'limit': '5',
    });
  });

  test('event commands use encoded ids and expected request bodies', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final requests = <String>[];
    final bodies = <Object?>[];
    final api = ClientApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          bodies.add(
            request.body.isEmpty ? null : jsonDecode(request.body),
          );
          return http.Response('{}', 200);
        }),
      ),
    );

    await api.createEvent(const <String, Object?>{
      'uid': 'event-1',
      'summary': 'Plan',
    });
    await api.updateEvent(
      id: 'event/server 1',
      patch: const <String, Object?>{'summary': 'Updated plan'},
    );
    await api.deleteEvent('event/server 1');

    expect(requests, <String>[
      'POST /api/client/events',
      'PATCH /api/client/events/event%2Fserver%201',
      'DELETE /api/client/events/event%2Fserver%201',
    ]);
    expect(bodies, <Object?>[
      <String, Object?>{'uid': 'event-1', 'summary': 'Plan'},
      <String, Object?>{'summary': 'Updated plan'},
      null,
    ]);
  });

  test('settings, heartbeat, and import commands shape bodies and ids',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final requests = <String>[];
    final bodies = <Object?>[];
    final api = ClientApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          bodies.add(
            request.body.isEmpty ? null : jsonDecode(request.body),
          );
          return http.Response('{}', 200);
        }),
      ),
    );

    await api.heartbeat(
      deviceId: 'device/1',
      body: const <String, Object?>{'online': true},
    );
    await api.updateSetting(
      key: 'theme/user',
      value: const <String, Object?>{'mode': 'dark'},
      description: 'User theme',
      isSensitive: true,
    );
    await api.createLocalSnapshotImport(
      const <String, Object?>{'schemaVersion': 1},
    );
    await api.importStatus('import/1');
    await api.confirmImport('import/1');
    await api.cancelImport('import/1', reason: 'retry later');
    await api.cancelImport('import/2');

    expect(requests, <String>[
      'POST /api/devices/device%2F1/heartbeat',
      'PATCH /api/client/settings/theme%2Fuser',
      'POST /api/client/import/local-snapshot',
      'GET /api/client/import/import%2F1',
      'POST /api/client/import/import%2F1/confirm',
      'POST /api/client/import/import%2F1/cancel',
      'POST /api/client/import/import%2F2/cancel',
    ]);
    expect(bodies[0], <String, Object?>{'online': true});
    expect(bodies[1], <String, Object?>{
      'value': <String, Object?>{'mode': 'dark'},
      'scope': 'user.preference',
      'isSensitive': true,
      'description': 'User theme',
    });
    expect(bodies[2], <String, Object?>{
      'snapshot': <String, Object?>{'schemaVersion': 1},
    });
    expect(bodies[5], <String, Object?>{'reason': 'retry later'});
    expect(bodies[6], <String, Object?>{});
  });

  test('outlook refresh posts and HTTP errors surface as ApiError', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    var requestCount = 0;
    final api = ClientApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          requestCount++;
          expect(request.method, 'POST');
          expect(request.url.path, '/api/client/outlook/refresh');
          return http.Response('{"error":"offline"}', 503);
        }),
      ),
    );

    await expectLater(
      api.refreshOutlook(),
      throwsA(
        isA<ApiError>()
            .having((error) => error.statusCode, 'statusCode', 503)
            .having((error) => error.body, 'body', contains('offline')),
      ),
    );
    expect(requestCount, 1);
  });
}
