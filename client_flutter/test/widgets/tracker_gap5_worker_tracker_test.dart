import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_page.dart';
import 'package:flowplanv2/features/tracker/services/tracker_platform_source.dart';
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
  setUp(() {
    debugTrackerPlatformOverride = const TrackerPlatformSource.testing(
      platformLabel: 'Android',
      collectionMode: TrackerCollectionMode.manualUsageStatsImport,
      supportsInputAnalytics: false,
      supportsSequenceRecording: false,
      supportsUsageAccessPermission: true,
      supportsDetailedInputHistory: false,
    );
  });

  tearDown(() {
    debugTrackerPlatformOverride = null;
  });

  testWidgets('Android tracker mode panel follows debug platform override',
      (tester) async {
    final notifier = _FakeTrackerServiceNotifier(
      initialState: TrackerState(
        isRunning: true,
        hasUsageStatsPermission: false,
        lastSampleAt: DateTime(2026, 6, 11, 10, 45),
      ),
    );
    final store = TrackingStoreTestDouble();

    await _pumpTracker(
      tester,
      trackerNotifier: notifier,
      store: store,
      size: const Size(1100, 900),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);

    expect(find.byIcon(Icons.mobile_off_outlined), findsOneWidget);
    expect(
        find.widgetWithIcon(
            OutlinedButton, Icons.admin_panel_settings_outlined),
        findsOneWidget);
    expect(find.widgetWithIcon(FilledButton, Icons.refresh_outlined),
        findsOneWidget);
    expect(find.byIcon(Icons.keyboard_alt), findsNothing);
    expect(find.byIcon(Icons.keyboard_alt_outlined), findsNothing);
    expect(store.inputHeatmapCalls, isEmpty);

    final usageAccessButton = find.widgetWithIcon(
        OutlinedButton, Icons.admin_panel_settings_outlined);
    await tester.ensureVisible(usageAccessButton);
    await tester.pump();
    await tester.tap(usageAccessButton);
    await tester.pump();
    expect(notifier.openUsageAccessSettingsCalls, 1);

    final importButton =
        find.widgetWithIcon(FilledButton, Icons.refresh_outlined);
    await _pumpUntilFilledButtonEnabled(tester, importButton);
    await tester.ensureVisible(importButton);
    await tester.pump();
    await tester.tap(importButton);
    await pumpUntil(tester, () => notifier.refreshCalls == 1);
  });

  testWidgets(
      'Android tracker mode shows pending permission and keeps refresh available',
      (tester) async {
    final notifier = _FakeTrackerServiceNotifier(
      initialState: const TrackerState(
        isRunning: true,
        hasUsageStatsPermission: null,
      ),
    );

    final store = TrackingStoreTestDouble();
    await _pumpTracker(
      tester,
      trackerNotifier: notifier,
      store: store,
      size: const Size(1100, 900),
    );
    await pumpUntilFound(tester, find.byType(TrackerPage), maxPumps: 20);
    await _pumpUntilFilledButtonEnabled(
      tester,
      find.widgetWithIcon(FilledButton, Icons.refresh_outlined),
    );

    final refreshButton = tester.widget<FilledButton>(
      find.widgetWithIcon(FilledButton, Icons.refresh_outlined),
    );
    expect(find.byIcon(Icons.mobile_off_outlined), findsOneWidget);
    expect(refreshButton.onPressed, isNotNull);
    expect(notifier.refreshCalls, 0);
  });
}

Future<void> _pumpUntilFilledButtonEnabled(
  WidgetTester tester,
  Finder finder,
) {
  return pumpUntil(
    tester,
    () {
      return finder.evaluate().isNotEmpty &&
          tester.widget<FilledButton>(finder).onPressed != null;
    },
    maxPumps: 80,
  );
}

Future<void> _pumpTracker(
  WidgetTester tester, {
  required _FakeTrackerServiceNotifier trackerNotifier,
  required TrackingStoreTestDouble store,
  Size size = const Size(1100, 900),
}) {
  return pumpAppAt(
    tester,
    initialLocation: AppRoutes.tracker,
    size: size,
    overrides: <Override>[
      trackerServiceNotifierProvider.overrideWith(() => trackerNotifier),
      sequenceRecordingProvider.overrideWith((ref) => true),
      trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      activityDaySummaryProvider
          .overrideWith((ref) async => _emptyDaySummary()),
      allTasksProvider.overrideWith((ref) => Stream.value(const <TaskItem>[])),
      allEventCalendarsProvider.overrideWith(
        (ref) => Stream.value(const <EventCalendar>[]),
      ),
      allTaskListsProvider.overrideWith(
        (ref) => Stream.value(const <TaskList>[]),
      ),
      trackingUploadServiceProvider.overrideWith(
        (ref) async => const _FakeTrackingUploadService(),
      ),
    ],
  );
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

class _FakeTrackerServiceNotifier extends TrackerServiceNotifier {
  _FakeTrackerServiceNotifier({required this.initialState});

  final TrackerState initialState;
  var refreshCalls = 0;
  var openUsageAccessSettingsCalls = 0;

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
    state = state.copyWith(
      isRunning: true,
      hasUsageStatsPermission: true,
      lastSampleAt: DateTime(2026, 6, 11, 11),
    );
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
