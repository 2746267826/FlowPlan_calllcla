part of 'settings_page.dart';

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({
    required this.title,
    required this.subtitle,
    required this.badge,
  });

  final String title;
  final String subtitle;
  final String badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Chip(
            label: Text(badge),
            visualDensity: VisualDensity.compact,
            backgroundColor: Theme.of(context).cardColor,
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  indent: 56,
                  color: Colors.grey.withValues(alpha: 0.12),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _AndroidTrackerAccessTile extends ConsumerWidget {
  const _AndroidTrackerAccessTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(androidUsageAccessStatusProvider);
    return status.when(
      loading: () => const ListTile(
        leading: Icon(Icons.query_stats_outlined),
        title: Text('使用情况访问权限'),
        subtitle: Text('正在检查安卓应用使用记录权限...'),
      ),
      error: (error, _) => ListTile(
        leading: const Icon(Icons.query_stats_outlined),
        title: const Text('使用情况访问权限'),
        subtitle: Text('读取权限状态失败：$error'),
        trailing: TextButton(
          onPressed: () => ref.invalidate(androidUsageAccessStatusProvider),
          child: const Text('重试'),
        ),
      ),
      data: (granted) => ListTile(
        leading: Icon(
          granted ? Icons.verified_user_outlined : Icons.security_outlined,
          color: granted ? const Color(0xFF0EA8A0) : Colors.orange,
        ),
        title: const Text('使用情况访问权限'),
        subtitle: Text(
          granted
              ? '已开启。FlowPlanV2 会在打开应用或手动刷新时导入安卓应用前台使用记录。'
              : '未开启。开启后才能在追踪页显示安卓应用使用记录，并且会优先展示应用名。',
        ),
        trailing: TextButton(
          onPressed: () async {
            await const AndroidUsageStatsService().openUsageAccessSettings();
            ref.invalidate(androidUsageAccessStatusProvider);
          },
          child: Text(granted ? '重新检查' : '去开启'),
        ),
      ),
    );
  }
}

class _AndroidDeviceIdentityTile extends ConsumerWidget {
  const _AndroidDeviceIdentityTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(deviceIdentityDisplayProvider);
    return identity.when(
      loading: () => const ListTile(
        leading: Icon(Icons.perm_device_information_outlined),
        title: Text('设备标识'),
        subtitle: Text('正在读取本机设备标识...'),
      ),
      error: (error, _) => ListTile(
        leading: const Icon(Icons.perm_device_information_outlined),
        title: const Text('设备标识'),
        subtitle: Text('读取设备标识失败：$error'),
      ),
      data: (deviceId) => ListTile(
        leading: const Icon(Icons.perm_device_information_outlined),
        title: const Text('设备标识'),
        subtitle: Text(
          '本机标识：${_shortDeviceId(deviceId)}。追踪日志会用它区分 Windows、手机和平板来源。',
        ),
      ),
    );
  }

  static String _shortDeviceId(String value) {
    if (value.length <= 12) {
      return value;
    }
    return '${value.substring(0, 8)}...${value.substring(value.length - 4)}';
  }
}

class _AndroidReminderSystemTile extends ConsumerWidget {
  const _AndroidReminderSystemTile({
    required this.status,
  });

  final AsyncValue<ReminderSystemStatus> status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return status.when(
      loading: () => const ListTile(
        leading: Icon(Icons.alarm_on_outlined),
        title: Text('Android 系统级提醒'),
        subtitle: Text('正在检查精准闹钟权限与提醒调度状态...'),
      ),
      error: (error, _) => ListTile(
        leading: const Icon(Icons.alarm_on_outlined),
        title: const Text('Android 系统级提醒'),
        subtitle: Text('读取提醒状态失败：$error'),
        trailing: TextButton(
          onPressed: () => ref.invalidate(reminderSystemStatusProvider),
          child: const Text('重试'),
        ),
      ),
      data: (value) {
        final lastRebuiltAt = value.lastRebuiltAt == null
            ? '尚未重建'
            : _formatDateTime(value.lastRebuiltAt!);
        final permissionText = value.canScheduleExactAlarms
            ? '精准闹钟权限已开启'
            : '精准闹钟权限未开启，点击本项去系统设置开启';
        return ListTile(
          leading: Icon(
            value.canScheduleExactAlarms
                ? Icons.alarm_on_outlined
                : Icons.alarm_off_outlined,
          ),
          title: const Text('Android 系统级提醒'),
          subtitle: Text(
            '$permissionText；当前已写入 ${value.pendingSystemReminderCount} 条未来提醒。'
            '\n上次重建：$lastRebuiltAt。设备重启、时间变化或应用重新打开后会自动恢复已缓存的提醒。',
          ),
          isThreeLine: true,
          onTap: value.needsAndroidExactAlarmPermission
              ? () {
                  unawaited(
                    ref
                        .read(reminderServiceProvider)
                        .openAndroidExactAlarmSettings(),
                  );
                }
              : null,
          trailing: IconButton(
            tooltip: '立即重建提醒调度',
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () async {
              await ref.read(reminderServiceProvider).rebuildSystemSchedule();
              ref.invalidate(reminderSystemStatusProvider);
            },
          ),
        );
      },
    );
  }

  static String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }
}

class _WorkScheduleEditorDialog extends StatefulWidget {
  const _WorkScheduleEditorDialog({
    required this.initial,
    required this.onSave,
  });

  final WeeklyWorkSchedule initial;
  final Future<void> Function(WeeklyWorkSchedule schedule) onSave;

  @override
  State<_WorkScheduleEditorDialog> createState() =>
      _WorkScheduleEditorDialogState();
}

class _WorkScheduleEditorDialogState extends State<_WorkScheduleEditorDialog> {
  late final Map<int, TextEditingController> _controllers;
  bool _saving = false;
  String? _error;

  static const _weekdayNames = {
    DateTime.monday: '周一',
    DateTime.tuesday: '周二',
    DateTime.wednesday: '周三',
    DateTime.thursday: '周四',
    DateTime.friday: '周五',
    DateTime.saturday: '周六',
    DateTime.sunday: '周日',
  };

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final weekday in _weekdayNames.keys)
        weekday: TextEditingController(
          text: _rangesToText(widget.initial.rangesForWeekday(weekday)),
        ),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('多组工作时间'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '每一行可以填写多段时间，用逗号分隔，例如：09:00-12:00，13:30-18:00，19:30-22:00。留空表示当天休息。',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _saving ? null : _applyDefaultWeekdays,
                    child: const Text('套用工作日默认'),
                  ),
                  OutlinedButton(
                    onPressed: _saving ? null : _copyMondayToWorkdays,
                    child: const Text('周一复制到工作日'),
                  ),
                  OutlinedButton(
                    onPressed: _saving ? null : _clearWeekend,
                    child: const Text('周末设为休息'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final entry in _weekdayNames.entries) ...[
                TextField(
                  controller: _controllers[entry.key],
                  enabled: !_saving,
                  decoration: InputDecoration(
                    labelText: entry.value,
                    hintText: '09:00-12:00，13:30-18:00',
                    suffixIcon: IconButton(
                      tooltip: '设为休息',
                      icon: const Icon(Icons.clear),
                      onPressed: _saving
                          ? null
                          : () => _controllers[entry.key]?.clear(),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => _applySchedule(
            WeeklyWorkSchedule.defaults(),
            closeAfterSave: false,
          ),
          child: const Text('恢复默认'),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('保存'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final rangesByWeekday = <int, List<WorkTimeRange>>{};
    try {
      for (final entry in _controllers.entries) {
        rangesByWeekday[entry.key] = _parseRanges(
          entry.value.text,
          weekdayName: _weekdayNames[entry.key]!,
        );
      }
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }

    await _applySchedule(WeeklyWorkSchedule(rangesByWeekday));
  }

  Future<void> _applySchedule(
    WeeklyWorkSchedule schedule, {
    bool closeAfterSave = true,
  }) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(schedule);
      if (!mounted) {
        return;
      }
      if (closeAfterSave) {
        Navigator.of(context).pop();
      } else {
        for (final weekday in _weekdayNames.keys) {
          _controllers[weekday]?.text = _rangesToText(
            schedule.rangesForWeekday(weekday),
          );
        }
        setState(() => _saving = false);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = '保存失败：$error';
      });
    }
  }

  void _applyDefaultWeekdays() {
    const text = '09:00-12:00，13:30-18:00，19:30-22:00';
    for (final weekday in [
      DateTime.monday,
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    ]) {
      _controllers[weekday]?.text = text;
    }
  }

  void _copyMondayToWorkdays() {
    final text = _controllers[DateTime.monday]?.text ?? '';
    for (final weekday in [
      DateTime.tuesday,
      DateTime.wednesday,
      DateTime.thursday,
      DateTime.friday,
    ]) {
      _controllers[weekday]?.text = text;
    }
  }

  void _clearWeekend() {
    _controllers[DateTime.saturday]?.clear();
    _controllers[DateTime.sunday]?.clear();
  }

  static String _rangesToText(List<WorkTimeRange> ranges) {
    return ranges.map((range) => range.format()).join('，');
  }

  static List<WorkTimeRange> _parseRanges(
    String raw, {
    required String weekdayName,
  }) {
    final text = raw.trim();
    if (text.isEmpty || text == '休息') {
      return const <WorkTimeRange>[];
    }
    final parts = text
        .split(RegExp(r'[,，;；]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);
    final ranges = <WorkTimeRange>[];
    for (final part in parts) {
      final pair = part.split(RegExp(r'\s*[-~～—]\s*'));
      if (pair.length != 2) {
        throw FormatException('$weekdayName 的时间段“$part”格式不正确。');
      }
      final start = _parseMinute(pair[0], weekdayName: weekdayName);
      final end = _parseMinute(pair[1], weekdayName: weekdayName);
      final range = WorkTimeRange(startMinute: start, endMinute: end);
      if (!range.isValid) {
        throw FormatException('$weekdayName 的时间段“$part”结束时间必须晚于开始时间。');
      }
      ranges.add(range);
    }
    return WeeklyWorkSchedule({DateTime.monday: ranges})
        .rangesForWeekday(DateTime.monday);
  }

  static int _parseMinute(String raw, {required String weekdayName}) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
    if (match == null) {
      throw FormatException('$weekdayName 的时间“$raw”格式不正确，请使用 09:00。');
    }
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour < 0 || hour > 24 || minute < 0 || minute > 59) {
      throw FormatException('$weekdayName 的时间“$raw”超出范围。');
    }
    if (hour == 24 && minute != 0) {
      throw FormatException('$weekdayName 的 24 点只能写作 24:00。');
    }
    return hour * 60 + minute;
  }
}
