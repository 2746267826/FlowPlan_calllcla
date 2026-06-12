import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/features/tracker/models/work_session.dart';
import 'package:flowplanv2/features/tracker/models/input_heatmap_summary.dart';
import 'package:flowplanv2/features/tracker/presentation/activity_review_page.dart';
import 'package:flowplanv2/features/tracker/presentation/input_heatmap_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_log_history_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_page.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/features/tracker/services/tracking_upload_service.dart';
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
  testWidgets(
      'heatmap analysis toggles range panel and drilldown reloads hours',
      (tester) async {
    final today = _today();
    final store = TrackingStoreTestDouble(
      trackingSummaryResponseBuilder: () => <String, dynamic>{
        'canonicalObjectCounts': <String, Object?>{'activity_record': 3},
        'latestReceivedAtByKind': <String, Object?>{
          'activity_record':
              today.add(const Duration(hours: 10)).toIso8601String(),
        },
      },
      activityHeatmapResponseBuilder: (call) {
        if (call.bucket == 'hour') {
          return <String, dynamic>{
            'buckets': <Map<String, Object?>>[
              <String, Object?>{
                'bucketStart':
                    today.add(const Duration(hours: 9)).toIso8601String(),
                'recordCount': 1,
                'totalMinutes': 40,
              },
            ],
          };
        }
        return <String, dynamic>{
          'buckets': <Map<String, Object?>>[
            <String, Object?>{
              'bucketStart': today.toIso8601String(),
              'recordCount': 2,
              'totalMinutes': 85,
            },
          ],
        };
      },
      rangeAnalysisResponseBuilder: (_) => _daySummary(
        records: <Map<String, Object?>>[
          _recordPayload(
            id: 'range-code',
            start: today.add(const Duration(hours: 9)),
            durationMinutes: 40,
            processName: 'Code.exe',
            title: 'Range analysis coding',
          ),
        ],
      ),
    );

    await _pumpTracker(tester, store: store, size: const Size(1400, 1200));
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 12);
    await pumpUntilFound(tester, find.text('${today.day}'), maxPumps: 20);

    await tester.tap(find.text('${today.day}').first);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '查看区间分析'));
    await pumpUntil(tester, () => store.rangeAnalysisCalls.isNotEmpty);

    expect(store.rangeAnalysisCalls.first.start, today);
    await pumpUntil(
      tester,
      () => find.textContaining('区间分析').evaluate().isNotEmpty,
    );
    expect(find.widgetWithText(FilledButton, '收起区间分析'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '关闭'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '收起区间分析'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, '关闭'), findsNothing);

    final previousRangeCalls = store.rangeAnalysisCalls.length;
    await tester.tap(find.widgetWithText(FilledButton, '查看区间分析'));
    await pumpUntil(
        tester, () => store.rangeAnalysisCalls.length > previousRangeCalls);
    await tester.tap(find.widgetWithText(OutlinedButton, '进入逐小时'));
    await pumpUntil(
        tester, () => store.activityHeatmapCalls.last.bucket == 'hour');

    expect(store.activityHeatmapCalls.last.start, today);
    expect(store.activityHeatmapCalls.last.end,
        today.add(const Duration(days: 1)));
    await pumpUntil(
      tester,
      () => find.widgetWithText(FilledButton, '按此小时筛选列表').evaluate().isNotEmpty,
    );
    expect(find.widgetWithText(TextButton, '关闭'), findsNothing);
  });

  testWidgets('task binding sheet shows linked task and redirects selections',
      (tester) async {
    final today = _today();
    final store = TrackingStoreTestDouble(
      activityDaySummaryResponseBuilder: (_) => _daySummary(
        records: <Map<String, Object?>>[
          _recordPayload(
            id: 'linked-record',
            start: today.add(const Duration(hours: 9)),
            durationMinutes: 50,
            processName: 'Code.exe',
            title: 'Linked tracker work',
            linkedTaskId: 7,
          ),
        ],
        sessions: <Map<String, Object?>>[
          <String, Object?>{
            'startTime': today.add(const Duration(hours: 9)).toIso8601String(),
            'endTime': today
                .add(const Duration(hours: 9, minutes: 50))
                .toIso8601String(),
            'label': 'Linked tracker work',
            'processName': 'Code.exe',
            'category': 'coding',
            'durationMinutes': 50,
            'keyCount': 18,
            'mouseClicks': 4,
            'mouseMovePx': 300,
            'scrollPx': 900,
            'processNames': <String>['Code.exe'],
            'categories': <String>['coding'],
            'rawRecordCount': 1,
          },
        ],
      ),
    );

    await _pumpDayDetails(
      tester,
      store: store,
      workSessions: <WorkSession>[
        WorkSession(
          startTime: today.add(const Duration(hours: 9)),
          endTime: today.add(const Duration(hours: 9, minutes: 50)),
          label: 'Linked tracker work',
          processName: 'Code.exe',
          category: 'coding',
          records: <ActivityRecord>[
            _activityRecord(
              id: 7,
              start: today.add(const Duration(hours: 9)),
              durationMinutes: 50,
              linkedTaskId: 7,
            ),
          ],
          durationMinutes: 50,
          keyCount: 18,
          mouseClicks: 4,
          mouseMovePx: 300,
          scrollPx: 900,
          processNames: const <String>['Code.exe'],
          categories: const <String>['coding'],
          interruptionCount: 0,
        ),
      ],
      tasks: <TaskItem>[
        _task(7, 'Ship tracker coverage'),
        _task(8, 'Review analytics timeline'),
      ],
      size: const Size(1400, 1200),
    );
    await pumpUntilFound(tester, find.text('调整任务关联'), maxPumps: 80);

    await tester.ensureVisible(find.text('调整任务关联').first);
    await tester.tap(find.text('调整任务关联').first);
    await tester.pumpAndSettle();

    expect(find.text('当前关联'), findsOneWidget);
    expect(find.text('任务：Ship tracker coverage'), findsWidgets);
    expect(find.text('取消关联'), findsOneWidget);
    expect(find.text('Review analytics timeline'), findsOneWidget);

    await tester.tap(find.text('Review analytics timeline'));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    await pumpUntilFound(tester, find.byType(ActivityReviewPage), maxPumps: 20);
  });

  testWidgets(
      'menu, keyboard shortcut, upload and summary errors surface state',
      (tester) async {
    final trackerNotifier = _FakeTrackerServiceNotifier(
      lastUploadError: 'offline queue failed',
    );
    final uploadService = _FakeTrackingUploadService(
      error: StateError('manual upload failed'),
    );

    await _pumpTracker(
      tester,
      trackerNotifier: trackerNotifier,
      uploadService: uploadService,
      daySummaryError: StateError('summary gap failure'),
      size: const Size(1400, 1000),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 12);
    await pumpUntilFound(tester, find.byIcon(Icons.keyboard_alt), maxPumps: 20);

    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    final uploadIcon =
        tester.widget<Icon>(find.byIcon(Icons.cloud_upload_outlined));
    expect(uploadIcon.color, Colors.orange);
    expect(
      find.textContaining('summary gap failure', findRichText: true),
      findsOneWidget,
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TrackerPage)),
    );
    expect(container.read(sequenceRecordingProvider), isTrue);

    await tester.tap(find.byIcon(Icons.keyboard_alt).first);
    await tester.pump();
    expect(find.byIcon(Icons.keyboard_alt_outlined), findsWidgets);

    await tester.tap(find.byIcon(Icons.cloud_upload_outlined));
    await pumpUntil(tester, () => uploadService.uploadCalls == 1);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);

    await tester.tap(find.byTooltip('键鼠热力图'));
    await pumpUntilFound(tester, find.byType(InputHeatmapPage), maxPumps: 20);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('查看历史活动记录').last);
    await pumpUntilFound(tester, find.byType(TrackerLogHistoryPage),
        maxPumps: 20);
  });
}

Future<void> _pumpDayDetails(
  WidgetTester tester, {
  required TrackingStoreTestDouble store,
  required List<WorkSession> workSessions,
  required List<TaskItem> tasks,
  Size size = const Size(1400, 1200),
}) async {
  final db = createTestDatabase();
  final router = GoRouter(
    initialLocation: AppRoutes.trackerDayDetails,
    routes: [
      GoRoute(
        path: AppRoutes.trackerDayDetails,
        builder: (context, state) => const TrackerDayDetailsPage(),
      ),
      GoRoute(
        path: AppRoutes.activityReview,
        builder: (context, state) => const ActivityReviewPage(),
      ),
      GoRoute(
        path: AppRoutes.tracker,
        builder: (context, state) => const TrackerPage(),
      ),
    ],
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    await db.close();
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: size,
    overrides: <Override>[
      trackerServiceNotifierProvider.overrideWith(
        () => _FakeTrackerServiceNotifier(),
      ),
      sequenceRecordingProvider.overrideWith((ref) => true),
      trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
      allEventCalendarsProvider.overrideWith(
        (ref) => Stream.value(const <EventCalendar>[]),
      ),
      allTaskListsProvider.overrideWith(
        (ref) => Stream.value(const <TaskList>[]),
      ),
      activityDaySummaryProvider.overrideWith(
        (ref) => store.activityDaySummary(date: _today()),
      ),
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
      trackingUploadServiceProvider.overrideWith(
        (ref) => Future<TrackingUploadService>.error(
          StateError('upload is not used by this harness'),
        ),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
  await tester.pump();
}

Future<void> _pumpTracker(
  WidgetTester tester, {
  String initialLocation = AppRoutes.tracker,
  TrackingStoreTestDouble? store,
  _FakeTrackerServiceNotifier? trackerNotifier,
  _FakeTrackingUploadService? uploadService,
  List<TaskItem> tasks = const <TaskItem>[],
  List<WorkSession>? workSessions,
  Object? daySummaryError,
  Size size = const Size(1400, 900),
}) async {
  final fakeStore = store ?? TrackingStoreTestDouble();
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
      if (daySummaryError != null)
        activityDaySummaryProvider.overrideWith((ref) async {
          throw daySummaryError;
        }),
      if (workSessions != null)
        workSessionsForDateProvider.overrideWith((ref) => workSessions),
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
        (ref) async =>
            uploadService ??
            _FakeTrackingUploadService(
              result: const TrackingUploadResult(
                uploadedBatches: 0,
                uploadedRecords: 0,
                details: <Map<String, Object?>>[],
              ),
            ),
      ),
    ],
  );
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 30,
}) async {
  for (var i = 0; i < maxPumps; i++) {
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
      'totalKeys': 18,
      'totalClicks': 4,
      'totalMovePx': 300,
      'totalScrollPx': 900,
      'productiveRecordCount': records.length,
      'sequenceRecordCount': 0,
      'topProcesses': <Map<String, Object?>>[
        <String, Object?>{
          'label': 'Code.exe',
          'minutes': totalMinutes,
          'keys': 18,
          'clicks': 4,
          'movePx': 300,
          'scrollPx': 900,
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
      'keyCount': 18,
      'mouseClicks': 4,
      'mouseMovePx': 300,
      'scrollPx': 900,
      'isAuto': true,
    },
  };
}

ActivityRecord _activityRecord({
  required int id,
  required DateTime start,
  required int durationMinutes,
  int? linkedTaskId,
}) {
  return ActivityRecord(
    id: id,
    startTime: start,
    endTime: start.add(Duration(minutes: durationMinutes)),
    durationMinutes: durationMinutes,
    manualLabel: 'Linked tracker work',
    processName: 'Code.exe',
    windowTitle: 'Linked tracker work',
    category: 'coding',
    linkedTaskId: linkedTaskId,
    keyCount: 18,
    mouseClicks: 4,
    mouseMovePx: 300,
    scrollPx: 900,
    isAuto: true,
    source: 'tracker-gap-worker-test',
  );
}

TaskItem _task(int id, String summary) {
  final day = _today();
  return TaskItem(
    id: id,
    uid: 'task-$id',
    dtstamp: day,
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

class _FakeTrackerServiceNotifier extends TrackerServiceNotifier {
  _FakeTrackerServiceNotifier({this.lastUploadError});

  final String? lastUploadError;

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
  Future<void> refreshNow() async {}

  @override
  DateTime? get lastAutoUploadAt => null;

  @override
  String? get lastAutoUploadError => lastUploadError;

  @override
  bool get isAutoUploading => false;
}

class _FakeTrackingUploadService implements TrackingUploadService {
  _FakeTrackingUploadService({this.result, this.error});

  final TrackingUploadResult? result;
  final Object? error;
  var uploadCalls = 0;

  @override
  Future<TrackingUploadResult> uploadPending({
    int limitPerKind = 2000,
    int chunkSize = 200,
  }) async {
    uploadCalls += 1;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return result ??
        const TrackingUploadResult(
          uploadedBatches: 0,
          uploadedRecords: 0,
          details: <Map<String, Object?>>[],
        );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
