import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/sync/ms_graph_service.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_sync_policy.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_snapshot.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_sync_service.dart';
import 'package:flowplanv2/features/sync/sync_engine.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('bad sync report payloads are ignored and reset clears stale cursors',
      () async {
    final attemptedAt = DateTime.utc(2026, 6, 10, 8);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_last_sync': attemptedAt.toIso8601String(),
      'outlook_sync_delta_schema_version': 99,
      'outlook_sync_delta_link.calendar-a': 'delta-a',
      'outlook_last_sync_report_time': attemptedAt.toIso8601String(),
      'outlook_last_sync_report_status': 'success',
      'outlook_last_sync_report_mode': 'future_mode',
      'outlook_last_sync_report_calendar_books': 2,
      'outlook_last_sync_report_downloaded': 3,
      'outlook_last_sync_report_calendar_details': '{"not":"a list"}',
      'outlook_last_sync_report_task_mirror_details': '[',
    });

    final report = await SyncEngine.getLastSyncReport();

    expect(report, isNotNull);
    expect(report!.mode, OutlookSyncMode.readOnly);
    expect(report.calendarBooks, 2);
    expect(report.downloaded, 3);
    expect(report.calendarDetails, isEmpty);
    expect(report.taskMirrorDetails, isEmpty);

    await SyncEngine.resetSync();
    final prefs = await SharedPreferences.getInstance();
    expect(await SyncEngine.getLastSyncTime(), isNull);
    expect(await SyncEngine.getLastSyncReport(), isNull);
    expect(prefs.getString('outlook_sync_delta_link.calendar-a'), isNull);
    expect(prefs.getInt('outlook_sync_delta_schema_version'), isNull);
  });

  test('bidirectional sync reports moved mirror containers as conflicts',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_mode': OutlookSyncMode.bidirectional.storageValue,
    });
    final db = createTestDatabase();
    addTearDown(db.close);
    final taskRepository = TaskRepository(db);
    final bindingsRepository = OutlookSyncBindingsRepository(db);
    final mirrorRepository = OutlookTaskMirrorRepository(db);
    final taskListId = await insertFixtureTaskList(db, name: 'Inbox');
    final taskId = await _createTask(
      taskRepository,
      taskListId: taskListId,
      summary: 'Moved mirror calendar',
    );
    await bindingsRepository.saveTaskListBinding(
      OutlookTaskListBinding(
        localTaskListId: taskListId,
        remoteCalendarId: 'new-calendar',
        remoteCalendarName: _remoteCalendarName('Inbox'),
        linkedAt: fixtureNow(),
      ),
    );
    final task = await taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    await mirrorRepository.saveTaskMirrorBinding(
      OutlookTaskMirrorBinding(
        localTaskId: taskId,
        localTaskListId: taskListId,
        remoteCalendarId: 'old-calendar',
        remoteCalendarName: _remoteCalendarName('Inbox'),
        remoteEventId: 'old-event',
        syncedAt: fixtureNow(),
        localSnapshotHash: snapshot.fingerprint,
        localSnapshotJson: snapshot.stableJson,
        remoteSnapshotHash: snapshot.fingerprint,
        remoteSnapshotJson: snapshot.stableJson,
      ),
    );

    final result = await _engine(db).sync();
    final report = await SyncEngine.getLastSyncReport();
    final saved = await mirrorRepository.getTaskMirrorBinding(taskId);

    expect(result.mirroredCreated, 0);
    expect(result.mirroredUpdated, 0);
    expect(result.mirroredDeleted, 0);
    expect(result.mirroredConflicted, 1);
    expect(report, isNotNull);
    expect(report!.success, isTrue);
    expect(report.taskMirrorDetails, hasLength(1));
    expect(report.taskMirrorDetails.single.localTaskListId, taskListId);
    expect(report.taskMirrorDetails.single.remoteCalendarId, 'new-calendar');
    expect(report.taskMirrorDetails.single.conflicted, 1);
    expect(saved!.conflictState, OutlookTaskMirrorConflictState.remoteChanged);
    expect(saved.localSnapshotHash, snapshot.fingerprint);
  });

  test('syncBoundTaskMirrors resolves with local snapshot when refresh is empty',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Original title',
    );
    await harness.bindTaskList(taskListId);
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    final remoteEvent = graphEvent(
      id: 'event-refresh-empty',
      subject: snapshot.summary,
      snapshot: snapshot,
      start: fixtureNow(),
      end: fixtureNow().add(const Duration(hours: 1)),
    );
    final remoteSnapshot = OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
      task: task,
      taskListName: 'Inbox',
      event: remoteEvent,
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: snapshot,
        remoteSnapshot: remoteSnapshot,
        remoteEventId: 'event-refresh-empty',
      ),
    );
    harness.graph.events['remote-$taskListId/event-refresh-empty'] =
        remoteEvent;
    harness.graph.dropUpdatedEvents.add('event-refresh-empty');
    await harness.updateTaskSummary(taskId, 'Changed locally');

    final result = await harness.service.syncBoundTaskMirrors();
    final updatedTask = await harness.taskRepository.getById(taskId);
    final updatedSnapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: updatedTask!,
      taskListName: 'Inbox',
    );
    final saved = await harness.mirrorRepository.getTaskMirrorBinding(taskId);

    expect(result.updated, 1);
    expect(result.conflicted, 0);
    expect(harness.graph.updateEventCalls, hasLength(1));
    expect(saved!.conflictState, OutlookTaskMirrorConflictState.none);
    expect(saved.remoteSnapshotHash, updatedSnapshot.fingerprint);
    expect(saved.remoteLastModifiedAt, isNotNull);
  });

  test('syncBoundTaskMirrors falls back to remote name for blank task lists',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: '   ');
    await harness.createTask(
      taskListId: taskListId,
      summary: 'Blank local task list',
    );
    await harness.bindTaskList(taskListId, taskListName: 'Remote Inbox');

    final result = await harness.service.syncBoundTaskMirrors();

    expect(result.created, 1);
    expect(result.taskListDetails, hasLength(1));
    expect(
      result.taskListDetails.single.taskListName,
      _remoteCalendarName('Remote Inbox'),
    );
    expect(
      (harness.graph.createEventCalls.single.event['body']
          as Map<String, dynamic>)['content'],
      contains(_remoteCalendarName('Remote Inbox')),
    );
  });

  test('syncBoundTaskMirrors accepts FlowPlanV2 schedule managed containers',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    await harness.createTask(
      taskListId: taskListId,
      summary: 'Schedule managed target',
    );
    await harness.bindTaskList(
      taskListId,
      taskListName: 'Schedule Inbox',
      kind: OutlookManagedCalendarKind.scheduleBook,
    );

    final result = await harness.service.syncBoundTaskMirrors();

    expect(result.created, 1);
    expect(harness.graph.createEventCalls.single.isManagedContainer, isTrue);
  });

  test('applyRemoteToLocal marks missing remote mirrors as deleted', () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Missing remote',
    );
    await harness.bindTaskList(taskListId);
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: snapshot,
        remoteEventId: 'missing-event',
        conflictState: OutlookTaskMirrorConflictState.remoteChanged,
      ),
    );

    final result = await harness.service.applyRemoteToLocal(taskId);
    final saved = await harness.mirrorRepository.getTaskMirrorBinding(taskId);

    expect(result.success, isFalse);
    expect(saved!.conflictState, OutlookTaskMirrorConflictState.remoteDeleted);
    expect(saved.conflictMessage, contains('Outlook'));
  });

  test('applyRemoteToLocal reports when the refreshed local task disappeared',
      () async {
    final harness = await _createHarness(useDeletingTaskRepository: true);
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Deleted during apply',
    );
    await harness.bindTaskList(taskListId);
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: snapshot,
        remoteEventId: 'event-remote',
        conflictState: OutlookTaskMirrorConflictState.remoteChanged,
      ),
    );
    harness.graph.events['remote-$taskListId/event-remote'] = graphEvent(
      id: 'event-remote',
      subject: 'Remote title',
      snapshot: snapshot.copyWith(summary: 'Remote title'),
      start: fixtureNow(),
      end: fixtureNow().add(const Duration(hours: 1)),
    );

    final result = await harness.service.applyRemoteToLocal(taskId);

    expect(result.success, isFalse);
    expect(await harness.taskRepository.getById(taskId), isNull);
  });

  test('recreateRemoteMirror records writeFailed when Graph returns null',
      () async {
    final harness = await _createHarness();
    harness.graph.nullCreateSubjects.add('Recreate returns null');
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Recreate returns null',
    );
    await harness.bindTaskList(taskListId);
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: snapshot,
        remoteEventId: 'deleted-event',
        conflictState: OutlookTaskMirrorConflictState.remoteDeleted,
      ),
    );

    final result = await harness.service.recreateRemoteMirror(taskId);
    final saved = await harness.mirrorRepository.getTaskMirrorBinding(taskId);

    expect(result.success, isFalse);
    expect(harness.graph.createEventCalls, hasLength(1));
    expect(saved!.conflictState, OutlookTaskMirrorConflictState.writeFailed);
    expect(saved.conflictMessage, contains('Outlook 未返回新建事件'));
  });

  test('cleanupStaleTaskMirrors falls back when snapshot JSON is broken',
      () async {
    final harness = await _createHarness();
    final taskId = await harness.db.into(harness.db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'task-without-list',
            dtstamp: fixtureNow(),
            summary: 'Detached local task',
          ),
        );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      OutlookTaskMirrorBinding(
        localTaskId: taskId,
        localTaskListId: 404,
        remoteCalendarId: 'remote-stale',
        remoteCalendarName: 'Remote fallback',
        remoteEventId: 'event-stale',
        syncedAt: fixtureNow(),
        localSnapshotHash: 'old',
        localSnapshotJson: '{broken json',
        remoteSnapshotHash: 'old',
        remoteSnapshotJson: '{broken json',
      ),
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      OutlookTaskMirrorBinding(
        localTaskId: 9191,
        localTaskListId: 405,
        remoteCalendarId: 'remote-snapshot',
        remoteCalendarName: 'Remote snapshot fallback',
        remoteEventId: 'event-snapshot',
        syncedAt: fixtureNow(),
        localSnapshotHash: 'old',
        localSnapshotJson: jsonEncode(<String, Object?>{
          'task_list_name': ' Snapshot Inbox ',
        }),
      ),
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      OutlookTaskMirrorBinding(
        localTaskId: 9292,
        localTaskListId: 406,
        remoteCalendarId: 'remote-empty-snapshot',
        remoteCalendarName: 'Remote empty fallback',
        remoteEventId: 'event-empty-snapshot',
        syncedAt: fixtureNow(),
        localSnapshotHash: 'old',
        localSnapshotJson: '',
      ),
    );

    final result = await harness.service.cleanupStaleTaskMirrors();
    final bindings = await harness.mirrorRepository.loadTaskMirrorBindings();

    expect(result.success, isTrue);
    expect(result.affected, 3);
    expect(
      result.taskListDetails.map((detail) => detail.taskListName).toList(),
      [
        'Remote empty fallback',
        'Remote fallback',
        'Snapshot Inbox',
      ],
    );
    expect(
      result.taskListDetails.map((detail) => detail.deleted),
      everyElement(1),
    );
    expect(bindings, isEmpty);
  });

  test('forcePushLocalToRemote reports missing task-list binding context',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Binding missing',
    );
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: snapshot,
        remoteEventId: 'event-no-list-binding',
      ),
    );

    final result = await harness.service.forcePushLocalToRemote(taskId);

    expect(result.success, isFalse);
    expect(harness.graph.createEventCalls, isEmpty);
    expect(harness.graph.updateEventCalls, isEmpty);
  });

  test('forcePushLocalToRemote resolves update when refresh returns null',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Force push refresh empty',
    );
    await harness.bindTaskList(taskListId);
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Inbox',
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Inbox',
        snapshot: snapshot,
        remoteEventId: 'event-force-null',
      ),
    );
    harness.graph.dropUpdatedEvents.add('event-force-null');

    final result = await harness.service.forcePushLocalToRemote(taskId);
    final saved = await harness.mirrorRepository.getTaskMirrorBinding(taskId);

    expect(result.success, isTrue);
    expect(harness.graph.updateEventCalls, hasLength(1));
    expect(saved!.conflictState, OutlookTaskMirrorConflictState.none);
    expect(saved.remoteSnapshotHash, snapshot.fingerprint);
    expect(saved.remoteLastModifiedAt, isNotNull);
  });

  test('forcePushLocalToRemote falls back to remote name for blank task lists',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: '   ');
    final taskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Force push blank list',
    );
    await harness.bindTaskList(taskListId, taskListName: 'Remote Force');
    final task = await harness.taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: _remoteCalendarName('Remote Force'),
    );
    await harness.mirrorRepository.saveTaskMirrorBinding(
      harness.bindingFor(
        task: task,
        taskListName: 'Remote Force',
        snapshot: snapshot,
        remoteEventId: 'event-force-blank-list',
      ),
    );

    final result = await harness.service.forcePushLocalToRemote(taskId);

    expect(result.success, isTrue);
    expect(
      (harness.graph.updateEventCalls.single.event['body']
          as Map<String, dynamic>)['content'],
      contains(_remoteCalendarName('Remote Force')),
    );
  });

  test('recreateAllRemoteDeletedMirrors reports partial failures', () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    await harness.bindTaskList(taskListId);
    final okTaskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Recreate ok',
    );
    final failTaskId = await harness.createTask(
      taskListId: taskListId,
      summary: 'Recreate fail',
    );
    harness.graph.nullCreateSubjects.add('Recreate fail');

    for (final taskId in <int>[okTaskId, failTaskId]) {
      final task = await harness.taskRepository.getById(taskId);
      final snapshot = OutlookTaskMirrorSnapshot.fromTask(
        task: task!,
        taskListName: 'Inbox',
      );
      await harness.mirrorRepository.saveTaskMirrorBinding(
        harness.bindingFor(
          task: task,
          taskListName: 'Inbox',
          snapshot: snapshot,
          remoteEventId: 'deleted-$taskId',
          conflictState: OutlookTaskMirrorConflictState.remoteDeleted,
        ),
      );
    }

    final result = await harness.service.recreateAllRemoteDeletedMirrors();
    final okBinding = await harness.mirrorRepository.getTaskMirrorBinding(
      okTaskId,
    );
    final failedBinding = await harness.mirrorRepository.getTaskMirrorBinding(
      failTaskId,
    );

    expect(result.success, isFalse);
    expect(result.affected, 1);
    expect(result.failed, 1);
    expect(okBinding!.conflictState, OutlookTaskMirrorConflictState.none);
    expect(
      failedBinding!.conflictState,
      OutlookTaskMirrorConflictState.writeFailed,
    );
  });

  test('create payload uses due fallback, default duration, and location',
      () async {
    final harness = await _createHarness();
    final taskListId = await harness.createTaskList(name: 'Inbox');
    await harness.bindTaskList(taskListId);
    await harness.createTask(
      taskListId: taskListId,
      summary: 'Due based task',
      dtstart: null,
      due: fixtureNow().add(const Duration(hours: 4)),
      durationMinutes: 90,
      location: '  Focus room  ',
    );
    await harness.createTask(
      taskListId: taskListId,
      summary: 'No dates task',
      dtstart: null,
      due: null,
      durationMinutes: 0,
    );

    final result = await harness.service.syncBoundTaskMirrors();

    expect(result.created, 2);
    final duePayload = harness.graph.createEventCalls
        .singleWhere((call) => call.event['subject'] == 'Due based task')
        .event;
    final dueStart = DateTime.parse(
      (duePayload['start'] as Map<String, dynamic>)['dateTime'] as String,
    );
    final dueEnd = DateTime.parse(
      (duePayload['end'] as Map<String, dynamic>)['dateTime'] as String,
    );
    expect(dueEnd.difference(dueStart).inMinutes, 90);
    expect(
      duePayload['location'],
      <String, Object?>{'displayName': 'Focus room'},
    );

    final noDatePayload = harness.graph.createEventCalls
        .singleWhere((call) => call.event['subject'] == 'No dates task')
        .event;
    final noDateStart = DateTime.parse(
      (noDatePayload['start'] as Map<String, dynamic>)['dateTime'] as String,
    );
    final noDateEnd = DateTime.parse(
      (noDatePayload['end'] as Map<String, dynamic>)['dateTime'] as String,
    );
    expect(noDateEnd.difference(noDateStart).inMinutes, 60);
  });
}

SyncEngine _engine(AppDatabase db) {
  return SyncEngine(
    EventRepository(db),
    CalendarBooksRepository(db),
    TaskRepository(db),
    OutlookSyncBindingsRepository(db),
    OutlookTaskMirrorRepository(db),
    const OutlookConfig(clientId: 'client-id'),
    DataOperationLogRepository(db),
  );
}

Future<int> _createTask(
  TaskRepository taskRepository, {
  required int taskListId,
  required String summary,
}) {
  return taskRepository.create(
    TaskItemsCompanion.insert(
      uid: 'task-$taskListId-$summary',
      dtstamp: fixtureNow(),
      summary: summary,
      taskListId: Value(taskListId),
      description: const Value('Local notes'),
      dtstart: Value(fixtureNow()),
      due: Value(fixtureNow().add(const Duration(hours: 1))),
    ),
    audit: false,
  );
}

String _remoteCalendarName(String taskListName) {
  return OutlookSyncPolicy.buildManagedCalendarName(
    kind: OutlookManagedCalendarKind.taskMirrorBook,
    containerName: taskListName,
  );
}

Future<_MirrorHarness> _createHarness({
  bool useDeletingTaskRepository = false,
}) async {
  final db = createTestDatabase();
  addTearDown(db.close);
  final graph = _FakeGraphService();
  final taskRepository = useDeletingTaskRepository
      ? _DeletingAfterUpdateTaskRepository(db)
      : TaskRepository(db);
  return _MirrorHarness(
    db: db,
    graph: graph,
    calendarBooksRepository: CalendarBooksRepository(db),
    taskRepository: taskRepository,
    bindingsRepository: OutlookSyncBindingsRepository(db),
    mirrorRepository: OutlookTaskMirrorRepository(db),
  );
}

Map<String, dynamic> graphEvent({
  required String id,
  required String subject,
  required OutlookTaskMirrorSnapshot snapshot,
  required DateTime start,
  required DateTime end,
  String? location,
  String showAs = 'tentative',
}) {
  return <String, dynamic>{
    'id': id,
    'subject': subject,
    'body': <String, dynamic>{
      'contentType': 'Text',
      'content': [
        'Description',
        OutlookTaskMirrorSnapshot.metadataStartMarker,
        jsonEncode(snapshot.toJson()),
        OutlookTaskMirrorSnapshot.metadataEndMarker,
      ].join('\n'),
    },
    'start': <String, dynamic>{
      'dateTime': start.toIso8601String(),
      'timeZone': 'Asia/Shanghai',
    },
    'end': <String, dynamic>{
      'dateTime': end.toIso8601String(),
      'timeZone': 'Asia/Shanghai',
    },
    if (location != null)
      'location': <String, dynamic>{
        'displayName': location,
      },
    'showAs': showAs,
    'lastModifiedDateTime': fixtureNow().toIso8601String(),
  };
}

class _MirrorHarness {
  const _MirrorHarness({
    required this.db,
    required this.graph,
    required this.calendarBooksRepository,
    required this.taskRepository,
    required this.bindingsRepository,
    required this.mirrorRepository,
  });

  final AppDatabase db;
  final _FakeGraphService graph;
  final CalendarBooksRepository calendarBooksRepository;
  final TaskRepository taskRepository;
  final OutlookSyncBindingsRepository bindingsRepository;
  final OutlookTaskMirrorRepository mirrorRepository;

  OutlookTaskMirrorSyncService get service => OutlookTaskMirrorSyncService(
        graphService: graph,
        taskRepository: taskRepository,
        calendarBooksRepository: calendarBooksRepository,
        taskListBindingsRepository: bindingsRepository,
        taskMirrorRepository: mirrorRepository,
      );

  Future<int> createTaskList({required String name}) {
    return insertFixtureTaskList(db, name: name);
  }

  Future<int> createTask({
    required int taskListId,
    required String summary,
    DateTime? dtstart,
    DateTime? due,
    int durationMinutes = 60,
    String? location,
  }) {
    return taskRepository.create(
      TaskItemsCompanion.insert(
        uid: 'task-$summary',
        dtstamp: fixtureNow(),
        summary: summary,
        taskListId: Value(taskListId),
        description: const Value('Local notes'),
        location: Value(location),
        dtstart: Value(dtstart),
        due: Value(due),
        durationMinutes: Value(durationMinutes),
      ),
      audit: false,
    );
  }

  Future<void> updateTaskSummary(int taskId, String summary) {
    return (db.update(db.taskItems)..where((task) => task.id.equals(taskId)))
        .write(TaskItemsCompanion(summary: Value(summary)));
  }

  Future<void> bindTaskList(
    int taskListId, {
    String taskListName = 'Inbox',
    OutlookManagedCalendarKind kind = OutlookManagedCalendarKind.taskMirrorBook,
  }) {
    return bindingsRepository.saveTaskListBinding(
      OutlookTaskListBinding(
        localTaskListId: taskListId,
        remoteCalendarId: 'remote-$taskListId',
        remoteCalendarName: OutlookSyncPolicy.buildManagedCalendarName(
          kind: kind,
          containerName: taskListName,
        ),
        linkedAt: fixtureNow(),
      ),
    );
  }

  OutlookTaskMirrorBinding bindingFor({
    required TaskItem task,
    required String taskListName,
    required OutlookTaskMirrorSnapshot snapshot,
    OutlookTaskMirrorSnapshot? remoteSnapshot,
    required String remoteEventId,
    OutlookTaskMirrorConflictState conflictState =
        OutlookTaskMirrorConflictState.none,
  }) {
    final resolvedRemoteSnapshot = remoteSnapshot ?? snapshot;
    return OutlookTaskMirrorBinding(
      localTaskId: task.id,
      localTaskListId: task.taskListId!,
      remoteCalendarId: 'remote-${task.taskListId}',
      remoteCalendarName: _remoteCalendarName(taskListName),
      remoteEventId: remoteEventId,
      syncedAt: fixtureNow(),
      localSnapshotHash: snapshot.fingerprint,
      localSnapshotJson: snapshot.stableJson,
      remoteSnapshotHash: resolvedRemoteSnapshot.fingerprint,
      remoteSnapshotJson: resolvedRemoteSnapshot.stableJson,
      conflictState: conflictState,
      conflictMessage:
          conflictState == OutlookTaskMirrorConflictState.none ? null : 'mock',
      conflictDetectedAt: conflictState == OutlookTaskMirrorConflictState.none
          ? null
          : fixtureNow(),
    );
  }
}

class _DeletingAfterUpdateTaskRepository extends TaskRepository {
  _DeletingAfterUpdateTaskRepository(this.db) : super(db);

  final AppDatabase db;

  @override
  Future<bool> update(
    TaskItemsCompanion companion, {
    bool audit = true,
    String actor = 'user',
    String action = 'update',
    String? summary,
    Object? metadata,
  }) async {
    final updated = await super.update(
      companion,
      audit: audit,
      actor: actor,
      action: action,
      summary: summary,
      metadata: metadata,
    );
    if (companion.id.present) {
      await (db.delete(db.taskItems)
            ..where((task) => task.id.equals(companion.id.value)))
          .go();
    }
    return updated;
  }
}

class _CreateEventCall {
  const _CreateEventCall({
    required this.calendarId,
    required this.event,
    required this.isManagedContainer,
  });

  final String calendarId;
  final Map<String, dynamic> event;
  final bool isManagedContainer;
}

class _UpdateEventCall {
  const _UpdateEventCall({
    required this.calendarId,
    required this.eventId,
    required this.event,
    required this.isManagedContainer,
  });

  final String calendarId;
  final String eventId;
  final Map<String, dynamic> event;
  final bool isManagedContainer;
}

class _FakeGraphService extends MsGraphService {
  _FakeGraphService()
      : super(
          const OutlookConfig(clientId: 'mock-client'),
          syncMode: OutlookSyncMode.bidirectional,
        );

  final createEventCalls = <_CreateEventCall>[];
  final updateEventCalls = <_UpdateEventCall>[];
  final events = <String, Map<String, dynamic>?>{};
  final updateFailures = <String>{};
  final dropUpdatedEvents = <String>{};
  final nullCreateSubjects = <String>{};

  @override
  Future<Map<String, dynamic>?> createEvent(
    Map<String, dynamic> event, {
    required String calendarId,
    required bool isFlowPlanV2ManagedContainer,
  }) async {
    createEventCalls.add(
      _CreateEventCall(
        calendarId: calendarId,
        event: event,
        isManagedContainer: isFlowPlanV2ManagedContainer,
      ),
    );
    if (nullCreateSubjects.contains(event['subject'])) {
      return null;
    }
    final id = 'created-${createEventCalls.length}';
    final created = <String, dynamic>{
      ...event,
      'id': id,
      'lastModifiedDateTime': fixtureNow().toIso8601String(),
    };
    events['$calendarId/$id'] = created;
    return created;
  }

  @override
  Future<bool> updateEvent({
    required String calendarId,
    required String eventId,
    required Map<String, dynamic> event,
    required bool isFlowPlanV2ManagedContainer,
  }) async {
    updateEventCalls.add(
      _UpdateEventCall(
        calendarId: calendarId,
        eventId: eventId,
        event: event,
        isManagedContainer: isFlowPlanV2ManagedContainer,
      ),
    );
    if (updateFailures.contains(eventId)) {
      return false;
    }
    events['$calendarId/$eventId'] = dropUpdatedEvents.contains(eventId)
        ? null
        : <String, dynamic>{
            ...event,
            'id': eventId,
            'lastModifiedDateTime': fixtureNow().toIso8601String(),
          };
    return true;
  }

  @override
  Future<Map<String, dynamic>?> getEvent({
    required String calendarId,
    required String eventId,
  }) async {
    return events['$calendarId/$eventId'];
  }
}
