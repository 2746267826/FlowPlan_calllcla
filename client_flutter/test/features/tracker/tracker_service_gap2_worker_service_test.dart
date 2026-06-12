import 'dart:async';
import 'dart:typed_data';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/server_api/tracking_ingest_api.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/tracker/models/tracked_input_event.dart';
import 'package:flowplanv2/features/tracker/services/raw_input_service.dart';
import 'package:flowplanv2/features/tracker/services/tracker_platform_source.dart';
import 'package:flowplanv2/features/tracker/services/tracker_service.dart';
import 'package:flowplanv2/features/tracker/services/tracking_upload_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flowplanv2/shared/providers/settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/temp_app_storage.dart';
import '../../test_support/test_database.dart';

final _sequenceRecordingToggleProvider = StateProvider<bool>((ref) => false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    debugTrackerPlatformOverride =
        const TrackerPlatformSource.windowsForTesting();
  });

  tearDown(() {
    debugRawInputServiceOverride = null;
    debugTrackerPlatformOverride = null;
  });

  test('start is idempotent and stop clears state and cancels poll timers',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final rawInput = _FakeRawInputService();
    debugRawInputServiceOverride = rawInput;
    final container = _container(db);
    addTearDown(container.dispose);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    try {
      notifier.start();
      notifier.start();
      await _waitFor(() => rawInput.startCount == 1);
      await _waitFor(() => rawInput.pendingPollCount == 1);

      expect(container.read(trackerServiceNotifierProvider).isRunning, isTrue);
      expect(rawInput.stopCount, 0);

      notifier.stop();
      notifier.stop();
      await _waitFor(
        () => !container.read(trackerServiceNotifierProvider).isRunning,
      );
      final pollsAtStop = rawInput.pendingPollCount;
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      final state = container.read(trackerServiceNotifierProvider);
      expect(state.currentTelemetry?.keyCount, 0);
      expect(state.isRunning, isFalse);
      expect(rawInput.startCount, 1);
      expect(rawInput.stopCount, 1);
      expect(rawInput.pendingPollCount, pollsAtStop);
    } finally {
      notifier.stop();
      await _flushAsync();
    }
  });

  test('input poll errors set lastError and later polls persist and ack events',
      () async {
    await setUpTempAppStorage(prefix: 'tracker-service-gap2-');
    final db = createTestDatabase();
    addTearDown(db.close);
    final rawInput = _FakeRawInputService()..throwOnNextPendingPoll = true;
    debugRawInputServiceOverride = rawInput;
    final container = _container(db);
    addTearDown(container.dispose);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);
    final initialTick = container.read(activityLogRefreshTickProvider);
    final eventAt = DateTime(2026, 6, 10, 14, 15);

    try {
      notifier.start();
      await _waitFor(
        () => container.read(trackerServiceNotifierProvider).lastError != null,
      );
      expect(
        container.read(trackerServiceNotifierProvider).lastError,
        contains('pending bridge failed'),
      );

      rawInput.pendingEvents = <RawInputEvent>[
        RawInputEvent(
          sequenceId: 21,
          timestampMicros: eventAt.microsecondsSinceEpoch,
          kind: RawInputEventKind.keyDown,
          keyCode: 65,
          processName: 'Code.exe',
          className: 'EditorWindow',
          windowTitle: 'main.dart',
          tokenText: 'A',
        ),
        RawInputEvent(
          sequenceId: 22,
          timestampMicros: eventAt
              .add(const Duration(milliseconds: 20))
              .microsecondsSinceEpoch,
          kind: RawInputEventKind.mouseButtonDown,
          eventCount: 2,
          processName: 'Code.exe',
          className: 'EditorWindow',
          windowTitle: 'main.dart',
          mouseButton: 'left',
        ),
      ];

      await _waitFor(() => rawInput.ackedSequenceIds.contains(22));
      final events = await container
          .read(inputActivityEventServiceProvider)
          .listEvents(includeIgnored: true);

      expect(events.map((event) => event.sequenceId), <int>[21, 22]);
      expect(events.first.processName, 'Code.exe');
      expect(events.first.className, 'EditorWindow');
      expect(events.first.windowTitle, 'main.dart');
      expect(events.first.kind, TrackedInputEventKind.keyDown);
      expect(events.first.keyLabel, 'A');
      expect(events.first.tokenText, 'A');
      expect(events.last.kind, TrackedInputEventKind.mouseButtonDown);
      expect(events.last.eventCount, 2);
      expect(events.last.mouseButton, 'left');
      expect(rawInput.pendingPollCount, greaterThanOrEqualTo(2));
      expect(
        container.read(activityLogRefreshTickProvider),
        greaterThan(initialTick),
      );
    } finally {
      notifier.stop();
      await _waitFor(
        () => !container.read(trackerServiceNotifierProvider).isRunning,
      );
    }
  });

  test('upload service path leaves tracker upload getters settled on errors',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await _insertClosedActivityRecord(db, DateTime(2026, 6, 10, 9));
    final rawInput = _FakeRawInputService();
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
    addTearDown(container.dispose);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    await uploadService.uploadPending();
    expect(api.createCallCount, 1);
    expect(notifier.lastAutoUploadAt, isNull);
    expect(notifier.lastAutoUploadError, isNull);
    expect(notifier.isAutoUploading, isFalse);

    api.throwOnCreate = true;
    await _insertClosedActivityRecord(db, DateTime(2026, 6, 10, 10));
    await uploadService.uploadPending().catchError(
          (_) => const TrackingUploadResult(
            uploadedBatches: 0,
            uploadedRecords: 0,
            details: <Map<String, Object?>>[],
          ),
        );
    expect(api.createCallCount, 2);
    expect(notifier.lastAutoUploadError, isNull);
    expect(notifier.isAutoUploading, isFalse);

    try {
      notifier.start();
      await _waitFor(() => rawInput.startCount == 1);
    } finally {
      notifier.stop();
      await _waitFor(
        () => !container.read(trackerServiceNotifierProvider).isRunning,
      );
    }
  });

  test('sequence recording changes are forwarded while stopped and running',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final rawInput = _FakeRawInputService();
    debugRawInputServiceOverride = rawInput;
    final container = ProviderContainer(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        sequenceRecordingProvider.overrideWith(
          (ref) => ref.watch(_sequenceRecordingToggleProvider),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(trackerServiceNotifierProvider.notifier);

    try {
      await _waitFor(() => rawInput.sequenceRecordingValues.length == 1);
      container.read(_sequenceRecordingToggleProvider.notifier).state = true;
      await _waitFor(() => rawInput.sequenceRecordingValues.length == 2);
      notifier.start();
      await _waitFor(() => rawInput.startCount == 1);
      container.read(_sequenceRecordingToggleProvider.notifier).state = false;
      await _waitFor(() => rawInput.sequenceRecordingValues.length == 3);

      expect(rawInput.sequenceRecordingValues, <bool>[false, true, false]);
      expect(container.read(trackerServiceNotifierProvider).isRunning, isTrue);
    } finally {
      notifier.stop();
      await _waitFor(
        () => !container.read(trackerServiceNotifierProvider).isRunning,
      );
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
      'test',
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

  final List<bool> sequenceRecordingValues = <bool>[];
  final List<int> ackedSequenceIds = <int>[];
  List<RawInputEvent> pendingEvents = const <RawInputEvent>[];
  bool throwOnNextPendingPoll = false;
  int startCount = 0;
  int stopCount = 0;
  int pendingPollCount = 0;
  int statsCount = 0;
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  String? get lastError => null;

  @override
  Future<void> start() async {
    if (_running) return;
    startCount += 1;
    _running = true;
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
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
    return InputTelemetry.empty(DateTime.now());
  }

  @override
  Future<List<RawInputEvent>> getPendingInputEvents({
    int maxEvents = 1000,
  }) async {
    pendingPollCount += 1;
    if (throwOnNextPendingPoll) {
      throwOnNextPendingPoll = false;
      throw StateError('pending bridge failed');
    }
    final events = pendingEvents.take(maxEvents).toList(growable: false);
    pendingEvents = const <RawInputEvent>[];
    return events;
  }

  @override
  Future<void> ackInputEvents(int throughSequenceId) async {
    ackedSequenceIds.add(throughSequenceId);
  }
}

class _FakeTrackingIngestApi implements TrackingIngestApi {
  bool throwOnCreate = false;
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
    if (throwOnCreate) {
      throw StateError('upload offline');
    }
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
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> summary({DateTime? start, DateTime? end}) async {
    return <String, dynamic>{};
  }
}
