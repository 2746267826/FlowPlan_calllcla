import 'dart:async';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/tracker/services/activity_classifier.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flowplanv2/features/tracker/services/tracker_platform_source.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/features/tracker/services/window_sensor.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

final _sequenceRecordingToggleProvider = StateProvider<bool>((ref) => false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const androidUsageChannel = MethodChannel(
    'com.flowplanv2.app/android_usage_stats',
  );

  tearDown(() {
    debugTrackerPlatformOverride = null;
    debugRawInputServiceOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidUsageChannel, null);
  });

  test('TrackerState copyWith preserves clears and replaces display fields',
      () {
    final firstAt = DateTime(2026, 6, 10, 9);
    final nextAt = DateTime(2026, 6, 10, 10);
    final firstSnapshot = _snapshot('Code.exe', firstAt);
    final nextSnapshot = _snapshot('Chrome.exe', nextAt);
    const firstClassification = ActivityClassification(
      category: 'coding',
      label: 'VS Code',
      confidence: 0.9,
    );
    const nextClassification = ActivityClassification(
      category: 'browser',
      label: 'Chrome',
      confidence: 0.8,
    );
    final firstTelemetry = InputTelemetry.empty(firstAt).copyWith(keyCount: 3);
    final nextTelemetry = InputTelemetry.empty(nextAt).copyWith(keyCount: 7);
    final state = TrackerState(
      displaySnapshot: firstSnapshot,
      displayClassification: firstClassification,
      displaySessionStart: firstAt,
      displayTelemetry: firstTelemetry,
      isViewingExcludedApp: true,
      hasUsageStatsPermission: true,
      lastSampleAt: firstAt,
      lastError: 'old error',
    );

    final preserved = state.copyWith();
    expect(preserved.displaySnapshot, same(firstSnapshot));
    expect(preserved.displayClassification, same(firstClassification));
    expect(preserved.displaySessionStart, firstAt);
    expect(preserved.displayTelemetry, same(firstTelemetry));
    expect(preserved.isViewingExcludedApp, isTrue);
    expect(preserved.hasUsageStatsPermission, isTrue);
    expect(preserved.lastSampleAt, firstAt);
    expect(preserved.lastError, 'old error');

    final cleared = state.copyWith(
      displaySnapshot: null,
      displayClassification: null,
      displaySessionStart: null,
      displayTelemetry: null,
      isViewingExcludedApp: false,
      hasUsageStatsPermission: null,
      lastSampleAt: null,
      lastError: null,
    );
    expect(cleared.displaySnapshot, isNull);
    expect(cleared.displayClassification, isNull);
    expect(cleared.displaySessionStart, isNull);
    expect(cleared.displayTelemetry, isNull);
    expect(cleared.isViewingExcludedApp, isFalse);
    expect(cleared.hasUsageStatsPermission, isNull);
    expect(cleared.lastSampleAt, isNull);
    expect(cleared.lastError, isNull);

    final replaced = state.copyWith(
      displaySnapshot: nextSnapshot,
      displayClassification: nextClassification,
      displaySessionStart: nextAt,
      displayTelemetry: nextTelemetry,
      isViewingExcludedApp: false,
      hasUsageStatsPermission: false,
      lastSampleAt: nextAt,
      lastError: 'new error',
    );
    expect(replaced.displaySnapshot, same(nextSnapshot));
    expect(replaced.displayClassification, same(nextClassification));
    expect(replaced.displaySessionStart, nextAt);
    expect(replaced.displayTelemetry, same(nextTelemetry));
    expect(replaced.isViewingExcludedApp, isFalse);
    expect(replaced.hasUsageStatsPermission, isFalse);
    expect(replaced.lastSampleAt, nextAt);
    expect(replaced.lastError, 'new error');
  });

  test('public getters expose initial classifier telemetry and upload state',
      () {
    debugTrackerPlatformOverride = _unsupportedPlatform;
    final container = ProviderContainer(
      overrides: <Override>[
        sequenceRecordingProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    expect(notifier.classifier, isA<ActivityClassifier>());
    expect(notifier.currentTelemetry, isNull);
    expect(notifier.lastAutoUploadAt, isNull);
    expect(notifier.lastAutoUploadError, isNull);
    expect(notifier.isAutoUploading, isFalse);
  });

  test('unsupported collection mode keeps start refresh and stop as no-ops',
      () async {
    debugTrackerPlatformOverride = _unsupportedPlatform;
    final rawInput = _FakeRawInputService();
    debugRawInputServiceOverride = rawInput;
    final container = ProviderContainer(
      overrides: <Override>[
        sequenceRecordingProvider.overrideWith((ref) => false),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    notifier.start();
    await notifier.refreshNow();
    notifier.stop();
    await _flushAsync();

    final state = container.read(trackerServiceNotifierProvider);
    expect(state.isRunning, isFalse);
    expect(state.lastSampleAt, isNull);
    expect(state.lastError, isNull);
    expect(rawInput.startCount, 0);
    expect(rawInput.stopCount, 0);
    expect(rawInput.statsCount, 0);
    expect(rawInput.sequenceRecordingValues, isEmpty);
  });

  test('manual collection mode imports on start refresh and resets on stop',
      () async {
    debugTrackerPlatformOverride = const TrackerPlatformSource.testing(
      platformLabel: 'Android',
      collectionMode: TrackerCollectionMode.manualUsageStatsImport,
      supportsInputAnalytics: false,
      supportsSequenceRecording: false,
      supportsUsageAccessPermission: true,
      supportsDetailedInputHistory: false,
    );
    final rawInput = _FakeRawInputService();
    debugRawInputServiceOverride = rawInput;
    final db = createTestDatabase();
    addTearDown(db.close);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidUsageChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'getUsageAccessPermissionStatus' => false,
        _ => null,
      };
    });
    final container = _container(db);
    addTearDown(container.dispose);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    notifier.start();
    await _waitFor(
      () =>
          container
              .read(trackerServiceNotifierProvider)
              .hasUsageStatsPermission ==
          false,
    );
    await notifier.refreshNow();
    notifier.stop();
    await _waitFor(
      () => !container.read(trackerServiceNotifierProvider).isRunning,
    );

    final state = container.read(trackerServiceNotifierProvider);
    expect(state.currentTelemetry, isNull);
    expect(state.hasUsageStatsPermission, isNull);
    expect(calls.map((call) => call.method),
        everyElement('getUsageAccessPermissionStatus'));
    expect(calls.length, greaterThanOrEqualTo(2));
    expect(rawInput.startCount, 0);
    expect(rawInput.stopCount, 0);
    expect(rawInput.statsCount, 0);
    expect(rawInput.sequenceRecordingValues, isEmpty);
  });

  test('sequence recording provider changes are forwarded to fake raw input',
      () async {
    debugTrackerPlatformOverride =
        const TrackerPlatformSource.windowsForTesting();
    final rawInput = _FakeRawInputService();
    debugRawInputServiceOverride = rawInput;
    final container = ProviderContainer(
      overrides: <Override>[
        sequenceRecordingProvider.overrideWith(
          (ref) => ref.watch(_sequenceRecordingToggleProvider),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(trackerServiceNotifierProvider);
    await _waitFor(() => rawInput.sequenceRecordingValues.length == 1);
    container.read(_sequenceRecordingToggleProvider.notifier).state = true;
    await _waitFor(() => rawInput.sequenceRecordingValues.length == 2);

    expect(rawInput.sequenceRecordingValues, <bool>[false, true]);
    expect(rawInput.startCount, 0);
    expect(rawInput.stopCount, 0);
  });
}

const _unsupportedPlatform = TrackerPlatformSource.testing(
  platformLabel: 'Unsupported',
  collectionMode: TrackerCollectionMode.unsupported,
  supportsInputAnalytics: false,
  supportsSequenceRecording: false,
  supportsUsageAccessPermission: false,
  supportsDetailedInputHistory: false,
);

WindowSnapshot _snapshot(String processName, DateTime timestamp) {
  return WindowSnapshot(
    processName: processName,
    className: 'MainWindow',
    windowTitle: '$processName window',
    isFullscreen: false,
    timestamp: timestamp,
  );
}

ProviderContainer _container(AppDatabase db) {
  return ProviderContainer(
    overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      sequenceRecordingProvider.overrideWith((ref) => false),
    ],
  );
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(milliseconds: 1));
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Condition was not met within $timeout.');
    }
    await _flushAsync();
  }
}

class _FakeRawInputService extends RawInputService {
  _FakeRawInputService() : super(isWindows: () => true);

  final List<bool> sequenceRecordingValues = <bool>[];
  int startCount = 0;
  int stopCount = 0;
  int statsCount = 0;
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  String? get lastError => null;

  @override
  Future<void> start() async {
    startCount += 1;
    _running = true;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _running = false;
  }

  @override
  Future<void> setSequenceRecording(bool enabled) async {
    sequenceRecordingValues.add(enabled);
  }

  @override
  Future<InputTelemetry?> getStats() async {
    statsCount += 1;
    return null;
  }
}
