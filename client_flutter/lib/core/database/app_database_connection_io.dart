import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' show Database;

import '../storage/app_storage.dart';

QueryExecutor openAppDatabaseConnection() {
  return LazyDatabase(() async {
    final file = await resolvePrimaryDatabaseFile();
    await file.parent.create(recursive: true);
    return NativeDatabase.createInBackground(file, setup: _configureDatabase);
  });
}

void _configureDatabase(Database database) {
  database.execute('PRAGMA busy_timeout = 5000');
  database.execute('PRAGMA journal_mode = WAL');
}

Future<String> resolveAppDatabasePathForDisplay() async {
  final file = await resolvePrimaryDatabaseFile();
  return file.path;
}

Future<void> exportAppDatabase(GeneratedDatabase database, String targetPath) async {
  final targetFile = File(targetPath);
  await targetFile.parent.create(recursive: true);
  if (await targetFile.exists()) {
    await targetFile.delete();
  }

  await database.customStatement('PRAGMA wal_checkpoint(FULL)');
  final escapedPath = targetFile.path.replaceAll("'", "''");
  await database.customStatement("VACUUM INTO '$escapedPath'");
}
