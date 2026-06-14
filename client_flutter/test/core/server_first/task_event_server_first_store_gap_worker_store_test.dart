import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/client_api.dart';
import 'package:flowplanv2/core/server_first/mutation_coordinator.dart';
import 'package:flowplanv2/core/server_first/server_first_repository.dart';
import 'package:flowplanv2/core/server_first/task_event_server_first_store.dart';
import 'package:flowplanv2/core/sync/sync_object_registry.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_status.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test('tasks and events forward query filters in request order', () async {
    final harness = _Harness((_) async {
      return http.Response('{"items":[]}', 200);
    });
    await harness.setUp();
    addTearDown(harness.dispose);

    final from = DateTime.utc(2026, 6, 10, 1);
    final to = DateTime.utc(2026, 6, 10, 2);
    final tasks = await harness.store.tasks(
      from: from,
      to: to,
      q: 'deep work',
      limit: 3,
    );
    final events = await harness.store.events(
      from: from,
      to: to,
      q: 'standup',
      limit: 4,
    );

    expect(tasks, <String, Object?>{'items': <Object?>[]});
    expect(events, <String, Object?>{'items': <Object?>[]});
    expect(
      harness.requests.map((request) => '${request.method} ${request.path}'),
      <String>[
        'GET /api/client/tasks',
        'GET /api/client/events',
      ],
    );
    expect(harness.requests[0].query, <String, String>{
      'from': '2026-06-10T01:00:00.000Z',
      'to': '2026-06-10T02:00:00.000Z',
      'q': 'deep work',
      'limit': '3',
    });
    expect(harness.requests[1].query, <String, String>{
      'from': '2026-06-10T01:00:00.000Z',
      'to': '2026-06-10T02:00:00.000Z',
      'q': 'standup',
      'limit': '4',
    });
  });

  test('direct task and event delete wrappers send remote deletes', () async {
    final harness = _Harness((_) async {
      return http.Response('{"serverVersion":19}', 200);
    });
    await harness.setUp();
    addTearDown(harness.dispose);

    final taskResult = await harness.store.deleteTask(
      id: 'task/server 8',
      baseServerVersion: 17,
    );
    final eventResult = await harness.store.deleteEvent(
      id: 'event/server 9',
      baseServerVersion: 18,
    );

    expect(taskResult.isCanonical, isTrue);
    expect(eventResult.isCanonical, isTrue);
    expect(
      harness.requests.map((request) => '${request.method} ${request.path}'),
      <String>[
        'DELETE /api/client/tasks/task%2Fserver%208',
        'DELETE /api/client/events/event%2Fserver%209',
      ],
    );
    expect(await harness.mutationStore.listPending(), isEmpty);
  });

  test('completeLocalTask with blank server id throws without cache changes',
      () async {
    final harness = _Harness((request) async {
      fail('unexpected remote ${request.method} ${request.url}');
    });
    await harness.setUp();
    addTearDown(harness.dispose);
    final localId = await harness.db.into(harness.db.taskItems).insert(
          fixtureTask(
            uid: 'task-blank-server-uid',
            summary: 'Complete locally',
            taskListId: harness.taskListId,
          ),
        );
    await harness.stateStore.markPending(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
      serverId: '   ',
      uid: 'task-blank-server-uid',
      state: SyncState.pendingUpdate,
    );

    final taskBefore = await (harness.db.select(harness.db.taskItems)
          ..where((row) => row.id.equals(localId)))
        .getSingle();

    await expectLater(
      harness.store.completeLocalTask(
        localId: localId,
        body: const <String, Object?>{
          'completedAt': '2026-06-10T06:30:00Z',
          'percentComplete': 40,
        },
        baseServerVersion: 31,
      ),
      throwsA(isA<StateError>()),
    );

    final task = await (harness.db.select(harness.db.taskItems)
          ..where((row) => row.id.equals(localId)))
        .getSingle();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
    );

    expect(harness.requests, isEmpty);
    expect(task.status, taskBefore.status);
    expect(task.percentComplete, taskBefore.percentComplete);
    expect(task.completed, taskBefore.completed);
    expect(await harness.mutationStore.listPending(), isEmpty);
    expect(state?.syncState, SyncState.pendingUpdate);
    expect(state?.serverId, '   ');
  });

  test('createTask accepts top-level item payload and item server version',
      () async {
    final harness = _Harness((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/client/tasks');
      return http.Response(
        jsonEncode(<String, Object?>{
          'item': <String, Object?>{
            'id': 'server-task-item-version',
            'uid': 'task-item-version-uid',
            'serverVersion': 44,
            'summary': 'Top-level canonical task',
            'status': 'in_progress',
            'taskListId': _fixtureTaskListId,
            'priorityLocal': 5,
          },
        }),
        201,
      );
    });
    await harness.setUp();
    addTearDown(harness.dispose);

    final result = await harness.store.createTask(<String, Object?>{
      'uid': 'task-item-version-uid',
      'summary': 'Fallback task',
      'taskListId': harness.taskListId,
    });

    final task = (await harness.db.select(harness.db.taskItems).get()).single;
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: task.id.toString(),
    );

    expect(result.isCanonical, isTrue);
    expect(task.summary, 'Top-level canonical task');
    expect(task.status, 'IN-PROCESS');
    expect(task.priorityLocal, 5);
    expect(state?.syncState, SyncState.synced);
    expect(state?.serverId, 'server-task-item-version');
    expect(state?.serverVersion, 44);
    expect(state?.uid, 'task-item-version-uid');
    expect(await harness.mutationStore.listPending(), isEmpty);
  });

  test('updateLocalTask applies canonical patch response and sync metadata',
      () async {
    final harness = _Harness((request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/client/tasks/server-task-canonical');
      expect(jsonDecode(request.body), <String, Object?>{
        'summary': 'Client task patch',
        'priority': 3,
        'baseServerVersion': 41,
      });
      return http.Response(
        jsonEncode(<String, Object?>{
          'item': <String, Object?>{
            'id': 'server-task-canonical',
            'uid': 'task-canonical-uid',
            'serverVersion': 42,
            'payload': <String, Object?>{
              'summary': 'Server task patch',
              'status': 'cancelled',
              'priority': '7',
              'taskListId': _fixtureTaskListId,
            },
          },
        }),
        200,
      );
    });
    await harness.setUp();
    addTearDown(harness.dispose);
    final localId = await harness.db.into(harness.db.taskItems).insert(
          fixtureTask(
            uid: 'task-canonical-uid',
            summary: 'Before canonical patch',
            taskListId: harness.taskListId,
          ),
        );
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
      serverId: 'server-task-canonical',
      serverVersion: 41,
      uid: 'task-canonical-uid',
    );

    final result = await harness.store.updateLocalTask(
      localId: localId,
      patch: const <String, Object?>{
        'summary': 'Client task patch',
        'priority': 3,
      },
      changedFields: const <String>['summary', 'priority'],
    );

    final task = await (harness.db.select(harness.db.taskItems)
          ..where((row) => row.id.equals(localId)))
        .getSingle();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
    );

    expect(result.isCanonical, isTrue);
    expect(task.summary, 'Server task patch');
    expect(task.status, 'CANCELLED');
    expect(task.priority, 7);
    expect(state?.syncState, SyncState.synced);
    expect(state?.serverId, 'server-task-canonical');
    expect(state?.serverVersion, 42);
    expect(state?.uid, 'task-canonical-uid');
    expect(await harness.mutationStore.listPending(), isEmpty);
  });

  test('updateLocalTask applies nullable and bool canonical patch fallbacks',
      () async {
    final harness = _Harness((request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/client/tasks/server-task-value-fallbacks');
      return http.Response(
        jsonEncode(<String, Object?>{
          'item': <String, Object?>{
            'id': 'server-task-value-fallbacks',
            'uid': 'task-value-fallbacks-uid',
            'serverVersion': 46,
            'payload': <String, Object?>{
              'description': 123,
              'isLocked': 'true',
              'percentComplete': 'bad-int',
              'status': 'done',
              'taskListId': _fixtureTaskListId,
            },
          },
        }),
        200,
      );
    });
    await harness.setUp();
    addTearDown(harness.dispose);
    final localId = await harness.db.into(harness.db.taskItems).insert(
          fixtureTask(
            uid: 'task-value-fallbacks-uid',
            summary: 'Before value fallback patch',
            taskListId: harness.taskListId,
          ),
        );
    await (harness.db.update(harness.db.taskItems)
          ..where((row) => row.id.equals(localId)))
        .write(const TaskItemsCompanion(
      description: Value('before description'),
    ));
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
      serverId: 'server-task-value-fallbacks',
      serverVersion: 45,
      uid: 'task-value-fallbacks-uid',
    );

    final result = await harness.store.updateLocalTask(
      localId: localId,
      patch: const <String, Object?>{
        'description': null,
        'isLocked': false,
      },
      changedFields: const <String>['description', 'isLocked'],
    );

    final task = await (harness.db.select(harness.db.taskItems)
          ..where((row) => row.id.equals(localId)))
        .getSingle();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
    );

    expect(result.isCanonical, isTrue);
    expect(task.description, '123');
    expect(task.isLocked, isTrue);
    expect(task.percentComplete, 0);
    expect(task.status, 'COMPLETED');
    expect(state?.syncState, SyncState.synced);
    expect(state?.serverVersion, 46);
    expect(await harness.mutationStore.listPending(), isEmpty);
  });

  test('canonical create without server version leaves synced item pending',
      () async {
    final harness = _Harness((_) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'serverId': 'server-event-no-version',
          'item': <String, Object?>{
            'uid': 'event-no-version-uid',
            'payload': <String, Object?>{
              'summary': 'Remote event without version',
              'startAt': '2026-06-10T09:00:00Z',
              'eventCalendarId': _fixtureCalendarId,
            },
          },
        }),
        201,
      );
    });
    await harness.setUp();
    addTearDown(harness.dispose);

    final result = await harness.store.createEvent(<String, Object?>{
      'uid': 'event-no-version-uid',
      'summary': 'Fallback event',
      'eventCalendarId': harness.calendarId,
    });

    final event =
        (await harness.db.select(harness.db.calendarEvents).get()).single;
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.calendarEvent.key,
      localId: event.id.toString(),
    );

    expect(result.isCanonical, isTrue);
    expect(event.summary, 'Remote event without version');
    expect(event.dtstart.toUtc(), DateTime.parse('2026-06-10T09:00:00Z'));
    expect(state?.syncState, SyncState.pendingUpdate);
    expect(state?.serverId, 'server-event-no-version');
    expect(state?.serverVersion, isNull);
    expect(state?.uid, 'event-no-version-uid');
  });

  test('local task and event delete success removes rows without queueing',
      () async {
    final harness = _Harness((request) async {
      return http.Response(
        jsonEncode(<String, Object?>{
          'serverVersion': request.url.path.contains('/tasks/') ? 51 : 61,
          'serverId': request.url.pathSegments.last,
        }),
        200,
      );
    });
    await harness.setUp();
    addTearDown(harness.dispose);
    final taskId = await harness.db.into(harness.db.taskItems).insert(
          fixtureTask(
            uid: 'task-delete-success-uid',
            summary: 'Remote delete task',
            taskListId: harness.taskListId,
          ),
        );
    final eventId = await harness.db.into(harness.db.calendarEvents).insert(
          fixtureEvent(
            uid: 'event-delete-success-uid',
            summary: 'Remote delete event',
            calendarId: harness.calendarId,
          ),
        );
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.taskItem.key,
      localId: taskId.toString(),
      serverId: 'server-task-delete-success',
      serverVersion: 50,
      uid: 'task-delete-success-uid',
    );
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.calendarEvent.key,
      localId: eventId.toString(),
      serverId: 'server-event-delete-success',
      serverVersion: 60,
      uid: 'event-delete-success-uid',
    );

    final taskResult = await harness.store.deleteLocalTask(localId: taskId);
    final eventResult = await harness.store.deleteLocalEvent(localId: eventId);

    final taskState = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: taskId.toString(),
    );
    final eventState = await harness.stateStore.getState(
      objectType: SyncObjectType.calendarEvent.key,
      localId: eventId.toString(),
    );

    expect(taskResult.isCanonical, isTrue);
    expect(eventResult.isCanonical, isTrue);
    expect(
      harness.requests.map((request) => '${request.method} ${request.path}'),
      <String>[
        'DELETE /api/client/tasks/server-task-delete-success',
        'DELETE /api/client/events/server-event-delete-success',
      ],
    );
    expect(await harness.db.select(harness.db.taskItems).get(), isEmpty);
    expect(await harness.db.select(harness.db.calendarEvents).get(), isEmpty);
    expect(await harness.mutationStore.listPending(), isEmpty);
    expect(taskState?.syncState, SyncState.synced);
    expect(taskState?.serverId, 'server-task-delete-success');
    expect(taskState?.serverVersion, 51);
    expect(eventState?.syncState, SyncState.synced);
    expect(eventState?.serverId, 'server-event-delete-success');
    expect(eventState?.serverVersion, 61);
  });

  test('createTask without uid rethrows failure without local cache changes',
      () async {
    final harness = _Harness((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.keys, <String>['taskListId', 'uid']);
      expect(body['taskListId'], _fixtureTaskListId);
      expect(body['uid'], isA<String>());
      expect((body['uid'] as String), isNotEmpty);
      return http.Response('offline', 503);
    });
    await harness.setUp();
    addTearDown(harness.dispose);

    await expectLater(
      harness.store.createTask(<String, Object?>{
        'taskListId': harness.taskListId,
      }),
      throwsA(isA<Object>()),
    );

    expect(await harness.db.select(harness.db.taskItems).get(), isEmpty);
    expect(await harness.mutationStore.listPending(), isEmpty);
  });

  test('updateLocalEvent failure leaves nullable patch out of local cache',
      () async {
    final harness = _Harness((request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/client/events/server-event-retry');
      expect(
        jsonDecode(request.body),
        containsPair('baseServerVersion', 8),
      );
      return http.Response('conflict', 409);
    });
    await harness.setUp();
    addTearDown(harness.dispose);
    final localId = await harness.db.into(harness.db.calendarEvents).insert(
          fixtureEvent(
            uid: 'event-retry-uid',
            summary: 'Before retry',
            calendarId: harness.calendarId,
          ),
        );
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.calendarEvent.key,
      localId: localId.toString(),
      serverId: 'server-event-retry',
      serverVersion: 8,
      uid: 'event-retry-uid',
    );
    final eventBefore = await (harness.db.select(harness.db.calendarEvents)
          ..where((row) => row.id.equals(localId)))
        .getSingle();

    await expectLater(
      harness.store.updateLocalEvent(
        localId: localId,
        patch: <String, Object?>{
          'summary': 'Retry event patch',
          'notes': null,
          'location': '',
          'startAt': '2026-06-10T11:00:00Z',
          'endAt': null,
          'eventCalendarId': null,
          'colorHex': '#123456',
          'blocking': true,
          'status': 'cancelled',
        },
        changedFields: const <String>[
          'summary',
          'notes',
          'location',
          'startAt',
          'endAt',
          'eventCalendarId',
          'colorHex',
          'blocking',
          'status',
        ],
      ),
      throwsA(isA<Object>()),
    );

    final event = await (harness.db.select(harness.db.calendarEvents)
          ..where((row) => row.id.equals(localId)))
        .getSingle();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.calendarEvent.key,
      localId: localId.toString(),
    );

    expect(event.summary, eventBefore.summary);
    expect(event.description, eventBefore.description);
    expect(event.location, eventBefore.location);
    expect(event.dtstart, eventBefore.dtstart);
    expect(event.dtend, eventBefore.dtend);
    expect(event.eventCalendarId, eventBefore.eventCalendarId);
    expect(event.colorHex, eventBefore.colorHex);
    expect(event.isBlock, eventBefore.isBlock);
    expect(event.status, eventBefore.status);
    expect(await harness.mutationStore.listPending(), isEmpty);
    expect(state?.syncState, SyncState.synced);
    expect(state?.serverId, 'server-event-retry');
  });

  test('local deletes rethrow failures without deleting rows or queueing',
      () async {
    final harness = _Harness((request) async {
      if (request.url.path.contains('/events/')) {
        return http.Response('event down', 503);
      }
      return http.Response('task down', 503);
    });
    await harness.setUp();
    addTearDown(harness.dispose);
    final taskId = await harness.db.into(harness.db.taskItems).insert(
          fixtureTask(
            uid: 'task-delete-order-uid',
            summary: 'Delete task in order',
            taskListId: harness.taskListId,
          ),
        );
    final eventId = await harness.db.into(harness.db.calendarEvents).insert(
          fixtureEvent(
            uid: 'event-delete-order-uid',
            summary: 'Delete event in order',
            calendarId: harness.calendarId,
          ),
        );
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.taskItem.key,
      localId: taskId.toString(),
      serverId: 'server-task-delete-order',
      serverVersion: 20,
      uid: 'task-delete-order-uid',
    );
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.calendarEvent.key,
      localId: eventId.toString(),
      serverId: 'server-event-delete-order',
      serverVersion: 21,
      uid: 'event-delete-order-uid',
    );

    await expectLater(
      harness.store.deleteLocalTask(localId: taskId),
      throwsA(isA<Object>()),
    );
    await expectLater(
      harness.store.deleteLocalEvent(localId: eventId),
      throwsA(isA<Object>()),
    );

    final mutations = await harness.mutationStore.listPending();
    final taskState = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: taskId.toString(),
    );
    final eventState = await harness.stateStore.getState(
      objectType: SyncObjectType.calendarEvent.key,
      localId: eventId.toString(),
    );

    expect(
      harness.requests.map((request) => '${request.method} ${request.path}'),
      <String>[
        'DELETE /api/client/tasks/server-task-delete-order',
        'DELETE /api/client/events/server-event-delete-order',
      ],
    );
    expect(mutations, isEmpty);
    expect(taskState?.syncState, SyncState.synced);
    expect(eventState?.syncState, SyncState.synced);
    expect(await harness.db.select(harness.db.taskItems).get(), hasLength(1));
    expect(
      await harness.db.select(harness.db.calendarEvents).get(),
      hasLength(1),
    );
  });
}

const _fixtureTaskListId = 1;
const _fixtureCalendarId = 1;

class _Harness {
  _Harness(this.handler);

  final Future<http.Response> Function(http.Request request) handler;
  final db = createTestDatabase();
  final requests = <_CapturedRequest>[];
  late final OfflineMutationStore mutationStore;
  late final SyncObjectStateStore stateStore;
  late final TaskEventServerFirstStore store;
  late final int taskListId;
  late final int calendarId;

  Future<void> setUp() async {
    taskListId = await insertFixtureTaskList(db);
    calendarId = await insertFixtureCalendar(db);
    mutationStore = OfflineMutationStore(db);
    stateStore = SyncObjectStateStore(db);
    final mutationCoordinator = MutationCoordinator(
      mutationStore: mutationStore,
    );
    final repository = ServerFirstRepository(
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
      mutationCoordinator: mutationCoordinator,
    );

    store = TaskEventServerFirstStore(
      repository: repository,
      mutationCoordinator: mutationCoordinator,
      stateStore: stateStore,
      database: db,
      taskRepository: TaskRepository(db),
      eventRepository: EventRepository(db),
    );
  }

  Future<void> dispose() => db.close();
}

class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.body,
  });

  factory _CapturedRequest.from(http.Request request) {
    return _CapturedRequest(
      method: request.method,
      path: request.url.path,
      query: Map<String, String>.from(request.url.queryParameters),
      body: request.body,
    );
  }

  final String method;
  final String path;
  final Map<String, String> query;
  final String body;
}
