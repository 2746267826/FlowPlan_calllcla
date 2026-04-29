import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../database/app_database.dart';
import 'conflict_snapshot.dart';

class SyncConflictStore {
  SyncConflictStore(
    this._database, {
    Uuid? uuid,
  }) : _uuid = uuid ?? const Uuid();

  final AppDatabase _database;
  final Uuid _uuid;

  Future<String> createConflict(ConflictSnapshot snapshot) async {
    final conflictUid = snapshot.conflictId.isEmpty
        ? _uuid.v4()
        : snapshot.conflictId;
    await _database.customStatement(
      '''
      INSERT INTO sync_conflicts (
        conflict_uid,
        object_type,
        server_id,
        base_version,
        local_version,
        server_version,
        fields_json,
        status,
        created_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(conflict_uid) DO UPDATE SET
        fields_json = excluded.fields_json,
        status = excluded.status,
        server_version = excluded.server_version
      ''',
      [
        conflictUid,
        snapshot.objectType,
        snapshot.serverId,
        snapshot.baseVersion,
        snapshot.localVersion,
        snapshot.serverVersion,
        jsonEncode(snapshot.fields.map((field) => field.toJson()).toList()),
        'open',
        DateTime.now().toIso8601String(),
      ],
    );
    return conflictUid;
  }

  Future<List<StoredSyncConflict>> listOpen({int limit = 100}) async {
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM sync_conflicts
      WHERE status = 'open'
      ORDER BY created_at DESC
      LIMIT ?
      ''',
      variables: [Variable<int>(limit)],
    ).get();
    return rows.map(StoredSyncConflict.fromRow).toList(growable: false);
  }

  Future<void> resolve({
    required String conflictUid,
    required Map<String, Object?> resolution,
  }) {
    return _database.customStatement(
      '''
      UPDATE sync_conflicts
      SET status = 'resolved', resolved_at = ?, resolution_json = ?
      WHERE conflict_uid = ?
      ''',
      [
        DateTime.now().toIso8601String(),
        jsonEncode(resolution),
        conflictUid,
      ],
    );
  }
}

class StoredSyncConflict {
  const StoredSyncConflict({
    required this.id,
    required this.conflictUid,
    required this.objectType,
    required this.serverId,
    required this.localVersion,
    required this.serverVersion,
    required this.fieldsJson,
    required this.status,
    required this.createdAt,
    this.localId,
    this.baseVersion,
    this.resolvedAt,
    this.resolutionJson,
  });

  final int id;
  final String conflictUid;
  final String objectType;
  final String? localId;
  final String? serverId;
  final int? baseVersion;
  final int localVersion;
  final int serverVersion;
  final String fieldsJson;
  final String status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final String? resolutionJson;

  factory StoredSyncConflict.fromRow(QueryRow row) {
    return StoredSyncConflict(
      id: row.read<int>('id'),
      conflictUid: row.read<String>('conflict_uid'),
      objectType: row.read<String>('object_type'),
      localId: row.data['local_id'] as String?,
      serverId: row.data['server_id'] as String?,
      baseVersion: row.data['base_version'] as int?,
      localVersion: row.read<int>('local_version'),
      serverVersion: row.read<int>('server_version'),
      fieldsJson: row.read<String>('fields_json'),
      status: row.read<String>('status'),
      createdAt: DateTime.parse(row.read<String>('created_at')),
      resolvedAt: _parseDate(row.data['resolved_at']),
      resolutionJson: row.data['resolution_json'] as String?,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}
