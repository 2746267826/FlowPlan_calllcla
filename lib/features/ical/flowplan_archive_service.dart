import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../audit/data_operation_log_repository.dart';
import '../calendar/data/calendar_books_repository.dart';
import '../calendar/data/event_repository.dart';
import '../task/data/task_repository.dart';

enum FlowPlanArchiveImportMode {
  smartMerge,
  appendOnly,
  replaceMatchingContainers,
}

extension FlowPlanArchiveImportModeX on FlowPlanArchiveImportMode {
  String get label {
    switch (this) {
      case FlowPlanArchiveImportMode.smartMerge:
        return '\u667a\u80fd\u5408\u5e76';
      case FlowPlanArchiveImportMode.appendOnly:
        return '\u4ec5\u8ffd\u52a0';
      case FlowPlanArchiveImportMode.replaceMatchingContainers:
        return '\u66ff\u6362\u540c\u540d\u5bb9\u5668\u5185\u5bb9';
    }
  }

  String get description {
    switch (this) {
      case FlowPlanArchiveImportMode.smartMerge:
        return '\u540c\u540d\u65e5\u5386\u672c / \u4efb\u52a1\u672c\u4f1a\u5408\u5e76\uff1b\u540c UID \u9879\u76ee\u4f1a\u66f4\u65b0\uff0c\u5176\u4f59\u9879\u76ee\u65b0\u589e\u3002';
      case FlowPlanArchiveImportMode.appendOnly:
        return '\u4e0d\u4f1a\u6539\u5199\u5df2\u6709\u9879\u76ee\uff1b\u540c\u540d\u5bb9\u5668\u5185\u5df2\u5b58\u5728\u7684 UID \u4f1a\u8df3\u8fc7\uff0c\u53ea\u8ffd\u52a0\u65b0\u9879\u76ee\u3002';
      case FlowPlanArchiveImportMode.replaceMatchingContainers:
        return '\u540c\u540d\u5bb9\u5668\u4f1a\u5148\u6e05\u7a7a\u5176\u5185\u90e8\u9879\u76ee\uff0c\u518d\u5bfc\u5165\u5f52\u6863\u5185\u5bb9\uff1b\u5176\u4ed6\u5bb9\u5668\u4e0d\u53d7\u5f71\u54cd\u3002';
    }
  }
}

class FlowPlanArchiveData {
  const FlowPlanArchiveData({
    required this.exportedAt,
    required this.calendars,
    required this.taskLists,
  });

  static const schema = 'flowplan.container_archive.v1';
  static const version = 1;

  final DateTime exportedAt;
  final List<FlowPlanArchiveCalendar> calendars;
  final List<FlowPlanArchiveTaskList> taskLists;

  factory FlowPlanArchiveData.fromJsonString(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('\u0046\u006c\u006f\u0077\u0050\u006c\u0061\u006e \u7ed3\u6784\u5316\u5f52\u6863\u683c\u5f0f\u65e0\u6548\u3002');
    }
    return FlowPlanArchiveData.fromJson(decoded);
  }

  factory FlowPlanArchiveData.fromJson(Map<String, dynamic> json) {
    if (json['schema'] != schema) {
      throw const FormatException('\u8fd9\u4e0d\u662f FlowPlan \u7ed3\u6784\u5316\u5bb9\u5668\u5f52\u6863\u6587\u4ef6\u3002');
    }

    return FlowPlanArchiveData(
      exportedAt: _readDateTime(json['exported_at']) ?? DateTime.now(),
      calendars: _readObjectList(json['calendars'])
          .map(FlowPlanArchiveCalendar.fromJson)
          .toList(growable: false),
      taskLists: _readObjectList(json['task_lists'])
          .map(FlowPlanArchiveTaskList.fromJson)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schema': schema,
      'version': version,
      'exported_at': exportedAt.toIso8601String(),
      'calendars': calendars.map((calendar) => calendar.toJson()).toList(),
      'task_lists': taskLists.map((taskList) => taskList.toJson()).toList(),
    };
  }

  String toPrettyJson() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }
}

class FlowPlanArchiveCalendar {
  const FlowPlanArchiveCalendar({
    required this.name,
    required this.colorHex,
    required this.description,
    required this.isVisible,
    required this.isDefault,
    required this.defaultIsBlock,
    required this.events,
  });

  final String name;
  final String colorHex;
  final String? description;
  final bool isVisible;
  final bool isDefault;
  final bool defaultIsBlock;
  final List<FlowPlanArchiveEvent> events;

  factory FlowPlanArchiveCalendar.fromEntity({
    required EventCalendar calendar,
    required EventCalendarDefaults defaults,
    required List<CalendarEvent> events,
  }) {
    return FlowPlanArchiveCalendar(
      name: calendar.name,
      colorHex: calendar.colorHex,
      description: calendar.description,
      isVisible: calendar.isVisible,
      isDefault: calendar.isDefault,
      defaultIsBlock: defaults.defaultIsBlock,
      events: events.map(FlowPlanArchiveEvent.fromEntity).toList(growable: false),
    );
  }

  factory FlowPlanArchiveCalendar.fromJson(Map<String, dynamic> json) {
    return FlowPlanArchiveCalendar(
      name: _readString(json['name'], fallback: '\u672a\u547d\u540d\u65e5\u5386\u672c'),
      colorHex: _readString(json['color_hex'], fallback: '#6B5EE4'),
      description: _readNullableString(json['description']),
      isVisible: _readBool(json['is_visible'], fallback: true),
      isDefault: _readBool(json['is_default'], fallback: false),
      defaultIsBlock: _readBool(json['default_is_block'], fallback: false),
      events: _readObjectList(json['events'])
          .map(FlowPlanArchiveEvent.fromJson)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'color_hex': colorHex,
      'description': description,
      'is_visible': isVisible,
      'is_default': isDefault,
      'default_is_block': defaultIsBlock,
      'events': events.map((event) => event.toJson()).toList(),
    };
  }
}

class FlowPlanArchiveEvent {
  const FlowPlanArchiveEvent({
    required this.uid,
    required this.dtstamp,
    required this.summary,
    required this.description,
    required this.location,
    required this.dtstart,
    required this.dtend,
    required this.rrule,
    required this.status,
    required this.transp,
    required this.source,
    required this.colorHex,
    required this.isBlock,
  });

  final String uid;
  final DateTime dtstamp;
  final String summary;
  final String? description;
  final String? location;
  final DateTime dtstart;
  final DateTime? dtend;
  final String? rrule;
  final String status;
  final String transp;
  final String source;
  final String colorHex;
  final bool isBlock;

  factory FlowPlanArchiveEvent.fromEntity(CalendarEvent event) {
    return FlowPlanArchiveEvent(
      uid: event.uid,
      dtstamp: event.dtstamp,
      summary: event.summary,
      description: event.description,
      location: event.location,
      dtstart: event.dtstart,
      dtend: event.dtend,
      rrule: event.rrule,
      status: event.status,
      transp: event.transp,
      source: event.source,
      colorHex: event.colorHex,
      isBlock: event.isBlock,
    );
  }

  factory FlowPlanArchiveEvent.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return FlowPlanArchiveEvent(
      uid: _readString(json['uid'], fallback: 'flowplan-import-${now.microsecondsSinceEpoch}'),
      dtstamp: _readDateTime(json['dtstamp']) ?? now,
      summary: _readString(json['summary'], fallback: '\u672a\u547d\u540d\u65e5\u7a0b'),
      description: _readNullableString(json['description']),
      location: _readNullableString(json['location']),
      dtstart: _readDateTime(json['dtstart']) ?? now,
      dtend: _readDateTime(json['dtend']),
      rrule: _readNullableString(json['rrule']),
      status: _readString(json['status'], fallback: 'CONFIRMED'),
      transp: _readString(json['transp'], fallback: 'OPAQUE'),
      source: _readString(json['source'], fallback: 'local'),
      colorHex: _readString(json['color_hex'], fallback: '#6B5EE4'),
      isBlock: _readBool(json['is_block'], fallback: false),
    );
  }

  CalendarEventsCompanion toCompanion({
    required int eventCalendarId,
    int? id,
  }) {
    return CalendarEventsCompanion(
      id: id == null ? const Value.absent() : Value(id),
      uid: Value(uid),
      dtstamp: Value(dtstamp),
      summary: Value(summary),
      description: Value(description),
      location: Value(location),
      dtstart: Value(dtstart),
      dtend: Value(dtend),
      rrule: Value(rrule),
      status: Value(status),
      transp: Value(transp),
      source: const Value('local'),
      eventCalendarId: Value(eventCalendarId),
      colorHex: Value(colorHex),
      isBlock: Value(isBlock),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'dtstamp': dtstamp.toIso8601String(),
      'summary': summary,
      'description': description,
      'location': location,
      'dtstart': dtstart.toIso8601String(),
      'dtend': dtend?.toIso8601String(),
      'rrule': rrule,
      'status': status,
      'transp': transp,
      'source': source,
      'color_hex': colorHex,
      'is_block': isBlock,
    };
  }
}

class FlowPlanArchiveTaskList {
  const FlowPlanArchiveTaskList({
    required this.name,
    required this.colorHex,
    required this.emoji,
    required this.isVisible,
    required this.isDefault,
    required this.isArchived,
    required this.defaultIsAutoScheduled,
    required this.defaultReminderMinutesBefore,
    required this.tasks,
  });

  final String name;
  final String colorHex;
  final String? emoji;
  final bool isVisible;
  final bool isDefault;
  final bool isArchived;
  final bool defaultIsAutoScheduled;
  final int defaultReminderMinutesBefore;
  final List<FlowPlanArchiveTask> tasks;

  factory FlowPlanArchiveTaskList.fromEntity({
    required TaskList taskList,
    required TaskListDefaults defaults,
    required List<TaskItem> tasks,
  }) {
    return FlowPlanArchiveTaskList(
      name: taskList.name,
      colorHex: taskList.colorHex,
      emoji: taskList.emoji,
      isVisible: taskList.isVisible,
      isDefault: taskList.isDefault,
      isArchived: taskList.isArchived,
      defaultIsAutoScheduled: defaults.defaultIsAutoScheduled,
      defaultReminderMinutesBefore: defaults.defaultReminderMinutesBefore,
      tasks: tasks.map(FlowPlanArchiveTask.fromEntity).toList(growable: false),
    );
  }

  factory FlowPlanArchiveTaskList.fromJson(Map<String, dynamic> json) {
    return FlowPlanArchiveTaskList(
      name: _readString(json['name'], fallback: '\u672a\u547d\u540d\u4efb\u52a1\u672c'),
      colorHex: _readString(json['color_hex'], fallback: '#0EA8A0'),
      emoji: _readNullableString(json['emoji']),
      isVisible: _readBool(json['is_visible'], fallback: true),
      isDefault: _readBool(json['is_default'], fallback: false),
      isArchived: _readBool(json['is_archived'], fallback: false),
      defaultIsAutoScheduled: _readBool(
        json['default_is_auto_scheduled'],
        fallback: true,
      ),
      defaultReminderMinutesBefore: _readInt(
        json['default_reminder_minutes_before'],
        fallback: 15,
      ),
      tasks: _readObjectList(json['tasks'])
          .map(FlowPlanArchiveTask.fromJson)
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'color_hex': colorHex,
      'emoji': emoji,
      'is_visible': isVisible,
      'is_default': isDefault,
      'is_archived': isArchived,
      'default_is_auto_scheduled': defaultIsAutoScheduled,
      'default_reminder_minutes_before': defaultReminderMinutesBefore,
      'tasks': tasks.map((task) => task.toJson()).toList(),
    };
  }
}

class FlowPlanArchiveTask {
  const FlowPlanArchiveTask({
    required this.uid,
    required this.dtstamp,
    required this.summary,
    required this.description,
    required this.dtstart,
    required this.due,
    required this.completed,
    required this.priority,
    required this.status,
    required this.percentComplete,
    required this.categories,
    required this.rrule,
    required this.durationMinutes,
    required this.isSplittable,
    required this.priorityLocal,
    required this.isAutoScheduled,
    required this.tagId,
    required this.isLocked,
    required this.reminderMinutesBefore,
  });

  final String uid;
  final DateTime dtstamp;
  final String summary;
  final String? description;
  final DateTime? dtstart;
  final DateTime? due;
  final DateTime? completed;
  final int priority;
  final String status;
  final int percentComplete;
  final String categories;
  final String? rrule;
  final int durationMinutes;
  final bool isSplittable;
  final int priorityLocal;
  final bool isAutoScheduled;
  final String? tagId;
  final bool isLocked;
  final int reminderMinutesBefore;

  factory FlowPlanArchiveTask.fromEntity(TaskItem task) {
    return FlowPlanArchiveTask(
      uid: task.uid,
      dtstamp: task.dtstamp,
      summary: task.summary,
      description: task.description,
      dtstart: task.dtstart,
      due: task.due,
      completed: task.completed,
      priority: task.priority,
      status: task.status,
      percentComplete: task.percentComplete,
      categories: task.categories,
      rrule: task.rrule,
      durationMinutes: task.durationMinutes,
      isSplittable: task.isSplittable,
      priorityLocal: task.priorityLocal,
      isAutoScheduled: task.isAutoScheduled,
      tagId: task.tagId,
      isLocked: task.isLocked,
      reminderMinutesBefore: task.reminderMinutesBefore,
    );
  }

  factory FlowPlanArchiveTask.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    return FlowPlanArchiveTask(
      uid: _readString(json['uid'], fallback: 'flowplan-task-import-${now.microsecondsSinceEpoch}'),
      dtstamp: _readDateTime(json['dtstamp']) ?? now,
      summary: _readString(json['summary'], fallback: '\u672a\u547d\u540d\u4efb\u52a1'),
      description: _readNullableString(json['description']),
      dtstart: _readDateTime(json['dtstart']),
      due: _readDateTime(json['due']),
      completed: _readDateTime(json['completed']),
      priority: _readInt(json['priority'], fallback: 0),
      status: _readString(json['status'], fallback: 'NEEDS-ACTION'),
      percentComplete: _readInt(json['percent_complete'], fallback: 0),
      categories: _readCategories(json['categories']),
      rrule: _readNullableString(json['rrule']),
      durationMinutes: _readInt(json['duration_minutes'], fallback: 60),
      isSplittable: _readBool(json['is_splittable'], fallback: false),
      priorityLocal: _readInt(json['priority_local'], fallback: 2),
      isAutoScheduled: _readBool(json['is_auto_scheduled'], fallback: true),
      tagId: _readNullableString(json['tag_id']),
      isLocked: _readBool(json['is_locked'], fallback: false),
      reminderMinutesBefore: _readInt(
        json['reminder_minutes_before'],
        fallback: 15,
      ),
    );
  }

  TaskItemsCompanion toCompanion({
    required int taskListId,
    int? id,
  }) {
    return TaskItemsCompanion(
      id: id == null ? const Value.absent() : Value(id),
      uid: Value(uid),
      dtstamp: Value(dtstamp),
      summary: Value(summary),
      description: Value(description),
      dtstart: Value(dtstart),
      due: Value(due),
      completed: Value(completed),
      priority: Value(priority),
      status: Value(status),
      percentComplete: Value(percentComplete),
      categories: Value(categories),
      rrule: Value(rrule),
      durationMinutes: Value(durationMinutes),
      isSplittable: Value(isSplittable),
      priorityLocal: Value(priorityLocal),
      isAutoScheduled: Value(isAutoScheduled),
      taskListId: Value(taskListId),
      tagId: Value(tagId),
      isLocked: Value(isLocked),
      reminderMinutesBefore: Value(reminderMinutesBefore),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'dtstamp': dtstamp.toIso8601String(),
      'summary': summary,
      'description': description,
      'dtstart': dtstart?.toIso8601String(),
      'due': due?.toIso8601String(),
      'completed': completed?.toIso8601String(),
      'priority': priority,
      'status': status,
      'percent_complete': percentComplete,
      'categories': _categoriesForJson(categories),
      'rrule': rrule,
      'duration_minutes': durationMinutes,
      'is_splittable': isSplittable,
      'priority_local': priorityLocal,
      'is_auto_scheduled': isAutoScheduled,
      'tag_id': tagId,
      'is_locked': isLocked,
      'reminder_minutes_before': reminderMinutesBefore,
    };
  }
}

class FlowPlanArchiveContainerPreview {
  const FlowPlanArchiveContainerPreview({
    required this.kindLabel,
    required this.name,
    required this.willCreateContainer,
    required this.createCount,
    required this.updateCount,
    required this.skipCount,
    required this.removeBeforeImportCount,
  });

  final String kindLabel;
  final String name;
  final bool willCreateContainer;
  final int createCount;
  final int updateCount;
  final int skipCount;
  final int removeBeforeImportCount;

  String get actionLabel => willCreateContainer ? '\u65b0\u5efa\u5bb9\u5668' : '\u5408\u5e76\u5230\u540c\u540d\u5bb9\u5668';
}

class FlowPlanArchivePreview {
  const FlowPlanArchivePreview({
    required this.mode,
    required this.containers,
  });

  final FlowPlanArchiveImportMode mode;
  final List<FlowPlanArchiveContainerPreview> containers;

  int get createdContainers =>
      containers.where((container) => container.willCreateContainer).length;
  int get mergedContainers => containers.length - createdContainers;
  int get createdItems =>
      containers.fold(0, (sum, container) => sum + container.createCount);
  int get updatedItems =>
      containers.fold(0, (sum, container) => sum + container.updateCount);
  int get skippedItems =>
      containers.fold(0, (sum, container) => sum + container.skipCount);
  int get removedBeforeImportItems => containers.fold(
        0,
        (sum, container) => sum + container.removeBeforeImportCount,
      );
}

class FlowPlanArchiveImportResult {
  const FlowPlanArchiveImportResult({
    required this.backupPath,
    required this.createdCalendars,
    required this.mergedCalendars,
    required this.createdTaskLists,
    required this.mergedTaskLists,
    required this.createdEvents,
    required this.updatedEvents,
    required this.skippedEvents,
    required this.removedEvents,
    required this.createdTasks,
    required this.updatedTasks,
    required this.skippedTasks,
    required this.removedTasks,
  });

  final String backupPath;
  final int createdCalendars;
  final int mergedCalendars;
  final int createdTaskLists;
  final int mergedTaskLists;
  final int createdEvents;
  final int updatedEvents;
  final int skippedEvents;
  final int removedEvents;
  final int createdTasks;
  final int updatedTasks;
  final int skippedTasks;
  final int removedTasks;
}

class FlowPlanArchiveService {
  const FlowPlanArchiveService({
    required AppDatabase database,
    required CalendarBooksRepository calendarBooksRepository,
    required EventRepository eventRepository,
    required TaskRepository taskRepository,
    this.operationLogRepository,
  })  : _db = database,
        _calendarBooksRepository = calendarBooksRepository,
        _eventRepository = eventRepository,
        _taskRepository = taskRepository;

  final AppDatabase _db;
  final CalendarBooksRepository _calendarBooksRepository;
  final EventRepository _eventRepository;
  final TaskRepository _taskRepository;
  final DataOperationLogRepository? operationLogRepository;

  Future<FlowPlanArchiveData> buildArchive({
    required Iterable<int> calendarIds,
    required Iterable<int> taskListIds,
  }) async {
    final selectedCalendarIds = calendarIds.toSet();
    final selectedTaskListIds = taskListIds.toSet();

    final localCalendars = (await _calendarBooksRepository.getAllEventCalendars())
        .where(
          (calendar) =>
              calendar.source == 'local' && selectedCalendarIds.contains(calendar.id),
        )
        .toList(growable: false);
    final allEvents = await _eventRepository.getByCalendarIds(
      localCalendars.map((calendar) => calendar.id),
    );
    final eventsByCalendarId = <int, List<CalendarEvent>>{};
    for (final event in allEvents) {
      final calendarId = event.eventCalendarId;
      if (calendarId == null) {
        continue;
      }
      eventsByCalendarId.putIfAbsent(calendarId, () => <CalendarEvent>[]).add(event);
    }

    final calendars = <FlowPlanArchiveCalendar>[];
    for (final calendar in localCalendars) {
      final defaults =
          await _calendarBooksRepository.getEventCalendarDefaults(calendar.id);
      calendars.add(
        FlowPlanArchiveCalendar.fromEntity(
          calendar: calendar,
          defaults: defaults,
          events: eventsByCalendarId[calendar.id] ?? const <CalendarEvent>[],
        ),
      );
    }

    final taskLists = (await _calendarBooksRepository.getAllTaskLists())
        .where((taskList) => selectedTaskListIds.contains(taskList.id))
        .toList(growable: false);
    final allTasks = await _taskRepository.getByTaskListIds(
      taskLists.map((taskList) => taskList.id),
    );
    final tasksByTaskListId = <int, List<TaskItem>>{};
    for (final task in allTasks) {
      final taskListId = task.taskListId;
      if (taskListId == null) {
        continue;
      }
      tasksByTaskListId.putIfAbsent(taskListId, () => <TaskItem>[]).add(task);
    }

    final archiveTaskLists = <FlowPlanArchiveTaskList>[];
    for (final taskList in taskLists) {
      final defaults = await _calendarBooksRepository.getTaskListDefaults(taskList.id);
      archiveTaskLists.add(
        FlowPlanArchiveTaskList.fromEntity(
          taskList: taskList,
          defaults: defaults,
          tasks: tasksByTaskListId[taskList.id] ?? const <TaskItem>[],
        ),
      );
    }

    return FlowPlanArchiveData(
      exportedAt: DateTime.now(),
      calendars: calendars,
      taskLists: archiveTaskLists,
    );
  }

  Future<FlowPlanArchivePreview> previewImport({
    required FlowPlanArchiveData archive,
    required FlowPlanArchiveImportMode mode,
  }) async {
    final containers = <FlowPlanArchiveContainerPreview>[];
    final localCalendars = await _calendarBooksRepository.getEventCalendarsBySource(
      'local',
    );
    final calendarsByName = {
      for (final calendar in localCalendars) _normalizeName(calendar.name): calendar,
    };

    for (final archiveCalendar in archive.calendars) {
      final existing = calendarsByName[_normalizeName(archiveCalendar.name)];
      final existingEvents = existing == null
          ? const <CalendarEvent>[]
          : await _eventRepository.getByCalendarId(existing.id);
      final existingByUid = {
        for (final event in existingEvents)
          if (event.uid.trim().isNotEmpty) event.uid.trim(): event,
      };

      var createCount = 0;
      var updateCount = 0;
      var skipCount = 0;
      final removeCount = existing == null ||
              mode != FlowPlanArchiveImportMode.replaceMatchingContainers
          ? 0
          : existingEvents.length;

      for (final event in archiveCalendar.events) {
        final exists = existingByUid.containsKey(event.uid.trim());
        if (mode == FlowPlanArchiveImportMode.replaceMatchingContainers) {
          createCount++;
        } else if (!exists) {
          createCount++;
        } else if (mode == FlowPlanArchiveImportMode.smartMerge) {
          updateCount++;
        } else {
          skipCount++;
        }
      }

      containers.add(
        FlowPlanArchiveContainerPreview(
          kindLabel: '\u65e5\u5386\u672c',
          name: archiveCalendar.name,
          willCreateContainer: existing == null,
          createCount: createCount,
          updateCount: updateCount,
          skipCount: skipCount,
          removeBeforeImportCount: removeCount,
        ),
      );
    }

    final taskLists = await _calendarBooksRepository.getAllTaskLists();
    final taskListsByName = {
      for (final taskList in taskLists) _normalizeName(taskList.name): taskList,
    };

    for (final archiveTaskList in archive.taskLists) {
      final existing = taskListsByName[_normalizeName(archiveTaskList.name)];
      final existingTasks = existing == null
          ? const <TaskItem>[]
          : await _taskRepository.getByTaskListIds([existing.id]);
      final existingByUid = {
        for (final task in existingTasks)
          if (task.uid.trim().isNotEmpty) task.uid.trim(): task,
      };

      var createCount = 0;
      var updateCount = 0;
      var skipCount = 0;
      final removeCount = existing == null ||
              mode != FlowPlanArchiveImportMode.replaceMatchingContainers
          ? 0
          : existingTasks.length;

      for (final task in archiveTaskList.tasks) {
        final exists = existingByUid.containsKey(task.uid.trim());
        if (mode == FlowPlanArchiveImportMode.replaceMatchingContainers) {
          createCount++;
        } else if (!exists) {
          createCount++;
        } else if (mode == FlowPlanArchiveImportMode.smartMerge) {
          updateCount++;
        } else {
          skipCount++;
        }
      }

      containers.add(
        FlowPlanArchiveContainerPreview(
          kindLabel: '\u4efb\u52a1\u672c',
          name: archiveTaskList.name,
          willCreateContainer: existing == null,
          createCount: createCount,
          updateCount: updateCount,
          skipCount: skipCount,
          removeBeforeImportCount: removeCount,
        ),
      );
    }

    return FlowPlanArchivePreview(
      mode: mode,
      containers: containers,
    );
  }

  Future<FlowPlanArchiveImportResult> importArchive({
    required FlowPlanArchiveData archive,
    required FlowPlanArchiveImportMode mode,
    String? sourcePath,
  }) async {
    final backupPath = await _createRollbackBackup();

    var createdCalendars = 0;
    var mergedCalendars = 0;
    var createdTaskLists = 0;
    var mergedTaskLists = 0;
    var createdEvents = 0;
    var updatedEvents = 0;
    var skippedEvents = 0;
    var removedEvents = 0;
    var createdTasks = 0;
    var updatedTasks = 0;
    var skippedTasks = 0;
    var removedTasks = 0;

    await _db.transaction(() async {
      final calendarsByName = {
        for (final calendar
            in await _calendarBooksRepository.getEventCalendarsBySource('local'))
          _normalizeName(calendar.name): calendar,
      };

      for (final archiveCalendar in archive.calendars) {
        final normalizedName = _normalizeName(archiveCalendar.name);
        var target = calendarsByName[normalizedName];
        if (target == null) {
          final id = await _calendarBooksRepository.createEventCalendar(
            EventCalendarsCompanion.insert(
              name: archiveCalendar.name,
              colorHex: Value(archiveCalendar.colorHex),
              description: Value(archiveCalendar.description),
              isVisible: Value(archiveCalendar.isVisible),
              isDefault: Value(archiveCalendar.isDefault),
              source: const Value('local'),
              syncUrl: const Value<String?>(null),
              createdAt: DateTime.now(),
            ),
            audit: false,
          );
          target = await _calendarBooksRepository.getEventCalendarById(id);
          createdCalendars++;
        } else {
          if (mode != FlowPlanArchiveImportMode.appendOnly) {
            await _calendarBooksRepository.updateEventCalendar(
              EventCalendarsCompanion(
                id: Value(target.id),
                name: Value(archiveCalendar.name),
                colorHex: Value(archiveCalendar.colorHex),
                description: Value(archiveCalendar.description),
                isVisible: Value(archiveCalendar.isVisible),
                isDefault: Value(target.isDefault),
                source: const Value('local'),
                syncUrl: const Value<String?>(null),
                createdAt: Value(target.createdAt),
              ),
              audit: false,
            );
            target = await _calendarBooksRepository.getEventCalendarById(target.id);
          }
          mergedCalendars++;
        }

        if (target == null) {
          continue;
        }
        calendarsByName[normalizedName] = target;
        if (mode != FlowPlanArchiveImportMode.appendOnly) {
          await _calendarBooksRepository.saveEventCalendarDefaults(
            id: target.id,
            defaultIsBlock: archiveCalendar.defaultIsBlock,
            audit: false,
          );
        }

        if (mode == FlowPlanArchiveImportMode.replaceMatchingContainers) {
          final deletedEvents =
              await _eventRepository.deleteByCalendarId(target.id);
          removedEvents = removedEvents + deletedEvents;
        }

        final existingEvents =
            mode == FlowPlanArchiveImportMode.replaceMatchingContainers
                ? const <CalendarEvent>[]
                : await _eventRepository.getByCalendarId(target.id);
        final existingByUid = {
          for (final event in existingEvents)
            if (event.uid.trim().isNotEmpty) event.uid.trim(): event.id,
        };

        for (final event in archiveCalendar.events) {
          final existingId = existingByUid[event.uid.trim()];
          if (existingId != null) {
            if (mode == FlowPlanArchiveImportMode.smartMerge) {
              await _eventRepository.update(
                event.toCompanion(
                  eventCalendarId: target.id,
                  id: existingId,
                ),
                audit: false,
              );
              updatedEvents++;
            } else {
              skippedEvents++;
            }
            continue;
          }

          final id = await _eventRepository.create(
            event.toCompanion(eventCalendarId: target.id),
            audit: false,
          );
          if (event.uid.trim().isNotEmpty) {
            existingByUid[event.uid.trim()] = id;
          }
          createdEvents++;
        }
      }

      final taskListsByName = {
        for (final taskList in await _calendarBooksRepository.getAllTaskLists())
          _normalizeName(taskList.name): taskList,
      };

      for (final archiveTaskList in archive.taskLists) {
        final normalizedName = _normalizeName(archiveTaskList.name);
        var target = taskListsByName[normalizedName];
        if (target == null) {
          final id = await _calendarBooksRepository.createTaskList(
            TaskListsCompanion.insert(
              name: archiveTaskList.name,
              colorHex: Value(archiveTaskList.colorHex),
              emoji: Value(archiveTaskList.emoji),
              isVisible: Value(archiveTaskList.isVisible),
              isDefault: Value(archiveTaskList.isDefault),
              isArchived: const Value(false),
              createdAt: DateTime.now(),
            ),
            audit: false,
          );
          target = await _calendarBooksRepository.getTaskListById(id);
          createdTaskLists++;
        } else {
          if (mode != FlowPlanArchiveImportMode.appendOnly) {
            await _calendarBooksRepository.updateTaskList(
              TaskListsCompanion(
                id: Value(target.id),
                name: Value(archiveTaskList.name),
                colorHex: Value(archiveTaskList.colorHex),
                emoji: Value(archiveTaskList.emoji),
                isVisible: Value(archiveTaskList.isVisible),
                isDefault: Value(target.isDefault),
                isArchived: const Value(false),
                createdAt: Value(target.createdAt),
              ),
              audit: false,
            );
            target = await _calendarBooksRepository.getTaskListById(target.id);
          }
          mergedTaskLists++;
        }

        if (target == null) {
          continue;
        }
        taskListsByName[normalizedName] = target;
        if (mode != FlowPlanArchiveImportMode.appendOnly) {
          await _calendarBooksRepository.saveTaskListDefaults(
            id: target.id,
            defaultIsAutoScheduled: archiveTaskList.defaultIsAutoScheduled,
            defaultReminderMinutesBefore:
                archiveTaskList.defaultReminderMinutesBefore,
            audit: false,
          );
        }

        if (mode == FlowPlanArchiveImportMode.replaceMatchingContainers) {
          final deletedTasks =
              await _taskRepository.deleteByTaskListId(target.id);
          removedTasks = removedTasks + deletedTasks;
        }

        final existingTasks =
            mode == FlowPlanArchiveImportMode.replaceMatchingContainers
                ? const <TaskItem>[]
                : await _taskRepository.getByTaskListIds([target.id]);
        final existingByUid = {
          for (final task in existingTasks)
            if (task.uid.trim().isNotEmpty) task.uid.trim(): task.id,
        };

        for (final task in archiveTaskList.tasks) {
          final existingId = existingByUid[task.uid.trim()];
          if (existingId != null) {
            if (mode == FlowPlanArchiveImportMode.smartMerge) {
              await _taskRepository.update(
                task.toCompanion(
                  taskListId: target.id,
                  id: existingId,
                ),
                audit: false,
              );
              updatedTasks++;
            } else {
              skippedTasks++;
            }
            continue;
          }

          final id = await _taskRepository.create(
            task.toCompanion(taskListId: target.id),
            audit: false,
          );
          if (task.uid.trim().isNotEmpty) {
            existingByUid[task.uid.trim()] = id;
          }
          createdTasks++;
        }
      }
    });

    final result = FlowPlanArchiveImportResult(
      backupPath: backupPath,
      createdCalendars: createdCalendars,
      mergedCalendars: mergedCalendars,
      createdTaskLists: createdTaskLists,
      mergedTaskLists: mergedTaskLists,
      createdEvents: createdEvents,
      updatedEvents: updatedEvents,
      skippedEvents: skippedEvents,
      removedEvents: removedEvents,
      createdTasks: createdTasks,
      updatedTasks: updatedTasks,
      skippedTasks: skippedTasks,
      removedTasks: removedTasks,
    );
    await operationLogRepository?.record(
      actor: 'user',
      action: 'import_structured_archive',
      entityType: 'flowplan_archive',
      summary: '\u5df2\u5bfc\u5165 FlowPlan \u7ed3\u6784\u5316\u5f52\u6863',
      metadata: <String, Object?>{
        'mode': mode.name,
        'source_path': sourcePath,
        'backup_path': backupPath,
        'archive_calendar_count': archive.calendars.length,
        'archive_task_list_count': archive.taskLists.length,
        'created_calendars': createdCalendars,
        'merged_calendars': mergedCalendars,
        'created_task_lists': createdTaskLists,
        'merged_task_lists': mergedTaskLists,
        'created_events': createdEvents,
        'updated_events': updatedEvents,
        'skipped_events': skippedEvents,
        'removed_events': removedEvents,
        'created_tasks': createdTasks,
        'updated_tasks': updatedTasks,
        'skipped_tasks': skippedTasks,
        'removed_tasks': removedTasks,
      },
    );
    return result;
  }

  Future<String> _createRollbackBackup() async {
    final databasePath = await _db.getDatabasePath();
    final folder = File(databasePath).parent;
    final now = DateTime.now();
    final fileName =
        'flowplan-before-structured-import-${_formatFileDateTime(now)}.db';
    final backupPath = '${folder.path}${Platform.pathSeparator}$fileName';
    await _db.exportToFile(backupPath);
    return backupPath;
  }
}

List<Map<String, dynamic>> _readObjectList(Object? raw) {
  if (raw is! List) {
    return const <Map<String, dynamic>>[];
  }
  return raw.whereType<Map<String, dynamic>>().toList(growable: false);
}

String _readString(Object? raw, {required String fallback}) {
  if (raw is! String) {
    return fallback;
  }
  final trimmed = raw.trim();
  return trimmed.isEmpty ? fallback : trimmed;
}

String? _readNullableString(Object? raw) {
  if (raw is! String) {
    return null;
  }
  final trimmed = raw.trim();
  return trimmed.isEmpty ? null : trimmed;
}

bool _readBool(Object? raw, {required bool fallback}) {
  if (raw is bool) {
    return raw;
  }
  if (raw is num) {
    return raw != 0;
  }
  if (raw is String) {
    switch (raw.trim().toLowerCase()) {
      case 'true':
      case '1':
      case 'yes':
      case 'on':
        return true;
      case 'false':
      case '0':
      case 'no':
      case 'off':
        return false;
    }
  }
  return fallback;
}

int _readInt(Object? raw, {required int fallback}) {
  if (raw is int) {
    return raw;
  }
  if (raw is num) {
    return raw.round();
  }
  if (raw is String) {
    return int.tryParse(raw.trim()) ?? fallback;
  }
  return fallback;
}

DateTime? _readDateTime(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw.trim());
}

String _readCategories(Object? raw) {
  if (raw is List) {
    return jsonEncode(raw);
  }
  if (raw is String && raw.trim().isNotEmpty) {
    return raw;
  }
  return '[]';
}

Object _categoriesForJson(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded;
    }
  } catch (_) {
    /* \u4fdd\u7559\u539f\u59cb\u5b57\u7b26\u4e32\uff0c\u907f\u514d\u5bfc\u51fa\u65f6\u4e22\u5931\u7528\u6237\u901a\u8fc7\u6570\u636e\u5e93\u624b\u52a8\u7ef4\u62a4\u7684\u5185\u5bb9\u3002 */ }
  return raw;
}

String _normalizeName(String value) => value.trim().toLowerCase();

String _formatFileDateTime(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  final second = value.second.toString().padLeft(2, '0');
  return '$year$month$day-$hour$minute$second';
}
