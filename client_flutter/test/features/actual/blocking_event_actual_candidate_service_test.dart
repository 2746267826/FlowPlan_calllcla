import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/actual/data/actual_activity_log_repository.dart';
import 'package:flowplanv2/features/actual/services/blocking_event_actual_candidate_service.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  group('BlockingEventActualCandidateService', () {
    late AppDatabase db;
    late ActualActivityLogRepository actualLogs;
    late ActivityRecordRepository activityRecords;
    late BlockingEventActualCandidateService service;

    setUp(() {
      db = createTestDatabase();
      actualLogs = ActualActivityLogRepository(db);
      activityRecords = ActivityRecordRepository(db);
      service = BlockingEventActualCandidateService(
        db,
        actualLogs,
        activityRecords,
      );
    });

    tearDown(() async {
      await actualLogs.dispose();
      await db.close();
    });

    test('creates candidates for ended blocking events with source payload',
        () async {
      final base = DateTime.utc(2026, 6, 10, 9);
      final eventId = await _insertEvent(
        db,
        uid: 'ended-block',
        summary: 'Client workshop',
        start: base,
        end: base.add(const Duration(hours: 1)),
        location: 'Room 3',
        source: 'outlook',
      );
      await _insertEvent(
        db,
        uid: 'plain-event',
        summary: 'Visible but not blocking',
        start: base.add(const Duration(hours: 2)),
        isBlock: false,
      );
      await _insertEvent(
        db,
        uid: 'cancelled-block',
        summary: 'Cancelled block',
        start: base.add(const Duration(hours: 3)),
        status: 'cancelled',
      );

      final result = await service.generateForRange(
        start: base.subtract(const Duration(hours: 1)),
        end: base.add(const Duration(days: 1)),
        now: base.add(const Duration(days: 1)),
      );
      final event = await _eventById(db, eventId);

      expect(result.created, 1);
      expect(result.skippedTotal, 0);
      final actual = await actualLogs.getBySource(
        sourceType: ActualActivitySourceType.blockingEvent,
        sourceId: eventId.toString(),
      );
      expect(actual == null, isFalse);
      expect(actual!.title, 'Client workshop');
      expect(actual.startAt, event.dtstart);
      expect(actual.endAt, event.dtend);
      expect(actual.confidence, 0.82);
      expect(actual.status, ActualActivityStatus.candidate);
      expect(actual.note, isNotEmpty);

      final payload =
          jsonDecode(actual.sourcePayloadJson) as Map<String, dynamic>;
      expect(payload, containsPair('eventId', eventId));
      expect(payload, containsPair('eventUid', 'ended-block'));
      expect(payload, containsPair('location', 'Room 3'));
      expect(payload, containsPair('source', 'outlook'));
      expect(payload, containsPair('isBlock', true));
    });

    test('skips existing candidates but regenerates after rejection', () async {
      final base = DateTime.utc(2026, 6, 10, 9);
      final eventId = await _insertEvent(
        db,
        uid: 'source-dedupe',
        summary: 'Planning block',
        start: base,
        end: base.add(const Duration(minutes: 45)),
      );

      final first = await service.generateForRange(
        start: base.subtract(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 2)),
        now: base.add(const Duration(hours: 3)),
      );
      final firstActual = await actualLogs.getBySource(
        sourceType: ActualActivitySourceType.blockingEvent,
        sourceId: eventId.toString(),
      );
      final second = await service.generateForRange(
        start: base.subtract(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 2)),
        now: base.add(const Duration(hours: 3)),
      );

      await actualLogs.reject(firstActual!.id);
      final third = await service.generateForRange(
        start: base.subtract(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 2)),
        now: base.add(const Duration(hours: 3)),
      );
      final rows = await actualLogs.listInRange(
        DateTime.utc(2026, 6, 10),
        DateTime.utc(2026, 6, 11),
      );

      expect(first.created, 1);
      expect(second.created, 0);
      expect(second.skippedExisting, 1);
      expect(third.created, 1);
      expect(
        rows.map((row) => row.status),
        contains(ActualActivityStatus.rejected),
      );
      expect(
        rows.where(
          (row) =>
              row.sourceType == ActualActivitySourceType.blockingEvent &&
              row.sourceId == eventId.toString() &&
              row.status == ActualActivityStatus.candidate,
        ),
        hasLength(1),
      );
    });

    test('skips when a confirmed actual overlaps the blocking event', () async {
      final base = DateTime.utc(2026, 6, 10, 9);
      final eventId = await _insertEvent(
        db,
        uid: 'confirmed-overlap-block',
        summary: 'Overlapped block',
        start: base,
        end: base.add(const Duration(hours: 1)),
      );
      final event = await _eventById(db, eventId);
      final actualId = await actualLogs.insertCandidate(
        title: 'Already confirmed work',
        startAt: event.dtstart.add(const Duration(minutes: 15)),
        endAt: event.dtstart.add(const Duration(minutes: 45)),
        sourceType: ActualActivitySourceType.manual,
      );
      await actualLogs.confirm(actualId);

      final result = await service.generateForRange(
        start: base.subtract(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 2)),
        now: base.add(const Duration(hours: 3)),
      );

      expect(result.created, 0);
      expect(result.skippedConfirmedOverlap, 1);
      expect(result.skippedTotal, 1);
    });

    test('skips obvious tracking conflicts above the overlap threshold',
        () async {
      final base = DateTime.utc(2026, 6, 10, 9);
      await _insertEvent(
        db,
        uid: 'tracking-conflict-block',
        summary: 'Budget review',
        start: base,
        end: base.add(const Duration(hours: 1)),
      );
      await _insertActivityRecord(
        db,
        start: base.add(const Duration(minutes: 10)),
        end: base.add(const Duration(minutes: 40)),
        category: 'gaming',
        windowTitle: 'Arcade leaderboard',
      );

      final result = await service.generateForRange(
        start: base.subtract(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 2)),
        now: base.add(const Duration(hours: 3)),
      );

      expect(result.created, 0);
      expect(result.skippedTrackingConflict, 1);
      expect(result.skippedTotal, 1);
    });

    test('ignores related tracking records and uses a one hour default end',
        () async {
      final base = DateTime.utc(2026, 6, 10, 9);
      final eventId = await _insertEvent(
        db,
        uid: 'default-end-block',
        summary: 'Budget review',
        start: base,
      );
      await _insertActivityRecord(
        db,
        start: base.add(const Duration(minutes: 5)),
        end: base.add(const Duration(minutes: 50)),
        windowTitle: 'Budget review notes',
        category: 'productivity',
      );

      final result = await service.generateForRange(
        start: base.subtract(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 2)),
        now: base.add(const Duration(hours: 3)),
      );
      final event = await _eventById(db, eventId);

      expect(result.created, 1);
      expect(result.skippedTrackingConflict, 0);
      final actual = await actualLogs.getBySource(
        sourceType: ActualActivitySourceType.blockingEvent,
        sourceId: eventId.toString(),
      );
      expect(actual?.endAt, event.dtstart.add(const Duration(hours: 1)));
    });

    test('counts blocking events that have not ended yet', () async {
      final base = DateTime.utc(2026, 6, 10, 9);
      await _insertEvent(
        db,
        uid: 'future-end-block',
        summary: 'Still running',
        start: base,
        end: base.add(const Duration(hours: 2)),
      );

      final result = await service.generateForRange(
        start: base.subtract(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 3)),
        now: base.add(const Duration(hours: 1)),
      );

      expect(result.created, 0);
      expect(result.skippedNotEnded, 1);
      expect(result.skippedTotal, 1);
    });
  });
}

Future<int> _insertEvent(
  AppDatabase db, {
  required String uid,
  required String summary,
  required DateTime start,
  DateTime? end,
  String? location,
  String source = 'local',
  String status = 'CONFIRMED',
  bool isBlock = true,
}) {
  return db.into(db.calendarEvents).insert(
        CalendarEventsCompanion.insert(
          uid: uid,
          dtstamp: DateTime.utc(2026, 6, 1),
          summary: summary,
          dtstart: start,
          dtend: Value(end),
          location: Value(location),
          source: Value(source),
          status: Value(status),
          isBlock: Value(isBlock),
        ),
      );
}

Future<CalendarEvent> _eventById(AppDatabase db, int id) {
  return (db.select(db.calendarEvents)..where((event) => event.id.equals(id)))
      .getSingle();
}

Future<int> _insertActivityRecord(
  AppDatabase db, {
  required DateTime start,
  required DateTime end,
  String? category,
  String? manualLabel,
  String? processName,
  String? windowTitle,
  String? packageName,
}) {
  return db.into(db.activityRecords).insert(
        ActivityRecordsCompanion.insert(
          startTime: start,
          endTime: Value(end),
          durationMinutes: Value(end.difference(start).inMinutes),
          manualLabel: Value(manualLabel),
          processName: Value(processName),
          windowTitle: Value(windowTitle),
          packageName: Value(packageName),
          category: Value(category),
          isAuto: const Value(true),
          source: const Value('blocking_event_candidate_service_test'),
        ),
      );
}
