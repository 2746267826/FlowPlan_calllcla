import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../audit/data_operation_log_repository.dart';
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
  final DataOperationLogRepository? _operationLogRepository;
  CalendarBooksRepository(this._db, [this._operationLogRepository]);

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

  Future<int> createEventCalendar(
    EventCalendarsCompanion companion, {
    bool audit = true,
    String actor = 'user',
    String action = 'create',
    String? summary,
    Object? metadata,
  }) async {
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

    if (audit) {
      final created = await getEventCalendarById(id);
      if (created != null) {
        await _recordContainerOperation(
          actor: actor,
          action: action,
          entityType: 'event_calendar',
          entityId: created.id.toString(),
          summary: summary ?? '\u521b\u5efa\u65e5\u5386\u672c\u300c${created.name}\u300d',
          after: await _eventCalendarSnapshot(created),
          metadata: metadata,
        );
      }
    }

    return id;
  }

  Future<bool> updateEventCalendar(
    EventCalendarsCompanion companion, {
    bool audit = true,
    String actor = 'user',
    String action = 'update',
    String? summary,
    Object? metadata,
  }) async {
    final id = companion.id.present ? companion.id.value : null;
    final before = id == null ? null : await _eventCalendarSnapshotById(id);
    final updated = await _db.update(_db.eventCalendars).replace(companion);
    if (audit && updated && id != null) {
      final after = await _eventCalendarSnapshotById(id);
      final name = (after?['name'] as String?) ??
          (before?['name'] as String?) ??
          '\u672a\u547d\u540d\u65e5\u5386\u672c';
      await _recordContainerOperation(
        actor: actor,
        action: action,
        entityType: 'event_calendar',
        entityId: id.toString(),
        summary: summary ?? '\u66f4\u65b0\u65e5\u5386\u672c\u300c$name\u300d',
        before: before,
        after: after,
        metadata: metadata,
      );
    }
    return updated;
  }

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
    bool audit = true,
    String actor = 'user',
    String action = 'update_defaults',
    String? summary,
    Object? metadata,
  }) async {
    final before = audit ? await _eventCalendarSnapshotById(id) : null;
    await _db.setBoolSetting(
      _eventCalendarDefaultBlockKey(id),
      defaultIsBlock,
    );
    if (audit) {
      final after = await _eventCalendarSnapshotById(id);
      final name = (after?['name'] as String?) ??
          (before?['name'] as String?) ??
          '\u672a\u547d\u540d\u65e5\u5386\u672c';
      await _recordContainerOperation(
        actor: actor,
        action: action,
        entityType: 'event_calendar',
        entityId: id.toString(),
        summary: summary ?? '\u66f4\u65b0\u65e5\u5386\u672c\u300c$name\u300d\u9ed8\u8ba4\u89c4\u5219',
        before: before,
        after: after,
        metadata: metadata,
      );
    }
  }

  Future<void> setDefaultEventCalendar(
    int id, {
    bool audit = true,
    String actor = 'user',
    String action = 'set_default',
    String? summary,
    Object? metadata,
  }) async {
    final before = audit ? await _eventCalendarSnapshotById(id) : null;
    final calendar = await getEventCalendarById(id);
    if (calendar == null) {
      return;
    }
    if (calendar.source != 'local') {
      throw StateError('\u53ea\u6709\u672c\u5730\u65e5\u5386\u672c\u53ef\u4ee5\u8bbe\u4e3a\u9ed8\u8ba4\u65e5\u5386\u672c\u3002');
    }

    await _normalizeLocalEventCalendarDefault(preferredId: id);
    if (audit) {
      final after = await _eventCalendarSnapshotById(id);
      await _recordContainerOperation(
        actor: actor,
        action: action,
        entityType: 'event_calendar',
        entityId: id.toString(),
        summary: summary ?? '\u5c06\u65e5\u5386\u672c\u300c${calendar.name}\u300d\u8bbe\u4e3a\u9ed8\u8ba4',
        before: before,
        after: after,
        metadata: metadata,
      );
    }
  }

  Future<int> deleteEventCalendar(
    int id, {
    bool audit = true,
    String actor = 'user',
    String action = 'delete',
    String? summary,
    Object? metadata,
  }) async {
    final calendar = await getEventCalendarById(id);
    if (calendar == null) {
      return 0;
    }
    final before = audit ? await _eventCalendarSnapshot(calendar) : null;
    final eventCount = await countEventsInCalendar(id);

    final deleted = await _db.transaction(() async {
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
    if (audit && deleted > 0) {
      await _recordContainerOperation(
        actor: actor,
        action: action,
        entityType: 'event_calendar',
        entityId: id.toString(),
        summary: summary ?? '\u5220\u9664\u65e5\u5386\u672c\u300c${calendar.name}\u300d',
        before: before,
        metadata: <String, Object?>{
          'event_count': eventCount,
          'source': calendar.source,
          if (metadata != null) 'extra': metadata,
        },
      );
    }
    return deleted;
  }

  Future<void> toggleEventCalendarVisible(
    int id,
    bool visible, {
    bool audit = true,
    String actor = 'user',
    String action = 'toggle_visible',
    String? summary,
    Object? metadata,
  }) async {
    final before = audit ? await _eventCalendarSnapshotById(id) : null;
    await (_db.update(_db.eventCalendars)..where((c) => c.id.equals(id)))
        .write(EventCalendarsCompanion(isVisible: Value(visible)));
    if (audit) {
      final after = await _eventCalendarSnapshotById(id);
      final name = (after?['name'] as String?) ??
          (before?['name'] as String?) ??
          '\u672a\u547d\u540d\u65e5\u5386\u672c';
      await _recordContainerOperation(
        actor: actor,
        action: action,
        entityType: 'event_calendar',
        entityId: id.toString(),
        summary: summary ?? '${visible ? '\u663e\u793a' : '\u9690\u85cf'}\u65e5\u5386\u672c\u300c$name\u300d',
        before: before,
        after: after,
        metadata: metadata,
      );
    }
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
    bool audit = true,
    String actor = 'sync',
    String action = 'upsert_synced',
    Object? metadata,
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
        audit: audit,
        actor: actor,
        action: action,
        summary: '\u540c\u6b65\u63a5\u5165 Outlook \u65e5\u5386\u672c\u300c$name\u300d',
        metadata: <String, Object?>{
          'source': source,
          'remote_id': remoteId,
          if (metadata != null) 'extra': metadata,
        },
      );
    }

    final before = audit ? await _eventCalendarSnapshot(existing) : null;
    await (_db.update(_db.eventCalendars)..where((c) => c.id.equals(existing.id))).write(
      EventCalendarsCompanion(
        name: Value(name),
        colorHex: Value(colorHex),
        description: Value(description),
        source: Value(source),
        syncUrl: Value(remoteId),
      ),
    );
    if (audit) {
      final after = await _eventCalendarSnapshotById(existing.id);
      await _recordContainerOperation(
        actor: actor,
        action: action,
        entityType: 'event_calendar',
        entityId: existing.id.toString(),
        summary: '\u66f4\u65b0\u540c\u6b65\u65e5\u5386\u672c\u300c$name\u300d',
        before: before,
        after: after,
        metadata: <String, Object?>{
          'source': source,
          'remote_id': remoteId,
          if (metadata != null) 'extra': metadata,
        },
      );
    }

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

  Future<int> createTaskList(
    TaskListsCompanion companion, {
    bool audit = true,
    String actor = 'user',
    String action = 'create',
    String? summary,
    Object? metadata,
  }) async {
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

    if (audit) {
      final created = await getTaskListById(id);
      if (created != null) {
        await _recordContainerOperation(
          actor: actor,
          action: action,
          entityType: 'task_list',
          entityId: created.id.toString(),
          summary: summary ?? '\u521b\u5efa\u4efb\u52a1\u672c\u300c${created.name}\u300d',
          after: await _taskListSnapshot(created),
          metadata: metadata,
        );
      }
    }

    return id;
  }

  Future<bool> updateTaskList(
    TaskListsCompanion companion, {
    bool audit = true,
    String actor = 'user',
    String action = 'update',
    String? summary,
    Object? metadata,
  }) async {
    final id = companion.id.present ? companion.id.value : null;
    final before = id == null ? null : await _taskListSnapshotById(id);
    final updated = _db.update(_db.taskLists).replace(companion);
    final result = await updated;
    if (audit && result && id != null) {
      final after = await _taskListSnapshotById(id);
      final name = (after?['name'] as String?) ??
          (before?['name'] as String?) ??
          '\u672a\u547d\u540d\u4efb\u52a1\u672c';
      await _recordContainerOperation(
        actor: actor,
        action: action,
        entityType: 'task_list',
        entityId: id.toString(),
        summary: summary ?? '\u66f4\u65b0\u4efb\u52a1\u672c\u300c$name\u300d',
        before: before,
        after: after,
        metadata: metadata,
      );
    }
    return result;
  }

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
    bool audit = true,
    String actor = 'user',
    String action = 'update_defaults',
    String? summary,
    Object? metadata,
  }) async {
    final before = audit ? await _taskListSnapshotById(id) : null;
    await _db.setBoolSetting(
      _taskListDefaultAutoScheduledKey(id),
      defaultIsAutoScheduled,
    );
    await _db.setIntSetting(
      _taskListDefaultReminderKey(id),
      defaultReminderMinutesBefore,
    );
    if (audit) {
      final after = await _taskListSnapshotById(id);
      final name = (after?['name'] as String?) ??
          (before?['name'] as String?) ??
          '\u672a\u547d\u540d\u4efb\u52a1\u672c';
      await _recordContainerOperation(
        actor: actor,
        action: action,
        entityType: 'task_list',
        entityId: id.toString(),
        summary: summary ?? '\u66f4\u65b0\u4efb\u52a1\u672c\u300c$name\u300d\u9ed8\u8ba4\u89c4\u5219',
        before: before,
        after: after,
        metadata: metadata,
      );
    }
  }

  Future<void> setDefaultTaskList(
    int id, {
    bool audit = true,
    String actor = 'user',
    String action = 'set_default',
    String? summary,
    Object? metadata,
  }) async {
    final before = audit ? await _taskListSnapshotById(id) : null;
    final taskList = await getTaskListById(id);
    if (taskList == null) {
      return;
    }
    if (taskList.isArchived) {
      throw StateError('\u5df2\u5f52\u6863\u4efb\u52a1\u672c\u4e0d\u80fd\u8bbe\u4e3a\u9ed8\u8ba4\u4efb\u52a1\u672c\u3002');
    }

    await _normalizeActiveTaskListDefault(preferredId: id);
    if (audit) {
      final after = await _taskListSnapshotById(id);
      await _recordContainerOperation(
        actor: actor,
        action: action,
        entityType: 'task_list',
        entityId: id.toString(),
        summary: summary ?? '\u5c06\u4efb\u52a1\u672c\u300c${taskList.name}\u300d\u8bbe\u4e3a\u9ed8\u8ba4',
        before: before,
        after: after,
        metadata: metadata,
      );
    }
  }

  Future<void> archiveTaskList(
    int id, {
    bool audit = true,
    String actor = 'user',
    String action = 'archive',
    String? summary,
    Object? metadata,
  }) async {
    final existing = await (_db.select(_db.taskLists)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (existing == null || existing.isArchived) {
      return;
    }
    final before = audit ? await _taskListSnapshot(existing) : null;
    final taskCount = await countTasksInTaskList(id);

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
    if (audit) {
      final after = await _taskListSnapshotById(id);
      await _recordContainerOperation(
        actor: actor,
        action: action,
        entityType: 'task_list',
        entityId: id.toString(),
        summary: summary ?? '\u5f52\u6863\u4efb\u52a1\u672c\u300c${existing.name}\u300d',
        before: before,
        after: after,
        metadata: <String, Object?>{
          'task_count': taskCount,
          if (metadata != null) 'extra': metadata,
        },
      );
    }
  }

  Future<void> unarchiveTaskList(
    int id, {
    bool audit = true,
    String actor = 'user',
    String action = 'restore',
    String? summary,
    Object? metadata,
  }) async {
    final existing = await getTaskListById(id);
    if (existing == null || !existing.isArchived) {
      return;
    }
    final before = audit ? await _taskListSnapshot(existing) : null;

    await (_db.update(_db.taskLists)..where((t) => t.id.equals(id))).write(
      const TaskListsCompanion(
        isArchived: Value(false),
        isVisible: Value(true),
      ),
    );
    await _normalizeActiveTaskListDefault();
    if (audit) {
      final after = await _taskListSnapshotById(id);
      await _recordContainerOperation(
        actor: actor,
        action: action,
        entityType: 'task_list',
        entityId: id.toString(),
        summary: summary ?? '\u6062\u590d\u4efb\u52a1\u672c\u300c${existing.name}\u300d',
        before: before,
        after: after,
        metadata: metadata,
      );
    }
  }

  Future<int> deleteTaskList(
    int id, {
    bool audit = true,
    String actor = 'user',
    String action = 'delete',
    String? summary,
    Object? metadata,
  }) async {
    final existing = await getTaskListById(id);
    if (existing == null) {
      return 0;
    }
    final before = audit ? await _taskListSnapshot(existing) : null;
    final taskCount = await countTasksInTaskList(id);

    final deleted = await _db.transaction(() async {
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
    if (audit && deleted > 0) {
      await _recordContainerOperation(
        actor: actor,
        action: action,
        entityType: 'task_list',
        entityId: id.toString(),
        summary: summary ?? '\u5220\u9664\u4efb\u52a1\u672c\u300c${existing.name}\u300d',
        before: before,
        metadata: <String, Object?>{
          'task_count': taskCount,
          if (metadata != null) 'extra': metadata,
        },
      );
    }
    return deleted;
  }

  Future<void> toggleTaskListVisible(
    int id,
    bool visible, {
    bool audit = true,
    String actor = 'user',
    String action = 'toggle_visible',
    String? summary,
    Object? metadata,
  }) async {
    final before = audit ? await _taskListSnapshotById(id) : null;
    await (_db.update(_db.taskLists)..where((t) => t.id.equals(id)))
        .write(TaskListsCompanion(isVisible: Value(visible)));
    if (audit) {
      final after = await _taskListSnapshotById(id);
      final name = (after?['name'] as String?) ??
          (before?['name'] as String?) ??
          '\u672a\u547d\u540d\u4efb\u52a1\u672c';
      await _recordContainerOperation(
        actor: actor,
        action: action,
        entityType: 'task_list',
        entityId: id.toString(),
        summary: summary ?? '${visible ? '\u663e\u793a' : '\u9690\u85cf'}\u4efb\u52a1\u672c\u300c$name\u300d',
        before: before,
        after: after,
        metadata: metadata,
      );
    }
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

  Future<Map<String, Object?>?> _eventCalendarSnapshotById(int id) async {
    final calendar = await getEventCalendarById(id);
    if (calendar == null) {
      return null;
    }
    return _eventCalendarSnapshot(calendar);
  }

  Future<Map<String, Object?>> _eventCalendarSnapshot(
    EventCalendar calendar,
  ) async {
    final defaults = await getEventCalendarDefaults(calendar.id);
    return <String, Object?>{
      'id': calendar.id,
      'name': calendar.name,
      'color_hex': calendar.colorHex,
      'description': calendar.description,
      'source': calendar.source,
      'sync_url': calendar.syncUrl,
      'is_visible': calendar.isVisible,
      'is_default': calendar.isDefault,
      'default_is_block': defaults.defaultIsBlock,
    };
  }

  Future<Map<String, Object?>?> _taskListSnapshotById(int id) async {
    final taskList = await getTaskListById(id);
    if (taskList == null) {
      return null;
    }
    return _taskListSnapshot(taskList);
  }

  Future<Map<String, Object?>> _taskListSnapshot(TaskList taskList) async {
    final defaults = await getTaskListDefaults(taskList.id);
    return <String, Object?>{
      'id': taskList.id,
      'name': taskList.name,
      'color_hex': taskList.colorHex,
      'emoji': taskList.emoji,
      'is_visible': taskList.isVisible,
      'is_default': taskList.isDefault,
      'is_archived': taskList.isArchived,
      'default_is_auto_scheduled': defaults.defaultIsAutoScheduled,
      'default_reminder_minutes_before': defaults.defaultReminderMinutesBefore,
    };
  }

  Future<void> _recordContainerOperation({
    required String actor,
    required String action,
    required String entityType,
    required String entityId,
    required String summary,
    Object? before,
    Object? after,
    Object? metadata,
  }) async {
    final operationLogs = _operationLogRepository;
    if (operationLogs == null) {
      return;
    }
    await operationLogs.record(
      actor: actor,
      action: action,
      entityType: entityType,
      entityId: entityId,
      summary: summary,
      before: before,
      after: after,
      metadata: metadata,
    );
  }
}

