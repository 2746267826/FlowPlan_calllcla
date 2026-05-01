part of 'calendar_books_page.dart';

class _EventCalendarTile extends StatelessWidget {
  final EventCalendar calendar;
  final ValueChanged<bool> onToggle;
  final VoidCallback onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EventCalendarTile({
    required this.calendar,
    required this.onToggle,
    required this.onSetDefault,
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
      title: _TitleWithTags(
        title: calendar.name,
        tags: [
          if (calendar.isDefault)
            const _StateTag(
              label: '默认',
              backgroundColor: Color(0xFFEAE6FF),
              foregroundColor: AppColors.primary,
            ),
        ],
      ),
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
              if (value == 'set_default') {
                onSetDefault();
              } else if (value == 'edit') {
                onEdit();
              } else if (value == 'delete') {
                onDelete();
              }
            },
            itemBuilder: (_) => [
              if (!calendar.isDefault)
                const PopupMenuItem(
                  value: 'set_default',
                  child: Text('\u8bbe\u4e3a\u9ed8\u8ba4'),
                ),
              const PopupMenuItem(
                value: 'edit',
                child: Text('\u7f16\u8f91'),
              ),
              const PopupMenuItem(
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
                  'Outlook \u65e5\u5386\u672c\u7531\u540c\u6b65\u81ea\u52a8\u7ef4\u62a4\uff0c\u53ea\u80fd\u5728 FlowPlanV2 \u4e2d\u63a7\u5236\u663e\u793a\u6216\u9690\u85cf\u3002',
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
  final OutlookTaskListBinding? outlookBinding;
  final ValueChanged<bool> onToggle;
  final VoidCallback onSetDefault;
  final VoidCallback onEdit;
  final VoidCallback onBindOutlook;
  final VoidCallback onUnbindOutlook;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  const _TaskListTile({
    required this.taskList,
    required this.outlookBinding,
    required this.onToggle,
    required this.onSetDefault,
    required this.onEdit,
    required this.onBindOutlook,
    required this.onUnbindOutlook,
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
    final syncSubtitle = outlookBinding == null
        ? '\u672a\u7ed1\u5b9a Outlook \u4e13\u5c5e\u4efb\u52a1\u955c\u50cf\u5bb9\u5668'
        : 'Outlook \u4efb\u52a1\u955c\u50cf\uff1a${outlookBinding!.remoteCalendarName}';
    return ListTile(
      leading: Text(
        taskList.emoji?.isNotEmpty == true ? taskList.emoji! : '\u6536',
        style: const TextStyle(fontSize: 20),
      ),
      title: _TitleWithTags(
        title: taskList.name,
        tags: [
          if (taskList.isDefault)
            const _StateTag(
              label: '默认',
              backgroundColor: Color(0xFFE7F8F5),
              foregroundColor: Color(0xFF0A7C73),
            ),
        ],
      ),
      subtitle: Text(
        syncSubtitle,
        style: const TextStyle(fontSize: 12),
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
              if (value == 'set_default') {
                onSetDefault();
              } else if (value == 'edit') {
                onEdit();
              } else if (value == 'bind_outlook') {
                onBindOutlook();
              } else if (value == 'unbind_outlook') {
                onUnbindOutlook();
              } else if (value == 'archive') {
                onArchive();
              } else if (value == 'delete') {
                onDelete();
              }
            },
            itemBuilder: (_) => [
              if (!taskList.isDefault)
                const PopupMenuItem(
                  value: 'set_default',
                  child: Text('\u8bbe\u4e3a\u9ed8\u8ba4'),
                ),
              const PopupMenuItem(
                value: 'edit',
                child: Text('\u7f16\u8f91'),
              ),
              PopupMenuItem(
                value: outlookBinding == null
                    ? 'bind_outlook'
                    : 'unbind_outlook',
                child: Text(
                  outlookBinding == null
                      ? '\u7ed1\u5b9a Outlook \u4efb\u52a1\u955c\u50cf'
                      : '\u89e3\u9664 Outlook \u7ed1\u5b9a',
                ),
              ),
              const PopupMenuItem(
                value: 'archive',
                child: Text(
                  '\u5f52\u6863',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
              const PopupMenuItem(
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

class _CalendarBooksBoundaryCard extends StatelessWidget {
  const _CalendarBooksBoundaryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.account_tree_outlined,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '容器边界',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '日程必须属于日历本，任务必须属于任务本；这里集中管理容器，而不是直接编辑条目内容。',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _BoundaryChip(
                icon: Icons.edit_outlined,
                label: '普通编辑',
                description: '本地容器可修改名称、颜色、默认值',
              ),
              _BoundaryChip(
                icon: Icons.cloud_sync_outlined,
                label: '同步容器',
                description: 'Outlook 来源只维护映射和显示状态',
              ),
              _BoundaryChip(
                icon: Icons.event_busy_outlined,
                label: '本地排程策略',
                description: '默认阻挡、默认提醒等只影响 FlowPlanV2',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoundaryChip extends StatelessWidget {
  const _BoundaryChip({
    required this.icon,
    required this.label,
    required this.description,
  });

  final IconData icon;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleWithTags extends StatelessWidget {
  final String title;
  final List<Widget> tags;

  const _TitleWithTags({
    required this.title,
    required this.tags,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(title),
        ...tags,
      ],
    );
  }
}

class _StateTag extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  const _StateTag({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foregroundColor,
        ),
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
  final bool initialDefaultIsBlock;
  final Future<void> Function(
    String name,
    String color,
    bool defaultIsBlock,
  ) onSave;

  const _EditCalendarDialog({
    required this.title,
    required this.initialName,
    required this.initialColor,
    required this.initialDefaultIsBlock,
    required this.onSave,
  });

  @override
  State<_EditCalendarDialog> createState() => _EditCalendarDialogState();
}

class _EditCalendarDialogState extends State<_EditCalendarDialog> {
  late TextEditingController _nameController;
  late String _colorHex;
  late bool _defaultIsBlock;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _colorHex = widget.initialColor;
    _defaultIsBlock = widget.initialDefaultIsBlock;
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
      content: SingleChildScrollView(
        child: Column(
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
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '\u9ed8\u8ba4\u963b\u6321\u81ea\u52a8\u6392\u7a0b',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                '\u4f7f\u7528\u6b64\u65e5\u5386\u672c\u65b0\u5efa\u65e5\u7a0b\u65f6\uff0c\u9ed8\u8ba4\u628a\u65f6\u6bb5\u4f5c\u4e3a\u6392\u7a0b\u963b\u6321\u533a\u95f4\u3002',
              ),
              value: _defaultIsBlock,
              activeThumbColor: AppColors.primary,
              onChanged: (value) => setState(() => _defaultIsBlock = value),
            ),
          ],
        ),
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
                    _defaultIsBlock,
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

class _EditTaskListDialog extends StatefulWidget {
  final String title;
  final String initialName;
  final String initialColor;
  final String initialEmoji;
  final bool initialDefaultIsAutoScheduled;
  final int initialDefaultReminderMinutes;
  final Future<void> Function(
    String name,
    String color,
    String emoji,
    bool defaultIsAutoScheduled,
    int defaultReminderMinutesBefore,
  ) onSave;

  const _EditTaskListDialog({
    required this.title,
    required this.initialName,
    required this.initialColor,
    required this.initialEmoji,
    required this.initialDefaultIsAutoScheduled,
    required this.initialDefaultReminderMinutes,
    required this.onSave,
  });

  @override
  State<_EditTaskListDialog> createState() => _EditTaskListDialogState();
}

class _EditTaskListDialogState extends State<_EditTaskListDialog> {
  late TextEditingController _nameController;
  late TextEditingController _emojiController;
  late String _colorHex;
  late bool _defaultIsAutoScheduled;
  late int _defaultReminderMinutes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _emojiController = TextEditingController(text: widget.initialEmoji);
    _colorHex = widget.initialColor;
    _defaultIsAutoScheduled = widget.initialDefaultIsAutoScheduled;
    _defaultReminderMinutes = widget.initialDefaultReminderMinutes;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emojiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const reminderOptions = [
      (value: 0, label: '\u51c6\u65f6'),
      (value: 5, label: '5 \u5206\u949f'),
      (value: 15, label: '15 \u5206\u949f'),
      (value: 30, label: '30 \u5206\u949f'),
      (value: 60, label: '1 \u5c0f\u65f6'),
      (value: 1440, label: '1 \u5929'),
    ];

    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
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
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '\u9ed8\u8ba4\u5f00\u542f\u81ea\u52a8\u6392\u7a0b',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                '\u4f7f\u7528\u6b64\u4efb\u52a1\u672c\u65b0\u5efa\u4efb\u52a1\u65f6\uff0c\u9ed8\u8ba4\u5141\u8bb8\u8fdb\u5165\u81ea\u52a8\u6392\u7a0b\u3002',
              ),
              value: _defaultIsAutoScheduled,
              activeThumbColor: AppColors.primary,
              onChanged: (value) =>
                  setState(() => _defaultIsAutoScheduled = value),
            ),
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '\u9ed8\u8ba4\u63d0\u524d\u63d0\u9192',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: reminderOptions.map((option) {
                final selected = option.value == _defaultReminderMinutes;
                return ChoiceChip(
                  label: Text(option.label),
                  selected: selected,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : null,
                    fontSize: 12,
                  ),
                  onSelected: (_) =>
                      setState(() => _defaultReminderMinutes = option.value),
                );
              }).toList(),
            ),
          ],
        ),
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
                    _defaultIsAutoScheduled,
                    _defaultReminderMinutes,
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
