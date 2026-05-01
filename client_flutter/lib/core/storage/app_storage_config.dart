import 'package:flutter/foundation.dart';

enum AppStorageFlavor {
  debug,
  profile,
  release,
}

const appDatabaseFileName = 'flowplanv2.db';
const appPendingDatabaseRestoreFileName = 'flowplanv2.restore.pending.db';
const appPendingDatabaseRestoreMetadataFileName =
    'flowplanv2.restore.pending.json';
const appDatabaseRestoreNoticeFileName = 'flowplanv2.restore.notice.json';
const appDatabasePreRestoreBackupFileName = 'flowplanv2.before_restore.db';

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
      return 'FlowPlanV2';
    case AppStorageFlavor.profile:
      return 'FlowPlanV2_profile';
    case AppStorageFlavor.debug:
      return 'FlowPlanV2_debug';
  }
}

String? get appSharedPreferencesPrefix {
  switch (currentAppStorageFlavor) {
    case AppStorageFlavor.release:
      return 'flowplanv2.';
    case AppStorageFlavor.profile:
      return 'flowplanv2.profile.';
    case AppStorageFlavor.debug:
      return 'flowplanv2.debug.';
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
