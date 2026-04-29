part of 'tracker_page.dart';

enum _RangeSessionSortMode {
  recent,
  longest,
  input,
}

// 区间分析已从追踪主页面下沉到二级体验，保留面板实现以便后续接入独立入口。
// ignore: unused_element
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
                  key: ValueKey<String?>('detail-process-$selectedProcess'),
                  initialValue: selectedProcess,
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
                  key: ValueKey<String?>('detail-category-$selectedCategory'),
                  initialValue: selectedCategory,
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
                    : '共 ${sortedSessions.length} 段工作会话，当前显示 $visibleSessionCount 段。',
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
                  ,
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
                  ,
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
                '当前默认显示最新 $visibleLogCount 条，可点击右上角“显示全部”查看完整列表。',
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
                ),
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

