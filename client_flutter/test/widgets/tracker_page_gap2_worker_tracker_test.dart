import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/features/tracker/data/tracker_repository.dart';
import 'package:flowplanv2/features/tracker/models/input_event_query.dart';
import 'package:flowplanv2/features/tracker/models/input_heatmap_summary.dart';
import 'package:flowplanv2/features/tracker/models/work_session.dart';
import 'package:flowplanv2/features/tracker/presentation/activity_review_page.dart';
import 'package:flowplanv2/features/tracker/presentation/input_heatmap_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_input_history_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_page.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/features/tracker/services/tracking_upload_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/tracking_store_test_double.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('menu activity review action navigates', (tester) async {
    await _pumpTracker(tester, size: const Size(1400, 1100));
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);

    await _selectMoreMenuItem(tester, '活动理解与确认');
    await pumpUntilFound(tester, find.byType(ActivityReviewPage), maxPumps: 20);
  });

  testWidgets('menu input and log history actions navigate', (tester) async {
    await _pumpTracker(tester, size: const Size(1400, 1100));
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);

    await _selectMoreMenuItem(tester, '查看完整输入历史');
    await pumpUntilFound(
      tester,
      find.byType(TrackerInputHistoryPage),
      maxPumps: 20,
    );
  });

  testWidgets('menu export cancellation is surfaced', (tester) async {
    final picker = _FakeFilePicker(saveResults: <String?>[null]);
    _setFilePickerForTest(picker);

    await _pumpTracker(tester, size: const Size(1400, 1100));
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);

    await _selectMoreMenuItem(tester, '导出数据库副本');
    await tester.pump(const Duration(milliseconds: 250));

    expect(picker.saveRequests, hasLength(1));
    expect(picker.saveRequests.single.allowedExtensions,
        const <String>['db', 'sqlite', 'sqlite3']);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('已取消导出数据库'), findsOneWidget);
  });

  testWidgets('export failures stay in-app without opening system folders',
      (tester) async {
    final picker = _FakeFilePicker(
      saveError: StateError('picker write denied'),
    );
    _setFilePickerForTest(picker);

    await _pumpTracker(tester, size: const Size(1400, 1100));
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);

    await _selectMoreMenuItem(tester, '导出数据库副本');
    await tester.pump(const Duration(milliseconds: 250));

    expect(picker.saveRequests, hasLength(1));
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('导出数据库失败'), findsOneWidget);
    expect(find.textContaining('picker write denied'), findsOneWidget);
  });

  testWidgets('heatmap errors, empty input behavior, and summary errors render',
      (tester) async {
    final store = TrackingStoreTestDouble()
      ..activityHeatmapError = StateError('activity heatmap gap')
      ..inputHeatmapError = StateError('input heatmap gap');

    await _pumpTracker(
      tester,
      store: store,
      daySummaryError: StateError('daily summary gap'),
      size: const Size(1400, 1100),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);
    await pumpUntilFound(
      tester,
      find.textContaining('activity heatmap gap'),
      maxPumps: 20,
    );

    expect(find.textContaining('加载热力图失败'), findsOneWidget);
    expect(find.textContaining('daily summary gap'), findsOneWidget);
    expect(find.textContaining('input heatmap gap'), findsOneWidget);
  });

  testWidgets('year and month heatmap drilldown update queried bucket scale',
      (tester) async {
    final today = _today();
    final store = TrackingStoreTestDouble(
      trackingSummaryResponseBuilder: () => <String, dynamic>{
        'canonicalObjectCounts': <String, Object?>{'activity_record': 4},
        'latestReceivedAtByKind': <String, Object?>{
          'activity_record': today.toIso8601String(),
        },
      },
      activityHeatmapResponseBuilder: (call) {
        if (call.bucket == 'month') {
          return <String, dynamic>{
            'buckets': <Map<String, Object?>>[
              <String, Object?>{
                'bucketStart':
                    DateTime(today.year, today.month).toIso8601String(),
                'recordCount': 4,
                'totalMinutes': 160,
              },
            ],
          };
        }
        if (call.bucket == 'day') {
          return <String, dynamic>{
            'buckets': <Map<String, Object?>>[
              <String, Object?>{
                'bucketStart': today.toIso8601String(),
                'recordCount': 2,
                'totalMinutes': 80,
              },
            ],
          };
        }
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
      },
    );

    await _pumpTracker(
      tester,
      store: store,
      initialHeatmapScale: ActivityHeatmapScale.year,
      size: const Size(1400, 1200),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);
    await pumpUntil(tester, () => store.activityHeatmapCalls.isNotEmpty);

    expect(store.activityHeatmapCalls.last.bucket, 'month');
    await tester.tap(find.widgetWithText(OutlinedButton, '进入逐月'));
    await pumpUntil(
      tester,
      () =>
          store.activityHeatmapCalls.length >= 2 &&
          store.activityHeatmapCalls.last.bucket == 'month',
    );

    await pumpUntil(
      tester,
      () => find.widgetWithText(OutlinedButton, '进入每日').evaluate().isNotEmpty,
    );
    await tester.tap(find.widgetWithText(OutlinedButton, '进入每日'));
    await pumpUntil(
      tester,
      () => store.activityHeatmapCalls.any((call) => call.bucket == 'day'),
    );

    expect(
      store.activityHeatmapCalls.map((call) => call.bucket),
      containsAllInOrder(<String>['month', 'month', 'day']),
    );
  });

  testWidgets('day details upload diagnostics errors render', (tester) async {
    final session = _linkedSession();
    await _pumpTracker(
      tester,
      initialLocation: AppRoutes.trackerDayDetails,
      store: TrackingStoreTestDouble(
        activityDaySummaryResponseBuilder: (_) => _summaryForSession(session),
      ),
      workSessions: <WorkSession>[session],
      tasks: <TaskItem>[_task(7, 'Linked tracker task')],
      uploadDiagnosticsError: StateError('diagnostics gap'),
      size: const Size(1400, 1200),
    );
    await pumpUntilFound(
      tester,
      find.byType(TrackerDayDetailsPage),
      maxPumps: 20,
    );

    expect(find.textContaining('diagnostics gap'), findsOneWidget);
  });

  testWidgets(
      'toolbar upload and detail hub input heatmap errors are reachable',
      (tester) async {
    final upload = _FakeTrackingUploadService(
      error: StateError('manual upload gap'),
    );

    await _pumpTracker(
      tester,
      uploadService: upload,
      inputSummary: InputHeatmapSummary.empty(
        InputEventQuery(
          start: _today(),
          end: _today().add(const Duration(days: 1)),
        ),
      ),
      size: const Size(1400, 1200),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);
    await pumpUntilFound(tester, find.byIcon(Icons.cloud_upload_outlined),
        maxPumps: 20);

    await tester.tap(find.byIcon(Icons.cloud_upload_outlined).first);
    await pumpUntil(tester, () => upload.uploadCalls == 1);
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('manual upload gap'), findsOneWidget);
    expect(find.text('这一天还没有可分析的输入事件'), findsOneWidget);

    await tester.ensureVisible(find.text('打开键鼠热力图'));
    await tester.tap(find.text('打开键鼠热力图'));
    await pumpUntilFound(tester, find.byType(InputHeatmapPage), maxPumps: 20);
    await tester.pump(const Duration(seconds: 31));
  });
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
  Object? uploadDiagnosticsError,
  InputHeatmapSummary? inputSummary,
  ActivityHeatmapScale? initialHeatmapScale,
  Size size = const Size(1400, 1000),
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
      if (daySummaryError != null)
        activityDaySummaryProvider.overrideWith((ref) async {
          throw daySummaryError;
        }),
      if (workSessions != null)
        workSessionsForDateProvider.overrideWith((ref) => workSessions),
      inputHeatmapSummaryProvider.overrideWith(
        (ref, query) async {
          final error = fakeStore.inputHeatmapError;
          if (error != null) {
            throw error;
          }
          return inputSummary ?? InputHeatmapSummary.empty(query);
        },
      ),
      trackingUploadDiagnosticsProvider.overrideWith(
        (ref) async {
          final error = uploadDiagnosticsError;
          if (error != null) {
            throw error;
          }
          return <String, Object?>{
            'lastActivityRecordId': 0,
            'lastInputEventId': 0,
            'lastRawLogId': 0,
            'pendingActivityRecords': 0,
            'pendingInputEvents': 0,
            'pendingRawLogs': 0,
          };
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

WorkSession _linkedSession() {
  final today = _today();
  final record = _activityRecord(
    id: 7,
    start: today.add(const Duration(hours: 9)),
    durationMinutes: 35,
    linkedTaskId: 7,
  );
  return WorkSession(
    startTime: record.startTime,
    endTime: record.endTime!,
    label: 'Linked tracker work',
    processName: 'Code.exe',
    category: 'coding',
    records: <ActivityRecord>[record],
    durationMinutes: 35,
    keyCount: 8,
    mouseClicks: 2,
    mouseMovePx: 120,
    scrollPx: 300,
    processNames: const <String>['Code.exe'],
    categories: const <String>['coding'],
    interruptionCount: 0,
  );
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
      'topProcesses': <Map<String, Object?>>[],
      'topCategories': <Map<String, Object?>>[],
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
    windowTitle: 'Linked tracker window',
    category: 'coding',
    linkedTaskId: linkedTaskId,
    keyCount: 8,
    mouseClicks: 2,
    mouseMovePx: 120,
    scrollPx: 300,
    isAuto: true,
    source: 'tracker-gap2-worker-test',
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
  _FakeTrackerServiceNotifier();

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

  @override
  DateTime? get lastAutoUploadAt => null;

  @override
  String? get lastAutoUploadError => null;

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

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker({
    List<String?> saveResults = const <String?>[],
    this.saveError,
  }) : _saveResults = List<String?>.from(saveResults);

  final List<String?> _saveResults;
  final Object? saveError;
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
    final failure = saveError;
    if (failure != null) {
      throw failure;
    }
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
