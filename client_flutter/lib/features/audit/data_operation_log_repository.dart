import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/sync/sync_object_registry.dart';
import '../../core/sync/sync_write_recorder.dart';

class DataOperationLogRepository {
  DataOperationLogRepository(this._db, [this._syncWriteRecorder]);

  final AppDatabase _db;
  final SyncWriteRecorder? _syncWriteRecorder;

  Future<void> record({
    required String actor,
    required String action,
    required String entityType,
    String? entityId,
    required String summary,
    Object? before,
    Object? after,
    Object? metadata,
  }) async {
    await _db.customStatement(
      '''
      INSERT INTO data_operation_logs (
        occurred_at,
        actor,
        action,
        entity_type,
        entity_id,
        summary,
        before_json,
        after_json,
        metadata_json
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        DateTime.now().toIso8601String(),
        actor,
        action,
        entityType,
        entityId,
        summary,
        _encode(before),
        _encode(after),
        _encode(metadata),
      ],
    );
    final row = await _db.customSelect(
      'SELECT last_insert_rowid() AS id',
    ).getSingle();
    final id = row.read<int>('id');
    await _syncWriteRecorder?.recordCreate(
      objectType: SyncObjectType.auditLog.key,
      localId: id.toString(),
      payload: <String, Object?>{
        'id': id,
        'occurred_at': DateTime.now().toIso8601String(),
        'actor': actor,
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'summary': summary,
        'before_json': _encode(before),
        'after_json': _encode(after),
        'metadata_json': _encode(metadata),
      },
    );
  }

  Future<List<DataOperationLogEntry>> listRecent({int limit = 100}) async {
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM data_operation_logs
      ORDER BY occurred_at DESC
      LIMIT ?
      ''',
      variables: [Variable<int>(limit)],
    ).get();
    return rows.map(DataOperationLogEntry.fromRow).toList();
  }

  String? _encode(Object? value) {
    if (value == null) {
      return null;
    }
    return jsonEncode(value);
  }
}

class DataOperationLogEntry {
  const DataOperationLogEntry({
    required this.id,
    required this.occurredAt,
    required this.actor,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.summary,
    required this.beforeJson,
    required this.afterJson,
    required this.metadataJson,
  });

  final int id;
  final DateTime occurredAt;
  final String actor;
  final String action;
  final String entityType;
  final String? entityId;
  final String summary;
  final String? beforeJson;
  final String? afterJson;
  final String? metadataJson;

  factory DataOperationLogEntry.fromRow(QueryRow row) {
    return DataOperationLogEntry(
      id: row.read<int>('id'),
      occurredAt: DateTime.parse(row.read<String>('occurred_at')),
      actor: row.read<String>('actor'),
      action: row.read<String>('action'),
      entityType: row.read<String>('entity_type'),
      entityId: row.data['entity_id'] as String?,
      summary: row.read<String>('summary'),
      beforeJson: row.data['before_json'] as String?,
      afterJson: row.data['after_json'] as String?,
      metadataJson: row.data['metadata_json'] as String?,
    );
  }
}
