import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../audit/data_operation_log_repository.dart';
import '../calendar/data/calendar_books_repository.dart';
import '../task/data/task_repository.dart';
import 'ms_graph_service.dart';
import 'outlook_sync_bindings_repository.dart';
import 'outlook_sync_policy.dart';
import 'outlook_task_list_binding.dart';
import 'outlook_task_mirror_binding.dart';
import 'outlook_task_mirror_repository.dart';
import 'outlook_task_mirror_snapshot.dart';

class OutlookTaskMirrorTaskListSummary {
  const OutlookTaskMirrorTaskListSummary({
    required this.localTaskListId,
    required this.taskListName,
    required this.remoteCalendarId,
    required this.remoteCalendarName,
    required this.created,
    required this.updated,
    required this.deleted,
    required this.conflicted,
  });

  final int localTaskListId;
  final String taskListName;
  final String remoteCalendarId;
  final String remoteCalendarName;
  final int created;
  final int updated;
  final int deleted;
  final int conflicted;
}

class OutlookTaskMirrorSyncResult {
  const OutlookTaskMirrorSyncResult({
    required this.created,
    required this.updated,
    required this.deleted,
    required this.conflicted,
    required this.taskListDetails,
  });

  final int created;
  final int updated;
  final int deleted;
  final int conflicted;
  final List<OutlookTaskMirrorTaskListSummary> taskListDetails;
}

class OutlookTaskMirrorActionResult {
  const OutlookTaskMirrorActionResult({
    required this.success,
    required this.taskId,
    required this.message,
  });

  final bool success;
  final int taskId;
  final String message;
}

class OutlookTaskMirrorBatchActionResult {
  const OutlookTaskMirrorBatchActionResult({
    required this.success,
    required this.affected,
    required this.failed,
    required this.message,
    this.taskListDetails = const <OutlookTaskMirrorTaskListSummary>[],
  });

  final bool success;
  final int affected;
  final int failed;
  final String message;
  final List<OutlookTaskMirrorTaskListSummary> taskListDetails;
}

class OutlookTaskMirrorSyncService {
  const OutlookTaskMirrorSyncService({
    required this.graphService,
    required this.taskRepository,
    required this.calendarBooksRepository,
    required this.taskListBindingsRepository,
    required this.taskMirrorRepository,
    this.operationLogRepository,
  });

  final MsGraphService graphService;
  final TaskRepository taskRepository;
  final CalendarBooksRepository calendarBooksRepository;
  final OutlookSyncBindingsRepository taskListBindingsRepository;
  final OutlookTaskMirrorRepository taskMirrorRepository;
  final DataOperationLogRepository? operationLogRepository;

  Future<OutlookTaskMirrorSyncResult> syncBoundTaskMirrors() async {
    final taskListBindings = await taskListBindingsRepository.loadTaskListBindings();
    if (taskListBindings.isEmpty) {
      return const OutlookTaskMirrorSyncResult(
        created: 0,
        updated: 0,
        deleted: 0,
        conflicted: 0,
        taskListDetails: <OutlookTaskMirrorTaskListSummary>[],
      );
    }

    final taskLists = await calendarBooksRepository.getAllTaskLists();
    final taskListById = <int, TaskList>{
      for (final taskList in taskLists) taskList.id: taskList,
    };
    final tasks = await taskRepository.getByTaskListIds(taskListBindings.keys);
    final mirrorBindings = await taskMirrorRepository.loadTaskMirrorBindings();

    final counters = <int, _TaskListCounter>{};
    var created = 0;
    var updated = 0;
    var conflicted = 0;

    for (final task in tasks) {
      final taskListId = task.taskListId;
      if (taskListId == null) {
        continue;
      }
      final taskListBinding = taskListBindings[taskListId];
      if (taskListBinding == null) {
        continue;
      }

      final taskListName =
          taskListById[taskListId]?.name.trim().isNotEmpty == true
              ? taskListById[taskListId]!.name
              : taskListBinding.remoteCalendarName;
      final snapshot = OutlookTaskMirrorSnapshot.fromTask(
        task: task,
        taskListName: taskListName,
      );
      final existingBinding = mirrorBindings[task.id];
      final counter = counters.putIfAbsent(
        taskListId,
        () => _TaskListCounter.fromBinding(
          taskListBinding,
          taskListName: taskListName,
        ),
      );

      if (existingBinding == null) {
        final createdEvent = await graphService.createEvent(
          _buildMirrorEventPayload(
            task: task,
            taskListName: taskListName,
            snapshot: snapshot,
          ),
          calendarId: taskListBinding.remoteCalendarId,
          isFlowPlanManagedContainer: _isManagedContainer(
            taskListBinding.remoteCalendarName,
          ),
        );
        if (createdEvent == null) {
          conflicted++;
          counter.conflicted++;
          continue;
        }

        final remoteSnapshot = OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
          task: task,
          taskListName: taskListName,
          event: createdEvent,
        );
        final binding = OutlookTaskMirrorBinding(
          localTaskId: task.id,
          localTaskListId: taskListId,
          remoteCalendarId: taskListBinding.remoteCalendarId,
          remoteCalendarName: taskListBinding.remoteCalendarName,
          remoteEventId: (createdEvent['id'] as String? ?? '').trim(),
          syncedAt: DateTime.now(),
          localSnapshotHash: snapshot.fingerprint,
          localSnapshotJson: snapshot.stableJson,
          remoteSnapshotHash: remoteSnapshot.fingerprint,
          remoteSnapshotJson: remoteSnapshot.stableJson,
          remoteLastModifiedAt:
              _parseGraphDateTime(createdEvent['lastModifiedDateTime']),
        );
        await taskMirrorRepository.saveTaskMirrorBinding(binding);
        created++;
        counter.created++;
        continue;
      }

      if (existingBinding.remoteCalendarId != taskListBinding.remoteCalendarId) {
        final conflictBinding = existingBinding.markConflict(
          state: OutlookTaskMirrorConflictState.remoteChanged,
          message: '\u4efb\u52a1\u672c\u7ed1\u5b9a\u7684 Outlook \u955c\u50cf\u5bb9\u5668\u5df2\u7ecf\u53d8\u66f4\uff0c\u8bf7\u4eba\u5de5\u786e\u8ba4\u662f\u5426\u91cd\u5efa\u955c\u50cf\u3002',
          detectedAt: DateTime.now(),
          localSnapshotHash: snapshot.fingerprint,
          localSnapshotJson: snapshot.stableJson,
        );
        await taskMirrorRepository.saveTaskMirrorBinding(conflictBinding);
        conflicted++;
        counter.conflicted++;
        continue;
      }

      final localChanged = _hasLocalChanges(existingBinding, snapshot);
      final remoteEvent = await graphService.getEvent(
        calendarId: existingBinding.remoteCalendarId,
        eventId: existingBinding.remoteEventId,
      );
      if (remoteEvent == null) {
        final conflictBinding = existingBinding.markConflict(
          state: OutlookTaskMirrorConflictState.remoteDeleted,
          message: 'Outlook \u4fa7\u955c\u50cf\u4e8b\u4ef6\u5df2\u4e0d\u5b58\u5728\uff0c\u8bf7\u9009\u62e9\u91cd\u5efa\u955c\u50cf\u6216\u89e3\u9664\u7ed1\u5b9a\u3002',
          detectedAt: DateTime.now(),
          localSnapshotHash: snapshot.fingerprint,
          localSnapshotJson: snapshot.stableJson,
        );
        await taskMirrorRepository.saveTaskMirrorBinding(conflictBinding);
        conflicted++;
        counter.conflicted++;
        continue;
      }

      final remoteSnapshot = OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
        task: task,
        taskListName: taskListName,
        event: remoteEvent,
      );
      final remoteChanged = _hasRemoteChanges(existingBinding, remoteSnapshot);

      if (localChanged && remoteChanged) {
        final conflictBinding = existingBinding.markConflict(
          state: OutlookTaskMirrorConflictState.divergent,
          message: 'FlowPlan \u4e0e Outlook \u4e24\u4fa7\u90fd\u53d1\u751f\u4e86\u4fee\u6539\uff0c\u8bf7\u4eba\u5de5\u786e\u8ba4\u4ee5\u54ea\u4e00\u4fa7\u4e3a\u51c6\u3002',
          detectedAt: DateTime.now(),
          localSnapshotHash: snapshot.fingerprint,
          localSnapshotJson: snapshot.stableJson,
          remoteSnapshotHash: remoteSnapshot.fingerprint,
          remoteSnapshotJson: remoteSnapshot.stableJson,
          remoteLastModifiedAt: _parseGraphDateTime(
            remoteEvent['lastModifiedDateTime'],
          ),
        );
        await taskMirrorRepository.saveTaskMirrorBinding(conflictBinding);
        conflicted++;
        counter.conflicted++;
        continue;
      }

      if (remoteChanged) {
        final conflictBinding = existingBinding.markConflict(
          state: OutlookTaskMirrorConflictState.remoteChanged,
          message: 'Outlook \u955c\u50cf\u5df2\u88ab\u4fee\u6539\uff0c\u8bf7\u9009\u62e9\u91c7\u7528 Outlook \u5185\u5bb9\u6216\u6309\u672c\u5730\u5185\u5bb9\u8986\u76d6\u8fdc\u7aef\u3002',
          detectedAt: DateTime.now(),
          localSnapshotHash: snapshot.fingerprint,
          localSnapshotJson: snapshot.stableJson,
          remoteSnapshotHash: remoteSnapshot.fingerprint,
          remoteSnapshotJson: remoteSnapshot.stableJson,
          remoteLastModifiedAt: _parseGraphDateTime(
            remoteEvent['lastModifiedDateTime'],
          ),
        );
        await taskMirrorRepository.saveTaskMirrorBinding(conflictBinding);
        conflicted++;
        counter.conflicted++;
        continue;
      }

      if (!localChanged) {
        final resolved = existingBinding.markResolved(
          syncedAt: DateTime.now(),
          localSnapshotHash: snapshot.fingerprint,
          localSnapshotJson: snapshot.stableJson,
          remoteSnapshotHash: remoteSnapshot.fingerprint,
          remoteSnapshotJson: remoteSnapshot.stableJson,
          remoteLastModifiedAt: _parseGraphDateTime(
            remoteEvent['lastModifiedDateTime'],
          ),
          localTaskListId: taskListId,
          remoteCalendarId: taskListBinding.remoteCalendarId,
          remoteCalendarName: taskListBinding.remoteCalendarName,
          remoteEventId: existingBinding.remoteEventId,
        );
        await taskMirrorRepository.saveTaskMirrorBinding(resolved);
        continue;
      }

      try {
        final updatedOk = await graphService.updateEvent(
          calendarId: existingBinding.remoteCalendarId,
          eventId: existingBinding.remoteEventId,
          event: _buildMirrorEventPayload(
            task: task,
            taskListName: taskListName,
            snapshot: snapshot,
          ),
          isFlowPlanManagedContainer: _isManagedContainer(
            existingBinding.remoteCalendarName,
          ),
        );
        if (!updatedOk) {
          throw StateError('Outlook \u955c\u50cf\u66f4\u65b0\u8fd4\u56de\u5931\u8d25\u3002');
        }

        final refreshedEvent = await graphService.getEvent(
          calendarId: existingBinding.remoteCalendarId,
          eventId: existingBinding.remoteEventId,
        );
        final refreshedSnapshot = refreshedEvent == null
            ? snapshot
            : OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
                task: task,
                taskListName: taskListName,
                event: refreshedEvent,
              );
        final resolved = existingBinding.markResolved(
          syncedAt: DateTime.now(),
          localSnapshotHash: snapshot.fingerprint,
          localSnapshotJson: snapshot.stableJson,
          remoteSnapshotHash: refreshedSnapshot.fingerprint,
          remoteSnapshotJson: refreshedSnapshot.stableJson,
          remoteLastModifiedAt: refreshedEvent == null
              ? DateTime.now()
              : _parseGraphDateTime(refreshedEvent['lastModifiedDateTime']),
          localTaskListId: taskListId,
          remoteCalendarId: taskListBinding.remoteCalendarId,
          remoteCalendarName: taskListBinding.remoteCalendarName,
          remoteEventId: existingBinding.remoteEventId,
        );
        await taskMirrorRepository.saveTaskMirrorBinding(resolved);
        updated++;
        counter.updated++;
      } catch (error) {
        final conflictBinding = existingBinding.markConflict(
          state: OutlookTaskMirrorConflictState.writeFailed,
          message: '\u5199\u56de Outlook \u5931\u8d25\uff1a$error',
          detectedAt: DateTime.now(),
          localSnapshotHash: snapshot.fingerprint,
          localSnapshotJson: snapshot.stableJson,
          remoteSnapshotHash: remoteSnapshot.fingerprint,
          remoteSnapshotJson: remoteSnapshot.stableJson,
          remoteLastModifiedAt: _parseGraphDateTime(
            remoteEvent['lastModifiedDateTime'],
          ),
        );
        await taskMirrorRepository.saveTaskMirrorBinding(conflictBinding);
        conflicted++;
        counter.conflicted++;
      }
    }

    return OutlookTaskMirrorSyncResult(
      created: created,
      updated: updated,
      deleted: 0,
      conflicted: conflicted,
      taskListDetails: _toSummaries(counters),
    );
  }

  Future<OutlookTaskMirrorBatchActionResult> cleanupStaleTaskMirrors() async {
    final mirrorBindings = await taskMirrorRepository.loadTaskMirrorBindings();
    if (mirrorBindings.isEmpty) {
      return const OutlookTaskMirrorBatchActionResult(
        success: true,
        affected: 0,
        failed: 0,
        message: '\u5f53\u524d\u6ca1\u6709\u9700\u8981\u6e05\u7406\u7684\u4efb\u52a1\u955c\u50cf\u7d22\u5f15\u3002',
      );
    }

    final taskListBindings = await taskListBindingsRepository.loadTaskListBindings();
    final taskLists = await calendarBooksRepository.getAllTaskLists();
    final tasks = await taskRepository.getByIds(mirrorBindings.keys);
    final taskById = <int, TaskItem>{
      for (final task in tasks) task.id: task,
    };
    final taskListById = <int, TaskList>{
      for (final taskList in taskLists) taskList.id: taskList,
    };

    final staleIds = <int>[];
    final counters = <int, _TaskListCounter>{};

    for (final entry in mirrorBindings.entries) {
      final binding = entry.value;
      final task = taskById[entry.key];
      final taskListId = task?.taskListId ?? binding.localTaskListId;
      final taskListName =
          taskListById[taskListId]?.name ??
          _taskListNameFromSnapshot(binding.localSnapshotJson) ??
          binding.remoteCalendarName;
      final counter = counters.putIfAbsent(
        taskListId,
        () => _TaskListCounter(
          localTaskListId: taskListId,
          taskListName: taskListName,
          remoteCalendarId: binding.remoteCalendarId,
          remoteCalendarName: binding.remoteCalendarName,
        ),
      );

      if (task == null) {
        staleIds.add(entry.key);
        counter.deleted++;
        continue;
      }

      final currentTaskListId = task.taskListId;
      if (currentTaskListId == null) {
        staleIds.add(entry.key);
        counter.deleted++;
        continue;
      }

      final taskListBinding = taskListBindings[currentTaskListId];
      if (taskListBinding == null ||
          taskListBinding.remoteCalendarId != binding.remoteCalendarId) {
        staleIds.add(entry.key);
        counter.deleted++;
      }
    }

    if (staleIds.isEmpty) {
      return const OutlookTaskMirrorBatchActionResult(
        success: true,
        affected: 0,
        failed: 0,
        message: '\u6ca1\u6709\u53d1\u73b0\u5931\u6548\u7684\u4efb\u52a1\u955c\u50cf\u7d22\u5f15\u3002',
      );
    }

    await taskMirrorRepository.removeTaskMirrorBindings(staleIds);
    await _recordOperation(
      actor: 'system',
      action: 'cleanup',
      entityType: 'outlook_task_mirror_binding',
      summary: '\u6e05\u7406 ${staleIds.length} \u6761\u5931\u6548\u7684 Outlook \u4efb\u52a1\u955c\u50cf\u7d22\u5f15\u3002',
      metadata: <String, dynamic>{
        'task_ids': staleIds,
      },
    );

    return OutlookTaskMirrorBatchActionResult(
      success: true,
      affected: staleIds.length,
      failed: 0,
      message: '\u5df2\u6e05\u7406 ${staleIds.length} \u6761\u5931\u6548\u7684 Outlook \u4efb\u52a1\u955c\u50cf\u7d22\u5f15\u3002',
      taskListDetails: _toSummaries(counters),
    );
  }

  Future<OutlookTaskMirrorActionResult> forcePushLocalToRemote(int taskId) async {
    final context = await _loadTaskContext(taskId);
    if (context == null) {
      return OutlookTaskMirrorActionResult(
        success: false,
        taskId: taskId,
        message: '\u627e\u4e0d\u5230\u8981\u5904\u7406\u7684\u4efb\u52a1\u955c\u50cf\u7ed1\u5b9a\u3002',
      );
    }

    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: context.task,
      taskListName: context.taskListName,
    );
    Map<String, dynamic>? remoteEvent;
    String remoteEventId = context.binding.remoteEventId;

    try {
      final shouldRecreate =
          context.binding.remoteCalendarId != context.taskListBinding.remoteCalendarId ||
          context.binding.conflictState ==
              OutlookTaskMirrorConflictState.remoteDeleted ||
          context.binding.remoteEventId.trim().isEmpty;

      if (shouldRecreate) {
        remoteEvent = await graphService.createEvent(
          _buildMirrorEventPayload(
            task: context.task,
            taskListName: context.taskListName,
            snapshot: snapshot,
          ),
          calendarId: context.taskListBinding.remoteCalendarId,
          isFlowPlanManagedContainer: _isManagedContainer(
            context.taskListBinding.remoteCalendarName,
          ),
        );
        remoteEventId = (remoteEvent?['id'] as String? ?? '').trim();
      } else {
        final ok = await graphService.updateEvent(
          calendarId: context.binding.remoteCalendarId,
          eventId: context.binding.remoteEventId,
          event: _buildMirrorEventPayload(
            task: context.task,
            taskListName: context.taskListName,
            snapshot: snapshot,
          ),
          isFlowPlanManagedContainer: _isManagedContainer(
            context.binding.remoteCalendarName,
          ),
        );
        if (!ok) {
          throw StateError('Outlook \u955c\u50cf\u66f4\u65b0\u5931\u8d25\u3002');
        }
        remoteEvent = await graphService.getEvent(
          calendarId: context.binding.remoteCalendarId,
          eventId: context.binding.remoteEventId,
        );
      }

      final remoteSnapshot = remoteEvent == null
          ? snapshot
          : OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
              task: context.task,
              taskListName: context.taskListName,
              event: remoteEvent,
            );
      final resolved = context.binding.markResolved(
        syncedAt: DateTime.now(),
        localSnapshotHash: snapshot.fingerprint,
        localSnapshotJson: snapshot.stableJson,
        remoteSnapshotHash: remoteSnapshot.fingerprint,
        remoteSnapshotJson: remoteSnapshot.stableJson,
        remoteLastModifiedAt: remoteEvent == null
            ? DateTime.now()
            : _parseGraphDateTime(remoteEvent['lastModifiedDateTime']),
        localTaskListId: context.task.taskListId,
        remoteCalendarId: context.taskListBinding.remoteCalendarId,
        remoteCalendarName: context.taskListBinding.remoteCalendarName,
        remoteEventId: remoteEventId,
      );
      await taskMirrorRepository.saveTaskMirrorBinding(resolved);
      await _recordOperation(
        actor: 'user',
        action: 'force_push_local_to_remote',
        entityType: 'outlook_task_mirror_binding',
        entityId: taskId.toString(),
        summary: '\u6309 FlowPlan \u672c\u5730\u5185\u5bb9\u8986\u76d6 Outlook \u4efb\u52a1\u955c\u50cf\u3002',
        before: context.binding.toJson(),
        after: resolved.toJson(),
        metadata: <String, dynamic>{
          'task_summary': context.task.summary,
        },
      );

      return OutlookTaskMirrorActionResult(
        success: true,
        taskId: taskId,
        message: '\u5df2\u6309 FlowPlan \u672c\u5730\u5185\u5bb9\u66f4\u65b0 Outlook \u955c\u50cf\u3002',
      );
    } catch (error) {
      final failedBinding = context.binding.markConflict(
        state: OutlookTaskMirrorConflictState.writeFailed,
        message: '\u5199\u56de Outlook \u5931\u8d25\uff1a$error',
        detectedAt: DateTime.now(),
        localSnapshotHash: snapshot.fingerprint,
        localSnapshotJson: snapshot.stableJson,
      );
      await taskMirrorRepository.saveTaskMirrorBinding(failedBinding);
      return OutlookTaskMirrorActionResult(
        success: false,
        taskId: taskId,
        message: '\u5199\u56de Outlook \u5931\u8d25\uff1a$error',
      );
    }
  }

  Future<OutlookTaskMirrorActionResult> applyRemoteToLocal(int taskId) async {
    final context = await _loadTaskContext(taskId);
    if (context == null) {
      return OutlookTaskMirrorActionResult(
        success: false,
        taskId: taskId,
        message: '\u627e\u4e0d\u5230\u8981\u5904\u7406\u7684\u4efb\u52a1\u955c\u50cf\u7ed1\u5b9a\u3002',
      );
    }

    final remoteEvent = await graphService.getEvent(
      calendarId: context.binding.remoteCalendarId,
      eventId: context.binding.remoteEventId,
    );
    if (remoteEvent == null) {
      final conflictBinding = context.binding.markConflict(
        state: OutlookTaskMirrorConflictState.remoteDeleted,
        message: 'Outlook \u4fa7\u955c\u50cf\u5df2\u7ecf\u4e0d\u5b58\u5728\uff0c\u65e0\u6cd5\u56de\u586b\u5230\u672c\u5730\u3002',
        detectedAt: DateTime.now(),
      );
      await taskMirrorRepository.saveTaskMirrorBinding(conflictBinding);
      return OutlookTaskMirrorActionResult(
        success: false,
        taskId: taskId,
        message: 'Outlook \u955c\u50cf\u5df2\u4e0d\u5b58\u5728\uff0c\u65e0\u6cd5\u91c7\u7528\u8fdc\u7aef\u5185\u5bb9\u3002',
      );
    }

    final remoteSnapshot = OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
      task: context.task,
      taskListName: context.taskListName,
      event: remoteEvent,
    );
    final updatedTask = _taskCompanionFromSnapshot(
      task: context.task,
      snapshot: remoteSnapshot,
    );
    await taskRepository.update(updatedTask, audit: false);

    final refreshedTask = await taskRepository.getById(taskId);
    if (refreshedTask == null) {
      return OutlookTaskMirrorActionResult(
        success: false,
        taskId: taskId,
        message: '\u5e94\u7528 Outlook \u5185\u5bb9\u540e\u672a\u80fd\u91cd\u65b0\u8bfb\u53d6\u672c\u5730\u4efb\u52a1\u3002',
      );
    }
    final refreshedSnapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: refreshedTask,
      taskListName: context.taskListName,
    );
    final resolved = context.binding.markResolved(
      syncedAt: DateTime.now(),
      localSnapshotHash: refreshedSnapshot.fingerprint,
      localSnapshotJson: refreshedSnapshot.stableJson,
      remoteSnapshotHash: remoteSnapshot.fingerprint,
      remoteSnapshotJson: remoteSnapshot.stableJson,
      remoteLastModifiedAt: _parseGraphDateTime(
        remoteEvent['lastModifiedDateTime'],
      ),
      localTaskListId: refreshedTask.taskListId,
      remoteCalendarId: context.taskListBinding.remoteCalendarId,
      remoteCalendarName: context.taskListBinding.remoteCalendarName,
      remoteEventId: context.binding.remoteEventId,
    );
    await taskMirrorRepository.saveTaskMirrorBinding(resolved);
    await _recordOperation(
      actor: 'user',
      action: 'apply_remote_to_local',
      entityType: 'task_item',
      entityId: taskId.toString(),
      summary: '\u91c7\u7528 Outlook \u955c\u50cf\u5185\u5bb9\u56de\u586b\u672c\u5730\u4efb\u52a1\u3002',
      before: context.task.toJson(),
      after: refreshedTask.toJson(),
      metadata: <String, dynamic>{
        'remote_calendar_name': context.binding.remoteCalendarName,
        'remote_event_id': context.binding.remoteEventId,
      },
    );

    return OutlookTaskMirrorActionResult(
      success: true,
      taskId: taskId,
      message: '\u5df2\u91c7\u7528 Outlook \u955c\u50cf\u5185\u5bb9\u66f4\u65b0\u672c\u5730\u4efb\u52a1\u3002',
    );
  }

  Future<OutlookTaskMirrorActionResult> recreateRemoteMirror(int taskId) async {
    final context = await _loadTaskContext(taskId);
    if (context == null) {
      return OutlookTaskMirrorActionResult(
        success: false,
        taskId: taskId,
        message: '\u627e\u4e0d\u5230\u8981\u5904\u7406\u7684\u4efb\u52a1\u955c\u50cf\u7ed1\u5b9a\u3002',
      );
    }

    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: context.task,
      taskListName: context.taskListName,
    );
    try {
      final remoteEvent = await graphService.createEvent(
        _buildMirrorEventPayload(
          task: context.task,
          taskListName: context.taskListName,
          snapshot: snapshot,
        ),
        calendarId: context.taskListBinding.remoteCalendarId,
        isFlowPlanManagedContainer: _isManagedContainer(
          context.taskListBinding.remoteCalendarName,
        ),
      );
      if (remoteEvent == null) {
          throw StateError('Outlook \u672a\u8fd4\u56de\u65b0\u5efa\u4e8b\u4ef6\u3002');
      }

      final remoteSnapshot = OutlookTaskMirrorSnapshot.fromRemoteMirrorEvent(
        task: context.task,
        taskListName: context.taskListName,
        event: remoteEvent,
      );
      final resolved = context.binding.markResolved(
        syncedAt: DateTime.now(),
        localSnapshotHash: snapshot.fingerprint,
        localSnapshotJson: snapshot.stableJson,
        remoteSnapshotHash: remoteSnapshot.fingerprint,
        remoteSnapshotJson: remoteSnapshot.stableJson,
        remoteLastModifiedAt: _parseGraphDateTime(
          remoteEvent['lastModifiedDateTime'],
        ),
        localTaskListId: context.task.taskListId,
        remoteCalendarId: context.taskListBinding.remoteCalendarId,
        remoteCalendarName: context.taskListBinding.remoteCalendarName,
        remoteEventId: (remoteEvent['id'] as String? ?? '').trim(),
      );
      await taskMirrorRepository.saveTaskMirrorBinding(resolved);
      await _recordOperation(
        actor: 'user',
        action: 'recreate_remote_mirror',
        entityType: 'outlook_task_mirror_binding',
        entityId: taskId.toString(),
        summary: '\u91cd\u65b0\u521b\u5efa Outlook \u4efb\u52a1\u955c\u50cf\u3002',
        before: context.binding.toJson(),
        after: resolved.toJson(),
        metadata: <String, dynamic>{
          'task_summary': context.task.summary,
        },
      );

      return OutlookTaskMirrorActionResult(
        success: true,
        taskId: taskId,
        message: '\u5df2\u91cd\u65b0\u521b\u5efa Outlook \u4efb\u52a1\u955c\u50cf\u3002',
      );
    } catch (error) {
      final failedBinding = context.binding.markConflict(
        state: OutlookTaskMirrorConflictState.writeFailed,
        message: '\u91cd\u65b0\u521b\u5efa Outlook \u955c\u50cf\u5931\u8d25\uff1a$error',
        detectedAt: DateTime.now(),
        localSnapshotHash: snapshot.fingerprint,
        localSnapshotJson: snapshot.stableJson,
      );
      await taskMirrorRepository.saveTaskMirrorBinding(failedBinding);
      return OutlookTaskMirrorActionResult(
        success: false,
        taskId: taskId,
        message: '\u91cd\u65b0\u521b\u5efa Outlook \u955c\u50cf\u5931\u8d25\uff1a$error',
      );
    }
  }

  Future<OutlookTaskMirrorActionResult> detachMirror(
    int taskId, {
    String reason = '\u7528\u6237\u786e\u8ba4\u89e3\u9664 Outlook \u4efb\u52a1\u955c\u50cf\u7ed1\u5b9a',
  }) async {
    final binding = await taskMirrorRepository.getTaskMirrorBinding(taskId);
    if (binding == null) {
      return OutlookTaskMirrorActionResult(
        success: true,
        taskId: taskId,
        message: '\u5f53\u524d\u4efb\u52a1\u6ca1\u6709 Outlook \u955c\u50cf\u7ed1\u5b9a\u3002',
      );
    }

    await taskMirrorRepository.removeTaskMirrorBinding(taskId);
    await _recordOperation(
      actor: 'user',
      action: 'detach_mirror',
      entityType: 'outlook_task_mirror_binding',
      entityId: taskId.toString(),
      summary: reason,
      before: binding.toJson(),
      after: null,
    );
    return OutlookTaskMirrorActionResult(
      success: true,
      taskId: taskId,
      message: '\u5df2\u89e3\u9664 Outlook \u4efb\u52a1\u955c\u50cf\u7ed1\u5b9a\u3002',
    );
  }

  Future<OutlookTaskMirrorBatchActionResult>
      forcePushAllPendingLocalChanges() async {
    final mirrorBindings = await taskMirrorRepository.loadTaskMirrorBindings();
    if (mirrorBindings.isEmpty) {
      return const OutlookTaskMirrorBatchActionResult(
        success: true,
        affected: 0,
        failed: 0,
        message: '\u5f53\u524d\u6ca1\u6709\u53ef\u6279\u91cf\u5199\u56de\u7684\u4efb\u52a1\u955c\u50cf\u3002',
      );
    }

    final taskListBindings = await taskListBindingsRepository.loadTaskListBindings();
    final taskLists = await calendarBooksRepository.getAllTaskLists();
    final taskListById = <int, TaskList>{
      for (final taskList in taskLists) taskList.id: taskList,
    };
    final tasks = await taskRepository.getByIds(mirrorBindings.keys);
    final taskById = <int, TaskItem>{
      for (final task in tasks) task.id: task,
    };

    final eligibleTaskIds = <int>[];
    for (final entry in mirrorBindings.entries) {
      final task = taskById[entry.key];
      if (task == null || task.taskListId == null) {
        continue;
      }
      final taskListBinding = taskListBindings[task.taskListId!];
      if (taskListBinding == null) {
        continue;
      }
      final taskListName =
          taskListById[task.taskListId!]?.name ?? taskListBinding.remoteCalendarName;
      final snapshot = OutlookTaskMirrorSnapshot.fromTask(
        task: task,
        taskListName: taskListName,
      );
      final binding = entry.value;
      final localChanged = _hasLocalChanges(binding, snapshot);
      final isEligible = binding.conflictState ==
              OutlookTaskMirrorConflictState.pendingLocalPush ||
          binding.conflictState == OutlookTaskMirrorConflictState.writeFailed ||
          binding.conflictState == OutlookTaskMirrorConflictState.remoteChanged ||
          binding.conflictState == OutlookTaskMirrorConflictState.divergent ||
          localChanged;
      if (isEligible) {
        eligibleTaskIds.add(entry.key);
      }
    }

    if (eligibleTaskIds.isEmpty) {
      return const OutlookTaskMirrorBatchActionResult(
        success: true,
        affected: 0,
        failed: 0,
        message: '\u5f53\u524d\u6ca1\u6709\u9700\u8981\u6309\u672c\u5730\u5185\u5bb9\u8986\u76d6\u8fdc\u7aef\u7684\u4efb\u52a1\u955c\u50cf\u3002',
      );
    }

    var affected = 0;
    var failed = 0;
    for (final taskId in eligibleTaskIds) {
      final result = await forcePushLocalToRemote(taskId);
      if (result.success) {
        affected++;
      } else {
        failed++;
      }
    }
    return OutlookTaskMirrorBatchActionResult(
      success: failed == 0,
      affected: affected,
      failed: failed,
      message: failed == 0
          ? '\u5df2\u6279\u91cf\u6309\u672c\u5730\u5185\u5bb9\u66f4\u65b0 $affected \u6761 Outlook \u955c\u50cf\u3002'
          : '\u6279\u91cf\u5904\u7406\u5b8c\u6210\uff1a\u6210\u529f $affected \u6761\uff0c\u5931\u8d25 $failed \u6761\u3002',
    );
  }

  Future<OutlookTaskMirrorBatchActionResult>
      recreateAllRemoteDeletedMirrors() async {
    final mirrorBindings = await taskMirrorRepository.loadTaskMirrorBindings();
    final deletedIds = mirrorBindings.entries
        .where(
          (entry) =>
              entry.value.conflictState ==
              OutlookTaskMirrorConflictState.remoteDeleted,
        )
        .map((entry) => entry.key)
        .toList(growable: false);
    if (deletedIds.isEmpty) {
      return const OutlookTaskMirrorBatchActionResult(
        success: true,
        affected: 0,
        failed: 0,
        message: '\u5f53\u524d\u6ca1\u6709\u5df2\u5220\u9664\u7684\u8fdc\u7aef\u955c\u50cf\u9700\u8981\u91cd\u5efa\u3002',
      );
    }

    var affected = 0;
    var failed = 0;
    for (final taskId in deletedIds) {
      final result = await recreateRemoteMirror(taskId);
      if (result.success) {
        affected++;
      } else {
        failed++;
      }
    }
    return OutlookTaskMirrorBatchActionResult(
      success: failed == 0,
      affected: affected,
      failed: failed,
      message: failed == 0
          ? '\u5df2\u6279\u91cf\u91cd\u5efa $affected \u6761\u8fdc\u7aef\u955c\u50cf\u3002'
          : '\u6279\u91cf\u91cd\u5efa\u5b8c\u6210\uff1a\u6210\u529f $affected \u6761\uff0c\u5931\u8d25 $failed \u6761\u3002',
    );
  }

  Future<_TaskContext?> _loadTaskContext(int taskId) async {
    final task = await taskRepository.getById(taskId);
    final binding = await taskMirrorRepository.getTaskMirrorBinding(taskId);
    if (task == null || binding == null) {
      return null;
    }
    final taskListId = task.taskListId;
    if (taskListId == null) {
      return null;
    }
    final taskListBinding =
        await taskListBindingsRepository.getTaskListBinding(taskListId);
    if (taskListBinding == null) {
      return null;
    }
    final taskList = await calendarBooksRepository.getTaskListById(taskListId);
    final taskListName = taskList?.name.trim().isNotEmpty == true
        ? taskList!.name
        : taskListBinding.remoteCalendarName;
    return _TaskContext(
      task: task,
      binding: binding,
      taskListBinding: taskListBinding,
      taskListName: taskListName,
    );
  }

  bool _hasLocalChanges(
    OutlookTaskMirrorBinding binding,
    OutlookTaskMirrorSnapshot currentSnapshot,
  ) {
    final previousHash = binding.localSnapshotHash?.trim();
    if (previousHash == null || previousHash.isEmpty) {
      return false;
    }
    return previousHash != currentSnapshot.fingerprint;
  }

  bool _hasRemoteChanges(
    OutlookTaskMirrorBinding binding,
    OutlookTaskMirrorSnapshot currentSnapshot,
  ) {
    final previousHash = binding.remoteSnapshotHash?.trim();
    if (previousHash == null || previousHash.isEmpty) {
      return false;
    }
    return previousHash != currentSnapshot.fingerprint;
  }

  TaskItemsCompanion _taskCompanionFromSnapshot({
    required TaskItem task,
    required OutlookTaskMirrorSnapshot snapshot,
  }) {
    return TaskItemsCompanion(
      id: Value(task.id),
      uid: Value(task.uid),
      dtstamp: Value(task.dtstamp),
      summary: Value(snapshot.summary),
      description: Value(snapshot.description),
      dtstart: Value(snapshot.dtstart),
      due: Value(snapshot.due),
      completed: Value(snapshot.completed),
      priority: Value(task.priority),
      status: Value(snapshot.status),
      percentComplete: Value(snapshot.percentComplete),
      categories: Value(task.categories),
      rrule: Value(task.rrule),
      durationMinutes: Value(snapshot.durationMinutes),
      isSplittable: Value(snapshot.isSplittable),
      priorityLocal: Value(snapshot.priorityLocal),
      isAutoScheduled: Value(snapshot.isAutoScheduled),
      taskListId: Value(task.taskListId),
      tagId: Value(task.tagId),
      isLocked: Value(snapshot.isLocked),
      reminderMinutesBefore: Value(snapshot.reminderMinutesBefore),
    );
  }

  List<OutlookTaskMirrorTaskListSummary> _toSummaries(
    Map<int, _TaskListCounter> counters,
  ) {
    final items = counters.values
        .map(
          (counter) => OutlookTaskMirrorTaskListSummary(
            localTaskListId: counter.localTaskListId,
            taskListName: counter.taskListName,
            remoteCalendarId: counter.remoteCalendarId,
            remoteCalendarName: counter.remoteCalendarName,
            created: counter.created,
            updated: counter.updated,
            deleted: counter.deleted,
            conflicted: counter.conflicted,
          ),
        )
        .toList(growable: false);
    items.sort((left, right) => left.taskListName.compareTo(right.taskListName));
    return items;
  }

  Map<String, dynamic> _buildMirrorEventPayload({
    required TaskItem task,
    required String taskListName,
    required OutlookTaskMirrorSnapshot snapshot,
  }) {
    final duration = Duration(
      minutes: task.durationMinutes <= 0 ? 60 : task.durationMinutes,
    );
    final start =
        task.dtstart ??
        (task.due != null ? task.due!.subtract(duration) : DateTime.now());
    final end = task.due == null || !task.due!.isAfter(start)
        ? start.add(duration)
        : task.due!;

    return {
      'subject': task.summary,
      'body': {
        'contentType': 'Text',
        'content': _buildTaskMirrorBody(
          task: task,
          taskListName: taskListName,
          snapshot: snapshot,
        ),
      },
      'start': {
        'dateTime': start.toIso8601String(),
        'timeZone': 'Asia/Shanghai',
      },
      'end': {
        'dateTime': end.toIso8601String(),
        'timeZone': 'Asia/Shanghai',
      },
      'showAs': _showAsValue(task.status),
      'categories': <String>[
        'FlowPlan',
        'FlowPlan:\u4efb\u52a1\u955c\u50cf',
        'FlowPlan\u4efb\u52a1\u672c:$taskListName',
      ],
    };
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
      '\u3010FlowPlan \u4efb\u52a1\u955c\u50cf\u3011',
      '',
      '\u8fd9\u662f FlowPlan \u4e3a\u8de8\u8bbe\u5907\u67e5\u770b\u4efb\u52a1\u751f\u6210\u7684 Outlook \u955c\u50cf\u4e8b\u4ef6\u3002',
      '\u666e\u901a Outlook \u65e5\u5386\u59cb\u7ec8\u4e0d\u4f1a\u88ab FlowPlan \u5199\u56de\uff1b\u53ea\u6709 FlowPlan \u6258\u7ba1\u7684\u4e13\u5c5e\u955c\u50cf\u5bb9\u5668\u4f1a\u53c2\u4e0e\u53cc\u5411\u540c\u6b65\u3002',
      '\u5982\u679c\u4f60\u5728 Outlook \u4e2d\u4fee\u6539\u6216\u5220\u9664\u8fd9\u4e2a\u955c\u50cf\uff0cFlowPlan \u4f1a\u5c06\u5176\u6807\u8bb0\u4e3a\u5f85\u786e\u8ba4\u51b2\u7a81\uff0c\u800c\u4e0d\u4f1a\u9759\u9ed8\u8986\u76d6\u672c\u5730\u4efb\u52a1\u3002',
      '',
      '\u4e00\u3001\u4efb\u52a1\u6982\u89c8',
      '\u4efb\u52a1\u6807\u9898\uff1a${task.summary}',
      '\u4efb\u52a1\u672c\uff1a$taskListName',
      '\u72b6\u6001\uff1a${_statusLabel(task.status)}',
      '\u4f18\u5148\u7ea7\uff1a${_priorityLabel(task.priorityLocal)}',
      '\u9884\u8ba1\u65f6\u957f\uff1a${task.durationMinutes} \u5206\u949f',
      '\u5b8c\u6210\u5ea6\uff1a${task.percentComplete}%',
      '\u81ea\u52a8\u6392\u7a0b\uff1a${task.isAutoScheduled ? '\u5f00\u542f' : '\u5173\u95ed'}',
      '\u5141\u8bb8\u62c6\u5206\uff1a${task.isSplittable ? '\u662f' : '\u5426'}',
      '\u9501\u5b9a\u6392\u7a0b\uff1a${task.isLocked ? '\u662f' : '\u5426'}',
      '\u63d0\u524d\u63d0\u9192\uff1a${task.reminderMinutesBefore} \u5206\u949f',
      if (task.dtstart != null) '\u8ba1\u5212\u5f00\u59cb\uff1a${_formatDateTime(task.dtstart!)}',
      if (task.due != null) '\u622a\u6b62\u65f6\u95f4\uff1a${_formatDateTime(task.due!)}',
      if (task.completed != null) '\u5b8c\u6210\u65f6\u95f4\uff1a${_formatDateTime(task.completed!)}',
      '',
      '\u4e8c\u3001\u4efb\u52a1\u63cf\u8ff0',
      if (description != null && description.isNotEmpty) description else '\u65e0',
      '',
      '---',
      '\u4e09\u3001\u540c\u6b65\u8bf4\u660e',
      '\u5efa\u8bae\u4f18\u5148\u5728 FlowPlan \u5185\u7f16\u8f91\u4efb\u52a1\uff0c\u518d\u901a\u8fc7\u540c\u6b65\u628a\u53d8\u66f4\u5199\u56de\u5230 Outlook \u4e13\u5c5e\u955c\u50cf\u5bb9\u5668\u3002',
      '\u5982\u679c FlowPlan \u4e0e Outlook \u4e24\u4fa7\u90fd\u53d1\u751f\u4e86\u4fee\u6539\uff0c\u8bf7\u56de\u5230\u8bbe\u7f6e\u9875\u624b\u52a8\u786e\u8ba4\u4ee5\u54ea\u4e00\u4fa7\u4e3a\u51c6\u3002',
      '',
      '---',
      '\u56db\u3001\u673a\u5668\u5143\u6570\u636e\uff08\u8bf7\u52ff\u624b\u52a8\u7f16\u8f91\uff09',
      OutlookTaskMirrorSnapshot.metadataStartMarker,
      meta,
      OutlookTaskMirrorSnapshot.metadataEndMarker,
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

  String _showAsValue(String status) {
    switch (status) {
      case 'COMPLETED':
        return 'free';
      case 'IN-PROCESS':
        return 'tentative';
      case 'CANCELLED':
        return 'free';
      case 'NEEDS-ACTION':
      default:
        return 'busy';
    }
  }

  bool _isManagedContainer(String calendarName) {
    return OutlookSyncPolicy.isTaskMirrorCalendarName(calendarName) ||
        OutlookSyncPolicy.isFlowPlanManagedCalendarName(calendarName);
  }

  DateTime? _parseGraphDateTime(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw)?.toLocal();
  }

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }

  String? _taskListNameFromSnapshot(String? rawSnapshotJson) {
    if (rawSnapshotJson == null || rawSnapshotJson.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(rawSnapshotJson) as Map<String, dynamic>;
      final name = (decoded['task_list_name'] as String?)?.trim();
      return name == null || name.isEmpty ? null : name;
    } catch (_) {
      return null;
    }
  }

  Future<void> _recordOperation({
    required String actor,
    required String action,
    required String entityType,
    String? entityId,
    required String summary,
    Object? before,
    Object? after,
    Object? metadata,
  }) async {
    final repo = operationLogRepository;
    if (repo == null) {
      return;
    }
    await repo.record(
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

class _TaskContext {
  const _TaskContext({
    required this.task,
    required this.binding,
    required this.taskListBinding,
    required this.taskListName,
  });

  final TaskItem task;
  final OutlookTaskMirrorBinding binding;
  final OutlookTaskListBinding taskListBinding;
  final String taskListName;
}

class _TaskListCounter {
  _TaskListCounter({
    required this.localTaskListId,
    required this.taskListName,
    required this.remoteCalendarId,
    required this.remoteCalendarName,
  });

  factory _TaskListCounter.fromBinding(
    OutlookTaskListBinding binding, {
    required String taskListName,
  }) {
    return _TaskListCounter(
      localTaskListId: binding.localTaskListId,
      taskListName: taskListName,
      remoteCalendarId: binding.remoteCalendarId,
      remoteCalendarName: binding.remoteCalendarName,
    );
  }

  final int localTaskListId;
  final String taskListName;
  final String remoteCalendarId;
  final String remoteCalendarName;

  int created = 0;
  int updated = 0;
  int deleted = 0;
  int conflicted = 0;
}
