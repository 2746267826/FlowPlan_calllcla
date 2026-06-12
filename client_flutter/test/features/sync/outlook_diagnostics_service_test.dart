import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_diagnostics_service.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_sync_policy.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_snapshot.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'outlook_client_id': 'client-id',
      'outlook_sync_mode': OutlookSyncMode.bidirectional.storageValue,
      'outlook_auth_token': jsonEncode({
        'access_token': 'access',
        'refresh_token': 'refresh',
        'expires_in': 3600,
        'obtained_at': fixtureNow().toIso8601String(),
        'expires_at': DateTime.utc(2099).toIso8601String(),
        'granted_mode': OutlookSyncMode.bidirectional.storageValue,
        'scope': 'Calendars.ReadWrite offline_access',
      }),
    });
  });

  test('buildMarkdownReport summarizes auth, repositories, and diagnostics',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final calendarBooksRepository = CalendarBooksRepository(db);
    final taskRepository = TaskRepository(db);
    final bindingsRepository = OutlookSyncBindingsRepository(db);
    final mirrorRepository = OutlookTaskMirrorRepository(db);

    await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'External Outlook',
            source: const Value('outlook'),
            syncUrl: const Value('calendar-external'),
            createdAt: fixtureNow(),
          ),
        );
    await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: OutlookSyncPolicy.buildManagedCalendarName(
              kind: OutlookManagedCalendarKind.taskMirrorBook,
              containerName: 'Inbox',
            ),
            source: const Value('outlook'),
            syncUrl: const Value('calendar-managed'),
            createdAt: fixtureNow(),
          ),
        );

    final activeListId = await insertFixtureTaskList(db, name: 'Inbox');
    final unboundListId = await insertFixtureTaskList(db, name: 'Backlog');
    final movedListId = await insertFixtureTaskList(db, name: 'Moved');

    await bindingsRepository.saveTaskListBinding(
      OutlookTaskListBinding(
        localTaskListId: activeListId,
        remoteCalendarId: 'remote-active',
        remoteCalendarName: 'FlowPlanV2 active',
        linkedAt: fixtureNow(),
      ),
    );
    await bindingsRepository.saveTaskListBinding(
      OutlookTaskListBinding(
        localTaskListId: movedListId,
        remoteCalendarId: 'remote-new',
        remoteCalendarName: 'FlowPlanV2 moved new',
        linkedAt: fixtureNow(),
      ),
    );

    final activeTaskId = await taskRepository.create(
      TaskItemsCompanion.insert(
        uid: 'task-active',
        dtstamp: fixtureNow(),
        summary: 'Before local edit',
        taskListId: Value(activeListId),
      ),
      audit: false,
    );
    final unboundTaskId = await taskRepository.create(
      TaskItemsCompanion.insert(
        uid: 'task-unbound',
        dtstamp: fixtureNow(),
        summary: 'Unbound mirror',
        taskListId: Value(unboundListId),
      ),
      audit: false,
    );
    final movedTaskId = await taskRepository.create(
      TaskItemsCompanion.insert(
        uid: 'task-moved',
        dtstamp: fixtureNow(),
        summary: 'Moved mirror',
        taskListId: Value(movedListId),
      ),
      audit: false,
    );

    final activeTask = await taskRepository.getById(activeTaskId);
    final activeSnapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: activeTask!,
      taskListName: 'Inbox',
    );
    await mirrorRepository.saveTaskMirrorBinding(
      _binding(
        localTaskId: activeTaskId,
        localTaskListId: activeListId,
        remoteCalendarId: 'remote-active',
        remoteCalendarName: 'FlowPlanV2 active',
        snapshot: activeSnapshot,
        conflictState: OutlookTaskMirrorConflictState.remoteChanged,
      ),
    );
    await (db.update(db.taskItems)
          ..where((task) => task.id.equals(activeTaskId)))
        .write(const TaskItemsCompanion(summary: Value('After local edit')));

    final unboundTask = await taskRepository.getById(unboundTaskId);
    final unboundSnapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: unboundTask!,
      taskListName: 'Backlog',
    );
    await mirrorRepository.saveTaskMirrorBinding(
      _binding(
        localTaskId: unboundTaskId,
        localTaskListId: unboundListId,
        remoteCalendarId: 'remote-unbound',
        remoteCalendarName: 'FlowPlanV2 unbound',
        snapshot: unboundSnapshot,
        conflictState: OutlookTaskMirrorConflictState.remoteDeleted,
      ),
    );

    final movedTask = await taskRepository.getById(movedTaskId);
    final movedSnapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: movedTask!,
      taskListName: 'Moved',
    );
    await mirrorRepository.saveTaskMirrorBinding(
      _binding(
        localTaskId: movedTaskId,
        localTaskListId: movedListId,
        remoteCalendarId: 'remote-old',
        remoteCalendarName: 'FlowPlanV2 moved old',
        snapshot: movedSnapshot,
        conflictState: OutlookTaskMirrorConflictState.divergent,
      ),
    );

    await mirrorRepository.saveTaskMirrorBinding(
      OutlookTaskMirrorBinding(
        localTaskId: 9999,
        localTaskListId: activeListId,
        remoteCalendarId: 'remote-active',
        remoteCalendarName: 'FlowPlanV2 active',
        remoteEventId: 'event-missing',
        syncedAt: fixtureNow(),
        conflictState: OutlookTaskMirrorConflictState.writeFailed,
      ),
    );

    final report = await OutlookDiagnosticsService(
      calendarBooksRepository: calendarBooksRepository,
      taskRepository: taskRepository,
      taskListBindingsRepository: bindingsRepository,
      taskMirrorRepository: mirrorRepository,
    ).buildMarkdownReport();

    expect(report, contains('FlowPlanV2 Outlook'));
    expect(report, isNot(contains('client-id')));
    final machineSnapshot = _extractMachineSnapshot(report);
    final mirrorDiagnostics =
        machineSnapshot['mirror_diagnostics'] as Map<String, dynamic>;

    expect(machineSnapshot['sync_mode'], 'bidirectional');
    expect(machineSnapshot['authorization'], '\u8bfb\u5199\u6388\u6743');
    expect(machineSnapshot['outlook_calendar_count'], 2);
    expect(machineSnapshot['managed_calendar_count'], 1);
    expect(machineSnapshot['task_list_binding_count'], 2);
    expect(machineSnapshot['mirror_binding_count'], 4);
    expect(mirrorDiagnostics['active'], 1);
    expect(mirrorDiagnostics['pending_cleanup'], 3);
    expect(mirrorDiagnostics['missing_tasks'], 1);
    expect(mirrorDiagnostics['unbound_task_lists'], 1);
    expect(mirrorDiagnostics['moved_targets'], 1);
    expect(mirrorDiagnostics['local_changed'], 1);
    expect(mirrorDiagnostics['remote_deleted'], 1);
    expect(mirrorDiagnostics['remote_changed'], 1);
    expect(mirrorDiagnostics['divergent'], 1);
    expect(mirrorDiagnostics['write_failed'], 1);
    expect(
      mirrorDiagnostics['conflict_lines'] as List<dynamic>,
      hasLength(greaterThanOrEqualTo(4)),
    );
    expect(machineSnapshot['last_sync'], isNull);
  });

  test('buildMarkdownReport handles unauthenticated empty repositories',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = createTestDatabase();
    addTearDown(db.close);

    final report = await OutlookDiagnosticsService(
      calendarBooksRepository: CalendarBooksRepository(db),
      taskRepository: TaskRepository(db),
      taskListBindingsRepository: OutlookSyncBindingsRepository(db),
      taskMirrorRepository: OutlookTaskMirrorRepository(db),
    ).buildMarkdownReport();

    final machineSnapshot = _extractMachineSnapshot(report);
    final mirrorDiagnostics =
        machineSnapshot['mirror_diagnostics'] as Map<String, dynamic>;
    expect(machineSnapshot['sync_mode'], 'read_only');
    expect(machineSnapshot['authorization'], '\u672a\u6388\u6743');
    expect(machineSnapshot['outlook_calendar_count'], 0);
    expect(machineSnapshot['managed_calendar_count'], 0);
    expect(machineSnapshot['task_list_binding_count'], 0);
    expect(machineSnapshot['mirror_binding_count'], 0);
    expect(mirrorDiagnostics['active'], 0);
    expect(mirrorDiagnostics['pending_cleanup'], 0);
    expect(mirrorDiagnostics['conflict_lines'], isEmpty);
  });
}

OutlookTaskMirrorBinding _binding({
  required int localTaskId,
  required int localTaskListId,
  required String remoteCalendarId,
  required String remoteCalendarName,
  required OutlookTaskMirrorSnapshot snapshot,
  required OutlookTaskMirrorConflictState conflictState,
}) {
  return OutlookTaskMirrorBinding(
    localTaskId: localTaskId,
    localTaskListId: localTaskListId,
    remoteCalendarId: remoteCalendarId,
    remoteCalendarName: remoteCalendarName,
    remoteEventId: 'event-$localTaskId',
    syncedAt: fixtureNow(),
    localSnapshotHash: snapshot.fingerprint,
    localSnapshotJson: snapshot.stableJson,
    remoteSnapshotHash: snapshot.fingerprint,
    remoteSnapshotJson: snapshot.stableJson,
    conflictState: conflictState,
    conflictMessage: conflictState == OutlookTaskMirrorConflictState.none
        ? null
        : 'conflict',
    conflictDetectedAt: conflictState == OutlookTaskMirrorConflictState.none
        ? null
        : fixtureNow(),
  );
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
