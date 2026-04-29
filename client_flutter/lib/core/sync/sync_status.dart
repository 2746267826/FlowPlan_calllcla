enum SyncState {
  synced,
  pendingCreate,
  pendingUpdate,
  pendingDelete,
  conflict,
  failed;

  String get wireName {
    switch (this) {
      case SyncState.synced:
        return 'synced';
      case SyncState.pendingCreate:
        return 'pending_create';
      case SyncState.pendingUpdate:
        return 'pending_update';
      case SyncState.pendingDelete:
        return 'pending_delete';
      case SyncState.conflict:
        return 'conflict';
      case SyncState.failed:
        return 'failed';
    }
  }

  static SyncState fromWireName(String value) {
    for (final state in SyncState.values) {
      if (state.wireName == value) {
        return state;
      }
    }
    return SyncState.failed;
  }
}

class SyncObjectState {
  const SyncObjectState({
    required this.objectType,
    required this.localId,
    required this.syncState,
    required this.localVersion,
    required this.createdAt,
    required this.updatedAt,
    this.serverId,
    this.uid,
    this.serverVersion,
    this.originDeviceId,
    this.lastModifiedDeviceId,
    this.deletedAt,
    this.lastSyncedAt,
    this.lastSyncError,
  });

  final String objectType;
  final String localId;
  final String? serverId;
  final String? uid;
  final SyncState syncState;
  final int localVersion;
  final int? serverVersion;
  final String? originDeviceId;
  final String? lastModifiedDeviceId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final DateTime? lastSyncedAt;
  final String? lastSyncError;
}
