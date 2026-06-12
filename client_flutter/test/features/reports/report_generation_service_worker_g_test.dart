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
  group('ReportGenerationService worker G coverage', () {
    test(
        'daily templates include confirmed and candidate facts but exclude rejected actuals',
        () async {
      final harness = await _ReportGenerationHarness.create();
      addTearDown(harness.close);
      final day = DateTime(2026, 6, 10);

      harness.actuals.rows = <ActualActivityLog>[
        _actual(
          id: 1,
          title: 'Confirmed deep work',
          startAt: day.add(const Duration(hours: 9)),
          endAt: day.add(const Duration(hours: 10)),
          status: ActualActivityStatus.confirmed,
          confidence: 0.91,
        ),
        _actual(
          id: 2,
          title: 'Candidate follow-up',
          startAt: day.add(const Duration(hours: 11)),
          endAt: day.add(const Duration(hours: 11, minutes: 30)),
          status: ActualActivityStatus.candidate,
          confidence: 0.64,
        ),
        _actual(
          id: 3,
          title: 'Rejected noise',
          startAt: day.add(const Duration(hours: 12)),
          endAt: day.add(const Duration(hours: 12, minutes: 15)),
          status: ActualActivityStatus.rejected,
        ),
      ];
      await harness.fusion.insertSegment(
        ActivitySegmentDraft(
          startAt: day.add(const Duration(hours: 13)),
          endAt: day.add(const Duration(hours: 13, minutes: 45)),
          sourceRecordIds: const <int>[1],
          evidence: const <String, Object?>{'source': 'test'},
          category: 'writing',
          label: 'Writing report segment',
          confidence: 0.88,
        ),
        sync: false,
        audit: false,
      );

      final result = await harness.service.generateDaily(day);

      expect(result.report.summaryMarkdown, contains('Confirmed deep work'));
      expect(result.report.summaryMarkdown, contains('Candidate follow-up'));
      expect(result.report.summaryMarkdown, contains('64%'));
      expect(result.report.summaryMarkdown, isNot(contains('Rejected noise')));
      expect(result.diary!.bodyMarkdown, contains('Confirmed deep work'));
      expect(result.diary!.bodyMarkdown, contains('Writing report segment'));
      expect(
          result.diary!.bodyMarkdown, isNot(contains('Candidate follow-up')));

      final metrics =
          jsonDecode(result.report.metricsJson) as Map<String, dynamic>;
      expect(metrics['actual_count'], 2);
      expect(metrics['confirmed_actual_count'], 1);
      expect(metrics['activity_segment_count'], 1);

      final snapshot =
          jsonDecode(result.report.sourceSnapshotJson) as Map<String, dynamic>;
      expect(
        (snapshot['actuals'] as List)
            .map((item) => (item as Map<String, dynamic>)['title']),
        containsAll(<String>['Confirmed deep work', 'Candidate follow-up']),
      );
      expect(snapshot['actuals'].toString(), isNot(contains('Rejected noise')));
    });

    test('source snapshot caps large collections while metrics keep totals',
        () async {
      final harness = await _ReportGenerationHarness.create();
      addTearDown(harness.close);
      final day = DateTime(2026, 6, 11);
      await harness.seedCalendar();

      for (var i = 0; i < 55; i++) {
        await harness.events.create(
          CalendarEventsCompanion.insert(
            uid: 'event-$i',
            dtstamp: day,
            summary: 'Report event $i',
            dtstart: day.add(Duration(minutes: i)),
            dtend: Value(day.add(Duration(minutes: i + 1))),
            eventCalendarId: Value(harness.calendarId),
          ),
          audit: false,
        );
        harness.actuals.rows.add(
          _actual(
            id: i + 1,
            title: 'Actual $i',
            startAt: day.add(Duration(hours: 1, minutes: i)),
            endAt: day.add(Duration(hours: 1, minutes: i + 1)),
            status: ActualActivityStatus.candidate,
          ),
        );
        await harness.fusion.insertSegment(
          ActivitySegmentDraft(
            startAt: day.add(Duration(hours: 2, minutes: i)),
            endAt: day.add(Duration(hours: 2, minutes: i + 1)),
            sourceRecordIds: <int>[i],
            evidence: <String, Object?>{'index': i},
            label: 'Segment $i',
          ),
          sync: false,
          audit: false,
        );
      }

      final result = await harness.service.generateDaily(
        day,
        includeDiaryDraft: false,
      );

      final metrics =
          jsonDecode(result.report.metricsJson) as Map<String, dynamic>;
      expect(metrics['event_count'], 55);
      expect(metrics['actual_count'], 55);
      expect(metrics['activity_segment_count'], 55);

      final snapshot =
          jsonDecode(result.report.sourceSnapshotJson) as Map<String, dynamic>;
      expect(snapshot['events'], hasLength(50));
      expect(snapshot['actuals'], hasLength(50));
      expect(snapshot['activity_segments'], hasLength(50));
      expect(result.diary, isNull);
    });
  });
}

class _ReportGenerationHarness {
  _ReportGenerationHarness._({
    required this.db,
    required this.service,
    required this.events,
    required this.actuals,
    required this.fusion,
  });

  final AppDatabase db;
  final ReportGenerationService service;
  final EventRepository events;
  final _FakeActualActivityLogRepository actuals;
  final ActivityFusionRepository fusion;
  late final int calendarId;

  static Future<_ReportGenerationHarness> create() async {
    final db = createTestDatabase();
    final actuals = _FakeActualActivityLogRepository(db);
    final service = ReportGenerationService(
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
    return _ReportGenerationHarness._(
      db: db,
      service: service,
      events: EventRepository(db),
      actuals: actuals,
      fusion: ActivityFusionRepository(db),
    );
  }

  Future<void> seedCalendar() async {
    calendarId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Reports calendar',
            createdAt: DateTime(2026, 6, 11),
            isDefault: const Value(true),
          ),
        );
  }

  Future<void> close() => db.close();
}

class _FakeActualActivityLogRepository extends ActualActivityLogRepository {
  _FakeActualActivityLogRepository(super.db);

  List<ActualActivityLog> rows = <ActualActivityLog>[];

  @override
  Future<List<ActualActivityLog>> listInRange(
    DateTime start,
    DateTime end, {
    Iterable<String>? statuses,
  }) async {
    final statusSet = statuses?.toSet();
    return rows
        .where((row) => row.startAt.isBefore(end) && row.endAt.isAfter(start))
        .where((row) => statusSet == null || statusSet.contains(row.status))
        .toList()
      ..sort((left, right) => left.startAt.compareTo(right.startAt));
  }
}

ActualActivityLog _actual({
  required int id,
  required String title,
  required DateTime startAt,
  required DateTime endAt,
  required String status,
  double confidence = 0.75,
}) {
  final createdAt = DateTime(2026, 6, 10, 8).add(Duration(minutes: id));
  return ActualActivityLog(
    id: id,
    actualUid: 'actual-$id',
    title: title,
    startAt: startAt,
    endAt: endAt,
    sourceType: ActualActivitySourceType.trackingInference,
    sourceId: 'source-$id',
    sourcePayloadJson: '{}',
    confidence: confidence,
    status: status,
    note: null,
    createdAt: createdAt,
    updatedAt: createdAt,
    confirmedAt: status == ActualActivityStatus.confirmed ? createdAt : null,
    rejectedAt: status == ActualActivityStatus.rejected ? createdAt : null,
    mergedIntoId: null,
  );
}
