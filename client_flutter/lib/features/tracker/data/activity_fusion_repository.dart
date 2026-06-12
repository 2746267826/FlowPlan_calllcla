import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_object_registry.dart';
import '../../../core/sync/sync_write_recorder.dart';
import '../../audit/data_operation_log_repository.dart';

class ActivitySegment {
  const ActivitySegment({
    required this.id,
    required this.segmentUid,
    required this.startAt,
    required this.endAt,
    required this.primaryProcessName,
    required this.primaryWindowTitle,
    required this.category,
    required this.label,
    required this.sourceRecordIdsJson,
    required this.evidenceJson,
    required this.confidence,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String segmentUid;
  final DateTime startAt;
  final DateTime endAt;
  final String? primaryProcessName;
  final String? primaryWindowTitle;
  final String? category;
  final String? label;
  final String sourceRecordIdsJson;
  final String evidenceJson;
  final double confidence;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get durationMinutes => endAt.difference(startAt).inMinutes;
  List<int> get sourceRecordIds {
    final decoded = _decodeJson(sourceRecordIdsJson);
    if (decoded is! List) {
      return const <int>[];
    }
    return decoded.whereType<num>().map((item) => item.toInt()).toList();
  }

  Map<String, Object?> get evidence => _decodeJsonMap(evidenceJson);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'segmentUid': segmentUid,
      'startAt': startAt.toIso8601String(),
      'endAt': endAt.toIso8601String(),
      'primaryProcessName': primaryProcessName,
      'primaryWindowTitle': primaryWindowTitle,
      'category': category,
      'label': label,
      'sourceRecordIdsJson': sourceRecordIdsJson,
      'evidenceJson': evidenceJson,
      'confidence': confidence,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ActivitySegment.fromRow(QueryRow row) {
    return ActivitySegment(
      id: row.read<int>('id'),
      segmentUid: row.read<String>('segment_uid'),
      startAt: DateTime.parse(row.read<String>('start_at')),
      endAt: DateTime.parse(row.read<String>('end_at')),
      primaryProcessName: row.data['primary_process_name'] as String?,
      primaryWindowTitle: row.data['primary_window_title'] as String?,
      category: row.data['category'] as String?,
      label: row.data['label'] as String?,
      sourceRecordIdsJson: row.read<String>('source_record_ids_json'),
      evidenceJson: row.read<String>('evidence_json'),
      confidence: (row.data['confidence'] as num).toDouble(),
      status: row.read<String>('status'),
      createdAt: DateTime.parse(row.read<String>('created_at')),
      updatedAt: DateTime.parse(row.read<String>('updated_at')),
    );
  }
}

class ActivityInterpretation {
  const ActivityInterpretation({
    required this.id,
    required this.interpretationUid,
    required this.segmentId,
    required this.summary,
    required this.inferredProject,
    required this.inferredDocument,
    required this.inferredTaskId,
    required this.confidence,
    required this.evidenceJson,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String interpretationUid;
  final int segmentId;
  final String summary;
  final String? inferredProject;
  final String? inferredDocument;
  final int? inferredTaskId;
  final double confidence;
  final String evidenceJson;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> get evidence => _decodeJsonMap(evidenceJson);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'interpretationUid': interpretationUid,
      'segmentId': segmentId,
      'summary': summary,
      'inferredProject': inferredProject,
      'inferredDocument': inferredDocument,
      'inferredTaskId': inferredTaskId,
      'confidence': confidence,
      'evidenceJson': evidenceJson,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ActivityInterpretation.fromRow(QueryRow row) {
    return ActivityInterpretation(
      id: row.read<int>('id'),
      interpretationUid: row.read<String>('interpretation_uid'),
      segmentId: row.read<int>('segment_id'),
      summary: row.read<String>('summary'),
      inferredProject: row.data['inferred_project'] as String?,
      inferredDocument: row.data['inferred_document'] as String?,
      inferredTaskId: row.data['inferred_task_id'] as int?,
      confidence: (row.data['confidence'] as num).toDouble(),
      evidenceJson: row.read<String>('evidence_json'),
      status: row.read<String>('status'),
      createdAt: DateTime.parse(row.read<String>('created_at')),
      updatedAt: DateTime.parse(row.read<String>('updated_at')),
    );
  }
}

class TaskWorkLog {
  const TaskWorkLog({
    required this.id,
    required this.workUid,
    required this.taskId,
    required this.segmentId,
    required this.actualId,
    required this.startAt,
    required this.endAt,
    required this.durationMinutes,
    required this.confidence,
    required this.sourceType,
    required this.evidenceJson,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String workUid;
  final int taskId;
  final int? segmentId;
  final int? actualId;
  final DateTime startAt;
  final DateTime endAt;
  final int durationMinutes;
  final double confidence;
  final String sourceType;
  final String evidenceJson;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> get evidence => _decodeJsonMap(evidenceJson);

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'workUid': workUid,
      'taskId': taskId,
      'segmentId': segmentId,
      'actualId': actualId,
      'startAt': startAt.toIso8601String(),
      'endAt': endAt.toIso8601String(),
      'durationMinutes': durationMinutes,
      'confidence': confidence,
      'sourceType': sourceType,
      'evidenceJson': evidenceJson,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory TaskWorkLog.fromRow(QueryRow row) {
    return TaskWorkLog(
      id: row.read<int>('id'),
      workUid: row.read<String>('work_uid'),
      taskId: row.read<int>('task_id'),
      segmentId: row.data['segment_id'] as int?,
      actualId: row.data['actual_id'] as int?,
      startAt: DateTime.parse(row.read<String>('start_at')),
      endAt: DateTime.parse(row.read<String>('end_at')),
      durationMinutes: row.read<int>('duration_minutes'),
      confidence: (row.data['confidence'] as num).toDouble(),
      sourceType: row.read<String>('source_type'),
      evidenceJson: row.read<String>('evidence_json'),
      status: row.read<String>('status'),
      createdAt: DateTime.parse(row.read<String>('created_at')),
      updatedAt: DateTime.parse(row.read<String>('updated_at')),
    );
  }
}

class ActivityFusionRepository {
  ActivityFusionRepository(
    this._db, [
    this._operationLogs,
    this._syncWriteRecorder,
  ]);

  final AppDatabase _db;
  final DataOperationLogRepository? _operationLogs;
  final SyncWriteRecorder? _syncWriteRecorder;
  final Uuid _uuid = const Uuid();

  Future<void> replaceSegmentsForRange({
    required DateTime start,
    required DateTime end,
    required List<ActivitySegmentDraft> segments,
  }) async {
    await _db.transaction(() async {
      await _db.customStatement(
        '''
        DELETE FROM task_work_logs
        WHERE segment_id IN (
          SELECT id FROM activity_segments
          WHERE start_at < ? AND end_at > ? AND status <> 'confirmed'
        )
        ''',
        [end.toIso8601String(), start.toIso8601String()],
      );
      await _db.customStatement(
        '''
        DELETE FROM activity_interpretations
        WHERE segment_id IN (
          SELECT id FROM activity_segments
          WHERE start_at < ? AND end_at > ? AND status <> 'confirmed'
        )
        ''',
        [end.toIso8601String(), start.toIso8601String()],
      );
      await _db.customStatement(
        '''
        DELETE FROM activity_segments
        WHERE start_at < ? AND end_at > ? AND status <> 'confirmed'
        ''',
        [end.toIso8601String(), start.toIso8601String()],
      );

      for (final draft in segments) {
        await insertSegment(draft, sync: true, audit: false);
      }
    });

    await _operationLogs?.record(
      actor: 'system',
      action: 'rebuild_activity_segments',
      entityType: 'activity_segment',
      summary: '重建活动片段 ${segments.length} 条',
      metadata: <String, Object?>{
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'count': segments.length,
      },
    );
  }

  Future<ActivitySegment> insertSegment(
    ActivitySegmentDraft draft, {
    bool sync = true,
    bool audit = true,
  }) async {
    final now = DateTime.now();
    await _db.customStatement(
      '''
      INSERT INTO activity_segments (
        segment_uid,
        start_at,
        end_at,
        primary_process_name,
        primary_window_title,
        category,
        label,
        source_record_ids_json,
        evidence_json,
        confidence,
        status,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        _uuid.v4(),
        draft.startAt.toIso8601String(),
        draft.endAt.toIso8601String(),
        draft.primaryProcessName,
        draft.primaryWindowTitle,
        draft.category,
        draft.label,
        jsonEncode(draft.sourceRecordIds),
        jsonEncode(draft.evidence),
        draft.confidence.clamp(0, 1).toDouble(),
        draft.status,
        now.toIso8601String(),
        now.toIso8601String(),
      ],
    );
    final segment =
        ActivitySegment.fromRow(await _lastRow('activity_segments'));
    if (audit) {
      await _operationLogs?.record(
        actor: 'system',
        action: 'create_activity_segment',
        entityType: 'activity_segment',
        entityId: segment.id.toString(),
        summary:
            '生成活动片段「${segment.label ?? segment.category ?? segment.primaryProcessName ?? '未分类'}」',
        after: segment.toJson(),
      );
    }
    if (sync) {
      await _syncWriteRecorder?.recordCreate(
        objectType: SyncObjectType.activitySegment.key,
        localId: segment.id.toString(),
        uid: segment.segmentUid,
        payload: segment.toJson(),
      );
    }
    return segment;
  }

  Future<ActivitySegment?> getSegmentById(int id) async {
    final row = await _db.customSelect(
      'SELECT * FROM activity_segments WHERE id = ? LIMIT 1',
      variables: [Variable<int>(id)],
    ).getSingleOrNull();
    return row == null ? null : ActivitySegment.fromRow(row);
  }

  Future<void> updateSegmentStatus(
    int id, {
    required String status,
    String actor = 'user',
  }) async {
    final before = await getSegmentById(id);
    if (before == null) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    await _db.customStatement(
      '''
      UPDATE activity_segments
      SET status = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [status, now, id],
    );
    final after = await getSegmentById(id);
    if (after == null) {
      return;
    }
    await _operationLogs?.record(
      actor: actor,
      action: 'update_activity_segment_status',
      entityType: 'activity_segment',
      entityId: id.toString(),
      summary: '更新活动片段状态为 $status',
      before: before.toJson(),
      after: after.toJson(),
    );
    await _syncWriteRecorder?.recordUpdate(
      objectType: SyncObjectType.activitySegment.key,
      localId: after.id.toString(),
      uid: after.segmentUid,
      payload: after.toJson(),
      changedFields: const <String>['status', 'updatedAt'],
    );
  }

  Future<ActivityInterpretation> insertInterpretation({
    required int segmentId,
    required String summary,
    String? inferredProject,
    String? inferredDocument,
    int? inferredTaskId,
    required double confidence,
    Map<String, Object?> evidence = const <String, Object?>{},
    String status = 'candidate',
  }) async {
    final now = DateTime.now();
    await _db.customStatement(
      '''
      INSERT INTO activity_interpretations (
        interpretation_uid,
        segment_id,
        summary,
        inferred_project,
        inferred_document,
        inferred_task_id,
        confidence,
        evidence_json,
        status,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        _uuid.v4(),
        segmentId,
        summary,
        inferredProject,
        inferredDocument,
        inferredTaskId,
        confidence.clamp(0, 1).toDouble(),
        jsonEncode(evidence),
        status,
        now.toIso8601String(),
        now.toIso8601String(),
      ],
    );
    final row = await _lastRow('activity_interpretations');
    final interpretation = ActivityInterpretation.fromRow(row);
    await _operationLogs?.record(
      actor: 'system',
      action: 'create_activity_interpretation',
      entityType: 'activity_interpretation',
      entityId: interpretation.id.toString(),
      summary: '生成活动理解：${interpretation.summary}',
      after: interpretation.toJson(),
    );
    await _syncWriteRecorder?.recordCreate(
      objectType: SyncObjectType.activityInterpretation.key,
      localId: interpretation.id.toString(),
      uid: interpretation.interpretationUid,
      payload: interpretation.toJson(),
    );
    return interpretation;
  }

  Future<void> updateInterpretationsStatusForSegment(
    int segmentId, {
    required String status,
    String actor = 'user',
  }) async {
    final beforeRows = await _db.customSelect(
      '''
      SELECT *
      FROM activity_interpretations
      WHERE segment_id = ?
      ''',
      variables: [Variable<int>(segmentId)],
    ).get();
    final before = beforeRows.map(ActivityInterpretation.fromRow).toList();
    final now = DateTime.now().toIso8601String();
    await _db.customStatement(
      '''
      UPDATE activity_interpretations
      SET status = ?,
          updated_at = ?
      WHERE segment_id = ?
      ''',
      [status, now, segmentId],
    );
    await _operationLogs?.record(
      actor: actor,
      action: 'update_activity_interpretation_status',
      entityType: 'activity_interpretation',
      summary: '更新片段 $segmentId 的活动理解状态为 $status',
      metadata: <String, Object?>{
        'segmentId': segmentId,
        'status': status,
      },
    );
    final afterRows = await _db.customSelect(
      '''
      SELECT *
      FROM activity_interpretations
      WHERE segment_id = ?
      ''',
      variables: [Variable<int>(segmentId)],
    ).get();
    final afterById = <int, ActivityInterpretation>{
      for (final row in afterRows)
        ActivityInterpretation.fromRow(row).id:
            ActivityInterpretation.fromRow(row),
    };
    for (final item in before) {
      final updated = afterById[item.id];
      if (updated == null) {
        continue;
      }
      await _syncWriteRecorder?.recordUpdate(
        objectType: SyncObjectType.activityInterpretation.key,
        localId: updated.id.toString(),
        uid: updated.interpretationUid,
        payload: updated.toJson(),
        changedFields: const <String>['status', 'updatedAt'],
      );
    }
  }

  Future<TaskWorkLog> insertTaskWorkLog({
    required int taskId,
    int? segmentId,
    int? actualId,
    required DateTime startAt,
    required DateTime endAt,
    required double confidence,
    required String sourceType,
    Map<String, Object?> evidence = const <String, Object?>{},
    String status = 'candidate',
  }) async {
    final now = DateTime.now();
    final duration =
        endAt.difference(startAt).inMinutes.clamp(0, 1 << 31).toInt();
    await _db.customStatement(
      '''
      INSERT INTO task_work_logs (
        work_uid,
        task_id,
        segment_id,
        actual_id,
        start_at,
        end_at,
        duration_minutes,
        confidence,
        source_type,
        evidence_json,
        status,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        _uuid.v4(),
        taskId,
        segmentId,
        actualId,
        startAt.toIso8601String(),
        endAt.toIso8601String(),
        duration,
        confidence.clamp(0, 1).toDouble(),
        sourceType,
        jsonEncode(evidence),
        status,
        now.toIso8601String(),
        now.toIso8601String(),
      ],
    );
    final row = await _lastRow('task_work_logs');
    final workLog = TaskWorkLog.fromRow(row);
    await _operationLogs?.record(
      actor: 'system',
      action: 'create_task_work_log',
      entityType: 'task_work_log',
      entityId: workLog.id.toString(),
      summary: '生成任务实际投入 ${workLog.durationMinutes} 分钟',
      after: workLog.toJson(),
    );
    await _syncWriteRecorder?.recordCreate(
      objectType: SyncObjectType.taskWorkLog.key,
      localId: workLog.id.toString(),
      uid: workLog.workUid,
      payload: workLog.toJson(),
    );
    return workLog;
  }

  Future<List<TaskWorkLog>> listTaskWorkLogsForSegment(
    int segmentId, {
    int limit = 200,
    int offset = 0,
  }) async {
    final normalizedLimit = limit.clamp(1, 1000).toInt();
    final normalizedOffset = offset < 0 ? 0 : offset;
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM task_work_logs
      WHERE segment_id = ?
      ORDER BY start_at ASC
      LIMIT ? OFFSET ?
      ''',
      variables: [
        Variable<int>(segmentId),
        Variable<int>(normalizedLimit),
        Variable<int>(normalizedOffset),
      ],
    ).get();
    return rows.map(TaskWorkLog.fromRow).toList();
  }

  Future<TaskWorkLog> upsertConfirmedTaskWorkLogForSegment({
    required int taskId,
    required int segmentId,
    required int actualId,
    required DateTime startAt,
    required DateTime endAt,
    required double confidence,
    required Map<String, Object?> evidence,
    String actor = 'user',
  }) async {
    final existingRows = await _db.customSelect(
      '''
      SELECT *
      FROM task_work_logs
      WHERE task_id = ? AND segment_id = ?
      ORDER BY created_at DESC
      LIMIT 1
      ''',
      variables: [
        Variable<int>(taskId),
        Variable<int>(segmentId),
      ],
    ).get();
    if (existingRows.isEmpty) {
      return insertTaskWorkLog(
        taskId: taskId,
        segmentId: segmentId,
        actualId: actualId,
        startAt: startAt,
        endAt: endAt,
        confidence: confidence,
        sourceType: 'user_confirmed_activity_segment',
        evidence: evidence,
        status: 'confirmed',
      );
    }

    final before = TaskWorkLog.fromRow(existingRows.first);
    final now = DateTime.now().toIso8601String();
    final duration =
        endAt.difference(startAt).inMinutes.clamp(0, 1 << 31).toInt();
    await _db.customStatement(
      '''
      UPDATE task_work_logs
      SET actual_id = ?,
          start_at = ?,
          end_at = ?,
          duration_minutes = ?,
          confidence = ?,
          source_type = ?,
          evidence_json = ?,
          status = ?,
          updated_at = ?
      WHERE id = ?
      ''',
      [
        actualId,
        startAt.toIso8601String(),
        endAt.toIso8601String(),
        duration,
        confidence.clamp(0, 1).toDouble(),
        'user_confirmed_activity_segment',
        jsonEncode(evidence),
        'confirmed',
        now,
        before.id,
      ],
    );
    final after = TaskWorkLog.fromRow(
      await _db.customSelect(
        'SELECT * FROM task_work_logs WHERE id = ?',
        variables: [Variable<int>(before.id)],
      ).getSingle(),
    );
    await _operationLogs?.record(
      actor: actor,
      action: 'confirm_task_work_log',
      entityType: 'task_work_log',
      entityId: after.id.toString(),
      summary: '确认任务实际投入 ${after.durationMinutes} 分钟',
      before: before.toJson(),
      after: after.toJson(),
    );
    await _syncWriteRecorder?.recordUpdate(
      objectType: SyncObjectType.taskWorkLog.key,
      localId: after.id.toString(),
      uid: after.workUid,
      payload: after.toJson(),
      changedFields: const <String>[
        'actualId',
        'startAt',
        'endAt',
        'durationMinutes',
        'confidence',
        'sourceType',
        'evidenceJson',
        'status',
        'updatedAt',
      ],
    );
    return after;
  }

  Future<void> rejectTaskWorkLogsForSegmentExcept({
    required int segmentId,
    required int taskId,
    String actor = 'user',
  }) async {
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM task_work_logs
      WHERE segment_id = ? AND task_id <> ? AND status <> 'rejected'
      ''',
      variables: [
        Variable<int>(segmentId),
        Variable<int>(taskId),
      ],
    ).get();
    if (rows.isEmpty) {
      return;
    }
    final before = rows.map(TaskWorkLog.fromRow).toList();
    final now = DateTime.now().toIso8601String();
    await _db.customStatement(
      '''
      UPDATE task_work_logs
      SET status = 'rejected',
          updated_at = ?
      WHERE segment_id = ? AND task_id <> ? AND status <> 'rejected'
      ''',
      [now, segmentId, taskId],
    );
    await _operationLogs?.record(
      actor: actor,
      action: 'reject_competing_task_work_logs',
      entityType: 'task_work_log',
      summary: '拒绝同一活动片段下未被确认的其他任务投入候选',
      before: before.map((item) => item.toJson()).toList(),
      metadata: <String, Object?>{
        'segmentId': segmentId,
        'keptTaskId': taskId,
      },
    );
    final afterRows = await _db.customSelect(
      '''
      SELECT *
      FROM task_work_logs
      WHERE segment_id = ? AND task_id <> ?
      ''',
      variables: [
        Variable<int>(segmentId),
        Variable<int>(taskId),
      ],
    ).get();
    for (final row in afterRows) {
      final updated = TaskWorkLog.fromRow(row);
      await _syncWriteRecorder?.recordUpdate(
        objectType: SyncObjectType.taskWorkLog.key,
        localId: updated.id.toString(),
        uid: updated.workUid,
        payload: updated.toJson(),
        changedFields: const <String>['status', 'updatedAt'],
      );
    }
  }

  Future<void> rejectTaskWorkLogsForSegment({
    required int segmentId,
    String actor = 'user',
  }) async {
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM task_work_logs
      WHERE segment_id = ? AND status <> 'rejected'
      ''',
      variables: [Variable<int>(segmentId)],
    ).get();
    if (rows.isEmpty) {
      return;
    }
    final before = rows.map(TaskWorkLog.fromRow).toList();
    final now = DateTime.now().toIso8601String();
    await _db.customStatement(
      '''
      UPDATE task_work_logs
      SET status = 'rejected',
          updated_at = ?
      WHERE segment_id = ? AND status <> 'rejected'
      ''',
      [now, segmentId],
    );
    await _operationLogs?.record(
      actor: actor,
      action: 'reject_task_work_logs_for_segment',
      entityType: 'task_work_log',
      summary: '拒绝活动片段下的任务投入候选',
      before: before.map((item) => item.toJson()).toList(),
      metadata: <String, Object?>{'segmentId': segmentId},
    );
    final afterRows = await _db.customSelect(
      '''
      SELECT *
      FROM task_work_logs
      WHERE segment_id = ?
      ''',
      variables: [Variable<int>(segmentId)],
    ).get();
    for (final row in afterRows) {
      final updated = TaskWorkLog.fromRow(row);
      await _syncWriteRecorder?.recordUpdate(
        objectType: SyncObjectType.taskWorkLog.key,
        localId: updated.id.toString(),
        uid: updated.workUid,
        payload: updated.toJson(),
        changedFields: const <String>['status', 'updatedAt'],
      );
    }
  }

  Future<List<ActivitySegment>> listSegmentsInRange(
    DateTime start,
    DateTime end, {
    int limit = 200,
    int offset = 0,
  }) async {
    final normalizedLimit = limit.clamp(1, 1000).toInt();
    final normalizedOffset = offset < 0 ? 0 : offset;
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM activity_segments
      WHERE start_at < ? AND end_at > ?
      ORDER BY start_at ASC
      LIMIT ? OFFSET ?
      ''',
      variables: [
        Variable<String>(end.toIso8601String()),
        Variable<String>(start.toIso8601String()),
        Variable<int>(normalizedLimit),
        Variable<int>(normalizedOffset),
      ],
    ).get();
    return rows.map(ActivitySegment.fromRow).toList();
  }

  Future<List<ActivityInterpretation>> listInterpretationsForSegment(
    int segmentId, {
    int limit = 200,
    int offset = 0,
  }) async {
    final normalizedLimit = limit.clamp(1, 1000).toInt();
    final normalizedOffset = offset < 0 ? 0 : offset;
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM activity_interpretations
      WHERE segment_id = ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?
      ''',
      variables: [
        Variable<int>(segmentId),
        Variable<int>(normalizedLimit),
        Variable<int>(normalizedOffset),
      ],
    ).get();
    return rows.map(ActivityInterpretation.fromRow).toList();
  }

  Future<List<TaskWorkLog>> listTaskWorkLogsForTask(
    int taskId, {
    int limit = 200,
    int offset = 0,
  }) async {
    final normalizedLimit = limit.clamp(1, 1000).toInt();
    final normalizedOffset = offset < 0 ? 0 : offset;
    final rows = await _db.customSelect(
      '''
      SELECT *
      FROM task_work_logs
      WHERE task_id = ?
      ORDER BY start_at DESC
      LIMIT ? OFFSET ?
      ''',
      variables: [
        Variable<int>(taskId),
        Variable<int>(normalizedLimit),
        Variable<int>(normalizedOffset),
      ],
    ).get();
    return rows.map(TaskWorkLog.fromRow).toList();
  }

  Future<QueryRow> _lastRow(String tableName) async {
    return _db
        .customSelect(
          'SELECT * FROM $tableName WHERE id = last_insert_rowid()',
        )
        .getSingle();
  }
}

class ActivitySegmentDraft {
  const ActivitySegmentDraft({
    required this.startAt,
    required this.endAt,
    required this.sourceRecordIds,
    required this.evidence,
    this.primaryProcessName,
    this.primaryWindowTitle,
    this.category,
    this.label,
    this.confidence = 0.6,
    this.status = 'candidate',
  });

  final DateTime startAt;
  final DateTime endAt;
  final List<int> sourceRecordIds;
  final Map<String, Object?> evidence;
  final String? primaryProcessName;
  final String? primaryWindowTitle;
  final String? category;
  final String? label;
  final double confidence;
  final String status;
}

Object? _decodeJson(String value) {
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

Map<String, Object?> _decodeJsonMap(String value) {
  final decoded = _decodeJson(value);
  if (decoded is! Map) {
    return const <String, Object?>{};
  }
  return decoded.map(
    (key, value) => MapEntry(key.toString(), value),
  );
}
