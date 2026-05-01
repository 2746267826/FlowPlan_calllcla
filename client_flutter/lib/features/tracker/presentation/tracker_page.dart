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
import '../models/work_session.dart';
import '../services/raw_input_service.dart';
import '../services/tracker_platform_source.dart';
import '../services/tracker_service.dart';
import '../widgets/heatmap_widget.dart';

part 'tracker_page_models.dart';
part 'tracker_page_panels.dart';
part 'tracker_day_details_page.dart';
part 'tracker_history_filter_panel.dart';
part 'tracker_input_behavior_panel.dart';
part 'tracker_range_analysis_panel.dart';
part 'tracker_session_tiles.dart';
part 'tracker_page_helpers.dart';

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

    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('任务关联已迁移到服务端活动理解，请在“活动理解与确认”页修正并确认片段。'),
      ),
    );
    context.push(AppRoutes.activityReview);
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
            '\u6570\u636e\u5e93\u5df2\u5bfc\u51fa\u5230\uff1a$outputPath',
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
            '\u5df2\u6253\u5f00\u6570\u636e\u5e93\u76ee\u5f55\uff1a$folderPath',
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

      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('完整键鼠记录导出已迁移为服务端诊断包流程，本地导出不再作为追踪主路径。'),
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
  }) {
    final isLoaded = _loadedKey?.matches(
          selectedDate: selectedDate,
        ) ??
        false;
    if (isLoaded) {
      return;
    }

    final isScheduled = _scheduledKey?.matches(
          selectedDate: selectedDate,
        ) ??
        false;
    if (isScheduled) {
      return;
    }

    _scheduledKey = _TrackerPageLoadKey(
      selectedDate: selectedDate,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _refreshSnapshot();
    });
  }

  _TrackerPageSnapshot _createLoadingSnapshot({
    required TrackerState trackerState,
  }) {
    return _TrackerPageSnapshot(
      dayRecordsAsync: const AsyncLoading<List<ActivityRecord>>(),
      insights: ActivityInsights.empty(),
      workSessions: const <WorkSession>[],
      inputBehaviorSummaryAsync: const AsyncLoading<InputHeatmapSummary>(),
      trackerState: trackerState,
      refreshedAt: DateTime.now(),
    );
  }

  void _updateSnapshotPart({
    required int requestId,
    required _TrackerPageLoadKey key,
    AsyncValue<List<ActivityRecord>>? dayRecordsAsync,
    ActivityInsights? insights,
    List<WorkSession>? workSessions,
    AsyncValue<InputHeatmapSummary>? inputBehaviorSummaryAsync,
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
        dayRecordsAsync: dayRecordsAsync,
        insights: insights,
        workSessions: workSessions,
        inputBehaviorSummaryAsync: inputBehaviorSummaryAsync,
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
    final key = _TrackerPageLoadKey(
      selectedDate: selectedDate,
    );

    if (!force &&
        (_loadedKey?.matches(
              selectedDate: selectedDate,
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
          trackerState: initialTrackerState,
        );
        _loadedKey = key;
      });
    }

    try {
      if (refreshTrackerNow) {
        await ref.read(trackerServiceNotifierProvider.notifier).refreshNow();
      }

      final supportsInputAnalytics =
          TrackerPlatformSource.current().supportsInputAnalytics;
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

      final daySummaryFuture = AsyncValue.guard(
        () => _withLoadTimeout(
          ref.read(activityDaySummaryProvider.future),
          '今日服务端追踪摘要',
        ),
      );
      final inputBehaviorFuture = supportsInputAnalytics
            ? AsyncValue.guard(
                () => _withLoadTimeout(
                ref.read(inputHeatmapSummaryProvider(inputQuery).future),
                '输入行为分析',
              ),
            )
          : Future.value(
              AsyncData<InputHeatmapSummary>(
                InputHeatmapSummary.empty(inputQuery),
              ),
            );
      await Future.wait<void>([
        () async {
          final daySummaryAsync = await daySummaryFuture;
          final records = daySummaryAsync.hasValue
              ? activityRecordsFromServerPreview(daySummaryAsync.value!)
              : const <ActivityRecord>[];
          _updateSnapshotPart(
            requestId: requestId,
            key: key,
            dayRecordsAsync: daySummaryAsync.whenData(
              (_) => records,
            ),
            insights: daySummaryAsync.hasValue
                ? activityInsightsFromServer(daySummaryAsync.value!)
                : ActivityInsights.empty(),
            workSessions: daySummaryAsync.hasValue
                ? workSessionsFromServer(daySummaryAsync.value!)
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
    final selectedProcessRaw = ref.watch(trackerHistorySelectedProcessProvider);
    final selectedHeatmapBucket =
        ref.watch(trackerHistorySelectedHeatmapBucketProvider);
    final selectedAnalysisBucket =
        ref.watch(trackerHistorySelectedAnalysisBucketProvider);
    final heatmapScaleOverride = ref.watch(activityHeatmapScaleOverrideProvider);
    final heatmapSeriesAsync = ref.watch(activityHeatmapSeriesProvider);
    final AsyncValue<TrackerRangeAnalysisSnapshot?>? rangeAnalysisAsync =
        selectedAnalysisBucket == null
            ? null
            : ref.watch(trackerRangeAnalysisProvider);
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
    );

    final snapshot = _snapshot;
    final hasFreshSnapshot = snapshot != null &&
        (_loadedKey?.matches(
              selectedDate: selectedDate,
            ) ??
            false);
    final AsyncValue<List<ActivityRecord>> dayRecordsAsync = hasFreshSnapshot
        ? snapshot.dayRecordsAsync
        : const AsyncLoading<List<ActivityRecord>>();
    final ActivityInsights insights =
        hasFreshSnapshot ? snapshot.insights : ActivityInsights.empty();
    final List<WorkSession> workSessions =
        hasFreshSnapshot ? snapshot.workSessions : const <WorkSession>[];
    final AsyncValue<InputHeatmapSummary> inputBehaviorSummaryAsync = hasFreshSnapshot
        ? snapshot.inputBehaviorSummaryAsync
        : const AsyncLoading<InputHeatmapSummary>();
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
                case _TrackerMenuAction.viewActivityReview:
                  context.push(AppRoutes.activityReview);
                  break;
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
                value: _TrackerMenuAction.viewActivityReview,
                child: Text('活动理解与确认'),
              ),
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
            _card(
              context,
              heatmapSeriesAsync.when(
                loading: () => const SizedBox(
                  height: 180,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => SizedBox(
                  height: 120,
                  child: Center(child: Text('加载热力图失败：$error')),
                ),
                data: (series) => HeatmapWidget(
                  series: series,
                  selectedScaleOverride: heatmapScaleOverride,
                  activeFilterBucket: selectedHeatmapBucket,
                  activeAnalysisBucket: selectedAnalysisBucket,
                  onScaleChanged: (scale) {
                    widget._clearHeatmapSelections(ref);
                    ref
                        .read(activityHeatmapScaleOverrideProvider.notifier)
                        .state = scale;
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
                  onClearBucketFilter: () {
                    widget._clearHeatmapBucketFilter(ref);
                  },
                  onClearAnalysisBucket: () {
                    widget._clearHeatmapAnalysisBucket(ref);
                  },
                ),
              ),
            ),
            if (selectedAnalysisBucket != null) ...[
              const SizedBox(height: 16),
              rangeAnalysisAsync!.when(
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
                      child: Text('加载服务端区间分析失败：$error'),
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
                onOpenActivityReview: () {
                  context.push(AppRoutes.activityReview);
                },
                onOpenDayDetails: () {
                  context.push(AppRoutes.trackerDayDetails);
                },
                onOpenInputHistory: supportsInputAnalytics
                    ? () {
                        context.push(AppRoutes.trackerInputHistory);
                      }
                    : null,
                onOpenInputHeatmap: supportsInputAnalytics
                    ? () {
                        context.push(AppRoutes.trackerInputHeatmap);
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

