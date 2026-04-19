// 日历本管理页：任务清单 + 事件日历本（完全分离，可创建/编辑/删除/切换可见性）
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../core/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/providers/app_providers.dart';

class CalendarBooksPage extends ConsumerWidget {
  const CalendarBooksPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventCals = ref.watch(allEventCalendarsProvider);
    final taskLists = ref.watch(allTaskListsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('日历本管理')),
      body: ListView(
        children: [
          // ── 事件日历本 ─────────────────────────────────────────────────────
          _SectionHeader(
            title: '日历本',
            subtitle: '日程事件',
            icon: Icons.event_outlined,
            onAdd: () => _showEditEventCalendar(context, ref, null),
          ),
          eventCals.when(
            loading: () => const _LoadingTile(),
            error: (e, _) => _ErrorTile(message: e.toString()),
            data: (cals) => cals.isEmpty
                ? const _EmptyHint(message: '暂无日历本，点击 + 创建')
                : Column(
                    children: cals
                        .map((cal) => _EventCalendarTile(
                              calendar: cal,
                              onToggle: (v) => ref
                                  .read(calendarBooksRepositoryProvider)
                                  .toggleEventCalendarVisible(cal.id, v),
                              onEdit: () =>
                                  _showEditEventCalendar(context, ref, cal),
                              onDelete: () => _confirmDelete(
                                  context,
                                  '删除日历本「${cal.name}」？',
                                  () => ref
                                      .read(calendarBooksRepositoryProvider)
                                      .deleteEventCalendar(cal.id)),
                            ))
                        .toList(),
                  ),
          ),
          const Divider(height: 32),

          // ── 任务清单 ───────────────────────────────────────────────────────
          _SectionHeader(
            title: '任务清单',
            subtitle: '待办任务',
            icon: Icons.task_alt_outlined,
            onAdd: () => _showEditTaskList(context, ref, null),
          ),
          taskLists.when(
            loading: () => const _LoadingTile(),
            error: (e, _) => _ErrorTile(message: e.toString()),
            data: (lists) => lists.isEmpty
                ? const _EmptyHint(message: '暂无任务清单，点击 + 创建')
                : Column(
                    children: lists
                        .map((list) => _TaskListTile(
                              taskList: list,
                              onToggle: (v) => ref
                                  .read(calendarBooksRepositoryProvider)
                                  .toggleTaskListVisible(list.id, v),
                              onEdit: () =>
                                  _showEditTaskList(context, ref, list),
                              onDelete: () => _confirmDelete(
                                  context,
                                  '归档清单「${list.name}」？',
                                  () => ref
                                      .read(calendarBooksRepositoryProvider)
                                      .archiveTaskList(list.id)),
                            ))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showEditEventCalendar(
      BuildContext context, WidgetRef ref, EventCalendar? existing) {
    showDialog(
      context: context,
      builder: (_) => _EditCalendarDialog(
        title: existing == null ? '新建日历本' : '编辑日历本',
        initialName: existing?.name ?? '',
        initialColor: existing?.colorHex ?? '#6B5EE4',
        onSave: (name, color) async {
          final repo = ref.read(calendarBooksRepositoryProvider);
          if (existing == null) {
            await repo.createEventCalendar(EventCalendarsCompanion.insert(
              name: name,
              colorHex: Value(color),
              createdAt: DateTime.now(),
            ));
          } else {
            await repo.updateEventCalendar(EventCalendarsCompanion(
              id: Value(existing.id),
              name: Value(name),
              colorHex: Value(color),
            ));
          }
        },
      ),
    );
  }

  void _showEditTaskList(
      BuildContext context, WidgetRef ref, TaskList? existing) {
    showDialog(
      context: context,
      builder: (_) => _EditTaskListDialog(
        title: existing == null ? '新建任务清单' : '编辑清单',
        initialName: existing?.name ?? '',
        initialColor: existing?.colorHex ?? '#6B5EE4',
        initialEmoji: existing?.emoji ?? '📋',
        onSave: (name, color, emoji) async {
          final repo = ref.read(calendarBooksRepositoryProvider);
          if (existing == null) {
            await repo.createTaskList(TaskListsCompanion.insert(
              name: name,
              colorHex: Value(color),
              emoji: Value(emoji),
              createdAt: DateTime.now(),
            ));
          } else {
            await repo.updateTaskList(TaskListsCompanion(
              id: Value(existing.id),
              name: Value(name),
              colorHex: Value(color),
              emoji: Value(emoji),
            ));
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, String message, VoidCallback onConfirm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认操作'),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) onConfirm();
  }
}

// ── 事件日历本列表项 ────────────────────────────────────────────────────────────
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
      subtitle: Text(calendar.source == 'local' ? '本地' : calendar.source,
          style: const TextStyle(fontSize: 12)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: calendar.isVisible,
            onChanged: onToggle,
            activeThumbColor: AppColors.primary,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'delete') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑')),
              const PopupMenuItem(
                  value: 'delete',
                  child: Text('删除', style: TextStyle(color: Colors.red))),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 任务清单列表项 ──────────────────────────────────────────────────────────────
class _TaskListTile extends StatelessWidget {
  final TaskList taskList;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _TaskListTile({
    required this.taskList,
    required this.onToggle,
    required this.onEdit,
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
      leading:
          Text(taskList.emoji ?? '📋', style: const TextStyle(fontSize: 20)),
      title: Text(taskList.name),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: _color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Switch(
            value: taskList.isVisible,
            onChanged: onToggle,
            activeThumbColor: AppColors.primary,
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'archive') onDelete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑')),
              const PopupMenuItem(
                  value: 'archive',
                  child: Text('归档', style: TextStyle(color: Colors.orange))),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 辅助 Widgets ────────────────────────────────────────────────────────────────

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
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: IconButton(
        icon: const Icon(Icons.add_circle_outline, color: AppColors.primary),
        onPressed: onAdd,
        tooltip: '新建',
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();
  @override
  Widget build(BuildContext context) => const Center(
          child: Padding(
        padding: EdgeInsets.all(16),
        child: CircularProgressIndicator(),
      ));
}

class _ErrorTile extends StatelessWidget {
  final String message;
  const _ErrorTile({required this.message});
  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.error_outline, color: Colors.red),
        title: const Text('加载失败'),
        subtitle: Text(message, maxLines: 2),
      );
}

class _EmptyHint extends StatelessWidget {
  final String message;
  const _EmptyHint({required this.message});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Text(message,
          style: const TextStyle(color: Colors.grey, fontSize: 13)));
}

// ── 编辑日历本对话框 ────────────────────────────────────────────────────────────
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
  late TextEditingController _nameCtrl;
  late String _colorHex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _colorHex = widget.initialColor;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
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
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          const SizedBox(height: 16),
          const Align(
              alignment: Alignment.centerLeft,
              child: Text('颜色',
                  style: TextStyle(fontSize: 12, color: Colors.grey))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: AppColors.taskPalette.map((color) {
              final hex =
                  '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
              final sel = hex == _colorHex.toUpperCase();
              return GestureDetector(
                onTap: () => setState(() => _colorHex = hex),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: sel
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 2)
                          : null),
                  child: sel
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
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  if (_nameCtrl.text.trim().isEmpty) return;
                  setState(() => _saving = true);
                  await widget.onSave(_nameCtrl.text.trim(), _colorHex);
                  if (!mounted) return;
                  navigator.pop();
                },
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('保存'),
        ),
      ],
    );
  }
}

// ── 编辑任务清单对话框 ──────────────────────────────────────────────────────────
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
  late TextEditingController _nameCtrl;
  late TextEditingController _emojiCtrl;
  late String _colorHex;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _emojiCtrl = TextEditingController(text: widget.initialEmoji);
    _colorHex = widget.initialColor;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emojiCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            SizedBox(
              width: 64,
              child: TextField(
                controller: _emojiCtrl,
                decoration: const InputDecoration(labelText: 'Emoji'),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(labelText: '名称'),
            )),
          ]),
          const SizedBox(height: 16),
          const Align(
              alignment: Alignment.centerLeft,
              child: Text('颜色',
                  style: TextStyle(fontSize: 12, color: Colors.grey))),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: AppColors.taskPalette.map((color) {
              final hex =
                  '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
              final sel = hex == _colorHex.toUpperCase();
              return GestureDetector(
                onTap: () => setState(() => _colorHex = hex),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: sel
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 2)
                          : null),
                  child: sel
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
            onPressed: () => Navigator.pop(context), child: const Text('取消')),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  if (_nameCtrl.text.trim().isEmpty) return;
                  setState(() => _saving = true);
                  await widget.onSave(
                      _nameCtrl.text.trim(), _colorHex, _emojiCtrl.text.trim());
                  if (!mounted) return;
                  navigator.pop();
                },
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('保存'),
        ),
      ],
    );
  }
}
