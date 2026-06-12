import 'dart:convert';
import 'dart:typed_data';

import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/models_api.dart';
import 'package:flowplanv2/core/server_api/scheduler_api.dart';
import 'package:flowplanv2/core/server_api/server_config_store.dart';
import 'package:flowplanv2/core/server_api/tracking_ingest_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  test('tracking ingest API shapes batch, chunk, complete, and summary calls',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final requests = <http.Request>[];
    final api = TrackingIngestApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('{"ok":true}', 200);
        }),
      ),
    );

    await api.createBatch(
      batchUid: 'batch-uid-1',
      dataKind: 'input',
      startAt: DateTime.parse('2026-06-10T08:00:00+08:00'),
      endAt: DateTime.parse('2026-06-10T09:00:00+08:00'),
      compression: 'gzip',
      records: const <Map<String, dynamic>>[
        <String, dynamic>{'event': 'key'},
      ],
      metadata: const <String, dynamic>{'source': 'desktop'},
    );
    await api.uploadChunk(
      batchId: 'batch/server 1',
      chunkIndex: 2,
      records: const <Map<String, dynamic>>[
        <String, dynamic>{'event': 'mouse'},
      ],
      compressedJsonBytes: Uint8List.fromList(<int>[1, 2, 3]),
      checksum: 'sha256:abc',
    );
    await api.completeBatch(
      batchId: 'batch/server 1',
      records: const <Map<String, dynamic>>[
        <String, dynamic>{'event': 'done'},
      ],
    );
    await api.summary(
      start: DateTime.parse('2026-06-10T00:00:00+08:00'),
      end: DateTime.parse('2026-06-11T00:00:00+08:00'),
    );

    expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        <String>[
          'POST /api/tracking/ingest/batches',
          'POST /api/tracking/ingest/batches/batch/server%201/chunks',
          'POST /api/tracking/ingest/batches/batch/server%201/complete',
          'GET /api/tracking/summary',
        ]);
    expect(jsonDecode(requests[0].body), <String, Object?>{
      'batchUid': 'batch-uid-1',
      'dataKind': 'input',
      'compression': 'gzip',
      'startAt': '2026-06-10T00:00:00.000Z',
      'endAt': '2026-06-10T01:00:00.000Z',
      'records': <Object?>[
        <String, Object?>{'event': 'key'},
      ],
      'metadata': <String, Object?>{'source': 'desktop'},
    });
    expect(jsonDecode(requests[1].body), <String, Object?>{
      'chunkIndex': 2,
      'payload': <String, Object?>{
        'records': <Object?>[
          <String, Object?>{'event': 'mouse'},
        ],
      },
      'payloadBase64': 'AQID',
      'checksum': 'sha256:abc',
    });
    expect(jsonDecode(requests[2].body), <String, Object?>{
      'records': <Object?>[
        <String, Object?>{'event': 'done'},
      ],
    });
    expect(requests[3].url.queryParameters, <String, String>{
      'start': '2026-06-09T16:00:00.000Z',
      'end': '2026-06-10T16:00:00.000Z',
    });
  });

  test('tracking ingest API omits optional empty payload fields', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final bodies = <Map<String, dynamic>>[];
    final api = TrackingIngestApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('{}', 200);
        }),
      ),
    );

    await api.createBatch(batchUid: 'batch-uid-2', dataKind: 'activity');
    await api.uploadChunk(batchId: 'batch-2', chunkIndex: 0);
    await api.completeBatch(batchId: 'batch-2');

    expect(bodies, <Map<String, dynamic>>[
      <String, dynamic>{
        'batchUid': 'batch-uid-2',
        'dataKind': 'activity',
        'compression': 'none',
      },
      <String, dynamic>{'chunkIndex': 0},
      <String, dynamic>{},
    ]);
  });

  test('models API uses expected paths, query parameters, and bodies',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final requests = <http.Request>[];
    final api = ModelsApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('{"ok":true}', 200);
        }),
      ),
    );

    await api.models();
    await api.llmHealth();
    await api.versions('task-model');
    await api.runs('task-model', status: 'failed', limit: 7);
    await api.feedback(
      modelKey: 'task-model',
      targetType: 'task',
      targetId: 'task-1',
      feedbackType: 'thumbs_up',
      feedbackPayload: const <String, Object?>{'score': 1},
      modelRunId: 'run-1',
      source: 'worker-test',
    );
    await api.learn('task-model', autoActivate: false);

    expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        <String>[
          'GET /api/models',
          'GET /api/models/llm/health',
          'GET /api/models/task-model/versions',
          'GET /api/models/task-model/runs',
          'POST /api/models/task-model/feedback',
          'POST /api/models/task-model/learn',
        ]);
    expect(requests[3].url.queryParameters, <String, String>{
      'limit': '7',
      'status': 'failed',
    });
    expect(jsonDecode(requests[4].body), <String, Object?>{
      'targetType': 'task',
      'targetId': 'task-1',
      'feedbackType': 'thumbs_up',
      'outcome': 'thumbs_up',
      'source': 'worker-test',
      'feedbackPayload': <String, Object?>{'score': 1},
      'modelRunId': 'run-1',
    });
    expect(jsonDecode(requests[5].body), <String, Object?>{
      'autoActivate': false,
    });
  });

  test('scheduler API sends run lifecycle payloads', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final requests = <http.Request>[];
    final api = SchedulerApi(
      ApiClient(
        baseUri: Uri.parse('http://localhost:3202/api'),
        tokenStore: AuthTokenStore(db),
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('{"ok":true}', 200);
        }),
      ),
    );

    await api.createDraftRun(
      startAt: DateTime.utc(2026, 6, 10, 1),
      endAt: DateTime.utc(2026, 6, 10, 9),
      defaultTaskMinutes: 45,
      strategy: 'deep_work',
    );
    await api.run('run 1');
    await api.acceptRun(runId: 'run 1', note: 'ship it');
    await api.rejectRun(runId: 'run 1');
    await api.detectDeviations(
      startAt: DateTime.utc(2026, 6, 10),
      endAt: DateTime.utc(2026, 6, 11),
    );

    expect(
        requests.map((request) => '${request.method} ${request.url.path}'),
        <String>[
          'POST /api/scheduler/runs',
          'GET /api/scheduler/runs/run%201',
          'POST /api/scheduler/runs/run%201/accept',
          'POST /api/scheduler/runs/run%201/reject',
          'POST /api/scheduler/deviations/detect',
        ]);
    expect(jsonDecode(requests[0].body), <String, Object?>{
      'rangeStart': '2026-06-10T01:00:00.000Z',
      'rangeEnd': '2026-06-10T09:00:00.000Z',
      'defaultTaskMinutes': 45,
      'strategy': 'deep_work',
    });
    expect(jsonDecode(requests[2].body), <String, Object?>{
      'note': 'ship it',
    });
    expect(jsonDecode(requests[3].body), <String, Object?>{'reason': null});
    expect(jsonDecode(requests[4].body), <String, Object?>{
      'rangeStart': '2026-06-10T00:00:00.000Z',
      'rangeEnd': '2026-06-11T00:00:00.000Z',
    });
  });

  test('server config store defaults, migrates reserved URL, and normalizes',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final store = ServerConfigStore(db);

    expect(await store.readBaseUri(), Uri.parse('http://localhost:3202/api'));

    await db.setSetting('server.api.base_url', ' http://localhost:3000/api ');
    expect(await store.readBaseUri(), Uri.parse('http://localhost:3202/api'));

    await store.saveBaseUri(Uri.parse('http://example.test:8080/root/?x=1#f'));
    expect(
      await store.readBaseUri(),
      Uri.parse('http://example.test:8080/root/api'),
    );
  });
}
