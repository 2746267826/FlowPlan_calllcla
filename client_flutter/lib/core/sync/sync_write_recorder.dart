import 'dart:async';

import '../offline_queue/offline_mutation.dart';
import '../offline_queue/offline_mutation_store.dart';
import 'sync_object_state_store.dart';
import 'sync_status.dart';

class SyncWriteRecorder {
  SyncWriteRecorder({
    required OfflineMutationStore mutationStore,
    required SyncObjectStateStore stateStore,
  })  : _mutationStore = mutationStore,
        _stateStore = stateStore;

  final OfflineMutationStore _mutationStore;
  final SyncObjectStateStore _stateStore;

  static Future<void> Function()? onMutationRecorded;
  static bool _hookRunning = false;

  Future<void> recordCreate({
    required String objectType,
    required String localId,
    required Map<String, Object?> payload,
    String? uid,
  }) {
    return _record(
      objectType: objectType,
      localId: localId,
      action: OfflineMutationAction.create,
      payload: payload,
      uid: uid,
      changedFields: payload.keys.toList(growable: false),
    );
  }

  Future<void> recordUpdate({
    required String objectType,
    required String localId,
    required Map<String, Object?> payload,
    String? uid,
    List<String>? changedFields,
  }) {
    return _record(
      objectType: objectType,
      localId: localId,
      action: OfflineMutationAction.update,
      payload: payload,
      uid: uid,
      changedFields: changedFields ?? payload.keys.toList(growable: false),
    );
  }

  Future<void> recordDelete({
    required String objectType,
    required String localId,
    required Map<String, Object?> payload,
    String? uid,
  }) {
    return _record(
      objectType: objectType,
      localId: localId,
      action: OfflineMutationAction.delete,
      payload: payload,
      uid: uid,
      changedFields: const <String>['deleted_at'],
    );
  }

  Future<void> _record({
    required String objectType,
    required String localId,
    required OfflineMutationAction action,
    required Map<String, Object?> payload,
    String? uid,
    List<String>? changedFields,
  }) async {
    final current = await _stateStore.getState(
      objectType: objectType,
      localId: localId,
    );
    final serverId = current?.serverId;
    final isCreate = action == OfflineMutationAction.create ||
        serverId == null ||
        serverId.trim().isEmpty;
    final syncState = action == OfflineMutationAction.delete
        ? SyncState.pendingDelete
        : isCreate
            ? SyncState.pendingCreate
            : SyncState.pendingUpdate;

    await _stateStore.markPending(
      objectType: objectType,
      localId: localId,
      state: syncState,
      uid: uid,
      serverId: serverId,
    );
    await _mutationStore.enqueue(
      objectType: objectType,
      localId: localId,
      action: action,
      payload: payload,
      serverId: serverId,
      baseServerVersion: current?.serverVersion,
      changedFields: changedFields,
    );
    final hook = onMutationRecorded;
    if (hook != null && objectType != 'audit_log' && !_hookRunning) {
      _hookRunning = true;
      unawaited(
        hook().whenComplete(() {
          _hookRunning = false;
        }),
      );
    }
  }
}
