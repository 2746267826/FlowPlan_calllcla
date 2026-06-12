import 'dart:convert';

import 'package:flowplanv2/core/database/app_database.dart';
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

  test('sync is a no-op loop when Outlook sync is paused', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_mode': OutlookSyncMode.paused.storageValue,
      'outlook_last_sync': DateTime.utc(2026, 6, 7).toIso8601String(),
    });
    final db = createTestDatabase();
    addTearDown(db.close);

    final result = await _engine(db).sync();

    expect(result.calendarBooks, 0);
    expect(result.downloaded, 0);
    expect(result.mirroredCreated, 0);
    expect(result.mirroredUpdated, 0);
    expect(result.mirroredDeleted, 0);
    expect(result.mirroredConflicted, 0);
    expect(await SyncEngine.getLastSyncTime(), DateTime.utc(2026, 6, 7));
    expect(await SyncEngine.getLastSyncReport(), isNull);
  });

  test('sync records a successful empty pull report in read-only mode',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_mode': OutlookSyncMode.readOnly.storageValue,
    });
    final db = createTestDatabase();
    addTearDown(db.close);

    final result = await _engine(db).sync();
    final lastSync = await SyncEngine.getLastSyncTime();
    final report = await SyncEngine.getLastSyncReport();

    expect(result.calendarBooks, 0);
    expect(result.downloaded, 0);
    expect(lastSync, isNotNull);
    expect(report, isNotNull);
    expect(report!.success, isTrue);
    expect(report.mode, OutlookSyncMode.readOnly);
    expect(report.calendarBooks, 0);
    expect(report.downloaded, 0);
    expect(report.calendarDetails, isEmpty);
    expect(report.taskMirrorDetails, isEmpty);
    expect(report.errorMessage, isNull);
  });

  test('sync skips task mirror loop when Graph write mode is not enabled',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_mode': OutlookSyncMode.readOnly.storageValue,
    });
    final db = createTestDatabase();
    addTearDown(db.close);
    await db.setSetting(
      OutlookSyncBindingsRepository.taskListBindingsSettingKey,
      jsonEncode(<Map<String, Object?>>[
        <String, Object?>{
          'local_task_list_id': 1,
          'remote_calendar_id': 'remote-task-list',
          'remote_calendar_name': 'FlowPlanV2 Inbox',
          'linked_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
        },
      ]),
    );

    final result = await _engine(db).sync();
    final report = await SyncEngine.getLastSyncReport();

    expect(result.mirroredCreated, 0);
    expect(result.mirroredUpdated, 0);
    expect(result.mirroredDeleted, 0);
    expect(result.mirroredConflicted, 0);
    expect(report!.taskMirrorDetails, isEmpty);
  });

  test('recordSyncFailure persists calendar pull failure report', () async {
    await SyncEngine.recordSyncFailure(
      mode: OutlookSyncMode.readOnly,
      error: StateError('calendar pull failed'),
    );

    final report = await SyncEngine.getLastSyncReport();

    expect(report, isNotNull);
    expect(report!.success, isFalse);
    expect(report.mode, OutlookSyncMode.readOnly);
    expect(report.calendarBooks, 0);
    expect(report.downloaded, 0);
    expect(report.errorMessage, contains('calendar pull failed'));
  });

  test('getLastSyncReport drops malformed timestamps and bad detail JSON',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_last_sync_report_time': 'not-a-date',
      'outlook_last_sync_report_status': 'success',
      'outlook_last_sync_report_calendar_details': '{not-json',
      'outlook_last_sync_report_task_mirror_details': '{not-json',
    });

    expect(await SyncEngine.getLastSyncReport(), isNull);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_last_sync_report_time':
          DateTime.utc(2026, 6, 8, 9).toIso8601String(),
      'outlook_last_sync_report_status': 'success',
      'outlook_last_sync_report_mode': 'unknown-mode',
      'outlook_last_sync_report_calendar_details': '{not-json',
      'outlook_last_sync_report_task_mirror_details': '{not-json',
    });

    final report = await SyncEngine.getLastSyncReport();

    expect(report, isNotNull);
    expect(report!.mode, OutlookSyncMode.readOnly);
    expect(report.calendarDetails, isEmpty);
    expect(report.taskMirrorDetails, isEmpty);
  });

  test('getLastSyncReport filters incomplete persisted detail rows', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_last_sync_report_time':
          DateTime.utc(2026, 6, 8, 9).toIso8601String(),
      'outlook_last_sync_report_status': 'success',
      'outlook_last_sync_report_mode': OutlookSyncMode.bidirectional.name,
      'outlook_last_sync_report_calendar_details': jsonEncode(<Object?>[
        <String, Object?>{
          'remote_calendar_id': 'remote-1',
          'local_calendar_id': 7,
          'calendar_name': 'Work',
          'color_hex': '#0078D4',
          'downloaded': 3,
        },
        <String, Object?>{
          'remote_calendar_id': '',
          'local_calendar_id': 8,
          'calendar_name': 'Missing remote',
        },
      ]),
      'outlook_last_sync_report_task_mirror_details': jsonEncode(<Object?>[
        <String, Object?>{
          'local_task_list_id': 2,
          'task_list_name': 'Inbox',
          'remote_calendar_id': 'remote-task',
          'remote_calendar_name': 'FlowPlanV2 Inbox',
          'created': 1,
          'updated': 2,
          'deleted': 3,
          'conflicted': 4,
        },
        <String, Object?>{
          'local_task_list_id': 0,
          'task_list_name': 'Broken',
          'remote_calendar_name': 'FlowPlanV2 Broken',
        },
      ]),
    });

    final report = await SyncEngine.getLastSyncReport();

    expect(report, isNotNull);
    expect(report!.calendarDetails, hasLength(1));
    expect(report.calendarDetails.single.remoteCalendarId, 'remote-1');
    expect(report.taskMirrorDetails, hasLength(1));
    expect(report.taskMirrorDetails.single.changedCount, 10);
  });

  test('resetSync clears delta state, last sync, and report keys only',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_delta_link.remote-a': 'delta-a',
      'outlook_sync_delta_link.remote-b': 'delta-b',
      'outlook_sync_delta_schema_version': 3,
      'outlook_last_sync': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
      'outlook_last_sync_report_time':
          DateTime.utc(2026, 6, 8, 9).toIso8601String(),
      'outlook_last_sync_report_status': 'failure',
      'outlook_last_sync_report_mode': OutlookSyncMode.readOnly.name,
      'outlook_last_sync_report_calendar_books': 2,
      'outlook_last_sync_report_downloaded': 3,
      'outlook_last_sync_report_mirrored_created': 4,
      'outlook_last_sync_report_mirrored_updated': 5,
      'outlook_last_sync_report_mirrored_deleted': 6,
      'outlook_last_sync_report_mirrored_conflicted': 7,
      'outlook_last_sync_report_calendar_details': '[]',
      'outlook_last_sync_report_task_mirror_details': '[]',
      'outlook_last_sync_report_error': 'failed',
      'outlook_auth_token': 'keep-token',
      'unrelated': 'keep',
    });

    await SyncEngine.resetSync();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('outlook_sync_delta_link.remote-a'), isNull);
    expect(prefs.getString('outlook_sync_delta_link.remote-b'), isNull);
    expect(prefs.getInt('outlook_sync_delta_schema_version'), isNull);
    expect(await SyncEngine.getLastSyncTime(), isNull);
    expect(await SyncEngine.getLastSyncReport(), isNull);
    expect(prefs.getString('outlook_auth_token'), 'keep-token');
    expect(prefs.getString('unrelated'), 'keep');
  });
}

SyncEngine _engine(AppDatabase db) {
  return SyncEngine(
    EventRepository(db),
    CalendarBooksRepository(db),
    TaskRepository(db),
    OutlookSyncBindingsRepository(db),
    OutlookTaskMirrorRepository(db),
    const OutlookConfig(clientId: 'client-id'),
  );
}
