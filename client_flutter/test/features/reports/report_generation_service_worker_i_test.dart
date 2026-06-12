import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/actual/data/actual_activity_log_repository.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/reports/data/report_repository.dart';
import 'package:flowplanv2/features/reports/services/report_generation_service.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_fusion_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  group('ReportGenerationService', () {
    test('generates daily report and diary with complete source snapshot',
        () async {
      final harness = await _GenerationHarness.create();
      addTearDown(harness.close);
      final day = DateTime(2026, 6, 10);
      final data = await harness.seedReportInputs(day);

      final result = await harness.service.generateDaily(day);

      expect(result.report.reportType, ReportType.daily);
      expect(result.report.periodStart, day);
      expect(result.report.periodEnd, DateTime(2026, 6, 11));
      expect(result.report.summaryMarkdown, contains('Editor research'));

      final metrics =
          jsonDecode(result.report.metricsJson) as Map<String, dynamic>;
      expect(metrics['event_count'], 1);
      expect(metrics['schedule_segment_count'], 1);
      expect(metrics['actual_count'], 0);
      expect(metrics['confirmed_actual_count'], 0);
      expect(metrics['activity_segment_count'], 1);
      expect(metrics['completed_task_count'], 1);
      expect(metrics['scheduled_task_count'], 1);
      expect(metrics['task_work_minutes'], 45);

      final snapshot =
          jsonDecode(result.report.sourceSnapshotJson) as Map<String, dynamic>;
      expect(snapshot['start'], day.toIso8601String());
      expect(snapshot['end'], DateTime(2026, 6, 11).toIso8601String());
      expect(snapshot['single_day'], day.toIso8601String());
      expect(snapshot['events'], hasLength(1));
      expect(snapshot['actuals'], isEmpty);
      expect(snapshot['activity_segments'], hasLength(1));
      expect(
        (snapshot['task_work_by_task']
            as Map<String, dynamic>)['${data.completedTaskId}'],
        45,
      );

      final diary = result.diary;
      expect(diary, isNotNull);
      expect(diary!.sourceReportId, result.report.id);
      expect(diary.entryDate, day);
      expect(diary.bodyMarkdown, startsWith('# 2026-06-10'));
      expect(jsonDecode(diary.linkedTaskIdsJson), <Object?>[
        data.completedTaskId,
      ]);
      expect(diary.weatherJson, '{}');
      expect(diary.locationJson, '{}');
    });

    test('can generate daily report without a diary draft for empty days',
        () async {
      final harness = await _GenerationHarness.create();
      addTearDown(harness.close);
      final day = DateTime(2026, 6, 12);

      final result = await harness.service.generateDaily(
        day,
        includeDiaryDraft: false,
      );

      expect(result.diary, isNull);
      expect(result.report.periodStart, day);
      final metrics =
          jsonDecode(result.report.metricsJson) as Map<String, dynamic>;
      expect(metrics['event_count'], 0);
      expect(metrics['actual_count'], 0);
      expect(metrics['task_work_minutes'], 0);
      expect(result.report.summaryMarkdown, contains('#'));
    });

    test('generates weekly and monthly reports over normalized periods',
        () async {
      final harness = await _GenerationHarness.create();
      addTearDown(harness.close);
      final day = DateTime(2026, 6, 10);
      final data = await harness.seedReportInputs(day);

      final weekly =
          await harness.service.generateWeekly(DateTime(2026, 6, 12));
      final monthly =
          await harness.service.generateMonthly(DateTime(2026, 6, 30));

      expect(weekly.reportType, ReportType.weekly);
      expect(weekly.periodStart, DateTime(2026, 6, 8));
      expect(weekly.periodEnd, DateTime(2026, 6, 15));
      expect(weekly.summaryMarkdown, contains('#${data.completedTaskId}'));
      expect(
        (jsonDecode(weekly.metricsJson)
            as Map<String, dynamic>)['task_work_minutes'],
        45,
      );

      expect(monthly.reportType, ReportType.monthly);
      expect(monthly.periodStart, DateTime(2026, 6));
      expect(monthly.periodEnd, DateTime(2026, 7));
      final monthlySnapshot =
          jsonDecode(monthly.sourceSnapshotJson) as Map<String, dynamic>;
      expect(monthlySnapshot['single_day'], isNull);
      expect(monthlySnapshot['events'], hasLength(1));
      expect(
        (monthlySnapshot['task_work_by_task']
            as Map<String, dynamic>)['${data.completedTaskId}'],
        45,
      );
    });
  });
}

class _SeededReportInputs {
  const _SeededReportInputs({
    required this.completedTaskId,
    required this.scheduledTaskId,
  });

  final int completedTaskId;
  final int scheduledTaskId;
}

class _GenerationHarness {
  _GenerationHarness._({
    required this.db,
    required this.service,
    required this.events,
    required this.tasks,
    required this.actuals,
    required this.fusion,
  });

  final AppDatabase db;
  final ReportGenerationService service;
  final EventRepository events;
  final TaskRepository tasks;
  final ActualActivityLogRepository actuals;
  final ActivityFusionRepository fusion;

  static Future<_GenerationHarness> create() async {
    final db = createTestDatabase();
    final reports = ReportRepository(db);
    final events = EventRepository(db);
    final tasks = TaskRepository(db);
    final actuals = ActualActivityLogRepository(db);
    final fusion = ActivityFusionRepository(db);
    final segments = TaskScheduleSegmentRepository(
      db,
      DataOperationLogRepository(db),
    );
    final service = ReportGenerationService(
      reportRepository: reports,
      eventRepository: events,
      taskRepository: tasks,
      segmentRepository: segments,
      actualRepository: actuals,
      fusionRepository: fusion,
    );
    return _GenerationHarness._(
      db: db,
      service: service,
      events: events,
      tasks: tasks,
      actuals: actuals,
      fusion: fusion,
    );
  }

  Future<_SeededReportInputs> seedReportInputs(DateTime day) async {
    final calendarId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Reports calendar',
            createdAt: day,
            isDefault: const Value(true),
          ),
        );
    final taskListId = await db.into(db.taskLists).insert(
          TaskListsCompanion.insert(
            name: 'Reports tasks',
            createdAt: day,
            isDefault: const Value(true),
          ),
        );

    await events.create(
      CalendarEventsCompanion.insert(
        uid: 'event-report-review',
        dtstamp: day,
        summary: 'Review generated report',
        dtstart: day.add(const Duration(hours: 9)),
        dtend: Value(day.add(const Duration(hours: 10))),
        eventCalendarId: Value(calendarId),
      ),
      audit: false,
    );

    final completedTaskId = await tasks.create(
      TaskItemsCompanion.insert(
        uid: 'task-completed-report',
        dtstamp: day,
        summary: 'Ship report draft',
        completed: Value(day.add(const Duration(hours: 16))),
        status: const Value('COMPLETED'),
        percentComplete: const Value(100),
        taskListId: Value(taskListId),
      ),
      audit: false,
    );
    final scheduledTaskId = await tasks.create(
      TaskItemsCompanion.insert(
        uid: 'task-scheduled-report',
        dtstamp: day,
        summary: 'Plan report follow-up',
        dtstart: Value(day.add(const Duration(hours: 13))),
        taskListId: Value(taskListId),
      ),
      audit: false,
    );

    await db.customStatement(
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
      <Object?>[
        scheduledTaskId,
        0,
        day.add(const Duration(hours: 13)).toIso8601String(),
        day.add(const Duration(hours: 14)).toIso8601String(),
        'test',
        'plan-run-1',
        'scheduled for report',
        day.toIso8601String(),
        day.toIso8601String(),
      ],
    );

    final segment = await fusion.insertSegment(
      ActivitySegmentDraft(
        startAt: day.add(const Duration(hours: 12)),
        endAt: day.add(const Duration(hours: 12, minutes: 45)),
        sourceRecordIds: const <int>[101],
        evidence: const <String, Object?>{'window': 'editor'},
        primaryProcessName: 'Code.exe',
        primaryWindowTitle: 'report_generation_service.dart',
        category: 'coding',
        label: 'Editor research',
        confidence: 0.88,
      ),
      sync: false,
      audit: false,
    );
    await fusion.insertTaskWorkLog(
      taskId: completedTaskId,
      segmentId: segment.id,
      startAt: day.add(const Duration(hours: 12)),
      endAt: day.add(const Duration(hours: 12, minutes: 45)),
      confidence: 0.91,
      sourceType: 'test',
      status: 'confirmed',
    );

    return _SeededReportInputs(
      completedTaskId: completedTaskId,
      scheduledTaskId: scheduledTaskId,
    );
  }

  Future<void> close() => db.close();
}
