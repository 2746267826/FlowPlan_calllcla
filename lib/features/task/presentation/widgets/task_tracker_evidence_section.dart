import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/providers/app_providers.dart';
import '../../../tracker/models/activity_insights.dart';
import '../../../tracker/models/input_heatmap_summary.dart';
import '../../../tracker/models/tracked_input_event.dart';
import '../../../tracker/models/work_session.dart';

final _taskLinkedRecordsProvider =
    StreamProvider.family<List<ActivityRecord>, int>((ref, taskId) {
  final repository = ref.watch(activityRecordRepositoryProvider);
  return repository.watchByTaskId(taskId);
});

final _taskLinkedInputSummaryProvider =
    FutureProvider.family<InputHeatmapSummary, int>((ref, taskId) {
  final service = ref.watch(inputActivityEventServiceProvider);
  return service.buildHeatmapSummaryForTask(taskId);
});

final _taskLinkedRecentEventsProvider =
    FutureProvider.family<List<TrackedInputEvent>, int>((ref, taskId) {
  final service = ref.watch(inputActivityEventServiceProvider);
  return service.listRecentEventsForTask(taskId, limit: 8);
});

class TaskTrackerEvidenceSection extends ConsumerWidget {
  const TaskTrackerEvidenceSection({
    super.key,
    required this.taskId,
  });

  final int taskId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(_taskLinkedRecordsProvider(taskId));
    final inputSummaryAsync = ref.watch(_taskLinkedInputSummaryProvider(taskId));
    final recentEventsAsync = ref.watch(_taskLinkedRecentEventsProvider(taskId));

    return recordsAsync.when(
      loading: () => _TaskTrackerSectionCard(
        child: SizedBox(
          height: 180,
          child: const Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (error, _) => _TaskTrackerSectionCard(
        child: _TaskTrackerMessage(
          icon: Icons.warning_amber_rounded,
          title: '追踪证据读取失败',
          subtitle: '$error',
        ),
      ),
      data: (records) {
        final insights = ActivityInsights.fromRecords(records);
        final sessions = WorkSessionGrouper.fromRecords(records);
        final latestAnchor = sessions.isNotEmpty
            ? sessions.last.startTime
            : (records.isEmpty ? null : records.last.startTime);
        final recentRecords = records.reversed.take(6).toList(growable: false);

        return _TaskTrackerSectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.radar_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '追踪证据',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      final anchor = latestAnchor ?? DateTime.now();
                      ref.read(selectedDateProvider.notifier).setDate(anchor);
                      context.go(AppRoutes.tracker);
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('打开追踪页'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                records.isEmpty
                    ? '这个任务还没有关联追踪记录。后续可在追踪页中从工作会话或原始记录直接绑定。'
                    : '这里汇总与当前任务关联的工作会话、原始活动记录和输入行为证据，方便回看真实执行过程。',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              if (records.isEmpty)
                const _TaskTrackerMessage(
                  icon: Icons.link_off_outlined,
                  title: '暂时没有追踪证据',
                  subtitle: '先去追踪页中把工作会话或原始活动记录关联到这个任务，这里就会自动出现历史证据。',
                )
              else ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _TaskTrackerMetricCard(
                      title: '累计追踪时长',
                      value: _formatMinutes(insights.totalMinutes),
                      subtitle: '来自 ${records.length} 条原始记录',
                    ),
                    _TaskTrackerMetricCard(
                      title: '工作会话',
                      value: '${sessions.length} 段',
                      subtitle: '已按去碎片规则合并',
                    ),
                    _TaskTrackerMetricCard(
                      title: '按键与点击',
                      value: '${insights.totalKeys} 键 / ${insights.totalClicks} 次',
                      subtitle: '来自活动记录聚合',
                    ),
                    _TaskTrackerMetricCard(
                      title: '输入事件',
                      value: inputSummaryAsync.maybeWhen(
                        data: (summary) => '${summary.totalEventCount} 条',
                        orElse: () => '读取中',
                      ),
                      subtitle: inputSummaryAsync.maybeWhen(
                        data: (summary) =>
                            '活跃 ${summary.activeMinuteCount} 分钟',
                        orElse: () => '来自 tracked_input_events',
                      ),
                    ),
                  ],
                ),
                if (insights.topProcesses.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    '主力应用：${insights.topProcesses.map((item) => item.label).join('、')}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
                const SizedBox(height: 18),
                _TaskInputEvidencePanel(
                  summaryAsync: inputSummaryAsync,
                  recentEventsAsync: recentEventsAsync,
                ),
                const SizedBox(height: 18),
                Text(
                  '关联工作会话',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                ...sessions.reversed.take(5).map(
                  (session) => _TaskLinkedSessionCard(
                    session: session,
                    onOpenDay: () {
                      ref.read(selectedDateProvider.notifier).setDate(
                            session.startTime,
                          );
                      context.go(AppRoutes.tracker);
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '最近关联的原始记录',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                ...recentRecords.map(
                  (record) => _TaskLinkedRecordCard(
                    record: record,
                    onOpenDay: () {
                      ref.read(selectedDateProvider.notifier).setDate(
                            record.startTime,
                          );
                      context.go(AppRoutes.tracker);
                    },
                    onUnlink: () async {
                      await ref
                          .read(activityRecordRepositoryProvider)
                          .linkTask(record.id, null);
                      ref.invalidate(_taskLinkedInputSummaryProvider(taskId));
                      ref.invalidate(_taskLinkedRecentEventsProvider(taskId));
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已取消这条原始记录与当前任务的关联'),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TaskInputEvidencePanel extends StatelessWidget {
  const _TaskInputEvidencePanel({
    required this.summaryAsync,
    required this.recentEventsAsync,
  });

  final AsyncValue<InputHeatmapSummary> summaryAsync;
  final AsyncValue<List<TrackedInputEvent>> recentEventsAsync;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '输入行为证据',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        summaryAsync.when(
          loading: () => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              '正在汇总任务级输入行为分析…',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          error: (error, _) => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '读取输入行为分析失败：$error',
              style: const TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
          data: (summary) {
            if (summary.totalEventCount <= 0) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  '当前任务已有关联记录，但还没有更细粒度的输入事件可供分析。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              );
            }

            final peakHour = summary.peakHourBucket;
            final leadingProcess = summary.leadingProcessIntensity;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _TaskTag(
                      text:
                          '键盘占比 ${(summary.keyboardInteractionShare * 100).toStringAsFixed(1)}%',
                    ),
                    _TaskTag(
                      text:
                          '指针占比 ${(summary.pointerInteractionShare * 100).toStringAsFixed(1)}%',
                    ),
                    if (peakHour != null)
                      _TaskTag(
                        text:
                            '峰值时段 ${_formatHourLabel(peakHour.hour)} · ${peakHour.totalEvents} 条',
                      ),
                    if (leadingProcess != null)
                      _TaskTag(
                        text:
                            '主力应用 ${leadingProcess.processName} · 强度 ${leadingProcess.intensityScore}',
                      ),
                  ],
                ),
                if (summary.topKeys.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: summary.topKeys
                        .take(6)
                        .map(
                          (item) => _TaskTag(
                            text: '${item.label} ${item.count} 次',
                            highlighted: true,
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
                const SizedBox(height: 12),
                recentEventsAsync.when(
                  loading: () => const Text(
                    '正在读取最近输入事件…',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  error: (error, _) => Text(
                    '最近输入事件读取失败：$error',
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                  data: (events) {
                    if (events.isEmpty) {
                      return const Text(
                        '当前没有可展示的最近输入事件。',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      );
                    }

                    return Column(
                      children: events
                          .map((event) => _TaskRecentEventTile(event: event))
                          .toList(growable: false),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TaskLinkedSessionCard extends StatelessWidget {
  const _TaskLinkedSessionCard({
    required this.session,
    required this.onOpenDay,
  });

  final WorkSession session;
  final VoidCallback onOpenDay;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (session.category != null && session.category!.trim().isNotEmpty)
        session.category!.trim(),
      if (session.processName != null && session.processName!.trim().isNotEmpty)
        session.processName!.trim(),
      if (session.spansMultipleProcesses) '跨 ${session.processNames.length} 个应用',
      if (session.interruptionCount > 0) '吸收 ${session.interruptionCount} 次打断',
    ].join(' · ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
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
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _formatMinutes(session.durationMinutes),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatDate(session.startTime)} ${_formatTime(session.startTime)} - ${_formatTime(session.endTime)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              meta,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TaskTag(text: '${session.keyCount} 次按键'),
              _TaskTag(text: '${session.mouseClicks} 次点击'),
              if (session.scrollPx > 0) _TaskTag(text: '${session.scrollPx}px 滚动'),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onOpenDay,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('查看当天追踪'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskLinkedRecordCard extends StatelessWidget {
  const _TaskLinkedRecordCard({
    required this.record,
    required this.onOpenDay,
    required this.onUnlink,
  });

  final ActivityRecord record;
  final VoidCallback onOpenDay;
  final Future<void> Function() onUnlink;

  @override
  Widget build(BuildContext context) {
    final endTime = record.endTime ?? record.startTime;
    final meta = <String>[
      if (record.category != null && record.category!.trim().isNotEmpty)
        record.category!.trim(),
      if (record.processName != null && record.processName!.trim().isNotEmpty)
        record.processName!.trim(),
    ].join(' · ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  WorkSessionGrouper.preferredLabel(record),
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
                _formatMinutes(record.durationMinutes),
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatDate(record.startTime)} ${_formatTime(record.startTime)} - ${_formatTime(endTime)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              meta,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (record.keyCount > 0) _TaskTag(text: '${record.keyCount} 次按键'),
              if (record.mouseClicks > 0)
                _TaskTag(text: '${record.mouseClicks} 次点击'),
              if (record.scrollPx > 0) _TaskTag(text: '${record.scrollPx}px 滚动'),
              if (record.mouseMovePx > 0)
                _TaskTag(text: '${record.mouseMovePx}px 移动'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: onOpenDay,
                icon: const Icon(Icons.travel_explore_outlined, size: 16),
                label: const Text('查看当天'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  onUnlink();
                },
                icon: const Icon(Icons.link_off_outlined, size: 16),
                label: const Text('取消关联'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskRecentEventTile extends StatelessWidget {
  const _TaskRecentEventTile({
    required this.event,
  });

  final TrackedInputEvent event;

  @override
  Widget build(BuildContext context) {
    final subtitle = <String>[
      if (event.processName != null && event.processName!.trim().isNotEmpty)
        event.processName!.trim(),
      if (event.activityLabel != null && event.activityLabel!.trim().isNotEmpty)
        event.activityLabel!.trim(),
    ].join(' · ');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              _formatTimeWithSeconds(event.timestamp),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _eventTitle(event),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
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

class _TaskTrackerMetricCard extends StatelessWidget {
  const _TaskTrackerMetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 170, maxWidth: 230),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _TaskTrackerSectionCard extends StatelessWidget {
  const _TaskTrackerSectionCard({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).dividerColor.withValues(alpha: 0.12),
        ),
      ),
      child: child,
    );
  }
}

class _TaskTrackerMessage extends StatelessWidget {
  const _TaskTrackerMessage({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 28, color: Colors.grey),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _TaskTag extends StatelessWidget {
  const _TaskTag({
    required this.text,
    this.highlighted = false,
  });

  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? AppColors.primary : Colors.grey.shade700;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlighted
            ? AppColors.primary.withValues(alpha: 0.08)
            : Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: highlighted ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}

String _formatDate(DateTime value) {
  final date = value.toLocal();
  return '${date.year}年${date.month}月${date.day}日';
}

String _formatTime(DateTime value) {
  final date = value.toLocal();
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _formatTimeWithSeconds(DateTime value) {
  final date = value.toLocal();
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  final second = date.second.toString().padLeft(2, '0');
  return '$hour:$minute:$second';
}

String _formatMinutes(int minutes) {
  if (minutes <= 0) {
    return '不足 1 分钟';
  }
  if (minutes < 60) {
    return '$minutes 分钟';
  }
  final hours = minutes ~/ 60;
  final restMinutes = minutes % 60;
  if (restMinutes == 0) {
    return '$hours 小时';
  }
  return '$hours 小时 $restMinutes 分钟';
}

String _formatHourLabel(int hour) {
  final start = hour.toString().padLeft(2, '0');
  final end = ((hour + 1) % 24).toString().padLeft(2, '0');
  return '$start:00-$end:00';
}

String _eventTitle(TrackedInputEvent event) {
  switch (event.kind) {
    case TrackedInputEventKind.keyDown:
      final label = event.keyLabel?.trim();
      if (label != null && label.isNotEmpty) {
        return '按键 $label';
      }
      return '按键输入';
    case TrackedInputEventKind.mouseButton:
      return '鼠标${event.mouseButton ?? '按键'}';
    case TrackedInputEventKind.mouseWheel:
      return '滚轮 ${event.wheelDelta}';
    case TrackedInputEventKind.mouseMove:
      return '鼠标移动 ${event.moveDistance}px';
  }
}
