part of 'tracker_page.dart';

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
                      ),
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

