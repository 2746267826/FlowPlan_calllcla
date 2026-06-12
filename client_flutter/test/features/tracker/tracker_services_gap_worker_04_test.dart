import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/tracker/data/activity_fusion_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
import 'package:flowplanv2/features/tracker/models/tracked_input_event.dart';
import 'package:flowplanv2/features/tracker/services/input_activity_event_service.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/temp_app_storage.dart';
import '../../test_support/test_database.dart';

void main() {
  Future<void> insertTrackedInputEventRow(
    AppDatabase db, {
    required String eventUid,
    required int sequenceId,
    required DateTime at,
    String kind = 'key_down',
    String occurredAt = '',
    String? processName = 'Code.exe',
    bool isIgnored = false,
    int eventCount = 1,
    String payloadJson = '{}',
  }) async {
    await db.customStatement(
      '''
      INSERT INTO tracked_input_events (
        event_uid,
        sequence_id,
        occurred_at,
        day_key,
        event_kind,
        process_name,
        is_ignored,
        event_count,
        payload_json,
        created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        eventUid,
        sequenceId,
        occurredAt.isEmpty ? at.toIso8601String() : occurredAt,
        _dayKey(at),
        kind,
        processName,
        isIgnored ? 1 : 0,
        eventCount,
        payloadJson,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  ActivitySegmentDraft segmentDraft({
    required DateTime start,
    Duration duration = const Duration(minutes: 20),
    String status = 'candidate',
    double confidence = 0.6,
    List<int> sourceRecordIds = const <int>[1, 2],
    Map<String, Object?> evidence = const <String, Object?>{'origin': 'test'},
    String? label = 'Focused work',
  }) {
    return ActivitySegmentDraft(
      startAt: start,
      endAt: start.add(duration),
      sourceRecordIds: sourceRecordIds,
      evidence: evidence,
      primaryProcessName: 'Code.exe',
      primaryWindowTitle: 'tracker_services_gap_worker_04_test.dart',
      category: 'coding',
      label: label,
      confidence: confidence,
      status: status,
    );
  }

  group('InputActivityEventService gap coverage', () {
    test('empty append initializes storage without creating archive files',
        () async {
      final storage = await setUpTempAppStorage();
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = InputActivityEventService(db);

      await service.appendEvents(
        events: const <RawInputEvent>[],
        bindings: const <InputEventContextBinding>[],
      );

      expect(await service.listEvents(includeIgnored: true), isEmpty);
      expect(await service.listArchiveDays(), isEmpty);
      expect(
        await Directory('${storage.path}${Platform.pathSeparator}logs')
            .exists(),
        isFalse,
      );
    });

    test('archive scan ignores unrelated files and sorts valid days descending',
        () async {
      await setUpTempAppStorage();
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = InputActivityEventService(db);
      final logs = Directory(await service.getArchiveDirectoryPath());
      await logs.create(recursive: true);
      await File('${logs.path}${Platform.pathSeparator}notes.txt')
          .writeAsString('ignore me');
      await File(
        '${logs.path}${Platform.pathSeparator}2026-06-08.input-events.jsonl',
      ).writeAsString('{}\n');
      await File(
        '${logs.path}${Platform.pathSeparator}2026-06-10.input-events.jsonl',
      ).writeAsString('{}\n{}\n');

      final days = await service.listArchiveDays();

      expect(days.map((day) => day.dayKey), <String>[
        '2026-06-10',
        '2026-06-08',
      ]);
      expect(days.first.date, DateTime(2026, 6, 10));
      expect(days.first.fileSizeBytes, greaterThan(days.last.fileSizeBytes));
    });

    test('decode skips malformed rows and falls back from payload columns',
        () async {
      await setUpTempAppStorage();
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = InputActivityEventService(db);
      final base = DateTime(2026, 6, 9, 12);

      await insertTrackedInputEventRow(
        db,
        eventUid: 'bad-kind-row',
        sequenceId: 1,
        at: base,
        kind: 'key_down',
        occurredAt: 'not-a-date',
        payloadJson: jsonEncode(<String, Object?>{
          'eventCount': 7,
          'deltaX': 11,
          'deltaY': 12,
          'tokenText': 'payload-token',
        }),
      );
      await insertTrackedInputEventRow(
        db,
        eventUid: 'malformed-payload-row',
        sequenceId: 2,
        at: base.add(const Duration(minutes: 1)),
        payloadJson: '{not-json',
      );

      final events = await service.listEvents(includeIgnored: true);
      final eventsByUid = <String, TrackedInputEvent>{
        for (final event in events) event.eventUid: event,
      };

      expect(events, hasLength(2));
      expect(eventsByUid['bad-kind-row']?.timestamp,
          DateTime.fromMillisecondsSinceEpoch(0));
      expect(eventsByUid['bad-kind-row']?.eventCount, 1);
      expect(eventsByUid['bad-kind-row']?.deltaX, 0);
      expect(eventsByUid['bad-kind-row']?.deltaY, 0);
      expect(eventsByUid['bad-kind-row']?.tokenText, 'payload-token');
      expect(eventsByUid['malformed-payload-row']?.eventCount, 1);
    });

    test('empty heatmap summary preserves query and derived zero metrics',
        () async {
      await setUpTempAppStorage();
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = InputActivityEventService(db);
      final query = InputEventQuery(
        start: DateTime(2026, 6, 1),
        end: DateTime(2026, 6, 2),
        processName: 'missing.exe',
      );

      final summary = await service.buildHeatmapSummary(query);

      expect(summary.query, same(query));
      expect(summary.totalEventCount, 0);
      expect(summary.leadingKey, isNull);
      expect(summary.leadingProcessIntensity, isNull);
      expect(summary.trackedInteractionCount, 0);
      expect(summary.keyboardInteractionShare, 0);
      expect(summary.pointerInteractionShare, 0);
      expect(summary.averageEventsPerActiveMinute, 0);
      expect(summary.maxKeyCount, 0);
      expect(summary.maxMouseCount, 0);
      expect(summary.maxProcessIntensityScore, 0);
      expect(summary.maxHourlyIntensityScore, 0);
      expect(summary.peakHourBucket?.hour, 0);
    });
  });

  group('ActivityRecordRepository gap coverage', () {
    test('imported records clamp negative duration and retain explicit context',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActivityRecordRepository(db);
      final end = DateTime(2026, 6, 9, 10);

      final id = await repository.insertImportedRecord(
        startTime: end.add(const Duration(minutes: 5)),
        endTime: end,
        processName: 'Chrome.exe',
        windowTitle: 'Research',
        packageName: 'com.browser',
        category: 'browser',
        deviceId: ' imported-device ',
        platform: ' android ',
      );

      final record = await repository.getById(id);
      final context = await db.customSelect(
        'SELECT device_id, platform FROM activity_records WHERE id = ?',
        variables: <Variable>[Variable<int>(id)],
      ).getSingle();

      expect(record?.durationMinutes, 0);
      expect(record?.isAuto, isTrue);
      expect(record?.source, 'imported');
      expect(record?.packageName, 'com.browser');
      expect(context.data['device_id'], 'imported-device');
      expect(context.data['platform'], 'android');
    });

    test('telemetry updates no-op on null and can omit duration changes',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActivityRecordRepository(db);
      final start = DateTime(2026, 6, 9, 9);
      final id = await repository.startRecord(
        startTime: start,
        processName: 'Code.exe',
        category: 'coding',
        deviceId: 'device',
        platform: 'windows',
      );

      await repository.updateTelemetry(id, telemetry: null, durationMinutes: 9);
      var record = await repository.getById(id);
      expect(record?.durationMinutes, 0);

      await repository.updateTelemetry(
        id,
        telemetry: InputTelemetry(
          keyCount: 6,
          keyDistribution: const <int, int>{65: 6},
          keySequence: 'abcdef',
          clicks: const MouseClicks(left: 2, right: 1),
          scrollPx: 120,
          mouseMovePx: 340,
          timestamp: start.add(const Duration(minutes: 1)),
          inputEvents: const <RawInputEvent>[],
        ),
      );

      record = await repository.getById(id);
      expect(record?.durationMinutes, 0);
      expect(record?.keyCount, 6);
      expect(record?.mouseClicks, 3);
      expect(record?.scrollPx, 120);
      expect(record?.mouseMovePx, 340);
      expect(record?.keySequence, 'abcdef');

      await repository.endRecord(999999, start.add(const Duration(minutes: 1)));
      expect(await repository.getById(999999), isNull);
    });

    test('range, task, active, link, and delete paths handle boundaries',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActivityRecordRepository(db);
      final base = DateTime(2026, 6, 10, 9);

      final before = await repository.startRecord(
        startTime: base.subtract(const Duration(hours: 2)),
        processName: 'Code.exe',
        category: 'coding',
        linkedTaskId: 1,
        deviceId: 'device',
        platform: 'windows',
      );
      await repository.endRecord(
          before, base.subtract(const Duration(hours: 1)));
      final first = await repository.startRecord(
        startTime: base.add(const Duration(minutes: 10)),
        processName: 'Code.exe',
        category: 'coding',
        linkedTaskId: 1,
        deviceId: 'device',
        platform: 'windows',
      );
      await repository.endRecord(first, base.add(const Duration(minutes: 30)));
      final active = await repository.startRecord(
        startTime: base.add(const Duration(minutes: 40)),
        processName: 'Chrome.exe',
        category: 'browser',
        linkedTaskId: 2,
        deviceId: 'device',
        platform: 'windows',
      );

      expect((await repository.getActiveRecord())?.id, active);
      expect(
        (await repository.listInRange(base, base.add(const Duration(hours: 1))))
            .map((record) => record.id),
        <int>[first, active],
      );
      expect(
        await repository.watchForDate(base).first,
        isA<List<ActivityRecord>>().having(
            (records) => records.map((r) => r.id), 'ids', contains(first)),
      );

      final page = await repository.listInRangePage(
        start: base,
        end: base.add(const Duration(hours: 1)),
        processName: ' Code.exe ',
        category: ' coding ',
        linkedTaskId: 1,
        limit: 0,
        offset: -10,
      );
      expect(page.single.id, first);

      await repository.linkTasks(<int>[first, first, active], 42);
      expect(
        (await repository.listByTaskId(42)).map((record) => record.id),
        <int>[first, active],
      );
      expect(
        (await repository.watchByTaskId(42).first).map((record) => record.id),
        <int>[first, active],
      );

      await repository.linkTask(active, null);
      expect((await repository.listByTaskId(42)).map((record) => record.id),
          <int>[first]);
      await repository.linkTasks(const <int>[], 99);
      expect(await repository.delete(first), 1);
      expect(await repository.getById(first), isNull);
    });
  });

  group('ActivityFusionRepository gap coverage', () {
    test('status updates and rejection methods no-op when rows are absent',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActivityFusionRepository(db);

      await repository.updateSegmentStatus(404, status: 'confirmed');
      await repository.updateInterpretationsStatusForSegment(
        404,
        status: 'rejected',
      );
      await repository.rejectTaskWorkLogsForSegmentExcept(
        segmentId: 404,
        taskId: 1,
      );
      await repository.rejectTaskWorkLogsForSegment(segmentId: 404);

      expect(
        await db
            .customSelect('SELECT COUNT(*) AS count FROM activity_segments')
            .getSingle()
            .then((row) => row.read<int>('count')),
        0,
      );
    });

    test(
        'confirmed upsert creates when no matching task and reuses latest match',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActivityFusionRepository(db);
      final base = DateTime(2026, 6, 11, 9);
      final segment = await repository.insertSegment(
        segmentDraft(start: base),
        sync: false,
        audit: false,
      );

      final created = await repository.upsertConfirmedTaskWorkLogForSegment(
        taskId: 7,
        segmentId: segment.id,
        actualId: 70,
        startAt: base,
        endAt: base.add(const Duration(minutes: 20)),
        confidence: 2,
        evidence: const <String, Object?>{'first': true},
      );
      final laterCandidate = await repository.insertTaskWorkLog(
        taskId: 7,
        segmentId: segment.id,
        actualId: 71,
        startAt: base.add(const Duration(minutes: 30)),
        endAt: base.add(const Duration(minutes: 45)),
        confidence: 0.4,
        sourceType: 'candidate',
      );
      await db.customStatement(
        'UPDATE task_work_logs SET created_at = ?, updated_at = ? WHERE id = ?',
        <Object?>[
          base.add(const Duration(minutes: 1)).toIso8601String(),
          base.add(const Duration(minutes: 1)).toIso8601String(),
          created.id,
        ],
      );
      await db.customStatement(
        'UPDATE task_work_logs SET created_at = ?, updated_at = ? WHERE id = ?',
        <Object?>[
          base.add(const Duration(minutes: 2)).toIso8601String(),
          base.add(const Duration(minutes: 2)).toIso8601String(),
          laterCandidate.id,
        ],
      );

      final updated = await repository.upsertConfirmedTaskWorkLogForSegment(
        taskId: 7,
        segmentId: segment.id,
        actualId: 72,
        startAt: base.add(const Duration(minutes: 35)),
        endAt: base.add(const Duration(minutes: 80)),
        confidence: -5,
        evidence: const <String, Object?>{'updated': true},
      );

      expect(created.status, 'confirmed');
      expect(created.confidence, 1);
      expect(updated.id, laterCandidate.id);
      expect(updated.id, isNot(created.id));
      expect(updated.actualId, 72);
      expect(updated.confidence, 0);
      expect(updated.durationMinutes, 45);
      expect(updated.evidence, containsPair('updated', true));
    });

    test('model JSON helpers tolerate non-list and scalar evidence payloads',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActivityFusionRepository(db);
      final base = DateTime(2026, 6, 12, 9);
      final segment = await repository.insertSegment(
        segmentDraft(start: base),
        sync: false,
        audit: false,
      );
      final interpretation = await repository.insertInterpretation(
        segmentId: segment.id,
        summary: 'scalar evidence',
        confidence: 0.7,
      );

      await db.customStatement(
        '''
        UPDATE activity_segments
        SET source_record_ids_json = ?, evidence_json = ?
        WHERE id = ?
        ''',
        <Object?>['{"not":"a-list"}', '"scalar"', segment.id],
      );
      await db.customStatement(
        'UPDATE activity_interpretations SET evidence_json = ? WHERE id = ?',
        <Object?>['42', interpretation.id],
      );

      final storedSegment = await repository.getSegmentById(segment.id);
      final storedInterpretations =
          await repository.listInterpretationsForSegment(segment.id);

      expect(storedSegment?.sourceRecordIds, isEmpty);
      expect(storedSegment?.evidence, isEmpty);
      expect(storedInterpretations.single.evidence, isEmpty);
      expect(storedInterpretations.single.toJson(),
          containsPair('summary', 'scalar evidence'));
    });
  });

  group('TrackedInputEvent model gap coverage', () {
    test('unknown event kind and sparse JSON fall back to safe defaults', () {
      final event = TrackedInputEvent.fromJson(<String, dynamic>{
        'kind': 'future_native_event',
        'isIgnored': true,
        'eventCount': 3,
      });

      expect(event.eventUid, '');
      expect(event.sequenceId, 0);
      expect(event.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
      expect(event.kind, TrackedInputEventKind.keyDown);
      expect(event.eventCount, 3);
      expect(event.isIgnored, isTrue);
      expect(event.toJson(), containsPair('kind', 'key_down'));
    });
  });
}

String _dayKey(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
