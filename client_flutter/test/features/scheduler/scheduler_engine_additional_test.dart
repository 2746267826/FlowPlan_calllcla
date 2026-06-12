import 'package:flowplanv2/features/scheduler/scheduler_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Scheduler model serialization', () {
    test('serializes run log entries with optional fields', () {
      final start = DateTime(2026, 6, 8, 9);
      final end = DateTime(2026, 6, 8, 9, 30);

      final full = SchedulerRunLogEntry(
        level: 'warning',
        message: 'No room left',
        taskId: 42,
        taskSummary: 'Write proposal',
        start: start,
        end: end,
      ).toJson();

      expect(full, {
        'level': 'warning',
        'message': 'No room left',
        'task_id': 42,
        'task_summary': 'Write proposal',
        'start': '2026-06-08T09:00:00.000',
        'end': '2026-06-08T09:30:00.000',
      });

      final minimal = const SchedulerRunLogEntry(
        level: 'info',
        message: 'Nothing changed',
      ).toJson();

      expect(minimal, {
        'level': 'info',
        'message': 'Nothing changed',
      });
      expect(minimal, isNot(contains('task_id')));
      expect(minimal, isNot(contains('start')));
    });

    test('serializes segment plans and derives duration in minutes', () {
      final segment = SchedulerTaskSegmentPlan(
        start: DateTime(2026, 6, 8, 10, 15),
        end: DateTime(2026, 6, 8, 11),
      );

      expect(segment.durationMinutes, 45);
      expect(segment.toJson(), {
        'start': '2026-06-08T10:15:00.000',
        'end': '2026-06-08T11:00:00.000',
        'duration_minutes': 45,
      });
    });

    test('serializes placements and exposes the first segment as dtstart', () {
      final first = SchedulerTaskSegmentPlan(
        start: DateTime(2026, 6, 8, 13),
        end: DateTime(2026, 6, 8, 13, 30),
      );
      final second = SchedulerTaskSegmentPlan(
        start: DateTime(2026, 6, 8, 15),
        end: DateTime(2026, 6, 8, 15, 45),
      );
      final placement = SchedulerTaskPlacement(
        taskId: 7,
        taskSummary: 'Draft agenda',
        wasRescheduled: true,
        isSplit: true,
        originalDurationMinutes: 90,
        actualWorkedMinutes: 15,
        remainingMinutes: 75,
        reason: 'partial evidence',
        requiredConfirmation: true,
        segments: [first, second],
      );

      expect(placement.dtstart, DateTime(2026, 6, 8, 13));
      expect(placement.toJson(), {
        'task_id': 7,
        'task_summary': 'Draft agenda',
        'was_rescheduled': true,
        'is_split': true,
        'original_duration_minutes': 90,
        'actual_worked_minutes': 15,
        'remaining_minutes': 75,
        'reason': 'partial evidence',
        'required_confirmation': true,
        'segments': [first.toJson(), second.toJson()],
      });
    });

    test('serializes unscheduled tasks and context snapshots', () {
      final evidence = SchedulerTaskEvidence(
        taskId: 9,
        taskSummary: 'Review inbox',
        originalDurationMinutes: 30,
        actualWorkedMinutes: 30,
        remainingMinutes: 0,
        workLogCount: 1,
        actualCandidateCount: 2,
        reason: 'already done',
      );
      final unscheduled = const SchedulerUnscheduledTask(
        taskId: 11,
        taskSummary: 'Plan next sprint',
        reason: 'no free slot',
        originalDurationMinutes: 60,
        actualWorkedMinutes: 10,
        remainingMinutes: 50,
      );
      final context = SchedulerContextSnapshot(
        date: DateTime(2026, 6, 8),
        effectiveStart: DateTime(2026, 6, 8, 9),
        effectiveEnd: DateTime(2026, 6, 8, 18),
        fixedBlockCount: 3,
        confirmedActualCount: 4,
        taskEvidence: [evidence],
        deviationReason: 'late start',
        usesWeatherContext: true,
        usesLocationContext: false,
        usesFileContext: true,
      );

      expect(unscheduled.toJson(), {
        'task_id': 11,
        'task_summary': 'Plan next sprint',
        'reason': 'no free slot',
        'original_duration_minutes': 60,
        'actual_worked_minutes': 10,
        'remaining_minutes': 50,
      });
      expect(context.toJson(), {
        'date': '2026-06-08T00:00:00.000',
        'effective_start': '2026-06-08T09:00:00.000',
        'effective_end': '2026-06-08T18:00:00.000',
        'fixed_block_count': 3,
        'confirmed_actual_count': 4,
        'task_evidence': [evidence.toJson()],
        'deviation_reason': 'late start',
        'uses_weather_context': true,
        'uses_location_context': false,
        'uses_file_context': true,
      });
    });
  });

  group('SchedulerRunResult summaries and JSON', () {
    test('reports scheduled changes and serializes nested details', () {
      final placement = _placement(taskId: 1);
      final result = _result(
        scheduledTaskCount: 1,
        rescheduledTaskCount: 1,
        clearedTaskCount: 1,
        placements: [placement],
        clearedTaskIds: [99],
        logEntries: [_logEntry()],
      );

      expect(result.hasChanges, isTrue);
      expect(result.requiresConfirmation, isTrue);
      expect(result.summary, contains('1'));
      expect(result.toJson(), {
        'date': '2026-06-08T00:00:00.000',
        'plan_run_id': 'run-1',
        'trigger': 'manual_reschedule',
        'effective_start': '2026-06-08T09:00:00.000',
        'effective_end': '2026-06-08T18:00:00.000',
        'scheduled_task_count': 1,
        'rescheduled_task_count': 1,
        'cleared_task_count': 1,
        'unscheduled_task_count': 0,
        'split_suggested_task_count': 0,
        'evidence_completed_task_count': 0,
        'placements': [placement.toJson()],
        'cleared_task_ids': [99],
        'unscheduled_tasks': <Object?>[],
        'log_entries': [_logEntry().toJson()],
        'context': _context().toJson(),
      });
    });

    test('reports unscheduled work without requiring confirmation', () {
      final unscheduled = const SchedulerUnscheduledTask(
        taskId: 12,
        taskSummary: 'Too large for today',
        reason: 'no continuous or split room',
        originalDurationMinutes: 120,
        actualWorkedMinutes: 0,
        remainingMinutes: 120,
      );
      final result = _result(
        unscheduledTaskCount: 1,
        unscheduledTasks: [unscheduled],
      );

      expect(result.hasChanges, isFalse);
      expect(result.requiresConfirmation, isFalse);
      expect(result.summary, contains('1'));
      expect(result.toJson()['unscheduled_tasks'], [unscheduled.toJson()]);
    });

    test('uses the no-change summary when nothing was scheduled or blocked',
        () {
      final result = _result();

      expect(result.hasChanges, isFalse);
      expect(result.requiresConfirmation, isFalse);
      expect(result.summary, isNotEmpty);
      expect(result.summary, isNot(contains('1')));
      expect(result.toJson()['scheduled_task_count'], 0);
      expect(result.toJson()['unscheduled_task_count'], 0);
    });
  });
}

SchedulerRunResult _result({
  int scheduledTaskCount = 0,
  int rescheduledTaskCount = 0,
  int clearedTaskCount = 0,
  int unscheduledTaskCount = 0,
  int splitSuggestedTaskCount = 0,
  int evidenceCompletedTaskCount = 0,
  List<SchedulerTaskPlacement> placements = const <SchedulerTaskPlacement>[],
  List<int> clearedTaskIds = const <int>[],
  List<SchedulerUnscheduledTask> unscheduledTasks =
      const <SchedulerUnscheduledTask>[],
  List<SchedulerRunLogEntry> logEntries = const <SchedulerRunLogEntry>[],
}) {
  return SchedulerRunResult(
    date: DateTime(2026, 6, 8),
    planRunId: 'run-1',
    trigger: 'manual_reschedule',
    effectiveStart: DateTime(2026, 6, 8, 9),
    effectiveEnd: DateTime(2026, 6, 8, 18),
    scheduledTaskCount: scheduledTaskCount,
    rescheduledTaskCount: rescheduledTaskCount,
    clearedTaskCount: clearedTaskCount,
    unscheduledTaskCount: unscheduledTaskCount,
    splitSuggestedTaskCount: splitSuggestedTaskCount,
    evidenceCompletedTaskCount: evidenceCompletedTaskCount,
    placements: placements,
    clearedTaskIds: clearedTaskIds,
    unscheduledTasks: unscheduledTasks,
    logEntries: logEntries,
    context: _context(),
  );
}

SchedulerTaskPlacement _placement({required int taskId}) {
  return SchedulerTaskPlacement(
    taskId: taskId,
    taskSummary: 'Write proposal',
    wasRescheduled: true,
    isSplit: false,
    originalDurationMinutes: 60,
    actualWorkedMinutes: 15,
    remainingMinutes: 45,
    reason: 'partial evidence',
    requiredConfirmation: true,
    segments: [
      SchedulerTaskSegmentPlan(
        start: DateTime(2026, 6, 8, 9, 30),
        end: DateTime(2026, 6, 8, 10, 15),
      ),
    ],
  );
}

SchedulerRunLogEntry _logEntry() {
  return SchedulerRunLogEntry(
    level: 'success',
    message: 'Scheduled',
    taskId: 1,
    taskSummary: 'Write proposal',
    start: DateTime(2026, 6, 8, 9, 30),
    end: DateTime(2026, 6, 8, 10, 15),
  );
}

SchedulerContextSnapshot _context() {
  return SchedulerContextSnapshot(
    date: DateTime(2026, 6, 8),
    effectiveStart: DateTime(2026, 6, 8, 9),
    effectiveEnd: DateTime(2026, 6, 8, 18),
    fixedBlockCount: 0,
    confirmedActualCount: 0,
    taskEvidence: const <SchedulerTaskEvidence>[],
    deviationReason: null,
    usesWeatherContext: false,
    usesLocationContext: false,
    usesFileContext: false,
  );
}
