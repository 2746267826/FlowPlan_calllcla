import 'dart:convert';

import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/platform/device_identity_service.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/api_error.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_first/mutation_coordinator.dart';
import 'package:flowplanv2/core/sync/server_sync_change_applier.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/features/actual/data/actual_activity_log_repository.dart';
import 'package:flowplanv2/features/actual/services/blocking_event_actual_candidate_service.dart';
import 'package:flowplanv2/features/audit/presentation/data_operation_log_page.dart';
import 'package:flowplanv2/features/scheduler/scheduler_engine.dart';
import 'package:flowplanv2/features/tracker/data/activity_record_repository.dart';
import 'package:flowplanv2/shared/widgets/time_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../test_support/test_database.dart';

void main() {
  test('misc static containers and simple summaries are constructible', () {
    expect(const ActualActivityStatus(), isA<ActualActivityStatus>());
    expect(
      const ActualActivitySourceType(),
      isA<ActualActivitySourceType>(),
    );
    expect(const AppKeys(), isA<AppKeys>());
    expect(const DataOperationLogPage(), isA<DataOperationLogPage>());
    expect(
      const BlockingEventCandidateRunResult(
        created: 1,
        skippedExisting: 2,
        skippedConfirmedOverlap: 3,
        skippedTrackingConflict: 4,
        skippedNotEnded: 5,
      ).skippedTotal,
      14,
    );
    expect(
      DeviceIdentityService(
        isWindowsForTesting: () => false,
        isAndroidForTesting: () => true,
      ).currentPlatform,
      'android',
    );
  });

  test('actual log row parser accepts string confidence values', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 6, 11, 9);
    await db.customStatement(
      '''
      INSERT INTO actual_activity_logs (
        actual_uid, title, start_at, end_at, status, source_type, source_id,
        source_payload_json, confidence, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        'actual-string-confidence',
        'String confidence',
        now.toIso8601String(),
        now.add(const Duration(minutes: 30)).toIso8601String(),
        ActualActivityStatus.candidate,
        ActualActivitySourceType.manual,
        '',
        '{}',
        '0.75',
        now.toIso8601String(),
        now.toIso8601String(),
      ],
    );

    final row = await ActualActivityLogRepository(db)
        .getBySource(sourceType: ActualActivitySourceType.manual, sourceId: '');

    expect(row!.confidence, 0.75);
    expect(ActualActivityLog.readDoubleForTesting('0.25'), 0.25);
    expect(ActualActivityLog.readDoubleForTesting('bad'), 0);
  });

  test('api client converts map-like JSON and rejects unsupported verbs',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final client = _ExposedApiClient(
      baseUri: Uri.parse('http://localhost:3202/api'),
      tokenStore: AuthTokenStore(db),
      httpClient: MockClient(
        (_) async => http.Response('{"ok":true}', 200),
      ),
    );

    expect(await client.getJson('/client/ping'), containsPair('ok', true));
    await expectLater(
      client.sendUnsupported(),
      throwsA(
        isA<ApiError>().having(
          (error) => error.message,
          'message',
          contains('Unsupported HTTP method'),
        ),
      ),
    );
  });

  test('mutation coordinator generates a local id when payload lacks ids',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final coordinator = MutationCoordinator(
      mutationStore: OfflineMutationStore(db),
    );

    final result = await coordinator.enqueueBusinessMutation(
      objectType: 'gap7_object',
      action: OfflineMutationAction.update,
      payload: const <String, Object?>{'summary': 'No ids'},
      pushImmediately: false,
    );

    expect(result.localId, startsWith('local-'));
  });

  test('server sync summaries expose defaults and unknown upserts skip', () {
    final change = ServerSyncChange.fromJson(const <String, Object?>{
      'changeId': 'change-1',
      'objectType': 'unknown_type',
      'serverId': 'server-1',
      'payload': <String, Object?>{'id': 1},
    });
    const result = ServerSyncApplyResult(
      received: 1,
      applied: 0,
      skipped: 1,
      failed: 0,
      perType: <String, int>{'unknown_type': 1},
      appliedChangeIds: <String>[],
      errors: <String>[],
    );

    expect(change.action, 'upsert');
    expect(change.serverVersion, 1);
    expect(result.hasFailures, isFalse);
    expect(result.toSummary().containsKey('errors'), isFalse);
  });

  test('server sync applier test hook exposes unsupported upsert branch',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final applier = ServerSyncChangeApplier(db, SyncObjectStateStore(db));

    final localId = await applier.upsertLocalForTesting(
      const ServerSyncChange(
        changeId: 'change-unsupported',
        objectType: 'unsupported_registered_type',
        serverId: 'server-unsupported',
        action: 'upsert',
        serverVersion: 1,
        payload: <String, dynamic>{},
      ),
    );

    expect(localId, isNull);
  });

  test('blocking event candidate service uses current time default', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final service = BlockingEventActualCandidateService(
      db,
      ActualActivityLogRepository(db),
      ActivityRecordRepository(db),
    );

    final result = await service.generateForRange(
      start: DateTime.utc(2026, 6, 11),
      end: DateTime.utc(2026, 6, 12),
    );

    expect(result.created, 0);
    expect(result.skippedTotal, 0);
  });

  testWidgets('time indicator starts its timer and paints red marker',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Stack(
          children: [
            TimeIndicator(hourHeight: 48),
            TimeIndicator(
              hourHeight: 48,
              refreshIntervalForTesting: Duration(milliseconds: 1),
            ),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 2));

    expect(find.byType(TimeIndicator), findsNWidgets(2));
    expect(find.byType(Positioned), findsNWidgets(2));
  });

  test('scheduler run log and context snapshots serialize optional values', () {
    final start = DateTime.utc(2026, 6, 11, 9);
    final log = SchedulerRunLogEntry(
      level: 'warning',
      message: 'No windows',
      taskId: 7,
      taskSummary: 'Task',
      start: start,
      end: start.add(const Duration(minutes: 30)),
    );
    final context = SchedulerContextSnapshot(
      date: start,
      effectiveStart: start,
      effectiveEnd: start.add(const Duration(hours: 8)),
      fixedBlockCount: 0,
      confirmedActualCount: 0,
      taskEvidence: const <SchedulerTaskEvidence>[],
      deviationReason: 'manual',
      usesWeatherContext: false,
      usesLocationContext: false,
      usesFileContext: true,
    );

    expect(jsonEncode(log.toJson()), contains('task_id'));
    expect(context.toJson(), containsPair('uses_file_context', true));
  });
}

class _ExposedApiClient extends ApiClient {
  _ExposedApiClient({
    required super.baseUri,
    required super.tokenStore,
    required super.httpClient,
  });

  Future<http.Response> sendUnsupported() {
    return super.sendForTesting('TRACE', '/client/ping');
  }
}
