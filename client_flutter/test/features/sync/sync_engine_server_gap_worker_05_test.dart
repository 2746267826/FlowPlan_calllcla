import 'dart:convert';

import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_status.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/sync_engine.dart';
import 'package:flowplanv2/features/sync/sync_status_badge.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/test_database.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('last sync report ignores invalid JSON and unknown modes safely',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_last_sync_report_time':
          DateTime.utc(2026, 6, 10, 1, 2).toIso8601String(),
      'outlook_last_sync_report_status': 'failure',
      'outlook_last_sync_report_mode': 'future-mode',
      'outlook_last_sync_report_calendar_books': 3,
      'outlook_last_sync_report_downloaded': 4,
      'outlook_last_sync_report_mirrored_created': 5,
      'outlook_last_sync_report_mirrored_updated': 6,
      'outlook_last_sync_report_mirrored_deleted': 7,
      'outlook_last_sync_report_mirrored_conflicted': 8,
      'outlook_last_sync_report_calendar_details': '{not-json',
      'outlook_last_sync_report_task_mirror_details': jsonEncode(<Object?>[
        <String, Object?>{
          'local_task_list_id': 0,
          'task_list_name': 'Missing id',
          'remote_calendar_name': 'FlowPlanV2 Inbox',
        },
        <String, Object?>{
          'local_task_list_id': 9,
          'task_list_name': '',
          'remote_calendar_name': 'FlowPlanV2 Inbox',
        },
      ]),
      'outlook_last_sync_report_error': 'server unavailable',
    });

    final report = await SyncEngine.getLastSyncReport();

    expect(report, isNotNull);
    expect(report!.success, isFalse);
    expect(report.mode, OutlookSyncMode.readOnly);
    expect(report.calendarBooks, 3);
    expect(report.downloaded, 4);
    expect(report.mirroredChanges, 26);
    expect(report.calendarDetails, isEmpty);
    expect(report.taskMirrorDetails, isEmpty);
    expect(report.errorMessage, 'server unavailable');
  });

  test('resetSync clears delta keys and report keys only', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'outlook_sync_delta_link.calendar-1': 'delta-1',
      'outlook_sync_delta_schema_version': 3,
      'outlook_last_sync': DateTime.utc(2026, 6, 10).toIso8601String(),
      'outlook_last_sync_report_time':
          DateTime.utc(2026, 6, 10, 1).toIso8601String(),
      'outlook_last_sync_report_status': 'success',
      'unrelated_key': 'keep-me',
    });

    await SyncEngine.resetSync();
    final prefs = await SharedPreferences.getInstance();

    expect(prefs.getString('outlook_sync_delta_link.calendar-1'), isNull);
    expect(prefs.getInt('outlook_sync_delta_schema_version'), isNull);
    expect(prefs.getString('outlook_last_sync'), isNull);
    expect(await SyncEngine.getLastSyncReport(), isNull);
    expect(prefs.getString('unrelated_key'), 'keep-me');
  });

  test('syncObjectStateByKeyProvider rejects malformed lookup keys', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final missingSeparator =
        await container.read(syncObjectStateByKeyProvider('task_item').future);
    final missingLocal =
        await container.read(syncObjectStateByKeyProvider('task_item|').future);

    expect(missingSeparator, isNull);
    expect(missingLocal, isNull);
  });

  testWidgets('sync status badge renders local, synced, pending, failed, conflict',
      (tester) async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    await stateStore.markSynced(
      objectType: 'task_item',
      localId: 'synced',
      serverId: 'server-synced',
      serverVersion: 2,
    );
    await stateStore.markPending(
      objectType: 'task_item',
      localId: 'pending',
      state: SyncState.pendingUpdate,
    );
    await stateStore.markPending(
      objectType: 'task_item',
      localId: 'failed',
      state: SyncState.pendingUpdate,
    );
    await stateStore.markFailed(
      objectType: 'task_item',
      localId: 'failed',
      error: StateError('push rejected'),
    );
    await stateStore.markConflict(
      objectType: 'task_item',
      localId: 'conflict',
      serverId: 'server-conflict',
      serverVersion: 4,
      error: 'manual merge required',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncObjectStateStoreProvider.overrideWithValue(stateStore),
        ],
        child: const MaterialApp(
          home: Material(
            child: Column(
              children: [
                SyncStatusBadge(objectType: 'task_item', localId: 'local'),
                SyncStatusBadge(objectType: 'task_item', localId: 'synced'),
                SyncStatusBadge(objectType: 'task_item', localId: 'pending'),
                SyncStatusBadge(objectType: 'task_item', localId: 'failed'),
                SyncStatusBadge(objectType: 'task_item', localId: 'conflict'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byType(SizedBox), findsWidgets);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    expect(find.byIcon(Icons.cloud_done_outlined), findsOneWidget);
    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    expect(find.byIcon(Icons.sync_problem_outlined), findsOneWidget);
    expect(find.byIcon(Icons.report_problem_outlined), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.contains('push rejected') ?? false),
      ),
      findsOneWidget,
    );
  });

  testWidgets('sync status badge renders provider errors', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          syncObjectStateByKeyProvider('task_item|boom').overrideWith(
            (ref) => Future<SyncObjectState?>.error(StateError('db closed')),
          ),
        ],
        child: const MaterialApp(
          home: Material(
            child: SyncStatusBadge(objectType: 'task_item', localId: 'boom'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Tooltip &&
            (widget.message?.contains('db closed') ?? false),
      ),
      findsOneWidget,
    );
  });
}
