// 所有核心 Provider：手写形式（不依赖 riverpod_generator，避免 codegen 问题）
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/app_database.dart';
import '../../shared/providers/database_provider.dart';
import '../../features/task/data/task_repository.dart';
import '../../features/calendar/data/event_repository.dart';
import '../../features/calendar/data/calendar_books_repository.dart';
import '../../features/tracker/data/tracker_repository.dart';
import '../../features/tracker/data/activity_record_repository.dart';
import '../../features/tracker/models/activity_log_archive_day.dart';
import '../../features/tracker/models/activity_log_entry.dart';
import '../../features/tracker/models/activity_insights.dart';
import '../../features/tracker/models/input_event_query.dart';
import '../../features/tracker/models/input_heatmap_summary.dart';
import '../../features/tracker/models/tracked_input_event.dart';
import '../../features/tracker/models/work_session.dart';
import '../../features/tracker/services/activity_log_service.dart';
import '../../features/tracker/services/input_activity_event_service.dart';
import '../../features/audit/data_operation_log_repository.dart';
import '../../features/scheduler/task_schedule_segment_repository.dart';
import '../../features/sync/outlook_sync_bindings_repository.dart';
import '../../features/sync/outlook_task_mirror_repository.dart';
import '../../features/sync/outlook_task_list_binding.dart';
import '../../features/sync/outlook_task_mirror_binding.dart';
import '../../features/sync/outlook_task_mirror_snapshot.dart';

// 鈹€鈹€ Repository Providers 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  return TaskRepository(db, operationLogs);
}, dependencies: [databaseProvider, dataOperationLogRepositoryProvider]);

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  return EventRepository(db, operationLogs);
}, dependencies: [databaseProvider, dataOperationLogRepositoryProvider]);

final calendarBooksRepositoryProvider =
    Provider<CalendarBooksRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  return CalendarBooksRepository(db, operationLogs);
}, dependencies: [databaseProvider, dataOperationLogRepositoryProvider]);

final dataOperationLogRepositoryProvider =
    Provider<DataOperationLogRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return DataOperationLogRepository(db);
}, dependencies: [databaseProvider]);

final taskScheduleSegmentRepositoryProvider =
    Provider<TaskScheduleSegmentRepository>((ref) {
  final db = ref.watch(databaseProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  return TaskScheduleSegmentRepository(db, operationLogs);
}, dependencies: [databaseProvider, dataOperationLogRepositoryProvider]);

final outlookSyncBindingsRepositoryProvider =
    Provider<OutlookSyncBindingsRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return OutlookSyncBindingsRepository(db);
}, dependencies: [databaseProvider]);

final outlookTaskMirrorRepositoryProvider =
    Provider<OutlookTaskMirrorRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return OutlookTaskMirrorRepository(db);
}, dependencies: [databaseProvider]);

final outlookBindingRefreshTickProvider = StateProvider<int>((ref) => 0);

final outlookTaskListBindingsProvider =
    FutureProvider<Map<int, OutlookTaskListBinding>>((ref) {
  ref.watch(outlookBindingRefreshTickProvider);
  final repo = ref.watch(outlookSyncBindingsRepositoryProvider);
  return repo.loadTaskListBindings();
});

class OutlookTaskMirrorDiagnostics {
  const OutlookTaskMirrorDiagnostics({
    required this.totalBindings,
    required this.activeBindings,
    required this.pendingCleanup,
    required this.missingTasks,
    required this.unboundTaskLists,
    required this.movedTargets,
    required this.localChangedSinceLastMirror,
  });

  const OutlookTaskMirrorDiagnostics.empty()
      : totalBindings = 0,
        activeBindings = 0,
        pendingCleanup = 0,
        missingTasks = 0,
        unboundTaskLists = 0,
        movedTargets = 0,
        localChangedSinceLastMirror = 0;

  final int totalBindings;
  final int activeBindings;
  final int pendingCleanup;
  final int missingTasks;
  final int unboundTaskLists;
  final int movedTargets;
  final int localChangedSinceLastMirror;

  bool get hasPendingCleanup => pendingCleanup > 0;
}

final outlookTaskMirrorDiagnosticsProvider =
    FutureProvider<OutlookTaskMirrorDiagnostics>((ref) async {
  ref.watch(outlookBindingRefreshTickProvider);
  final mirrorRepo = ref.watch(outlookTaskMirrorRepositoryProvider);
  final taskListBindingsRepo = ref.watch(outlookSyncBindingsRepositoryProvider);
  final taskRepo = ref.watch(taskRepositoryProvider);

  final mirrorBindings = await mirrorRepo.loadTaskMirrorBindings();
  if (mirrorBindings.isEmpty) {
    return const OutlookTaskMirrorDiagnostics.empty();
  }

  final taskListBindings = await taskListBindingsRepo.loadTaskListBindings();
  final tasks = await taskRepo.getByIds(mirrorBindings.keys);
  final taskById = <int, TaskItem>{
    for (final task in tasks) task.id: task,
  };

  var activeBindings = 0;
  var pendingCleanup = 0;
  var missingTasks = 0;
  var unboundTaskLists = 0;
  var movedTargets = 0;
  var localChangedSinceLastMirror = 0;

  for (final entry in mirrorBindings.entries) {
    final task = taskById[entry.key];
    if (task == null) {
      missingTasks++;
      pendingCleanup++;
      continue;
    }

    final taskListId = task.taskListId;
    if (taskListId == null) {
      missingTasks++;
      pendingCleanup++;
      continue;
    }

    final taskListBinding = taskListBindings[taskListId];
    if (taskListBinding == null) {
      unboundTaskLists++;
      pendingCleanup++;
      continue;
    }

    if (taskListBinding.remoteCalendarId != entry.value.remoteCalendarId) {
      movedTargets++;
      pendingCleanup++;
      continue;
    }

    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task,
      taskListName: _previousSnapshotTaskListName(
            entry.value.localSnapshotJson,
          ) ??
          taskListBinding.remoteCalendarName,
    );
    final previousHash = entry.value.localSnapshotHash?.trim();
    if (previousHash != null &&
        previousHash.isNotEmpty &&
        previousHash != snapshot.fingerprint) {
      localChangedSinceLastMirror++;
    }

    activeBindings++;
  }

  return OutlookTaskMirrorDiagnostics(
    totalBindings: mirrorBindings.length,
    activeBindings: activeBindings,
    pendingCleanup: pendingCleanup,
    missingTasks: missingTasks,
    unboundTaskLists: unboundTaskLists,
    movedTargets: movedTargets,
    localChangedSinceLastMirror: localChangedSinceLastMirror,
  );
});

String? _previousSnapshotTaskListName(String? rawSnapshotJson) {
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

class OutlookFieldConflictSummary {
  const OutlookFieldConflictSummary({
    required this.taskId,
    required this.taskSummary,
    required this.taskListName,
    required this.remoteCalendarName,
    required this.conflictState,
    required this.changedFields,
    required this.detail,
    required this.canPushLocal,
    required this.canPullRemote,
    required this.canRecreateRemote,
    required this.canDetachMirror,
  });

  final int taskId;
  final String taskSummary;
  final String taskListName;
  final String remoteCalendarName;
  final OutlookTaskMirrorConflictState conflictState;
  final List<String> changedFields;
  final String detail;
  final bool canPushLocal;
  final bool canPullRemote;
  final bool canRecreateRemote;
  final bool canDetachMirror;
}

final outlookFieldConflictSummariesProvider =
    FutureProvider<List<OutlookFieldConflictSummary>>((ref) async {
  ref.watch(outlookBindingRefreshTickProvider);
  final mirrorRepo = ref.watch(outlookTaskMirrorRepositoryProvider);
  final taskListBindingsRepo = ref.watch(outlookSyncBindingsRepositoryProvider);
  final taskRepo = ref.watch(taskRepositoryProvider);
  final calendarBooksRepo = ref.watch(calendarBooksRepositoryProvider);

  final mirrorBindings = await mirrorRepo.loadTaskMirrorBindings();
  if (mirrorBindings.isEmpty) {
    return const <OutlookFieldConflictSummary>[];
  }

  final taskListBindings = await taskListBindingsRepo.loadTaskListBindings();
  final tasks = await taskRepo.getByIds(mirrorBindings.keys);
  final taskLists = await calendarBooksRepo.getAllTaskLists();
  final taskById = <int, TaskItem>{
    for (final task in tasks) task.id: task,
  };
  final taskListById = <int, TaskList>{
    for (final taskList in taskLists) taskList.id: taskList,
  };

  final results = <OutlookFieldConflictSummary>[];
  for (final entry in mirrorBindings.entries) {
    final binding = entry.value;
    final task = taskById[entry.key];
    if (task == null) {
      results.add(
        OutlookFieldConflictSummary(
          taskId: entry.key,
          taskSummary: '任务 #${entry.key}',
          taskListName:
              _previousSnapshotTaskListName(binding.localSnapshotJson) ?? '任务本',
          remoteCalendarName: binding.remoteCalendarName,
          conflictState: OutlookTaskMirrorConflictState.remoteDeleted,
          changedFields: const <String>['本地任务已不存在'],
          detail:
              '本地任务已经不存在，但仍保留了 Outlook 镜像绑定。建议先清理镜像索引，或导出诊断报告后再处理。',
          canPushLocal: false,
          canPullRemote: false,
          canRecreateRemote: false,
          canDetachMirror: true,
        ),
      );
      continue;
    }

    if (task.taskListId == null) {
      results.add(
        OutlookFieldConflictSummary(
          taskId: task.id,
          taskSummary: task.summary,
          taskListName:
              _previousSnapshotTaskListName(binding.localSnapshotJson) ?? '任务本',
          remoteCalendarName: binding.remoteCalendarName,
          conflictState: OutlookTaskMirrorConflictState.writeFailed,
          changedFields: const <String>['缺少任务本归属'],
          detail: '该任务已经失去任务本归属，当前无法继续安全同步，请先检查容器归属关系。',
          canPushLocal: false,
          canPullRemote: false,
          canRecreateRemote: false,
          canDetachMirror: true,
        ),
      );
      continue;
    }

    final taskListBinding = taskListBindings[task.taskListId!];
    if (taskListBinding == null) {
      results.add(
        OutlookFieldConflictSummary(
          taskId: task.id,
          taskSummary: task.summary,
          taskListName: taskListById[task.taskListId!]?.name ??
              _previousSnapshotTaskListName(binding.localSnapshotJson) ??
              '任务本',
          remoteCalendarName: binding.remoteCalendarName,
          conflictState: OutlookTaskMirrorConflictState.writeFailed,
          changedFields: const <String>['任务本已解除绑定'],
          detail: '该任务本已经解除 Outlook 镜像绑定，当前任务无法继续写回远端。',
          canPushLocal: false,
          canPullRemote: false,
          canRecreateRemote: false,
          canDetachMirror: true,
        ),
      );
      continue;
    }

    if (taskListBinding.remoteCalendarId != binding.remoteCalendarId) {
      results.add(
        OutlookFieldConflictSummary(
          taskId: task.id,
          taskSummary: task.summary,
          taskListName: taskListById[task.taskListId!]?.name ??
              _previousSnapshotTaskListName(binding.localSnapshotJson) ??
              '任务本',
          remoteCalendarName: binding.remoteCalendarName,
          conflictState: OutlookTaskMirrorConflictState.remoteChanged,
          changedFields: const <String>['镜像目标已变更'],
          detail: '任务本绑定的 Outlook 容器已经变化，旧镜像需要人工确认是重建还是解除绑定。',
          canPushLocal: true,
          canPullRemote: false,
          canRecreateRemote: true,
          canDetachMirror: true,
        ),
      );
      continue;
    }

    final taskListName = taskListById[task.taskListId!]?.name ??
        _previousSnapshotTaskListName(binding.localSnapshotJson) ??
        taskListBinding.remoteCalendarName;
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task,
      taskListName: taskListName,
    );
    final previousHash = binding.localSnapshotHash?.trim();
    final localChanged = previousHash != null &&
        previousHash.isNotEmpty &&
        previousHash != snapshot.fingerprint;

    final conflictState = binding.conflictState ==
            OutlookTaskMirrorConflictState.none
        ? (localChanged
            ? OutlookTaskMirrorConflictState.pendingLocalPush
            : OutlookTaskMirrorConflictState.none)
        : binding.conflictState;
    if (conflictState == OutlookTaskMirrorConflictState.none) {
      continue;
    }

    List<String> changedFields;
    String detail;
    var canPushLocal = false;
    var canPullRemote = false;
    var canRecreateRemote = false;
    var canDetachMirror = false;

    switch (conflictState) {
      case OutlookTaskMirrorConflictState.pendingLocalPush:
        changedFields = OutlookTaskMirrorSnapshot.changedFieldLabels(
          previousSnapshotJson: binding.localSnapshotJson,
          current: snapshot,
        );
        detail = '本地任务字段已经变化，等待用户确认是否按 FlowPlan 当前内容写回 Outlook 镜像。';
        canPushLocal = true;
        break;
      case OutlookTaskMirrorConflictState.remoteDeleted:
        changedFields = const <String>['远端镜像已删除'];
        detail = binding.conflictMessage?.trim().isNotEmpty == true
            ? binding.conflictMessage!.trim()
            : '远端镜像已经不存在。可以重建镜像，也可以仅解除镜像绑定并保留本地任务。';
        canPushLocal = true;
        canRecreateRemote = true;
        canDetachMirror = true;
        break;
      case OutlookTaskMirrorConflictState.remoteChanged:
        changedFields = OutlookTaskMirrorSnapshot.changedFieldLabelsBetween(
          leftSnapshotJson: binding.localSnapshotJson,
          rightSnapshotJson: binding.remoteSnapshotJson,
        );
        detail = binding.conflictMessage?.trim().isNotEmpty == true
            ? binding.conflictMessage!.trim()
            : 'Outlook 镜像已被修改，请确认是用本地内容覆盖远端，还是把远端内容回填到 FlowPlan。';
        canPushLocal = true;
        canPullRemote = true;
        canDetachMirror = true;
        break;
      case OutlookTaskMirrorConflictState.divergent:
        changedFields = OutlookTaskMirrorSnapshot.changedFieldLabelsBetween(
          leftSnapshotJson: binding.localSnapshotJson,
          rightSnapshotJson: binding.remoteSnapshotJson,
        );
        detail = binding.conflictMessage?.trim().isNotEmpty == true
            ? binding.conflictMessage!.trim()
            : 'FlowPlan 与 Outlook 两侧都已经修改，请人工选择以哪一侧为准。';
        canPushLocal = true;
        canPullRemote = true;
        canDetachMirror = true;
        break;
      case OutlookTaskMirrorConflictState.writeFailed:
        changedFields = localChanged
            ? OutlookTaskMirrorSnapshot.changedFieldLabels(
                previousSnapshotJson: binding.localSnapshotJson,
                current: snapshot,
              )
            : const <String>['远端写回失败'];
        detail = binding.conflictMessage?.trim().isNotEmpty == true
            ? binding.conflictMessage!.trim()
            : '最近一次远端写回失败，请稍后重试，或导出诊断报告进一步检查。';
        canPushLocal = true;
        canDetachMirror = true;
        break;
      case OutlookTaskMirrorConflictState.none:
        changedFields = const <String>[];
        detail = '';
        break;
    }

    results.add(
      OutlookFieldConflictSummary(
        taskId: task.id,
        taskSummary: task.summary,
        taskListName: taskListName,
        remoteCalendarName: taskListBinding.remoteCalendarName,
        conflictState: conflictState,
        changedFields: changedFields,
        detail: detail,
        canPushLocal: canPushLocal,
        canPullRemote: canPullRemote,
        canRecreateRemote: canRecreateRemote,
        canDetachMirror: canDetachMirror,
      ),
    );
  }

  results.sort((left, right) => left.taskSummary.compareTo(right.taskSummary));
  return results;
});

// 鈹€鈹€ 褰撳墠鏌ョ湅鏃ユ湡 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

class _SelectedDateNotifier extends StateNotifier<DateTime> {
  _SelectedDateNotifier()
      : super(DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
        ));

  void setDate(DateTime date) =>
      state = DateTime(date.year, date.month, date.day);
  void goToToday() => setDate(DateTime.now());
  void goToPrevDay() => state = state.subtract(const Duration(days: 1));
  void goToNextDay() => state = state.add(const Duration(days: 1));
}

final selectedDateProvider =
    StateNotifierProvider<_SelectedDateNotifier, DateTime>(
  (ref) => _SelectedDateNotifier(),
);

// 鈹€鈹€ 褰撴棩浠诲姟娴?鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final tasksForSelectedDateProvider = StreamProvider<List<TaskItem>>((ref) {
  final date = ref.watch(selectedDateProvider);
  final repo = ref.watch(taskRepositoryProvider);
  return repo.watchForDate(date);
});

final taskScheduleSegmentsForSelectedDateProvider =
    StreamProvider<List<TaskScheduleSegmentWithTask>>((ref) {
  final date = ref.watch(selectedDateProvider);
  final repo = ref.watch(taskScheduleSegmentRepositoryProvider);
  return repo.watchForDate(date);
});

// 鈹€鈹€ 褰撴棩浜嬩欢娴?鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final eventsForSelectedDateProvider =
    StreamProvider<List<CalendarEvent>>((ref) {
  final date = ref.watch(selectedDateProvider);
  final repo = ref.watch(eventRepositoryProvider);
  return repo.watchVisibleForDate(date);
});

// 鈹€鈹€ 浜嬩欢鏃ュ巻鏈垪琛ㄦ祦 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final allEventCalendarsProvider = StreamProvider<List<EventCalendar>>((ref) {
  final repo = ref.watch(calendarBooksRepositoryProvider);
  return repo.watchAllEventCalendars();
});

// 鈹€鈹€ 浠诲姟娓呭崟鍒楄〃娴?鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final allTaskListsProvider = StreamProvider<List<TaskList>>((ref) {
  final repo = ref.watch(calendarBooksRepositoryProvider);
  return repo.watchAllTaskLists();
});
final archivedTaskListsProvider = StreamProvider<List<TaskList>>((ref) {
  final repo = ref.watch(calendarBooksRepositoryProvider);
  return repo.watchArchivedTaskLists();
});

// 鈹€鈹€ 鎵€鏈変换鍔℃祦 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final allTasksProvider = StreamProvider<List<TaskItem>>((ref) {
  final repo = ref.watch(taskRepositoryProvider);
  return repo.watchAll();
});

final managementTasksProvider = StreamProvider<List<TaskItem>>((ref) {
  final repo = ref.watch(taskRepositoryProvider);
  return repo.watchAllForManagement();
});

final managementEventsProvider = StreamProvider<List<CalendarEvent>>((ref) {
  final repo = ref.watch(eventRepositoryProvider);
  return repo.watchAllForManagement();
});

// 鈹€鈹€ Tracker Repository 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final trackerRepositoryProvider = Provider<TrackerRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return TrackerRepository(db);
}, dependencies: [databaseProvider]);

// 鈹€鈹€ Activity Record Repository 鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final activityRecordRepositoryProvider =
    Provider<ActivityRecordRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return ActivityRecordRepository(db);
}, dependencies: [databaseProvider]);

final activityLogServiceProvider = Provider<ActivityLogService>((ref) {
  final db = ref.watch(databaseProvider);
  return ActivityLogService(db);
}, dependencies: [databaseProvider]);

final inputActivityEventServiceProvider =
    Provider<InputActivityEventService>((ref) {
  final db = ref.watch(databaseProvider);
  return InputActivityEventService(db);
}, dependencies: [databaseProvider]);

final activityLogRefreshTickProvider = StateProvider<int>((ref) => 0);

final inputEventProcessOptionsProvider = FutureProvider<List<String>>((ref) {
  ref.watch(activityLogRefreshTickProvider);
  final service = ref.watch(inputActivityEventServiceProvider);
  return service.listProcessNames();
});

final inputHeatmapSummaryProvider =
    FutureProvider.family<InputHeatmapSummary, InputEventQuery>((ref, query) {
  ref.watch(activityLogRefreshTickProvider);
  final service = ref.watch(inputActivityEventServiceProvider);
  return service.buildHeatmapSummary(query);
});

final selectedDateInputBehaviorSummaryProvider =
    FutureProvider<InputHeatmapSummary>((ref) {
  ref.watch(activityLogRefreshTickProvider);
  final selectedDate = ref.watch(selectedDateProvider);
  final start = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );
  final end = start.add(const Duration(days: 1));
  final service = ref.watch(inputActivityEventServiceProvider);
  return service.buildHeatmapSummary(
    InputEventQuery(
      start: start,
      end: end,
    ),
  );
});

// 鈹€鈹€ 鐑姏鍥炬暟鎹紙杩囧幓涓€骞达級鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final activityHeatmapScaleOverrideProvider =
    StateProvider<ActivityHeatmapScale?>((ref) => null);

final activityHistorySummaryProvider =
    FutureProvider<ActivityHistorySummary>((ref) {
  final repo = ref.watch(trackerRepositoryProvider);
  return repo.getHistorySummary();
});

final activityHeatmapSeriesProvider =
    FutureProvider<ActivityHeatmapSeries>((ref) async {
  final repo = ref.watch(trackerRepositoryProvider);
  final selectedDate = ref.watch(selectedDateProvider);
  final override = ref.watch(activityHeatmapScaleOverrideProvider);
  final summary = await ref.watch(activityHistorySummaryProvider.future);
  final scale = override ?? summary.recommendedScale;
  return repo.getHeatmapSeries(
    scale: scale,
    anchorDate: selectedDate,
    historySummary: summary,
  );
});

// 鈹€鈹€ 鎷栨嫿鐘舵€?鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€
// 鍏ㄥ眬锛氬綋鍓嶆嫋鎷藉厜鏍囨槸鍚﹀湪鏃堕棿杞翠笂鏂?
final dragHoveringTimelineProvider = StateProvider<bool>((ref) => false);

// 鈹€鈹€ 褰撴棩娲诲姩璁板綍娴?鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€鈹€

final activityRecordsForDateProvider =
    StreamProvider<List<ActivityRecord>>((ref) {
  final date = ref.watch(selectedDateProvider);
  final repo = ref.watch(activityRecordRepositoryProvider);
  return repo.watchForDate(date);
});

final activityInsightsProvider = Provider<ActivityInsights>((ref) {
  final recordsAsync = ref.watch(activityRecordsForDateProvider);
  return recordsAsync.maybeWhen(
    data: ActivityInsights.fromRecords,
    orElse: ActivityInsights.empty,
  );
});

final workSessionsForDateProvider = Provider<List<WorkSession>>((ref) {
  final recordsAsync = ref.watch(activityRecordsForDateProvider);
  return recordsAsync.maybeWhen(
    data: WorkSessionGrouper.fromRecords,
    orElse: () => const <WorkSession>[],
  );
});

final activityLogEntriesForDateProvider =
    FutureProvider<List<ActivityLogEntry>>((ref) {
  ref.watch(activityLogRefreshTickProvider);
  final date = ref.watch(selectedDateProvider);
  final service = ref.watch(activityLogServiceProvider);
  return service.readEntriesForDate(date);
});

final activityLogStoragePathProvider = FutureProvider<String>((ref) {
  final service = ref.watch(activityLogServiceProvider);
  return service.getStoragePath();
});

final activityLogArchiveDirectoryPathProvider = FutureProvider<String>((ref) {
  final service = ref.watch(activityLogServiceProvider);
  return service.getArchiveDirectoryPath();
});

final inputEventArchiveDirectoryPathProvider = FutureProvider<String>((ref) {
  final service = ref.watch(inputActivityEventServiceProvider);
  return service.getArchiveDirectoryPath();
});

final activityLogArchiveDaysProvider =
    FutureProvider<List<ActivityLogArchiveDay>>((ref) {
  ref.watch(activityLogRefreshTickProvider);
  final service = ref.watch(activityLogServiceProvider);
  return service.listArchiveDays();
});

final inputEventArchiveDaysProvider =
    FutureProvider<List<ActivityLogArchiveDay>>((ref) {
  ref.watch(activityLogRefreshTickProvider);
  final service = ref.watch(inputActivityEventServiceProvider);
  return service.listArchiveDays();
});

final activityLogArchiveEntriesForDateProvider =
    FutureProvider.family<List<ActivityLogEntry>, DateTime>((ref, date) {
  ref.watch(activityLogRefreshTickProvider);
  final service = ref.watch(activityLogServiceProvider);
  return service.readArchivedEntriesForDate(date);
});

final inputEventArchiveEntriesForDateProvider =
    FutureProvider.family<List<TrackedInputEvent>, DateTime>((ref, date) {
  ref.watch(activityLogRefreshTickProvider);
  final service = ref.watch(inputActivityEventServiceProvider);
  return service.readArchivedEventsForDate(date);
});

final recentTrackedInputEventsProvider =
    FutureProvider<List<TrackedInputEvent>>((ref) {
  ref.watch(activityLogRefreshTickProvider);
  final service = ref.watch(inputActivityEventServiceProvider);
  return service.listRecentEvents(
    limit: 12,
    includeIgnored: false,
  );
});

class TrackerHistoryFilterOptions {
  final List<String> processOptions;
  final List<String> categoryOptions;

  const TrackerHistoryFilterOptions({
    required this.processOptions,
    required this.categoryOptions,
  });

  const TrackerHistoryFilterOptions.empty()
      : processOptions = const <String>[],
        categoryOptions = const <String>[];
}

class TrackerRangeAnalysisSnapshot {
  final ActivityHeatmapBucket bucket;
  final List<ActivityRecord> records;
  final List<ActivityLogEntry> logEntries;
  final ActivityInsights insights;
  final List<WorkSession> sessions;

  const TrackerRangeAnalysisSnapshot({
    required this.bucket,
    required this.records,
    required this.logEntries,
    required this.insights,
    required this.sessions,
  });
}

final trackerHistorySearchQueryProvider = StateProvider<String>((ref) => '');

final trackerHistorySelectedProcessProvider =
    StateProvider<String?>((ref) => null);

final trackerHistorySelectedCategoryProvider =
    StateProvider<String?>((ref) => null);

final trackerHistorySelectedTaskIdProvider = StateProvider<int?>((ref) => null);

final trackerHistoryOnlyWithInputProvider =
    StateProvider<bool>((ref) => false);

final trackerHistorySelectedHeatmapBucketProvider =
    StateProvider<ActivityHeatmapBucket?>((ref) => null);

final trackerHistorySelectedAnalysisBucketProvider =
    StateProvider<ActivityHeatmapBucket?>((ref) => null);

final trackerRangeAnalysisRecordsProvider =
    StreamProvider<List<ActivityRecord>>((ref) {
  final bucket = ref.watch(trackerHistorySelectedAnalysisBucketProvider);
  if (bucket == null) {
    return Stream.value(const <ActivityRecord>[]);
  }

  final repo = ref.watch(activityRecordRepositoryProvider);
  return repo.watchInRange(bucket.start, bucket.end);
});

final trackerRangeAnalysisLogEntriesProvider =
    FutureProvider<List<ActivityLogEntry>>((ref) {
  ref.watch(activityLogRefreshTickProvider);
  final bucket = ref.watch(trackerHistorySelectedAnalysisBucketProvider);
  if (bucket == null) {
    return Future.value(const <ActivityLogEntry>[]);
  }

  final service = ref.watch(activityLogServiceProvider);
  return service.readEntriesBetween(bucket.start, bucket.end);
});

final trackerRangeAnalysisProvider =
    Provider<AsyncValue<TrackerRangeAnalysisSnapshot?>>((ref) {
  final bucket = ref.watch(trackerHistorySelectedAnalysisBucketProvider);
  if (bucket == null) {
    return const AsyncData(null);
  }

  final recordsAsync = ref.watch(trackerRangeAnalysisRecordsProvider);
  final logsAsync = ref.watch(trackerRangeAnalysisLogEntriesProvider);

  if (recordsAsync.hasError) {
    return AsyncValue.error(
      recordsAsync.error!,
      recordsAsync.stackTrace ?? StackTrace.current,
    );
  }

  if (logsAsync.hasError) {
    return AsyncValue.error(
      logsAsync.error!,
      logsAsync.stackTrace ?? StackTrace.current,
    );
  }

  final records = recordsAsync.asData?.value;
  final logEntries = logsAsync.asData?.value;
  if (records == null || logEntries == null) {
    return const AsyncLoading();
  }

  return AsyncData(
    TrackerRangeAnalysisSnapshot(
      bucket: bucket,
      records: records,
      logEntries: logEntries,
      insights: ActivityInsights.fromRecords(records),
      sessions: WorkSessionGrouper.fromRecords(records),
    ),
  );
});

final trackerHistoryFilterOptionsProvider =
    Provider<TrackerHistoryFilterOptions>((ref) {
  final recordsAsync = ref.watch(activityRecordsForDateProvider);
  return recordsAsync.maybeWhen(
    data: (records) {
      final processes = <String>{};
      final categories = <String>{};

      for (final record in records) {
        final process = record.processName?.trim();
        if (process != null && process.isNotEmpty) {
          processes.add(process);
        }

        final category = record.category?.trim();
        if (category != null && category.isNotEmpty) {
          categories.add(category);
        }
      }

      final sortedProcesses = processes.toList()
        ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
      final sortedCategories = categories.toList()
        ..sort((left, right) => left.compareTo(right));

      return TrackerHistoryFilterOptions(
        processOptions: sortedProcesses,
        categoryOptions: sortedCategories,
      );
    },
    orElse: TrackerHistoryFilterOptions.empty,
  );
});
