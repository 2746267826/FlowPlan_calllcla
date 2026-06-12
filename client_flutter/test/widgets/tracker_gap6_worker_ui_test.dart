import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/tracker/models/work_session.dart';
import 'package:flowplanv2/features/tracker/presentation/activity_review_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_input_history_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_log_history_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_page.dart';
import 'package:flowplanv2/features/tracker/services/activity_classifier.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flowplanv2/features/tracker/services/tracker_platform_source.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/features/tracker/services/tracking_upload_service.dart';
import 'package:flowplanv2/features/tracker/services/window_sensor.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/tracking_store_test_double.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  tearDown(() {
    debugTrackerPlatformOverride = null;
  });

  testWidgets('Android toolbar opens usage settings and refreshes snapshot', (
    tester,
  ) async {
    debugTrackerPlatformOverride = const TrackerPlatformSource.testing(
      platformLabel: 'Android',
      collectionMode: TrackerCollectionMode.manualUsageStatsImport,
      supportsInputAnalytics: false,
      supportsSequenceRecording: false,
      supportsUsageAccessPermission: true,
      supportsDetailedInputHistory: false,
    );
    final notifier = _FakeTrackerServiceNotifier(
      initialState: const TrackerState(
        isRunning: true,
        hasUsageStatsPermission: false,
      ),
    );

    await _pumpTracker(
      tester,
      trackerNotifier: notifier,
      store: TrackingStoreTestDouble(),
      daySummary: _emptyDaySummary(),
    );
    await _pumpUntilFound(tester, find.byType(TrackerPage));

    await tester.tap(
      find.widgetWithIcon(OutlinedButton, Icons.admin_panel_settings_outlined),
    );
    await tester.pump();
    expect(notifier.openUsageAccessSettingsCalls, 1);

    await _pumpUntil(
      tester,
      () {
        final buttons = tester.widgetList<FilledButton>(
          find.widgetWithIcon(FilledButton, Icons.refresh_outlined),
        );
        return buttons.isNotEmpty && buttons.first.onPressed != null;
      },
      maxPumps: 80,
    );
    await tester.tap(find.widgetWithIcon(FilledButton, Icons.refresh_outlined));
    await _pumpUntil(tester, () => notifier.refreshCalls == 1);
  });

  testWidgets('session details cover cross-day fallback titles and filters', (
    tester,
  ) async {
    final store = TrackingStoreTestDouble(
      activityDaySummaryResponseBuilder: (_) => _gapDaySummary(),
      inputHeatmapResponseBuilder: (_) => _gapInputHeatmap(),
    );

    await _pumpTracker(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      trackerNotifier: _FakeTrackerServiceNotifier(),
      store: store,
      daySummary: _gapDaySummary(),
      workSessions: _gapWorkSessions(),
      tasks: <TaskItem>[
        _task(id: 2, summary: 'Task without anchor'),
        _task(
          id: 3,
          summary: 'Task with anchor',
          dtstart: _day.add(const Duration(hours: 21)),
        ),
      ],
    );
    await _pumpUntilFound(tester, find.text('Overnight focus label'));

    expect(find.text('23:40 - 00:20'), findsOneWidget);
    expect(find.textContaining('LongProcessOne.exe'), findsWidgets);
    expect(find.textContaining('等 4 个应用'), findsWidgets);
    expect(find.textContaining('UntitledWindow.exe'), findsWidgets);
    expect(find.textContaining('misc'), findsWidgets);

    final secondSessionDetails = find.byType(ExpansionTile).last;
    await tester.ensureVisible(secondSessionDetails);
    await tester.pumpAndSettle();
    await tester.tap(secondSessionDetails);
    await tester.pumpAndSettle();
    expect(find.text('Standalone Window Title'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'zz-no-match');
    await tester.pump();
    expect(find.textContaining('当前筛选下没有工作会话'), findsOneWidget);

    await tester.tap(find.text('清空筛选'));
    await tester.pump();
    expect(find.text('Overnight focus label'), findsOneWidget);

    await tester.tap(find.text('关联任务').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('06-09 23:40'), findsWidgets);
    expect(find.text('Task with anchor'), findsOneWidget);
    expect(find.text('Task without anchor'), findsOneWidget);
  });

  testWidgets('history pages cover date picker cancel and fallback rows', (
    tester,
  ) async {
    final logStore = TrackingStoreTestDouble(
      activityRecordsResponseBuilder: (_) => <String, dynamic>{
        'total': 2,
        'items': <Map<String, Object?>>[
          <String, Object?>{
            'serverId': 'fallback-occurred-at',
            'occurredAt': _day.toIso8601String(),
            'metricMinutes': '7',
            'payload': <String, Object?>{
              'processName': 'OnlyProcess.exe',
              'windowTitle': 'OnlyProcess detail window',
              'className': 'OnlyProcessClass',
              'recordId': 202,
              'note': 'server note',
            },
          },
          <String, Object?>{
            'serverId': 'empty-start',
            'payload': <String, Object?>{},
          },
        ],
      },
    );

    final logPage = await _pumpPlainTrackerPage(
      tester,
      store: logStore,
      child: const TrackerLogHistoryPage(),
    );
    await _pumpUntilFound(tester, find.text('OnlyProcess.exe'));
    expect(find.textContaining('01-01'), findsWidgets);
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('OnlyProcess.exe'), findsWidgets);

    await tester.tap(find.byKey(const Key('tracker-log-history-date-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(logStore.activityRecordsCalls.length, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 4);
    await logPage.close();

    final inputStore = TrackingStoreTestDouble(
      inputEventsResponseBuilder: (_) => <String, dynamic>{
        'total': 80,
        'items': <Map<String, Object?>>[
          _inputItem('move', 'mouse_move', processName: 'Mover.exe'),
          _inputItem('wheel', 'mouse_wheel', windowTitle: 'Wheel window'),
          _inputItem('button', 'mouse_button', processName: 'Clicker.exe'),
          _inputItem('empty', 'key_down'),
          for (var index = 0; index < 76; index += 1)
            _inputItem('extra-$index', 'key_down',
                processName: 'Extra$index.exe',
                timestamp: _day.subtract(Duration(minutes: index + 1))),
        ],
      },
    );

    await _pumpPlainTrackerPage(
      tester,
      store: inputStore,
      child: const TrackerInputHistoryPage(),
    );
    await _pumpUntilFound(tester, find.text('Mover.exe'));
    expect(find.text('Wheel window'), findsOneWidget);
    expect(find.text('Clicker.exe'), findsWidgets);
    expect(find.textContaining('未命名事件'), findsWidgets);
    expect(find.textContaining('位移'), findsWidgets);
    expect(find.textContaining('鼠标移动'), findsWidgets);

    await tester.tap(find.byKey(AppKeys.trackerInputHistoryNextPageButton));
    await _pumpUntil(
        tester, () => inputStore.inputEventsCalls.last.offset == 80);
  });

  testWidgets('activity review renders fallback labels and evidence details', (
    tester,
  ) async {
    final store = _ReviewStore(
      items: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'review-fallback',
          'segmentUid': 'review-fallback',
          'startAt': _day.add(const Duration(hours: 8)).toIso8601String(),
          'endAt':
              _day.add(const Duration(hours: 8, minutes: 25)).toIso8601String(),
          'primaryProcessName': 'ReviewProcess.exe',
          'primaryWindowTitle': 'Review window',
          'confidence': '0.64',
          'status': 'candidate',
          'evidence': <Object?, Object?>{
            'activityRecordCount': 2,
            'rawLogCount': 1,
            'inputEventCount': 4,
            'processes': <String>[
              'One.exe',
              'Two.exe',
              'Three.exe',
              'Four.exe'
            ],
          },
        },
      ],
    );

    await pumpAppAt(
      tester,
      initialLocation: AppRoutes.activityReview,
      size: const Size(1000, 900),
      overrides: <Override>[
        trackingServerFirstStoreProvider.overrideWith((ref) async => store),
        allTasksProvider
            .overrideWith((ref) => Stream.value(const <TaskItem>[])),
      ],
    );
    await _pumpUntilFound(tester, find.byType(ActivityReviewPage));
    await _pumpUntilFound(tester, find.text('ReviewProcess.exe'));

    expect(find.textContaining('证据摘要'), findsOneWidget);
    expect(find.textContaining('One.exe'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await _pumpUntilFound(
        tester, find.byKey(AppKeys.trackerReviewConfirmButton));
    final titleField = find.byType(TextField).first;
    expect(
      tester.widget<TextField>(titleField).controller?.text,
      'ReviewProcess.exe',
    );
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(store.confirmedSegments, isEmpty);
  });
}

Future<void> _pumpTracker(
  WidgetTester tester, {
  String initialLocation = AppRoutes.tracker,
  required _FakeTrackerServiceNotifier trackerNotifier,
  required TrackingStoreTestDouble store,
  required Map<String, dynamic> daySummary,
  List<WorkSession> workSessions = const <WorkSession>[],
  List<TaskItem> tasks = const <TaskItem>[],
}) async {
  await pumpAppAt(
    tester,
    initialLocation: initialLocation,
    size: const Size(1400, 1100),
    overrides: <Override>[
      trackerServiceNotifierProvider.overrideWith(() => trackerNotifier),
      sequenceRecordingProvider.overrideWith((ref) => true),
      trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      activityDaySummaryProvider.overrideWith((ref) async => daySummary),
      workSessionsForDateProvider.overrideWith((ref) => workSessions),
      trackingUploadDiagnosticsProvider.overrideWith(
        (ref) async => <String, Object?>{
          'lastActivityRecordId': 0,
          'lastInputEventId': 0,
          'lastRawLogId': 0,
          'pendingActivityRecords': 0,
          'pendingInputEvents': 0,
          'pendingRawLogs': 0,
        },
      ),
      allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
      allEventCalendarsProvider.overrideWith(
        (ref) => Stream.value(const <EventCalendar>[]),
      ),
      allTaskListsProvider.overrideWith(
        (ref) => Stream.value(const <TaskList>[]),
      ),
      trackingUploadServiceProvider.overrideWith(
        (ref) async => const _FakeTrackingUploadService(),
      ),
    ],
  );
}

Future<_PlainTrackerPageHandle> _pumpPlainTrackerPage(
  WidgetTester tester, {
  required TrackingStoreTestDouble store,
  required Widget child,
}) async {
  final db = createTestDatabase();
  final handle = _PlainTrackerPageHandle(db);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 4);
    await handle.close();
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(1200, 900),
    overrides: <Override>[
      trackingServerFirstStoreProvider.overrideWith((ref) async => store),
    ],
    child: MaterialApp(home: child),
  );
  await _pumpFrames(tester);
  return handle;
}

class _PlainTrackerPageHandle {
  _PlainTrackerPageHandle(this._db);

  final AppDatabase _db;
  var _closed = false;

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _db.close();
  }
}

Map<String, dynamic> _emptyDaySummary() {
  return <String, dynamic>{
    'insights': <String, Object?>{
      'recordCount': 0,
      'totalMinutes': 0,
      'focusMinutes': 0,
      'totalKeys': 0,
      'totalClicks': 0,
      'totalMovePx': 0,
      'totalScrollPx': 0,
      'productiveRecordCount': 0,
      'sequenceRecordCount': 0,
      'topProcesses': <Map<String, Object?>>[],
      'topCategories': <Map<String, Object?>>[],
    },
    'previewRecords': <Map<String, Object?>>[],
    'sessions': <Map<String, Object?>>[],
  };
}

Map<String, dynamic> _gapDaySummary() {
  return <String, dynamic>{
    'insights': <String, Object?>{
      'recordCount': 3,
      'totalMinutes': 65,
      'focusMinutes': 40,
      'totalKeys': 30,
      'totalClicks': 2,
      'totalMovePx': 12,
      'totalScrollPx': 18,
      'productiveRecordCount': 2,
      'sequenceRecordCount': 1,
      'topProcesses': <Map<String, Object?>>[],
      'topCategories': <Map<String, Object?>>[],
    },
    'previewRecords': <Map<String, Object?>>[
      _recordPayload(
        id: 101,
        start: _day.subtract(const Duration(minutes: 20)),
        durationMinutes: 40,
        processName: 'LongProcessOne.exe',
        windowTitle: 'Long cross day title',
        category: 'deep',
        manualLabel: 'Overnight record',
        keyCount: 30,
      ),
      _recordPayload(
        id: 102,
        start: _day.add(const Duration(hours: 1)),
        durationMinutes: 5,
        processName: 'UntitledWindow.exe',
        windowTitle: 'Standalone Window Title',
        category: 'misc',
        manualLabel: '',
        keyCount: 0,
        className: 'StandaloneClass',
        note: 'manual note',
      ),
    ],
    'sessions': <Map<String, Object?>>[],
  };
}

List<WorkSession> _gapWorkSessions() {
  final first = _activityRecord(
    id: 101,
    start: _day.subtract(const Duration(minutes: 20)),
    durationMinutes: 40,
    processName: 'LongProcessOne.exe',
    windowTitle: 'Long cross day title',
    category: 'deep',
    manualLabel: 'Overnight record',
    keyCount: 30,
  );
  final second = _activityRecord(
    id: 102,
    start: _day.add(const Duration(hours: 1)),
    durationMinutes: 5,
    processName: '',
    windowTitle: 'Standalone Window Title',
    category: '',
    manualLabel: '',
    keyCount: 0,
    className: 'StandaloneClass',
    note: 'manual note',
  );
  return <WorkSession>[
    WorkSession(
      startTime: _day.subtract(const Duration(minutes: 20)),
      endTime: _day.add(const Duration(minutes: 20)),
      label: 'Overnight focus label',
      processName: 'LongProcessOne.exe',
      category: 'deep',
      records: <ActivityRecord>[first],
      durationMinutes: 40,
      keyCount: 30,
      mouseClicks: 2,
      mouseMovePx: 12,
      scrollPx: 18,
      processNames: const <String>[
        'LongProcessOne.exe',
        'LongProcessTwo.exe',
        'LongProcessThree.exe',
        'LongProcessFour.exe',
      ],
      categories: const <String>['deep'],
      interruptionCount: 0,
    ),
    WorkSession(
      startTime: _day.add(const Duration(hours: 1)),
      endTime: _day.add(const Duration(hours: 1, minutes: 5)),
      label: 'UntitledWindow.exe',
      processName: 'UntitledWindow.exe',
      category: 'misc',
      records: <ActivityRecord>[second],
      durationMinutes: 5,
      keyCount: 0,
      mouseClicks: 0,
      mouseMovePx: 0,
      scrollPx: 0,
      processNames: const <String>['UntitledWindow.exe'],
      categories: const <String>['misc'],
      interruptionCount: 0,
    ),
  ];
}

ActivityRecord _activityRecord({
  required int id,
  required DateTime start,
  required int durationMinutes,
  required String processName,
  required String windowTitle,
  required String category,
  required String manualLabel,
  required int keyCount,
  String? className,
  String? note,
}) {
  return ActivityRecord(
    id: id,
    startTime: start,
    endTime: start.add(Duration(minutes: durationMinutes)),
    durationMinutes: durationMinutes,
    keyCount: keyCount,
    mouseClicks: keyCount > 0 ? 2 : 0,
    mouseMovePx: keyCount > 0 ? 12 : 0,
    scrollPx: keyCount > 0 ? 18 : 0,
    manualLabel: manualLabel,
    processName: processName,
    windowTitle: windowTitle,
    category: category,
    isAuto: true,
    source: 'gap6-widget-test',
  );
}

Map<String, Object?> _recordPayload({
  required int id,
  required DateTime start,
  required int durationMinutes,
  required String processName,
  required String windowTitle,
  required String category,
  required String manualLabel,
  required int keyCount,
  String? className,
  String? note,
}) {
  return <String, Object?>{
    'serverId': 'record-$id',
    'objectType': 'activity_record',
    'occurredAt': start.toIso8601String(),
    'metricMinutes': durationMinutes,
    'payload': <String, Object?>{
      'startTime': start.toIso8601String(),
      'endTime':
          start.add(Duration(minutes: durationMinutes)).toIso8601String(),
      'durationMinutes': durationMinutes,
      'processName': processName,
      'windowTitle': windowTitle,
      'category': category,
      'manualLabel': manualLabel,
      'keyCount': keyCount,
      'mouseClicks': keyCount > 0 ? 2 : 0,
      'mouseMovePx': keyCount > 0 ? 12 : 0,
      'scrollPx': keyCount > 0 ? 18 : 0,
      if (className != null) 'className': className,
      if (note != null) 'note': note,
      'isAuto': true,
    },
  };
}

Map<String, dynamic> _gapInputHeatmap() {
  return <String, dynamic>{
    'buckets': <Map<String, Object?>>[
      <String, Object?>{
        'bucketStart': _day.toIso8601String(),
        'eventCount': 30,
        'keyboardEventCount': 20,
        'mouseButtonEventCount': 2,
        'wheelEventCount': 3,
        'mouseMoveEventCount': 5,
        'mouseMoveDistance': 120,
      },
    ],
  };
}

Map<String, Object?> _inputItem(
  String id,
  String kind, {
  String? processName,
  String? windowTitle,
  DateTime? timestamp,
}) {
  final eventTime = timestamp ?? _day;
  return <String, Object?>{
    'serverId': id,
    'objectType': 'tracked_input_event',
    'occurredAt': eventTime.toIso8601String(),
    'payload': <String, Object?>{
      'eventUid': id,
      'sequenceId': 10,
      'timestamp': eventTime.toIso8601String(),
      'kind': kind,
      if (processName != null) 'processName': processName,
      if (windowTitle != null) 'windowTitle': windowTitle,
      if (kind == 'mouse_move') ...<String, Object?>{
        'deltaX': 7,
        'deltaY': -2,
        'moveDistance': 9,
      },
      if (kind == 'mouse_wheel') 'wheelDelta': -120,
      if (kind == 'mouse_button') 'mouseButton': 'left',
    },
  };
}

TaskItem _task({
  required int id,
  required String summary,
  DateTime? dtstart,
}) {
  return TaskItem(
    id: id,
    uid: 'task-$id',
    dtstamp: _day,
    dtstart: dtstart,
    summary: summary,
    priority: 0,
    status: 'NEEDS-ACTION',
    percentComplete: 0,
    categories: '',
    durationMinutes: 0,
    isSplittable: false,
    priorityLocal: 0,
    isAutoScheduled: false,
    isLocked: false,
    reminderMinutesBefore: 0,
  );
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 40,
}) async {
  await _pumpUntil(
    tester,
    () => finder.evaluate().isNotEmpty,
    maxPumps: maxPumps,
  );
  expect(finder, findsWidgets);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 40,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) {
      return;
    }
  }
  expect(condition(), isTrue);
}

class _FakeTrackerServiceNotifier extends TrackerServiceNotifier {
  _FakeTrackerServiceNotifier({
    TrackerState? initialState,
  }) : initialState = initialState ?? _runningState();

  final TrackerState initialState;
  var refreshCalls = 0;
  var openUsageAccessSettingsCalls = 0;

  @override
  TrackerState build() {
    return initialState;
  }

  @override
  Future<void> refreshNow() async {
    refreshCalls += 1;
    state = state.copyWith(hasUsageStatsPermission: true);
  }

  @override
  Future<void> openAndroidUsageAccessSettings() async {
    openUsageAccessSettingsCalls += 1;
  }

  @override
  DateTime? get lastAutoUploadAt => null;

  @override
  String? get lastAutoUploadError => null;

  @override
  bool get isAutoUploading => false;
}

TrackerState _runningState() {
  return TrackerState(
    isRunning: true,
    currentSnapshot: WindowSnapshot(
      processName: 'Code.exe',
      className: 'FlutterWindow',
      windowTitle: 'FlowPlanV2 tests',
      isFullscreen: false,
      timestamp: _day,
    ),
    displaySnapshot: WindowSnapshot(
      processName: 'Code.exe',
      className: 'FlutterWindow',
      windowTitle: 'FlowPlanV2 tests',
      isFullscreen: false,
      timestamp: _day,
    ),
    displayClassification: const ActivityClassification(
      category: 'coding',
      label: 'Deep work',
      confidence: 0.95,
    ),
    displaySessionStart: _day.subtract(const Duration(minutes: 20)),
    displayTelemetry: InputTelemetry(
      keyCount: 12,
      keyDistribution: const <int, int>{65: 12},
      keySequence: 'A',
      clicks: const MouseClicks(left: 1),
      scrollPx: 10,
      mouseMovePx: 20,
      timestamp: _day,
      inputEvents: const <RawInputEvent>[],
    ),
    lastSampleAt: _day,
  );
}

class _FakeTrackingUploadService implements TrackingUploadService {
  const _FakeTrackingUploadService();

  @override
  Future<TrackingUploadResult> uploadPending({
    int limitPerKind = 2000,
    int chunkSize = 200,
  }) async {
    return const TrackingUploadResult(
      uploadedBatches: 0,
      uploadedRecords: 0,
      details: <Map<String, Object?>>[],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReviewStore extends FakeTrackingServerFirstStore {
  _ReviewStore({required this.items});

  final List<Map<String, Object?>> items;

  @override
  Future<Map<String, dynamic>> segments({
    DateTime? startAt,
    DateTime? endAt,
    String? status,
    int limit = 100,
    int offset = 0,
  }) async {
    return <String, dynamic>{'items': items};
  }
}

final _day = DateTime(2026, 6, 10);
