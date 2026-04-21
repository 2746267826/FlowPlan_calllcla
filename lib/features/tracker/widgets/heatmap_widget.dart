import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../data/tracker_repository.dart';

class HeatmapWidget extends StatefulWidget {
  final ActivityHeatmapSeries series;
  final ActivityHeatmapScale? selectedScaleOverride;
  final ActivityHeatmapBucket? activeFilterBucket;
  final ActivityHeatmapBucket? activeAnalysisBucket;
  final ValueChanged<ActivityHeatmapScale?> onScaleChanged;
  final ValueChanged<ActivityHeatmapBucket> onFilterBucket;
  final ValueChanged<ActivityHeatmapBucket> onAnalyzeBucket;
  final ValueChanged<ActivityHeatmapBucket> onDrillDownBucket;
  final VoidCallback onClearBucketFilter;
  final VoidCallback onClearAnalysisBucket;

  const HeatmapWidget({
    super.key,
    required this.series,
    required this.selectedScaleOverride,
    required this.activeFilterBucket,
    required this.activeAnalysisBucket,
    required this.onScaleChanged,
    required this.onFilterBucket,
    required this.onAnalyzeBucket,
    required this.onDrillDownBucket,
    required this.onClearBucketFilter,
    required this.onClearAnalysisBucket,
  });

  @override
  State<HeatmapWidget> createState() => _HeatmapWidgetState();
}

class _HeatmapWidgetState extends State<HeatmapWidget> {
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = _defaultIndex(widget.series);
  }

  @override
  void didUpdateWidget(covariant HeatmapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series.scale != widget.series.scale ||
        oldWidget.series.anchorDate != widget.series.anchorDate ||
        oldWidget.series.buckets.length != widget.series.buckets.length) {
      _selectedIndex = _defaultIndex(widget.series);
      return;
    }

    if (oldWidget.activeFilterBucket != widget.activeFilterBucket ||
        oldWidget.activeAnalysisBucket != widget.activeAnalysisBucket) {
      final externallySelected =
          widget.activeAnalysisBucket ?? widget.activeFilterBucket;
      if (externallySelected == null) {
        return;
      }

      final index = widget.series.buckets.indexWhere(
        (bucket) => _isSameBucket(bucket, externallySelected),
      );
      if (index >= 0) {
        _selectedIndex = index;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final series = widget.series;
    final buckets = series.buckets;
    final hasBuckets = buckets.isNotEmpty;
    final selectedIndex = hasBuckets
        ? (_selectedIndex ?? 0).clamp(0, buckets.length - 1).toInt()
        : 0;
    final selectedBucket = hasBuckets ? buckets[selectedIndex] : null;
    final isFilterActive =
        selectedBucket != null &&
        widget.activeFilterBucket != null &&
        _isSameBucket(selectedBucket, widget.activeFilterBucket!);
    final isAnalysisActive =
        selectedBucket != null &&
        widget.activeAnalysisBucket != null &&
        _isSameBucket(selectedBucket, widget.activeAnalysisBucket!);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        final isCompactHeader = maxWidth < 520;
        final columns = _columnCount(
          series.scale,
          buckets.length,
          maxWidth: maxWidth,
        );
        final cellWidth = _cellWidth(
          availableWidth: maxWidth,
          columns: columns,
        );
        final cellHeight = _cellHeight(
          scale: series.scale,
          cellWidth: cellWidth,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isCompactHeader)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTitleBlock(context, series),
                  const SizedBox(height: 12),
                  _buildScaleSelector(),
                ],
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildTitleBlock(context, series),
                  ),
                  const SizedBox(width: 12),
                  _buildScaleSelector(),
                ],
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.auto_awesome_outlined,
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.selectedScaleOverride == null
                        ? '\u5f53\u524d\u4e3a\u81ea\u52a8\u63a8\u8350\uff1a'
                            '${series.historySummary.recommendedScale.label}\u89c6\u56fe'
                        : '\u5f53\u524d\u4e3a\u624b\u52a8\u67e5\u770b\uff1a'
                            '${series.scale.label}\u89c6\u56fe',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildLegend(),
            const SizedBox(height: 12),
            if (!hasBuckets)
              const _EmptyHeatmapState()
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: buckets.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  mainAxisExtent: cellHeight,
                ),
                itemBuilder: (context, index) {
                  final bucket = buckets[index];
                  final isSelected = index == selectedIndex;
                  return _HeatmapCell(
                    bucket: bucket,
                    maxMinutes: series.maxMinutes,
                    isSelected: isSelected,
                    cellWidth: cellWidth,
                    onTap: () {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                  );
                },
              ),
            if (selectedBucket != null) ...[
              const SizedBox(height: 14),
              _SelectedBucketCard(
                bucket: selectedBucket,
                scale: series.scale,
                isFilterActive: isFilterActive,
                isAnalysisActive: isAnalysisActive,
                onFilterAction: () {
                  if (isFilterActive) {
                    widget.onClearBucketFilter();
                    return;
                  }
                  widget.onFilterBucket(selectedBucket);
                },
                onAnalyzeAction: () {
                  if (isAnalysisActive) {
                    widget.onClearAnalysisBucket();
                    return;
                  }
                  widget.onAnalyzeBucket(selectedBucket);
                },
                onDrillDownAction: () {
                  widget.onDrillDownBucket(selectedBucket);
                },
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildTitleBlock(BuildContext context, ActivityHeatmapSeries series) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          series.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          series.subtitle,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Widget _buildScaleSelector() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(
          label: const Text('\u81ea\u52a8'),
          selected: widget.selectedScaleOverride == null,
          onSelected: (_) => widget.onScaleChanged(null),
        ),
        for (final scale in ActivityHeatmapScale.values)
          ChoiceChip(
            label: Text(scale.label),
            selected: widget.selectedScaleOverride == scale,
            onSelected: (_) => widget.onScaleChanged(scale),
          ),
      ],
    );
  }

  Widget _buildLegend() {
    final colors = _colorScale();
    return Row(
      children: [
        const Text(
          '\u5c11',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(width: 6),
        for (final color in colors)
          Container(
            width: 14,
            height: 14,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        const Text(
          '\u591a',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }

  int _defaultIndex(ActivityHeatmapSeries series) {
    if (series.buckets.isEmpty) {
      return 0;
    }
    for (var index = series.buckets.length - 1; index >= 0; index--) {
      if (series.buckets[index].hasData) {
        return index;
      }
    }
    return series.buckets.length - 1;
  }

  int _columnCount(
    ActivityHeatmapScale scale,
    int itemCount, {
    required double maxWidth,
  }) {
    final preferred = switch (scale) {
      ActivityHeatmapScale.hour => 6,
      ActivityHeatmapScale.day => 7,
      ActivityHeatmapScale.month => 4,
      ActivityHeatmapScale.year => 5,
    };
    final compactPreferred = switch (scale) {
      ActivityHeatmapScale.hour => maxWidth < 340 ? 4 : 5,
      ActivityHeatmapScale.day => maxWidth < 340 ? 5 : 7,
      ActivityHeatmapScale.month => 4,
      ActivityHeatmapScale.year => maxWidth < 340 ? 4 : 5,
    };
    return math
        .max(
          1,
          math.min(
            maxWidth < 380 ? compactPreferred : preferred,
            itemCount,
          ),
        )
        .toInt();
  }

  double _cellWidth({
    required double availableWidth,
    required int columns,
  }) {
    if (columns <= 0) {
      return availableWidth;
    }
    final spacing = (math.max(0, columns - 1) * 8).toDouble();
    return (availableWidth - spacing) / columns;
  }

  double _cellHeight({
    required ActivityHeatmapScale scale,
    required double cellWidth,
  }) {
    final compact = cellWidth < 60;
    switch (scale) {
      case ActivityHeatmapScale.hour:
        return compact ? 60 : 74;
      case ActivityHeatmapScale.day:
        return compact ? 56 : 74;
      case ActivityHeatmapScale.month:
        return compact ? 62 : 76;
      case ActivityHeatmapScale.year:
        return compact ? 62 : 76;
    }
  }

  List<Color> _colorScale() {
    return const [
      Color(0xFFEAEFF2),
      Color(0xFFCDE7DE),
      Color(0xFF93D2C1),
      Color(0xFF4CB7A1),
      Color(0xFF178D80),
    ];
  }

  bool _isSameBucket(
    ActivityHeatmapBucket left,
    ActivityHeatmapBucket right,
  ) {
    return left.start == right.start && left.end == right.end;
  }
}

class _HeatmapCell extends StatelessWidget {
  final ActivityHeatmapBucket bucket;
  final int maxMinutes;
  final bool isSelected;
  final double cellWidth;
  final VoidCallback onTap;

  const _HeatmapCell({
    required this.bucket,
    required this.maxMinutes,
    required this.isSelected,
    required this.cellWidth,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = _resolveColor(bucket.totalMinutes, maxMinutes);
    final foreground = bucket.hasData ? Colors.black87 : Colors.grey.shade600;
    final compact = cellWidth < 60;
    final ultraCompact = cellWidth < 48;
    final minutesLabel = ultraCompact
        ? '${bucket.totalMinutes}\u5206'
        : compact
            ? '${bucket.totalMinutes} \u5206'
            : '${bucket.totalMinutes} \u5206\u949f';
    final recordLabel = ultraCompact
        ? '${bucket.completedCount}\u6761'
        : compact
            ? '${bucket.completedCount} \u6761'
            : '${bucket.completedCount} \u6761\u8bb0\u5f55';

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.all(ultraCompact ? 6 : (compact ? 8 : 10)),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              ultraCompact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Text(
              bucket.shortLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: ultraCompact ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                fontSize: ultraCompact ? 11 : 12,
                fontWeight: FontWeight.w700,
                color: foreground,
                height: 1,
              ),
            ),
            const Spacer(),
            Text(
              minutesLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: ultraCompact ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                fontSize: ultraCompact ? 10 : 11,
                color: foreground,
                fontWeight: bucket.hasData ? FontWeight.w600 : FontWeight.w400,
                height: 1,
              ),
            ),
            if (!ultraCompact)
              Text(
                recordLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.start,
                style: TextStyle(
                  fontSize: compact ? 9 : 10,
                  color: foreground.withValues(alpha: 0.75),
                  height: 1,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _resolveColor(int minutes, int maxMinutes) {
    if (minutes <= 0) {
      return const Color(0xFFEAEFF2);
    }
    final ratio = minutes / maxMinutes;
    if (ratio <= 0.25) {
      return const Color(0xFFCDE7DE);
    }
    if (ratio <= 0.5) {
      return const Color(0xFF93D2C1);
    }
    if (ratio <= 0.75) {
      return const Color(0xFF4CB7A1);
    }
    return const Color(0xFF178D80);
  }
}

class _SelectedBucketCard extends StatelessWidget {
  final ActivityHeatmapBucket bucket;
  final ActivityHeatmapScale scale;
  final bool isFilterActive;
  final bool isAnalysisActive;
  final VoidCallback onFilterAction;
  final VoidCallback onAnalyzeAction;
  final VoidCallback onDrillDownAction;

  const _SelectedBucketCard({
    required this.bucket,
    required this.scale,
    required this.isFilterActive,
    required this.isAnalysisActive,
    required this.onFilterAction,
    required this.onAnalyzeAction,
    required this.onDrillDownAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bucket.longLabel,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BucketPill(
                label: '\u6d3b\u52a8\u65f6\u957f',
                value: '${bucket.totalMinutes} \u5206\u949f',
              ),
              _BucketPill(
                label: '\u539f\u59cb\u8bb0\u5f55',
                value: '${bucket.completedCount} \u6761',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _actionHint(
              scale,
              isFilterActive: isFilterActive,
              isAnalysisActive: isAnalysisActive,
            ),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 10),
          if (scale == ActivityHeatmapScale.hour)
            FilledButton.tonalIcon(
              onPressed: onFilterAction,
              icon: Icon(
                _filterActionIcon(isFilterActive: isFilterActive),
                size: 18,
              ),
              label: Text(
                _filterActionLabel(isFilterActive: isFilterActive),
              ),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onAnalyzeAction,
                  icon: Icon(
                    _analysisActionIcon(
                      isAnalysisActive: isAnalysisActive,
                    ),
                    size: 18,
                  ),
                  label: Text(
                    _analysisActionLabel(
                      isAnalysisActive: isAnalysisActive,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onDrillDownAction,
                  icon: const Icon(
                    Icons.zoom_in_outlined,
                    size: 18,
                  ),
                  label: Text(_drillDownActionLabel(scale)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  static String _filterActionLabel({
    required bool isFilterActive,
  }) {
    return isFilterActive
        ? '\u53d6\u6d88\u5217\u8868\u7b5b\u9009'
        : '\u6309\u6b64\u5c0f\u65f6\u7b5b\u9009\u5217\u8868';
  }

  static String _actionHint(
    ActivityHeatmapScale scale, {
    required bool isFilterActive,
    required bool isAnalysisActive,
  }) {
    switch (scale) {
      case ActivityHeatmapScale.hour:
        return isFilterActive
            ? '\u4e0b\u65b9\u5de5\u4f5c\u4f1a\u8bdd\u548c\u539f\u59cb\u65e5\u5fd7\u5df2\u8054\u52a8\u5230\u8fd9\u4e2a\u5c0f\u65f6\uff0c\u53ef\u518d\u6b21\u70b9\u51fb\u53d6\u6d88\u3002'
            : '\u628a\u4e0b\u65b9\u5de5\u4f5c\u4f1a\u8bdd\u548c\u539f\u59cb\u65e5\u5fd7\u7f29\u5c0f\u5230\u8fd9\u4e2a\u5c0f\u65f6\uff0c\u4fbf\u4e8e\u67e5\u770b\u540c\u4e00\u65f6\u95f4\u6bb5\u5185\u7684\u7ec6\u8282\u3002';
      case ActivityHeatmapScale.day:
        return isAnalysisActive
            ? '\u5df2\u5c55\u5f00\u8fd9\u4e00\u5929\u7684\u533a\u95f4\u5206\u6790\uff0c\u4e5f\u53ef\u4ee5\u7ee7\u7eed\u4e0b\u94bb\u5230\u9010\u5c0f\u65f6\u5206\u5e03\u3002'
            : '\u53ef\u4ee5\u5148\u76f4\u63a5\u67e5\u770b\u8fd9\u4e00\u5929\u7684\u805a\u5408\u5206\u6790\uff0c\u4e5f\u53ef\u7ee7\u7eed\u4e0b\u94bb\u5230\u9010\u5c0f\u65f6\u5206\u5e03\u3002';
      case ActivityHeatmapScale.month:
        return isAnalysisActive
            ? '\u5df2\u5c55\u5f00\u8fd9\u4e2a\u6708\u7684\u533a\u95f4\u5206\u6790\uff0c\u4e5f\u53ef\u7ee7\u7eed\u4e0b\u94bb\u5230\u6bcf\u65e5\u5206\u5e03\u3002'
            : '\u53ef\u4ee5\u5148\u76f4\u63a5\u67e5\u770b\u8fd9\u4e2a\u6708\u7684\u805a\u5408\u5206\u6790\uff0c\u4e5f\u53ef\u7ee7\u7eed\u4e0b\u94bb\u5230\u6bcf\u65e5\u5206\u5e03\u3002';
      case ActivityHeatmapScale.year:
        return isAnalysisActive
            ? '\u5df2\u5c55\u5f00\u8fd9\u4e00\u5e74\u7684\u533a\u95f4\u5206\u6790\uff0c\u4e5f\u53ef\u7ee7\u7eed\u4e0b\u94bb\u5230\u9010\u6708\u5206\u5e03\u3002'
            : '\u53ef\u4ee5\u5148\u76f4\u63a5\u67e5\u770b\u8fd9\u4e00\u5e74\u7684\u805a\u5408\u5206\u6790\uff0c\u4e5f\u53ef\u7ee7\u7eed\u4e0b\u94bb\u5230\u9010\u6708\u5206\u5e03\u3002';
    }
  }

  static IconData _filterActionIcon({
    required bool isFilterActive,
  }) {
    return isFilterActive
        ? Icons.filter_alt_off_outlined
        : Icons.filter_alt_outlined;
  }

  static String _analysisActionLabel({
    required bool isAnalysisActive,
  }) {
    return isAnalysisActive
        ? '\u6536\u8d77\u533a\u95f4\u5206\u6790'
        : '\u67e5\u770b\u533a\u95f4\u5206\u6790';
  }

  static IconData _analysisActionIcon({
    required bool isAnalysisActive,
  }) {
    return isAnalysisActive
        ? Icons.analytics_outlined
        : Icons.query_stats_outlined;
  }

  static String _drillDownActionLabel(ActivityHeatmapScale scale) {
    switch (scale) {
      case ActivityHeatmapScale.hour:
        return '';
      case ActivityHeatmapScale.day:
        return '\u8fdb\u5165\u9010\u5c0f\u65f6';
      case ActivityHeatmapScale.month:
        return '\u8fdb\u5165\u6bcf\u65e5';
      case ActivityHeatmapScale.year:
        return '\u8fdb\u5165\u9010\u6708';
    }
  }
}

class _BucketPill extends StatelessWidget {
  final String label;
  final String value;

  const _BucketPill({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label\uff1a$value',
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
    );
  }
}

class _EmptyHeatmapState extends StatelessWidget {
  const _EmptyHeatmapState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      alignment: Alignment.center,
      child: const Column(
        children: [
          Icon(
            Icons.grid_view_outlined,
            size: 36,
            color: Colors.grey,
          ),
          SizedBox(height: 8),
          Text(
            '\u5f53\u524d\u65f6\u95f4\u8303\u56f4\u8fd8\u6ca1\u6709\u6d3b\u52a8\u6570\u636e',
            style: TextStyle(
              color: Colors.grey,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
