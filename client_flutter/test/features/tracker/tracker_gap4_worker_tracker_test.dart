import 'dart:async';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/tracker/models/activity_insights.dart';
import 'package:flowplanv2/features/tracker/services/tracker_platform_source.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/temp_app_storage.dart';
import '../../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    debugTrackerPlatformOverride = null;
    debugTrackerWindowCaptureOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_androidUsageChannel, null);
  });

  group('TrackerPlatformSource gap4 branches', () {
    test('testing fallback exposes unsupported flags and description', () {
      const source = TrackerPlatformSource.testing(
        platformLabel: 'Desktop fallback',
        collectionMode: TrackerCollectionMode.unsupported,
        supportsInputAnalytics: false,
        supportsSequenceRecording: false,
        supportsUsageAccessPermission: false,
        supportsDetailedInputHistory: false,
      );

      expect(source.isWindows, isFalse);
      expect(source.isAndroid, isFalse);
      expect(source.isSupported, isFalse);
      expect(source.collectionDescription, contains('不支持'));
    });

    test('current host platform reports a coherent collection mode', () {
      final source = TrackerPlatformSource.current();

      expect(source.platformLabel.trim(), isNotEmpty);
      expect(source.collectionDescription.trim(), isNotEmpty);
      expect(
        source.isSupported,
        source.collectionMode != TrackerCollectionMode.unsupported,
      );
      expect(
        source.isAndroid,
        source.collectionMode == TrackerCollectionMode.manualUsageStatsImport,
      );
      expect(
        source.isWindows,
        source.collectionMode == TrackerCollectionMode.continuousWindowSampling,
      );
    });
  });

  group('ActivityInsights gap4 branches', () {
    test('productive count falls back to input-bearing records only', () {
      final base = DateTime(2026, 6, 11, 9);

      final insights = ActivityInsights.fromRecords(<ActivityRecord>[
        _record(
          id: 1,
          start: base,
          processName: null,
          windowTitle: '  Untitled notes  ',
          category: null,
          keyCount: 0,
          mouseClicks: 0,
          mouseMovePx: 0,
          scrollPx: 0,
        ),
        _record(
          id: 2,
          start: base.add(const Duration(minutes: 10)),
          processName: '  Code.exe  ',
          windowTitle: 'main.dart',
          category: '  coding  ',
          keyCount: 8,
          mouseClicks: 0,
          mouseMovePx: 0,
          scrollPx: 0,
          keySequence: 'abc',
        ),
        _record(
          id: 3,
          start: base.add(const Duration(minutes: 20)),
          processName: null,
          windowTitle: null,
          category: null,
          keyCount: 0,
          mouseClicks: 1,
          mouseMovePx: 0,
          scrollPx: 0,
        ),
      ]);

      expect(insights.productiveRecordCount, 2);
      expect(insights.sequenceRecordCount, 1);
      expect(insights.focusMinutes, 10);
      expect(insights.topProcesses.map((slice) => slice.label), containsAll(
        <String>['Untitled notes', 'Code.exe', '未知应用'],
      ));
      expect(insights.topCategories.map((slice) => slice.label), containsAll(
        <String>['coding', '未分类'],
      ));
      expect(insights.busiestRecords.first.record.id, 2);
    });

    test('productive count override wins over derived record inputs', () {
      final insights = ActivityInsights(
        records: <ActivityRecord>[
          _record(
            id: 10,
            start: DateTime(2026, 6, 11, 10),
            keyCount: 5,
          ),
        ],
        totalMinutes: 5,
        focusMinutes: 5,
        totalKeys: 5,
        totalClicks: 0,
        totalMovePx: 0,
        totalScrollPx: 0,
        sequenceRecordCount: 0,
        productiveRecordCountOverride: 0,
        topProcesses: const <ActivityInsightSlice>[],
        topCategories: const <ActivityInsightSlice>[],
        busiestRecords: const <ActivityInsightRecord>[],
      );

      expect(insights.productiveRecordCount, 0);
      expect(insights.keysPerMinute, 1);
      expect(insights.clickPerHour, 0);
    });
  });

  group('TrackerService Android manual import gap4 branches', () {
    test('manual import records denied usage access without crashing',
        () async {
      final calls = <MethodCall>[];
      _mockAndroidUsageStats((call) async {
        calls.add(call);
        if (call.method == 'getUsageAccessPermissionStatus') {
          return false;
        }
        return null;
      });
      debugTrackerPlatformOverride = const TrackerPlatformSource.testing(
        platformLabel: 'Android',
        collectionMode: TrackerCollectionMode.manualUsageStatsImport,
        supportsInputAnalytics: false,
        supportsSequenceRecording: false,
        supportsUsageAccessPermission: true,
        supportsDetailedInputHistory: false,
      );
      final db = createTestDatabase();
      addTearDown(db.close);
      final container = _container(db);
      addTearDown(container.dispose);
      final notifier = container.read(trackerServiceNotifierProvider.notifier);

      notifier.start();
      await _waitFor(() =>
          container.read(trackerServiceNotifierProvider).hasUsageStatsPermission ==
          false);

      final state = container.read(trackerServiceNotifierProvider);
      expect(state.isRunning, isTrue);
      expect(state.currentTelemetry?.keyCount, 0);
      expect(state.lastSampleAt, isNotNull);
      expect(calls.map((call) => call.method),
          contains('getUsageAccessPermissionStatus'));

      notifier.stop();
      await _flushAsync();
      expect(container.read(trackerServiceNotifierProvider).isRunning, isFalse);
    });

    test('manual refresh imports empty Android usage window and sets permission',
        () async {
      final calls = <MethodCall>[];
      _mockAndroidUsageStats((call) async {
        calls.add(call);
        return switch (call.method) {
          'getUsageAccessPermissionStatus' => true,
          'queryUsageEvents' => const <Object?>[],
          _ => null,
        };
      });
      debugTrackerPlatformOverride = const TrackerPlatformSource.testing(
        platformLabel: 'Android',
        collectionMode: TrackerCollectionMode.manualUsageStatsImport,
        supportsInputAnalytics: false,
        supportsSequenceRecording: false,
        supportsUsageAccessPermission: true,
        supportsDetailedInputHistory: false,
      );
      final db = createTestDatabase();
      addTearDown(db.close);
      final container = _container(db);
      addTearDown(container.dispose);
      final notifier = container.read(trackerServiceNotifierProvider.notifier);

      await notifier.refreshNow();
      await _waitFor(() =>
          container.read(trackerServiceNotifierProvider).hasUsageStatsPermission ==
          true);

      final state = container.read(trackerServiceNotifierProvider);
      expect(state.isRunning, isTrue);
      expect(state.currentSnapshot, isNull);
      expect(state.currentTelemetry?.keyCount, 0);
      expect(calls.map((call) => call.method), containsAll(<String>[
        'getUsageAccessPermissionStatus',
        'queryUsageEvents',
      ]));
    });

    test('opens Android usage settings through injected platform source',
        () async {
      final calls = <MethodCall>[];
      _mockAndroidUsageStats((call) async {
        calls.add(call);
        return null;
      });
      debugTrackerPlatformOverride = const TrackerPlatformSource.testing(
        platformLabel: 'Android',
        collectionMode: TrackerCollectionMode.manualUsageStatsImport,
        supportsInputAnalytics: false,
        supportsSequenceRecording: false,
        supportsUsageAccessPermission: true,
        supportsDetailedInputHistory: false,
      );
      final db = createTestDatabase();
      addTearDown(db.close);
      final container = _container(db);
      addTearDown(container.dispose);
      final notifier = container.read(trackerServiceNotifierProvider.notifier);

      await notifier.openAndroidUsageAccessSettings();

      expect(calls.map((call) => call.method), <String>[
        'openUsageAccessSettings',
      ]);
    });

    test('manual refresh with imported sessions notifies log listeners',
        () async {
      await setUpTempAppStorage(prefix: 'tracker-gap4-service-import-');
      final base = DateTime.now().subtract(const Duration(minutes: 30));
      final calls = <MethodCall>[];
      _mockAndroidUsageStats((call) async {
        calls.add(call);
        return switch (call.method) {
          'getUsageAccessPermissionStatus' => true,
          'queryUsageEvents' => <Object?>[
              <String, Object?>{
                'timestampMillis': base.millisecondsSinceEpoch,
                'packageName': 'com.example.editor',
                'eventType': 'activity_resumed',
                'className': 'MainActivity',
                'appLabel': 'Editor',
              },
              <String, Object?>{
                'timestampMillis':
                    base.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
                'packageName': 'com.example.editor',
                'eventType': 'activity_paused',
                'className': 'MainActivity',
                'appLabel': 'Editor',
              },
            ],
          _ => null,
        };
      });
      debugTrackerPlatformOverride = const TrackerPlatformSource.testing(
        platformLabel: 'Android',
        collectionMode: TrackerCollectionMode.manualUsageStatsImport,
        supportsInputAnalytics: false,
        supportsSequenceRecording: false,
        supportsUsageAccessPermission: true,
        supportsDetailedInputHistory: false,
      );
      final db = createTestDatabase();
      addTearDown(db.close);
      final container = _container(db);
      addTearDown(container.dispose);
      final notifier = container.read(trackerServiceNotifierProvider.notifier);
      final initialTick = container.read(activityLogRefreshTickProvider);

      await notifier.refreshNow();

      final state = container.read(trackerServiceNotifierProvider);
      expect(state.currentSnapshot?.processName, 'Editor');
      expect(state.hasUsageStatsPermission, isTrue);
      expect(
        container.read(activityLogRefreshTickProvider),
        initialTick + 1,
      );
      expect(calls.map((call) => call.method), containsAll(<String>[
        'getUsageAccessPermissionStatus',
        'queryUsageEvents',
      ]));
    });
  });

  group('TrackerService sampling gap4 branches', () {
    test('refresh records a sample timestamp when no window is captured',
        () async {
      debugTrackerPlatformOverride = const TrackerPlatformSource.windowsForTesting();
      debugTrackerWindowCaptureOverride = () => null;
      final db = createTestDatabase();
      addTearDown(db.close);
      final container = _container(db);
      addTearDown(container.dispose);
      final notifier = container.read(trackerServiceNotifierProvider.notifier);

      await notifier.refreshNow();

      final state = container.read(trackerServiceNotifierProvider);
      expect(state.currentSnapshot, isNull);
      expect(state.lastSampleAt, isNotNull);
      expect(state.lastError, isNull);
    });
  });
}

const _androidUsageChannel =
    MethodChannel('com.flowplanv2.app/android_usage_stats');

void _mockAndroidUsageStats(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_androidUsageChannel, handler);
}

ProviderContainer _container(AppDatabase db) {
  return ProviderContainer(
    overrides: <Override>[
      databaseProvider.overrideWithValue(db),
    ],
  );
}

ActivityRecord _record({
  required int id,
  required DateTime start,
  int durationMinutes = 5,
  String? processName = 'Code.exe',
  String? windowTitle = 'main.dart',
  String? category = 'coding',
  int keyCount = 0,
  int mouseClicks = 0,
  int mouseMovePx = 0,
  int scrollPx = 0,
  String? keySequence,
}) {
  return ActivityRecord(
    id: id,
    startTime: start,
    endTime: start.add(Duration(minutes: durationMinutes)),
    durationMinutes: durationMinutes,
    manualLabel: null,
    processName: processName,
    windowTitle: windowTitle,
    category: category,
    keyCount: keyCount,
    mouseClicks: mouseClicks,
    mouseMovePx: mouseMovePx,
    scrollPx: scrollPx,
    keySequence: keySequence,
    isAuto: true,
    source: 'tracker-gap4-worker-tracker-test',
  );
}

Future<void> _waitFor(
  FutureOr<bool> Function() condition, {
  Duration timeout = const Duration(seconds: 4),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met within $timeout.');
    }
    await _flushAsync();
  }
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(milliseconds: 1));
}
