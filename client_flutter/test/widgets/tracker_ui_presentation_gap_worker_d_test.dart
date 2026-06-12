import 'dart:io';

import 'package:drift/native.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/server_first/tracking_server_first_store.dart';
import 'package:flowplanv2/features/tracker/data/tracker_repository.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
import 'package:flowplanv2/features/tracker/models/input_heatmap_summary.dart';
import 'package:flowplanv2/features/tracker/models/work_session.dart';
import 'package:flowplanv2/features/tracker/presentation/activity_review_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_page.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/features/tracker/services/tracking_upload_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/user_workflow_harness.dart';

void main() {
  test('database folder platform helper starts explorer only on Windows',
      () async {
    final started = <Object?>[];

    await openTrackerDatabaseFolderForPlatform(
      folderPath: r'C:\flowplan-test\db',
      isWindows: true,
      startProcess: (executable, arguments) async {
        started.add(<Object?>[executable, arguments]);
        return Object();
      },
    );
    await openTrackerDatabaseFolderForPlatform(
      folderPath: '/tmp/flowplan-test/db',
      isWindows: false,
      startProcess: (executable, arguments) async {
        started.add(<Object?>[executable, arguments]);
        return Object();
      },
    );

    expect(started, [
      <Object?>[
        'explorer.exe',
        <String>[r'C:\flowplan-test\db'],
      ],
    ]);
  });

  testWidgets(
    'activity review falls back from missing summary to label category and process',
    (tester) async {
      final store = _ReviewFallbackStore();

      await pumpAppAt(
        tester,
        initialLocation: AppRoutes.activityReview,
        size: const Size(1200, 900),
        overrides: [
          trackingServerFirstStoreProvider.overrideWith((ref) async => store),
          allTasksProvider.overrideWith(
            (ref) => Stream.value(const <TaskItem>[]),
          ),
        ],
      );
      await pumpUntilFound(tester, find.byType(ActivityReviewPage));
      await pumpUntilFound(tester, find.text('Label fallback'), maxPumps: 20);

      expect(find.text('Label fallback'), findsOneWidget);
      expect(find.text('Category fallback'), findsOneWidget);
      expect(find.text('ProcessFallback.exe'), findsOneWidget);
      expect(
        debugActivityReviewEvidenceSummary(
          <String, Object?>{
            'evidence': <Object?, Object?>{
              'activityRecordCount': 2,
              'rawLogCount': 3,
              'inputEventCount': 4,
              'processes': <String>['EvidenceApp.exe'],
            },
          },
        ),
        contains('EvidenceApp.exe'),
      );

      await tester.tap(find.byIcon(Icons.check_circle_outline).first);
      await _pumpFrames(tester, 6);
      expect(_firstTextFieldText(tester), 'Label fallback');

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextButton),
        ),
      );
      await _pumpFrames(tester, 6);

      await tester.tap(find.byIcon(Icons.check_circle_outline).at(1));
      await _pumpFrames(tester, 6);
      expect(_firstTextFieldText(tester), 'Category fallback');
    },
  );

  testWidgets('tracker menu opens database directory through injected opener', (
    tester,
  ) async {
    final openedPaths = <String>[];
    final database = _FixedPathDatabase(
      'C:${Platform.pathSeparator}flowplan-test${Platform.pathSeparator}db'
      '${Platform.pathSeparator}flowplanv2.db',
    );
    addTearDown(database.close);

    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.tracker,
      overrides: [
        trackerPageDatabaseFolderOpenerProvider.overrideWithValue(
          (path) async => openedPaths.add(path),
        ),
        databaseProvider.overrideWithValue(database),
      ],
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);

    await tester.tap(find.byTooltip('更多操作'));
    await _pumpFrames(tester, 6);
    await tester.tap(find.text('打开数据库目录').last);
    await _pumpUntil(tester, () => openedPaths.isNotEmpty);

    final dbPath = await _readDatabasePath(tester);
    final folderPath = File(dbPath).parent.path;
    expect(openedPaths, [folderPath]);
    expect(find.textContaining(folderPath), findsOneWidget);
  });

  testWidgets('day details toolbar returns to tracker overview',
      (tester) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      store: _TrackingUiStore(daySummary: _daySummary()),
    );
    await pumpUntilFound(
      tester,
      find.byType(TrackerDayDetailsPage),
      maxPumps: 20,
    );

    await tester.tap(find.byIcon(Icons.analytics_outlined).last);
    await _pumpFrames(tester, 8);

    expect(find.byType(TrackerPage), findsOneWidget);
  });

  testWidgets('day details filter panel clears linked heatmap bucket', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      store: _TrackingUiStore(daySummary: _daySummary()),
      workSessions: _workSessions(),
      selectedHeatmapBucket: _hourBucket(9),
    );
    await pumpUntilFound(
      tester,
      find.text('\u53d6\u6d88\u8054\u52a8'),
      maxPumps: 20,
    );
    expect(find.textContaining('1/1'), findsWidgets);

    await tester.tap(find.text('\u53d6\u6d88\u8054\u52a8'));
    await _pumpFrames(tester, 6);

    expect(find.text('\u53d6\u6d88\u8054\u52a8'), findsNothing);
  });

  testWidgets('tracker input behavior hourly bars select a linked hour', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.tracker,
      store: _TrackingUiStore(daySummary: _daySummary()),
      inputSummary: _inputSummary(),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);
    await pumpUntilFound(tester, find.textContaining('09:00'), maxPumps: 20);

    final bars = find.byWidgetPredicate(
      (widget) =>
          widget is GestureDetector &&
          widget.onTap != null &&
          widget.child is Align,
    );
    expect(bars, findsWidgets);
    final bar = bars.at(9);

    await tester.ensureVisible(bar);
    await tester.tap(bar);
    await _pumpFrames(tester, 6);

    expect(
      find.textContaining('\u8054\u52a8\u65f6\u6bb5\uff1a09:00'),
      findsWidgets,
    );
  });

  testWidgets('expanded session record can show full date time labels', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      store: _TrackingUiStore(daySummary: _daySummary()),
      workSessions: _workSessions(),
    );
    await pumpUntilFound(tester, find.text('Morning focus'), maxPumps: 20);

    await tester.tap(
      find
          .textContaining(
            '\u67e5\u770b\u539f\u59cb\u8bb0\u5f55\u4e0e\u5408\u5e76\u7ec6\u8282',
          )
          .first,
    );
    await _pumpFrames(tester, 6);

    expect(find.textContaining(_shortDate(_day)), findsWidgets);
  });

  testWidgets('task candidates prefer scheduled tasks over unscheduled ties', (
    tester,
  ) async {
    await _pumpTrackerRoute(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      store: _TrackingUiStore(daySummary: _daySummary()),
      workSessions: _workSessions(),
      tasks: <TaskItem>[
        _task(id: 1, summary: 'Unscheduled same status'),
        _task(
          id: 2,
          summary: 'Scheduled same status',
          dtstart: _day.add(const Duration(hours: 8)),
        ),
      ],
    );
    await pumpUntilFound(tester, find.text('Morning focus'), maxPumps: 20);

    await tester
        .tap(find.widgetWithIcon(TextButton, Icons.link_outlined).first);
    await _pumpFrames(tester, 6);

    final scheduledTop = tester.getTopLeft(find.text('Scheduled same status'));
    final unscheduledTop =
        tester.getTopLeft(find.text('Unscheduled same status'));
    expect(scheduledTop.dy, lessThan(unscheduledTop.dy));
  });
}

Future<void> _pumpTrackerRoute(
  WidgetTester tester, {
  required String initialLocation,
  _TrackingUiStore? store,
  List<WorkSession>? workSessions,
  List<TaskItem> tasks = const <TaskItem>[],
  ActivityHeatmapBucket? selectedHeatmapBucket,
  InputHeatmapSummary? inputSummary,
  List<Override> overrides = const <Override>[],
}) async {
  final fakeStore = store ?? _TrackingUiStore(daySummary: _daySummary());

  await pumpAppAt(
    tester,
    initialLocation: initialLocation,
    size: const Size(1400, 1000),
    overrides: [
      trackerServiceNotifierProvider.overrideWith(
        () => _FakeTrackerServiceNotifier(),
      ),
      trackingServerFirstStoreProvider.overrideWith((ref) async => fakeStore),
      allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
      allEventCalendarsProvider.overrideWith(
        (ref) => Stream.value(const <EventCalendar>[]),
      ),
      allTaskListsProvider.overrideWith(
        (ref) => Stream.value(const <TaskList>[]),
      ),
      activityDaySummaryProvider.overrideWith(
        (ref) async => fakeStore.daySummary,
      ),
      workSessionsForDateProvider.overrideWith(
        (ref) => workSessions ?? _workSessions(),
      ),
      if (selectedHeatmapBucket != null)
        trackerHistorySelectedHeatmapBucketProvider.overrideWith(
          (ref) => selectedHeatmapBucket,
        ),
      inputHeatmapSummaryProvider.overrideWith(
        (ref, query) async => inputSummary ?? InputHeatmapSummary.empty(query),
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
        (ref) => Future<TrackingUploadService>.error(StateError('unused')),
      ),
      ...overrides,
    ],
  );
}

Future<void> _pumpFrames(WidgetTester tester, [int count = 4]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition,
) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (condition()) {
      return;
    }
  }
  expect(condition(), isTrue);
}

Future<String> _readDatabasePath(WidgetTester tester) async {
  final context = tester.element(find.byType(TrackerPage));
  final container = ProviderScope.containerOf(context);
  return container.read(databaseProvider).getDatabasePath();
}

String _firstTextFieldText(WidgetTester tester) {
  return (tester.widget(find.byType(TextField).first) as TextField)
      .controller!
      .text;
}

Map<String, dynamic> _daySummary() {
  return <String, dynamic>{
    'insights': <String, Object?>{
      'recordCount': 1,
      'totalMinutes': 60,
      'focusMinutes': 45,
      'totalKeys': 12,
      'totalClicks': 3,
      'totalMovePx': 120,
      'totalScrollPx': 240,
      'productiveRecordCount': 1,
      'sequenceRecordCount': 0,
      'topProcesses': <Map<String, Object?>>[],
      'topCategories': <Map<String, Object?>>[],
    },
    'previewRecords': <Map<String, Object?>>[],
    'sessions': <Map<String, Object?>>[],
  };
}

InputHeatmapSummary _inputSummary() {
  final query = InputEventQuery(
    start: _day,
    end: _day.add(const Duration(days: 1)),
  );
  return InputHeatmapSummary(
    query: query,
    totalEventCount: 12,
    activeMinuteCount: 1,
    keyboardEventCount: 8,
    mouseButtonEventCount: 2,
    wheelEventCount: 1,
    mouseMoveEventCount: 1,
    mouseMoveDistance: 50,
    keyCounts: const <int, int>{65: 8},
    mouseCounts: const <String, int>{'left': 2},
    topKeys: const <InputKeyStat>[
      InputKeyStat(keyCode: 65, label: 'A', count: 8, share: 1),
    ],
    processIntensities: const <InputProcessIntensity>[
      InputProcessIntensity(
        processName: 'Code.exe',
        totalEvents: 12,
        keyEvents: 8,
        mouseButtonEvents: 2,
        wheelEvents: 1,
        mouseMoveEvents: 1,
        moveDistance: 50,
        activeMinutes: 1,
        intensityScore: 24,
      ),
    ],
    hourlyDistribution: List<InputHourDistributionBucket>.generate(
      24,
      (hour) => InputHourDistributionBucket(
        hour: hour,
        totalEvents: hour == 9 ? 12 : 0,
        keyEvents: hour == 9 ? 8 : 0,
        mouseButtonEvents: hour == 9 ? 2 : 0,
        wheelEvents: hour == 9 ? 1 : 0,
        mouseMoveEvents: hour == 9 ? 1 : 0,
        moveDistance: hour == 9 ? 50 : 0,
        activeMinutes: hour == 9 ? 1 : 0,
        intensityScore: hour == 9 ? 24 : 0,
      ),
    ),
  );
}

List<WorkSession> _workSessions() {
  final record = _activityRecord(
    id: 1,
    start: _day.add(const Duration(hours: 9)),
    durationMinutes: 60,
    processName: 'Code.exe',
    windowTitle: 'Editor window',
    category: 'coding',
    manualLabel: 'Code record',
    keyCount: 12,
    mouseClicks: 3,
    mouseMovePx: 120,
    scrollPx: 240,
  );

  return <WorkSession>[
    WorkSession(
      startTime: _day.add(const Duration(hours: 9)),
      endTime: _day.add(const Duration(hours: 10)),
      label: 'Morning focus',
      processName: 'Code.exe',
      category: 'coding',
      records: <ActivityRecord>[record],
      durationMinutes: 60,
      keyCount: 12,
      mouseClicks: 3,
      mouseMovePx: 120,
      scrollPx: 240,
      processNames: const <String>['Code.exe'],
      categories: const <String>['coding'],
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
    isAuto: true,
    source: 'tracker-ui-gap-worker-d',
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

String _shortDate(DateTime date) {
  return '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

final DateTime _day = DateTime(
  DateTime.now().year,
  DateTime.now().month,
  DateTime.now().day,
);

class _ReviewFallbackStore extends FakeTrackingServerFirstStore {
  @override
  Future<Map<String, dynamic>> segments({
    DateTime? startAt,
    DateTime? endAt,
    String? status,
    int limit = 100,
    int offset = 0,
  }) async {
    final baseStart = DateTime.utc(2026, 6, 8, 9);
    return <String, dynamic>{
      'items': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'label-fallback',
          'segmentUid': 'label-fallback',
          'startAt': baseStart.toIso8601String(),
          'endAt': baseStart.add(const Duration(minutes: 20)).toIso8601String(),
          'title': 'Label fallback',
          'primaryProcessName': 'Code.exe',
          'primaryWindowTitle': 'Editor',
          'category': 'coding',
          'confidence': 0.8,
          'status': 'candidate',
          'evidence': <String, Object?>{
            'evidence': <Object?, Object?>{
              'activityRecordCount': 2,
              'rawLogCount': 3,
              'inputEventCount': 4,
              'processes': <String>['EvidenceApp.exe'],
            },
          },
        },
        <String, Object?>{
          'id': 'category-fallback',
          'segmentUid': 'category-fallback',
          'startAt': baseStart.add(const Duration(hours: 1)).toIso8601String(),
          'endAt': baseStart
              .add(const Duration(hours: 1, minutes: 20))
              .toIso8601String(),
          'primaryProcessName': 'CategoryProcess.exe',
          'category': 'Category fallback',
          'confidence': 0.7,
          'status': 'candidate',
          'evidence': <String, Object?>{
            'activityRecordCount': 1,
            'rawLogCount': 0,
            'inputEventCount': 0,
          },
        },
        <String, Object?>{
          'id': 'process-fallback',
          'segmentUid': 'process-fallback',
          'startAt': baseStart.add(const Duration(hours: 2)).toIso8601String(),
          'endAt': baseStart
              .add(const Duration(hours: 2, minutes: 20))
              .toIso8601String(),
          'primaryProcessName': 'ProcessFallback.exe',
          'confidence': 0.6,
          'status': 'candidate',
          'evidence': <String, Object?>{
            'activityRecordCount': 0,
            'rawLogCount': 0,
            'inputEventCount': 0,
          },
        },
      ],
    };
  }
}

class _TrackingUiStore implements TrackingServerFirstStore {
  const _TrackingUiStore({required this.daySummary});

  final Map<String, dynamic> daySummary;

  @override
  Future<Map<String, dynamic>> activityDaySummary({
    required DateTime date,
  }) async {
    return daySummary;
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
    return <String, dynamic>{'buckets': <Map<String, Object?>>[]};
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
    return <String, dynamic>{'buckets': <Map<String, Object?>>[]};
  }

  @override
  Future<Map<String, dynamic>> filterOptions({
    DateTime? start,
    DateTime? end,
  }) async {
    return <String, dynamic>{
      'processOptions': <String>['Code.exe'],
      'categoryOptions': <String>['coding'],
    };
  }

  @override
  Future<Map<String, dynamic>> trackingSummary({
    DateTime? start,
    DateTime? end,
  }) async {
    return <String, dynamic>{
      'canonicalObjectCounts': <String, Object?>{'activity_record': 1},
      'latestReceivedAtByKind': <String, Object?>{},
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FixedPathDatabase extends AppDatabase {
  _FixedPathDatabase(this.path) : super(NativeDatabase.memory());

  final String path;

  @override
  Future<String> getDatabasePath() async {
    return path;
  }
}

class _FakeTrackerServiceNotifier extends TrackerServiceNotifier {
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
  String? get lastAutoUploadError => null;

  @override
  bool get isAutoUploading => false;
}
