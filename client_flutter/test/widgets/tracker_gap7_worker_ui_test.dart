import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/server_first/tracking_server_first_store.dart';
import 'package:flowplanv2/features/tracker/data/tracker_repository.dart';
import 'package:flowplanv2/features/tracker/models/work_session.dart';
import 'package:flowplanv2/features/tracker/presentation/activity_review_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_log_history_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_page.dart';
import 'package:flowplanv2/features/tracker/services/activity_classifier.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flowplanv2/features/tracker/services/tracker_platform_source.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/features/tracker/services/tracking_upload_service.dart';
import 'package:flowplanv2/features/tracker/services/window_sensor.dart';
import 'package:flowplanv2/features/tracker/widgets/heatmap_widget.dart';
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

  testWidgets('Android permission panel opens settings and refreshes after grant',
      (tester) async {
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

    await _pumpTrackerShell(
      tester,
      trackerNotifier: notifier,
      daySummary: _emptyDaySummary(),
      store: TrackingStoreTestDouble(),
      size: const Size(1400, 1200),
    );
    await _pumpUntilFound(tester, find.byType(TrackerPage));

    final openSettingsButton =
        find.widgetWithIcon(FilledButton, Icons.open_in_new);
    await tester.ensureVisible(openSettingsButton);
    await tester.tap(openSettingsButton);
    await tester.pump();
    expect(notifier.openUsageAccessSettingsCalls, 1);

    final refreshButton =
        find.widgetWithIcon(OutlinedButton, Icons.refresh_outlined);
    await tester.ensureVisible(refreshButton);
    await tester.tap(refreshButton);
    await _pumpUntil(tester, () => notifier.refreshCalls == 1);
  });

  testWidgets('current session shows Android input fallback when telemetry hidden',
      (tester) async {
    debugTrackerPlatformOverride = const TrackerPlatformSource.testing(
      platformLabel: 'Android',
      collectionMode: TrackerCollectionMode.manualUsageStatsImport,
      supportsInputAnalytics: false,
      supportsSequenceRecording: false,
      supportsUsageAccessPermission: false,
      supportsDetailedInputHistory: false,
    );

    await _pumpTrackerShell(
      tester,
      trackerNotifier: _FakeTrackerServiceNotifier(
        initialState: _runningState(mouseMovePx: 1200),
      ),
      daySummary: _emptyDaySummary(),
      store: TrackingStoreTestDouble(),
      size: const Size(1400, 1000),
    );
    await _pumpUntilFound(tester, find.byType(TrackerPage));

    expect(find.textContaining('只记录应用前台会话'), findsOneWidget);
  });

  testWidgets('day details filters clear linked heatmap state and show counts',
      (tester) async {
    final bucket = ActivityHeatmapBucket(
      start: _day.add(const Duration(hours: 9)),
      end: _day.add(const Duration(hours: 10)),
      shortLabel: '09:00',
      longLabel: '2026-06-10 09:00',
      completedCount: 1,
      totalMinutes: 20,
    );

    await _pumpTrackerShell(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      trackerNotifier: _FakeTrackerServiceNotifier(),
      daySummary: _daySummaryWithRecords(),
      store: TrackingStoreTestDouble(),
      workSessions: <WorkSession>[
        _session(
          label: 'Filtered coding block',
          processName: 'Code.exe',
          category: 'coding',
          keyCount: 12,
        ),
      ],
      overrides: <Override>[
        trackerHistorySelectedHeatmapBucketProvider.overrideWith(
          (ref) => bucket,
        ),
      ],
      size: const Size(1400, 1000),
    );
    await _pumpUntilFound(tester, find.text('Filtered coding block'));

    expect(find.textContaining('热力图区间'), findsOneWidget);
    expect(find.textContaining('1/1'), findsWidgets);

    await tester.tap(find.widgetWithText(TextButton, '取消联动'));
    await tester.pump();
    expect(find.textContaining('热力图区间'), findsNothing);
  });

  testWidgets('log history accepts a picked date and resets pagination',
      (tester) async {
    final store = TrackingStoreTestDouble(
      activityRecordsResponseBuilder: (_) => <String, dynamic>{
        'total': 60,
        'items': <Map<String, Object?>>[
          for (var index = 0; index < 50; index += 1)
            _recordPayload(
              id: 1000 + index,
              start: DateTime(2026, 6, 10, 9).add(Duration(minutes: index)),
              durationMinutes: 1,
              processName: 'LogPicker.exe',
              windowTitle: 'Picked date row $index',
              category: 'review',
              manualLabel: 'Picked date row $index',
              keyCount: 1,
            ),
        ],
      },
    );

    await _pumpPlainTrackerPage(
      tester,
      store: store,
      child: const TrackerLogHistoryPage(),
    );
    await _pumpUntilFound(tester, find.text('Picked date row 49'));

    await tester.tap(find.byKey(const Key('tracker-log-history-date-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1').last);
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await _pumpUntil(
      tester,
      () => store.activityRecordsCalls.length >= 2 &&
          store.activityRecordsCalls.last.offset == 0,
      maxPumps: 60,
    );
  });

  testWidgets('activity review falls back through category, process and map evidence',
      (tester) async {
    final store = _ReviewStore(
      items: <Map<String, Object?>>[
        <String, Object?>{
          'id': 'category-only',
          'segmentUid': 'category-only',
          'startAt': _day.add(const Duration(hours: 8)).toIso8601String(),
          'endAt': _day.add(const Duration(hours: 8, minutes: 10)).toIso8601String(),
          'category': 'category fallback title',
          'confidence': 0.7,
          'status': 'candidate',
          'evidence': <String, Object?>{
            'evidence': <Object?, Object?>{
              'activityRecordCount': 2,
              'rawLogCount': 1,
              'inputEventCount': 3,
            },
          },
        },
        <String, Object?>{
          'id': 'process-only',
          'segmentUid': 'process-only',
          'startAt': _day.add(const Duration(hours: 9)).toIso8601String(),
          'endAt': _day.add(const Duration(hours: 9, minutes: 10)).toIso8601String(),
          'primaryProcessName': 'ProcessFallback.exe',
          'confidence': 0.6,
          'status': 'candidate',
          'evidence': '{"evidence":{"activityRecordCount":1}}',
        },
      ],
    );

    await _pumpReviewPage(tester, store: store);
    expect(find.text('ProcessFallback.exe'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(FilledButton, Icons.check_circle_outline).first);
    await tester.pumpAndSettle();
    expect(find.textContaining('ProcessFallback.exe'), findsWidgets);
  });

  testWidgets('heatmap updates selection when series shape changes and uses compact labels',
      (tester) async {
    final first = _heatmapSeries(
      <ActivityHeatmapBucket>[
        _bucket('D1', totalMinutes: 3, completedCount: 1),
      ],
      anchorDate: _day,
    );
    final secondBucket = _bucket('D2', totalMinutes: 12, completedCount: 2);
    final second = _heatmapSeries(
      <ActivityHeatmapBucket>[secondBucket, _bucket('D3')],
      anchorDate: _day.add(const Duration(days: 1)),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 130,
              child: _HeatmapHarness(series: first),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('3'), findsWidgets);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 130,
              child: _HeatmapHarness(series: second),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('12'), findsWidgets);
    expect(find.textContaining('2'), findsWidgets);
    expect(find.text('D2 long'), findsOneWidget);
  });

}

class _HeatmapHarness extends StatefulWidget {
  const _HeatmapHarness({required this.series});

  final ActivityHeatmapSeries series;

  @override
  State<_HeatmapHarness> createState() => _HeatmapHarnessState();
}

class _HeatmapHarnessState extends State<_HeatmapHarness> {
  @override
  Widget build(BuildContext context) {
    return HeatmapWidget(
      series: widget.series,
      selectedScaleOverride: null,
      activeFilterBucket: null,
      activeAnalysisBucket: null,
      onScaleChanged: (_) {},
      onFilterBucket: (_) {},
      onAnalyzeBucket: (_) {},
      onDrillDownBucket: (_) {},
      onClearBucketFilter: () {},
      onClearAnalysisBucket: () {},
    );
  }
}

Future<void> _pumpTrackerShell(
  WidgetTester tester, {
  String initialLocation = AppRoutes.tracker,
  required _FakeTrackerServiceNotifier trackerNotifier,
  required TrackingStoreTestDouble store,
  required Map<String, dynamic> daySummary,
  List<WorkSession> workSessions = const <WorkSession>[],
  List<Override> overrides = const <Override>[],
  Size size = const Size(1200, 900),
}) async {
  await pumpAppAt(
    tester,
    initialLocation: initialLocation,
    size: size,
    overrides: <Override>[
      trackerServiceNotifierProvider.overrideWith(() => trackerNotifier),
      sequenceRecordingProvider.overrideWith((ref) => true),
      trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      activityDaySummaryProvider.overrideWith((ref) async => daySummary),
      workSessionsForDateProvider.overrideWith((ref) => workSessions),
      trackerHistoryFilterOptionsProvider.overrideWith(
        (ref) => const TrackerHistoryFilterOptions(
          processOptions: <String>['Code.exe'],
          categoryOptions: <String>['coding'],
        ),
      ),
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
      allTasksProvider.overrideWith((ref) => Stream.value(<TaskItem>[
            _task(7, 'Linked task'),
          ])),
      allEventCalendarsProvider.overrideWith(
        (ref) => Stream.value(const <EventCalendar>[]),
      ),
      allTaskListsProvider.overrideWith(
        (ref) => Stream.value(const <TaskList>[]),
      ),
      trackingUploadServiceProvider.overrideWith(
        (ref) async => const _FakeTrackingUploadService(),
      ),
      ...overrides,
    ],
  );
}

Future<void> _pumpPlainTrackerPage(
  WidgetTester tester, {
  required TrackingStoreTestDouble store,
  required Widget child,
}) async {
  final db = createTestDatabase();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 4);
    await db.close();
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
}

Future<void> _pumpReviewPage(
  WidgetTester tester, {
  required _ReviewStore store,
}) async {
  final db = createTestDatabase();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 4);
    await db.close();
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: const Size(1100, 900),
    overrides: <Override>[
      trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      allTasksProvider.overrideWith((ref) => Stream.value(const <TaskItem>[])),
    ],
    child: const MaterialApp(home: ActivityReviewPage()),
  );
  await _pumpFrames(tester);
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

Map<String, dynamic> _daySummaryWithRecords() {
  return <String, dynamic>{
    'insights': <String, Object?>{
      'recordCount': 1,
      'totalMinutes': 20,
      'focusMinutes': 20,
      'totalKeys': 12,
      'totalClicks': 1,
      'totalMovePx': 10,
      'totalScrollPx': 0,
      'productiveRecordCount': 1,
      'sequenceRecordCount': 0,
      'topProcesses': <Map<String, Object?>>[],
      'topCategories': <Map<String, Object?>>[],
    },
    'previewRecords': <Map<String, Object?>>[
      _recordPayload(
        id: 1,
        start: _day.add(const Duration(hours: 9)),
        durationMinutes: 20,
        processName: 'Code.exe',
        windowTitle: 'Window',
        category: 'coding',
        manualLabel: 'Filtered coding block',
        keyCount: 12,
      ),
    ],
    'sessions': <Map<String, Object?>>[],
  };
}

WorkSession _session({
  required String label,
  required String processName,
  required String category,
  required int keyCount,
}) {
  final record = _activityRecord(
    id: 1,
    start: _day.add(const Duration(hours: 9)),
    durationMinutes: 20,
    processName: processName,
    windowTitle: 'Window',
    category: category,
    manualLabel: label,
    keyCount: keyCount,
  );
  return WorkSession(
    startTime: record.startTime,
    endTime: record.endTime!,
    label: label,
    processName: processName,
    category: category,
    records: <ActivityRecord>[record],
    durationMinutes: 20,
    keyCount: keyCount,
    mouseClicks: 1,
    mouseMovePx: 10,
    scrollPx: 0,
    processNames: <String>[processName],
    categories: <String>[category],
    interruptionCount: 0,
  );
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
  int? linkedTaskId,
}) {
  return ActivityRecord(
    id: id,
    startTime: start,
    endTime: start.add(Duration(minutes: durationMinutes)),
    durationMinutes: durationMinutes,
    keyCount: keyCount,
    mouseClicks: keyCount > 0 ? 1 : 0,
    mouseMovePx: keyCount > 0 ? 10 : 0,
    scrollPx: 0,
    manualLabel: manualLabel,
    processName: processName,
    windowTitle: windowTitle,
    category: category,
    linkedTaskId: linkedTaskId,
    isAuto: true,
    source: 'gap7-widget-test',
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
}) {
  return <String, Object?>{
    'serverId': 'record-$id',
    'objectType': 'activity_record',
    'occurredAt': start.toIso8601String(),
    'metricMinutes': durationMinutes,
    'payload': <String, Object?>{
      'startTime': start.toIso8601String(),
      'endTime': start.add(Duration(minutes: durationMinutes)).toIso8601String(),
      'durationMinutes': durationMinutes,
      'processName': processName,
      'windowTitle': windowTitle,
      'category': category,
      'manualLabel': manualLabel,
      'keyCount': keyCount,
      'mouseClicks': keyCount > 0 ? 1 : 0,
      'mouseMovePx': keyCount > 0 ? 10 : 0,
      'scrollPx': 0,
      'isAuto': true,
    },
  };
}

ActivityHeatmapBucket _bucket(
  String label, {
  int totalMinutes = 0,
  int completedCount = 0,
}) {
  return ActivityHeatmapBucket(
    start: _day,
    end: _day.add(const Duration(hours: 1)),
    shortLabel: label,
    longLabel: '$label long',
    completedCount: completedCount,
    totalMinutes: totalMinutes,
  );
}

ActivityHeatmapSeries _heatmapSeries(
  List<ActivityHeatmapBucket> buckets, {
  required DateTime anchorDate,
}) {
  return ActivityHeatmapSeries(
    scale: ActivityHeatmapScale.day,
    anchorDate: anchorDate,
    title: 'Gap7 density',
    subtitle: 'Gap7 range',
    buckets: buckets,
    maxMinutes: 20,
    historySummary: ActivityHistorySummary(
      firstRecordAt: anchorDate,
      lastRecordAt: anchorDate,
      totalRecords: 1,
    ),
  );
}

TaskItem _task(int id, String summary) {
  return TaskItem(
    id: id,
    uid: 'task-$id',
    dtstamp: _day,
    dtstart: _day,
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
  for (var index = 0; index < count; index += 1) {
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
  for (var index = 0; index < maxPumps; index += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) {
      return;
    }
  }
  expect(condition(), isTrue);
}

class _FakeTrackerServiceNotifier extends TrackerServiceNotifier {
  _FakeTrackerServiceNotifier({TrackerState? initialState})
      : initialState = initialState ?? _runningState();

  final TrackerState initialState;
  var refreshCalls = 0;
  var openUsageAccessSettingsCalls = 0;

  @override
  TrackerState build() => initialState;

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

TrackerState _runningState({int mouseMovePx = 20}) {
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
      mouseMovePx: mouseMovePx,
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

class _ReviewStore implements TrackingServerFirstStore {
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

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _day = DateTime(2026, 6, 10);
