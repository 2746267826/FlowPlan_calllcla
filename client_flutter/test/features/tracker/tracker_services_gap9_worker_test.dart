import 'dart:convert';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/actual/data/actual_activity_log_repository.dart';
import 'package:flowplanv2/features/files/data/file_context_repository.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_fusion_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flowplanv2/features/tracker/models/activity_log_entry.dart';
import 'package:flowplanv2/features/tracker/models/tracked_input_event.dart';
import 'package:flowplanv2/features/tracker/services/activity_fusion_service.dart';
import 'package:flowplanv2/features/tracker/services/activity_log_service.dart';
import 'package:flowplanv2/features/tracker/services/input_activity_event_service.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flowplanv2/features/tracker/services/tracker_platform_source.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/features/tracker/services/window_sensor.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/temp_app_storage.dart';
import '../../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugTrackerPlatformOverride =
        const TrackerPlatformSource.windowsForTesting();
  });

  tearDown(() {
    debugRawInputServiceOverride = null;
    debugTrackerPlatformOverride = null;
    debugTrackerWindowCaptureOverride = null;
  });

  group('TrackerService gap9 sampling branches', () {
    test('refresh on testing Windows records last sample timestamp', () async {
      await setUpTempAppStorage(prefix: 'tracker-gap9-null-capture-');
      final db = createTestDatabase();
      addTearDown(db.close);
      debugRawInputServiceOverride = _FakeRawInputService();
      final sampledAt = DateTime(2026, 6, 12, 13);
      debugTrackerWindowCaptureOverride = () => _snapshot(
            processName: 'Code.exe',
            className: 'EditorWindow',
            windowTitle: 'main.dart',
            timestamp: sampledAt,
          );
      final container = _trackerContainer(db);
      addTearDown(container.dispose);
      final notifier = container.read(trackerServiceNotifierProvider.notifier);

      await notifier.refreshNow();

      final state = container.read(trackerServiceNotifierProvider);
      expect(state.lastSampleAt, sampledAt);
      expect(state.currentSnapshot?.processName, 'Code.exe');
      expect(
        await db.customSelect('SELECT * FROM activity_records').get(),
        hasLength(1),
      );
    });

    test('context change binds input events to previous record and context',
        () async {
      await setUpTempAppStorage(prefix: 'tracker-gap9-context-change-');
      final db = createTestDatabase();
      addTearDown(db.close);
      final firstAt = DateTime(2026, 6, 12, 14);
      final secondAt = firstAt.add(const Duration(minutes: 2));
      final rawInput = _FakeRawInputService()
        ..statsQueue.addAll(<Future<InputTelemetry?>>[
          Future<InputTelemetry?>.value(
            _telemetry(
              at: firstAt,
              keys: 1,
              events: <RawInputEvent>[_rawEvent(1, firstAt, keyCode: 65)],
            ),
          ),
          Future<InputTelemetry?>.value(
            _telemetry(
              at: secondAt,
              keys: 3,
              events: <RawInputEvent>[_rawEvent(2, secondAt, keyCode: 66)],
            ),
          ),
        ]);
      debugRawInputServiceOverride = rawInput;
      final snapshots = <WindowSnapshot>[
        _snapshot(
          processName: 'Code.exe',
          className: 'EditorWindow',
          windowTitle: 'first.dart',
          timestamp: firstAt,
        ),
        _snapshot(
          processName: 'Browser.exe',
          className: 'Chrome_WidgetWin_1',
          windowTitle: 'Docs',
          timestamp: secondAt,
        ),
      ];
      debugTrackerWindowCaptureOverride = () => snapshots.removeAt(0);
      final container = _trackerContainer(db);
      addTearDown(container.dispose);
      final notifier = container.read(trackerServiceNotifierProvider.notifier);

      await notifier.refreshNow();
      final previousRecordId =
          container.read(trackerServiceNotifierProvider).activeRecordId;
      await notifier.refreshNow();

      final rows = await db.customSelect(
        '''
            SELECT sequence_id, record_id, process_name, class_name,
                   window_title
            FROM tracked_input_events
            ORDER BY sequence_id ASC
            ''',
      ).get();
      expect(rows, hasLength(2));
      expect(rows.last.read<int>('sequence_id'), 2);
      expect(rows.last.read<int?>('record_id'), previousRecordId);
      expect(rows.last.read<String?>('process_name'), 'Code.exe');
      expect(rows.last.read<String?>('class_name'), 'EditorWindow');
      expect(rows.last.read<String?>('window_title'), 'first.dart');
    });

    test('same context with null telemetry baseline keeps empty delta stable',
        () async {
      await setUpTempAppStorage(prefix: 'tracker-gap9-null-baseline-');
      final db = createTestDatabase();
      addTearDown(db.close);
      final at = DateTime(2026, 6, 12, 15);
      final rawInput = _FakeRawInputService()
        ..statsQueue.addAll(<Future<InputTelemetry?>>[
          Future<InputTelemetry?>.value(null),
          Future<InputTelemetry?>.value(
            _telemetry(
              at: at.add(const Duration(minutes: 1)),
              keys: 5,
            ),
          ),
        ]);
      debugRawInputServiceOverride = rawInput;
      final snapshots = <WindowSnapshot>[
        _snapshot(
          processName: 'Code.exe',
          className: 'EditorWindow',
          windowTitle: 'first.dart',
          timestamp: at,
        ),
        _snapshot(
          processName: 'Code.exe',
          className: 'EditorWindow',
          windowTitle: 'second.dart',
          timestamp: at.add(const Duration(minutes: 1)),
        ),
      ];
      debugTrackerWindowCaptureOverride = () => snapshots.removeAt(0);
      final container = _trackerContainer(db);
      addTearDown(container.dispose);
      final notifier = container.read(trackerServiceNotifierProvider.notifier);

      await notifier.refreshNow();
      await notifier.refreshNow();

      final state = container.read(trackerServiceNotifierProvider);
      expect(state.currentTelemetry?.keyCount, 0);
      final logs = await container
          .read(activityLogServiceProvider)
          .readEntriesForDate(DateTime(2026, 6, 12));
      expect(logs.last.keyCount, 0);
      expect(logs.last.note, isNull);
    });
  });

  group('ActivityFusionService gap9 confirm branches', () {
    test('throws when confirming a missing segment', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = _fusionService(db);

      await expectLater(
        service.confirmSegment(404),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Activity segment not found.',
          ),
        ),
      );
    });

    test('trims explicit title before creating confirmed actual', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final base = DateTime(2026, 6, 12, 9);
      final fusion = _FakeFusionRepository(db)
        ..seedSegment(
          _segment(
            id: 1,
            start: base,
            label: 'Fallback label',
          ),
        );
      final actuals = _FakeActualActivityLogRepository(db);
      final service = _fusionService(db, fusion: fusion, actuals: actuals);

      final result = await service.confirmSegment(
        1,
        title: '  Reviewed focus block  ',
        actor: 'gap9',
      );

      expect(result.actual.title, 'Reviewed focus block');
      expect(result.taskWorkLog, isNull);
      expect(actuals.insertedTitles, <String>['Reviewed focus block']);
      expect(fusion.segmentById(1)?.status, 'confirmed');
    });

    test('throws when inserted actual cannot be read back', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final fusion = _FakeFusionRepository(db)
        ..seedSegment(_segment(id: 2, start: DateTime(2026, 6, 12, 10)));
      final service = _fusionService(
        db,
        fusion: fusion,
        actuals: _FakeActualActivityLogRepository(db, dropReadBack: true),
      );

      await expectLater(
        service.confirmSegment(2),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'Confirmed actual record not found.',
          ),
        ),
      );
    });
  });

  group('ActivityFusionService gap9 merge and inference branches', () {
    test('merges sparse same linked task evidence despite empty context',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final base = DateTime(2026, 6, 12, 11);
      final fusion = _FakeFusionRepository(db);
      final service = _fusionService(
        db,
        fusion: fusion,
        records: <ActivityRecord>[
          _record(
            id: 10,
            start: base,
            processName: null,
            category: null,
            linkedTaskId: 77,
          ),
          _record(
            id: 11,
            start: base.add(const Duration(minutes: 7)),
            processName: '',
            category: '',
            linkedTaskId: 77,
          ),
        ],
      );

      final result = await service.rebuildRange(
        start: base,
        end: base.add(const Duration(hours: 1)),
      );

      expect(result.segmentCount, 1);
      final segment = fusion.segments.single;
      expect(segment.primaryProcessName, isNull);
      expect(segment.category, isNull);
      expect(segment.label, isNull);
      expect(jsonDecode(segment.sourceRecordIdsJson), <Object?>[10, 11]);
      expect(_jsonMap(segment.evidenceJson)['linkedTaskIds'], <Object?>[77]);
      expect(segment.confidence, greaterThanOrEqualTo(0.78));
    });

    test('merges category-only evidence when process and task are absent',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final base = DateTime(2026, 6, 12, 11, 30);
      final fusion = _FakeFusionRepository(db);
      final service = _fusionService(
        db,
        fusion: fusion,
        records: <ActivityRecord>[
          _record(
            id: 12,
            start: base,
            processName: null,
            category: 'research',
            linkedTaskId: null,
          ),
          _record(
            id: 13,
            start: base.add(const Duration(minutes: 6)),
            processName: '',
            category: ' research ',
            linkedTaskId: null,
          ),
        ],
      );

      final result = await service.rebuildRange(
        start: base,
        end: base.add(const Duration(hours: 1)),
      );

      expect(result.segmentCount, 1);
      final segment = fusion.segments.single;
      expect(segment.primaryProcessName, isNull);
      expect(segment.category, 'research');
      expect(jsonDecode(segment.sourceRecordIdsJson), <Object?>[12, 13]);
      expect(_jsonMap(segment.evidenceJson)['linkedTaskIds'], isEmpty);
    });

    test('folder exact match wins over weaker keyword inference', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final base = DateTime(2026, 6, 12, 12);
      final fusion = _FakeFusionRepository(db);
      final service = _fusionService(
        db,
        fusion: fusion,
        records: <ActivityRecord>[
          _record(
            id: 20,
            start: base,
            processName: 'Code.exe',
            windowTitle: r'C:\projects\phoenix_app\lib\main.dart',
            category: 'coding',
          ),
        ],
        tasks: <TaskItem>[
          _task(id: 1, summary: 'Coding cleanup', categories: 'coding'),
          _task(id: 2, summary: 'Phoenix app milestone'),
        ],
        foldersByTaskId: <int, List<FileFolder>>{
          2: <FileFolder>[
            _folder(
              id: 2,
              displayName: 'phoenix_app',
            ),
          ],
        },
      );

      final result = await service.rebuildRange(
        start: base,
        end: base.add(const Duration(hours: 1)),
      );

      expect(result.taskWorkLogCount, 1);
      expect(fusion.interpretations.single.inferredTaskId, 2);
      final evidence = _jsonMap(fusion.interpretations.single.evidenceJson);
      expect(evidence['matchedBy'], 'keyword+folder');
      expect(evidence['matchedFolders'], <Object?>['phoenix_app']);
      expect(fusion.taskWorkLogs.single.taskId, 2);
    });
  });

  group('InputActivityEventService gap9 payload branches', () {
    test('falls back to structured columns when payload is not a JSON object',
        () async {
      await setUpTempAppStorage(prefix: 'tracker-gap9-input-');
      final db = createTestDatabase();
      addTearDown(db.close);
      final service = InputActivityEventService(db);
      final at = DateTime(2026, 6, 12, 13);

      await _insertInputEventRow(
        db,
        eventUid: 'array-payload',
        sequenceId: 1,
        at: at,
        payloadJson: '[{"eventCount":99,"deltaX":99,"deltaY":99}]',
        eventCount: 1,
        deltaX: 0,
        deltaY: 0,
      );
      await _insertInputEventRow(
        db,
        eventUid: 'string-payload',
        sequenceId: 2,
        at: at.add(const Duration(seconds: 1)),
        payloadJson: '"not-a-map"',
        eventCount: 4,
        deltaX: 8,
        deltaY: -3,
      );

      final events = await service.listEvents(includeIgnored: true);

      expect(events, hasLength(2));
      expect(events.first.eventUid, 'array-payload');
      expect(events.first.eventCount, 1);
      expect(events.first.deltaX, 0);
      expect(events.first.deltaY, 0);
      expect(events.last.eventUid, 'string-payload');
      expect(events.last.eventCount, 4);
      expect(events.last.deltaX, 8);
      expect(events.last.deltaY, -3);
    });

    test(
        'reads count and movement from payload when structured columns are null',
        () async {
      await setUpTempAppStorage(prefix: 'tracker-gap9-input-payload-');
      final db = createTestDatabase();
      addTearDown(db.close);
      await _recreateTrackedInputEventsWithNullableMetrics(db);
      final service = InputActivityEventService(db);
      final at = DateTime(2026, 6, 12, 13, 30);

      await _insertInputEventRow(
        db,
        eventUid: 'payload-metrics',
        sequenceId: 3,
        at: at,
        payloadJson: jsonEncode(<String, Object?>{
          'eventCount': 6,
          'deltaX': 14,
          'deltaY': -9,
        }),
        eventCount: null,
        deltaX: null,
        deltaY: null,
      );
      await _insertInputEventRow(
        db,
        eventUid: 'default-metrics',
        sequenceId: 4,
        at: at.add(const Duration(seconds: 1)),
        payloadJson: '{}',
        eventCount: null,
        deltaX: null,
        deltaY: null,
      );

      final events = await service.listEvents(includeIgnored: true);
      final byUid = <String, TrackedInputEvent>{
        for (final event in events) event.eventUid: event,
      };

      expect(byUid['payload-metrics']?.eventCount, 6);
      expect(byUid['payload-metrics']?.deltaX, 14);
      expect(byUid['payload-metrics']?.deltaY, -9);
      expect(byUid['default-metrics']?.eventCount, 1);
      expect(byUid['default-metrics']?.deltaX, 0);
      expect(byUid['default-metrics']?.deltaY, 0);
    });
  });
}

ActivityFusionService _fusionService(
  AppDatabase db, {
  List<ActivityRecord> records = const <ActivityRecord>[],
  _FakeFusionRepository? fusion,
  _FakeActualActivityLogRepository? actuals,
  List<TaskItem> tasks = const <TaskItem>[],
  Map<int, List<FileFolder>> foldersByTaskId = const <int, List<FileFolder>>{},
}) {
  return ActivityFusionService(
    _FakeActivityRecordRepository(db, records),
    _FakeActivityLogService(db),
    _FakeInputActivityEventService(db),
    fusion ?? _FakeFusionRepository(db),
    _FakeTaskRepository(db, tasks),
    _FakeFileContextRepository(db, foldersByTaskId),
    actuals ?? _FakeActualActivityLogRepository(db),
  );
}

ActivityRecord _record({
  required int id,
  required DateTime start,
  String? processName = 'Code.exe',
  String? windowTitle,
  String? category = 'coding',
  int? linkedTaskId,
}) {
  return ActivityRecord(
    id: id,
    startTime: start,
    endTime: start.add(const Duration(minutes: 5)),
    durationMinutes: 5,
    keyCount: 0,
    mouseClicks: 0,
    mouseMovePx: 0,
    scrollPx: 0,
    processName: processName,
    windowTitle: windowTitle,
    category: category,
    linkedTaskId: linkedTaskId,
    isAuto: true,
    source: 'gap9',
  );
}

ActivitySegment _segment({
  required int id,
  required DateTime start,
  String? label = 'Coding',
}) {
  return ActivitySegment(
    id: id,
    segmentUid: 'segment-$id',
    startAt: start,
    endAt: start.add(const Duration(minutes: 25)),
    primaryProcessName: 'Code.exe',
    primaryWindowTitle: 'main.dart - Code',
    category: 'coding',
    label: label,
    sourceRecordIdsJson: '[]',
    evidenceJson: '{}',
    confidence: 0.67,
    status: 'candidate',
    createdAt: start,
    updatedAt: start,
  );
}

TaskItem _task({
  required int id,
  required String summary,
  String? description,
  String categories = '',
}) {
  return TaskItem(
    id: id,
    uid: 'task-$id',
    dtstamp: DateTime(2026, 6, 12),
    summary: summary,
    description: description,
    priority: 0,
    status: 'NEEDS-ACTION',
    percentComplete: 0,
    categories: categories,
    durationMinutes: 30,
    isSplittable: true,
    priorityLocal: 0,
    isAutoScheduled: false,
    isLocked: false,
    reminderMinutesBefore: 0,
  );
}

FileFolder _folder({
  required int id,
  required String displayName,
  String? localPath,
}) {
  final now = DateTime(2026, 6, 12);
  return FileFolder(
    id: id,
    folderUid: 'folder-$id',
    provider: FileProviderKind.local,
    displayName: displayName,
    localPath: localPath,
    remoteId: null,
    parentPath: null,
    sourceContext: null,
    pinned: false,
    availability: FileAvailability.local,
    useCount: 0,
    lastUsedAt: null,
    metadataJson: '{}',
    createdAt: now,
    updatedAt: now,
  );
}

Map<String, Object?> _jsonMap(String raw) {
  return Map<String, Object?>.from(jsonDecode(raw) as Map);
}

Future<void> _recreateTrackedInputEventsWithNullableMetrics(
  AppDatabase db,
) async {
  await db.customStatement('DROP TABLE IF EXISTS tracked_input_events');
  await db.customStatement(
    '''
    CREATE TABLE tracked_input_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event_uid TEXT NOT NULL UNIQUE,
      sequence_id INTEGER NOT NULL,
      occurred_at TEXT NOT NULL,
      day_key TEXT NOT NULL,
      event_kind TEXT NOT NULL,
      record_id INTEGER,
      process_name TEXT,
      class_name TEXT,
      window_title TEXT,
      category TEXT,
      activity_label TEXT,
      is_ignored INTEGER NOT NULL DEFAULT 0,
      key_code INTEGER,
      key_label TEXT,
      mouse_button TEXT,
      wheel_delta INTEGER NOT NULL DEFAULT 0,
      delta_x INTEGER,
      delta_y INTEGER,
      move_distance INTEGER NOT NULL DEFAULT 0,
      event_count INTEGER,
      token_text TEXT,
      payload_json TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL
    )
    ''',
  );
}

String _dayKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

Future<void> _insertInputEventRow(
  AppDatabase db, {
  required String eventUid,
  required int sequenceId,
  required DateTime at,
  required String payloadJson,
  int? eventCount,
  int? deltaX,
  int? deltaY,
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
    ) VALUES (?, ?, ?, ?, ?, NULL, ?, NULL, NULL, ?, NULL, 0, NULL, NULL, NULL, 0, ?, ?, 0, ?, NULL, ?, ?)
    ''',
    <Object?>[
      eventUid,
      sequenceId,
      at.toIso8601String(),
      _dayKey(at),
      'mouse_move',
      'Code.exe',
      'coding',
      deltaX,
      deltaY,
      eventCount,
      payloadJson,
      DateTime.now().toIso8601String(),
    ],
  );
}

ProviderContainer _trackerContainer(AppDatabase db) {
  return ProviderContainer(
    overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      sequenceRecordingProvider.overrideWith((ref) => false),
    ],
  );
}

WindowSnapshot _snapshot({
  required String processName,
  required String className,
  required String windowTitle,
  required DateTime timestamp,
}) {
  return WindowSnapshot(
    processName: processName,
    className: className,
    windowTitle: windowTitle,
    isFullscreen: false,
    timestamp: timestamp,
  );
}

InputTelemetry _telemetry({
  required DateTime at,
  int keys = 0,
  List<RawInputEvent> events = const <RawInputEvent>[],
}) {
  return InputTelemetry(
    keyCount: keys,
    keyDistribution: keys == 0 ? const <int, int>{} : const <int, int>{65: 1},
    keySequence: keys == 0 ? null : 'A',
    clicks: const MouseClicks(),
    scrollPx: 0,
    mouseMovePx: 0,
    timestamp: at,
    inputEvents: events,
  );
}

RawInputEvent _rawEvent(int sequenceId, DateTime at, {int keyCode = 65}) {
  return RawInputEvent(
    sequenceId: sequenceId,
    timestampMicros: at.microsecondsSinceEpoch,
    kind: RawInputEventKind.keyDown,
    keyCode: keyCode,
  );
}

class _FakeRawInputService extends RawInputService {
  _FakeRawInputService() : super(isWindows: () => true);

  final List<Future<InputTelemetry?>> statsQueue = <Future<InputTelemetry?>>[];

  @override
  bool get isRunning => false;

  @override
  String? get lastError => null;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<InputTelemetry?> getStats() {
    if (statsQueue.isEmpty) {
      return Future<InputTelemetry?>.value(InputTelemetry.empty());
    }
    return statsQueue.removeAt(0);
  }

  @override
  Future<List<RawInputEvent>> getPendingInputEvents({
    int maxEvents = 1000,
  }) async {
    return const <RawInputEvent>[];
  }

  @override
  Future<void> ackInputEvents(int throughSequenceId) async {}
}

class _FakeActivityRecordRepository extends ActivityRecordRepository {
  _FakeActivityRecordRepository(super.db, this.records);

  final List<ActivityRecord> records;

  @override
  Future<List<ActivityRecord>> listInRange(DateTime start, DateTime end) async {
    return records
        .where((record) => !record.startTime.isBefore(start))
        .where((record) => record.startTime.isBefore(end))
        .toList(growable: false);
  }
}

class _FakeActivityLogService extends ActivityLogService {
  _FakeActivityLogService(super.db);

  @override
  Future<List<ActivityLogEntry>> readEntriesBetween(
    DateTime start,
    DateTime end, {
    int limit = 200,
    int offset = 0,
  }) async {
    return const <ActivityLogEntry>[];
  }
}

class _FakeInputActivityEventService extends InputActivityEventService {
  _FakeInputActivityEventService(super.db);

  @override
  Future<List<TrackedInputEvent>> listEvents({
    DateTime? start,
    DateTime? end,
    String? processName,
    String? category,
    String? eventKind,
    int limit = 200,
    int offset = 0,
    bool includeIgnored = false,
  }) async {
    return const <TrackedInputEvent>[];
  }
}

class _FakeTaskRepository extends TaskRepository {
  _FakeTaskRepository(super.db, this.tasks);

  final List<TaskItem> tasks;

  @override
  Future<List<TaskItem>> listAllVisible() async => tasks;
}

class _FakeFileContextRepository extends FileContextRepository {
  _FakeFileContextRepository(super.db, this.foldersByTaskId);

  final Map<int, List<FileFolder>> foldersByTaskId;

  @override
  Future<List<FileFolder>> listConfirmedFoldersForEntity({
    required String entityType,
    required String entityId,
  }) async {
    if (entityType != FileContextEntityType.task) {
      return const <FileFolder>[];
    }
    return foldersByTaskId[int.tryParse(entityId)] ?? const <FileFolder>[];
  }
}

class _FakeFusionRepository extends ActivityFusionRepository {
  _FakeFusionRepository(super.db);

  final List<ActivitySegment> segments = <ActivitySegment>[];
  final List<ActivityInterpretation> interpretations =
      <ActivityInterpretation>[];
  final List<TaskWorkLog> taskWorkLogs = <TaskWorkLog>[];
  int _nextSegmentId = 100;
  int _nextInterpretationId = 1;
  int _nextWorkLogId = 1;

  void seedSegment(ActivitySegment segment) {
    segments.add(segment);
  }

  ActivitySegment? segmentById(int id) {
    for (final segment in segments) {
      if (segment.id == id) {
        return segment;
      }
    }
    return null;
  }

  @override
  Future<void> replaceSegmentsForRange({
    required DateTime start,
    required DateTime end,
    required List<ActivitySegmentDraft> segments,
  }) async {
    this.segments
      ..clear()
      ..addAll(segments.map(_segmentFromDraft));
  }

  @override
  Future<List<ActivitySegment>> listSegmentsInRange(
    DateTime start,
    DateTime end, {
    int limit = 200,
    int offset = 0,
  }) async {
    return segments
        .where((segment) => segment.startAt.isBefore(end))
        .where((segment) => segment.endAt.isAfter(start))
        .skip(offset < 0 ? 0 : offset)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<ActivitySegment?> getSegmentById(int id) async => segmentById(id);

  @override
  Future<ActivityInterpretation> insertInterpretation({
    required int segmentId,
    required String summary,
    String? inferredProject,
    String? inferredDocument,
    int? inferredTaskId,
    required double confidence,
    Map<String, Object?> evidence = const <String, Object?>{},
    String status = 'candidate',
  }) async {
    final id = _nextInterpretationId++;
    final now = DateTime(2026, 6, 12);
    final interpretation = ActivityInterpretation(
      id: id,
      interpretationUid: 'interpretation-$id',
      segmentId: segmentId,
      summary: summary,
      inferredProject: inferredProject,
      inferredDocument: inferredDocument,
      inferredTaskId: inferredTaskId,
      confidence: confidence.clamp(0, 1).toDouble(),
      evidenceJson: jsonEncode(evidence),
      status: status,
      createdAt: now,
      updatedAt: now,
    );
    interpretations.add(interpretation);
    return interpretation;
  }

  @override
  Future<List<ActivityInterpretation>> listInterpretationsForSegment(
    int segmentId, {
    int limit = 200,
    int offset = 0,
  }) async {
    return interpretations
        .where((interpretation) => interpretation.segmentId == segmentId)
        .skip(offset < 0 ? 0 : offset)
        .take(limit)
        .toList(growable: false);
  }

  @override
  Future<TaskWorkLog> insertTaskWorkLog({
    required int taskId,
    int? segmentId,
    int? actualId,
    required DateTime startAt,
    required DateTime endAt,
    required double confidence,
    required String sourceType,
    Map<String, Object?> evidence = const <String, Object?>{},
    String status = 'candidate',
  }) async {
    final workLog = _workLog(
      taskId: taskId,
      segmentId: segmentId,
      actualId: actualId,
      startAt: startAt,
      endAt: endAt,
      confidence: confidence,
      sourceType: sourceType,
      evidence: evidence,
      status: status,
    );
    taskWorkLogs.add(workLog);
    return workLog;
  }

  @override
  Future<TaskWorkLog> upsertConfirmedTaskWorkLogForSegment({
    required int taskId,
    required int segmentId,
    required int actualId,
    required DateTime startAt,
    required DateTime endAt,
    required double confidence,
    required Map<String, Object?> evidence,
    String actor = 'user',
  }) async {
    final workLog = _workLog(
      taskId: taskId,
      segmentId: segmentId,
      actualId: actualId,
      startAt: startAt,
      endAt: endAt,
      confidence: confidence,
      sourceType: 'user_confirmed_activity_segment',
      evidence: evidence,
      status: 'confirmed',
    );
    taskWorkLogs.add(workLog);
    return workLog;
  }

  @override
  Future<void> rejectTaskWorkLogsForSegmentExcept({
    required int segmentId,
    required int taskId,
    String actor = 'user',
  }) async {}

  @override
  Future<void> updateSegmentStatus(
    int id, {
    required String status,
    String actor = 'user',
  }) async {
    final index = segments.indexWhere((segment) => segment.id == id);
    if (index != -1) {
      segments[index] = _copySegment(segments[index], status: status);
    }
  }

  @override
  Future<void> updateInterpretationsStatusForSegment(
    int segmentId, {
    required String status,
    String actor = 'user',
  }) async {
    for (var index = 0; index < interpretations.length; index += 1) {
      final interpretation = interpretations[index];
      if (interpretation.segmentId == segmentId) {
        interpretations[index] =
            _copyInterpretation(interpretation, status: status);
      }
    }
  }

  ActivitySegment _segmentFromDraft(ActivitySegmentDraft draft) {
    final id = _nextSegmentId++;
    final now = DateTime(2026, 6, 12);
    return ActivitySegment(
      id: id,
      segmentUid: 'segment-$id',
      startAt: draft.startAt,
      endAt: draft.endAt,
      primaryProcessName: draft.primaryProcessName,
      primaryWindowTitle: draft.primaryWindowTitle,
      category: draft.category,
      label: draft.label,
      sourceRecordIdsJson: jsonEncode(draft.sourceRecordIds),
      evidenceJson: jsonEncode(draft.evidence),
      confidence: draft.confidence,
      status: draft.status,
      createdAt: now,
      updatedAt: now,
    );
  }

  TaskWorkLog _workLog({
    required int taskId,
    int? segmentId,
    int? actualId,
    required DateTime startAt,
    required DateTime endAt,
    required double confidence,
    required String sourceType,
    required Map<String, Object?> evidence,
    required String status,
  }) {
    final id = _nextWorkLogId++;
    final now = DateTime(2026, 6, 12);
    return TaskWorkLog(
      id: id,
      workUid: 'work-$id',
      taskId: taskId,
      segmentId: segmentId,
      actualId: actualId,
      startAt: startAt,
      endAt: endAt,
      durationMinutes: endAt.difference(startAt).inMinutes,
      confidence: confidence.clamp(0, 1).toDouble(),
      sourceType: sourceType,
      evidenceJson: jsonEncode(evidence),
      status: status,
      createdAt: now,
      updatedAt: now,
    );
  }
}

class _FakeActualActivityLogRepository extends ActualActivityLogRepository {
  _FakeActualActivityLogRepository(super.db, {this.dropReadBack = false});

  final bool dropReadBack;
  final List<String> insertedTitles = <String>[];
  final List<ActualActivityLog> actuals = <ActualActivityLog>[];
  int _nextActualId = 1;

  @override
  Future<int> insertCandidate({
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    required String sourceType,
    String? sourceId,
    Map<String, Object?> sourcePayload = const <String, Object?>{},
    double confidence = 0.75,
    String? note,
    String actor = 'system',
  }) async {
    insertedTitles.add(title);
    final id = _nextActualId++;
    final now = DateTime(2026, 6, 12);
    if (!dropReadBack) {
      actuals.add(
        ActualActivityLog(
          id: id,
          actualUid: 'actual-$id',
          title: title,
          startAt: startAt,
          endAt: endAt,
          sourceType: sourceType,
          sourceId: sourceId,
          sourcePayloadJson: jsonEncode(sourcePayload),
          confidence: confidence.clamp(0, 1).toDouble(),
          status: ActualActivityStatus.candidate,
          note: note,
          createdAt: now,
          updatedAt: now,
          confirmedAt: null,
          rejectedAt: null,
          mergedIntoId: null,
        ),
      );
    }
    return id;
  }

  @override
  Future<void> confirm(
    int id, {
    String actor = 'user',
    String? note,
  }) async {
    final index = actuals.indexWhere((actual) => actual.id == id);
    if (index != -1) {
      actuals[index] = _copyActual(
        actuals[index],
        status: ActualActivityStatus.confirmed,
        note: note ?? actuals[index].note,
      );
    }
  }

  @override
  Future<ActualActivityLog?> getById(int id) async {
    for (final actual in actuals) {
      if (actual.id == id) {
        return actual;
      }
    }
    return null;
  }
}

ActivitySegment _copySegment(ActivitySegment segment,
    {required String status}) {
  return ActivitySegment(
    id: segment.id,
    segmentUid: segment.segmentUid,
    startAt: segment.startAt,
    endAt: segment.endAt,
    primaryProcessName: segment.primaryProcessName,
    primaryWindowTitle: segment.primaryWindowTitle,
    category: segment.category,
    label: segment.label,
    sourceRecordIdsJson: segment.sourceRecordIdsJson,
    evidenceJson: segment.evidenceJson,
    confidence: segment.confidence,
    status: status,
    createdAt: segment.createdAt,
    updatedAt: DateTime(2026, 6, 12, 1),
  );
}

ActivityInterpretation _copyInterpretation(
  ActivityInterpretation interpretation, {
  required String status,
}) {
  return ActivityInterpretation(
    id: interpretation.id,
    interpretationUid: interpretation.interpretationUid,
    segmentId: interpretation.segmentId,
    summary: interpretation.summary,
    inferredProject: interpretation.inferredProject,
    inferredDocument: interpretation.inferredDocument,
    inferredTaskId: interpretation.inferredTaskId,
    confidence: interpretation.confidence,
    evidenceJson: interpretation.evidenceJson,
    status: status,
    createdAt: interpretation.createdAt,
    updatedAt: DateTime(2026, 6, 12, 1),
  );
}

ActualActivityLog _copyActual(
  ActualActivityLog actual, {
  required String status,
  String? note,
}) {
  return ActualActivityLog(
    id: actual.id,
    actualUid: actual.actualUid,
    title: actual.title,
    startAt: actual.startAt,
    endAt: actual.endAt,
    sourceType: actual.sourceType,
    sourceId: actual.sourceId,
    sourcePayloadJson: actual.sourcePayloadJson,
    confidence: actual.confidence,
    status: status,
    note: note,
    createdAt: actual.createdAt,
    updatedAt: DateTime(2026, 6, 12, 1),
    confirmedAt: DateTime(2026, 6, 12, 1),
    rejectedAt: actual.rejectedAt,
    mergedIntoId: actual.mergedIntoId,
  );
}
