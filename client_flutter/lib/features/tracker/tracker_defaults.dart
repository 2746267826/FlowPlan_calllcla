const Set<String> kDefaultTrackerIgnoredProcesses = <String>{
  'flowplan.exe',
  'calllclaude.exe',
};

const Set<String> kDefaultTrackerIgnoredAndroidPackages = <String>{
  'com.flowplan.flowplan',
  'com.android.systemui',
  'com.android.launcher3',
  'com.google.android.apps.nexuslauncher',
  'com.miui.home',
  'com.sec.android.app.launcher',
  'com.oppo.launcher',
  'com.vivo.launcher',
  'com.hihonor.android.launcher',
};

const List<String> kDefaultTrackerIgnoredTitleKeywords = <String>[
  'flowplan',
];

bool isTrackerSelfExcludedWindow({
  String? processName,
  String? windowTitle,
}) {
  final normalizedProcess = processName?.trim().toLowerCase();
  if (normalizedProcess != null &&
      kDefaultTrackerIgnoredProcesses.contains(normalizedProcess)) {
    return true;
  }

  final normalizedTitle = windowTitle?.trim().toLowerCase();
  if (normalizedTitle != null) {
    for (final keyword in kDefaultTrackerIgnoredTitleKeywords) {
      if (normalizedTitle.contains(keyword)) {
        return true;
      }
    }
  }

  return false;
}

bool isAndroidTrackerIgnoredPackage(String? packageName) {
  final normalizedPackage = packageName?.trim().toLowerCase();
  if (normalizedPackage == null || normalizedPackage.isEmpty) {
    return true;
  }
  return kDefaultTrackerIgnoredAndroidPackages.contains(normalizedPackage);
}
