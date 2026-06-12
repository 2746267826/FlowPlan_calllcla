import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/actual/data/actual_activity_log_repository.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/reports/data/report_repository.dart';
import 'package:flowplanv2/features/reports/services/report_generation_service.dart';
import 'package:flowplanv2/features/reports/services/report_push_service.dart';
import 'package:flowplanv2/features/scheduler/scheduler_engine.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_fusion_repository.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/ical_import_export_harness.dart';
import '../../test_support/test_database.dart';

void main() {
  group('Reports / iCal / Scheduler gap9 worker coverage', () {
    test('report status value holders remain constructible', () {
      expect(const ReportType(), isA<ReportType>());
      expect(const ReportStatus(), isA<ReportStatus>());
      expect(const PushDeliveryStatus(), isA<PushDeliveryStatus>());
      expect(ReportType.monthly, 'monthly');
      expect(ReportStatus.archived, 'archived');
      expect(PushDeliveryStatus.sending, 'sending');
    });

    test('empty daily generation writes the diary empty-state prompt',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final actuals = _EmptyActualActivityLogRepository(db);
      final generation = ReportGenerationService(
        reportRepository: ReportRepository(db),
        eventRepository: EventRepository(db),
        taskRepository: TaskRepository(db),
        segmentRepository: TaskScheduleSegmentRepository(
          db,
          DataOperationLogRepository(db),
        ),
        actualRepository: actuals,
        fusionRepository: ActivityFusionRepository(db),
      );

      final result = await generation.generateDaily(DateTime(2026, 6, 12));

      expect(result.diary, isNotNull);
      expect(
        result.diary!.bodyMarkdown,
        contains('目前还没有足够的实际记录或活动片段'),
      );
    });

    test('webhook deliveries decode JSON payloads before posting', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ReportRepository(db);
      final bodies = <Map<String, dynamic>>[];
      final service = ReportPushService(
        database: db,
        reportRepository: repository,
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response('ok', 200);
        }),
      );
      await repository.queueDelivery(
        channel: 'webhook',
        target: 'https://hooks.example/gap9',
        payload: const <String, Object?>{
          'event': 'report.ready',
          'nested': <String, Object?>{'report_id': 7},
        },
        scheduledAt: DateTime.now().subtract(const Duration(minutes: 1)),
      );

      final result = await service.sendPendingWebhooks();

      expect(result.sent, 1);
      expect(result.failed, 0);
      expect(bodies.single, containsPair('event', 'report.ready'));
      expect(
        bodies.single['nested'],
        containsPair('report_id', 7),
      );
    });

    test('segment repository reads string true booleans from raw rows',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = TaskScheduleSegmentRepository(
        db,
        DataOperationLogRepository(db),
      );
      final taskListId = await insertFixtureTaskList(db);
      final taskId = await _insertRawTask(
        db,
        id: 901,
        uid: 'string-true-bools',
        summary: 'String true bools',
        taskListId: taskListId,
        isSplittable: 1,
        isAutoScheduled: 1,
        isLocked: 1,
      );
      await _insertRawSegment(
        db,
        taskId: taskId,
        start: DateTime(2026, 6, 12, 9),
        end: DateTime(2026, 6, 12, 9, 30),
      );

      final item = (await repository.getForDate(DateTime(2026, 6, 12))).single;

      expect(item.task.isSplittable, isTrue);
      expect(item.task.isAutoScheduled, isTrue);
      expect(item.task.isLocked, isTrue);
    });

    test('scheduler orders scheduled starts before tasks without starts',
        () async {
      final harness = await _SchedulerHarness.create(
        schedule: _scheduleFor(
          DateTime.monday,
          const [WorkTimeRange(startMinute: 9 * 60, endMinute: 11 * 60)],
        ),
      );
      addTearDown(harness.close);
      final due = await harness.insertTask(
        uid: 'due-before-scheduled',
        summary: 'Due before scheduled',
        durationMinutes: 15,
        due: DateTime(2026, 6, 9),
      );
      final scheduled = await harness.insertTask(
        uid: 'scheduled-before-floating',
        summary: 'Scheduled before floating',
        durationMinutes: 15,
        dtstart: DateTime(2026, 6, 8, 10),
      );
      final floating = await harness.insertTask(
        uid: 'floating-after-scheduled',
        summary: 'Floating after scheduled',
        durationMinutes: 15,
      );

      final result = await harness.engine.autoScheduleDetailed(
        DateTime(2026, 6, 8),
        from: DateTime(2026, 6, 8, 9),
        until: DateTime(2026, 6, 8, 11),
      );

      expect(
        result.placements.map((placement) => placement.taskId),
        <int>[due, scheduled, floating],
      );
    });

    testWidgets('replace iCal import reports the replace-calendar summary',
        (tester) async {
      final harness = await ICalImportExportHarness.pump(tester);
      final calendarId = await harness.createCalendar(
        name: 'Gap9 Replace',
        isDefault: true,
      );
      await harness.createEvent(
        calendarId: calendarId,
        uid: 'old-gap9',
        summary: 'Old gap9 event',
      );
      await pumpIcalFrames(tester);

      await _tapChoiceChip(tester, '清空后导入');
      harness.filePicker.queuePickText(
        name: 'replace-gap9.ics',
        content: _ics([
          _vevent(
            uid: 'new-gap9',
            summary: 'New gap9 event',
            start: '20260612T090000',
            end: '20260612T100000',
          ),
        ]),
      );

      await _tapIcalButtonWithRealAsync(tester, '选择文件');
      await pumpUntilIcalFound(tester, find.byType(AlertDialog));
      await _tapDialogButtonWithRealAsync(tester, '继续');
      await pumpIcalFrames(tester);

      final events = await harness.eventsInCalendar(calendarId);
      expect(events.map((event) => event.uid), <String>['new-gap9']);
    });
  });
}

class _EmptyActualActivityLogRepository extends ActualActivityLogRepository {
  _EmptyActualActivityLogRepository(super.db);

  @override
  Future<List<ActualActivityLog>> listInRange(
    DateTime start,
    DateTime end, {
    Iterable<String>? statuses,
  }) async {
    return const <ActualActivityLog>[];
  }
}

WeeklyWorkSchedule _scheduleFor(int weekday, List<WorkTimeRange> ranges) {
  return WeeklyWorkSchedule({weekday: ranges});
}

class _SchedulerHarness {
  _SchedulerHarness({
    required this.db,
    required this.taskRepository,
    required this.engine,
    required this.taskListId,
  });

  final AppDatabase db;
  final TaskRepository taskRepository;
  final SchedulerEngine engine;
  final int taskListId;

  static Future<_SchedulerHarness> create({
    required WeeklyWorkSchedule schedule,
  }) async {
    final db = createTestDatabase();
    final operationLogs = DataOperationLogRepository(db);
    final taskRepository = TaskRepository(db, operationLogs);
    final taskListId = await insertFixtureTaskList(db);
    final engine = SchedulerEngine(
      taskRepository,
      EventRepository(db, operationLogs),
      db,
      schedule,
      TaskScheduleSegmentRepository(db, operationLogs),
      operationLogs,
      ActualActivityLogRepository(db, operationLogs),
      ActivityFusionRepository(db, operationLogs),
    );
    return _SchedulerHarness(
      db: db,
      taskRepository: taskRepository,
      engine: engine,
      taskListId: taskListId,
    );
  }

  Future<void> close() => db.close();

  Future<int> insertTask({
    required String uid,
    required String summary,
    required int durationMinutes,
    DateTime? due,
    DateTime? dtstart,
  }) {
    return taskRepository.create(
      fixtureTask(uid: uid, summary: summary, taskListId: taskListId).copyWith(
        durationMinutes: Value(durationMinutes),
        due: Value(due),
        dtstart: Value(dtstart),
        isAutoScheduled: const Value(true),
      ),
      audit: false,
    );
  }
}

Future<int> _insertRawTask(
  AppDatabase db, {
  required int id,
  required String uid,
  required String summary,
  required int taskListId,
  required int isSplittable,
  required int isAutoScheduled,
  required int isLocked,
}) async {
  await db.customStatement(
    '''
    INSERT INTO task_items (
      id,
      uid,
      dtstamp,
      summary,
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
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      id,
      uid,
      '2026-06-12T08:00:00.000',
      summary,
      0,
      'NEEDS-ACTION',
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
  required DateTime start,
  required DateTime end,
}) {
  final now = DateTime(2026, 6, 12, 8).toIso8601String();
  return db.customStatement(
    '''
    INSERT INTO task_schedule_segments (
      task_id,
      segment_index,
      start_at,
      end_at,
      source,
      created_at,
      updated_at
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''',
    [
      taskId,
      0,
      start.toIso8601String(),
      end.toIso8601String(),
      'gap9',
      now,
      now,
    ],
  );
}

Future<void> _tapChoiceChip(WidgetTester tester, String label) async {
  final chip = find.widgetWithText(ChoiceChip, label);
  expect(chip, findsOneWidget);
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pump();
}

Future<void> _tapDialogButtonWithRealAsync(
  WidgetTester tester,
  String label,
) async {
  final buttonLabel = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.text(label),
  );
  expect(buttonLabel, findsOneWidget);
  await tester.runAsync(() async {
    await tester.tap(buttonLabel);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

Future<void> _tapIcalButtonWithRealAsync(
  WidgetTester tester,
  String text,
) async {
  final finder = find.text(text);
  await tester.ensureVisible(finder.last);
  await tester.runAsync(() async {
    await tester.tap(finder.last);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

String _ics(List<String> events) {
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    ...events.map((event) => event.trim()),
    'END:VCALENDAR',
    '',
  ].join('\r\n');
}

String _vevent({
  required String uid,
  required String summary,
  required String start,
  required String end,
}) {
  return '''
BEGIN:VEVENT
UID:$uid
SUMMARY:$summary
DTSTART:$start
DTEND:$end
STATUS:CONFIRMED
END:VEVENT
''';
}
