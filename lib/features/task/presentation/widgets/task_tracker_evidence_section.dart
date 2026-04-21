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
  return ref.watch(activityRecordRepositoryProvider).watchByTaskId(taskId);
});

final _taskLinkedInputSummaryProvider =
    FutureProvider.family<InputHeatmapSummary, int>((ref, taskId) {
  return ref.watch(inputActivityEventServiceProvider).buildHeatmapSummaryForTask(taskId);
});

final _taskLinkedRecentEventsProvider =
    FutureProvider.family<List<TrackedInputEvent>, int>((ref, taskId) {
  return ref.watch(inputActivityEventServiceProvider).listRecentEventsForTask(taskId, limit: 8);
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
    final summaryAsync = ref.watch(_taskLinkedInputSummaryProvider(taskId));
    final recentEventsAsync = ref.watch(_taskLinkedRecentEventsProvider(taskId));

    return recordsAsync.when(
      loading: () => const _SectionCard(
        child: SizedBox(height: 180, child: Center(child: CircularProgressIndicator())),
      ),
      error: (error, _) => _SectionCard(
        child: _EmptyMessage(
          icon: Icons.warning_amber_rounded,
          title: '\u8ffd\u8e2a\u8bc1\u636e\u8bfb\u53d6\u5931\u8d25',
          subtitle: '$error',
        ),
      ),
      data: (records) {
        final insights = ActivityInsights.fromRecords(records);
        final sessions = WorkSessionGrouper.fromRecords(records);
        final latestAnchor = sessions.isNotEmpty
            ? sessions.last.startTime
            : (records.isEmpty ? null : records.last.startTime);
        final recentRecords = records.reversed.take(5).toList(growable: false);

        return _SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.radar_outlined, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '\u8ffd\u8e2a\u8bc1\u636e',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      ref.read(selectedDateProvider.notifier).setDate(latestAnchor ?? DateTime.now());
                      context.go(AppRoutes.tracker);
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('\u6253\u5f00\u8ffd\u8e2a\u9875'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                records.isEmpty
                    ? '\u5f53\u524d\u4efb\u52a1\u8fd8\u6ca1\u6709\u5173\u8054\u8ffd\u8e2a\u8bb0\u5f55\u3002\u540e\u7eed\u53ef\u4ee5\u5728\u8ffd\u8e2a\u9875\u4e2d\u4ece\u5de5\u4f5c\u4f1a\u8bdd\u6216\u539f\u59cb\u6d3b\u52a8\u8bb0\u5f55\u76f4\u63a5\u7ed1\u5b9a\u3002'
                    : '\u8fd9\u91cc\u4f1a\u6c47\u603b\u5f53\u524d\u4efb\u52a1\u5173\u8054\u7684\u5de5\u4f5c\u4f1a\u8bdd\u3001\u539f\u59cb\u6d3b\u52a8\u8bb0\u5f55\u4e0e\u8f93\u5165\u884c\u4e3a\u8bc1\u636e\u3002',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              if (records.isEmpty)
                const _EmptyMessage(
                  icon: Icons.link_off_outlined,
                  title: '\u6682\u65f6\u6ca1\u6709\u8ffd\u8e2a\u8bc1\u636e',
                  subtitle: '\u5148\u5728\u8ffd\u8e2a\u9875\u4e2d\u628a\u5de5\u4f5c\u4f1a\u8bdd\u6216\u539f\u59cb\u6d3b\u52a8\u8bb0\u5f55\u5173\u8054\u5230\u8fd9\u4e2a\u4efb\u52a1\u3002',
                )
              else ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _MetricCard(
                      title: '\u7d2f\u8ba1\u8ffd\u8e2a\u65f6\u957f',
                      value: _formatMinutes(insights.totalMinutes),
                      subtitle: '\u6765\u81ea ${records.length} \u6761\u539f\u59cb\u8bb0\u5f55',
                    ),
                    _MetricCard(
                      title: '\u5de5\u4f5c\u4f1a\u8bdd',
                      value: '${sessions.length} \u6bb5',
                      subtitle: '\u5df2\u6309\u53bb\u788e\u7247\u89c4\u5219\u5408\u5e76',
                    ),
                    _MetricCard(
                      title: '\u6309\u952e\u4e0e\u70b9\u51fb',
                      value: '${insights.totalKeys} \u952e / ${insights.totalClicks} \u6b21',
                      subtitle: '\u6765\u81ea\u6d3b\u52a8\u8bb0\u5f55\u805a\u5408',
                    ),
                    _MetricCard(
                      title: '\u8f93\u5165\u4e8b\u4ef6',
                      value: summaryAsync.maybeWhen(
                        data: (summary) => '${summary.totalEventCount} \u6761',
                        orElse: () => '\u8bfb\u53d6\u4e2d',
                      ),
                      subtitle: summaryAsync.maybeWhen(
                        data: (summary) => '\u6d3b\u8dc3 ${summary.activeMinuteCount} \u5206\u949f',
                        orElse: () => '\u6765\u81ea tracked_input_events',
                      ),
                    ),
                  ],
                ),
                if (insights.topProcesses.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    '\u4e3b\u529b\u5e94\u7528\uff1a${insights.topProcesses.map((item) => item.label).join('\u3001')}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
                const SizedBox(height: 18),
                _InputEvidencePanel(
                  summaryAsync: summaryAsync,
                  recentEventsAsync: recentEventsAsync,
                ),
                const SizedBox(height: 18),
                Text(
                  '\u5173\u8054\u5de5\u4f5c\u4f1a\u8bdd',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                ...sessions.reversed.take(5).map(
                  (session) => _SessionCard(
                    session: session,
                    onOpenDay: () {
                      ref.read(selectedDateProvider.notifier).setDate(session.startTime);
                      context.go(AppRoutes.tracker);
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  '\u6700\u8fd1\u5173\u8054\u7684\u539f\u59cb\u8bb0\u5f55',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                ...recentRecords.map(
                  (record) => _RecordCard(
                    record: record,
                    onOpenDay: () {
                      ref.read(selectedDateProvider.notifier).setDate(record.startTime);
                      context.go(AppRoutes.tracker);
                    },
                    onUnlink: () async {
                      await ref.read(activityRecordRepositoryProvider).linkTask(record.id, null);
                      ref.invalidate(_taskLinkedInputSummaryProvider(taskId));
                      ref.invalidate(_taskLinkedRecentEventsProvider(taskId));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('\u5df2\u53d6\u6d88\u8fd9\u6761\u8bb0\u5f55\u4e0e\u5f53\u524d\u4efb\u52a1\u7684\u5173\u8054'),
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

class _InputEvidencePanel extends StatelessWidget {
  const _InputEvidencePanel({
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
          '\u8f93\u5165\u884c\u4e3a\u8bc1\u636e',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        summaryAsync.when(
          loading: () => _surfaceMessage('\u6b63\u5728\u6c47\u603b\u4efb\u52a1\u7ea7\u8f93\u5165\u884c\u4e3a\u5206\u6790...', context),
          error: (error, _) => _surfaceMessage(
            '\u8bfb\u53d6\u8f93\u5165\u884c\u4e3a\u5206\u6790\u5931\u8d25\uff1a$error',
            context,
            isError: true,
          ),
          data: (summary) {
            if (summary.totalEventCount <= 0) {
              return _surfaceMessage(
                '\u5f53\u524d\u4efb\u52a1\u5df2\u6709\u5173\u8054\u8bb0\u5f55\uff0c\u4f46\u8fd8\u6ca1\u6709\u66f4\u7ec6\u7c92\u5ea6\u7684\u8f93\u5165\u4e8b\u4ef6\u53ef\u4f9b\u5206\u6790\u3002',
                context,
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Tag(text: '\u952e\u76d8\u5360\u6bd4 ${(summary.keyboardInteractionShare * 100).toStringAsFixed(1)}%'),
                    _Tag(text: '\u6307\u9488\u5360\u6bd4 ${(summary.pointerInteractionShare * 100).toStringAsFixed(1)}%'),
                    if (summary.peakHourBucket != null)
                      _Tag(
                        text:
                            '\u5cf0\u503c\u65f6\u6bb5 ${_formatHourLabel(summary.peakHourBucket!.hour)} \u00b7 ${summary.peakHourBucket!.totalEvents} \u6761',
                      ),
                    if (summary.leadingProcessIntensity != null)
                      _Tag(
                        text:
                            '\u4e3b\u529b\u5e94\u7528 ${summary.leadingProcessIntensity!.processName} \u00b7 \u5f3a\u5ea6 ${summary.leadingProcessIntensity!.intensityScore}',
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
                        .map((item) => _Tag(text: '${item.label} ${item.count} \u6b21', highlighted: true))
                        .toList(growable: false),
                  ),
                ],
                const SizedBox(height: 12),
                recentEventsAsync.when(
                  loading: () => const Text(
                    '\u6b63\u5728\u8bfb\u53d6\u6700\u8fd1\u8f93\u5165\u4e8b\u4ef6...',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  error: (error, _) => Text(
                    '\u6700\u8fd1\u8f93\u5165\u4e8b\u4ef6\u8bfb\u53d6\u5931\u8d25\uff1a$error',
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                  data: (events) {
                    if (events.isEmpty) {
                      return const Text(
                        '\u5f53\u524d\u6ca1\u6709\u53ef\u5c55\u793a\u7684\u6700\u8fd1\u8f93\u5165\u4e8b\u4ef6\u3002',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      );
                    }
                    return Column(
                      children: events
                          .map((event) => _RecentEventTile(event: event))
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

  Widget _surfaceMessage(
    String message,
    BuildContext context, {
    bool isError = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        message,
        style: TextStyle(fontSize: 12, color: isError ? Colors.red : Colors.grey),
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.onOpenDay,
  });

  final WorkSession session;
  final VoidCallback onOpenDay;

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (session.category != null && session.category!.trim().isNotEmpty) session.category!.trim(),
      if (session.processName != null && session.processName!.trim().isNotEmpty) session.processName!.trim(),
      if (session.spansMultipleProcesses) '\u8de8 ${session.processNames.length} \u4e2a\u5e94\u7528',
      if (session.interruptionCount > 0) '\u88ab\u6253\u65ad ${session.interruptionCount} \u6b21',
    ].join(' \u00b7 ');

    return _EvidenceCard(
      title: session.label,
      subtitle:
          '${_formatDate(session.startTime)} ${_formatTime(session.startTime)} - ${_formatTime(session.endTime)}',
      durationText: _formatMinutes(session.durationMinutes),
      meta: meta,
      tags: [
        _Tag(text: '${session.keyCount} \u6b21\u6309\u952e'),
        _Tag(text: '${session.mouseClicks} \u6b21\u70b9\u51fb'),
        if (session.scrollPx > 0) _Tag(text: '${session.scrollPx}px \u6eda\u52a8'),
      ],
      trailing: TextButton.icon(
        onPressed: onOpenDay,
        icon: const Icon(Icons.open_in_new, size: 16),
        label: const Text('\u67e5\u770b\u5f53\u5929\u8ffd\u8e2a'),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
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
      if (record.category != null && record.category!.trim().isNotEmpty) record.category!.trim(),
      if (record.processName != null && record.processName!.trim().isNotEmpty) record.processName!.trim(),
    ].join(' \u00b7 ');

    return _EvidenceCard(
      title: WorkSessionGrouper.preferredLabel(record),
      subtitle:
          '${_formatDate(record.startTime)} ${_formatTime(record.startTime)} - ${_formatTime(endTime)}',
      durationText: _formatMinutes(record.durationMinutes),
      meta: meta,
      tags: [
        if (record.keyCount > 0) _Tag(text: '${record.keyCount} \u6b21\u6309\u952e'),
        if (record.mouseClicks > 0) _Tag(text: '${record.mouseClicks} \u6b21\u70b9\u51fb'),
        if (record.scrollPx > 0) _Tag(text: '${record.scrollPx}px \u6eda\u52a8'),
        if (record.mouseMovePx > 0) _Tag(text: '${record.mouseMovePx}px \u79fb\u52a8'),
      ],
      trailing: Row(
        children: [
          TextButton.icon(
            onPressed: onOpenDay,
            icon: const Icon(Icons.travel_explore_outlined, size: 16),
            label: const Text('\u67e5\u770b\u5f53\u5929'),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: onUnlink,
            icon: const Icon(Icons.link_off_outlined, size: 16),
            label: const Text('\u53d6\u6d88\u5173\u8054'),
          ),
        ],
      ),
    );
  }
}

class _RecentEventTile extends StatelessWidget {
  const _RecentEventTile({required this.event});

  final TrackedInputEvent event;

  @override
  Widget build(BuildContext context) {
    final subtitle = <String>[
      if (event.processName != null && event.processName!.trim().isNotEmpty) event.processName!.trim(),
      if (event.activityLabel != null && event.activityLabel!.trim().isNotEmpty) event.activityLabel!.trim(),
    ].join(' \u00b7 ');

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
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _eventTitle(event),
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
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
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({
    required this.title,
    required this.subtitle,
    required this.durationText,
    required this.meta,
    required this.tags,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final String durationText;
  final String meta;
  final List<Widget> tags;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Text(durationText, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(meta, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: tags),
          ],
          const SizedBox(height: 8),
          trailing,
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

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

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({
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
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
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

class _Tag extends StatelessWidget {
  const _Tag({
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
            : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
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
  return '${date.year}\u5e74${date.month}\u6708${date.day}\u65e5';
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
  if (minutes <= 0) return '\u4e0d\u8db3 1 \u5206\u949f';
  if (minutes < 60) return '$minutes \u5206\u949f';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (rest == 0) return '$hours \u5c0f\u65f6';
  return '$hours \u5c0f\u65f6 $rest \u5206\u949f';
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
        return '\u6309\u952e $label';
      }
      return '\u6309\u952e\u8f93\u5165';
    case TrackedInputEventKind.mouseButton:
      return '\u9f20\u6807${event.mouseButton ?? '\u6309\u952e'}';
    case TrackedInputEventKind.mouseWheel:
      return '\u6eda\u8f6e ${event.wheelDelta}';
    case TrackedInputEventKind.mouseMove:
      return '\u9f20\u6807\u79fb\u52a8 ${event.moveDistance}px';
  }
}
