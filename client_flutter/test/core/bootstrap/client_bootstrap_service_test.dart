import 'dart:convert';

import 'package:flowplanv2/core/bootstrap/client_bootstrap_service.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_runner.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/client_api.dart';
import 'package:flowplanv2/core/server_api/remote_settings_repository.dart';
import 'package:flowplanv2/core/sync/sync_cursor_store.dart';
import 'package:flowplanv2/core/sync/sync_engine.dart';
import 'package:flowplanv2/core/sync/sync_result.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  test(
      'bootstrapAndSync reports progress, persists bootstrap mode, and logs summary',
      () async {
    final harness = _BootstrapHarness();
    addTearDown(harness.dispose);
    harness.api.bootstrapResponse = <String, dynamic>{
      'settingsVersion': 41,
      'syncCursor': 'cursor-bootstrap',
      'pendingActions': <String, Object?>{'importRequired': false},
    };
    harness.api.settingsResponse = <String, dynamic>{
      'version': 42,
      'updatedAt': '2026-06-10T09:00:00Z',
      'settings': <Object?>[
        <String, Object?>{'key': 'theme', 'value': 'dark'},
      ],
      'policy': <String, Object?>{'allowClientOverrides': true},
    };
    harness.engine.pullResult = <String, dynamic>{
      'changes': <Object?>[
        <String, Object?>{'changeId': 'change-1'},
        <String, Object?>{'changeId': 'change-2'},
      ],
      'pulledChanges': 6,
      'appliedChanges': 4,
      'skippedChanges': 1,
      'failedChanges': 0,
      'perType': <String, int>{'task_item': 4},
      'orphanCalendarEvents': 1,
    };
    harness.trackingUploadResult = <String, Object?>{
      'uploaded': 3,
      'buffered': 0,
    };
    final progress = <ClientSyncProgress>[];
    harness.service.onProgress = progress.add;

    final state = await harness.service.bootstrapAndSync(source: 'startup');

    expect(state.mode, 'server_first');
    expect(state.syncing, isFalse);
    expect(state.serverReachable, isTrue);
    expect(state.settingsVersion, 42);
    expect(state.syncCursor, 'cursor-bootstrap');
    expect(state.lastSyncAt, isNotNull);
    expect(await harness.db.getSetting(ClientBootstrapService.modeKey),
        'server_first');
    expect(
      jsonDecode(
        (await harness.db.getSetting(ClientBootstrapService.stateKey))!,
      ),
      containsPair('syncCursor', 'cursor-bootstrap'),
    );
    expect(harness.engine.pushSources, isEmpty);
    expect(harness.engine.refreshSources, <String>['refresh']);
    expect(
      progress.map((item) => item.phase),
      <String>[
        'preparing',
        'pulling',
        'applying',
        'tracking_upload',
        'completed',
      ],
    );
    expect(progress[2].current, 6);
    expect(progress.last.current, 6);
    _expectNoLegacyPushSummary(progress.last.summary);
    expect(progress.last.summary['pulledChanges'], 6);
    expect(progress.last.summary['appliedChanges'], 4);
    expect(progress.last.summary['skippedChanges'], 1);
    expect(progress.last.summary['failedChanges'], 0);
    expect(progress.last.summary['legacyQueue'], <String, Object?>{
      'pendingCount': 0,
      'failedCount': 0,
      'conflictCount': 0,
    });
    expect(progress.last.summary['trackingUpload'], <String, Object?>{
      'enabled': true,
      'ok': true,
      'uploaded': 3,
      'buffered': 0,
    });

    final logs = await DataOperationLogRepository(harness.db).listRecent();
    final syncLog = logs.singleWhere(
      (log) => log.action == 'client_bootstrap_sync',
    );
    final metadata =
        jsonDecode(syncLog.metadataJson ?? '{}') as Map<String, dynamic>;
    expect(syncLog.metadataJson, contains('"settingsVersion":42'));
    _expectNoLegacyPushSummary(metadata);
    expect(syncLog.metadataJson, contains('"pulledChanges":6'));
    expect(syncLog.metadataJson, contains('"legacyQueue"'));
    expect(syncLog.metadataJson, contains('"uploaded":3'));
  });

  test(
      'syncNow keeps sync successful when tracking upload fails and records the upload error',
      () async {
    final harness = _BootstrapHarness();
    addTearDown(harness.dispose);
    harness.engine.pullResult = <String, dynamic>{
      'changes': <Object?>[],
      'pulledChanges': 0,
      'appliedChanges': 0,
      'skippedChanges': 0,
      'failedChanges': 0,
    };
    harness.trackingUploadError = StateError('tracking offline');
    final progress = <ClientSyncProgress>[];
    harness.service.onProgress = progress.add;

    final state = await harness.service.syncNow(source: 'timer');

    expect(state.mode, 'server_first');
    expect(state.syncing, isFalse);
    expect(state.serverReachable, isTrue);
    expect(state.lastError, isNull);
    expect(
      await harness.db.getSetting('tracking.upload.last_error'),
      'Bad state: tracking offline',
    );
    expect(progress.last.phase, 'completed');
    expect(harness.engine.pushSources, isEmpty);
    expect(harness.engine.refreshSources, <String>['refresh']);
    _expectNoLegacyPushSummary(progress.last.summary);
    expect(progress.last.summary['trackingUpload'], <String, Object?>{
      'enabled': true,
      'ok': false,
      'error': 'Bad state: tracking offline',
    });
    final logs = await DataOperationLogRepository(harness.db).listRecent();
    expect(
      logs.map((log) => log.action),
      containsAll(<String>['tracking_upload_failed', 'client_sync_now']),
    );
    final syncLog = logs.singleWhere((log) => log.action == 'client_sync_now');
    final metadata =
        jsonDecode(syncLog.metadataJson ?? '{}') as Map<String, dynamic>;
    expect(syncLog.actor, 'system');
    _expectNoLegacyPushSummary(metadata);
    expect(syncLog.metadataJson, contains('"ok":false'));
  });

  test(
      'syncNow summarizes list-only pulls and preserves server legacy queue values',
      () async {
    final harness = _BootstrapHarness();
    addTearDown(harness.dispose);
    harness.engine.pullResult = <String, dynamic>{
      'changes': <Object?>[
        <String, Object?>{'changeId': 'change-list-1'},
        <String, Object?>{'changeId': 'change-list-2'},
      ],
      'appliedChanges': 2,
      'legacyQueue': <String, Object?>{
        'pendingCount': 3.5,
        'failedCount': '4',
        'conflictCount': 1,
      },
    };
    final progress = <ClientSyncProgress>[];
    harness.service.onProgress = progress.add;

    final state = await harness.service.syncNow(source: 'manual');

    expect(state.mode, 'server_first');
    expect(progress.last.phase, 'completed');
    expect(progress.last.current, 2);
    expect(progress.last.summary['pulledChanges'], 2);
    expect(progress.last.summary['appliedChanges'], 2);
    expect(progress.last.summary['skippedChanges'], 0);
    expect(progress.last.summary['failedChanges'], 0);
    expect(progress.last.summary['legacyQueue'], <String, Object?>{
      'pendingCount': 3.5,
      'failedCount': '4',
      'conflictCount': 1,
    });

    final logs = await DataOperationLogRepository(harness.db).listRecent();
    final syncLog = logs.singleWhere((log) => log.action == 'client_sync_now');
    final metadata =
        jsonDecode(syncLog.metadataJson ?? '{}') as Map<String, dynamic>;
    expect(metadata['pulledChanges'], 2);
    expect(metadata['legacyQueue'], <String, Object?>{
      'pendingCount': 3.5,
      'failedCount': '4',
      'conflictCount': 1,
    });
  });

  test('syncNow summarizes local legacy queue counts when pull omits them',
      () async {
    final harness = _BootstrapHarness();
    addTearDown(harness.dispose);
    await _insertOfflineMutation(harness.db, uid: 'pending-summary');
    await _insertOfflineMutation(
      harness.db,
      uid: 'failed-summary',
      status: 'failed',
    );
    await _insertOfflineMutation(
      harness.db,
      uid: 'conflict-summary',
      status: 'conflict',
    );
    harness.engine.pullResult = const <String, dynamic>{
      'changes': <Object?>[],
    };
    final progress = <ClientSyncProgress>[];
    harness.service.onProgress = progress.add;

    await harness.service.syncNow(source: 'manual');

    expect(progress.last.summary['pulledChanges'], 0);
    expect(progress.last.summary['legacyQueue'], <String, Object?>{
      'pendingCount': 1,
      'failedCount': 1,
      'conflictCount': 1,
    });
  });

  test('readSummaryInt converts numeric and string summary values', () async {
    final harness = _BootstrapHarness();
    addTearDown(harness.dispose);

    expect(harness.service.readSummaryIntForTesting(2.9), 2);
    expect(harness.service.readSummaryIntForTesting('7'), 7);
    expect(harness.service.readSummaryIntForTesting('not-a-count'), isNull);
  });

  test('start triggers periodic timer sync with the timer source', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final api = _FakeClientApi(db);
    final service = _TimerOnlyBootstrapService(db, api);

    fakeAsync((async) {
      try {
        service.start();

        expect(service.bootstrapSources, <String>['startup']);
        expect(service.syncSources, isEmpty);

        async.elapse(const Duration(minutes: 3));

        expect(service.syncSources, <String>['timer']);
      } finally {
        service.dispose();
      }
    });
  });

  test(
      'bootstrapAndSync falls back to local cache when bootstrap is unreachable',
      () async {
    final harness = _BootstrapHarness();
    addTearDown(harness.dispose);
    harness.api.bootstrapError = StateError('server unavailable');
    final progress = <ClientSyncProgress>[];
    harness.service.onProgress = progress.add;

    final state = await harness.service.bootstrapAndSync(source: 'startup');

    expect(state.mode, 'local_cache');
    expect(state.syncing, isFalse);
    expect(state.serverReachable, isFalse);
    expect(state.lastError, 'Bad state: server unavailable');
    expect(await harness.db.getSetting(ClientBootstrapService.modeKey),
        'local_cache');
    expect(
      await harness.db.getSetting(ClientBootstrapService.lastErrorKey),
      'Bad state: server unavailable',
    );
    expect(progress.map((item) => item.phase), <String>['preparing', 'failed']);
    expect(harness.engine.pushSources, isEmpty);
    expect(harness.engine.refreshSources, isEmpty);
    final logs = await DataOperationLogRepository(harness.db).listRecent();
    final failureLog = logs.singleWhere(
      (log) => log.action == 'client_bootstrap_sync_failed',
    );
    expect(failureLog.metadataJson, contains('server unavailable'));
  });

  test(
      'bootstrapAndSync keeps server-first bootstrap state when later sync work fails',
      () async {
    final harness = _BootstrapHarness();
    addTearDown(harness.dispose);
    harness.api.bootstrapResponse = <String, dynamic>{
      'settingsVersion': 7,
      'syncCursor': 'cursor-before-failure',
    };
    harness.api.settingsError = StateError('settings refresh failed');

    final state = await harness.service.bootstrapAndSync(source: 'manual');

    expect(state.mode, 'server_first');
    expect(state.serverReachable, isTrue);
    expect(state.syncCursor, 'cursor-before-failure');
    expect(state.settingsVersion, 7);
    expect(state.lastError, 'Bad state: settings refresh failed');
    expect(await harness.db.getSetting(ClientBootstrapService.modeKey),
        'server_first');
    expect(
      await harness.db.getSetting(ClientBootstrapService.lastErrorKey),
      'Bad state: settings refresh failed',
    );
  });

  test('syncNow falls back to local cache when the server was not reachable',
      () async {
    final harness = _BootstrapHarness();
    addTearDown(harness.dispose);
    harness.engine.pullError = StateError('pull offline');
    final progress = <ClientSyncProgress>[];
    harness.service.onProgress = progress.add;

    final state = await harness.service.syncNow(source: 'manual');

    expect(state.mode, 'local_cache');
    expect(state.syncing, isFalse);
    expect(state.serverReachable, isFalse);
    expect(state.lastError, 'Bad state: pull offline');
    expect(
      await harness.db.getSetting(ClientBootstrapService.lastErrorKey),
      'Bad state: pull offline',
    );
    expect(
      progress.map((item) => item.phase),
      <String>['preparing', 'pulling', 'failed'],
    );
    expect(harness.engine.pushSources, isEmpty);
    expect(harness.engine.refreshSources, <String>['refresh']);
    expect(progress.last.summary, <String, Object?>{
      'source': 'manual',
      'error': 'Bad state: pull offline',
    });
  });

  test(
      'prepareLocalImport uploads a filtered local snapshot and logs the response',
      () async {
    final harness = _BootstrapHarness();
    addTearDown(harness.dispose);
    final listId = await insertFixtureTaskList(harness.db, name: 'Inbox');
    await harness.db.into(harness.db.taskItems).insert(
          fixtureTask(
            uid: 'task-import-1',
            summary: 'Snapshot task',
            taskListId: listId,
          ),
        );
    final calendarId =
        await insertFixtureCalendar(harness.db, name: 'Planning');
    await harness.db.into(harness.db.calendarEvents).insert(
          fixtureEvent(
            uid: 'event-import-1',
            summary: 'Snapshot event',
            calendarId: calendarId,
          ),
        );
    await harness.db.setSetting('theme.mode', 'dark');
    await harness.db.setSetting('server.api.base_url', 'http://private');
    harness.api.snapshotImportResponse = <String, dynamic>{
      'importId': 'import-123',
      'objectCount': 2,
    };

    final response = await harness.service.prepareLocalImport();

    expect(response, containsPair('importId', 'import-123'));
    final snapshot = harness.api.lastSnapshot!;
    expect(snapshot['schemaVersion'], 1);
    expect(snapshot['generatedAt'], isA<String>());
    final objects = snapshot['objects']! as Map<String, Object?>;
    final tasks = objects['task_items']! as List<Map<String, Object?>>;
    final events = objects['calendar_events']! as List<Map<String, Object?>>;
    expect(tasks.single['summary'], 'Snapshot task');
    expect(events.single['summary'], 'Snapshot event');
    final settings = snapshot['settings']! as List<Map<String, Object?>>;
    expect(
      settings.map((row) => row['setting_key']),
      contains('theme.mode'),
    );
    expect(
      settings.map((row) => row['setting_key']),
      isNot(contains('server.api.base_url')),
    );
    final summary = snapshot['localStateSummary']! as Map<String, Object?>;
    expect(summary['tasks'], 1);
    expect(summary['events'], 1);
    expect(summary['conflicts'], 0);

    final logs = await DataOperationLogRepository(harness.db).listRecent();
    final importLog = logs.singleWhere(
      (log) => log.action == 'client_import_prepare',
    );
    expect(importLog.actor, 'user');
    expect(importLog.metadataJson, contains('import-123'));
  });

  test('confirmImport logs the confirmation and runs an import sync', () async {
    final harness = _BootstrapHarness();
    addTearDown(harness.dispose);
    harness.api.confirmImportResponse = <String, dynamic>{
      'importId': 'import-456',
      'status': 'confirmed',
    };
    harness.api.bootstrapResponse = <String, dynamic>{
      'settingsVersion': '12',
      'syncCursor': 99,
      'pendingActions': 'invalid',
    };
    harness.api.settingsResponse = <String, dynamic>{
      'version': 13,
      'settings': <Object?>[],
    };
    harness.engine.pullResult = <String, dynamic>{
      'changes': <Object?>[],
      'pulledChanges': 0,
    };

    final response = await harness.service.confirmImport('import-456');

    expect(response['status'], 'confirmed');
    expect(harness.api.confirmedImportIds, <String>['import-456']);
    expect(harness.service.state.mode, 'server_first');
    expect(harness.service.state.settingsVersion, 13);
    expect(harness.service.state.syncCursor, '99');
    expect(harness.service.state.pendingActions, isEmpty);
    expect(harness.engine.pushSources, isEmpty);
    expect(harness.engine.refreshSources, <String>['refresh']);
    final logs = await DataOperationLogRepository(harness.db).listRecent();
    final confirmLog = logs.singleWhere(
      (log) => log.action == 'client_import_confirm',
    );
    expect(confirmLog.entityId, 'import-456');
    expect(confirmLog.metadataJson, contains('confirmed'));
  });
}

void _expectNoLegacyPushSummary(Map<String, Object?> summary) {
  expect(summary, isNot(containsPair('accepted', anything)));
  expect(summary, isNot(containsPair('conflicts', anything)));
  expect(summary, isNot(containsPair('rejected', anything)));
  expect(summary, isNot(containsPair('pushed', anything)));
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
      'task_item',
      uid,
      'update',
      '{}',
      DateTime.utc(2026, 6, 10).toIso8601String(),
      status,
    ],
  );
}

class _BootstrapHarness {
  _BootstrapHarness() : db = createTestDatabase() {
    api = _FakeClientApi(db);
    engine = _FakeServerSyncEngine(db);
    service = ClientBootstrapService(
      database: db,
      clientApi: api,
      remoteSettingsRepository: RemoteSettingsRepository(
        database: db,
        clientApi: api,
      ),
      syncEngineLoader: () async => engine,
      operationLogs: DataOperationLogRepository(db),
      trackingUploadRunner: () async {
        final error = trackingUploadError;
        if (error != null) {
          throw error;
        }
        return trackingUploadResult;
      },
    );
  }

  final AppDatabase db;
  late _FakeClientApi api;
  late _FakeServerSyncEngine engine;
  late ClientBootstrapService service;
  Map<String, Object?> trackingUploadResult = const <String, Object?>{};
  Object? trackingUploadError;

  Future<void> dispose() async {
    service.dispose();
    await db.close();
  }
}

class _TimerOnlyBootstrapService extends ClientBootstrapService {
  _TimerOnlyBootstrapService(AppDatabase db, ClientApi clientApi)
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

  @override
  Future<ClientRuntimeState> bootstrapAndSync({String source = 'manual'}) {
    bootstrapSources.add(source);
    return Future<ClientRuntimeState>.value(const ClientRuntimeState());
  }

  @override
  Future<ClientRuntimeState> syncNow({String source = 'manual'}) {
    syncSources.add(source);
    return Future<ClientRuntimeState>.value(const ClientRuntimeState());
  }
}

class _FakeClientApi extends ClientApi {
  _FakeClientApi(AppDatabase db) : super(_unusedApiClient(db));

  Map<String, dynamic> bootstrapResponse = const <String, dynamic>{};
  Map<String, dynamic> settingsResponse = const <String, dynamic>{
    'version': 1,
    'settings': <Object?>[],
  };
  Object? bootstrapError;
  Object? settingsError;
  Map<String, dynamic> snapshotImportResponse = const <String, dynamic>{};
  Map<String, Object?>? lastSnapshot;
  Map<String, dynamic> confirmImportResponse = const <String, dynamic>{};
  final confirmedImportIds = <String>[];

  @override
  Future<Map<String, dynamic>> bootstrap() async {
    final error = bootstrapError;
    if (error != null) {
      throw error;
    }
    return bootstrapResponse;
  }

  @override
  Future<Map<String, dynamic>> settings() async {
    final error = settingsError;
    if (error != null) {
      throw error;
    }
    return settingsResponse;
  }

  @override
  Future<Map<String, dynamic>> createLocalSnapshotImport(
    Map<String, Object?> snapshot,
  ) async {
    lastSnapshot = snapshot;
    return snapshotImportResponse;
  }

  @override
  Future<Map<String, dynamic>> confirmImport(String importId) async {
    confirmedImportIds.add(importId);
    return confirmImportResponse;
  }
}

class _FakeServerSyncEngine extends ServerSyncEngine {
  _FakeServerSyncEngine(AppDatabase db)
      : super(
          apiClient: _unusedApiClient(db),
          cursorStore: SyncCursorStore(db),
          offlineMutationRunner:
              OfflineMutationRunner(OfflineMutationStore(db)),
        );

  final pushSources = <String>[];
  final pullSources = <String>[];
  final refreshSources = <String>[];
  Map<String, dynamic> pullResult = const <String, dynamic>{
    'changes': <Object?>[],
  };
  Object? pullError;

  @override
  Future<ServerSyncResult> pushPending() async {
    pushSources.add('push');
    throw StateError('pushPending must not run during cache refresh');
  }

  @override
  Future<Map<String, dynamic>> refreshCacheFromServer({
    int limit = 200,
    void Function(int pulledChanges, int pageCount)? onProgress,
  }) async {
    refreshSources.add('refresh');
    return pullChanges(limit: limit, onProgress: onProgress);
  }

  @override
  Future<Map<String, dynamic>> pullChanges({
    int limit = 200,
    void Function(int pulledChanges, int pageCount)? onProgress,
  }) async {
    pullSources.add('pull');
    final error = pullError;
    if (error != null) {
      throw error;
    }
    final pulled = pullResult['pulledChanges'];
    if (pulled is int) {
      onProgress?.call(pulled, 1);
    }
    return pullResult;
  }
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
