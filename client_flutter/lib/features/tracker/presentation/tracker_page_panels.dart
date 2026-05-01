part of 'tracker_page.dart';

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

class _TrackerDetailHubPanel extends StatelessWidget {
  final DateTime selectedDate;
  final int workSessionCount;
  final int activityRecordCount;
  final bool hasLinkedInputBehavior;
  final VoidCallback onOpenActivityReview;
  final VoidCallback onOpenDayDetails;
  final VoidCallback? onOpenInputHistory;
  final VoidCallback? onOpenInputHeatmap;
  final VoidCallback onOpenLogHistory;

  const _TrackerDetailHubPanel({
    required this.selectedDate,
    required this.workSessionCount,
    required this.activityRecordCount,
    required this.hasLinkedInputBehavior,
    required this.onOpenActivityReview,
    required this.onOpenDayDetails,
    required this.onOpenInputHistory,
    required this.onOpenInputHeatmap,
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
            FilledButton.icon(
              onPressed: onOpenActivityReview,
              icon: const Icon(Icons.psychology_alt_outlined, size: 18),
              label: const Text('活动理解与确认'),
            ),
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
            if (onOpenInputHeatmap != null)
              OutlinedButton.icon(
                onPressed: onOpenInputHeatmap,
                icon: const Icon(Icons.grid_view_outlined, size: 18),
                label: const Text('打开键鼠热力图'),
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
        if (state.lastError != null && state.lastError!.trim().isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '追踪诊断：${state.lastError}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
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

