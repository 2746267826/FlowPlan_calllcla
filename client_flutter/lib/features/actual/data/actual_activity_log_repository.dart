import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_object_registry.dart';
import '../../../core/sync/sync_write_recorder.dart';
import '../../audit/data_operation_log_repository.dart';

class ActualActivityStatus {
  const ActualActivityStatus._();

  static const candidate = 'candidate';
  static const confirmed = 'confirmed';
  static const rejected = 'rejected';
  static const merged = 'merged';
}

class ActualActivitySourceType {
  const ActualActivitySourceType._();

  static const manual = 'manual';
  static const blockingEvent = 'blocking_event';
  static const trackingInference = 'tracking_inference';
  static const aiDraft = 'ai_draft';
}

class ActualActivityLog {
  const ActualActivityLog({
    required this.id,
    required this.actualUid,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.sourceType,
    required this.sourceId,
    required this.sourcePayloadJson,
    required this.confidence,
    required this.status,
    required this.note,
    required this.createdAt,
    required this.updatedAt,
    required this.confirmedAt,
    required this.rejectedAt,
    required this.mergedIntoId,
  });

  final int id;
  final String actualUid;
  final String title;
  final DateTime startAt;
  final DateTime endAt;
  final String sourceType;
  final String? sourceId;
  final String sourcePayloadJson;
  final double confidence;
  final String status;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? confirmedAt;
  final DateTime? rejectedAt;
  final int? mergedIntoId;

  bool get isConfirmed => status == ActualActivityStatus.confirmed;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'actualUid': actualUid,
      'title': title,
      'startAt': startAt.toIso8601String(),
      'endAt': endAt.toIso8601String(),
      'sourceType': sourceType,
      'sourceId': sourceId,
      'sourcePayloadJson': sourcePayloadJson,
      'confidence': confidence,
      'status': status,
      'note': note,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'confirmedAt': confirmedAt?.toIso8601String(),
      'rejectedAt': rejectedAt?.toIso8601String(),
      'mergedIntoId': mergedIntoId,
    };
  }

  factory ActualActivityLog.fromRow(QueryRow row) {
    return ActualActivityLog(
      id: row.read<int>('id'),
      actualUid: row.read<String>('actual_uid'),
      title: row.read<String>('title'),
      startAt: DateTime.parse(row.read<String>('start_at')),
      endAt: DateTime.parse(row.read<String>('end_at')),
      sourceType: row.read<String>('source_type'),
      sourceId: row.data['source_id'] as String?,
      sourcePayloadJson: row.read<String>('source_payload_json'),
      confidence: (row.read<num>('confidence')).toDouble(),
      status: row.read<String>('status'),
      note: row.data['note'] as String?,
      createdAt: DateTime.parse(row.read<String>('created_at')),
      updatedAt: DateTime.parse(row.read<String>('updated_at')),
      confirmedAt: _optionalDate(row.data['confirmed_at']),
      rejectedAt: _optionalDate(row.data['rejected_at']),
      mergedIntoId: row.data['merged_into_id'] as int?,
    );
  }

  static DateTime? _optionalDate(Object? value) {
    if (value is String && value.trim().isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class ActualActivityLogRepository {
  ActualActivityLogRepository(
    this._db, [
    this._operationLogs,
    this._syncWriteRecorder,
  ]);

  final AppDatabase _db;
  final DataOperationLogRepository? _operationLogs;
  final SyncWriteRecorder? _syncWriteRecorder;
  final Uuid _uuid = const Uuid();

  Future<ActualActivityLog?> getById(int id) async {
    final row = await _db.customSelect(
      'SELECT * FROM actual_activity_logs WHERE id = ? LIMIT 1',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    return row == null ? null : ActualActivityLog.fromRow(row);
  }

  Future<ActualActivityLog?> getBySource({
    required String sourceType,
    required String sourceId,
  }) async {
    final row = await _db.customSelect(
      '''
      SELECT *
      FROM actual_activity_logs
      WHERE source_type = ? AND source_id = ?
      ORDER BY created_at DESC
      LIMIT 1
      ''',
      variables: [
        Variable<String>(sourceType),
        Variable<String>(sourceId),
      ],
    ).getSingleOrNull();
    return row == null ? null : ActualActivityLog.fromRow(row);
  }

  Stream<List<ActualActivityLog>> watchInRange(
    DateTime start,
    DateTime end, {
    Iterable<String>? statuses,
  }) {
    final statusList = statuses?.toSet().toList(growable: false);
    final sqlStatuses = statusList == null || statusList.isEmpty
        ? ''
        : 'AND status IN (${List.filled(statusList.length, '?').join(', ')})';
    return _db
        .customSelect(
          '''
          SELECT *
          FROM actual_activity_logs
          WHERE start_at < ? AND end_at > ?
          $sqlStatuses
          ORDER BY start_at ASC
          ''',
          variables: [
            Variable<String>(end.toIso8601String()),
            Variable<String>(start.toIso8601String()),
            for (final status in statusList ?? const <String>[])
              Variable<String>(status),
          ],
          readsFrom: const {},
        )
        .watch()
        .map((rows) => rows.map(ActualActivityLog.fromRow).toList());
  }

  Future<List<ActualActivityLog>> listInRange(
    DateTime start,
    DateTime end, {
    Iterable<String>? statuses,
  }) async {
    final statusList = statuses?.toSet().toList(growable: false);
    final sqlStatuses = statusList == null || statusList.isEmpty
        ? ''
        : 'AND status IN (${List.filled(statusList.length, '?').join(', ')})';
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM actual_activity_logs
      WHERE start_at < ? AND end_at > ?
      $sqlStatuses
      ORDER BY start_at ASC
      ''',
      variables: [
        Variable<String>(end.toIso8601String()),
        Variable<String>(start.toIso8601String()),
        for (final status in statusList ?? const <String>[])
          Variable<String>(status),
      ],
    ).get();
    return rows.map(ActualActivityLog.fromRow).toList();
  }

  Future<bool> hasOverlappingConfirmed(DateTime start, DateTime end) async {
    final row = await _db.customSelect(
      '''
      SELECT COUNT(*) AS count
      FROM actual_activity_logs
      WHERE status = ?
        AND start_at < ?
        AND end_at > ?
      ''',
      variables: [
        const Variable<String>(ActualActivityStatus.confirmed),
        Variable<String>(end.toIso8601String()),
        Variable<String>(start.toIso8601String()),
      ],
    ).getSingle();
    return row.read<int>('count') > 0;
  }

  Future<int> insertCandidate({
    required String title,
    required DateTime startAt,
    required DateTime endAt,
    required String sourceType,
    String? sourceId,
    Map<String, Object?> sourcePayload = const <String, Object?>{},
    double confidence = 0.75,
    String? note,
    String actor = 'system',
  }) async {
    if (!endAt.isAfter(startAt)) {
      throw ArgumentError.value(endAt, 'endAt', 'must be after startAt');
    }

    if (sourceId != null) {
      final existing = await getBySource(
        sourceType: sourceType,
        sourceId: sourceId,
      );
      if (existing != null &&
          existing.status != ActualActivityStatus.rejected) {
        return existing.id;
      }
    }

    final now = DateTime.now();
    await _db.customStatement(
      '''
      INSERT INTO actual_activity_logs (
        actual_uid,
        title,
        start_at,
        end_at,
        source_type,
        source_id,
        source_payload_json,
        confidence,
        status,
        note,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        _uuid.v4(),
        title.trim().isEmpty ? '未命名实际记录' : title.trim(),
        startAt.toIso8601String(),
        endAt.toIso8601String(),
        sourceType,
        sourceId,
        jsonEncode(sourcePayload),
        confidence.clamp(0, 1).toDouble(),
        ActualActivityStatus.candidate,
        note,
        now.toIso8601String(),
        now.toIso8601String(),
      ],
    );
    final id = await _lastInsertedId();
    final created = await getById(id);
    if (created != null) {
      await _recordCreate(actor: actor, actual: created);
      await _syncWriteRecorder?.recordCreate(
        objectType: SyncObjectType.actualActivityLog.key,
        localId: id.toString(),
        uid: created.actualUid,
        payload: created.toJson(),
      );
    }
    return id;
  }

  Future<void> confirm(
    int id, {
    String actor = 'user',
    String? note,
  }) async {
    final before = await getById(id);
    if (before == null) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    await _db.customStatement(
      '''
      UPDATE actual_activity_logs
      SET status = ?,
          note = COALESCE(?, note),
          confirmed_at = ?,
          rejected_at = NULL,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        ActualActivityStatus.confirmed,
        note,
        now,
        now,
        id,
      ],
    );
    await _recordUpdate(
      id,
      actor: actor,
      action: 'confirm',
      summary: '确认实际记录「${before.title}」',
      before: before,
      changedFields: const <String>[
        'status',
        'note',
        'confirmedAt',
        'rejectedAt',
      ],
    );
  }

  Future<void> reject(
    int id, {
    String actor = 'user',
    String? note,
  }) async {
    final before = await getById(id);
    if (before == null) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    await _db.customStatement(
      '''
      UPDATE actual_activity_logs
      SET status = ?,
          note = COALESCE(?, note),
          rejected_at = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        ActualActivityStatus.rejected,
        note,
        now,
        now,
        id,
      ],
    );
    await _recordUpdate(
      id,
      actor: actor,
      action: 'reject',
      summary: '拒绝实际记录候选「${before.title}」',
      before: before,
      changedFields: const <String>['status', 'note', 'rejectedAt'],
    );
  }

  Future<void> mergeInto(
    int id,
    int targetId, {
    String actor = 'user',
  }) async {
    final before = await getById(id);
    if (before == null) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    await _db.customStatement(
      '''
      UPDATE actual_activity_logs
      SET status = ?,
          merged_into_id = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [ActualActivityStatus.merged, targetId, now, id],
    );
    await _recordUpdate(
      id,
      actor: actor,
      action: 'merge',
      summary: '合并实际记录「${before.title}」',
      before: before,
      changedFields: const <String>['status', 'mergedIntoId'],
    );
  }

  Future<int> _lastInsertedId() async {
    final row = await _db.customSelect(
      'SELECT last_insert_rowid() AS id',
    ).getSingle();
    return row.read<int>('id');
  }

  Future<void> _recordCreate({
    required String actor,
    required ActualActivityLog actual,
  }) async {
    await _operationLogs?.record(
      actor: actor,
      action: 'create_candidate',
      entityType: 'actual_activity_log',
      entityId: actual.id.toString(),
      summary: '生成实际记录候选「${actual.title}」',
      after: actual.toJson(),
    );
  }

  Future<void> _recordUpdate(
    int id, {
    required String actor,
    required String action,
    required String summary,
    required ActualActivityLog before,
    required List<String> changedFields,
  }) async {
    final after = await getById(id);
    if (after == null) {
      return;
    }
    await _operationLogs?.record(
      actor: actor,
      action: action,
      entityType: 'actual_activity_log',
      entityId: id.toString(),
      summary: summary,
      before: before.toJson(),
      after: after.toJson(),
    );
    await _syncWriteRecorder?.recordUpdate(
      objectType: SyncObjectType.actualActivityLog.key,
      localId: id.toString(),
      uid: after.actualUid,
      payload: after.toJson(),
      changedFields: changedFields,
    );
  }
}
