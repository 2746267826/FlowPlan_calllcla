import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/actual/data/actual_activity_log_repository.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/scheduler/scheduler_engine.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_fusion_repository.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  group('SchedulerEngine gap3 worker scheduler coverage', () {
    test('autoScheduleFromDeviation uses the default current-time lower bound',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(DateTime.now().weekday, const <WorkTimeRange>[]),
      );
      addTearDown(harness.close);
      await harness.insertTask(
        uid: 'default-deviation-from',
        summary: 'Default deviation from',
        durationMinutes: 30,
        dtstart: DateTime.now().subtract(const Duration(minutes: 20)),
      );

      final result = await harness.engine.autoScheduleFromDeviation(
        date: DateTime.now(),
        deviatedTaskId: -1,
      );

      expect(result.trigger, 'plan_deviation');
      expect(result.context.deviationReason, isNotNull);
      expect(result.effectiveStart.minute % 15, 0);
      expect(result.scheduledTaskCount, 0);
    });

    test('fallback evidence is used when candidate loading changes mid-run',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final operationLogs = DataOperationLogRepository(db);
      final task = _taskItem(
        id: 101,
        uid: 'late-candidate',
        summary: 'Late candidate',
        durationMinutes: 0,
      );
      final taskRepository = _ChangingTaskRepository(db, task);
      final engine = SchedulerEngine(
        taskRepository,
        EventRepository(db, operationLogs),
        db,
        _scheduleFor(DateTime.monday, const <WorkTimeRange>[]),
        TaskScheduleSegmentRepository(db, operationLogs),
        operationLogs,
        ActualActivityLogRepository(db, operationLogs),
        ActivityFusionRepository(db, operationLogs),
      );

      final result = await engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 10),
      );

      expect(taskRepository.pendingCalls, 2);
      expect(result.unscheduledTasks.single.taskId, 101);
      expect(result.unscheduledTasks.single.originalDurationMinutes, 30);
      expect(result.unscheduledTasks.single.remainingMinutes, 30);
    });

    test('valid and malformed actual payloads count task id aliases', () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 11 * 60)],
        ),
      );
      addTearDown(harness.close);
      final firstTaskId = await harness.insertTask(
        uid: 'json-task-id',
        summary: 'JSON task id',
        durationMinutes: 30,
      );
      final secondTaskId = await harness.insertTask(
        uid: 'malformed-task-id',
        summary: 'Malformed task id',
        durationMinutes: 30,
      );
      await harness.insertActualLog(
        title: 'Valid map alias',
        start: DateTime(2026, 6, 8, 7),
        end: DateTime(2026, 6, 8, 7, 10),
        status: ActualActivityStatus.candidate,
        payloadJson: '{"task_id":"$firstTaskId"}',
      );
      await harness.insertActualLog(
        title: 'Malformed alias',
        start: DateTime(2026, 6, 8, 7, 15),
        end: DateTime(2026, 6, 8, 7, 25),
        status: ActualActivityStatus.candidate,
        payloadJson: '{"task_id": $secondTaskId',
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 11),
      );

      expect(
        result.context.taskEvidence
            .singleWhere((item) => item.taskId == firstTaskId)
            .actualCandidateCount,
        1,
      );
      expect(
        result.context.taskEvidence
            .singleWhere((item) => item.taskId == secondTaskId)
            .actualCandidateCount,
        1,
      );
    });

    test('split suggestions account for blockers inside work windows',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [
            WorkTimeRange(startMinute: 9 * 60, endMinute: 9 * 60 + 30),
            WorkTimeRange(startMinute: 10 * 60, endMinute: 10 * 60 + 45),
          ],
        ),
      );
      addTearDown(harness.close);
      await harness.insertBlock(
        uid: 'split-inner-block',
        summary: 'Inner block',
        start: DateTime(2026, 6, 8, 10, 15),
        end: DateTime(2026, 6, 8, 10, 30),
      );
      final taskId = await harness.insertTask(
        uid: 'split-before-block',
        summary: 'Split before block',
        durationMinutes: 60,
        isSplittable: true,
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 10, 45),
      );

      expect(result.scheduledTaskCount, 1);
      expect(result.splitSuggestedTaskCount, 1);
      final placement = result.placements.single;
      expect(placement.taskId, taskId);
      expect(placement.isSplit, isTrue);
      expect(
        placement.segments.map((segment) => segment.durationMinutes),
        <int>[30, 15, 15],
      );
      expect(
        placement.segments.map((segment) => segment.start),
        <DateTime>[
          DateTime(2026, 6, 8, 9),
          DateTime(2026, 6, 8, 10),
          DateTime(2026, 6, 8, 10, 30),
        ],
      );
    });

    test('splittable work remains unscheduled when total gaps are too small',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [
            WorkTimeRange(startMinute: 9 * 60, endMinute: 9 * 60 + 15),
            WorkTimeRange(startMinute: 10 * 60, endMinute: 10 * 60 + 15),
          ],
        ),
      );
      addTearDown(harness.close);
      final taskId = await harness.insertTask(
        uid: 'split-no-op',
        summary: 'Split no-op',
        durationMinutes: 45,
        isSplittable: true,
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 10, 15),
      );

      expect(result.scheduledTaskCount, 0);
      expect(result.splitSuggestedTaskCount, 0);
      expect(result.unscheduledTasks.single.taskId, taskId);
    });

    test('scheduler tie breaks due dates before unscheduled start dates',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 11 * 60)],
        ),
      );
      addTearDown(harness.close);
      final dueTask = await harness.insertTask(
        uid: 'due-before-no-due',
        summary: 'Due before no due',
        durationMinutes: 15,
        due: DateTime(2026, 6, 9),
      );
      final noDueTask = await harness.insertTask(
        uid: 'no-due-after-due',
        summary: 'No due after due',
        durationMinutes: 15,
      );
      final scheduledLater = await harness.insertTask(
        uid: 'scheduled-later',
        summary: 'Scheduled later',
        durationMinutes: 15,
        dtstart: DateTime(2026, 6, 8, 10),
      );
      final scheduledLatest = await harness.insertTask(
        uid: 'scheduled-latest',
        summary: 'Scheduled latest',
        durationMinutes: 15,
        dtstart: DateTime(2026, 6, 8, 10, 15),
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 11),
      );

      expect(
        result.placements.map((placement) => placement.taskId),
        <int>[dueTask, scheduledLater, scheduledLatest, noDueTask],
      );
    });

    test('scheduler comparator prefers scheduled starts over unscheduled tasks',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 10 * 60)],
        ),
      );
      addTearDown(harness.close);
      final scheduled = _taskItem(
        id: 501,
        uid: 'compare-scheduled',
        summary: 'Scheduled comparator',
        durationMinutes: 15,
        dtstart: DateTime(2026, 6, 8, 9),
      );
      final unscheduled = _taskItem(
        id: 502,
        uid: 'compare-unscheduled',
        summary: 'Unscheduled comparator',
        durationMinutes: 15,
      );

      expect(
        harness.engine.debugCompareTasksForScheduling(scheduled, unscheduled),
        lessThan(0),
      );
    });

    test('applyRunResult returns without writes when there are no changes',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 10 * 60)],
        ),
      );
      addTearDown(harness.close);
      final result = _runResult();

      await harness.engine.applyRunResult(result);

      expect(await harness.operationLogs.listRecent(), isEmpty);
      expect(await harness.segmentRepository.getForDate(result.date), isEmpty);
    });
  });

  group('TaskScheduleSegmentRepository gap3 worker coverage', () {
    test('query filters status and archived lists while reading string fields',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final operationLogs = DataOperationLogRepository(db);
      final repository = TaskScheduleSegmentRepository(db, operationLogs);
      final activeListId = await insertFixtureTaskList(db, name: 'Active');
      final archivedListId = await insertFixtureTaskList(db, name: 'Archived');
      await (db.update(db.taskLists)
            ..where((list) => list.id.equals(archivedListId)))
          .write(const TaskListsCompanion(isArchived: Value(true)));

      final visibleTaskId = await _insertRawTask(
        db,
        id: 301,
        uid: 'string-reader-visible',
        summary: 'String reader visible',
        taskListId: activeListId,
        dtstamp: '2026-06-08T08:00:00.000',
        due: '2026-06-08T12:00:00.000',
        isSplittable: '1',
        isAutoScheduled: '1',
        isLocked: '1',
      );
      await _insertRawTask(
        db,
        id: 302,
        uid: 'completed-filtered',
        summary: 'Completed filtered',
        taskListId: activeListId,
        status: 'COMPLETED',
      );
      await _insertRawTask(
        db,
        id: 303,
        uid: 'archived-filtered',
        summary: 'Archived filtered',
        taskListId: archivedListId,
      );
      await _insertRawSegment(
        db,
        taskId: visibleTaskId,
        segmentIndex: 0,
        start: DateTime(2026, 6, 8, 9),
        end: DateTime(2026, 6, 8, 9, 45),
        source: 'manual',
        planRunId: 'raw-plan',
        note: 'raw note',
      );
      await _insertRawSegment(
        db,
        taskId: 302,
        segmentIndex: 0,
        start: DateTime(2026, 6, 8, 10),
        end: DateTime(2026, 6, 8, 10, 30),
      );
      await _insertRawSegment(
        db,
        taskId: 303,
        segmentIndex: 0,
        start: DateTime(2026, 6, 8, 10),
        end: DateTime(2026, 6, 8, 10, 30),
      );

      final items = await repository.getForDate(DateTime(2026, 6, 8));
      final segment = items.single.segment;
      final task = items.single.task;

      expect(task.id, visibleTaskId);
      expect(task.dtstamp, DateTime(2026, 6, 8, 8));
      expect(task.due, DateTime(2026, 6, 8, 12));
      expect(task.isSplittable, isTrue);
      expect(task.isAutoScheduled, isTrue);
      expect(task.isLocked, isTrue);
      expect(segment.durationMinutes, 45);
      expect(segment.toJson(), {
        'id': segment.id,
        'task_id': visibleTaskId,
        'segment_index': 0,
        'start_at': '2026-06-08T09:00:00.000',
        'end_at': '2026-06-08T09:45:00.000',
        'source': 'manual',
        'plan_run_id': 'raw-plan',
        'note': 'raw note',
      });
    });

    test('raw row readers fall back for unsupported dates and string bools',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final operationLogs = DataOperationLogRepository(db);
      final repository = TaskScheduleSegmentRepository(db, operationLogs);
      final taskListId = await insertFixtureTaskList(db);
      final beforeRead = DateTime.now();
      final taskId = await _insertRawTask(
        db,
        id: 304,
        uid: 'fallback-date-reader',
        summary: 'Fallback date reader',
        taskListId: taskListId,
        dtstamp: Uint8List.fromList(<int>[1, 2, 3]),
        isSplittable: '1',
        isAutoScheduled: '1',
        isLocked: '0',
      );
      await _insertRawSegment(
        db,
        taskId: taskId,
        segmentIndex: 0,
        start: DateTime(2026, 6, 8, 11),
        end: DateTime(2026, 6, 8, 11, 30),
      );

      final item = (await repository.getForDate(DateTime(2026, 6, 8))).single;
      final afterRead = DateTime.now();

      expect(item.task.dtstamp.isBefore(beforeRead), isFalse);
      expect(item.task.dtstamp.isAfter(afterRead), isFalse);
      expect(item.task.isSplittable, isTrue);
      expect(item.task.isAutoScheduled, isTrue);
      expect(item.task.isLocked, isFalse);
    });

    test('query row reader accepts textual bool values from custom rows',
        () async {
      final db = _TextBoolSegmentDatabase();
      addTearDown(db.close);
      final operationLogs = DataOperationLogRepository(db);
      final repository = TaskScheduleSegmentRepository(db, operationLogs);

      final item = (await repository.getForDate(DateTime(2026, 6, 8))).single;

      expect(item.task.isSplittable, isTrue);
      expect(item.task.isAutoScheduled, isTrue);
      expect(item.task.isLocked, isFalse);
    });

    test('watchForDate polls the repository again after the first snapshot',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 10 * 60)],
        ),
      );
      addTearDown(harness.close);
      final taskId = await harness.insertTask(
        uid: 'watch-segment',
        summary: 'Watch segment',
        durationMinutes: 30,
      );
      await harness.segmentRepository.replaceForTasks(
        taskIds: [taskId],
        segments: [
          TaskScheduleSegmentDraft(
            taskId: taskId,
            segmentIndex: 0,
            startAt: DateTime(2026, 6, 8, 9),
            endAt: DateTime(2026, 6, 8, 9, 30),
            source: 'test',
            planRunId: 'watch-plan',
          ),
        ],
        actor: 'test',
        summary: 'seed watch segment',
        metadata: const <String, Object?>{},
      );

      await expectLater(
        harness.segmentRepository.watchForDate(DateTime(2026, 6, 8)).take(2),
        emitsInOrder(<Matcher>[hasLength(1), hasLength(1)]),
      );
    });

    test('clearForTask deletes old segments and records sync delete metadata',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final operationLogs = DataOperationLogRepository(db);
      final recorder = SyncWriteRecorder(
        mutationStore: OfflineMutationStore(db),
        stateStore: SyncObjectStateStore(db),
      );
      final repository = TaskScheduleSegmentRepository(
        db,
        operationLogs,
        recorder,
      );
      final taskListId = await insertFixtureTaskList(db);
      final taskId = await TaskRepository(db, operationLogs).create(
        fixtureTask(
          uid: 'sync-delete-segment',
          summary: 'Sync delete segment',
          taskListId: taskListId,
        ),
        audit: false,
      );
      await repository.replaceForTasks(
        taskIds: [taskId],
        segments: [
          TaskScheduleSegmentDraft(
            taskId: taskId,
            segmentIndex: 0,
            startAt: DateTime(2026, 6, 8, 9),
            endAt: DateTime(2026, 6, 8, 9, 30),
            source: 'test',
            planRunId: 'delete-plan',
          ),
        ],
        actor: 'test',
        summary: 'seed before delete',
        metadata: const <String, Object?>{},
      );

      await repository.clearForTask(
        taskId: taskId,
        actor: 'test',
        summary: 'clear old segments',
      );

      expect(await repository.getByTaskId(taskId), isEmpty);
      final mutations = await OfflineMutationStore(db).listPending(limit: 10);
      expect(mutations.map((mutation) => mutation.action.wireName), [
        'create',
        'delete',
      ]);
      final audit = await operationLogs.listRecent();
      expect(audit.first.metadataJson, contains('clear_single_task_segments'));
    });

    test('replaceForTasks is a no-op when both task ids and drafts are empty',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final operationLogs = DataOperationLogRepository(db);
      final repository = TaskScheduleSegmentRepository(db, operationLogs);

      await repository.replaceForTasks(
        taskIds: const <int>[],
        segments: const <TaskScheduleSegmentDraft>[],
        actor: 'test',
        summary: 'empty no-op',
        metadata: const <String, Object?>{},
      );

      expect(await operationLogs.listRecent(), isEmpty);
    });
  });
}

WeeklyWorkSchedule _scheduleFor(int weekday, List<WorkTimeRange> ranges) {
  return WeeklyWorkSchedule({weekday: ranges});
}

class _SchedulerHarness {
  _SchedulerHarness({
    required this.db,
    required this.operationLogs,
    required this.taskRepository,
    required this.segmentRepository,
    required this.engine,
    required this.taskListId,
    required this.calendarId,
    required this.fusionRepository,
  });

  final AppDatabase db;
  final DataOperationLogRepository operationLogs;
  final TaskRepository taskRepository;
  final TaskScheduleSegmentRepository segmentRepository;
  final SchedulerEngine engine;
  final int taskListId;
  final int calendarId;
  final ActivityFusionRepository fusionRepository;

  static Future<_SchedulerHarness> create({
    required WeeklyWorkSchedule schedule,
  }) async {
    final db = createTestDatabase();
    final operationLogs = DataOperationLogRepository(db);
    final taskRepository = TaskRepository(db, operationLogs);
    final eventRepository = EventRepository(db, operationLogs);
    final segmentRepository = TaskScheduleSegmentRepository(db, operationLogs);
    final actualRepository = ActualActivityLogRepository(db, operationLogs);
    final fusionRepository = ActivityFusionRepository(db, operationLogs);
    final taskListId = await insertFixtureTaskList(db);
    final calendarId = await insertFixtureCalendar(db);
    final engine = SchedulerEngine(
      taskRepository,
      eventRepository,
      db,
      schedule,
      segmentRepository,
      operationLogs,
      actualRepository,
      fusionRepository,
    );
    return _SchedulerHarness(
      db: db,
      operationLogs: operationLogs,
      taskRepository: taskRepository,
      segmentRepository: segmentRepository,
      engine: engine,
      taskListId: taskListId,
      calendarId: calendarId,
      fusionRepository: fusionRepository,
    );
  }

  Future<void> close() => db.close();

  Future<int> insertTask({
    required String uid,
    required String summary,
    required int durationMinutes,
    int priorityLocal = 2,
    DateTime? due,
    DateTime? dtstart,
    bool isSplittable = false,
    bool isLocked = false,
    bool isAutoScheduled = true,
  }) {
    return taskRepository.create(
      fixtureTask(uid: uid, summary: summary, taskListId: taskListId).copyWith(
        durationMinutes: Value(durationMinutes),
        priorityLocal: Value(priorityLocal),
        due: Value(due),
        dtstart: Value(dtstart),
        isSplittable: Value(isSplittable),
        isLocked: Value(isLocked),
        isAutoScheduled: Value(isAutoScheduled),
      ),
      audit: false,
    );
  }

  Future<int> insertBlock({
    required String uid,
    required String summary,
    required DateTime start,
    required DateTime end,
  }) {
    return db.into(db.calendarEvents).insert(
          fixtureEvent(uid: uid, summary: summary, calendarId: calendarId)
              .copyWith(
            dtstart: Value(start),
            dtend: Value(end),
            isBlock: const Value(true),
          ),
        );
  }

  Future<void> insertActualLog({
    required String title,
    required DateTime start,
    required DateTime end,
    required String status,
    required String payloadJson,
  }) {
    final now = DateTime.now().toIso8601String();
    return db.customStatement(
      '''
      INSERT INTO actual_activity_logs (
        actual_uid,
        title,
        start_at,
        end_at,
        source_type,
        source_payload_json,
        confidence,
        status,
        created_at,
        updated_at,
        confirmed_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        'actual-$title-${start.microsecondsSinceEpoch}',
        title,
        start.toIso8601String(),
        end.toIso8601String(),
        ActualActivitySourceType.manual,
        payloadJson,
        1.0,
        status,
        now,
        now,
        status == ActualActivityStatus.confirmed ? now : null,
      ],
    );
  }
}

class _ChangingTaskRepository extends TaskRepository {
  _ChangingTaskRepository(super.db, this.task);

  final TaskItem task;
  var pendingCalls = 0;

  @override
  Future<List<TaskItem>> getPendingForSchedule() async {
    pendingCalls++;
    return pendingCalls == 1 ? const <TaskItem>[] : <TaskItem>[task];
  }

  @override
  Future<List<TaskItem>> getActiveScheduledForDate(DateTime date) async {
    return const <TaskItem>[];
  }
}

TaskItem _taskItem({
  required int id,
  required String uid,
  required String summary,
  required int durationMinutes,
  DateTime? due,
  DateTime? dtstart,
}) {
  return TaskItem(
    id: id,
    uid: uid,
    dtstamp: DateTime(2026, 6, 8, 8),
    summary: summary,
    dtstart: dtstart,
    due: due,
    priority: 0,
    status: 'NEEDS-ACTION',
    percentComplete: 0,
    categories: '[]',
    durationMinutes: durationMinutes,
    isSplittable: false,
    priorityLocal: 2,
    isAutoScheduled: true,
    isLocked: false,
    reminderMinutesBefore: 15,
  );
}

SchedulerRunResult _runResult() {
  return SchedulerRunResult(
    date: DateTime(2026, 6, 8),
    planRunId: 'empty-run',
    trigger: 'manual_reschedule',
    effectiveStart: DateTime(2026, 6, 8, 9),
    effectiveEnd: DateTime(2026, 6, 8, 10),
    scheduledTaskCount: 0,
    rescheduledTaskCount: 0,
    clearedTaskCount: 0,
    unscheduledTaskCount: 0,
    splitSuggestedTaskCount: 0,
    evidenceCompletedTaskCount: 0,
    placements: const <SchedulerTaskPlacement>[],
    clearedTaskIds: const <int>[],
    unscheduledTasks: const <SchedulerUnscheduledTask>[],
    logEntries: const <SchedulerRunLogEntry>[],
    context: SchedulerContextSnapshot(
      date: DateTime(2026, 6, 8),
      effectiveStart: DateTime(2026, 6, 8, 9),
      effectiveEnd: DateTime(2026, 6, 8, 10),
      fixedBlockCount: 0,
      confirmedActualCount: 0,
      taskEvidence: const <SchedulerTaskEvidence>[],
      deviationReason: null,
      usesWeatherContext: false,
      usesLocationContext: false,
      usesFileContext: false,
    ),
  );
}

Future<int> _insertRawTask(
  AppDatabase db, {
  required int id,
  required String uid,
  required String summary,
  required int taskListId,
  Object dtstamp = '2026-06-08T08:00:00.000',
  String? due,
  String status = 'NEEDS-ACTION',
  String isSplittable = '0',
  String isAutoScheduled = '1',
  String isLocked = '0',
}) async {
  await db.customStatement(
    '''
    INSERT INTO task_items (
      id,
      uid,
      dtstamp,
      summary,
      due,
      priority,
      status,
      percent_complete,
      categories,
      duration_minutes,
      is_splittable,
      priority_local,
      is_auto_scheduled,
      task_list_id,
      is_locked,
      reminder_minutes_before
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      id,
      uid,
      dtstamp,
      summary,
      due,
      0,
      status,
      0,
      '[]',
      30,
      isSplittable,
      2,
      isAutoScheduled,
      taskListId,
      isLocked,
      15,
    ],
  );
  return id;
}

Future<void> _insertRawSegment(
  AppDatabase db, {
  required int taskId,
  required int segmentIndex,
  required DateTime start,
  required DateTime end,
  String source = 'test',
  String? planRunId,
  String? note,
}) {
  final now = DateTime(2026, 6, 8, 8).toIso8601String();
  return db.customStatement(
    '''
    INSERT INTO task_schedule_segments (
      task_id,
      segment_index,
      start_at,
      end_at,
      source,
      plan_run_id,
      note,
      created_at,
      updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      taskId,
      segmentIndex,
      start.toIso8601String(),
      end.toIso8601String(),
      source,
      planRunId,
      note,
      now,
      now,
    ],
  );
}

class _TextBoolSegmentDatabase extends AppDatabase {
  _TextBoolSegmentDatabase() : super(NativeDatabase.memory());

  @override
  Selectable<QueryRow> customSelect(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation> readsFrom = const {},
  }) {
    if (query.contains('FROM task_schedule_segments s')) {
      return _SchedulerQueryRows(this, const [
        <String, Object?>{
          'id': 1,
          'task_id': 42,
          'segment_index': 0,
          'start_at': '2026-06-08T09:00:00.000',
          'end_at': '2026-06-08T09:30:00.000',
          'source': 'test',
          'plan_run_id': 'text-bool-plan',
          'note': null,
          'created_at': '2026-06-08T08:00:00.000',
          'updated_at': '2026-06-08T08:00:00.000',
          'task_row_id': 42,
          'uid': 'text-bool-task',
          'dtstamp': '2026-06-08T08:00:00.000',
          'summary': 'Text bool task',
          'description': null,
          'location': null,
          'dtstart': null,
          'due': null,
          'completed': null,
          'priority': 0,
          'status': 'NEEDS-ACTION',
          'percent_complete': 0,
          'categories': '[]',
          'rrule': null,
          'duration_minutes': 30,
          'is_splittable': 'true',
          'priority_local': 2,
          'is_auto_scheduled': '1',
          'task_list_id': 7,
          'tag_id': null,
          'is_locked': 'false',
          'reminder_minutes_before': 15,
        },
      ]);
    }
    return super.customSelect(
      query,
      variables: variables,
      readsFrom: readsFrom,
    );
  }
}

class _SchedulerQueryRows with Selectable<QueryRow> {
  _SchedulerQueryRows(this.db, this.rows);

  final AppDatabase db;
  final List<Map<String, Object?>> rows;

  @override
  Future<List<QueryRow>> get() async {
    return rows.map((row) => QueryRow(row, db)).toList(growable: false);
  }

  @override
  Stream<List<QueryRow>> watch() => Stream.fromFuture(get());
}
