import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_sync_policy.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_repository.dart';
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

  test('report detail decoders keep zero-count rows and trim labels', () async {
    final attemptedAt = DateTime.utc(2026, 6, 10, 10, 15);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_last_sync_report_time': attemptedAt.toIso8601String(),
      'outlook_last_sync_report_status': 'success',
      'outlook_last_sync_report_mode': OutlookSyncMode.bidirectional.name,
      'outlook_last_sync_report_calendar_books': 1,
      'outlook_last_sync_report_downloaded': 0,
      'outlook_last_sync_report_mirrored_created': 0,
      'outlook_last_sync_report_mirrored_updated': 0,
      'outlook_last_sync_report_mirrored_deleted': 0,
      'outlook_last_sync_report_mirrored_conflicted': 1,
      'outlook_last_sync_report_calendar_details': jsonEncode(<Object?>[
        <String, Object?>{
          'remote_calendar_id': ' remote-calendar ',
          'local_calendar_id': 5,
          'calendar_name': ' Work ',
          'color_hex': ' 0078D4 ',
          'downloaded': 0,
        },
      ]),
      'outlook_last_sync_report_task_mirror_details': jsonEncode(<Object?>[
        <String, Object?>{
          'local_task_list_id': 6,
          'task_list_name': ' Inbox ',
          'remote_calendar_id': '',
          'remote_calendar_name': ' FlowPlanV2 Inbox ',
          'created': 0,
          'updated': 0,
          'deleted': 0,
          'conflicted': 1,
        },
      ]),
    });

    final report = await SyncEngine.getLastSyncReport();

    expect(report, isNotNull);
    expect(report!.attemptedAt, attemptedAt);
    expect(report.mirroredChanges, 1);
    expect(report.calendarDetails, hasLength(1));
    expect(report.calendarDetails.single.remoteCalendarId, 'remote-calendar');
    expect(report.calendarDetails.single.calendarName, 'Work');
    expect(report.calendarDetails.single.colorHex, '0078D4');
    expect(report.calendarDetails.single.downloaded, 0);
    expect(report.taskMirrorDetails, hasLength(1));
    expect(report.taskMirrorDetails.single.taskListName, 'Inbox');
    expect(report.taskMirrorDetails.single.remoteCalendarId, isEmpty);
    expect(
      report.taskMirrorDetails.single.remoteCalendarName,
      'FlowPlanV2 Inbox',
    );
    expect(report.taskMirrorDetails.single.changedCount, 1);
  });

  test('read-only sync ignores bound task mirrors and preserves bindings',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_mode': OutlookSyncMode.readOnly.storageValue,
    });
    final db = createTestDatabase();
    addTearDown(db.close);
    final taskListId = await insertFixtureTaskList(db, name: 'Inbox');
    final taskId = await _createTask(db, taskListId, 'Write read-only test');
    await _bindTaskList(db, taskListId, 'Inbox');
    final mirrorRepository = OutlookTaskMirrorRepository(db);
    await mirrorRepository.saveTaskMirrorBinding(
      OutlookTaskMirrorBinding(
        localTaskId: taskId,
        localTaskListId: taskListId,
        remoteCalendarId: 'remote-$taskListId',
        remoteCalendarName: _remoteCalendarName('Inbox'),
        remoteEventId: 'remote-event-$taskId',
        syncedAt: fixtureNow(),
        conflictState: OutlookTaskMirrorConflictState.pendingLocalPush,
        conflictMessage: 'waiting for write mode',
        conflictDetectedAt: fixtureNow(),
      ),
    );

    final result = await _engine(db).sync();
    final report = await SyncEngine.getLastSyncReport();
    final saved = await mirrorRepository.getTaskMirrorBinding(taskId);

    expect(result.mirroredCreated, 0);
    expect(result.mirroredUpdated, 0);
    expect(result.mirroredDeleted, 0);
    expect(result.mirroredConflicted, 0);
    expect(report, isNotNull);
    expect(report!.success, isTrue);
    expect(report.mode, OutlookSyncMode.readOnly);
    expect(report.taskMirrorDetails, isEmpty);
    expect(saved, isNotNull);
    expect(
        saved!.conflictState, OutlookTaskMirrorConflictState.pendingLocalPush);
    expect(saved.conflictMessage, 'waiting for write mode');
  });

  test(
      'bidirectional sync reports task mirror write failures from client Graph stub',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_mode': OutlookSyncMode.bidirectional.storageValue,
    });
    final db = createTestDatabase();
    addTearDown(db.close);
    final operationLogs = DataOperationLogRepository(db);
    final taskListId = await insertFixtureTaskList(db, name: 'Inbox');
    final taskId = await _createTask(db, taskListId, 'Mirror me');
    await _bindTaskList(db, taskListId, 'Inbox');
    final mirrorRepository = OutlookTaskMirrorRepository(db);

    await expectLater(
      _engine(db, operationLogs).sync(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('server-managed and read-only'),
        ),
      ),
    );
    final report = await SyncEngine.getLastSyncReport();
    final saved = await mirrorRepository.getTaskMirrorBinding(taskId);
    final logs = await operationLogs.listRecent(limit: 1);

    expect(report, isNotNull);
    expect(report!.success, isFalse);
    expect(report.mode, OutlookSyncMode.bidirectional);
    expect(report.calendarBooks, 0);
    expect(report.downloaded, 0);
    expect(report.mirroredCreated, 0);
    expect(report.mirroredUpdated, 0);
    expect(report.mirroredDeleted, 0);
    expect(report.mirroredConflicted, 0);
    expect(report.calendarDetails, isEmpty);
    expect(report.taskMirrorDetails, isEmpty);
    expect(report.errorMessage, contains('server-managed and read-only'));
    expect(saved, isNull);
    expect(logs, isEmpty);
  });

  test(
      'recordSyncFailure replaces stale detail rows with empty failure details',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_last_sync_report_time':
          DateTime.utc(2026, 6, 9).toIso8601String(),
      'outlook_last_sync_report_status': 'success',
      'outlook_last_sync_report_mode': OutlookSyncMode.bidirectional.name,
      'outlook_last_sync_report_calendar_books': 2,
      'outlook_last_sync_report_downloaded': 4,
      'outlook_last_sync_report_mirrored_created': 1,
      'outlook_last_sync_report_calendar_details': jsonEncode(<Object?>[
        <String, Object?>{
          'remote_calendar_id': 'old-calendar',
          'local_calendar_id': 1,
          'calendar_name': 'Old',
        },
      ]),
      'outlook_last_sync_report_task_mirror_details': jsonEncode(<Object?>[
        <String, Object?>{
          'local_task_list_id': 1,
          'task_list_name': 'Old inbox',
          'remote_calendar_name': 'FlowPlanV2 Old',
          'conflicted': 9,
        },
      ]),
    });

    await SyncEngine.recordSyncFailure(
      mode: OutlookSyncMode.bidirectional,
      error: StateError('manual report failure'),
    );

    final report = await SyncEngine.getLastSyncReport();

    expect(report, isNotNull);
    expect(report!.success, isFalse);
    expect(report.mode, OutlookSyncMode.bidirectional);
    expect(report.calendarBooks, 0);
    expect(report.downloaded, 0);
    expect(report.mirroredChanges, 0);
    expect(report.calendarDetails, isEmpty);
    expect(report.taskMirrorDetails, isEmpty);
    expect(report.errorMessage, contains('manual report failure'));
  });
}

SyncEngine _engine(
  AppDatabase db, [
  DataOperationLogRepository? operationLogs,
]) {
  return SyncEngine(
    EventRepository(db),
    CalendarBooksRepository(db),
    TaskRepository(db),
    OutlookSyncBindingsRepository(db),
    OutlookTaskMirrorRepository(db),
    const OutlookConfig(clientId: 'client-id'),
    operationLogs,
  );
}

Future<int> _createTask(AppDatabase db, int taskListId, String summary) {
  return TaskRepository(db).create(
    TaskItemsCompanion.insert(
      uid: 'task-$taskListId-$summary',
      dtstamp: fixtureNow(),
      summary: summary,
      taskListId: Value(taskListId),
      description: const Value('Local notes'),
      dtstart: Value(fixtureNow()),
      due: Value(fixtureNow().add(const Duration(hours: 1))),
    ),
    audit: false,
  );
}

Future<void> _bindTaskList(
  AppDatabase db,
  int taskListId,
  String taskListName,
) {
  return OutlookSyncBindingsRepository(db).saveTaskListBinding(
    OutlookTaskListBinding(
      localTaskListId: taskListId,
      remoteCalendarId: 'remote-$taskListId',
      remoteCalendarName: _remoteCalendarName(taskListName),
      linkedAt: fixtureNow(),
    ),
  );
}

String _remoteCalendarName(String taskListName) {
  return OutlookSyncPolicy.buildManagedCalendarName(
    kind: OutlookManagedCalendarKind.taskMirrorBook,
    containerName: taskListName,
  );
}
