import 'package:flowplanv2/core/bootstrap/client_bootstrap_service.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/server_api/remote_settings_repository.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/sync/server_sync_status_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('server sync run replays queue state and handles failures', (
    tester,
  ) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await seedSyncDiagnostics(db);
    final clientApi = FakeClientApi(db);
    final syncEngine = FakeServerSyncEngine(db);

    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.serverSync,
      size: const Size(900, 900),
      overrides: [
        clientApiProvider.overrideWith((ref) async => clientApi),
        remoteSettingsRepositoryProvider.overrideWith(
          (ref) async => RemoteSettingsRepository(
            database: db,
            clientApi: clientApi,
          ),
        ),
        serverSyncEngineProvider.overrideWith((ref) async => syncEngine),
        clientBootstrapServiceProvider.overrideWith(
          (ref) async => ClientBootstrapService(
            database: db,
            clientApi: clientApi,
            remoteSettingsRepository: RemoteSettingsRepository(
              database: db,
              clientApi: clientApi,
            ),
            syncEngineLoader: () async => syncEngine,
            operationLogs: ref.watch(dataOperationLogRepositoryProvider),
            trackingUploadRunner: () async => const <String, Object?>{
              'uploadedBatches': 0,
              'uploadedRecords': 0,
            },
          ),
        ),
      ],
    );
    await pumpUntilFound(tester, find.byType(ServerSyncStatusPage));

    expect(find.byType(ServerSyncStatusPage), findsOneWidget);
    expect(find.byKey(AppKeys.syncRunButton), findsOneWidget);
    expect(find.textContaining('network timeout'), findsOneWidget);
    expect(find.textContaining('#2'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.syncRunButton));
    await tester.pump();
    expect(tester.widget<Widget>(find.byKey(AppKeys.syncRunButton)),
        isA<Widget>());
    await tester.pump(const Duration(milliseconds: 100));

    expect(clientApi.bootstrapCalls, 1);
    expect(clientApi.settingsCalls, 1);
    expect(syncEngine.pushCalls, 0);
    expect(syncEngine.pullCalls, 1);
    expect(find.textContaining('pulled 3'), findsOneWidget);

    clientApi.bootstrapError = StateError('manual sync failed');
    await tester.tap(find.byKey(AppKeys.syncRunButton));
    await tester.pump();
    await pumpUntilFound(
      tester,
      find.textContaining('manual sync failed'),
      maxPumps: 20,
    );

    expect(clientApi.bootstrapCalls, 2);
    expect(syncEngine.pushCalls, 0);
    expect(find.text('Bad state: manual sync failed'), findsOneWidget);
    expect(find.textContaining('manual sync failed'), findsWidgets);
  });
}
