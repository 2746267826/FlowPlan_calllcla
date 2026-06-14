import 'dart:convert';
import 'dart:io';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
import 'package:flowplanv2/features/tracker/models/tracked_input_event.dart';
import 'package:flowplanv2/features/tracker/services/activity_log_service.dart';
import 'package:flowplanv2/features/tracker/services/android_usage_import_service.dart';
import 'package:flowplanv2/features/tracker/services/android_usage_stats_service.dart';
import 'package:flowplanv2/features/tracker/services/input_activity_event_service.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flowplanv2/features/tracker/services/tracker_platform_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/temp_app_storage.dart';
import '../../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InputEventQuery gap7 coverage', () {
    test('copyWith clears individual fields and equality tracks value fields',
        () {
      final start = DateTime(2026, 6, 11, 8);
      final end = DateTime(2026, 6, 11, 9);
      final query = InputEventQuery(
        start: start,
        end: end,
        processName: 'Code.exe',
      );

      final cleared = query.copyWith(
        clearStart: true,
        clearEnd: true,
        clearProcessName: true,
      );

      expect(cleared.start, isNull);
      expect(cleared.end, isNull);
      expect(cleared.processName, isNull);
      expect(cleared.hasTimeRange, isFalse);
      expect(query.hasTimeRange, isTrue);
      expect(query,
          InputEventQuery(start: start, end: end, processName: 'Code.exe'));
      expect(
          query.hashCode,
          InputEventQuery(start: start, end: end, processName: 'Code.exe')
              .hashCode);
      expect(query == Object(), isFalse);
    });
  });

  group('TrackerPlatformSource gap7 coverage', () {
    test('testing constructors expose mode capabilities and descriptions', () {
      const custom = TrackerPlatformSource.testing(
        platformLabel: 'Android Test',
        collectionMode: TrackerCollectionMode.manualUsageStatsImport,
        supportsInputAnalytics: false,
        supportsSequenceRecording: false,
        supportsUsageAccessPermission: true,
        supportsDetailedInputHistory: false,
      );
      const windows = TrackerPlatformSource.windowsForTesting();
      const unsupported = TrackerPlatformSource.testing(
        platformLabel: 'Other',
        collectionMode: TrackerCollectionMode.unsupported,
        supportsInputAnalytics: false,
        supportsSequenceRecording: false,
        supportsUsageAccessPermission: false,
        supportsDetailedInputHistory: false,
      );

      expect(custom.isAndroid, isTrue);
      expect(custom.isWindows, isFalse);
      expect(custom.isSupported, isTrue);
      expect(custom.supportsUsageAccessPermission, isTrue);
      expect(custom.collectionDescription, isNotEmpty);
      expect(windows.isWindows, isTrue);
      expect(windows.supportsDetailedInputHistory, isTrue);
      expect(unsupported.isSupported, isFalse);
      expect(unsupported.collectionDescription, isNotEmpty);
    });
  });

  group('InputActivityEventService gap7 coverage', () {
    test(
        'orders equal timestamps by sequence and decodes payload token fallback',
        () async {
      await setUpTempAppStorage(prefix: 'tracker-gap7-input-payload-');
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = InputActivityEventService(db);
      final at = DateTime(2026, 6, 11, 9);

      await service.appendEvents(
        events: <RawInputEvent>[
          _rawEvent(
            sequenceId: 2,
            at: at,
            kind: RawInputEventKind.mouseMove,
            deltaX: 0,
            deltaY: 0,
            moveDistance: 0,
          ),
          _rawEvent(
            sequenceId: 1,
            at: at,
            kind: RawInputEventKind.keyDown,
            eventCount: 1,
            keyCode: 65,
          ),
        ],
        bindings: const <InputEventContextBinding>[
          InputEventContextBinding(
            recordId: 1,
            processName: 'Code.exe',
            category: 'coding',
          ),
        ],
      );

      await _insertInputEventRow(
        db,
        eventUid: 'payload-fallback',
        sequenceId: 3,
        at: at.add(const Duration(seconds: 1)),
        kind: 'mouse_move',
        eventCount: 7,
        deltaX: 12,
        deltaY: -4,
        moveDistance: 0,
        payloadJson: jsonEncode(<Object?, Object?>{
          'eventCount': 7,
          'tokenText': 'payload-token',
        }),
      );

      final events = await service.listEvents(includeIgnored: true, limit: 10);

      expect(events.map((event) => event.sequenceId), <int>[1, 2, 3]);
      expect(events.last.eventCount, 7);
      expect(events.last.deltaX, 12);
      expect(events.last.deltaY, -4);
      expect(events.last.tokenText, 'payload-token');
    });

    test('archive scanning ignores invalid names and parses damaged day keys',
        () async {
      final storage =
          await setUpTempAppStorage(prefix: 'tracker-gap7-archive-');
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = InputActivityEventService(db);
      expect(storage.path, isNotEmpty);
      final logs = Directory(await service.getArchiveDirectoryPath());
      await logs.create(recursive: true);
      await File(
              '${logs.path}${Platform.pathSeparator}not-a-day.input-events.jsonl')
          .writeAsString('{}\n');
      await File(
              '${logs.path}${Platform.pathSeparator}2026-13-40.input-events.jsonl')
          .writeAsString('{}\n');

      final days = await service.listArchiveDays();

      expect(days.map((day) => day.dayKey), contains('2026-13-40'));
      expect(days.single.date, DateTime(2026, 13, 40));
    });
  });

  group('ActivityRecordRepository gap7 coverage', () {
    test('endRecord clamps a backwards finish time before persisting',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActivityRecordRepository(db);
      final start = DateTime(2026, 6, 14, 16);
      final backwardsEnd = start.subtract(const Duration(days: 730));

      final id = await repository.startRecord(
        startTime: start,
        processName: 'Code.exe',
        category: 'coding',
      );
      await repository.endRecord(
        id,
        backwardsEnd,
        telemetry: InputTelemetry.empty(backwardsEnd),
      );

      final record = await repository.getById(id);

      expect(record?.endTime, start);
      expect(record?.durationMinutes, 0);
    });
  });

  group('AndroidUsageImportService gap7 coverage', () {
    test('opens a new package by closing the previous session at the boundary',
        () async {
      await setUpTempAppStorage(prefix: 'tracker-gap7-android-boundary-');
      final db = createTestDatabase();
      addTearDown(db.close);
      final base = DateTime.now().subtract(const Duration(minutes: 15));
      await db.setSetting(
        'tracker.android_usage_stats_cursor_millis',
        base
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch
            .toString(),
      );
      final usage = _FakeAndroidUsageStatsService(
        events: <AndroidUsageEvent>[
          _usageEvent(base, 'com.example.editor', 'activity_resumed'),
          _usageEvent(
            base.add(const Duration(minutes: 5)),
            'com.example.browser',
            'activity_resumed',
            appLabel: ' Browser ',
          ),
          _usageEvent(
            base.add(const Duration(minutes: 10)),
            'com.example.browser',
            'activity_paused',
            appLabel: 'Browser',
          ),
        ],
      );
      final service = AndroidUsageImportService(
        database: db,
        activityRecordRepository: ActivityRecordRepository(db),
        activityLogService: ActivityLogService(db),
        usageStatsService: usage,
        isAndroid: () => true,
      );

      final result = await service.importLatest();
      final records = await db
          .customSelect(
              'SELECT * FROM activity_records ORDER BY start_time ASC')
          .get();

      expect(result.importedRecordCount, 2);
      expect(records.first.read<String>('process_name'), 'com.example.editor');
      expect(records.first.read<int>('duration_minutes'), 5);
      expect(records.last.read<String>('process_name'), 'Browser');
      expect(result.latestSnapshot?.processName, 'Browser');
    });
  });
}

RawInputEvent _rawEvent({
  required int sequenceId,
  required DateTime at,
  required RawInputEventKind kind,
  int eventCount = 1,
  int? keyCode,
  int deltaX = 0,
  int deltaY = 0,
  int moveDistance = 0,
}) {
  return RawInputEvent(
    sequenceId: sequenceId,
    timestampMicros: at.microsecondsSinceEpoch,
    kind: kind,
    eventCount: eventCount,
    keyCode: keyCode,
    deltaX: deltaX,
    deltaY: deltaY,
    moveDistance: moveDistance,
  );
}

Future<void> _insertInputEventRow(
  AppDatabase db, {
  required String eventUid,
  required int sequenceId,
  required DateTime at,
  required String kind,
  int? eventCount,
  int? deltaX,
  int? deltaY,
  int moveDistance = 0,
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
      record_id,
      process_name,
      class_name,
      window_title,
      category,
      activity_label,
      is_ignored,
      key_code,
      key_label,
      mouse_button,
      wheel_delta,
      delta_x,
      delta_y,
      move_distance,
      event_count,
      token_text,
      payload_json,
      created_at
    ) VALUES (?, ?, ?, ?, ?, NULL, ?, NULL, NULL, ?, NULL, 0, NULL, NULL, NULL, 0, ?, ?, ?, ?, NULL, ?, ?)
    ''',
    <Object?>[
      eventUid,
      sequenceId,
      at.toIso8601String(),
      '${at.year.toString().padLeft(4, '0')}-'
          '${at.month.toString().padLeft(2, '0')}-'
          '${at.day.toString().padLeft(2, '0')}',
      kind,
      'Code.exe',
      'coding',
      deltaX,
      deltaY,
      moveDistance,
      eventCount,
      payloadJson,
      DateTime.now().toIso8601String(),
    ],
  );
}

AndroidUsageEvent _usageEvent(
  DateTime timestamp,
  String packageName,
  String eventType, {
  String? appLabel,
}) {
  return AndroidUsageEvent.fromMap(<String, Object?>{
    'timestampMillis': timestamp.millisecondsSinceEpoch,
    'packageName': packageName,
    'eventType': eventType,
    if (appLabel != null) 'appLabel': appLabel,
  });
}

class _FakeAndroidUsageStatsService extends AndroidUsageStatsService {
  _FakeAndroidUsageStatsService({required this.events});

  final List<AndroidUsageEvent> events;

  @override
  Future<bool> hasUsageAccessPermission() async => true;

  @override
  Future<List<AndroidUsageEvent>> queryUsageEvents({
    required DateTime start,
    required DateTime end,
  }) async {
    return events;
  }
}
