import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum AppStorageFlavor {
  debug,
  profile,
  release,
}

const appDatabaseFileName = 'flowplan.db';
const appPendingDatabaseRestoreFileName = 'flowplan.restore.pending.db';
const appPendingDatabaseRestoreMetadataFileName =
    'flowplan.restore.pending.json';
const appDatabaseRestoreNoticeFileName = 'flowplan.restore.notice.json';
const appDatabasePreRestoreBackupFileName = 'flowplan.before_restore.db';

AppStorageFlavor get currentAppStorageFlavor {
  if (kReleaseMode) {
    return AppStorageFlavor.release;
  }
  if (kProfileMode) {
    return AppStorageFlavor.profile;
  }
  return AppStorageFlavor.debug;
}

String get appStorageDirectoryName {
  switch (currentAppStorageFlavor) {
    case AppStorageFlavor.release:
      return 'flowplan';
    case AppStorageFlavor.profile:
      return 'flowplan_profile';
    case AppStorageFlavor.debug:
      return 'flowplan_debug';
  }
}

String? get appSharedPreferencesPrefix {
  switch (currentAppStorageFlavor) {
    case AppStorageFlavor.release:
      return null;
    case AppStorageFlavor.profile:
      return 'flowplan.profile.';
    case AppStorageFlavor.debug:
      return 'flowplan.debug.';
  }
}

String get appStorageFlavorLabel {
  switch (currentAppStorageFlavor) {
    case AppStorageFlavor.release:
      return 'release';
    case AppStorageFlavor.profile:
      return 'profile';
    case AppStorageFlavor.debug:
      return 'debug';
  }
}

String get appStorageFlavorDisplayName {
  switch (currentAppStorageFlavor) {
    case AppStorageFlavor.release:
      return 'release\uff08\u6b63\u5f0f\u53d1\u5e03\uff09';
    case AppStorageFlavor.profile:
      return 'profile\uff08\u6027\u80fd\u5206\u6790\uff09';
    case AppStorageFlavor.debug:
      return 'debug\uff08\u5f00\u53d1\u8c03\u8bd5\uff09';
  }
}

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
