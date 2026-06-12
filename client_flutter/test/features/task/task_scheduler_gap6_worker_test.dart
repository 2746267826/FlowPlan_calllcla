import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/scheduler/scheduler_engine.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test('task repository rejects creates without an explicit task list',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = TaskRepository(db);

    await expectLater(
      repository.create(
        TaskItemsCompanion.insert(
          uid: 'task-gap6-missing-list',
          dtstamp: fixtureNow(),
          summary: 'Missing list',
        ),
        audit: false,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('task repository empty id filters return empty results', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final repository = TaskRepository(db);

    expect(await repository.getByIds(const <int>[]), isEmpty);
    expect(await repository.getByTaskListIds(const <int>[]), isEmpty);
  });

  test('scheduler model json keeps optional dates out when absent', () {
    const entry = SchedulerRunLogEntry(
      level: 'info',
      message: 'No placement',
    );
    final placement = SchedulerTaskPlacement(
      taskId: 8,
      taskSummary: 'Read brief',
      wasRescheduled: false,
      isSplit: false,
      originalDurationMinutes: 25,
      actualWorkedMinutes: 0,
      remainingMinutes: 25,
      reason: 'single slot',
      requiredConfirmation: false,
      segments: const <SchedulerTaskSegmentPlan>[],
    );

    expect(entry.toJson(), <String, Object?>{
      'level': 'info',
      'message': 'No placement',
    });
    expect(() => placement.dtstart, throwsStateError);
    expect(placement.toJson()['segments'], isEmpty);
  });

  test('task schedule segment models expose duration and nullable json fields',
      () {
    final start = DateTime(2026, 6, 11, 10);
    final end = DateTime(2026, 6, 11, 10, 45);
    final segment = TaskScheduleSegment(
      id: 1,
      taskId: 2,
      segmentIndex: 0,
      startAt: start,
      endAt: end,
      source: 'auto',
      planRunId: null,
      note: null,
      createdAt: start,
      updatedAt: end,
    );
    final draft = TaskScheduleSegmentDraft(
      taskId: 2,
      segmentIndex: 1,
      startAt: DateTime(2026, 6, 11, 11),
      endAt: DateTime(2026, 6, 11, 12),
      source: 'manual',
      planRunId: 'run-gap6',
    );

    expect(segment.durationMinutes, 45);
    expect(segment.toJson(), containsPair('plan_run_id', null));
    expect(segment.toJson(), containsPair('note', null));
    expect(draft.toJson(), containsPair('note', null));
  });
}
