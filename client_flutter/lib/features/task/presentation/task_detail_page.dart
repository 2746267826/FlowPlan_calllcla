import 'package:flowplanv2/core/server_first/server_first_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/router/app_router.dart';
import '../../../core/sync/sync_object_registry.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_keys.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/settings_provider.dart';
import '../../files/data/file_context_repository.dart';
import '../../files/presentation/file_context_panel.dart';
import '../../sync/sync_status_badge.dart';
import 'widgets/task_tracker_evidence_section.dart';

class TaskDetailPage extends ConsumerStatefulWidget {
  final int? taskId;

  const TaskDetailPage({super.key, required this.taskId});

  @override
  ConsumerState<TaskDetailPage> createState() => _TaskDetailPageState();
}

class _TaskDetailPageState extends ConsumerState<TaskDetailPage> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();

  int _durationMinutes = 60;
  int _priorityLocal = 2;
  bool _isSplittable = false;
  bool _isAutoScheduled = true;
  bool _isLocked = false;
  DateTime? _due;
  String? _rrule;
  int? _taskListId;
  int _reminderMinutes = 15;
  bool _saving = false;
  bool _hasUserEditedAutoScheduled = false;
  bool _hasUserEditedReminder = false;
  int _taskListDefaultsRequestVersion = 0;

  @override
  void initState() {
    super.initState();
    if (widget.taskId != null) {
      _loadExistingTask();
    }
  }

  Future<void> _loadExistingTask() async {
    final repo = ref.read(taskRepositoryProvider);
    final task = await repo.getById(widget.taskId!);
    if (task == null || !mounted) {
      return;
    }

    setState(() {
      _titleController.text = task.summary;
      _descController.text = task.description ?? '';
      _locationController.text = task.location ?? '';
      _durationMinutes = task.durationMinutes;
      _priorityLocal = task.priorityLocal;
      _isSplittable = task.isSplittable;
      _isAutoScheduled = task.isAutoScheduled;
      _isLocked = task.isLocked;
      _due = task.due;
      _rrule = task.rrule;
      _taskListId = task.taskListId;
      _reminderMinutes = task.reminderMinutesBefore;
    });
  }

  Future<void> _handleTaskListSelection(
    int? taskListId, {
    bool forceApplyDefaults = false,
  }) async {
    if (!mounted) {
      return;
    }

    setState(() => _taskListId = taskListId);
    if (widget.taskId != null || taskListId == null) {
      return;
    }

    final fallbackReminderMinutes = ref.read(reminderMinutesProvider);
    final requestVersion = ++_taskListDefaultsRequestVersion;
    final defaults =
        await ref.read(calendarBooksRepositoryProvider).getTaskListDefaults(
              taskListId,
              fallbackReminderMinutes: fallbackReminderMinutes,
            );
    if (!mounted ||
        widget.taskId != null ||
        requestVersion != _taskListDefaultsRequestVersion ||
        _taskListId != taskListId) {
      return;
    }

    setState(() {
      if (forceApplyDefaults || !_hasUserEditedAutoScheduled) {
        _isAutoScheduled = defaults.defaultIsAutoScheduled;
      }
      if (forceApplyDefaults || !_hasUserEditedReminder) {
        _reminderMinutes = defaults.defaultReminderMinutesBefore;
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = widget.taskId == null;
    final taskListsAsync = ref.watch(allTaskListsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isCreating ? '\u65b0\u5efa\u4efb\u52a1' : '\u7f16\u8f91\u4efb\u52a1',
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _close(context),
        ),
        actions: [
          if (!isCreating)
            IconButton(
              onPressed: _saving ? null : _delete,
              tooltip: '\u5220\u9664\u4efb\u52a1',
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton.icon(
            key: AppKeys.taskSaveButton,
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check, size: 18),
            label: const Text('\u4fdd\u5b58'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isCreating) ...[
              SyncStatusBadge(
                objectType: SyncObjectType.taskItem.key,
                localId: widget.taskId!.toString(),
              ),
              const SizedBox(height: 16),
            ],
            const _SectionLabel('\u4efb\u52a1\u672c'),
            taskListsAsync.when(
              loading: () => const SizedBox(
                height: 40,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text(
                '\u52a0\u8f7d\u5931\u8d25\uff1a$error',
              ),
              data: (lists) {
                if (lists.isEmpty) {
                  return const _WarningNotice(
                    message:
                        '\u5f53\u524d\u6ca1\u6709\u53ef\u7528\u7684\u4efb\u52a1\u672c\u3002\u8bf7\u5148\u5728\u201c\u65e5\u5386\u672c\u201d\u4e2d\u521b\u5efa\u4e00\u4e2a\u4efb\u52a1\u672c\uff0c\u518d\u521b\u5efa\u4efb\u52a1\u3002',
                  );
                }
                if (isCreating && _taskListId == null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      _handleTaskListSelection(
                        lists.first.id,
                        forceApplyDefaults: true,
                      );
                    }
                  });
                }
                return _TaskListSelector(
                  lists: lists,
                  selectedId: _taskListId,
                  onChanged: (id) => _handleTaskListSelection(id),
                );
              },
            ),
            const SizedBox(height: 20),
            TextField(
              key: AppKeys.taskSummaryField,
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '\u6807\u9898',
                hintText: '\u4efb\u52a1\u6807\u9898',
              ),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                labelText: '\u63cf\u8ff0',
                hintText: '\u6dfb\u52a0\u63cf\u8ff0\uff08\u53ef\u9009\uff09',
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: '地点',
                hintText: '添加地点（可选）',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 24),
            const _SectionLabel('\u9884\u8ba1\u65f6\u957f'),
            _DurationPicker(
              value: _durationMinutes,
              onChanged: (value) => setState(() => _durationMinutes = value),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('\u622a\u6b62\u65f6\u95f4'),
            _DateTimeTile(
              dateTime: _due,
              label: '\u8bbe\u7f6e\u622a\u6b62\u65f6\u95f4',
              onTap: _pickDeadline,
              onClear: _due == null ? null : () => setState(() => _due = null),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('\u4f18\u5148\u7ea7'),
            _PrioritySelector(
              value: _priorityLocal,
              onChanged: (value) => setState(() => _priorityLocal = value),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('\u91cd\u590d'),
            _RepeatSelector(
              rrule: _rrule,
              onChanged: (value) => setState(() => _rrule = value),
            ),
            const SizedBox(height: 20),
            const _SectionLabel('\u63d0\u524d\u63d0\u9192'),
            _ReminderSelector(
              value: _reminderMinutes,
              onChanged: (value) => setState(() {
                _reminderMinutes = value;
                _hasUserEditedReminder = true;
              }),
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              title: const Text(
                '\u81ea\u52a8\u6392\u7a0b',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                '\u7531\u6392\u7a0b\u5f15\u64ce\u81ea\u52a8\u5b89\u6392\u65f6\u95f4',
              ),
              value: _isAutoScheduled,
              onChanged: (value) => setState(() {
                _isAutoScheduled = value;
                _hasUserEditedAutoScheduled = true;
              }),
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text(
                '\u5141\u8bb8\u62c6\u5206',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                '\u53ef\u88ab\u62c6\u6210\u591a\u6bb5\u5206\u5e03\u5728\u4e0d\u540c\u65f6\u95f4',
              ),
              value: _isSplittable,
              onChanged: (value) => setState(() => _isSplittable = value),
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text(
                '\u9501\u5b9a\u6392\u7a0b',
                style: TextStyle(fontSize: 14),
              ),
              subtitle: const Text(
                '\u9501\u5b9a\u540e\u4e00\u952e\u91cd\u6392\u4e0d\u4f1a\u79fb\u52a8\u8fd9\u4e2a\u4efb\u52a1',
              ),
              value: _isLocked,
              onChanged: (value) => setState(() => _isLocked = value),
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
            if (!isCreating) ...[
              const SizedBox(height: 28),
              EntityFileContextPanel(
                entityType: FileContextEntityType.task,
                entityId: widget.taskId!.toString(),
                title: _titleController.text,
                description: _descController.text,
              ),
              const SizedBox(height: 28),
              TaskTrackerEvidenceSection(taskId: widget.taskId!),
            ],
          ],
        ),
      ),
    );
  }

  void _close(BuildContext context) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      context.pop();
      return;
    }

    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    context.go(AppRoutes.timeline);
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _due ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) {
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime:
          _due == null ? TimeOfDay.now() : TimeOfDay.fromDateTime(_due!),
    );
    if (time == null || !mounted) {
      return;
    }

    setState(() {
      _due = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('\u8bf7\u8f93\u5165\u4efb\u52a1\u6807\u9898'),
        ),
      );
      return;
    }
    if (_taskListId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u4efb\u52a1\u5fc5\u987b\u5f52\u5c5e\u4e8e\u4e00\u4e2a\u4efb\u52a1\u672c\uff0c\u8bf7\u5148\u9009\u62e9\u4efb\u52a1\u672c\u3002',
          ),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    final title = _titleController.text.trim();
    final description = _descController.text.trim();
    final location = _locationController.text.trim();
    final payload = <String, Object?>{
      'uid': widget.taskId == null ? const Uuid().v4() : null,
      'summary': title,
      'title': title,
      'description': description.isEmpty ? null : description,
      'location': location.isEmpty ? null : location,
      'dueAt': _due?.toIso8601String(),
      'priorityLocal': _priorityLocal,
      'durationMinutes': _durationMinutes,
      'isSplittable': _isSplittable,
      'isAutoScheduled': _isAutoScheduled,
      'isLocked': _isLocked,
      'taskListId': _taskListId,
      'rrule': _rrule,
      'reminderMinutesBefore': _reminderMinutes,
    };

    try {
      final store = await ref.read(taskEventServerFirstStoreProvider.future);
      late final ServerFirstWriteResult result;
      if (widget.taskId == null) {
        result = await store.createTask(payload);
      } else {
        result = await store.updateLocalTask(
          localId: widget.taskId!,
          patch: payload,
          changedFields: payload.keys.toList(growable: false),
        );
      }

      if (!mounted) {
        return;
      }

      if (_due != null) {
        ref.read(selectedDateProvider.notifier).setDate(_due!);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isPending
                ? '\u4efb\u52a1\u300c$title\u300d\u5df2\u4fdd\u5b58\u5230\u672c\u673a\uff0c\u7b49\u5f85\u540c\u6b65'
                : '\u4efb\u52a1\u300c$title\u300d\u5df2\u540c\u6b65\u4fdd\u5b58',
          ),
        ),
      );
      _close(context);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\u4fdd\u5b58\u5931\u8d25\uff1a$error'),
        ),
      );
    }
  }

  Future<void> _delete() async {
    if (widget.taskId == null || _saving) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('\u5220\u9664\u4efb\u52a1'),
        content: Text(
          '\u786e\u5b9a\u8981\u5220\u9664\u4efb\u52a1\u300c${_titleController.text.trim().isEmpty ? '\u672a\u547d\u540d\u4efb\u52a1' : _titleController.text.trim()}\u300d\u5417\uff1f',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('\u53d6\u6d88'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              '\u5220\u9664',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _saving = true);

    try {
      final store = await ref.read(taskEventServerFirstStoreProvider.future);
      final result = await store.deleteLocalTask(localId: widget.taskId!);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isPending
                ? '\u5220\u9664\u5df2\u8fdb\u5165\u5f85\u540c\u6b65'
                : '\u4efb\u52a1\u5df2\u540c\u6b65\u5220\u9664',
          ),
        ),
      );
      _close(context);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('\u5220\u9664\u5931\u8d25\uff1a$error'),
        ),
      );
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: Colors.grey),
      ),
    );
  }
}

class _WarningNotice extends StatelessWidget {
  final String message;

  const _WarningNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        message,
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

class _TaskListSelector extends StatelessWidget {
  final List<TaskList> lists;
  final int? selectedId;
  final ValueChanged<int?> onChanged;

  const _TaskListSelector({
    required this.lists,
    required this.selectedId,
    required this.onChanged,
  });

  Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: lists.map((list) {
        final selected = list.id == selectedId;
        final color = _parseColor(list.colorHex);
        return GestureDetector(
          onTap: () => onChanged(list.id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? color.withValues(alpha: 0.15)
                  : Theme.of(context).inputDecorationTheme.fillColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? color : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  list.emoji?.isNotEmpty == true ? list.emoji! : '\u6536',
                ),
                const SizedBox(width: 6),
                Text(
                  list.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? color : null,
                  ),
                ),
                if (list.isDefault) ...[
                  const SizedBox(width: 6),
                  _SelectorTag(
                    label: '\u9ed8\u8ba4',
                    color: selected ? color : AppColors.primary,
                  ),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SelectorTag extends StatelessWidget {
  final String label;
  final Color color;

  const _SelectorTag({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _DateTimeTile extends StatelessWidget {
  final DateTime? dateTime;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _DateTimeTile({
    required this.dateTime,
    required this.label,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).inputDecorationTheme.fillColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_outlined, size: 18),
            const SizedBox(width: 12),
            Text(
              dateTime == null ? label : _format(dateTime!),
              style: TextStyle(
                color: dateTime == null ? Colors.grey : null,
                fontSize: 14,
              ),
            ),
            if (onClear != null) ...[
              const Spacer(),
              GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 16, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _format(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}\u5e74${value.month}\u6708${value.day}\u65e5 $hour:$minute';
  }
}

class _DurationPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _DurationPicker({required this.value, required this.onChanged});

  String _format(int minutes) {
    if (minutes < 60) {
      return '$minutes \u5206\u949f';
    }
    final hours = minutes ~/ 60;
    final restMinutes = minutes % 60;
    if (restMinutes == 0) {
      return '$hours \u5c0f\u65f6';
    }
    return '$hours \u5c0f\u65f6 $restMinutes \u5206\u949f';
  }

  @override
  Widget build(BuildContext context) {
    const options = [15, 30, 45, 60, 90, 120, 180, 240, 360, 480];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: options.map((minutes) {
        final selected = minutes == value;
        return ChoiceChip(
          label: Text(_format(minutes)),
          selected: selected,
          onSelected: (_) => onChanged(minutes),
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(
            color: selected ? Colors.white : null,
            fontSize: 12,
          ),
        );
      }).toList(),
    );
  }
}

class _PrioritySelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _PrioritySelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const items = [
      (value: 1, label: '\u9ad8', color: Color(0xFFE53935)),
      (value: 2, label: '\u4e2d', color: Color(0xFFFFA726)),
      (value: 3, label: '\u4f4e', color: Color(0xFF43A047)),
    ];

    return Row(
      children: items.map((item) {
        final selected = item.value == value;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(item.label),
            selected: selected,
            onSelected: (_) => onChanged(item.value),
            selectedColor: item.color,
            labelStyle: TextStyle(
              color: selected ? Colors.white : null,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _RepeatSelector extends StatelessWidget {
  final String? rrule;
  final ValueChanged<String?> onChanged;

  const _RepeatSelector({required this.rrule, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = [
      (value: null, label: '\u4e0d\u91cd\u590d'),
      (value: 'FREQ=DAILY', label: '\u6bcf\u5929'),
      (value: 'FREQ=WEEKLY', label: '\u6bcf\u5468'),
      (value: 'FREQ=MONTHLY', label: '\u6bcf\u6708'),
      (value: 'FREQ=YEARLY', label: '\u6bcf\u5e74'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: options.map((option) {
        final selected = option.value == rrule;
        return ChoiceChip(
          label: Text(option.label),
          selected: selected,
          onSelected: (_) => onChanged(option.value),
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(
            color: selected ? Colors.white : null,
            fontSize: 12,
          ),
        );
      }).toList(),
    );
  }
}

class _ReminderSelector extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  const _ReminderSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const options = [
      (value: 0, label: '\u51c6\u65f6'),
      (value: 5, label: '5 \u5206\u949f'),
      (value: 15, label: '15 \u5206\u949f'),
      (value: 30, label: '30 \u5206\u949f'),
      (value: 60, label: '1 \u5c0f\u65f6'),
      (value: 1440, label: '1 \u5929'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: options.map((option) {
        final selected = option.value == value;
        return ChoiceChip(
          label: Text(option.label),
          selected: selected,
          onSelected: (_) => onChanged(option.value),
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(
            color: selected ? Colors.white : null,
            fontSize: 12,
          ),
        );
      }).toList(),
    );
  }
}
