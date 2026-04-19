// 时间轴视图 v2：Provider 驱动，渲染数据库中的真实任务和日程
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/widgets/time_indicator.dart';
import '../../../shared/widgets/task_block.dart';
import '../../../shared/providers/app_providers.dart';
import '../../task/presentation/task_detail_page.dart';
import 'event_detail_page.dart';

class TimelineView extends ConsumerStatefulWidget {
  const TimelineView({super.key});

  @override
  ConsumerState<TimelineView> createState() => _TimelineViewState();
}

class _TimelineViewState extends ConsumerState<TimelineView> {
  static const double _hourHeight = 80.0;
  static const double _timeColumnWidth = 56.0;
  static const int _startHour = 0;
  static const int _endHour = 24;
  final double _totalHeight = (_endHour - _startHour) * _hourHeight;

  double? _hoverY;
  TaskItem? _hoverTaskItem;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow());
  }

  void _scrollToNow() {
    final now = TimeOfDay.now();
    final offset = (now.hour + now.minute / 60.0 - 2) * _hourHeight;
    _scrollController.animateTo(
      offset.clamp(0, _totalHeight),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selectedDate = ref.watch(selectedDateProvider);
    final tasksAsync = ref.watch(tasksForSelectedDateProvider);
    final eventsAsync = ref.watch(eventsForSelectedDateProvider);
    final isWide = MediaQuery.of(context).size.width >= 600;

    return Scaffold(
      body: Column(
        children: [
          _buildHeader(context, selectedDate),
          _buildDateStrip(context, selectedDate),
          Expanded(
            child: _buildTimeline(context, isWide, tasksAsync, eventsAsync),
          ),
        ],
      ),
    );
  }

  // ─── 顶部标题栏 ──────────────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, DateTime date) {
    final weekdays = ['一', '二', '三', '四', '五', '六', '日'];
    final weekday = weekdays[date.weekday - 1];
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
                Text('${date.month}月${date.day}日 星期$weekday',
                    style: Theme.of(context).textTheme.titleLarge),
                Text(isToday ? '今日' : '${date.year}年',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.primary)),
              ],
            ),
            const Spacer(),
            if (!isToday)
              TextButton(
                onPressed: () =>
                    ref.read(selectedDateProvider.notifier).goToToday(),
                child: const Text('今日'),
              ),
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () =>
                  ref.read(selectedDateProvider.notifier).goToPrevDay(),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () =>
                  ref.read(selectedDateProvider.notifier).goToNextDay(),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 日期横向滚动条 ──────────────────────────────────────────────────────
  Widget _buildDateStrip(BuildContext context, DateTime selectedDate) {
    final now = DateTime.now();
    return SizedBox(
      height: 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 14,
        itemBuilder: (ctx, i) {
          final day = now.subtract(Duration(days: 7 - i));
          final isToday = day.day == now.day &&
              day.month == now.month &&
              day.year == now.year;
          final isSelected = day.day == selectedDate.day &&
              day.month == selectedDate.month &&
              day.year == selectedDate.year;
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
                    ['一', '二', '三', '四', '五', '六', '日'][day.weekday - 1],
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
                      fontWeight: isSelected || isToday
                          ? FontWeight.w700
                          : FontWeight.w400,
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

  // ─── 时间轴主体 ──────────────────────────────────────────────────────────
  Widget _buildTimeline(
    BuildContext context,
    bool isWide,
    AsyncValue<List<TaskItem>> tasksAsync,
    AsyncValue<List<CalendarEvent>> eventsAsync,
  ) {
    return SingleChildScrollView(
      controller: _scrollController,
      child: SizedBox(
        height: _totalHeight,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 左侧小时刻度
            SizedBox(
              width: _timeColumnWidth,
              child: Stack(
                children: List.generate(_endHour - _startHour, (i) {
                  final hour = _startHour + i;
                  return Positioned(
                    top: i * _hourHeight - 8,
                    left: 0,
                    right: 0,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        hour == 0
                            ? ''
                            : '${hour.toString().padLeft(2, '0')}:00',
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
            ),
            // 分隔线
            Container(
              width: 1,
              color: Theme.of(context).dividerColor.withValues(alpha: 0.3),
            ),
            // 双轨道区域
            Expanded(
              child: Stack(
                children: [
                  // 小时网格线
                  ..._buildGridLines(context),
                  // 计划列 + 实际列并排
                  Row(
                    children: [
                      // 计划列（接受从收集箱拖入的任务）
                      Expanded(
                        flex: 3,
                        child: DragTarget<TaskItem>(
                          onAcceptWithDetails: (details) async {
                            setState(() {
                              _hoverY = null;
                              _hoverTaskItem = null;
                            });
                            // 使用 RenderBox 获取相对坐标
                            final RenderBox box =
                                context.findRenderObject() as RenderBox;
                            final localPos = box.globalToLocal(details.offset);
                            // localPos 已经是在整体长列表中的坐标，直接使用
                            final adjustedY = localPos.dy;
                            // 计算具体落点时间
                            final selectedDate = ref.read(selectedDateProvider);
                            final dropTime =
                                _topToDateTime(adjustedY, selectedDate);
                            // 更新任务 dtstart
                            await ref
                                .read(taskRepositoryProvider)
                                .updateDtstart(details.data.id, dropTime);
                          },
                          onMove: (details) {
                            final RenderBox box =
                                context.findRenderObject() as RenderBox;
                            final localPos = box.globalToLocal(details.offset);
                            setState(() {
                              _hoverY = localPos.dy;
                              _hoverTaskItem = details.data;
                            });
                          },
                          onLeave: (data) {
                            setState(() {
                              _hoverY = null;
                              _hoverTaskItem = null;
                            });
                          },
                          builder: (context, candidateData, rejectedData) {
                            final isHovering = candidateData.isNotEmpty;
                            return Stack(
                              children: [
                                if (isHovering)
                                  Positioned.fill(
                                    child: Container(
                                      color: AppColors.primary
                                          .withValues(alpha: 0.06),
                                    ),
                                  ),
                                Positioned(
                                  top: 4,
                                  left: 8,
                                  child: Text('计划',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w600)),
                                ),
                                // 真实事件数据
                                ..._buildEventBlocks(eventsAsync),
                                // 真实任务数据
                                ..._buildTaskBlocks(tasksAsync),
                                // 实时阴影预览 (Ghost Block)
                                if (_hoverY != null && _hoverTaskItem != null)
                                  Positioned(
                                    top: _hoverY!,
                                    left: 4,
                                    right: 4,
                                    height:
                                        ((_hoverTaskItem!.durationMinutes > 0
                                                    ? _hoverTaskItem!
                                                        .durationMinutes
                                                    : 30) /
                                                60.0) *
                                            _hourHeight,
                                    child: IgnorePointer(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: AppColors.primary
                                              .withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                            color: AppColors.primary
                                                .withValues(alpha: 0.5),
                                            width: 1.5,
                                            style: BorderStyle.solid,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      // 分隔
                      Container(
                        width: 1,
                        color: Theme.of(context)
                            .dividerColor
                            .withValues(alpha: 0.2),
                      ),
                      // 实际列：活动记录色块
                      Expanded(
                        flex: 2,
                        child: Consumer(builder: (context, ref, _) {
                          final recordsAsync =
                              ref.watch(activityRecordsForDateProvider);
                          return Stack(
                            children: [
                              Positioned(
                                top: 4,
                                left: 8,
                                child: Text('实际',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                            color: Colors.grey,
                                            fontWeight: FontWeight.w600)),
                              ),
                              ...recordsAsync.when(
                                loading: () => <Widget>[],
                                error: (_, __) => <Widget>[],
                                data: (records) => records
                                    .where((r) => r.endTime != null)
                                    .map((r) {
                                  final startMin = r.startTime.hour * 60 +
                                      r.startTime.minute -
                                      _startHour * 60;
                                  final endMin = r.endTime!.hour * 60 +
                                      r.endTime!.minute -
                                      _startHour * 60;
                                  final top = (startMin / 60.0) * _hourHeight;
                                  final height = ((endMin - startMin) / 60.0) *
                                      _hourHeight;
                                  if (height < 2) return const SizedBox();
                                  final color = _categoryColor(r.category);
                                  return Positioned(
                                    top: top,
                                    left: 4,
                                    right: 4,
                                    height: height.clamp(4.0, double.infinity),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: color.withValues(alpha: 0.5),
                                          width: 1,
                                        ),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      child: Text(
                                        r.manualLabel ??
                                            r.category ??
                                            r.processName ??
                                            '',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: color,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          );
                        }),
                      ),
                    ],
                  ),
                  // 当前时间红线
                  const TimeIndicator(
                      hourHeight: _hourHeight, startHour: _startHour),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGridLines(BuildContext context) {
    return List.generate(_endHour - _startHour, (i) {
      return Positioned(
        top: i * _hourHeight,
        left: 0,
        right: 0,
        child: Divider(
          height: 1,
          color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
        ),
      );
    });
  }

  // ── 像素坐标 → 时间转换 ──────────────────────────────────────────────────
  DateTime _topToDateTime(double top, DateTime baseDate) {
    final totalMinutes = (top / _hourHeight * 60).round();
    // 吸附到15分钟栅格
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
    final minutes = (height / _hourHeight * 60).round();
    return (minutes / 15).round() * 15; // 吸附到15分钟
  }

  // ── 渲染数据库中的事件 ────────────────────────────────────────────
  List<Widget> _buildEventBlocks(AsyncValue<List<CalendarEvent>> eventsAsync) {
    final selectedDate = ref.read(selectedDateProvider);
    return eventsAsync.when(
      loading: () => [],
      error: (_, __) => [],
      data: (events) => events.map((event) {
        final top =
            (event.dtstart.hour + event.dtstart.minute / 60.0) * _hourHeight;
        final endTime =
            event.dtend ?? event.dtstart.add(const Duration(hours: 1));
        final durationHours =
            endTime.difference(event.dtstart).inMinutes / 60.0;
        final height = (durationHours * _hourHeight).clamp(20.0, 999.0);
        final color = _parseColor(event.colorHex);

        return TaskBlock(
          key: ValueKey('event_${event.id}'),
          top: top,
          height: height,
          label: event.summary,
          color: color,
          isDraggable: true,
          onDragEnd: (finalTop) async {
            final newStart = _topToDateTime(finalTop, selectedDate);
            final duration = endTime.difference(event.dtstart);
            final newEnd = newStart.add(duration);
            await ref
                .read(eventRepositoryProvider)
                .updateTimes(event.id, newStart, newEnd);
          },
          onResizeEnd: (finalHeight) async {
            final newMins = _heightToMinutes(finalHeight);
            final newEnd =
                event.dtstart.add(Duration(minutes: newMins.clamp(15, 1440)));
            await ref
                .read(eventRepositoryProvider)
                .updateTimes(event.id, event.dtstart, newEnd);
          },
          onTap: () {
            final isDesktop = MediaQuery.of(context).size.width >= 700;
            if (isDesktop) {
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
            } else {
              context.push('/event/detail/${event.id}');
            }
          },
        );
      }).toList(),
    );
  }

  // ── 渲染数据库中的任务（有 dtstart 的）──────────────────────────────
  List<Widget> _buildTaskBlocks(AsyncValue<List<TaskItem>> tasksAsync) {
    final selectedDate = ref.read(selectedDateProvider);
    return tasksAsync.when(
      loading: () => [],
      error: (_, __) => [],
      data: (tasks) => tasks.where((t) => t.dtstart != null).map((task) {
        final top =
            (task.dtstart!.hour + task.dtstart!.minute / 60.0) * _hourHeight;
        final height =
            (task.durationMinutes / 60.0 * _hourHeight).clamp(20.0, 999.0);
        final color = _priorityColor(task.priorityLocal);

        // 用 LongPressDraggable 包裹，支持拖回收集箱
        return Positioned(
          key: ValueKey('task_pos_${task.id}'),
          top: top + 2,
          left: 4,
          right: 4,
          height: height - 4,
          child: LongPressDraggable<TaskItem>(
            data: task,
            delay: const Duration(milliseconds: 300),
            hapticFeedbackOnStart: true,
            feedback: Consumer(builder: (context, ref, _) {
              final isHoveringTimeline =
                  ref.watch(dragHoveringTimelineProvider);
              if (isHoveringTimeline) return const SizedBox.shrink();

              return Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 180,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    task.summary,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            }),
            childWhenDragging: const SizedBox.shrink(),
            child: _buildTaskBlockContent(
                task, top, height, color, selectedDate,
                isDraggable: true),
          ),
        );
      }).toList(),
    );
  }

  /// 构造任务色块内容（抽取出来供 draggable 和非 draggable 复用）
  Widget _buildTaskBlockContent(
    TaskItem task,
    double top,
    double height,
    Color color,
    DateTime selectedDate, {
    required bool isDraggable,
  }) {
    return TaskBlock(
      top: 0, // 在 Positioned 中已定位，此处不需要偏移
      height: height,
      label: task.summary,
      color: color,
      isDraggable: isDraggable,
      onDragEnd: isDraggable
          ? (finalTop) async {
              final newStart = _topToDateTime(finalTop + top, selectedDate);
              await ref
                  .read(taskRepositoryProvider)
                  .updateDtstart(task.id, newStart);
            }
          : null,
      onResizeEnd: isDraggable
          ? (finalHeight) async {
              final newMins = _heightToMinutes(finalHeight).clamp(15, 1440);
              await ref
                  .read(taskRepositoryProvider)
                  .updateDuration(task.id, newMins);
            }
          : null,
      onTap: () {
        final isDesktop = MediaQuery.of(context).size.width >= 700;
        if (isDesktop) {
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
        } else {
          context.push('/task/detail/${task.id}');
        }
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
    switch (priority) {
      case 1:
        return const Color(0xFFE53935); // 高
      case 3:
        return const Color(0xFF43A047); // 低
      default:
        return const Color(0xFF0EA8A0); // 中
    }
  }

  Color _categoryColor(String? category) {
    switch (category) {
      case '编程':
        return const Color(0xFF6B5EE4);
      case '办公':
        return const Color(0xFF0EA8A0);
      case '设计':
        return const Color(0xFFE91E63);
      case '沟通':
        return const Color(0xFF2196F3);
      case '学习':
        return const Color(0xFFFF9800);
      case '娱乐':
      case '游戏':
        return const Color(0xFFE53935);
      case '浏览器':
        return const Color(0xFF4CAF50);
      default:
        return Colors.blueGrey;
    }
  }
}
