import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/ical/flowplanv2_archive_service.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_path_provider.dart';
import '../../test_support/test_database.dart';

final _stamp = DateTime.utc(2026, 6, 8, 9);

void main() {
  group('FlowPlanV2ArchiveService gap worker 07', () {
    test('task json keeps non-empty string categories as-is', () {
      final task = FlowPlanV2ArchiveTask.fromJson({
        'uid': 'string-categories',
        'dtstamp': '2026-06-08T09:00:00.000Z',
        'summary': 'String categories',
        'categories': 'legacy,manual',
      });

      expect(task.categories, 'legacy,manual');
      expect(task.toJson()['categories'], 'legacy,manual');
    });

    test(
        'appendOnly import unarchives matching archived task list when archive has tasks',
        () async {
      final harness = await _createHarness();
      final taskListId = await harness.createTaskList(
        name: 'Backlog',
        isArchived: true,
      );

      final result = await harness.service.importArchive(
        archive: FlowPlanV2ArchiveData(
          exportedAt: _stamp,
          calendars: const [],
          taskLists: [
            FlowPlanV2ArchiveTaskList(
              name: ' backlog ',
              colorHex: '#FFAA00',
              emoji: null,
              isVisible: false,
              isDefault: true,
              isArchived: true,
              defaultIsAutoScheduled: false,
              defaultReminderMinutesBefore: 30,
              tasks: [
                _archiveTask(
                  uid: 'new-archived-task',
                  summary: 'Imported into archived list',
                ),
              ],
            ),
          ],
        ),
        mode: FlowPlanV2ArchiveImportMode.appendOnly,
      );

      expect(File(result.backupPath).existsSync(), isTrue);
      expect(result.createdTaskLists, 0);
      expect(result.mergedTaskLists, 1);
      expect(result.createdTasks, 1);
      expect(result.skippedTasks, 0);

      final taskList = await harness.books.getTaskListById(taskListId);
      expect(taskList, isNotNull);
      expect(taskList!.isArchived, isTrue);
      expect(taskList.isVisible, isFalse);
      expect(taskList.isDefault, isFalse);
      expect(taskList.colorHex, '#0EA8A0');

      final defaults = await harness.books.getTaskListDefaults(taskListId);
      expect(defaults.defaultIsAutoScheduled, isTrue);
      expect(defaults.defaultReminderMinutesBefore, 15);

      final tasks = await harness.tasks.getByTaskListIds([taskListId]);
      expect(
        tasks.map((task) => task.uid),
        ['new-archived-task'],
      );
      expect(
        tasks.singleWhere((task) => task.uid == 'new-archived-task').summary,
        'Imported into archived list',
      );
    });
  });
}

Future<_ArchiveHarness> _createHarness() async {
  final documentsDirectory = await setFakePathProviderDocumentsDirectory(
    'ical_services_gap_worker_07_',
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
    required this.tasks,
    required this.service,
  });

  final AppDatabase db;
  final CalendarBooksRepository books;
  final TaskRepository tasks;
  final FlowPlanV2ArchiveService service;

  Future<int> createTaskList({
    required String name,
    bool isArchived = false,
  }) {
    return books.createTaskList(
      TaskListsCompanion.insert(
        name: name,
        colorHex: const Value('#0EA8A0'),
        isVisible: const Value(false),
        isDefault: const Value(false),
        isArchived: Value(isArchived),
        createdAt: _stamp,
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
