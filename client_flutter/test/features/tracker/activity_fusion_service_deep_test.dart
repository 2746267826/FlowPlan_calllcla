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
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  group('ActivityFusionService rebuildRange', () {
    test('merges activity records, raw logs, and input events into one segment',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final base = DateTime(2026, 6, 10, 9);
      final fusion = _FakeFusionRepository(db);
      final service = _service(
        db,
        records: <ActivityRecord>[
          _record(
            id: 10,
            start: base,
            durationMinutes: 20,
            processName: 'Code.exe',
            windowTitle: 'sprint_alpha_design.md - Code',
            category: 'coding',
            manualLabel: 'Implementation',
            linkedTaskId: 1,
            keyCount: 25,
          ),
        ],
        rawLogs: <ActivityLogEntry>[
          _rawLog(
            at: base.add(const Duration(minutes: 21)),
            durationMinutes: 4,
            recordId: 10,
            processName: 'Code.exe',
            windowTitle: 'sprint_alpha_design.md - Code',
            category: 'coding',
            label: 'Implementation',
            mouseClicks: 3,
          ),
        ],
        inputEvents: <TrackedInputEvent>[
          _inputEvent(
            sequenceId: 1,
            at: base.add(const Duration(minutes: 25, seconds: 10)),
            kind: TrackedInputEventKind.keyDown,
            eventCount: 2,
            recordId: 10,
            processName: 'Code.exe',
            windowTitle: 'sprint_alpha_design.md - Code',
            category: 'coding',
            activityLabel: 'Implementation',
          ),
          _inputEvent(
            sequenceId: 2,
            at: base.add(const Duration(minutes: 26)),
            kind: TrackedInputEventKind.mouseButtonDown,
            recordId: 10,
            processName: 'Code.exe',
            windowTitle: 'sprint_alpha_design.md - Code',
            category: 'coding',
            activityLabel: 'Implementation',
          ),
          _inputEvent(
            sequenceId: 3,
            at: base.add(const Duration(minutes: 26, seconds: 30)),
            kind: TrackedInputEventKind.mouseWheel,
            recordId: 10,
            processName: 'Code.exe',
            windowTitle: 'sprint_alpha_design.md - Code',
            category: 'coding',
            activityLabel: 'Implementation',
            wheelDelta: -240,
          ),
        ],
        fusion: fusion,
        tasks: <TaskItem>[
          _task(
            id: 1,
            summary: 'Implement sprint alpha parser',
            description: 'Code the alpha workflow parser',
            categories: 'coding',
          ),
        ],
        foldersByTaskId: <int, List<FileFolder>>{
          1: <FileFolder>[
            _folder(
              id: 1,
              displayName: 'Sprint Alpha',
              localPath: r'C:\work\sprint-alpha',
            ),
          ],
        },
      );

      final result = await service.rebuildRange(
        start: base,
        end: base.add(const Duration(hours: 1)),
      );

      expect(result.sourceRecordCount, 1);
      expect(result.rawLogCount, 1);
      expect(result.inputEventCount, 3);
      expect(result.segmentCount, 1);
      expect(result.interpretationCount, 1);
      expect(result.taskWorkLogCount, 1);
      expect(result.actualCandidateCount, 0);

      final segment = fusion.segments.single;
      expect(segment.startAt, base);
      expect(
        segment.endAt,
        base.add(const Duration(minutes: 27, seconds: 30)),
      );
      expect(segment.primaryProcessName, 'Code.exe');
      expect(segment.primaryWindowTitle, 'sprint_alpha_design.md - Code');
      expect(segment.category, 'coding');
      expect(segment.label, 'Implementation');
      expect(segment.confidence, 0.95);
      expect(jsonDecode(segment.sourceRecordIdsJson), <Object?>[10]);

      final evidence = _jsonMap(segment.evidenceJson);
      expect(evidence['sourceCount'], 3);
      expect(evidence['activityRecordCount'], 1);
      expect(evidence['rawLogCount'], 1);
      expect(evidence['inputEventCount'], 4);
      expect(evidence['linkedTaskIds'], <Object?>[1]);
      expect(evidence['hasInputTelemetry'], isTrue);

      final interpretation = fusion.interpretations.single;
      expect(interpretation.segmentId, segment.id);
      expect(interpretation.inferredTaskId, 1);
      expect(interpretation.inferredProject, 'coding');
      expect(interpretation.inferredDocument, 'sprint_alpha_design.md');
      expect(interpretation.status, 'candidate');
      expect(
          _jsonMap(interpretation.evidenceJson)['matchedBy'], 'keyword+folder');

      final workLog = fusion.taskWorkLogs.single;
      expect(workLog.taskId, 1);
      expect(workLog.segmentId, segment.id);
      expect(workLog.startAt, segment.startAt);
      expect(workLog.endAt, segment.endAt);
      expect(workLog.status, 'candidate');
      expect(workLog.sourceType, 'activity_interpretation');
    });

    test('splits conflicting contexts and de-duplicates repeated source ids',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final base = DateTime(2026, 6, 10, 10);
      final fusion = _FakeFusionRepository(db);
      final service = _service(
        db,
        records: <ActivityRecord>[
          _record(
            id: 21,
            start: base,
            durationMinutes: 5,
            processName: 'Code.exe',
            category: 'coding',
          ),
          _record(
            id: 21,
            start: base.add(const Duration(minutes: 2)),
            durationMinutes: 4,
            processName: 'Code.exe',
            category: 'coding',
          ),
        ],
        rawLogs: <ActivityLogEntry>[
          _rawLog(
            at: base.add(const Duration(minutes: 4)),
            durationMinutes: 5,
            recordId: 99,
            processName: 'Browser.exe',
            category: 'research',
            label: 'Research',
          ),
        ],
        fusion: fusion,
      );

      final result = await service.rebuildRange(
        start: base,
        end: base.add(const Duration(hours: 1)),
      );

      expect(result.segmentCount, 2);
      expect(fusion.segments.map((segment) => segment.primaryProcessName),
          <String?>['Code.exe', 'Browser.exe']);

      final duplicateSegment = fusion.segments.first;
      expect(jsonDecode(duplicateSegment.sourceRecordIdsJson), <Object?>[21]);
      expect(_jsonMap(duplicateSegment.evidenceJson)['sourceCount'], 2);

      final conflictingSegment = fusion.segments.last;
      expect(conflictingSegment.startAt, base.add(const Duration(minutes: 4)));
      expect(conflictingSegment.category, 'research');
      expect(conflictingSegment.label, 'Research');
      expect(jsonDecode(conflictingSegment.sourceRecordIdsJson), <Object?>[99]);
    });

    test('merges exactly at the max gap and falls back to process label',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final base = DateTime(2026, 6, 10, 11);
      final fusion = _FakeFusionRepository(db);
      final service = _service(
        db,
        records: <ActivityRecord>[
          _record(
            id: 31,
            start: base,
            durationMinutes: 5,
            processName: 'Terminal.exe',
            category: null,
          ),
          _record(
            id: 32,
            start: base.add(const Duration(minutes: 15)),
            durationMinutes: 5,
            processName: 'Terminal.exe',
            category: null,
          ),
          _record(
            id: 33,
            start: base.add(const Duration(minutes: 31)),
            durationMinutes: 5,
            processName: 'Terminal.exe',
            category: null,
          ),
        ],
        fusion: fusion,
      );

      await service.rebuildRange(
        start: base,
        end: base.add(const Duration(hours: 1)),
        maxMergeGap: const Duration(minutes: 10),
      );

      expect(fusion.segments, hasLength(2));
      expect(fusion.segments.first.startAt, base);
      expect(
        fusion.segments.first.endAt,
        base.add(const Duration(minutes: 20)),
      );
      expect(fusion.segments.first.category, isNull);
      expect(fusion.segments.first.label, 'Terminal.exe');
      expect(jsonDecode(fusion.segments.first.sourceRecordIdsJson),
          <Object?>[31, 32]);
      expect(fusion.interpretations.first.summary, contains('Terminal.exe'));

      expect(
        fusion.segments.last.startAt,
        base.add(const Duration(minutes: 31)),
      );
      expect(
          jsonDecode(fusion.segments.last.sourceRecordIdsJson), <Object?>[33]);
    });

    test('returns empty output and skips open or ignored evidence', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final base = DateTime(2026, 6, 10, 12);
      final fusion = _FakeFusionRepository(db);
      final service = _service(
        db,
        records: <ActivityRecord>[
          _record(
            id: 41,
            start: base,
            durationMinutes: 0,
            endTime: null,
            processName: 'Code.exe',
            category: 'coding',
          ),
        ],
        rawLogs: <ActivityLogEntry>[
          _rawLog(
            at: base.add(const Duration(minutes: 1)),
            processName: 'Code.exe',
            category: 'coding',
            isIgnored: true,
          ),
        ],
        inputEvents: <TrackedInputEvent>[
          _inputEvent(
            sequenceId: 1,
            at: base.add(const Duration(minutes: 2)),
            processName: 'Code.exe',
            category: 'coding',
            isIgnored: true,
          ),
        ],
        fusion: fusion,
        inputSourceRespectsIgnoredFlag: false,
      );

      final result = await service.rebuildRange(
        start: base,
        end: base.add(const Duration(hours: 1)),
      );

      expect(result.sourceRecordCount, 1);
      expect(result.rawLogCount, 1);
      expect(result.inputEventCount, 1);
      expect(result.segmentCount, 0);
      expect(result.interpretationCount, 0);
      expect(result.taskWorkLogCount, 0);
      expect(fusion.segments, isEmpty);
      expect(fusion.interpretations, isEmpty);
      expect(fusion.taskWorkLogs, isEmpty);
    });

    test('passes exact range bounds to sources and keeps end exclusive',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final base = DateTime(2026, 6, 10, 13);
      final fusion = _FakeFusionRepository(db);
      final recordSource = _FakeActivityRecordRepository(
        db,
        records: <ActivityRecord>[
          _record(
            id: 51,
            start: base.subtract(const Duration(minutes: 10)),
            durationMinutes: 5,
            processName: 'Before.exe',
          ),
          _record(
            id: 52,
            start: base,
            durationMinutes: 5,
            processName: 'Inside.exe',
          ),
        ],
      );
      final rawSource = _FakeActivityLogService(
        db,
        logs: <ActivityLogEntry>[
          _rawLog(
            at: base.add(const Duration(minutes: 6)),
            processName: 'Inside.exe',
          ),
          _rawLog(
            at: base.add(const Duration(hours: 1)),
            processName: 'EndExclusive.exe',
          ),
        ],
      );
      final inputSource = _FakeInputActivityEventService(
        db,
        events: <TrackedInputEvent>[
          _inputEvent(
            sequenceId: 1,
            at: base.add(const Duration(minutes: 7)),
            processName: 'Inside.exe',
          ),
          _inputEvent(
            sequenceId: 2,
            at: base.add(const Duration(hours: 1)),
            processName: 'EndExclusive.exe',
          ),
        ],
      );
      final service = ActivityFusionService(
        recordSource,
        rawSource,
        inputSource,
        fusion,
        _FakeTaskRepository(db),
        _FakeFileContextRepository(db),
        _FakeActualActivityLogRepository(db),
      );

      final result = await service.rebuildRange(
        start: base,
        end: base.add(const Duration(hours: 1)),
      );

      expect(recordSource.lastStart, base);
      expect(recordSource.lastEnd, base.add(const Duration(hours: 1)));
      expect(rawSource.lastLimit, 1000);
      expect(inputSource.lastLimit, 2000);
      expect(inputSource.lastIncludeIgnored, isFalse);
      expect(result.sourceRecordCount, 1);
      expect(result.rawLogCount, 1);
      expect(result.inputEventCount, 1);
      expect(fusion.segments, hasLength(1));
      expect(fusion.segments.single.primaryProcessName, 'Inside.exe');
    });
  });

  group('ActivityFusionService confirmSegment', () {
    test('creates confirmed actual log and resolves competing task work logs',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final base = DateTime(2026, 6, 10, 15);
      final fusion = _FakeFusionRepository(db);
      final actualLogs = _FakeActualActivityLogRepository(db);
      final service = _service(
        db,
        records: <ActivityRecord>[
          _record(
            id: 61,
            start: base,
            durationMinutes: 30,
            processName: 'Code.exe',
            windowTitle: 'alpha_report.md - Code',
            category: 'coding',
            linkedTaskId: 7,
          ),
        ],
        fusion: fusion,
        actualLogs: actualLogs,
        tasks: <TaskItem>[
          _task(
            id: 7,
            summary: 'Write alpha report',
            description: 'Finish alpha_report.md',
            categories: 'reporting',
          ),
        ],
      );

      await service.rebuildRange(
        start: base,
        end: base.add(const Duration(hours: 1)),
      );
      final segment = fusion.segments.single;
      await fusion.insertTaskWorkLog(
        taskId: 99,
        segmentId: segment.id,
        startAt: segment.startAt,
        endAt: segment.endAt,
        confidence: 0.4,
        sourceType: 'activity_interpretation',
        status: 'candidate',
      );

      final result = await service.confirmSegment(
        segment.id,
        note: 'looks right',
        actor: 'tester',
      );

      expect(result.actual.isConfirmed, isTrue);
      expect(
          result.actual.sourceType, ActualActivitySourceType.trackingInference);
      expect(result.actual.sourceId, segment.segmentUid);
      expect(result.actual.note, 'looks right');
      expect(result.taskWorkLog, isNotNull);
      expect(result.taskWorkLog?.taskId, 7);
      expect(result.taskWorkLog?.actualId, result.actual.id);
      expect(result.taskWorkLog?.status, 'confirmed');
      expect(result.taskWorkLog?.sourceType, 'user_confirmed_activity_segment');

      expect(fusion.segmentById(segment.id)?.status, 'confirmed');
      expect(
        fusion.interpretations
            .where((item) => item.segmentId == segment.id)
            .map((item) => item.status)
            .toSet(),
        <String>{'confirmed'},
      );
      expect(
        fusion.taskWorkLogs
            .where((item) => item.segmentId == segment.id && item.taskId == 99)
            .single
            .status,
        'rejected',
      );
    });
  });
}

ActivityFusionService _service(
  AppDatabase db, {
  List<ActivityRecord> records = const <ActivityRecord>[],
  List<ActivityLogEntry> rawLogs = const <ActivityLogEntry>[],
  List<TrackedInputEvent> inputEvents = const <TrackedInputEvent>[],
  _FakeFusionRepository? fusion,
  _FakeActualActivityLogRepository? actualLogs,
  List<TaskItem> tasks = const <TaskItem>[],
  Map<int, List<FileFolder>> foldersByTaskId = const <int, List<FileFolder>>{},
  bool inputSourceRespectsIgnoredFlag = true,
}) {
  return ActivityFusionService(
    _FakeActivityRecordRepository(db, records: records),
    _FakeActivityLogService(db, logs: rawLogs),
    _FakeInputActivityEventService(
      db,
      events: inputEvents,
      respectIncludeIgnoredFlag: inputSourceRespectsIgnoredFlag,
    ),
    fusion ?? _FakeFusionRepository(db),
    _FakeTaskRepository(db, tasks: tasks),
    _FakeFileContextRepository(db, foldersByTaskId: foldersByTaskId),
    actualLogs ?? _FakeActualActivityLogRepository(db),
  );
}

ActivityRecord _record({
  required int id,
  required DateTime start,
  int durationMinutes = 5,
  DateTime? endTime,
  String? manualLabel,
  String? processName = 'Code.exe',
  String? windowTitle,
  String? packageName,
  String? category = 'coding',
  int? linkedTaskId,
  int keyCount = 0,
  int mouseClicks = 0,
  int mouseMovePx = 0,
  int scrollPx = 0,
}) {
  final resolvedEnd = endTime ??
      (durationMinutes <= 0
          ? null
          : start.add(Duration(minutes: durationMinutes)));
  return ActivityRecord(
    id: id,
    startTime: start,
    endTime: resolvedEnd,
    durationMinutes: durationMinutes,
    keyCount: keyCount,
    mouseClicks: mouseClicks,
    mouseMovePx: mouseMovePx,
    scrollPx: scrollPx,
    manualLabel: manualLabel,
    processName: processName,
    windowTitle: windowTitle,
    packageName: packageName,
    category: category,
    linkedTaskId: linkedTaskId,
    isAuto: true,
    source: 'test',
  );
}

ActivityLogEntry _rawLog({
  required DateTime at,
  int? durationMinutes = 1,
  int? recordId,
  bool isIgnored = false,
  String? processName = 'Code.exe',
  String? windowTitle,
  String? category = 'coding',
  String? label,
  int keyCount = 0,
  int mouseClicks = 0,
  int mouseMovePx = 0,
  int scrollPx = 0,
}) {
  return ActivityLogEntry(
    timestamp: at,
    type: ActivityLogEntryType.sample,
    recordId: recordId,
    isIgnored: isIgnored,
    processName: processName,
    windowTitle: windowTitle,
    category: category,
    label: label,
    durationMinutes: durationMinutes,
    keyCount: keyCount,
    mouseClicks: mouseClicks,
    mouseMovePx: mouseMovePx,
    scrollPx: scrollPx,
  );
}

TrackedInputEvent _inputEvent({
  required int sequenceId,
  required DateTime at,
  TrackedInputEventKind kind = TrackedInputEventKind.keyDown,
  int eventCount = 1,
  int? recordId,
  bool isIgnored = false,
  String? processName = 'Code.exe',
  String? windowTitle,
  String? category = 'coding',
  String? activityLabel,
  int wheelDelta = 0,
  int moveDistance = 0,
}) {
  return TrackedInputEvent(
    eventUid: 'event-$sequenceId',
    sequenceId: sequenceId,
    timestamp: at,
    kind: kind,
    eventCount: eventCount,
    recordId: recordId,
    isIgnored: isIgnored,
    processName: processName,
    windowTitle: windowTitle,
    category: category,
    activityLabel: activityLabel,
    wheelDelta: wheelDelta,
    moveDistance: moveDistance,
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
    dtstamp: DateTime(2026, 6, 10),
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
  final now = DateTime(2026, 6, 10);
  return FileFolder(
    id: id,
    folderUid: 'folder-$id',
    provider: FileProviderKind.local,
    displayName: displayName,
    localPath: localPath,
    remoteId: null,
    parentPath: null,
    sourceContext: displayName,
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

class _FakeActivityRecordRepository extends ActivityRecordRepository {
  _FakeActivityRecordRepository(
    super.db, {
    this.records = const <ActivityRecord>[],
  });

  final List<ActivityRecord> records;
  DateTime? lastStart;
  DateTime? lastEnd;

  @override
  Future<List<ActivityRecord>> listInRange(DateTime start, DateTime end) async {
    lastStart = start;
    lastEnd = end;
    return records
        .where(
          (record) =>
              record.startTime.isBefore(end) &&
              ((record.endTime == null) || !record.endTime!.isBefore(start)),
        )
        .toList(growable: false);
  }
}

class _FakeActivityLogService extends ActivityLogService {
  _FakeActivityLogService(
    super.db, {
    this.logs = const <ActivityLogEntry>[],
  });

  final List<ActivityLogEntry> logs;
  int? lastLimit;

  @override
  Future<List<ActivityLogEntry>> readEntriesBetween(
    DateTime start,
    DateTime end, {
    int limit = 200,
    int offset = 0,
  }) async {
    lastLimit = limit;
    return logs
        .where(
          (log) =>
              !log.timestamp.isBefore(start) && log.timestamp.isBefore(end),
        )
        .skip(offset < 0 ? 0 : offset)
        .take(limit)
        .toList(growable: false);
  }
}

class _FakeInputActivityEventService extends InputActivityEventService {
  _FakeInputActivityEventService(
    super.db, {
    this.events = const <TrackedInputEvent>[],
    this.respectIncludeIgnoredFlag = true,
  });

  final List<TrackedInputEvent> events;
  final bool respectIncludeIgnoredFlag;
  int? lastLimit;
  bool? lastIncludeIgnored;

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
    lastLimit = limit;
    lastIncludeIgnored = includeIgnored;
    return events
        .where((event) => start == null || !event.timestamp.isBefore(start))
        .where((event) => end == null || event.timestamp.isBefore(end))
        .where((event) =>
            includeIgnored || !respectIncludeIgnoredFlag || !event.isIgnored)
        .skip(offset < 0 ? 0 : offset)
        .take(limit)
        .toList(growable: false);
  }
}

class _FakeTaskRepository extends TaskRepository {
  _FakeTaskRepository(
    super.db, {
    this.tasks = const <TaskItem>[],
  });

  final List<TaskItem> tasks;

  @override
  Future<List<TaskItem>> listAllVisible() async => tasks;
}

class _FakeFileContextRepository extends FileContextRepository {
  _FakeFileContextRepository(
    super.db, {
    this.foldersByTaskId = const <int, List<FileFolder>>{},
  });

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
  int _nextSegmentId = 1;
  int _nextInterpretationId = 1;
  int _nextWorkLogId = 1;

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
    this.segments.removeWhere(
          (segment) =>
              segment.startAt.isBefore(end) &&
              segment.endAt.isAfter(start) &&
              segment.status != 'confirmed',
        );
    interpretations.removeWhere(
      (interpretation) => segmentById(interpretation.segmentId) == null,
    );
    taskWorkLogs.removeWhere(
      (workLog) =>
          workLog.segmentId != null && segmentById(workLog.segmentId!) == null,
    );
    this.segments.addAll(segments.map(_segmentFromDraft));
    this.segments.sort((left, right) => left.startAt.compareTo(right.startAt));
  }

  @override
  Future<List<ActivitySegment>> listSegmentsInRange(
    DateTime start,
    DateTime end, {
    int limit = 200,
    int offset = 0,
  }) async {
    final matches = segments
        .where(
          (segment) =>
              segment.startAt.isBefore(end) && segment.endAt.isAfter(start),
        )
        .toList(growable: false)
      ..sort((left, right) => left.startAt.compareTo(right.startAt));
    return matches
        .skip(offset < 0 ? 0 : offset)
        .take(limit)
        .toList(growable: false);
  }

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
    final now = DateTime(2026, 6, 10);
    final interpretation = ActivityInterpretation(
      id: _nextInterpretationId++,
      interpretationUid: 'interpretation-${_nextInterpretationId - 1}',
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
  Future<ActivitySegment?> getSegmentById(int id) async => segmentById(id);

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
    final existingIndex = taskWorkLogs.indexWhere(
      (workLog) => workLog.taskId == taskId && workLog.segmentId == segmentId,
    );
    final updated = _workLog(
      id: existingIndex == -1 ? null : taskWorkLogs[existingIndex].id,
      workUid: existingIndex == -1 ? null : taskWorkLogs[existingIndex].workUid,
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
    if (existingIndex == -1) {
      taskWorkLogs.add(updated);
    } else {
      taskWorkLogs[existingIndex] = updated;
    }
    return updated;
  }

  @override
  Future<void> rejectTaskWorkLogsForSegmentExcept({
    required int segmentId,
    required int taskId,
    String actor = 'user',
  }) async {
    for (var index = 0; index < taskWorkLogs.length; index += 1) {
      final workLog = taskWorkLogs[index];
      if (workLog.segmentId == segmentId &&
          workLog.taskId != taskId &&
          workLog.status != 'rejected') {
        taskWorkLogs[index] = _copyWorkLog(workLog, status: 'rejected');
      }
    }
  }

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
        interpretations[index] = _copyInterpretation(
          interpretation,
          status: status,
        );
      }
    }
  }

  ActivitySegment _segmentFromDraft(ActivitySegmentDraft draft) {
    final now = DateTime(2026, 6, 10);
    final id = _nextSegmentId++;
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
    int? id,
    String? workUid,
    required int taskId,
    int? segmentId,
    int? actualId,
    required DateTime startAt,
    required DateTime endAt,
    required double confidence,
    required String sourceType,
    Map<String, Object?> evidence = const <String, Object?>{},
    String status = 'candidate',
  }) {
    final resolvedId = id ?? _nextWorkLogId++;
    final now = DateTime(2026, 6, 10);
    return TaskWorkLog(
      id: resolvedId,
      workUid: workUid ?? 'work-$resolvedId',
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
  _FakeActualActivityLogRepository(super.db);

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
    final id = _nextActualId++;
    final now = DateTime(2026, 6, 10);
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
    return id;
  }

  @override
  Future<void> confirm(
    int id, {
    String actor = 'user',
    String? note,
  }) async {
    final index = actuals.indexWhere((actual) => actual.id == id);
    if (index == -1) {
      return;
    }
    actuals[index] = _copyActual(
      actuals[index],
      status: ActualActivityStatus.confirmed,
      note: note ?? actuals[index].note,
      confirmedAt: DateTime(2026, 6, 10, 1),
    );
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

ActivitySegment _copySegment(ActivitySegment segment, {String? status}) {
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
    status: status ?? segment.status,
    createdAt: segment.createdAt,
    updatedAt: DateTime(2026, 6, 10, 1),
  );
}

ActivityInterpretation _copyInterpretation(
  ActivityInterpretation interpretation, {
  String? status,
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
    status: status ?? interpretation.status,
    createdAt: interpretation.createdAt,
    updatedAt: DateTime(2026, 6, 10, 1),
  );
}

TaskWorkLog _copyWorkLog(TaskWorkLog workLog, {String? status}) {
  return TaskWorkLog(
    id: workLog.id,
    workUid: workLog.workUid,
    taskId: workLog.taskId,
    segmentId: workLog.segmentId,
    actualId: workLog.actualId,
    startAt: workLog.startAt,
    endAt: workLog.endAt,
    durationMinutes: workLog.durationMinutes,
    confidence: workLog.confidence,
    sourceType: workLog.sourceType,
    evidenceJson: workLog.evidenceJson,
    status: status ?? workLog.status,
    createdAt: workLog.createdAt,
    updatedAt: DateTime(2026, 6, 10, 1),
  );
}

ActualActivityLog _copyActual(
  ActualActivityLog actual, {
  String? status,
  String? note,
  DateTime? confirmedAt,
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
    status: status ?? actual.status,
    note: note,
    createdAt: actual.createdAt,
    updatedAt: DateTime(2026, 6, 10, 1),
    confirmedAt: confirmedAt ?? actual.confirmedAt,
    rejectedAt: actual.rejectedAt,
    mergedIntoId: actual.mergedIntoId,
  );
}
