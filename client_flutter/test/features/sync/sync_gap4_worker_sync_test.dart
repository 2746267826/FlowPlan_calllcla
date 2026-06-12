import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_diagnostics_service.dart';
import 'package:flowplanv2/features/sync/outlook_oauth_config.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_snapshot.dart';
import 'package:flowplanv2/features/sync/sync_engine.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('auth config and JSON models tolerate legacy sparse payloads', () async {
    const config = OutlookConfig(clientId: 'gap4-client');
    expect(config.authority, OutlookOAuthPlatformConfig.authority);
    expect(config.authorizeUrl, OutlookOAuthPlatformConfig.authorizeEndpoint);
    expect(config.tokenUrl, OutlookOAuthPlatformConfig.tokenEndpoint);
    expect(config.redirectUri, OutlookOAuthPlatformConfig.redirectUri);
    expect(config.scopes, OutlookOAuthPlatformConfig.scopes);
    expect(config.scopeString, OutlookOAuthPlatformConfig.scopeString);

    final token = AuthToken.fromJson(<String, dynamic>{
      'access_token': 'gap4-access',
      'expires_in': '45',
      'granted_mode': 'import_only',
      'scope': '   ',
    });
    expect(token.accessToken, 'gap4-access');
    expect(token.expiresInSeconds, 45);
    expect(token.obtainedAt.isBefore(token.expiresAt), isTrue);
    expect(token.grantedMode, OutlookSyncMode.readOnly);
    expect(token.scope, OutlookOAuthPlatformConfig.scopeString);
    expect(token.supportsMode(OutlookSyncMode.readOnly), isTrue);
    expect(token.supportsMode(OutlookSyncMode.bidirectional), isFalse);

    final pending = OutlookPendingAuthSession.fromJson(<String, dynamic>{
      'client_id': ' gap4-client ',
      'code_verifier': ' verifier ',
      'state': ' state ',
      'requested_mode': 'disabled',
      'created_at': 'not-a-date',
    });
    expect(pending.clientId, 'gap4-client');
    expect(pending.codeVerifier, 'verifier');
    expect(pending.state, 'state');
    expect(pending.requestedMode, OutlookSyncMode.paused);
    expect(pending.createdAt, isA<DateTime>());

    const exception = OutlookAuthException(
      code: 'gap4',
      userMessage: 'friendly message',
      debugMessage: 'debug',
      statusCode: 418,
    );
    expect(exception.toString(), 'friendly message');

    final responseToken = AuthToken.fromTokenResponse(
      <String, dynamic>{
        'access_token': 'new-access',
        'expires_in': 60.8,
      },
      previousToken: token,
    );
    expect(responseToken.refreshToken, token.refreshToken);
    expect(responseToken.expiresInSeconds, 60);
    expect(responseToken.grantedMode, OutlookSyncMode.readOnly);
  });

  test('mirror binding copyWith preserves old fields and replaces overrides',
      () {
    final syncedAt = fixtureNow();
    final binding = OutlookTaskMirrorBinding(
      localTaskId: 1,
      localTaskListId: 2,
      remoteCalendarId: 'remote-old',
      remoteCalendarName: 'Remote Old',
      remoteEventId: 'event-old',
      syncedAt: syncedAt,
      localSnapshotHash: 'local-old',
      localSnapshotJson: '{"old":true}',
      remoteSnapshotHash: 'remote-old',
      remoteSnapshotJson: '{"remote":true}',
      remoteLastModifiedAt: syncedAt,
      conflictState: OutlookTaskMirrorConflictState.remoteChanged,
      conflictMessage: 'review',
      conflictDetectedAt: syncedAt,
    );

    final copied = binding.copyWith(
      remoteCalendarId: 'remote-new',
      remoteCalendarName: 'Remote New',
      remoteEventId: 'event-new',
      syncedAt: syncedAt.add(const Duration(minutes: 1)),
      localSnapshotHash: 'local-new',
      remoteSnapshotHash: 'remote-new',
      conflictState: OutlookTaskMirrorConflictState.none,
    );

    expect(copied.localTaskId, 1);
    expect(copied.localTaskListId, 2);
    expect(copied.remoteCalendarId, 'remote-new');
    expect(copied.remoteCalendarName, 'Remote New');
    expect(copied.remoteEventId, 'event-new');
    expect(copied.syncedAt, syncedAt.add(const Duration(minutes: 1)));
    expect(copied.localSnapshotHash, 'local-new');
    expect(copied.localSnapshotJson, '{"old":true}');
    expect(copied.remoteSnapshotHash, 'remote-new');
    expect(copied.remoteSnapshotJson, '{"remote":true}');
    expect(copied.remoteLastModifiedAt, syncedAt);
    expect(copied.conflictState, OutlookTaskMirrorConflictState.none);
    expect(copied.conflictMessage, 'review');
    expect(copied.conflictDetectedAt, syncedAt);
  });

  test('remote mirror snapshots fall back when metadata and dates are partial',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final taskListId = await insertFixtureTaskList(db, name: 'Inbox');
    final taskRepository = TaskRepository(db);
    final taskId = await taskRepository.create(
      TaskItemsCompanion.insert(
        uid: 'gap4-task',
        dtstamp: fixtureNow(),
        summary: 'Local title',
        taskListId: Value(taskListId),
        description: const Value('Local notes'),
        durationMinutes: const Value(0),
      ),
      audit: false,
    );
    final task = await taskRepository.getById(taskId);

    final remote = OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
      task: task!,
      taskListName: 'Inbox',
      event: <String, dynamic>{
        'subject': '   ',
        'body': <String, dynamic>{
          'content': '二、任务描述\nDescription without terminator',
        },
        'location': <String, dynamic>{'displayName': ''},
        'start': <String, dynamic>{'dateTime': 'not-a-date'},
        'end': <String, dynamic>{'dateTime': 'also-not-a-date'},
        'showAs': 'tentative',
      },
    );

    expect(remote.taskId, taskId);
    expect(remote.taskUid, 'gap4-task');
    expect(remote.taskListId, taskListId);
    expect(remote.taskListName, 'Inbox');
    expect(remote.summary, 'Local title');
    expect(remote.description, 'Description without terminator');
    expect(remote.location, isNull);
    expect(remote.status, 'IN-PROCESS');
    expect(remote.dtstart, isNull);
    expect(remote.due, isNull);
    expect(remote.durationMinutes, 60);

    final free = OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
      task: task,
      taskListName: 'Inbox',
      event: <String, dynamic>{'showAs': 'oof'},
    );
    expect(free.status, 'NEEDS-ACTION');
  });

  test('diagnostics report includes failures, orphan tasks, and bad snapshots',
      () async {
    final attemptedAt = DateTime.utc(2026, 6, 10, 8);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_mode': OutlookSyncMode.bidirectional.storageValue,
      'outlook_last_sync_report_time': attemptedAt.toIso8601String(),
      'outlook_last_sync_report_status': 'failure',
      'outlook_last_sync_report_mode': OutlookSyncMode.bidirectional.name,
      'outlook_last_sync_report_calendar_books': 1,
      'outlook_last_sync_report_downloaded': 2,
      'outlook_last_sync_report_mirrored_created': 0,
      'outlook_last_sync_report_mirrored_updated': 0,
      'outlook_last_sync_report_mirrored_deleted': 0,
      'outlook_last_sync_report_mirrored_conflicted': 1,
      'outlook_last_sync_report_error': 'Graph gap4 throttled',
    });

    final db = createTestDatabase();
    addTearDown(db.close);
    final taskRepository = TaskRepository(db);
    final bindingsRepository = OutlookSyncBindingsRepository(db);
    final mirrorRepository = OutlookTaskMirrorRepository(db);
    final boundListId = await insertFixtureTaskList(db, name: 'Bound');
    await bindingsRepository.saveTaskListBinding(
      OutlookTaskListBinding(
        localTaskListId: boundListId,
        remoteCalendarId: 'remote-bound',
        remoteCalendarName: 'FlowPlanV2 Bound',
        linkedAt: fixtureNow(),
      ),
    );

    final detachedTaskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'gap4-detached',
            dtstamp: fixtureNow(),
            summary: 'Detached task',
          ),
        );
    await mirrorRepository.saveTaskMirrorBinding(
      OutlookTaskMirrorBinding(
        localTaskId: detachedTaskId,
        localTaskListId: boundListId,
        remoteCalendarId: 'remote-bound',
        remoteCalendarName: 'FlowPlanV2 Bound',
        remoteEventId: 'event-detached',
        syncedAt: fixtureNow(),
        localSnapshotHash: 'old',
        localSnapshotJson: '{bad',
      ),
    );

    final fallbackTaskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'gap4-fallback',
            dtstamp: fixtureNow(),
            summary: 'Fallback task',
            taskListId: const Value(9999),
          ),
        );
    await mirrorRepository.saveTaskMirrorBinding(
      OutlookTaskMirrorBinding(
        localTaskId: fallbackTaskId,
        localTaskListId: 9999,
        remoteCalendarId: 'remote-fallback',
        remoteCalendarName: 'FlowPlanV2 Fallback',
        remoteEventId: 'event-fallback',
        syncedAt: fixtureNow(),
        localSnapshotHash: 'old',
        localSnapshotJson: jsonEncode(<String, Object?>{
          'task_list_name': ' Snapshot Name ',
        }),
      ),
    );

    final report = await OutlookDiagnosticsService(
      calendarBooksRepository: CalendarBooksRepository(db),
      taskRepository: taskRepository,
      taskListBindingsRepository: bindingsRepository,
      taskMirrorRepository: mirrorRepository,
    ).buildMarkdownReport();
    final snapshot = _extractMachineSnapshot(report);
    final diagnostics = snapshot['mirror_diagnostics'] as Map<String, dynamic>;

    expect(report, contains('Graph gap4 throttled'));
    expect(diagnostics['missing_tasks'], 1);
    expect(diagnostics['unbound_task_lists'], 1);
    expect(diagnostics['pending_cleanup'], 2);
    expect(diagnostics['conflict_lines'], isNotEmpty);
    expect(snapshot['last_sync'], isNotNull);
  });

  test('recorded sync failures can be loaded as failed reports', () async {
    await SyncEngine.recordSyncFailure(
      mode: OutlookSyncMode.bidirectional,
      error: StateError('gap4 sync exploded'),
    );

    final report = await SyncEngine.getLastSyncReport();

    expect(report, isNotNull);
    expect(report!.success, isFalse);
    expect(report.mode, OutlookSyncMode.bidirectional);
    expect(report.errorMessage, contains('gap4 sync exploded'));
    expect(report.calendarDetails, isEmpty);
    expect(report.taskMirrorDetails, isEmpty);
  });
}

Map<String, dynamic> _extractMachineSnapshot(String report) {
  final fenceStart = report.indexOf('```json');
  expect(fenceStart, isNonNegative);
  final jsonStart = fenceStart + '```json'.length;
  final fenceEnd = report.indexOf('```', jsonStart);
  expect(fenceEnd, isNonNegative);
  return jsonDecode(report.substring(jsonStart, fenceEnd).trim())
      as Map<String, dynamic>;
}
