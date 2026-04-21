import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/app/app_release.dart';
import '../../../core/router/app_router.dart';
import '../../../core/storage/app_storage.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/providers/settings_provider.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isWindowsDesktop = Platform.isWindows;
    final themeMode = ref.watch(themeModeProvider);
    final workStart = ref.watch(workStartProvider);
    final workEnd = ref.watch(workEndProvider);
    final reminderMin = ref.watch(reminderMinutesProvider);
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
              onChanged: (value) {
                if (value == null) {
                  return;
                }
                ref.read(reminderMinutesNotifierProvider.notifier).set(value);
              },
            ),
          ),
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
          const Divider(),
          const _SectionTitle('\u6570\u636e\u540c\u6b65'),
          ListTile(
            leading: const Icon(Icons.import_export_outlined),
            title: const Text('iCalendar \u5bfc\u5165 / \u5bfc\u51fa'),
            subtitle: const Text(
              '\u652f\u6301\u6807\u51c6 .ics \u6587\u4ef6\u683c\u5f0f',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.icalImportExport),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync_outlined),
            title: const Text('Outlook \u65e5\u5386\u540c\u6b65'),
            subtitle: const Text(
              '\u901a\u8fc7 Microsoft Graph API \u5355\u5411\u53ea\u8bfb\u540c\u6b65 Outlook \u65e5\u5386',
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
