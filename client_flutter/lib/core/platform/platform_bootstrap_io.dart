import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../features/audit/data_operation_log_repository.dart';
import '../../features/calendar/data/calendar_books_repository.dart';
import '../../features/reminders/reminder_service.dart';
import '../../features/tracker/services/raw_input_service.dart';
import '../../features/tracker/services/tracker_service.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/providers/settings_provider.dart';
import '../database/app_database.dart';
import '../storage/database_restore_service.dart';
import 'platform_bootstrap_types.dart';

Future<PlatformStartup> preparePlatformStartup() async {
  final restoreResult =
      await const DatabaseRestoreService().applyPendingRestoreIfNeeded();
  final database = AppDatabase();
  if (restoreResult.applied) {
    await DataOperationLogRepository(database).record(
      actor: 'system',
      action: 'apply_database_restore',
      entityType: 'database_backup',
      summary: '已在启动时应用待处理的数据库恢复副本',
      metadata: <String, Object?>{
        'previous_database_backup_path': restoreResult.previousDatabaseBackupPath,
        'restored_database_path': restoreResult.restoredDatabasePath,
      },
    );
  }
  await CalendarBooksRepository(database).ensureContainerIntegrity();
  if (Platform.isWindows) {
    await rawInputService.start();
  }
  return PlatformStartup(
    database: database,
    restoreApplied: restoreResult.applied,
    previousDatabaseBackupPath: restoreResult.previousDatabaseBackupPath,
    restoredDatabasePath: restoreResult.restoredDatabasePath,
  );
}

class FlowPlanPlatformBootstrapper extends ConsumerWidget {
  const FlowPlanPlatformBootstrapper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (Platform.isWindows) {
      ref.watch(minimizeToTrayNotifierProvider);
      ref.watch(launchAtStartupNotifierProvider);
    }

    final tracker = ref.read(trackerServiceNotifierProvider.notifier);
    final reminderService = ref.read(reminderServiceProvider);
    ref.listen<int>(reminderMinutesProvider, (previous, next) {
      if (previous == next) {
        return;
      }
      unawaited(reminderService.rebuildSystemSchedule());
      ref.invalidate(reminderSystemStatusProvider);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.read(trackerServiceNotifierProvider).isRunning) {
        tracker.start();
      }
      reminderService.start();
      unawaited(
        ref
            .read(serverConnectionServiceProvider.future)
            .then((service) => service.start()),
      );
    });

    return const FlowPlanApp();
  }
}
