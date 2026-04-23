import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../sync/outlook_sync_bindings_repository.dart';

class EventCalendarDefaults {
  const EventCalendarDefaults({
    required this.defaultIsBlock,
  });

  const EventCalendarDefaults.fallback()
      : defaultIsBlock = false;

  final bool defaultIsBlock;
}

class TaskListDefaults {
  const TaskListDefaults({
    required this.defaultIsAutoScheduled,
    required this.defaultReminderMinutesBefore,
  });

  const TaskListDefaults.fallback({
    int reminderMinutesBefore = 15,
  })  : defaultIsAutoScheduled = true,
        defaultReminderMinutesBefore = reminderMinutesBefore;

  final bool defaultIsAutoScheduled;
  final int defaultReminderMinutesBefore;
}

class CalendarBooksRepository {
  static const _defaultLocalCalendarName = '\u9ed8\u8ba4\u65e5\u5386';
  static const _defaultLocalCalendarColor = '#6B5EE4';
  static const _defaultTaskListName = '\u6536\u4ef6\u7bb1';
  static const _defaultTaskListColor = '#0EA8A0';
  static const _defaultTaskListEmoji = '\u6536';
  static const _eventCalendarDefaultBlockPrefix =
      'event_calendar.default_is_block.v1.';
  static const _taskListDefaultAutoScheduledPrefix =
      'task_list.default_auto_scheduled.v1.';
  static const _taskListDefaultReminderPrefix =
      'task_list.default_reminder_minutes.v1.';

  final AppDatabase _db;
  CalendarBooksRepository(this._db);

  String _eventCalendarDefaultBlockKey(int id) =>
      '$_eventCalendarDefaultBlockPrefix$id';

  String _taskListDefaultAutoScheduledKey(int id) =>
      '$_taskListDefaultAutoScheduledPrefix$id';

  String _taskListDefaultReminderKey(int id) =>
      '$_taskListDefaultReminderPrefix$id';

  Stream<List<EventCalendar>> watchAllEventCalendars() =>
      (_db.select(_db.eventCalendars)
            ..orderBy([
              (c) => OrderingTerm(
                    expression: c.isDefault,
                    mode: OrderingMode.desc,
                  ),
              (c) => OrderingTerm(expression: c.name),
            ]))
          .watch();

  Future<List<EventCalendar>> getAllEventCalendars() =>
      _db.select(_db.eventCalendars).get();

  Future<List<EventCalendar>> getEventCalendarsBySource(String source) =>
      (_db.select(_db.eventCalendars)..where((c) => c.source.equals(source)))
          .get();

  Future<EventCalendar?> getEventCalendarById(int id) =>
      (_db.select(_db.eventCalendars)..where((c) => c.id.equals(id)))
          .getSingleOrNull();

  Future<int> createEventCalendar(EventCalendarsCompanion companion) async {
    final source = companion.source.present ? companion.source.value : 'local';
    final requestedDefault =
        companion.isDefault.present ? companion.isDefault.value : false;
    final shouldNormalize = source == 'local';

    if (requestedDefault && source == 'local') {
      await (_db.update(_db.eventCalendars)
            ..where((c) => c.source.equals('local') & c.isDefault.equals(true)))
          .write(const EventCalendarsCompanion(isDefault: Value(false)));
    }

    final id = await _db.into(_db.eventCalendars).insert(
          companion.copyWith(
            isDefault: Value(source == 'local' ? requestedDefault : false),
          ),
        );

    if (shouldNormalize) {
      await _normalizeLocalEventCalendarDefault(
        preferredId: requestedDefault ? id : null,
      );
    }

    return id;
  }

  Future<bool> updateEventCalendar(EventCalendarsCompanion companion) =>
      _db.update(_db.eventCalendars).replace(companion);

  Future<int> countEventsInCalendar(int id) async {
    final countExpression = _db.calendarEvents.id.count();
    final query = _db.selectOnly(_db.calendarEvents)
      ..addColumns([countExpression])
      ..where(_db.calendarEvents.eventCalendarId.equals(id));
    final row = await query.getSingle();
    return row.read(countExpression) ?? 0;
  }

  Future<EventCalendarDefaults> getEventCalendarDefaults(int id) async {
    final defaultIsBlock = await _db.getBoolSetting(
      _eventCalendarDefaultBlockKey(id),
      defaultValue: false,
    );
    return EventCalendarDefaults(defaultIsBlock: defaultIsBlock);
  }

  Future<void> saveEventCalendarDefaults({
    required int id,
    required bool defaultIsBlock,
  }) async {
    await _db.setBoolSetting(
      _eventCalendarDefaultBlockKey(id),
      defaultIsBlock,
    );
  }

  Future<void> setDefaultEventCalendar(int id) async {
    final calendar = await getEventCalendarById(id);
    if (calendar == null) {
      return;
    }
    if (calendar.source != 'local') {
      throw StateError('只有本地日历本可以设为默认日历本。');
    }

    await _normalizeLocalEventCalendarDefault(preferredId: id);
  }

  Future<int> deleteEventCalendar(int id) async {
    final calendar = await getEventCalendarById(id);
    if (calendar == null) {
      return 0;
    }

    return _db.transaction(() async {
      int? fallbackId;
      if (calendar.source == 'local') {
        fallbackId = await getOrCreateWritableEventCalendarId(
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

      await _db.deleteSetting(_eventCalendarDefaultBlockKey(id));
      final deleted =
          await (_db.delete(_db.eventCalendars)..where((c) => c.id.equals(id)))
              .go();

      if (calendar.source == 'local' && fallbackId != null) {
        await _normalizeLocalEventCalendarDefault(preferredId: fallbackId);
      }

      return deleted;
    });
  }

  Future<void> toggleEventCalendarVisible(int id, bool visible) async {
    await (_db.update(_db.eventCalendars)..where((c) => c.id.equals(id)))
        .write(EventCalendarsCompanion(isVisible: Value(visible)));
  }

  Future<int> getOrCreateWritableEventCalendarId({
    int? excludingId,
  }) async {
    final calendars =
        await _getOrderedLocalEventCalendars(excludingId: excludingId);
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
        ..orderBy([
          (t) => OrderingTerm(
                expression: t.isDefault,
                mode: OrderingMode.desc,
              ),
          (t) => OrderingTerm(expression: t.name),
        ]))
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

  Future<int> createTaskList(TaskListsCompanion companion) async {
    final isArchived =
        companion.isArchived.present ? companion.isArchived.value : false;
    final requestedDefault =
        companion.isDefault.present ? companion.isDefault.value : false;

    if (requestedDefault && !isArchived) {
      await (_db.update(_db.taskLists)..where((t) => t.isDefault.equals(true)))
          .write(const TaskListsCompanion(isDefault: Value(false)));
    }

    final id = await _db.into(_db.taskLists).insert(
          companion.copyWith(
            isDefault: Value(!isArchived && requestedDefault),
          ),
        );

    if (!isArchived) {
      await _normalizeActiveTaskListDefault(
        preferredId: requestedDefault ? id : null,
      );
    }

    return id;
  }

  Future<bool> updateTaskList(TaskListsCompanion companion) =>
      _db.update(_db.taskLists).replace(companion);

  Future<int> countTasksInTaskList(int id) async {
    final countExpression = _db.taskItems.id.count();
    final query = _db.selectOnly(_db.taskItems)
      ..addColumns([countExpression])
      ..where(_db.taskItems.taskListId.equals(id));
    final row = await query.getSingle();
    return row.read(countExpression) ?? 0;
  }

  Future<TaskListDefaults> getTaskListDefaults(
    int id, {
    int fallbackReminderMinutes = 15,
  }) async {
    final defaultIsAutoScheduled = await _db.getBoolSetting(
      _taskListDefaultAutoScheduledKey(id),
      defaultValue: true,
    );
    final defaultReminderMinutesBefore = await _db.getIntSetting(
      _taskListDefaultReminderKey(id),
      defaultValue: fallbackReminderMinutes,
    );
    return TaskListDefaults(
      defaultIsAutoScheduled: defaultIsAutoScheduled,
      defaultReminderMinutesBefore: defaultReminderMinutesBefore,
    );
  }

  Future<void> saveTaskListDefaults({
    required int id,
    required bool defaultIsAutoScheduled,
    required int defaultReminderMinutesBefore,
  }) async {
    await _db.setBoolSetting(
      _taskListDefaultAutoScheduledKey(id),
      defaultIsAutoScheduled,
    );
    await _db.setIntSetting(
      _taskListDefaultReminderKey(id),
      defaultReminderMinutesBefore,
    );
  }

  Future<void> setDefaultTaskList(int id) async {
    final taskList = await getTaskListById(id);
    if (taskList == null) {
      return;
    }
    if (taskList.isArchived) {
      throw StateError('已归档任务本不能设为默认任务本。');
    }

    await _normalizeActiveTaskListDefault(preferredId: id);
  }

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
          isDefault: Value(false),
        ),
      );
      final bindingsRepo = OutlookSyncBindingsRepository(_db);
      await bindingsRepo.removeTaskListBinding(id);
      await _normalizeActiveTaskListDefault(
        preferredId: existing.isDefault ? fallbackId : null,
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
    await _normalizeActiveTaskListDefault();
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
      final bindingsRepo = OutlookSyncBindingsRepository(_db);
      await bindingsRepo.removeTaskListBinding(id);
      await _db.deleteSetting(_taskListDefaultAutoScheduledKey(id));
      await _db.deleteSetting(_taskListDefaultReminderKey(id));

      final deleted =
          await (_db.delete(_db.taskLists)..where((t) => t.id.equals(id))).go();
      await _normalizeActiveTaskListDefault(
        preferredId: existing.isDefault ? fallbackId : null,
      );
      return deleted;
    });
  }

  Future<void> toggleTaskListVisible(int id, bool visible) async {
    await (_db.update(_db.taskLists)..where((t) => t.id.equals(id)))
        .write(TaskListsCompanion(isVisible: Value(visible)));
  }

  Future<int> getOrCreateActiveTaskListId({
    int? excludingId,
  }) async {
    final lists = await _getOrderedActiveTaskLists(excludingId: excludingId);
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

      await _normalizeLocalEventCalendarDefault(preferredId: fallbackEventCalendarId);
      await _normalizeActiveTaskListDefault(preferredId: fallbackTaskListId);
    });
  }

  Future<List<EventCalendar>> _getOrderedLocalEventCalendars({
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

    final calendars = await query.get();
    if (excludingId == null) {
      return calendars;
    }
    return calendars.where((calendar) => calendar.id != excludingId).toList();
  }

  Future<void> _normalizeLocalEventCalendarDefault({
    int? preferredId,
  }) async {
    final calendars = await _getOrderedLocalEventCalendars();
    if (calendars.isEmpty) {
      return;
    }

    int targetId = calendars.first.id;
    if (preferredId != null) {
      for (final calendar in calendars) {
        if (calendar.id == preferredId) {
          targetId = preferredId;
          break;
        }
      }
    }

    await (_db.update(_db.eventCalendars)
          ..where((c) => c.source.equals('local') & c.isDefault.equals(true)))
        .write(const EventCalendarsCompanion(isDefault: Value(false)));
    await (_db.update(_db.eventCalendars)..where((c) => c.id.equals(targetId)))
        .write(const EventCalendarsCompanion(isDefault: Value(true)));
  }

  Future<List<TaskList>> _getOrderedActiveTaskLists({
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

    final lists = await query.get();
    if (excludingId == null) {
      return lists;
    }
    return lists.where((list) => list.id != excludingId).toList();
  }

  Future<void> _normalizeActiveTaskListDefault({
    int? preferredId,
  }) async {
    final lists = await _getOrderedActiveTaskLists();
    await (_db.update(_db.taskLists)..where((t) => t.isDefault.equals(true)))
        .write(const TaskListsCompanion(isDefault: Value(false)));
    if (lists.isEmpty) {
      return;
    }

    int targetId = lists.first.id;
    if (preferredId != null) {
      for (final list in lists) {
        if (list.id == preferredId) {
          targetId = preferredId;
          break;
        }
      }
    }

    await (_db.update(_db.taskLists)..where((t) => t.id.equals(targetId)))
        .write(const TaskListsCompanion(isDefault: Value(true)));
  }
}
