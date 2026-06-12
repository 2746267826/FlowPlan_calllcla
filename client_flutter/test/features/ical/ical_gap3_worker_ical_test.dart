import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/ical/flowplanv2_archive_service.dart';
import 'package:flowplanv2/features/ical/ical_parser.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_path_provider.dart';
import '../../test_support/test_database.dart';

final _stamp = DateTime.utc(2026, 6, 8, 9);

void main() {
  group('ICalParser gap worker boundaries', () {
    test('skips invalid starts while keeping generated uid defaults', () {
      final events = const ICalParser().parse('''
BEGIN:VCALENDAR
VERSION:2.0
BEGIN:VEVENT
SUMMARY:Bad start
DTSTART:not-a-date
END:VEVENT
BEGIN:VEVENT
SUMMARY:Generated uid
DESCRIPTION:
LOCATION:
DTSTART:20260608T090000
DTEND:not-a-date
END:VEVENT
END:VCALENDAR
''');

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.uid.value, isNotEmpty);
      expect(event.summary.value, 'Generated uid');
      expect(event.description.value, isNull);
      expect(event.location.value, isNull);
      expect(event.dtend.value, isNull);
      expect(event.status.value, 'CONFIRMED');
    });
  });

  group('FlowPlanV2ArchiveService gap worker metadata', () {
    test('smart merge import records audit metadata with item counts', () async {
      final harness = await _createHarness();
      final calendarId = await harness.createCalendar(name: 'Work');
      await harness.createEvent(
        calendarId: calendarId,
        uid: 'same-event',
        summary: 'Old event',
      );
      final taskListId = await harness.createTaskList(name: 'Inbox');
      await harness.createTask(
        taskListId: taskListId,
        uid: 'same-task',
        summary: 'Old task',
      );

      final result = await harness.service.importArchive(
        archive: FlowPlanV2ArchiveData(
          exportedAt: _stamp,
          calendars: [
            FlowPlanV2ArchiveCalendar(
              name: ' work ',
              colorHex: '#112233',
              description: 'Updated work',
              isVisible: false,
              isDefault: true,
              defaultIsBlock: true,
              events: [
                _archiveEvent(uid: 'same-event', summary: 'Updated event'),
                _archiveEvent(uid: 'new-event', summary: 'New event'),
              ],
            ),
          ],
          taskLists: [
            FlowPlanV2ArchiveTaskList(
              name: ' inbox ',
              colorHex: '#445566',
              emoji: 'I',
              isVisible: true,
              isDefault: true,
              isArchived: false,
              defaultIsAutoScheduled: false,
              defaultReminderMinutesBefore: 45,
              tasks: [
                _archiveTask(uid: 'same-task', summary: 'Updated task'),
                _archiveTask(uid: 'new-task', summary: 'New task'),
              ],
            ),
          ],
        ),
        mode: FlowPlanV2ArchiveImportMode.smartMerge,
        sourcePath: r'C:\imports\containers.flowplanv2.json',
      );

      expect(File(result.backupPath).existsSync(), isTrue);
      expect(result.mergedCalendars, 1);
      expect(result.updatedEvents, 1);
      expect(result.createdEvents, 1);
      expect(result.mergedTaskLists, 1);
      expect(result.updatedTasks, 1);
      expect(result.createdTasks, 1);

      final logs = await harness.logs.listRecent();
      expect(logs, hasLength(1));
      expect(logs.single.action, 'import_structured_archive');
      final metadata =
          jsonDecode(logs.single.metadataJson!) as Map<String, dynamic>;
      expect(metadata['mode'], FlowPlanV2ArchiveImportMode.smartMerge.name);
      expect(metadata['source_path'], r'C:\imports\containers.flowplanv2.json');
      expect(metadata['backup_path'], result.backupPath);
      expect(metadata['archive_calendar_count'], 1);
      expect(metadata['archive_task_list_count'], 1);
      expect(metadata['created_events'], 1);
      expect(metadata['updated_events'], 1);
      expect(metadata['created_tasks'], 1);
      expect(metadata['updated_tasks'], 1);
    });

    test('replace matching import reports removals and leaves unrelated data',
        () async {
      final harness = await _createHarness();
      final matchingCalendarId = await harness.createCalendar(name: 'Work');
      await harness.createEvent(
        calendarId: matchingCalendarId,
        uid: 'remove-event',
        summary: 'Remove event',
      );
      final otherCalendarId = await harness.createCalendar(name: 'Personal');
      await harness.createEvent(
        calendarId: otherCalendarId,
        uid: 'keep-event',
        summary: 'Keep event',
      );
      final matchingTaskListId = await harness.createTaskList(name: 'Inbox');
      await harness.createTask(
        taskListId: matchingTaskListId,
        uid: 'remove-task',
        summary: 'Remove task',
      );
      final otherTaskListId = await harness.createTaskList(name: 'Later');
      await harness.createTask(
        taskListId: otherTaskListId,
        uid: 'keep-task',
        summary: 'Keep task',
      );

      final result = await harness.service.importArchive(
        archive: FlowPlanV2ArchiveData(
          exportedAt: _stamp,
          calendars: [
            FlowPlanV2ArchiveCalendar(
              name: 'Work',
              colorHex: '#6B5EE4',
              description: null,
              isVisible: true,
              isDefault: false,
              defaultIsBlock: false,
              events: [
                _archiveEvent(uid: 'replacement-event', summary: 'Replacement'),
              ],
            ),
          ],
          taskLists: [
            FlowPlanV2ArchiveTaskList(
              name: 'Inbox',
              colorHex: '#0EA8A0',
              emoji: null,
              isVisible: true,
              isDefault: false,
              isArchived: false,
              defaultIsAutoScheduled: true,
              defaultReminderMinutesBefore: 15,
              tasks: [
                _archiveTask(uid: 'replacement-task', summary: 'Replacement'),
              ],
            ),
          ],
        ),
        mode: FlowPlanV2ArchiveImportMode.replaceMatchingContainers,
      );

      expect(result.removedEvents, 1);
      expect(result.createdEvents, 1);
      expect(result.removedTasks, 1);
      expect(result.createdTasks, 1);

      final matchingEvents = await harness.events.getByCalendarId(
        matchingCalendarId,
      );
      expect(matchingEvents.map((event) => event.uid), ['replacement-event']);
      final otherEvents = await harness.events.getByCalendarId(otherCalendarId);
      expect(otherEvents.map((event) => event.uid), ['keep-event']);

      final matchingTasks = await harness.tasks.getByTaskListIds([
        matchingTaskListId,
      ]);
      expect(matchingTasks.map((task) => task.uid), ['replacement-task']);
      final otherTasks = await harness.tasks.getByTaskListIds([
        otherTaskListId,
      ]);
      expect(otherTasks.map((task) => task.uid), ['keep-task']);

      final metadata = jsonDecode(
        (await harness.logs.listRecent()).single.metadataJson!,
      ) as Map<String, dynamic>;
      expect(
        metadata['mode'],
        FlowPlanV2ArchiveImportMode.replaceMatchingContainers.name,
      );
      expect(metadata['removed_events'], 1);
      expect(metadata['removed_tasks'], 1);
    });
  });
}

Future<_ArchiveHarness> _createHarness() async {
  final documentsDirectory = await setFakePathProviderDocumentsDirectory(
    'ical_gap3_worker_ical_',
  );
  addTearDown(() async {
    if (await documentsDirectory.exists()) {
      await documentsDirectory.delete(recursive: true);
    }
  });

  final db = createTestDatabase();
  addTearDown(db.close);

  final books = CalendarBooksRepository(db);
  final events = EventRepository(db);
  final tasks = TaskRepository(db);
  final logs = DataOperationLogRepository(db);
  return _ArchiveHarness(
    books: books,
    events: events,
    tasks: tasks,
    logs: logs,
    service: FlowPlanV2ArchiveService(
      database: db,
      calendarBooksRepository: books,
      eventRepository: events,
      taskRepository: tasks,
      operationLogRepository: logs,
    ),
  );
}

class _ArchiveHarness {
  const _ArchiveHarness({
    required this.books,
    required this.events,
    required this.tasks,
    required this.logs,
    required this.service,
  });

  final CalendarBooksRepository books;
  final EventRepository events;
  final TaskRepository tasks;
  final DataOperationLogRepository logs;
  final FlowPlanV2ArchiveService service;

  Future<int> createCalendar({required String name}) {
    return books.createEventCalendar(
      EventCalendarsCompanion.insert(
        name: name,
        colorHex: const Value('#6B5EE4'),
        isDefault: const Value(false),
        createdAt: _stamp,
      ),
      audit: false,
    );
  }

  Future<int> createTaskList({required String name}) {
    return books.createTaskList(
      TaskListsCompanion.insert(
        name: name,
        colorHex: const Value('#0EA8A0'),
        isDefault: const Value(false),
        createdAt: _stamp,
      ),
      audit: false,
    );
  }

  Future<int> createEvent({
    required int calendarId,
    required String uid,
    required String summary,
  }) {
    return events.create(
      CalendarEventsCompanion.insert(
        uid: uid,
        dtstamp: _stamp,
        summary: summary,
        dtstart: _stamp,
        dtend: Value(_stamp.add(const Duration(hours: 1))),
        status: const Value('CONFIRMED'),
        transp: const Value('OPAQUE'),
        source: const Value('local'),
        eventCalendarId: Value(calendarId),
        colorHex: const Value('#6B5EE4'),
        isBlock: const Value(false),
      ),
      audit: false,
    );
  }

  Future<int> createTask({
    required int taskListId,
    required String uid,
    required String summary,
  }) {
    return tasks.create(
      TaskItemsCompanion.insert(
        uid: uid,
        dtstamp: _stamp,
        summary: summary,
        status: const Value('NEEDS-ACTION'),
        percentComplete: const Value(0),
        categories: const Value('[]'),
        durationMinutes: const Value(60),
        priorityLocal: const Value(2),
        isAutoScheduled: const Value(true),
        taskListId: Value(taskListId),
        reminderMinutesBefore: const Value(15),
      ),
      audit: false,
    );
  }
}

FlowPlanV2ArchiveEvent _archiveEvent({
  required String uid,
  required String summary,
}) {
  return FlowPlanV2ArchiveEvent(
    uid: uid,
    dtstamp: _stamp,
    summary: summary,
    description: null,
    location: null,
    dtstart: _stamp.add(const Duration(days: 1)),
    dtend: _stamp.add(const Duration(days: 1, hours: 1)),
    rrule: null,
    status: 'CONFIRMED',
    transp: 'OPAQUE',
    source: 'local',
    colorHex: '#6B5EE4',
    isBlock: false,
  );
}

FlowPlanV2ArchiveTask _archiveTask({
  required String uid,
  required String summary,
}) {
  return FlowPlanV2ArchiveTask(
    uid: uid,
    dtstamp: _stamp,
    summary: summary,
    description: null,
    location: null,
    dtstart: _stamp.add(const Duration(days: 1)),
    due: _stamp.add(const Duration(days: 1, hours: 1)),
    completed: null,
    priority: 0,
    status: 'NEEDS-ACTION',
    percentComplete: 0,
    categories: '[]',
    rrule: null,
    durationMinutes: 60,
    isSplittable: false,
    priorityLocal: 2,
    isAutoScheduled: true,
    tagId: null,
    isLocked: false,
    reminderMinutesBefore: 15,
  );
}
