import 'dart:convert';

import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
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

  test('createTask queues pending mutation when server write fails', () async {
    final harness = _Harness((_) async => http.Response('server down', 503));
    await harness.setUp();
    addTearDown(harness.dispose);

    final result = await harness.store.createTask(<String, Object?>{
      'uid': 'task-uid-2',
      'summary': 'Offline draft',
      'taskListId': harness.taskListId,
    });

    final tasks = await harness.db.select(harness.db.taskItems).get();
    final mutations = await harness.mutationStore.listPending();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: tasks.single.id.toString(),
    );

    expect(result.isPending, isTrue);
    expect(tasks.single.summary, 'Offline draft');
    expect(mutations.single.objectType, SyncObjectType.taskItem.key);
    expect(mutations.single.localId, tasks.single.id.toString());
    expect(mutations.single.action, OfflineMutationAction.create);
    expect(mutations.single.payloadJson, contains('Offline draft'));
    expect(state?.syncState, SyncState.pendingCreate);
    expect(state?.uid, 'task-uid-2');
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

  test(
      'updateLocalEvent queues locally without a remote call when server id is missing',
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

    final result = await harness.store.updateLocalEvent(
      localId: localId,
      patch: <String, Object?>{
        'summary': 'Queued event edit',
        'status': 'cancelled',
      },
      changedFields: const <String>['summary', 'status'],
    );

    final updatedEvent = await (harness.db.select(harness.db.calendarEvents)
          ..where((row) => row.id.equals(localId)))
        .getSingle();
    final mutations = await harness.mutationStore.listPending();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.calendarEvent.key,
      localId: localId.toString(),
    );

    expect(requests, isEmpty);
    expect(result.isPending, isTrue);
    expect(updatedEvent.summary, 'Queued event edit');
    expect(updatedEvent.status, 'cancelled');
    expect(mutations.single.objectType, SyncObjectType.calendarEvent.key);
    expect(mutations.single.localId, localId.toString());
    expect(mutations.single.serverId, isNull);
    expect(mutations.single.action, OfflineMutationAction.update);
    expect(
      jsonDecode(mutations.single.changedFieldsJson!),
      <String>['summary', 'status'],
    );
    expect(mutations.single.payloadJson, contains('Queued event edit'));
    expect(state?.syncState, SyncState.pendingUpdate);
    expect(state?.serverId, isNull);
  });

  test('updateLocalTask queues pending mutation after server write fails',
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

    final result = await harness.store.updateLocalTask(
      localId: localId,
      patch: <String, Object?>{
        'summary': 'Queued local edit',
        'status': 'done',
      },
      changedFields: const <String>['summary', 'status'],
    );

    final updatedTask = await (harness.db.select(harness.db.taskItems)
          ..where((row) => row.id.equals(localId)))
        .getSingle();
    final mutations = await harness.mutationStore.listPending();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
    );

    expect(requests, hasLength(1));
    expect(requests.single.method, 'PATCH');
    expect(requests.single.url.path, '/api/client/tasks/server-task-3');
    expect(jsonDecode(requests.single.body),
        containsPair('baseServerVersion', 11));
    expect(result.isPending, isTrue);
    expect(updatedTask.summary, 'Queued local edit');
    expect(updatedTask.status, 'COMPLETED');
    expect(updatedTask.percentComplete, 100);
    expect(mutations.single.objectType, SyncObjectType.taskItem.key);
    expect(mutations.single.localId, localId.toString());
    expect(mutations.single.serverId, 'server-task-3');
    expect(mutations.single.action, OfflineMutationAction.update);
    expect(mutations.single.baseServerVersion, 11);
    expect(
      jsonDecode(mutations.single.changedFieldsJson!),
      <String>['summary', 'status'],
    );
    expect(mutations.single.payloadJson, contains('Queued local edit'));
    expect(state?.syncState, SyncState.pendingUpdate);
    expect(state?.serverId, 'server-task-3');
    expect(state?.uid, 'task-uid-3');
  });

  test('deleteLocalTask queues pending mutation after server delete fails',
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

    final result = await harness.store.deleteLocalTask(localId: localId);

    final remainingTasks = await harness.db.select(harness.db.taskItems).get();
    final mutations = await harness.mutationStore.listPending();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: localId.toString(),
    );

    expect(requests, hasLength(1));
    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.path, '/api/client/tasks/server-task-4');
    expect(result.isPending, isTrue);
    expect(remainingTasks.where((task) => task.id == localId), isEmpty);
    expect(mutations.single.objectType, SyncObjectType.taskItem.key);
    expect(mutations.single.localId, localId.toString());
    expect(mutations.single.serverId, 'server-task-4');
    expect(mutations.single.action, OfflineMutationAction.delete);
    expect(mutations.single.baseServerVersion, 13);
    expect(mutations.single.payloadJson, contains('task-uid-4'));
    expect(state?.syncState, SyncState.pendingDelete);
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
