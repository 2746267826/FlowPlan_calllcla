import 'package:drift/drift.dart';

import '../database/app_database.dart';
import 'sync_status.dart';

class SyncObjectStateStore {
  SyncObjectStateStore(this._database);

  final AppDatabase _database;

  Future<SyncObjectState?> getState({
    required String objectType,
    required String localId,
  }) async {
    final row = await _database.customSelect(
      '''
      SELECT *
      FROM sync_object_states
      WHERE object_type = ? AND local_id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(objectType),
        Variable<String>(localId),
      ],
    ).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<SyncObjectState?> getStateByServerId({
    required String objectType,
    required String serverId,
  }) async {
    final row = await _database.customSelect(
      '''
      SELECT *
      FROM sync_object_states
      WHERE object_type = ? AND server_id = ?
      LIMIT 1
      ''',
      variables: [
        Variable<String>(objectType),
        Variable<String>(serverId),
      ],
    ).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  Future<void> markPending({
    required String objectType,
    required String localId,
    required SyncState state,
    String? uid,
    String? serverId,
    String? originDeviceId,
    String? lastModifiedDeviceId,
  }) async {
    final now = DateTime.now().toIso8601String();
    await _database.customStatement(
      '''
      INSERT INTO sync_object_states (
        object_type,
        local_id,
        server_id,
        uid,
        sync_state,
        local_version,
        origin_device_id,
        last_modified_device_id,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?)
      ON CONFLICT(object_type, local_id) DO UPDATE SET
        server_id = COALESCE(excluded.server_id, sync_object_states.server_id),
        uid = COALESCE(excluded.uid, sync_object_states.uid),
        sync_state = excluded.sync_state,
        local_version = sync_object_states.local_version + 1,
        last_modified_device_id = excluded.last_modified_device_id,
        updated_at = excluded.updated_at,
        last_sync_error = NULL
      ''',
      [
        objectType,
        localId,
        serverId,
        uid,
        state.wireName,
        originDeviceId,
        lastModifiedDeviceId,
        now,
        now,
      ],
    );
  }

  Future<void> markSynced({
    required String objectType,
    required String localId,
    required String serverId,
    required int serverVersion,
    String? uid,
  }) {
    final now = DateTime.now().toIso8601String();
    return _database.customStatement(
      '''
      INSERT INTO sync_object_states (
        object_type,
        local_id,
        server_id,
        uid,
        sync_state,
        local_version,
        server_version,
        created_at,
        updated_at,
        last_synced_at
      ) VALUES (?, ?, ?, ?, ?, 1, ?, ?, ?, ?)
      ON CONFLICT(object_type, local_id) DO UPDATE SET
        server_id = excluded.server_id,
        uid = COALESCE(excluded.uid, sync_object_states.uid),
        sync_state = excluded.sync_state,
        server_version = excluded.server_version,
        last_synced_at = excluded.last_synced_at,
        updated_at = excluded.updated_at,
        last_sync_error = NULL
      ''',
      [
        objectType,
        localId,
        serverId,
        uid,
        SyncState.synced.wireName,
        serverVersion,
        now,
        now,
        now,
      ],
    );
  }

  Future<void> markConflict({
    required String objectType,
    required String localId,
    required String serverId,
    required int serverVersion,
    Object? error,
  }) {
    final now = DateTime.now().toIso8601String();
    return _database.customStatement(
      '''
      INSERT INTO sync_object_states (
        object_type,
        local_id,
        server_id,
        sync_state,
        local_version,
        server_version,
        created_at,
        updated_at,
        last_sync_error
      ) VALUES (?, ?, ?, ?, 1, ?, ?, ?, ?)
      ON CONFLICT(object_type, local_id) DO UPDATE SET
        server_id = excluded.server_id,
        sync_state = excluded.sync_state,
        server_version = excluded.server_version,
        updated_at = excluded.updated_at,
        last_sync_error = excluded.last_sync_error
      ''',
      [
        objectType,
        localId,
        serverId,
        SyncState.conflict.wireName,
        serverVersion,
        now,
        now,
        error?.toString(),
      ],
    );
  }

  Future<void> markFailed({
    required String objectType,
    required String localId,
    required Object error,
  }) {
    return _database.customStatement(
      '''
      UPDATE sync_object_states
      SET sync_state = ?, last_sync_error = ?, updated_at = ?
      WHERE object_type = ? AND local_id = ?
      ''',
      [
        SyncState.failed.wireName,
        error.toString(),
        DateTime.now().toIso8601String(),
        objectType,
        localId,
      ],
    );
  }

  Future<void> removeState({
    required String objectType,
    required String localId,
  }) {
    return _database.customStatement(
      '''
      DELETE FROM sync_object_states
      WHERE object_type = ? AND local_id = ?
      ''',
      [objectType, localId],
    );
  }

  Future<List<SyncObjectState>> listByState(
    SyncState state, {
    int limit = 100,
  }) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM sync_object_states
      WHERE sync_state = ?
      ORDER BY updated_at ASC
      LIMIT ?
      ''',
      variables: [
        Variable<String>(state.wireName),
        Variable<int>(limit),
      ],
    ).get();
    return rows.map(_fromRow).toList(growable: false);
  }

  SyncObjectState _fromRow(QueryRow row) {
    return SyncObjectState(
      objectType: row.read<String>('object_type'),
      localId: row.read<String>('local_id'),
      serverId: row.data['server_id'] as String?,
      uid: row.data['uid'] as String?,
      syncState: SyncState.fromWireName(row.read<String>('sync_state')),
      localVersion: row.read<int>('local_version'),
      serverVersion: row.data['server_version'] as int?,
      originDeviceId: row.data['origin_device_id'] as String?,
      lastModifiedDeviceId: row.data['last_modified_device_id'] as String?,
      createdAt: DateTime.parse(row.read<String>('created_at')),
      updatedAt: DateTime.parse(row.read<String>('updated_at')),
      deletedAt: _parseDate(row.data['deleted_at']),
      lastSyncedAt: _parseDate(row.data['last_synced_at']),
      lastSyncError: row.data['last_sync_error'] as String?,
    );
  }

  DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}
