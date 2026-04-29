import 'dart:io';

enum TrackerCollectionMode {
  continuousWindowSampling,
  manualUsageStatsImport,
  unsupported,
}

class TrackerPlatformSource {
  const TrackerPlatformSource._({
    required this.platformLabel,
    required this.collectionMode,
    required this.supportsInputAnalytics,
    required this.supportsSequenceRecording,
    required this.supportsUsageAccessPermission,
    required this.supportsDetailedInputHistory,
  });

  factory TrackerPlatformSource.current() {
    if (Platform.isWindows) {
      return const TrackerPlatformSource._(
        platformLabel: 'Windows',
        collectionMode: TrackerCollectionMode.continuousWindowSampling,
        supportsInputAnalytics: true,
        supportsSequenceRecording: true,
        supportsUsageAccessPermission: false,
        supportsDetailedInputHistory: true,
      );
    }
    if (Platform.isAndroid) {
      return const TrackerPlatformSource._(
        platformLabel: 'Android',
        collectionMode: TrackerCollectionMode.manualUsageStatsImport,
        supportsInputAnalytics: false,
        supportsSequenceRecording: false,
        supportsUsageAccessPermission: true,
        supportsDetailedInputHistory: false,
      );
    }
    return const TrackerPlatformSource._(
      platformLabel: '当前平台',
      collectionMode: TrackerCollectionMode.unsupported,
      supportsInputAnalytics: false,
      supportsSequenceRecording: false,
      supportsUsageAccessPermission: false,
      supportsDetailedInputHistory: false,
    );
  }

  final String platformLabel;
  final TrackerCollectionMode collectionMode;
  final bool supportsInputAnalytics;
  final bool supportsSequenceRecording;
  final bool supportsUsageAccessPermission;
  final bool supportsDetailedInputHistory;

  bool get isWindows =>
      collectionMode == TrackerCollectionMode.continuousWindowSampling;

  bool get isAndroid =>
      collectionMode == TrackerCollectionMode.manualUsageStatsImport;

  bool get isSupported =>
      collectionMode != TrackerCollectionMode.unsupported;

  String get collectionDescription {
    return switch (collectionMode) {
      TrackerCollectionMode.continuousWindowSampling =>
        '连续采集 Windows 前台窗口，并记录键鼠输入统计。',
      TrackerCollectionMode.manualUsageStatsImport =>
        '打开应用或手动刷新时读取 Android 使用情况记录，不常驻后台。',
      TrackerCollectionMode.unsupported => '当前平台暂不支持自动活动追踪。',
    };
  }
}
