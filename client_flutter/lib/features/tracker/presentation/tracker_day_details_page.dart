part of 'tracker_page.dart';

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
    final supportsInputAnalytics =
        TrackerPlatformSource.current().supportsInputAnalytics;
    final selectedDate = ref.watch(selectedDateProvider);
    final recordsAsync = ref.watch(activityRecordsForDateProvider);
    final uploadDiagnosticsAsync = ref.watch(trackingUploadDiagnosticsProvider);
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
    final workSessions = ref.watch(workSessionsForDateProvider);
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
            tooltip: '查看历史活动记录',
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
                              '主页现在只展示服务端处理后的摘要；本页的日志区域仅用于本机上传缓冲诊断，避免把本地日志当作事实统计。',
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
                        label: const Text('查看历史活动记录'),
                      ),
                    ],
                  ),
                  if (hasActiveHistoryFilters) ...[
                    const SizedBox(height: 10),
                    const Text(
                      '当前筛选已作用于服务端会话和本机诊断日志预览；统计、报告和排程均以服务端汇总结果为准。',
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
                  filteredLogCount: 0,
                  totalLogCount: 0,
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
              uploadDiagnosticsAsync.when(
                loading: () => const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => SizedBox(
                  height: 120,
                  child: Center(
                    child: Text('加载上传缓冲状态失败：$error'),
                  ),
                ),
                data: (diagnostics) {
                  final lastActivityRecordId =
                      _intValue(diagnostics['lastActivityRecordId']);
                  final lastInputEventId =
                      _intValue(diagnostics['lastInputEventId']);
                  final lastRawLogId =
                      _intValue(diagnostics['lastRawLogId']);
                  final pendingRecords =
                      _intValue(diagnostics['pendingActivityRecords']);
                  final pendingEvents =
                      _intValue(diagnostics['pendingInputEvents']);
                  final pendingLogs =
                      _intValue(diagnostics['pendingRawLogs']);
                  final lastCompletedAt =
                      _stringValue(diagnostics['lastCompletedAt']);
                  final lastError =
                      _stringValue(diagnostics['lastError']);

                  final totalPending = pendingRecords + pendingEvents + pendingLogs;
                  final hasPending = totalPending > 0;
                  final hasError = lastError != null && lastError.isNotEmpty;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TrackerSectionHeader(
                        icon: Icons.cloud_upload_outlined,
                        title: '上传缓冲状态',
                        subtitle: '显示本机待上传的追踪数据缓冲，数据会定期自动上传到服务端。',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _summaryCard(
                            '待上传活动记录',
                            '$pendingRecords',
                            '游标 ID: $lastActivityRecordId',
                          ),
                          _summaryCard(
                            '待上传输入事件',
                            '$pendingEvents',
                            '游标 ID: $lastInputEventId',
                          ),
                          _summaryCard(
                            '待上传原始日志',
                            '$pendingLogs',
                            '游标 ID: $lastRawLogId',
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _tag(hasPending
                              ? '总计 $totalPending 条待上传'
                              : '缓冲区已清空'),
                          if (lastCompletedAt != null)
                            _tag('上次上传：$lastCompletedAt'),
                        ],
                      ),
                      if (hasError) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .errorContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '上次上传错误：$lastError',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                      ],
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


