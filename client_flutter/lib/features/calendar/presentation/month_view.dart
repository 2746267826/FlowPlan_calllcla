import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../task/presentation/task_detail_page.dart';
import 'event_detail_page.dart';

final monthEventsProvider = StreamProvider.family<List<CalendarEvent>,
    ({DateTime start, DateTime end})>((ref, range) {
  return ref.watch(eventRepositoryProvider).watchVisibleForDateRange(
        range.start,
        range.end,
      );
});

final monthTasksProvider =
    StreamProvider.family<List<TaskItem>, ({DateTime start, DateTime end})>(
  (ref, range) {
    return ref.watch(taskRepositoryProvider).watchAll().map(
          (tasks) => tasks
              .where(
                (task) =>
                    task.dtstart != null &&
                    task.dtstart!.isAfter(
                      range.start.subtract(const Duration(hours: 1)),
                    ) &&
                    task.dtstart!.isBefore(range.end),
              )
              .toList(),
        );
  },
);

class MonthView extends ConsumerStatefulWidget {
  const MonthView({super.key});

  @override
  ConsumerState<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends ConsumerState<MonthView> {
  CalendarFormat _format = CalendarFormat.month;

  @override
  Widget build(BuildContext context) {
    final selectedDay = ref.watch(selectedDateProvider);
    final monthStart = DateTime(selectedDay.year, selectedDay.month, 1);
    final monthEnd = DateTime(selectedDay.year, selectedDay.month + 1, 1);

    final eventsAsync =
        ref.watch(monthEventsProvider((start: monthStart, end: monthEnd)));
    final tasksAsync =
        ref.watch(monthTasksProvider((start: monthStart, end: monthEnd)));

    final counts = <String, int>{};
    eventsAsync.whenData((events) {
      for (final event in events) {
        final key = '${event.dtstart.year}-${event.dtstart.month}-${event.dtstart.day}';
        counts[key] = (counts[key] ?? 0) + 1;
      }
    });
    tasksAsync.whenData((tasks) {
      for (final task in tasks) {
        final date = task.dtstart;
        if (date == null) continue;
        final key = '${date.year}-${date.month}-${date.day}';
        counts[key] = (counts[key] ?? 0) + 1;
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TableCalendar(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2035, 12, 31),
              focusedDay: selectedDay,
              calendarFormat: _format,
              selectedDayPredicate: (day) => isSameDay(selectedDay, day),
              onDaySelected: (day, focusedDay) {
                ref.read(selectedDateProvider.notifier).setDate(day);
              },
              onPageChanged: (focusedDay) {
                ref.read(selectedDateProvider.notifier).setDate(focusedDay);
              },
              onFormatChanged: (value) {
                setState(() => _format = value);
              },
              eventLoader: (day) {
                final key = '${day.year}-${day.month}-${day.day}';
                return List.generate((counts[key] ?? 0).clamp(0, 4), (_) => '');
              },
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                todayTextStyle: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
                selectedDecoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: const TextStyle(color: Colors.white),
                markersMaxCount: 4,
                markerDecoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                markerSize: 5,
                markersAlignment: Alignment.bottomCenter,
                outsideDaysVisible: false,
              ),
              headerStyle: HeaderStyle(
                titleCentered: true,
                formatButtonDecoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary),
                  borderRadius: BorderRadius.circular(8),
                ),
                formatButtonTextStyle: const TextStyle(color: AppColors.primary),
              ),
              locale: 'zh_CN',
            ),
            const Divider(height: 1),
            Expanded(child: _MonthDayPreview(day: selectedDay)),
          ],
        ),
      ),
    );
  }
}

class _MonthDayPreview extends ConsumerWidget {
  const _MonthDayPreview({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final eventsAsync =
        ref.watch(monthEventsProvider((start: dayStart, end: dayEnd)));
    final tasksAsync =
        ref.watch(monthTasksProvider((start: dayStart, end: dayEnd)));

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(child: Text('\u52a0\u8f7d\u5931\u8d25\uff1a$error')),
      data: (events) {
        final tasks = tasksAsync.maybeWhen(
          data: (value) => value,
          orElse: () => const <TaskItem>[],
        );

        if (events.isEmpty && tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_note_outlined, size: 48, color: Colors.grey.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                Text('${day.month}/${day.day}', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  '\u6682\u65e0\u5b89\u6392',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (events.isNotEmpty) ...[
              Text(
                '\u65e5\u7a0b',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              ...events.map(
                (event) => _PreviewTile(
                  title: event.summary,
                  subtitle: _compactSubtitle([
                    '${event.dtstart.hour.toString().padLeft(2, '0')}:${event.dtstart.minute.toString().padLeft(2, '0')}',
                    event.location,
                    event.description,
                  ]),
                  color: _parseColor(event.colorHex),
                  onTap: () => _showEventDialog(context, event.id),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (tasks.isNotEmpty) ...[
              Text(
                '\u4efb\u52a1',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 4),
              ...tasks.map(
                (task) => _PreviewTile(
                  title: task.summary,
                  subtitle: _compactSubtitle([
                    task.dtstart != null
                        ? '${task.dtstart!.hour.toString().padLeft(2, '0')}:${task.dtstart!.minute.toString().padLeft(2, '0')}'
                        : null,
                    _durationLabel(task.durationMinutes),
                    task.location,
                    task.description,
                  ]),
                  color: _priorityColor(task.priorityLocal),
                  onTap: () => _showTaskDialog(context, task.id),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  void _showEventDialog(BuildContext context, int eventId) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
        child: SizedBox(width: 560, child: EventDetailPage(eventId: eventId)),
      ),
    );
  }

  void _showTaskDialog(BuildContext context, int taskId) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
        child: SizedBox(width: 560, child: TaskDetailPage(taskId: taskId)),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  Color _priorityColor(int priority) {
    if (priority == 1) return const Color(0xFFE53935);
    if (priority == 3) return const Color(0xFF43A047);
    return const Color(0xFF0EA8A0);
  }

  String _compactSubtitle(List<String?> parts) {
    return parts
        .map((part) => part?.trim())
        .whereType<String>()
        .where((part) => part.isNotEmpty)
        .join(' · ');
  }

  String _durationLabel(int minutes) {
    if (minutes < 60) {
      return '$minutes 分钟';
    }
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0 ? '$hours 小时' : '$hours 小时 $rest 分钟';
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Colors.grey.withValues(alpha: 0.7)),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 16, color: Colors.grey.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}
