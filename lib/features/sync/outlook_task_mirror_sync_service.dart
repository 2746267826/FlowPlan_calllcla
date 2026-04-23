import 'dart:convert';

import '../../core/database/app_database.dart';
import '../calendar/data/calendar_books_repository.dart';
import '../task/data/task_repository.dart';
import 'ms_graph_service.dart';
import 'outlook_task_list_binding.dart';
import 'outlook_task_mirror_binding.dart';
import 'outlook_task_mirror_repository.dart';
import 'outlook_task_mirror_snapshot.dart';
import 'outlook_sync_bindings_repository.dart';

class OutlookTaskMirrorTaskListSummary {
  const OutlookTaskMirrorTaskListSummary({
    required this.localTaskListId,
    required this.taskListName,
    required this.remoteCalendarId,
    required this.remoteCalendarName,
    this.created = 0,
    this.updated = 0,
    this.deleted = 0,
    this.conflicted = 0,
  });

  final int localTaskListId;
  final String taskListName;
  final String remoteCalendarId;
  final String remoteCalendarName;
  final int created;
  final int updated;
  final int deleted;
  final int conflicted;

  int get changedCount => created + updated + deleted + conflicted;

  OutlookTaskMirrorTaskListSummary copyWith({
    int? localTaskListId,
    String? taskListName,
    String? remoteCalendarId,
    String? remoteCalendarName,
    int? created,
    int? updated,
    int? deleted,
    int? conflicted,
  }) {
    return OutlookTaskMirrorTaskListSummary(
      localTaskListId: localTaskListId ?? this.localTaskListId,
      taskListName: taskListName ?? this.taskListName,
      remoteCalendarId: remoteCalendarId ?? this.remoteCalendarId,
      remoteCalendarName: remoteCalendarName ?? this.remoteCalendarName,
      created: created ?? this.created,
      updated: updated ?? this.updated,
      deleted: deleted ?? this.deleted,
      conflicted: conflicted ?? this.conflicted,
    );
  }
}

class OutlookTaskMirrorSyncResult {
  const OutlookTaskMirrorSyncResult({
    this.created = 0,
    this.updated = 0,
    this.deleted = 0,
    this.conflicted = 0,
    this.taskListDetails = const <OutlookTaskMirrorTaskListSummary>[],
  });

  final int created;
  final int updated;
  final int deleted;
  final int conflicted;
  final List<OutlookTaskMirrorTaskListSummary> taskListDetails;

  int get changedCount => created + updated + deleted + conflicted;
}

class OutlookTaskMirrorSyncService {
  OutlookTaskMirrorSyncService({
    required this.graphService,
    required this.taskRepository,
    required this.calendarBooksRepository,
    required this.taskListBindingsRepository,
    required this.taskMirrorRepository,
  });

  final MsGraphService graphService;
  final TaskRepository taskRepository;
  final CalendarBooksRepository calendarBooksRepository;
  final OutlookSyncBindingsRepository taskListBindingsRepository;
  final OutlookTaskMirrorRepository taskMirrorRepository;

  Future<OutlookTaskMirrorSyncResult> cleanupStaleTaskMirrors() async {
    final taskListBindings =
        await taskListBindingsRepository.loadTaskListBindings();
    final taskLists = await calendarBooksRepository.getAllTaskLists();
    final taskListById = <int, TaskList>{
      for (final taskList in taskLists) taskList.id: taskList,
    };
    final mirrorBindings = await taskMirrorRepository.loadTaskMirrorBindings();
    final mirrorTaskIds = mirrorBindings.keys.toSet();
    final mirroredTasks = await taskRepository.getByIds(mirrorTaskIds);
    final mirroredTaskById = <int, TaskItem>{
      for (final task in mirroredTasks) task.id: task,
    };

    return _cleanupStaleMirrorBindings(
      taskListBindings: taskListBindings,
      taskListById: taskListById,
      mirrorBindings: mirrorBindings,
      mirroredTaskById: mirroredTaskById,
    );
  }

  Future<OutlookTaskMirrorSyncResult> syncBoundTaskMirrors() async {
    final taskListBindings =
        await taskListBindingsRepository.loadTaskListBindings();
    final taskLists = await calendarBooksRepository.getAllTaskLists();
    final taskListById = <int, TaskList>{
      for (final taskList in taskLists) taskList.id: taskList,
    };
    final mirrorBindings = await taskMirrorRepository.loadTaskMirrorBindings();
    final mirrorTaskIds = mirrorBindings.keys.toSet();

    final mirroredTasks = await taskRepository.getByIds(mirrorTaskIds);
    final mirroredTaskById = <int, TaskItem>{
      for (final task in mirroredTasks) task.id: task,
    };

    var created = 0;
    var updated = 0;
    var conflicted = 0;
    final cleanupResult = await _cleanupStaleMirrorBindings(
      taskListBindings: taskListBindings,
      taskListById: taskListById,
      mirrorBindings: mirrorBindings,
      mirroredTaskById: mirroredTaskById,
    );
    var deleted = cleanupResult.deleted;
    conflicted += cleanupResult.conflicted;
    final taskListDetailsById = <int, OutlookTaskMirrorTaskListSummary>{
      for (final detail in cleanupResult.taskListDetails)
        detail.localTaskListId: detail,
    };

    if (taskListBindings.isEmpty) {
      return OutlookTaskMirrorSyncResult(
        created: created,
        updated: updated,
        deleted: deleted,
        taskListDetails: _sortedTaskListDetails(taskListDetailsById),
      );
    }

    final boundTaskListIds = taskListBindings.keys.toSet();
    final boundTasks = await taskRepository.getByTaskListIds(boundTaskListIds);
    final activeMirrorBindings = await taskMirrorRepository.loadTaskMirrorBindings();

    for (final task in boundTasks) {
      final taskListId = task.taskListId;
      if (taskListId == null) {
        continue;
      }

      final taskListBinding = taskListBindings[taskListId];
      if (taskListBinding == null) {
        continue;
      }

      final taskListName =
          taskListById[taskListId]?.name ?? '\u4efb\u52a1\u672c';
      final snapshot = OutlookTaskMirrorSnapshot.fromTask(
        task: task,
        taskListName: taskListName,
      );
      final payload = _buildMirrorEventPayload(
        task: task,
        taskListName: taskListName,
        snapshot: snapshot,
      );
      final mirrorBinding = activeMirrorBindings[task.id];

      if (mirrorBinding == null) {
        final createdBinding = await _createRemoteMirror(
          task: task,
          taskListBinding: taskListBinding,
          payload: payload,
          snapshot: snapshot,
        );
        await taskMirrorRepository.saveTaskMirrorBinding(createdBinding);
        activeMirrorBindings[task.id] = createdBinding;
        created++;
        _recordTaskListChange(
          taskListDetailsById,
          localTaskListId: taskListId,
          taskListName: taskListName,
          remoteCalendarId: taskListBinding.remoteCalendarId,
          remoteCalendarName: taskListBinding.remoteCalendarName,
          createdDelta: 1,
        );
        continue;
      }

      final updatedBinding = await _updateOrRecreateRemoteMirror(
        task: task,
        taskListBinding: taskListBinding,
        mirrorBinding: mirrorBinding,
        payload: payload,
        snapshot: snapshot,
      );
      if (updatedBinding.conflicted) {
        conflicted++;
        _recordTaskListChange(
          taskListDetailsById,
          localTaskListId: taskListId,
          taskListName: taskListName,
          remoteCalendarId: taskListBinding.remoteCalendarId,
          remoteCalendarName: taskListBinding.remoteCalendarName,
          conflictedDelta: 1,
        );
      } else if (updatedBinding.updated) {
        await taskMirrorRepository.saveTaskMirrorBinding(updatedBinding.binding);
        activeMirrorBindings[task.id] = updatedBinding.binding;
        updated++;
        _recordTaskListChange(
          taskListDetailsById,
          localTaskListId: taskListId,
          taskListName: taskListName,
          remoteCalendarId: taskListBinding.remoteCalendarId,
          remoteCalendarName: taskListBinding.remoteCalendarName,
          updatedDelta: 1,
        );
      }
    }

    return OutlookTaskMirrorSyncResult(
      created: created,
      updated: updated,
      deleted: deleted,
      conflicted: conflicted,
      taskListDetails: _sortedTaskListDetails(taskListDetailsById),
    );
  }

  Future<OutlookTaskMirrorSyncResult> _cleanupStaleMirrorBindings({
    required Map<int, OutlookTaskListBinding> taskListBindings,
    required Map<int, TaskList> taskListById,
    required Map<int, OutlookTaskMirrorBinding> mirrorBindings,
    required Map<int, TaskItem> mirroredTaskById,
  }) async {
    var deleted = 0;
    final taskListDetailsById = <int, OutlookTaskMirrorTaskListSummary>{};

    for (final entry in mirrorBindings.entries.toList(growable: false)) {
      final localTaskId = entry.key;
      final mirrorBinding = entry.value;
      final task = mirroredTaskById[localTaskId];
      final taskListBinding = task == null || task.taskListId == null
          ? null
          : taskListBindings[task.taskListId!];

      final shouldDeleteRemote =
          task == null ||
          task.taskListId == null ||
          taskListBinding == null ||
          taskListBinding.remoteCalendarId != mirrorBinding.remoteCalendarId;

      if (!shouldDeleteRemote) {
        continue;
      }

      final removed = await _deleteRemoteMirror(mirrorBinding);
      if (!removed) {
        continue;
      }

      deleted++;
      _recordTaskListChange(
        taskListDetailsById,
        localTaskListId: mirrorBinding.localTaskListId,
        taskListName: _resolveTaskListName(
          taskListById,
          mirrorBinding.localTaskListId,
        ),
        remoteCalendarId: mirrorBinding.remoteCalendarId,
        remoteCalendarName: mirrorBinding.remoteCalendarName,
        deletedDelta: 1,
      );
      await taskMirrorRepository.removeTaskMirrorBinding(localTaskId);
    }

    return OutlookTaskMirrorSyncResult(
      deleted: deleted,
      taskListDetails: _sortedTaskListDetails(taskListDetailsById),
    );
  }

  List<OutlookTaskMirrorTaskListSummary> _sortedTaskListDetails(
    Map<int, OutlookTaskMirrorTaskListSummary> values,
  ) {
    final details = values.values
        .where((detail) => detail.changedCount > 0)
        .toList();
    details.sort((left, right) {
      final changedCompare = right.changedCount.compareTo(left.changedCount);
      if (changedCompare != 0) {
        return changedCompare;
      }
      return left.taskListName.compareTo(right.taskListName);
    });
    return details;
  }

  void _recordTaskListChange(
    Map<int, OutlookTaskMirrorTaskListSummary> target, {
    required int localTaskListId,
    required String taskListName,
    required String remoteCalendarId,
    required String remoteCalendarName,
    int createdDelta = 0,
    int updatedDelta = 0,
    int deletedDelta = 0,
    int conflictedDelta = 0,
  }) {
    final existing = target[localTaskListId];
    target[localTaskListId] = OutlookTaskMirrorTaskListSummary(
      localTaskListId: localTaskListId,
      taskListName: taskListName,
      remoteCalendarId: remoteCalendarId,
      remoteCalendarName: remoteCalendarName,
      created: (existing?.created ?? 0) + createdDelta,
      updated: (existing?.updated ?? 0) + updatedDelta,
      deleted: (existing?.deleted ?? 0) + deletedDelta,
      conflicted: (existing?.conflicted ?? 0) + conflictedDelta,
    );
  }

  String _resolveTaskListName(
    Map<int, TaskList> taskListById,
    int taskListId,
  ) {
    final name = taskListById[taskListId]?.name.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return '\u4efb\u52a1\u672c #$taskListId';
  }

  Future<OutlookTaskMirrorBinding> _createRemoteMirror({
    required TaskItem task,
    required OutlookTaskListBinding taskListBinding,
    required Map<String, dynamic> payload,
    required OutlookTaskMirrorSnapshot snapshot,
  }) async {
    final createdEvent = await graphService.createEvent(
      payload,
      calendarId: taskListBinding.remoteCalendarId,
      isFlowPlanManagedContainer: true,
    );
    final remoteEventId = createdEvent?['id'] as String? ?? '';
    if (remoteEventId.trim().isEmpty) {
      throw StateError(
        'Outlook \u5df2\u521b\u5efa\u4efb\u52a1\u955c\u50cf\uff0c\u4f46\u7f3a\u5c11\u53ef\u7528\u7684\u4e8b\u4ef6 ID\u3002',
      );
    }

    return OutlookTaskMirrorBinding(
      localTaskId: task.id,
      localTaskListId: task.taskListId ?? taskListBinding.localTaskListId,
      remoteCalendarId: taskListBinding.remoteCalendarId,
      remoteCalendarName: taskListBinding.remoteCalendarName,
      remoteEventId: remoteEventId.trim(),
      syncedAt: DateTime.now(),
      localSnapshotHash: snapshot.fingerprint,
      localSnapshotJson: snapshot.stableJson,
    );
  }

  Future<
      ({
        OutlookTaskMirrorBinding binding,
        bool updated,
        bool conflicted,
      })>
      _updateOrRecreateRemoteMirror({
    required TaskItem task,
    required OutlookTaskListBinding taskListBinding,
    required OutlookTaskMirrorBinding mirrorBinding,
    required Map<String, dynamic> payload,
    required OutlookTaskMirrorSnapshot snapshot,
  }) async {
    try {
      final updated = await graphService.updateEvent(
        calendarId: mirrorBinding.remoteCalendarId,
        eventId: mirrorBinding.remoteEventId,
        event: payload,
        isFlowPlanManagedContainer: true,
      );
      if (updated) {
        return (
          binding: mirrorBinding.copyWith(
            localTaskListId: task.taskListId ?? mirrorBinding.localTaskListId,
            remoteCalendarId: taskListBinding.remoteCalendarId,
            remoteCalendarName: taskListBinding.remoteCalendarName,
            syncedAt: DateTime.now(),
            localSnapshotHash: snapshot.fingerprint,
            localSnapshotJson: snapshot.stableJson,
          ),
          updated: true,
          conflicted: false,
        );
      }
    } catch (_) {
      // Treat write failures as conflicts instead of silently overwriting or
      // recreating remote data. The user can inspect and resolve from settings.
    }

    return (
      binding: mirrorBinding,
      updated: false,
      conflicted: true,
    );
  }

  Future<bool> _deleteRemoteMirror(OutlookTaskMirrorBinding binding) async {
    try {
      return await graphService.deleteEvent(
        calendarId: binding.remoteCalendarId,
        eventId: binding.remoteEventId,
        isFlowPlanManagedContainer: true,
      );
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _buildMirrorEventPayload({
    required TaskItem task,
    required String taskListName,
    required OutlookTaskMirrorSnapshot snapshot,
  }) {
    final timeRange = _resolveTimeRange(task);
    final body = _buildTaskMirrorBody(
      task: task,
      taskListName: taskListName,
      snapshot: snapshot,
    );

    return {
      'subject': task.summary,
      'body': {
        'contentType': 'Text',
        'content': body,
      },
      'start': {
        'dateTime': timeRange.start.toIso8601String(),
        'timeZone': 'Asia/Shanghai',
      },
      'end': {
        'dateTime': timeRange.end.toIso8601String(),
        'timeZone': 'Asia/Shanghai',
      },
      'showAs': task.status == 'COMPLETED' ? 'free' : 'tentative',
      'isAllDay': false,
      'categories': <String>[
        'FlowPlan \u4efb\u52a1\u955c\u50cf',
        'FlowPlan:$taskListName',
      ],
    };
  }

  ({DateTime start, DateTime end}) _resolveTimeRange(TaskItem task) {
    final duration = Duration(
      minutes: task.durationMinutes <= 0 ? 60 : task.durationMinutes,
    );

    if (task.dtstart != null) {
      final start = task.dtstart!;
      return (start: start, end: start.add(duration));
    }

    if (task.due != null) {
      final end = task.due!;
      final start = end.subtract(duration);
      return (start: start, end: end);
    }

    final base = task.dtstamp;
    return (start: base, end: base.add(duration));
  }

  String _buildTaskMirrorBody({
    required TaskItem task,
    required String taskListName,
    required OutlookTaskMirrorSnapshot snapshot,
  }) {
    final description = task.description?.trim();
    final generatedAt = DateTime.now();
    final meta = jsonEncode({
      ...snapshot.toJson(),
      'generated_at': generatedAt.toIso8601String(),
      'snapshot_hash': snapshot.fingerprint,
    });

    final lines = <String>[
      '【FlowPlan 任务镜像】',
      '',
      '这是 FlowPlan 为了跨设备查看任务而生成的 Outlook 镜像事件。',
      '请优先在 FlowPlan 内编辑任务；如果你在 Outlook 中修改或删除此镜像，FlowPlan 会把它视为同步冲突候选，不会用它直接删除本地任务。',
      '',
      '一、任务概览',
      '任务标题：${task.summary}',
      '\u4efb\u52a1\u672c\uff1a$taskListName',
      '\u72b6\u6001\uff1a${_statusLabel(task.status)}',
      '\u4f18\u5148\u7ea7\uff1a${_priorityLabel(task.priorityLocal)}',
      '\u9884\u8ba1\u65f6\u957f\uff1a${task.durationMinutes}\u5206\u949f',
      '完成度：${task.percentComplete}%',
      '\u81ea\u52a8\u6392\u7a0b\uff1a${task.isAutoScheduled ? '\u5f00\u542f' : '\u5173\u95ed'}',
      '\u5141\u8bb8\u62c6\u5206\uff1a${task.isSplittable ? '\u662f' : '\u5426'}',
      '锁定排程：${task.isLocked ? '是' : '否'}',
      '提前提醒：${task.reminderMinutesBefore} 分钟',
      if (task.dtstart != null)
        '\u8ba1\u5212\u5f00\u59cb\uff1a${_formatDateTime(task.dtstart!)}',
      if (task.due != null)
        '\u622a\u6b62\u65f6\u95f4\uff1a${_formatDateTime(task.due!)}',
      if (task.completed != null)
        '\u5b8c\u6210\u65f6\u95f4\uff1a${_formatDateTime(task.completed!)}',
      '',
      '二、任务描述',
      if (description != null && description.isNotEmpty) description,
      if (description == null || description.isEmpty) '无',
      '',
      '---',
      '三、恢复信息',
      '本段供 FlowPlan 诊断与恢复使用，请不要手动修改。',
      'FLOWPLAN_TASK_META_START',
      meta,
      'FLOWPLAN_TASK_META_END',
    ];

    return lines.join('\n');
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'COMPLETED':
        return '\u5df2\u5b8c\u6210';
      case 'CANCELLED':
        return '\u5df2\u53d6\u6d88';
      case 'IN-PROCESS':
        return '\u8fdb\u884c\u4e2d';
      case 'NEEDS-ACTION':
      default:
        return '\u5f85\u5904\u7406';
    }
  }

  String _priorityLabel(int priorityLocal) {
    switch (priorityLocal) {
      case 1:
        return '\u9ad8';
      case 3:
        return '\u4f4e';
      case 2:
      default:
        return '\u4e2d';
    }
  }

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }
}
