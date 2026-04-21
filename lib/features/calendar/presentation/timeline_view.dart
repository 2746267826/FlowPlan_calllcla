import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/task_block.dart';
import '../../../shared/widgets/time_indicator.dart';
import '../../task/presentation/task_detail_page.dart';
import 'event_detail_page.dart';

class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({super.key});

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView> {
  static const double _hourHeight = 80;
  static const double _timeColumnWidth = 56;
  static const int _startHour = 0;
  static const int _endHour = 24;

  final ScrollController _scrollController = ScrollController();
  double? _hoverTop;
  TaskItem? _hoverTask;

  double get _totalHeight => (_endHour - _startHour) * _hourHeight;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToNow() {
    final now = TimeOfDay.now();
    final offset = (now.hour + now.minute / 60 - 2) * _hourHeight;
    _scrollController.animateTo(
      offset.clamp(0, _totalHeight),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final tasksAsync = ref.watch(tasksForSelectedDateProvider);
    final eventsAsync = ref.watch(eventsForSelectedDateProvider);

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(context, selectedDate),
          _buildDateStrip(context, selectedDate),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              child: SizedBox(
                height: _totalHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHourColumn(context),
                    Container(
                      width: 1,
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
                    ),
                    Expanded(
                      child: Stack(
                        children: [
                          ..._buildGridLines(context),
                          Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: _PlanColumn(
                                  hourHeight: _hourHeight,
                                  selectedDate: selectedDate,
                                  hoverTop: _hoverTop,
                                  hoverTask: _hoverTask,
                                  tasksAsync: tasksAsync,
                                  eventsAsync: eventsAsync,
                                  onHoverChanged: (top, task) {
                                    setState(() {
                                      _hoverTop = top;
                                      _hoverTask = task;
                                    });
                                  },
                                ),
                              ),
                              Container(
                                width: 1,
                                color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                              ),
                              Expanded(
                                flex: 2,
                                child: _ActualColumn(hourHeight: _hourHeight),
                              ),
                            ],
                          ),
                          const TimeIndicator(
                            hourHeight: _hourHeight,
                            startHour: _startHour,
                          ),
                        ],
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

  Widget _buildHeader(BuildContext context, DateTime date) {
    const weekdayLabels = [
      '\u4e00',
      '\u4e8c',
      '\u4e09',
      '\u56db',
      '\u4e94',
      '\u516d',
      '\u65e5',
    ];
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${date.month}/${date.day} \u661f\u671f${weekdayLabels[date.weekday - 1]}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  isToday ? '\u4eca\u65e5' : '${date.year}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.primary,
                      ),
                ),
              ],
            ),
            const Spacer(),
            if (!isToday)
              TextButton(
                onPressed: () => ref.read(selectedDateProvider.notifier).goToToday(),
                child: const Text('\u4eca\u65e5'),
              ),
            IconButton(
              onPressed: () => ref.read(selectedDateProvider.notifier).goToPrevDay(),
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              onPressed: () => ref.read(selectedDateProvider.notifier).goToNextDay(),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateStrip(BuildContext context, DateTime selectedDate) {
    final now = DateTime.now();
    final anchor = selectedDate;
    const weekdayLabels = [
      '\u4e00',
      '\u4e8c',
      '\u4e09',
      '\u56db',
      '\u4e94',
      '\u516d',
      '\u65e5',
    ];

    return SizedBox(
      height: 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 14,
        itemBuilder: (context, index) {
          final day = anchor.subtract(Duration(days: 7 - index));
          final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
          final isSelected = day.year == selectedDate.year &&
              day.month == selectedDate.month &&
              day.day == selectedDate.day;
          return GestureDetector(
            onTap: () => ref.read(selectedDateProvider.notifier).setDate(day),
            child: Container(
              width: 44,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primary
                    : isToday
                        ? AppColors.primary.withValues(alpha: 0.15)
                        : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    weekdayLabels[day.weekday - 1],
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected
                          ? Colors.white
                          : Theme.of(context).textTheme.bodySmall?.color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${day.day}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w400,
                      color: isSelected
                          ? Colors.white
                          : Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHourColumn(BuildContext context) {
    return SizedBox(
      width: _timeColumnWidth,
      child: Stack(
        children: List.generate(_endHour - _startHour, (index) {
          final hour = _startHour + index;
          return Positioned(
            top: index * _hourHeight - 8,
            left: 0,
            right: 0,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                hour == 0 ? '' : '${hour.toString().padLeft(2, '0')}:00',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.color
                          ?.withValues(alpha: 0.6),
                    ),
              ),
            ),
          );
        }),
      ),
    );
  }

  List<Widget> _buildGridLines(BuildContext context) {
    return List.generate(_endHour - _startHour, (index) {
      return Positioned(
        top: index * _hourHeight,
        left: 0,
        right: 0,
        child: Divider(
          height: 1,
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      );
    });
  }
}

class _PlanColumn extends ConsumerWidget {
  const _PlanColumn({
    required this.hourHeight,
    required this.selectedDate,
    required this.hoverTop,
    required this.hoverTask,
    required this.tasksAsync,
    required this.eventsAsync,
    required this.onHoverChanged,
  });

  final double hourHeight;
  final DateTime selectedDate;
  final double? hoverTop;
  final TaskItem? hoverTask;
  final AsyncValue<List<TaskItem>> tasksAsync;
  final AsyncValue<List<CalendarEvent>> eventsAsync;
  final void Function(double? top, TaskItem? task) onHoverChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<TaskItem>(
      onAcceptWithDetails: (details) async {
        onHoverChanged(null, null);
        final renderBox = context.findRenderObject() as RenderBox;
        final local = renderBox.globalToLocal(details.offset);
        final start = _topToDateTime(local.dy, selectedDate);
        await ref.read(taskRepositoryProvider).updateDtstart(details.data.id, start);
      },
      onMove: (details) {
        final renderBox = context.findRenderObject() as RenderBox;
        final local = renderBox.globalToLocal(details.offset);
        onHoverChanged(local.dy, details.data);
      },
      onLeave: (_) => onHoverChanged(null, null),
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty;
        return Stack(
          children: [
            if (hovering)
              Positioned.fill(
                child: Container(color: AppColors.primary.withValues(alpha: 0.06)),
              ),
            Positioned(
              top: 4,
              left: 8,
              child: Text(
                '\u8ba1\u5212',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            ...eventsAsync.maybeWhen(
              data: (events) => events
                  .map(
                    (event) => TaskBlock(
                      key: ValueKey('timeline_event_${event.id}'),
                      top: (event.dtstart.hour + event.dtstart.minute / 60) * hourHeight,
                      height: ((event.dtend ?? event.dtstart.add(const Duration(hours: 1)))
                                      .difference(event.dtstart)
                                      .inMinutes /
                                  60 *
                                  hourHeight)
                              .clamp(20.0, 999.0),
                      label: event.summary,
                      color: _parseColor(event.colorHex),
                      isDraggable: event.source != 'outlook',
                      onDragEnd: event.source == 'outlook'
                          ? null
                          : (finalTop) async {
                              final start = _topToDateTime(finalTop, selectedDate);
                              final duration =
                                  (event.dtend ?? event.dtstart.add(const Duration(hours: 1)))
                                      .difference(event.dtstart);
                              await ref.read(eventRepositoryProvider).updateTimes(
                                    event.id,
                                    start,
                                    start.add(duration),
                                  );
                            },
                      onResizeEnd: event.source == 'outlook'
                          ? null
                          : (finalHeight) async {
                              final minutes = _heightToMinutes(finalHeight).clamp(15, 1440);
                              await ref.read(eventRepositoryProvider).updateTimes(
                                    event.id,
                                    event.dtstart,
                                    event.dtstart.add(Duration(minutes: minutes)),
                                  );
                            },
                      onTap: () => _openEvent(context, event.id),
                    ),
                  )
                  .toList(),
              orElse: () => const <Widget>[],
            ),
            ...tasksAsync.maybeWhen(
              data: (tasks) => tasks
                  .where((task) => task.dtstart != null)
                  .map(
                    (task) => TaskBlock(
                      top: (task.dtstart!.hour + task.dtstart!.minute / 60) * hourHeight,
                      height:
                          (task.durationMinutes / 60 * hourHeight).clamp(20.0, 999.0),
                      label: task.summary,
                      color: _priorityColor(task.priorityLocal),
                      isDraggable: true,
                      onDragEnd: (finalTop) async {
                        final start = _topToDateTime(finalTop, selectedDate);
                        await ref.read(taskRepositoryProvider).updateDtstart(task.id, start);
                      },
                      onResizeEnd: (finalHeight) async {
                        final minutes = _heightToMinutes(finalHeight).clamp(15, 1440);
                        await ref.read(taskRepositoryProvider).updateDuration(task.id, minutes);
                      },
                      onTap: () => _openTask(context, task.id),
                    ),
                  )
                  .toList(),
              orElse: () => const <Widget>[],
            ),
            if (hoverTop != null && hoverTask != null)
              Positioned(
                top: hoverTop!,
                left: 4,
                right: 4,
                height: ((hoverTask!.durationMinutes <= 0 ? 30 : hoverTask!.durationMinutes) /
                        60 *
                        hourHeight)
                    .clamp(20.0, 999.0),
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _openEvent(BuildContext context, int eventId) {
    if (MediaQuery.of(context).size.width >= 700) {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
          child: SizedBox(width: 560, child: EventDetailPage(eventId: eventId)),
        ),
      );
      return;
    }
    context.push('/event/$eventId');
  }

  void _openTask(BuildContext context, int taskId) {
    if (MediaQuery.of(context).size.width >= 700) {
      showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
          child: SizedBox(width: 560, child: TaskDetailPage(taskId: taskId)),
        ),
      );
      return;
    }
    context.push('/task/$taskId');
  }

  DateTime _topToDateTime(double top, DateTime baseDate) {
    final totalMinutes = (top / hourHeight * 60).round();
    final snapped = (totalMinutes / 15).round() * 15;
    return DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      snapped ~/ 60,
      snapped % 60,
    );
  }

  int _heightToMinutes(double height) {
    final minutes = (height / hourHeight * 60).round();
    return (minutes / 15).round() * 15;
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

class _ActualColumn extends ConsumerWidget {
  const _ActualColumn({required this.hourHeight});

  final double hourHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(activityRecordsForDateProvider);

    return Stack(
      children: [
        Positioned(
          top: 4,
          left: 8,
          child: Text(
            '\u5b9e\u9645',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.grey,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        ...recordsAsync.maybeWhen(
          data: (records) => records
              .where((record) => record.endTime != null)
              .map((record) {
            final startMinutes = record.startTime.hour * 60 + record.startTime.minute;
            final endMinutes = record.endTime!.hour * 60 + record.endTime!.minute;
            final top = (startMinutes / 60) * hourHeight;
            final height = ((endMinutes - startMinutes) / 60) * hourHeight;
            if (height < 2) return const SizedBox.shrink();
            final color = _categoryColor(record.category);
            return Positioned(
              top: top,
              left: 4,
              right: 4,
              height: height.clamp(4.0, double.infinity),
              child: Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: color.withValues(alpha: 0.5)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  record.manualLabel ?? record.category ?? record.processName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
                ),
              ),
            );
          }).toList(),
          orElse: () => const <Widget>[],
        ),
      ],
    );
  }

  Color _categoryColor(String? category) {
    switch (category) {
      case '\u7f16\u7a0b':
        return const Color(0xFF6B5EE4);
      case '\u529e\u516c':
        return const Color(0xFF0EA8A0);
      case '\u8bbe\u8ba1':
        return const Color(0xFFE91E63);
      case '\u6c9f\u901a':
        return const Color(0xFF2196F3);
      case '\u5b66\u4e60':
        return const Color(0xFFFF9800);
      case '\u5a31\u4e50':
      case '\u6e38\u620f':
        return const Color(0xFFE53935);
      case '\u6d4f\u89c8\u5668':
        return const Color(0xFF4CAF50);
      default:
        return Colors.blueGrey;
    }
  }
}
