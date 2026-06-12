import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/server_first/tracking_server_first_store.dart';
import 'package:flowplanv2/features/tracker/data/tracker_repository.dart';
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

import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('tracker helper formatting and status mapping render on overview',
      (
    tester,
  ) async {
    final notifier = _FakeTrackerServiceNotifier(
      initialState: _runningState(
        isViewingExcludedApp: true,
        displaySessionStart: _day.add(const Duration(hours: 9)),
        lastSampleAt: _day.add(const Duration(hours: 10, minutes: 15)),
      ),
    );

    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.tracker,
      trackerNotifier: notifier,
      store: _FakeTrackingStore(
        daySummary: _richDaySummary(),
        inputHeatmap: _inputHeatmapResponse(),
      ),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 12);
    await pumpUntilFound(tester, find.textContaining('冻结查看'), maxPumps: 20);
    await pumpUntilFound(tester, find.text('记录时长'), maxPumps: 20);

    expect(find.textContaining('冻结查看'), findsOneWidget);
    expect(find.text('Deep work · FlowPlanV2 tests'), findsOneWidget);
    expect(find.text('编程 · Code.exe'), findsOneWidget);
    expect(find.text('开始时间：09:00'), findsOneWidget);
    expect(find.text('已记录时长：1 小时 15 分钟'), findsOneWidget);
    expect(find.text('记录时长'), findsOneWidget);
    expect(find.text('2 小时 5 分钟'), findsOneWidget);
    expect(find.text('有效输入时长'), findsOneWidget);
    expect(find.text('1 小时'), findsOneWidget);
    expect(find.text('输入事件'), findsOneWidget);
    expect(find.text('400'), findsOneWidget);
    expect(find.textContaining('峰值时'), findsOneWidget);
    expect(find.textContaining('320 条事'), findsOneWidget);
    expect(find.text('09:00'), findsWidgets);
    expect(find.text('主力应用'), findsOneWidget);
    expect(find.text('Code.exe'), findsWidgets);
    expect(find.text('最近按键序列：Ctrl+S <回车> Enter'), findsOneWidget);
  });

  testWidgets('tracker overview renders empty and error helper states', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.tracker,
      trackerNotifier: _FakeTrackerServiceNotifier(
        initialState: const TrackerState(isRunning: true),
      ),
      store: _FakeTrackingStore(
        daySummary: _emptyDaySummary(),
        inputHeatmapError: StateError('input heatmap unavailable'),
      ),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 12);
    await pumpUntilFound(tester, find.text('等待采集'), maxPumps: 20);

    expect(find.text('等待采集'), findsOneWidget);
    expect(find.text('还没有捕获到外部工作会话'), findsOneWidget);
    expect(find.text('记录时长'), findsOneWidget);
    expect(find.text('0 分钟'), findsWidgets);
    expect(
      find.textContaining('读取输入行为分析失败：Bad state: input heatmap unavailable'),
      findsOneWidget,
    );
  });

  testWidgets('current session title falls back to window process and unnamed',
      (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.tracker,
      trackerNotifier: _FakeTrackerServiceNotifier(
        initialState: _currentSnapshotState(
          processName: 'ServerApp.exe',
          windowTitle: 'Server supplied window',
        ),
      ),
    );
    await pumpUntilFound(tester, find.text('Server supplied window'),
        maxPumps: 20);
    expectCurrentSessionTitle('Server supplied window');

    await _resetTrackerHarness(tester);
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.tracker,
      trackerNotifier: _FakeTrackerServiceNotifier(
        initialState: _currentSnapshotState(
          processName: 'FallbackProcess.exe',
          windowTitle: '   ',
        ),
      ),
    );
    await pumpUntilFound(tester, find.text('FallbackProcess.exe'),
        maxPumps: 20);
    expectCurrentSessionTitle('FallbackProcess.exe');

    await _resetTrackerHarness(tester);
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.tracker,
      trackerNotifier: _FakeTrackerServiceNotifier(
        initialState: _currentSnapshotState(
          processName: '   ',
          windowTitle: '   ',
        ),
      ),
    );
    await pumpUntilFound(tester, find.text('\u672a\u547d\u540d\u7a97\u53e3'),
        maxPumps: 20);
    expectCurrentSessionTitle('\u672a\u547d\u540d\u7a97\u53e3');
  });

  testWidgets('input behavior truncates long leading process labels', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.tracker,
      trackerNotifier: _FakeTrackerServiceNotifier(
        initialState: _runningState(),
      ),
      store: _FakeTrackingStore(
        daySummary: _richDaySummary(),
        inputHeatmap: _inputHeatmapResponse(
          leadingProcessName: 'ExtremelyLongProcessName.exe',
        ),
      ),
    );
    await pumpUntilFound(tester, find.text('ExtremelyL...'), maxPumps: 20);

    expect(find.text('ExtremelyL...'), findsOneWidget);
    expect(find.text('ExtremelyLongProcessName.exe'), findsWidgets);
  });

  testWidgets('input behavior panel applies and clears linked filters', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.tracker,
      trackerNotifier: _FakeTrackerServiceNotifier(
        initialState: _runningState(),
      ),
      store: _FakeTrackingStore(
        daySummary: _richDaySummary(),
        inputHeatmap: _inputHeatmapResponse(),
      ),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 12);
    await pumpUntilFound(tester, find.textContaining('应用内输入强'), maxPumps: 20);

    final codeProcessInRow = find.descendant(
      of: find.byType(InkWell),
      matching: find.text('Code.exe'),
    );
    expect(codeProcessInRow, findsWidgets);
    await tester.ensureVisible(codeProcessInRow.first);
    await tester.tap(codeProcessInRow.first);
    await tester.pumpAndSettle();

    expect(find.text('联动应用：Code.exe'), findsWidgets);
    expect(find.textContaining('已联'), findsOneWidget);
    expect(find.text('清除联动'), findsOneWidget);

    await tester.ensureVisible(find.text('清除联动'));
    await tester.tap(find.text('清除联动'));
    await tester.pumpAndSettle();
    expect(find.text('联动应用：Code.exe'), findsNothing);

    final hourChip = find.descendant(
      of: find.byType(ActionChip),
      matching: find.textContaining('09:00'),
    );
    expect(hourChip, findsWidgets);
    await tester.ensureVisible(hourChip.first);
    await tester.tap(hourChip.first);
    await tester.pumpAndSettle();

    expect(find.textContaining('联动时段'), findsWidgets);
    expect(find.text('清除联动'), findsOneWidget);

    await tester.ensureVisible(find.text('清除联动'));
    await tester.tap(find.text('清除联动'));
    await tester.pumpAndSettle();
    expect(find.text('联动时段�?9:00'), findsNothing);
  });

  testWidgets('day details category fallback keeps legacy session category', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      selectedCategory: 'legacy-cat',
      store: _FakeTrackingStore(daySummary: _richDaySummary()),
      workSessions: <WorkSession>[
        _sessionForFilters(
          label: 'Legacy category session',
          processName: 'Legacy.exe',
          category: 'legacy-cat',
          categories: const <String>[],
        ),
        _sessionForFilters(
          label: 'Other category session',
          processName: 'Other.exe',
          category: 'other-cat',
          categories: const <String>[],
          startOffset: const Duration(hours: 13),
        ),
      ],
    );
    await pumpUntilFound(tester, find.text('Legacy category session'),
        maxPumps: 20);

    expect(find.text('Legacy category session'), findsOneWidget);
    expect(find.text('Other category session'), findsNothing);
  });

  testWidgets('day details task filter keeps matching linked sessions', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      selectedTaskId: 7,
      store: _FakeTrackingStore(daySummary: _richDaySummary()),
      tasks: <TaskItem>[_task(id: 7, summary: 'Ship tracker coverage')],
    );
    await pumpUntilFound(
      tester,
      find.text('Tracker coverage focus with an intentionally long label'),
      maxPumps: 20,
    );

    expect(find.text('Tracker coverage focus with an intentionally long label'),
        findsOneWidget);
    expect(find.text('Passive notes review'), findsNothing);

    await _resetTrackerHarness(tester);
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      selectedTaskId: 404,
      store: _FakeTrackingStore(daySummary: _richDaySummary()),
      tasks: <TaskItem>[
        _task(id: 7, summary: 'Ship tracker coverage'),
        _task(id: 404, summary: 'Missing linked task'),
      ],
    );
    await pumpUntilFound(
      tester,
      find.textContaining('当前筛选下没有工作会话'),
      maxPumps: 20,
    );

    expect(find.text('Tracker coverage focus with an intentionally long label'),
        findsNothing);
    expect(find.text('Passive notes review'), findsNothing);
  });

  testWidgets('day details heatmap bucket keeps overlapping sessions only', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      selectedHeatmapBucket: _hourBucket(9),
      store: _FakeTrackingStore(daySummary: _richDaySummary()),
    );
    await pumpUntilFound(
      tester,
      find.text('Tracker coverage focus with an intentionally long label'),
      maxPumps: 20,
    );

    expect(find.text('Tracker coverage focus with an intentionally long label'),
        findsOneWidget);
    expect(find.text('Passive notes review'), findsNothing);
  });

  testWidgets('day details renders server and upload diagnostic errors', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      daySummaryError: StateError('summary unavailable'),
      uploadDiagnosticsError: StateError('diagnostics unavailable'),
    );
    await pumpUntilFound(
      tester,
      find.byType(TrackerDayDetailsPage),
      maxPumps: 20,
    );

    expect(find.textContaining('summary unavailable'), findsOneWidget);
    expect(find.textContaining('diagnostics unavailable'), findsOneWidget);
  });

  testWidgets('day details renders pending upload diagnostics and last error', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      store: _FakeTrackingStore(daySummary: _richDaySummary()),
      uploadDiagnostics: <String, Object?>{
        'lastActivityRecordId': 41,
        'lastInputEventId': 82,
        'lastRawLogId': 123,
        'pendingActivityRecords': 2,
        'pendingInputEvents': 3,
        'pendingRawLogs': 1,
        'lastCompletedAt': '2026-06-10 09:30',
        'lastError': 'network timeout',
      },
    );
    await pumpUntilFound(
      tester,
      find.byType(TrackerDayDetailsPage),
      maxPumps: 20,
    );
    await pumpUntilFound(tester, find.textContaining('上传缓冲状'), maxPumps: 20);

    expect(find.textContaining('待上传活动记'), findsOneWidget);
    expect(find.textContaining('待上传输入事'), findsOneWidget);
    expect(find.textContaining('待上传原始日'), findsOneWidget);
    expect(find.text('总计 6 条待上传'), findsOneWidget);
    expect(find.textContaining('上次上传：2026-06-10 09:30'), findsOneWidget);
    expect(find.text('上次上传错误：network timeout'), findsOneWidget);
  });

  testWidgets(
      'session tiles render long text, links, tasks, and expansion rows', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      store: _FakeTrackingStore(daySummary: _richDaySummary()),
      tasks: <TaskItem>[_task(id: 7, summary: 'Ship tracker coverage')],
    );
    await pumpUntilFound(tester, find.text('工作会话'), maxPumps: 20);

    expect(find.text('Tracker coverage focus with an intentionally long label'),
        findsOneWidget);
    expect(find.text('09:00 - 10:15'), findsOneWidget);
    expect(find.text('1 小时 15 分钟'), findsOneWidget);
    expect(find.textContaining('coding · 2 个应'), findsOneWidget);
    expect(find.text('涉及应用：Code.exe、Browser.exe'), findsOneWidget);
    expect(find.text('任务：Ship tracker coverage'), findsOneWidget);
    expect(find.textContaining('3 条原始记'), findsWidgets);
    expect(find.textContaining('2 个应'), findsWidgets);
    expect(find.textContaining('2 次打'), findsWidgets);
    expect(find.textContaining('80 次按'), findsOneWidget);
    expect(find.textContaining('8 次点'), findsOneWidget);
    expect(find.text('360px 移动'), findsOneWidget);
    expect(find.text('1440px 滚动'), findsOneWidget);
    expect(find.textContaining('Code.exe'), findsWidgets);
    expect(find.text('查看 09:00 输入分析'), findsOneWidget);
    expect(find.text('调整任务关联'), findsOneWidget);
    expect(find.text('打开任务'), findsOneWidget);

    await tester.tap(find.textContaining('查看原始记录').first);
    await tester.pumpAndSettle();

    expect(find.text('涉及分类：coding、research'), findsOneWidget);
    expect(find.text('Code record label'), findsOneWidget);
    expect(find.text('Browser research record'), findsOneWidget);
    expect(find.text('关联任务：Ship tracker coverage'), findsOneWidget);
    expect(find.text('改绑任务'), findsOneWidget);
    expect(find.text('联动应用分析'), findsWidgets);
    expect(find.text('联动 09:00'), findsWidgets);
  });

  testWidgets('expanded record row linkage buttons return to tracker overview',
      (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      store: _FakeTrackingStore(daySummary: _richDaySummary()),
      tasks: <TaskItem>[_task(id: 7, summary: 'Ship tracker coverage')],
    );
    await pumpUntilFound(tester, find.text('工作会话'), maxPumps: 20);

    final expandDetailsButton = find.textContaining('查看原始记录');
    await tester.ensureVisible(expandDetailsButton.first);
    await tester.tap(expandDetailsButton.first);
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Browser research record'),
        maxPumps: 20);

    final recordProcessLink =
        find.widgetWithIcon(TextButton, Icons.tune_outlined).first;
    await tester.ensureVisible(recordProcessLink);
    await tester.tap(recordProcessLink);
    await tester.pumpAndSettle();

    expect(find.byType(TrackerPage), findsOneWidget);
    expect(find.textContaining('Code.exe'), findsWidgets);

    final openDayDetails =
        find.widgetWithIcon(FilledButton, Icons.view_list_outlined);
    await tester.ensureVisible(openDayDetails);
    await tester.tap(openDayDetails);
    await tester.pumpAndSettle();
    await tester.ensureVisible(expandDetailsButton.first);
    await tester.tap(expandDetailsButton.first);
    await tester.pumpAndSettle();

    final recordHourLink =
        find.widgetWithIcon(TextButton, Icons.schedule_outlined).first;
    await tester.ensureVisible(recordHourLink);
    await tester.tap(recordHourLink);
    await tester.pumpAndSettle();

    expect(find.byType(TrackerPage), findsOneWidget);
    expect(find.textContaining('09:00'), findsWidgets);
  });

  testWidgets(
      'session tile link chips toggle selected process and hour callbacks', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      store: _FakeTrackingStore(daySummary: _richDaySummary()),
    );
    await pumpUntilFound(tester, find.textContaining('Code.exe'), maxPumps: 20);

    await tester.tap(find.widgetWithIcon(ActionChip, Icons.tune).first);
    await tester.pumpAndSettle();

    expect(find.text('联动应用：Code.exe'), findsWidgets);

    await tester.ensureVisible(find.text('查看今日详细数据'));
    await tester.tap(find.text('查看今日详细数据'));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.textContaining('已联动应用'), maxPumps: 20);
    await pumpUntilFound(tester, find.text('查看 09:00 输入分析'), maxPumps: 20);

    await tester.tap(find.text('查看 09:00 输入分析'));
    await tester.pumpAndSettle();

    expect(find.textContaining('09:00'), findsWidgets);

    await tester.ensureVisible(find.text('查看今日详细数据'));
    await tester.tap(find.text('查看今日详细数据'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已联动时段'), findsWidgets);
  });

  testWidgets(
      'session filters handle search only-with-input task and empty result', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      store: _FakeTrackingStore(daySummary: _richDaySummary()),
      tasks: <TaskItem>[_task(id: 7, summary: 'Ship tracker coverage')],
    );
    await pumpUntilFound(tester, find.byType(TextField), maxPumps: 20);

    await tester.enterText(find.byType(TextField).first, 'passive notes');
    await tester.pump();

    expect(find.text('Passive notes review'), findsOneWidget);
    expect(find.text('Tracker coverage focus with an intentionally long label'),
        findsNothing);

    await tester.tap(find.textContaining('仅看有输入活'));
    await tester.pump();

    expect(find.textContaining('当前筛选下没有工作会话'), findsOneWidget);

    await tester.tap(find.textContaining('清空筛').first);
    await tester.pump();
    expect(find.text('Tracker coverage focus with an intentionally long label'),
        findsOneWidget);
  });

  testWidgets('task binding sheet covers empty task menu and create option', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      store: _FakeTrackingStore(daySummary: _richDaySummary()),
      tasks: const <TaskItem>[],
    );
    await pumpUntilFound(tester, find.text('关联任务'), maxPumps: 20);

    await tester.ensureVisible(find.text('关联任务').first);
    await tester.tap(find.text('关联任务').first);
    await tester.pumpAndSettle();

    expect(find.text('关联任务'), findsWidgets);
    expect(
      find.text(
        '工作会话：Passive notes review · ${_dayShort(_day)} 11:20 - 11:25',
      ),
      findsOneWidget,
    );
    expect(find.text('新建任务'), findsOneWidget);
    expect(find.textContaining('当前还没有可选任务'), findsOneWidget);
  });
  testWidgets('task binding sheet orders anchored task before unanchored peer',
      (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      store: _FakeTrackingStore(daySummary: _richDaySummary()),
      tasks: <TaskItem>[
        _task(id: 11, summary: 'Zulu no anchor'),
        _task(
          id: 13,
          summary: 'Beta later anchored',
          dtstart: _day.add(const Duration(hours: 12)),
        ),
        _task(
          id: 12,
          summary: 'Alpha anchored',
          dtstart: _day.add(const Duration(hours: 10)),
        ),
      ],
    );
    final bindTaskButton = find.widgetWithIcon(TextButton, Icons.link_outlined);
    await pumpUntilFound(tester, bindTaskButton, maxPumps: 20);

    await tester.ensureVisible(bindTaskButton.first);
    await tester.tap(bindTaskButton.first);
    await tester.pumpAndSettle();

    expect(find.text('Alpha anchored'), findsOneWidget);
    expect(find.text('Beta later anchored'), findsOneWidget);
    expect(find.text('Zulu no anchor'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Alpha anchored')).dy,
      lessThan(tester.getTopLeft(find.text('Beta later anchored')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Beta later anchored')).dy,
      lessThan(tester.getTopLeft(find.text('Zulu no anchor')).dy),
    );
  });
}

void expectCurrentSessionTitle(String text) {
  expect(
    find.byWidgetPredicate(
      (widget) =>
          widget is Text &&
          widget.data == text &&
          widget.style?.fontWeight == FontWeight.w700,
      description: 'current session title "$text"',
    ),
    findsOneWidget,
  );
}

Future<void> _resetTrackerHarness(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Future<void> _pumpTrackerRoute(
  WidgetTester tester, {
  required String initialLocation,
  _FakeTrackerServiceNotifier? trackerNotifier,
  _FakeTrackingStore? store,
  List<TaskItem> tasks = const <TaskItem>[],
  Size size = const Size(1400, 1100),
  Object? daySummaryError,
  Map<String, Object?>? uploadDiagnostics,
  Object? uploadDiagnosticsError,
  List<WorkSession>? workSessions,
  String? selectedCategory,
  int? selectedTaskId,
  ActivityHeatmapBucket? selectedHeatmapBucket,
}) async {
  final fakeStore = store ?? _FakeTrackingStore(daySummary: _emptyDaySummary());
  await pumpAppAt(
    tester,
    initialLocation: initialLocation,
    size: size,
    overrides: <Override>[
      trackerServiceNotifierProvider.overrideWith(
        () => trackerNotifier ?? _FakeTrackerServiceNotifier(),
      ),
      sequenceRecordingProvider.overrideWith((ref) => true),
      allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
      allEventCalendarsProvider.overrideWith(
        (ref) => Stream.value(const <EventCalendar>[]),
      ),
      allTaskListsProvider.overrideWith(
        (ref) => Stream.value(const <TaskList>[]),
      ),
      activityDaySummaryProvider.overrideWith(
        (ref) async {
          final error = daySummaryError;
          if (error != null) {
            throw error;
          }
          return fakeStore.daySummary;
        },
      ),
      workSessionsForDateProvider.overrideWith(
        (ref) => workSessions ?? _workSessions(),
      ),
      if (selectedCategory != null)
        trackerHistorySelectedCategoryProvider.overrideWith(
          (ref) => selectedCategory,
        ),
      if (selectedTaskId != null)
        trackerHistorySelectedTaskIdProvider.overrideWith(
          (ref) => selectedTaskId,
        ),
      if (selectedHeatmapBucket != null)
        trackerHistorySelectedHeatmapBucketProvider.overrideWith(
          (ref) => selectedHeatmapBucket,
        ),
      trackingUploadDiagnosticsProvider.overrideWith(
        (ref) async {
          final error = uploadDiagnosticsError;
          if (error != null) {
            throw error;
          }
          return uploadDiagnostics ??
              <String, Object?>{
                'lastActivityRecordId': 0,
                'lastInputEventId': 0,
                'lastRawLogId': 0,
                'pendingActivityRecords': 0,
                'pendingInputEvents': 0,
                'pendingRawLogs': 0,
              };
        },
      ),
      trackingServerFirstStoreProvider.overrideWith((ref) async => fakeStore),
      trackingUploadServiceProvider.overrideWith(
        (ref) => Future<TrackingUploadService>.error(
          StateError('upload service is not used in widget coverage'),
        ),
      ),
    ],
  );
}

TrackerState _currentSnapshotState({
  required String processName,
  required String windowTitle,
}) {
  final now = _day.add(const Duration(hours: 14));
  final snapshot = WindowSnapshot(
    processName: processName,
    className: 'ServerWindow',
    windowTitle: windowTitle,
    isFullscreen: false,
    timestamp: now,
  );
  return TrackerState(
    isRunning: true,
    currentSnapshot: snapshot,
    displaySnapshot: snapshot,
    displaySessionStart: _day.add(const Duration(hours: 13, minutes: 45)),
    lastSampleAt: now,
  );
}

List<WorkSession> _workSessions() {
  final code = _activityRecord(
    id: 1,
    start: _day.add(const Duration(hours: 9)),
    durationMinutes: 75,
    processName: 'Code.exe',
    windowTitle: 'FlowPlanV2 tests',
    category: 'coding',
    manualLabel: 'Code record label',
    linkedTaskId: 7,
    keyCount: 80,
    mouseClicks: 8,
    mouseMovePx: 360,
    scrollPx: 1440,
  );
  final browser = _activityRecord(
    id: 2,
    start: _day.add(const Duration(hours: 9, minutes: 22)),
    durationMinutes: 15,
    processName: 'Browser.exe',
    windowTitle: 'Long research window title that should be ellipsized in row',
    category: 'research',
    manualLabel: 'Browser research record',
    keyCount: 14,
    mouseClicks: 5,
    mouseMovePx: 210,
    scrollPx: 900,
  );
  final passive = _activityRecord(
    id: 3,
    start: _day.add(const Duration(hours: 11, minutes: 20)),
    durationMinutes: 5,
    processName: 'Notes.exe',
    windowTitle: 'Passive notes window',
    category: 'admin',
    manualLabel: 'Passive notes review',
    keyCount: 0,
    mouseClicks: 0,
    mouseMovePx: 0,
    scrollPx: 0,
  );

  return <WorkSession>[
    WorkSession(
      startTime: _day.add(const Duration(hours: 9)),
      endTime: _day.add(const Duration(hours: 10, minutes: 15)),
      label: 'Tracker coverage focus with an intentionally long label',
      processName: 'Code.exe',
      category: 'coding',
      records: <ActivityRecord>[code, browser],
      durationMinutes: 75,
      keyCount: 80,
      mouseClicks: 8,
      mouseMovePx: 360,
      scrollPx: 1440,
      processNames: const <String>['Code.exe', 'Browser.exe'],
      categories: const <String>['coding', 'research'],
      interruptionCount: 2,
      rawRecordCountOverride: 3,
    ),
    WorkSession(
      startTime: _day.add(const Duration(hours: 11, minutes: 20)),
      endTime: _day.add(const Duration(hours: 11, minutes: 25)),
      label: 'Passive notes review',
      processName: 'Notes.exe',
      category: 'admin',
      records: <ActivityRecord>[passive],
      durationMinutes: 5,
      keyCount: 0,
      mouseClicks: 0,
      mouseMovePx: 0,
      scrollPx: 0,
      processNames: const <String>['Notes.exe'],
      categories: const <String>['admin'],
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
  int? linkedTaskId,
  required int keyCount,
  required int mouseClicks,
  required int mouseMovePx,
  required int scrollPx,
}) {
  return ActivityRecord(
    id: id,
    startTime: start,
    endTime: start.add(Duration(minutes: durationMinutes)),
    durationMinutes: durationMinutes,
    keyCount: keyCount,
    mouseClicks: mouseClicks,
    mouseMovePx: mouseMovePx,
    scrollPx: scrollPx,
    manualLabel: manualLabel,
    processName: processName,
    windowTitle: windowTitle,
    category: category,
    linkedTaskId: linkedTaskId,
    isAuto: true,
    source: 'tracker-widget-test',
  );
}

TrackerState _runningState({
  bool isViewingExcludedApp = false,
  DateTime? displaySessionStart,
  DateTime? lastSampleAt,
}) {
  final now = _day.add(const Duration(hours: 10, minutes: 15));
  return TrackerState(
    isRunning: true,
    currentSnapshot: WindowSnapshot(
      processName: isViewingExcludedApp ? 'FlowPlanV2.exe' : 'Code.exe',
      className: 'FlutterWindow',
      windowTitle:
          isViewingExcludedApp ? 'FlowPlanV2 Tracker' : 'FlowPlanV2 tests',
      isFullscreen: false,
      timestamp: now,
    ),
    displaySnapshot: WindowSnapshot(
      processName: 'Code.exe',
      className: 'Chrome_WidgetWin_1',
      windowTitle: 'FlowPlanV2 tests',
      isFullscreen: false,
      timestamp: now,
    ),
    displayClassification: const ActivityClassification(
      category: '编程',
      label: 'Deep work',
      confidence: 0.95,
    ),
    displaySessionStart:
        displaySessionStart ?? _day.add(const Duration(hours: 9)),
    displayTelemetry: InputTelemetry(
      keyCount: 24,
      keyDistribution: const <int, int>{17: 2, 83: 4},
      keySequence: 'Ctrl+S\nEnter',
      clicks: const MouseClicks(left: 3, right: 1),
      scrollPx: 600,
      mouseMovePx: 2048,
      timestamp: now,
      inputEvents: const <RawInputEvent>[],
    ),
    isViewingExcludedApp: isViewingExcludedApp,
    lastSampleAt: lastSampleAt ?? now,
  );
}

Map<String, dynamic> _richDaySummary() {
  final first = _recordPayload(
    serverId: 'record-code',
    start: _day.add(const Duration(hours: 9)),
    durationMinutes: 75,
    processName: 'Code.exe',
    windowTitle: 'FlowPlanV2 tests',
    category: 'coding',
    manualLabel: 'Code record label',
    linkedTaskId: 7,
    keyCount: 80,
    mouseClicks: 8,
    mouseMovePx: 360,
    scrollPx: 1440,
  );
  final second = _recordPayload(
    serverId: 'record-browser',
    start: _day.add(const Duration(hours: 9, minutes: 22)),
    durationMinutes: 15,
    processName: 'Browser.exe',
    windowTitle: 'Long research window title that should be ellipsized in row',
    category: 'research',
    manualLabel: 'Browser research record',
    keyCount: 14,
    mouseClicks: 5,
    mouseMovePx: 210,
    scrollPx: 900,
  );
  final passive = _recordPayload(
    serverId: 'record-passive',
    start: _day.add(const Duration(hours: 11, minutes: 20)),
    durationMinutes: 5,
    processName: 'Notes.exe',
    windowTitle: 'Passive notes window',
    category: 'admin',
    manualLabel: 'Passive notes review',
    keyCount: 0,
    mouseClicks: 0,
    mouseMovePx: 0,
    scrollPx: 0,
  );

  return <String, dynamic>{
    'insights': <String, Object?>{
      'recordCount': 3,
      'totalMinutes': 125,
      'focusMinutes': 60,
      'totalKeys': 94,
      'totalClicks': 13,
      'totalMovePx': 570,
      'totalScrollPx': 2340,
      'productiveRecordCount': 2,
      'sequenceRecordCount': 1,
      'topProcesses': <Map<String, Object?>>[
        <String, Object?>{
          'label': 'Code.exe',
          'minutes': 75,
          'keys': 80,
          'clicks': 8,
          'movePx': 360,
          'scrollPx': 1440,
          'sessions': 1,
        },
        <String, Object?>{
          'label': 'Browser.exe',
          'minutes': 15,
          'keys': 14,
          'clicks': 5,
          'movePx': 210,
          'scrollPx': 900,
          'sessions': 1,
        },
      ],
      'topCategories': <Map<String, Object?>>[
        <String, Object?>{
          'label': 'coding',
          'minutes': 75,
          'keys': 80,
          'clicks': 8,
          'movePx': 360,
          'scrollPx': 1440,
          'sessions': 1,
        },
      ],
    },
    'previewRecords': <Map<String, Object?>>[first, second, passive],
    'sessions': <Map<String, Object?>>[
      <String, Object?>{
        'startTime': _day.add(const Duration(hours: 9)).toIso8601String(),
        'endTime':
            _day.add(const Duration(hours: 10, minutes: 15)).toIso8601String(),
        'label': 'Tracker coverage focus with an intentionally long label',
        'processName': 'Code.exe',
        'category': 'coding',
        'durationMinutes': 75,
        'keyCount': 80,
        'mouseClicks': 8,
        'mouseMovePx': 360,
        'scrollPx': 1440,
        'processNames': <String>['Code.exe', 'Browser.exe'],
        'categories': <String>['coding', 'research'],
        'interruptionCount': 2,
        'rawRecordCount': 3,
      },
      <String, Object?>{
        'startTime':
            _day.add(const Duration(hours: 11, minutes: 20)).toIso8601String(),
        'endTime':
            _day.add(const Duration(hours: 11, minutes: 25)).toIso8601String(),
        'label': 'Passive notes review',
        'processName': 'Notes.exe',
        'category': 'admin',
        'durationMinutes': 5,
        'keyCount': 0,
        'mouseClicks': 0,
        'mouseMovePx': 0,
        'scrollPx': 0,
        'processNames': <String>['Notes.exe'],
        'categories': <String>['admin'],
        'interruptionCount': 0,
        'rawRecordCount': 1,
      },
    ],
  };
}

Map<String, Object?> _recordPayload({
  required String serverId,
  required DateTime start,
  required int durationMinutes,
  required String processName,
  required String windowTitle,
  required String category,
  required String manualLabel,
  int? linkedTaskId,
  required int keyCount,
  required int mouseClicks,
  required int mouseMovePx,
  required int scrollPx,
}) {
  return <String, Object?>{
    'serverId': serverId,
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
      if (linkedTaskId != null) 'linkedTaskId': linkedTaskId,
      'keyCount': keyCount,
      'mouseClicks': mouseClicks,
      'mouseMovePx': mouseMovePx,
      'scrollPx': scrollPx,
      'isAuto': true,
    },
  };
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

Map<String, dynamic> _inputHeatmapResponse({
  String leadingProcessName = 'Code.exe',
}) {
  return <String, dynamic>{
    'buckets': <Map<String, Object?>>[
      <String, Object?>{
        'bucketStart': _day.add(const Duration(hours: 9)).toIso8601String(),
        'eventCount': 320,
        'keyboardEventCount': 220,
        'mouseButtonEventCount': 45,
        'wheelEventCount': 30,
        'mouseMoveEventCount': 25,
        'mouseMoveDistance': 5600,
      },
      <String, Object?>{
        'bucketStart': _day.add(const Duration(hours: 10)).toIso8601String(),
        'eventCount': 80,
        'keyboardEventCount': 30,
        'mouseButtonEventCount': 20,
        'wheelEventCount': 10,
        'mouseMoveEventCount': 20,
        'mouseMoveDistance': 1200,
      },
    ],
    'keyCounts': <String, Object?>{'83': 42, '17': 12},
    'mouseCounts': <String, Object?>{'left': 31, 'right': 4},
    'topKeys': <Map<String, Object?>>[
      <String, Object?>{'keyCode': 83, 'label': 'S', 'count': 42},
      <String, Object?>{'keyCode': 17, 'label': 'Ctrl', 'count': 12},
    ],
    'processIntensities': <Map<String, Object?>>[
      <String, Object?>{
        'processName': leadingProcessName,
        'totalEvents': 300,
        'keyEvents': 220,
        'mouseButtonEvents': 40,
        'wheelEvents': 20,
        'mouseMoveEvents': 20,
        'moveDistance': 4800,
        'activeMinutes': 58,
        'intensityScore': 348,
      },
      <String, Object?>{
        'processName': 'Browser.exe',
        'totalEvents': 100,
        'keyEvents': 30,
        'mouseButtonEvents': 25,
        'wheelEvents': 20,
        'mouseMoveEvents': 25,
        'moveDistance': 2000,
        'activeMinutes': 30,
        'intensityScore': 120,
      },
    ],
  };
}

WorkSession _sessionForFilters({
  required String label,
  required String processName,
  required String category,
  required List<String> categories,
  Duration startOffset = const Duration(hours: 12),
}) {
  final start = _day.add(startOffset);
  final record = _activityRecord(
    id: startOffset.inMinutes,
    start: start,
    durationMinutes: 25,
    processName: processName,
    windowTitle: '$label window',
    category: category,
    manualLabel: label,
    keyCount: 10,
    mouseClicks: 1,
    mouseMovePx: 20,
    scrollPx: 120,
  );
  return WorkSession(
    startTime: start,
    endTime: start.add(const Duration(minutes: 25)),
    label: label,
    processName: processName,
    category: category,
    records: <ActivityRecord>[record],
    durationMinutes: 25,
    keyCount: 10,
    mouseClicks: 1,
    mouseMovePx: 20,
    scrollPx: 120,
    processNames: <String>[processName],
    categories: categories,
    interruptionCount: 0,
  );
}

ActivityHeatmapBucket _hourBucket(int hour) {
  final start = DateTime(_day.year, _day.month, _day.day, hour);
  return ActivityHeatmapBucket(
    start: start,
    end: start.add(const Duration(hours: 1)),
    shortLabel: hour.toString().padLeft(2, '0'),
    longLabel: '${hour.toString().padLeft(2, '0')}:00 bucket',
    completedCount: 0,
    totalMinutes: 0,
  );
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

class _FakeTrackingStore implements TrackingServerFirstStore {
  _FakeTrackingStore({
    required this.daySummary,
    Map<String, dynamic>? inputHeatmap,
    Object? inputHeatmapError,
  })  : inputHeatmapResponse = inputHeatmap ??
            <String, dynamic>{'buckets': <Map<String, Object?>>[]},
        inputHeatmapFailure = inputHeatmapError;

  final Map<String, dynamic> daySummary;
  final Map<String, dynamic> inputHeatmapResponse;
  final Object? inputHeatmapFailure;

  @override
  Future<Map<String, dynamic>> activityDaySummary({
    required DateTime date,
  }) async {
    return daySummary;
  }

  @override
  Future<Map<String, dynamic>> trackingSummary({
    DateTime? start,
    DateTime? end,
  }) async {
    return <String, dynamic>{
      'canonicalObjectCounts': <String, Object?>{'activity_record': 3},
      'latestReceivedAtByKind': <String, Object?>{
        'activity_record':
            _day.add(const Duration(hours: 11)).toIso8601String(),
      },
    };
  }

  @override
  Future<Map<String, dynamic>> activityHeatmap({
    DateTime? start,
    DateTime? end,
    String bucket = 'day',
    String? processName,
    String? category,
    int? taskId,
  }) async {
    return <String, dynamic>{
      'buckets': <Map<String, Object?>>[
        <String, Object?>{
          'bucketStart': _day.add(const Duration(hours: 9)).toIso8601String(),
          'recordCount': 2,
          'totalMinutes': 90,
        },
        <String, Object?>{
          'bucketStart': _day.add(const Duration(hours: 11)).toIso8601String(),
          'recordCount': 1,
          'totalMinutes': 5,
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> inputHeatmap({
    DateTime? start,
    DateTime? end,
    String bucket = 'hour',
    String? processName,
    String? category,
    String? eventKind,
  }) async {
    final failure = inputHeatmapFailure;
    if (failure != null) {
      throw failure;
    }
    return inputHeatmapResponse;
  }

  @override
  Future<Map<String, dynamic>> filterOptions({
    DateTime? start,
    DateTime? end,
  }) async {
    return <String, dynamic>{
      'processOptions': <String>['Browser.exe', 'Code.exe', 'Notes.exe'],
      'categoryOptions': <String>['admin', 'coding', 'research'],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTrackerServiceNotifier extends TrackerServiceNotifier {
  _FakeTrackerServiceNotifier({
    this.initialState = const TrackerState(),
  });

  final TrackerState initialState;
  var refreshCalls = 0;

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
  Future<void> refreshNow() async {
    refreshCalls += 1;
  }

  @override
  Future<void> openAndroidUsageAccessSettings() async {}

  @override
  DateTime? get lastAutoUploadAt => null;

  @override
  String? get lastAutoUploadError => null;

  @override
  bool get isAutoUploading => false;
}

String _dayShort(DateTime date) {
  return '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

final DateTime _day = DateTime(
  DateTime.now().year,
  DateTime.now().month,
  DateTime.now().day,
);
