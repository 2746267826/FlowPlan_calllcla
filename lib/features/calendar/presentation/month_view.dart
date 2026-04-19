// 月视图 v2 — table_calendar + Provider 驱动的密度标记和当日预览
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/providers/app_providers.dart';
import '../../task/presentation/task_detail_page.dart';
import 'event_detail_page.dart';

// ── 月范围任务/事件 Provider（文档密度标记用）─────────────────────────────────
final monthEventsProvider = StreamProvider.family<List<CalendarEvent>,
    ({DateTime start, DateTime end})>((ref, range) {
  final repo = ref.watch(eventRepositoryProvider);
  return repo.watchForDateRange(range.start, range.end);
});

final monthTasksProvider =
    StreamProvider.family<List<TaskItem>, ({DateTime start, DateTime end})>(
        (ref, range) {
  final repo = ref.watch(taskRepositoryProvider);
  return repo.watchAll().map((tasks) => tasks
      .where((t) =>
          t.dtstart != null &&
          t.dtstart!.isAfter(range.start.subtract(const Duration(hours: 1))) &&
          t.dtstart!.isBefore(range.end))
      .toList());
});

class MonthView extends ConsumerStatefulWidget {
  const MonthView({super.key});

  @override
  ConsumerState<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends ConsumerState<MonthView> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  @override
  Widget build(BuildContext context) {
    // 当月范围
    final monthStart = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final monthEnd = DateTime(_focusedDay.year, _focusedDay.month + 1, 1);

    final eventsAsync =
        ref.watch(monthEventsProvider((start: monthStart, end: monthEnd)));
    final tasksAsync =
        ref.watch(monthTasksProvider((start: monthStart, end: monthEnd)));

    // 构建日→条目数映射（用于密度标记）
    final Map<String, int> dayCountMap = {};
    eventsAsync.whenData((events) {
      for (final e in events) {
        final key = '${e.dtstart.year}-${e.dtstart.month}-${e.dtstart.day}';
        dayCountMap[key] = (dayCountMap[key] ?? 0) + 1;
      }
    });
    tasksAsync.whenData((tasks) {
      for (final t in tasks) {
        if (t.dtstart != null) {
          final key =
              '${t.dtstart!.year}-${t.dtstart!.month}-${t.dtstart!.day}';
          dayCountMap[key] = (dayCountMap[key] ?? 0) + 1;
        }
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TableCalendar(
              firstDay: DateTime.utc(2020, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: _calendarFormat,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                // 更新全局选中日期（影响时间轴等其他视图）
                ref.read(selectedDateProvider.notifier).setDate(selectedDay);
              },
              onFormatChanged: (format) {
                setState(() => _calendarFormat = format);
              },
              onPageChanged: (focusedDay) {
                setState(() => _focusedDay = focusedDay);
              },
              // 密度标记点
              eventLoader: (day) {
                final key = '${day.year}-${day.month}-${day.day}';
                final count = dayCountMap[key] ?? 0;
                // 返回 N 个占位对象作为 marker
                return List.generate(count.clamp(0, 4), (_) => '');
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
                markerSize: 5.0,
                markersAlignment: Alignment.bottomCenter,
                outsideDaysVisible: false,
              ),
              headerStyle: HeaderStyle(
                titleCentered: true,
                formatButtonDecoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary),
                  borderRadius: BorderRadius.circular(8),
                ),
                formatButtonTextStyle:
                    const TextStyle(color: AppColors.primary),
              ),
              locale: 'zh_CN',
            ),
            const Divider(height: 1),
            // 选中日期的任务+日程预览
            Expanded(
              child: _SelectedDayPreview(
                  selectedDay: _selectedDay ?? DateTime.now()),
            ),
          ],
        ),
      ),
    );
  }
}

/// 选中日期的任务+事件列表预览
class _SelectedDayPreview extends ConsumerWidget {
  final DateTime selectedDay;
  const _SelectedDayPreview({required this.selectedDay});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dayStart =
        DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
    final dayEnd = dayStart.add(const Duration(days: 1));

    final eventsAsync =
        ref.watch(monthEventsProvider((start: dayStart, end: dayEnd)));
    final tasksAsync =
        ref.watch(monthTasksProvider((start: dayStart, end: dayEnd)));

    return eventsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('加载失败: $err')),
      data: (events) {
        final tasks = tasksAsync.when(
          data: (t) => t,
          loading: () => <TaskItem>[],
          error: (_, __) => <TaskItem>[],
        );

        if (events.isEmpty && tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_note_outlined,
                    size: 48, color: Colors.grey.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                Text(
                  '${selectedDay.month}月${selectedDay.day}日',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text('暂无安排',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.grey)),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            if (events.isNotEmpty) ...[
              Text('📅 日程',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              ...events.map((e) => _PreviewTile(
                    title: e.summary,
                    subtitle:
                        '${e.dtstart.hour.toString().padLeft(2, '0')}:${e.dtstart.minute.toString().padLeft(2, '0')}',
                    color: _parseColor(e.colorHex),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        insetPadding: const EdgeInsets.symmetric(
                            horizontal: 60, vertical: 40),
                        child: SizedBox(
                            width: 560, child: EventDetailPage(eventId: e.id)),
                      ),
                    ),
                  )),
              const SizedBox(height: 12),
            ],
            if (tasks.isNotEmpty) ...[
              Text('✅ 任务',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: AppColors.primary, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              ...tasks.map((t) => _PreviewTile(
                    title: t.summary,
                    subtitle: t.dtstart != null
                        ? '${t.dtstart!.hour.toString().padLeft(2, '0')}:${t.dtstart!.minute.toString().padLeft(2, '0')} · ${t.durationMinutes}分钟'
                        : '${t.durationMinutes}分钟',
                    color: _priorityColor(t.priorityLocal),
                    onTap: () => showDialog(
                      context: context,
                      builder: (_) => Dialog(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20)),
                        insetPadding: const EdgeInsets.symmetric(
                            horizontal: 60, vertical: 40),
                        child: SizedBox(
                            width: 560, child: TaskDetailPage(taskId: t.id)),
                      ),
                    ),
                  )),
            ],
          ],
        );
      },
    );
  }

  static Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  static Color _priorityColor(int priority) {
    if (priority == 1) return const Color(0xFFE53935);
    if (priority == 3) return const Color(0xFF43A047);
    return const Color(0xFF0EA8A0);
  }
}

class _PreviewTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _PreviewTile({
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

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
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.withValues(alpha: 0.7))),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 16, color: Colors.grey.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}
