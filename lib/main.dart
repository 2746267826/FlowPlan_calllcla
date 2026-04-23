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

  await const DatabaseRestoreService().applyPendingRestoreIfNeeded();

  final database = AppDatabase();
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
