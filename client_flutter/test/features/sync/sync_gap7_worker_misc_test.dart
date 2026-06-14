import 'dart:convert';

import 'package:drift/drift.dart' hide isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/sync/outlook_diagnostics_service.dart';
import 'package:flowplanv2/features/sync/outlook_oauth_config.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
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
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('OutlookOAuthPlatformConfig exposes platform defaults', () {
    expect(OutlookOAuthPlatformConfig(), isA<OutlookOAuthPlatformConfig>());
    expect(OutlookOAuthPlatformConfig.preferTimezone, 'Asia/Shanghai');
    expect(OutlookOAuthPlatformConfig.scopeString, 'Calendars.Read');
  });

  test('diagnostics falls back to previous snapshot task list name', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final taskRepository = TaskRepository(db);
    final bindingsRepository = OutlookSyncBindingsRepository(db);
    final mirrorRepository = OutlookTaskMirrorRepository(db);
    final taskListId = await insertFixtureTaskList(db, name: 'Archived list');
    final taskId = await taskRepository.create(
      TaskItemsCompanion.insert(
        uid: 'task-gap7',
        dtstamp: fixtureNow(),
        summary: 'Fallback list task',
        taskListId: Value(taskListId),
      ),
      audit: false,
    );
    final task = await taskRepository.getById(taskId);
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task!,
      taskListName: 'Previous snapshot list',
    );

    await bindingsRepository.saveTaskListBinding(
      OutlookTaskListBinding(
        localTaskListId: taskListId,
        remoteCalendarId: 'remote-list',
        remoteCalendarName: 'Remote list',
        linkedAt: fixtureNow(),
      ),
    );
    await mirrorRepository.saveTaskMirrorBinding(
      OutlookTaskMirrorBinding(
        localTaskId: taskId,
        localTaskListId: taskListId,
        remoteCalendarId: 'remote-list',
        remoteCalendarName: 'Remote list',
        remoteEventId: 'event-gap7',
        syncedAt: fixtureNow(),
        localSnapshotHash: snapshot.fingerprint,
        localSnapshotJson: snapshot.stableJson,
      ),
    );
    await db
        .customStatement('DELETE FROM task_lists WHERE id = ?', [taskListId]);
    await (db.update(db.taskItems)..where((task) => task.id.equals(taskId)))
        .write(const TaskItemsCompanion(summary: Value('Edited task')));

    final report = await OutlookDiagnosticsService(
      calendarBooksRepository: CalendarBooksRepository(db),
      taskRepository: taskRepository,
      taskListBindingsRepository: bindingsRepository,
      taskMirrorRepository: mirrorRepository,
    ).buildMarkdownReport();
    final machineSnapshot = _extractMachineSnapshot(report);
    final mirrorDiagnostics =
        machineSnapshot['mirror_diagnostics'] as Map<String, dynamic>;

    expect(mirrorDiagnostics['active'], 1);
    expect(mirrorDiagnostics['local_changed'], 1);
    expect(
      (mirrorDiagnostics['conflict_lines'] as List<dynamic>).join('\n'),
      contains('Edited task'),
    );
  });

  test('task mirror description parser returns null for empty legacy body', () {
    final task = _task();
    final snapshot = OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
      task: task,
      taskListName: 'Inbox',
      event: const <String, Object?>{
        'body': <String, Object?>{
          'content': '一、任务概览\n\n二、任务描述\n无\n---\n三、元数据',
        },
      },
    );

    expect(snapshot.description, isNull);
    expect(snapshot.copyWith(summary: 'Renamed').summary, 'Renamed');
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

TaskItem _task() {
  return TaskItem(
    id: 1,
    uid: 'task-1',
    dtstamp: fixtureNow(),
    summary: 'Task',
    description: null,
    location: null,
    dtstart: null,
    due: null,
    completed: null,
    priority: 0,
    status: 'NEEDS-ACTION',
    percentComplete: 0,
    categories: '',
    rrule: null,
    durationMinutes: 60,
    isSplittable: false,
    isAutoScheduled: true,
    isLocked: false,
    taskListId: 1,
    reminderMinutesBefore: 15,
    priorityLocal: 2,
  );
}
