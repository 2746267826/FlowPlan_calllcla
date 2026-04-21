import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/app_providers.dart';

class CalendarBooksPage extends ConsumerWidget {
  const CalendarBooksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventCalendars = ref.watch(allEventCalendarsProvider);
    final taskLists = ref.watch(allTaskListsProvider);
    final archivedTaskLists = ref.watch(archivedTaskListsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u65e5\u5386\u672c\u7ba1\u7406'),
      ),
      body: ListView(
        children: [
          _SectionHeader(
            title: '\u65e5\u5386\u672c',
            subtitle: '\u65e5\u7a0b\u5bb9\u5668',
            icon: Icons.event_outlined,
            onAdd: () => _showEditEventCalendar(context, ref, null),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Outlook \u65e5\u5386\u4f1a\u5728\u540c\u6b65\u540e\u81ea\u52a8\u51fa\u73b0\uff0c\u5e76\u4ee5\u53ea\u8bfb\u65b9\u5f0f\u63a5\u5165\u3002\u4f60\u4ecd\u7136\u53ef\u4ee5\u63a7\u5236\u5b83\u4eec\u5728 FlowPlan \u4e2d\u662f\u5426\u663e\u793a\u3002',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          eventCalendars.when(
            loading: () => const _LoadingTile(),
            error: (error, _) => _ErrorTile(message: error.toString()),
            data: (items) {
              if (items.isEmpty) {
                return const _EmptyHint(
                  message: '\u6682\u65e0\u65e5\u5386\u672c\uff0c\u70b9\u51fb\u53f3\u4e0a\u89d2\u521b\u5efa',
                );
              }
              return Column(
                children: items.map((calendar) {
                  if (calendar.source == 'outlook') {
                    return _ReadOnlyEventCalendarTile(
                      calendar: calendar,
                      onToggle: (value) => ref
                          .read(calendarBooksRepositoryProvider)
                          .toggleEventCalendarVisible(calendar.id, value),
                    );
                  }
                  return _EventCalendarTile(
                    calendar: calendar,
                    onToggle: (value) => ref
                        .read(calendarBooksRepositoryProvider)
                        .toggleEventCalendarVisible(calendar.id, value),
                    onEdit: () => _showEditEventCalendar(context, ref, calendar),
                    onDelete: () => _runConfirmedAction(
                      context,
                      title: '\u5220\u9664\u65e5\u5386\u672c',
                      message:
                          '\u5220\u9664\u65e5\u5386\u672c\u201c${calendar.name}\u201d\u540e\uff0c\u5176\u4e2d\u672c\u5730\u65e5\u7a0b\u4f1a\u81ea\u52a8\u8fc1\u79fb\u5230\u5176\u4ed6\u53ef\u7528\u672c\u5730\u65e5\u5386\u672c\u3002',
                      successMessage:
                          '\u65e5\u5386\u672c\u300c${calendar.name}\u300d\u5df2\u5220\u9664\uff0c\u672c\u5730\u65e5\u7a0b\u5df2\u8fc1\u79fb',
                      onConfirm: () => ref
                          .read(calendarBooksRepositoryProvider)
                          .deleteEventCalendar(calendar.id),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          const Divider(height: 32),
          _SectionHeader(
            title: '\u4efb\u52a1\u672c',
            subtitle: '\u4efb\u52a1\u5bb9\u5668',
            icon: Icons.task_alt_outlined,
            onAdd: () => _showEditTaskList(context, ref, null),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '\u5f52\u6863\u4efb\u52a1\u672c\u65f6\uff0c\u5176\u4e2d\u4efb\u52a1\u4f1a\u81ea\u52a8\u8fc1\u79fb\u5230\u5176\u4ed6\u53ef\u7528\u4efb\u52a1\u672c\u3002\u5df2\u5f52\u6863\u7684\u4efb\u52a1\u672c\u53ef\u4ee5\u5728\u4e0b\u65b9\u6062\u590d\u6216\u5f7b\u5e95\u5220\u9664\u3002',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          taskLists.when(
            loading: () => const _LoadingTile(),
            error: (error, _) => _ErrorTile(message: error.toString()),
            data: (items) {
              if (items.isEmpty) {
                return const _EmptyHint(
                  message: '\u6682\u65e0\u4efb\u52a1\u672c\uff0c\u70b9\u51fb\u53f3\u4e0a\u89d2\u521b\u5efa',
                );
              }
              return Column(
                children: items.map((taskList) {
                  return _TaskListTile(
                    taskList: taskList,
                    onToggle: (value) => ref
                        .read(calendarBooksRepositoryProvider)
                        .toggleTaskListVisible(taskList.id, value),
                    onEdit: () => _showEditTaskList(context, ref, taskList),
                    onArchive: () => _runConfirmedAction(
                      context,
                      title: '\u5f52\u6863\u4efb\u52a1\u672c',
                      message:
                          '\u5f52\u6863\u4efb\u52a1\u672c\u201c${taskList.name}\u201d\u540e\uff0c\u5176\u4e2d\u4efb\u52a1\u4f1a\u81ea\u52a8\u8fc1\u79fb\u5230\u5176\u4ed6\u53ef\u7528\u4efb\u52a1\u672c\u3002',
                      successMessage:
                          '\u4efb\u52a1\u672c\u300c${taskList.name}\u300d\u5df2\u5f52\u6863',
                      onConfirm: () => ref
                          .read(calendarBooksRepositoryProvider)
                          .archiveTaskList(taskList.id),
                    ),
                    onDelete: () => _runConfirmedAction(
                      context,
                      title: '\u5220\u9664\u4efb\u52a1\u672c',
                      message:
                          '\u5220\u9664\u4efb\u52a1\u672c\u201c${taskList.name}\u201d\u540e\uff0c\u5176\u4e2d\u4efb\u52a1\u4f1a\u81ea\u52a8\u8fc1\u79fb\u5230\u5176\u4ed6\u53ef\u7528\u4efb\u52a1\u672c\u3002',
                      successMessage:
                          '\u4efb\u52a1\u672c\u300c${taskList.name}\u300d\u5df2\u5220\u9664\uff0c\u4efb\u52a1\u5df2\u8fc1\u79fb',
                      onConfirm: () => ref
                          .read(calendarBooksRepositoryProvider)
                          .deleteTaskList(taskList.id),
                    ),
                  );
                }).toList(),
              );
            },
          ),
          archivedTaskLists.when(
            loading: () => const SizedBox.shrink(),
            error: (error, _) => _ErrorTile(message: error.toString()),
            data: (items) {
              if (items.isEmpty) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      '\u5df2\u5f52\u6863\u4efb\u52a1\u672c',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ...items.map(
                    (taskList) => _ArchivedTaskListTile(
                      taskList: taskList,
                      onRestore: () => _runConfirmedAction(
                        context,
                        title: '\u6062\u590d\u4efb\u52a1\u672c',
                        message:
                            '\u786e\u5b9a\u8981\u6062\u590d\u4efb\u52a1\u672c\u201c${taskList.name}\u201d\u5417\uff1f',
                        successMessage:
                            '\u4efb\u52a1\u672c\u300c${taskList.name}\u300d\u5df2\u6062\u590d',
                        onConfirm: () => ref
                            .read(calendarBooksRepositoryProvider)
                            .unarchiveTaskList(taskList.id),
                      ),
                      onDelete: () => _runConfirmedAction(
                        context,
                        title: '\u5f7b\u5e95\u5220\u9664\u4efb\u52a1\u672c',
                        message:
                            '\u786e\u5b9a\u8981\u5f7b\u5e95\u5220\u9664\u5df2\u5f52\u6863\u4efb\u52a1\u672c\u201c${taskList.name}\u201d\u5417\uff1f',
                        successMessage:
                            '\u5df2\u5f52\u6863\u4efb\u52a1\u672c\u300c${taskList.name}\u300d\u5df2\u5220\u9664',
                        onConfirm: () => ref
                            .read(calendarBooksRepositoryProvider)
                            .deleteTaskList(taskList.id),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showEditEventCalendar(
    BuildContext context,
    WidgetRef ref,
    EventCalendar? existing,
  ) {
    if (existing?.source == 'outlook') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Outlook \u65e5\u5386\u672c\u7531\u540c\u6b65\u81ea\u52a8\u7ef4\u62a4\uff0c\u4e0d\u80fd\u5728 FlowPlan \u4e2d\u76f4\u63a5\u7f16\u8f91\u3002',
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => _EditCalendarDialog(
        title: existing == null
            ? '\u65b0\u5efa\u65e5\u5386\u672c'
            : '\u7f16\u8f91\u65e5\u5386\u672c',
        initialName: existing?.name ?? '',
        initialColor: existing?.colorHex ?? '#6B5EE4',
        onSave: (name, color) async {
          final repo = ref.read(calendarBooksRepositoryProvider);
          if (existing == null) {
            await repo.createEventCalendar(
              EventCalendarsCompanion.insert(
                name: name,
                colorHex: Value(color),
                createdAt: DateTime.now(),
              ),
            );
          } else {
            await repo.updateEventCalendar(
              EventCalendarsCompanion(
                id: Value(existing.id),
                name: Value(name),
                colorHex: Value(color),
              ),
            );
          }
        },
      ),
    );
  }

  void _showEditTaskList(
    BuildContext context,
    WidgetRef ref,
    TaskList? existing,
  ) {
    showDialog(
      context: context,
      builder: (_) => _EditTaskListDialog(
        title: existing == null
            ? '\u65b0\u5efa\u4efb\u52a1\u672c'
            : '\u7f16\u8f91\u4efb\u52a1\u672c',
        initialName: existing?.name ?? '',
        initialColor: existing?.colorHex ?? '#6B5EE4',
        initialEmoji:
            existing?.emoji?.isNotEmpty == true ? existing!.emoji! : '\u6536',
        onSave: (name, color, emoji) async {
          final repo = ref.read(calendarBooksRepositoryProvider);
          final finalEmoji = emoji.trim().isEmpty ? '\u6536' : emoji.trim();
          if (existing == null) {
            await repo.createTaskList(
              TaskListsCompanion.insert(
                name: name,
                colorHex: Value(color),
                emoji: Value(finalEmoji),
                createdAt: DateTime.now(),
              ),
            );
          } else {
            await repo.updateTaskList(
              TaskListsCompanion(
                id: Value(existing.id),
                name: Value(name),
                colorHex: Value(color),
                emoji: Value(finalEmoji),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _runConfirmedAction(
    BuildContext context, {
    required String title,
    required String message,
    required String successMessage,
    required Future<dynamic> Function() onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('\u53d6\u6d88'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              '\u786e\u8ba4',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await onConfirm();
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('\u64cd\u4f5c\u5931\u8d25\uff1a$error'),
          ),
        );
      }
    }
  }
}

class _EventCalendarTile extends StatelessWidget {
  final EventCalendar calendar;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EventCalendarTile({
    required this.calendar,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  Color get _color {
    try {
      final hex = calendar.colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
      ),
      title: Text(calendar.name),
      subtitle: const Text(
        '\u672c\u5730',
        style: TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: calendar.isVisible,
            onChanged: onToggle,
            activeThumbColor: AppColors.primary,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                onEdit();
              } else if (value == 'delete') {
                onDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: Text('\u7f16\u8f91'),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  '\u5220\u9664',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyEventCalendarTile extends StatelessWidget {
  final EventCalendar calendar;
  final ValueChanged<bool> onToggle;

  const _ReadOnlyEventCalendarTile({
    required this.calendar,
    required this.onToggle,
  });

  Color get _color {
    try {
      final hex = calendar.colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
      ),
      title: Text(calendar.name),
      subtitle: const Text(
        'Outlook\uff08\u53ea\u8bfb\uff09',
        style: TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: calendar.isVisible,
            onChanged: onToggle,
            activeThumbColor: AppColors.primary,
          ),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Tooltip(
              message:
                  'Outlook \u65e5\u5386\u672c\u7531\u540c\u6b65\u81ea\u52a8\u7ef4\u62a4\uff0c\u53ea\u80fd\u5728 FlowPlan \u4e2d\u63a7\u5236\u663e\u793a\u6216\u9690\u85cf\u3002',
              child: Icon(
                Icons.lock_outline,
                size: 20,
                color: Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskListTile extends StatelessWidget {
  final TaskList taskList;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  const _TaskListTile({
    required this.taskList,
    required this.onToggle,
    required this.onEdit,
    required this.onArchive,
    required this.onDelete,
  });

  Color get _color {
    try {
      final hex = taskList.colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Text(
        taskList.emoji?.isNotEmpty == true ? taskList.emoji! : '\u6536',
        style: const TextStyle(fontSize: 20),
      ),
      title: Text(taskList.name),
      subtitle: const Text(
        '\u6d3b\u8dc3',
        style: TextStyle(fontSize: 12),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Switch(
            value: taskList.isVisible,
            onChanged: onToggle,
            activeThumbColor: AppColors.primary,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                onEdit();
              } else if (value == 'archive') {
                onArchive();
              } else if (value == 'delete') {
                onDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: Text('\u7f16\u8f91'),
              ),
              PopupMenuItem(
                value: 'archive',
                child: Text(
                  '\u5f52\u6863',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  '\u5220\u9664',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ArchivedTaskListTile extends StatelessWidget {
  final TaskList taskList;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  const _ArchivedTaskListTile({
    required this.taskList,
    required this.onRestore,
    required this.onDelete,
  });

  Color get _color {
    try {
      final hex = taskList.colorHex.replaceAll('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Text(
        taskList.emoji?.isNotEmpty == true ? taskList.emoji! : '\u6536',
        style: const TextStyle(fontSize: 20),
      ),
      title: Text(taskList.name),
      subtitle: const Text(
        '\u5df2\u5f52\u6863',
        style: TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: onRestore,
            child: const Text('\u6062\u590d'),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'restore') {
                onRestore();
              } else if (value == 'delete') {
                onDelete();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'restore',
                child: Text('\u6062\u590d'),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  '\u5f7b\u5e95\u5220\u9664',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onAdd;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.grey),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
        onPressed: onAdd,
        tooltip: '\u65b0\u5efa',
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  final String message;

  const _ErrorTile({required this.message});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.error_outline, color: Colors.red),
      title: const Text('\u52a0\u8f7d\u5931\u8d25'),
      subtitle: Text(message, maxLines: 2),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String message;

  const _EmptyHint({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Text(
        message,
        style: const TextStyle(color: Colors.grey, fontSize: 13),
      ),
    );
  }
}

class _EditCalendarDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String initialColor;
  final Future<void> Function(String name, String color) onSave;

  const _EditCalendarDialog({
    required this.title,
    required this.initialName,
    required this.initialColor,
    required this.onSave,
  });

  @override
  State<_EditCalendarDialog> createState() => _EditCalendarDialogState();
}

class _EditCalendarDialogState extends State<_EditCalendarDialog> {
  late TextEditingController _nameController;
  late String _colorHex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _colorHex = widget.initialColor;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '\u540d\u79f0',
            ),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '\u989c\u8272',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: AppColors.taskPalette.map((color) {
              final hex =
                  '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
              final selected = hex == _colorHex.toUpperCase();
              return GestureDetector(
                onTap: () => setState(() => _colorHex = hex),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(
                            color: Theme.of(context).colorScheme.onSurface,
                            width: 2,
                          )
                        : null,
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('\u53d6\u6d88'),
        ),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () async {
                  if (_nameController.text.trim().isEmpty) {
                    return;
                  }
                  final navigator = Navigator.of(context);
                  setState(() => _saving = true);
                  await widget.onSave(_nameController.text.trim(), _colorHex);
                  if (!mounted) {
                    return;
                  }
                  navigator.pop();
                },
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('\u4fdd\u5b58'),
        ),
      ],
    );
  }
}

class _EditTaskListDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String initialColor;
  final String initialEmoji;
  final Future<void> Function(String name, String color, String emoji) onSave;

  const _EditTaskListDialog({
    required this.title,
    required this.initialName,
    required this.initialColor,
    required this.initialEmoji,
    required this.onSave,
  });

  @override
  State<_EditTaskListDialog> createState() => _EditTaskListDialogState();
}

class _EditTaskListDialogState extends State<_EditTaskListDialog> {
  late TextEditingController _nameController;
  late TextEditingController _emojiController;
  late String _colorHex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _emojiController = TextEditingController(text: widget.initialEmoji);
    _colorHex = widget.initialColor;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _emojiController,
                  decoration: const InputDecoration(
                    labelText: '\u56fe\u6807',
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '\u540d\u79f0',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '\u989c\u8272',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: AppColors.taskPalette.map((color) {
              final hex =
                  '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
              final selected = hex == _colorHex.toUpperCase();
              return GestureDetector(
                onTap: () => setState(() => _colorHex = hex),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: selected
                        ? Border.all(
                            color: Theme.of(context).colorScheme.onSurface,
                            width: 2,
                          )
                        : null,
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('\u53d6\u6d88'),
        ),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () async {
                  if (_nameController.text.trim().isEmpty) {
                    return;
                  }
                  final navigator = Navigator.of(context);
                  setState(() => _saving = true);
                  await widget.onSave(
                    _nameController.text.trim(),
                    _colorHex,
                    _emojiController.text.trim(),
                  );
                  if (!mounted) {
                    return;
                  }
                  navigator.pop();
                },
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('\u4fdd\u5b58'),
        ),
      ],
    );
  }
}
