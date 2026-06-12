import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/tracker/models/input_heatmap_summary.dart';
import 'package:flowplanv2/features/tracker/presentation/activity_review_page.dart';
import 'package:flowplanv2/features/tracker/presentation/input_heatmap_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_input_history_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_log_history_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_page.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/features/tracker/services/tracking_upload_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/tracking_store_test_double.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('tracker start stop and review flow update state and store', (
    tester,
  ) async {
    final fakeTrackingStore = FakeTrackingServerFirstStore();

    await pumpAppAt(
      tester,
      initialLocation: AppRoutes.tracker,
      size: const Size(1400, 900),
      overrides: [
        trackingServerFirstStoreProvider.overrideWith(
          (ref) async => fakeTrackingStore,
        ),
        allTasksProvider.overrideWith(
          (ref) => Stream.value(const <TaskItem>[]),
        ),
        activityDaySummaryProvider.overrideWith(
          (ref) async => <String, dynamic>{
            'insights': <String, Object?>{'totalMinutes': 0},
            'previewRecords': <Map<String, Object?>>[],
            'sessions': <Map<String, Object?>>[],
          },
        ),
        inputHeatmapSummaryProvider.overrideWith(
          (ref, query) async => InputHeatmapSummary.empty(query),
        ),
      ],
    );
    await pumpUntilFound(tester, find.byType(TrackerPage));

    expect(find.byType(TrackerPage), findsOneWidget);
    expect(find.byKey(AppKeys.shellTracker), findsOneWidget);
    expect(find.byKey(AppKeys.trackerStartButton), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    expect(find.text('已停止'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    expect(find.text('等待采集'), findsOneWidget);

    await tester.tap(find.byType(Switch).first);
    await tester.pump();

    expect(tester.widget<Switch>(find.byType(Switch).first).value, isFalse);
    expect(find.text('已停止'), findsOneWidget);

    await tester.ensureVisible(find.text('活动理解与确认'));
    await tester.tap(find.text('活动理解与确认'));
    await pumpUntilFound(tester, find.byType(ActivityReviewPage));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.text('Focused coding'), maxPumps: 20);

    final buildSegmentsButton = find.byTooltip('重新读取并整理当天追踪');
    expect(buildSegmentsButton, findsOneWidget);
    await tester.tap(buildSegmentsButton);
    await _pumpUntil(
      tester,
      () => fakeTrackingStore.buildSegmentsCalls == 1,
    );

    expect(fakeTrackingStore.buildSegmentsCalls, 1);
    expect(find.text('Focused coding'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.check_circle_outline));
    await pumpUntilFound(
      tester,
      find.byKey(AppKeys.trackerReviewConfirmButton),
    );
    await tester.tap(find.byKey(AppKeys.trackerReviewConfirmButton));
    await _pumpUntil(
      tester,
      () => fakeTrackingStore.confirmedSegmentIds.contains('segment-1'),
    );

    expect(fakeTrackingStore.confirmedSegmentIds, ['segment-1']);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('tracker toolbar refresh and upload buttons run real actions', (
    tester,
  ) async {
    final trackerNotifier = _FakeTrackerServiceNotifier();
    final uploadService = _FakeTrackingUploadService(
      result: const TrackingUploadResult(
        uploadedBatches: 2,
        uploadedRecords: 5,
        details: <Map<String, Object?>>[],
      ),
    );

    await _pumpTrackerOverview(
      tester,
      trackerNotifier: trackerNotifier,
      uploadService: uploadService,
    );
    await pumpUntilFound(tester, find.byType(TrackerPage));
    await pumpUntilFound(tester, find.byIcon(Icons.refresh_outlined));

    await tester.tap(find.byIcon(Icons.refresh_outlined).first);
    await _pumpUntil(tester, () => trackerNotifier.refreshCalls == 1);
    expect(trackerNotifier.refreshCalls, 1);

    await tester.tap(find.byIcon(Icons.cloud_upload_outlined).first);
    await _pumpUntil(tester, () => uploadService.uploadCalls == 1);
    await tester.pump(const Duration(milliseconds: 250));
    expect(uploadService.uploadCalls, 1);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('tracker upload button surfaces failures without leaving busy', (
    tester,
  ) async {
    final uploadService = _FakeTrackingUploadService(
      error: StateError('upload transport failed'),
    );

    await _pumpTrackerOverview(tester, uploadService: uploadService);
    await pumpUntilFound(tester, find.byType(TrackerPage));
    await pumpUntilFound(tester, find.byIcon(Icons.cloud_upload_outlined));

    await tester.tap(find.byIcon(Icons.cloud_upload_outlined).first);
    await _pumpUntil(tester, () => uploadService.uploadCalls == 1);
    await tester.pump(const Duration(milliseconds: 250));

    expect(uploadService.uploadCalls, 1);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsWidgets);
  });

  testWidgets('tracker detail hub opens secondary tracker pages', (
    tester,
  ) async {
    await _pumpTrackerOverview(tester, size: const Size(1400, 1200));
    await pumpUntilFound(tester, find.byType(TrackerPage));
    await pumpUntilFound(tester, find.text('详细数据入口'), maxPumps: 20);

    await tester.ensureVisible(find.text('查看今日详细数据'));
    await tester.tap(find.text('查看今日详细数据'));
    await pumpUntilFound(tester, find.byType(TrackerDayDetailsPage));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.byType(TrackerPage));

    await tester.ensureVisible(find.text('查看完整输入历史'));
    await tester.tap(find.text('查看完整输入历史'));
    await pumpUntilFound(tester, find.byType(TrackerInputHistoryPage));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.byType(TrackerPage));

    await tester.ensureVisible(find.text('打开键鼠热力图'));
    await tester.tap(find.text('打开键鼠热力图'));
    await pumpUntilFound(tester, find.byType(InputHeatmapPage));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.byType(TrackerPage));

    await tester.ensureVisible(find.text('查看历史活动记录'));
    await tester.tap(find.text('查看历史活动记录'));
    await pumpUntilFound(tester, find.byType(TrackerLogHistoryPage));
  });
}

Future<void> _pumpTrackerOverview(
  WidgetTester tester, {
  _FakeTrackerServiceNotifier? trackerNotifier,
  _FakeTrackingUploadService? uploadService,
  Size size = const Size(1400, 900),
}) async {
  final store = TrackingStoreTestDouble(
    processOptions: const <String>['Code.exe'],
    categoryOptions: const <String>['coding'],
  );

  await pumpAppAt(
    tester,
    initialLocation: AppRoutes.tracker,
    size: size,
    overrides: [
      trackerServiceNotifierProvider.overrideWith(
        () => trackerNotifier ?? _FakeTrackerServiceNotifier(),
      ),
      trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      allTasksProvider.overrideWith(
        (ref) => Stream.value(const <TaskItem>[]),
      ),
      allEventCalendarsProvider.overrideWith(
        (ref) => Stream.value(const <EventCalendar>[]),
      ),
      allTaskListsProvider.overrideWith(
        (ref) => Stream.value(const <TaskList>[]),
      ),
      activityDaySummaryProvider.overrideWith(
        (ref) async => <String, dynamic>{
          'insights': <String, Object?>{'totalMinutes': 0},
          'previewRecords': <Map<String, Object?>>[],
          'sessions': <Map<String, Object?>>[],
        },
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
  DateTime? get lastAutoUploadAt => null;

  @override
  String? get lastAutoUploadError => null;

  @override
  bool get isAutoUploading => false;
}

class _FakeTrackingUploadService implements TrackingUploadService {
  _FakeTrackingUploadService({
    this.result,
    this.error,
  });

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
