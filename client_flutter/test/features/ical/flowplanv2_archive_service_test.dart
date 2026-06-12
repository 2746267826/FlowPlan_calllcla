import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/ical/flowplanv2_archive_service.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_path_provider.dart';
import '../../test_support/test_database.dart';

const _eventKind = '\u65e5\u5386\u672c';
const _taskListKind = '\u4efb\u52a1\u672c';

final _stamp = DateTime.utc(2026, 6, 8, 9);

void main() {
  group('FlowPlanV2ArchiveService', () {
    test('buildArchive exports selected local containers with defaults',
        () async {
      final harness = await _createHarness();
      final exportedCalendarId = await harness.createCalendar(
        name: 'Exported calendar',
        colorHex: '#112233',
      );
      final skippedCalendarId = await harness.createCalendar(
        name: 'Skipped calendar',
      );
      final remoteCalendarId = await harness.createCalendar(
        name: 'Outlook calendar',
        source: 'outlook',
        syncUrl: 'remote-calendar',
      );
      await harness.books.saveEventCalendarDefaults(
        id: exportedCalendarId,
        defaultIsBlock: true,
        audit: false,
      );
      await harness.createEvent(
        calendarId: exportedCalendarId,
        uid: 'export-event',
        summary: 'Exported event',
        isBlock: true,
      );
      await harness.createEvent(
        calendarId: skippedCalendarId,
        uid: 'skipped-event',
        summary: 'Skipped event',
      );
      await harness.createEvent(
        calendarId: remoteCalendarId,
        uid: 'remote-event',
        summary: 'Remote event',
      );

      final exportedTaskListId = await harness.createTaskList(
        name: 'Exported tasks',
        colorHex: '#445566',
      );
      final skippedTaskListId = await harness.createTaskList(
        name: 'Skipped tasks',
      );
      await harness.books.saveTaskListDefaults(
        id: exportedTaskListId,
        defaultIsAutoScheduled: false,
        defaultReminderMinutesBefore: 45,
        audit: false,
      );
      await harness.createTask(
        taskListId: exportedTaskListId,
        uid: 'export-task',
        summary: 'Exported task',
        reminderMinutesBefore: 45,
      );
      await harness.createTask(
        taskListId: skippedTaskListId,
        uid: 'skipped-task',
        summary: 'Skipped task',
      );

      final archive = await harness.service.buildArchive(
        calendarIds: [exportedCalendarId, remoteCalendarId],
        taskListIds: [exportedTaskListId],
      );

      expect(archive.calendars, hasLength(1));
      expect(archive.calendars.single.name, 'Exported calendar');
      expect(archive.calendars.single.colorHex, '#112233');
      expect(archive.calendars.single.defaultIsBlock, isTrue);
      expect(archive.calendars.single.events.single.uid, 'export-event');
      expect(archive.calendars.single.events.single.isBlock, isTrue);

      expect(archive.taskLists, hasLength(1));
      expect(archive.taskLists.single.name, 'Exported tasks');
      expect(archive.taskLists.single.colorHex, '#445566');
      expect(archive.taskLists.single.defaultIsAutoScheduled, isFalse);
      expect(archive.taskLists.single.defaultReminderMinutesBefore, 45);
      expect(archive.taskLists.single.tasks.single.uid, 'export-task');
      expect(archive.taskLists.single.tasks.single.reminderMinutesBefore, 45);
    });

    test('FlowPlanV2ArchiveData parses json fallbacks and round trips models',
        () {
      final archive = FlowPlanV2ArchiveData.fromJsonString(
        jsonEncode({
          'schema': FlowPlanV2ArchiveData.schema,
          'version': FlowPlanV2ArchiveData.version,
          'exported_at': '2026-06-08T09:00:00.000Z',
          'calendars': [
            {
              'name': '  Imported calendar  ',
              'color_hex': 42,
              'description': '  ',
              'is_visible': 'off',
              'is_default': 1,
              'default_is_block': 'yes',
              'events': [
                {
                  'uid': '  event-json  ',
                  'dtstamp': '2026-06-08T09:00:00.000Z',
                  'summary': '',
                  'description': '  Event details  ',
                  'location': '',
                  'dtstart': '2026-06-09T10:30:00.000Z',
                  'dtend': null,
                  'rrule': 'FREQ=DAILY;COUNT=2',
                  'status': '',
                  'transp': 'TRANSPARENT',
                  'source': null,
                  'color_hex': '',
                  'is_block': 'true',
                },
              ],
            },
          ],
          'task_lists': [
            {
              'name': '',
              'color_hex': false,
              'emoji': '  pin  ',
              'is_visible': 'no',
              'is_default': '1',
              'is_archived': 1,
              'default_is_auto_scheduled': 0,
              'default_reminder_minutes_before': '45',
              'tasks': [
                {
                  'uid': 'task-json',
                  'dtstamp': '2026-06-08T09:00:00.000Z',
                  'summary': ' Task summary ',
                  'description': '',
                  'location': '  Desk  ',
                  'dtstart': '2026-06-10T08:00:00.000Z',
                  'due': '2026-06-10T09:00:00.000Z',
                  'completed': '',
                  'priority': '3',
                  'status': null,
                  'percent_complete': 70.5,
                  'categories': ['deep', 3],
                  'rrule': '',
                  'duration_minutes': 'bad',
                  'is_splittable': 'on',
                  'priority_local': 1.7,
                  'is_auto_scheduled': 'false',
                  'tag_id': '  tag-a  ',
                  'is_locked': 'yes',
                  'reminder_minutes_before': '20',
                },
              ],
            },
          ],
        }),
      );

      expect(archive.exportedAt, DateTime.utc(2026, 6, 8, 9));
      expect(archive.calendars, hasLength(1));
      final calendar = archive.calendars.single;
      expect(calendar.name, 'Imported calendar');
      expect(calendar.colorHex, '#6B5EE4');
      expect(calendar.description, null);
      expect(calendar.isVisible, isFalse);
      expect(calendar.isDefault, isTrue);
      expect(calendar.defaultIsBlock, isTrue);
      final event = calendar.events.single;
      expect(event.uid, 'event-json');
      expect(event.summary, '\u672a\u547d\u540d\u65e5\u7a0b');
      expect(event.description, 'Event details');
      expect(event.location, null);
      expect(event.dtstart, DateTime.utc(2026, 6, 9, 10, 30));
      expect(event.dtend, null);
      expect(event.status, 'CONFIRMED');
      expect(event.source, 'local');
      expect(event.colorHex, '#6B5EE4');
      expect(event.isBlock, isTrue);

      expect(archive.taskLists, hasLength(1));
      final taskList = archive.taskLists.single;
      expect(taskList.name, '\u672a\u547d\u540d\u4efb\u52a1\u672c');
      expect(taskList.colorHex, '#0EA8A0');
      expect(taskList.emoji, 'pin');
      expect(taskList.isVisible, isFalse);
      expect(taskList.isDefault, isTrue);
      expect(taskList.isArchived, isTrue);
      expect(taskList.defaultIsAutoScheduled, isFalse);
      expect(taskList.defaultReminderMinutesBefore, 45);
      final task = taskList.tasks.single;
      expect(task.summary, 'Task summary');
      expect(task.description, null);
      expect(task.location, 'Desk');
      expect(task.status, 'NEEDS-ACTION');
      expect(task.percentComplete, 71);
      expect(task.categories, '["deep",3]');
      expect(task.rrule, null);
      expect(task.durationMinutes, 60);
      expect(task.isSplittable, isTrue);
      expect(task.priorityLocal, 2);
      expect(task.isAutoScheduled, isFalse);
      expect(task.tagId, 'tag-a');
      expect(task.isLocked, isTrue);
      expect(task.reminderMinutesBefore, 20);

      final roundTripped =
          FlowPlanV2ArchiveData.fromJsonString(archive.toPrettyJson());
      expect(roundTripped.calendars.single.events.single.uid, 'event-json');
      expect(
        roundTripped.taskLists.single.tasks.single.categories,
        '["deep",3]',
      );
      expect(
        roundTripped.toJson()['task_lists'],
        [
          containsPair(
            'tasks',
            [
              containsPair('categories', ['deep', 3]),
            ],
          ),
        ],
      );
    });

    test('FlowPlanV2ArchiveData rejects non archive json', () {
      expect(
        () => FlowPlanV2ArchiveData.fromJsonString('[]'),
        throwsFormatException,
      );
      expect(
        () => FlowPlanV2ArchiveData.fromJson({'schema': 'other'}),
        throwsFormatException,
      );
    });

    test('previewImport counts smart append and replace actions', () async {
      final harness = await _createHarness();
      final calendarId = await harness.createCalendar(name: 'Work');
      await harness.createEvent(
        calendarId: calendarId,
        uid: 'event-1',
        summary: 'Existing event',
      );
      await harness.createEvent(
        calendarId: calendarId,
        uid: 'event-old',
        summary: 'Old event',
      );
      final taskListId = await harness.createTaskList(name: 'Inbox');
      await harness.createTask(
        taskListId: taskListId,
        uid: 'task-1',
        summary: 'Existing task',
      );
      await harness.createTask(
        taskListId: taskListId,
        uid: 'task-old',
        summary: 'Old task',
      );
      final archive = _archive(
        calendars: [
          _archiveCalendar(
            name: ' work ',
            events: [
              _archiveEvent(uid: 'event-1', summary: 'Changed event'),
              _archiveEvent(uid: 'event-2', summary: 'New event'),
            ],
          ),
        ],
        taskLists: [
          _archiveTaskList(
            name: 'INBOX',
            tasks: [
              _archiveTask(uid: 'task-1', summary: 'Changed task'),
              _archiveTask(uid: 'task-2', summary: 'New task'),
            ],
          ),
        ],
      );

      final smart = await harness.service.previewImport(
        archive: archive,
        mode: FlowPlanV2ArchiveImportMode.smartMerge,
      );
      final append = await harness.service.previewImport(
        archive: archive,
        mode: FlowPlanV2ArchiveImportMode.appendOnly,
      );
      final replace = await harness.service.previewImport(
        archive: archive,
        mode: FlowPlanV2ArchiveImportMode.replaceMatchingContainers,
      );

      expect(smart.createdContainers, 0);
      expect(smart.mergedContainers, 2);
      expect(smart.createdItems, 2);
      expect(smart.updatedItems, 2);
      expect(smart.skippedItems, 0);
      expect(smart.removedBeforeImportItems, 0);
      expect(_container(smart, _eventKind).createCount, 1);
      expect(_container(smart, _eventKind).updateCount, 1);
      expect(_container(smart, _taskListKind).createCount, 1);
      expect(_container(smart, _taskListKind).updateCount, 1);

      expect(append.createdItems, 2);
      expect(append.updatedItems, 0);
      expect(append.skippedItems, 2);
      expect(append.removedBeforeImportItems, 0);

      expect(replace.createdItems, 4);
      expect(replace.updatedItems, 0);
      expect(replace.skippedItems, 0);
      expect(replace.removedBeforeImportItems, 4);
      expect(_container(replace, _eventKind).removeBeforeImportCount, 2);
      expect(_container(replace, _taskListKind).removeBeforeImportCount, 2);
    });

    test('importArchive smartMerge updates matching uids and creates new items',
        () async {
      final harness = await _createHarness();
      final calendarId = await harness.createCalendar(
        name: 'Work',
        colorHex: '#111111',
      );
      await harness.books.saveEventCalendarDefaults(
        id: calendarId,
        defaultIsBlock: false,
        audit: false,
      );
      await harness.createEvent(
        calendarId: calendarId,
        uid: 'event-1',
        summary: 'Old event',
      );
      final taskListId = await harness.createTaskList(
        name: 'Inbox',
        colorHex: '#222222',
      );
      await harness.books.saveTaskListDefaults(
        id: taskListId,
        defaultIsAutoScheduled: true,
        defaultReminderMinutesBefore: 15,
        audit: false,
      );
      await harness.createTask(
        taskListId: taskListId,
        uid: 'task-1',
        summary: 'Old task',
      );
      final archive = _archive(
        calendars: [
          _archiveCalendar(
            name: 'Work',
            colorHex: '#AABBCC',
            defaultIsBlock: true,
            events: [
              _archiveEvent(uid: 'event-1', summary: 'Updated event'),
              _archiveEvent(uid: 'event-2', summary: 'New event'),
            ],
          ),
        ],
        taskLists: [
          _archiveTaskList(
            name: 'Inbox',
            colorHex: '#DDEEFF',
            defaultIsAutoScheduled: false,
            defaultReminderMinutesBefore: 60,
            tasks: [
              _archiveTask(uid: 'task-1', summary: 'Updated task'),
              _archiveTask(uid: 'task-2', summary: 'New task'),
            ],
          ),
        ],
      );

      final result = await harness.service.importArchive(
        archive: archive,
        mode: FlowPlanV2ArchiveImportMode.smartMerge,
        sourcePath: 'fixture.flowplanv2.json',
      );

      expect(File(result.backupPath).existsSync(), isTrue);
      expect(result.createdCalendars, 0);
      expect(result.mergedCalendars, 1);
      expect(result.createdEvents, 1);
      expect(result.updatedEvents, 1);
      expect(result.skippedEvents, 0);
      expect(result.removedEvents, 0);
      expect(result.createdTaskLists, 0);
      expect(result.mergedTaskLists, 1);
      expect(result.createdTasks, 1);
      expect(result.updatedTasks, 1);
      expect(result.skippedTasks, 0);
      expect(result.removedTasks, 0);

      final calendar = await harness.books.getEventCalendarById(calendarId);
      final calendarDefaults =
          await harness.books.getEventCalendarDefaults(calendarId);
      final events = await harness.events.getByCalendarId(calendarId);
      expect(calendar!.colorHex, '#AABBCC');
      expect(calendarDefaults.defaultIsBlock, isTrue);
      expect(events, hasLength(2));
      expect(_event(events, 'event-1').summary, 'Updated event');
      expect(_event(events, 'event-1').source, 'local');
      expect(_event(events, 'event-2').summary, 'New event');

      final taskList = await harness.books.getTaskListById(taskListId);
      final taskDefaults = await harness.books.getTaskListDefaults(taskListId);
      final tasks = await harness.tasks.getByTaskListIds([taskListId]);
      expect(taskList!.colorHex, '#DDEEFF');
      expect(taskDefaults.defaultIsAutoScheduled, isFalse);
      expect(taskDefaults.defaultReminderMinutesBefore, 60);
      expect(tasks, hasLength(2));
      expect(_task(tasks, 'task-1').summary, 'Updated task');
      expect(_task(tasks, 'task-2').summary, 'New task');
    });

    test(
        'importArchive appendOnly skips matching uids without changing defaults',
        () async {
      final harness = await _createHarness();
      final calendarId = await harness.createCalendar(
        name: 'Work',
        colorHex: '#111111',
      );
      await harness.books.saveEventCalendarDefaults(
        id: calendarId,
        defaultIsBlock: false,
        audit: false,
      );
      await harness.createEvent(
        calendarId: calendarId,
        uid: 'event-1',
        summary: 'Old event',
      );
      final taskListId = await harness.createTaskList(
        name: 'Inbox',
        colorHex: '#222222',
      );
      await harness.books.saveTaskListDefaults(
        id: taskListId,
        defaultIsAutoScheduled: true,
        defaultReminderMinutesBefore: 15,
        audit: false,
      );
      await harness.createTask(
        taskListId: taskListId,
        uid: 'task-1',
        summary: 'Old task',
      );
      final archive = _archive(
        calendars: [
          _archiveCalendar(
            name: 'WORK',
            colorHex: '#AABBCC',
            defaultIsBlock: true,
            events: [
              _archiveEvent(uid: 'event-1', summary: 'Updated event'),
              _archiveEvent(uid: 'event-2', summary: 'New event'),
            ],
          ),
        ],
        taskLists: [
          _archiveTaskList(
            name: ' inbox ',
            colorHex: '#DDEEFF',
            defaultIsAutoScheduled: false,
            defaultReminderMinutesBefore: 60,
            tasks: [
              _archiveTask(uid: 'task-1', summary: 'Updated task'),
              _archiveTask(uid: 'task-2', summary: 'New task'),
            ],
          ),
        ],
      );

      final result = await harness.service.importArchive(
        archive: archive,
        mode: FlowPlanV2ArchiveImportMode.appendOnly,
      );

      expect(File(result.backupPath).existsSync(), isTrue);
      expect(result.createdEvents, 1);
      expect(result.updatedEvents, 0);
      expect(result.skippedEvents, 1);
      expect(result.createdTasks, 1);
      expect(result.updatedTasks, 0);
      expect(result.skippedTasks, 1);

      final calendar = await harness.books.getEventCalendarById(calendarId);
      final calendarDefaults =
          await harness.books.getEventCalendarDefaults(calendarId);
      final events = await harness.events.getByCalendarId(calendarId);
      expect(calendar!.colorHex, '#111111');
      expect(calendarDefaults.defaultIsBlock, isFalse);
      expect(_event(events, 'event-1').summary, 'Old event');
      expect(_event(events, 'event-2').summary, 'New event');

      final taskList = await harness.books.getTaskListById(taskListId);
      final taskDefaults = await harness.books.getTaskListDefaults(taskListId);
      final tasks = await harness.tasks.getByTaskListIds([taskListId]);
      expect(taskList!.colorHex, '#222222');
      expect(taskDefaults.defaultIsAutoScheduled, isTrue);
      expect(taskDefaults.defaultReminderMinutesBefore, 15);
      expect(_task(tasks, 'task-1').summary, 'Old task');
      expect(_task(tasks, 'task-2').summary, 'New task');
    });

    test('importArchive replace removes old matching-container items',
        () async {
      final harness = await _createHarness();
      final calendarId = await harness.createCalendar(name: 'Work');
      await harness.createEvent(
        calendarId: calendarId,
        uid: 'event-old-1',
        summary: 'Old event 1',
      );
      await harness.createEvent(
        calendarId: calendarId,
        uid: 'event-old-2',
        summary: 'Old event 2',
      );
      final taskListId = await harness.createTaskList(name: 'Inbox');
      await harness.createTask(
        taskListId: taskListId,
        uid: 'task-old-1',
        summary: 'Old task 1',
      );
      await harness.createTask(
        taskListId: taskListId,
        uid: 'task-old-2',
        summary: 'Old task 2',
      );
      final archive = _archive(
        calendars: [
          _archiveCalendar(
            name: 'Work',
            events: [_archiveEvent(uid: 'event-new', summary: 'New event')],
          ),
        ],
        taskLists: [
          _archiveTaskList(
            name: 'Inbox',
            tasks: [_archiveTask(uid: 'task-new', summary: 'New task')],
          ),
        ],
      );

      final result = await harness.service.importArchive(
        archive: archive,
        mode: FlowPlanV2ArchiveImportMode.replaceMatchingContainers,
      );

      expect(File(result.backupPath).existsSync(), isTrue);
      expect(result.removedEvents, 2);
      expect(result.createdEvents, 1);
      expect(result.updatedEvents, 0);
      expect(result.skippedEvents, 0);
      expect(result.removedTasks, 2);
      expect(result.createdTasks, 1);
      expect(result.updatedTasks, 0);
      expect(result.skippedTasks, 0);

      final events = await harness.events.getByCalendarId(calendarId);
      final tasks = await harness.tasks.getByTaskListIds([taskListId]);
      expect(events.map((event) => event.uid), ['event-new']);
      expect(tasks.map((task) => task.uid), ['task-new']);
    });

    test('importArchive creates missing containers with defaults and items',
        () async {
      final harness = await _createHarness();
      final archive = _archive(
        calendars: [
          _archiveCalendar(
            name: 'New calendar',
            colorHex: '#ABCDEF',
            defaultIsBlock: true,
            events: [
              _archiveEvent(uid: 'new-event', summary: 'Imported event'),
            ],
          ),
        ],
        taskLists: [
          _archiveTaskList(
            name: 'New tasks',
            colorHex: '#FEDCBA',
            defaultIsAutoScheduled: false,
            defaultReminderMinutesBefore: 25,
            tasks: [
              _archiveTask(uid: 'new-task', summary: 'Imported task'),
            ],
          ),
        ],
      );

      final preview = await harness.service.previewImport(
        archive: archive,
        mode: FlowPlanV2ArchiveImportMode.smartMerge,
      );
      expect(preview.createdContainers, 2);
      expect(preview.mergedContainers, 0);
      expect(preview.createdItems, 2);
      expect(preview.updatedItems, 0);
      expect(_container(preview, _eventKind).willCreateContainer, isTrue);
      expect(_container(preview, _taskListKind).willCreateContainer, isTrue);

      final result = await harness.service.importArchive(
        archive: archive,
        mode: FlowPlanV2ArchiveImportMode.smartMerge,
        sourcePath: 'new-containers.flowplanv2.json',
      );

      expect(File(result.backupPath).existsSync(), isTrue);
      expect(result.createdCalendars, 1);
      expect(result.mergedCalendars, 0);
      expect(result.createdEvents, 1);
      expect(result.updatedEvents, 0);
      expect(result.skippedEvents, 0);
      expect(result.createdTaskLists, 1);
      expect(result.mergedTaskLists, 0);
      expect(result.createdTasks, 1);
      expect(result.updatedTasks, 0);
      expect(result.skippedTasks, 0);

      final calendars = await harness.books.getEventCalendarsBySource('local');
      final calendar = calendars.singleWhere(
        (calendar) => calendar.name == 'New calendar',
      );
      final calendarDefaults =
          await harness.books.getEventCalendarDefaults(calendar.id);
      final events = await harness.events.getByCalendarId(calendar.id);
      expect(calendar.colorHex, '#ABCDEF');
      expect(calendar.source, 'local');
      expect(calendar.syncUrl, null);
      expect(calendarDefaults.defaultIsBlock, isTrue);
      expect(events, hasLength(1));
      expect(events.single.uid, 'new-event');
      expect(events.single.summary, 'Imported event');
      expect(events.single.source, 'local');
      expect(events.single.eventCalendarId, calendar.id);

      final taskLists = await harness.books.getAllTaskLists();
      final taskList = taskLists.singleWhere(
        (taskList) => taskList.name == 'New tasks',
      );
      final taskDefaults = await harness.books.getTaskListDefaults(taskList.id);
      final tasks = await harness.tasks.getByTaskListIds([taskList.id]);
      expect(taskList.colorHex, '#FEDCBA');
      expect(taskList.isArchived, isFalse);
      expect(taskDefaults.defaultIsAutoScheduled, isFalse);
      expect(taskDefaults.defaultReminderMinutesBefore, 25);
      expect(tasks, hasLength(1));
      expect(tasks.single.uid, 'new-task');
      expect(tasks.single.summary, 'Imported task');
      expect(tasks.single.taskListId, taskList.id);
    });

    test('archive round trip preserves archived task list state', () async {
      final source = await _createHarness();
      final archivedTaskListId = await source.createTaskList(
        name: 'Archived backlog',
        isArchived: true,
      );

      final archive = await source.service.buildArchive(
        calendarIds: const [],
        taskListIds: [archivedTaskListId],
      );
      expect(archive.taskLists.single.isArchived, isTrue);
      await source.db.close();

      final target = await _createHarness();
      final result = await target.service.importArchive(
        archive: archive,
        mode: FlowPlanV2ArchiveImportMode.smartMerge,
      );

      expect(result.createdTaskLists, 1);
      final importedTaskList = (await target.books.getArchivedTaskLists())
          .singleWhere((taskList) => taskList.name == 'Archived backlog');
      expect(importedTaskList.isArchived, isTrue);
    });

    test('importArchive imports tasks before archiving imported task lists',
        () async {
      final harness = await _createHarness();
      final archive = _archive(
        calendars: const [],
        taskLists: [
          _archiveTaskList(
            name: 'Archived backlog',
            isArchived: true,
            tasks: [
              _archiveTask(uid: 'archived-task', summary: 'Archived task'),
            ],
          ),
        ],
      );

      final result = await harness.service.importArchive(
        archive: archive,
        mode: FlowPlanV2ArchiveImportMode.smartMerge,
      );

      expect(result.createdTaskLists, 1);
      expect(result.createdTasks, 1);
      final taskList = (await harness.books.getArchivedTaskLists())
          .singleWhere((taskList) => taskList.name == 'Archived backlog');
      expect(taskList.isArchived, isTrue);
      final tasks = await harness.tasks.getByTaskListIds([taskList.id]);
      expect(tasks.single.uid, 'archived-task');
      expect(tasks.single.summary, 'Archived task');
    });
  });
}

Future<_ArchiveHarness> _createHarness() async {
  final documentsDirectory = await setFakePathProviderDocumentsDirectory(
    'flowplanv2_archive_service_test_',
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
  return _ArchiveHarness(
    db: db,
    books: books,
    events: events,
    tasks: tasks,
    service: FlowPlanV2ArchiveService(
      database: db,
      calendarBooksRepository: books,
      eventRepository: events,
      taskRepository: tasks,
    ),
  );
}

class _ArchiveHarness {
  const _ArchiveHarness({
    required this.db,
    required this.books,
    required this.events,
    required this.tasks,
    required this.service,
  });

  final AppDatabase db;
  final CalendarBooksRepository books;
  final EventRepository events;
  final TaskRepository tasks;
  final FlowPlanV2ArchiveService service;

  Future<int> createCalendar({
    required String name,
    String colorHex = '#6B5EE4',
    String source = 'local',
    String? syncUrl,
  }) {
    return books.createEventCalendar(
      EventCalendarsCompanion.insert(
        name: name,
        colorHex: Value(colorHex),
        source: Value(source),
        syncUrl: Value(syncUrl),
        createdAt: _stamp,
      ),
      audit: false,
    );
  }

  Future<int> createTaskList({
    required String name,
    String colorHex = '#0EA8A0',
    bool isArchived = false,
  }) {
    return books.createTaskList(
      TaskListsCompanion.insert(
        name: name,
        colorHex: Value(colorHex),
        isArchived: Value(isArchived),
        createdAt: _stamp,
      ),
      audit: false,
    );
  }

  Future<int> createEvent({
    required int calendarId,
    required String uid,
    required String summary,
    bool isBlock = false,
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
        isBlock: Value(isBlock),
      ),
      audit: false,
    );
  }

  Future<int> createTask({
    required int taskListId,
    required String uid,
    required String summary,
    int reminderMinutesBefore = 15,
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
        reminderMinutesBefore: Value(reminderMinutesBefore),
      ),
      audit: false,
    );
  }
}

FlowPlanV2ArchiveData _archive({
  required List<FlowPlanV2ArchiveCalendar> calendars,
  required List<FlowPlanV2ArchiveTaskList> taskLists,
}) {
  return FlowPlanV2ArchiveData(
    exportedAt: _stamp,
    calendars: calendars,
    taskLists: taskLists,
  );
}

FlowPlanV2ArchiveCalendar _archiveCalendar({
  required String name,
  String colorHex = '#6B5EE4',
  bool defaultIsBlock = false,
  required List<FlowPlanV2ArchiveEvent> events,
}) {
  return FlowPlanV2ArchiveCalendar(
    name: name,
    colorHex: colorHex,
    description: null,
    isVisible: true,
    isDefault: false,
    defaultIsBlock: defaultIsBlock,
    events: events,
  );
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
    source: 'imported',
    colorHex: '#123456',
    isBlock: true,
  );
}

FlowPlanV2ArchiveTaskList _archiveTaskList({
  required String name,
  String colorHex = '#0EA8A0',
  bool isArchived = false,
  bool defaultIsAutoScheduled = true,
  int defaultReminderMinutesBefore = 15,
  required List<FlowPlanV2ArchiveTask> tasks,
}) {
  return FlowPlanV2ArchiveTaskList(
    name: name,
    colorHex: colorHex,
    emoji: null,
    isVisible: true,
    isDefault: false,
    isArchived: isArchived,
    defaultIsAutoScheduled: defaultIsAutoScheduled,
    defaultReminderMinutesBefore: defaultReminderMinutesBefore,
    tasks: tasks,
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
    dtstart: _stamp.add(const Duration(days: 2)),
    due: _stamp.add(const Duration(days: 3)),
    completed: null,
    priority: 0,
    status: 'NEEDS-ACTION',
    percentComplete: 0,
    categories: '[]',
    rrule: null,
    durationMinutes: 90,
    isSplittable: false,
    priorityLocal: 1,
    isAutoScheduled: true,
    tagId: null,
    isLocked: false,
    reminderMinutesBefore: 30,
  );
}

FlowPlanV2ArchiveContainerPreview _container(
  FlowPlanV2ArchivePreview preview,
  String kindLabel,
) {
  return preview.containers.singleWhere(
    (container) => container.kindLabel == kindLabel,
  );
}

CalendarEvent _event(List<CalendarEvent> events, String uid) {
  return events.singleWhere((event) => event.uid == uid);
}

TaskItem _task(List<TaskItem> tasks, String uid) {
  return tasks.singleWhere((task) => task.uid == uid);
}
