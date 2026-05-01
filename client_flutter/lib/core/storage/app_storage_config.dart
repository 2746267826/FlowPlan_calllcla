import 'package:flutter/foundation.dart';

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
      return 'flowplanV2';
    case AppStorageFlavor.profile:
      return 'flowplanV2_profile';
    case AppStorageFlavor.debug:
      return 'flowplanV2_debug';
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
      return 'release（正式发布）';
    case AppStorageFlavor.profile:
      return 'profile（性能分析）';
    case AppStorageFlavor.debug:
      return 'debug（开发调试）';
  }
}
