import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/features/tracker/data/tracker_repository.dart';
import 'package:flowplanv2/features/tracker/models/activity_insights.dart';
import 'package:flowplanv2/features/tracker/models/activity_log_entry.dart';
import 'package:flowplanv2/features/tracker/models/input_heatmap_summary.dart';
import 'package:flowplanv2/features/tracker/models/work_session.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_page.dart';
import 'package:flowplanv2/features/tracker/services/activity_classifier.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/features/tracker/services/tracking_upload_service.dart';
import 'package:flowplanv2/features/tracker/services/window_sensor.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/tracking_store_test_double.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('overview renders input distance and truncated process labels', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.tracker,
      trackerNotifier: _FakeTrackerServiceNotifier(
        initialState: _runningState(),
      ),
      store: TrackingStoreTestDouble(
        activityDaySummaryResponseBuilder: (_) => _daySummary(),
        inputHeatmapResponseBuilder: (_) => <String, dynamic>{
          'buckets': <Map<String, Object?>>[],
          'processIntensities': <Map<String, Object?>>[
            <String, Object?>{
              'processName': 'VeryLongProcessName.exe',
              'totalEvents': 42,
              'keyEvents': 20,
              'mouseButtonEvents': 10,
              'wheelEvents': 5,
              'mouseMoveEvents': 7,
              'moveDistance': 1400,
              'activeMinutes': 8,
              'intensityScore': 99,
            },
          ],
        },
      ),
      size: const Size(1400, 1100),
    );

    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 12);
    await pumpUntilFound(tester, find.text('0.5米'), maxPumps: 20);

    expect(find.text('0.5米'), findsWidgets);
    expect(find.byType(TrackerPage), findsOneWidget);
    await _disposeTestApp(tester);
  });

  testWidgets('session tiles expose task opening and linked analysis actions', (
    tester,
  ) async {
    final today = _today();
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      store: TrackingStoreTestDouble(
        activityDaySummaryResponseBuilder: (_) => _daySummary(
          records: <Map<String, Object?>>[
            _recordPayload(
              id: 'tile-record',
              start: today.add(const Duration(hours: 9)),
              durationMinutes: 45,
              processName: 'Code.exe',
              title: 'Tile linked work',
              linkedTaskId: 7,
            ),
          ],
          sessions: <Map<String, Object?>>[
            <String, Object?>{
              'startTime':
                  today.add(const Duration(hours: 9)).toIso8601String(),
              'endTime': today
                  .add(const Duration(hours: 9, minutes: 45))
                  .toIso8601String(),
              'label': 'Tile linked work',
              'processName': 'Code.exe',
              'category': 'coding',
              'durationMinutes': 45,
              'keyCount': 24,
              'mouseClicks': 3,
              'mouseMovePx': 320,
              'scrollPx': 640,
              'processNames': <String>['Code.exe'],
              'categories': <String>['coding'],
              'rawRecordCount': 1,
            },
          ],
        ),
      ),
      workSessions: <WorkSession>[
        _workSession(
          start: today.add(const Duration(hours: 9)),
          durationMinutes: 45,
          label: 'Tile linked work',
          linkedTaskId: 7,
        ),
      ],
      tasks: <TaskItem>[
        _task(7, 'Alpha anchored task',
            dtstart: today.add(const Duration(hours: 8))),
        _task(8, 'Beta anchored task',
            dtstart: today.add(const Duration(hours: 12))),
        _task(9, 'Zulu unanchored far'),
        _task(
          10,
          'Omega anchored far',
          due: today.add(const Duration(days: 1048576)),
        ),
      ],
      size: const Size(1400, 1200),
    );

    await pumpUntilFound(tester, find.text('打开任务'), maxPumps: 30);

    await tester.ensureVisible(find.text('打开任务'));
    await tester.tap(find.text('打开任务'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    await _disposeTestApp(tester);
  });

  testWidgets('range analysis covers fallback titles filters and log dates', (
    tester,
  ) async {
    final bucket = _analysisBucket();
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.tracker,
      tasks: <TaskItem>[
        _task(
          4,
          'Alpha anchored far',
          due: bucket.start.add(const Duration(days: 1048576)),
        ),
      ],
      rangeAnalysis: AsyncData(_rangeSnapshot(bucket)),
      selectedAnalysisBucket: bucket,
      size: const Size(1500, 1500),
    );

    await pumpUntilFound(tester, find.text('2026-06-08 全天区间分析'), maxPumps: 20);

    expect(find.text('Window title only'), findsOneWidget);
    expect(find.text('ProcessOnly.exe'), findsWidgets);
    expect(find.textContaining('日期分布：'), findsWidgets);

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _rangeDropdowns().at(1),
      valueFragment: 'coding',
    );
    expect(find.text('Category fallback session'), findsWidgets);

    final taskDropdowns = _rangeDropdowns();
    if (taskDropdowns.evaluate().length > 2) {
      await chooseDropdownMenuItemByValue(
        tester,
        dropdown: taskDropdowns.at(2),
        valueFragment: 'Alpha anchored far',
      );
      expect(find.text('Null record id log'), findsNothing);
      expect(find.text('Linked task log'), findsOneWidget);
    }

    await tester.ensureVisible(find.widgetWithText(OutlinedButton, '清空筛选'));
    await tester.tap(find.widgetWithText(OutlinedButton, '清空筛选'));
    await tester.pump();

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _rangeDropdowns().first,
      valueFragment: 'ProcessOnly.exe',
    );
    expect(
      find.text('该区间仍有 1 条服务端日志预览，可以继续在下方检索明细。'),
      findsOneWidget,
    );
    await _disposeTestApp(tester);
  });
}

Future<void> _pumpTrackerRoute(
  WidgetTester tester, {
  required String initialLocation,
  TrackingStoreTestDouble? store,
  _FakeTrackerServiceNotifier? trackerNotifier,
  List<TaskItem> tasks = const <TaskItem>[],
  List<WorkSession>? workSessions,
  AsyncValue<TrackerRangeAnalysisSnapshot?>? rangeAnalysis,
  ActivityHeatmapBucket? selectedAnalysisBucket,
  Size size = const Size(1400, 1000),
}) async {
  final fakeStore = store ?? TrackingStoreTestDouble();
  final selectedBucketState =
      StateProvider<ActivityHeatmapBucket?>((ref) => selectedAnalysisBucket);

  await pumpAppAt(
    tester,
    initialLocation: initialLocation,
    size: size,
    overrides: <Override>[
      trackerServiceNotifierProvider.overrideWith(
        () => trackerNotifier ?? _FakeTrackerServiceNotifier(),
      ),
      sequenceRecordingProvider.overrideWith((ref) => true),
      trackingServerFirstStoreProvider.overrideWith((ref) async => fakeStore),
      allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
      allEventCalendarsProvider.overrideWith(
        (ref) => Stream.value(const <EventCalendar>[]),
      ),
      allTaskListsProvider.overrideWith(
        (ref) => Stream.value(const <TaskList>[]),
      ),
      activityDaySummaryProvider.overrideWith(
        (ref) => fakeStore.activityDaySummary(date: _today()),
      ),
      workSessionsForDateProvider.overrideWith(
        (ref) => workSessions ?? const <WorkSession>[],
      ),
      inputHeatmapSummaryProvider.overrideWith(
        (ref, query) async => InputHeatmapSummary.empty(query),
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
      trackingUploadServiceProvider.overrideWith(
        (ref) => Future<TrackingUploadService>.error(
          StateError('upload is not used in gap9 coverage'),
        ),
      ),
      if (rangeAnalysis != null) ...[
        trackerHistorySelectedAnalysisBucketProvider.overrideWith(
          (ref) => ref.watch(selectedBucketState),
        ),
        trackerRangeAnalysisProvider.overrideWith((ref) => rangeAnalysis),
      ],
    ],
  );
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 30,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) {
      return;
    }
  }
  expect(condition(), isTrue);
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

Finder _rangeDropdowns() {
  return find.byWidgetPredicate(
    (widget) => widget is DropdownButtonFormField<String?>,
  );
}

Future<void> _disposeTestApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pump(Duration.zero);
  await tester.pump(const Duration(milliseconds: 1));
}

TrackerState _runningState() {
  final now = _today().add(const Duration(hours: 10));
  return TrackerState(
    isRunning: true,
    currentSnapshot: WindowSnapshot(
      processName: 'Code.exe',
      className: 'FlutterWindow',
      windowTitle: 'FlowPlanV2 tests',
      isFullscreen: false,
      timestamp: now,
    ),
    displaySnapshot: WindowSnapshot(
      processName: 'Code.exe',
      className: 'FlutterWindow',
      windowTitle: 'FlowPlanV2 tests',
      isFullscreen: false,
      timestamp: now,
    ),
    displayClassification: const ActivityClassification(
      category: 'coding',
      label: 'Deep work',
      confidence: 0.9,
    ),
    displaySessionStart: _today().add(const Duration(hours: 9)),
    displayTelemetry: InputTelemetry(
      keyCount: 12,
      keyDistribution: const <int, int>{83: 4},
      keySequence: 'Ctrl+S',
      clicks: const MouseClicks(left: 2, right: 1),
      scrollPx: 300,
      mouseMovePx: 2048,
      timestamp: now,
      inputEvents: const <RawInputEvent>[],
    ),
    lastSampleAt: now,
  );
}

ActivityHeatmapBucket _analysisBucket() {
  final start = DateTime(2026, 6, 8);
  return ActivityHeatmapBucket(
    start: start,
    end: start.add(const Duration(days: 1)),
    shortLabel: '06-08',
    longLabel: '2026-06-08 全天',
    completedCount: 3,
    totalMinutes: 45,
  );
}

TrackerRangeAnalysisSnapshot _rangeSnapshot(ActivityHeatmapBucket bucket) {
  final base = bucket.start.add(const Duration(hours: 9));
  final records = <ActivityRecord>[
    _activityRecord(
      id: 4,
      start: base,
      durationMinutes: 20,
      processName: 'Code.exe',
      windowTitle: 'Category fallback session',
      linkedTaskId: 4,
    ),
  ];
  final sessions = <WorkSession>[
    WorkSession(
      startTime: base,
      endTime: base.add(const Duration(minutes: 20)),
      label: 'Category fallback session',
      processName: 'Code.exe',
      category: 'coding',
      records: records,
      durationMinutes: 20,
      keyCount: 10,
      mouseClicks: 2,
      mouseMovePx: 120,
      scrollPx: 0,
      processNames: const <String>[],
      categories: const <String>[],
      interruptionCount: 0,
    ),
  ];
  final logs = <ActivityLogEntry>[
    ActivityLogEntry(
      timestamp: base.add(const Duration(minutes: 1)),
      type: ActivityLogEntryType.sample,
      recordId: 4,
      processName: 'Code.exe',
      windowTitle: 'Window title only',
      category: 'coding',
      label: '',
      durationMinutes: 5,
      keyCount: 8,
    ),
    ActivityLogEntry(
      timestamp: base.add(const Duration(minutes: 2)),
      type: ActivityLogEntryType.sample,
      processName: 'ProcessOnly.exe',
      windowTitle: '',
      category: 'coding',
      durationMinutes: 1,
      keyCount: 1,
    ),
    ActivityLogEntry(
      timestamp: base.add(const Duration(minutes: 3)),
      type: ActivityLogEntryType.sample,
      processName: '',
      windowTitle: '',
      category: 'coding',
      label: '',
      durationMinutes: 1,
      keyCount: 1,
    ),
    ActivityLogEntry(
      timestamp: base.add(const Duration(minutes: 4)),
      type: ActivityLogEntryType.sample,
      recordId: 4,
      processName: 'Code.exe',
      windowTitle: 'Linked task log',
      category: 'coding',
      durationMinutes: 2,
      keyCount: 1,
    ),
    ActivityLogEntry(
      timestamp: base.add(const Duration(minutes: 5)),
      type: ActivityLogEntryType.sample,
      processName: 'Code.exe',
      windowTitle: 'Null record id log',
      category: 'coding',
      durationMinutes: 2,
      keyCount: 1,
    ),
    ActivityLogEntry(
      timestamp: bucket.end.add(const Duration(minutes: 5)),
      type: ActivityLogEntryType.sample,
      recordId: 4,
      processName: 'Code.exe',
      windowTitle: 'Outside selected bucket',
      category: 'coding',
      durationMinutes: 1,
      keyCount: 1,
    ),
    for (var day = 2; day <= 4; day += 1)
      ActivityLogEntry(
        timestamp: bucket.start.add(Duration(days: day, minutes: 5)),
        type: ActivityLogEntryType.sample,
        recordId: 4,
        processName: 'Code.exe',
        windowTitle: 'Later day log $day',
        category: 'coding',
        durationMinutes: 1,
        keyCount: 1,
      ),
  ];
  return TrackerRangeAnalysisSnapshot(
    bucket: bucket,
    records: records,
    logEntries: logs,
    insights: ActivityInsights.fromRecords(records),
    sessions: sessions,
  );
}

WorkSession _workSession({
  required DateTime start,
  required int durationMinutes,
  required String label,
  int? linkedTaskId,
}) {
  final record = _activityRecord(
    id: 7,
    start: start,
    durationMinutes: durationMinutes,
    processName: 'Code.exe',
    windowTitle: label,
    linkedTaskId: linkedTaskId,
  );
  return WorkSession(
    startTime: start,
    endTime: start.add(Duration(minutes: durationMinutes)),
    label: label,
    processName: 'Code.exe',
    category: 'coding',
    records: <ActivityRecord>[record],
    durationMinutes: durationMinutes,
    keyCount: 24,
    mouseClicks: 3,
    mouseMovePx: 320,
    scrollPx: 640,
    processNames: const <String>['Code.exe'],
    categories: const <String>['coding'],
    interruptionCount: 0,
  );
}

ActivityRecord _activityRecord({
  required int id,
  required DateTime start,
  required int durationMinutes,
  required String processName,
  required String windowTitle,
  int? linkedTaskId,
}) {
  return ActivityRecord(
    id: id,
    startTime: start,
    endTime: start.add(Duration(minutes: durationMinutes)),
    durationMinutes: durationMinutes,
    manualLabel: windowTitle,
    processName: processName,
    windowTitle: windowTitle,
    category: 'coding',
    linkedTaskId: linkedTaskId,
    keyCount: 24,
    mouseClicks: 3,
    mouseMovePx: 320,
    scrollPx: 640,
    isAuto: true,
    source: 'tracker-gap9-worker-test',
  );
}

Map<String, dynamic> _daySummary({
  List<Map<String, Object?>> records = const <Map<String, Object?>>[],
  List<Map<String, Object?>> sessions = const <Map<String, Object?>>[],
}) {
  final totalMinutes = records.fold<int>(
    0,
    (total, record) => total + ((record['metricMinutes'] as int?) ?? 0),
  );
  return <String, dynamic>{
    'insights': <String, Object?>{
      'recordCount': records.length,
      'totalMinutes': totalMinutes,
      'focusMinutes': totalMinutes,
      'totalKeys': 24,
      'totalClicks': 3,
      'totalMovePx': 320,
      'totalScrollPx': 640,
      'productiveRecordCount': records.length,
      'sequenceRecordCount': 0,
      'topProcesses': <Map<String, Object?>>[
        <String, Object?>{
          'label': 'Code.exe',
          'minutes': totalMinutes,
          'keys': 24,
          'clicks': 3,
          'movePx': 320,
          'scrollPx': 640,
          'sessions': 1,
        },
      ],
      'topCategories': <Map<String, Object?>>[
        <String, Object?>{
          'label': 'coding',
          'minutes': totalMinutes,
          'sessions': 1,
        },
      ],
    },
    'previewRecords': records,
    'sessions': sessions,
  };
}

Map<String, Object?> _recordPayload({
  required String id,
  required DateTime start,
  required int durationMinutes,
  required String processName,
  required String title,
  int? linkedTaskId,
}) {
  return <String, Object?>{
    'serverId': id,
    'objectType': 'activity_record',
    'occurredAt': start.toIso8601String(),
    'metricMinutes': durationMinutes,
    'payload': <String, Object?>{
      'startTime': start.toIso8601String(),
      'endTime':
          start.add(Duration(minutes: durationMinutes)).toIso8601String(),
      'durationMinutes': durationMinutes,
      'processName': processName,
      'windowTitle': title,
      'manualLabel': title,
      'category': 'coding',
      if (linkedTaskId != null) 'linkedTaskId': linkedTaskId,
      'keyCount': 24,
      'mouseClicks': 3,
      'mouseMovePx': 320,
      'scrollPx': 640,
      'isAuto': true,
    },
  };
}

TaskItem _task(
  int id,
  String summary, {
  DateTime? dtstart,
  DateTime? due,
}) {
  return TaskItem(
    id: id,
    uid: 'task-$id',
    dtstamp: _today(),
    summary: summary,
    dtstart: dtstart,
    due: due,
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

class _FakeTrackerServiceNotifier extends TrackerServiceNotifier {
  _FakeTrackerServiceNotifier({this.initialState = const TrackerState()});

  final TrackerState initialState;

  @override
  TrackerState build() {
    return initialState;
  }

  @override
  void start() {
    state = state.copyWith(isRunning: true);
  }

  @override
  void stop() {
    state = state.copyWith(isRunning: false);
  }

  @override
  Future<void> refreshNow() async {}

  @override
  Future<void> openAndroidUsageAccessSettings() async {}

  @override
  DateTime? get lastAutoUploadAt => null;

  @override
  String? get lastAutoUploadError => null;

  @override
  bool get isAutoUploading => false;
}
