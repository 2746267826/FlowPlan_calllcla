import 'dart:convert';

import '../server_api/api_client.dart';
import '../server_api/request_context.dart';
import '../sync/conflict_snapshot.dart';
import '../sync/sync_conflict_store.dart';
import '../sync/sync_object_state_store.dart';
import '../sync/sync_result.dart';
import 'offline_mutation.dart';
import 'offline_mutation_store.dart';

class OfflineMutationRunner {
  OfflineMutationRunner(
    this._store, {
    SyncObjectStateStore? stateStore,
    SyncConflictStore? conflictStore,
    RequestContext? requestContext,
    String Function()? clientBatchIdFactory,
  })  : _stateStore = stateStore,
        _conflictStore = conflictStore,
        _requestContext = requestContext,
        _clientBatchIdFactory = clientBatchIdFactory;

  final OfflineMutationStore _store;
  final SyncObjectStateStore? _stateStore;
  final SyncConflictStore? _conflictStore;
  final RequestContext? _requestContext;
  final String Function()? _clientBatchIdFactory;

  Future<ServerSyncResult> pushPending(ApiClient apiClient) async {
    final mutations = await _store.listPending();
    if (mutations.isEmpty) {
      return const ServerSyncResult(
        acceptedCount: 0,
        conflictCount: 0,
        rejectedCount: 0,
        pendingCount: 0,
      );
    }

    await _store.markSending(mutations.map((mutation) => mutation.id).toList());
    final mutationByUid = {
      for (final mutation in mutations) mutation.mutationUid: mutation,
    };

    try {
      final response = await apiClient.postJson(
        '/sync/push',
        body: {
          if (_requestContext != null) ..._requestContext.toJson(),
          if (_clientBatchIdFactory != null)
            'clientBatchId': _clientBatchIdFactory(),
          'mutations': mutations.map(_toPayload).toList(growable: false),
        },
      );
      final accepted = _list(response['accepted']);
      final conflicts = _list(response['conflicts']);
      final rejected = _list(response['rejected']);

      for (final item in accepted) {
        final mutationUid = item['mutationUid'] as String?;
        if (mutationUid != null) {
          await _store.markAckedByMutationUid(mutationUid);
          final mutation = mutationByUid[mutationUid];
          final serverId = item['serverId'] as String?;
          if (mutation != null && serverId != null && serverId.isNotEmpty) {
            await _stateStore?.markSynced(
              objectType: mutation.objectType,
              localId: mutation.localId,
              serverId: serverId,
              serverVersion: (item['serverVersion'] as int?) ?? 1,
            );
          }
        }
      }
      for (final item in conflicts) {
        final mutationUid = item['mutationUid'] as String?;
        if (mutationUid != null) {
          await _store.markConflictByMutationUid(
            mutationUid,
            'Server reported conflict',
          );
          final mutation = mutationByUid[mutationUid];
          await _storeConflict(item, mutation);
        }
      }
      for (final item in rejected) {
        final mutationUid = item['mutationUid'] as String?;
        if (mutationUid != null) {
          final reason = item['reason'] ?? 'Server rejected mutation';
          await _store.markFailedByMutationUid(mutationUid, reason);
          final mutation = mutationByUid[mutationUid];
          if (mutation != null) {
            await _stateStore?.markFailed(
              objectType: mutation.objectType,
              localId: mutation.localId,
              error: reason,
            );
          }
        }
      }

      return ServerSyncResult(
        acceptedCount: accepted.length,
        conflictCount: conflicts.length,
        rejectedCount: rejected.length,
        pendingCount: mutations.length,
      );
    } catch (error) {
      await _store.markFailed(
        mutations.map((mutation) => mutation.id).toList(),
        error,
      );
      for (final mutation in mutations) {
        await _stateStore?.markFailed(
          objectType: mutation.objectType,
          localId: mutation.localId,
          error: error,
        );
      }
      rethrow;
    }
  }

  Map<String, Object?> _toPayload(OfflineMutation mutation) {
    final payload = jsonDecode(mutation.payloadJson);
    return {
      'mutationUid': mutation.mutationUid,
      'objectType': mutation.objectType,
      'localId': mutation.localId,
      'serverId': mutation.serverId,
      'uid': _uidFromPayload(payload),
      'action': mutation.action.wireName,
      'baseServerVersion': mutation.baseServerVersion,
      'changedFields': _decodeChangedFields(mutation.changedFieldsJson),
      'payload': payload,
    };
  }

  String? _uidFromPayload(Object? payload) {
    if (payload is Map) {
      final value = payload['uid'];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  List<String>? _decodeChangedFields(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return decoded.whereType<String>().toList(growable: false);
    }
    return null;
  }

  List<Map<String, dynamic>> _list(Object? raw) {
    if (raw is! List) {
      return const <Map<String, dynamic>>[];
    }
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  Future<void> _storeConflict(
    Map<String, dynamic> item,
    OfflineMutation? mutation,
  ) async {
    final conflictStore = _conflictStore;
    if (conflictStore == null) {
      return;
    }

    final objectType =
        (item['objectType'] as String?) ?? mutation?.objectType ?? 'unknown';
    final serverId = (item['serverId'] as String?) ?? '';
    final serverVersion = (item['serverVersion'] as int?) ?? 1;
    final localVersion = (item['localVersion'] as int?) ?? 1;

    await conflictStore.createConflict(
      ConflictSnapshot(
        conflictId: (item['conflictId'] as String?) ?? '',
        objectType: objectType,
        serverId: serverId,
        baseVersion: item['baseVersion'] as int?,
        localVersion: localVersion,
        serverVersion: serverVersion,
        fields: _conflictFields(item['fields']),
      ),
    );

    if (mutation != null && serverId.isNotEmpty) {
      await _stateStore?.markConflict(
        objectType: objectType,
        localId: mutation.localId,
        serverId: serverId,
        serverVersion: serverVersion,
        error: 'Server reported conflict',
      );
    }
  }

  List<ConflictFieldSnapshot> _conflictFields(Object? raw) {
    if (raw is! List) {
      return const <ConflictFieldSnapshot>[];
    }
    return raw.whereType<Map>().map((field) {
      final map = Map<String, dynamic>.from(field);
      return ConflictFieldSnapshot(
        field: (map['field'] as String?) ?? 'unknown',
        base: map['base'],
        local: map['local'],
        server: map['server'],
      );
    }).toList(growable: false);
  }
}
