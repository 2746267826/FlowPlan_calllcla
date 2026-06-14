import 'dart:async';

import 'package:drift/drift.dart'
    show QueryRow, ResultSetImplementation, Selectable, Variable;
import 'package:drift/native.dart';
import 'package:flowplanv2/core/bootstrap/client_bootstrap_service.dart';
import 'package:flowplanv2/core/connection/server_connection_service.dart';
import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/server_api/remote_settings_repository.dart';
import 'package:flowplanv2/core/sync/sync_cursor_store.dart';
import 'package:flowplanv2/core/sync/sync_result.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/sync/server_sync_status_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  test('summary load accepts numeric and textual counter values', () async {
    final db = _TypedSummaryDatabase();
    addTearDown(db.close);

    final summary = await ServerSyncMvpSummary.load(db, SyncCursorStore(db));

    expect(summary.waitingMutations, 2);
    expect(summary.failedMutations, 4);
    expect(summary.ackedMutations, 0);
    expect(summary.conflictMutations, 0);
    expect(summary.syncedObjects, 3);
    expect(summary.recentMutations, isEmpty);
  });

  testWidgets('manual sync shows progress, summary counts, and success calls',
      (tester) async {
    final harness = await _ServerSyncPageHarness.create(tester);
    await harness.seedDenseDiagnostics();
    harness.connection.update(
      const ServerConnectionState(
        syncing: true,
        syncPhase: 'pulling',
        syncReason: 'manual',
        progressCurrent: 4,
        progressTotal: 9,
        lastSyncSummary: <String, Object?>{
          'accepted': 2,
          'conflicts': 1,
          'pulledChanges': 5,
          'trackingUpload': <String, Object?>{'ok': true},
        },
      ),
    );

    await harness.pumpPage(tester);

    expect(find.byType(ServerSyncStatusPage), findsOneWidget);
    expect(find.byKey(AppKeys.syncRunButton), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.textContaining('accepted 2'), findsOneWidget);
    expect(find.textContaining('conflicts 1'), findsOneWidget);
    expect(find.textContaining('pulled 5'), findsOneWidget);
    expect(find.textContaining('tracking {ok: true}'), findsOneWidget);
    expect(find.text('3'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    expect(find.text('7'), findsWidgets);
    expect(find.textContaining('orphan calendar missing'), findsOneWidget);
    expect(find.textContaining('#4'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.syncRunButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.clientApi.bootstrapCalls, 1);
    expect(harness.clientApi.settingsCalls, 1);
    expect(harness.syncEngine.pushCalls, 0);
    expect(harness.syncEngine.pullCalls, 1);
    expect(harness.trackingUploadCalls, 1);
  });

  testWidgets('buttons are disabled while actions run and failures surface',
      (tester) async {
    final bootstrapCompleter = Completer<Map<String, dynamic>>();
    final harness = await _ServerSyncPageHarness.create(
      tester,
      bootstrapCompleter: bootstrapCompleter,
    );
    await harness.pumpPage(tester);

    await tester.tap(find.byKey(AppKeys.syncRunButton));
    await tester.pump();

    expect(harness.clientApi.bootstrapCalls, 1);
    expect(_firstFilledButton(tester).onPressed, isNull);
    expect(
      _syncActionOutlinedButtons(tester).every(
        (button) => button.onPressed == null,
      ),
      isTrue,
    );
    expect(_lastTonalButton(tester).onPressed, isNull);

    bootstrapCompleter.complete(<String, dynamic>{
      'mode': 'server_first',
      'serverReachable': true,
      'syncCursor': 'cursor-after-delay',
      'settingsVersion': 11,
      'pendingActions': <String, Object?>{},
    });
    await tester.pump(const Duration(milliseconds: 100));

    harness.syncEngine.pullError = StateError('manual pull failed');
    await tester.tap(find.byType(OutlinedButton).at(1));
    await tester.pump();
    await pumpUntilFound(
      tester,
      find.textContaining('manual pull failed'),
      maxPumps: 20,
    );

    expect(harness.syncEngine.pushCalls, 0);
    expect(harness.clientApi.bootstrapCalls, 1);
    expect(find.text('Bad state: manual pull failed'), findsOneWidget);
  });

  testWidgets(
      'import prepare enables confirm and confirm bootstraps canonical data',
      (tester) async {
    final harness = await _ServerSyncPageHarness.create(tester);
    await harness.seedDenseDiagnostics();
    await harness.pumpPage(tester);

    expect(_lastTonalButton(tester).onPressed, isNull);

    await tester.tap(find.byType(OutlinedButton).at(2));
    await tester.pump();
    await _pumpUntil(
        tester, () => harness.clientApi.importSnapshots.isNotEmpty);

    expect(harness.clientApi.importSnapshots, hasLength(1));
    expect(
      harness.clientApi.importSnapshots.single['localStateSummary'],
      containsPair('offlineMutations', 6),
    );
    expect(_lastTonalButton(tester).onPressed, isNotNull);

    await tester.tap(find.byType(FilledButton).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(harness.clientApi.confirmedImportIds, <String>['import-789']);
    expect(harness.clientApi.bootstrapCalls, 1);
    expect(harness.clientApi.settingsCalls, 1);
    expect(harness.syncEngine.pushCalls, 0);
    expect(harness.syncEngine.pullCalls, 1);
  });

  testWidgets('empty import confirm shows error without service call',
      (tester) async {
    final harness = await _ServerSyncPageHarness.create(tester);
    await harness.pumpPage(tester);

    expect(_lastTonalButton(tester).onPressed, isNull);
    expect(harness.clientApi.confirmedImportIds, isEmpty);
  });

  testWidgets('service provider errors render runtime and progress errors',
      (tester) async {
    final harness = await _ServerSyncPageHarness.create(
      tester,
      bootstrapProviderError: StateError('bootstrap provider failed'),
      connectionProviderError: StateError('connection provider failed'),
    );

    await harness.pumpPage(tester);

    expect(find.textContaining('bootstrap provider failed'), findsOneWidget);
    expect(find.textContaining('connection provider failed'), findsOneWidget);
  });
}

FilledButton _firstFilledButton(WidgetTester tester) {
  return tester.widget<FilledButton>(find.byType(FilledButton).first);
}

Iterable<OutlinedButton> _syncActionOutlinedButtons(WidgetTester tester) {
  final buttons = find
      .byType(OutlinedButton)
      .evaluate()
      .map((element) => element.widget)
      .whereType<OutlinedButton>()
      .toList(growable: false);
  return buttons.skip(1).take(2);
}

FilledButton _lastTonalButton(WidgetTester tester) {
  return tester.widget<FilledButton>(find.byType(FilledButton).last);
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int maxPumps = 20,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (done()) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(done(), isTrue);
}

class _ServerSyncPageHarness {
  _ServerSyncPageHarness({
    required this.db,
    required this.clientApi,
    required this.syncEngine,
    required this.connection,
    this.bootstrapProviderError,
    this.connectionProviderError,
  });

  final AppDatabase db;
  final _RecordingClientApi clientApi;
  final _RecordingServerSyncEngine syncEngine;
  final _FakeServerConnectionService connection;
  final Object? bootstrapProviderError;
  final Object? connectionProviderError;
  var trackingUploadCalls = 0;

  static Future<_ServerSyncPageHarness> create(
    WidgetTester tester, {
    Object? bootstrapProviderError,
    Object? connectionProviderError,
    Completer<Map<String, dynamic>>? bootstrapCompleter,
  }) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final clientApi = _RecordingClientApi(db);
    clientApi.bootstrapCompleter = bootstrapCompleter;
    final syncEngine = _RecordingServerSyncEngine(db);
    final connection = _FakeServerConnectionService(
      const ServerConnectionState(
        level: ServerConnectionLevel.online,
        serverUrl: 'http://localhost:3202/api',
        deviceId: 'device-test',
        platform: 'windows',
      ),
    );
    return _ServerSyncPageHarness(
      db: db,
      clientApi: clientApi,
      syncEngine: syncEngine,
      connection: connection,
      bootstrapProviderError: bootstrapProviderError,
      connectionProviderError: connectionProviderError,
    );
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await pumpAppAt(
      tester,
      db: db,
      initialLocation: AppRoutes.serverSync,
      size: const Size(980, 980),
      overrides: [
        clientApiProvider.overrideWith((ref) async => clientApi),
        remoteSettingsRepositoryProvider.overrideWith(
          (ref) async => RemoteSettingsRepository(
            database: db,
            clientApi: clientApi,
          ),
        ),
        serverSyncEngineProvider.overrideWith((ref) async => syncEngine),
        clientBootstrapServiceProvider.overrideWith((ref) async {
          final error = bootstrapProviderError;
          if (error != null) {
            throw error;
          }
          return ClientBootstrapService(
            database: db,
            clientApi: clientApi,
            remoteSettingsRepository: RemoteSettingsRepository(
              database: db,
              clientApi: clientApi,
            ),
            syncEngineLoader: () async => syncEngine,
            operationLogs: ref.watch(dataOperationLogRepositoryProvider),
            trackingUploadRunner: () async {
              trackingUploadCalls++;
              return const <String, Object?>{'uploadedRecords': 2};
            },
          );
        }),
        serverConnectionServiceProvider.overrideWith((ref) async {
          final error = connectionProviderError;
          if (error != null) {
            throw error;
          }
          return connection;
        }),
      ],
    );
    await pumpUntilFound(tester, find.byType(ServerSyncStatusPage));
    await tester.pump();
  }

  Future<void> seedDenseDiagnostics() async {
    final now = DateTime.utc(2026, 6, 8, 10).toIso8601String();
    await db.customStatement(
      '''
      INSERT INTO offline_mutations (
        mutation_uid, object_type, local_id, action, payload_json,
        created_at, status, attempts, last_error
      ) VALUES
        ('mutation-pending-1', 'task_item', '101', 'create', '{}', ?, 'pending', 0, NULL),
        ('mutation-pending-2', 'calendar_event', '202', 'update', '{}', ?, 'sending', 1, NULL),
        ('mutation-pending-3', 'file_item', '303', 'delete', '{}', ?, 'pending', 2, NULL),
        ('mutation-failed', 'calendar_event', '404', 'update', '{}', ?, 'failed', 4, 'orphan calendar missing'),
        ('mutation-conflict', 'report_document', '505', 'update', '{}', ?, 'conflict', 5, 'remote changed'),
        ('mutation-acked', 'audit_log', '606', 'create', '{}', ?, 'acked', 1, NULL)
      ''',
      [now, now, now, now, now, now],
    );
    await db.customStatement(
      '''
      INSERT INTO sync_object_states (
        object_type, local_id, server_id, sync_state, local_version,
        server_version, created_at, updated_at, last_sync_error
      ) VALUES
        ('task_item', '101', NULL, 'pending_create', 1, 0, ?, ?, NULL),
        ('calendar_event', '202', 'event-202', 'pending_update', 2, 1, ?, ?, NULL),
        ('calendar_event', '404', 'event-404', 'failed', 3, 1, ?, ?, 'remote rejected'),
        ('report_document', '505', 'report-505', 'conflict', 4, 2, ?, ?, 'field conflict'),
        ('audit_log', '606', 'audit-606', 'synced', 5, 5, ?, ?, NULL),
        ('file_item', '707', 'file-707', 'synced', 6, 6, ?, ?, NULL)
      ''',
      [now, now, now, now, now, now, now, now, now, now, now, now],
    );
    await db.customStatement(
      '''
      INSERT INTO event_calendars (
        name, color_hex, source, sync_url, is_visible, is_default, created_at
      ) VALUES
        ('Outlook Main', '#3366FF', 'outlook', 'book-1', 1, 0, ?),
        ('Outlook Archive', '#33AA66', 'outlook', 'book-2', 1, 0, ?)
      ''',
      [now, now],
    );
    await db.customStatement(
      '''
      INSERT INTO calendar_events (
        uid, dtstamp, summary, dtstart, dtend, status, transp, source,
        event_calendar_id, color_hex, is_block
      ) VALUES
        ('event-1', ?, 'Outlook synced', ?, ?, 'confirmed', 'opaque', 'outlook', 1, '#3366FF', 0),
        ('event-2', ?, 'Outlook orphan', ?, ?, 'confirmed', 'opaque', 'outlook', NULL, '#3366FF', 0),
        ('event-3', ?, 'Outlook orphan 2', ?, ?, 'confirmed', 'opaque', 'outlook', NULL, '#3366FF', 0),
        ('event-4', ?, 'Outlook orphan 3', ?, ?, 'confirmed', 'opaque', 'outlook', NULL, '#3366FF', 0),
        ('event-5', ?, 'Outlook orphan 4', ?, ?, 'confirmed', 'opaque', 'outlook', NULL, '#3366FF', 0),
        ('event-6', ?, 'Outlook orphan 5', ?, ?, 'confirmed', 'opaque', 'outlook', NULL, '#3366FF', 0),
        ('event-7', ?, 'Outlook orphan 6', ?, ?, 'confirmed', 'opaque', 'outlook', NULL, '#3366FF', 0)
      ''',
      [
        now,
        now,
        now,
        now,
        now,
        now,
        now,
        now,
        now,
        now,
        now,
        now,
        now,
        now,
        now,
        now,
        now,
        now,
        now,
        now,
        now,
      ],
    );
  }
}

class _RecordingClientApi extends FakeClientApi {
  _RecordingClientApi(super.db);

  final importSnapshots = <Map<String, Object?>>[];
  final confirmedImportIds = <String>[];
  Completer<Map<String, dynamic>>? bootstrapCompleter;

  @override
  Future<Map<String, dynamic>> bootstrap() async {
    bootstrapCalls++;
    final completer = bootstrapCompleter;
    if (completer != null) {
      bootstrapCompleter = null;
      return completer.future;
    }
    final error = bootstrapError;
    if (error != null) {
      throw error;
    }
    return <String, dynamic>{
      'mode': 'server_first',
      'serverReachable': true,
      'syncCursor': 'cursor-after-bootstrap',
      'settingsVersion': 7,
      'pendingActions': <String, Object?>{'serverJobs': 1},
    };
  }

  @override
  Future<Map<String, dynamic>> createLocalSnapshotImport(
    Map<String, Object?> snapshot,
  ) async {
    importSnapshots.add(Map<String, Object?>.from(snapshot));
    return <String, dynamic>{
      'importId': 'import-789',
      'status': 'prepared',
      'receivedObjects': 12,
    };
  }

  @override
  Future<Map<String, dynamic>> confirmImport(String importId) async {
    confirmedImportIds.add(importId);
    return <String, dynamic>{
      'importId': importId,
      'status': 'confirmed',
    };
  }
}

class _RecordingServerSyncEngine extends FakeServerSyncEngine {
  _RecordingServerSyncEngine(super.db);

  Object? pushError;
  Object? pullError;

  @override
  Future<ServerSyncResult> pushPending() async {
    pushCalls++;
    final error = pushError;
    if (error != null) {
      throw error;
    }
    return const ServerSyncResult(
      pendingCount: 2,
      acceptedCount: 1,
      conflictCount: 1,
      rejectedCount: 0,
    );
  }

  @override
  Future<Map<String, dynamic>> pullChanges({
    int limit = 200,
    void Function(int pulledChanges, int pageCount)? onProgress,
  }) async {
    final error = pullError;
    if (error != null) {
      throw error;
    }
    return super.pullChanges(limit: limit, onProgress: onProgress);
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

  void update(ServerConnectionState next) {
    _state = next;
    notifyListeners();
  }

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
}

class _TypedSummaryDatabase extends AppDatabase {
  _TypedSummaryDatabase() : super(NativeDatabase.memory());

  @override
  Selectable<QueryRow> customSelect(
    String query, {
    List<Variable> variables = const [],
    Set<ResultSetImplementation> readsFrom = const {},
  }) {
    if (query.contains('ORDER BY id DESC')) {
      return _QueryRows(this, const <Map<String, Object?>>[]);
    }
    if (query.contains('FROM offline_mutations')) {
      return _QueryRows(this, const [
        <String, Object?>{
          'waiting': 2.9,
          'failed': '4',
          'acked': '',
          'conflict': null,
        },
      ]);
    }
    if (query.contains('FROM sync_object_states')) {
      return _QueryRows(this, const [
        <String, Object?>{
          'synced': 3,
          'pending': 1,
          'failed': 0,
          'conflict': 0,
        },
      ]);
    }
    if (query.contains('FROM event_calendars')) {
      return _QueryRows(this, const [
        <String, Object?>{
          'calendar_books': 0,
          'calendar_events': 0,
          'orphan_events': 0,
        },
      ]);
    }
    if (query.contains('FROM app_settings')) {
      return _QueryRows(this, const <Map<String, Object?>>[]);
    }
    return super.customSelect(
      query,
      variables: variables,
      readsFrom: readsFrom,
    );
  }
}

class _QueryRows with Selectable<QueryRow> {
  _QueryRows(this.db, this.rows);

  final AppDatabase db;
  final List<Map<String, Object?>> rows;

  @override
  Future<List<QueryRow>> get() async {
    return rows.map((row) => QueryRow(row, db)).toList(growable: false);
  }

  @override
  Stream<List<QueryRow>> watch() => Stream.fromFuture(get());
}
