import 'dart:convert';

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
  test('createTask stores canonical server payload locally and marks it synced',
      () async {
    final harness = _Harness((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/client/tasks');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['uid'], 'task-uid-1');
      expect(body['summary'], 'Draft tests');
      return http.Response(
        jsonEncode(<String, Object?>{
          'serverVersion': 7,
          'item': <String, Object?>{
            'id': 'server-task-1',
            'uid': 'task-uid-1',
            'payload': <String, Object?>{
              'summary': 'Canonical tests',
              'taskListId': harnessTaskListId,
              'status': 'done',
            },
          },
        }),
        201,
      );
    });
    await harness.setUp();
    addTearDown(harness.dispose);

    final result = await harness.store.createTask(<String, Object?>{
      'uid': 'task-uid-1',
      'summary': 'Draft tests',
      'taskListId': harness.taskListId,
    });

    final tasks = await harness.db.select(harness.db.taskItems).get();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: tasks.single.id.toString(),
    );

    expect(result.isCanonical, isTrue);
    expect(tasks.single.summary, 'Canonical tests');
    expect(tasks.single.status, 'COMPLETED');
    expect(state?.syncState, SyncState.synced);
    expect(state?.serverId, 'server-task-1');
    expect(state?.serverVersion, 7);
    expect(await harness.mutationStore.listPending(), isEmpty);
  });

  test('createTask rethrows server failure without changing local cache',
      () async {
    final harness = _Harness((_) async => http.Response('server down', 503));
    await harness.setUp();
    addTearDown(harness.dispose);

    await expectLater(
      harness.store.createTask(<String, Object?>{
        'uid': 'task-uid-2',
        'summary': 'Offline draft',
        'taskListId': harness.taskListId,
      }),
      throwsA(isA<Object>()),
    );

    expect(await harness.db.select(harness.db.taskItems).get(), isEmpty);
    expect(await harness.mutationStore.listPending(), isEmpty);
  });

  test(
      'createEvent stores canonical server payload locally and marks it synced',
      () async {
    final harness = _Harness((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/api/client/events');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['uid'], 'event-uid-1');
      expect(body['summary'], 'Draft event');
      return http.Response(
        jsonEncode(<String, Object?>{
          'serverVersion': 9,
          'item': <String, Object?>{
            'id': 'server-event-1',
            'uid': 'event-uid-1',
            'payload': <String, Object?>{
              'summary': 'Canonical event',
              'startAt': '2026-06-10T09:00:00Z',
              'endAt': '2026-06-10T10:00:00Z',
              'eventCalendarId': harnessCalendarId,
              'status': 'tentative',
              'source': 'server',
            },
          },
        }),
        201,
      );
    });
    await harness.setUp();
    addTearDown(harness.dispose);

    final result = await harness.store.createEvent(<String, Object?>{
      'uid': 'event-uid-1',
      'summary': 'Draft event',
      'startAt': '2026-06-10T08:00:00Z',
      'eventCalendarId': harness.calendarId,
    });

    final events = await harness.db.select(harness.db.calendarEvents).get();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.calendarEvent.key,
      localId: events.single.id.toString(),
    );

    expect(result.isCanonical, isTrue);
    expect(events.single.summary, 'Canonical event');
    expect(
      events.single.dtstart.toUtc(),
      DateTime.parse('2026-06-10T09:00:00Z'),
    );
    expect(
      events.single.dtend?.toUtc(),
      DateTime.parse('2026-06-10T10:00:00Z'),
    );
    expect(events.single.status, 'tentative');
    expect(state?.syncState, SyncState.synced);
    expect(state?.serverId, 'server-event-1');
    expect(state?.serverVersion, 9);
    expect(await harness.mutationStore.listPending(), isEmpty);
  });

  test('updateLocalEvent without server id throws without local cache changes',
      () async {
    final requests = <http.Request>[];
    final harness = _Harness((request) async {
      requests.add(request);
      return http.Response('unexpected remote call', 500);
    });
    await harness.setUp();
    addTearDown(harness.dispose);
    final localId = await harness.db.into(harness.db.calendarEvents).insert(
          fixtureEvent(
            uid: 'event-uid-2',
            summary: 'Local-only event',
            calendarId: harness.calendarId,
          ),
        );
    final eventBefore = await (harness.db.select(harness.db.calendarEvents)
          ..where((row) => row.id.equals(localId)))
        .getSingle();

    await expectLater(
      harness.store.updateLocalEvent(
        localId: localId,
        patch: <String, Object?>{
          'summary': 'Queued event edit',
          'status': 'cancelled',
        },
        changedFields: const <String>['summary', 'status'],
      ),
      throwsA(isA<StateError>()),
    );

    final eventAfter = await (harness.db.select(harness.db.calendarEvents)
          ..where((row) => row.id.equals(localId)))
        .getSingle();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.calendarEvent.key,
      localId: localId.toString(),
    );

    expect(requests, isEmpty);
    expect(eventAfter.summary, eventBefore.summary);
    expect(eventAfter.status, eventBefore.status);
    expect(await harness.mutationStore.listPending(), isEmpty);
    expect(state, isNull);
  });

  test('updateLocalTask rethrows server failure without changing local cache',
      () async {
    final requests = <http.Request>[];
    final harness = _Harness((request) async {
      requests.add(request);
      return http.Response('conflict', 409);
    });
    await harness.setUp();
    addTearDown(harness.dispose);
    final localId = await harness.db.into(harness.db.taskItems).insert(
          fixtureTask(
            uid: 'task-uid-3',
            summary: 'Before server failure',
            taskListId: harness.taskListId,
          ),
        );
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
      serverId: 'server-task-3',
      serverVersion: 11,
      uid: 'task-uid-3',
    );
    final taskBefore = await (harness.db.select(harness.db.taskItems)
          ..where((row) => row.id.equals(localId)))
        .getSingle();

    await expectLater(
      harness.store.updateLocalTask(
        localId: localId,
        patch: <String, Object?>{
          'summary': 'Queued local edit',
          'status': 'done',
        },
        changedFields: const <String>['summary', 'status'],
      ),
      throwsA(isA<Object>()),
    );

    final taskAfter = await (harness.db.select(harness.db.taskItems)
          ..where((row) => row.id.equals(localId)))
        .getSingle();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
    );

    expect(requests, hasLength(1));
    expect(requests.single.method, 'PATCH');
    expect(requests.single.url.path, '/api/client/tasks/server-task-3');
    expect(jsonDecode(requests.single.body),
        containsPair('baseServerVersion', 11));
    expect(taskAfter.summary, taskBefore.summary);
    expect(taskAfter.status, taskBefore.status);
    expect(taskAfter.percentComplete, taskBefore.percentComplete);
    expect(await harness.mutationStore.listPending(), isEmpty);
    expect(state?.syncState, SyncState.synced);
    expect(state?.serverId, 'server-task-3');
    expect(state?.uid, 'task-uid-3');
  });

  test('updateLocalTask writes completedAt from canonical payload', () async {
    final harness = _Harness((request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/client/tasks/server-task-complete');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['completedAt'], '2026-06-10T12:00:00Z');
      return http.Response(
        jsonEncode(<String, Object?>{
          'serverVersion': 12,
          'item': <String, Object?>{
            'id': 'server-task-complete',
            'uid': 'task-uid-complete',
            'payload': <String, Object?>{
              'summary': 'Completed canonical task',
              'completedAt': '2026-06-10T12:00:00Z',
              'status': 'done',
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
            uid: 'task-uid-complete',
            summary: 'Before completion',
            taskListId: harness.taskListId,
          ),
        );
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
      serverId: 'server-task-complete',
      serverVersion: 11,
      uid: 'task-uid-complete',
    );

    final result = await harness.store.updateLocalTask(
      localId: localId,
      patch: <String, Object?>{
        'completedAt': '2026-06-10T12:00:00Z',
      },
      changedFields: const <String>['completedAt'],
    );

    final taskAfter = await (harness.db.select(harness.db.taskItems)
          ..where((row) => row.id.equals(localId)))
        .getSingle();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
    );

    expect(result.isCanonical, isTrue);
    expect(taskAfter.summary, 'Completed canonical task');
    expect(
      taskAfter.completed?.toUtc(),
      DateTime.parse('2026-06-10T12:00:00Z'),
    );
    expect(taskAfter.status, 'COMPLETED');
    expect(state?.serverVersion, 12);
  });

  test('deleteLocalTask rethrows server failure without deleting local cache',
      () async {
    final requests = <http.Request>[];
    final harness = _Harness((request) async {
      requests.add(request);
      return http.Response('server down', 503);
    });
    await harness.setUp();
    addTearDown(harness.dispose);
    final localId = await harness.db.into(harness.db.taskItems).insert(
          fixtureTask(
            uid: 'task-uid-4',
            summary: 'Delete me later',
            taskListId: harness.taskListId,
          ),
        );
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
      serverId: 'server-task-4',
      serverVersion: 13,
      uid: 'task-uid-4',
    );

    await expectLater(
      harness.store.deleteLocalTask(localId: localId),
      throwsA(isA<Object>()),
    );

    final remainingTasks = await harness.db.select(harness.db.taskItems).get();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
    );

    expect(requests, hasLength(1));
    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.path, '/api/client/tasks/server-task-4');
    expect(remainingTasks.where((task) => task.id == localId), hasLength(1));
    expect(await harness.mutationStore.listPending(), isEmpty);
    expect(state?.syncState, SyncState.synced);
    expect(state?.serverId, 'server-task-4');
    expect(state?.uid, 'task-uid-4');
  });
}

const harnessTaskListId = 1;
const harnessCalendarId = 1;

class _Harness {
  _Harness(this.handler);

  final Future<http.Response> Function(http.Request request) handler;
  final db = createTestDatabase();
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
          httpClient: MockClient(handler),
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
