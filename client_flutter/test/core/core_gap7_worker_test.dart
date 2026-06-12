import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show QueryRow;
import 'package:flowplanv2/core/bootstrap/client_bootstrap_service.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_runner.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/client_api.dart';
import 'package:flowplanv2/core/server_api/remote_settings_repository.dart';
import 'package:flowplanv2/core/storage/app_storage.dart';
import 'package:flowplanv2/core/storage/database_restore_service.dart';
import 'package:flowplanv2/core/sync/sync_cursor_store.dart';
import 'package:flowplanv2/core/sync/sync_engine.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../test_support/temp_app_storage.dart';
import '../test_support/test_database.dart';

void main() {
  test('pending restore with non-object metadata falls back to staged file',
      () async {
    await setUpTempAppStorage(prefix: 'core-gap7-restore-');
    final service = const DatabaseRestoreService();
    final stagedFile = await resolvePendingDatabaseRestoreFile();
    final metadataFile = await resolvePendingDatabaseRestoreMetadataFile();
    await stagedFile.parent.create(recursive: true);
    await _writeSqliteLikeDatabase(stagedFile);
    await metadataFile.writeAsString('[1,2,3]');

    final pending = await service.getPendingRestore();

    expect(pending, isNotNull);
    expect(pending!.sourcePath, stagedFile.path);
    expect(pending.stagedPath, stagedFile.path);
    expect(pending.stagedAt, await stagedFile.lastModified());
    expect(await metadataFile.exists(), isFalse);
  });

  test('startup sync begins from start and local snapshot serializes dates',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    var bootstrapCalls = 0;
    final apiClient = ApiClient(
      baseUri: Uri.parse('https://flowplan.test'),
      tokenStore: AuthTokenStore(db),
      httpClient: MockClient((request) async {
        if (request.url.path == '/client/bootstrap') {
          bootstrapCalls++;
          return http.Response(
            jsonEncode(<String, Object?>{
              'settingsVersion': 1,
              'syncCursor': 'startup-cursor',
            }),
            200,
          );
        }
        if (request.url.path == '/client/settings') {
          return http.Response(
            jsonEncode(<String, Object?>{
              'version': 2,
              'settings': <Object?>[],
            }),
            200,
          );
        }
        if (request.url.path == '/sync/pull') {
          return http.Response(
            jsonEncode(<String, Object?>{'changes': <Object?>[]}),
            200,
          );
        }
        return http.Response('{"ok":true}', 200);
      }),
    );
    final clientApi = ClientApi(apiClient);
    final service = ClientBootstrapService(
      database: db,
      clientApi: clientApi,
      remoteSettingsRepository: RemoteSettingsRepository(
        database: db,
        clientApi: clientApi,
      ),
      syncEngineLoader: () async => ServerSyncEngine(
        apiClient: apiClient,
        cursorStore: SyncCursorStore(db),
        offlineMutationRunner: OfflineMutationRunner(
          OfflineMutationStore(db),
        ),
      ),
      operationLogs: DataOperationLogRepository(db),
    );
    addTearDown(service.dispose);

    service.start();
    await _waitFor(() async =>
        await db.getSetting(ClientBootstrapService.modeKey) == 'server_first');

    expect(bootstrapCalls, 1);
    expect(service.state.mode, 'server_first');
    expect(service.state.syncing, isFalse);

    final converted = service.rowToJsonForTesting(
      QueryRow(
        <String, Object?>{
          'id': 1,
          'updated_at': DateTime.utc(2026, 6, 11, 10, 30),
        },
        db,
      ),
    );

    expect(converted['updated_at'], '2026-06-11T10:30:00.000Z');
  });
}

Future<void> _writeSqliteLikeDatabase(File file) async {
  await file.parent.create(recursive: true);
  final bytes = <int>[
    ...ascii.encode('SQLite format 3'),
    0,
    ...List<int>.filled(64, 0),
  ];
  await file.writeAsBytes(bytes);
}

Future<void> _waitFor(
  Future<bool> Function() predicate, {
  int attempts = 40,
}) async {
  for (var i = 0; i < attempts; i++) {
    if (await predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('Condition was not met within the bounded wait.');
}
