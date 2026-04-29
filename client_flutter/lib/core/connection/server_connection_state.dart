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
    );
  }
}
