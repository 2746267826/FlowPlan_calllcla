import '../sync/sync_status.dart';

enum OfflineMutationAction {
  create,
  update,
  delete;

  String get wireName => name;

  static OfflineMutationAction fromWireName(String value) {
    for (final action in OfflineMutationAction.values) {
      if (action.wireName == value) {
        return action;
      }
    }
    return OfflineMutationAction.update;
  }
}

enum OfflineMutationStatus {
  pending,
  sending,
  acked,
  failed,
  conflict;

  String get wireName => name;

  SyncState get syncState {
    switch (this) {
      case OfflineMutationStatus.pending:
      case OfflineMutationStatus.sending:
        return SyncState.pendingUpdate;
      case OfflineMutationStatus.acked:
        return SyncState.synced;
      case OfflineMutationStatus.failed:
        return SyncState.failed;
      case OfflineMutationStatus.conflict:
        return SyncState.conflict;
    }
  }

  static OfflineMutationStatus fromWireName(String value) {
    for (final status in OfflineMutationStatus.values) {
      if (status.wireName == value) {
        return status;
      }
    }
    return OfflineMutationStatus.failed;
  }
}

class OfflineMutation {
  const OfflineMutation({
    required this.id,
    required this.mutationUid,
    required this.objectType,
    required this.localId,
    required this.action,
    required this.payloadJson,
    required this.createdAt,
    required this.attempts,
    required this.status,
    this.serverId,
    this.baseServerVersion,
    this.changedFieldsJson,
    this.lastError,
  });

  final int id;
  final String mutationUid;
  final String objectType;
  final String localId;
  final String? serverId;
  final OfflineMutationAction action;
  final int? baseServerVersion;
  final String payloadJson;
  final String? changedFieldsJson;
  final DateTime createdAt;
  final int attempts;
  final String? lastError;
  final OfflineMutationStatus status;
}
