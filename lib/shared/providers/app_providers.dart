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
import '../../features/sync/outlook_task_mirror_snapshot.dart';

// ── Repository Providers ──────────────────────────────────────────────────────

final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return TaskRepository(db);
}, dependencies: [databaseProvider]);

final eventRepositoryProvider = Provider<EventRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return EventRepository(db);
}, dependencies: [databaseProvider]);

final calendarBooksRepositoryProvider =
    Provider<CalendarBooksRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return CalendarBooksRepository(db);
}, dependencies: [databaseProvider]);

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
    required this.changedFields,
  });

  final int taskId;
  final String taskSummary;
  final String taskListName;
  final String remoteCalendarName;
  final List<String> changedFields;
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
    final task = taskById[entry.key];
    if (task == null || task.taskListId == null) {
      continue;
    }

    final taskListBinding = taskListBindings[task.taskListId!];
    if (taskListBinding == null ||
        taskListBinding.remoteCalendarId != entry.value.remoteCalendarId) {
      continue;
    }

    final taskListName = taskListById[task.taskListId!]?.name ??
        _previousSnapshotTaskListName(entry.value.localSnapshotJson) ??
        taskListBinding.remoteCalendarName;
    final snapshot = OutlookTaskMirrorSnapshot.fromTask(
      task: task,
      taskListName: taskListName,
    );
    final previousHash = entry.value.localSnapshotHash?.trim();
    if (previousHash == null ||
        previousHash.isEmpty ||
        previousHash == snapshot.fingerprint) {
      continue;
    }

    results.add(
      OutlookFieldConflictSummary(
        taskId: task.id,
        taskSummary: task.summary,
        taskListName: taskListName,
        remoteCalendarName: taskListBinding.remoteCalendarName,
        changedFields: OutlookTaskMirrorSnapshot.changedFieldLabels(
          previousSnapshotJson: entry.value.localSnapshotJson,
          current: snapshot,
        ),
      ),
    );
  }

  results.sort((left, right) => left.taskSummary.compareTo(right.taskSummary));
  return results;
});

// ── 当前查看日期 ───────────────────────────────────────────────────────────────

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

// ── 当日任务流 ────────────────────────────────────────────────────────────────

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

// ── 当日事件流 ────────────────────────────────────────────────────────────────

final eventsForSelectedDateProvider =
    StreamProvider<List<CalendarEvent>>((ref) {
  final date = ref.watch(selectedDateProvider);
  final repo = ref.watch(eventRepositoryProvider);
  return repo.watchVisibleForDate(date);
});

// ── 事件日历本列表流 ──────────────────────────────────────────────────────────

final allEventCalendarsProvider = StreamProvider<List<EventCalendar>>((ref) {
  final repo = ref.watch(calendarBooksRepositoryProvider);
  return repo.watchAllEventCalendars();
});

// ── 任务清单列表流 ────────────────────────────────────────────────────────────

final allTaskListsProvider = StreamProvider<List<TaskList>>((ref) {
  final repo = ref.watch(calendarBooksRepositoryProvider);
  return repo.watchAllTaskLists();
});
final archivedTaskListsProvider = StreamProvider<List<TaskList>>((ref) {
  final repo = ref.watch(calendarBooksRepositoryProvider);
  return repo.watchArchivedTaskLists();
});

// ── 所有任务流 ────────────────────────────────────────────────────────────────

final allTasksProvider = StreamProvider<List<TaskItem>>((ref) {
  final repo = ref.watch(taskRepositoryProvider);
  return repo.watchAll();
});

// ── Tracker Repository ────────────────────────────────────────────────────────

final trackerRepositoryProvider = Provider<TrackerRepository>((ref) {
  final db = ref.watch(databaseProvider);
  return TrackerRepository(db);
}, dependencies: [databaseProvider]);

// ── Activity Record Repository ────────────────────────────────────────────────

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

// ── 热力图数据（过去一年）─────────────────────────────────────────────────────

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

// ── 拖拽状态 ───────────────────────────────────────────────────────────────
// 全局：当前拖拽光标是否在时间轴上方
final dragHoveringTimelineProvider = StateProvider<bool>((ref) => false);

// ── 当日活动记录流 ────────────────────────────────────────────────────────────

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
