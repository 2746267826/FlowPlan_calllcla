import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_object_registry.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/ui/app_keys.dart';
import '../../../shared/providers/app_providers.dart';
import '../../files/data/file_context_repository.dart';
import '../../files/presentation/file_context_panel.dart';
import '../../sync/sync_status_badge.dart';

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
  bool _isReadOnly = false;
  bool _hasUserEditedBlock = false;
  int _eventCalendarDefaultsRequestVersion = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final rounded = now.copyWith(
      hour: now.minute > 0 ? now.hour + 1 : now.hour,
      minute: 0,
      second: 0,
      millisecond: 0,
      microsecond: 0,
    );
    _dtstart = rounded;
    _dtend = rounded.add(const Duration(hours: 1));

    if (widget.eventId != null) {
      _loadExistingEvent();
    }
  }

  Future<void> _loadExistingEvent() async {
    final repo = ref.read(eventRepositoryProvider);
    final event = await repo.getById(widget.eventId!);
    if (event == null || !mounted) {
      return;
    }

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
      _isReadOnly = event.source == 'outlook';
    });
  }

  Future<void> _handleEventCalendarSelection(
    int? eventCalendarId, {
    bool forceApplyDefaults = false,
  }) async {
    if (!mounted) {
      return;
    }

    setState(() => _eventCalendarId = eventCalendarId);
    if (widget.eventId != null || eventCalendarId == null) {
      return;
    }

    final requestVersion = ++_eventCalendarDefaultsRequestVersion;
    final defaults = await ref
        .read(calendarBooksRepositoryProvider)
        .getEventCalendarDefaults(eventCalendarId);
    if (!mounted ||
        widget.eventId != null ||
        requestVersion != _eventCalendarDefaultsRequestVersion ||
        _eventCalendarId != eventCalendarId) {
      return;
    }

    setState(() {
      if (forceApplyDefaults || !_hasUserEditedBlock) {
        _isBlock = defaults.defaultIsBlock;
      }
    });
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
      return;
    }
    Navigator.of(context).pop();
  }

  bool _selectedCalendarIsOutlook() {
    final calendars =
        ref.read(allEventCalendarsProvider).asData?.value ?? const <EventCalendar>[];
    for (final calendar in calendars) {
      if (calendar.id == _eventCalendarId) {
        return calendar.source == 'outlook';
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isCreating = widget.eventId == null;
    final calendarsAsync = ref.watch(allEventCalendarsProvider);
    final calendars = calendarsAsync.asData?.value ?? const <EventCalendar>[];
    EventCalendar? selectedCalendar;
    for (final calendar in calendars) {
      if (calendar.id == _eventCalendarId) {
        selectedCalendar = calendar;
        break;
      }
    }

    final isReadOnly =
        _isReadOnly || (selectedCalendar?.source == 'outlook' && !isCreating);
    final pageTitle = isCreating
        ? '\u65b0\u5efa\u65e5\u7a0b'
        : isReadOnly
            ? 'Outlook \u65e5\u7a0b\uff08\u53ea\u8bfb\uff09'
            : '\u7f16\u8f91\u65e5\u7a0b';

    return Scaffold(
      appBar: AppBar(
        title: Text(pageTitle),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _close(context),
        ),
        actions: [
          if (!isCreating && !isReadOnly)
            IconButton(
              onPressed: _saving ? null : _delete,
              tooltip: '\u5220\u9664\u65e5\u7a0b',
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton.icon(
            key: AppKeys.eventSaveButton,
            onPressed: _saving || isReadOnly ? null : _save,
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
                objectType: SyncObjectType.calendarEvent.key,
                localId: widget.eventId!.toString(),
              ),
              const SizedBox(height: 16),
            ],
            if (isReadOnly) ...[
              const _WarningNotice(
                message:
                    '\u8fd9\u662f\u4ece Outlook \u540c\u6b65\u8fc7\u6765\u7684\u53ea\u8bfb\u65e5\u7a0b\u3002\u8bf7\u5728 Outlook \u5b98\u65b9\u5ba2\u6237\u7aef\u4e2d\u4fee\u6539\u540e\uff0c\u518d\u56de\u5230 FlowPlanV2 \u6267\u884c\u540c\u6b65\u3002',
              ),
              const SizedBox(height: 16),
            ],
            AbsorbPointer(
              absorbing: isReadOnly,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionLabel('\u65e5\u5386\u672c'),
                  calendarsAsync.when(
                    loading: () => const SizedBox(
                      height: 40,
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, _) => Text(
                      '\u52a0\u8f7d\u5931\u8d25\uff1a$error',
                    ),
                    data: (value) {
                      final selectableCalendars = isCreating
                          ? value.where((calendar) => calendar.source == 'local').toList()
                          : value;
                      if (selectableCalendars.isEmpty) {
                        return const _WarningNotice(
                          message:
                              '\u5f53\u524d\u6ca1\u6709\u53ef\u5199\u5165\u7684\u672c\u5730\u65e5\u5386\u672c\u3002\u8bf7\u5148\u5728\u201c\u65e5\u5386\u672c\u201d\u4e2d\u521b\u5efa\u4e00\u4e2a\u672c\u5730\u65e5\u5386\u672c\uff0c\u518d\u521b\u5efa\u6216\u6574\u7406\u672c\u5730\u65e5\u7a0b\u3002',
                        );
                      }
                      if (isCreating && _eventCalendarId == null) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) {
                            _handleEventCalendarSelection(
                              selectableCalendars.first.id,
                              forceApplyDefaults: true,
                            );
                          }
                        });
                      }
                      return _CalendarSelector(
                        calendars: selectableCalendars,
                        selectedId: _eventCalendarId,
                        onChanged: (id) => _handleEventCalendarSelection(id),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    key: AppKeys.eventSummaryField,
                    controller: _titleController,
                    autofocus: !isReadOnly,
                    decoration: const InputDecoration(
                      labelText: '\u6807\u9898',
                      hintText: '\u65e5\u7a0b\u6807\u9898',
                    ),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: const Text(
                      '\u5168\u5929',
                      style: TextStyle(fontSize: 14),
                    ),
                    value: _isAllDay,
                    onChanged: (value) => setState(() => _isAllDay = value),
                    activeThumbColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const _SectionLabel('\u5f00\u59cb\u65f6\u95f4'),
                  _DateTimeTile(
                    dateTime: _dtstart,
                    isAllDay: _isAllDay,
                    onTap: () => _pickDateTime(isStart: true),
                  ),
                  const SizedBox(height: 12),
                  const _SectionLabel('\u7ed3\u675f\u65f6\u95f4'),
                  _DateTimeTile(
                    dateTime: _dtend,
                    isAllDay: _isAllDay,
                    onTap: () => _pickDateTime(isStart: false),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _locationController,
                    decoration: const InputDecoration(
                      labelText: '\u5730\u70b9',
                      hintText: '\u6dfb\u52a0\u5730\u70b9\uff08\u53ef\u9009\uff09',
                      prefixIcon: Icon(Icons.location_on_outlined, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _descController,
                    decoration: const InputDecoration(
                      labelText: '\u5907\u6ce8',
                      hintText: '\u6dfb\u52a0\u5907\u6ce8\uff08\u53ef\u9009\uff09',
                      prefixIcon: Icon(Icons.notes_outlined, size: 20),
                    ),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  const _SectionLabel('\u989c\u8272'),
                  _ColorPicker(
                    selected: _colorHex,
                    onChanged: (value) => setState(() => _colorHex = value),
                  ),
                  const SizedBox(height: 20),
                  const _SectionLabel('\u786e\u8ba4\u72b6\u6001'),
                  _StatusSelector(
                    value: _status,
                    onChanged: (value) => setState(() => _status = value),
                  ),
                  const SizedBox(height: 20),
                  const _SectionLabel('\u91cd\u590d'),
                  _RepeatSelector(
                    rrule: _rrule,
                    onChanged: (value) => setState(() => _rrule = value),
                  ),
                  const SizedBox(height: 20),
                  SwitchListTile(
                    title: const Text(
                      '\u963b\u6321\u81ea\u52a8\u6392\u7a0b',
                      style: TextStyle(fontSize: 14),
                    ),
                    subtitle: const Text(
                      '\u5f00\u542f\u540e\u6b64\u65f6\u95f4\u6bb5\u4e0d\u4f1a\u88ab\u81ea\u52a8\u6392\u5165\u4efb\u52a1',
                    ),
                    value: _isBlock,
                    onChanged: (value) => setState(() {
                      _isBlock = value;
                      _hasUserEditedBlock = true;
                    }),
                    activeThumbColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
            if (!isCreating) ...[
              const SizedBox(height: 28),
              EntityFileContextPanel(
                entityType: FileContextEntityType.event,
                entityId: widget.eventId!.toString(),
                title: _titleController.text,
                description: _descController.text,
                location: _locationController.text,
              ),
            ],
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
    if (date == null || !mounted) {
      return;
    }

    if (_isAllDay) {
      setState(() {
        final selected = DateTime(date.year, date.month, date.day);
        if (isStart) {
          _dtstart = selected;
          if (_dtend.isBefore(_dtstart)) {
            _dtend = _dtstart;
          }
        } else {
          if (selected.isBefore(_dtstart)) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  '\u7ed3\u675f\u65f6\u95f4\u5fc5\u987b\u665a\u4e8e\u6216\u7b49\u4e8e\u5f00\u59cb\u65f6\u95f4',
                ),
              ),
            );
          } else {
            _dtend = selected;
          }
        }
      });
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) {
      return;
    }

    final result =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _dtstart = result;
        if (_dtend.isBefore(_dtstart)) {
          _dtend = _dtstart.add(const Duration(hours: 1));
        }
      } else if (result.isAfter(_dtstart)) {
        _dtend = result;
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\u7ed3\u675f\u65f6\u95f4\u5fc5\u987b\u665a\u4e8e\u5f00\u59cb\u65f6\u95f4',
            ),
          ),
        );
      }
    });
  }

  Future<void> _save() async {
    if (_isReadOnly || _selectedCalendarIsOutlook()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Outlook \u540c\u6b65\u65e5\u7a0b\u4e3a\u53ea\u8bfb\uff0c\u8bf7\u5728 Outlook \u5b98\u65b9\u5ba2\u6237\u7aef\u4e2d\u4fee\u6539\u3002',
          ),
        ),
      );
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('\u8bf7\u8f93\u5165\u65e5\u7a0b\u6807\u9898'),
        ),
      );
      return;
    }
    if (_eventCalendarId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u65e5\u7a0b\u5fc5\u987b\u5f52\u5c5e\u4e8e\u4e00\u4e2a\u65e5\u5386\u672c\uff0c\u8bf7\u5148\u9009\u62e9\u65e5\u5386\u672c\u3002',
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
      'uid': widget.eventId == null ? const Uuid().v4() : null,
      'summary': title,
      'title': title,
      'description': description.isEmpty ? null : description,
      'location': location.isEmpty ? null : location,
      'startAt': _dtstart.toIso8601String(),
      'endAt': _dtend.toIso8601String(),
      'rrule': _rrule,
      'status': _status,
      'colorHex': _colorHex,
      'isBlock': _isBlock,
      'eventCalendarId': _eventCalendarId,
    };

    try {
      final store = await ref.read(taskEventServerFirstStoreProvider.future);
      late final result;
      if (widget.eventId == null) {
        result = await store.createEvent(payload);
      } else {
        result = await store.updateLocalEvent(
          localId: widget.eventId!,
          patch: payload,
          changedFields: payload.keys.toList(growable: false),
        );
      }

      if (!mounted) {
        return;
      }
      ref.read(selectedDateProvider.notifier).setDate(_dtstart);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isPending
                ? '\u65e5\u7a0b\u300c$title\u300d\u5df2\u4fdd\u5b58\u5230\u672c\u673a\uff0c\u7b49\u5f85\u540c\u6b65'
                : '\u65e5\u7a0b\u300c$title\u300d\u5df2\u540c\u6b65\u4fdd\u5b58',
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
    if (widget.eventId == null || _saving) {
      return;
    }
    if (_isReadOnly || _selectedCalendarIsOutlook()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Outlook \u540c\u6b65\u65e5\u7a0b\u4e3a\u53ea\u8bfb\uff0c\u4e0d\u80fd\u5728 FlowPlanV2 \u4e2d\u5220\u9664\u3002',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('\u5220\u9664\u65e5\u7a0b'),
        content: Text(
          '\u786e\u5b9a\u8981\u5220\u9664\u65e5\u7a0b\u300c${_titleController.text.trim().isEmpty ? '\u672a\u547d\u540d\u65e5\u7a0b' : _titleController.text.trim()}\u300d\u5417\uff1f',
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
      final result = await store.deleteLocalEvent(localId: widget.eventId!);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isPending
                ? '\u5220\u9664\u5df2\u8fdb\u5165\u5f85\u540c\u6b65'
                : '\u65e5\u7a0b\u5df2\u540c\u6b65\u5220\u9664',
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
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: calendars.map((calendar) {
        final selected = calendar.id == selectedId;
        final color = _parseColor(calendar.colorHex);
        return GestureDetector(
          onTap: () => onChanged(calendar.id),
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
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  calendar.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? color : null,
                  ),
                ),
                if (calendar.isDefault) ...[
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
  final DateTime dateTime;
  final bool isAllDay;
  final VoidCallback onTap;

  const _DateTimeTile({
    required this.dateTime,
    required this.isAllDay,
    required this.onTap,
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
            const Icon(Icons.access_time_outlined, size: 18),
            const SizedBox(width: 12),
            Text(
              _format(dateTime, isAllDay),
              style: const TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  String _format(DateTime dt, bool allDay) {
    final date =
        '${dt.year}\u5e74${dt.month}\u6708${dt.day}\u65e5';
    if (allDay) {
      return date;
    }
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$date $hour:$minute';
  }
}

class _ColorPicker extends StatelessWidget {
  final String selected;
  final ValueChanged<String> onChanged;

  const _ColorPicker({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      children: AppColors.taskPalette.map((color) {
        final hex =
            '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
        final isSelected = hex == selected.toUpperCase();
        return GestureDetector(
          onTap: () => onChanged(hex),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: isSelected
                  ? Border.all(
                      color: Theme.of(context).colorScheme.onSurface,
                      width: 3,
                    )
                  : null,
            ),
            child: isSelected
                ? const Icon(Icons.check, color: Colors.white, size: 16)
                : null,
          ),
        );
      }).toList(),
    );
  }
}

class _StatusSelector extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _StatusSelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const items = [
      (
        value: 'CONFIRMED',
        label: '\u5df2\u786e\u8ba4',
        icon: Icons.check_circle_outline,
      ),
      (
        value: 'TENTATIVE',
        label: '\u6682\u5b9a',
        icon: Icons.help_outline,
      ),
      (
        value: 'CANCELLED',
        label: '\u5df2\u53d6\u6d88',
        icon: Icons.cancel_outlined,
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items.map((item) {
        final selected = item.value == value;
        return ChoiceChip(
          avatar: Icon(item.icon, size: 16),
          label: Text(item.label),
          selected: selected,
          onSelected: (_) => onChanged(item.value),
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

class _RepeatSelector extends StatelessWidget {
  final String? rrule;
  final ValueChanged<String?> onChanged;

  const _RepeatSelector({required this.rrule, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const items = [
      (value: null, label: '\u4e0d\u91cd\u590d'),
      (value: 'FREQ=DAILY', label: '\u6bcf\u5929'),
      (value: 'FREQ=WEEKLY', label: '\u6bcf\u5468'),
      (value: 'FREQ=MONTHLY', label: '\u6bcf\u6708'),
      (value: 'FREQ=YEARLY', label: '\u6bcf\u5e74'),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: items.map((item) {
        final selected = item.value == rrule;
        return ChoiceChip(
          label: Text(item.label),
          selected: selected,
          onSelected: (_) => onChanged(item.value),
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
