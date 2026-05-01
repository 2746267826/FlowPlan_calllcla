import 'dart:async';

import 'package:uuid/uuid.dart';

import '../offline_queue/offline_mutation.dart';
import '../offline_queue/offline_mutation_store.dart';

class QueuedMutationResult {
  const QueuedMutationResult({
    required this.mutationUid,
    required this.objectType,
    required this.localId,
    required this.action,
  });

  final String mutationUid;
  final String objectType;
  final String localId;
  final OfflineMutationAction action;
}

class MutationCoordinator {
  MutationCoordinator({
    required OfflineMutationStore mutationStore,
    Future<void> Function()? pushPending,
    Uuid? uuid,
  })  : _mutationStore = mutationStore,
        _pushPending = pushPending,
        _uuid = uuid ?? const Uuid();

  final OfflineMutationStore _mutationStore;
  final Future<void> Function()? _pushPending;
  final Uuid _uuid;

  Future<QueuedMutationResult> enqueueBusinessMutation({
    required String objectType,
    required OfflineMutationAction action,
    required Map<String, Object?> payload,
    String? localId,
    String? serverId,
    int? baseServerVersion,
    List<String>? changedFields,
    bool pushImmediately = true,
  }) async {
    final effectiveLocalId = localId ??
        _readString(payload, 'id') ??
        _readString(payload, 'uid') ??
        'local-${_uuid.v4()}';
    final mutationUid = await _mutationStore.enqueue(
      objectType: objectType,
      localId: effectiveLocalId,
      serverId: serverId,
      action: action,
      baseServerVersion: baseServerVersion,
      changedFields: changedFields,
      payload: payload,
    );
    if (pushImmediately) {
      // Fire-and-forget: UI must keep the pending state visible until sync ack.
      final push = _pushPending;
      if (push != null) {
        unawaited(push().catchError((_) {
          // The queued mutation remains pending/failed in offline_mutations;
          // connection status UI and sync diagnostics surface the real error.
        }));
      }
    }
    return QueuedMutationResult(
      mutationUid: mutationUid,
      objectType: objectType,
      localId: effectiveLocalId,
      action: action,
    );
  }

  String? _readString(Map<String, Object?> payload, String key) {
    final value = payload[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }
}
