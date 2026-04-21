import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';
import 'task_detail_page.dart';

class UnscheduledTaskPanel extends ConsumerWidget {
  const UnscheduledTaskPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasksAsync = ref.watch(allTasksProvider);
    final taskListsAsync = ref.watch(allTaskListsProvider);
    final taskLists = taskListsAsync.maybeWhen(
      data: (value) => value,
      orElse: () => const <TaskList>[],
    );

    return DragTarget<TaskItem>(
      onWillAcceptWithDetails: (details) => details.data.dtstart != null,
      onAcceptWithDetails: (details) async {
        await ref.read(taskRepositoryProvider).clearDtstart(details.data.id);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '\u4efb\u52a1\u300c${details.data.summary}\u300d\u5df2\u9000\u56de\u6536\u96c6\u7bb1',
            ),
          ),
        );
      },
      builder: (context, candidateData, rejectedData) {
        final hovering = candidateData.isNotEmpty;
        return Container(
          width: 320,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: hovering
                ? Border.all(color: AppColors.primary, width: 2)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PanelHeader(hovering: hovering),
              const Divider(height: 1),
              Expanded(
                child: tasksAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (error, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('\u52a0\u8f7d\u5931\u8d25\uff1a$error'),
                    ),
                  ),
                  data: (tasks) {
                    final unscheduled = tasks.where((task) => task.dtstart == null).toList();
                    if (unscheduled.isEmpty) {
                      return _EmptyState(hovering: hovering);
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: unscheduled.length,
                      itemBuilder: (context, index) {
                        return _DraggableTaskTile(
                          task: unscheduled[index],
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
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.hovering});

  final bool hovering;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            hovering ? Icons.move_to_inbox : Icons.inbox_outlined,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              hovering
                  ? '\u91ca\u653e\u4ee5\u9000\u56de\u6536\u96c6\u7bb1'
                  : '\u6536\u96c6\u7bb1 / \u672a\u6392\u7a0b',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: hovering ? AppColors.primary : null,
                  ),
            ),
          ),
          Tooltip(
            message: '\u957f\u6309\u4efb\u52a1\u5361\u7247\u53ef\u62d6\u62fd\u5230\u65f6\u95f4\u8f74\u6392\u7a0b',
            child: Icon(
              Icons.info_outline,
              size: 16,
              color: Colors.grey.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hovering});

  final bool hovering;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: Colors.grey.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 12),
            Text(
              hovering
                  ? '\u91ca\u653e\u4ee5\u9000\u56de\u6536\u96c6\u7bb1'
                  : '\u6240\u6709\u4efb\u52a1\u5747\u5df2\u6392\u5165\u65e5\u7a0b',
              style: TextStyle(
                color: hovering ? AppColors.primary : Colors.grey,
                fontWeight: hovering ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraggableTaskTile extends StatelessWidget {
  const _DraggableTaskTile({
    required this.task,
    required this.taskLists,
  });

  final TaskItem task;
  final List<TaskList> taskLists;

  @override
  Widget build(BuildContext context) {
    final content = _TaskTileContent(task: task, taskLists: taskLists);
    return LongPressDraggable<TaskItem>(
      data: task,
      delay: const Duration(milliseconds: 200),
      hapticFeedbackOnStart: true,
      feedback: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(width: 260, child: Opacity(opacity: 0.92, child: content)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: content),
      child: content,
    );
  }
}

class _TaskTileContent extends StatelessWidget {
  const _TaskTileContent({
    required this.task,
    required this.taskLists,
  });

  final TaskItem task;
  final List<TaskList> taskLists;

  @override
  Widget build(BuildContext context) {
    TaskList? taskList;
    for (final item in taskLists) {
      if (item.id == task.taskListId) {
        taskList = item;
        break;
      }
    }

    Color? listColor;
    if (taskList != null) {
      try {
        listColor = Color(int.parse('FF${taskList.colorHex.replaceAll('#', '')}', radix: 16));
      } catch (_) {
        listColor = Colors.grey;
      }
    }

    return InkWell(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (_) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
            child: SizedBox(width: 560, child: TaskDetailPage(taskId: task.id)),
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
            border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
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
                      color: _priorityColor(task.priorityLocal),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.summary,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                  Icon(Icons.drag_indicator, size: 16, color: Colors.grey.withValues(alpha: 0.4)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (taskList != null)
                    _MetaChip(
                      icon: Icons.folder_open_outlined,
                      label: '${taskList.emoji == null ? '' : '${taskList.emoji!} '}${taskList.name}',
                      color: listColor ?? Colors.grey,
                    ),
                  _MetaChip(
                    icon: Icons.schedule_outlined,
                    label: '${task.durationMinutes} \u5206\u949f',
                    color: Colors.grey,
                  ),
                  if (task.due != null)
                    _MetaChip(
                      icon: Icons.event_busy_outlined,
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

  Color _priorityColor(int priority) {
    if (priority == 1) return const Color(0xFFE53935);
    if (priority == 3) return const Color(0xFF43A047);
    return const Color(0xFFFFA726);
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

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
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
