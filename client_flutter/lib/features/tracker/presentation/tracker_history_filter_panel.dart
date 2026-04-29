part of 'tracker_page.dart';

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
                key: ValueKey<String?>('history-process-${widget.selectedProcess}'),
                initialValue: widget.selectedProcess,
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
                key: ValueKey<String?>('history-category-${widget.selectedCategory}'),
                initialValue: widget.selectedCategory,
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
                key: ValueKey<String>('history-task-${widget.selectedTaskId}'),
                initialValue: widget.selectedTaskId,
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

