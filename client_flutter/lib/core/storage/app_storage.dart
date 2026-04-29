import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

export 'app_storage_config.dart';

import 'app_storage_config.dart';

Future<Directory> resolveAppStorageDirectory() async {
  final documentsDirectory = await getApplicationDocumentsDirectory();
  return Directory(
    p.join(documentsDirectory.path, appStorageDirectoryName),
  );
}

Future<File> resolveAppStorageFile(String fileName) async {
  final directory = await resolveAppStorageDirectory();
  return File(p.join(directory.path, fileName));
}

Future<File> resolvePrimaryDatabaseFile() {
  return resolveAppStorageFile(appDatabaseFileName);
}

Future<File> resolvePendingDatabaseRestoreFile() {
  return resolveAppStorageFile(appPendingDatabaseRestoreFileName);
}

Future<File> resolvePendingDatabaseRestoreMetadataFile() {
  return resolveAppStorageFile(appPendingDatabaseRestoreMetadataFileName);
}

Future<File> resolveDatabaseRestoreNoticeFile() {
  return resolveAppStorageFile(appDatabaseRestoreNoticeFileName);
}

Future<File> resolvePreRestoreDatabaseBackupFile() {
  return resolveAppStorageFile(appDatabasePreRestoreBackupFileName);
}
