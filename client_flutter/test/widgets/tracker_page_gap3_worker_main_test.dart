import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flowplanv2/app.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/features/tracker/data/tracker_repository.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
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
import 'package:go_router/go_router.dart';

import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/tracking_store_test_double.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('task binding sheet create-new branch opens task route',
      (tester) async {
    final session = _linkedSession();

    await _pumpTracker(
      tester,
      daySummary: _summaryForSession(session),
      workSessions: <WorkSession>[session],
      tasks: const <TaskItem>[],
      size: const Size(1400, 1200),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);

    await tester.ensureVisible(find.text('查看今日详细数据'));
    await tester.tap(find.text('查看今日详细数据'));
    await pumpUntilFound(
      tester,
      find.byType(TrackerDayDetailsPage),
      maxPumps: 20,
    );
    await pumpUntilFound(tester, find.text('调整任务关联'), maxPumps: 80);

    await tester.tap(find.text('调整任务关联').first);
    await tester.pumpAndSettle();

    expect(find.text('当前还没有可选任务，可以先创建任务再回来绑定。'), findsOneWidget);

    await tester.tap(find.text('新建任务'));
    await tester.pumpAndSettle();

    expect(find.text('task create route'), findsOneWidget);
  });

  testWidgets('task binding sheet unbind branch redirects to review hub',
      (tester) async {
    final session = _linkedSession();

    await _pumpTracker(
      tester,
      daySummary: _summaryForSession(session),
      workSessions: <WorkSession>[session],
      tasks: <TaskItem>[_task(7, 'Linked tracker task')],
      size: const Size(1400, 1200),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);

    await tester.ensureVisible(find.text('查看今日详细数据'));
    await tester.tap(find.text('查看今日详细数据'));
    await pumpUntilFound(
      tester,
      find.byType(TrackerDayDetailsPage),
      maxPumps: 20,
    );
    await pumpUntilFound(tester, find.text('调整任务关联'), maxPumps: 80);

    await tester.tap(find.text('调整任务关联').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消关联'));
    await tester.pumpAndSettle();

    expect(find.text('activity review route'), findsOneWidget);
  });

  testWidgets('database export menu covers cancel and success snackbars',
      (tester) async {
    final database = _RecordingExportDatabase();
    final picker = _FakeFilePicker(
      saveResults: <String?>[
        '   ',
        r'C:\tracker-gap3-export.db',
      ],
    );
    _setFilePickerForTest(picker);

    await _pumpTracker(
      tester,
      database: database,
      size: const Size(1400, 1000),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);

    await _selectMoreMenuItem(tester, '导出数据库副本');
    await tester.pump(const Duration(milliseconds: 250));

    expect(picker.saveRequests, hasLength(1));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('已取消导出数据库'), findsOneWidget);
    expect(database.exportedPaths, isEmpty);
    ScaffoldMessenger.of(tester.element(find.byType(TrackerPage)))
        .hideCurrentSnackBar();
    await tester.pumpAndSettle();

    await _selectMoreMenuItem(tester, '导出数据库副本');
    await tester.pump(const Duration(milliseconds: 250));

    expect(picker.saveRequests, hasLength(2));
    expect(database.exportedPaths, <String>[r'C:\tracker-gap3-export.db']);
    await pumpUntilFound(
      tester,
      find.textContaining('数据库已导出到：'),
      maxPumps: 80,
    );
  });

  testWidgets('menu day details and database-folder failure are surfaced',
      (tester) async {
    final database = _PathFailingDatabase(StateError('database path denied'));

    await _pumpTracker(
      tester,
      database: database,
      size: const Size(1400, 1000),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);

    await _selectMoreMenuItem(tester, '查看今日详细数据');
    await pumpUntilFound(
      tester,
      find.byType(TrackerDayDetailsPage),
      maxPumps: 20,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);

    await _selectMoreMenuItem(tester, '打开数据库目录');
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('打开数据库目录失败：'), findsOneWidget);
    expect(find.textContaining('database path denied'), findsOneWidget);
  });

  testWidgets('heatmap scale, filter, and clear callbacks update main state',
      (tester) async {
    final today = _today();
    final store = TrackingStoreTestDouble(
      trackingSummaryResponseBuilder: () => <String, dynamic>{
        'canonicalObjectCounts': <String, Object?>{'activity_record': 3},
        'latestReceivedAtByKind': <String, Object?>{
          'activity_record':
              today.add(const Duration(hours: 9)).toIso8601String(),
        },
      },
      activityHeatmapResponseBuilder: (call) {
        final bucketStart = switch (call.bucket) {
          'hour' => today.add(const Duration(hours: 9)),
          'day' => today,
          'month' => DateTime(today.year, today.month),
          _ => DateTime(today.year),
        };
        return <String, dynamic>{
          'buckets': <Map<String, Object?>>[
            <String, Object?>{
              'bucketStart': bucketStart.toIso8601String(),
              'recordCount': 3,
              'totalMinutes': 90,
            },
          ],
        };
      },
    );

    await _pumpTracker(
      tester,
      store: store,
      initialHeatmapScale: ActivityHeatmapScale.day,
      size: const Size(1400, 1200),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);
    await pumpUntil(tester, () => store.activityHeatmapCalls.isNotEmpty);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, '小时'));
    await tester.tap(find.widgetWithText(ChoiceChip, '小时'));
    await pumpUntil(
      tester,
      () => store.activityHeatmapCalls.any((call) => call.bucket == 'hour'),
    );

    await pumpUntilFound(
      tester,
      find.widgetWithText(FilledButton, '按此小时筛选列表'),
      maxPumps: 20,
    );
    await tester.tap(find.widgetWithText(FilledButton, '按此小时筛选列表'));
    await tester.pump();

    expect(find.widgetWithText(FilledButton, '取消列表筛选'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '取消列表筛选'));
    await tester.pump();

    expect(find.widgetWithText(FilledButton, '按此小时筛选列表'), findsOneWidget);
  });

  testWidgets(
      'session sequence toggle, auto-upload timestamp, and input analysis route work',
      (tester) async {
    final now = DateTime.now();
    final trackerNotifier = _FakeTrackerServiceNotifier(
      lastAutoUploadAt: DateTime(now.year, now.month, now.day, 8, 30),
    );

    await _pumpTracker(
      tester,
      trackerNotifier: trackerNotifier,
      inputSummary: _inputSummary(
        InputEventQuery(
          start: _today(),
          end: _today().add(const Duration(days: 1)),
        ),
      ),
      size: const Size(1400, 1200),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);
    await pumpUntilFound(tester, find.textContaining('上次自动上传'), maxPumps: 20);

    await tester.ensureVisible(find.widgetWithText(TextButton, '关闭序列记录'));
    await tester.tap(find.widgetWithText(TextButton, '关闭序列记录'));
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(TrackerPage)),
    );
    expect(container.read(sequenceRecordingProvider), isFalse);

    await tester.ensureVisible(find.widgetWithText(TextButton, '展开热力图'));
    await tester.tap(find.widgetWithText(TextButton, '展开热力图'));
    await tester.pumpAndSettle();

    expect(find.text('input heatmap route'), findsOneWidget);
  });
}

Future<void> _pumpTracker(
  WidgetTester tester, {
  String initialLocation = AppRoutes.tracker,
  AppDatabase? database,
  TrackingStoreTestDouble? store,
  _FakeTrackerServiceNotifier? trackerNotifier,
  _FakeTrackingUploadService? uploadService,
  List<TaskItem> tasks = const <TaskItem>[],
  List<WorkSession>? workSessions,
  Map<String, dynamic>? daySummary,
  Object? daySummaryError,
  InputHeatmapSummary? inputSummary,
  ActivityHeatmapScale? initialHeatmapScale,
  Size size = const Size(1400, 1000),
}) async {
  final db = database ?? createTestDatabase();
  final fakeStore = store ?? TrackingStoreTestDouble();
  final router = GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.tracker,
        builder: (context, state) => const TrackerPage(),
      ),
      GoRoute(
        path: AppRoutes.trackerDayDetails,
        builder: (context, state) => const TrackerDayDetailsPage(),
      ),
      GoRoute(
        path: AppRoutes.activityReview,
        builder: (context, state) => _placeholder('activity review route'),
      ),
      GoRoute(
        path: AppRoutes.taskCreate,
        builder: (context, state) => _placeholder('task create route'),
      ),
      GoRoute(
        path: AppRoutes.trackerInputHeatmap,
        builder: (context, state) => _placeholder('input heatmap route'),
      ),
      GoRoute(
        path: AppRoutes.trackerInputHistory,
        builder: (context, state) => _placeholder('input history route'),
      ),
      GoRoute(
        path: AppRoutes.trackerLogHistory,
        builder: (context, state) => _placeholder('log history route'),
      ),
      GoRoute(
        path: '/task/:id',
        builder: (context, state) => _placeholder('task detail route'),
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
        () => trackerNotifier ?? _FakeTrackerServiceNotifier(),
      ),
      sequenceRecordingNotifierProvider.overrideWith(
        () => _FakeSequenceRecordingNotifier(initialValue: true),
      ),
      if (initialHeatmapScale != null)
        activityHeatmapScaleOverrideProvider
            .overrideWith((ref) => initialHeatmapScale),
      trackingServerFirstStoreProvider.overrideWith((ref) async => fakeStore),
      allTasksProvider.overrideWith((ref) => Stream.value(tasks)),
      allEventCalendarsProvider.overrideWith(
        (ref) => Stream.value(const <EventCalendar>[]),
      ),
      allTaskListsProvider.overrideWith(
        (ref) => Stream.value(const <TaskList>[]),
      ),
      activityDaySummaryProvider.overrideWith((ref) async {
        final error = daySummaryError;
        if (error != null) {
          throw error;
        }
        return daySummary ?? _emptyDaySummary();
      }),
      workSessionsForDateProvider.overrideWith(
        (ref) => workSessions ?? const <WorkSession>[],
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
    child: FlowPlanV2App(routerOverride: router),
  );
  await tester.pump();
}

Widget _placeholder(String text) {
  return Scaffold(
    body: Center(child: Text(text)),
  );
}

Future<void> _selectMoreMenuItem(WidgetTester tester, String label) async {
  await tester.tap(find.byTooltip('更多操作'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void _setFilePickerForTest(FilePicker picker) {
  FilePicker? previousPicker;
  try {
    previousPicker = FilePicker.platform;
  } on Object {
    previousPicker = null;
  }
  FilePicker.platform = picker;
  addTearDown(() {
    if (previousPicker != null) {
      FilePicker.platform = previousPicker;
    } else {
      FilePicker.platform = _FakeFilePicker();
    }
  });
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 40,
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

Map<String, dynamic> _summaryForSession(WorkSession session) {
  final records = <Map<String, Object?>>[
    for (final record in session.records)
      <String, Object?>{
        'serverId': 'record-${record.id}',
        'objectType': 'activity_record',
        'occurredAt': record.startTime.toIso8601String(),
        'metricMinutes': record.durationMinutes,
        'payload': <String, Object?>{
          'startTime': record.startTime.toIso8601String(),
          'endTime': record.endTime?.toIso8601String(),
          'durationMinutes': record.durationMinutes,
          'processName': record.processName,
          'windowTitle': record.windowTitle,
          'manualLabel': record.manualLabel,
          'category': record.category,
          'linkedTaskId': record.linkedTaskId,
          'keyCount': record.keyCount,
          'mouseClicks': record.mouseClicks,
          'mouseMovePx': record.mouseMovePx,
          'scrollPx': record.scrollPx,
          'isAuto': record.isAuto,
        },
      },
  ];
  return <String, dynamic>{
    'insights': <String, Object?>{
      'recordCount': records.length,
      'totalMinutes': session.durationMinutes,
      'focusMinutes': session.durationMinutes,
      'totalKeys': session.keyCount,
      'totalClicks': session.mouseClicks,
      'totalMovePx': session.mouseMovePx,
      'totalScrollPx': session.scrollPx,
      'productiveRecordCount': records.length,
      'sequenceRecordCount': 0,
      'topProcesses': <Map<String, Object?>>[
        <String, Object?>{
          'label': 'Code.exe',
          'minutes': session.durationMinutes,
          'keys': session.keyCount,
          'clicks': session.mouseClicks,
          'movePx': session.mouseMovePx,
          'scrollPx': session.scrollPx,
          'sessions': 1,
        },
      ],
      'topCategories': <Map<String, Object?>>[
        <String, Object?>{
          'label': 'coding',
          'minutes': session.durationMinutes,
          'sessions': 1,
        },
      ],
    },
    'previewRecords': records,
    'sessions': <Map<String, Object?>>[
      <String, Object?>{
        'startTime': session.startTime.toIso8601String(),
        'endTime': session.endTime.toIso8601String(),
        'label': session.label,
        'processName': session.processName,
        'category': session.category,
        'durationMinutes': session.durationMinutes,
        'keyCount': session.keyCount,
        'mouseClicks': session.mouseClicks,
        'mouseMovePx': session.mouseMovePx,
        'scrollPx': session.scrollPx,
        'processNames': session.processNames,
        'categories': session.categories,
        'interruptionCount': session.interruptionCount,
        'rawRecordCount': session.rawRecordCount,
      },
    ],
  };
}

WorkSession _linkedSession() {
  final today = _today();
  final record = _activityRecord(
    id: 7,
    start: today.add(const Duration(hours: 9)),
    durationMinutes: 45,
    linkedTaskId: 7,
  );
  return WorkSession(
    startTime: record.startTime,
    endTime: record.endTime!,
    label: 'Linked tracker work',
    processName: 'Code.exe',
    category: 'coding',
    records: <ActivityRecord>[record],
    durationMinutes: 45,
    keyCount: 12,
    mouseClicks: 4,
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
  int? linkedTaskId,
}) {
  return ActivityRecord(
    id: id,
    startTime: start,
    endTime: start.add(Duration(minutes: durationMinutes)),
    durationMinutes: durationMinutes,
    manualLabel: 'Linked tracker work',
    processName: 'Code.exe',
    windowTitle: 'Tracker gap3 window',
    category: 'coding',
    linkedTaskId: linkedTaskId,
    keyCount: 12,
    mouseClicks: 4,
    mouseMovePx: 320,
    scrollPx: 640,
    isAuto: true,
    source: 'tracker-gap3-worker-main-test',
  );
}

InputHeatmapSummary _inputSummary(InputEventQuery query) {
  return InputHeatmapSummary(
    query: query,
    totalEventCount: 48,
    activeMinuteCount: 12,
    keyboardEventCount: 24,
    mouseButtonEventCount: 8,
    wheelEventCount: 6,
    mouseMoveEventCount: 10,
    mouseMoveDistance: 1800,
    keyCounts: const <int, int>{65: 16, 66: 8},
    mouseCounts: const <String, int>{'left': 8},
    topKeys: const <InputKeyStat>[
      InputKeyStat(keyCode: 65, label: 'A', count: 16, share: 0.33),
    ],
    processIntensities: const <InputProcessIntensity>[
      InputProcessIntensity(
        processName: 'Code.exe',
        totalEvents: 36,
        keyEvents: 22,
        mouseButtonEvents: 5,
        wheelEvents: 4,
        mouseMoveEvents: 5,
        moveDistance: 1200,
        activeMinutes: 9,
        intensityScore: 92,
      ),
    ],
    hourlyDistribution: List<InputHourDistributionBucket>.generate(
      24,
      (hour) => InputHourDistributionBucket(
        hour: hour,
        totalEvents: hour == 9 ? 36 : 0,
        keyEvents: hour == 9 ? 22 : 0,
        mouseButtonEvents: hour == 9 ? 5 : 0,
        wheelEvents: hour == 9 ? 4 : 0,
        mouseMoveEvents: hour == 9 ? 5 : 0,
        moveDistance: hour == 9 ? 1200 : 0,
        activeMinutes: hour == 9 ? 9 : 0,
        intensityScore: hour == 9 ? 92 : 0,
      ),
    ),
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
  _FakeTrackerServiceNotifier({
    this.lastAutoUploadAt,
  });

  @override
  final DateTime? lastAutoUploadAt;
  @override
  String? get lastAutoUploadError => null;
  var refreshCalls = 0;
  var usageSettingsCalls = 0;

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
  Future<void> openAndroidUsageAccessSettings() async {
    usageSettingsCalls += 1;
  }

  @override
  bool get isAutoUploading => false;
}

class _FakeSequenceRecordingNotifier extends SequenceRecordingNotifier {
  _FakeSequenceRecordingNotifier({required this.initialValue});

  final bool initialValue;

  @override
  bool build() {
    return initialValue;
  }

  @override
  Future<void> set(bool enabled) async {
    state = enabled;
  }
}

class _FakeTrackingUploadService implements TrackingUploadService {
  _FakeTrackingUploadService({this.result});

  final TrackingUploadResult? result;
  var uploadCalls = 0;

  @override
  Future<TrackingUploadResult> uploadPending({
    int limitPerKind = 2000,
    int chunkSize = 200,
  }) async {
    uploadCalls += 1;
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

class _RecordingExportDatabase extends AppDatabase {
  _RecordingExportDatabase() : super(NativeDatabase.memory());

  final exportedPaths = <String>[];

  @override
  Future<void> exportToFile(String targetPath) async {
    exportedPaths.add(targetPath);
  }
}

class _PathFailingDatabase extends AppDatabase {
  _PathFailingDatabase(this.error) : super(NativeDatabase.memory());

  final Object error;

  @override
  Future<String> getDatabasePath() async {
    throw error;
  }
}

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker({
    List<String?> saveResults = const <String?>[],
  }) : _saveResults = List<String?>.from(saveResults);

  final List<String?> _saveResults;
  final saveRequests = <_SaveRequest>[];

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    saveRequests.add(
      _SaveRequest(
        dialogTitle: dialogTitle,
        fileName: fileName,
        type: type,
        allowedExtensions: allowedExtensions,
      ),
    );
    return _saveResults.isEmpty ? null : _saveResults.removeAt(0);
  }
}

class _SaveRequest {
  const _SaveRequest({
    required this.dialogTitle,
    required this.fileName,
    required this.type,
    required this.allowedExtensions,
  });

  final String? dialogTitle;
  final String? fileName;
  final FileType type;
  final List<String>? allowedExtensions;
}
