import 'dart:convert';

import 'package:flowplanv2/core/bootstrap/client_bootstrap_service.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_runner.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/platform/device_identity_service.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/client_api.dart';
import 'package:flowplanv2/core/server_api/remote_settings_repository.dart';
import 'package:flowplanv2/core/server_first/tracking_server_first_store.dart';
import 'package:flowplanv2/core/sync/sync_cursor_store.dart';
import 'package:flowplanv2/core/sync/sync_engine.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/actual/data/actual_activity_log_repository.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/reports/data/report_repository.dart';
import 'package:flowplanv2/features/sync/outlook_oauth_config.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_snapshot.dart';
import 'package:flowplanv2/features/tracker/models/activity_log_entry.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../test_support/test_database.dart';

void main() {
  test('small static constructors expose stable constants', () {
    expect(const AppKeys(), isA<AppKeys>());
    expect(AppKeys.shellCreateTask, const Key('flowplan.shell.create_task'));
    expect(const ActualActivityStatus(), isA<ActualActivityStatus>());
    expect(ActualActivityStatus(), isA<ActualActivityStatus>());
    expect(const ActualActivitySourceType(), isA<ActualActivitySourceType>());
    expect(ActualActivitySourceType(), isA<ActualActivitySourceType>());
    expect(ReportType(), isA<ReportType>());
    expect(ReportStatus(), isA<ReportStatus>());
    expect(
      const OutlookOAuthPlatformConfig(),
      isA<OutlookOAuthPlatformConfig>(),
    );
    expect(OutlookOAuthPlatformConfig.scopeString, 'Calendars.Read');
  });

  test('device identity reports windows and unknown testing platforms', () {
    expect(
      DeviceIdentityService(
        isWindowsForTesting: () => true,
        isAndroidForTesting: () => true,
      ).currentPlatform,
      'windows',
    );
    expect(
      DeviceIdentityService(
        isWindowsForTesting: () => false,
        isAndroidForTesting: () => false,
      ).currentPlatform,
      'unknown',
    );
    expect(
      DeviceIdentityService().currentPlatform,
      isIn(<String>['windows', 'android', 'unknown']),
    );
  });

  test('api client treats an empty JSON response as an empty object', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final client = ApiClient(
      baseUri: Uri.parse('https://flowplan.test/api'),
      tokenStore: AuthTokenStore(db),
      httpClient: MockClient((_) async => http.Response('  ', 204)),
    );

    await expectLater(client.getJson('/empty'), completion(isEmpty));
  });

  test('startup sync begins from start', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = _bootstrapService(db);
    addTearDown(service.dispose);
    var progressSources = <String>[];
    service.onProgress = (progress) {
      progressSources.add('${progress.source}:${progress.phase}');
    };

    service.start();
    await _waitFor(
      () =>
          progressSources.contains('startup:preparing') &&
          !service.state.syncing,
    );

    expect(progressSources, contains('startup:preparing'));
    expect(service.state.mode, 'server_first');
  });

  test(
      'local activity fallback uses one minute when duration and end are absent',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final day = DateTime(2026, 6, 12);
    await db.setBoolSetting('tracker.legacy_jsonl_to_database_migrated', true);
    await db.setBoolSetting('tracker.database_to_daily_jsonl_backfilled', true);
    final rawEntry = ActivityLogEntry(
      timestamp: day.add(const Duration(hours: 9)),
      type: ActivityLogEntryType.sample,
      processName: 'Code.exe',
      durationMinutes: 2,
      source: 'gap9',
    );
    await db.customStatement(
      '''
      INSERT INTO raw_activity_logs (
        entry_uid,
        occurred_at,
        day_key,
        entry_type,
        process_name,
        is_ignored,
        payload_json,
        created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        'gap9-local-fallback-raw',
        rawEntry.timestamp.toIso8601String(),
        '2026-06-12',
        rawEntry.type.value,
        rawEntry.processName,
        0,
        jsonEncode(rawEntry.toJson()),
        rawEntry.timestamp.toIso8601String(),
      ],
    );
    await db.into(db.activityRecords).insert(
          ActivityRecordsCompanion.insert(
            startTime: day.add(const Duration(hours: 9)),
            durationMinutes: const Value(0),
            processName: const Value('Code.exe'),
            source: const Value('gap9'),
          ),
        );
    final store = _TrackingStoreFake();
    final container = ProviderContainer(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        trackingServerFirstStoreProvider.overrideWith((ref) async => store),
      ],
    );
    addTearDown(container.dispose);
    final dynamic notifier = container.read(selectedDateProvider.notifier);
    notifier.setDate(day);

    final summary = await container.read(activityDaySummaryProvider.future);
    final previewRecords = summary['previewRecords'] as List<Object?>;
    final first = previewRecords.single as Map<String, Object?>;
    final payload = first['payload'] as Map<String, Object?>;

    expect(summary['source'], 'local-fallback');
    expect(first['metricMinutes'], 1);
    expect(payload['durationMinutes'], 1);
  });

  test('actual log numeric helpers and JSON preserve optional nulls', () {
    final start = DateTime.utc(2026, 6, 12, 9);
    final actual = ActualActivityLog(
      id: 1,
      actualUid: 'actual-1',
      title: 'Focused work',
      startAt: start,
      endAt: start.add(const Duration(minutes: 25)),
      sourceType: ActualActivitySourceType.manual,
      sourceId: null,
      sourcePayloadJson: '{}',
      confidence: ActualActivityLog.readDoubleForTesting(0.8),
      status: ActualActivityStatus.confirmed,
      note: null,
      createdAt: start,
      updatedAt: start,
      confirmedAt: null,
      rejectedAt: null,
      mergedIntoId: null,
    );

    expect(actual.isConfirmed, isTrue);
    expect(actual.toJson(), containsPair('sourceId', null));
    expect(ActualActivityLog.readDoubleForTesting(null), 0);
  });

  test('outlook snapshot copyWith can replace summary only', () {
    final base = OutlookTaskMirrorSnapshot(
      taskId: 1,
      taskUid: 'task-1',
      taskListId: 2,
      taskListName: 'Inbox',
      summary: 'Before',
      description: null,
      location: null,
      status: 'needsAction',
      dtstart: null,
      due: null,
      completed: null,
      durationMinutes: 0,
      priorityLocal: 0,
      percentComplete: 0,
      isAutoScheduled: false,
      isSplittable: true,
      isLocked: false,
      reminderMinutesBefore: 0,
    );

    final changed = base.copyWith(summary: 'After');

    expect(changed.summary, 'After');
    expect(changed.taskListName, 'Inbox');
    expect(changed.fingerprint, isNot(base.fingerprint));
  });
}

Future<void> _waitFor(
  bool Function() predicate, {
  int attempts = 40,
}) async {
  for (var i = 0; i < attempts; i++) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
  fail('Condition was not met within the bounded wait.');
}

ClientBootstrapService _bootstrapService(AppDatabase db) {
  final apiClient = ApiClient(
    baseUri: Uri.parse('https://flowplan.test'),
    tokenStore: AuthTokenStore(db),
    httpClient: MockClient((request) async {
      switch (request.url.path) {
        case '/client/bootstrap':
          return http.Response(
            jsonEncode(<String, Object?>{
              'settingsVersion': 1,
              'syncCursor': 'cursor',
            }),
            200,
          );
        case '/client/settings':
          return http.Response(
            jsonEncode(<String, Object?>{
              'version': 1,
              'settings': <Object?>[],
            }),
            200,
          );
        case '/sync/pull':
          return http.Response(
            jsonEncode(<String, Object?>{'changes': <Object?>[]}),
            200,
          );
        default:
          return http.Response('{"ok":true}', 200);
      }
    }),
  );
  final clientApi = ClientApi(apiClient);
  return ClientBootstrapService(
    database: db,
    clientApi: clientApi,
    remoteSettingsRepository: RemoteSettingsRepository(
      database: db,
      clientApi: clientApi,
    ),
    syncEngineLoader: () async => ServerSyncEngine(
      apiClient: apiClient,
      cursorStore: SyncCursorStore(db),
      offlineMutationRunner: OfflineMutationRunner(OfflineMutationStore(db)),
    ),
    operationLogs: DataOperationLogRepository(db),
  );
}

class _TrackingStoreFake implements TrackingServerFirstStore {
  @override
  Future<Map<String, dynamic>> activityDaySummary({
    required DateTime date,
  }) async {
    return <String, dynamic>{
      'range': <String, Object?>{
        'start': DateTime(date.year, date.month, date.day).toIso8601String(),
        'end': DateTime(date.year, date.month, date.day + 1).toIso8601String(),
      },
      'source': 'server',
      'insights': <String, Object?>{'totalMinutes': 0},
      'previewRecords': <Map<String, Object?>>[],
      'sessions': <Map<String, Object?>>[],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
