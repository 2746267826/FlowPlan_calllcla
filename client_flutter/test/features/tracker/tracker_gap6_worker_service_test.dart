import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/server_api/tracking_ingest_api.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/tracker/models/activity_log_entry.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flowplanv2/features/tracker/services/tracker_platform_source.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/features/tracker/services/tracking_upload_service.dart';
import 'package:flowplanv2/features/tracker/services/window_sensor.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/temp_app_storage.dart';
import '../../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    debugTrackerPlatformOverride =
        const TrackerPlatformSource.windowsForTesting();
  });

  tearDown(() {
    debugRawInputServiceOverride = null;
    debugTrackerPlatformOverride = null;
    debugTrackerWindowCaptureOverride = null;
    debugTrackerSampleIntervalOverride = null;
    debugTrackerInputEventPollIntervalOverride = null;
    debugTrackerAutoUploadIntervalOverride = null;
    debugTrackerSampleTimeoutOverride = null;
    debugTrackerInputEventPollTimeoutOverride = null;
  });

  test('refresh samples same context deltas and persists bound input events',
      () async {
    await setUpTempAppStorage(prefix: 'tracker-gap6-same-context-');
    final db = createTestDatabase();
    addTearDown(db.close);
    final rawInput = _FakeRawInputService()
      ..statsQueue.addAll(<Future<InputTelemetry?>>[
        Future<InputTelemetry?>.value(
          _telemetry(
            at: DateTime(2026, 6, 11, 9),
            keys: 2,
            events: <RawInputEvent>[
              _rawEvent(1, DateTime(2026, 6, 11, 9), keyCode: 65),
            ],
          ),
        ),
        Future<InputTelemetry?>.value(
          _telemetry(
            at: DateTime(2026, 6, 11, 9, 1),
            keys: 5,
            clicks: const MouseClicks(left: 2),
            movePx: 300,
            events: <RawInputEvent>[
              _rawEvent(2, DateTime(2026, 6, 11, 9, 1), keyCode: 66),
            ],
          ),
        ),
      ]);
    debugRawInputServiceOverride = rawInput;
    final snapshots = <WindowSnapshot>[
      _snapshot(
        processName: 'Code.exe',
        className: 'Chrome_WidgetWin_1',
        windowTitle: 'first.dart',
        timestamp: DateTime(2026, 6, 11, 9),
      ),
      _snapshot(
        processName: 'Code.exe',
        className: 'Chrome_WidgetWin_1',
        windowTitle: 'second.dart',
        timestamp: DateTime(2026, 6, 11, 9, 1),
      ),
    ];
    debugTrackerWindowCaptureOverride = () => snapshots.removeAt(0);
    final container = _container(db);
    addTearDown(container.dispose);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    await notifier.refreshNow();
    final stateAfterOpen = container.read(trackerServiceNotifierProvider);
    final openedRecordId = stateAfterOpen.activeRecordId;
    expect(openedRecordId, isNotNull);

    await notifier.refreshNow();

    final state = container.read(trackerServiceNotifierProvider);
    expect(state.currentSnapshot?.windowTitle, 'second.dart');
    expect(state.displaySnapshot?.windowTitle, 'second.dart');
    expect(state.currentTelemetry?.keyCount, 3);
    expect(state.currentTelemetry?.clicks.left, 2);
    expect(state.currentTelemetry?.mouseMovePx, 300);
    expect(state.sessionStart, DateTime(2026, 6, 11, 9));
    expect(state.activeRecordId, openedRecordId);

    final events = await container
        .read(inputActivityEventServiceProvider)
        .listEvents(includeIgnored: true);
    expect(events.map((event) => event.sequenceId), <int>[1, 2]);
    expect(events.every((event) => event.recordId == openedRecordId), isTrue);
    expect(events.every((event) => !event.isIgnored), isTrue);

    final logs = await container
        .read(activityLogServiceProvider)
        .readEntriesForDate(DateTime(2026, 6, 11));
    expect(
      logs.map((entry) => entry.type),
      containsAll(<ActivityLogEntryType>[
        ActivityLogEntryType.sessionOpen,
        ActivityLogEntryType.sessionUpdate,
        ActivityLogEntryType.sample,
      ]),
    );
  });

  test(
      'self excluded foreground closes active record and freezes display state',
      () async {
    await setUpTempAppStorage(prefix: 'tracker-gap6-self-excluded-');
    final db = createTestDatabase();
    addTearDown(db.close);
    final rawInput = _FakeRawInputService()
      ..statsQueue.addAll(<Future<InputTelemetry?>>[
        Future<InputTelemetry?>.value(
          _telemetry(at: DateTime(2026, 6, 11, 10), keys: 1),
        ),
        Future<InputTelemetry?>.value(
          _telemetry(
            at: DateTime(2026, 6, 11, 10, 2),
            keys: 4,
            events: <RawInputEvent>[
              _rawEvent(10, DateTime(2026, 6, 11, 10, 2), keyCode: 70),
            ],
          ),
        ),
      ]);
    debugRawInputServiceOverride = rawInput;
    final normal = _snapshot(
      processName: 'Code.exe',
      className: 'EditorWindow',
      windowTitle: 'project.dart',
      timestamp: DateTime(2026, 6, 11, 10),
    );
    final excluded = _snapshot(
      processName: 'flowplanv2.exe',
      className: 'FlutterWindow',
      windowTitle: 'FlowPlanV2 tracker',
      timestamp: DateTime(2026, 6, 11, 10, 2),
    );
    final snapshots = <WindowSnapshot>[normal, excluded];
    debugTrackerWindowCaptureOverride = () => snapshots.removeAt(0);
    final container = _container(db);
    addTearDown(container.dispose);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    await notifier.refreshNow();
    final activeRecordId =
        container.read(trackerServiceNotifierProvider).activeRecordId;
    expect(activeRecordId, isNotNull);

    await notifier.refreshNow();

    final state = container.read(trackerServiceNotifierProvider);
    expect(state.isViewingExcludedApp, isTrue);
    expect(state.activeRecordId, isNull);
    expect(state.sessionStart, isNull);
    expect(state.currentSnapshot?.processName, 'flowplanv2.exe');
    expect(state.displaySnapshot?.processName, 'Code.exe');
    expect(state.displaySnapshot?.windowTitle, 'project.dart');

    final record = await _recordById(db, activeRecordId!);
    expect(record?['end_time'], isNotNull);

    final logs = await container
        .read(activityLogServiceProvider)
        .readEntriesForDate(DateTime(2026, 6, 11));
    final ignoredSample = logs.lastWhere(
      (entry) => entry.note == 'foreground_self_excluded',
    );
    expect(ignoredSample.isIgnored, isTrue);
    expect(ignoredSample.processName, 'flowplanv2.exe');
    expect(ignoredSample.recordId, isNull);
  });

  test('sample errors and timeouts settle without leaving in-flight state',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final rawInput = _FakeRawInputService()
      ..statsQueue.add(
        Future<InputTelemetry?>.error(StateError('stats exploded')),
      );
    debugRawInputServiceOverride = rawInput;
    debugTrackerWindowCaptureOverride = () => _snapshot(
          processName: 'Code.exe',
          className: 'EditorWindow',
          windowTitle: 'main.dart',
          timestamp: DateTime(2026, 6, 11, 11),
        );
    final container = _container(db);
    addTearDown(container.dispose);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    await notifier.refreshNow();
    expect(
      container.read(trackerServiceNotifierProvider).lastError,
      contains('stats exploded'),
    );

    debugTrackerSampleTimeoutOverride = const Duration(milliseconds: 1);
    final timeoutDb = createTestDatabase();
    addTearDown(timeoutDb.close);
    final timeoutRawInput = _FakeRawInputService()
      ..statsQueue.add(Completer<InputTelemetry?>().future);
    debugRawInputServiceOverride = timeoutRawInput;
    final timeoutContainer = _container(timeoutDb);
    addTearDown(timeoutContainer.dispose);
    final timeoutNotifier =
        timeoutContainer.read(trackerServiceNotifierProvider.notifier);

    await timeoutNotifier.refreshNow();
    expect(timeoutRawInput.statsCount, 1);
    expect(timeoutContainer.read(trackerServiceNotifierProvider).lastError,
        isNull);
  });

  test('periodic timers sample null snapshots and record upload success errors',
      () async {
    await setUpTempAppStorage(prefix: 'tracker-gap6-timers-upload-');
    final db = createTestDatabase();
    await _insertClosedActivityRecord(db, DateTime(2026, 6, 11, 12));
    var captureCount = 0;
    debugTrackerWindowCaptureOverride = () {
      captureCount += 1;
      return null;
    };
    debugTrackerSampleIntervalOverride = const Duration(milliseconds: 10);
    debugTrackerInputEventPollIntervalOverride =
        const Duration(milliseconds: 10);
    debugTrackerAutoUploadIntervalOverride = const Duration(milliseconds: 10);
    debugTrackerInputEventPollTimeoutOverride = const Duration(milliseconds: 1);
    final rawInput = _FakeRawInputService()
      ..pendingEventsQueue.add(Completer<List<RawInputEvent>>().future);
    debugRawInputServiceOverride = rawInput;
    final api = _FakeTrackingIngestApi();
    final uploadService = TrackingUploadService(
      database: db,
      api: api,
      operationLogs: DataOperationLogRepository(db),
    );
    final container = _container(
      db,
      overrides: <Override>[
        trackingUploadServiceProvider
            .overrideWith((ref) async => uploadService),
      ],
    );
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    try {
      notifier.start();
      await _waitFor(() => captureCount > 1);
      await _waitFor(() => api.successfulDataKinds.isNotEmpty);
      expect(api.successfulDataKinds, contains('activity_record'));
      expect(api.createCallCount, greaterThanOrEqualTo(1));
      expect(api.uploadChunkCount, greaterThanOrEqualTo(1));
      expect(api.completeCallCount, greaterThanOrEqualTo(1));
      expect(notifier.lastAutoUploadError, isNull);
      expect(rawInput.pendingPollCount, greaterThanOrEqualTo(1));

      api.throwOnCreate = true;
      final successfulCreateCalls = api.createCallCount;
      await _insertClosedActivityRecord(db, DateTime(2026, 6, 11, 13));
      String? uploadError;
      await _waitFor(() {
        uploadError = notifier.lastAutoUploadError;
        return uploadError != null;
      });
      final lastSampleAt =
          container.read(trackerServiceNotifierProvider).lastSampleAt;
      notifier.stop();
      await _waitFor(() => !notifier.isAutoUploading);
      expect(api.createCallCount, greaterThan(successfulCreateCalls));
      expect(uploadError, contains('upload refused'));
      expect(notifier.isAutoUploading, isFalse);
      expect(lastSampleAt, isNotNull);
    } finally {
      notifier.stop();
      await _waitFor(
        () => !container.read(trackerServiceNotifierProvider).isRunning,
      );
      container.dispose();
      await db.close();
    }
  });
}

ProviderContainer _container(
  AppDatabase db, {
  List<Override> overrides = const <Override>[],
}) {
  return ProviderContainer(
    overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      sequenceRecordingProvider.overrideWith((ref) => false),
      ...overrides,
    ],
  );
}

WindowSnapshot _snapshot({
  required String processName,
  required String className,
  required String windowTitle,
  required DateTime timestamp,
}) {
  return WindowSnapshot(
    processName: processName,
    className: className,
    windowTitle: windowTitle,
    isFullscreen: false,
    timestamp: timestamp,
  );
}

InputTelemetry _telemetry({
  required DateTime at,
  int keys = 0,
  MouseClicks clicks = const MouseClicks(),
  int movePx = 0,
  List<RawInputEvent> events = const <RawInputEvent>[],
}) {
  return InputTelemetry(
    keyCount: keys,
    keyDistribution: keys == 0 ? const <int, int>{} : const <int, int>{65: 1},
    keySequence: keys == 0 ? null : 'A',
    clicks: clicks,
    scrollPx: 0,
    mouseMovePx: movePx,
    timestamp: at,
    inputEvents: events,
  );
}

RawInputEvent _rawEvent(int sequenceId, DateTime at, {int keyCode = 65}) {
  return RawInputEvent(
    sequenceId: sequenceId,
    timestampMicros: at.microsecondsSinceEpoch,
    kind: RawInputEventKind.keyDown,
    keyCode: keyCode,
  );
}

Future<Map<String, Object?>?> _recordById(AppDatabase db, int id) async {
  final row = await db.customSelect(
    'SELECT * FROM activity_records WHERE id = ?',
    variables: [drift.Variable<int>(id)],
  ).getSingleOrNull();
  return row?.data;
}

Future<void> _insertClosedActivityRecord(AppDatabase db, DateTime start) async {
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
      'gap6',
    ],
  );
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(const Duration(milliseconds: 1));
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

class _FakeRawInputService extends RawInputService {
  _FakeRawInputService() : super(isWindows: () => true);

  final List<Future<InputTelemetry?>> statsQueue = <Future<InputTelemetry?>>[];
  final List<Future<List<RawInputEvent>>> pendingEventsQueue =
      <Future<List<RawInputEvent>>>[];
  var statsCount = 0;
  var pendingPollCount = 0;
  var stopCount = 0;
  var _running = false;

  @override
  bool get isRunning => _running;

  @override
  String? get lastError => null;

  @override
  Future<void> start() async {
    _running = true;
  }

  @override
  Future<void> stop() async {
    stopCount += 1;
    _running = false;
  }

  @override
  Future<InputTelemetry?> getStats() {
    statsCount += 1;
    if (statsQueue.isEmpty) {
      return Future<InputTelemetry?>.value(InputTelemetry.empty());
    }
    return statsQueue.removeAt(0);
  }

  @override
  Future<List<RawInputEvent>> getPendingInputEvents({
    int maxEvents = 1000,
  }) {
    pendingPollCount += 1;
    if (pendingEventsQueue.isEmpty) {
      return Future<List<RawInputEvent>>.value(const <RawInputEvent>[]);
    }
    return pendingEventsQueue.removeAt(0);
  }

  @override
  Future<void> ackInputEvents(int throughSequenceId) async {}
}

class _FakeTrackingIngestApi implements TrackingIngestApi {
  var createCallCount = 0;
  var uploadChunkCount = 0;
  var completeCallCount = 0;
  var throwOnCreate = false;
  final successfulDataKinds = <String>[];

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
    if (throwOnCreate) {
      throw StateError('upload refused');
    }
    successfulDataKinds.add(dataKind);
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
    uploadChunkCount += 1;
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> completeBatch({
    required String batchId,
    List<Map<String, dynamic>> records = const [],
  }) async {
    completeCallCount += 1;
    return <String, dynamic>{'ok': true, 'accepted': 1, 'rejected': 0};
  }

  @override
  Future<Map<String, dynamic>> summary({DateTime? start, DateTime? end}) async {
    return <String, dynamic>{};
  }
}
