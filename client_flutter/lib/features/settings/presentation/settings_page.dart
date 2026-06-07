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
import '../../../core/ui/app_keys.dart';
import '../../reminders/reminder_service.dart';
import '../../tracker/services/android_usage_stats_service.dart';
import '../../../shared/providers/database_provider.dart';
import '../../../shared/providers/settings_provider.dart';

part 'settings_widgets.dart';

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
      appBar: AppBar(title: const Text('\u8bbe\u7f6e')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _SettingsHeader(
            title: appProductName,
            subtitle: appAboutSubtitle,
            badge: appStorageFlavorLabel,
          ),
          const SizedBox(height: 16),
          _SettingsSection(
            title: '\u5916\u89c2',
            icon: Icons.palette_outlined,
            children: [
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
            ],
          ),
          _SettingsSection(
            title: '\u5de5\u4f5c\u65f6\u95f4',
            icon: Icons.work_history_outlined,
            children: [
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
            ],
          ),
          _SettingsSection(
            title: '\u63d0\u9192',
            icon: Icons.notifications_active_outlined,
            children: [
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
                  ? '应用运行时会检查日程、任务和计划偏离；Windows 仅触发托盘/系统通知，不再弹出置顶软件窗口。'
                  : '应用运行时会检查日程、任务和计划偏离；Android 会同时尝试写入系统精准提醒调度。',
            ),
          ),
          if (Platform.isAndroid)
            _AndroidReminderSystemTile(status: reminderSystemStatus),
            ],
          ),
          if (Platform.isAndroid) ...[
            _SettingsSection(
              title: '安卓端状态',
              icon: Icons.phone_android_outlined,
              children: [
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
            ),
          ],
          _SettingsSection(
            title: '\u7cfb\u7edf',
            icon: Icons.tune_outlined,
            children: [
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
                '\u767b\u5f55 Windows \u540e\u901a\u8fc7\u8ba1\u5212\u4efb\u52a1\u4ee5\u6700\u9ad8\u6743\u9650\u542f\u52a8 FlowPlanV2\uff0c\u5e76\u9ed8\u8ba4\u9759\u9ed8\u7f29\u5230\u6258\u76d8\u3002',
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
            ],
          ),
          _SettingsSection(
            title: '\u6570\u636e\u540c\u6b65\u4e0e\u5907\u4efd',
            icon: Icons.storage_outlined,
            children: [
          ListTile(
            leading: const Icon(Icons.dataset_outlined),
            title: const Text('全部任务与日程管理'),
            subtitle: const Text(
              '统一查看、筛选、多选和批量管理所有任务与日程数据。',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.dataManagement),
          ),
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
              '\u652f\u6301\u53ea\u8bfb\u3001\u53cc\u5411\u540c\u6b65\u4e0e\u6682\u505c\u540c\u6b65\uff0c\u53cc\u5411\u6a21\u5f0f\u4ec5\u5199\u5165 FlowPlanV2 \u6258\u7ba1\u5bb9\u5668',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.outlookSync),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_upload_outlined),
            title: const Text('FlowPlanV2 服务端同步'),
            subtitle: const Text(
              '查看任务和日程的等待同步、同步失败、已同步状态，并在网络恢复后手动推送离线队列。',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.serverSync),
          ),
            ],
          ),
          _SettingsSection(
            title: '\u65f6\u95f4\u683c\u5f0f',
            icon: Icons.access_time_outlined,
            children: [
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
            ],
          ),
          _SettingsSection(
            title: '\u5173\u4e8e',
            icon: Icons.info_outline,
            children: [
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
        ],
      ),
    );
  }
}

