import 'dart:async';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/tracker/data/tracker_repository.dart';
import 'package:flowplanv2/features/tracker/models/activity_insights.dart';
import 'package:flowplanv2/features/tracker/models/activity_log_entry.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
import 'package:flowplanv2/features/tracker/models/input_heatmap_summary.dart';
import 'package:flowplanv2/features/tracker/models/work_session.dart';
import 'package:flowplanv2/features/tracker/presentation/activity_review_page.dart';
import 'package:flowplanv2/features/tracker/presentation/input_heatmap_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_input_history_page.dart';
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
import 'package:go_router/go_router.dart';

import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/tracking_store_test_double.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('input heatmap refreshes filters, ranges, export and errors',
      (tester) async {
    final queries = <InputEventQuery>[];
    var processCalls = 0;
    var failProcessOptions = false;
    var failSummary = false;
    Completer<InputHeatmapSummary>? delayedSummary;

    await _pumpPlainPage(
      tester,
      size: const Size(1200, 1100),
      overrides: <Override>[
        inputEventProcessOptionsProvider.overrideWith((ref) async {
          processCalls += 1;
          if (failProcessOptions) {
            throw StateError('process options gap');
          }
          return const <String>['Code.exe', 'Browser.exe'];
        }),
        inputHeatmapSummaryProvider.overrideWith((ref, query) async {
          queries.add(query);
          final pending = delayedSummary;
          if (pending != null) {
            delayedSummary = null;
            return pending.future;
          }
          if (failSummary) {
            throw StateError('summary range gap');
          }
          return _busyInputSummary(query);
        }),
      ],
      child: const InputHeatmapPage(),
    );

    await _pumpUntil(tester, () => queries.isNotEmpty && processCalls == 1);
    await _pumpUntilFound(tester, find.textContaining('Code.exe'));

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _stringDropdowns().first,
      valueFragment: 'Code.exe',
    );
    await _pumpUntil(tester, () => queries.last.processName == 'Code.exe');

    failProcessOptions = true;
    delayedSummary = Completer<InputHeatmapSummary>();
    final pendingSummary = delayedSummary!;
    await tester.tap(find.byTooltip('\u624b\u52a8\u5237\u65b0'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    pendingSummary.complete(_busyInputSummary(queries.last));
    await _pumpUntil(tester, () => processCalls >= 2);
    await _pumpUntilFound(tester, find.textContaining('process options gap'));
    ScaffoldMessenger.of(tester.element(find.byType(InputHeatmapPage)))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();

    failProcessOptions = false;
    failSummary = true;
    final callsBeforeRangeError = queries.length;
    await tester.tap(
      find.widgetWithText(ChoiceChip, '\u6700\u8fd1 30 \u5929'),
    );
    await _pumpUntil(
      tester,
      () =>
          queries.length > callsBeforeRangeError && queries.last.start != null,
    );
    await _pumpUntilFound(
      tester,
      find.textContaining('summary range gap'),
      maxPumps: 80,
    );
    expect(queries.last.start, isNotNull);
    expect(queries.last.processName, 'Code.exe');

    failSummary = false;
    await tester
        .tap(find.widgetWithText(ChoiceChip, '\u5168\u90e8\u65f6\u95f4'));
    await _pumpUntil(tester, () => queries.last.start == null);
    await tester.tap(find.widgetWithText(ChoiceChip, '\u4eca\u5929'));
    await _pumpUntil(tester, () => queries.last.start != null);

    await tester.tap(find.widgetWithText(ChoiceChip, '\u81ea\u5b9a\u4e49'));
    await _pumpUntilFound(tester, find.byType(DateRangePickerDialog));
    await _tapAnyText(tester, const <String>['\u786e\u5b9a', 'SAVE', 'OK']);
    await _pumpUntil(
      tester,
      () => queries.last.start != null && queries.last.end != null,
    );
    expect(find.textContaining('\u5df2\u9009\u62e9'), findsWidgets);

    await tester.tap(find.byIcon(Icons.date_range_outlined).last);
    await _pumpUntilFound(tester, find.byType(DateRangePickerDialog));
    await _popRoute(tester);

    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();
    expect(find.byType(SnackBar), findsWidgets);
  });

  testWidgets('input heatmap range change keeps cold summary in loading state',
      (tester) async {
    var summaryCalls = 0;
    final firstSummary = Completer<InputHeatmapSummary>();

    await _pumpPlainPage(
      tester,
      size: const Size(1000, 900),
      overrides: <Override>[
        inputEventProcessOptionsProvider.overrideWith(
          (ref) async => const <String>['Code.exe'],
        ),
        inputHeatmapSummaryProvider.overrideWith((ref, query) async {
          summaryCalls += 1;
          if (summaryCalls == 1) {
            return firstSummary.future;
          }
          throw StateError('cold summary gap');
        }),
      ],
      child: const InputHeatmapPage(),
    );

    await _pumpUntil(tester, () => summaryCalls == 1);
    await tester.tap(
      find.widgetWithText(ChoiceChip, '\u6700\u8fd1 7 \u5929'),
    );
    await _pumpUntilFound(tester, find.textContaining('cold summary gap'));
    firstSummary.complete(
      InputHeatmapSummary.empty(
        InputEventQuery(start: _today(), end: _todayPlus(days: 1)),
      ),
    );
  });

  testWidgets(
      'input history retries, changes dates and paginates on compact UI',
      (tester) async {
    final store = TrackingStoreTestDouble(
      inputEventsResponseBuilder: (call) {
        return <String, dynamic>{
          'items': _inputHistoryItems(count: 80, offset: call.offset),
        };
      },
    )..inputEventsError = StateError('input page gap');

    await _pumpPlainPage(
      tester,
      size: const Size(520, 840),
      overrides: <Override>[
        trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      ],
      child: const TrackerInputHistoryPage(),
    );

    await _pumpUntilFound(tester, find.textContaining('input page gap'));
    store.inputEventsError = null;
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.refresh).first);
    await _pumpUntil(tester, () => store.inputEventsCalls.length >= 2);
    await _pumpUntilFound(tester, find.textContaining('Code.exe'));

    await tester.ensureVisible(
      find.byKey(AppKeys.trackerInputHistoryNextPageButton),
    );
    await tester.tap(find.byKey(AppKeys.trackerInputHistoryNextPageButton));
    await _pumpUntil(tester, () => store.inputEventsCalls.last.offset == 80);
    await _pumpUntilFound(tester, find.text('\u7b2c 2 \u9875'));

    await _pumpUntilFound(
      tester,
      find.byKey(AppKeys.trackerInputHistoryPreviousPageButton),
    );
    await tester.ensureVisible(
      find.byKey(AppKeys.trackerInputHistoryPreviousPageButton),
    );
    await tester.tap(find.text('\u4e0a\u4e00\u9875'));
    await _pumpUntilFound(tester, find.text('\u7b2c 1 \u9875'));

    final callsBeforeNextDay = store.inputEventsCalls.length;
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await _pumpUntil(
      tester,
      () => store.inputEventsCalls.length > callsBeforeNextDay,
    );

    await tester.tap(find.byIcon(Icons.today_outlined));
    await _pumpUntilFound(
      tester,
      find.textContaining(
          '${_formatDate(DateTime.now())} \u8f93\u5165\u4e8b\u4ef6'),
    );

    await tester.tap(find.text(_formatDate(DateTime.now())).first);
    await _pumpUntilFound(tester, find.byType(DatePickerDialog));
    await _popRoute(tester);

    await tester.tap(find.text(_formatDate(DateTime.now())).first);
    await _pumpUntilFound(tester, find.byType(DatePickerDialog));
    await _tapAnyText(tester, const <String>['OK', '\u786e\u5b9a']);
    await tester.pump();
  });

  testWidgets('input history empty compact page renders no event summary',
      (tester) async {
    final store = TrackingStoreTestDouble(
      inputEventsResponseBuilder: (_) => <String, dynamic>{
        'items': <Map<String, Object?>>[],
      },
    );

    await _pumpPlainPage(
      tester,
      size: const Size(500, 760),
      overrides: <Override>[
        trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      ],
      child: const TrackerInputHistoryPage(),
    );

    await _pumpUntil(tester, () => store.inputEventsCalls.isNotEmpty);
    expect(find.byType(TrackerInputHistoryPage), findsOneWidget);
  });

  testWidgets('day details history filters navigate and bind records',
      (tester) async {
    final bucket =
        _analysisBucket('details', _today().add(const Duration(hours: 9)));
    final selectedHeatmapBucket =
        StateProvider<ActivityHeatmapBucket?>((ref) => bucket);
    final selectedAnalysisBucket =
        StateProvider<ActivityHeatmapBucket?>((ref) => bucket);
    final task = _task(7, 'Tracker linked task');
    final tasks = <TaskItem>[
      task,
      _task(8, 'Completed task', status: 'COMPLETED'),
      _task(9, 'No anchor beta', includeDefaultDates: false),
      _task(10, 'No anchor alpha', includeDefaultDates: false),
      _task(
        11,
        'Tomorrow task',
        dtstart: _today().add(const Duration(days: 1)),
      ),
    ];
    final record = _record(
      id: 7,
      start: _today().add(const Duration(hours: 9)),
      durationMinutes: 35,
      processName: 'Code.exe',
      windowTitle: 'Tracker details window',
      category: 'coding',
      linkedTaskId: 7,
    );
    final session = WorkSession(
      startTime: record.startTime,
      endTime: record.endTime!,
      label: 'Tracker details session',
      processName: 'Code.exe',
      category: 'coding',
      records: <ActivityRecord>[record],
      durationMinutes: 35,
      keyCount: 14,
      mouseClicks: 3,
      mouseMovePx: 180,
      scrollPx: 240,
      processNames: const <String>['Code.exe'],
      categories: const <String>['coding'],
      interruptionCount: 0,
    );

    await _pumpRouter(
      tester,
      size: const Size(480, 1050),
      initialLocation: AppRoutes.trackerDayDetails,
      routes: <RouteBase>[
        GoRoute(
          path: AppRoutes.trackerDayDetails,
          builder: (context, state) => const TrackerDayDetailsPage(),
        ),
        GoRoute(
          path: AppRoutes.tracker,
          builder: (context, state) => const Text('tracker-route'),
        ),
        GoRoute(
          path: AppRoutes.trackerInputHistory,
          builder: (context, state) => const Text('input-history-route'),
        ),
        GoRoute(
          path: AppRoutes.trackerLogHistory,
          builder: (context, state) => const Text('log-history-route'),
        ),
        GoRoute(
          path: '/task/:taskId',
          builder: (context, state) =>
              Text('task-route-${state.pathParameters['taskId']}'),
        ),
      ],
      overrides: <Override>[
        trackerHistorySelectedHeatmapBucketProvider.overrideWith(
          (ref) => ref.watch(selectedHeatmapBucket),
        ),
        trackerHistorySelectedAnalysisBucketProvider.overrideWith(
          (ref) => ref.watch(selectedAnalysisBucket),
        ),
        activityRecordsForDateProvider.overrideWith(
          (ref) async => <ActivityRecord>[record],
        ),
        workSessionsForDateProvider.overrideWith(
          (ref) => <WorkSession>[session],
        ),
        trackerHistoryFilterOptionsProvider.overrideWith(
          (ref) => const TrackerHistoryFilterOptions(
            processOptions: <String>['Code.exe', 'Browser.exe'],
            categoryOptions: <String>['coding', 'research'],
          ),
        ),
        trackingUploadDiagnosticsProvider.overrideWith((ref) async {
          return <String, Object?>{
            'lastActivityRecordId': '41',
            'lastInputEventId': 42.7,
            'lastRawLogId': '43',
            'pendingActivityRecords': '2',
            'pendingInputEvents': 3.2,
            'pendingRawLogs': '4',
            'lastCompletedAt': '2026-06-10T10:00:00Z',
            'lastError': 'upload diagnostics gap',
          };
        }),
        allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
        allEventCalendarsProvider.overrideWith(
          (ref) => Stream.value(const <EventCalendar>[]),
        ),
        allTaskListsProvider.overrideWith(
          (ref) => Stream.value(const <TaskList>[]),
        ),
      ],
    );

    await _pumpUntilFound(tester, find.byType(TrackerDayDetailsPage));
    await tester.tap(find.byIcon(Icons.chevron_left).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.chevron_right).first);
    await tester.pump();
    await tester
        .tap(find.widgetWithText(TextButton, '\u56de\u5230\u4eca\u5929'));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TrackerDayDetailsPage)),
    );
    container.read(trackerHistorySearchQueryProvider.notifier).state =
        'external';
    await tester.pump();
    await tester.tap(find.byTooltip('\u6e05\u7a7a\u641c\u7d22'));
    await tester.pump();

    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _stringDropdowns().first,
      valueFragment: 'Code.exe',
    );
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _stringDropdowns().at(1),
      valueFragment: 'coding',
    );
    await chooseDropdownMenuItemByValue(
      tester,
      dropdown: _intDropdowns().first,
      valueFragment: '7',
    );

    expect(find.text('\u8054\u52a8\u5e94\u7528\uff1aCode.exe'), findsOneWidget);
    expect(
      find.widgetWithText(
        FilledButton,
        '\u8fd4\u56de\u67e5\u770b\u5df2\u8054\u52a8\u5206\u6790',
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.widgetWithText(
          OutlinedButton, '\u67e5\u770b\u5b8c\u6574\u8f93\u5165\u5386\u53f2'),
    );
    await _pumpUntilFound(tester, find.text('input-history-route'));
    await _popRoute(tester);
    await _pumpUntilFound(tester, find.byType(TrackerDayDetailsPage));

    await tester.tap(
      find.widgetWithText(
          OutlinedButton, '\u67e5\u770b\u5386\u53f2\u6d3b\u52a8\u8bb0\u5f55'),
    );
    await _pumpUntilFound(tester, find.text('log-history-route'));
    await _popRoute(tester);
    await _pumpUntilFound(tester, find.byType(TrackerDayDetailsPage));

    await tester.tap(
        find.byTooltip('\u67e5\u770b\u5386\u53f2\u6d3b\u52a8\u8bb0\u5f55'));
    await _pumpUntilFound(tester, find.text('log-history-route'));
    await _popRoute(tester);
    await _pumpUntilFound(tester, find.byType(TrackerDayDetailsPage));

    await tester.ensureVisible(find.byType(ExpansionTile).first);
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();

    await tester
        .tap(find.widgetWithText(TextButton, '\u6253\u5f00\u4efb\u52a1').last);
    await _pumpUntilFound(tester, find.text('task-route-7'));
    await _popRoute(tester);

    await tester.ensureVisible(
      find.widgetWithText(TextButton, '\u6539\u7ed1\u4efb\u52a1').last,
    );
    await tester.tap(
      find.widgetWithText(TextButton, '\u6539\u7ed1\u4efb\u52a1').last,
    );
    await tester.pumpAndSettle();
    await _popRoute(tester);

    await tester.ensureVisible(
      find.widgetWithText(
        FilledButton,
        '\u8fd4\u56de\u67e5\u770b\u5df2\u8054\u52a8\u5206\u6790',
      ),
    );
    await tester.tap(
      find.widgetWithText(
        FilledButton,
        '\u8fd4\u56de\u67e5\u770b\u5df2\u8054\u52a8\u5206\u6790',
      ),
    );
    await _pumpUntilFound(tester, find.text('tracker-route'));
  });

  testWidgets('tracker page current session and range panel edge UI render',
      (tester) async {
    final bucketA = _analysisBucket('alpha', DateTime(2026, 6, 8, 9));
    final bucketB = _analysisBucket('beta', DateTime(2026, 6, 8, 10));
    final selectedAnalysisBucket =
        StateProvider<ActivityHeatmapBucket?>((ref) => bucketA);
    final trackerNotifier = _FakeTrackerServiceNotifier(
      initialState: _trackerStateWithTelemetry(),
    );

    await _pumpPlainPage(
      tester,
      size: const Size(1500, 1800),
      overrides: <Override>[
        trackerServiceNotifierProvider.overrideWith(() => trackerNotifier),
        sequenceRecordingProvider.overrideWith((ref) => true),
        trackerHistorySelectedAnalysisBucketProvider.overrideWith(
          (ref) => ref.watch(selectedAnalysisBucket),
        ),
        activityHeatmapSeriesProvider.overrideWith(
          (ref) async =>
              _heatmapSeries(<ActivityHeatmapBucket>[bucketA, bucketB]),
        ),
        trackerRangeAnalysisProvider.overrideWith((ref) {
          final bucket = ref.watch(selectedAnalysisBucket);
          return AsyncData<TrackerRangeAnalysisSnapshot?>(
            bucket == null ? null : _rangeSnapshot(bucket),
          );
        }),
        activityDaySummaryProvider.overrideWith((ref) async => _daySummary()),
        inputHeatmapSummaryProvider.overrideWith(
          (ref, query) async => _busyInputSummaryWithoutTopKeys(query),
        ),
        trackingUploadServiceProvider.overrideWith(
          (ref) async => _FakeTrackingUploadService(),
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
      child: const TrackerPage(),
    );

    await _pumpUntilFound(tester, find.textContaining('tracker rawinput gap'));
    await _pumpUntilFound(tester, find.text('Alpha multi process'));

    await tester.ensureVisible(
      find.widgetWithText(ChoiceChip, '\u8f93\u5165\u4f18\u5148'),
    );
    await tester
        .tap(find.widgetWithText(ChoiceChip, '\u8f93\u5165\u4f18\u5148'));
    await tester.pump();

    await tester.ensureVisible(
      find.widgetWithText(
          FilterChip, '\u4ec5\u770b\u6709\u8f93\u5165\u6d3b\u52a8'),
    );
    await tester.tap(
      find.widgetWithText(
          FilterChip, '\u4ec5\u770b\u6709\u8f93\u5165\u6d3b\u52a8'),
    );
    await tester.pump();

    await tester.ensureVisible(
      find.widgetWithText(TextButton, '\u663e\u793a\u5168\u90e8').first,
    );
    await tester.tap(
      find.widgetWithText(TextButton, '\u663e\u793a\u5168\u90e8').first,
    );
    await tester.pump();

    await tester.ensureVisible(find.byType(TextField).last);
    await tester.enterText(find.byType(TextField).last, 'needle');
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TrackerPage)),
    );
    container.read(selectedAnalysisBucket.notifier).state = bucketB;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.textContaining('beta'), findsWidgets);

    await _pumpUntilFound(
      tester,
      find.text(
          '\u8fd9\u4e00\u5929\u8fd8\u6ca1\u6709\u952e\u76d8\u8f93\u5165\uff0c\u6682\u65f6\u65e0\u6cd5\u751f\u6210\u9ad8\u9891\u6309\u952e\u3002'),
    );

    final hourChip = find.descendant(
      of: find.byType(ActionChip),
      matching: find.textContaining('09:00'),
    );
    await tester.ensureVisible(hourChip.first);
    await tester.tap(hourChip.first);
    await tester.pump();
    expect(find.text('\u8054\u52a8\u65f6\u6bb5\uff1a09:00'), findsWidgets);
  });

  testWidgets('activity review parses edge server data and closes with go',
      (tester) async {
    final store = _ActivityReviewStore();
    final task = _task(7, 'Activity task');

    await _pumpActivityReviewRouter(
      tester,
      initialLocation: AppRoutes.activityReview,
      store: store,
      tasks: <TaskItem>[task],
    );

    await _pumpUntil(tester, () => store.segmentCalls == 1);
    await _pumpUntilFound(tester, find.textContaining('Code.exe'));

    await tester.tap(find.byIcon(Icons.auto_fix_high_outlined).first);
    await _pumpUntil(tester, () => store.buildSegmentsCalls == 1);
    await _pumpUntilFound(tester, find.byIcon(Icons.check_circle_outline));

    await tester.tap(find.byIcon(Icons.check_circle_outline).first);
    await _pumpUntilFound(
        tester, find.byKey(AppKeys.trackerReviewConfirmButton));
    await tester.tap(find.byKey(AppKeys.trackerReviewConfirmButton));
    await _pumpUntil(tester, () => store.confirmedSegments.isNotEmpty);

    await tester.tap(find.byIcon(Icons.close));
    await _pumpUntilFound(tester, find.text('tracker-review-target'));
  });

  testWidgets('activity review close pops when opened from a host route',
      (tester) async {
    final store = _ActivityReviewStore();

    await _pumpActivityReviewRouter(
      tester,
      initialLocation: '/host',
      store: store,
      tasks: const <TaskItem>[],
      includeHost: true,
    );

    await tester.tap(find.text('open-review'));
    await _pumpUntilFound(tester, find.byType(ActivityReviewPage));
    await tester.tap(find.byIcon(Icons.close));
    await _pumpUntilFound(tester, find.text('host-route'));
  });
}

Future<void> _pumpPlainPage(
  WidgetTester tester, {
  required Widget child,
  required List<Override> overrides,
  Size size = const Size(1000, 900),
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
    size: size,
    overrides: overrides,
    child: MaterialApp(home: child),
  );
  await tester.pump();
}

Future<void> _pumpRouter(
  WidgetTester tester, {
  required String initialLocation,
  required List<RouteBase> routes,
  required List<Override> overrides,
  Size size = const Size(1000, 900),
}) async {
  final db = createTestDatabase();
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: routes,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpFrames(tester, 4);
    router.dispose();
    await db.close();
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: size,
    overrides: overrides,
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
}

Future<void> _pumpActivityReviewRouter(
  WidgetTester tester, {
  required String initialLocation,
  required _ActivityReviewStore store,
  required List<TaskItem> tasks,
  bool includeHost = false,
}) async {
  await _pumpRouter(
    tester,
    initialLocation: initialLocation,
    size: const Size(900, 1100),
    routes: <RouteBase>[
      if (includeHost)
        GoRoute(
          path: '/host',
          builder: (context, state) => Center(
            child: Column(
              children: [
                const Text('host-route'),
                TextButton(
                  onPressed: () => context.push(AppRoutes.activityReview),
                  child: const Text('open-review'),
                ),
              ],
            ),
          ),
        ),
      GoRoute(
        path: AppRoutes.activityReview,
        builder: (context, state) => const ActivityReviewPage(),
      ),
      GoRoute(
        path: AppRoutes.tracker,
        builder: (context, state) => const Text('tracker-review-target'),
      ),
    ],
    overrides: <Override>[
      trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
    ],
  );
}

Finder _stringDropdowns() {
  return find.byWidgetPredicate(
    (widget) => widget is DropdownButtonFormField<String?>,
  );
}

Finder _intDropdowns() {
  return find.byWidgetPredicate(
    (widget) => widget is DropdownButtonFormField<int?>,
  );
}

Future<void> _tapAnyText(WidgetTester tester, List<String> labels) async {
  for (final label in labels) {
    final finder = find.text(label);
    if (finder.evaluate().isNotEmpty) {
      await tester.tap(finder.last);
      await tester.pump();
      return;
    }
  }
  expect(
    labels.any((label) => find.text(label).evaluate().isNotEmpty),
    isTrue,
  );
}

Future<void> _popRoute(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
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
  bool Function() predicate, {
  int maxPumps = 40,
}) async {
  for (var i = 0; i < maxPumps; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
    if (predicate()) {
      return;
    }
  }
  expect(
    predicate(),
    isTrue,
    reason: 'Expected condition to become true within bounded pumps.',
  );
}

Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i += 1) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _todayPlus({required int days}) => _today().add(Duration(days: days));

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

InputHeatmapSummary _busyInputSummary(InputEventQuery query) {
  final hours = List<InputHourDistributionBucket>.generate(24, (hour) {
    final active = hour == 9 || hour == 10 || hour == 14;
    return InputHourDistributionBucket(
      hour: hour,
      totalEvents: active ? (hour == 9 ? 42 : 30) : 0,
      keyEvents: active ? 12 : 0,
      mouseButtonEvents: active ? 4 : 0,
      wheelEvents: active ? 3 : 0,
      mouseMoveEvents: active ? 6 : 0,
      moveDistance: active ? 300 + hour : 0,
      activeMinutes: active ? 18 : 0,
      intensityScore: hour == 9 ? 90 : (active ? 80 : 0),
    );
  });
  return InputHeatmapSummary(
    query: query,
    totalEventCount: 120,
    activeMinuteCount: 54,
    keyboardEventCount: 48,
    mouseButtonEventCount: 14,
    wheelEventCount: 9,
    mouseMoveEventCount: 18,
    mouseMoveDistance: 1200,
    keyCounts: const <int, int>{65: 24, 66: 12},
    mouseCounts: const <String, int>{'left': 8, 'right': 3},
    topKeys: const <InputKeyStat>[
      InputKeyStat(keyCode: 65, label: 'A', count: 24, share: 0.5),
    ],
    processIntensities: const <InputProcessIntensity>[
      InputProcessIntensity(
        processName: 'Code.exe',
        totalEvents: 80,
        keyEvents: 40,
        mouseButtonEvents: 10,
        wheelEvents: 8,
        mouseMoveEvents: 12,
        moveDistance: 900,
        activeMinutes: 40,
        intensityScore: 92,
      ),
    ],
    hourlyDistribution: hours,
  );
}

InputHeatmapSummary _busyInputSummaryWithoutTopKeys(InputEventQuery query) {
  final summary = _busyInputSummary(query);
  return InputHeatmapSummary(
    query: summary.query,
    totalEventCount: summary.totalEventCount,
    activeMinuteCount: summary.activeMinuteCount,
    keyboardEventCount: 0,
    mouseButtonEventCount: summary.mouseButtonEventCount,
    wheelEventCount: summary.wheelEventCount,
    mouseMoveEventCount: summary.mouseMoveEventCount,
    mouseMoveDistance: summary.mouseMoveDistance,
    keyCounts: const <int, int>{},
    mouseCounts: summary.mouseCounts,
    topKeys: const <InputKeyStat>[],
    processIntensities: summary.processIntensities,
    hourlyDistribution: summary.hourlyDistribution,
  );
}

List<Map<String, Object?>> _inputHistoryItems({
  required int count,
  required int offset,
}) {
  final base = DateTime(2026, 6, 10, 9);
  return List<Map<String, Object?>>.generate(count, (index) {
    final absolute = offset + index;
    final timestamp = base.add(Duration(seconds: absolute));
    if (absolute == 0) {
      return <String, Object?>{
        'objectType': 'tracked_input_event',
        'occurredAt': timestamp.toIso8601String(),
        'metricCount': '3',
        'payload': <Object, Object?>{
          'timestamp': timestamp.toIso8601String(),
          'kind': 'mouse_move',
          'sequenceId': '11',
          'eventCount': '3',
          'processName': 'Code.exe',
          'deltaX': '4',
          'deltaY': '5',
          'moveDistance': '30',
          'keyCode': '65',
        },
      };
    }
    if (absolute == 1) {
      return <String, Object?>{
        'serverId': 'input-$absolute',
        'objectType': 'tracked_input_event',
        'occurredAt': timestamp.toIso8601String(),
        'payload': <String, Object?>{
          'eventUid': 'input-$absolute',
          'timestamp': timestamp.toIso8601String(),
          'kind': 'key_down',
          'sequence_id': 12.2,
          'eventCount': 1,
          'processName': 'Code.exe',
          'activityLabel': 'Key typing $absolute',
          'keyCode': 66.7,
          'keyLabel': 'B',
          'tokenText': 'b',
        },
      };
    }
    return <String, Object?>{
      'serverId': 'input-$absolute',
      'objectType': 'tracked_input_event',
      'occurredAt': timestamp.toIso8601String(),
      'metricCount': 1,
      'payload': <String, Object?>{
        'eventUid': 'input-$absolute',
        'sequenceId': absolute + 20,
        'timestamp': timestamp.toIso8601String(),
        'kind': absolute.isEven ? 'mouse_wheel' : 'key_down',
        'eventCount': 1,
        'processName': absolute.isEven ? 'Browser.exe' : 'Code.exe',
        'windowTitle': 'Input window $absolute',
        'category': absolute.isEven ? 'research' : 'coding',
        'activityLabel': 'Input event $absolute',
        if (absolute.isEven) ...<String, Object?>{
          'wheelDelta': -120,
          'mouseButton': 'wheel',
        } else ...<String, Object?>{
          'keyCode': 70,
          'keyLabel': 'F',
        },
      },
    };
  });
}

ActivityHeatmapBucket _analysisBucket(String label, DateTime start) {
  return ActivityHeatmapBucket(
    start: start,
    end: start.add(const Duration(hours: 1)),
    shortLabel: label,
    longLabel: 'bucket-$label',
    completedCount: 3,
    totalMinutes: 60,
  );
}

ActivityHeatmapSeries _heatmapSeries(List<ActivityHeatmapBucket> buckets) {
  return ActivityHeatmapSeries(
    scale: ActivityHeatmapScale.hour,
    anchorDate: buckets.first.start,
    title: 'heatmap',
    subtitle: 'test buckets',
    buckets: buckets,
    maxMinutes: 60,
    historySummary: ActivityHistorySummary(
      firstRecordAt: buckets.first.start,
      lastRecordAt: buckets.last.end,
      totalRecords: buckets.length,
    ),
  );
}

TrackerRangeAnalysisSnapshot _rangeSnapshot(ActivityHeatmapBucket bucket) {
  final base = bucket.start;
  final first = _record(
    id: 101,
    start: base,
    durationMinutes: 35,
    processName: 'Code.exe',
    windowTitle: 'Alpha code',
    category: 'coding',
  );
  final second = _record(
    id: 102,
    start: base.add(const Duration(minutes: 10)),
    durationMinutes: 20,
    processName: 'Browser.exe',
    windowTitle: 'Alpha browser',
    category: 'research',
  );
  final sessions = <WorkSession>[
    WorkSession(
      startTime: base,
      endTime: base.add(const Duration(minutes: 55)),
      label: 'Alpha multi process',
      processName: 'Code.exe',
      category: 'coding',
      records: <ActivityRecord>[first, second],
      durationMinutes: 55,
      keyCount: 20,
      mouseClicks: 6,
      mouseMovePx: 500,
      scrollPx: 300,
      processNames: const <String>['Code.exe', 'Browser.exe'],
      categories: const <String>['coding', 'research'],
      interruptionCount: 2,
      rawRecordCountOverride: 4,
    ),
    WorkSession(
      startTime: base.add(const Duration(minutes: 5)),
      endTime: base.add(const Duration(minutes: 25)),
      label: 'Input tie session',
      processName: 'Notes.exe',
      category: 'admin',
      records: <ActivityRecord>[
        _record(
          id: 103,
          start: base.add(const Duration(minutes: 5)),
          durationMinutes: 20,
          processName: 'Notes.exe',
          windowTitle: 'Tie notes',
          category: 'admin',
        ),
      ],
      durationMinutes: 20,
      keyCount: 20,
      mouseClicks: 6,
      mouseMovePx: 500,
      scrollPx: 300,
      processNames: const <String>['Notes.exe'],
      categories: const <String>['admin'],
      interruptionCount: 0,
    ),
  ];
  final logs = <ActivityLogEntry>[
    for (var i = 0; i < 31; i += 1)
      ActivityLogEntry(
        timestamp: base.add(Duration(minutes: i)),
        type: i == 1
            ? ActivityLogEntryType.sessionOpen
            : ActivityLogEntryType.sample,
        recordId: 100 + i,
        processName: i.isEven ? 'Code.exe' : 'Browser.exe',
        windowTitle: i == 4 ? 'needle window' : 'Log window $i',
        category: i.isEven ? 'coding' : 'research',
        label: i == 4 ? 'needle range log' : 'Range log $i',
        durationMinutes: 2,
        keyCount: i + 1,
        mouseClicks: 1,
        mouseMovePx: 10,
        scrollPx: 5,
        keySequence: i == 4 ? 'Ctrl+S' : null,
        note: i == 4 ? 'needle note' : null,
      ),
  ];
  final records = sessions.expand((session) => session.records).toList();
  return TrackerRangeAnalysisSnapshot(
    bucket: bucket,
    records: records,
    logEntries: logs,
    insights: ActivityInsights.fromRecords(records),
    sessions: sessions,
  );
}

Map<String, dynamic> _daySummary() {
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
      'busiestRecords': <Map<String, Object?>>[],
    },
    'previewRecords': <Map<String, Object?>>[],
    'sessions': <Map<String, Object?>>[],
  };
}

ActivityRecord _record({
  required int id,
  required DateTime start,
  required int durationMinutes,
  required String processName,
  required String windowTitle,
  required String category,
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
    category: category,
    linkedTaskId: linkedTaskId,
    keyCount: 12,
    mouseClicks: 3,
    mouseMovePx: 180,
    scrollPx: 240,
    isAuto: true,
    source: 'tracker-aux-ui-gap3-worker',
  );
}

TaskItem _task(
  int id,
  String summary, {
  String status = 'NEEDS-ACTION',
  DateTime? dtstart,
  DateTime? due,
  DateTime? completed,
  bool includeDefaultDates = true,
}) {
  final day = DateTime.utc(2026, 6, 10);
  return TaskItem(
    id: id,
    uid: 'task-$id',
    dtstamp: day,
    summary: summary,
    priority: 0,
    status: status,
    percentComplete: 0,
    categories: '',
    durationMinutes: 0,
    isSplittable: false,
    priorityLocal: 0,
    isAutoScheduled: false,
    isLocked: false,
    reminderMinutesBefore: 0,
    dtstart: includeDefaultDates ? (dtstart ?? day) : dtstart,
    due: includeDefaultDates ? (due ?? day.add(const Duration(hours: 2))) : due,
    completed: completed,
  );
}

TrackerState _trackerStateWithTelemetry() {
  final now = DateTime.now();
  return TrackerState(
    isRunning: true,
    currentSnapshot: WindowSnapshot(
      processName: 'FlowPlanV2.exe',
      className: 'FlutterWindow',
      windowTitle: 'FlowPlanV2',
      isFullscreen: false,
      timestamp: now,
    ),
    displaySnapshot: WindowSnapshot(
      processName: 'Code.exe',
      className: 'Chrome_WidgetWin_1',
      windowTitle: 'tracker_aux_ui_gap3_worker_tracker_test.dart',
      isFullscreen: false,
      timestamp: now,
    ),
    displayClassification: const ActivityClassification(
      category: 'coding',
      label: 'VS Code',
      confidence: 0.92,
    ),
    displaySessionStart: now.subtract(const Duration(minutes: 24)),
    displayTelemetry: InputTelemetry(
      keyCount: 48,
      keyDistribution: const <int, int>{65: 12, 13: 4},
      keySequence: 'Ctrl+S\nEnter',
      clicks: const MouseClicks(
        left: 4,
        right: 2,
        middle: 1,
        xButton1: 2,
        xButton2: 1,
      ),
      scrollPx: 360,
      mouseMovePx: 7560,
      timestamp: now,
      inputEvents: const <RawInputEvent>[],
    ),
    isViewingExcludedApp: true,
    lastSampleAt: now,
    lastError: 'tracker rawinput gap',
  );
}

class _FakeTrackerServiceNotifier extends TrackerServiceNotifier {
  _FakeTrackerServiceNotifier({required this.initialState});

  final TrackerState initialState;
  var refreshCalls = 0;

  @override
  TrackerState build() => initialState;

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

class _FakeTrackingUploadService implements TrackingUploadService {
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
  Future<Map<String, Object?>> buildUploadDiagnostics() async {
    return <String, Object?>{
      'lastActivityRecordId': 0,
      'lastInputEventId': 0,
      'lastRawLogId': 0,
      'pendingActivityRecords': 0,
      'pendingInputEvents': 0,
      'pendingRawLogs': 0,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ActivityReviewStore extends TrackingStoreTestDouble {
  var segmentCalls = 0;
  var buildSegmentsCalls = 0;
  final confirmedSegments = <Map<String, Object?>>[];

  @override
  Future<Map<String, dynamic>> segments({
    DateTime? startAt,
    DateTime? endAt,
    String? status,
    int limit = 100,
    int offset = 0,
  }) async {
    segmentCalls += 1;
    return <String, dynamic>{
      'items': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'segment-edge',
          'segmentUid': 'segment-edge',
          'endAt': DateTime.utc(2026, 6, 10, 9, 25).toIso8601String(),
          'primaryProcessName': 'Code.exe',
          'primaryWindowTitle': 'Activity review edge',
          'category': 'coding',
          'confidence': '0.73',
          'status': 'candidate',
          'matchedTaskId': 'task-7',
          'evidence': <String, Object?>{
            'activityRecordCount': 1,
            'rawLogCount': 2,
            'inputEventCount': 3,
          },
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> buildSegments({
    required DateTime date,
    bool includeTrackedInputEvents = true,
    bool includeRawActivityLogs = true,
    bool includeActivityRecords = true,
  }) async {
    buildSegmentsCalls += 1;
    return <String, dynamic>{
      'rawCount': 5.4,
      'segmentsCreated': '2',
      'segmentsUpdated': 1,
      'lowConfidenceCount': '1',
    };
  }

  @override
  Future<Map<String, dynamic>> confirmSegment({
    required String segmentId,
    String? title,
    String? taskId,
    String? note,
  }) async {
    confirmedSegments.add(<String, Object?>{
      'segmentId': segmentId,
      'title': title,
      'taskId': taskId,
      'note': note,
    });
    return <String, dynamic>{'taskId': taskId};
  }
}
