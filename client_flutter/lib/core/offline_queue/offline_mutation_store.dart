import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'offline_mutation.dart';

class OfflineMutationStore {
  OfflineMutationStore(
    this._database, {
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  Future<String> enqueue({
    required String objectType,
    required String localId,
    required OfflineMutationAction action,
    required Map<String, Object?> payload,
    String? serverId,
    int? baseServerVersion,
    List<String>? changedFields,
  }) async {
    final mutationUid = _uuid.v4();
    await _database.customStatement(
      '''
      INSERT INTO offline_mutations (
        mutation_uid,
        object_type,
        local_id,
        server_id,
        action,
        base_server_version,
        payload_json,
        changed_fields_json,
        created_at,
        status
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        mutationUid,
        objectType,
        localId,
        serverId,
        action.wireName,
        baseServerVersion,
        jsonEncode(payload),
        changedFields == null ? null : jsonEncode(changedFields),
        DateTime.now().toIso8601String(),
        OfflineMutationStatus.pending.wireName,
      ],
    );
    return mutationUid;
  }

  Future<List<OfflineMutation>> listPending({int limit = 50}) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM offline_mutations
      WHERE status IN ('pending', 'failed')
      ORDER BY id ASC
      LIMIT ?
      ''',
      variables: [Variable<int>(limit)],
    ).get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<void> markSending(List<int> ids) async {
    if (ids.isEmpty) {
      return;
    }
    await _database.transaction(() async {
      for (final id in ids) {
        await _database.customStatement(
          '''
          UPDATE offline_mutations
          SET status = ?, attempts = attempts + 1, last_error = NULL
          WHERE id = ?
          ''',
          [OfflineMutationStatus.sending.wireName, id],
        );
      }
    });
  }

  Future<void> markAckedByMutationUid(String mutationUid) {
    return _database.customStatement(
      '''
      UPDATE offline_mutations
      SET status = ?, last_error = NULL
      WHERE mutation_uid = ?
      ''',
      [OfflineMutationStatus.acked.wireName, mutationUid],
    );
  }

  Future<void> markConflictByMutationUid(String mutationUid, String message) {
    return _database.customStatement(
      '''
      UPDATE offline_mutations
      SET status = ?, last_error = ?
      WHERE mutation_uid = ?
      ''',
      [OfflineMutationStatus.conflict.wireName, message, mutationUid],
    );
  }

  Future<void> markFailed(List<int> ids, Object error) async {
    if (ids.isEmpty) {
      return;
    }
    await _database.transaction(() async {
      for (final id in ids) {
        await _database.customStatement(
          '''
          UPDATE offline_mutations
          SET status = ?, last_error = ?
          WHERE id = ?
          ''',
          [OfflineMutationStatus.failed.wireName, error.toString(), id],
        );
      }
    });
  }

  OfflineMutation _fromRow(QueryRow row) {
    return OfflineMutation(
      id: row.read<int>('id'),
      mutationUid: row.read<String>('mutation_uid'),
      objectType: row.read<String>('object_type'),
      localId: row.read<String>('local_id'),
      serverId: row.data['server_id'] as String?,
      action: OfflineMutationAction.fromWireName(row.read<String>('action')),
      baseServerVersion: row.data['base_server_version'] as int?,
      payloadJson: row.read<String>('payload_json'),
      changedFieldsJson: row.data['changed_fields_json'] as String?,
      createdAt: DateTime.parse(row.read<String>('created_at')),
      attempts: row.read<int>('attempts'),
      lastError: row.data['last_error'] as String?,
      status: OfflineMutationStatus.fromWireName(row.read<String>('status')),
    );
  }
}
