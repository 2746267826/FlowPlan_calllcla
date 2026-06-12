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
  test('createEvent queues pending create when server write fails', () async {
    final harness = _Harness((_) async => http.Response('server down', 503));
    await harness.setUp();
    addTearDown(harness.dispose);

    final result = await harness.store.createEvent(<String, Object?>{
      'uid': 'event-create-failure-uid',
      'summary': 'Offline event draft',
      'startAt': '2026-06-10T08:30:00Z',
      'eventCalendarId': harness.calendarId,
    });

    final events = await harness.db.select(harness.db.calendarEvents).get();
    final mutations = await harness.mutationStore.listPending();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.calendarEvent.key,
      localId: events.single.id.toString(),
    );

    expect(result.isPending, isTrue);
    expect(events.single.summary, 'Offline event draft');
    expect(
        events.single.dtstart.toUtc(), DateTime.parse('2026-06-10T08:30:00Z'));
    expect(mutations.single.objectType, SyncObjectType.calendarEvent.key);
    expect(mutations.single.localId, events.single.id.toString());
    expect(mutations.single.serverId, isNull);
    expect(mutations.single.action, OfflineMutationAction.create);
    expect(mutations.single.payloadJson, contains('Offline event draft'));
    expect(
      jsonDecode(mutations.single.changedFieldsJson!),
      containsAll(<String>['uid', 'summary', 'startAt', 'eventCalendarId']),
    );
    expect(state?.syncState, SyncState.pendingCreate);
    expect(state?.uid, 'event-create-failure-uid');
    expect(state?.serverId, isNull);
  });

  test('updateLocalTask without server id updates locally and queues only',
      () async {
    final requests = <http.Request>[];
    final harness = _Harness((request) async {
      requests.add(request);
      return http.Response('unexpected remote call', 500);
    });
    await harness.setUp();
    addTearDown(harness.dispose);
    final localId = await harness.db.into(harness.db.taskItems).insert(
          fixtureTask(
            uid: 'task-no-server-uid',
            summary: 'Local task before edit',
            taskListId: harness.taskListId,
          ),
        );

    final result = await harness.store.updateLocalTask(
      localId: localId,
      patch: <String, Object?>{
        'summary': 'Local task after edit',
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

    expect(requests, isEmpty);
    expect(result.isPending, isTrue);
    expect(updatedTask.summary, 'Local task after edit');
    expect(updatedTask.status, 'COMPLETED');
    expect(updatedTask.percentComplete, 100);
    expect(mutations.single.objectType, SyncObjectType.taskItem.key);
    expect(mutations.single.localId, localId.toString());
    expect(mutations.single.serverId, isNull);
    expect(mutations.single.action, OfflineMutationAction.update);
    expect(
      jsonDecode(mutations.single.changedFieldsJson!),
      <String>['summary', 'status'],
    );
    expect(mutations.single.payloadJson, contains('Local task after edit'));
    expect(state?.syncState, SyncState.pendingUpdate);
    expect(state?.serverId, isNull);
  });

  test('updateLocalEvent with server id applies canonical remote payload',
      () async {
    final requests = <http.Request>[];
    final harness = _Harness((request) async {
      requests.add(request);
      expect(request.method, 'PATCH');
      expect(request.url.path, '/api/client/events/server-event-update');
      expect(
        jsonDecode(request.body),
        containsPair('baseServerVersion', 22),
      );
      return http.Response(
        jsonEncode(<String, Object?>{
          'serverVersion': 23,
          'item': <String, Object?>{
            'id': 'server-event-update',
            'uid': 'event-update-success-uid',
            'payload': <String, Object?>{
              'summary': 'Canonical remote event',
              'startAt': '2026-06-10T11:00:00Z',
              'endAt': '2026-06-10T11:45:00Z',
              'status': 'tentative',
              'eventCalendarId': 1,
            },
          },
        }),
        200,
      );
    });
    await harness.setUp();
    addTearDown(harness.dispose);
    final localId = await harness.db.into(harness.db.calendarEvents).insert(
          fixtureEvent(
            uid: 'event-update-success-uid',
            summary: 'Event before server edit',
            calendarId: harness.calendarId,
          ),
        );
    await harness.stateStore.markSynced(
      objectType: SyncObjectType.calendarEvent.key,
      localId: localId.toString(),
      serverId: 'server-event-update',
      serverVersion: 22,
      uid: 'event-update-success-uid',
    );

    final result = await harness.store.updateLocalEvent(
      localId: localId,
      patch: <String, Object?>{
        'summary': 'Client event edit',
        'status': 'cancelled',
      },
      changedFields: const <String>['summary', 'status'],
    );

    final updatedEvent = await (harness.db.select(harness.db.calendarEvents)
          ..where((row) => row.id.equals(localId)))
        .getSingle();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.calendarEvent.key,
      localId: localId.toString(),
    );

    expect(requests, hasLength(1));
    expect(result.isCanonical, isTrue);
    expect(updatedEvent.summary, 'Canonical remote event');
    expect(
        updatedEvent.dtstart.toUtc(), DateTime.parse('2026-06-10T11:00:00Z'));
    expect(updatedEvent.dtend?.toUtc(), DateTime.parse('2026-06-10T11:45:00Z'));
    expect(updatedEvent.status, 'tentative');
    expect(await harness.mutationStore.listPending(), isEmpty);
    expect(state?.syncState, SyncState.synced);
    expect(state?.serverId, 'server-event-update');
    expect(state?.serverVersion, 23);
    expect(state?.uid, 'event-update-success-uid');
  });

  test('deleteLocalEvent without server id deletes locally and queues only',
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
            uid: 'event-delete-local-uid',
            summary: 'Local event to delete',
            calendarId: harness.calendarId,
          ),
        );

    final result = await harness.store.deleteLocalEvent(localId: localId);

    final remainingEvents =
        await harness.db.select(harness.db.calendarEvents).get();
    final mutations = await harness.mutationStore.listPending();
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.calendarEvent.key,
      localId: localId.toString(),
    );

    expect(requests, isEmpty);
    expect(result.isPending, isTrue);
    expect(remainingEvents.where((event) => event.id == localId), isEmpty);
    expect(mutations.single.objectType, SyncObjectType.calendarEvent.key);
    expect(mutations.single.localId, localId.toString());
    expect(mutations.single.serverId, isNull);
    expect(mutations.single.action, OfflineMutationAction.delete);
    expect(mutations.single.payloadJson, contains(localId.toString()));
    expect(state?.syncState, SyncState.pendingDelete);
    expect(state?.serverId, isNull);
  });

  test('queueLegacyCacheMutation marks pending state for each action',
      () async {
    final harness = _Harness((_) async => http.Response('unused', 500));
    await harness.setUp();
    addTearDown(harness.dispose);

    await harness.store.queueLegacyCacheMutation(
      objectType: SyncObjectType.taskItem.key,
      localId: 'local-create',
      action: OfflineMutationAction.create,
      payload: <String, Object?>{'uid': 'legacy-create-uid'},
    );
    await harness.store.queueLegacyCacheMutation(
      objectType: SyncObjectType.taskItem.key,
      localId: 'local-update',
      serverId: 'server-update',
      action: OfflineMutationAction.update,
      payload: <String, Object?>{'uid': 'legacy-update-uid'},
    );
    await harness.store.queueLegacyCacheMutation(
      objectType: SyncObjectType.taskItem.key,
      localId: 'local-delete',
      serverId: 'server-delete',
      action: OfflineMutationAction.delete,
      payload: <String, Object?>{'uid': 'legacy-delete-uid'},
    );

    final createState = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: 'local-create',
    );
    final updateState = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: 'local-update',
    );
    final deleteState = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: 'local-delete',
    );
    final mutations = await harness.mutationStore.listPending();

    expect(mutations, hasLength(3));
    expect(createState?.syncState, SyncState.pendingCreate);
    expect(createState?.uid, 'legacy-create-uid');
    expect(updateState?.syncState, SyncState.pendingUpdate);
    expect(updateState?.serverId, 'server-update');
    expect(updateState?.uid, 'legacy-update-uid');
    expect(deleteState?.syncState, SyncState.pendingDelete);
    expect(deleteState?.serverId, 'server-delete');
    expect(deleteState?.uid, 'legacy-delete-uid');
  });
}

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
