import 'dart:async';

import 'package:flowplanv2/core/bootstrap/client_bootstrap_service.dart';
import 'package:flowplanv2/core/connection/server_connection_service.dart';
import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/client_api.dart';
import 'package:flowplanv2/core/server_api/remote_settings_repository.dart';
import 'package:flowplanv2/core/server_api/server_config_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:drift/drift.dart'
    show QueryRow, ResultSetImplementation, Selectable, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/test_database.dart';

void main() {
  setUp(() {
    SyncWriteRecorder.onMutationRecorded = null;
  });

  tearDown(() {
    SyncWriteRecorder.onMutationRecorded = null;
  });

  test(
      'start initializes once and dispose leaves external mutation hook intact',
      () async {
    final harness = await _createHarness();
    Future<void> externalHook() async {}

    SyncWriteRecorder.onMutationRecorded = externalHook;
    final timers = await _recordTimers((timers) async {
      harness.service.start();
      harness.service.start();

      await _pumpUntil(
        () =>
            harness.bootstrap.bootstrapSources.length == 1 &&
            harness.api.heartbeatCalls.length == 1 &&
            timers.periodicDelays.contains(const Duration(minutes: 5)) &&
            timers.nonZeroSingleDelays.contains(const Duration(seconds: 30)),
      );
    });

    expect(harness.bootstrap.bootstrapSources, <String>['startup']);
    expect(harness.bootstrap.syncSources, isEmpty);
    expect(harness.service.state.level, ServerConnectionLevel.online);
    expect(harness.service.state.serverUrl, 'http://localhost:3202/api');
    expect(harness.service.state.deviceId, 'test-device');
    expect(harness.service.state.platform, 'test-platform');
    expect(SyncWriteRecorder.onMutationRecorded, same(externalHook));
    expect(harness.bootstrap.onProgress, isNotNull);
    expect(timers.periodicDelays, contains(const Duration(minutes: 5)));
    expect(timers.timers, everyElement(isA<_RecordedTimer>()));

    await harness.dispose();

    expect(SyncWriteRecorder.onMutationRecorded, same(externalHook));
    expect(harness.bootstrap.onProgress, isNull);
    expect(timers.timers, everyElement(predicate<Timer>((timer) {
      return !timer.isActive;
    })));
    SyncWriteRecorder.onMutationRecorded = null;
  });

  test('start does not install an automatic mutation push hook', () async {
    final harness = await _createHarness();

    await _recordTimers((timers) async {
      harness.service.start();

      await _pumpUntil(
        () =>
            harness.bootstrap.bootstrapSources.length == 1 &&
            timers.periodicDelays.contains(const Duration(minutes: 5)),
      );
    });

    expect(SyncWriteRecorder.onMutationRecorded, isNull);
  });

  test('requestSync queues a second sync while the service is busy', () async {
    final harness = await _createHarness();
    final firstStarted = Completer<void>();
    final firstRelease = Completer<ClientRuntimeState>();
    final firstSyncedAt = DateTime.utc(2026, 6, 10, 1);
    final secondSyncedAt = DateTime.utc(2026, 6, 10, 2);

    harness.bootstrap.syncNowHandlers.add((source) {
      firstStarted.complete();
      return firstRelease.future;
    });
    harness.bootstrap.syncNowHandlers.add((source) async {
      return _runtime(lastSyncAt: secondSyncedAt);
    });

    final inFlight = harness.service.syncNow(
      source: 'manual',
      reason: 'first_refresh',
    );
    await firstStarted.future;

    harness.service.requestSync(
      source: 'write',
      reason: 'local_write',
      immediate: true,
    );

    expect(harness.service.state.syncPhase, 'queued');
    expect(harness.service.state.syncReason, 'local_write');

    firstRelease.complete(_runtime(lastSyncAt: firstSyncedAt));
    await inFlight;

    expect(harness.bootstrap.syncSources, <String>['manual', 'write']);
    expect(harness.service.state.level, ServerConnectionLevel.online);
    expect(harness.service.state.syncing, isFalse);
    expect(harness.service.state.syncPhase, 'completed');
    expect(harness.service.state.syncReason, 'local_write');
    expect(harness.service.state.lastSyncAt, secondSyncedAt);
    expect(harness.api.heartbeatEventSources, <String>[
      'sync_success',
      'sync_success',
    ]);
  });

  test('sync success refreshes local summary and heartbeats', () async {
    final harness = await _createHarness();
    final syncedAt = DateTime.utc(2026, 6, 10, 3);
    await _insertOfflineMutation(harness.db, uid: 'pending-1');
    await _insertOfflineMutation(
      harness.db,
      uid: 'failed-1',
      status: 'failed',
    );
    harness.bootstrap.syncNowHandlers.add((source) async {
      return _runtime(lastSyncAt: syncedAt);
    });
    harness.api.heartbeatResponses.add(<String, dynamic>{
      'ok': true,
      'nextHeartbeatSeconds': 45,
    });

    final timers = await _recordTimers((_) {
      return harness.service.syncNow(
        source: 'manual',
        reason: 'button_press',
      );
    });

    final heartbeatBody =
        harness.api.heartbeatCalls.single['body']! as Map<String, Object?>;
    final summary = heartbeatBody['syncSummary']! as Map<String, Object?>;
    expect(harness.service.state.level, ServerConnectionLevel.online);
    expect(harness.service.state.syncing, isFalse);
    expect(harness.service.state.syncPhase, 'completed');
    expect(harness.service.state.syncReason, 'button_press');
    expect(harness.service.state.lastSyncAt, syncedAt);
    expect(harness.service.state.lastError, isNull);
    expect(harness.service.state.pendingCount, 1);
    expect(harness.service.state.failedCount, 1);
    expect(summary, containsPair('pendingCount', 1));
    expect(summary, containsPair('failedCount', 1));
    expect(harness.api.heartbeatEventSources, <String>['sync_success']);
    expect(timers.nonZeroSingleDelays, <Duration>[
      const Duration(seconds: 45),
    ]);
  });

  test('sync runtime error leaves the connection degraded', () async {
    final harness = await _createHarness();
    final failedAt = DateTime.utc(2026, 6, 10, 4);
    harness.bootstrap.syncNowHandlers.add((source) async {
      return _runtime(lastSyncAt: failedAt, lastError: 'pull failed');
    });

    final timers = await _recordTimers((_) {
      return harness.service.syncNow(
        source: 'manual',
        reason: 'button_press',
      );
    });

    expect(harness.service.state.level, ServerConnectionLevel.degraded);
    expect(harness.service.state.syncing, isFalse);
    expect(harness.service.state.syncPhase, 'failed');
    expect(harness.service.state.syncReason, 'button_press');
    expect(harness.service.state.lastSyncAt, failedAt);
    expect(harness.service.state.lastError, 'pull failed');
    expect(harness.api.heartbeatCalls, isEmpty);
    expect(timers.nonZeroSingleDelays, <Duration>[
      const Duration(seconds: 30),
    ]);
  });

  test('sync tolerates locked local summary queries', () async {
    final db = _LockedSummaryDatabase();
    final harness = await _createHarness(db: db);
    final syncedAt = DateTime.utc(2026, 6, 10, 4, 30);
    harness.bootstrap.syncNowHandlers.add((source) async {
      return _runtime(lastSyncAt: syncedAt);
    });

    final timers = await _recordTimers((_) {
      return harness.service.syncNow(
        source: 'manual',
        reason: 'button_press',
      );
    });

    expect(harness.bootstrap.syncSources, <String>['manual']);
    expect(harness.api.heartbeatEventSources, <String>['sync_success']);
    expect(harness.service.state.level, ServerConnectionLevel.online);
    expect(harness.service.state.syncing, isFalse);
    expect(harness.service.state.syncPhase, 'completed');
    expect(harness.service.state.lastSyncAt, syncedAt);
    expect(harness.service.state.lastError, isNull);
    expect(harness.service.state.pendingCount, 0);
    expect(harness.service.state.failedCount, 0);
    expect(harness.service.state.conflictCount, 0);
    expect(timers.nonZeroSingleDelays, <Duration>[
      const Duration(seconds: 30),
    ]);
  });

  for (final testCase in <_HeartbeatAuthCase>[
    _HeartbeatAuthCase(
      name: 'authRequired',
      response: <String, dynamic>{
        'authRequired': true,
        'reason': 'login required',
      },
      expectedError: 'login required',
    ),
    _HeartbeatAuthCase(
      name: 'revoked',
      response: <String, dynamic>{
        'connectionStatus': 'revoked',
        'message': 'device revoked',
      },
      expectedError: 'device revoked',
    ),
  ]) {
    test('heartbeat marks authRequired when ${testCase.name}', () async {
      final harness = await _createHarness();
      harness.api.heartbeatResponses.add(testCase.response);

      final timers = await _recordTimers((_) {
        return harness.service.heartbeat(eventSource: 'timer');
      });

      expect(harness.service.state.level, ServerConnectionLevel.authRequired);
      expect(harness.service.state.serverUrl, 'http://localhost:3202/api');
      expect(harness.service.state.deviceId, 'test-device');
      expect(harness.service.state.platform, 'test-platform');
      expect(harness.service.state.syncing, isFalse);
      expect(harness.service.state.lastError, testCase.expectedError);
      expect(timers.nonZeroSingleDelays, <Duration>[
        const Duration(minutes: 5),
      ]);
    });
  }

  test('heartbeat ok false records failure and backs off', () async {
    final harness = await _createHarness();
    harness.api.heartbeatResponses.addAll(<Map<String, dynamic>>[
      <String, dynamic>{'ok': false, 'message': 'still down 1'},
      <String, dynamic>{'ok': false, 'message': 'still down 2'},
      <String, dynamic>{'ok': false, 'message': 'still down 3'},
      <String, dynamic>{'ok': false, 'message': 'still down 4'},
    ]);

    final delays = <Duration>[];
    delays.addAll((await _recordTimers((_) {
      return harness.service.heartbeat(eventSource: 'timer');
    }))
        .nonZeroSingleDelays);
    expect(harness.service.state.level, ServerConnectionLevel.degraded);

    delays.addAll((await _recordTimers((_) {
      return harness.service.heartbeat(eventSource: 'timer');
    }))
        .nonZeroSingleDelays);
    expect(harness.service.state.level, ServerConnectionLevel.offline);

    delays.addAll((await _recordTimers((_) {
      return harness.service.heartbeat(eventSource: 'timer');
    }))
        .nonZeroSingleDelays);
    delays.addAll((await _recordTimers((_) {
      return harness.service.heartbeat(eventSource: 'timer');
    }))
        .nonZeroSingleDelays);

    expect(delays, <Duration>[
      const Duration(seconds: 30),
      const Duration(seconds: 60),
      const Duration(seconds: 120),
      const Duration(seconds: 300),
    ]);
    expect(harness.service.state.lastError, 'still down 4');
    expect(
      await harness.db.getSetting(ClientBootstrapService.lastErrorKey),
      'still down 4',
    );
    final logs = await DataOperationLogRepository(harness.db).listRecent();
    expect(logs.first.action, 'server_connection_failed');
    expect(logs.first.metadataJson, contains('"failureCount":4'));
  });

  test('heartbeat with server changes requests immediate sync', () async {
    final harness = await _createHarness();
    final syncedAt = DateTime.utc(2026, 6, 10, 5);
    harness.api.heartbeatResponses.addAll(<Map<String, dynamic>>[
      <String, dynamic>{
        'ok': true,
        'hasServerChanges': true,
        'nextHeartbeatSeconds': 75,
      },
      <String, dynamic>{
        'ok': true,
        'nextHeartbeatSeconds': 30,
      },
    ]);
    harness.bootstrap.syncNowHandlers.add((source) async {
      return _runtime(lastSyncAt: syncedAt);
    });

    final timers = await _recordTimers((_) async {
      await harness.service.heartbeat(eventSource: 'timer');
      expect(harness.service.state.level, ServerConnectionLevel.online);
      expect(harness.service.state.nextHeartbeatSeconds, 75);
      await _pumpUntil(() => harness.bootstrap.syncSources.isNotEmpty);
    });

    expect(harness.bootstrap.syncSources, <String>[
      'heartbeat_remote_change',
    ]);
    expect(harness.service.state.syncPhase, 'completed');
    expect(harness.service.state.syncReason, 'server_changes_available');
    expect(harness.service.state.lastSyncAt, syncedAt);
    expect(harness.api.heartbeatEventSources, <String>[
      'timer',
      'sync_success',
    ]);
    expect(timers.nonZeroSingleDelays, <Duration>[
      const Duration(seconds: 75),
      const Duration(seconds: 30),
    ]);
  });

  test('bootstrap progress callback updates connection progress state',
      () async {
    final harness = await _createHarness();

    harness.bootstrap.emitProgress(
      const ClientSyncProgress(
        phase: 'applying',
        source: 'manual',
        current: 7,
        total: 9,
        summary: <String, Object?>{
          'appliedChanges': 7,
          'failedChanges': 0,
        },
      ),
    );

    expect(harness.service.state.syncPhase, 'applying');
    expect(harness.service.state.syncReason, 'manual');
    expect(harness.service.state.progressCurrent, 7);
    expect(harness.service.state.progressTotal, 9);
    expect(harness.service.state.lastSyncSummary, <String, Object?>{
      'appliedChanges': 7,
      'failedChanges': 0,
    });
  });
}

Future<_ConnectionHarness> _createHarness({AppDatabase? db}) async {
  db ??= createTestDatabase();
  final api = _FakeClientApi(db);
  final bootstrap = _FakeBootstrapService(db, api);
  final service = ServerConnectionService(
    database: db,
    clientApi: api,
    bootstrapService: bootstrap,
    serverConfigStore: ServerConfigStore(db),
    operationLogs: DataOperationLogRepository(db),
    deviceId: 'test-device',
    platform: 'test-platform',
  );
  final harness = _ConnectionHarness(
    db: db,
    api: api,
    bootstrap: bootstrap,
    service: service,
  );
  addTearDown(harness.dispose);
  return harness;
}

ClientRuntimeState _runtime({
  DateTime? lastSyncAt,
  String? lastError,
  bool serverReachable = true,
}) {
  return ClientRuntimeState(
    mode: 'server_first',
    syncing: false,
    serverReachable: serverReachable,
    lastSyncAt: lastSyncAt ?? DateTime.utc(2026, 6, 10),
    lastError: lastError,
  );
}

Future<void> _insertOfflineMutation(
  AppDatabase db, {
  required String uid,
  String status = 'pending',
}) {
  return db.customStatement(
    '''
    INSERT INTO offline_mutations (
      mutation_uid,
      object_type,
      local_id,
      action,
      payload_json,
      created_at,
      status
    ) VALUES (?, ?, ?, ?, ?, ?, ?)
    ''',
    <Object?>[
      uid,
      'task',
      uid,
      'create',
      '{}',
      DateTime.utc(2026, 6, 10).toIso8601String(),
      status,
    ],
  );
}

Future<void> _pumpUntil(
  bool Function() condition, {
  int maxPumps = 30,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (condition()) {
      return;
    }
    await pumpEventQueue();
  }
  fail('Condition was not met after $maxPumps event queue pumps.');
}

Future<_RecordedTimers> _recordTimers(
  Future<void> Function(_RecordedTimers timers) body,
) async {
  final timers = _RecordedTimers();
  await runZoned<Future<void>>(
    () => body(timers),
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        timers.singleDelays.add(duration);
        if (duration == Duration.zero) {
          return parent.createTimer(zone, duration, callback);
        }
        final timer = _RecordedTimer();
        timers.timers.add(timer);
        return timer;
      },
      createPeriodicTimer: (self, parent, zone, period, callback) {
        timers.periodicDelays.add(period);
        final timer = _RecordedTimer();
        timers.timers.add(timer);
        return timer;
      },
    ),
  );
  return timers;
}

class _ConnectionHarness {
  _ConnectionHarness({
    required this.db,
    required this.api,
    required this.bootstrap,
    required this.service,
  });

  final AppDatabase db;
  final _FakeClientApi api;
  final _FakeBootstrapService bootstrap;
  final ServerConnectionService service;

  var _disposed = false;
  var _dbClosed = false;

  Future<void> dispose() async {
    if (!_disposed) {
      service.dispose();
      _disposed = true;
    }
    if (!_dbClosed) {
      await db.close();
      _dbClosed = true;
    }
  }
}

class _FakeClientApi extends ClientApi {
  _FakeClientApi(AppDatabase db) : super(_unusedApiClient(db));

  final heartbeatResponses = <Map<String, dynamic>>[];
  final heartbeatCalls = <Map<String, Object?>>[];

  List<String> get heartbeatEventSources {
    return heartbeatCalls.map((call) {
      final body = call['body']! as Map<String, Object?>;
      final networkSummary = body['networkSummary']! as Map<String, Object?>;
      return networkSummary['source']! as String;
    }).toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> heartbeat({
    required String deviceId,
    required Map<String, Object?> body,
  }) async {
    heartbeatCalls.add(<String, Object?>{
      'deviceId': deviceId,
      'body': body,
    });
    if (heartbeatResponses.isNotEmpty) {
      return heartbeatResponses.removeAt(0);
    }
    return <String, dynamic>{
      'ok': true,
      'nextHeartbeatSeconds': 30,
    };
  }
}

class _FakeBootstrapService extends ClientBootstrapService {
  _FakeBootstrapService(AppDatabase db, ClientApi clientApi)
      : super(
          database: db,
          clientApi: clientApi,
          remoteSettingsRepository: RemoteSettingsRepository(
            database: db,
            clientApi: clientApi,
          ),
          syncEngineLoader: () {
            throw UnsupportedError('sync engine is not used by this fake');
          },
          operationLogs: DataOperationLogRepository(db),
        );

  final bootstrapSources = <String>[];
  final syncSources = <String>[];
  final bootstrapHandlers = <Future<ClientRuntimeState> Function(String)>[];
  final syncNowHandlers = <Future<ClientRuntimeState> Function(String)>[];

  @override
  Future<ClientRuntimeState> bootstrapAndSync({String source = 'manual'}) {
    bootstrapSources.add(source);
    if (bootstrapHandlers.isNotEmpty) {
      return bootstrapHandlers.removeAt(0)(source);
    }
    return Future<ClientRuntimeState>.value(_runtime());
  }

  @override
  Future<ClientRuntimeState> syncNow({String source = 'manual'}) {
    syncSources.add(source);
    if (syncNowHandlers.isNotEmpty) {
      return syncNowHandlers.removeAt(0)(source);
    }
    return Future<ClientRuntimeState>.value(_runtime());
  }

  void emitProgress(ClientSyncProgress progress) {
    onProgress?.call(progress);
  }
}

class _HeartbeatAuthCase {
  const _HeartbeatAuthCase({
    required this.name,
    required this.response,
    required this.expectedError,
  });

  final String name;
  final Map<String, dynamic> response;
  final String expectedError;
}

class _RecordedTimers {
  final singleDelays = <Duration>[];
  final periodicDelays = <Duration>[];
  final timers = <_RecordedTimer>[];

  List<Duration> get nonZeroSingleDelays {
    return singleDelays
        .where((duration) => duration != Duration.zero)
        .toList(growable: false);
  }
}

class _RecordedTimer implements Timer {
  var _active = true;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() {
    _active = false;
  }
}

class _LockedSummaryDatabase extends AppDatabase {
  _LockedSummaryDatabase() : super(NativeDatabase.memory());

  @override
  Selectable<QueryRow> customSelect(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation> readsFrom = const {},
  }) {
    if (query.contains('FROM offline_mutations') ||
        query.contains('FROM sync_conflicts')) {
      return _ThrowingRows(StateError('database is locked'));
    }
    return super.customSelect(
      query,
      variables: variables,
      readsFrom: readsFrom,
    );
  }
}

class _ThrowingRows with Selectable<QueryRow> {
  const _ThrowingRows(this.error);

  final Object error;

  @override
  Future<List<QueryRow>> get() async {
    throw error;
  }

  @override
  Stream<List<QueryRow>> watch() => Stream<List<QueryRow>>.error(error);
}

ApiClient _unusedApiClient(AppDatabase db) {
  return ApiClient(
    baseUri: Uri.parse('http://localhost:3202/api'),
    tokenStore: AuthTokenStore(db),
    httpClient: MockClient((request) async {
      return http.Response('{}', 500);
    }),
  );
}
