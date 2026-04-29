import '../database/app_database.dart';

class PlatformStartup {
  const PlatformStartup({
    required this.database,
    this.restoreApplied = false,
    this.previousDatabaseBackupPath,
    this.restoredDatabasePath,
  });

  final AppDatabase database;
  final bool restoreApplied;
  final String? previousDatabaseBackupPath;
  final String? restoredDatabasePath;
}
