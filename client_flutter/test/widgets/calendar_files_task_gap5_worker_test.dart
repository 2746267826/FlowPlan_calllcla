import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide Uint8List, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/server_api/file_cloud_api.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/calendar/presentation/timeline_view.dart';
import 'package:flowplanv2/features/files/services/file_transfer_service.dart';
import 'package:flowplanv2/features/scheduler/task_schedule_segment_repository.dart';
import 'package:flowplanv2/features/task/presentation/widgets/task_tracker_evidence_section.dart';
import 'package:flowplanv2/features/tracker/data/activity_fusion_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
import 'package:flowplanv2/features/tracker/models/input_heatmap_summary.dart';
import 'package:flowplanv2/features/tracker/models/tracked_input_event.dart';
import 'package:flowplanv2/features/tracker/services/input_activity_event_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/widgets/task_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_support/fixtures.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('event repository watches ranges, calendars, and sync create evidence',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final evidence = _createEvidence(db);
    final repository = EventRepository(
      db,
      evidence.auditRepository,
      evidence.recorder,
    );
    final calendarId = await insertFixtureCalendar(db, name: 'Gap calendar');
    final otherCalendarId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Other calendar',
            createdAt: fixtureNow().add(const Duration(minutes: 1)),
          ),
        );

    final createdId = await repository.create(
      fixtureEvent(
        uid: 'gap5-created-event',
        summary: 'Gap5 created event',
        calendarId: calendarId,
      ),
      metadata: const <String, Object?>{'source': 'gap5'},
    );
    await repository.create(
      fixtureEvent(
        uid: 'gap5-other-event',
        summary: 'Gap5 other event',
        calendarId: otherCalendarId,
      ),
      audit: false,
    );

    final rangeEvents = await repository
        .watchForDateRange(
          fixtureNow().subtract(const Duration(minutes: 1)),
          fixtureNow().add(const Duration(hours: 1)),
        )
        .first;
    final calendarEvents = await repository.watchByCalendar(calendarId).first;
    final auditRows = await evidence.auditRepository.listRecent();
    final pendingMutations = await evidence.mutationStore.listPending();

    expect(rangeEvents.map((event) => event.summary),
        contains('Gap5 created event'));
    expect(rangeEvents.map((event) => event.summary),
        contains('Gap5 other event'));
    expect(calendarEvents.map((event) => event.id), <int>[createdId]);
    expect(auditRows.map((row) => row.action), contains('create'));
    expect(
      pendingMutations
          .where((mutation) => mutation.objectType == 'calendar_event')
          .map((mutation) => mutation.localId),
      contains(createdId.toString()),
    );
  });

  test('file transfer covers dynamic maps and guarded transfer failures',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final tempDir =
        await Directory.systemTemp.createTemp('flowplanv2-gap5-xfer-');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final uploadFile =
        File('${tempDir.path}${Platform.pathSeparator}dynamic.txt');
    final bytes = utf8.encode('dynamic upload');
    await uploadFile.writeAsBytes(bytes);
    final checksum = sha256.convert(bytes).toString();
    final dynamicApi = _Gap5FileCloudApi(
      uploadCompleteChecksum: checksum,
      useDynamicMaps: true,
    );
    final dynamicService = _createTransferService(db, dynamicApi);
    addTearDown(dynamicService.dispose);

    await dynamicService.uploadFile(uploadFile.path);

    expect(dynamicService.jobs.single.status, FileTransferStatus.uploaded);
    expect(
        dynamicService.jobs.single.storageObjectId, 'dynamic-storage-object');
    expect(dynamicApi.uploadedChunks.single['bytes'], bytes);

    final missingSessionFile =
        File('${tempDir.path}${Platform.pathSeparator}missing-session.txt');
    await missingSessionFile.writeAsString('missing session');
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final missingSessionService = _createTransferService(
      db,
      _Gap5FileCloudApi(omitUploadSessionId: true),
    );
    addTearDown(missingSessionService.dispose);

    await expectLater(
      missingSessionService.uploadFile(missingSessionFile.path),
      throwsA(isA<StateError>()),
    );
    expect(missingSessionService.jobs, isEmpty);

    final zeroFile = File('${tempDir.path}${Platform.pathSeparator}zero.bin');
    await zeroFile.writeAsBytes(const <int>[]);
    final zeroService = _createTransferService(
      db,
      _Gap5FileCloudApi(uploadCompleteOk: false),
    );
    addTearDown(zeroService.dispose);

    await expectLater(
      zeroService.uploadFile(zeroFile.path),
      throwsA(isA<StateError>()),
    );
    expect(zeroService.jobs.first.expectedChunks, 0);
    expect(zeroService.jobs.first.status, FileTransferStatus.failed);

    final resumeService = _createTransferService(db, _Gap5FileCloudApi());
    addTearDown(resumeService.dispose);
    final downloadJob = _transferJob(
      localPath: '${tempDir.path}${Platform.pathSeparator}zero-download.txt',
      totalBytes: 0,
    );

    await expectLater(
      resumeService.resumeDownload(downloadJob),
      throwsA(isA<StateError>()),
    );
    final failedDownload = resumeService.jobs.first;
    expect(failedDownload.status, FileTransferStatus.failed);
    expect(failedDownload.canResume, isTrue);
    expect(failedDownload.errorMessage, contains('Bad state'));
    expect(
      await File('${downloadJob.localPath}.flowplanv2.part').exists(),
      isFalse,
    );
    expect(
      await _auditActions(db),
      containsAll(<String>[
        'file_transfer.download.resume',
        'file_transfer.download.failed',
      ]),
    );
  });

  testWidgets('timeline covers segment fallback, hover leave, and desktop open',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final calendarId =
        await insertFixtureCalendar(db, name: 'Desktop calendar');
    final taskListId = await insertFixtureTaskList(db, name: 'Desktop tasks');
    final day = DateTime(2026, 6, 10);
    final hour = _visibleHour();
    final eventId = await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            uid: 'desktop-event',
            dtstamp: day,
            summary: 'Desktop open event',
            dtstart: _at(day, hour),
            dtend: Value(_at(day, hour, 45)),
            eventCalendarId: Value(calendarId),
          ),
        );
    final taskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'desktop-task',
            dtstamp: day,
            summary: 'Desktop open task',
            taskListId: Value(taskListId),
            dtstart: Value(_at(day, hour + 1)),
            durationMinutes: const Value(45),
          ),
        );
    final task = _task(
      id: taskId,
      summary: 'Desktop open task',
      start: _at(day, hour + 1),
      taskListId: taskListId,
    );

    await _pumpTimeline(
      tester,
      db: db,
      size: const Size(920, 900),
      selectedDate: day,
      tasks: <TaskItem>[task],
      events: <CalendarEvent>[
        _event(
          id: eventId,
          summary: 'Desktop open event',
          start: _at(day, hour),
          end: _at(day, hour, 45),
          calendarId: calendarId,
        ),
      ],
      segments: <TaskScheduleSegmentWithTask>[
        TaskScheduleSegmentWithTask(
          task: task,
          segment: _segment(
            id: 8001,
            taskId: taskId,
            start: _at(day, hour + 2),
            end: _at(day, hour + 2, 30),
          ),
        ),
      ],
    );

    expect(find.text('Desktop open task'), findsNothing);
    expect(find.text('Desktop open task (1)'), findsOneWidget);

    tester
        .widget<TaskBlock>(
            find.byKey(ValueKey<String>('timeline_event_$eventId')))
        .onTap
        ?.call();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pump();

    tester
        .widget<TaskBlock>(
          find.byKey(const ValueKey<String>('timeline_task_segment_8001')),
        )
        .onTap
        ?.call();
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pump();

    final targetFinder = find.byWidgetPredicate(
      (widget) => widget is DragTarget<TaskItem>,
    );
    final target = tester.widget<DragTarget<TaskItem>>(targetFinder);
    target.onMove?.call(
      DragTargetDetails<TaskItem>(
        data: task,
        offset: tester.getRect(targetFinder).center,
      ),
    );
    await tester.pump();

    target.onLeave?.call(task);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('timeline keeps dated tasks visible when segment stream errors',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final day = DateTime(2026, 6, 10);

    await _pumpTimeline(
      tester,
      db: db,
      size: const Size(620, 860),
      selectedDate: day,
      tasks: <TaskItem>[
        _task(
          id: 9001,
          summary: 'Segments unavailable task',
          start: _at(day, _visibleHour()),
        ),
      ],
      overrides: <Override>[
        taskScheduleSegmentsForSelectedDateProvider.overrideWith(
          (ref) => Stream<List<TaskScheduleSegmentWithTask>>.error(
            StateError('segments unavailable'),
          ),
        ),
      ],
    );

    expect(find.text('Segments unavailable task'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('task evidence renders remaining recent input event titles',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final base = DateTime(2026, 6, 9, 9);
    final recordsRepo = _Gap5ActivityRecordRepository(
      db,
      records: <ActivityRecord>[
        _activityRecord(id: 1, start: base),
      ],
    );
    final inputService = _Gap5InputActivityEventService(
      db,
      summary: _inputSummary(totalEvents: 7),
      recentEvents: <TrackedInputEvent>[
        _trackedEvent(
          uid: 'key-down-empty',
          at: base,
          kind: TrackedInputEventKind.keyDown,
        ),
        _trackedEvent(
          uid: 'key-up-label',
          at: base.add(const Duration(seconds: 1)),
          kind: TrackedInputEventKind.keyUp,
          keyLabel: 'Esc',
        ),
        _trackedEvent(
          uid: 'key-up-empty',
          at: base.add(const Duration(seconds: 2)),
          kind: TrackedInputEventKind.keyUp,
        ),
        _trackedEvent(
          uid: 'mouse-down',
          at: base.add(const Duration(seconds: 3)),
          kind: TrackedInputEventKind.mouseButtonDown,
          mouseButton: 'left',
        ),
        _trackedEvent(
          uid: 'mouse-up-empty',
          at: base.add(const Duration(seconds: 4)),
          kind: TrackedInputEventKind.mouseButtonUp,
        ),
        _trackedEvent(
          uid: 'mouse-button-empty',
          at: base.add(const Duration(seconds: 5)),
          kind: TrackedInputEventKind.mouseButton,
        ),
        _trackedEvent(
          uid: 'mouse-move',
          at: base.add(const Duration(seconds: 6)),
          kind: TrackedInputEventKind.mouseMove,
          moveDistance: 240,
        ),
      ],
    );
    final fusionRepository = _Gap5ActivityFusionRepository(db);
    final router = GoRouter(
      initialLocation: '/evidence',
      routes: <RouteBase>[
        GoRoute(
          path: '/evidence',
          builder: (context, state) => const Scaffold(
            body: SingleChildScrollView(
              child: TaskTrackerEvidenceSection(taskId: 42),
            ),
          ),
        ),
        GoRoute(
          path: AppRoutes.tracker,
          builder: (context, state) => const Scaffold(body: Text('tracker')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          activityRecordRepositoryProvider.overrideWithValue(recordsRepo),
          inputActivityEventServiceProvider.overrideWithValue(inputService),
          activityFusionRepositoryProvider.overrideWithValue(fusionRepository),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await _pumpFrames(tester);

    expect(find.text('\u6309\u952e\u8f93\u5165'), findsOneWidget);
    expect(find.text('\u6309\u952e\u62ac\u8d77 Esc'), findsOneWidget);
    expect(find.text('\u6309\u952e\u62ac\u8d77'), findsOneWidget);
    expect(find.text('\u9f20\u6807\u6309\u4e0bleft'), findsOneWidget);
    expect(find.text('\u9f20\u6807\u62ac\u8d77\u6309\u952e'), findsOneWidget);
    expect(find.text('\u9f20\u6807\u6309\u952e'), findsOneWidget);
    expect(find.text('\u9f20\u6807\u79fb\u52a8 240px'), findsOneWidget);
  });
}

typedef _Evidence = ({
  DataOperationLogRepository auditRepository,
  OfflineMutationStore mutationStore,
  SyncWriteRecorder recorder,
});

_Evidence _createEvidence(AppDatabase db) {
  final mutationStore = OfflineMutationStore(db);
  final recorder = SyncWriteRecorder(
    mutationStore: mutationStore,
    stateStore: SyncObjectStateStore(db),
  );
  return (
    auditRepository: DataOperationLogRepository(db, recorder),
    mutationStore: mutationStore,
    recorder: recorder,
  );
}

FileTransferService _createTransferService(
  AppDatabase db,
  FileCloudApi api,
) {
  return FileTransferService(
    apiLoader: () async => api,
    operationLogs: DataOperationLogRepository(db),
  );
}

FileTransferJob _transferJob({
  required String localPath,
  required int totalBytes,
}) {
  final now = DateTime.utc(2026, 6, 9, 12);
  return FileTransferJob(
    id: 'gap5-download-job',
    direction: FileTransferDirection.download,
    fileName: 'gap5-download.txt',
    localPath: localPath,
    totalBytes: totalBytes,
    chunkSize: 4,
    expectedChunks: 0,
    transferredBytes: 0,
    status: FileTransferStatus.failed,
    createdAt: now,
    updatedAt: now,
    sessionId: 'download-session-1',
    storageObjectId: 'storage-object-1',
  );
}

Future<List<String>> _auditActions(AppDatabase db) async {
  final rows = await db
      .customSelect(
        'SELECT action FROM data_operation_logs ORDER BY id ASC',
      )
      .get();
  return rows.map<String>((row) => row.read<String>('action')).toList();
}

class _Gap5FileCloudApi implements FileCloudApi {
  _Gap5FileCloudApi({
    this.uploadCompleteChecksum,
    this.uploadCompleteOk = true,
    this.omitUploadSessionId = false,
    this.useDynamicMaps = false,
  });

  final String? uploadCompleteChecksum;
  final bool uploadCompleteOk;
  final bool omitUploadSessionId;
  final bool useDynamicMaps;
  final uploadedChunks = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> createUploadSession({
    required String fileName,
    required int totalBytes,
    String providerKey = 'server_storage',
    int chunkSize = 5 * 1024 * 1024,
    String? checksum,
    String? objectKey,
    String? localPath,
    String? remoteId,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    final session = omitUploadSessionId
        ? <dynamic, dynamic>{}
        : <dynamic, dynamic>{'sessionId': 'upload-session-1'};
    return <String, dynamic>{
      if (omitUploadSessionId)
        'uploadSession': useDynamicMaps
            ? session
            : Map<String, Object?>.from(session)
      else
        'uploadSession':
            useDynamicMaps ? session : Map<String, Object?>.from(session),
    };
  }

  @override
  Future<Map<String, dynamic>> missingUploadChunks(String sessionId) async {
    final session = <dynamic, dynamic>{'receivedBytes': 0};
    return <String, dynamic>{
      'missingChunks': <Object>[0],
      'session': useDynamicMaps ? session : Map<String, Object?>.from(session),
    };
  }

  @override
  Future<Map<String, dynamic>> uploadChunk({
    required String sessionId,
    required int chunkIndex,
    required int startByte,
    required Uint8List bytes,
    String? checksum,
  }) async {
    uploadedChunks.add(<String, Object?>{
      'sessionId': sessionId,
      'chunkIndex': chunkIndex,
      'startByte': startByte,
      'bytes': bytes.toList(growable: false),
      'checksum': checksum,
    });
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> completeUploadSession(String sessionId) async {
    final storage = <dynamic, dynamic>{
      'storageObjectId': 'dynamic-storage-object',
    };
    return <String, dynamic>{
      'ok': uploadCompleteOk,
      if (!uploadCompleteOk) 'reason': 'zero complete denied',
      if (uploadCompleteOk)
        'storageObject':
            useDynamicMaps ? storage : Map<String, Object?>.from(storage),
      if (uploadCompleteChecksum != null) 'checksum': uploadCompleteChecksum,
    };
  }

  @override
  Future<Map<String, dynamic>> transfers({
    String? direction,
    String? status,
    int limit = 100,
    int offset = 0,
  }) async {
    return <String, dynamic>{'transfers': const <Map<String, Object?>>[]};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pumpTimeline(
  WidgetTester tester, {
  required AppDatabase db,
  required Size size,
  DateTime? selectedDate,
  List<TaskItem> tasks = const <TaskItem>[],
  List<CalendarEvent> events = const <CalendarEvent>[],
  List<TaskScheduleSegmentWithTask> segments =
      const <TaskScheduleSegmentWithTask>[],
  List<Override> overrides = const <Override>[],
}) async {
  final router = GoRouter(
    initialLocation: AppRoutes.timeline,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.timeline,
        builder: (context, state) => const TimelineView(),
      ),
      GoRoute(
        path: AppRoutes.eventDetail,
        builder: (context, state) =>
            Text('event ${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: AppRoutes.taskDetail,
        builder: (context, state) => Text('task ${state.pathParameters['id']}'),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: size,
    overrides: <Override>[
      tasksForSelectedDateProvider.overrideWith(
        (ref) => Stream<List<TaskItem>>.value(tasks),
      ),
      eventsForSelectedDateProvider.overrideWith(
        (ref) => Stream<List<CalendarEvent>>.value(events),
      ),
      taskScheduleSegmentsForSelectedDateProvider.overrideWith(
        (ref) => Stream<List<TaskScheduleSegmentWithTask>>.value(segments),
      ),
      activityRecordsForDateProvider.overrideWith(
        (ref) async => const <ActivityRecord>[],
      ),
      taskEventServerFirstStoreProvider.overrideWith(
        (ref) async => FakeTaskEventServerFirstStore(),
      ),
      ...overrides,
    ],
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
  if (selectedDate != null) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(TimelineView)),
    );
    final dynamic notifier = container.read(selectedDateProvider.notifier);
    notifier.setDate(selectedDate);
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 700));
}

TaskItem _task({
  required int id,
  required String summary,
  required DateTime start,
  int taskListId = 1,
}) {
  return TaskItem(
    id: id,
    uid: 'task-$id',
    dtstamp: DateTime(2026, 6, 10),
    summary: summary,
    description: 'Notes for $summary',
    location: 'Desk',
    dtstart: start,
    priority: 0,
    status: 'NEEDS-ACTION',
    percentComplete: 0,
    categories: '[]',
    durationMinutes: 45,
    isSplittable: false,
    priorityLocal: 2,
    isAutoScheduled: true,
    taskListId: taskListId,
    isLocked: false,
    reminderMinutesBefore: 15,
  );
}

CalendarEvent _event({
  required int id,
  required String summary,
  required DateTime start,
  required DateTime end,
  required int calendarId,
}) {
  return CalendarEvent(
    id: id,
    uid: 'event-$id',
    dtstamp: DateTime(2026, 6, 10),
    summary: summary,
    description: 'Notes for $summary',
    dtstart: start,
    dtend: end,
    status: 'CONFIRMED',
    transp: 'OPAQUE',
    source: 'server',
    eventCalendarId: calendarId,
    colorHex: '#6B5EE4',
    isBlock: false,
  );
}

TaskScheduleSegment _segment({
  required int id,
  required int taskId,
  required DateTime start,
  required DateTime end,
}) {
  return TaskScheduleSegment(
    id: id,
    taskId: taskId,
    segmentIndex: 0,
    startAt: start,
    endAt: end,
    source: 'gap5',
    planRunId: 'gap5-plan',
    note: 'gap5',
    createdAt: DateTime(2026, 6, 10),
    updatedAt: DateTime(2026, 6, 10),
  );
}

DateTime _at(DateTime date, int hour, [int minute = 0]) {
  return DateTime(date.year, date.month, date.day, hour, minute);
}

int _visibleHour() {
  return DateTime.now().hour.clamp(2, 20).toInt();
}

class _Gap5ActivityRecordRepository extends ActivityRecordRepository {
  _Gap5ActivityRecordRepository(
    super.db, {
    required this.records,
  });

  final List<ActivityRecord> records;

  @override
  Stream<List<ActivityRecord>> watchByTaskId(int taskId) {
    return Stream<List<ActivityRecord>>.value(records);
  }
}

class _Gap5InputActivityEventService extends InputActivityEventService {
  _Gap5InputActivityEventService(
    super.db, {
    required this.summary,
    required this.recentEvents,
  });

  final InputHeatmapSummary summary;
  final List<TrackedInputEvent> recentEvents;

  @override
  Future<InputHeatmapSummary> buildHeatmapSummaryForTask(int taskId) async {
    return summary;
  }

  @override
  Future<List<TrackedInputEvent>> listRecentEventsForTask(
    int taskId, {
    int limit = 10,
  }) async {
    return recentEvents.take(limit).toList(growable: false);
  }
}

class _Gap5ActivityFusionRepository extends ActivityFusionRepository {
  _Gap5ActivityFusionRepository(super.db);

  @override
  Future<List<TaskWorkLog>> listTaskWorkLogsForTask(
    int taskId, {
    int limit = 200,
    int offset = 0,
  }) async {
    return const <TaskWorkLog>[];
  }
}

ActivityRecord _activityRecord({
  required int id,
  required DateTime start,
}) {
  return ActivityRecord(
    id: id,
    startTime: start,
    endTime: start.add(const Duration(minutes: 30)),
    durationMinutes: 30,
    keyCount: 10,
    mouseClicks: 2,
    mouseMovePx: 50,
    scrollPx: 0,
    manualLabel: 'Gap5 focus',
    processName: 'Code.exe',
    category: 'coding',
    linkedTaskId: 42,
    isAuto: true,
    source: 'gap5',
  );
}

InputHeatmapSummary _inputSummary({required int totalEvents}) {
  final base = DateTime(2026, 6, 9, 9);
  return InputHeatmapSummary(
    query: InputEventQuery(
      start: base,
      end: base.add(const Duration(hours: 1)),
    ),
    totalEventCount: totalEvents,
    activeMinuteCount: 30,
    keyboardEventCount: 3,
    mouseButtonEventCount: 3,
    wheelEventCount: 0,
    mouseMoveEventCount: 1,
    mouseMoveDistance: 240,
    keyCounts: const <int, int>{},
    mouseCounts: const <String, int>{},
    topKeys: const <InputKeyStat>[],
    processIntensities: const <InputProcessIntensity>[],
    hourlyDistribution: List<InputHourDistributionBucket>.generate(
      24,
      (hour) => InputHourDistributionBucket(
        hour: hour,
        totalEvents: hour == 9 ? totalEvents : 0,
        keyEvents: hour == 9 ? 3 : 0,
        mouseButtonEvents: hour == 9 ? 3 : 0,
        wheelEvents: 0,
        mouseMoveEvents: hour == 9 ? 1 : 0,
        moveDistance: hour == 9 ? 240 : 0,
        activeMinutes: hour == 9 ? 30 : 0,
        intensityScore: hour == 9 ? totalEvents : 0,
      ),
    ),
  );
}

TrackedInputEvent _trackedEvent({
  required String uid,
  required DateTime at,
  required TrackedInputEventKind kind,
  String? keyLabel,
  String? mouseButton,
  int moveDistance = 0,
}) {
  return TrackedInputEvent(
    eventUid: uid,
    sequenceId: uid.hashCode.abs(),
    timestamp: at,
    kind: kind,
    keyLabel: keyLabel,
    mouseButton: mouseButton,
    moveDistance: moveDistance,
    processName: 'Code.exe',
    activityLabel: 'Gap5 focus',
  );
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 6]) async {
  for (var i = 0; i < count; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
