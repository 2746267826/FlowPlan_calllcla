import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

class CalendarBooksRepository {
  static const _defaultLocalCalendarName = '\u9ed8\u8ba4\u65e5\u5386';
  static const _defaultLocalCalendarColor = '#6B5EE4';
  static const _defaultTaskListName = '\u6536\u4ef6\u7bb1';
  static const _defaultTaskListColor = '#0EA8A0';
  static const _defaultTaskListEmoji = '\u6536';

  final AppDatabase _db;
  CalendarBooksRepository(this._db);

  Stream<List<EventCalendar>> watchAllEventCalendars() =>
      (_db.select(_db.eventCalendars)
            ..orderBy([(c) => OrderingTerm(expression: c.name)]))
          .watch();

  Future<List<EventCalendar>> getAllEventCalendars() =>
      _db.select(_db.eventCalendars).get();

  Future<List<EventCalendar>> getEventCalendarsBySource(String source) =>
      (_db.select(_db.eventCalendars)..where((c) => c.source.equals(source)))
          .get();

  Future<EventCalendar?> getEventCalendarById(int id) =>
      (_db.select(_db.eventCalendars)..where((c) => c.id.equals(id)))
          .getSingleOrNull();

  Future<int> createEventCalendar(EventCalendarsCompanion companion) =>
      _db.into(_db.eventCalendars).insert(companion);

  Future<bool> updateEventCalendar(EventCalendarsCompanion companion) =>
      _db.update(_db.eventCalendars).replace(companion);

  Future<int> deleteEventCalendar(int id) async {
    final calendar = await getEventCalendarById(id);
    if (calendar == null) {
      return 0;
    }

    return _db.transaction(() async {
      if (calendar.source == 'local') {
        final fallbackId = await getOrCreateWritableEventCalendarId(
          excludingId: id,
        );
        await (_db.update(_db.calendarEvents)
              ..where((e) => e.eventCalendarId.equals(id)))
            .write(
          CalendarEventsCompanion(
            eventCalendarId: Value(fallbackId),
          ),
        );
      } else {
        await (_db.delete(_db.calendarEvents)
              ..where((e) => e.eventCalendarId.equals(id)))
            .go();
      }

      return (_db.delete(_db.eventCalendars)..where((c) => c.id.equals(id)))
          .go();
    });
  }

  Future<void> toggleEventCalendarVisible(int id, bool visible) async {
    await (_db.update(_db.eventCalendars)..where((c) => c.id.equals(id)))
        .write(EventCalendarsCompanion(isVisible: Value(visible)));
  }

  Future<int> getOrCreateWritableEventCalendarId({
    int? excludingId,
  }) async {
    final query = _db.select(_db.eventCalendars)
      ..where((c) => c.source.equals('local'))
      ..orderBy([
        (c) => OrderingTerm(
              expression: c.isDefault,
              mode: OrderingMode.desc,
            ),
        (c) => OrderingTerm(expression: c.createdAt),
      ]);

    final calendars = (await query.get())
        .where((calendar) => excludingId == null || calendar.id != excludingId)
        .toList();
    if (calendars.isNotEmpty) {
      return calendars.first.id;
    }

    return createEventCalendar(
      EventCalendarsCompanion.insert(
        name: _defaultLocalCalendarName,
        colorHex: const Value(_defaultLocalCalendarColor),
        isDefault: const Value(true),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<int> upsertSyncedEventCalendar({
    required String source,
    required String remoteId,
    required String name,
    required String colorHex,
    String? description,
  }) async {
    final matches = await (_db.select(_db.eventCalendars)
          ..where((c) => c.source.equals(source) & c.syncUrl.equals(remoteId)))
        .get();

    final existing = matches.isNotEmpty ? matches.first : null;
    if (matches.length > 1) {
      final duplicateIds = matches.skip(1).map((calendar) => calendar.id).toList();
      if (duplicateIds.isNotEmpty) {
        await (_db.update(_db.calendarEvents)
              ..where((e) => e.eventCalendarId.isIn(duplicateIds)))
            .write(
          CalendarEventsCompanion(
            eventCalendarId: Value(existing!.id),
          ),
        );
        await (_db.delete(_db.eventCalendars)
              ..where((c) => c.id.isIn(duplicateIds)))
            .go();
      }
    }

    if (existing == null) {
      return createEventCalendar(
        EventCalendarsCompanion.insert(
          name: name,
          colorHex: Value(colorHex),
          description: Value(description),
          source: Value(source),
          syncUrl: Value(remoteId),
          createdAt: DateTime.now(),
        ),
      );
    }

    await (_db.update(_db.eventCalendars)..where((c) => c.id.equals(existing.id)))
        .write(
      EventCalendarsCompanion(
        name: Value(name),
        colorHex: Value(colorHex),
        description: Value(description),
        source: Value(source),
        syncUrl: Value(remoteId),
      ),
    );

    return existing.id;
  }

  Stream<List<TaskList>> watchAllTaskLists() => (_db.select(_db.taskLists)
        ..where((t) => t.isArchived.equals(false))
        ..orderBy([(t) => OrderingTerm(expression: t.name)]))
      .watch();

  Stream<List<TaskList>> watchArchivedTaskLists() => (_db.select(_db.taskLists)
        ..where((t) => t.isArchived.equals(true))
        ..orderBy([(t) => OrderingTerm(expression: t.name)]))
      .watch();

  Future<List<TaskList>> getAllTaskLists() =>
      (_db.select(_db.taskLists)..where((t) => t.isArchived.equals(false)))
          .get();

  Future<List<TaskList>> getArchivedTaskLists() =>
      (_db.select(_db.taskLists)..where((t) => t.isArchived.equals(true))).get();

  Future<TaskList?> getTaskListById(int id) =>
      (_db.select(_db.taskLists)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> createTaskList(TaskListsCompanion companion) =>
      _db.into(_db.taskLists).insert(companion);

  Future<bool> updateTaskList(TaskListsCompanion companion) =>
      _db.update(_db.taskLists).replace(companion);

  Future<void> archiveTaskList(int id) async {
    final existing = await (_db.select(_db.taskLists)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (existing == null || existing.isArchived) {
      return;
    }

    await _db.transaction(() async {
      final fallbackId = await getOrCreateActiveTaskListId(excludingId: id);
      await (_db.update(_db.taskItems)..where((t) => t.taskListId.equals(id)))
          .write(TaskItemsCompanion(taskListId: Value(fallbackId)));
      await (_db.update(_db.taskLists)..where((t) => t.id.equals(id))).write(
        const TaskListsCompanion(
          isArchived: Value(true),
          isVisible: Value(false),
        ),
      );
    });
  }

  Future<void> unarchiveTaskList(int id) async {
    final existing = await getTaskListById(id);
    if (existing == null || !existing.isArchived) {
      return;
    }

    await (_db.update(_db.taskLists)..where((t) => t.id.equals(id))).write(
      const TaskListsCompanion(
        isArchived: Value(false),
        isVisible: Value(true),
      ),
    );
  }

  Future<int> deleteTaskList(int id) async {
    final existing = await getTaskListById(id);
    if (existing == null) {
      return 0;
    }

    return _db.transaction(() async {
      final fallbackId = await getOrCreateActiveTaskListId(excludingId: id);
      await (_db.update(_db.taskItems)..where((t) => t.taskListId.equals(id)))
          .write(TaskItemsCompanion(taskListId: Value(fallbackId)));

      return (_db.delete(_db.taskLists)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<void> toggleTaskListVisible(int id, bool visible) async {
    await (_db.update(_db.taskLists)..where((t) => t.id.equals(id)))
        .write(TaskListsCompanion(isVisible: Value(visible)));
  }

  Future<int> getOrCreateActiveTaskListId({
    int? excludingId,
  }) async {
    final query = _db.select(_db.taskLists)
      ..where((t) => t.isArchived.equals(false))
      ..orderBy([
        (t) => OrderingTerm(
              expression: t.isDefault,
              mode: OrderingMode.desc,
            ),
        (t) => OrderingTerm(expression: t.createdAt),
      ]);

    final lists = (await query.get())
        .where((list) => excludingId == null || list.id != excludingId)
        .toList();
    if (lists.isNotEmpty) {
      return lists.first.id;
    }

    return createTaskList(
      TaskListsCompanion.insert(
        name: _defaultTaskListName,
        colorHex: const Value(_defaultTaskListColor),
        emoji: const Value(_defaultTaskListEmoji),
        isDefault: const Value(true),
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> ensureContainerIntegrity() async {
    await _db.transaction(() async {
      final fallbackEventCalendarId = await getOrCreateWritableEventCalendarId();
      final fallbackTaskListId = await getOrCreateActiveTaskListId();

      final validEventCalendarIds = (await getAllEventCalendars())
          .map((calendar) => calendar.id)
          .toSet();
      final validTaskListIds = (await (_db.select(_db.taskLists)
            ..where((t) => t.isArchived.equals(false)))
          .get())
          .map((list) => list.id)
          .toSet();

      final events = await _db.select(_db.calendarEvents).get();
      for (final event in events) {
        final calendarId = event.eventCalendarId;
        if (calendarId == null || !validEventCalendarIds.contains(calendarId)) {
          await (_db.update(_db.calendarEvents)
                ..where((e) => e.id.equals(event.id)))
              .write(
            CalendarEventsCompanion(
              eventCalendarId: Value(fallbackEventCalendarId),
            ),
          );
        }
      }

      final tasks = await _db.select(_db.taskItems).get();
      for (final task in tasks) {
        final currentTaskListId = task.taskListId;
        if (currentTaskListId == null ||
            !validTaskListIds.contains(currentTaskListId)) {
          await (_db.update(_db.taskItems)..where((t) => t.id.equals(task.id)))
              .write(
            TaskItemsCompanion(
              taskListId: Value(fallbackTaskListId),
            ),
          );
        }
      }
    });
  }
}
