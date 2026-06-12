import 'dart:convert';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_runner.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/client_api.dart';
import 'package:flowplanv2/core/sync/sync_cursor_store.dart';
import 'package:flowplanv2/core/sync/sync_engine.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flowplanv2/features/sync/outlook_settings_page.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../test_support/test_database.dart';
import '../test_support/user_workflow_harness.dart';

void main() {
  testWidgets('server-managed Outlook refresh handles success and failure',
      (tester) async {
    final harness = await _pumpOutlookSettings(tester);
    await pumpUntilFound(tester, find.textContaining('manual-test'));

    expect(find.byType(OutlookSettingsPage), findsOneWidget);
    expect(find.textContaining('字段覆盖'), findsOneWidget);
    expect(find.textContaining('缺地点 1'), findsOneWidget);
    expect(find.textContaining('manual-test'), findsOneWidget);
    expect(find.textContaining('succeeded'), findsOneWidget);
    expect(find.textContaining('日历 1'), findsOneWidget);
    expect(find.textContaining('更新 2'), findsOneWidget);
    expect(harness.clientApi.adminRunsCalls, 1);
    expect(harness.clientApi.adminDiagnosticsCalls, 1);

    await _expandRunLogTile(tester, 'manual-test');
    expect(find.textContaining('Graph 字段统计'), findsOneWidget);
    expect(find.textContaining('缺 location 1'), findsOneWidget);
    expect(find.textContaining('下发重放：日历本 1，日程 2，变更 3'), findsOneWidget);

    await tester.tap(_serverRefreshButton());
    await pumpUntilFound(
      tester,
      find.textContaining('mock-refreshed'),
      maxPumps: 20,
    );

    expect(harness.clientApi.refreshCalls, 1);
    expect(harness.serverSyncEngine.pullCalls, 1);
    expect(harness.reminderService.rebuildCalls, 1);
    expect(harness.clientApi.adminRunsCalls, 2);
    expect(harness.clientApi.adminDiagnosticsCalls, 2);
    expect(find.textContaining('mock-refreshed'), findsOneWidget);
    expect(find.textContaining('客户端已拉取 1 条服务端变更'), findsOneWidget);
    await pumpUntilFound(tester, find.textContaining('manual-refresh'));
    expect(find.textContaining('manual-refresh'), findsOneWidget);
    expect(find.textContaining('日历 2'), findsOneWidget);
    expect(find.text('日历 2，更新 3，删除 1'), findsOneWidget);

    harness.clientApi.refreshError = StateError('mock-refresh-failed');
    await tester.tap(_serverRefreshButton());
    await pumpUntilFound(
      tester,
      find.textContaining('mock-refresh-failed'),
      maxPumps: 20,
    );

    expect(harness.clientApi.refreshCalls, 2);
    expect(harness.serverSyncEngine.pullCalls, 1);
    expect(harness.reminderService.rebuildCalls, 1);
    expect(harness.clientApi.adminRunsCalls, 2);
    expect(harness.clientApi.adminDiagnosticsCalls, 2);
    expect(find.textContaining('mock-refresh-failed'), findsOneWidget);
  });

  testWidgets('server-managed Outlook diagnostics handles empty results',
      (tester) async {
    final harness = await _pumpOutlookSettings(
      tester,
      emptyDiagnostics: true,
    );

    await pumpUntilFound(tester, find.textContaining('暂无 Outlook 服务端同步运行记录'));

    expect(find.textContaining('字段覆盖：事件 0'), findsOneWidget);
    expect(find.textContaining('暂无 Outlook 服务端同步运行记录'), findsOneWidget);
    expect(harness.clientApi.adminRunsCalls, 1);
    expect(harness.clientApi.adminDiagnosticsCalls, 1);
  });

  testWidgets('server-managed Outlook diagnostics reports admin API errors',
      (tester) async {
    final harness = await _pumpOutlookSettings(
      tester,
      adminDiagnosticsError: StateError('diagnostics-down'),
    );

    await pumpUntilFound(tester, find.textContaining('diagnostics-down'));

    expect(find.textContaining('Outlook 服务端诊断读取失败'), findsOneWidget);
    expect(find.textContaining('diagnostics-down'), findsOneWidget);
    expect(harness.clientApi.adminRunsCalls, 1);
    expect(harness.clientApi.adminDiagnosticsCalls, 1);
  });
}

Finder _serverRefreshButton() {
  return find.ancestor(
    of: find.byIcon(Icons.refresh_outlined),
    matching: find.byType(ElevatedButton),
  );
}

Future<void> _expandRunLogTile(
  WidgetTester tester,
  String triggerSource,
) async {
  await tester.tap(find.textContaining(triggerSource).first);
  await tester.pumpAndSettle();
}

Future<_OutlookWidgetHarness> _pumpOutlookSettings(
  WidgetTester tester, {
  Object? refreshError,
  Object? adminRunsError,
  Object? adminDiagnosticsError,
  bool emptyDiagnostics = false,
}) async {
  final db = createTestDatabase();
  final clientApi = _FakeClientApi(
    db,
    refreshError: refreshError,
    adminRunsError: adminRunsError,
    adminDiagnosticsError: adminDiagnosticsError,
    emptyDiagnostics: emptyDiagnostics,
  );
  final serverSyncEngine = _FakeServerSyncEngine(db);
  final reminderService = _FakeReminderService(db);

  await pumpAppAt(
    tester,
    db: db,
    initialLocation: AppRoutes.outlookSync,
    size: const Size(900, 900),
    overrides: [
      clientApiProvider.overrideWith((ref) async => clientApi),
      serverSyncEngineProvider.overrideWith((ref) async => serverSyncEngine),
      reminderServiceProvider.overrideWithValue(reminderService),
    ],
  );

  addTearDown(() async {
    reminderService.dispose();
    await db.close();
  });

  return _OutlookWidgetHarness(
    clientApi: clientApi,
    serverSyncEngine: serverSyncEngine,
    reminderService: reminderService,
  );
}

class _OutlookWidgetHarness {
  const _OutlookWidgetHarness({
    required this.clientApi,
    required this.serverSyncEngine,
    required this.reminderService,
  });

  final _FakeClientApi clientApi;
  final _FakeServerSyncEngine serverSyncEngine;
  final _FakeReminderService reminderService;
}

class _FakeClientApi extends ClientApi {
  _FakeClientApi(
    AppDatabase db, {
    this.refreshError,
    this.adminRunsError,
    this.adminDiagnosticsError,
    this.emptyDiagnostics = false,
  }) : super(_mockApiClient(db));

  Object? refreshError;
  Object? adminRunsError;
  Object? adminDiagnosticsError;
  bool emptyDiagnostics;
  var refreshCalls = 0;
  var adminRunsCalls = 0;
  var adminDiagnosticsCalls = 0;

  @override
  Future<Map<String, dynamic>> refreshOutlook() async {
    refreshCalls++;
    final error = refreshError;
    if (error != null) {
      throw error;
    }
    return <String, dynamic>{
      'status': 'mock-refreshed',
      'calendarCount': 2,
      'eventUpserts': 3,
      'eventDeletes': 1,
    };
  }

  @override
  Future<Map<String, dynamic>> adminOutlookRuns() async {
    adminRunsCalls++;
    final error = adminRunsError;
    if (error != null) {
      throw error;
    }
    if (emptyDiagnostics) {
      return <String, dynamic>{
        'runs': <Map<String, Object?>>[],
      };
    }
    final refreshed = adminRunsCalls > 1;
    return <String, dynamic>{
      'runs': <Map<String, Object?>>[
        <String, Object?>{
          'triggerSource': refreshed ? 'manual-refresh' : 'manual-test',
          'status': 'succeeded',
          'startedAt':
              refreshed ? '2026-06-09T10:05:00Z' : '2026-06-09T10:00:00Z',
          'calendarCount': refreshed ? 2 : 1,
          'eventUpserts': refreshed ? 3 : 2,
          'eventDeletes': refreshed ? 1 : 0,
          'metadata': <String, Object?>{
            'fieldStats': <String, Object?>{
              'totalEvents': refreshed ? 3 : 2,
              'removedEvents': refreshed ? 1 : 0,
              'privateEvents': 0,
              'missingSubject': 0,
              'missingLocation': 1,
              'missingBodyPreview': 0,
              'missingOrganizer': 0,
              'recurrenceFallbacks': 0,
              'masterLookupFailures': 0,
            },
            'replay': <String, Object?>{
              'calendarBooks': refreshed ? 2 : 1,
              'calendarEvents': refreshed ? 3 : 2,
              'changes': refreshed ? 4 : 3,
            },
          },
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> adminOutlookDiagnostics() async {
    adminDiagnosticsCalls++;
    final error = adminDiagnosticsError;
    if (error != null) {
      throw error;
    }
    if (emptyDiagnostics) {
      return <String, dynamic>{
        'fieldCoverage': <String, Object?>{},
        'recentRuns': <Map<String, Object?>>[],
      };
    }
    return <String, dynamic>{
      'fieldCoverage': <String, Object?>{
        'eventCount': 2,
        'missingTitle': 0,
        'missingLocation': 1,
        'missingBodyPreview': 0,
        'missingOrganizer': 0,
      },
      'recentRuns': <Map<String, Object?>>[],
    };
  }
}

class _FakeServerSyncEngine extends ServerSyncEngine {
  _FakeServerSyncEngine(AppDatabase db)
      : super(
          apiClient: _mockApiClient(db),
          cursorStore: SyncCursorStore(db),
          offlineMutationRunner: OfflineMutationRunner(
            OfflineMutationStore(db),
          ),
        );

  var pullCalls = 0;

  @override
  Future<Map<String, dynamic>> pullChanges({
    int limit = 200,
    void Function(int pulledChanges, int pageCount)? onProgress,
  }) async {
    pullCalls++;
    onProgress?.call(1, 1);
    return <String, dynamic>{
      'changes': <Map<String, Object?>>[
        <String, Object?>{'id': 'change-1'},
      ],
      'pulledChanges': 1,
      'pageCount': 1,
    };
  }
}

class _FakeReminderService extends ReminderService {
  _FakeReminderService(AppDatabase db)
      : super(
          database: db,
          defaultEventReminderMinutes: () => 0,
        );

  var rebuildCalls = 0;

  @override
  Future<ReminderRebuildResult> rebuildSystemSchedule() async {
    rebuildCalls++;
    return const ReminderRebuildResult(
      scheduledCount: 0,
      canScheduleExactAlarms: false,
    );
  }
}

ApiClient _mockApiClient(AppDatabase db) {
  return ApiClient(
    baseUri: Uri.parse('http://localhost:3202/api'),
    tokenStore: AuthTokenStore(db),
    httpClient: MockClient((request) async {
      return http.Response(jsonEncode(<String, Object?>{}), 500);
    }),
  );
}
