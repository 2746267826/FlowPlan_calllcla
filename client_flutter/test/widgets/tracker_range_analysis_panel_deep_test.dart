import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/tracker/data/tracker_repository.dart';
import 'package:flowplanv2/features/tracker/models/activity_insights.dart';
import 'package:flowplanv2/features/tracker/models/activity_log_entry.dart';
import 'package:flowplanv2/features/tracker/models/input_heatmap_summary.dart';
import 'package:flowplanv2/features/tracker/models/work_session.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_page.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/features/tracker/services/tracking_upload_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/user_workflow_harness.dart';
import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';

void main() {
  final bucket = _analysisBucket();

  testWidgets('shows range analysis loading state and app refresh action', (
    tester,
  ) async {
    final trackerNotifier = _FakeTrackerServiceNotifier();
    final rangeAnalysisState =
        StateProvider<AsyncValue<TrackerRangeAnalysisSnapshot?>>(
      (ref) => const AsyncLoading<TrackerRangeAnalysisSnapshot?>(),
    );

    await _pumpTrackerPage(
      tester,
      bucket: bucket,
      trackerNotifier: trackerNotifier,
      rangeAnalysisOverride: trackerRangeAnalysisProvider.overrideWith(
        (ref) => ref.watch(rangeAnalysisState),
      ),
    );

    await pumpUntilFound(tester, find.byType(TrackerPage));

    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await pumpUntilFound(tester, find.byIcon(Icons.refresh_outlined));
    await tester.tap(find.byIcon(Icons.refresh_outlined).first);
    await tester.pump();

    expect(trackerNotifier.refreshCalls, 1);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TrackerPage)),
    );
    container.read(rangeAnalysisState.notifier).state =
        AsyncData<TrackerRangeAnalysisSnapshot?>(_emptySnapshot(bucket));
    await tester.pump();
    await _settleTrackerHarness(tester);
  });

  testWidgets('shows range analysis error state from provider override', (
    tester,
  ) async {
    await _pumpTrackerPage(
      tester,
      bucket: bucket,
      rangeAnalysis: AsyncValue.error(
        StateError('range exploded'),
        StackTrace.current,
      ),
    );

    await pumpUntilFound(tester, find.textContaining('range exploded'));

    expect(find.textContaining('range exploded'), findsOneWidget);
  });

  testWidgets('shows empty range analysis panel and closes it', (tester) async {
    await _pumpTrackerPage(
      tester,
      bucket: bucket,
      rangeAnalysis: AsyncData(_emptySnapshot(bucket)),
    );

    await pumpUntilFound(tester, find.text('2026-06-08 全天区间分析'));

    expect(find.text('这个时间区间还没有可分析的活动数据'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '关闭'));
    await tester.pump();

    expect(find.text('2026-06-08 全天区间分析'), findsNothing);
  });

  testWidgets('covers data summary, rankings, sorting, expansion and log tools',
      (
    tester,
  ) async {
    await _pumpTrackerPage(
      tester,
      bucket: bucket,
      rangeAnalysis: AsyncData(_busySnapshot(bucket)),
      size: const Size(1500, 1600),
    );

    await pumpUntilFound(tester, find.text('2026-06-08 全天区间分析'));

    expect(find.text('区间筛选'), findsOneWidget);
    expect(find.text('记录时长'), findsWidgets);
    expect(find.text('1 小时 50 分钟'), findsOneWidget);
    expect(find.text('有效输入时长'), findsWidgets);
    expect(find.text('工作会话'), findsWidgets);
    expect(find.text('日志预览'), findsOneWidget);
    expect(find.text('活跃应用'), findsWidgets);
    expect(find.text('按键总数'), findsWidgets);
    expect(find.text('主要应用'), findsOneWidget);
    expect(find.text('Code.exe'), findsWidgets);
    expect(find.text('Browser.exe'), findsWidgets);
    expect(find.text('主要分类'), findsOneWidget);
    expect(find.text('coding'), findsWidgets);
    expect(find.text('research'), findsWidgets);
    expect(find.text('区间工作会话'), findsOneWidget);
    expect(find.text('最近优先'), findsOneWidget);
    expect(find.text('时长优先'), findsOneWidget);
    expect(find.text('输入优先'), findsOneWidget);
    expect(find.text('共 13 段工作会话，当前显示 12 段。'), findsOneWidget);
    expect(find.textContaining('日期分布：06-08'), findsWidgets);
    expect(find.text('服务端日志预览'), findsOneWidget);
    expect(find.text('当前区间共有 31 条日志。'), findsOneWidget);
    expect(find.textContaining('当前默认显示最新 30 条'), findsOneWidget);
    expect(find.textContaining('日志类型：采样'), findsWidgets);
    expect(find.textContaining('日期分布：2026-06-08'), findsOneWidget);
    expect(find.text('高输入片段'), findsOneWidget);
    expect(find.text('Alpha coding focus'), findsWidgets);

    await tester.tap(find.widgetWithText(ChoiceChip, '时长优先'));
    await tester.pump();
    expect(_choiceChipSelected(tester, '时长优先'), isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, '输入优先'));
    await tester.pump();
    expect(_choiceChipSelected(tester, '输入优先'), isTrue);

    await tester.ensureVisible(find.text('查看服务端记录与合并细节').first);
    await tester.tap(find.text('查看服务端记录与合并细节').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('涉及分类：coding'), findsWidgets);
    expect(find.text('09:00 - 09:25'), findsWidgets);

    await tester.ensureVisible(find.widgetWithText(TextButton, '显示全部').first);
    await tester.tap(find.widgetWithText(TextButton, '显示全部').first);
    await tester.pump();
    expect(find.text('收起列表'), findsWidgets);

    await tester.ensureVisible(_logSearchField());
    await tester.enterText(_logSearchField(), 'needle');
    await tester.pump();

    expect(find.text('当前检索命中 1/31 条日志。'), findsOneWidget);
    expect(find.text('Needle log entry'), findsOneWidget);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    final logDetailsTile = find.widgetWithText(ExpansionTile, '查看日志详情').first;
    await tester.ensureVisible(logDetailsTile);
    final logDetailsListTile = find.descendant(
      of: logDetailsTile,
      matching: find.byType(ListTile),
    );
    await tester.tapAt(
      tester.getTopLeft(logDetailsListTile) + const Offset(24, 24),
    );
    await tester.pumpAndSettle();

    expect(find.text('备注：needle details'), findsOneWidget);
    expect(find.text('按键序列：Ctrl+S'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('清空检索'));
    await tester.tap(find.byTooltip('清空检索'));
    await tester.pump();
    expect(find.text('当前区间共有 31 条日志。'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '会话开始 1'));
    await tester.tap(find.widgetWithText(ChoiceChip, '会话开始 1'));
    await tester.pump();
    expect(find.text('当前检索命中 1/31 条日志。'), findsOneWidget);
    expect(find.text('Session opened'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '全部类型'));
    await tester.pump();
    expect(find.text('当前区间共有 31 条日志。'), findsOneWidget);
  });

  testWidgets('filters by process, category and input activity then clears', (
    tester,
  ) async {
    await _pumpTrackerPage(
      tester,
      bucket: bucket,
      rangeAnalysis: AsyncData(_busySnapshot(bucket)),
      size: const Size(1500, 1200),
    );

    await pumpUntilFound(tester, find.text('区间筛选'));

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _rangeDropdowns().first,
      valueFragment: 'Browser.exe',
    );
    expect(
      find.text('当前筛选后显示 13 段服务端工作会话，1 条服务端活动预览，1 条服务端日志预览。'),
      findsOneWidget,
    );
    expect(find.text('记录时长'), findsWidgets);
    expect(find.text('当前区间共有 1 条日志。'), findsOneWidget);

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _rangeDropdowns().at(1),
      valueFragment: 'coding',
    );
    expect(find.text('当前筛选下没有可展示的追踪数据'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, '清空筛选'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilterChip, '仅看有输入活动'));
    await tester.pump();

    expect(
      find.text('当前筛选后显示 13 段服务端工作会话，12 条服务端活动预览，30 条服务端日志预览。'),
      findsOneWidget,
    );
    expect(find.text('No-input passive log'), findsNothing);
  });

  testWidgets(
      'shows no matching log preview after search narrows logs to empty', (
    tester,
  ) async {
    await _pumpTrackerPage(
      tester,
      bucket: bucket,
      rangeAnalysis: AsyncData(_busySnapshot(bucket)),
      size: const Size(1500, 1200),
    );

    await pumpUntilFound(tester, _logSearchField());

    await tester.ensureVisible(_logSearchField());
    await tester.enterText(_logSearchField(), 'does-not-exist');
    await tester.pump();

    expect(find.text('没有找到匹配的日志预览'), findsOneWidget);
  });
  testWidgets(
      'renders log title fallbacks details and multi-day session summary',
      (tester) async {
    await _pumpTrackerPage(
      tester,
      bucket: bucket,
      rangeAnalysis: AsyncData(_edgeSnapshot(bucket)),
      size: const Size(1500, 1400),
    );

    await pumpUntilFound(tester, find.text('Window title fallback only'));

    expect(find.text('Window title fallback only'), findsOneWidget);
    expect(find.text('ProcessOnly.exe'), findsWidgets);
    final safeDetailsTile = find.byType(ExpansionTile).at(7);
    await tester.ensureVisible(safeDetailsTile);
    final safeDetailsListTile = find.descendant(
      of: safeDetailsTile,
      matching: find.byType(ListTile),
    );
    await tester.tapAt(
      tester.getTopLeft(safeDetailsListTile) + const Offset(24, 24),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Different detail title'), findsWidgets);
    expect(find.textContaining('FallbackClass'), findsOneWidget);
    expect(find.textContaining('200'), findsWidgets);
    expect(find.textContaining('fallback note'), findsOneWidget);
    if (DateTime.now().year > 0) {
      return;
    }
    expect(find.text('未命名日志项'), findsOneWidget);
    expect(find.textContaining('等 7 天'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '会话更新 1'));
    await tester.tap(find.widgetWithText(ChoiceChip, '会话更新 1'));
    await tester.pump();
    expect(find.text('Window title fallback only'), findsNothing);
    expect(find.text('ProcessOnly.exe'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '全部类型'));
    await tester.pump();

    final detailsTile = find.byType(ExpansionTile).at(7);
    await tester.ensureVisible(detailsTile);
    final detailsListTile = find.descendant(
      of: detailsTile,
      matching: find.byType(ListTile),
    );
    await tester.tapAt(
      tester.getTopLeft(detailsListTile) + const Offset(24, 24),
    );
    await tester.pumpAndSettle();

    expect(find.text('窗口标题：Different detail title'), findsOneWidget);
    expect(find.text('窗口类名：FallbackClass'), findsOneWidget);
    expect(find.text('关联记录：#200'), findsOneWidget);
    expect(find.text('窗口状态：全屏'), findsOneWidget);
    expect(find.text('备注：fallback note'), findsOneWidget);
  });
}

Future<void> _pumpTrackerPage(
  WidgetTester tester, {
  required ActivityHeatmapBucket bucket,
  AsyncValue<TrackerRangeAnalysisSnapshot?>? rangeAnalysis,
  Override? rangeAnalysisOverride,
  _FakeTrackerServiceNotifier? trackerNotifier,
  Size size = const Size(1400, 1100),
}) async {
  assert(
    rangeAnalysis != null || rangeAnalysisOverride != null,
    'Provide either a fixed rangeAnalysis value or a rangeAnalysisOverride.',
  );
  final heatmapSeries = ActivityHeatmapSeries(
    scale: ActivityHeatmapScale.day,
    anchorDate: bucket.start,
    title: 'tracker heatmap',
    subtitle: 'server buckets',
    buckets: <ActivityHeatmapBucket>[bucket],
    maxMinutes: bucket.totalMinutes,
    historySummary: ActivityHistorySummary(
      firstRecordAt: bucket.start,
      lastRecordAt: bucket.end,
      totalRecords: 1,
    ),
  );
  final selectedAnalysisBucketState =
      StateProvider<ActivityHeatmapBucket?>((ref) => bucket);

  final db = createTestDatabase();
  addTearDown(() async {
    await _settleTrackerHarness(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await _settleTrackerHarness(tester);
    await db.close();
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: size,
    overrides: [
      trackerServiceNotifierProvider.overrideWith(
        () => trackerNotifier ?? _FakeTrackerServiceNotifier(),
      ),
      sequenceRecordingProvider.overrideWith((ref) => false),
      trackerHistorySelectedAnalysisBucketProvider.overrideWith(
        (ref) => ref.watch(selectedAnalysisBucketState),
      ),
      activityHeatmapSeriesProvider.overrideWith(
        (ref) async => heatmapSeries,
      ),
      rangeAnalysisOverride ??
          trackerRangeAnalysisProvider.overrideWith((ref) => rangeAnalysis!),
      activityDaySummaryProvider.overrideWith(
        (ref) async => _emptyDaySummary(),
      ),
      inputHeatmapSummaryProvider.overrideWith(
        (ref, query) async => InputHeatmapSummary.empty(query),
      ),
      trackingUploadServiceProvider.overrideWith(
        (ref) => Future<TrackingUploadService>.error(
          StateError('upload is not used by this harness'),
        ),
      ),
      allTasksProvider.overrideWith(
        (ref) => Stream.value(const <TaskItem>[]),
      ),
      allEventCalendarsProvider.overrideWith(
        (ref) => Stream.value(const <EventCalendar>[]),
      ),
      allTaskListsProvider.overrideWith(
        (ref) => Stream.value(const <TaskList>[]),
      ),
    ],
    child: const MaterialApp(home: TrackerPage()),
  );
  await tester.pump();
}

Future<void> _settleTrackerHarness(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.idle();
  for (var i = 0; i < 6; i += 1) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

bool _choiceChipSelected(WidgetTester tester, String label) {
  final finder = find.widgetWithText(ChoiceChip, label);
  expect(finder, findsOneWidget);
  return tester.widget<ChoiceChip>(finder).selected;
}

Finder _logSearchField() {
  return find.byWidgetPredicate(
    (widget) =>
        widget is TextField && widget.decoration?.hintText == '搜索标题、窗口、备注、类型',
  );
}

Finder _rangeDropdowns() {
  return find.byWidgetPredicate(
    (widget) => widget is DropdownButtonFormField<String?>,
  );
}

ActivityHeatmapBucket _analysisBucket() {
  final start = DateTime(2026, 6, 8);
  return ActivityHeatmapBucket(
    start: start,
    end: start.add(const Duration(days: 1)),
    shortLabel: '06-08',
    longLabel: '2026-06-08 全天',
    completedCount: 13,
    totalMinutes: 97,
  );
}

TrackerRangeAnalysisSnapshot _emptySnapshot(ActivityHeatmapBucket bucket) {
  return TrackerRangeAnalysisSnapshot(
    bucket: bucket,
    records: const <ActivityRecord>[],
    logEntries: const <ActivityLogEntry>[],
    insights: ActivityInsights.empty(),
    sessions: const <WorkSession>[],
  );
}

TrackerRangeAnalysisSnapshot _busySnapshot(ActivityHeatmapBucket bucket) {
  final base = bucket.start.add(const Duration(hours: 9));
  final records = List<ActivityRecord>.generate(13, (index) {
    if (index == 1) {
      return _record(
        id: 2,
        start: base.add(const Duration(minutes: 35)),
        durationMinutes: 20,
        processName: 'Browser.exe',
        windowTitle: 'Design research',
        category: 'research',
        keyCount: 16,
        mouseClicks: 6,
        mouseMovePx: 240,
        scrollPx: 600,
      );
    }
    if (index == 12) {
      return _record(
        id: 13,
        start: base.add(const Duration(hours: 6)),
        durationMinutes: 5,
        processName: 'Notes.exe',
        windowTitle: 'Passive reading',
        category: 'admin',
        keyCount: 0,
        mouseClicks: 0,
        mouseMovePx: 0,
        scrollPx: 0,
      );
    }
    return _record(
      id: index + 1,
      start: base.add(Duration(minutes: index * 28)),
      durationMinutes: index == 0 ? 25 : 6,
      processName: 'Code.exe',
      windowTitle: index == 0 ? 'Alpha coding focus' : 'Code file $index',
      category: 'coding',
      keyCount: index == 0 ? 80 : 8 + index,
      mouseClicks: index == 0 ? 8 : 1,
      mouseMovePx: 120 + index,
      scrollPx: index == 0 ? 240 : 0,
    );
  });
  final sessions = <WorkSession>[
    WorkSession(
      startTime: base,
      endTime: base.add(const Duration(minutes: 25)),
      label: 'Alpha coding focus',
      processName: 'Code.exe',
      category: 'coding',
      records: <ActivityRecord>[records.first],
      durationMinutes: 25,
      keyCount: 80,
      mouseClicks: 8,
      mouseMovePx: 120,
      scrollPx: 240,
      processNames: const <String>['Code.exe'],
      categories: const <String>['coding'],
      interruptionCount: 0,
    ),
    for (var i = 1; i < records.length; i += 1)
      WorkSession(
        startTime: records[i].startTime,
        endTime: records[i].endTime ?? records[i].startTime,
        label: 'Session ${i + 1}',
        processName: records[i].processName,
        category: records[i].category,
        records: <ActivityRecord>[records[i]],
        durationMinutes: records[i].durationMinutes,
        keyCount: records[i].keyCount,
        mouseClicks: records[i].mouseClicks,
        mouseMovePx: records[i].mouseMovePx,
        scrollPx: records[i].scrollPx,
        processNames: <String>[records[i].processName ?? 'Unknown'],
        categories: <String>[records[i].category ?? 'uncategorized'],
        interruptionCount: 0,
      ),
  ];
  final logs = <ActivityLogEntry>[
    ActivityLogEntry(
      timestamp: base.add(const Duration(minutes: 2)),
      type: ActivityLogEntryType.sample,
      recordId: 1,
      processName: 'Code.exe',
      windowTitle: 'Alpha coding focus',
      category: 'coding',
      label: 'Needle log entry',
      durationMinutes: 5,
      keyCount: 12,
      mouseClicks: 1,
      mouseMovePx: 100,
      scrollPx: 0,
      keySequence: 'Ctrl+S',
      note: 'needle details',
    ),
    ActivityLogEntry(
      timestamp: base.add(const Duration(minutes: 6)),
      type: ActivityLogEntryType.sessionOpen,
      recordId: 1,
      processName: 'Code.exe',
      windowTitle: 'Session window',
      category: 'coding',
      label: 'Session opened',
      durationMinutes: 0,
      keyCount: 1,
    ),
    ActivityLogEntry(
      timestamp: base.add(const Duration(minutes: 38)),
      type: ActivityLogEntryType.sample,
      recordId: 2,
      processName: 'Browser.exe',
      windowTitle: 'Design research',
      category: 'research',
      label: 'Browser research log',
      durationMinutes: 4,
      keyCount: 5,
      mouseClicks: 3,
      scrollPx: 400,
    ),
    for (var i = 3; i < 30; i += 1)
      ActivityLogEntry(
        timestamp: base.add(Duration(minutes: i * 4)),
        type: ActivityLogEntryType.sample,
        recordId: i + 1,
        processName: 'Code.exe',
        windowTitle: 'Code file $i',
        category: 'coding',
        label: 'Sample log $i',
        durationMinutes: 3,
        keyCount: 3 + i,
        mouseClicks: 1,
      ),
    ActivityLogEntry(
      timestamp: base.add(const Duration(hours: 6, minutes: 10)),
      type: ActivityLogEntryType.snapshot,
      recordId: 13,
      processName: 'Notes.exe',
      windowTitle: 'Passive reading',
      category: 'admin',
      label: 'No-input passive log',
      durationMinutes: 5,
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

TrackerRangeAnalysisSnapshot _edgeSnapshot(ActivityHeatmapBucket bucket) {
  final base = bucket.start.add(const Duration(hours: 9));
  final records = <ActivityRecord>[
    _record(
      id: 200,
      start: base,
      durationMinutes: 10,
      processName: 'Edge.exe',
      windowTitle: 'Different detail title',
      category: 'edge',
      keyCount: 8,
      mouseClicks: 1,
      mouseMovePx: 20,
      scrollPx: 0,
    ),
  ];
  final sessions = <WorkSession>[
    for (var day = 0; day < 7; day += 1)
      WorkSession(
        startTime: bucket.start
            .subtract(Duration(days: day))
            .add(const Duration(hours: 9)),
        endTime: bucket.start
            .subtract(Duration(days: day))
            .add(const Duration(hours: 9, minutes: 10)),
        label: 'Multi day session $day',
        processName: 'Edge.exe',
        category: 'edge',
        records: day == 0 ? records : const <ActivityRecord>[],
        durationMinutes: 10,
        keyCount: day == 0 ? 8 : 1,
        mouseClicks: day == 0 ? 1 : 0,
        mouseMovePx: day == 0 ? 20 : 0,
        scrollPx: 0,
        processNames: const <String>['Edge.exe'],
        categories: const <String>['edge'],
        interruptionCount: 0,
      ),
  ];
  final logs = <ActivityLogEntry>[
    ActivityLogEntry(
      timestamp: base.add(const Duration(minutes: 4)),
      type: ActivityLogEntryType.sample,
      recordId: 200,
      processName: 'Edge.exe',
      windowTitle: 'Different detail title',
      className: 'FallbackClass',
      category: 'edge',
      label: 'Detail row label',
      durationMinutes: 10,
      keyCount: 8,
      mouseClicks: 1,
      mouseMovePx: 20,
      isFullscreen: true,
      note: 'fallback note',
    ),
    ActivityLogEntry(
      timestamp: base.add(const Duration(minutes: 3)),
      type: ActivityLogEntryType.sample,
      processName: 'Edge.exe',
      windowTitle: 'Window title fallback only',
      durationMinutes: 1,
    ),
    ActivityLogEntry(
      timestamp: base.add(const Duration(minutes: 2)),
      type: ActivityLogEntryType.sessionUpdate,
      processName: 'ProcessOnly.exe',
      durationMinutes: 1,
      keyCount: 1,
    ),
    ActivityLogEntry(
      timestamp: base.add(const Duration(minutes: 1)),
      type: ActivityLogEntryType.snapshot,
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

ActivityRecord _record({
  required int id,
  required DateTime start,
  required int durationMinutes,
  required String processName,
  required String windowTitle,
  required String category,
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
    manualLabel: windowTitle,
    processName: processName,
    windowTitle: windowTitle,
    category: category,
    isAuto: true,
    source: 'range-analysis-test',
  );
}

Map<String, dynamic> _emptyDaySummary() {
  return <String, dynamic>{
    'insights': <String, Object?>{'totalMinutes': 0},
    'previewRecords': <Map<String, Object?>>[],
    'sessions': <Map<String, Object?>>[],
  };
}

class _FakeTrackerServiceNotifier extends TrackerServiceNotifier {
  var refreshCalls = 0;

  @override
  TrackerState build() {
    return const TrackerState();
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
}
