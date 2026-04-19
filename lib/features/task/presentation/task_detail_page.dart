// 任务详情页 v3：接通数据库，清单列表从 Provider 读取
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/providers/app_providers.dart';
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
  int _durationMinutes = 60;
  int _priorityLocal = 2;
  bool _isSplittable = false;
  bool _isAutoScheduled = true;
  DateTime? _due;
  String? _rrule;
  int? _taskListId;
  int _reminderMinutes = 15;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (widget.taskId != null) {
      // 编辑模式：加载已有数据
      _loadExistingTask();
    }
  }

  Future<void> _loadExistingTask() async {
    final repo = ref.read(taskRepositoryProvider);
    final task = await repo.getById(widget.taskId!);
    if (task != null && mounted) {
      setState(() {
        _titleController.text = task.summary;
        _descController.text = task.description ?? '';
        _durationMinutes = task.durationMinutes;
        _priorityLocal = task.priorityLocal;
        _isSplittable = task.isSplittable;
        _isAutoScheduled = task.isAutoScheduled;
        _due = task.due;
        _rrule = task.rrule;
        _taskListId = task.taskListId;
        _reminderMinutes = task.reminderMinutesBefore;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = widget.taskId == null;
    // 从 Provider 获取任务清单列表
    final taskListsAsync = ref.watch(allTaskListsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isCreating ? '新建任务' : '编辑任务'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _close(context),
        ),
        actions: [
          TextButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check, size: 18),
            label: const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 任务清单选择（从数据库读取）──────────────────────────────────
            _SectionLabel('任务清单'),
            taskListsAsync.when(
              loading: () => const SizedBox(
                  height: 36,
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text('加载失败: $e'),
              data: (lists) {
                // 若未选择，默认第一个
                if (_taskListId == null && lists.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _taskListId = lists.first.id);
                  });
                }
                return _TaskListSelector(
                  lists: lists,
                  selectedId: _taskListId,
                  onChanged: (id) => setState(() => _taskListId = id),
                );
              },
            ),
            const SizedBox(height: 20),

            // ── 标题 ────────────────────────────────────────────────────────
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration:
                  const InputDecoration(hintText: '任务标题', labelText: '标题'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 16),

            // ── 描述 ────────────────────────────────────────────────────────
            TextField(
              controller: _descController,
              decoration:
                  const InputDecoration(hintText: '添加描述（可选）', labelText: '描述'),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // ── 时长 ────────────────────────────────────────────────────────
            _SectionLabel('预估时长'),
            _DurationPicker(
                value: _durationMinutes,
                onChanged: (v) => setState(() => _durationMinutes = v)),
            const SizedBox(height: 20),

            // ── 截止时间 ─────────────────────────────────────────────────────
            _SectionLabel('截止时间'),
            _DateTimeTile(
              dateTime: _due,
              label: '设置截止时间',
              onTap: _pickDeadline,
              onClear: _due != null ? () => setState(() => _due = null) : null,
            ),
            const SizedBox(height: 20),

            // ── 优先级 ───────────────────────────────────────────────────────
            _SectionLabel('优先级'),
            _PrioritySelector(
                value: _priorityLocal,
                onChanged: (v) => setState(() => _priorityLocal = v)),
            const SizedBox(height: 20),

            // ── 重复规则 ─────────────────────────────────────────────────────
            _SectionLabel('重复'),
            _RepeatSelector(
                rrule: _rrule, onChanged: (r) => setState(() => _rrule = r)),
            const SizedBox(height: 20),

            // ── 提醒 ────────────────────────────────────────────────────────
            _SectionLabel('提前提醒'),
            _ReminderSelector(
                value: _reminderMinutes,
                onChanged: (v) => setState(() => _reminderMinutes = v)),
            const SizedBox(height: 20),

            // ── 开关项 ───────────────────────────────────────────────────────
            SwitchListTile(
              title: const Text('自动排程', style: TextStyle(fontSize: 14)),
              subtitle: const Text('由排程引擎自动安排时间'),
              value: _isAutoScheduled,
              onChanged: (v) => setState(() => _isAutoScheduled = v),
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('允许拆分', style: TextStyle(fontSize: 14)),
              subtitle: const Text('可被拆成多段分布在不同时间'),
              value: _isSplittable,
              onChanged: (v) => setState(() => _isSplittable = v),
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
            if (!isCreating) ...[
              const SizedBox(height: 28),
              TaskTrackerEvidenceSection(taskId: widget.taskId!),
            ],
          ],
        ),
      ),
    );
  }

  void _close(BuildContext context) {
    if (GoRouter.of(context).canPop()) {
      context.pop();
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickDeadline() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _due ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime:
          _due != null ? TimeOfDay.fromDateTime(_due!) : TimeOfDay.now(),
    );
    if (time == null || !mounted) return;
    setState(() {
      _due = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入任务标题')));
      return;
    }
    setState(() => _saving = true);

    final repo = ref.read(taskRepositoryProvider);
    final now = DateTime.now();
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();

    try {
      if (widget.taskId == null) {
        // ── 创建 ─────────────────────────────────────────────────────────
        await repo.create(TaskItemsCompanion.insert(
          uid: const Uuid().v4(),
          dtstamp: now,
          summary: title,
          description: Value(desc.isEmpty ? null : desc),
          due: Value(_due),
          priorityLocal: Value(_priorityLocal),
          durationMinutes: Value(_durationMinutes),
          isSplittable: Value(_isSplittable),
          isAutoScheduled: Value(_isAutoScheduled),
          taskListId: Value(_taskListId),
          rrule: Value(_rrule),
          reminderMinutesBefore: Value(_reminderMinutes),
        ));
      } else {
        // ── 更新 ─────────────────────────────────────────────────────────
        await repo.update(TaskItemsCompanion(
          id: Value(widget.taskId!),
          summary: Value(title),
          description: Value(desc.isEmpty ? null : desc),
          due: Value(_due),
          priorityLocal: Value(_priorityLocal),
          durationMinutes: Value(_durationMinutes),
          isSplittable: Value(_isSplittable),
          isAutoScheduled: Value(_isAutoScheduled),
          taskListId: Value(_taskListId),
          rrule: Value(_rrule),
          reminderMinutesBefore: Value(_reminderMinutes),
        ));
      }
      if (mounted) {
        if (_due != null) {
          ref.read(selectedDateProvider.notifier).setDate(_due!);
        }
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('任务「$title」已保存')));
        _close(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }
}

// ─── 辅助 Widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: Colors.grey)));
}

// 任务清单选择器（从数据库 TaskList 读取）
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
                  color: selected ? color : Colors.transparent, width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(list.emoji ?? '📋', style: const TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(list.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? color : null,
                    )),
              ],
            ),
          ),
        );
      }).toList(),
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
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).inputDecorationTheme.fillColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.event_outlined, size: 18),
          const SizedBox(width: 12),
          Text(
            dateTime == null
                ? label
                : '${dateTime!.year}年${dateTime!.month}月${dateTime!.day}日  '
                    '${dateTime!.hour.toString().padLeft(2, '0')}:${dateTime!.minute.toString().padLeft(2, '0')}',
            style: TextStyle(
                color: dateTime == null ? Colors.grey : null, fontSize: 14),
          ),
          if (onClear != null) ...[
            const Spacer(),
            GestureDetector(
                onTap: onClear,
                child: const Icon(Icons.close, size: 16, color: Colors.grey)),
          ],
        ]),
      ));
}

class _DurationPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  const _DurationPicker({required this.value, required this.onChanged});

  String _format(int m) {
    if (m < 60) return '$m 分钟';
    final h = m ~/ 60;
    final min = m % 60;
    return min == 0 ? '$h 小时' : '$h 时 $min 分';
  }

  @override
  Widget build(BuildContext context) {
    const opts = [15, 30, 45, 60, 90, 120, 180, 240, 360, 480];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: opts.map((m) {
        final sel = m == value;
        return ChoiceChip(
          label: Text(_format(m)),
          selected: sel,
          onSelected: (_) => onChanged(m),
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(color: sel ? Colors.white : null, fontSize: 12),
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
      (v: 1, label: '🔴 高', color: Color(0xFFE53935)),
      (v: 2, label: '🟡 中', color: Color(0xFFFFA726)),
      (v: 3, label: '🟢 低', color: Color(0xFF43A047)),
    ];
    return Row(
      children: items.map((item) {
        final sel = item.v == value;
        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(item.label),
            selected: sel,
            onSelected: (_) => onChanged(item.v),
            selectedColor: item.color,
            labelStyle: TextStyle(
                color: sel ? Colors.white : null,
                fontWeight: FontWeight.w500,
                fontSize: 13),
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
    const opts = [
      (v: null, label: '不重复'),
      (v: 'FREQ=DAILY', label: '每天'),
      (v: 'FREQ=WEEKLY', label: '每周'),
      (v: 'FREQ=MONTHLY', label: '每月'),
      (v: 'FREQ=YEARLY', label: '每年'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: opts.map((opt) {
        final sel = opt.v == rrule;
        return ChoiceChip(
          label: Text(opt.label),
          selected: sel,
          onSelected: (_) => onChanged(opt.v),
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(color: sel ? Colors.white : null, fontSize: 12),
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
    const opts = [
      (v: 0, label: '准时'),
      (v: 5, label: '5 分钟'),
      (v: 15, label: '15 分钟'),
      (v: 30, label: '30 分钟'),
      (v: 60, label: '1 小时'),
      (v: 1440, label: '1 天'),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: opts.map((opt) {
        final sel = opt.v == value;
        return ChoiceChip(
          label: Text(opt.label),
          selected: sel,
          onSelected: (_) => onChanged(opt.v),
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(color: sel ? Colors.white : null, fontSize: 12),
        );
      }).toList(),
    );
  }
}
