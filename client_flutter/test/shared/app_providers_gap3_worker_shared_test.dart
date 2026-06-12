import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_binding.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('shared app provider bootstrap graph', () {
    test('initializes server-first providers through the overridden api client',
        () async {
      final harness = await _ProviderHarness.create();
      addTearDown(harness.dispose);

      final repository =
          await harness.container.read(serverFirstRepositoryProvider.future);
      await repository.tasks(q: 'gap3', limit: 1);

      final coordinator = harness.container.read(mutationCoordinatorProvider);
      await coordinator.enqueueBusinessMutation(
        objectType: 'task_item',
        action: OfflineMutationAction.update,
        payload: const <String, Object?>{
          'uid': 'queued-task',
          'summary': 'Queued provider mutation',
        },
      );

      await harness.waitForRequest('POST /api/sync/push');
      await pumpEventQueue(times: 5);

      final taskEventStore =
          await harness.container.read(taskEventServerFirstStoreProvider.future);
      expect(taskEventStore, isNotNull);

      final cloudDriveStore =
          await harness.container.read(cloudDriveServerFirstStoreProvider.future);
      await cloudDriveStore.roots(query: 'root');

      final schedulerStore =
          await harness.container.read(schedulerServerFirstStoreProvider.future);
      await schedulerStore.createDraftRun(
        startAt: DateTime.utc(2026, 6, 10, 9),
        endAt: DateTime.utc(2026, 6, 10, 17),
      );

      final understandingStore = await harness.container
          .read(activityUnderstandingServerFirstStoreProvider.future);
      await understandingStore.segments(status: 'candidate', limit: 1);

      expect(
        harness.requests.map((request) => request.signature),
        containsAll(<String>[
          'GET /api/client/tasks',
          'POST /api/sync/push',
          'GET /api/files/drive/roots',
          'POST /api/scheduler/runs',
          'GET /api/activity-understanding/segments',
        ]),
      );
    });

    test('surfaces api override failures from dependent future providers',
        () async {
      final db = createTestDatabase();
      final container = ProviderContainer(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          apiClientProvider.overrideWith(
            (ref) async => throw StateError('gap3 api unavailable'),
          ),
        ],
      );
      addTearDown(() async {
        container.dispose();
        await db.close();
      });

      await expectLater(
        container.read(serverFirstRepositoryProvider.future),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'gap3 api unavailable',
          ),
        ),
      );
    });
  });

  group('outlook provider fallback names', () {
    test('uses previous snapshot or remote calendar names when lists are hidden',
        () async {
      final harness = await _ProviderHarness.create();
      addTearDown(harness.dispose);

      final remoteFallbackList = await harness.createTaskList(
        'Archived remote fallback',
        archived: true,
      );
      final previousUnboundList = await harness.createTaskList(
        'Archived unbound fallback',
        archived: true,
      );
      final previousMovedList = await harness.createTaskList(
        'Archived moved fallback',
        archived: true,
      );

      final remoteFallbackTask = await harness.createTask(
        'remote-fallback-task',
        'Remote fallback task',
        remoteFallbackList,
      );
      final previousUnboundTask = await harness.createTask(
        'previous-unbound-task',
        'Previous unbound task',
        previousUnboundList,
      );
      final previousMovedTask = await harness.createTask(
        'previous-moved-task',
        'Previous moved task',
        previousMovedList,
      );

      await harness.saveTaskListBinding(
        remoteFallbackList,
        'calendar-remote-fallback',
        remoteName: 'Remote fallback calendar',
      );
      await harness.saveTaskListBinding(
        previousMovedList,
        'calendar-moved-current',
        remoteName: 'Current moved calendar',
      );

      await harness.saveMirrorBinding(
        taskId: remoteFallbackTask,
        taskListId: remoteFallbackList,
        remoteCalendarId: 'calendar-remote-fallback',
        remoteName: 'Remote fallback calendar',
        localSnapshotHash: 'stale-remote-fallback-hash',
      );
      await harness.saveMirrorBinding(
        taskId: previousUnboundTask,
        taskListId: previousUnboundList,
        remoteCalendarId: 'calendar-unbound-missing',
        remoteName: 'Missing binding calendar',
        localSnapshotJson: _previousTaskListJson('Previous unbound list'),
      );
      await harness.saveMirrorBinding(
        taskId: previousMovedTask,
        taskListId: previousMovedList,
        remoteCalendarId: 'calendar-moved-old',
        remoteName: 'Old moved calendar',
        localSnapshotJson: _previousTaskListJson('Previous moved list'),
      );

      final diagnostics = await harness.container.read(
        outlookTaskMirrorDiagnosticsProvider.future,
      );
      expect(diagnostics.activeBindings, 1);
      expect(diagnostics.localChangedSinceLastMirror, 1);
      expect(diagnostics.unboundTaskLists, 1);
      expect(diagnostics.movedTargets, 1);

      final summaries = await harness.container.read(
        outlookFieldConflictSummariesProvider.future,
      );

      final remoteFallback = summaries.singleWhere(
        (summary) => summary.taskSummary == 'Remote fallback task',
      );
      expect(remoteFallback.taskListName, 'Remote fallback calendar');
      expect(
        remoteFallback.conflictState,
        OutlookTaskMirrorConflictState.pendingLocalPush,
      );
      expect(remoteFallback.changedFields, isNotEmpty);

      final previousUnbound = summaries.singleWhere(
        (summary) => summary.taskSummary == 'Previous unbound task',
      );
      expect(previousUnbound.taskListName, 'Previous unbound list');
      expect(
        previousUnbound.conflictState,
        OutlookTaskMirrorConflictState.writeFailed,
      );
      expect(previousUnbound.canDetachMirror, isTrue);

      final previousMoved = summaries.singleWhere(
        (summary) => summary.taskSummary == 'Previous moved task',
      );
      expect(previousMoved.taskListName, 'Previous moved list');
      expect(
        previousMoved.conflictState,
        OutlookTaskMirrorConflictState.remoteChanged,
      );
      expect(previousMoved.canRecreateRemote, isTrue);
    });
  });
}

String _previousTaskListJson(String name) {
  return jsonEncode(<String, Object?>{
    'task_list_name': name,
  });
}

class _ProviderHarness {
  _ProviderHarness(this.db, this.container, this.requests);

  final AppDatabase db;
  final ProviderContainer container;
  final List<_RecordedRequest> requests;

  static Future<_ProviderHarness> create() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = createTestDatabase();
    final requests = <_RecordedRequest>[];
    final apiClient = ApiClient(
      baseUri: Uri.parse('http://flowplan.test/api'),
      tokenStore: AuthTokenStore(db),
      httpClient: MockClient((request) async {
        requests.add(_RecordedRequest(request));
        return http.Response(jsonEncode(_responseFor(request)), 200);
      }),
    );
    final container = ProviderContainer(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        apiClientProvider.overrideWith((ref) async => apiClient),
      ],
    );
    return _ProviderHarness(db, container, requests);
  }

  Future<int> createTaskList(
    String name, {
    bool archived = false,
  }) {
    return db.into(db.taskLists).insert(
          TaskListsCompanion.insert(
            name: name,
            createdAt: DateTime.utc(2026, 6, 10),
            isArchived: Value(archived),
          ),
        );
  }

  Future<int> createTask(
    String uid,
    String summary,
    int? taskListId,
  ) {
    return db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: uid,
            dtstamp: DateTime.utc(2026, 6, 10),
            summary: summary,
            taskListId: Value(taskListId),
            durationMinutes: const Value(60),
          ),
        );
  }

  Future<void> saveTaskListBinding(
    int taskListId,
    String remoteCalendarId, {
    required String remoteName,
  }) {
    return container
        .read(outlookSyncBindingsRepositoryProvider)
        .saveTaskListBinding(
          OutlookTaskListBinding(
            localTaskListId: taskListId,
            remoteCalendarId: remoteCalendarId,
            remoteCalendarName: remoteName,
            linkedAt: DateTime.utc(2026, 6, 10),
          ),
        );
  }

  Future<void> saveMirrorBinding({
    required int taskId,
    required int taskListId,
    required String remoteCalendarId,
    required String remoteName,
    String? localSnapshotHash,
    String? localSnapshotJson,
  }) {
    return container
        .read(outlookTaskMirrorRepositoryProvider)
        .saveTaskMirrorBinding(
          OutlookTaskMirrorBinding(
            localTaskId: taskId,
            localTaskListId: taskListId,
            remoteCalendarId: remoteCalendarId,
            remoteCalendarName: remoteName,
            remoteEventId: 'event-$taskId',
            syncedAt: DateTime.utc(2026, 6, 10),
            localSnapshotHash: localSnapshotHash,
            localSnapshotJson: localSnapshotJson,
          ),
        );
  }

  Future<void> waitForRequest(String signature) async {
    for (var i = 0; i < 20; i++) {
      if (requests.any((request) => request.signature == signature)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('Expected request $signature');
  }

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

Map<String, Object?> _responseFor(http.Request request) {
  switch (request.url.path) {
    case '/api/sync/push':
      return const <String, Object?>{
        'accepted': <Object?>[],
        'conflicts': <Object?>[],
        'rejected': <Object?>[],
      };
    case '/api/files/drive/roots':
      return const <String, Object?>{'roots': <Object?>[]};
    case '/api/scheduler/runs':
      return const <String, Object?>{'runId': 'run-gap3'};
    case '/api/activity-understanding/segments':
      return const <String, Object?>{'segments': <Object?>[]};
    default:
      return const <String, Object?>{'ok': true};
  }
}

class _RecordedRequest {
  _RecordedRequest(http.Request request)
      : method = request.method,
        path = request.url.path;

  final String method;
  final String path;

  String get signature => '$method $path';
}
