enum ServerConnectionLevel {
  unknown,
  online,
  syncing,
  degraded,
  offline,
  authRequired,
  conflicted,
  localCacheOnly,
}

class ServerConnectionState {
  const ServerConnectionState({
    this.level = ServerConnectionLevel.unknown,
    this.serverUrl = '',
    this.deviceId = '',
    this.platform = '',
    this.lastHeartbeatAt,
    this.lastSyncAt,
    this.lastError,
    this.pendingCount = 0,
    this.failedCount = 0,
    this.conflictCount = 0,
    this.nextHeartbeatSeconds = 30,
    this.syncing = false,
    this.syncPhase,
    this.syncReason,
    this.progressCurrent,
    this.progressTotal,
    this.lastSyncSummary = const <String, Object?>{},
  });

  final ServerConnectionLevel level;
  final String serverUrl;
  final String deviceId;
  final String platform;
  final DateTime? lastHeartbeatAt;
  final DateTime? lastSyncAt;
  final String? lastError;
  final int pendingCount;
  final int failedCount;
  final int conflictCount;
  final int nextHeartbeatSeconds;
  final bool syncing;
  final String? syncPhase;
  final String? syncReason;
  final int? progressCurrent;
  final int? progressTotal;
  final Map<String, Object?> lastSyncSummary;

  bool get hasConflict => conflictCount > 0;

  ServerConnectionState copyWith({
    ServerConnectionLevel? level,
    String? serverUrl,
    String? deviceId,
    String? platform,
    DateTime? lastHeartbeatAt,
    DateTime? lastSyncAt,
    String? lastError,
    bool clearError = false,
    int? pendingCount,
    int? failedCount,
    int? conflictCount,
    int? nextHeartbeatSeconds,
    bool? syncing,
    String? syncPhase,
    String? syncReason,
    int? progressCurrent,
    int? progressTotal,
    Map<String, Object?>? lastSyncSummary,
    bool clearProgress = false,
  }) {
    return ServerConnectionState(
      level: level ?? this.level,
      serverUrl: serverUrl ?? this.serverUrl,
      deviceId: deviceId ?? this.deviceId,
      platform: platform ?? this.platform,
      lastHeartbeatAt: lastHeartbeatAt ?? this.lastHeartbeatAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastError: clearError ? null : lastError ?? this.lastError,
      pendingCount: pendingCount ?? this.pendingCount,
      failedCount: failedCount ?? this.failedCount,
      conflictCount: conflictCount ?? this.conflictCount,
      nextHeartbeatSeconds:
          nextHeartbeatSeconds ?? this.nextHeartbeatSeconds,
      syncing: syncing ?? this.syncing,
      syncPhase: clearProgress ? null : syncPhase ?? this.syncPhase,
      syncReason: clearProgress ? null : syncReason ?? this.syncReason,
      progressCurrent:
          clearProgress ? null : progressCurrent ?? this.progressCurrent,
      progressTotal: clearProgress ? null : progressTotal ?? this.progressTotal,
      lastSyncSummary: lastSyncSummary ?? this.lastSyncSummary,
    );
  }
}
