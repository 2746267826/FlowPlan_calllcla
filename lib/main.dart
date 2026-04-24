import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/database/app_database.dart';
import 'core/storage/app_storage.dart';
import 'core/storage/database_restore_service.dart';
import 'features/calendar/data/calendar_books_repository.dart';
import 'features/audit/data_operation_log_repository.dart';
import 'features/reminders/reminder_service.dart';
import 'features/tracker/services/raw_input_service.dart';
import 'features/tracker/services/tracker_service.dart';
import 'shared/providers/database_provider.dart';
import 'shared/providers/settings_provider.dart';

final RawInputService rawInputService = RawInputService();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final sharedPreferencesPrefix = appSharedPreferencesPrefix;
  if (sharedPreferencesPrefix != null) {
    SharedPreferences.setPrefix(sharedPreferencesPrefix);
  }

  await initializeDateFormatting('zh_CN', null);

  final restoreResult =
      await const DatabaseRestoreService().applyPendingRestoreIfNeeded();

  final database = AppDatabase();
  if (restoreResult.applied) {
    await DataOperationLogRepository(database).record(
      actor: 'system',
      action: 'apply_database_restore',
      entityType: 'database_backup',
      summary: '\u5df2\u5728\u542f\u52a8\u65f6\u5e94\u7528\u5f85\u5904\u7406\u7684\u6570\u636e\u5e93\u6062\u590d\u526f\u672c',
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

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(database),
      ],
      child: const _AppBootstrapper(),
    ),
  );
}

class _AppBootstrapper extends ConsumerWidget {
  const _AppBootstrapper();

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
    });

    return const FlowPlanApp();
  }
}
