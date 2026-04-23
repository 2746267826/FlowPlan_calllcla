import 'dart:io';

import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/database/app_database.dart';
import '../../../core/storage/app_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/providers/settings_provider.dart';
import '../data/tracker_repository.dart';
import '../models/activity_insights.dart';
import '../models/activity_log_entry.dart';
import '../models/input_event_query.dart';
import '../models/input_heatmap_summary.dart';
import '../models/tracked_input_event.dart';
import '../models/work_session.dart';
import '../services/raw_input_service.dart';
import '../services/tracker_platform_source.dart';
import '../services/tracker_service.dart';
import '../widgets/heatmap_widget.dart';

enum _TrackerMenuAction {
  viewDayDetails,
  viewLogHistory,
  viewInputHistory,
  exportInputEvents,
  exportDatabase,
  openDatabaseFolder,
  openLogArchiveFolder,
}

enum _TaskBindingSheetAction {
  unbind,
  createNew,
}

class _TrackerPageLoadKey {
  final DateTime selectedDate;
  final ActivityHeatmapScale? heatmapScaleOverride;
  final ActivityHeatmapBucket? analysisBucket;

  const _TrackerPageLoadKey({
    required this.selectedDate,
    required this.heatmapScaleOverride,
    required this.analysisBucket,
  });

  bool matches({
    required DateTime selectedDate,
    required ActivityHeatmapScale? heatmapScaleOverride,
    required ActivityHeatmapBucket? analysisBucket,
  }) {
    return DateUtils.isSameDay(this.selectedDate, selectedDate) &&
        this.heatmapScaleOverride == heatmapScaleOverride &&
        _isSameBucket(this.analysisBucket, analysisBucket);
  }
}

class _TrackerPageSnapshot {
  final AsyncValue<ActivityHeatmapSeries> heatmapAsync;
  final AsyncValue<List<ActivityRecord>> dayRecordsAsync;
  final ActivityInsights insights;
  final List<WorkSession> workSessions;
  final AsyncValue<InputHeatmapSummary> inputBehaviorSummaryAsync;
  final AsyncValue<TrackerRangeAnalysisSnapshot?> rangeAnalysisAsync;
  final TrackerState trackerState;
  final DateTime refreshedAt;

  const _TrackerPageSnapshot({
    required this.heatmapAsync,
    required this.dayRecordsAsync,
    required this.insights,
    required this.workSessions,
    required this.inputBehaviorSummaryAsync,
    required this.rangeAnalysisAsync,
    required this.trackerState,
    required this.refreshedAt,
  });

  _TrackerPageSnapshot copyWith({
    AsyncValue<ActivityHeatmapSeries>? heatmapAsync,
    AsyncValue<List<ActivityRecord>>? dayRecordsAsync,
    ActivityInsights? insights,
    List<WorkSession>? workSessions,
    AsyncValue<InputHeatmapSummary>? inputBehaviorSummaryAsync,
    AsyncValue<TrackerRangeAnalysisSnapshot?>? rangeAnalysisAsync,
    TrackerState? trackerState,
    DateTime? refreshedAt,
  }) {
    return _TrackerPageSnapshot(
      heatmapAsync: heatmapAsync ?? this.heatmapAsync,
      dayRecordsAsync: dayRecordsAsync ?? this.dayRecordsAsync,
      insights: insights ?? this.insights,
      workSessions: workSessions ?? this.workSessions,
      inputBehaviorSummaryAsync:
          inputBehaviorSummaryAsync ?? this.inputBehaviorSummaryAsync,
      rangeAnalysisAsync: rangeAnalysisAsync ?? this.rangeAnalysisAsync,
      trackerState: trackerState ?? this.trackerState,
      refreshedAt: refreshedAt ?? this.refreshedAt,
    );
  }
}

class _TrackerLoadTimeout implements Exception {
  final String message;

  const _TrackerLoadTimeout(this.message);

  @override
  String toString() => message;
}

class TrackerPage extends ConsumerStatefulWidget {
  const TrackerPage({super.key});

  @override
  ConsumerState<TrackerPage> createState() => _TrackerPageState();

  void _clearHeatmapBucketFilter(WidgetRef ref) {
    ref.read(trackerHistorySelectedHeatmapBucketProvider.notifier).state = null;
  }

  void _clearHeatmapAnalysisBucket(WidgetRef ref) {
    ref.read(trackerHistorySelectedAnalysisBucketProvider.notifier).state = null;
  }

  void _clearHeatmapSelections(WidgetRef ref) {
    _clearHeatmapBucketFilter(ref);
    _clearHeatmapAnalysisBucket(ref);
  }

  void _toggleHeatmapAnalysisBucket(
    WidgetRef ref,
    ActivityHeatmapBucket bucket,
  ) {
    final notifier =
        ref.read(trackerHistorySelectedAnalysisBucketProvider.notifier);
    final current = ref.read(trackerHistorySelectedAnalysisBucketProvider);
    notifier.state = _isSameBucket(current, bucket) ? null : bucket;
  }

  void _handleHeatmapBucketDrillDown(
    WidgetRef ref,
    ActivityHeatmapScale scale,
    ActivityHeatmapBucket bucket,
  ) {
    final dateNotifier = ref.read(selectedDateProvider.notifier);
    final scaleNotifier =
        ref.read(activityHeatmapScaleOverrideProvider.notifier);
    _clearHeatmapSelections(ref);

    switch (scale) {
      case ActivityHeatmapScale.hour:
        return;
      case ActivityHeatmapScale.day:
        dateNotifier.setDate(bucket.start);
        scaleNotifier.state = ActivityHeatmapScale.hour;
        return;
      case ActivityHeatmapScale.month:
        dateNotifier.setDate(bucket.start);
        scaleNotifier.state = ActivityHeatmapScale.day;
        return;
      case ActivityHeatmapScale.year:
        dateNotifier.setDate(bucket.start);
        scaleNotifier.state = ActivityHeatmapScale.month;
        return;
    }
  }

  void _toggleHistoryProcessFilter(WidgetRef ref, String processName) {
    final notifier = ref.read(trackerHistorySelectedProcessProvider.notifier);
    final current = ref.read(trackerHistorySelectedProcessProvider);
    notifier.state = current == processName ? null : processName;
  }

  void _toggleInputBehaviorHourFilter(
    WidgetRef ref,
    DateTime selectedDate,
    int hour,
  ) {
    final bucketStart = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      hour,
    );
    final bucket = ActivityHeatmapBucket(
      start: bucketStart,
      end: bucketStart.add(const Duration(hours: 1)),
      shortLabel: hour.toString().padLeft(2, '0'),
      longLabel:
          '${selectedDate.year}年${selectedDate.month}月${selectedDate.day}日 ${hour.toString().padLeft(2, '0')}:00',
      completedCount: 0,
      totalMinutes: 0,
    );

    final notifier =
        ref.read(trackerHistorySelectedHeatmapBucketProvider.notifier);
    final current = ref.read(trackerHistorySelectedHeatmapBucketProvider);
    notifier.state = _isSameBucket(current, bucket) ? null : bucket;
  }

  void _clearInputBehaviorLinkage(WidgetRef ref) {
    ref.read(trackerHistorySelectedProcessProvider.notifier).state = null;
    _clearHeatmapBucketFilter(ref);
  }

  int? _selectedInputBehaviorHour(
    ActivityHeatmapBucket? bucket,
    DateTime selectedDate,
  ) {
    if (bucket == null) {
      return null;
    }

    final dayStart = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final dayEnd = dayStart.add(const Duration(days: 1));
    final isHourlyBucket =
        bucket.end.difference(bucket.start) == const Duration(hours: 1);
    if (!isHourlyBucket ||
        bucket.start.isBefore(dayStart) ||
        bucket.end.isAfter(dayEnd)) {
      return null;
    }
    return bucket.start.hour;
  }

  static Future<void> _showTaskBindingSheet(
    BuildContext context,
    WidgetRef ref, {
    required String selectionLabel,
    required List<ActivityRecord> records,
    required List<TaskItem> availableTasks,
    required Map<int, TaskItem> taskById,
  }) async {
    final recordIds =
        records.map((record) => record.id).toSet().toList(growable: false);
    if (recordIds.isEmpty) {
      return;
    }

    final linkedTaskIds = _collectLinkedTaskIds(records);
    final action = await showModalBottomSheet<Object?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '关联任务',
                    style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    selectionLabel,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (linkedTaskIds.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '当前关联',
                      style: Theme.of(sheetContext)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: linkedTaskIds
                          .map(
                            (taskId) => _tag(
                              '任务：${_taskLabel(taskById[taskId], fallbackId: taskId)}',
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () {
                          Navigator.of(sheetContext)
                              .pop(_TaskBindingSheetAction.createNew);
                        },
                        icon: const Icon(Icons.add_task_outlined, size: 18),
                        label: const Text('新建任务'),
                      ),
                      if (linkedTaskIds.isNotEmpty)
                        OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(sheetContext)
                                .pop(_TaskBindingSheetAction.unbind);
                          },
                          icon: const Icon(Icons.link_off_outlined, size: 18),
                          label: const Text('取消关联'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '选择现有任务',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: availableTasks.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                '当前还没有可选任务，可以先创建任务再回来绑定。',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: availableTasks.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (sheetContext, index) {
                              final task = availableTasks[index];
                              final selected = linkedTaskIds.contains(task.id);
                              return ListTile(
                                onTap: () {
                                  Navigator.of(sheetContext).pop(task.id);
                                },
                                contentPadding: EdgeInsets.zero,
                                leading: Icon(
                                  selected
                                      ? Icons.task_alt_outlined
                                      : Icons.radio_button_unchecked,
                                  color: selected ? AppColors.primary : null,
                                ),
                                title: Text(
                                  task.summary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  _taskCandidateSubtitle(task),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: selected
                                    ? const Icon(
                                        Icons.check_circle,
                                        color: AppColors.primary,
                                      )
                                    : null,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (action == null) {
      return;
    }

    if (action == _TaskBindingSheetAction.createNew) {
      if (context.mounted) {
        context.push(AppRoutes.taskCreate);
      }
      return;
    }

    int? nextTaskId;
    if (action == _TaskBindingSheetAction.unbind) {
      nextTaskId = null;
    } else if (action is int) {
      nextTaskId = action;
    } else {
      return;
    }

    try {
      await ref
          .read(activityRecordRepositoryProvider)
          .linkTasks(recordIds, nextTaskId);
      ref.invalidate(activityRecordsForDateProvider);
      ref.invalidate(trackerRangeAnalysisRecordsProvider);
      ref.invalidate(trackerRangeAnalysisProvider);

      if (!context.mounted) {
        return;
      }

      final linkedTaskLabel = nextTaskId == null
          ? null
          : _taskLabel(taskById[nextTaskId], fallbackId: nextTaskId);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextTaskId == null
                ? '已取消 ${recordIds.length} 条活动记录的任务关联'
                : '已将 ${recordIds.length} 条活动记录关联到任务「$linkedTaskLabel」',
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('更新任务关联失败：$error'),
        ),
      );
    }
  }

  Future<void> _exportDatabase(BuildContext context, WidgetRef ref) async {
    try {
      final database = ref.read(databaseProvider);
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '\u5bfc\u51fa\u6570\u636e\u5e93\u526f\u672c',
        fileName:
            'flowplan-$appStorageFlavorLabel-backup-${_formatDate(DateTime.now())}.db',
        type: FileType.custom,
        allowedExtensions: const ['db', 'sqlite', 'sqlite3'],
      );

      if (outputPath == null || outputPath.trim().isEmpty) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('\u5df2\u53d6\u6d88\u5bfc\u51fa\u6570\u636e\u5e93'),
          ),
        );
        return;
      }

      await database.exportToFile(outputPath);

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '\u6570\u636e\u5e93\u5df2\u5bfc\u51fa\u5230\uff1a' + outputPath,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '\u5bfc\u51fa\u6570\u636e\u5e93\u5931\u8d25\uff1a$error',
          ),
        ),
      );
    }
  }

  Future<void> _openDatabaseFolder(BuildContext context, WidgetRef ref) async {
    try {
      final database = ref.read(databaseProvider);
      final databasePath = await database.getDatabasePath();
      final folderPath = File(databasePath).parent.path;

      if (Platform.isWindows) {
        await Process.start('explorer.exe', [folderPath]);
      }

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '\u5df2\u6253\u5f00\u6570\u636e\u5e93\u76ee\u5f55\uff1a' + folderPath,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '\u6253\u5f00\u6570\u636e\u5e93\u76ee\u5f55\u5931\u8d25\uff1a$error',
          ),
        ),
      );
    }
  }

  Future<void> _openLogArchiveFolder(BuildContext context, WidgetRef ref) async {
    try {
      final service = ref.read(activityLogServiceProvider);
      final folderPath = await service.getArchiveDirectoryPath();

      if (Platform.isWindows) {
        await Process.start('explorer.exe', [folderPath]);
      }

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已打开日志目录：$folderPath'),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('打开日志目录失败：$error'),
        ),
      );
    }
  }

  Future<void> _exportInputEvents(BuildContext context, WidgetRef ref) async {
    try {
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '\u5bfc\u51fa\u5b8c\u6574\u952e\u9f20\u8bb0\u5f55',
        fileName:
            'flowplan-$appStorageFlavorLabel-input-events-${_formatDate(DateTime.now())}.jsonl',
        type: FileType.custom,
        allowedExtensions: const ['jsonl'],
      );

      if (outputPath == null || outputPath.trim().isEmpty) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('\u5df2\u53d6\u6d88\u5bfc\u51fa\u952e\u9f20\u8bb0\u5f55'),
          ),
        );
        return;
      }

      final service = ref.read(inputActivityEventServiceProvider);
      await service.exportEventsToJsonl(outputPath);

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '\u952e\u9f20\u8bb0\u5f55\u5df2\u5bfc\u51fa\u5230\uff1a' + outputPath,
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '\u5bfc\u51fa\u952e\u9f20\u8bb0\u5f55\u5931\u8d25\uff1a$error',
          ),
        ),
      );
    }
  }

}

class _TrackerPageState extends ConsumerState<TrackerPage> {
  _TrackerPageSnapshot? _snapshot;
  _TrackerPageLoadKey? _loadedKey;
  _TrackerPageLoadKey? _scheduledKey;
  var _requestSerial = 0;
  var _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _refreshSnapshot(force: true);
    });
  }

  void _ensureSnapshotUpToDate({
    required DateTime selectedDate,
    required ActivityHeatmapScale? heatmapScaleOverride,
    required ActivityHeatmapBucket? selectedAnalysisBucket,
  }) {
    final isLoaded = _loadedKey?.matches(
          selectedDate: selectedDate,
          heatmapScaleOverride: heatmapScaleOverride,
          analysisBucket: selectedAnalysisBucket,
        ) ??
        false;
    if (isLoaded) {
      return;
    }

    final isScheduled = _scheduledKey?.matches(
          selectedDate: selectedDate,
          heatmapScaleOverride: heatmapScaleOverride,
          analysisBucket: selectedAnalysisBucket,
        ) ??
        false;
    if (isScheduled) {
      return;
    }

    _scheduledKey = _TrackerPageLoadKey(
      selectedDate: selectedDate,
      heatmapScaleOverride: heatmapScaleOverride,
      analysisBucket: selectedAnalysisBucket,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _refreshSnapshot();
    });
  }

  Future<AsyncValue<TrackerRangeAnalysisSnapshot?>> _loadRangeAnalysisSnapshot(
    ActivityHeatmapBucket? bucket,
  ) async {
    if (bucket == null) {
      return const AsyncData<TrackerRangeAnalysisSnapshot?>(null);
    }

    final recordRepository = ref.read(activityRecordRepositoryProvider);
    final logService = ref.read(activityLogServiceProvider);
    return AsyncValue.guard(() async {
      final records = await recordRepository.listInRange(bucket.start, bucket.end);
      final logEntries = await logService.readEntriesBetween(
        bucket.start,
        bucket.end,
      );
      return TrackerRangeAnalysisSnapshot(
        bucket: bucket,
        records: records,
        logEntries: logEntries,
        insights: ActivityInsights.fromRecords(records),
        sessions: WorkSessionGrouper.fromRecords(records),
      );
    });
  }

  _TrackerPageSnapshot _createLoadingSnapshot({
    required ActivityHeatmapBucket? selectedAnalysisBucket,
    required TrackerState trackerState,
  }) {
    return _TrackerPageSnapshot(
      heatmapAsync: const AsyncLoading<ActivityHeatmapSeries>(),
      dayRecordsAsync: const AsyncLoading<List<ActivityRecord>>(),
      insights: ActivityInsights.empty(),
      workSessions: const <WorkSession>[],
      inputBehaviorSummaryAsync: const AsyncLoading<InputHeatmapSummary>(),
      rangeAnalysisAsync: selectedAnalysisBucket == null
          ? const AsyncData<TrackerRangeAnalysisSnapshot?>(null)
          : const AsyncLoading<TrackerRangeAnalysisSnapshot?>(),
      trackerState: trackerState,
      refreshedAt: DateTime.now(),
    );
  }

  void _updateSnapshotPart({
    required int requestId,
    required _TrackerPageLoadKey key,
    AsyncValue<ActivityHeatmapSeries>? heatmapAsync,
    AsyncValue<List<ActivityRecord>>? dayRecordsAsync,
    ActivityInsights? insights,
    List<WorkSession>? workSessions,
    AsyncValue<InputHeatmapSummary>? inputBehaviorSummaryAsync,
    AsyncValue<TrackerRangeAnalysisSnapshot?>? rangeAnalysisAsync,
    TrackerState? trackerState,
  }) {
    if (!mounted || requestId != _requestSerial) {
      return;
    }

    setState(() {
      final currentSnapshot = _snapshot;
      if (currentSnapshot == null) {
        return;
      }
      _snapshot = currentSnapshot.copyWith(
        heatmapAsync: heatmapAsync,
        dayRecordsAsync: dayRecordsAsync,
        insights: insights,
        workSessions: workSessions,
        inputBehaviorSummaryAsync: inputBehaviorSummaryAsync,
        rangeAnalysisAsync: rangeAnalysisAsync,
        trackerState: trackerState,
        refreshedAt: DateTime.now(),
      );
      _loadedKey = key;
    });
  }

  Future<T> _withLoadTimeout<T>(Future<T> future, String label) {
    return future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {
        throw _TrackerLoadTimeout('$label加载超时，请点击右上角刷新重试。');
      },
    );
  }

  Future<void> _refreshSnapshot({
    bool refreshTrackerNow = false,
    bool force = false,
  }) async {
    final selectedDate = ref.read(selectedDateProvider);
    final heatmapScaleOverride = ref.read(activityHeatmapScaleOverrideProvider);
    final selectedAnalysisBucket =
        ref.read(trackerHistorySelectedAnalysisBucketProvider);
    final key = _TrackerPageLoadKey(
      selectedDate: selectedDate,
      heatmapScaleOverride: heatmapScaleOverride,
      analysisBucket: selectedAnalysisBucket,
    );

    if (!force &&
        (_loadedKey?.matches(
              selectedDate: selectedDate,
              heatmapScaleOverride: heatmapScaleOverride,
              analysisBucket: selectedAnalysisBucket,
            ) ??
            false)) {
      _scheduledKey = null;
      return;
    }

    final requestId = ++_requestSerial;
    _scheduledKey = null;
    final initialTrackerState = ref.read(trackerServiceNotifierProvider);
    if (mounted) {
      setState(() {
        _isRefreshing = true;
        _snapshot = _createLoadingSnapshot(
          selectedAnalysisBucket: selectedAnalysisBucket,
          trackerState: initialTrackerState,
        );
        _loadedKey = key;
      });
    }

    try {
      if (refreshTrackerNow) {
        await ref.read(trackerServiceNotifierProvider.notifier).refreshNow();
      }

      final trackerRepository = ref.read(trackerRepositoryProvider);
      final activityRecordRepository =
          ref.read(activityRecordRepositoryProvider);
      final supportsInputAnalytics =
          TrackerPlatformSource.current().supportsInputAnalytics;
      final inputActivityEventService = supportsInputAnalytics
          ? ref.read(inputActivityEventServiceProvider)
          : null;
      final dayStart = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
      );
      final dayEnd = dayStart.add(const Duration(days: 1));
      final inputQuery = InputEventQuery(
        start: dayStart,
        end: dayEnd,
      );
      final trackerState = ref.read(trackerServiceNotifierProvider);
      _updateSnapshotPart(
        requestId: requestId,
        key: key,
        trackerState: trackerState,
      );

      final heatmapFuture = AsyncValue.guard(
        () => _withLoadTimeout(
          () async {
            final summary = await trackerRepository.getHistorySummary();
            final scale = heatmapScaleOverride ?? summary.recommendedScale;
            return trackerRepository.getHeatmapSeries(
              scale: scale,
              anchorDate: selectedDate,
              historySummary: summary,
            );
          }(),
          '热力图',
        ),
      );
      final dayRecordsFuture = AsyncValue.guard(
        () => _withLoadTimeout(
          activityRecordRepository.listInRange(dayStart, dayEnd),
          '今日活动记录',
        ),
      );
      final inputBehaviorFuture = supportsInputAnalytics
          ? AsyncValue.guard(
              () => _withLoadTimeout(
                inputActivityEventService!.buildHeatmapSummary(inputQuery),
                '输入行为分析',
              ),
            )
          : Future.value(
              AsyncData<InputHeatmapSummary>(
                InputHeatmapSummary.empty(inputQuery),
              ),
            );
      final rangeAnalysisFuture = _withLoadTimeout(
        _loadRangeAnalysisSnapshot(selectedAnalysisBucket),
        '范围分析',
      );

      await Future.wait<void>([
        () async {
          final heatmapAsync = await heatmapFuture;
          _updateSnapshotPart(
            requestId: requestId,
            key: key,
            heatmapAsync: heatmapAsync,
          );
        }(),
        () async {
          final dayRecordsAsync = await dayRecordsFuture;
          final records = dayRecordsAsync.valueOrNull ?? const <ActivityRecord>[];
          _updateSnapshotPart(
            requestId: requestId,
            key: key,
            dayRecordsAsync: dayRecordsAsync,
            insights: dayRecordsAsync.hasValue
                ? ActivityInsights.fromRecords(records)
                : ActivityInsights.empty(),
            workSessions: dayRecordsAsync.hasValue
                ? WorkSessionGrouper.fromRecords(records)
                : const <WorkSession>[],
          );
        }(),
        () async {
          final inputBehaviorSummaryAsync = await inputBehaviorFuture;
          _updateSnapshotPart(
            requestId: requestId,
            key: key,
            inputBehaviorSummaryAsync: inputBehaviorSummaryAsync,
          );
        }(),
        () async {
          final rangeAnalysisAsync = await rangeAnalysisFuture;
          _updateSnapshotPart(
            requestId: requestId,
            key: key,
            rangeAnalysisAsync: rangeAnalysisAsync,
          );
        }(),
      ]);
    } finally {
      if (mounted && requestId == _requestSerial) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final trackerPlatform = TrackerPlatformSource.current();
    final supportsInputAnalytics = trackerPlatform.supportsInputAnalytics;
    final pageWidth = MediaQuery.of(context).size.width;
    final isCompactLayout = pageWidth < 600;
    final sequenceEnabled = ref.watch(sequenceRecordingProvider);
    final heatmapScaleOverride =
        ref.watch(activityHeatmapScaleOverrideProvider);
    final selectedProcessRaw = ref.watch(trackerHistorySelectedProcessProvider);
    final selectedHeatmapBucket =
        ref.watch(trackerHistorySelectedHeatmapBucketProvider);
    final selectedAnalysisBucket =
        ref.watch(trackerHistorySelectedAnalysisBucketProvider);
    final isTrackingRunning = ref.watch(
      trackerServiceNotifierProvider.select((state) => state.isRunning),
    );
    final androidUsagePermission = ref.watch(
      trackerServiceNotifierProvider.select(
        (state) => state.hasUsageStatsPermission,
      ),
    );
    final selectedProcess = selectedProcessRaw?.trim().isNotEmpty == true
        ? selectedProcessRaw!.trim()
        : null;
    final selectedInputBehaviorHour =
        widget._selectedInputBehaviorHour(selectedHeatmapBucket, selectedDate);
    final hasLinkedInputBehavior = supportsInputAnalytics &&
        (selectedProcess != null || selectedInputBehaviorHour != null);

    _ensureSnapshotUpToDate(
      selectedDate: selectedDate,
      heatmapScaleOverride: heatmapScaleOverride,
      selectedAnalysisBucket: selectedAnalysisBucket,
    );

    final snapshot = _snapshot;
    final hasFreshSnapshot = snapshot != null &&
        (_loadedKey?.matches(
              selectedDate: selectedDate,
              heatmapScaleOverride: heatmapScaleOverride,
              analysisBucket: selectedAnalysisBucket,
            ) ??
            false);
    final AsyncValue<ActivityHeatmapSeries> heatmapAsync = hasFreshSnapshot
        ? snapshot!.heatmapAsync
        : const AsyncLoading<ActivityHeatmapSeries>();
    final AsyncValue<List<ActivityRecord>> dayRecordsAsync = hasFreshSnapshot
        ? snapshot!.dayRecordsAsync
        : const AsyncLoading<List<ActivityRecord>>();
    final ActivityInsights insights =
        hasFreshSnapshot ? snapshot!.insights : ActivityInsights.empty();
    final List<WorkSession> workSessions =
        hasFreshSnapshot ? snapshot!.workSessions : const <WorkSession>[];
    final AsyncValue<InputHeatmapSummary> inputBehaviorSummaryAsync = hasFreshSnapshot
        ? snapshot!.inputBehaviorSummaryAsync
        : const AsyncLoading<InputHeatmapSummary>();
    final AsyncValue<TrackerRangeAnalysisSnapshot?> rangeAnalysisAsync = hasFreshSnapshot
        ? snapshot!.rangeAnalysisAsync
        : (selectedAnalysisBucket == null
            ? const AsyncData<TrackerRangeAnalysisSnapshot?>(null)
            : const AsyncLoading<TrackerRangeAnalysisSnapshot?>());
    final trackerState = (snapshot?.trackerState ?? const TrackerState())
        .copyWith(isRunning: isTrackingRunning);
    final hasAndroidUsageAccess =
        androidUsagePermission ?? trackerState.hasUsageStatsPermission;
    final lastRefreshedAt = snapshot?.refreshedAt;
    final freezeNotice = !hasFreshSnapshot && _isRefreshing
        ? '该页面已暂停自动刷新。正在按当前条件加载新的手动快照，后台记录不会中断。'
        : (lastRefreshedAt == null
            ? '该页面已暂停自动刷新。进入页面后会固定当前快照，后台仍继续记录；点击右上角刷新后才会更新显示。'
            : '该页面已暂停自动刷新。当前显示固定在 ${_formatDateTimeShort(lastRefreshedAt)} 的快照；后台仍继续记录，点击右上角刷新后才会更新显示。');

    return Scaffold(
      appBar: AppBar(
        title: const Text('活动追踪'),
        actions: [
          if (supportsInputAnalytics)
            IconButton(
              tooltip: sequenceEnabled ? '关闭按键序列记录' : '开启按键序列记录',
              icon: Icon(
                sequenceEnabled
                    ? Icons.keyboard_alt
                    : Icons.keyboard_alt_outlined,
              ),
              onPressed: () {
                ref.read(sequenceRecordingNotifierProvider.notifier).set(
                      !sequenceEnabled,
                    );
              },
            ),
          Switch(
            value: isTrackingRunning,
            activeThumbColor: AppColors.primary,
            onChanged: (value) {
              final notifier = ref.read(trackerServiceNotifierProvider.notifier);
              value ? notifier.start() : notifier.stop();
            },
          ),
          IconButton(
            tooltip: _isRefreshing ? '正在手动刷新' : '手动刷新（自动刷新已关闭）',
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(Icons.refresh_outlined),
            onPressed: _isRefreshing
                ? null
                : () async {
                    await _refreshSnapshot(
                      refreshTrackerNow: true,
                      force: true,
                    );
                  },
          ),
          if (supportsInputAnalytics)
            IconButton(
              tooltip: '键鼠热力图',
              icon: const Icon(Icons.keyboard_outlined),
              onPressed: () {
                context.push(AppRoutes.trackerInputHeatmap);
              },
            ),
          PopupMenuButton<_TrackerMenuAction>(
            tooltip: '更多操作',
            onSelected: (action) {
              switch (action) {
                case _TrackerMenuAction.viewDayDetails:
                  context.push(AppRoutes.trackerDayDetails);
                  break;
                case _TrackerMenuAction.viewLogHistory:
                  context.push(AppRoutes.trackerLogHistory);
                  break;
                case _TrackerMenuAction.viewInputHistory:
                  context.push(AppRoutes.trackerInputHistory);
                  break;
                case _TrackerMenuAction.exportInputEvents:
                  widget._exportInputEvents(context, ref);
                  break;
                case _TrackerMenuAction.exportDatabase:
                  widget._exportDatabase(context, ref);
                  break;
                case _TrackerMenuAction.openDatabaseFolder:
                  widget._openDatabaseFolder(context, ref);
                  break;
                case _TrackerMenuAction.openLogArchiveFolder:
                  widget._openLogArchiveFolder(context, ref);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _TrackerMenuAction.viewDayDetails,
                child: Text('查看今日详细数据'),
              ),
              const PopupMenuItem(
                value: _TrackerMenuAction.viewLogHistory,
                child: Text('查看历史日志文件'),
              ),
              if (supportsInputAnalytics)
                const PopupMenuItem(
                  value: _TrackerMenuAction.viewInputHistory,
                  child: Text('查看完整输入历史'),
                ),
              if (supportsInputAnalytics)
                const PopupMenuItem(
                  value: _TrackerMenuAction.exportInputEvents,
                  child: Text('导出完整键鼠记录'),
                ),
              const PopupMenuItem(
                value: _TrackerMenuAction.exportDatabase,
                child: Text('导出数据库副本'),
              ),
              const PopupMenuItem(
                value: _TrackerMenuAction.openDatabaseFolder,
                child: Text('打开数据库目录'),
              ),
              const PopupMenuItem(
                value: _TrackerMenuAction.openLogArchiveFolder,
                child: Text('打开日志归档目录'),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isCompactLayout ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HistoryToolbar(selectedDate: selectedDate),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.pause_circle_outline,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      freezeNotice,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (trackerPlatform.isAndroid) ...[
              _AndroidTrackingModePanel(
                hasUsageAccess: hasAndroidUsageAccess,
                platformDescription: trackerPlatform.collectionDescription,
                lastSampleAt: trackerState.lastSampleAt,
                isRefreshing: _isRefreshing,
                onOpenUsageAccessSettings: () {
                  ref
                      .read(trackerServiceNotifierProvider.notifier)
                      .openAndroidUsageAccessSettings();
                },
                onRefresh: () async {
                  await _refreshSnapshot(
                    refreshTrackerNow: true,
                    force: true,
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
            if (trackerPlatform.isAndroid && hasAndroidUsageAccess == false) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5A623).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: const Color(0xFFF5A623).withValues(alpha: 0.18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          size: 18,
                          color: Color(0xFFB26A00),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '安卓端需要“使用情况访问权限”后，才能导入应用前台使用记录。',
                            style:
                                Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '当前版本只会在打开应用或手动刷新时读取系统使用记录，不会常驻后台。授权后点击刷新即可把近期应用会话导入到追踪中。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () {
                            ref
                                .read(trackerServiceNotifierProvider.notifier)
                                .openAndroidUsageAccessSettings();
                          },
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('前往授权'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _isRefreshing
                              ? null
                              : () async {
                                  await _refreshSnapshot(
                                    refreshTrackerNow: true,
                                    force: true,
                                  );
                                },
                          icon: const Icon(Icons.refresh_outlined, size: 18),
                          label: const Text('授权后刷新'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            _card(
              context,
              heatmapAsync.when(
                loading: () => const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => SizedBox(
                  height: 180,
                  child: Center(
                    child: Text('加载热力图失败：$error'),
                  ),
                ),
                data: (series) => HeatmapWidget(
                  series: series,
                  selectedScaleOverride: heatmapScaleOverride,
                  activeFilterBucket: selectedHeatmapBucket,
                  activeAnalysisBucket: selectedAnalysisBucket,
                  onScaleChanged: (scale) {
                    widget._clearHeatmapSelections(ref);
                    ref.read(activityHeatmapScaleOverrideProvider.notifier).state =
                        scale;
                  },
                  onFilterBucket: (bucket) {
                    ref
                        .read(trackerHistorySelectedHeatmapBucketProvider.notifier)
                        .state = bucket;
                  },
                  onAnalyzeBucket: (bucket) {
                    widget._toggleHeatmapAnalysisBucket(ref, bucket);
                  },
                  onDrillDownBucket: (bucket) {
                    widget._handleHeatmapBucketDrillDown(
                      ref,
                      series.scale,
                      bucket,
                    );
                  },
                  onClearBucketFilter: () => widget._clearHeatmapBucketFilter(ref),
                  onClearAnalysisBucket: () =>
                      widget._clearHeatmapAnalysisBucket(ref),
                ),
              ),
            ),
            if (selectedAnalysisBucket != null) ...[
              const SizedBox(height: 16),
              rangeAnalysisAsync.when(
                loading: () => _card(
                  context,
                  const SizedBox(
                    height: 180,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
                error: (error, _) => _card(
                  context,
                  SizedBox(
                    height: 160,
                    child: Center(
                      child: Text('加载区间分析失败：$error'),
                    ),
                  ),
                ),
                data: (snapshot) {
                  if (snapshot == null) {
                    return const SizedBox.shrink();
                  }
                  return _card(
                    context,
                    _SelectedRangeAnalysisPanel(
                      snapshot: snapshot,
                      onClose: () => widget._clearHeatmapAnalysisBucket(ref),
                    ),
                  );
                },
              ),
            ],
            const SizedBox(height: 16),
            _card(
              context,
              _CurrentSessionPanel(
                state: trackerState,
                sequenceEnabled: sequenceEnabled,
                showInputTelemetry: supportsInputAnalytics,
                onToggleSequence: supportsInputAnalytics
                    ? () {
                        ref.read(sequenceRecordingNotifierProvider.notifier).set(
                              !sequenceEnabled,
                            );
                      }
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            _card(
              context,
              dayRecordsAsync.when(
                loading: () => const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => SizedBox(
                  height: 120,
                  child: Center(
                    child: Text('加载日报摘要失败：$error'),
                  ),
                ),
                data: (_) => _DailyOverview(
                  selectedDate: selectedDate,
                  insights: insights,
                  workSessionCount: workSessions.length,
                  showInputMetrics: supportsInputAnalytics,
                ),
              ),
            ),
            if (supportsInputAnalytics) ...[
              const SizedBox(height: 16),
              _card(
                context,
                _DailyInputBehaviorPanel(
                  selectedDate: selectedDate,
                  summaryAsync: inputBehaviorSummaryAsync,
                  selectedProcess: selectedProcess,
                  selectedHour: selectedInputBehaviorHour,
                  onApplyProcessFilter: (processName) {
                    widget._toggleHistoryProcessFilter(ref, processName);
                  },
                  onApplyHourFilter: (hour) {
                    widget._toggleInputBehaviorHourFilter(
                      ref,
                      selectedDate,
                      hour,
                    );
                  },
                  onClearLinkage: hasLinkedInputBehavior
                      ? () => widget._clearInputBehaviorLinkage(ref)
                      : null,
                  onOpenFullAnalysis: () {
                    context.push(AppRoutes.trackerInputHeatmap);
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
            _card(
              context,
              _TrackerDetailHubPanel(
                selectedDate: selectedDate,
                workSessionCount: workSessions.length,
                activityRecordCount: insights.records.length,
                hasLinkedInputBehavior: hasLinkedInputBehavior,
                onOpenDayDetails: () {
                  context.push(AppRoutes.trackerDayDetails);
                },
                onOpenInputHistory: supportsInputAnalytics
                    ? () {
                        context.push(AppRoutes.trackerInputHistory);
                      }
                    : null,
                onOpenLogHistory: () {
                  context.push(AppRoutes.trackerLogHistory);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AndroidTrackingModePanel extends StatelessWidget {
  const _AndroidTrackingModePanel({
    required this.hasUsageAccess,
    required this.platformDescription,
    required this.lastSampleAt,
    required this.isRefreshing,
    required this.onOpenUsageAccessSettings,
    required this.onRefresh,
  });

  final bool? hasUsageAccess;
  final String platformDescription;
  final DateTime? lastSampleAt;
  final bool isRefreshing;
  final VoidCallback onOpenUsageAccessSettings;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final granted = hasUsageAccess == true;
    final statusText = hasUsageAccess == null
        ? '等待权限检查'
        : (granted ? '使用情况访问权限已开启' : '尚未开启使用情况访问权限');
    final lastRefreshText = lastSampleAt == null
        ? '尚未导入'
        : '上次导入：${_formatDateTimeShort(lastSampleAt!)}';

    return _card(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                granted
                    ? Icons.mobile_friendly_outlined
                    : Icons.mobile_off_outlined,
                size: 18,
                color: granted ? const Color(0xFF0EA8A0) : Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '安卓追踪模式',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              _statusBadge(
                statusText,
                granted ? const Color(0xFF0EA8A0) : Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '$platformDescription 追踪页会优先展示应用名，包名仅作为技术标识保存在底层数据中。',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _tag(lastRefreshText),
              OutlinedButton.icon(
                onPressed: onOpenUsageAccessSettings,
                icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                label: const Text('使用情况权限'),
              ),
              FilledButton.tonalIcon(
                onPressed: isRefreshing ? null : onRefresh,
                icon: const Icon(Icons.refresh_outlined, size: 18),
                label: Text(isRefreshing ? '正在刷新' : '立即导入'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class TrackerDayDetailsPage extends ConsumerWidget {
  const TrackerDayDetailsPage({super.key});

  void _returnToTrackerOverview(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      context.pop();
      return;
    }
    context.go(AppRoutes.tracker);
  }

  void _toggleProcessAnalysisLink(
    BuildContext context,
    WidgetRef ref,
    String processName,
  ) {
    final notifier = ref.read(trackerHistorySelectedProcessProvider.notifier);
    final current = ref.read(trackerHistorySelectedProcessProvider);
    notifier.state = current == processName ? null : processName;
    _returnToTrackerOverview(context);
  }

  void _toggleHourAnalysisLink(
    BuildContext context,
    WidgetRef ref,
    DateTime selectedDate,
    int hour,
  ) {
    final bucketStart = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      hour,
    );
    final bucket = ActivityHeatmapBucket(
      start: bucketStart,
      end: bucketStart.add(const Duration(hours: 1)),
      shortLabel: hour.toString().padLeft(2, '0'),
      longLabel:
          '${selectedDate.year}年${selectedDate.month}月${selectedDate.day}日 ${hour.toString().padLeft(2, '0')}:00',
      completedCount: 0,
      totalMinutes: 0,
    );

    final notifier =
        ref.read(trackerHistorySelectedHeatmapBucketProvider.notifier);
    final current = ref.read(trackerHistorySelectedHeatmapBucketProvider);
    notifier.state = _isSameBucket(current, bucket) ? null : bucket;
    _returnToTrackerOverview(context);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const logPreviewLimit = 80;
    final supportsInputAnalytics =
        TrackerPlatformSource.current().supportsInputAnalytics;
    final selectedDate = ref.watch(selectedDateProvider);
    final recordsAsync = ref.watch(activityRecordsForDateProvider);
    final logEntriesAsync = ref.watch(activityLogEntriesForDateProvider);
    final logStoragePathAsync = ref.watch(activityLogStoragePathProvider);
    final logArchivePathAsync =
        ref.watch(activityLogArchiveDirectoryPathProvider);
    final filterOptions = ref.watch(trackerHistoryFilterOptionsProvider);
    final allTasksAsync = ref.watch(allTasksProvider);
    final searchQuery = ref.watch(trackerHistorySearchQueryProvider);
    final selectedProcessRaw = ref.watch(trackerHistorySelectedProcessProvider);
    final selectedCategoryRaw = ref.watch(trackerHistorySelectedCategoryProvider);
    final selectedTaskIdRaw = ref.watch(trackerHistorySelectedTaskIdProvider);
    final onlyWithInput = ref.watch(trackerHistoryOnlyWithInputProvider);
    final selectedHeatmapBucket =
        ref.watch(trackerHistorySelectedHeatmapBucketProvider);

    final records = recordsAsync.valueOrNull ?? const <ActivityRecord>[];
    final workSessions = records.isEmpty
        ? const <WorkSession>[]
        : WorkSessionGrouper.fromRecords(records);
    final logEntries = logEntriesAsync.valueOrNull ?? const <ActivityLogEntry>[];
    final allTasks = allTasksAsync.valueOrNull ?? const <TaskItem>[];
    final taskById = <int, TaskItem>{
      for (final task in allTasks) task.id: task,
    };
    final selectedProcess = selectedProcessRaw?.trim().isNotEmpty == true
        ? selectedProcessRaw!.trim()
        : null;
    final selectedCategory = selectedCategoryRaw?.trim().isNotEmpty == true
        ? selectedCategoryRaw!.trim()
        : null;
    final selectedTaskId = selectedTaskIdRaw;
    final selectedProcessForDropdown =
        selectedProcess != null &&
            filterOptions.processOptions.contains(selectedProcess)
        ? selectedProcess
        : null;
    final selectedCategoryForDropdown =
        selectedCategory != null &&
            filterOptions.categoryOptions.contains(selectedCategory)
        ? selectedCategory
        : null;
    final selectedRecordIds = selectedTaskId == null
        ? null
        : records
            .where((record) => record.linkedTaskId == selectedTaskId)
            .map((record) => record.id)
            .toSet();
    final filteredWorkSessions = workSessions
        .where(
          (session) => _matchesWorkSession(
            session,
            searchQuery: searchQuery,
            selectedProcess: selectedProcess,
            selectedCategory: selectedCategory,
            selectedTaskId: selectedTaskId,
            onlyWithInput: onlyWithInput,
            selectedHeatmapBucket: selectedHeatmapBucket,
          ),
        )
        .toList(growable: false);
    final filteredLogEntries = logEntries
        .where(
          (entry) => _matchesLogEntry(
            entry,
            searchQuery: searchQuery,
            selectedProcess: selectedProcess,
            selectedCategory: selectedCategory,
            selectedRecordIds: selectedRecordIds,
            onlyWithInput: onlyWithInput,
            selectedHeatmapBucket: selectedHeatmapBucket,
          ),
        )
        .toList(growable: false);
    final filteredLogEntriesPreview = filteredLogEntries
        .take(logPreviewLimit)
        .toList(growable: false);
    final taskOptions = _buildTaskFilterOptions(
      records: records,
      taskById: taskById,
    );
    final selectedTaskIdForDropdown =
        selectedTaskId != null &&
            taskOptions.any((task) => task.id == selectedTaskId)
        ? selectedTaskId
        : null;
    final taskCandidates = _buildTrackerTaskCandidates(allTasks, selectedDate);
    final selectedTimeBucketLabel = selectedHeatmapBucket?.longLabel;
    final hasLinkedInputBehavior = supportsInputAnalytics &&
        (selectedProcess != null || selectedTimeBucketLabel != null);
    final hasActiveHistoryFilters =
        searchQuery.trim().isNotEmpty ||
        selectedProcess != null ||
        selectedCategory != null ||
        selectedTaskId != null ||
        onlyWithInput ||
        selectedTimeBucketLabel != null;
    final logStoragePath = logStoragePathAsync.valueOrNull;
    final logArchivePath = logArchivePathAsync.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('追踪详细数据'),
        actions: [
          IconButton(
            tooltip: '返回摘要与分析',
            icon: const Icon(Icons.analytics_outlined),
            onPressed: () {
              _returnToTrackerOverview(context);
            },
          ),
          IconButton(
            tooltip: '查看历史日志文件',
            icon: const Icon(Icons.article_outlined),
            onPressed: () {
              context.push(AppRoutes.trackerLogHistory);
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HistoryToolbar(selectedDate: selectedDate),
            const SizedBox(height: 16),
            _card(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.dataset_linked_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '详细数据工作台',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '主页现在只保留摘要和分析，本页承载历史筛选、工作会话和原始日志，减少主页卡顿。',
                              style:
                                  TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _tag('日期：${_formatDate(selectedDate)}'),
                      _tag('${filteredWorkSessions.length}/${workSessions.length} 段会话'),
                      _tag('${filteredLogEntries.length}/${logEntries.length} 条日志'),
                      if (selectedProcess != null) _tag('联动应用：$selectedProcess'),
                      if (selectedTimeBucketLabel != null)
                        _tag('联动时段：$selectedTimeBucketLabel'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () {
                          _returnToTrackerOverview(context);
                        },
                        icon: const Icon(Icons.analytics_outlined, size: 18),
                        label: Text(
                          hasLinkedInputBehavior ? '返回查看已联动分析' : '返回摘要与分析',
                        ),
                      ),
                      if (supportsInputAnalytics)
                        OutlinedButton.icon(
                          onPressed: () {
                            context.push(AppRoutes.trackerInputHistory);
                          },
                          icon: const Icon(Icons.keyboard_outlined, size: 18),
                          label: const Text('查看完整输入历史'),
                        ),
                      OutlinedButton.icon(
                        onPressed: () {
                          context.push(AppRoutes.trackerLogHistory);
                        },
                        icon: const Icon(Icons.article_outlined, size: 18),
                        label: const Text('查看历史日志文件'),
                      ),
                    ],
                  ),
                  if (hasActiveHistoryFilters) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '当前筛选已作用于下方会话和日志列表，适合在这里做细查，避免主页一次性渲染过多内容。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            _card(
              context,
              _HistoryFilterPanel(
                options: filterOptions,
                searchQuery: searchQuery,
                selectedProcess: selectedProcessForDropdown,
                selectedCategory: selectedCategoryForDropdown,
                taskOptions: taskOptions,
                selectedTaskId: selectedTaskIdForDropdown,
                onlyWithInput: onlyWithInput,
                selectedTimeBucketLabel: selectedTimeBucketLabel,
                filteredSessionCount: filteredWorkSessions.length,
                totalSessionCount: workSessions.length,
                filteredLogCount: filteredLogEntries.length,
                totalLogCount: logEntries.length,
              ),
            ),
            const SizedBox(height: 16),
            _card(
              context,
              recordsAsync.when(
                loading: () => const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => SizedBox(
                  height: 180,
                  child: Center(
                    child: Text('加载工作会话失败：$error'),
                  ),
                ),
                data: (_) {
                  if (filteredWorkSessions.isEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TrackerSectionHeader(
                          icon: Icons.work_history_outlined,
                          title: '工作会话',
                          subtitle: '把零散窗口切换整理为更连贯的工作段，减少频繁切换造成的阅读噪音。',
                          trailing: Text(
                            '${workSessions.length} 段',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '当前筛选下没有工作会话，可尝试清空筛选后再查看。',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TrackerSectionHeader(
                        icon: Icons.work_history_outlined,
                        title: '工作会话',
                        subtitle: supportsInputAnalytics
                            ? '点击“查看某应用输入分析”后会返回到主页分析区，并自动保留联动条件。'
                            : '这里展示当前筛选下的工作会话拆分结果，便于在移动端查看应用使用片段。',
                        trailing: Text(
                          '${filteredWorkSessions.length}/${workSessions.length} 段',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...filteredWorkSessions.map(
                        (session) => _WorkSessionTile(
                          session: session,
                          selectedDate: selectedDate,
                          selectedProcess: selectedProcess,
                          selectedHour: _selectedHourForCurrentBucket(
                            selectedHeatmapBucket,
                            selectedDate,
                          ),
                          taskById: taskById,
                          onLinkProcessAnalysis: supportsInputAnalytics
                              ? (processName) {
                                  _toggleProcessAnalysisLink(
                                    context,
                                    ref,
                                    processName,
                                  );
                                }
                              : null,
                          onLinkHourAnalysis: supportsInputAnalytics
                              ? (hour) {
                                  _toggleHourAnalysisLink(
                                    context,
                                    ref,
                                    selectedDate,
                                    hour,
                                  );
                                }
                              : null,
                          onBindTask: () {
                            TrackerPage._showTaskBindingSheet(
                              context,
                              ref,
                              selectionLabel:
                                  '工作会话：${session.label} · ${_formatSessionRange(session.startTime, session.endTime)}',
                              records: session.records,
                              availableTasks: taskCandidates,
                              taskById: taskById,
                            );
                          },
                          onOpenTask: (taskId) {
                            context.push('/task/$taskId');
                          },
                          onBindRecordTask: (record) {
                            TrackerPage._showTaskBindingSheet(
                              context,
                              ref,
                              selectionLabel:
                                  '原始记录：${WorkSessionGrouper.preferredLabel(record)} · ${_formatTime(record.startTime)} - ${_formatTime(record.endTime ?? record.startTime)}',
                              records: [record],
                              availableTasks: taskCandidates,
                              taskById: taskById,
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            _card(
              context,
              logEntriesAsync.when(
                loading: () => const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => SizedBox(
                  height: 180,
                  child: Center(
                    child: Text('加载原始日志失败：$error'),
                  ),
                ),
                data: (_) {
                  if (filteredLogEntries.isEmpty) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _TrackerSectionHeader(
                          icon: Icons.receipt_long_outlined,
                          title: '原始日志预览',
                          subtitle: '这里保留当天明细预览，完整历史请进入日志页查看。',
                        ),
                        const SizedBox(height: 12),
                        Text(
                          logStoragePath == null
                              ? '当前筛选下没有可显示的日志。'
                              : '当前筛选下没有可显示的日志。日志文件位置：$logStoragePath',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TrackerSectionHeader(
                        icon: Icons.receipt_long_outlined,
                        title: '原始日志预览',
                        subtitle:
                            '为保证本页流畅度，这里只渲染前 $logPreviewLimit 条；完整日志可进入日志历史页查看。',
                        trailing: TextButton.icon(
                          onPressed: () {
                            context.push(AppRoutes.trackerLogHistory);
                          },
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('打开日志页'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (logStoragePath != null || logArchivePath != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (logStoragePath != null)
                                Text(
                                  '当日日志：$logStoragePath',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                              if (logArchivePath != null)
                                Text(
                                  '归档目录：$logArchivePath',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ...filteredLogEntriesPreview.map(
                        (entry) => _LogEntryTile(
                          entry: entry,
                          showDetails: true,
                        ),
                      ),
                      if (filteredLogEntries.length > filteredLogEntriesPreview.length)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '还有 ${filteredLogEntries.length - filteredLogEntriesPreview.length} 条日志未在本页渲染，可进入“历史日志文件”查看完整内容。',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackerDetailHubPanel extends StatelessWidget {
  final DateTime selectedDate;
  final int workSessionCount;
  final int activityRecordCount;
  final bool hasLinkedInputBehavior;
  final VoidCallback onOpenDayDetails;
  final VoidCallback? onOpenInputHistory;
  final VoidCallback onOpenLogHistory;

  const _TrackerDetailHubPanel({
    required this.selectedDate,
    required this.workSessionCount,
    required this.activityRecordCount,
    required this.hasLinkedInputBehavior,
    required this.onOpenDayDetails,
    required this.onOpenInputHistory,
    required this.onOpenLogHistory,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.dashboard_customize_outlined,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '详细数据入口',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '主页面只保留摘要和分析，重型列表与原始日志已迁到二级页面，减少首屏卡顿。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _tag('日期：${_formatDate(selectedDate)}'),
            _tag('$workSessionCount 段工作会话'),
            _tag('$activityRecordCount 条活动记录'),
            if (hasLinkedInputBehavior) _tag('已保留输入行为联动'),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: onOpenDayDetails,
              icon: const Icon(Icons.view_list_outlined, size: 18),
              label: const Text('查看今日详细数据'),
            ),
            if (onOpenInputHistory != null)
              OutlinedButton.icon(
                onPressed: onOpenInputHistory,
                icon: const Icon(Icons.keyboard_outlined, size: 18),
                label: const Text('查看完整输入历史'),
              ),
            OutlinedButton.icon(
              onPressed: onOpenLogHistory,
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('查看历史日志文件'),
            ),
          ],
        ),
      ],
    );
  }
}

class _TrackerSectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  const _TrackerSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 12),
          trailing!,
        ],
      ],
    );
  }
}

class _HistoryToolbar extends ConsumerWidget {
  final DateTime selectedDate;

  const _HistoryToolbar({required this.selectedDate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(selectedDateProvider.notifier);
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final normalizedSelected = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '\u5386\u53f2\u67e5\u8be2',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        IconButton(
          tooltip: '\u524d\u4e00\u5929',
          onPressed: () {
            ref.read(trackerHistorySelectedHeatmapBucketProvider.notifier).state =
                null;
            ref
                .read(trackerHistorySelectedAnalysisBucketProvider.notifier)
                .state = null;
            notifier.goToPrevDay();
          },
          icon: const Icon(Icons.chevron_left),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _formatDate(selectedDate),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          tooltip: '\u540e\u4e00\u5929',
          onPressed: normalizedSelected.isBefore(normalizedToday)
              ? () {
                  ref
                      .read(
                        trackerHistorySelectedHeatmapBucketProvider.notifier,
                      )
                      .state = null;
                  ref
                      .read(
                        trackerHistorySelectedAnalysisBucketProvider.notifier,
                      )
                      .state = null;
                  notifier.goToNextDay();
                }
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
        TextButton(
          onPressed: () {
            ref.read(trackerHistorySelectedHeatmapBucketProvider.notifier).state =
                null;
            ref
                .read(trackerHistorySelectedAnalysisBucketProvider.notifier)
                .state = null;
            notifier.goToToday();
          },
          child: const Text('\u56de\u5230\u4eca\u5929'),
        ),
      ],
    );
  }
}

class _HistoryFilterPanel extends ConsumerStatefulWidget {
  final TrackerHistoryFilterOptions options;
  final String searchQuery;
  final String? selectedProcess;
  final String? selectedCategory;
  final List<TaskItem> taskOptions;
  final int? selectedTaskId;
  final bool onlyWithInput;
  final String? selectedTimeBucketLabel;
  final int filteredSessionCount;
  final int totalSessionCount;
  final int? filteredLogCount;
  final int? totalLogCount;

  const _HistoryFilterPanel({
    required this.options,
    required this.searchQuery,
    required this.selectedProcess,
    required this.selectedCategory,
    required this.taskOptions,
    required this.selectedTaskId,
    required this.onlyWithInput,
    required this.selectedTimeBucketLabel,
    required this.filteredSessionCount,
    required this.totalSessionCount,
    required this.filteredLogCount,
    required this.totalLogCount,
  });

  @override
  ConsumerState<_HistoryFilterPanel> createState() =>
      _HistoryFilterPanelState();
}

class _HistoryFilterPanelState extends ConsumerState<_HistoryFilterPanel> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.searchQuery);
  }

  @override
  void didUpdateWidget(covariant _HistoryFilterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searchQuery != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.searchQuery,
        selection: TextSelection.collapsed(offset: widget.searchQuery.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supportsInputAnalytics =
        TrackerPlatformSource.current().supportsInputAnalytics;
    final hasFilters =
        widget.searchQuery.trim().isNotEmpty ||
        widget.selectedProcess != null ||
        widget.selectedCategory != null ||
        widget.selectedTaskId != null ||
        widget.onlyWithInput ||
        widget.selectedTimeBucketLabel != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.manage_search_outlined,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              '历史筛选',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            if (hasFilters)
              OutlinedButton.icon(
                onPressed: () {
                  _controller.clear();
                  ref.read(trackerHistorySearchQueryProvider.notifier).state = '';
                  ref.read(trackerHistorySelectedProcessProvider.notifier).state =
                      null;
                  ref.read(trackerHistorySelectedCategoryProvider.notifier).state =
                      null;
                  ref.read(trackerHistorySelectedTaskIdProvider.notifier).state =
                      null;
                  ref.read(trackerHistoryOnlyWithInputProvider.notifier).state =
                      false;
                  ref
                      .read(
                        trackerHistorySelectedHeatmapBucketProvider.notifier,
                      )
                      .state = null;
                },
                icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                label: const Text('清空筛选'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 260,
              child: TextField(
                controller: _controller,
                onChanged: (value) {
                  ref.read(trackerHistorySearchQueryProvider.notifier).state =
                      value;
                },
                decoration: InputDecoration(
                  hintText: '搜索应用、分类、标题',
                  prefixIcon: const Icon(Icons.search_outlined),
                  suffixIcon: widget.searchQuery.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清空搜索',
                          onPressed: () {
                            _controller.clear();
                            ref
                                .read(trackerHistorySearchQueryProvider.notifier)
                                .state = '';
                          },
                          icon: const Icon(Icons.close),
                        ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                value: widget.selectedProcess,
                decoration: InputDecoration(
                  labelText: '应用',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('全部应用'),
                  ),
                  ...widget.options.processOptions.map(
                    (process) => DropdownMenuItem<String?>(
                      value: process,
                      child: Text(
                        process,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  ref.read(trackerHistorySelectedProcessProvider.notifier).state =
                      value;
                },
              ),
            ),
            SizedBox(
              width: 220,
              child: DropdownButtonFormField<String?>(
                value: widget.selectedCategory,
                decoration: InputDecoration(
                  labelText: '分类',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('全部分类'),
                  ),
                  ...widget.options.categoryOptions.map(
                    (category) => DropdownMenuItem<String?>(
                      value: category,
                      child: Text(
                        category,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  ref
                      .read(trackerHistorySelectedCategoryProvider.notifier)
                      .state = value;
                },
              ),
            ),
            SizedBox(
              width: 260,
              child: DropdownButtonFormField<int?>(
                value: widget.selectedTaskId,
                decoration: InputDecoration(
                  labelText: '任务',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('全部任务'),
                  ),
                  ...widget.taskOptions.map(
                    (task) => DropdownMenuItem<int?>(
                      value: task.id,
                      child: Text(
                        task.summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
                onChanged: (value) {
                  ref.read(trackerHistorySelectedTaskIdProvider.notifier).state =
                      value;
                },
              ),
            ),
            if (supportsInputAnalytics)
              FilterChip(
                label: const Text('仅看有输入活动'),
                selected: widget.onlyWithInput,
                onSelected: (value) {
                  ref.read(trackerHistoryOnlyWithInputProvider.notifier).state =
                      value;
                },
              ),
          ],
        ),
        if (widget.selectedTimeBucketLabel != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.filter_alt_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '\u70ed\u529b\u56fe\u533a\u95f4\uff1a${widget.selectedTimeBucketLabel}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ref
                        .read(
                          trackerHistorySelectedHeatmapBucketProvider.notifier,
                        )
                        .state = null;
                  },
                  child: const Text('\u53d6\u6d88\u8054\u52a8'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          widget.filteredLogCount == null || widget.totalLogCount == null
              ? '当前筛选后显示 ${widget.filteredSessionCount}/${widget.totalSessionCount} 段工作会话。'
              : '当前筛选后显示 ${widget.filteredSessionCount}/${widget.totalSessionCount} 段工作会话，'
                  '${widget.filteredLogCount}/${widget.totalLogCount} 条原始日志。',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}

class _CurrentSessionPanel extends StatelessWidget {
  final TrackerState state;
  final bool sequenceEnabled;
  final bool showInputTelemetry;
  final VoidCallback? onToggleSequence;

  const _CurrentSessionPanel({
    required this.state,
    required this.sequenceEnabled,
    required this.showInputTelemetry,
    this.onToggleSequence,
  });

  @override
  Widget build(BuildContext context) {
    final snapshot = state.displaySnapshot;
    final classification = state.displayClassification;
    final telemetry = state.displayTelemetry ?? InputTelemetry.empty();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.monitor_heart_outlined,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              '\u5f53\u524d\u5de5\u4f5c\u4f1a\u8bdd',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(width: 10),
            _statusBadge(_statusText(state), _statusColor(state)),
            const Spacer(),
            if (showInputTelemetry && onToggleSequence != null)
              TextButton.icon(
                onPressed: onToggleSequence,
                icon: Icon(
                  sequenceEnabled
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 16,
                ),
                label: Text(
                  sequenceEnabled
                      ? '\u5173\u95ed\u5e8f\u5217\u8bb0\u5f55'
                      : '\u5f00\u542f\u5e8f\u5217\u8bb0\u5f55',
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (snapshot == null)
          _emptyState(
            icon: Icons.radar_outlined,
            title:
                '\u8fd8\u6ca1\u6709\u6355\u83b7\u5230\u5916\u90e8\u5de5\u4f5c\u4f1a\u8bdd',
            subtitle:
                '\u5f00\u59cb\u5728\u5176\u4ed6\u5e94\u7528\u4e2d\u5de5\u4f5c\u540e\uff0c\u8fd9\u91cc\u4f1a\u4fdd\u6301\u663e\u793a\u6700\u8fd1\u4e00\u6bb5\u5916\u90e8\u5de5\u4f5c\u4f1a\u8bdd\uff0c\u4e0d\u4f1a\u88ab\u5f53\u524d\u5e94\u7528\u81ea\u5df1\u62a2\u5360\u3002',
            compact: true,
          )
        else ...[
          Text(
            _sessionTitle(
              snapshot.processName,
              snapshot.windowTitle,
              classification?.label,
            ),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            _sessionSubtitle(snapshot.processName, classification?.category),
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(
                '\u5f00\u59cb\u65f6\u95f4',
                state.displaySessionStart == null
                    ? '\u672a\u77e5'
                    : _formatTime(state.displaySessionStart!),
              ),
              _pill(
                '\u5df2\u8bb0\u5f55\u65f6\u957f',
                _formatMinutes(
                  _sessionMinutes(state.displaySessionStart, state.lastSampleAt),
                ),
              ),
              _pill(
                '\u5f53\u524d\u524d\u53f0',
                state.currentSnapshot?.processName ?? '\u672a\u77e5',
              ),
            ],
          ),
          if (state.isViewingExcludedApp && state.currentSnapshot != null) ...[
            const SizedBox(height: 10),
            Text(
              '\u5f53\u524d\u524d\u53f0\u7a97\u53e3\u5df2\u88ab\u81ea\u6392\u9664\uff0c\u56e0\u6b64\u9875\u9762\u7ee7\u7eed\u5c55\u793a\u6700\u8fd1\u4e00\u6bb5\u5916\u90e8\u5de5\u4f5c\u4f1a\u8bdd\uff1a'
              '${state.currentSnapshot!.processName}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 12),
          if (showInputTelemetry) ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _metricChip(
                  Icons.keyboard_outlined,
                  '\u6309\u952e',
                  '${telemetry.keyCount}',
                  const Color(0xFF6B5EE4),
                ),
                _metricChip(
                  Icons.mouse_outlined,
                  '\u70b9\u51fb',
                  '${telemetry.clicks.total}',
                  const Color(0xFF0EA8A0),
                ),
                _metricChip(
                  Icons.open_with,
                  '\u79fb\u52a8',
                  telemetry.mouseMovePx < 1000
                      ? '${telemetry.mouseMovePx}px'
                      : '${(telemetry.mouseMovePx / 3780).toStringAsFixed(1)}\u7c73',
                  const Color(0xFFF5935A),
                ),
                _metricChip(
                  Icons.swipe_outlined,
                  '\u6eda\u52a8',
                  '${telemetry.scrollPx}px',
                  const Color(0xFFE05A7A),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _tag('\u5de6\u952e ${telemetry.clicks.left}'),
                _tag('\u53f3\u952e ${telemetry.clicks.right}'),
                _tag('\u4e2d\u952e ${telemetry.clicks.middle}'),
                if (telemetry.clicks.xButton1 > 0)
                  _tag('\u4fa7\u952e1 ${telemetry.clicks.xButton1}'),
                if (telemetry.clicks.xButton2 > 0)
                  _tag('\u4fa7\u952e2 ${telemetry.clicks.xButton2}'),
              ],
            ),
          ] else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '\u5f53\u524d\u5b89\u5353\u9002\u914d\u9636\u6bb5\u53ea\u8bb0\u5f55\u5e94\u7528\u524d\u53f0\u4f1a\u8bdd\uff0c\u4e0d\u8bb0\u5f55\u952e\u76d8\u548c\u9f20\u6807\u8f93\u5165\u3002',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          if (showInputTelemetry &&
              telemetry.keySequence != null &&
              telemetry.keySequence!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '\u6700\u8fd1\u6309\u952e\u5e8f\u5217\uff1a'
                '${telemetry.keySequence!.replaceAll('\n', ' <\u56de\u8f66> ')}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _RecentInputPreviewPanel extends StatelessWidget {
  const _RecentInputPreviewPanel({
    required this.recentEventsAsync,
    required this.onOpenHistory,
  });

  final AsyncValue<List<TrackedInputEvent>> recentEventsAsync;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.history_toggle_off_outlined,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              '最近输入预览',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: onOpenHistory,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('查看完整历史'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          '这里只展示最近 12 条外部应用输入摘要，完整顺序日志可进入历史页按天查询。',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        recentEventsAsync.when(
          loading: () => const SizedBox(
            height: 120,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SizedBox(
            height: 120,
            child: Center(
              child: Text('读取最近输入失败：$error'),
            ),
          ),
          data: (events) {
            if (events.isEmpty) {
              return _emptyState(
                icon: Icons.keyboard_alt_outlined,
                title: '还没有可预览的外部输入',
                subtitle: '开始在其他应用中输入后，这里会显示最近捕获的按键与鼠标事件。',
                compact: true,
              );
            }

            return Column(
              children: events
                  .map(
                    (event) => _RecentInputPreviewTile(
                      event: event,
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }
}

class _RecentInputPreviewTile extends StatelessWidget {
  const _RecentInputPreviewTile({
    required this.event,
  });

  final TrackedInputEvent event;

  @override
  Widget build(BuildContext context) {
    final subtitleParts = <String>[
      if (event.processName != null && event.processName!.trim().isNotEmpty)
        event.processName!.trim(),
      if (event.activityLabel != null && event.activityLabel!.trim().isNotEmpty)
        event.activityLabel!.trim(),
      if (event.category != null && event.category!.trim().isNotEmpty)
        event.category!.trim(),
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              _formatTimeWithSeconds(event.timestamp),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _statusBadge(
            _trackedInputEventKindLabel(event.kind),
            _trackedInputEventColor(event.kind),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _trackedInputEventTitle(event),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitleParts.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitleParts.join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyOverview extends StatelessWidget {
  final DateTime selectedDate;
  final ActivityInsights insights;
  final int workSessionCount;
  final bool showInputMetrics;

  const _DailyOverview({
    required this.selectedDate,
    required this.insights,
    required this.workSessionCount,
    required this.showInputMetrics,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.insights_outlined,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Text(
              '${_formatDate(selectedDate)}\u6d3b\u52a8\u5206\u6790',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _summaryCard(
              '\u8bb0\u5f55\u65f6\u957f',
              _formatMinutes(insights.totalMinutes),
              '\u5f53\u5929\u7d2f\u8ba1\u8bb0\u5f55',
            ),
            _summaryCard(
              showInputMetrics ? '\u6709\u6548\u8f93\u5165\u65f6\u957f' : '使用记录',
              showInputMetrics
                  ? _formatMinutes(insights.focusMinutes)
                  : '${insights.records.length}',
              showInputMetrics ? '\u68c0\u6d4b\u5230\u952e\u9f20\u8f93\u5165' : '当天导入的活动片段',
            ),
            _summaryCard(
              '\u5de5\u4f5c\u4f1a\u8bdd',
              '$workSessionCount',
              '\u5408\u5e76\u540e\u7684\u8fde\u7eed\u5de5\u4f5c\u6bb5',
            ),
            _summaryCard(
              '\u6d3b\u8dc3\u5e94\u7528',
              '${insights.activeProcessCount}',
              '\u5f53\u5929\u4e3b\u8981\u5e94\u7528\u6570',
            ),
            if (showInputMetrics)
              _summaryCard(
                '\u6309\u952e\u603b\u6570',
                '${insights.totalKeys}',
                '${insights.keysPerMinute.toStringAsFixed(1)} '
                    '\u6b21/\u5206\u949f',
              ),
            if (showInputMetrics)
              _summaryCard(
                '\u70b9\u51fb\u603b\u6570',
                '${insights.totalClicks}',
                '${insights.clickPerHour.toStringAsFixed(1)} '
                    '\u6b21/\u5c0f\u65f6',
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (insights.topProcesses.isNotEmpty)
          Text(
            '\u6700\u6d3b\u8dc3\u5e94\u7528\uff1a'
            '${insights.topProcesses.map((item) => item.label).join('\u3001')}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        if (insights.topCategories.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '\u5206\u7c7b\u5206\u5e03\uff1a'
            '${insights.topCategories.map((item) => item.label).join('\u3001')}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ],
    );
  }
}

class _DailyInputBehaviorPanel extends StatelessWidget {
  const _DailyInputBehaviorPanel({
    required this.selectedDate,
    required this.summaryAsync,
    required this.selectedProcess,
    required this.selectedHour,
    required this.onApplyProcessFilter,
    required this.onApplyHourFilter,
    required this.onClearLinkage,
    required this.onOpenFullAnalysis,
  });

  final DateTime selectedDate;
  final AsyncValue<InputHeatmapSummary> summaryAsync;
  final String? selectedProcess;
  final int? selectedHour;
  final ValueChanged<String> onApplyProcessFilter;
  final ValueChanged<int> onApplyHourFilter;
  final VoidCallback? onClearLinkage;
  final VoidCallback onOpenFullAnalysis;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.keyboard_command_key_outlined,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${_formatDate(selectedDate)}输入行为分析',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            TextButton.icon(
              onPressed: onOpenFullAnalysis,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('展开热力图'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          '基于完整的 tracked_input_events 顺序事件流生成，聚焦高频按键、应用内输入强度和时段分布。',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (selectedProcess != null || selectedHour != null) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (selectedProcess != null) _tag('联动应用：$selectedProcess'),
              if (selectedHour != null)
                _tag('联动时段：${_formatHourLabel(selectedHour!)}'),
              if (onClearLinkage != null)
                TextButton.icon(
                  onPressed: onClearLinkage,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                  label: const Text('清除联动'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        summaryAsync.when(
          loading: () => const SizedBox(
            height: 160,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => SizedBox(
            height: 140,
            child: Center(
              child: Text('读取输入行为分析失败：$error'),
            ),
          ),
          data: (summary) {
            if (summary.totalEventCount <= 0) {
              return _emptyState(
                icon: Icons.keyboard_alt_outlined,
                title: '这一天还没有可分析的输入事件',
                subtitle: '开始在外部应用中输入后，这里会展示高频按键、输入强度和时间分布。',
                compact: true,
              );
            }

            final peakHour = summary.peakHourBucket;
            final leadingProcess = summary.leadingProcessIntensity;
            final topHours = summary.hourlyDistribution
                .where((bucket) => bucket.totalEvents > 0)
                .toList(growable: false)
              ..sort((left, right) {
                final byScore =
                    right.intensityScore.compareTo(left.intensityScore);
                if (byScore != 0) {
                  return byScore;
                }
                return right.totalEvents.compareTo(left.totalEvents);
              });

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _summaryCard(
                      '输入事件',
                      '${summary.totalEventCount}',
                      '键盘、鼠标、滚轮与移动事件',
                    ),
                    _summaryCard(
                      '活跃输入分钟',
                      '${summary.activeMinuteCount}',
                      '${summary.averageEventsPerActiveMinute.toStringAsFixed(1)} 次/活跃分钟',
                    ),
                    _summaryCard(
                      '峰值时段',
                      peakHour == null
                          ? '暂无'
                          : _formatHourLabel(peakHour.hour),
                      peakHour == null
                          ? '暂无可分析时段'
                          : '${peakHour.totalEvents} 条事件 · 强度 ${peakHour.intensityScore}',
                    ),
                    _summaryCard(
                      '主力应用',
                      leadingProcess == null
                          ? '暂无'
                          : _truncateLabel(leadingProcess.processName, 10),
                      leadingProcess == null
                          ? '暂无主力应用'
                          : '${leadingProcess.totalEvents} 条事件 · ${leadingProcess.activeMinutes} 分钟',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '高频按键',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                if (summary.topKeys.isEmpty)
                  const Text(
                    '这一天还没有键盘输入，暂时无法生成高频按键。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: summary.topKeys
                        .take(8)
                        .map((item) => _InputKeyStatChip(stat: item))
                        .toList(growable: false),
                  ),
                if (summary.processIntensities.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '应用内输入强度',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ...summary.processIntensities
                      .take(5)
                      .map(
                        (item) => _InputProcessIntensityRow(
                          stat: item,
                          maxScore: summary.maxProcessIntensityScore,
                          selected: selectedProcess == item.processName,
                          onTap: () => onApplyProcessFilter(item.processName),
                        ),
                      )
                      .toList(growable: false),
                ],
                if (summary.hourlyDistribution.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    '时间段分布',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _HourlyIntensityMiniChart(
                    summary: summary,
                    selectedHour: selectedHour,
                    onSelectHour: onApplyHourFilter,
                  ),
                  if (topHours.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: topHours
                          .take(3)
                          .map(
                            (bucket) => ActionChip(
                              onPressed: () => onApplyHourFilter(bucket.hour),
                              avatar: selectedHour == bucket.hour
                                  ? const Icon(
                                      Icons.check,
                                      size: 16,
                                      color: AppColors.primary,
                                    )
                                  : null,
                              label: Text(
                                '${_formatHourLabel(bucket.hour)} · '
                                '${bucket.totalEvents} 条 · 强度 ${bucket.intensityScore}',
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _InputKeyStatChip extends StatelessWidget {
  const _InputKeyStatChip({
    required this.stat,
  });

  final InputKeyStat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 108, maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF6B5EE4).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF6B5EE4).withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${stat.count} 次 · ${(stat.share * 100).toStringAsFixed(1)}%',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _InputProcessIntensityRow extends StatelessWidget {
  const _InputProcessIntensityRow({
    required this.stat,
    required this.maxScore,
    required this.selected,
    required this.onTap,
  });

  final InputProcessIntensity stat;
  final int maxScore;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ratio = maxScore <= 0 ? 0.0 : stat.intensityScore / maxScore;
    final detail = <String>[
      '${stat.totalEvents} 条事件',
      '${stat.activeMinutes} 分钟',
      '${stat.keyEvents} 键',
      if (stat.mouseButtonEvents > 0) '${stat.mouseButtonEvents} 点击',
      if (stat.wheelEvents > 0) '${stat.wheelEvents} 滚轮',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? Border.all(
                    color: AppColors.primary.withValues(alpha: 0.22),
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      stat.processName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    selected ? '已联动' : '强度 ${stat.intensityScore}',
                    style: TextStyle(
                      fontSize: 11,
                      color: selected ? AppColors.primary : Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                detail,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: ratio.clamp(0.0, 1.0),
                  backgroundColor:
                      const Color(0xFF0EA8A0).withValues(alpha: 0.10),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFF0EA8A0),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HourlyIntensityMiniChart extends StatelessWidget {
  const _HourlyIntensityMiniChart({
    required this.summary,
    required this.selectedHour,
    required this.onSelectHour,
  });

  final InputHeatmapSummary summary;
  final int? selectedHour;
  final ValueChanged<int> onSelectHour;

  @override
  Widget build(BuildContext context) {
    final maxScore = summary.maxHourlyIntensityScore;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: summary.hourlyDistribution.map((bucket) {
                final ratio = maxScore <= 0
                    ? 0.0
                    : bucket.intensityScore / maxScore;
                final isSelected = selectedHour == bucket.hour;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: GestureDetector(
                      onTap: () => onSelectHour(bucket.hour),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: 14 + (ratio.clamp(0.0, 1.0) * 72),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : const Color(0xFFE05A7A).withValues(
                                    alpha: bucket.totalEvents > 0 ? 0.92 : 0.12,
                                  ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final hour in const [0, 4, 8, 12, 16, 20, 23])
                Expanded(
                  child: Text(
                    hour.toString().padLeft(2, '0'),
                    textAlign: hour == 0
                        ? TextAlign.left
                        : (hour == 23 ? TextAlign.right : TextAlign.center),
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _RangeSessionSortMode {
  recent,
  longest,
  input,
}

class _SelectedRangeAnalysisPanel extends StatefulWidget {
  final TrackerRangeAnalysisSnapshot snapshot;
  final VoidCallback onClose;

  const _SelectedRangeAnalysisPanel({
    required this.snapshot,
    required this.onClose,
  });

  @override
  State<_SelectedRangeAnalysisPanel> createState() =>
      _SelectedRangeAnalysisPanelState();
}

class _SelectedRangeAnalysisPanelState extends State<_SelectedRangeAnalysisPanel> {
  static const int _collapsedSessionLimit = 12;
  static const int _collapsedLogLimit = 30;

  late final TextEditingController _logSearchController;

  _RangeSessionSortMode _sortMode = _RangeSessionSortMode.recent;
  bool _showAllSessions = false;
  String? _selectedProcess;
  String? _selectedCategory;
  bool _onlyWithInput = false;
  String _logSearchQuery = '';
  ActivityLogEntryType? _selectedLogType;
  bool _showAllLogs = false;

  @override
  void initState() {
    super.initState();
    _logSearchController = TextEditingController();
  }

  @override
  void dispose() {
    _logSearchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _SelectedRangeAnalysisPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isSameBucket(oldWidget.snapshot.bucket, widget.snapshot.bucket)) {
      _showAllSessions = false;
      _sortMode = _RangeSessionSortMode.recent;
      _selectedProcess = null;
      _selectedCategory = null;
      _onlyWithInput = false;
      _logSearchQuery = '';
      _selectedLogType = null;
      _showAllLogs = false;
      _logSearchController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshot;
    final processOptions = _collectRangeProcessOptions(
      records: snapshot.records,
      logEntries: snapshot.logEntries,
    );
    final categoryOptions = _collectRangeCategoryOptions(
      records: snapshot.records,
      logEntries: snapshot.logEntries,
    );
    final selectedProcess = processOptions.contains(_selectedProcess)
        ? _selectedProcess
        : null;
    final selectedCategory = categoryOptions.contains(_selectedCategory)
        ? _selectedCategory
        : null;
    final hasFilters =
        selectedProcess != null || selectedCategory != null || _onlyWithInput;
    final filteredRecords = snapshot.records
        .where(
          (record) => _matchesActivityRecord(
            record,
            selectedProcess: selectedProcess,
            selectedCategory: selectedCategory,
            onlyWithInput: _onlyWithInput,
          ),
        )
        .toList(growable: false);
    final filteredInsights = ActivityInsights.fromRecords(filteredRecords);
    final filteredSessions = WorkSessionGrouper.fromRecords(filteredRecords);
    final filteredLogEntries = snapshot.logEntries
        .where(
          (entry) => _matchesLogEntry(
            entry,
            searchQuery: '',
            selectedProcess: selectedProcess,
            selectedCategory: selectedCategory,
            onlyWithInput: _onlyWithInput,
            selectedHeatmapBucket: null,
          ),
        )
        .toList(growable: false);
    final logTypeSummary = _buildLogTypeSummary(filteredLogEntries);
    final logTypeOptions = ActivityLogEntryType.values
        .where((type) => filteredLogEntries.any((entry) => entry.type == type))
        .toList(growable: false);
    final selectedLogType = logTypeOptions.contains(_selectedLogType)
        ? _selectedLogType
        : null;
    final searchedLogEntries = filteredLogEntries
        .where((entry) {
          if (selectedLogType != null && entry.type != selectedLogType) {
            return false;
          }
          return _matchesLogEntry(
            entry,
            searchQuery: _logSearchQuery,
            selectedProcess: selectedProcess,
            selectedCategory: selectedCategory,
            onlyWithInput: _onlyWithInput,
            selectedHeatmapBucket: null,
          );
        })
        .toList(growable: false);
    final sortedLogEntries = List<ActivityLogEntry>.from(searchedLogEntries)
      ..sort((left, right) => right.timestamp.compareTo(left.timestamp));
    final visibleLogCount = _showAllLogs
        ? sortedLogEntries.length
        : math.min(sortedLogEntries.length, _collapsedLogLimit);
    final visibleLogEntries = sortedLogEntries
        .take(visibleLogCount)
        .toList(growable: false);
    final searchedLogTypeSummary = _buildLogTypeSummary(sortedLogEntries);
    final logDaySummary = _buildLogDaySummary(sortedLogEntries);
    final hasLogQuery =
        _logSearchQuery.trim().isNotEmpty || selectedLogType != null;
    final hasAnyRangeData =
        snapshot.records.isNotEmpty || snapshot.logEntries.isNotEmpty;
    final sortedSessions = List<WorkSession>.from(filteredSessions)
      ..sort((left, right) {
        switch (_sortMode) {
          case _RangeSessionSortMode.recent:
            return right.startTime.compareTo(left.startTime);
          case _RangeSessionSortMode.longest:
            final byDuration =
                right.durationMinutes.compareTo(left.durationMinutes);
            if (byDuration != 0) {
              return byDuration;
            }
            return right.startTime.compareTo(left.startTime);
          case _RangeSessionSortMode.input:
            final byInput =
                _sessionInputScore(right).compareTo(_sessionInputScore(left));
            if (byInput != 0) {
              return byInput;
            }
            return right.startTime.compareTo(left.startTime);
        }
      });
    final visibleSessionCount = _showAllSessions
        ? sortedSessions.length
        : math.min(sortedSessions.length, _collapsedSessionLimit);
    final visibleSessions = sortedSessions
        .take(visibleSessionCount)
        .toList(growable: false);
    final sessionDaySummary = _buildSessionDaySummary(sortedSessions);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.query_stats_outlined,
              size: 16,
              color: AppColors.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${snapshot.bucket.longLabel}区间分析',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            TextButton.icon(
              onPressed: widget.onClose,
              icon: const Icon(Icons.close, size: 16),
              label: const Text('关闭'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '这部分来自热力图选中的时间桶，用于查看跨天或跨月的聚合趋势，不会改变下方按天展示的工作会话和原始日志。',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (hasAnyRangeData) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.filter_alt_outlined,
                size: 16,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                '区间筛选',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              if (hasFilters)
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedProcess = null;
                      _selectedCategory = null;
                      _onlyWithInput = false;
                    });
                  },
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                  label: const Text('清空筛选'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String?>(
                  value: selectedProcess,
                  decoration: InputDecoration(
                    labelText: '应用',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('全部应用'),
                    ),
                    ...processOptions.map(
                      (process) => DropdownMenuItem<String?>(
                        value: process,
                        child: Text(
                          process,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedProcess = value;
                    });
                  },
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String?>(
                  value: selectedCategory,
                  decoration: InputDecoration(
                    labelText: '分类',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('全部分类'),
                    ),
                    ...categoryOptions.map(
                      (category) => DropdownMenuItem<String?>(
                        value: category,
                        child: Text(
                          category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _selectedCategory = value;
                    });
                  },
                ),
              ),
              FilterChip(
                label: const Text('仅看有输入活动'),
                selected: _onlyWithInput,
                onSelected: (value) {
                  setState(() {
                    _onlyWithInput = value;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '当前筛选后显示 ${filteredSessions.length} 段工作会话，${filteredRecords.length} 条活动记录，${filteredLogEntries.length} 条原始日志。',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
        if (!hasAnyRangeData) ...[
          const SizedBox(height: 16),
          _emptyState(
            icon: Icons.data_usage_outlined,
            title: '这个时间区间还没有可分析的活动数据',
            subtitle: '可以换一个更活跃的热力图时间桶，或继续下钻到更细的时间尺度。',
            compact: true,
          ),
        ] else ...[
          if (filteredRecords.isEmpty) ...[
            const SizedBox(height: 16),
            _emptyState(
              icon: filteredLogEntries.isEmpty
                  ? Icons.filter_alt_off_outlined
                  : Icons.receipt_long_outlined,
              title: filteredLogEntries.isEmpty
                  ? '当前筛选下没有可展示的追踪数据'
                  : '当前筛选下没有可聚合的活动记录',
              subtitle: filteredLogEntries.isEmpty
                  ? '可以尝试切换应用、分类，或关闭“仅看有输入活动”。'
                  : '该区间仍保留 ${filteredLogEntries.length} 条原始日志，可以继续在下方检索明细。',
              compact: true,
            ),
          ] else ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _summaryCard(
                  '记录时长',
                  _formatMinutes(filteredInsights.totalMinutes),
                  '区间内累计记录',
                ),
                _summaryCard(
                  '有效输入时长',
                  _formatMinutes(filteredInsights.focusMinutes),
                  '检测到键鼠输入',
                ),
                _summaryCard(
                  '工作会话',
                  '${filteredSessions.length}',
                  '区间内合并后的连续工作段',
                ),
                _summaryCard(
                  '原始日志',
                  '${filteredLogEntries.length}',
                  '写入数据库的追踪日志条数',
                ),
                _summaryCard(
                  '活跃应用',
                  '${filteredInsights.activeProcessCount}',
                  '该区间主要应用数',
                ),
                _summaryCard(
                  '按键总数',
                  '${filteredInsights.totalKeys}',
                  '${filteredInsights.keysPerMinute.toStringAsFixed(1)} 次/分钟',
                ),
              ],
            ),
            if (logTypeSummary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                '日志类型：$logTypeSummary',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (filteredInsights.topProcesses.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '主要应用',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: filteredInsights.topProcesses
                    .map((slice) => _InsightSliceChip(slice: slice))
                    .toList(),
              ),
            ],
            if (filteredInsights.topCategories.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '主要分类',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: filteredInsights.topCategories
                    .map((slice) => _InsightSliceChip(slice: slice))
                    .toList(),
              ),
            ],
            if (sortedSessions.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '区间工作会话',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  if (sortedSessions.length > _collapsedSessionLimit)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showAllSessions = !_showAllSessions;
                        });
                      },
                      child: Text(_showAllSessions ? '收起列表' : '显示全部'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in _RangeSessionSortMode.values)
                    ChoiceChip(
                      label: Text(_rangeSessionSortModeLabel(mode)),
                      selected: _sortMode == mode,
                      onSelected: (_) {
                        setState(() {
                          _sortMode = mode;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                sortedSessions.length <= visibleSessionCount
                    ? '共 ${sortedSessions.length} 段工作会话。'
                    : '共 ${sortedSessions.length} 段工作会话，当前显示 ${visibleSessionCount} 段。',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (sessionDaySummary.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '日期分布：$sessionDaySummary',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
              const SizedBox(height: 8),
              ...visibleSessions
                  .map((session) => _RangeSessionTile(session: session))
                  .toList(),
            ],
            if (filteredInsights.busiestRecords.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                '高输入片段',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              ...filteredInsights.busiestRecords
                  .map((item) => _SessionRecordRow(record: item.record))
                  .toList(),
            ],
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  '区间原始日志',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (sortedLogEntries.length > _collapsedLogLimit)
                TextButton(
                  onPressed: () {
                    setState(() {
                      _showAllLogs = !_showAllLogs;
                    });
                  },
                  child: Text(_showAllLogs ? '收起列表' : '显示全部'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '原始日志按时间倒序展示，支持按关键词和日志类型继续缩小范围。',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 320,
            child: TextField(
              controller: _logSearchController,
              onChanged: (value) {
                setState(() {
                  _logSearchQuery = value;
                  _showAllLogs = false;
                });
              },
              decoration: InputDecoration(
                hintText: '搜索标题、窗口、备注、类型',
                prefixIcon: const Icon(Icons.search_outlined),
                suffixIcon: _logSearchQuery.trim().isEmpty
                    ? null
                    : IconButton(
                        tooltip: '清空检索',
                        onPressed: () {
                          _logSearchController.clear();
                          setState(() {
                            _logSearchQuery = '';
                            _showAllLogs = false;
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
            ),
          ),
          if (logTypeOptions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('全部类型'),
                  selected: selectedLogType == null,
                  onSelected: (_) {
                    setState(() {
                      _selectedLogType = null;
                      _showAllLogs = false;
                    });
                  },
                ),
                ...logTypeOptions.map(
                  (type) => ChoiceChip(
                    label: Text(
                      '${_LogEntryTile._entryTypeLabel(type)} '
                      '${filteredLogEntries.where((entry) => entry.type == type).length}',
                    ),
                    selected: selectedLogType == type,
                    onSelected: (_) {
                      setState(() {
                        _selectedLogType = type;
                        _showAllLogs = false;
                      });
                    },
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (sortedLogEntries.isEmpty)
            _emptyState(
              icon: Icons.receipt_long_outlined,
              title: hasLogQuery ? '没有找到匹配的原始日志' : '这个时间区间还没有原始日志',
              subtitle: hasLogQuery
                  ? '可以尝试清空关键词或切换日志类型。'
                  : '后续采样、会话变化和快照写入后，这里会逐步丰富。',
              compact: true,
            )
          else ...[
            Text(
              hasLogQuery
                  ? '当前检索命中 ${sortedLogEntries.length}/${filteredLogEntries.length} 条日志。'
                  : '当前区间共有 ${sortedLogEntries.length} 条日志。',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (sortedLogEntries.length > visibleLogCount) ...[
              const SizedBox(height: 4),
              Text(
                '当前默认显示最新 ${visibleLogCount} 条，可点击右上角“显示全部”查看完整列表。',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (searchedLogTypeSummary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '日志类型：$searchedLogTypeSummary',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            if (logDaySummary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '日期分布：$logDaySummary',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 8),
            ...visibleLogEntries
                .map(
                  (entry) => _LogEntryTile(
                    entry: entry,
                    showDate: true,
                    showDetails: true,
                  ),
                )
                .toList(),
          ],
        ],
      ],
    );
  }
}

class _InsightSliceChip extends StatelessWidget {
  final ActivityInsightSlice slice;

  const _InsightSliceChip({required this.slice});

  @override
  Widget build(BuildContext context) {
    final note = <String>[
      _formatMinutes(slice.minutes),
      '${slice.sessions}段记录',
      if (slice.keys > 0) '${slice.keys}键',
      if (slice.clicks > 0) '${slice.clicks}次点击',
    ].join(' · ');

    return Container(
      constraints: const BoxConstraints(minWidth: 160, maxWidth: 260),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            slice.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            note,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _RangeSessionTile extends StatelessWidget {
  final WorkSession session;

  const _RangeSessionTile({required this.session});

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (session.category != null && session.category!.trim().isNotEmpty)
        session.category!.trim(),
      if (!session.spansMultipleProcesses &&
          session.processName != null &&
          session.processName!.trim().isNotEmpty)
        session.processName!.trim(),
      if (session.spansMultipleProcesses) '${session.processNames.length} 个应用',
      if (session.spansMultipleCategories) '${session.categories.length} 个分类',
    ].join(' · ');
    final processSummary = _joinPreview(session.processNames);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  session.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatMinutes(session.durationMinutes),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatSessionRange(session.startTime, session.endTime),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              meta,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          if (session.spansMultipleProcesses) ...[
            const SizedBox(height: 4),
            Text(
              '涉及应用：$processSummary',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tag('${session.rawRecordCount} 条原始记录'),
              if (session.spansMultipleProcesses)
                _tag('跨 ${session.processNames.length} 个应用'),
              if (session.interruptionCount > 0)
                _tag('吸收 ${session.interruptionCount} 次打断'),
              if (session.keyCount > 0) _tag('${session.keyCount} 次按键'),
              if (session.mouseClicks > 0) _tag('${session.mouseClicks} 次点击'),
              if (session.mouseMovePx > 0) _tag('${session.mouseMovePx}px 移动'),
              if (session.scrollPx > 0) _tag('${session.scrollPx}px 滚动'),
            ],
          ),
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title: const Text(
                '查看原始记录与合并细节',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                session.interruptionCount > 0
                    ? '本段包含 ${session.rawRecordCount} 条原始记录，其中 ${session.interruptionCount} 次打断已被吸收'
                    : '本段包含 ${session.rawRecordCount} 条原始记录',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              children: [
                if (session.categories.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '涉及分类：${session.categories.join('、')}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ),
                if (session.processNames.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '涉及应用：${session.processNames.join('、')}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ),
                ...session.records.map(
                  (record) => _SessionRecordRow(record: record),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkSessionTile extends StatelessWidget {
  final WorkSession session;
  final DateTime selectedDate;
  final String? selectedProcess;
  final int? selectedHour;
  final Map<int, TaskItem> taskById;
  final ValueChanged<String>? onLinkProcessAnalysis;
  final ValueChanged<int>? onLinkHourAnalysis;
  final VoidCallback? onBindTask;
  final ValueChanged<int>? onOpenTask;
  final ValueChanged<ActivityRecord>? onBindRecordTask;

  const _WorkSessionTile({
    required this.session,
    required this.selectedDate,
    this.selectedProcess,
    this.selectedHour,
    this.taskById = const <int, TaskItem>{},
    this.onLinkProcessAnalysis,
    this.onLinkHourAnalysis,
    this.onBindTask,
    this.onOpenTask,
    this.onBindRecordTask,
  });

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (session.category != null && session.category!.trim().isNotEmpty)
        session.category!.trim(),
      if (!session.spansMultipleProcesses &&
          session.processName != null &&
          session.processName!.trim().isNotEmpty)
        session.processName!.trim(),
      if (session.spansMultipleProcesses) '${session.processNames.length} 个应用',
      if (session.spansMultipleCategories) '${session.categories.length} 个分类',
    ].join(' \u00b7 ');
    final processSummary = _joinPreview(session.processNames);
    final linkedTaskIds = _collectLinkedTaskIds(session.records);
    final singleLinkedTaskId =
        linkedTaskIds.length == 1 ? linkedTaskIds.first : null;
    final primaryProcess = session.processName?.trim().isNotEmpty == true
        ? session.processName!.trim()
        : null;
    final linkedHour = _dominantHourForRange(
      itemStart: session.startTime,
      itemEnd: session.endTime,
      selectedDate: selectedDate,
    );
    final isProcessLinked =
        primaryProcess != null && primaryProcess == selectedProcess;
    final isHourLinked = linkedHour != null && linkedHour == selectedHour;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  '${_formatTime(session.startTime)} - ${_formatTime(session.endTime)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  session.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                _formatMinutes(session.durationMinutes),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            meta.isEmpty ? '\u672a\u5206\u7c7b\u5de5\u4f5c\u4f1a\u8bdd' : meta,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (session.spansMultipleProcesses) ...[
            const SizedBox(height: 4),
            Text(
              '涉及应用：$processSummary',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
          if (linkedTaskIds.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: linkedTaskIds
                  .map(
                    (taskId) => _tag(
                      '任务：${_taskLabel(taskById[taskId], fallbackId: taskId)}',
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _tag('${session.rawRecordCount} '
                  '\u6761\u539f\u59cb\u8bb0\u5f55'),
              if (session.spansMultipleProcesses)
                _tag('跨 ${session.processNames.length} 个应用'),
              if (session.interruptionCount > 0)
                _tag('已吸收 ${session.interruptionCount} 次打断'),
              _tag('${session.keyCount} \u6b21\u6309\u952e'),
              _tag('${session.mouseClicks} \u6b21\u70b9\u51fb'),
              _tag('${session.mouseMovePx}px \u79fb\u52a8'),
              _tag('${session.scrollPx}px \u6eda\u52a8'),
            ],
          ),
          if (onLinkProcessAnalysis != null || onLinkHourAnalysis != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (primaryProcess != null && onLinkProcessAnalysis != null)
                  ActionChip(
                    onPressed: () => onLinkProcessAnalysis!(primaryProcess),
                    avatar: isProcessLinked
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: AppColors.primary,
                          )
                        : const Icon(Icons.tune, size: 16),
                    label: Text(
                      isProcessLinked
                          ? '已联动应用分析'
                          : '查看「$primaryProcess」输入分析',
                    ),
                  ),
                if (linkedHour != null && onLinkHourAnalysis != null)
                  ActionChip(
                    onPressed: () => onLinkHourAnalysis!(linkedHour),
                    avatar: isHourLinked
                        ? const Icon(
                            Icons.check,
                            size: 16,
                            color: AppColors.primary,
                          )
                        : const Icon(Icons.schedule_outlined, size: 16),
                    label: Text(
                      isHourLinked
                          ? '已联动时段分析'
                          : '查看 ${_formatHourLabel(linkedHour)} 输入分析',
                    ),
                  ),
              ],
            ),
          ],
          if (onBindTask != null || (singleLinkedTaskId != null && onOpenTask != null)) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onBindTask != null)
                  TextButton.icon(
                    onPressed: onBindTask,
                    icon: const Icon(Icons.link_outlined, size: 16),
                    label: Text(
                      linkedTaskIds.isEmpty ? '关联任务' : '调整任务关联',
                    ),
                  ),
                if (singleLinkedTaskId != null && onOpenTask != null)
                  TextButton.icon(
                    onPressed: () => onOpenTask!(singleLinkedTaskId),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('打开任务'),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 4),
              title: const Text(
                '\u67e5\u770b\u539f\u59cb\u8bb0\u5f55\u4e0e\u5408\u5e76\u7ec6\u8282',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                session.interruptionCount > 0
                    ? '\u672c\u6bb5\u5305\u542b ${session.rawRecordCount} \u6761\u539f\u59cb\u8bb0\u5f55\uff0c\u5176\u4e2d ${session.interruptionCount} \u6b21\u6253\u65ad\u5df2\u88ab\u5438\u6536'
                    : '\u672c\u6bb5\u5305\u542b ${session.rawRecordCount} \u6761\u539f\u59cb\u8bb0\u5f55',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              children: [
                if (session.categories.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '涉及分类：${session.categories.join('\u3001')}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ),
                if (session.processNames.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '涉及应用：${session.processNames.join('\u3001')}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  ),
                ...session.records.map(
                  (record) => _SessionRecordRow(
                    record: record,
                    selectedDate: selectedDate,
                    selectedProcess: selectedProcess,
                    selectedHour: selectedHour,
                    taskById: taskById,
                    onLinkProcessAnalysis: onLinkProcessAnalysis,
                    onLinkHourAnalysis: onLinkHourAnalysis,
                    onBindTask: onBindRecordTask == null
                        ? null
                        : () => onBindRecordTask!(record),
                    onOpenTask: record.linkedTaskId != null && onOpenTask != null
                        ? () => onOpenTask!(record.linkedTaskId!)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionRecordRow extends StatelessWidget {
  final ActivityRecord record;
  final DateTime? selectedDate;
  final String? selectedProcess;
  final int? selectedHour;
  final Map<int, TaskItem> taskById;
  final ValueChanged<String>? onLinkProcessAnalysis;
  final ValueChanged<int>? onLinkHourAnalysis;
  final VoidCallback? onBindTask;
  final VoidCallback? onOpenTask;

  const _SessionRecordRow({
    required this.record,
    this.selectedDate,
    this.selectedProcess,
    this.selectedHour,
    this.taskById = const <int, TaskItem>{},
    this.onLinkProcessAnalysis,
    this.onLinkHourAnalysis,
    this.onBindTask,
    this.onOpenTask,
  });

  @override
  Widget build(BuildContext context) {
    final title = WorkSessionGrouper.preferredLabel(record);
    final endTime = record.endTime ?? record.startTime;
    final linkedTaskId = record.linkedTaskId;
    final linkedTask =
        linkedTaskId == null ? null : taskById[linkedTaskId];
    final processName = record.processName?.trim().isNotEmpty == true
        ? record.processName!.trim()
        : null;
    final linkedHour = selectedDate == null
        ? null
        : _dominantHourForRange(
            itemStart: record.startTime,
            itemEnd: endTime,
            selectedDate: selectedDate!,
          );
    final isProcessLinked =
        processName != null && processName == selectedProcess;
    final isHourLinked = linkedHour != null && linkedHour == selectedHour;
    final meta = <String>[
      if (record.category != null && record.category!.trim().isNotEmpty)
        record.category!.trim(),
      if (record.processName != null && record.processName!.trim().isNotEmpty)
        record.processName!.trim(),
    ].join(' \u00b7 ');
    final metrics = <String>[
      if (record.durationMinutes > 0) '${record.durationMinutes} \u5206\u949f',
      if (record.keyCount > 0) '${record.keyCount} \u6b21\u6309\u952e',
      if (record.mouseClicks > 0) '${record.mouseClicks} \u6b21\u70b9\u51fb',
      if (record.mouseMovePx > 0) '${record.mouseMovePx}px \u79fb\u52a8',
      if (record.scrollPx > 0) '${record.scrollPx}px \u6eda\u52a8',
    ];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  '${_formatTime(record.startTime)} - ${_formatTime(endTime)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              meta,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metrics.map(_tag).toList(),
            ),
          ],
          if (linkedTaskId != null) ...[
            const SizedBox(height: 6),
            Text(
              '关联任务：${_taskLabel(linkedTask, fallbackId: linkedTaskId)}',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          if (onLinkProcessAnalysis != null ||
              onLinkHourAnalysis != null ||
              onBindTask != null ||
              onOpenTask != null) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (processName != null && onLinkProcessAnalysis != null)
                  TextButton.icon(
                    onPressed: () => onLinkProcessAnalysis!(processName),
                    icon: Icon(
                      isProcessLinked
                          ? Icons.check_circle
                          : Icons.tune_outlined,
                      size: 14,
                    ),
                    label: Text(
                      isProcessLinked ? '已联动应用分析' : '联动应用分析',
                    ),
                  ),
                if (linkedHour != null && onLinkHourAnalysis != null)
                  TextButton.icon(
                    onPressed: () => onLinkHourAnalysis!(linkedHour),
                    icon: Icon(
                      isHourLinked
                          ? Icons.check_circle
                          : Icons.schedule_outlined,
                      size: 14,
                    ),
                    label: Text(
                      isHourLinked
                          ? '已联动时段分析'
                          : '联动 ${_formatHourLabel(linkedHour)}',
                    ),
                  ),
                if (onBindTask != null)
                  TextButton.icon(
                    onPressed: onBindTask,
                    icon: const Icon(Icons.link_outlined, size: 14),
                    label: Text(
                      linkedTaskId == null ? '关联任务' : '改绑任务',
                    ),
                  ),
                if (onOpenTask != null)
                  TextButton.icon(
                    onPressed: onOpenTask,
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('打开任务'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final ActivityLogEntry entry;
  final bool showDate;
  final bool showDetails;

  const _LogEntryTile({
    required this.entry,
    this.showDate = false,
    this.showDetails = false,
  });

  @override
  Widget build(BuildContext context) {
    final title = entry.label?.trim().isNotEmpty == true
        ? entry.label!.trim()
        : (entry.windowTitle?.trim().isNotEmpty == true
            ? entry.windowTitle!.trim()
            : (entry.processName?.trim().isNotEmpty == true
                ? entry.processName!.trim()
                : '\u672a\u547d\u540d\u65e5\u5fd7\u9879'));

    final subtitle = <String>[
      if (entry.category != null && entry.category!.trim().isNotEmpty)
        entry.category!.trim(),
      if (entry.processName != null && entry.processName!.trim().isNotEmpty)
        entry.processName!.trim(),
      if (entry.isIgnored) '\u81ea\u6392\u9664',
    ].join(' \u00b7 ');

    final metrics = <String>[
      if (entry.keyCount > 0) '${entry.keyCount} \u6b21\u6309\u952e',
      if (entry.mouseClicks > 0) '${entry.mouseClicks} \u6b21\u70b9\u51fb',
      if (entry.mouseMovePx > 0) '${entry.mouseMovePx}px \u79fb\u52a8',
      if (entry.scrollPx > 0) '${entry.scrollPx}px \u6eda\u52a8',
      if (entry.durationMinutes != null)
        '${entry.durationMinutes} \u5206\u949f',
    ];
    final detailLines = <String>[
      if (entry.windowTitle != null &&
          entry.windowTitle!.trim().isNotEmpty &&
          entry.windowTitle!.trim() != title)
        '窗口标题：${entry.windowTitle!.trim()}',
      if (entry.className != null && entry.className!.trim().isNotEmpty)
        '窗口类名：${entry.className!.trim()}',
      if (entry.recordId != null) '关联记录：#${entry.recordId}',
      if (entry.isFullscreen) '窗口状态：全屏',
      if (entry.note != null && entry.note!.trim().isNotEmpty)
        '备注：${entry.note!.trim()}',
    ];
    final keySequence = entry.keySequence?.trim();
    final hasDetails =
        showDetails &&
        (detailLines.isNotEmpty || (keySequence != null && keySequence.isNotEmpty));
    final timeLabel = showDate
        ? _formatDateTimeShort(entry.timestamp)
        : _formatTime(entry.timestamp);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: showDate ? 104 : 64,
                child: Text(
                  timeLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusBadge(
                _entryTypeLabel(entry.type),
                entry.isIgnored
                    ? const Color(0xFFF5935A)
                    : const Color(0xFF0EA8A0),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metrics.map(_tag).toList(),
            ),
          ],
          if (hasDetails) ...[
            const SizedBox(height: 8),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: const Text(
                  '查看日志详情',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                children: [
                  for (final line in detailLines)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          line,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  if (keySequence != null && keySequence.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 2),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '按键序列：${keySequence.replaceAll('\n', ' <回车> ')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _entryTypeLabel(ActivityLogEntryType type) {
    switch (type) {
      case ActivityLogEntryType.sample:
        return '\u91c7\u6837';
      case ActivityLogEntryType.sessionOpen:
        return '\u4f1a\u8bdd\u5f00\u59cb';
      case ActivityLogEntryType.sessionUpdate:
        return '\u4f1a\u8bdd\u66f4\u65b0';
      case ActivityLogEntryType.sessionClose:
        return '\u4f1a\u8bdd\u7ed3\u675f';
      case ActivityLogEntryType.snapshot:
        return '\u5feb\u7167';
    }
  }
}

Widget _card(BuildContext context, Widget child) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

Widget _sectionTitle(BuildContext context, String title, String subtitle) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
    ],
  );
}

Widget _emptyState({
  required IconData icon,
  required String title,
  required String subtitle,
  bool compact = false,
}) {
  return Padding(
    padding: EdgeInsets.symmetric(vertical: compact ? 8 : 24),
    child: Center(
      child: Column(
        children: [
          Icon(
            icon,
            size: compact ? 30 : 44,
            color: Colors.grey.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    ),
  );
}

Widget _summaryCard(String title, String value, String note) {
  final views = WidgetsBinding.instance.platformDispatcher.views;
  final view = views.isEmpty ? null : views.first;
  final width = view == null
      ? 800.0
      : view.physicalSize.width / view.devicePixelRatio;
  final compact = width < 520;
  return Container(
    width: compact ? math.max(180, width - 56) : 210,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFF6F7F9),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(note, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    ),
  );
}

Widget _metricChip(IconData icon, String label, String value, Color color) {
  return Container(
    width: 170,
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    ),
  );
}

Widget _statusBadge(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    ),
  );
}

Widget _pill(String label, String value) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F4F7),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$label\uff1a$value',
      style: const TextStyle(fontSize: 12, color: Colors.grey),
    ),
  );
}

Widget _tag(String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F4F7),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, color: Colors.grey),
    ),
  );
}

String _formatDate(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

String _formatTime(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatTimeWithSeconds(DateTime dateTime) {
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final second = dateTime.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String _formatDateTimeShort(DateTime dateTime) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  return '$month-$day ${_formatTime(dateTime)}';
}

String _formatDayShort(DateTime dateTime) {
  final month = dateTime.month.toString().padLeft(2, '0');
  final day = dateTime.day.toString().padLeft(2, '0');
  return '$month-$day';
}

String _formatSessionRange(DateTime start, DateTime end) {
  final isSameDay =
      start.year == end.year && start.month == end.month && start.day == end.day;
  if (isSameDay) {
    return '${_formatDayShort(start)} ${_formatTime(start)} - ${_formatTime(end)}';
  }
  return '${_formatDateTimeShort(start)} - ${_formatDateTimeShort(end)}';
}

String _formatMinutes(int minutes) {
  if (minutes <= 0) {
    return '0 \u5206\u949f';
  }
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  if (hours <= 0) {
    return '$mins \u5206\u949f';
  }
  if (mins == 0) {
    return '$hours \u5c0f\u65f6';
  }
  return '$hours \u5c0f\u65f6 $mins \u5206\u949f';
}

String _sessionTitle(String? processName, String? windowTitle, String? label) {
  final trimmedLabel = label?.trim();
  final trimmedTitle = windowTitle?.trim();
  if (trimmedLabel != null && trimmedLabel.isNotEmpty) {
    if (trimmedTitle != null && trimmedTitle.isNotEmpty) {
      return '$trimmedLabel \u00b7 $trimmedTitle';
    }
    return trimmedLabel;
  }
  if (trimmedTitle != null && trimmedTitle.isNotEmpty) {
    return trimmedTitle;
  }
  final trimmedProcess = processName?.trim();
  return (trimmedProcess == null || trimmedProcess.isEmpty)
      ? '\u672a\u547d\u540d\u7a97\u53e3'
      : trimmedProcess;
}

String _sessionSubtitle(String? processName, String? category) {
  final parts = <String>[
    if (category != null && category.trim().isNotEmpty) category.trim(),
    if (processName != null && processName.trim().isNotEmpty) processName.trim(),
  ];
  return parts.isEmpty
      ? '\u672a\u5206\u7c7b\u5916\u90e8\u4f1a\u8bdd'
      : parts.join(' \u00b7 ');
}

String _statusText(TrackerState state) {
  if (!state.isRunning) {
    return '\u5df2\u505c\u6b62';
  }
  if (state.isViewingExcludedApp) {
    return '\u51bb\u7ed3\u67e5\u770b\u4e2d';
  }
  if (state.displaySnapshot == null) {
    return '\u7b49\u5f85\u91c7\u96c6';
  }
  return '\u91c7\u96c6\u4e2d';
}

Color _statusColor(TrackerState state) {
  if (!state.isRunning) {
    return Colors.grey;
  }
  if (state.isViewingExcludedApp) {
    return const Color(0xFFF5935A);
  }
  return const Color(0xFF0EA8A0);
}

int _sessionMinutes(DateTime? start, DateTime? end) {
  if (start == null || end == null) {
    return 0;
  }
  return end.difference(start).inMinutes.clamp(0, 1 << 31).toInt();
}

int _sessionInputScore(WorkSession session) {
  return session.keyCount + (session.mouseClicks * 4) + (session.scrollPx ~/ 120);
}

String _formatHourLabel(int hour) {
  final normalized = hour < 0
      ? 0
      : (hour > 23 ? 23 : hour);
  return '${normalized.toString().padLeft(2, '0')}:00';
}

int? _selectedHourForCurrentBucket(
  ActivityHeatmapBucket? bucket,
  DateTime selectedDate,
) {
  if (bucket == null) {
    return null;
  }

  final dayStart = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );
  final dayEnd = dayStart.add(const Duration(days: 1));
  final isHourlyBucket =
      bucket.end.difference(bucket.start) == const Duration(hours: 1);
  if (!isHourlyBucket ||
      bucket.start.isBefore(dayStart) ||
      bucket.end.isAfter(dayEnd)) {
    return null;
  }
  return bucket.start.hour;
}

int? _dominantHourForRange({
  required DateTime itemStart,
  required DateTime itemEnd,
  required DateTime selectedDate,
}) {
  final dayStart = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day,
  );
  final dayEnd = dayStart.add(const Duration(days: 1));
  if (!_timeRangeOverlaps(
    rangeStart: dayStart,
    rangeEnd: dayEnd,
    itemStart: itemStart,
    itemEnd: itemEnd,
  )) {
    return null;
  }

  final normalizedEnd =
      itemEnd.isAfter(itemStart) ? itemEnd : itemStart.add(const Duration(seconds: 1));
  final effectiveStart = itemStart.isBefore(dayStart) ? dayStart : itemStart;
  final effectiveEnd = normalizedEnd.isAfter(dayEnd) ? dayEnd : normalizedEnd;
  if (!effectiveEnd.isAfter(effectiveStart)) {
    return null;
  }

  var bestHour = effectiveStart.hour;
  var bestOverlapSeconds = -1;
  for (var hour = 0; hour < 24; hour += 1) {
    final bucketStart = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
      hour,
    );
    final bucketEnd = bucketStart.add(const Duration(hours: 1));
    final overlapSeconds = _timeRangeOverlapSeconds(
      leftStart: effectiveStart,
      leftEnd: effectiveEnd,
      rightStart: bucketStart,
      rightEnd: bucketEnd,
    );
    if (overlapSeconds > bestOverlapSeconds) {
      bestOverlapSeconds = overlapSeconds;
      bestHour = hour;
    }
  }

  return bestOverlapSeconds <= 0 ? null : bestHour;
}

String _truncateLabel(String value, int maxLength) {
  if (value.length <= maxLength) {
    return value;
  }
  return '${value.substring(0, maxLength)}...';
}

String _trackedInputEventKindLabel(TrackedInputEventKind kind) {
  switch (kind) {
    case TrackedInputEventKind.keyDown:
      return '按键';
    case TrackedInputEventKind.mouseButton:
      return '鼠标按钮';
    case TrackedInputEventKind.mouseWheel:
      return '滚轮';
    case TrackedInputEventKind.mouseMove:
      return '鼠标移动';
  }
}

Color _trackedInputEventColor(TrackedInputEventKind kind) {
  switch (kind) {
    case TrackedInputEventKind.keyDown:
      return const Color(0xFF6B5EE4);
    case TrackedInputEventKind.mouseButton:
      return const Color(0xFF0EA8A0);
    case TrackedInputEventKind.mouseWheel:
      return const Color(0xFFE05A7A);
    case TrackedInputEventKind.mouseMove:
      return const Color(0xFF4C8BF5);
  }
}

String _trackedInputEventTitle(TrackedInputEvent event) {
  switch (event.kind) {
    case TrackedInputEventKind.keyDown:
      final token = describeInputToken(event.tokenText);
      if (token.isNotEmpty) {
        return '按键 $token';
      }
      if (event.keyLabel != null && event.keyLabel!.trim().isNotEmpty) {
        return '按键 ${event.keyLabel!.trim()}';
      }
      if (event.keyCode != null) {
        return '按键 VK_${event.keyCode}';
      }
      return '按键事件';
    case TrackedInputEventKind.mouseButton:
      if (event.mouseButton != null && event.mouseButton!.trim().isNotEmpty) {
        return '鼠标${inputMouseButtonLabel(event.mouseButton!.trim())}';
      }
      return '鼠标按钮事件';
    case TrackedInputEventKind.mouseWheel:
      if (event.mouseButton != null && event.mouseButton!.trim().isNotEmpty) {
        return '滚轮 ${inputMouseButtonLabel(event.mouseButton!.trim())}';
      }
      return '滚轮 ${event.wheelDelta}';
    case TrackedInputEventKind.mouseMove:
      if (event.moveDistance > 0) {
        return '鼠标移动 ${event.moveDistance}px';
      }
      return '鼠标移动';
  }
}

String _rangeSessionSortModeLabel(_RangeSessionSortMode mode) {
  switch (mode) {
    case _RangeSessionSortMode.recent:
      return '最近优先';
    case _RangeSessionSortMode.longest:
      return '时长优先';
    case _RangeSessionSortMode.input:
      return '输入优先';
  }
}

bool _isSameBucket(
  ActivityHeatmapBucket? left,
  ActivityHeatmapBucket? right,
) {
  if (left == null || right == null) {
    return left == null && right == null;
  }
  return left.start == right.start && left.end == right.end;
}

bool _matchesWorkSession(
  WorkSession session, {
  required String searchQuery,
  required String? selectedProcess,
  required String? selectedCategory,
  required int? selectedTaskId,
  required bool onlyWithInput,
  required ActivityHeatmapBucket? selectedHeatmapBucket,
}) {
  if (selectedProcess != null && !session.processNames.contains(selectedProcess)) {
    return false;
  }

  if (selectedCategory != null &&
      !session.categories.contains(selectedCategory) &&
      session.category != selectedCategory) {
    return false;
  }

  if (selectedTaskId != null &&
      !session.records.any((record) => record.linkedTaskId == selectedTaskId)) {
    return false;
  }

  if (onlyWithInput &&
      !_hasInputActivity(
        keyCount: session.keyCount,
        mouseClicks: session.mouseClicks,
        mouseMovePx: session.mouseMovePx,
        scrollPx: session.scrollPx,
      )) {
    return false;
  }

  if (selectedHeatmapBucket != null &&
      !_timeRangeOverlaps(
        rangeStart: selectedHeatmapBucket.start,
        rangeEnd: selectedHeatmapBucket.end,
        itemStart: session.startTime,
        itemEnd: session.endTime,
      )) {
    return false;
  }

  final searchTarget = <String>[
    session.label,
    if (session.processName != null) session.processName!,
    if (session.category != null) session.category!,
    ...session.processNames,
    ...session.categories,
    ...session.records
        .map((record) => record.windowTitle?.trim())
        .whereType<String>(),
  ].join(' ');

  return _matchesSearchText(searchTarget, searchQuery);
}

bool _matchesActivityRecord(
  ActivityRecord record, {
  required String? selectedProcess,
  required String? selectedCategory,
  required bool onlyWithInput,
}) {
  if (selectedProcess != null && record.processName?.trim() != selectedProcess) {
    return false;
  }

  if (selectedCategory != null && record.category?.trim() != selectedCategory) {
    return false;
  }

  if (onlyWithInput &&
      !_hasInputActivity(
        keyCount: record.keyCount,
        mouseClicks: record.mouseClicks,
        mouseMovePx: record.mouseMovePx,
        scrollPx: record.scrollPx,
      )) {
    return false;
  }

  return true;
}

bool _matchesLogEntry(
  ActivityLogEntry entry, {
  required String searchQuery,
  required String? selectedProcess,
  required String? selectedCategory,
  Set<int>? selectedRecordIds,
  required bool onlyWithInput,
  required ActivityHeatmapBucket? selectedHeatmapBucket,
}) {
  if (selectedProcess != null && entry.processName?.trim() != selectedProcess) {
    return false;
  }

  if (selectedCategory != null && entry.category?.trim() != selectedCategory) {
    return false;
  }

  if (selectedRecordIds != null &&
      (entry.recordId == null || !selectedRecordIds.contains(entry.recordId))) {
    return false;
  }

  if (onlyWithInput &&
      !_hasInputActivity(
        keyCount: entry.keyCount,
        mouseClicks: entry.mouseClicks,
        mouseMovePx: entry.mouseMovePx,
        scrollPx: entry.scrollPx,
      )) {
    return false;
  }

  if (selectedHeatmapBucket != null &&
      !_timeRangeContains(
        timestamp: entry.timestamp,
        rangeStart: selectedHeatmapBucket.start,
        rangeEnd: selectedHeatmapBucket.end,
      )) {
    return false;
  }

  final searchTarget = <String>[
    if (entry.label != null) entry.label!,
    if (entry.processName != null) entry.processName!,
    if (entry.windowTitle != null) entry.windowTitle!,
    if (entry.category != null) entry.category!,
    if (entry.note != null) entry.note!,
    _LogEntryTile._entryTypeLabel(entry.type),
  ].join(' ');

  return _matchesSearchText(searchTarget, searchQuery);
}

bool _hasInputActivity({
  required int keyCount,
  required int mouseClicks,
  required int mouseMovePx,
  required int scrollPx,
}) {
  return keyCount > 0 || mouseClicks > 0 || mouseMovePx > 0 || scrollPx > 0;
}

bool _matchesSearchText(String target, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return true;
  }

  final normalizedTarget = target.toLowerCase();
  final tokens = normalizedQuery
      .split(RegExp(r'\s+'))
      .where((token) => token.isNotEmpty)
      .toList(growable: false);

  if (tokens.isEmpty) {
    return true;
  }

  return tokens.every(normalizedTarget.contains);
}

bool _timeRangeOverlaps({
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required DateTime itemStart,
  required DateTime itemEnd,
}) {
  final normalizedItemEnd =
      itemEnd.isAfter(itemStart) ? itemEnd : itemStart.add(const Duration(seconds: 1));
  return itemStart.isBefore(rangeEnd) && normalizedItemEnd.isAfter(rangeStart);
}

bool _timeRangeContains({
  required DateTime timestamp,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  return !timestamp.isBefore(rangeStart) && timestamp.isBefore(rangeEnd);
}

int _timeRangeOverlapSeconds({
  required DateTime leftStart,
  required DateTime leftEnd,
  required DateTime rightStart,
  required DateTime rightEnd,
}) {
  final effectiveStart = leftStart.isAfter(rightStart) ? leftStart : rightStart;
  final effectiveEnd = leftEnd.isBefore(rightEnd) ? leftEnd : rightEnd;
  if (!effectiveEnd.isAfter(effectiveStart)) {
    return 0;
  }
  return effectiveEnd.difference(effectiveStart).inSeconds;
}

String _buildLogTypeSummary(List<ActivityLogEntry> entries) {
  if (entries.isEmpty) {
    return '';
  }

  final counts = <ActivityLogEntryType, int>{};
  for (final entry in entries) {
    counts.update(entry.type, (value) => value + 1, ifAbsent: () => 1);
  }

  final orderedTypes = ActivityLogEntryType.values
      .where(counts.containsKey)
      .toList(growable: false);
  return orderedTypes
      .map((type) => '${_LogEntryTile._entryTypeLabel(type)} ${counts[type]}')
      .join(' · ');
}

String _buildLogDaySummary(List<ActivityLogEntry> entries) {
  if (entries.isEmpty) {
    return '';
  }

  final counts = <String, int>{};
  for (final entry in entries) {
    final day = _formatDate(entry.timestamp);
    counts.update(day, (value) => value + 1, ifAbsent: () => 1);
  }

  final orderedDays = counts.keys.toList()
    ..sort((left, right) => right.compareTo(left));
  return orderedDays
      .take(5)
      .map((day) => '$day ${counts[day]}条')
      .join(' · ');
}

List<String> _collectRangeProcessOptions({
  required List<ActivityRecord> records,
  required List<ActivityLogEntry> logEntries,
}) {
  final values = <String>{};

  for (final record in records) {
    final process = record.processName?.trim();
    if (process != null && process.isNotEmpty) {
      values.add(process);
    }
  }

  for (final entry in logEntries) {
    final process = entry.processName?.trim();
    if (process != null && process.isNotEmpty) {
      values.add(process);
    }
  }

  final sorted = values.toList()
    ..sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
  return sorted;
}

List<String> _collectRangeCategoryOptions({
  required List<ActivityRecord> records,
  required List<ActivityLogEntry> logEntries,
}) {
  final values = <String>{};

  for (final record in records) {
    final category = record.category?.trim();
    if (category != null && category.isNotEmpty) {
      values.add(category);
    }
  }

  for (final entry in logEntries) {
    final category = entry.category?.trim();
    if (category != null && category.isNotEmpty) {
      values.add(category);
    }
  }

  final sorted = values.toList()..sort((left, right) => left.compareTo(right));
  return sorted;
}

String _buildSessionDaySummary(
  List<WorkSession> sessions, {
  int limit = 6,
}) {
  if (sessions.isEmpty) {
    return '';
  }

  final counts = <String, int>{};
  for (final session in sessions) {
    final day = _formatDayShort(session.startTime);
    counts.update(day, (value) => value + 1, ifAbsent: () => 1);
  }

  final orderedDays = counts.keys.toList()
    ..sort((left, right) => right.compareTo(left));

  final preview = orderedDays.take(limit).map(
        (day) => '$day ${counts[day]}段',
      );
  final result = preview.join(' · ');
  if (orderedDays.length <= limit) {
    return result;
  }
  return '$result · 等 ${orderedDays.length} 天';
}

String _joinPreview(List<String> values, {int limit = 3}) {
  if (values.isEmpty) {
    return '\u672a\u77e5\u5e94\u7528';
  }
  if (values.length <= limit) {
    return values.join('\u3001');
  }
  final preview = values.take(limit).join('\u3001');
  return '$preview \u7b49 ${values.length} \u4e2a\u5e94\u7528';
}

List<TaskItem> _buildTaskFilterOptions({
  required List<ActivityRecord> records,
  required Map<int, TaskItem> taskById,
}) {
  final orderedIds = <int>[];
  final seenIds = <int>{};

  for (final record in records) {
    final taskId = record.linkedTaskId;
    if (taskId == null || !seenIds.add(taskId)) {
      continue;
    }
    orderedIds.add(taskId);
  }

  final tasks = orderedIds
      .map((taskId) => taskById[taskId])
      .whereType<TaskItem>()
      .toList(growable: false);
  tasks.sort((left, right) => left.summary.compareTo(right.summary));
  return tasks;
}

List<int> _collectLinkedTaskIds(Iterable<ActivityRecord> records) {
  final ids = <int>{};
  for (final record in records) {
    final taskId = record.linkedTaskId;
    if (taskId != null) {
      ids.add(taskId);
    }
  }
  final sorted = ids.toList()..sort();
  return sorted;
}

String _taskLabel(TaskItem? task, {required int fallbackId}) {
  final summary = task?.summary.trim();
  if (summary != null && summary.isNotEmpty) {
    return summary;
  }
  return '任务 #$fallbackId';
}

List<TaskItem> _buildTrackerTaskCandidates(
  List<TaskItem> tasks,
  DateTime referenceDate,
) {
  final candidates = List<TaskItem>.from(tasks);
  final referenceDay = DateUtils.dateOnly(referenceDate);
  candidates.sort((left, right) {
    final leftCompletion = _taskCompletionRank(left);
    final rightCompletion = _taskCompletionRank(right);
    if (leftCompletion != rightCompletion) {
      return leftCompletion.compareTo(rightCompletion);
    }

    final leftDistance = _taskDayDistance(left, referenceDay);
    final rightDistance = _taskDayDistance(right, referenceDay);
    if (leftDistance != rightDistance) {
      return leftDistance.compareTo(rightDistance);
    }

    final leftAnchor = _taskAnchorTime(left);
    final rightAnchor = _taskAnchorTime(right);
    if (leftAnchor != null && rightAnchor != null) {
      final byAnchor = leftAnchor.compareTo(rightAnchor);
      if (byAnchor != 0) {
        return byAnchor;
      }
    } else if (leftAnchor != null || rightAnchor != null) {
      return leftAnchor == null ? 1 : -1;
    }

    return left.summary.toLowerCase().compareTo(right.summary.toLowerCase());
  });

  return candidates.take(24).toList(growable: false);
}

int _taskCompletionRank(TaskItem task) {
  return task.status == 'COMPLETED' ? 1 : 0;
}

DateTime? _taskAnchorTime(TaskItem task) {
  return task.dtstart ?? task.due ?? task.completed;
}

int _taskDayDistance(TaskItem task, DateTime referenceDay) {
  final anchor = _taskAnchorTime(task);
  if (anchor == null) {
    return 1 << 20;
  }
  return DateUtils.dateOnly(anchor).difference(referenceDay).inDays.abs();
}

String _taskCandidateSubtitle(TaskItem task) {
  final parts = <String>[
    if (task.status.trim().isNotEmpty) _taskStatusLabel(task.status),
    if (task.due != null) '截止 ${_formatDateTimeShort(task.due!)}',
    if (task.dtstart != null) '安排于 ${_formatDateTimeShort(task.dtstart!)}',
  ];
  if (parts.isEmpty) {
    return '暂无时间信息';
  }
  return parts.join(' · ');
}

String _taskStatusLabel(String status) {
  switch (status) {
    case 'COMPLETED':
      return '已完成';
    case 'IN-PROCESS':
      return '进行中';
    case 'CANCELLED':
      return '已取消';
    case 'NEEDS-ACTION':
    default:
      return '待处理';
  }
}
