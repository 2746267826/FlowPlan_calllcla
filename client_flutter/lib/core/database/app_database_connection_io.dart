import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../storage/app_storage.dart';

QueryExecutor openAppDatabaseConnection() {
  return LazyDatabase(() async {
    final file = await resolvePrimaryDatabaseFile();
    await file.parent.create(recursive: true);
    return NativeDatabase.createInBackground(file);
  });
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
