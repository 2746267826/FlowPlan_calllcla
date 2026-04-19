// 周视图 v2 — 7列网格，Provider 驱动真实数据
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/widgets/task_block.dart';
import '../../../shared/providers/app_providers.dart';
import '../../task/presentation/task_detail_page.dart';
import 'event_detail_page.dart';

// ── 周任务/事件 Provider ─────────────────────────────────────────────────────
final weekEventsProvider = StreamProvider.family<List<CalendarEvent>,
    ({DateTime start, DateTime end})>((ref, range) {
  final repo = ref.watch(eventRepositoryProvider);
  return repo.watchForDateRange(range.start, range.end);
});

final weekTasksProvider =
    StreamProvider.family<List<TaskItem>, ({DateTime start, DateTime end})>(
        (ref, range) {
  final repo = ref.watch(taskRepositoryProvider);
  // 复用 watchForDate 但需要周范围数据，这里用 watchAll 然后客户端过滤
  return repo.watchAll().map((tasks) => tasks
      .where((t) =>
          t.dtstart != null &&
          t.dtstart!.isAfter(range.start.subtract(const Duration(hours: 1))) &&
          t.dtstart!.isBefore(range.end))
      .toList());
});

class WeekView extends ConsumerWidget {
  const WeekView({super.key});

  static const double _hourHeight = 60.0;
  static const int _startHour = 6;
  static const int _endHour = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];

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
                      '${monday.month}月${monday.day}日 — ${days.last.month}月${days.last.day}日',
                      style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  Text('${now.year}',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
          // 星期标题行
          Row(
            children: [
              const SizedBox(width: 44),
              ...days.asMap().entries.map((entry) {
                final i = entry.key;
                final day = entry.value;
                final isToday = day.day == now.day && day.month == now.month;
                return Expanded(
                  child: Column(
                    children: [
                      Text(weekdays[i],
                          style: Theme.of(context).textTheme.labelSmall),
                      const SizedBox(height: 2),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color:
                              isToday ? AppColors.primary : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text('${day.day}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight:
                                  isToday ? FontWeight.w700 : FontWeight.w400,
                              color: isToday ? Colors.white : null,
                            )),
                      ),
                    ],
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
                    // 时间列
                    SizedBox(
                      width: 44,
                      child: Stack(
                        children: List.generate(_endHour - _startHour, (i) {
                          return Positioned(
                            top: i * _hourHeight - 8,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: Text(
                                i == 0
                                    ? ''
                                    : (_startHour + i)
                                        .toString()
                                        .padLeft(2, '0'),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
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
                    // 7天列
                    ...days.asMap().entries.map((entry) {
                      final day = entry.value;
                      final isToday =
                          day.day == now.day && day.month == now.month;
                      final dayStart = DateTime(day.year, day.month, day.day);

                      return Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: isToday
                                ? AppColors.primary.withValues(alpha: 0.03)
                                : null,
                            border: Border(
                              left: BorderSide(
                                color: Theme.of(context)
                                    .dividerColor
                                    .withValues(alpha: 0.15),
                                width: 0.5,
                              ),
                            ),
                          ),
                          child: Stack(
                            children: [
                              // 小时网格线
                              ...List.generate(_endHour - _startHour, (i) {
                                return Positioned(
                                  top: i * _hourHeight,
                                  left: 0,
                                  right: 0,
                                  child: Divider(
                                    height: 1,
                                    color: Theme.of(context)
                                        .dividerColor
                                        .withValues(alpha: 0.15),
                                  ),
                                );
                              }),
                              // 事件色块
                              ..._buildDayEvents(
                                  context, eventsAsync, dayStart),
                              // 任务色块
                              ..._buildDayTasks(context, tasksAsync, dayStart),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDayEvents(BuildContext context,
      AsyncValue<List<CalendarEvent>> eventsAsync, DateTime dayStart) {
    return eventsAsync.when(
      loading: () => [],
      error: (_, __) => [],
      data: (events) {
        final dayEvents = events.where((e) =>
            e.dtstart.year == dayStart.year &&
            e.dtstart.month == dayStart.month &&
            e.dtstart.day == dayStart.day);

        return dayEvents.map((event) {
          final top =
              (event.dtstart.hour - _startHour + event.dtstart.minute / 60.0) *
                  _hourHeight;
          final endTime =
              event.dtend ?? event.dtstart.add(const Duration(hours: 1));
          final durationHours =
              endTime.difference(event.dtstart).inMinutes / 60.0;
          final height = (durationHours * _hourHeight).clamp(16.0, 999.0);
          final color = _parseColor(event.colorHex);

          return TaskBlock(
            key: ValueKey('we_${event.id}'),
            top: top.clamp(0, 999),
            height: height,
            label: event.summary,
            color: color,
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => Dialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  insetPadding:
                      const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
                  child: SizedBox(
                    width: 560,
                    child: EventDetailPage(eventId: event.id),
                  ),
                ),
              );
            },
          );
        }).toList();
      },
    );
  }

  List<Widget> _buildDayTasks(BuildContext context,
      AsyncValue<List<TaskItem>> tasksAsync, DateTime dayStart) {
    return tasksAsync.when(
      loading: () => [],
      error: (_, __) => [],
      data: (tasks) {
        final dayTasks = tasks.where((t) =>
            t.dtstart != null &&
            t.dtstart!.year == dayStart.year &&
            t.dtstart!.month == dayStart.month &&
            t.dtstart!.day == dayStart.day);

        return dayTasks.map((task) {
          final top =
              (task.dtstart!.hour - _startHour + task.dtstart!.minute / 60.0) *
                  _hourHeight;
          final height =
              (task.durationMinutes / 60.0 * _hourHeight).clamp(16.0, 999.0);
          final color = _priorityColor(task.priorityLocal);

          return TaskBlock(
            key: ValueKey('wt_${task.id}'),
            top: top.clamp(0, 999),
            height: height,
            label: task.summary,
            color: color,
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => Dialog(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  insetPadding:
                      const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
                  child: SizedBox(
                    width: 560,
                    child: TaskDetailPage(taskId: task.id),
                  ),
                ),
              );
            },
          );
        }).toList();
      },
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
