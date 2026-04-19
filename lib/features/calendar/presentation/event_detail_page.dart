// 日程详情页 v3：接通数据库，日历本列表从 Provider 读取
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/database/app_database.dart';
import '../../../shared/providers/app_providers.dart';

class EventDetailPage extends ConsumerStatefulWidget {
  final int? eventId;
  const EventDetailPage({super.key, required this.eventId});

  @override
  ConsumerState<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends ConsumerState<EventDetailPage> {
  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _descController = TextEditingController();

  late DateTime _dtstart;
  late DateTime _dtend;
  String _status = 'CONFIRMED';
  bool _isAllDay = false;
  String _colorHex = '#6B5EE4';
  String? _rrule;
  bool _isBlock = false;
  int? _eventCalendarId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final next = now.copyWith(
        hour: now.minute > 0 ? now.hour + 1 : now.hour,
        minute: 0,
        second: 0,
        millisecond: 0,
        microsecond: 0);
    _dtstart = next;
    _dtend = next.add(const Duration(hours: 1));

    if (widget.eventId != null) _loadExistingEvent();
  }

  Future<void> _loadExistingEvent() async {
    final repo = ref.read(eventRepositoryProvider);
    final event = await repo.getById(widget.eventId!);
    if (event != null && mounted) {
      setState(() {
        _titleController.text = event.summary;
        _locationController.text = event.location ?? '';
        _descController.text = event.description ?? '';
        _dtstart = event.dtstart;
        _dtend = event.dtend ?? event.dtstart.add(const Duration(hours: 1));
        _status = event.status;
        _colorHex = event.colorHex;
        _rrule = event.rrule;
        _isBlock = event.isBlock;
        _eventCalendarId = event.eventCalendarId;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _close(BuildContext context) {
    if (GoRouter.of(context).canPop()) {
      context.pop();
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = widget.eventId == null;
    final eventCalsAsync = ref.watch(allEventCalendarsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(isCreating ? '新建日程' : '编辑日程'),
        leading: IconButton(
            icon: const Icon(Icons.close), onPressed: () => _close(context)),
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
            // ── 日历本选择 ────────────────────────────────────────────────
            _SectionLabel('日历本'),
            eventCalsAsync.when(
              loading: () => const SizedBox(
                  height: 36,
                  child: Center(child: CircularProgressIndicator())),
              error: (e, _) => Text('加载失败: $e'),
              data: (cals) {
                if (_eventCalendarId == null && cals.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      setState(() => _eventCalendarId = cals.first.id);
                    }
                  });
                }
                return _CalendarSelector(
                  calendars: cals,
                  selectedId: _eventCalendarId,
                  onChanged: (id) => setState(() => _eventCalendarId = id),
                );
              },
            ),
            const SizedBox(height: 20),

            // ── 标题 ─────────────────────────────────────────────────────
            TextField(
              controller: _titleController,
              autofocus: true,
              decoration:
                  const InputDecoration(hintText: '日程标题', labelText: '标题'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 20),

            // ── 全天 + 时间 ──────────────────────────────────────────────
            SwitchListTile(
              title: const Text('全天', style: TextStyle(fontSize: 14)),
              value: _isAllDay,
              onChanged: (v) => setState(() => _isAllDay = v),
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
            _SectionLabel('开始时间'),
            _DateTimeTile(
                dateTime: _dtstart,
                isAllDay: _isAllDay,
                onTap: () => _pickDateTime(isStart: true)),
            const SizedBox(height: 12),
            _SectionLabel('结束时间'),
            _DateTimeTile(
                dateTime: _dtend,
                isAllDay: _isAllDay,
                onTap: () => _pickDateTime(isStart: false)),
            const SizedBox(height: 20),

            // ── 地点 ─────────────────────────────────────────────────────
            TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                  hintText: '添加地点（可选）',
                  labelText: '地点',
                  prefixIcon: Icon(Icons.location_on_outlined, size: 20)),
            ),
            const SizedBox(height: 16),

            // ── 备注 ─────────────────────────────────────────────────────
            TextField(
              controller: _descController,
              decoration: const InputDecoration(
                  hintText: '添加备注（可选）',
                  labelText: '备注',
                  prefixIcon: Icon(Icons.notes_outlined, size: 20)),
              maxLines: 3,
            ),
            const SizedBox(height: 20),

            // ── 颜色 ─────────────────────────────────────────────────────
            _SectionLabel('颜色'),
            _ColorPicker(
                selected: _colorHex,
                onChanged: (c) => setState(() => _colorHex = c)),
            const SizedBox(height: 20),

            // ── 状态 ─────────────────────────────────────────────────────
            _SectionLabel('确认状态'),
            _StatusSelector(
                value: _status, onChanged: (s) => setState(() => _status = s)),
            const SizedBox(height: 20),

            // ── 重复规则 ──────────────────────────────────────────────────
            _SectionLabel('重复'),
            _RepeatSelector(
                rrule: _rrule, onChanged: (r) => setState(() => _rrule = r)),
            const SizedBox(height: 20),

            // ── 排程阻挡 ──────────────────────────────────────────────────
            SwitchListTile(
              title: const Text('阻挡自动排程', style: TextStyle(fontSize: 14)),
              subtitle: const Text('开启后此时间段不会被自动排入任务'),
              value: _isBlock,
              onChanged: (v) => setState(() => _isBlock = v),
              activeThumbColor: AppColors.primary,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initial = isStart ? _dtstart : _dtend;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date == null || !mounted) return;
    if (_isAllDay) {
      setState(() {
        if (isStart) {
          _dtstart = DateTime(date.year, date.month, date.day);
        } else {
          _dtend = DateTime(date.year, date.month, date.day);
        }
      });
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final result =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _dtstart = result;
        if (_dtend.isBefore(_dtstart)) {
          _dtend = _dtstart.add(const Duration(hours: 1));
        }
      } else {
        if (result.isAfter(_dtstart)) {
          _dtend = result;
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('结束时间必须晚于开始时间')));
        }
      }
    });
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('请输入日程标题')));
      return;
    }
    setState(() => _saving = true);

    final repo = ref.read(eventRepositoryProvider);
    final now = DateTime.now();
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();
    final location = _locationController.text.trim();

    try {
      if (widget.eventId == null) {
        await repo.create(CalendarEventsCompanion.insert(
          uid: const Uuid().v4(),
          dtstamp: now,
          summary: title,
          description: Value(desc.isEmpty ? null : desc),
          location: Value(location.isEmpty ? null : location),
          dtstart: _dtstart,
          dtend: Value(_dtend),
          rrule: Value(_rrule),
          status: Value(_status),
          colorHex: Value(_colorHex),
          isBlock: Value(_isBlock),
          eventCalendarId: Value(_eventCalendarId),
        ));
      } else {
        await repo.update(CalendarEventsCompanion(
          id: Value(widget.eventId!),
          summary: Value(title),
          description: Value(desc.isEmpty ? null : desc),
          location: Value(location.isEmpty ? null : location),
          dtstart: Value(_dtstart),
          dtend: Value(_dtend),
          rrule: Value(_rrule),
          status: Value(_status),
          colorHex: Value(_colorHex),
          isBlock: Value(_isBlock),
          eventCalendarId: Value(_eventCalendarId),
        ));
      }
      if (mounted) {
        ref.read(selectedDateProvider.notifier).setDate(_dtstart);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('日程「$title」已保存')));
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

class _CalendarSelector extends StatelessWidget {
  final List<EventCalendar> calendars;
  final int? selectedId;
  final ValueChanged<int?> onChanged;
  const _CalendarSelector({
    required this.calendars,
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
  Widget build(BuildContext context) => Wrap(
      spacing: 8,
      runSpacing: 6,
      children: calendars.map((cal) {
        final selected = cal.id == selectedId;
        final color = _parseColor(cal.colorHex);
        return GestureDetector(
          onTap: () => onChanged(cal.id),
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
                Container(
                    width: 10,
                    height: 10,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(cal.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                      color: selected ? color : null,
                    )),
              ],
            ),
          ),
        );
      }).toList());
}

class _DateTimeTile extends StatelessWidget {
  final DateTime dateTime;
  final bool isAllDay;
  final VoidCallback onTap;
  const _DateTimeTile({
    required this.dateTime,
    required this.isAllDay,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: Theme.of(context).inputDecorationTheme.fillColor,
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.access_time_outlined, size: 18),
          const SizedBox(width: 12),
          Text(_format(dateTime, isAllDay),
              style: const TextStyle(fontSize: 15)),
        ]),
      ));

  String _format(DateTime dt, bool allDay) {
    final date = '${dt.year}年${dt.month}月${dt.day}日';
    if (allDay) return date;
    return '$date  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _ColorPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;
  const _ColorPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) => Wrap(
      spacing: 10,
      children: AppColors.taskPalette.map((color) {
        final hex =
            '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
        final isSel = hex == selected.toUpperCase();
        return GestureDetector(
          onTap: () => onChanged(hex),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: isSel
                    ? Border.all(
                        color: Theme.of(context).colorScheme.onSurface,
                        width: 3)
                    : null),
            child: isSel
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : null,
          ),
        );
      }).toList());
}

class _StatusSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const _StatusSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const items = [
      (v: 'CONFIRMED', label: '已确认', icon: Icons.check_circle_outline),
      (v: 'TENTATIVE', label: '暂定', icon: Icons.help_outline),
      (v: 'CANCELLED', label: '已取消', icon: Icons.cancel_outlined),
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items.map((item) {
        final sel = item.v == value;
        return ChoiceChip(
          avatar: Icon(item.icon, size: 16),
          label: Text(item.label),
          selected: sel,
          onSelected: (_) => onChanged(item.v),
          selectedColor: AppColors.primary,
          labelStyle: TextStyle(color: sel ? Colors.white : null, fontSize: 12),
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
