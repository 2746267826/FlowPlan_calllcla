import 'dart:async';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/server_api/tracking_ingest_api.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/features/tracker/services/tracker_platform_source.dart';
import 'package:flowplanv2/features/tracker/services/tracking_upload_service.dart';
import 'package:flowplanv2/features/tracker/models/tracked_input_event.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/temp_app_storage.dart';
import '../../test_support/test_database.dart';

final _sequenceRecordingToggleProvider = StateProvider<bool>((ref) => false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const rawInputChannel = MethodChannel('com.flowplanv2/raw_input');
  const androidUsageChannel = MethodChannel(
    'com.flowplanv2.app/android_usage_stats',
  );
  late RawInputService rawInputServiceUnderTest;

  setUp(() {
    rawInputServiceUnderTest = RawInputService(
      isWindows: () => true,
      channel: rawInputChannel,
    );
    debugRawInputServiceOverride = rawInputServiceUnderTest;
    debugTrackerPlatformOverride =
        const TrackerPlatformSource.windowsForTesting();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rawInputChannel, (call) async {
      return null;
    });
    await rawInputServiceUnderTest.stop();
    debugRawInputServiceOverride = null;
    debugTrackerPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rawInputChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidUsageChannel, null);
  });

  test('TrackerState copyWith preserves and explicitly clears nullable fields',
      () {
    final sampledAt = DateTime(2026, 6, 10, 9);
    final telemetry = InputTelemetry.empty(sampledAt).copyWith(keyCount: 3);
    final state = TrackerState(
      isRunning: true,
      activeRecordId: 42,
      currentTelemetry: telemetry,
      displayTelemetry: telemetry,
      hasUsageStatsPermission: true,
      lastSampleAt: sampledAt,
      lastError: 'old error',
    );

    final preserved = state.copyWith(isRunning: false);

    expect(preserved.isRunning, isFalse);
    expect(preserved.activeRecordId, 42);
    expect(preserved.currentTelemetry, same(telemetry));
    expect(preserved.displayTelemetry, same(telemetry));
    expect(preserved.hasUsageStatsPermission, isTrue);
    expect(preserved.lastSampleAt, sampledAt);
    expect(preserved.lastError, 'old error');

    final cleared = state.copyWith(
      activeRecordId: null,
      currentTelemetry: null,
      displayTelemetry: null,
      hasUsageStatsPermission: null,
      lastSampleAt: null,
      lastError: null,
    );

    expect(cleared.activeRecordId, isNull);
    expect(cleared.currentTelemetry, isNull);
    expect(cleared.displayTelemetry, isNull);
    expect(cleared.hasUsageStatsPermission, isNull);
    expect(cleared.lastSampleAt, isNull);
    expect(cleared.lastError, isNull);
  });

  test('start records RawInput channel failure and stop resets state',
      () async {
    final db = createTestDatabase();
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rawInputChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'start') {
        throw PlatformException(code: 'start_failed', message: 'denied');
      }
      return null;
    });
    final container = _container(db);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    try {
      notifier.start();
      await _waitFor(
        () => container.read(trackerServiceNotifierProvider).lastError != null,
      );

      expect(container.read(trackerServiceNotifierProvider).isRunning, isTrue);
      expect(
        container.read(trackerServiceNotifierProvider).lastError,
        contains('denied'),
      );
      expect(rawInputServiceUnderTest.isRunning, isFalse);
      expect(calls.where((method) => method == 'start'), hasLength(1));
    } finally {
      await _stopAndDispose(
        notifier: notifier,
        container: container,
        database: db,
      );
    }
  });

  test('start persists pending input events and acks highest sequence id',
      () async {
    await setUpTempAppStorage(prefix: 'tracker-service-input-');
    final db = createTestDatabase();
    final calls = <MethodCall>[];
    var pendingPollCount = 0;
    final eventAt = DateTime(2026, 6, 10, 10, 15);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rawInputChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'start' => null,
        'setSequenceRecording' => null,
        'getStats' => null,
        'getPendingInputEvents' => () {
            pendingPollCount += 1;
            if (pendingPollCount > 1) {
              return <Object?>[];
            }
            return <Object?>[
              <String, Object?>{
                'sequenceId': 8,
                'timestampMicros': eventAt.microsecondsSinceEpoch,
                'kind': 'key_down',
                'eventCount': 1,
                'keyCode': 65,
                'processName': 'Code.exe',
                'className': 'EditorWindow',
                'windowTitle': 'main.dart',
                'tokenText': 'A',
              },
              <String, Object?>{
                'sequenceId': 12,
                'timestampMicros': eventAt
                    .add(const Duration(milliseconds: 250))
                    .microsecondsSinceEpoch,
                'kind': 'mouse_button_down',
                'eventCount': 2,
                'mouseButton': 'left',
                'processName': 'Code.exe',
                'className': 'EditorWindow',
                'windowTitle': 'main.dart',
              },
            ];
          }(),
        'ackInputEvents' => null,
        'stop' => null,
        _ => null,
      };
    });
    final container = _container(db);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);
    final initialTick = container.read(activityLogRefreshTickProvider);

    try {
      notifier.start();
      await _waitFor(
        () => calls.any((call) => call.method == 'ackInputEvents'),
      );
      await _flushAsync();

      final ackCalls =
          calls.where((call) => call.method == 'ackInputEvents').toList();
      expect(ackCalls, hasLength(1));
      expect(
        ackCalls.single.arguments,
        <String, Object?>{'throughSequenceId': 12},
      );
      expect(
        calls
            .where((call) => call.method == 'getPendingInputEvents')
            .first
            .arguments,
        <String, Object?>{'maxEvents': 1000},
      );

      final events = await container
          .read(inputActivityEventServiceProvider)
          .listEvents(includeIgnored: true);
      expect(events.map((event) => event.sequenceId), <int>[8, 12]);
      expect(events.first.processName, 'Code.exe');
      expect(events.first.className, 'EditorWindow');
      expect(events.first.windowTitle, 'main.dart');
      expect(events.first.kind, TrackedInputEventKind.keyDown);
      expect(events.first.keyCode, 65);
      expect(events.first.keyLabel, 'A');
      expect(events.first.tokenText, 'A');
      expect(events.last.kind, TrackedInputEventKind.mouseButtonDown);
      expect(events.last.eventCount, 2);
      expect(events.last.mouseButton, 'left');
      expect(
        container.read(activityLogRefreshTickProvider),
        greaterThan(initialTick),
      );
    } finally {
      await _stopAndDispose(
        notifier: notifier,
        container: container,
        database: db,
      );
    }
  });

  test('start polls empty input events without acking them', () async {
    final db = createTestDatabase();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rawInputChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'start' => null,
        'setSequenceRecording' => null,
        'getStats' => null,
        'getPendingInputEvents' => <Object?>[],
        'stop' => null,
        _ => null,
      };
    });
    final container = _container(db);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    try {
      notifier.start();
      await _waitFor(
        () => calls.any((call) => call.method == 'getPendingInputEvents'),
      );

      expect(rawInputServiceUnderTest.isRunning, isTrue);
      expect(
        calls.map((call) => call.method),
        containsAll(<String>['start', 'getPendingInputEvents']),
      );
      expect(
        calls.where((call) => call.method == 'ackInputEvents'),
        isEmpty,
      );
    } finally {
      await _stopAndDispose(
        notifier: notifier,
        container: container,
        database: db,
      );
    }
  });

  test('sequence recording provider changes are forwarded to RawInput',
      () async {
    final db = createTestDatabase();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rawInputChannel, (call) async {
      calls.add(call);
      return null;
    });
    final container = ProviderContainer(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        sequenceRecordingProvider.overrideWith(
          (ref) => ref.watch(_sequenceRecordingToggleProvider),
        ),
      ],
    );

    try {
      container.read(trackerServiceNotifierProvider);
      await _waitFor(
        () => calls.any((call) => call.method == 'setSequenceRecording'),
      );

      container.read(_sequenceRecordingToggleProvider.notifier).state = true;
      await _waitFor(
        () =>
            calls
                .where((call) => call.method == 'setSequenceRecording')
                .length >=
            2,
      );

      final sequenceCalls =
          calls.where((call) => call.method == 'setSequenceRecording').toList();
      expect(sequenceCalls, hasLength(2));
      expect(sequenceCalls.first.arguments, <String, Object?>{'enabled': true});
      expect(sequenceCalls.last.arguments, <String, Object?>{'enabled': true});
      expect(rawInputServiceUnderTest.lastError, isNull);
    } finally {
      container.dispose();
      await db.close();
    }
  });

  test('unsupported platform leaves start and refresh as service no-ops',
      () async {
    debugTrackerPlatformOverride = const TrackerPlatformSource.testing(
      platformLabel: 'Unsupported',
      collectionMode: TrackerCollectionMode.unsupported,
      supportsInputAnalytics: false,
      supportsSequenceRecording: false,
      supportsUsageAccessPermission: false,
      supportsDetailedInputHistory: false,
    );
    final db = createTestDatabase();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rawInputChannel, (call) async {
      calls.add(call);
      return null;
    });
    final container = _container(db);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    try {
      notifier.start();
      await notifier.refreshNow();
      await _flushAsync();

      expect(container.read(trackerServiceNotifierProvider).isRunning, isFalse);
      expect(rawInputServiceUnderTest.isRunning, isFalse);
      expect(calls, isEmpty);
    } finally {
      container.dispose();
      await db.close();
    }
  });

  test('manual Android import records permission state and degrades on errors',
      () async {
    debugTrackerPlatformOverride = const TrackerPlatformSource.testing(
      platformLabel: 'Android',
      collectionMode: TrackerCollectionMode.manualUsageStatsImport,
      supportsInputAnalytics: false,
      supportsSequenceRecording: false,
      supportsUsageAccessPermission: true,
      supportsDetailedInputHistory: false,
    );
    final db = createTestDatabase();
    final calls = <MethodCall>[];
    var throwOnPermissionProbe = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(androidUsageChannel, (call) async {
      calls.add(call);
      if (throwOnPermissionProbe) {
        throw PlatformException(code: 'usage_denied', message: 'blocked');
      }
      return switch (call.method) {
        'getUsageAccessPermissionStatus' => false,
        _ => null,
      };
    });
    final container = _container(db);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    try {
      notifier.start();
      await _waitFor(
        () =>
            container
                .read(trackerServiceNotifierProvider)
                .hasUsageStatsPermission ==
            false,
      );

      final stateAfterStart = container.read(trackerServiceNotifierProvider);
      expect(stateAfterStart.isRunning, isTrue);
      expect(stateAfterStart.hasUsageStatsPermission, isFalse);
      expect(stateAfterStart.currentTelemetry, isNotNull);
      expect(calls.map((call) => call.method),
          contains('getUsageAccessPermissionStatus'));
      expect(rawInputServiceUnderTest.isRunning, isFalse);

      throwOnPermissionProbe = true;
      await notifier.refreshNow();
      await _flushAsync();
      final stateAfterFailedRefresh =
          container.read(trackerServiceNotifierProvider);
      expect(stateAfterFailedRefresh.isRunning, isTrue);
      expect(stateAfterFailedRefresh.lastSampleAt, isNotNull);

      notifier.stop();
      await _waitFor(
        () => !container.read(trackerServiceNotifierProvider).isRunning,
      );
      expect(container.read(trackerServiceNotifierProvider).currentTelemetry,
          isNull);
    } finally {
      container.dispose();
      await db.close();
    }
  });

  test('provider upload service path records failure while tracker is running',
      () async {
    final db = createTestDatabase();
    final api = _FakeTrackingIngestApi(
      completeResponse: <String, Object?>{
        'ok': false,
        'reason': 'server offline',
      },
    );
    final uploadService = TrackingUploadService(
      database: db,
      api: api,
      operationLogs: DataOperationLogRepository(db),
    );
    await _insertActivityRecord(db, DateTime(2026, 6, 10, 9));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(rawInputChannel, (call) async {
      return switch (call.method) {
        'start' => null,
        'setSequenceRecording' => null,
        'getStats' => null,
        'getPendingInputEvents' => <Object?>[],
        'stop' => null,
        _ => null,
      };
    });
    final container = _container(
      db,
      overrides: <Override>[
        trackingUploadServiceProvider.overrideWith(
          (ref) async => uploadService,
        ),
      ],
    );
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    try {
      notifier.start();
      await _waitFor(() => rawInputServiceUnderTest.isRunning);

      await uploadService.uploadPending().catchError((_) {
        return const TrackingUploadResult(
          uploadedBatches: 0,
          uploadedRecords: 0,
          details: <Map<String, Object?>>[],
        );
      });

      expect(api.createCallCount, 1);
      expect(notifier.isAutoUploading, isFalse);
    } finally {
      await _stopAndDispose(
        notifier: notifier,
        container: container,
        database: db,
      );
    }
  });
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

Future<void> _stopAndDispose({
  required TrackerServiceNotifier notifier,
  required ProviderContainer container,
  required AppDatabase database,
}) async {
  notifier.stop();
  await _waitFor(
    () => !container.read(trackerServiceNotifierProvider).isRunning,
  );
  await _flushAsync();
  container.dispose();
  await database.close();
}

ProviderContainer _container(
  AppDatabase db, {
  List<Override> overrides = const <Override>[],
}) {
  return ProviderContainer(
    overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      sequenceRecordingProvider.overrideWith((ref) => true),
      ...overrides,
    ],
  );
}

Future<void> _insertActivityRecord(AppDatabase db, DateTime start) async {
  await db.customStatement(
    '''
    INSERT INTO activity_records (
      start_time,
      end_time,
      duration_minutes,
      process_name,
      window_title,
      category,
      is_auto,
      source
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''',
    <Object?>[
      start.toIso8601String(),
      start.add(const Duration(minutes: 5)).toIso8601String(),
      5,
      'Code.exe',
      'main.dart',
      'coding',
      1,
      'test',
    ],
  );
}

class _FakeTrackingIngestApi implements TrackingIngestApi {
  _FakeTrackingIngestApi({this.completeResponse = const <String, Object?>{}});

  final Map<String, Object?> completeResponse;
  int createCallCount = 0;

  @override
  Future<Map<String, dynamic>> createBatch({
    required String batchUid,
    required String dataKind,
    DateTime? startAt,
    DateTime? endAt,
    String compression = 'none',
    List<Map<String, dynamic>> records = const [],
    Map<String, dynamic> metadata = const {},
  }) async {
    createCallCount += 1;
    return <String, dynamic>{'batchId': 'batch-$createCallCount'};
  }

  @override
  Future<Map<String, dynamic>> uploadChunk({
    required String batchId,
    required int chunkIndex,
    List<Map<String, dynamic>> records = const [],
    Uint8List? compressedJsonBytes,
    String? checksum,
  }) async {
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> completeBatch({
    required String batchId,
    List<Map<String, dynamic>> records = const [],
  }) async {
    return Map<String, dynamic>.from(completeResponse);
  }

  @override
  Future<Map<String, dynamic>> summary({DateTime? start, DateTime? end}) async {
    return <String, dynamic>{};
  }
}
