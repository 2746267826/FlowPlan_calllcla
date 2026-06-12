import 'package:async/async.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/fixtures.dart';
import '../test_support/test_database.dart';

typedef _Evidence = ({
  DataOperationLogRepository auditRepository,
  OfflineMutationStore mutationStore,
  SyncWriteRecorder recorder,
});

void main() {
  group('TaskRepository worker 09 gaps', () {
    test('watchByList and management stream expose hidden list tasks',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final booksRepository = CalendarBooksRepository(db);
      final taskRepository = TaskRepository(db);
      final visibleListId = await insertFixtureTaskList(db);
      final hiddenListId = await booksRepository.createTaskList(
        TaskListsCompanion.insert(
          name: 'Hidden active',
          createdAt: fixtureNow().add(const Duration(minutes: 1)),
          isVisible: const Value(false),
        ),
        audit: false,
      );
      await taskRepository.create(
        fixtureTask(
          uid: 'visible-list-task',
          summary: 'Visible list task',
          taskListId: visibleListId,
        ),
        audit: false,
      );
      await taskRepository.create(
        fixtureTask(
          uid: 'hidden-list-task',
          summary: 'Hidden list task',
          taskListId: hiddenListId,
        ),
        audit: false,
      );

      final hiddenQueue =
          StreamQueue<List<TaskItem>>(taskRepository.watchByList(hiddenListId));
      final managementQueue =
          StreamQueue<List<TaskItem>>(taskRepository.watchAllForManagement());
      addTearDown(hiddenQueue.cancel);
      addTearDown(managementQueue.cancel);

      expect(
        (await hiddenQueue.next).map((task) => task.summary),
        ['Hidden list task'],
      );
      expect(
        (await managementQueue.next).map((task) => task.summary),
        containsAll(<String>['Visible list task', 'Hidden list task']),
      );
    });

    test('direct schedule updates record focused changed fields', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final evidence = _createEvidence(db);
      final repository = TaskRepository(
        db,
        evidence.auditRepository,
        evidence.recorder,
      );
      final taskListId = await insertFixtureTaskList(db);
      final taskId = await repository.create(
        fixtureTask(
          uid: 'direct-schedule-task',
          summary: 'Direct schedule task',
          taskListId: taskListId,
        ),
        audit: false,
      );

      await repository.updateDtstart(
        taskId,
        fixtureNow().add(const Duration(hours: 1)),
      );
      await repository.updateDuration(taskId, 75);
      await repository.clearDtstart(taskId);

      final task = await repository.getById(taskId);
      final mutations = await evidence.mutationStore.listPending();

      expect(task?.dtstart, isNull);
      expect(task?.durationMinutes, 75);
      expect(
        mutations
            .where((mutation) => mutation.objectType == 'task_item')
            .map((mutation) => mutation.changedFieldsJson),
        containsAll(<String>[
          '["dtstart"]',
          '["durationMinutes"]',
        ]),
      );
    });

    test('markCompleted handles existing and missing rows', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final evidence = _createEvidence(db);
      final repository = TaskRepository(
        db,
        evidence.auditRepository,
        evidence.recorder,
      );
      final taskListId = await insertFixtureTaskList(db);
      final taskId = await repository.create(
        fixtureTask(
          uid: 'complete-task',
          summary: 'Complete task',
          taskListId: taskListId,
        ),
        audit: false,
      );

      await repository.markCompleted(taskId);
      await repository.markCompleted(404);

      final completed = await repository.getById(taskId);
      final auditRows = await evidence.auditRepository.listRecent();
      final mutations = await evidence.mutationStore.listPending();

      expect(completed?.status, 'COMPLETED');
      expect(completed?.percentComplete, 100);
      expect(completed?.completed, isNotNull);
      expect(
        auditRows
            .where((row) => row.entityType == 'task_item')
            .map((row) => row.action),
        ['mark_completed'],
      );
      expect(
        mutations
            .where((mutation) => mutation.objectType == 'task_item')
            .map((mutation) => mutation.changedFieldsJson),
        contains('["status","completed","percentComplete"]'),
      );
    });

    test(
        'active scheduled and pending schedule filters exclude done locked archived',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final taskRepository = TaskRepository(db);
      final activeListId = await insertFixtureTaskList(db);
      final archivedListId = await db.into(db.taskLists).insert(
            TaskListsCompanion.insert(
              name: 'Archived tasks',
              createdAt: fixtureNow().add(const Duration(minutes: 1)),
              isArchived: const Value(true),
            ),
          );

      await db.into(db.taskItems).insert(
            fixtureTask(
              uid: 'scheduled-active',
              summary: 'Scheduled active',
              taskListId: activeListId,
            ).copyWith(
              dtstart: Value(fixtureNow().add(const Duration(hours: 2))),
              priorityLocal: const Value(2),
            ),
          );
      await db.into(db.taskItems).insert(
            fixtureTask(
              uid: 'scheduled-done',
              summary: 'Scheduled done',
              taskListId: activeListId,
            ).copyWith(
              dtstart: Value(fixtureNow().add(const Duration(hours: 1))),
              status: const Value('COMPLETED'),
            ),
          );
      await db.into(db.taskItems).insert(
            fixtureTask(
              uid: 'pending-locked',
              summary: 'Pending locked',
              taskListId: activeListId,
            ).copyWith(isLocked: const Value(true)),
          );
      await db.into(db.taskItems).insert(
            fixtureTask(
              uid: 'pending-archived',
              summary: 'Pending archived',
              taskListId: archivedListId,
            ),
          );

      final scheduled = await taskRepository.getActiveScheduledForDate(
        fixtureNow(),
      );
      final pending = await taskRepository.getPendingForSchedule();

      expect(scheduled.map((task) => task.summary), ['Scheduled active']);
      expect(pending.map((task) => task.summary), ['Scheduled active']);
    });
  });

  group('EventRepository worker 09 gaps', () {
    test('empty calendar filters and management stream expose all events',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = EventRepository(db);
      final calendarId = await insertFixtureCalendar(db);
      await repository.create(
        fixtureEvent(
          uid: 'management-event',
          summary: 'Management event',
          calendarId: calendarId,
        ),
        audit: false,
      );
      final managementQueue = StreamQueue<List<CalendarEvent>>(
        repository.watchAllForManagement(),
      );
      addTearDown(managementQueue.cancel);

      expect(await repository.getByCalendarIds(const <int>[]), isEmpty);
      expect(
        (await managementQueue.next).map((event) => event.summary),
        ['Management event'],
      );
    });

    test('update without calendar binding and missing delete are no-ops',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final evidence = _createEvidence(db);
      final repository = EventRepository(
        db,
        evidence.auditRepository,
        evidence.recorder,
      );

      final updated = await repository.update(
        CalendarEventsCompanion.insert(
          id: const Value(404),
          uid: 'missing-event',
          dtstamp: fixtureNow(),
          summary: 'Missing event',
          dtstart: fixtureNow(),
        ),
      );
      await repository.updateTimes(
        404,
        fixtureNow(),
        fixtureNow().add(const Duration(hours: 1)),
      );
      final deleted = await repository.delete(404);

      expect(updated, isFalse);
      expect(deleted, 0);
      expect(await evidence.auditRepository.listRecent(), isEmpty);
      expect(await evidence.mutationStore.listPending(), isEmpty);
    });

    test('replace calendar events normalizes calendar id and delete helpers',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = EventRepository(db);
      final targetCalendarId = await insertFixtureCalendar(db, name: 'Target');
      final otherCalendarId = await insertFixtureCalendar(db, name: 'Other');
      await repository.create(
        fixtureEvent(
          uid: 'old-event',
          summary: 'Old event',
          calendarId: targetCalendarId,
        ),
        audit: false,
      );

      await repository.replaceCalendarEvents(
        calendarId: targetCalendarId,
        companions: [
          fixtureEvent(
            uid: 'replacement-event',
            summary: 'Replacement event',
            calendarId: otherCalendarId,
          ).copyWith(source: const Value('outlook')),
        ],
      );
      final afterReplace = await repository.getByCalendarId(targetCalendarId);
      final deletedBySource = await repository.deleteBySourceAndCalendarId(
        source: 'outlook',
        calendarId: targetCalendarId,
      );
      await repository.create(
        fixtureEvent(
          uid: 'delete-by-uid',
          summary: 'Delete by uid',
          calendarId: targetCalendarId,
        ),
        audit: false,
      );
      await repository.deleteByUid('delete-by-uid');

      expect(afterReplace.map((event) => event.uid), ['replacement-event']);
      expect(afterReplace.single.eventCalendarId, targetCalendarId);
      expect(deletedBySource, 1);
      expect(await repository.getAllByUid('delete-by-uid'), isEmpty);
    });

    test('blocks for date include only blocking events on the selected day',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = EventRepository(db);
      final calendarId = await insertFixtureCalendar(db);
      await repository.create(
        fixtureEvent(
          uid: 'block-event',
          summary: 'Block event',
          calendarId: calendarId,
        ).copyWith(isBlock: const Value(true)),
        audit: false,
      );
      await repository.create(
        fixtureEvent(
          uid: 'normal-event',
          summary: 'Normal event',
          calendarId: calendarId,
        ),
        audit: false,
      );

      final blocks = await repository.getBlocksForDate(fixtureNow());

      expect(blocks.map((event) => event.summary), ['Block event']);
    });
  });

  group('CalendarBooksRepository worker 09 gaps', () {
    test('deleting sole local calendars and task lists creates fallbacks',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = CalendarBooksRepository(db);
      final eventRepository = EventRepository(db);
      final taskRepository = TaskRepository(db);
      final calendarId = await repository.createEventCalendar(
        EventCalendarsCompanion.insert(
          name: 'Only calendar',
          createdAt: fixtureNow(),
          isDefault: const Value(true),
        ),
        audit: false,
      );
      final taskListId = await repository.createTaskList(
        TaskListsCompanion.insert(
          name: 'Only task list',
          createdAt: fixtureNow(),
          isDefault: const Value(true),
        ),
        audit: false,
      );
      final eventId = await eventRepository.create(
        fixtureEvent(
          uid: 'fallback-event',
          summary: 'Fallback event',
          calendarId: calendarId,
        ),
        audit: false,
      );
      final taskId = await taskRepository.create(
        fixtureTask(
          uid: 'fallback-task',
          summary: 'Fallback task',
          taskListId: taskListId,
        ),
        audit: false,
      );

      await repository.deleteEventCalendar(calendarId, audit: false);
      await repository.deleteTaskList(taskListId, audit: false);

      final calendars = await repository.getAllEventCalendars();
      final taskLists = await repository.getAllTaskLists();
      final movedEvent = await eventRepository.getById(eventId);
      final movedTask = await taskRepository.getById(taskId);

      expect(calendars.map((calendar) => calendar.id),
          isNot(contains(calendarId)));
      expect(calendars.where((calendar) => calendar.isDefault), hasLength(1));
      expect(
        calendars.map((calendar) => calendar.id),
        contains(movedEvent?.eventCalendarId),
      );
      expect(taskLists.map((taskList) => taskList.id),
          isNot(contains(taskListId)));
      expect(taskLists.where((taskList) => taskList.isDefault), hasLength(1));
      expect(
        taskLists.map((taskList) => taskList.id),
        contains(movedTask?.taskListId),
      );
    });

    test('integrity repair assigns orphan rows and normalizes defaults',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = CalendarBooksRepository(db);
      final brokenCalendarId = await db.into(db.eventCalendars).insert(
            EventCalendarsCompanion.insert(
              name: 'Broken calendar',
              createdAt: fixtureNow(),
            ),
          );
      final archivedTaskListId = await db.into(db.taskLists).insert(
            TaskListsCompanion.insert(
              name: 'Archived default',
              createdAt: fixtureNow(),
              isArchived: const Value(true),
              isDefault: const Value(true),
            ),
          );
      final eventId = await db.into(db.calendarEvents).insert(
            fixtureEvent(
              uid: 'orphan-event',
              summary: 'Orphan event',
              calendarId: brokenCalendarId,
            ).copyWith(eventCalendarId: const Value(null)),
          );
      final taskId = await db.into(db.taskItems).insert(
            fixtureTask(
              uid: 'orphan-task',
              summary: 'Orphan task',
              taskListId: archivedTaskListId,
            ).copyWith(taskListId: const Value(null)),
          );

      await repository.ensureContainerIntegrity();

      final repairedEvent = await EventRepository(db).getById(eventId);
      final repairedTask = await TaskRepository(db).getById(taskId);
      final defaultCalendar = (await repository.getAllEventCalendars())
          .where((calendar) => calendar.isDefault);
      final defaultTaskLists = (await repository.getAllTaskLists())
          .where((taskList) => taskList.isDefault);

      expect(repairedEvent?.eventCalendarId, isNotNull);
      expect(repairedTask?.taskListId, isNotNull);
      expect(defaultCalendar, hasLength(1));
      expect(defaultTaskLists, hasLength(1));
    });

    test('missing default targets are ignored without audit rows', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final evidence = _createEvidence(db);
      final repository = CalendarBooksRepository(
        db,
        evidence.auditRepository,
        evidence.recorder,
      );

      await repository.setDefaultEventCalendar(404);
      await repository.setDefaultTaskList(404);
      expect(await repository.deleteEventCalendar(404), 0);
      expect(await repository.deleteTaskList(404), 0);

      expect(await evidence.auditRepository.listRecent(), isEmpty);
      expect(await evidence.mutationStore.listPending(), isEmpty);
    });
  });
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
