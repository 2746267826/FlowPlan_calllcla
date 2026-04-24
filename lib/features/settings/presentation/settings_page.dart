import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app/app_release.dart';
import '../../../core/router/app_router.dart';
import '../../../core/storage/app_storage.dart';
import '../../../core/platform/device_identity_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../reminders/reminder_service.dart';
import '../../tracker/services/android_usage_stats_service.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/providers/settings_provider.dart';

final androidUsageAccessStatusProvider = FutureProvider.autoDispose<bool>((ref) {
  return const AndroidUsageStatsService().hasUsageAccessPermission();
});

final deviceIdentityDisplayProvider =
    FutureProvider.autoDispose<String>((ref) async {
  final database = ref.watch(databaseProvider);
  return DeviceIdentityService().getOrCreateDeviceId(database);
});

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWindowsDesktop = Platform.isWindows;
    final themeMode = ref.watch(themeModeProvider);
    final workStart = ref.watch(workStartProvider);
    final workEnd = ref.watch(workEndProvider);
    final weeklyWorkSchedule = ref.watch(weeklyWorkScheduleProvider);
    final reminderMin = ref.watch(reminderMinutesProvider);
    final reminderSystemStatus = ref.watch(reminderSystemStatusProvider);
    final use24h = ref.watch(use24hProvider);
    final firstDay = ref.watch(firstDayOfWeekProvider);
    final minimizeToTray =
        isWindowsDesktop ? ref.watch(minimizeToTrayProvider) : false;
    final launchAtStartup =
        isWindowsDesktop ? ref.watch(launchAtStartupProvider) : false;

    String formatTime(TimeOfDay value) {
      final hour = value.hour.toString().padLeft(2, '0');
      final minute = value.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('\u8bbe\u7f6e'),
      ),
      body: ListView(
        children: [
          const _SectionTitle('\u5916\u89c2'),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('\u4e3b\u9898\u6a21\u5f0f'),
            trailing: DropdownButton<ThemeMode>(
              value: themeMode,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('\u8ddf\u968f\u7cfb\u7edf'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text('\u6d45\u8272'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text('\u6df1\u8272'),
                ),
              ],
              onChanged: (mode) {
                if (mode == null) {
                  return;
                }
                ref
                    .read(themeModeNotifierProvider.notifier)
                    .setThemeMode(mode);
              },
            ),
          ),
          const Divider(),
          const _SectionTitle('\u5de5\u4f5c\u65f6\u95f4'),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: const Text('\u6bcf\u65e5\u5de5\u4f5c\u5f00\u59cb'),
            trailing: Text(formatTime(workStart)),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: workStart,
              );
              if (picked == null) {
                return;
              }
              ref.read(workStartNotifierProvider.notifier).set(picked);
            },
          ),
          ListTile(
            leading: const Icon(Icons.nightlight_outlined),
            title: const Text('\u6bcf\u65e5\u5de5\u4f5c\u7ed3\u675f'),
            trailing: Text(formatTime(workEnd)),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: workEnd,
              );
              if (picked == null) {
                return;
              }
              ref.read(workEndNotifierProvider.notifier).set(picked);
            },
          ),
          ListTile(
            leading: const Icon(Icons.view_day_outlined),
            title: const Text('\u591a\u7ec4\u5de5\u4f5c\u65f6\u95f4'),
            subtitle: Text(
              '${weeklyWorkSchedule.compactSummary}\n\u81ea\u52a8\u6392\u7a0b\u4f1a\u4f18\u5148\u4f7f\u7528\u8fd9\u91cc\u7684\u591a\u6bb5\u65f6\u95f4\uff0c\u7528\u4e8e\u8df3\u8fc7\u5348\u4f11\u3001\u665a\u996d\u7b49\u4e0d\u5de5\u4f5c\u65f6\u6bb5\u3002',
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              showDialog<void>(
                context: context,
                builder: (dialogContext) => _WorkScheduleEditorDialog(
                  initial: weeklyWorkSchedule,
                  onSave: (schedule) => ref
                      .read(weeklyWorkScheduleNotifierProvider.notifier)
                      .setSchedule(schedule),
                ),
              );
            },
          ),
          const Divider(),
          const _SectionTitle('\u63d0\u9192'),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('\u9ed8\u8ba4\u63d0\u524d\u63d0\u9192'),
            trailing: DropdownButton<int>(
              value: reminderMin,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 0, child: Text('\u4e0d\u63d0\u9192')),
                DropdownMenuItem(value: 5, child: Text('5 \u5206\u949f')),
                DropdownMenuItem(value: 10, child: Text('10 \u5206\u949f')),
                DropdownMenuItem(value: 15, child: Text('15 \u5206\u949f')),
                DropdownMenuItem(value: 30, child: Text('30 \u5206\u949f')),
                DropdownMenuItem(value: 60, child: Text('1 \u5c0f\u65f6')),
              ],
              onChanged: (value) async {
                if (value == null) {
                  return;
                }
                await ref
                    .read(reminderMinutesNotifierProvider.notifier)
                    .set(value);
                await ref.read(reminderServiceProvider).rebuildSystemSchedule();
                ref.invalidate(reminderSystemStatusProvider);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notification_important_outlined),
            title: const Text('\u8fd0\u884c\u65f6\u63d0\u9192\u670d\u52a1'),
            subtitle: Text(
              isWindowsDesktop
                  ? '应用运行时会检查日程、任务和计划偏离；Windows 会触发托盘通知与置顶强提醒。'
                  : '应用运行时会检查日程、任务和计划偏离；Android 会同时尝试写入系统精准提醒调度。',
            ),
          ),
          if (Platform.isAndroid)
            _AndroidReminderSystemTile(status: reminderSystemStatus),
          if (Platform.isAndroid) ...[
            const Divider(),
            const _SectionTitle('安卓端状态'),
            const _AndroidTrackerAccessTile(),
            const _AndroidDeviceIdentityTile(),
            ListTile(
              leading: const Icon(Icons.cloud_done_outlined),
              title: const Text('移动端同步状态'),
              subtitle: const Text(
                '查看 Outlook 连接、同步模式、最近同步结果与冲突诊断。安卓端可作为日程和任务同步查看终端。',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(AppRoutes.outlookSync),
            ),
          ],
          const Divider(),
          const _SectionTitle('\u7cfb\u7edf'),
          ListTile(
            leading: const Icon(Icons.developer_mode_outlined),
            title: const Text('\u5f53\u524d\u8fd0\u884c\u73af\u5883'),
            subtitle: Text(appStorageFlavorDisplayName),
            trailing: Text(
              appStorageFlavorLabel,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (isWindowsDesktop)
            SwitchListTile(
              secondary: const Icon(Icons.minimize_outlined),
              title: const Text(
                '\u5173\u95ed\u7a97\u53e3\u65f6\u7f29\u5230\u6258\u76d8',
              ),
              subtitle: const Text(
                '\u5173\u95ed\u4e3b\u7a97\u53e3\u540e\u4ecd\u5728\u540e\u53f0\u8fd0\u884c\uff0c\u5e76\u7ee7\u7eed\u9759\u9ed8\u8bb0\u5f55\u8ffd\u8e2a\u3002',
              ),
              value: minimizeToTray,
              activeThumbColor: AppColors.primary,
              onChanged: (value) {
                ref.read(minimizeToTrayNotifierProvider.notifier).set(value);
              },
            ),
          if (isWindowsDesktop)
            SwitchListTile(
              secondary: const Icon(Icons.rocket_launch_outlined),
              title: const Text('\u5f00\u673a\u81ea\u542f\u52a8'),
              subtitle: const Text(
                '\u767b\u5f55 Windows \u540e\u901a\u8fc7\u8ba1\u5212\u4efb\u52a1\u4ee5\u6700\u9ad8\u6743\u9650\u542f\u52a8 FlowPlan\uff0c\u5e76\u9ed8\u8ba4\u9759\u9ed8\u7f29\u5230\u6258\u76d8\u3002',
              ),
              value: launchAtStartup,
              activeThumbColor: AppColors.primary,
              onChanged: (value) {
                ref.read(launchAtStartupNotifierProvider.notifier).set(value);
              },
            ),
          ListTile(
            leading: const Icon(Icons.history_outlined),
            title: const Text('\u5386\u53f2\u65e5\u5fd7\u6587\u4ef6'),
            subtitle: const Text(
              '\u67e5\u770b\u6309\u5929\u5f52\u6863\u7684\u8ffd\u8e2a\u65e5\u5fd7\u6587\u4ef6\uff0c\u652f\u6301\u5e94\u7528\u5185\u5386\u53f2\u67e5\u8be2\u3002',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.trackerLogHistory),
          ),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: const Text('数据操作审计'),
            subtitle: const Text(
              '查看任务、日程、任务本、日历本、导入导出、数据库恢复、排程确认和 Outlook 同步等关键数据操作记录。',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.auditLogs),
          ),
          const Divider(),
          const _SectionTitle('\u6570\u636e\u540c\u6b65\u4e0e\u5907\u4efd'),
          ListTile(
            leading: const Icon(Icons.import_export_outlined),
            title: const Text('\u5bfc\u5165 / \u5bfc\u51fa\u4e0e\u5907\u4efd'),
            subtitle: const Text(
              '\u652f\u6301\u6807\u51c6 .ics \u65e5\u7a0b\u4ea4\u6362\uff0c\u4e5f\u53ef\u5bfc\u51fa\u4e0e\u6062\u590d\u5b8c\u6574\u6570\u636e\u5e93\u526f\u672c',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.icalImportExport),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Outlook \u65e5\u5386\u540c\u6b65'),
            subtitle: const Text(
              '\u652f\u6301\u53ea\u8bfb\u3001\u53cc\u5411\u540c\u6b65\u4e0e\u6682\u505c\u540c\u6b65\uff0c\u53cc\u5411\u6a21\u5f0f\u4ec5\u5199\u5165 FlowPlan \u6258\u7ba1\u5bb9\u5668',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.outlookSync),
          ),
          const Divider(),
          const _SectionTitle('\u65f6\u95f4\u683c\u5f0f'),
          ListTile(
            leading: const Icon(Icons.access_time_outlined),
            title: const Text('\u65f6\u95f4\u5236'),
            trailing: Text(
              use24h ? '24 \u5c0f\u65f6\u5236' : '12 \u5c0f\u65f6\u5236',
            ),
            onTap: () {
              ref.read(use24hNotifierProvider.notifier).toggle();
            },
          ),
          ListTile(
            leading: const Icon(Icons.calendar_today_outlined),
            title: const Text('\u4e00\u5468\u8d77\u59cb\u65e5'),
            trailing: DropdownButton<int>(
              value: firstDay,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(value: 1, child: Text('\u5468\u4e00')),
                DropdownMenuItem(value: 7, child: Text('\u5468\u65e5')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                ref.read(firstDayOfWeekNotifierProvider.notifier).set(value);
              },
            ),
          ),
          const Divider(),
          const _SectionTitle('\u5173\u4e8e'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text(appProductName),
            subtitle: Text(
              '$appAboutSubtitle\n\u53d1\u5e03\u53f7 $appPackageVersion',
            ),
            isThreeLine: true,
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
          letterSpacing: 0.5,
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
              ? '已开启。FlowPlan 会在打开应用或手动刷新时导入安卓应用前台使用记录。'
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
