import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/actual/data/actual_activity_log_repository.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/scheduler/scheduler_engine.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_fusion_repository.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  group('SchedulerEngine gap worker scheduler coverage', () {
    test('autoSchedule returns the detailed scheduled task count', () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 11 * 60)],
        ),
      );
      addTearDown(harness.close);
      await harness.insertTask(
        uid: 'count-wrapper',
        summary: 'Count wrapper result',
        durationMinutes: 30,
      );

      final count = await harness.engine.autoSchedule(DateTime(2026, 6, 8));

      expect(count, 1);
    });

    test(
        'until before from reports every task unscheduled with fallback duration',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 12 * 60)],
        ),
      );
      addTearDown(harness.close);
      final taskId = await harness.insertTask(
        uid: 'bad-range',
        summary: 'Bad selected range',
        durationMinutes: -5,
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 11),
        until: DateTime(2026, 6, 8, 10),
      );

      expect(result.scheduledTaskCount, 0);
      expect(result.unscheduledTaskCount, 1);
      expect(result.effectiveEnd, result.effectiveStart);
      expect(result.unscheduledTasks.single.taskId, taskId);
      expect(result.unscheduledTasks.single.originalDurationMinutes, 30);
      expect(result.unscheduledTasks.single.remainingMinutes, 30);
      expect(result.unscheduledTasks.single.reason, isNotEmpty);
      expect(result.logEntries.single.level, 'warning');
    });

    test('deviation reschedule can force a past auto scheduled task movable',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 10 * 60)],
        ),
      );
      addTearDown(harness.close);
      final taskId = await harness.insertTask(
        uid: 'forced-past',
        summary: 'Forced past task',
        durationMinutes: 30,
        dtstart: DateTime(2026, 6, 8, 8, 30),
      );

      final result = await harness.engine.autoScheduleFromDeviation(
        date: DateTime(2026, 6, 8),
        deviatedTaskId: taskId,
        from: DateTime(2026, 6, 8, 9),
      );

      expect(result.trigger, 'plan_deviation');
      expect(result.context.deviationReason, isNotNull);
      expect(result.scheduledTaskCount, 1);
      expect(result.rescheduledTaskCount, 1);
      expect(result.placements.single.taskId, taskId);
      expect(result.placements.single.wasRescheduled, isTrue);
      expect(
        result.placements.single.segments.single.start,
        DateTime(2026, 6, 8, 9),
      );
    });

    test('non auto scheduled task stays a blocker and pending work is rejected',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 10 * 60)],
        ),
      );
      addTearDown(harness.close);
      await harness.insertTask(
        uid: 'manual-blocker',
        summary: 'Manual blocker',
        durationMinutes: 60,
        dtstart: DateTime(2026, 6, 8, 9),
        isAutoScheduled: false,
      );
      final pendingId = await harness.insertTask(
        uid: 'blocked-pending',
        summary: 'Blocked pending work',
        durationMinutes: 30,
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 11),
      );

      expect(result.scheduledTaskCount, 0);
      expect(result.unscheduledTaskCount, 1);
      expect(result.unscheduledTasks.single.taskId, pendingId);
      expect(result.unscheduledTasks.single.reason, isNotEmpty);
    });

    test('existing schedule segments block only non movable tasks', () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 10 * 60)],
        ),
      );
      addTearDown(harness.close);
      final segmentedId = await harness.insertTask(
        uid: 'segmented-blocker',
        summary: 'Segmented blocker',
        durationMinutes: 30,
        dtstart: DateTime(2026, 6, 8, 9),
        isLocked: true,
      );
      await harness.segmentRepository.replaceForTasks(
        taskIds: [segmentedId],
        segments: [
          TaskScheduleSegmentDraft(
            taskId: segmentedId,
            segmentIndex: 0,
            startAt: DateTime(2026, 6, 8, 9),
            endAt: DateTime(2026, 6, 8, 9, 45),
            source: 'test',
            planRunId: 'existing',
          ),
        ],
        actor: 'test',
        summary: 'seed segment',
        metadata: const <String, dynamic>{},
      );
      final pendingId = await harness.insertTask(
        uid: 'segment-gap',
        summary: 'Uses segment gap',
        durationMinutes: 15,
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 10),
      );

      expect(result.scheduledTaskCount, 1);
      expect(result.placements.single.taskId, pendingId);
      expect(
        result.placements.single.segments.single.start,
        DateTime(2026, 6, 8, 9, 45),
      );
    });

    test('confirmed actual block is snapped and malformed payload still counts',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 10 * 60)],
        ),
      );
      addTearDown(harness.close);
      final taskId = await harness.insertTask(
        uid: 'actual-blocked',
        summary: 'Actual blocked task',
        durationMinutes: 30,
      );
      await harness.insertActualLog(
        title: 'Confirmed overlap',
        start: DateTime(2026, 6, 8, 9, 5),
        end: DateTime(2026, 6, 8, 9, 20),
        status: ActualActivityStatus.confirmed,
        payloadJson: '{"taskId": $taskId',
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 10),
      );

      expect(result.context.confirmedActualCount, 1);
      expect(result.context.taskEvidence.single.actualCandidateCount, 1);
      expect(result.placements.single.taskId, taskId);
      expect(
        result.placements.single.segments.single.start,
        DateTime(2026, 6, 8, 9, 30),
      );
      expect(
        result.logEntries.where((entry) => entry.level == 'info'),
        isNotEmpty,
      );
    });

    test('cancelled calendar blocks are ignored when choosing free time',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 10 * 60)],
        ),
      );
      addTearDown(harness.close);
      await harness.insertBlock(
        uid: 'cancelled-block',
        summary: 'Cancelled block',
        start: DateTime(2026, 6, 8, 9),
        end: DateTime(2026, 6, 8, 10),
        status: 'CANCELLED',
      );
      final taskId = await harness.insertTask(
        uid: 'cancelled-free',
        summary: 'Cancelled free slot',
        durationMinutes: 30,
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 10),
      );

      expect(result.context.fixedBlockCount, 0);
      expect(result.placements.single.taskId, taskId);
      expect(
        result.placements.single.segments.single.start,
        DateTime(2026, 6, 8, 9),
      );
    });

    test('priority ties fall through due date and summary ordering', () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 11 * 60)],
        ),
      );
      addTearDown(harness.close);
      final noDue = await harness.insertTask(
        uid: 'z-no-due',
        summary: 'No due task',
        durationMinutes: 15,
        priorityLocal: 2,
      );
      final beta = await harness.insertTask(
        uid: 'beta',
        summary: 'Beta same due',
        durationMinutes: 15,
        priorityLocal: 2,
        due: DateTime(2026, 6, 9),
      );
      final alpha = await harness.insertTask(
        uid: 'alpha',
        summary: 'Alpha same due',
        durationMinutes: 15,
        priorityLocal: 2,
        due: DateTime(2026, 6, 9),
      );
      final urgent = await harness.insertTask(
        uid: 'urgent',
        summary: 'Urgent low number',
        durationMinutes: 15,
        priorityLocal: 1,
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 11),
      );

      expect(
        result.placements.map((placement) => placement.taskId),
        [urgent, alpha, beta, noDue],
      );
      expect(
        result.placements.map((placement) => placement.segments.single.start),
        [
          DateTime(2026, 6, 8, 9),
          DateTime(2026, 6, 8, 9, 15),
          DateTime(2026, 6, 8, 9, 30),
          DateTime(2026, 6, 8, 9, 45),
        ],
      );
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
    String status = 'CONFIRMED',
  }) {
    return db.into(db.calendarEvents).insert(
          fixtureEvent(uid: uid, summary: summary, calendarId: calendarId)
              .copyWith(
            dtstart: Value(start),
            dtend: Value(end),
            isBlock: const Value(true),
            status: Value(status),
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

  Future<void> insertTaskWorkLog({
    required int taskId,
    required DateTime start,
    required DateTime end,
    required String status,
  }) async {
    await fusionRepository.insertTaskWorkLog(
      taskId: taskId,
      startAt: start,
      endAt: end,
      confidence: 1,
      sourceType: 'test',
      status: status,
    );
  }

  Future<Map<String, Object?>> savedReport() async {
    return jsonDecode(
      (await db.getSetting('scheduler.last_run_report.v1'))!,
    ) as Map<String, Object?>;
  }
}
