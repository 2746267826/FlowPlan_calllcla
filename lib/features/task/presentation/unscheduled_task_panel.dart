import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/providers/app_providers.dart';
import 'task_detail_page.dart';

/// 未排程任务面板（支持 LongPressDraggable 拖拽到时间轴排程）
class UnscheduledTaskPanel extends ConsumerWidget {
  const UnscheduledTaskPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(allTasksProvider);
    final taskListsAsync = ref.watch(allTaskListsProvider);

    final List<TaskList> taskLists = taskListsAsync.when(
      data: (lists) => lists,
      loading: () => <TaskList>[],
      error: (_, __) => <TaskList>[],
    );

    return DragTarget<TaskItem>(
      // 只接受已排期的任务（dtstart != null），收集箱自身的未排期任务不重复接收
      onWillAcceptWithDetails: (details) => details.data.dtstart != null,
      onAcceptWithDetails: (details) async {
        await ref.read(taskRepositoryProvider).clearDtstart(details.data.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('任务「${details.data.summary}」已退回收集箱')),
          );
        }
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Container(
          width: 320,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: isHovering
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context, isHovering),
              const Divider(height: 1),
              Expanded(
                child: tasksAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(child: Text('加载失败: $err')),
                  data: (tasks) {
                    final unscheduledTasks =
                        tasks.where((t) => t.dtstart == null).toList();

                    if (unscheduledTasks.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 48,
                                  color: Colors.grey.withValues(alpha: 0.5)),
                              const SizedBox(height: 12),
                              Text(
                                isHovering ? '释放以退回收集箱' : '所有任务均已排入日程',
                                style: TextStyle(
                                  color: isHovering
                                      ? AppColors.primary
                                      : Colors.grey,
                                  fontWeight: isHovering
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: unscheduledTasks.length,
                      itemBuilder: (context, index) {
                        final task = unscheduledTasks[index];
                        return _DraggableTaskTile(
                          task: task,
                          taskLists: taskLists,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, bool isHovering) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Icon(
            isHovering ? Icons.move_to_inbox : Icons.inbox_outlined,
            size: 20,
            color: isHovering ? AppColors.primary : AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isHovering ? '释放以退回收集箱' : '收集箱 / 未排程',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isHovering ? AppColors.primary : null,
                  ),
            ),
          ),
          Tooltip(
            message: '长按任务卡片可拖拽到时间轴排程',
            child: Icon(Icons.info_outline,
                size: 16, color: Colors.grey.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

/// 可拖拽的任务卡片（LongPressDraggable of TaskItem）
class _DraggableTaskTile extends StatelessWidget {
  final TaskItem task;
  final List<TaskList> taskLists;

  const _DraggableTaskTile({required this.task, required this.taskLists});

  @override
  Widget build(BuildContext context) {
    final tileContent = _TaskTileContent(task: task, taskLists: taskLists);

    return LongPressDraggable<TaskItem>(
      data: task,
      delay: const Duration(milliseconds: 200),
      hapticFeedbackOnStart: true,
      // 拖拽时跟随手指的「幽灵」反馈（受全局状态控制，滑入时间轴即自动隐藏）
      feedback: Consumer(builder: (context, ref, _) {
        final isHoveringTimeline = ref.watch(dragHoveringTimelineProvider);
        if (isHoveringTimeline) return const SizedBox.shrink();

        return Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 260,
            child: Opacity(
              opacity: 0.9,
              child: _TaskTileContent(task: task, taskLists: taskLists),
            ),
          ),
        );
      }),
      // 原位置半透明占位
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: tileContent,
      ),
      child: tileContent,
    );
  }
}

/// 任务卡片内容（被拖拽 feedback 和原位都共用）
class _TaskTileContent extends StatelessWidget {
  final TaskItem task;
  final List<TaskList> taskLists;

  const _TaskTileContent({required this.task, required this.taskLists});

  @override
  Widget build(BuildContext context) {
    String? listEmoji;
    String? listName;
    Color? listColor;

    if (task.taskListId != null) {
      try {
        final list = taskLists.firstWhere((l) => l.id == task.taskListId);
        listEmoji = list.emoji;
        listName = list.name;
        try {
          listColor = Color(
              int.parse('FF${list.colorHex.replaceAll('#', '')}', radix: 16));
        } catch (_) {}
      } catch (_) {}
    }

    final priorityColor = _priorityColor(task.priorityLocal);
    final listDisplayName = listName;

    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (_) => Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
            child: SizedBox(
              width: 560,
              child: TaskDetailPage(taskId: task.id),
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: priorityColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.summary,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w500),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 小拖拽把手图标
                  Icon(Icons.drag_indicator,
                      size: 16, color: Colors.grey.withValues(alpha: 0.4)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (listDisplayName != null)
                    _Chip(
                        icon: listEmoji ?? '📋',
                        label: listDisplayName,
                        color: listColor ?? Colors.grey),
                  _Chip(
                      icon: '⏳',
                      label: '${task.durationMinutes}m',
                      color: Colors.grey),
                  if (task.due != null)
                    _Chip(
                      icon: '📅',
                      label: '${task.due!.month}/${task.due!.day}',
                      color: Colors.redAccent,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Color _priorityColor(int priority) {
    if (priority == 1) return const Color(0xFFE53935);
    if (priority == 3) return const Color(0xFF43A047);
    return const Color(0xFFFFA726);
  }
}

class _Chip extends StatelessWidget {
  final String icon;
  final String label;
  final Color color;

  const _Chip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 10, color: color, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}
