import 'dart:convert';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_repository.dart';
import 'package:flowplanv2/features/sync/sync_engine.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/test_database.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('summary JSON payloads preserve fields used by reports and logs',
      () async {
    const calendar = OutlookSyncedCalendarSummary(
      remoteCalendarId: ' remote-calendar ',
      localCalendarId: 42,
      calendarName: ' Work ',
      colorHex: ' #123456 ',
      downloaded: 7,
    );
    const mirror = OutlookTaskMirrorListSummary(
      localTaskListId: 3,
      taskListName: ' Inbox ',
      remoteCalendarId: ' remote-task-calendar ',
      remoteCalendarName: ' FlowPlanV2 Inbox ',
      created: 1,
      updated: 2,
      deleted: 3,
      conflicted: 4,
    );

    expect(calendar.toJson(), <String, Object?>{
      'remote_calendar_id': ' remote-calendar ',
      'local_calendar_id': 42,
      'calendar_name': ' Work ',
      'color_hex': ' #123456 ',
      'downloaded': 7,
    });
    expect(mirror.toJson(), <String, Object?>{
      'local_task_list_id': 3,
      'task_list_name': ' Inbox ',
      'remote_calendar_id': ' remote-task-calendar ',
      'remote_calendar_name': ' FlowPlanV2 Inbox ',
      'created': 1,
      'updated': 2,
      'deleted': 3,
      'conflicted': 4,
    });

    final decodedCalendar = OutlookSyncedCalendarSummary.fromJson(
      Map<String, dynamic>.from(calendar.toJson()),
    );
    final decodedMirror = OutlookTaskMirrorListSummary.fromJson(
      Map<String, dynamic>.from(mirror.toJson()),
    );

    expect(decodedCalendar.remoteCalendarId, 'remote-calendar');
    expect(decodedCalendar.calendarName, 'Work');
    expect(decodedCalendar.colorHex, '#123456');
    expect(decodedMirror.taskListName, 'Inbox');
    expect(decodedMirror.remoteCalendarId, 'remote-task-calendar');
    expect(decodedMirror.remoteCalendarName, 'FlowPlanV2 Inbox');
    expect(decodedMirror.changedCount, 10);
  });

  test('paused sync returns zeros without changing prior lifecycle state',
      () async {
    final previousSync = DateTime.utc(2026, 6, 9, 10, 30);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_mode': OutlookSyncMode.paused.storageValue,
      'outlook_last_sync': previousSync.toIso8601String(),
      'outlook_last_sync_report_time':
          DateTime.utc(2026, 6, 9, 10).toIso8601String(),
      'outlook_last_sync_report_status': 'success',
      'outlook_last_sync_report_mode': OutlookSyncMode.readOnly.name,
      'outlook_last_sync_report_calendar_books': 9,
      'outlook_last_sync_report_downloaded': 8,
    });
    final db = createTestDatabase();
    addTearDown(db.close);

    final result = await _engine(db).sync();
    final report = await SyncEngine.getLastSyncReport();

    expect(result.calendarBooks, 0);
    expect(result.downloaded, 0);
    expect(result.mirroredCreated, 0);
    expect(result.mirroredUpdated, 0);
    expect(result.mirroredDeleted, 0);
    expect(result.mirroredConflicted, 0);
    expect(await SyncEngine.getLastSyncTime(), previousSync);
    expect(report, isNotNull);
    expect(report!.calendarBooks, 9);
    expect(report.downloaded, 8);
  });

  test('read-only sync records an empty pull success and operation log',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_mode': OutlookSyncMode.readOnly.storageValue,
      'outlook_last_sync_report_error': 'old error',
    });
    final db = createTestDatabase();
    addTearDown(db.close);
    final operationLogs = DataOperationLogRepository(db);

    final result = await _engine(db, operationLogs).sync();
    final report = await SyncEngine.getLastSyncReport();
    final logs = await operationLogs.listRecent(limit: 1);

    expect(result.calendarBooks, 0);
    expect(result.downloaded, 0);
    expect(result.mirroredCreated, 0);
    expect(report, isNotNull);
    expect(report!.success, isTrue);
    expect(report.mode, OutlookSyncMode.readOnly);
    expect(report.calendarDetails, isEmpty);
    expect(report.taskMirrorDetails, isEmpty);
    expect(report.errorMessage, isNull);
    expect(await SyncEngine.getLastSyncTime(), isNotNull);
    expect(logs, hasLength(1));
    expect(logs.single.action, 'outlook_sync');
    final metadata =
        jsonDecode(logs.single.metadataJson!) as Map<String, dynamic>;
    expect(metadata['mode'], OutlookSyncMode.readOnly.name);
    expect(metadata['calendar_books'], 0);
    expect(metadata['downloaded'], 0);
    expect(metadata['calendar_details'], isEmpty);
    expect(metadata['task_mirror_details'], isEmpty);
  });

  test('bidirectional sync runs the empty task mirror queue and reports zeros',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_mode': OutlookSyncMode.bidirectional.storageValue,
    });
    final db = createTestDatabase();
    addTearDown(db.close);

    final result = await _engine(db).sync();
    final report = await SyncEngine.getLastSyncReport();

    expect(result.calendarBooks, 0);
    expect(result.downloaded, 0);
    expect(result.mirroredCreated, 0);
    expect(result.mirroredUpdated, 0);
    expect(result.mirroredDeleted, 0);
    expect(result.mirroredConflicted, 0);
    expect(report, isNotNull);
    expect(report!.success, isTrue);
    expect(report.mode, OutlookSyncMode.bidirectional);
    expect(report.taskMirrorDetails, isEmpty);
  });

  test('sync rethrows late failures and replaces success with failure report',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_mode': OutlookSyncMode.bidirectional.storageValue,
    });
    final db = createTestDatabase();
    addTearDown(db.close);
    final operationLogs = _ThrowingOperationLogRepository(db);

    await expectLater(
      _engine(db, operationLogs).sync(),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'operation log unavailable',
        ),
      ),
    );

    final report = await SyncEngine.getLastSyncReport();
    expect(report, isNotNull);
    expect(report!.success, isFalse);
    expect(report.mode, OutlookSyncMode.bidirectional);
    expect(report.calendarBooks, 0);
    expect(report.downloaded, 0);
    expect(report.mirroredCreated, 0);
    expect(report.mirroredUpdated, 0);
    expect(report.mirroredDeleted, 0);
    expect(report.mirroredConflicted, 0);
    expect(report.errorMessage, contains('operation log unavailable'));
    expect(await SyncEngine.getLastSyncTime(), isNotNull);
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

class _ThrowingOperationLogRepository extends DataOperationLogRepository {
  _ThrowingOperationLogRepository(super.db);

  @override
  Future<void> record({
    required String actor,
    required String action,
    required String entityType,
    String? entityId,
    required String summary,
    Object? before,
    Object? after,
    Object? metadata,
  }) async {
    throw StateError('operation log unavailable');
  }
}
