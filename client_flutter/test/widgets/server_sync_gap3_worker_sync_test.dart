import 'dart:async';

import 'package:drift/drift.dart' show QueryRow;
import 'package:flowplanv2/core/bootstrap/client_bootstrap_service.dart';
import 'package:flowplanv2/core/connection/server_connection_service.dart';
import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/server_api/remote_settings_repository.dart';
import 'package:flowplanv2/core/server_api/server_config_store.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/sync/server_sync_status_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../test_support/provider_harness.dart';
import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  test('local mutation diagnostics fall back when created_at is malformed',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final diagnostic = LocalMutationDiagnostic.fromRow(
      QueryRow(
        <String, Object?>{
          'id': 9,
          'mutation_uid': 'mutation-bad-date',
          'object_type': 'task_item',
          'local_id': '101',
          'action': 'update',
          'status': 'failed',
          'attempts': 3,
          'last_error': 'bad payload',
          'created_at': 'not-a-date',
        },
        db,
      ),
    );

    expect(diagnostic.createdAt, DateTime.fromMillisecondsSinceEpoch(0));
    expect(diagnostic.lastError, 'bad payload');
  });

  testWidgets('saving server URL validates, normalizes, and reconnects',
      (tester) async {
    final harness = await _ServerSyncHarness.pump(tester);

    await tester.enterText(find.byType(TextField), 'localhost-only');
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.save_outlined));
    await tester.pump();

    expect(harness.config.saveCalls, 0);
    expect(harness.connection.startCalls, 0);

    await tester.enterText(find.byType(TextField), 'https://example.test/root/');
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.save_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(harness.config.saveCalls, 1);
    expect(harness.config.current.toString(), 'https://example.test/root/api');
    expect(harness.connection.startCalls, 1);
    expect(harness.connection.syncNowCalls, 1);
    expect(harness.connection.lastSyncSource, 'server_url_saved');
  });

  testWidgets('save and action failures surface snackbars', (tester) async {
    final saveHarness = await _ServerSyncHarness.pump(
      tester,
      saveError: StateError('save failed'),
    );

    await tester.enterText(find.byType(TextField), 'https://example.test/api');
    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.save_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(saveHarness.config.saveCalls, 1);
    expect(find.textContaining('save failed'), findsOneWidget);

    final actionHarness = await _ServerSyncHarness.pump(
      tester,
      syncNowError: StateError('manual retry failed'),
    );

    await _tapEnabledOutlinedButtonWithIcon(tester, Icons.sync_outlined);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(actionHarness.bootstrap.syncNowCalls, 1);
    expect(find.textContaining('manual retry failed'), findsOneWidget);
  });

  testWidgets('empty prepared import id reaches confirm guard', (tester) async {
    final harness = await _ServerSyncHarness.pump(tester, importId: '');

    await tester.tap(
      find.widgetWithIcon(OutlinedButton, Icons.inventory_2_outlined),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(FilledButton).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(harness.bootstrap.prepareImportCalls, 1);
    expect(harness.bootstrap.confirmImportCalls, 0);
  });

  testWidgets('refresh reloads summary and summary errors are rendered',
      (tester) async {
    final harness = await _ServerSyncHarness.pump(tester);
    final refresh = tester.widget<RefreshIndicator>(
      find.byType(RefreshIndicator),
    );
    final before = harness.summaryLoads;

    await refresh.onRefresh();
    await tester.pump();

    expect(harness.summaryLoads, greaterThan(before));

    await _ServerSyncHarness.pump(
      tester,
      summaryError: StateError('summary failed'),
    );

    await _pumpUntilFound(
      tester,
      find.textContaining('summary failed'),
      attempts: 60,
    );
  });

  testWidgets('back button pops when possible and falls back to timeline',
      (tester) async {
    await _ServerSyncHarness.pump(tester);

    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('timeline fallback'), findsOneWidget);

    final popHarness = await _ServerSyncHarness.pump(
      tester,
      initialLocation: AppRoutes.timeline,
    );
    unawaited(popHarness.router.push(AppRoutes.serverSync));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await _pumpUntilFound(tester, find.byType(ServerSyncStatusPage));

    await tester.tap(find.byIcon(Icons.arrow_back).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('timeline fallback'), findsOneWidget);
  });

  testWidgets('zero progress totals display current count only', (tester) async {
    await _ServerSyncHarness.pump(
      tester,
      connectionState: const ServerConnectionState(
        syncing: true,
        syncPhase: 'pulling',
        progressCurrent: 7,
        progressTotal: 0,
      ),
    );

    expect(find.textContaining('7'), findsWidgets);
  });
}

class _ServerSyncHarness {
  _ServerSyncHarness({
    required this.db,
    required this.router,
    required this.config,
    required this.bootstrap,
    required this.connection,
    required int Function() summaryLoads,
  }) : _summaryLoads = summaryLoads;

  final AppDatabase db;
  final GoRouter router;
  final _RecordingServerConfigStore config;
  final _RecordingBootstrapService bootstrap;
  final _FakeServerConnectionService connection;
  final int Function() _summaryLoads;

  int get summaryLoads => _summaryLoads();

  static Future<_ServerSyncHarness> pump(
    WidgetTester tester, {
    String initialLocation = AppRoutes.serverSync,
    Object? saveError,
    Object? syncNowError,
    Object? summaryError,
    String importId = 'import-1',
    ServerConnectionState connectionState = const ServerConnectionState(
      level: ServerConnectionLevel.online,
      serverUrl: 'http://localhost:3202/api',
      deviceId: 'device-test',
      platform: 'windows',
    ),
  }) async {
    final db = createTestDatabase();
    final config = _RecordingServerConfigStore(db, saveError: saveError);
    final bootstrap = _RecordingBootstrapService(
      db,
      syncNowError: syncNowError,
      importId: importId,
    );
    final connection = _FakeServerConnectionService(connectionState);
    var summaryLoads = 0;
    final router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: AppRoutes.timeline,
          builder: (context, state) => const Scaffold(
            body: Center(child: Text('timeline fallback')),
          ),
        ),
        GoRoute(
          path: AppRoutes.serverSync,
          builder: (context, state) => const ServerSyncStatusPage(),
        ),
      ],
    );

    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await db.close();
    });

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpFlowPlanTestApp(
      tester,
      db: db,
      size: const Size(900, 900),
      overrides: [
        serverConfigStoreProvider.overrideWith((ref) => config),
        clientBootstrapServiceProvider.overrideWith((ref) async => bootstrap),
        serverConnectionServiceProvider.overrideWith((ref) async => connection),
        serverSyncMvpSummaryProvider.overrideWith((ref) async {
          summaryLoads++;
          final error = summaryError;
          if (error != null) {
            throw error;
          }
          return _summary();
        }),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
    if (initialLocation == AppRoutes.serverSync) {
      await _pumpUntilFound(tester, find.byType(ServerSyncStatusPage));
    }
    await tester.pump();

    return _ServerSyncHarness(
      db: db,
      router: router,
      config: config,
      bootstrap: bootstrap,
      connection: connection,
      summaryLoads: () => summaryLoads,
    );
  }
}

ServerSyncMvpSummary _summary() {
  return const ServerSyncMvpSummary(
    waitingMutations: 1,
    failedMutations: 0,
    ackedMutations: 2,
    conflictMutations: 0,
    syncedObjects: 3,
    pendingObjects: 1,
    failedObjects: 0,
    conflictObjects: 0,
    outlookCalendarBooks: 0,
    outlookCalendarEvents: 0,
    outlookOrphanEvents: 0,
    recentMutations: <LocalMutationDiagnostic>[],
  );
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int attempts = 20,
}) async {
  for (var i = 0; i < attempts; i++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(finder, findsWidgets);
}

Future<void> _tapEnabledOutlinedButtonWithIcon(
  WidgetTester tester,
  IconData icon,
) async {
  final finder = find.widgetWithIcon(OutlinedButton, icon);
  for (var i = 0; i < 20; i++) {
    final widgets = tester.widgetList<OutlinedButton>(finder).toList();
    for (var index = 0; index < widgets.length; index += 1) {
      if (widgets[index].onPressed != null) {
        await tester.tap(finder.at(index));
        await tester.pump();
        return;
      }
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    tester.widgetList<OutlinedButton>(finder).any(
          (button) => button.onPressed != null,
        ),
    isTrue,
  );
}

class _RecordingServerConfigStore extends ServerConfigStore {
  _RecordingServerConfigStore(
    super.database, {
    Object? saveError,
  })  : current = Uri.parse('http://localhost:3202/api'),
        _saveError = saveError;

  Uri current;
  final Object? _saveError;
  var saveCalls = 0;

  @override
  Future<Uri> readBaseUri() async => current;

  @override
  Future<void> saveBaseUri(Uri uri) async {
    saveCalls++;
    final error = _saveError;
    if (error != null) {
      throw error;
    }
    current = ServerConfigStore.normalizeBaseUri(uri);
  }
}

class _RecordingBootstrapService extends ClientBootstrapService {
  _RecordingBootstrapService._(
    AppDatabase db,
    FakeClientApi clientApi, {
    this.syncNowError,
    required this.importId,
  }) : super(
          database: db,
          clientApi: clientApi,
          remoteSettingsRepository: RemoteSettingsRepository(
            database: db,
            clientApi: clientApi,
          ),
          syncEngineLoader: () async => FakeServerSyncEngine(db),
          operationLogs: DataOperationLogRepository(db),
        );

  factory _RecordingBootstrapService(
    AppDatabase db, {
    Object? syncNowError,
    String importId = 'import-1',
  }) {
    return _RecordingBootstrapService._(
      db,
      FakeClientApi(db),
      syncNowError: syncNowError,
      importId: importId,
    );
  }

  final Object? syncNowError;
  final String importId;
  var bootstrapAndSyncCalls = 0;
  var syncNowCalls = 0;
  var prepareImportCalls = 0;
  var confirmImportCalls = 0;

  @override
  Future<ClientRuntimeState> bootstrapAndSync({String source = 'manual'}) async {
    bootstrapAndSyncCalls++;
    return const ClientRuntimeState(
      mode: 'server_first',
      serverReachable: true,
    );
  }

  @override
  Future<ClientRuntimeState> syncNow({String source = 'manual'}) async {
    syncNowCalls++;
    final error = syncNowError;
    if (error != null) {
      throw error;
    }
    return const ClientRuntimeState(
      mode: 'server_first',
      serverReachable: true,
    );
  }

  @override
  Future<Map<String, dynamic>> prepareLocalImport() async {
    prepareImportCalls++;
    return <String, dynamic>{'importId': importId};
  }

  @override
  Future<Map<String, dynamic>> confirmImport(String importId) async {
    confirmImportCalls++;
    return <String, dynamic>{'importId': importId, 'status': 'confirmed'};
  }
}

class _FakeServerConnectionService extends ChangeNotifier
    implements ServerConnectionService {
  _FakeServerConnectionService(this._state);

  ServerConnectionState _state;
  var startCalls = 0;
  var syncNowCalls = 0;
  String? lastSyncSource;

  @override
  ServerConnectionState get state => _state;

  @override
  void start() {
    startCalls++;
  }

  @override
  void requestSync({
    String source = 'manual',
    String? reason,
    bool immediate = false,
  }) {}

  @override
  Future<void> syncNow({String source = 'manual', String? reason}) async {
    syncNowCalls++;
    lastSyncSource = source;
  }

  @override
  Future<void> heartbeat({String eventSource = 'timer'}) async {}

  void update(ServerConnectionState next) {
    _state = next;
    notifyListeners();
  }
}
