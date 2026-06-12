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
    harness.engine.pushResult = const ServerSyncResult(
      acceptedCount: 2,
      conflictCount: 1,
      rejectedCount: 0,
      pendingCount: 3,
    );
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
    expect(harness.engine.pushSources, hasLength(1));
    expect(harness.engine.pullSources, hasLength(1));
    expect(
      progress.map((item) => item.phase),
      <String>[
        'preparing',
        'pushing',
        'tracking_upload',
        'pulling',
        'applying',
        'completed',
      ],
    );
    expect(progress[4].current, 6);
    expect(progress.last.current, 6);
    expect(progress.last.summary['accepted'], 2);
    expect(progress.last.summary['conflicts'], 1);
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
    expect(syncLog.metadataJson, contains('"settingsVersion":42'));
    expect(syncLog.metadataJson, contains('"accepted":2'));
    expect(syncLog.metadataJson, contains('"uploaded":3'));
  });

  test(
      'syncNow keeps sync successful when tracking upload fails and records the upload error',
      () async {
    final harness = _BootstrapHarness();
    addTearDown(harness.dispose);
    harness.engine.pushResult = const ServerSyncResult(
      acceptedCount: 1,
      conflictCount: 0,
      rejectedCount: 0,
      pendingCount: 1,
    );
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
    expect(syncLog.actor, 'system');
    expect(syncLog.metadataJson, contains('"ok":false'));
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
    expect(harness.engine.pullSources, isEmpty);
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
    harness.engine.pushError = StateError('push offline');
    final progress = <ClientSyncProgress>[];
    harness.service.onProgress = progress.add;

    final state = await harness.service.syncNow(source: 'manual');

    expect(state.mode, 'local_cache');
    expect(state.syncing, isFalse);
    expect(state.serverReachable, isFalse);
    expect(state.lastError, 'Bad state: push offline');
    expect(
      await harness.db.getSetting(ClientBootstrapService.lastErrorKey),
      'Bad state: push offline',
    );
    expect(
      progress.map((item) => item.phase),
      <String>['preparing', 'pushing', 'failed'],
    );
    expect(progress.last.summary, <String, Object?>{
      'source': 'manual',
      'error': 'Bad state: push offline',
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
    expect(harness.engine.pushSources, <String>['push']);
    expect(harness.engine.pullSources, <String>['pull']);
    final logs = await DataOperationLogRepository(harness.db).listRecent();
    final confirmLog = logs.singleWhere(
      (log) => log.action == 'client_import_confirm',
    );
    expect(confirmLog.entityId, 'import-456');
    expect(confirmLog.metadataJson, contains('confirmed'));
  });
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
  ServerSyncResult pushResult = const ServerSyncResult(
    acceptedCount: 0,
    conflictCount: 0,
    rejectedCount: 0,
  );
  Map<String, dynamic> pullResult = const <String, dynamic>{
    'changes': <Object?>[],
  };
  Object? pushError;
  Object? pullError;

  @override
  Future<ServerSyncResult> pushPending() async {
    pushSources.add('push');
    final error = pushError;
    if (error != null) {
      throw error;
    }
    return pushResult;
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
