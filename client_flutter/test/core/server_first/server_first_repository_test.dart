import 'dart:convert';

import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/api_error.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/client_api.dart';
import 'package:flowplanv2/core/server_first/mutation_coordinator.dart';
import 'package:flowplanv2/core/server_first/server_first_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  test('read methods forward query filters to the client API', () async {
    final harness = _Harness((request) async {
      return http.Response('{"ok":true}', 200);
    });
    addTearDown(harness.close);
    final from = DateTime.utc(2026, 6, 1);
    final to = DateTime.utc(2026, 6, 2);

    await harness.repository.tasks(
      from: from,
      to: to,
      q: 'design',
      limit: 12,
    );
    await harness.repository.events(
      from: from,
      to: to,
      q: 'planning',
      limit: 8,
    );
    await harness.repository.actualRecords(from: from, to: to, limit: 4);
    await harness.repository.effectiveSettings();

    expect(
      harness.requests.map((request) => '${request.method} ${request.path}'),
      <String>[
        'GET /api/client/tasks',
        'GET /api/client/events',
        'GET /api/client/actual-records',
        'GET /api/client/settings/effective',
      ],
    );
    expect(harness.requests[0].query, <String, String>{
      'from': '2026-06-01T00:00:00.000Z',
      'to': '2026-06-02T00:00:00.000Z',
      'q': 'design',
      'limit': '12',
    });
    expect(harness.requests[1].query, <String, String>{
      'from': '2026-06-01T00:00:00.000Z',
      'to': '2026-06-02T00:00:00.000Z',
      'q': 'planning',
      'limit': '8',
    });
    expect(harness.requests[2].query, <String, String>{
      'from': '2026-06-01T00:00:00.000Z',
      'to': '2026-06-02T00:00:00.000Z',
      'limit': '4',
    });
  });

  test('successful writes return canonical results and shape remote requests',
      () async {
    final harness = _Harness((request) async {
      return http.Response('{"serverVersion":3,"item":{"id":"remote-1"}}', 200);
    });
    addTearDown(harness.close);

    final createTask = await harness.repository.createTask(
      const <String, Object?>{'uid': 'task-1', 'summary': 'Write tests'},
    );
    final updateTask = await harness.repository.updateTask(
      id: 'task/server 1',
      patch: const <String, Object?>{'summary': 'Updated'},
      baseServerVersion: 5,
      changedFields: const <String>['summary'],
    );
    final completeTask = await harness.repository.completeTask(
      id: 'task/server 1',
      body: const <String, Object?>{'completedAt': '2026-06-10T00:00:00Z'},
      baseServerVersion: 6,
    );
    final deleteTask = await harness.repository.deleteTask(
      id: 'task/server 1',
      baseServerVersion: 7,
    );
    final createEvent = await harness.repository.createEvent(
      const <String, Object?>{'uid': 'event-1', 'summary': 'Planning'},
    );
    final updateEvent = await harness.repository.updateEvent(
      id: 'event/server 1',
      patch: const <String, Object?>{'summary': 'Updated planning'},
      baseServerVersion: 8,
    );
    final deleteEvent = await harness.repository.deleteEvent(
      id: 'event/server 1',
      baseServerVersion: 9,
    );

    expect(
      <ServerFirstWriteResult>[
        createTask,
        updateTask,
        completeTask,
        deleteTask,
        createEvent,
        updateEvent,
        deleteEvent,
      ].every((result) => result.isCanonical),
      isTrue,
    );
    expect(await harness.store.listPending(), isEmpty);
    expect(
      harness.requests.map((request) => '${request.method} ${request.path}'),
      <String>[
        'POST /api/client/tasks',
        'PATCH /api/client/tasks/task%2Fserver%201',
        'POST /api/client/tasks/task%2Fserver%201/complete',
        'DELETE /api/client/tasks/task%2Fserver%201',
        'POST /api/client/events',
        'PATCH /api/client/events/event%2Fserver%201',
        'DELETE /api/client/events/event%2Fserver%201',
      ],
    );
    expect(harness.requests[1].jsonBody, <String, Object?>{
      'summary': 'Updated',
      'baseServerVersion': 5,
    });
    expect(harness.requests[2].jsonBody, <String, Object?>{
      'completedAt': '2026-06-10T00:00:00Z',
      'baseServerVersion': 6,
    });
    expect(harness.requests[5].jsonBody, <String, Object?>{
      'summary': 'Updated planning',
      'baseServerVersion': 8,
    });
  });

  test('API failures queue task writes when queueOnFailure is enabled',
      () async {
    final harness = _Harness((request) async {
      return http.Response('{"error":"offline"}', 503);
    });
    addTearDown(harness.close);

    final result = await harness.repository.createTask(
      const <String, Object?>{'uid': 'task-offline', 'summary': 'Offline task'},
    );

    expect(result.isPending, isTrue);
    expect(result.error, isA<ApiError>());
    expect(result.queuedMutation?.objectType, 'task_item');
    expect(result.queuedMutation?.localId, 'task-offline');
    expect(result.queuedMutation?.action, OfflineMutationAction.create);
    final pending = await harness.store.listPending();
    expect(pending, hasLength(1));
    expect(pending.single.objectType, 'task_item');
    expect(pending.single.localId, 'task-offline');
    expect(pending.single.action, OfflineMutationAction.create);
    expect(jsonDecode(pending.single.payloadJson), <String, Object?>{
      'uid': 'task-offline',
      'summary': 'Offline task',
    });
  });

  test('generic transport failures queue event updates with sync metadata',
      () async {
    final harness = _Harness((request) async {
      throw StateError('socket closed');
    });
    addTearDown(harness.close);

    final result = await harness.repository.updateEvent(
      id: 'event-server-1',
      patch: const <String, Object?>{'location': 'Room A'},
      baseServerVersion: 11,
      changedFields: const <String>['location'],
    );

    expect(result.isPending, isTrue);
    expect(result.error, isA<StateError>());
    expect(result.queuedMutation?.objectType, 'calendar_event');
    expect(result.queuedMutation?.localId, 'event-server-1');
    final pending = await harness.store.listPending();
    expect(pending, hasLength(1));
    expect(pending.single.objectType, 'calendar_event');
    expect(pending.single.serverId, 'event-server-1');
    expect(pending.single.action, OfflineMutationAction.update);
    expect(pending.single.baseServerVersion, 11);
    expect(jsonDecode(pending.single.changedFieldsJson!), <Object?>[
      'location',
    ]);
    expect(jsonDecode(pending.single.payloadJson), <String, Object?>{
      'location': 'Room A',
    });
  });

  test('queueOnFailure false rethrows and does not create offline mutations',
      () async {
    final harness = _Harness((request) async {
      return http.Response('{"error":"bad request"}', 400);
    });
    addTearDown(harness.close);

    await expectLater(
      harness.repository.createEvent(
        const <String, Object?>{'uid': 'event-1'},
        queueOnFailure: false,
      ),
      throwsA(isA<ApiError>()),
    );

    expect(await harness.store.listPending(), isEmpty);
  });
}

class _Harness {
  _Harness(Future<http.Response> Function(http.Request request) handler)
      : db = createTestDatabase() {
    store = OfflineMutationStore(db);
    repository = ServerFirstRepository(
      clientApi: ClientApi(
        ApiClient(
          baseUri: Uri.parse('http://localhost:3202/api'),
          tokenStore: AuthTokenStore(db),
          httpClient: MockClient((request) async {
            requests.add(_CapturedRequest.from(request));
            return handler(request);
          }),
        ),
      ),
      mutationCoordinator: MutationCoordinator(mutationStore: store),
    );
  }

  final dynamic db;
  late final OfflineMutationStore store;
  late final ServerFirstRepository repository;
  final List<_CapturedRequest> requests = <_CapturedRequest>[];

  Future<void> close() => db.close();
}

class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.jsonBody,
  });

  factory _CapturedRequest.from(http.Request request) {
    return _CapturedRequest(
      method: request.method,
      path: request.url.path,
      query: Map<String, String>.from(request.url.queryParameters),
      jsonBody: request.body.isEmpty
          ? const <String, Object?>{}
          : Map<String, Object?>.from(
              jsonDecode(request.body) as Map<String, dynamic>,
            ),
    );
  }

  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, Object?> jsonBody;
}
