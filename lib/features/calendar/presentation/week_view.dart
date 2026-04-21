import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/task_block.dart';
import '../../task/presentation/task_detail_page.dart';
import 'event_detail_page.dart';

final weekEventsProvider = StreamProvider.family<List<CalendarEvent>,
    ({DateTime start, DateTime end})>((ref, range) {
  return ref.watch(eventRepositoryProvider).watchVisibleForDateRange(
        range.start,
        range.end,
      );
});

final weekTasksProvider =
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

class WeekView extends ConsumerWidget {
  const WeekView({super.key});

  static const double _hourHeight = 60;
  static const int _startHour = 6;
  static const int _endHour = 24;
  static const _weekdayLabels = [
    '\u4e00',
    '\u4e8c',
    '\u4e09',
    '\u56db',
    '\u4e94',
    '\u516d',
    '\u65e5',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final now = DateTime.now();
    final monday =
        selectedDate.subtract(Duration(days: selectedDate.weekday - 1));
    final days = List.generate(7, (index) => monday.add(Duration(days: index)));
    final weekStart = DateTime(monday.year, monday.month, monday.day);
    final weekEnd = weekStart.add(const Duration(days: 7));

    final eventsAsync =
        ref.watch(weekEventsProvider((start: weekStart, end: weekEnd)));
    final tasksAsync =
        ref.watch(weekTasksProvider((start: weekStart, end: weekEnd)));

    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    '${monday.month}/${monday.day} - ${days.last.month}/${days.last.day}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Text('${selectedDate.year}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          Row(
            children: [
              const SizedBox(width: 44),
              ...days.asMap().entries.map((entry) {
                final index = entry.key;
                final day = entry.value;
                final isToday = day.year == now.year &&
                    day.month == now.month &&
                    day.day == now.day;
                final isSelected = day.year == selectedDate.year &&
                    day.month == selectedDate.month &&
                    day.day == selectedDate.day;
                return Expanded(
                  child: InkWell(
                    onTap: () => ref.read(selectedDateProvider.notifier).setDate(day),
                    child: Column(
                      children: [
                        Text(
                          _weekdayLabels[index],
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: 2),
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : isToday
                                    ? AppColors.primary.withValues(alpha: 0.16)
                                    : Colors.transparent,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected || isToday
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: isSelected ? Colors.white : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              child: SizedBox(
                height: (_endHour - _startHour) * _hourHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Stack(
                        children: List.generate(_endHour - _startHour, (index) {
                          final hour = _startHour + index;
                          return Positioned(
                            top: index * _hourHeight - 8,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Text(
                                hour == _startHour
                                    ? ''
                                    : hour.toString().padLeft(2, '0'),
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.color
                                          ?.withValues(alpha: 0.5),
                                    ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    ...days.map(
                      (day) => Expanded(
                        child: _WeekDayColumn(
                          day: day,
                          now: now,
                          hourHeight: _hourHeight,
                          startHour: _startHour,
                          endHour: _endHour,
                          eventsAsync: eventsAsync,
                          tasksAsync: tasksAsync,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekDayColumn extends StatelessWidget {
  const _WeekDayColumn({
    required this.day,
    required this.now,
    required this.hourHeight,
    required this.startHour,
    required this.endHour,
    required this.eventsAsync,
    required this.tasksAsync,
  });

  final DateTime day;
  final DateTime now;
  final double hourHeight;
  final int startHour;
  final int endHour;
  final AsyncValue<List<CalendarEvent>> eventsAsync;
  final AsyncValue<List<TaskItem>> tasksAsync;

  @override
  Widget build(BuildContext context) {
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;

    return Container(
      decoration: BoxDecoration(
        color: isToday ? AppColors.primary.withValues(alpha: 0.03) : null,
        border: Border(
          left: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
            width: 0.5,
          ),
        ),
      ),
      child: Stack(
        children: [
          ...List.generate(endHour - startHour, (index) {
            return Positioned(
              top: index * hourHeight,
              left: 0,
              right: 0,
              child: Divider(
                height: 1,
                color: Theme.of(context).dividerColor.withValues(alpha: 0.15),
              ),
            );
          }),
          ...eventsAsync.maybeWhen(
            data: (events) => events
                .where(
                  (event) =>
                      event.dtstart.year == day.year &&
                      event.dtstart.month == day.month &&
                      event.dtstart.day == day.day,
                )
                .map((event) {
              final end = event.dtend ?? event.dtstart.add(const Duration(hours: 1));
              final top =
                  (event.dtstart.hour - startHour + event.dtstart.minute / 60) *
                      hourHeight;
              final height =
                  (end.difference(event.dtstart).inMinutes / 60 * hourHeight)
                      .clamp(16.0, 999.0);
              return TaskBlock(
                key: ValueKey('week_event_${event.id}'),
                top: top.clamp(0, 999),
                height: height,
                label: event.summary,
                color: _parseColor(event.colorHex),
                onTap: () => _showEventDialog(context, event.id),
              );
            }).toList(),
            orElse: () => const <Widget>[],
          ),
          ...tasksAsync.maybeWhen(
            data: (tasks) => tasks
                .where(
                  (task) =>
                      task.dtstart != null &&
                      task.dtstart!.year == day.year &&
                      task.dtstart!.month == day.month &&
                      task.dtstart!.day == day.day,
                )
                .map((task) {
              final top = (task.dtstart!.hour - startHour + task.dtstart!.minute / 60) *
                  hourHeight;
              final height =
                  (task.durationMinutes / 60 * hourHeight).clamp(16.0, 999.0);
              return TaskBlock(
                key: ValueKey('week_task_${task.id}'),
                top: top.clamp(0, 999),
                height: height,
                label: task.summary,
                color: _priorityColor(task.priorityLocal),
                onTap: () => _showTaskDialog(context, task.id),
              );
            }).toList(),
            orElse: () => const <Widget>[],
          ),
        ],
      ),
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
}
