import 'dart:convert';

import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/sync_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('sync mode persists paused read-only and bidirectional values',
      () async {
    for (final mode in OutlookSyncMode.values) {
      await OutlookAuthService.saveSyncMode(mode);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('outlook_sync_mode'), mode.storageValue);
      expect(await OutlookAuthService.loadSyncMode(), mode);
    }
  });

  test('sync mode falls back to read-only for unknown persisted values',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_mode': 'surprise-mode',
    });

    expect(await OutlookAuthService.loadSyncMode(), OutlookSyncMode.readOnly);
  });

  test('last sync time reads valid timestamps and ignores missing or malformed',
      () async {
    expect(await SyncEngine.getLastSyncTime(), isNull);

    final completedAt = DateTime.utc(2026, 6, 10, 8, 30);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('outlook_last_sync', completedAt.toIso8601String());
    expect(await SyncEngine.getLastSyncTime(), completedAt);

    await prefs.setString('outlook_last_sync', 'not-a-date');
    expect(await SyncEngine.getLastSyncTime(), isNull);
  });

  test('resetSync clears all calendar delta links and schema version',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_delta_link.calendar-a': 'delta-a',
      'outlook_sync_delta_link.calendar-b': 'delta-b',
      'outlook_sync_delta_link.calendar-c': 'delta-c',
      'outlook_sync_delta_schema_version': 3,
      'outlook_sync_mode': OutlookSyncMode.bidirectional.storageValue,
      'unrelated_delta_link': 'keep',
    });

    await SyncEngine.resetSync();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('outlook_sync_delta_link.calendar-a'), isNull);
    expect(prefs.getString('outlook_sync_delta_link.calendar-b'), isNull);
    expect(prefs.getString('outlook_sync_delta_link.calendar-c'), isNull);
    expect(prefs.getInt('outlook_sync_delta_schema_version'), isNull);
    expect(prefs.getString('outlook_sync_mode'),
        OutlookSyncMode.bidirectional.storageValue);
    expect(prefs.getString('unrelated_delta_link'), 'keep');
  });

  test('recordSyncFailure writes failure reports for paused and bidirectional',
      () async {
    for (final mode in <OutlookSyncMode>[
      OutlookSyncMode.paused,
      OutlookSyncMode.bidirectional,
    ]) {
      SharedPreferences.setMockInitialValues(<String, Object>{});

      await SyncEngine.recordSyncFailure(
        mode: mode,
        error: StateError('${mode.name} failed'),
      );

      final report = await SyncEngine.getLastSyncReport();
      expect(report, isNotNull);
      expect(report!.success, isFalse);
      expect(report.mode, mode);
      expect(report.calendarBooks, 0);
      expect(report.downloaded, 0);
      expect(report.mirroredChanges, 0);
      expect(report.calendarDetails, isEmpty);
      expect(report.taskMirrorDetails, isEmpty);
      expect(report.errorMessage, contains('${mode.name} failed'));
    }
  });

  test('getLastSyncReport aggregates changes and parses success fields',
      () async {
    final attemptedAt = DateTime.utc(2026, 6, 10, 9, 15);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_last_sync_report_time': attemptedAt.toIso8601String(),
      'outlook_last_sync_report_status': 'success',
      'outlook_last_sync_report_mode': OutlookSyncMode.bidirectional.name,
      'outlook_last_sync_report_calendar_books': 2,
      'outlook_last_sync_report_downloaded': 5,
      'outlook_last_sync_report_mirrored_created': 1,
      'outlook_last_sync_report_mirrored_updated': 2,
      'outlook_last_sync_report_mirrored_deleted': 3,
      'outlook_last_sync_report_mirrored_conflicted': 4,
      'outlook_last_sync_report_calendar_details': jsonEncode(<Object?>[
        <String, Object?>{
          'remote_calendar_id': 'remote-a',
          'local_calendar_id': 11,
          'calendar_name': 'Work',
          'color_hex': '#0078D4',
          'downloaded': 2,
        },
        <String, Object?>{
          'remote_calendar_id': 'remote-b',
          'local_calendar_id': 12,
          'calendar_name': 'Home',
          'color_hex': '#D83B01',
          'downloaded': 3,
        },
      ]),
      'outlook_last_sync_report_task_mirror_details': jsonEncode(<Object?>[
        <String, Object?>{
          'local_task_list_id': 21,
          'task_list_name': 'Inbox',
          'remote_calendar_id': 'remote-task-a',
          'remote_calendar_name': 'FlowPlanV2 Inbox',
          'created': 1,
          'updated': 2,
          'deleted': 3,
          'conflicted': 4,
        },
        <String, Object?>{
          'local_task_list_id': 22,
          'task_list_name': 'Next',
          'remote_calendar_id': 'remote-task-b',
          'remote_calendar_name': 'FlowPlanV2 Next',
          'created': 5,
          'updated': 6,
          'deleted': 7,
          'conflicted': 8,
        },
      ]),
    });

    final report = await SyncEngine.getLastSyncReport();

    expect(report, isNotNull);
    expect(report!.attemptedAt, attemptedAt);
    expect(report.success, isTrue);
    expect(report.mode, OutlookSyncMode.bidirectional);
    expect(report.calendarBooks, 2);
    expect(report.downloaded, 5);
    expect(report.mirroredChanges, 10);
    expect(
        report.calendarDetails.map((detail) => detail.downloaded), <int>[2, 3]);
    expect(
      report.taskMirrorDetails.map((detail) => detail.changedCount),
      <int>[10, 26],
    );
    expect(
      report.taskMirrorDetails.fold<int>(
        0,
        (total, detail) => total + detail.changedCount,
      ),
      36,
    );
    expect(report.errorMessage, isNull);
  });

  test('getLastSyncReport parses failure status and malformed detail JSON',
      () async {
    final attemptedAt = DateTime.utc(2026, 6, 10, 9, 45);
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_last_sync_report_time': attemptedAt.toIso8601String(),
      'outlook_last_sync_report_status': 'failure',
      'outlook_last_sync_report_mode': 'unknown-mode',
      'outlook_last_sync_report_calendar_details': '{not-json',
      'outlook_last_sync_report_task_mirror_details': '{not-json',
      'outlook_last_sync_report_error': 'sync failed',
    });

    final report = await SyncEngine.getLastSyncReport();

    expect(report, isNotNull);
    expect(report!.success, isFalse);
    expect(report.mode, OutlookSyncMode.readOnly);
    expect(report.calendarDetails, isEmpty);
    expect(report.taskMirrorDetails, isEmpty);
    expect(report.errorMessage, 'sync failed');
  });
}
