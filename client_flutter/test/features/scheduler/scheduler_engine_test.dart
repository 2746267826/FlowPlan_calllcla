import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
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
  group('SchedulerEngine.autoScheduleDetailed', () {
    test('places pending tasks by business priority around fixed blocks',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 11 * 60)],
        ),
      );
      addTearDown(harness.close);
      final date = DateTime(2026, 6, 8);

      await harness.insertBlock(
        uid: 'standup',
        summary: 'Standup',
        start: DateTime(2026, 6, 8, 9),
        end: DateTime(2026, 6, 8, 9, 30),
      );
      final low = await harness.insertTask(
        uid: 'low',
        summary: 'Low priority follow-up',
        durationMinutes: 30,
        priorityLocal: 3,
      );
      final high = await harness.insertTask(
        uid: 'high',
        summary: 'High priority proposal',
        durationMinutes: 30,
        priorityLocal: 1,
      );

      final result = await harness.engine.autoScheduleDetailed(
        date,
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 11),
      );

      expect(result.scheduledTaskCount, 2);
      expect(result.unscheduledTaskCount, 0);
      expect(result.placements.map((item) => item.taskId), [high, low]);
      expect(result.placements.first.segments.single.start,
          DateTime(2026, 6, 8, 9, 30));
      expect(result.placements.last.segments.single.start,
          DateTime(2026, 6, 8, 10));
      expect(result.context.fixedBlockCount, 1);
      expect(
        result.logEntries.map((entry) => entry.level),
        containsAll(<String>['info', 'success']),
      );
    });

    test('reports every pending task when selected range has no work window',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(DateTime.monday, const <WorkTimeRange>[]),
      );
      addTearDown(harness.close);
      final taskId = await harness.insertTask(
        uid: 'no-window',
        summary: 'No available window',
        durationMinutes: 45,
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 10),
      );

      expect(result.scheduledTaskCount, 0);
      expect(result.unscheduledTaskCount, 1);
      expect(result.unscheduledTasks.single.taskId, taskId);
      expect(result.logEntries.single.level, 'warning');

      final savedReport = jsonDecode(
        (await harness.db.getSetting('scheduler.last_run_report.v1'))!,
      ) as Map<String, Object?>;
      expect(savedReport['unscheduled_task_count'], 1);
      expect(savedReport['scheduled_task_count'], 0);
    });

    test('keeps locked scheduled work as an immutable blocker', () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 10 * 60)],
        ),
      );
      addTearDown(harness.close);
      final locked = await harness.insertTask(
        uid: 'locked',
        summary: 'Locked existing task',
        durationMinutes: 60,
        dtstart: DateTime(2026, 6, 8, 9),
        isLocked: true,
      );
      final pending = await harness.insertTask(
        uid: 'pending',
        summary: 'Needs an opening',
        durationMinutes: 30,
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 10),
      );

      expect(result.scheduledTaskCount, 0);
      expect(result.unscheduledTaskCount, 1);
      expect(result.unscheduledTasks.single.taskId, pending);
      expect(result.placements.map((item) => item.taskId),
          isNot(contains(locked)));
    });

    test('suggests split segments when no continuous slot fits', () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [
            WorkTimeRange(startMinute: 9 * 60, endMinute: 9 * 60 + 30),
            WorkTimeRange(startMinute: 10 * 60, endMinute: 10 * 60 + 30),
          ],
        ),
      );
      addTearDown(harness.close);
      final taskId = await harness.insertTask(
        uid: 'split',
        summary: 'Split friendly task',
        durationMinutes: 60,
        isSplittable: true,
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 10, 30),
      );

      expect(result.scheduledTaskCount, 1);
      expect(result.splitSuggestedTaskCount, 1);
      final placement = result.placements.single;
      expect(placement.taskId, taskId);
      expect(placement.isSplit, isTrue);
      expect(placement.segments.map((item) => item.durationMinutes), [30, 30]);
      expect(
        placement.segments.map((item) => item.start),
        [DateTime(2026, 6, 8, 9), DateTime(2026, 6, 8, 10)],
      );
    });

    test('confirmed work evidence clears completed work from new schedule',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 10 * 60)],
        ),
      );
      addTearDown(harness.close);
      final taskId = await harness.insertTask(
        uid: 'evidence-done',
        summary: 'Already completed by actual work',
        durationMinutes: 30,
      );
      await harness.insertTaskWorkLog(
        taskId: taskId,
        start: DateTime(2026, 6, 8, 8, 20),
        end: DateTime(2026, 6, 8, 8, 50),
        status: 'confirmed',
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 10),
      );

      expect(result.scheduledTaskCount, 0);
      expect(result.unscheduledTaskCount, 0);
      expect(result.evidenceCompletedTaskCount, 1);
      expect(result.clearedTaskIds, [taskId]);
      expect(result.context.taskEvidence.single.remainingMinutes, 0);
    });

    test('falls back invalid durations and allows an exact midnight boundary',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [
            WorkTimeRange(startMinute: 23 * 60 + 30, endMinute: 24 * 60),
          ],
        ),
      );
      addTearDown(harness.close);
      final taskId = await harness.insertTask(
        uid: 'midnight',
        summary: 'Ends at midnight',
        durationMinutes: 0,
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 23, 30),
      );

      final placement = result.placements.single;
      expect(placement.taskId, taskId);
      expect(placement.originalDurationMinutes, 30);
      expect(placement.remainingMinutes, 30);
      expect(placement.segments.single.start, DateTime(2026, 6, 8, 23, 30));
      expect(placement.segments.single.end, DateTime(2026, 6, 9));
    });
  });

  group('SchedulerEngine.applyRunResult', () {
    test('writes single and split segment plans after confirmation', () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [
            WorkTimeRange(startMinute: 9 * 60, endMinute: 9 * 60 + 30),
            WorkTimeRange(startMinute: 10 * 60, endMinute: 10 * 60 + 30),
          ],
        ),
      );
      addTearDown(harness.close);
      final taskId = await harness.insertTask(
        uid: 'apply-split',
        summary: 'Apply split plan',
        durationMinutes: 60,
        isSplittable: true,
      );
      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 10, 30),
      );

      await harness.engine.applyRunResult(result);

      final updated = await harness.taskRepository.getById(taskId);
      final segments = await harness.segmentRepository.getByTaskId(taskId);
      final auditRows = await harness.operationLogs.listRecent();

      expect(updated?.dtstart, DateTime(2026, 6, 8, 9));
      expect(segments.map((item) => item.source), ['auto_split', 'auto_split']);
      expect(segments.map((item) => item.segmentIndex), [0, 1]);
      expect(
        auditRows.map((row) => row.action),
        containsAll(<String>[
          'replace_task_schedule_segments',
          'apply_scheduler_plan',
        ]),
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
}
