import 'package:drift/drift.dart' hide isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

typedef _Evidence = ({
  DataOperationLogRepository auditRepository,
  OfflineMutationStore mutationStore,
  SyncWriteRecorder recorder,
});

void main() {
  test('creates writable defaults and persists per-container defaults',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await _clearCalendarData(db);
    final evidence = _createEvidence(db);
    final repository = CalendarBooksRepository(
      db,
      evidence.auditRepository,
      evidence.recorder,
    );

    final calendarId = await repository.getOrCreateWritableEventCalendarId();
    await repository.saveEventCalendarDefaults(
      id: calendarId,
      defaultIsBlock: true,
    );
    await repository.toggleEventCalendarVisible(calendarId, false);

    final taskListId = await repository.getOrCreateActiveTaskListId();
    final fallbackDefaults = await repository.getTaskListDefaults(
      taskListId,
      fallbackReminderMinutes: 42,
    );
    await repository.saveTaskListDefaults(
      id: taskListId,
      defaultIsAutoScheduled: false,
      defaultReminderMinutesBefore: 7,
    );
    await repository.toggleTaskListVisible(taskListId, false);

    final calendar = await repository.getEventCalendarById(calendarId);
    final calendarDefaults =
        await repository.getEventCalendarDefaults(calendarId);
    final taskList = await repository.getTaskListById(taskListId);
    final savedTaskDefaults = await repository.getTaskListDefaults(
      taskListId,
      fallbackReminderMinutes: 42,
    );
    final auditRows = await evidence.auditRepository.listRecent(limit: 20);
    final pendingMutations = await evidence.mutationStore.listPending();

    expect(calendar?.name, '默认日历');
    expect(calendar?.isDefault, isTrue);
    expect(calendar?.isVisible, isFalse);
    expect(calendarDefaults.defaultIsBlock, isTrue);
    expect(taskList?.name, '收件箱');
    expect(taskList?.emoji, '收');
    expect(taskList?.isDefault, isTrue);
    expect(taskList?.isVisible, isFalse);
    expect(fallbackDefaults.defaultIsAutoScheduled, isTrue);
    expect(fallbackDefaults.defaultReminderMinutesBefore, 42);
    expect(savedTaskDefaults.defaultIsAutoScheduled, isFalse);
    expect(savedTaskDefaults.defaultReminderMinutesBefore, 7);
    expect(
      auditRows.map((row) => '${row.entityType}:${row.action}'),
      containsAll(<String>[
        'event_calendar:create',
        'event_calendar:update_defaults',
        'event_calendar:toggle_visible',
        'task_list:create',
        'task_list:update_defaults',
        'task_list:toggle_visible',
      ]),
    );
    expect(
      pendingMutations.map((mutation) => mutation.objectType),
      containsAll(<String>['calendar_book', 'task_list']),
    );
  });

  test('synced event calendar upsert creates, dedupes and records metadata',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await _clearCalendarData(db);
    final evidence = _createEvidence(db);
    final repository = CalendarBooksRepository(
      db,
      evidence.auditRepository,
      evidence.recorder,
    );

    final createdId = await repository.upsertSyncedEventCalendar(
      source: 'outlook',
      remoteId: 'remote-calendar',
      name: 'Remote calendar',
      colorHex: '#123456',
      description: 'Initial remote book',
      metadata: const <String, Object?>{'source_test': 'create'},
    );
    final duplicateId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Duplicate remote calendar',
            source: const Value('outlook'),
            syncUrl: const Value('remote-calendar'),
            createdAt: fixtureNow().add(const Duration(minutes: 1)),
          ),
        );
    final duplicateEventId = await db.into(db.calendarEvents).insert(
          fixtureEvent(
            uid: 'duplicate-remote-event',
            summary: 'Duplicate event',
            calendarId: duplicateId,
          ),
        );

    final updatedId = await repository.upsertSyncedEventCalendar(
      source: 'outlook',
      remoteId: 'remote-calendar',
      name: 'Remote calendar renamed',
      colorHex: '#654321',
      description: 'Updated remote book',
      metadata: const <String, Object?>{'source_test': 'update'},
    );

    final calendars = await repository.getEventCalendarsBySource('outlook');
    final migratedEvent = await EventRepository(db).getById(duplicateEventId);
    final auditRows = await evidence.auditRepository.listRecent(limit: 20);

    expect(updatedId, createdId);
    expect(calendars, hasLength(1));
    expect(calendars.single.name, 'Remote calendar renamed');
    expect(calendars.single.colorHex, '#654321');
    expect(calendars.single.description, 'Updated remote book');
    expect(migratedEvent?.eventCalendarId, createdId);
    expect(await repository.getEventCalendarById(duplicateId), isNull);
    expect(
      auditRows
          .where((row) =>
              row.entityType == 'event_calendar' &&
              row.action == 'upsert_synced' &&
              row.metadataJson?.contains('remote-calendar') == true)
          .length,
      greaterThanOrEqualTo(2),
    );
  });

  test('task list archive, restore and delete migrate tasks and bindings',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await _clearCalendarData(db);
    final evidence = _createEvidence(db);
    final repository = CalendarBooksRepository(
      db,
      evidence.auditRepository,
      evidence.recorder,
    );
    final bindingsRepository = OutlookSyncBindingsRepository(db);

    final sourceId = await repository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Bound tasks',
        createdAt: fixtureNow(),
        isDefault: const Value(true),
      ),
      audit: false,
    );
    final fallbackId = await repository.createTaskList(
      TaskListsCompanion.insert(
        name: 'Fallback tasks',
        createdAt: fixtureNow().add(const Duration(minutes: 1)),
      ),
      audit: false,
    );
    final firstTaskId = await db.into(db.taskItems).insert(
          fixtureTask(
            uid: 'bound-task-1',
            summary: 'Move on archive',
            taskListId: sourceId,
          ),
        );
    await repository.saveTaskListDefaults(
      id: sourceId,
      defaultIsAutoScheduled: false,
      defaultReminderMinutesBefore: 5,
      audit: false,
    );
    await _saveBinding(bindingsRepository, sourceId, 'remote-bound');

    await repository.archiveTaskList(sourceId);

    final archivedList = await repository.getTaskListById(sourceId);
    final migratedFirstTask = await _taskById(db, firstTaskId);
    expect(archivedList?.isArchived, isTrue);
    expect(archivedList?.isVisible, isFalse);
    expect(archivedList?.isDefault, isFalse);
    expect(migratedFirstTask?.taskListId, fallbackId);
    expect(await bindingsRepository.getTaskListBinding(sourceId), isNull);
    expect((await repository.getTaskListById(fallbackId))?.isDefault, isTrue);

    await repository.unarchiveTaskList(sourceId);
    await repository.setDefaultTaskList(sourceId);
    await _saveBinding(bindingsRepository, sourceId, 'remote-delete');
    await repository.saveTaskListDefaults(
      id: sourceId,
      defaultIsAutoScheduled: false,
      defaultReminderMinutesBefore: 9,
      audit: false,
    );
    final secondTaskId = await db.into(db.taskItems).insert(
          fixtureTask(
            uid: 'bound-task-2',
            summary: 'Move on delete',
            taskListId: sourceId,
          ),
        );

    final deleted = await repository.deleteTaskList(sourceId);

    final migratedSecondTask = await _taskById(db, secondTaskId);
    final deletedDefaults = await repository.getTaskListDefaults(
      sourceId,
      fallbackReminderMinutes: 33,
    );
    final auditRows = await evidence.auditRepository.listRecent(limit: 20);
    final pendingMutations = await evidence.mutationStore.listPending();

    expect(deleted, 1);
    expect(await repository.getTaskListById(sourceId), isNull);
    expect(migratedSecondTask?.taskListId, fallbackId);
    expect(await bindingsRepository.getTaskListBinding(sourceId), isNull);
    expect(deletedDefaults.defaultIsAutoScheduled, isTrue);
    expect(deletedDefaults.defaultReminderMinutesBefore, 33);
    expect(
      auditRows.map((row) => '${row.entityType}:${row.action}'),
      containsAll(<String>[
        'task_list:archive',
        'task_list:restore',
        'task_list:set_default',
        'task_list:delete',
      ]),
    );
    expect(
      auditRows.where(
        (row) =>
            row.entityType == 'task_list' &&
            row.action == 'delete' &&
            row.metadataJson?.contains('"task_count":1') == true,
      ),
      isNotEmpty,
    );
    expect(
      pendingMutations.where(
        (mutation) =>
            mutation.objectType == 'task_list' &&
            mutation.action.name == 'delete',
      ),
      isNotEmpty,
    );
  });

  test('container integrity repairs orphan events and tasks', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await _clearCalendarData(db);
    final repository = CalendarBooksRepository(db);

    final orphanEventId = await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            uid: 'orphan-event',
            dtstamp: fixtureNow(),
            summary: 'Orphan event',
            dtstart: fixtureNow(),
            eventCalendarId: const Value(9999),
          ),
        );
    final orphanTaskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'orphan-task',
            dtstamp: fixtureNow(),
            summary: 'Orphan task',
            taskListId: const Value(9999),
          ),
        );

    await repository.ensureContainerIntegrity();

    final repairedEvent = await EventRepository(db).getById(orphanEventId);
    final repairedTask = await _taskById(db, orphanTaskId);
    final calendars = await repository.getAllEventCalendars();
    final taskLists = await repository.getAllTaskLists();

    expect(calendars, hasLength(1));
    expect(taskLists, hasLength(1));
    expect(repairedEvent?.eventCalendarId, calendars.single.id);
    expect(repairedTask?.taskListId, taskLists.single.id);
    expect(calendars.single.isDefault, isTrue);
    expect(taskLists.single.isDefault, isTrue);
  });
}

Future<void> _clearCalendarData(AppDatabase db) async {
  await db.delete(db.calendarEvents).go();
  await db.delete(db.taskItems).go();
  await db.delete(db.eventCalendars).go();
  await db.delete(db.taskLists).go();
}

Future<void> _saveBinding(
  OutlookSyncBindingsRepository repository,
  int taskListId,
  String remoteCalendarId,
) {
  return repository.saveTaskListBinding(
    OutlookTaskListBinding(
      localTaskListId: taskListId,
      remoteCalendarId: remoteCalendarId,
      remoteCalendarName: 'Remote $remoteCalendarId',
      linkedAt: fixtureNow(),
    ),
  );
}

Future<TaskItem?> _taskById(AppDatabase db, int id) {
  return (db.select(db.taskItems)..where((task) => task.id.equals(id)))
      .getSingleOrNull();
}

_Evidence _createEvidence(AppDatabase db) {
  final mutationStore = OfflineMutationStore(db);
  final recorder = SyncWriteRecorder(
    mutationStore: mutationStore,
    stateStore: SyncObjectStateStore(db),
  );
  return (
    auditRepository: DataOperationLogRepository(db, recorder),
    mutationStore: mutationStore,
    recorder: recorder,
  );
}
