import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/scheduler/plan_feedback_service.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  group('PlanFeedbackService.evaluateNow', () {
    test('returns none when there is no active plan or activity', () async {
      final harness = await _FeedbackHarness.create();
      addTearDown(harness.close);

      final snapshot = await harness.service.evaluateNow();

      expect(snapshot.shouldPrompt, isFalse);
      expect(snapshot.plan, isNull);
      expect(snapshot.activity, isNull);
      expect(snapshot.promptKey, isEmpty);
    });

    test('prompts when current activity is unrelated to active task segment',
        () async {
      final harness = await _FeedbackHarness.create();
      addTearDown(harness.close);
      final now = DateTime.now();
      final taskId = await harness.insertTask(
        uid: 'planned',
        summary: 'Write budget report',
        durationMinutes: 60,
        dtstart: now.subtract(const Duration(minutes: 20)),
      );
      await harness.insertSegment(
        taskId: taskId,
        start: now.subtract(const Duration(minutes: 20)),
        end: now.add(const Duration(minutes: 40)),
      );
      final recordId = await harness.activityRepository.startRecord(
        startTime: now.subtract(const Duration(minutes: 5)),
        processName: 'steam.exe',
        windowTitle: 'Steam Library',
        category: 'games',
        deviceId: 'test-device',
        platform: 'test',
      );

      final snapshot = await harness.service.evaluateNow();

      expect(snapshot.shouldPrompt, isTrue);
      expect(snapshot.plan?.task.id, taskId);
      expect(snapshot.plan?.source, 'segment');
      expect(snapshot.activity?.record.id, recordId);
      expect(snapshot.activity?.label, 'Steam Library');
      expect(snapshot.promptKey, contains('$taskId:'));
      expect(snapshot.promptKey, contains(':$recordId'));
      expect(snapshot.reason, isNotEmpty);
    });

    test('sorts overlapping active segments and reports category deviations',
        () async {
      final harness = await _FeedbackHarness.create();
      addTearDown(harness.close);
      final now = DateTime.now();
      final laterTaskId = await harness.insertTask(
        uid: 'later-overlap',
        summary: 'Later overlap plan',
        durationMinutes: 60,
        dtstart: now.subtract(const Duration(minutes: 15)),
      );
      final earlierTaskId = await harness.insertTask(
        uid: 'earlier-overlap',
        summary: 'Earlier overlap plan',
        durationMinutes: 60,
        dtstart: now.subtract(const Duration(minutes: 30)),
      );
      await harness.insertSegments([
        TaskScheduleSegmentDraft(
          taskId: laterTaskId,
          segmentIndex: 0,
          startAt: now.subtract(const Duration(minutes: 15)),
          endAt: now.add(const Duration(minutes: 45)),
          source: 'test',
          planRunId: 'overlap-run',
        ),
        TaskScheduleSegmentDraft(
          taskId: earlierTaskId,
          segmentIndex: 1,
          startAt: now.subtract(const Duration(minutes: 30)),
          endAt: now.add(const Duration(minutes: 30)),
          source: 'test',
          planRunId: 'overlap-run',
        ),
      ]);
      await harness.activityRepository.startRecord(
        startTime: now.subtract(const Duration(minutes: 10)),
        windowTitle: 'Unrelated window',
        category: String.fromCharCodes(const <int>[0x6e38, 0x620f]),
        deviceId: 'test-device',
        platform: 'test',
      );

      final snapshot = await harness.service.evaluateNow();

      expect(snapshot.shouldPrompt, isTrue);
      expect(snapshot.plan?.task.id, earlierTaskId);
      expect(
        snapshot.reason,
        contains(String.fromCharCodes(const <int>[0x6e38, 0x620f])),
      );
    });

    test('does not prompt inside grace period after plan starts', () async {
      final harness = await _FeedbackHarness.create();
      addTearDown(harness.close);
      final now = DateTime.now();
      final taskId = await harness.insertTask(
        uid: 'fresh-plan',
        summary: 'Fresh plan',
        durationMinutes: 30,
        dtstart: now.subtract(const Duration(minutes: 3)),
      );
      await harness.insertSegment(
        taskId: taskId,
        start: now.subtract(const Duration(minutes: 3)),
        end: now.add(const Duration(minutes: 27)),
      );
      await harness.activityRepository.startRecord(
        startTime: now.subtract(const Duration(minutes: 2)),
        processName: 'steam.exe',
        category: 'games',
        deviceId: 'test-device',
        platform: 'test',
      );

      final snapshot = await harness.service.evaluateNow();

      expect(snapshot.shouldPrompt, isFalse);
    });

    test('treats linked activity records as aligned', () async {
      final harness = await _FeedbackHarness.create();
      addTearDown(harness.close);
      final now = DateTime.now();
      final taskId = await harness.insertTask(
        uid: 'linked-plan',
        summary: 'Write linked report',
        durationMinutes: 60,
        dtstart: now.subtract(const Duration(minutes: 20)),
      );
      await harness.insertSegment(
        taskId: taskId,
        start: now.subtract(const Duration(minutes: 20)),
        end: now.add(const Duration(minutes: 40)),
      );
      await harness.activityRepository.startRecord(
        startTime: now.subtract(const Duration(minutes: 10)),
        processName: 'steam.exe',
        category: 'games',
        linkedTaskId: taskId,
        deviceId: 'test-device',
        platform: 'test',
      );

      final snapshot = await harness.service.evaluateNow();

      expect(snapshot.shouldPrompt, isFalse);
    });

    test('treats task keywords in activity text as aligned', () async {
      final harness = await _FeedbackHarness.create();
      addTearDown(harness.close);
      final now = DateTime.now();
      final taskId = await harness.insertTask(
        uid: 'keyword-plan',
        summary: 'Budget review',
        description: 'Quarterly finance notes',
        durationMinutes: 60,
        dtstart: now.subtract(const Duration(minutes: 20)),
      );
      await harness.insertSegment(
        taskId: taskId,
        start: now.subtract(const Duration(minutes: 20)),
        end: now.add(const Duration(minutes: 40)),
      );
      await harness.activityRepository.startRecord(
        startTime: now.subtract(const Duration(minutes: 10)),
        windowTitle: 'Budget spreadsheet',
        processName: 'excel.exe',
        category: 'documents',
        deviceId: 'test-device',
        platform: 'test',
      );

      final snapshot = await harness.service.evaluateNow();

      expect(snapshot.shouldPrompt, isFalse);
    });

    test('falls back to active scheduled task when no segment exists',
        () async {
      final harness = await _FeedbackHarness.create();
      addTearDown(harness.close);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final planStart = now.difference(today) > const Duration(minutes: 12)
          ? now.subtract(const Duration(minutes: 12))
          : today;
      final taskId = await harness.insertTask(
        uid: 'task-only',
        summary: 'Quarterly budget planning',
        description: 'Spreadsheet finance review',
        durationMinutes: now.difference(planStart).inMinutes + 60,
        dtstart: planStart,
      );
      final recordId = await harness.activityRepository.startRecord(
        startTime: now.subtract(const Duration(minutes: 5)),
        manualLabel: 'Arcade racing session',
        packageName: 'com.arcade.racing',
        category: 'games',
        deviceId: 'test-device',
        platform: 'test',
      );

      final snapshot = await harness.service.evaluateNow();

      expect(snapshot.shouldPrompt, isTrue);
      expect(snapshot.plan?.task.id, taskId);
      expect(snapshot.plan?.source, 'task');
      expect(snapshot.activity?.record.id, recordId);
    });

    test('uses recent ended activity when no active record exists', () async {
      final harness = await _FeedbackHarness.create();
      addTearDown(harness.close);
      final now = DateTime.now();
      final taskId = await harness.insertTask(
        uid: 'recent-activity',
        summary: 'Current plan',
        durationMinutes: 45,
        dtstart: now.subtract(const Duration(minutes: 25)),
      );
      await harness.insertSegment(
        taskId: taskId,
        start: now.subtract(const Duration(minutes: 25)),
        end: now.add(const Duration(minutes: 20)),
      );
      final recordId = await harness.activityRepository.insertImportedRecord(
        startTime: now.subtract(const Duration(minutes: 11)),
        endTime: now.subtract(const Duration(minutes: 1)),
        processName: 'youtube.exe',
        windowTitle: 'YouTube',
        category: 'video',
        deviceId: 'test-device',
        platform: 'test',
      );

      final snapshot = await harness.service.evaluateNow();

      expect(snapshot.shouldPrompt, isTrue);
      expect(snapshot.activity?.record.id, recordId);
      expect(snapshot.activity?.endedAt, isNotNull);
    });

    test('suppresses prompt when snoozed or prompt key was already shown',
        () async {
      final harness = await _FeedbackHarness.create();
      addTearDown(harness.close);
      final now = DateTime.now();
      final taskId = await harness.insertTask(
        uid: 'suppressed',
        summary: 'Suppressed plan',
        durationMinutes: 60,
        dtstart: now.subtract(const Duration(minutes: 20)),
      );
      await harness.insertSegment(
        taskId: taskId,
        start: now.subtract(const Duration(minutes: 20)),
        end: now.add(const Duration(minutes: 40)),
      );
      await harness.activityRepository.startRecord(
        startTime: now.subtract(const Duration(minutes: 10)),
        processName: 'steam.exe',
        category: 'games',
        deviceId: 'test-device',
        platform: 'test',
      );

      await harness.db.setSetting(
        'plan_feedback.deviation_snooze_until',
        now.add(const Duration(minutes: 20)).toIso8601String(),
      );
      expect((await harness.service.evaluateNow()).shouldPrompt, isFalse);

      await harness.db.setSetting(
        'plan_feedback.deviation_snooze_until',
        now.subtract(const Duration(minutes: 1)).toIso8601String(),
      );
      final first = await harness.service.evaluateNow();
      expect(first.shouldPrompt, isTrue);

      await harness.db.setSetting(
        'plan_feedback.last_prompt_key',
        first.promptKey,
      );
      final repeated = await harness.service.evaluateNow();
      expect(repeated.shouldPrompt, isFalse);
    });
  });

  group('PlanFeedbackService.markDecision', () {
    test('records decision settings and audit metadata', () async {
      final harness = await _FeedbackHarness.create();
      addTearDown(harness.close);
      final now = DateTime.now();
      final taskId = await harness.insertTask(
        uid: 'decision',
        summary: 'Decision task',
        durationMinutes: 60,
        dtstart: now.subtract(const Duration(minutes: 20)),
      );
      await harness.insertSegment(
        taskId: taskId,
        start: now.subtract(const Duration(minutes: 20)),
        end: now.add(const Duration(minutes: 40)),
      );
      await harness.activityRepository.startRecord(
        startTime: now.subtract(const Duration(minutes: 10)),
        processName: 'steam.exe',
        category: 'games',
        deviceId: 'test-device',
        platform: 'test',
      );
      final snapshot = await harness.service.evaluateNow();

      await harness.service.markDecision(
        snapshot,
        decision: 'accepted',
        snooze: const Duration(minutes: 5),
      );

      expect(
        await harness.db.getSetting('plan_feedback.last_prompt_key'),
        snapshot.promptKey,
      );
      expect(
        await harness.db.getSetting('plan_feedback.last_decision'),
        'accepted',
      );
      expect(
        DateTime.parse(
          (await harness.db.getSetting(
            'plan_feedback.deviation_snooze_until',
          ))!,
        ).isAfter(DateTime.now()),
        isTrue,
      );

      final rows = await harness.operationLogs.listRecent();
      final decisionRows = rows.where(
        (row) =>
            row.action == 'plan_deviation_decision' &&
            row.entityType == 'scheduler_feedback',
      );
      expect(decisionRows, isNotEmpty);
      expect(decisionRows.first.entityId, snapshot.promptKey);
      expect(
          decisionRows.first.metadataJson, contains('"decision":"accepted"'));
      expect(decisionRows.first.metadataJson, contains('"task_id":$taskId'));
    });
  });
}

class _FeedbackHarness {
  _FeedbackHarness({
    required this.db,
    required this.operationLogs,
    required this.taskRepository,
    required this.activityRepository,
    required this.segmentRepository,
    required this.service,
    required this.taskListId,
  });

  final AppDatabase db;
  final DataOperationLogRepository operationLogs;
  final TaskRepository taskRepository;
  final ActivityRecordRepository activityRepository;
  final TaskScheduleSegmentRepository segmentRepository;
  final PlanFeedbackService service;
  final int taskListId;

  static Future<_FeedbackHarness> create() async {
    final db = createTestDatabase();
    final operationLogs = DataOperationLogRepository(db);
    final taskRepository = TaskRepository(db, operationLogs);
    final activityRepository = ActivityRecordRepository(db);
    final segmentRepository = TaskScheduleSegmentRepository(db, operationLogs);
    final taskListId = await insertFixtureTaskList(db);
    final service = PlanFeedbackService(
      taskRepository: taskRepository,
      activityRepository: activityRepository,
      segmentRepository: segmentRepository,
      operationLogs: operationLogs,
      database: db,
    );
    return _FeedbackHarness(
      db: db,
      operationLogs: operationLogs,
      taskRepository: taskRepository,
      activityRepository: activityRepository,
      segmentRepository: segmentRepository,
      service: service,
      taskListId: taskListId,
    );
  }

  Future<void> close() => db.close();

  Future<int> insertTask({
    required String uid,
    required String summary,
    String? description,
    required int durationMinutes,
    required DateTime dtstart,
    bool isLocked = false,
    bool isAutoScheduled = true,
  }) {
    return taskRepository.create(
      fixtureTask(uid: uid, summary: summary, taskListId: taskListId).copyWith(
        description: Value(description),
        durationMinutes: Value(durationMinutes),
        dtstart: Value(dtstart),
        isLocked: Value(isLocked),
        isAutoScheduled: Value(isAutoScheduled),
      ),
      audit: false,
    );
  }

  Future<void> insertSegment({
    required int taskId,
    required DateTime start,
    required DateTime end,
  }) {
    return segmentRepository.replaceForTasks(
      taskIds: [taskId],
      segments: [
        TaskScheduleSegmentDraft(
          taskId: taskId,
          segmentIndex: 0,
          startAt: start,
          endAt: end,
          source: 'test',
          planRunId: 'test-run',
        ),
      ],
      actor: 'test',
      summary: 'seed segment',
      metadata: const <String, Object?>{},
    );
  }

  Future<void> insertSegments(List<TaskScheduleSegmentDraft> segments) {
    return segmentRepository.replaceForTasks(
      taskIds: segments.map((segment) => segment.taskId),
      segments: segments,
      actor: 'test',
      summary: 'seed overlapping segments',
      metadata: const <String, Object?>{},
    );
  }
}
