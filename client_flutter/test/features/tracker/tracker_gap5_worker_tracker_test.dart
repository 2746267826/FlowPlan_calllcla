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
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    debugRawInputServiceOverride = null;
    debugTrackerPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_androidUsageChannel, null);
  });

  test(
      'tracker state copyWith preserves unset fields and clears nullable fields',
      () {
    final sampledAt = DateTime(2026, 6, 11, 9, 30);
    final snapshot = WindowSnapshot(
      processName: 'Code.exe',
      className: 'Chrome_WidgetWin_1',
      windowTitle: 'tracker_gap5_worker_tracker_test.dart',
      isFullscreen: true,
      timestamp: sampledAt,
    );
    const classification = ActivityClassification(
      category: 'coding',
      label: 'VS Code',
      confidence: 0.92,
    );
    final telemetry = InputTelemetry(
      keyCount: 7,
      keyDistribution: const <int, int>{65: 7},
      keySequence: 'AAAAAAA',
      clicks: const MouseClicks(left: 2, xButton1: 1),
      scrollPx: 120,
      mouseMovePx: 640,
      timestamp: sampledAt,
      inputEvents: const <RawInputEvent>[],
    );
    final state = TrackerState(
      isRunning: true,
      currentSnapshot: snapshot,
      currentClassification: classification,
      sessionStart: sampledAt.subtract(const Duration(minutes: 5)),
      activeRecordId: 42,
      currentTelemetry: telemetry,
      displaySnapshot: snapshot,
      displayClassification: classification,
      displaySessionStart: sampledAt.subtract(const Duration(minutes: 5)),
      displayTelemetry: telemetry,
      isViewingExcludedApp: true,
      hasUsageStatsPermission: false,
      lastSampleAt: sampledAt,
      lastError: 'raw input warning',
    );

    final preserved = state.copyWith(isRunning: false);

    expect(preserved.isRunning, isFalse);
    expect(preserved.currentSnapshot, same(snapshot));
    expect(preserved.currentClassification, same(classification));
    expect(preserved.currentTelemetry, same(telemetry));
    expect(preserved.displayTelemetry, same(telemetry));
    expect(preserved.hasUsageStatsPermission, isFalse);
    expect(preserved.lastError, 'raw input warning');

    final cleared = state.copyWith(
      currentSnapshot: null,
      currentClassification: null,
      sessionStart: null,
      activeRecordId: null,
      currentTelemetry: null,
      displaySnapshot: null,
      displayClassification: null,
      displaySessionStart: null,
      displayTelemetry: null,
      isViewingExcludedApp: false,
      hasUsageStatsPermission: null,
      lastSampleAt: null,
      lastError: null,
    );

    expect(cleared.currentSnapshot, isNull);
    expect(cleared.currentClassification, isNull);
    expect(cleared.sessionStart, isNull);
    expect(cleared.activeRecordId, isNull);
    expect(cleared.currentTelemetry, isNull);
    expect(cleared.displaySnapshot, isNull);
    expect(cleared.displayClassification, isNull);
    expect(cleared.displaySessionStart, isNull);
    expect(cleared.displayTelemetry, isNull);
    expect(cleared.isViewingExcludedApp, isFalse);
    expect(cleared.hasUsageStatsPermission, isNull);
    expect(cleared.lastSampleAt, isNull);
    expect(cleared.lastError, isNull);
  });

  test('unsupported tracker platform leaves start and refresh as no-ops',
      () async {
    debugTrackerPlatformOverride = const TrackerPlatformSource.testing(
      platformLabel: 'Unsupported desktop',
      collectionMode: TrackerCollectionMode.unsupported,
      supportsInputAnalytics: false,
      supportsSequenceRecording: false,
      supportsUsageAccessPermission: false,
      supportsDetailedInputHistory: false,
    );
    final rawInput = _FakeRawInputService();
    debugRawInputServiceOverride = rawInput;
    final db = createTestDatabase();
    addTearDown(db.close);
    final container = _container(db);
    addTearDown(container.dispose);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    notifier.start();
    await _flushAsync();
    await notifier.refreshNow();
    notifier.stop();
    await _flushAsync();

    final state = container.read(trackerServiceNotifierProvider);
    expect(state.isRunning, isFalse);
    expect(state.currentSnapshot, isNull);
    expect(state.currentTelemetry?.keyCount, anyOf(isNull, 0));
    expect(state.lastSampleAt, isNull);
    expect(rawInput.startCount, 0);
    expect(rawInput.pendingPollCount, 0);
    expect(rawInput.stopCount, 0);
  });

  test('Android usage import failures settle tracker state without permission',
      () async {
    _mockAndroidUsageStats((call) async {
      throw PlatformException(
        code: 'usage_bridge_failed',
        message: 'usage stats unavailable',
      );
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

    final state = container.read(trackerServiceNotifierProvider);
    expect(state.isRunning, isTrue);
    expect(state.hasUsageStatsPermission, isNull);
    expect(state.currentSnapshot, isNull);
    expect(state.lastSampleAt, isNotNull);
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
      sequenceRecordingProvider.overrideWith((ref) => false),
    ],
  );
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(milliseconds: 1));
}

class _FakeRawInputService extends RawInputService {
  _FakeRawInputService() : super(isWindows: () => true);

  var startCount = 0;
  var stopCount = 0;
  var pendingPollCount = 0;
  var _running = false;

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
  Future<List<RawInputEvent>> getPendingInputEvents({
    int maxEvents = 1000,
  }) async {
    pendingPollCount += 1;
    return const <RawInputEvent>[];
  }
}
