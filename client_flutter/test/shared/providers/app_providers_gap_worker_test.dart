import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_snapshot.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('client bootstrap and file context providers', () {
    test(
        'bootstrap service lazy-loads sync and tracking through provider graph',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final db = createTestDatabase();
      addTearDown(db.close);
      final requests = <_RecordedRequest>[];
      final container = _createContainer(db: db, requests: requests);
      addTearDown(container.dispose);

      final service =
          await container.read(clientBootstrapServiceProvider.future);

      await service.bootstrapAndSync(source: 'gap-worker');

      expect(
          requests.map((request) => request.signature),
          containsAll(<String>[
            'GET /api/client/bootstrap',
            'GET /api/client/settings',
            'GET /api/sync/pull',
          ]));
      expect(service.state.lastError, null);
    });

    test('file context interaction service uses the file context API loader',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final requests = <_RecordedRequest>[];
      final container = _createContainer(db: db, requests: requests);
      addTearDown(container.dispose);

      final service = container.read(fileContextInteractionServiceProvider);

      final now = DateTime.utc(2026, 6, 10);
      final result = await service.openNodeWithPlan(
        FileNode(
          id: 1,
          nodeUid: 'node-uid-1',
          remoteId: 'node-1',
          rootFolderId: 1,
          parentNodeId: null,
          itemType: FileNodeType.file,
          displayName: 'notes.md',
          localPath: '',
          relativePath: 'notes.md',
          mimeType: 'text/markdown',
          sizeBytes: 12,
          modifiedAt: now,
          availability: 'remote',
          scanBatchId: 'scan-1',
          depth: 0,
          hashSha256: null,
          storageObjectId: 'storage-1',
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(result.action, 'download_then_open');
      expect(
        requests.map((request) => request.signature),
        contains('POST /api/files/drive/nodes/node-1/open-plan'),
      );
    });
  });

  group('outlook diagnostics providers', () {
    test('count missing, unbound, moved, and locally changed mirror bindings',
        () async {
      final harness = await _OutlookHarness.create();
      addTearDown(harness.dispose);

      final activeList = await harness.createTaskList('Active list');
      final unboundList = await harness.createTaskList('Unbound list');
      final movedList = await harness.createTaskList('Moved list');
      final orphanList = await harness.createTaskList('Orphan list');
      final activeTask = await harness.createTask(
        'active-task',
        'Active changed',
        activeList,
      );
      final unboundTask = await harness.createTask(
        'unbound-task',
        'Unbound task',
        unboundList,
      );
      final movedTask = await harness.createTask(
        'moved-task',
        'Moved task',
        movedList,
      );
      final noListTask = await harness.createTask(
        'no-list-task',
        'No list task',
        null,
      );

      await harness.saveTaskListBinding(activeList, 'calendar-active');
      await harness.saveTaskListBinding(movedList, 'calendar-new');
      await harness.saveMirrorBinding(
        taskId: activeTask,
        taskListId: activeList,
        remoteCalendarId: 'calendar-active',
        localSnapshotJson: jsonEncode(<String, Object?>{
          'task_list_name': 'Previous active list',
          'summary': 'Old active title',
        }),
        localSnapshotHash: 'old-active-hash',
      );
      await harness.saveMirrorBinding(
        taskId: unboundTask,
        taskListId: unboundList,
        remoteCalendarId: 'calendar-unbound',
      );
      await harness.saveMirrorBinding(
        taskId: movedTask,
        taskListId: movedList,
        remoteCalendarId: 'calendar-old',
      );
      await harness.saveMirrorBinding(
        taskId: noListTask,
        taskListId: orphanList,
        remoteCalendarId: 'calendar-orphan',
      );
      await harness.saveMirrorBinding(
        taskId: 99999,
        taskListId: orphanList,
        remoteCalendarId: 'calendar-missing',
        localSnapshotJson: jsonEncode(<String, Object?>{
          'task_list_name': 'Missing previous list',
        }),
      );

      final diagnostics = await harness.container.read(
        outlookTaskMirrorDiagnosticsProvider.future,
      );

      expect(diagnostics.totalBindings, 5);
      expect(diagnostics.activeBindings, 1);
      expect(diagnostics.pendingCleanup, 4);
      expect(diagnostics.missingTasks, 2);
      expect(diagnostics.unboundTaskLists, 1);
      expect(diagnostics.movedTargets, 1);
      expect(diagnostics.localChangedSinceLastMirror, 1);
      expect(diagnostics.hasPendingCleanup, isTrue);
    });

    test('summaries include cleanup cases and filter clean bindings', () async {
      final harness = await _OutlookHarness.create();
      addTearDown(harness.dispose);

      final activeList = await harness.createTaskList('Active list');
      final unboundList = await harness.createTaskList('Unbound list');
      final movedList = await harness.createTaskList('Moved list');
      final activeTask = await harness.createTask(
        'active-task',
        'Clean task',
        activeList,
      );
      final dirtyTask = await harness.createTask(
        'dirty-task',
        'Dirty task',
        activeList,
      );
      final unboundTask = await harness.createTask(
        'unbound-task',
        'Unbound task',
        unboundList,
      );
      final movedTask = await harness.createTask(
        'moved-task',
        'Moved task',
        movedList,
      );
      final noListTask = await harness.createTask(
        'no-list-task',
        'No list task',
        null,
      );

      await harness.saveTaskListBinding(activeList, 'calendar-active');
      await harness.saveTaskListBinding(movedList, 'calendar-new');
      final cleanSnapshot =
          await harness.snapshotFor(activeTask, 'Active list');
      await harness.saveMirrorBinding(
        taskId: activeTask,
        taskListId: activeList,
        remoteCalendarId: 'calendar-active',
        localSnapshotJson: cleanSnapshot.stableJson,
        localSnapshotHash: cleanSnapshot.fingerprint,
      );
      await harness.saveMirrorBinding(
        taskId: dirtyTask,
        taskListId: activeList,
        remoteCalendarId: 'calendar-active',
        localSnapshotJson: jsonEncode(<String, Object?>{
          'task_list_name': 'Previous active list',
          'summary': 'Dirty before edit',
        }),
        localSnapshotHash: 'stale-hash',
      );
      await harness.saveMirrorBinding(
        taskId: unboundTask,
        taskListId: unboundList,
        remoteCalendarId: 'calendar-unbound',
      );
      await harness.saveMirrorBinding(
        taskId: movedTask,
        taskListId: movedList,
        remoteCalendarId: 'calendar-old',
      );
      await harness.saveMirrorBinding(
        taskId: noListTask,
        taskListId: activeList,
        remoteCalendarId: 'calendar-active',
        localSnapshotJson: jsonEncode(<String, Object?>{
          'task_list_name': 'Previous no-list',
        }),
      );
      await harness.saveMirrorBinding(
        taskId: 88888,
        taskListId: activeList,
        remoteCalendarId: 'calendar-active',
        localSnapshotJson: jsonEncode(<String, Object?>{
          'task_list_name': 'Missing previous list',
        }),
      );

      final summaries = await harness.container.read(
        outlookFieldConflictSummariesProvider.future,
      );

      expect(
          summaries.map((summary) => summary.taskSummary),
          isNot(
            contains('Clean task'),
          ));
      final dirty = summaries.singleWhere(
        (summary) => summary.taskSummary == 'Dirty task',
      );
      expect(
          dirty.conflictState, OutlookTaskMirrorConflictState.pendingLocalPush);
      expect(dirty.taskListName, 'Active list');
      expect(dirty.changedFields, isNotEmpty);
      expect(dirty.canPushLocal, isTrue);
      expect(dirty.canPullRemote, isFalse);

      final noList = summaries.singleWhere(
        (summary) => summary.taskSummary == 'No list task',
      );
      expect(noList.conflictState, OutlookTaskMirrorConflictState.writeFailed);
      expect(noList.taskListName, 'Previous no-list');
      expect(noList.canDetachMirror, isTrue);

      final unbound = summaries.singleWhere(
        (summary) => summary.taskSummary == 'Unbound task',
      );
      expect(unbound.conflictState, OutlookTaskMirrorConflictState.writeFailed);
      expect(unbound.taskListName, 'Unbound list');
      expect(unbound.canPushLocal, isFalse);

      final moved = summaries.singleWhere(
        (summary) => summary.taskSummary == 'Moved task',
      );
      expect(moved.conflictState, OutlookTaskMirrorConflictState.remoteChanged);
      expect(moved.canPushLocal, isTrue);
      expect(moved.canRecreateRemote, isTrue);

      final missing =
          summaries.singleWhere((summary) => summary.taskId == 88888);
      expect(
          missing.conflictState, OutlookTaskMirrorConflictState.remoteDeleted);
      expect(missing.taskListName, 'Missing previous list');
      expect(missing.canDetachMirror, isTrue);
    });

    test('summaries expose stored remote conflict states and field diffs',
        () async {
      final harness = await _OutlookHarness.create();
      addTearDown(harness.dispose);

      final listId = await harness.createTaskList('Conflict list');
      final remoteChangedTask = await harness.createTask(
        'remote-changed',
        'Remote changed task',
        listId,
      );
      final divergentTask = await harness.createTask(
        'divergent',
        'Divergent task',
        listId,
      );
      final failedTask = await harness.createTask(
        'failed',
        'Failed task',
        listId,
      );
      final deletedTask = await harness.createTask(
        'deleted',
        'Deleted task',
        listId,
      );

      await harness.saveTaskListBinding(listId, 'calendar-conflict');
      await harness.saveConflictMirror(
        taskId: remoteChangedTask,
        taskListId: listId,
        state: OutlookTaskMirrorConflictState.remoteChanged,
        leftSummary: 'Before remote',
        rightSummary: 'After remote',
        message: 'remote edited',
      );
      await harness.saveConflictMirror(
        taskId: divergentTask,
        taskListId: listId,
        state: OutlookTaskMirrorConflictState.divergent,
        leftSummary: 'Before divergent',
        rightSummary: 'After divergent',
        message: 'both edited',
      );
      await harness.saveConflictMirror(
        taskId: failedTask,
        taskListId: listId,
        state: OutlookTaskMirrorConflictState.writeFailed,
        leftSummary: 'Failed before edit',
        message: 'write failed',
      );
      await harness.saveConflictMirror(
        taskId: deletedTask,
        taskListId: listId,
        state: OutlookTaskMirrorConflictState.remoteDeleted,
        leftSummary: 'Deleted before edit',
        message: 'remote deleted',
      );

      final summaries = await harness.container.read(
        outlookFieldConflictSummariesProvider.future,
      );

      final remoteChanged = summaries.singleWhere(
        (summary) => summary.taskSummary == 'Remote changed task',
      );
      expect(remoteChanged.conflictState,
          OutlookTaskMirrorConflictState.remoteChanged);
      expect(remoteChanged.detail, 'remote edited');
      expect(remoteChanged.changedFields, isNotEmpty);
      expect(remoteChanged.canPullRemote, isTrue);

      final divergent = summaries.singleWhere(
        (summary) => summary.taskSummary == 'Divergent task',
      );
      expect(divergent.conflictState, OutlookTaskMirrorConflictState.divergent);
      expect(divergent.detail, 'both edited');
      expect(divergent.canPushLocal, isTrue);
      expect(divergent.canPullRemote, isTrue);

      final failed = summaries.singleWhere(
        (summary) => summary.taskSummary == 'Failed task',
      );
      expect(failed.conflictState, OutlookTaskMirrorConflictState.writeFailed);
      expect(failed.detail, 'write failed');
      expect(failed.changedFields, isNotEmpty);

      final deleted = summaries.singleWhere(
        (summary) => summary.taskSummary == 'Deleted task',
      );
      expect(
          deleted.conflictState, OutlookTaskMirrorConflictState.remoteDeleted);
      expect(deleted.detail, 'remote deleted');
      expect(deleted.canRecreateRemote, isTrue);
    });
  });

  group('selected date stream providers', () {
    test('emit tasks and schedule segments for the selected date', () async {
      final harness = await _OutlookHarness.create();
      addTearDown(harness.dispose);

      final listId = await harness.createTaskList('Today list');
      final today = DateTime(2026, 6, 10);
      final taskId = await harness.createTask(
        'today-task',
        'Today task',
        listId,
        start: DateTime(2026, 6, 10, 9),
      );
      await harness.createTask(
        'tomorrow-task',
        'Tomorrow task',
        listId,
        start: DateTime(2026, 6, 11, 9),
      );
      await harness.container
          .read(taskScheduleSegmentRepositoryProvider)
          .replaceForTasks(
            taskIds: <int>{taskId},
            segments: <TaskScheduleSegmentDraft>[
              TaskScheduleSegmentDraft(
                taskId: taskId,
                segmentIndex: 0,
                startAt: DateTime(2026, 6, 10, 10),
                endAt: DateTime(2026, 6, 10, 11),
                source: 'test',
                planRunId: 'plan-1',
              ),
            ],
            actor: 'test',
            summary: 'seed schedule',
            metadata: const <String, dynamic>{},
          );

      harness.container.read(selectedDateProvider.notifier).state = today;

      final tasks = await harness.container.read(
        tasksForSelectedDateProvider.future,
      );
      final segments = await harness.container.read(
        taskScheduleSegmentsForSelectedDateProvider.future,
      );

      expect(tasks.map((task) => task.summary), contains('Today task'));
      expect(
          tasks.map((task) => task.summary), isNot(contains('Tomorrow task')));
      expect(segments.single.task.summary, 'Today task');
      expect(segments.single.segment.planRunId, 'plan-1');
    });
  });
}

ProviderContainer _createContainer({
  required AppDatabase db,
  required List<_RecordedRequest> requests,
}) {
  final apiClient = ApiClient(
    baseUri: Uri.parse('http://flowplan.test/api'),
    tokenStore: AuthTokenStore(db),
    httpClient: MockClient((request) async {
      requests.add(_RecordedRequest(request));
      final body = _responseFor(request);
      return http.Response(jsonEncode(body), 200);
    }),
  );
  return ProviderContainer(
    overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWith((ref) async => apiClient),
    ],
  );
}

Map<String, Object?> _responseFor(http.Request request) {
  switch (request.url.path) {
    case '/api/client/settings':
      return const <String, Object?>{'settings': <String, Object?>{}};
    case '/api/sync/push':
      return const <String, Object?>{
        'pushed': 0,
        'failed': 0,
        'conflicts': <Object?>[],
      };
    case '/api/sync/pull':
      return const <String, Object?>{
        'changes': <Object?>[],
        'nextCursor': null,
      };
    case '/api/tracking/upload':
      return const <String, Object?>{
        'uploaded': 0,
        'failed': 0,
        'skipped': 0,
      };
    case '/api/files/drive/nodes/node-1/open-plan':
      return const <String, Object?>{
        'action': 'download_then_open',
        'reason': 'server copy required',
      };
    default:
      return const <String, Object?>{'ok': true};
  }
}

class _OutlookHarness {
  _OutlookHarness(this.db, this.container);

  final AppDatabase db;
  final ProviderContainer container;

  static Future<_OutlookHarness> create() async {
    final db = createTestDatabase();
    final container = _createContainer(db: db, requests: <_RecordedRequest>[]);
    return _OutlookHarness(db, container);
  }

  Future<int> createTaskList(String name) {
    return db.into(db.taskLists).insert(
          TaskListsCompanion.insert(
            name: name,
            createdAt: DateTime.utc(2026, 6, 10),
          ),
        );
  }

  Future<int> createTask(
    String uid,
    String summary,
    int? taskListId, {
    DateTime? start,
  }) {
    return db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: uid,
            dtstamp: DateTime.utc(2026, 6, 10),
            summary: summary,
            taskListId: Value(taskListId),
            dtstart: Value(start),
            durationMinutes: const Value(60),
          ),
        );
  }

  Future<void> saveTaskListBinding(int taskListId, String remoteCalendarId) {
    return container
        .read(outlookSyncBindingsRepositoryProvider)
        .saveTaskListBinding(
          OutlookTaskListBinding(
            localTaskListId: taskListId,
            remoteCalendarId: remoteCalendarId,
            remoteCalendarName: 'Remote $remoteCalendarId',
            linkedAt: DateTime.utc(2026, 6, 10),
          ),
        );
  }

  Future<void> saveMirrorBinding({
    required int taskId,
    required int taskListId,
    required String remoteCalendarId,
    String? localSnapshotHash,
    String? localSnapshotJson,
    OutlookTaskMirrorConflictState state = OutlookTaskMirrorConflictState.none,
    String? remoteSnapshotJson,
    String? conflictMessage,
  }) {
    return container
        .read(outlookTaskMirrorRepositoryProvider)
        .saveTaskMirrorBinding(
          OutlookTaskMirrorBinding(
            localTaskId: taskId,
            localTaskListId: taskListId,
            remoteCalendarId: remoteCalendarId,
            remoteCalendarName: 'Remote $remoteCalendarId',
            remoteEventId: 'event-$taskId',
            syncedAt: DateTime.utc(2026, 6, 10),
            localSnapshotHash: localSnapshotHash,
            localSnapshotJson: localSnapshotJson,
            remoteSnapshotJson: remoteSnapshotJson,
            conflictState: state,
            conflictMessage: conflictMessage,
            conflictDetectedAt: state == OutlookTaskMirrorConflictState.none
                ? null
                : DateTime.utc(2026, 6, 10, 12),
          ),
        );
  }

  Future<void> saveConflictMirror({
    required int taskId,
    required int taskListId,
    required OutlookTaskMirrorConflictState state,
    required String leftSummary,
    String? rightSummary,
    required String message,
  }) async {
    final task = await (db.select(db.taskItems)
          ..where((row) => row.id.equals(taskId)))
        .getSingle();
    final current = OutlookTaskMirrorSnapshot.fromTask(
      task: task,
      taskListName: 'Conflict list',
    );
    final left = current.copyWith(summary: leftSummary);
    final right = current.copyWith(summary: rightSummary ?? leftSummary);
    await saveMirrorBinding(
      taskId: taskId,
      taskListId: taskListId,
      remoteCalendarId: 'calendar-conflict',
      localSnapshotJson: left.stableJson,
      localSnapshotHash: left.fingerprint,
      remoteSnapshotJson: right.stableJson,
      state: state,
      conflictMessage: message,
    );
  }

  Future<OutlookTaskMirrorSnapshot> snapshotFor(
    int taskId,
    String taskListName,
  ) async {
    final task = await (db.select(db.taskItems)
          ..where((row) => row.id.equals(taskId)))
        .getSingle();
    return OutlookTaskMirrorSnapshot.fromTask(
      task: task,
      taskListName: taskListName,
    );
  }

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

class _RecordedRequest {
  _RecordedRequest(http.Request request)
      : method = request.method,
        path = request.url.path,
        query = Map<String, String>.from(request.url.queryParameters);

  final String method;
  final String path;
  final Map<String, String> query;

  String get signature => '$method $path';
}
