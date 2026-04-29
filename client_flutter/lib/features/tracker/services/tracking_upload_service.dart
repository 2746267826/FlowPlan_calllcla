import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/server_api/tracking_ingest_api.dart';
import '../../audit/data_operation_log_repository.dart';

class TrackingUploadResult {
  const TrackingUploadResult({
    required this.uploadedBatches,
    required this.uploadedRecords,
    required this.details,
  });

  final int uploadedBatches;
  final int uploadedRecords;
  final List<Map<String, Object?>> details;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'uploadedBatches': uploadedBatches,
      'uploadedRecords': uploadedRecords,
      'details': details,
    };
  }
}

class TrackingUploadService {
  TrackingUploadService({
    required AppDatabase database,
    required TrackingIngestApi api,
    required DataOperationLogRepository operationLogs,
  })  : _database = database,
        _api = api,
        _operationLogs = operationLogs;

  static const _lastActivityRecordIdKey =
      'tracking.upload.last_activity_record_id';
  static const _lastInputEventIdKey = 'tracking.upload.last_input_event_id';
  static const _lastRawLogIdKey = 'tracking.upload.last_raw_log_id';
  static const lastCompletedAtKey = 'tracking.upload.last_completed_at';
  static const lastErrorKey = 'tracking.upload.last_error';

  final AppDatabase _database;
  final TrackingIngestApi _api;
  final DataOperationLogRepository _operationLogs;

  Future<TrackingUploadResult> uploadPending({
    int limitPerKind = 500,
    int chunkSize = 200,
  }) async {
    final details = <Map<String, Object?>>[];
    var uploadedBatches = 0;
    var uploadedRecords = 0;

    final kinds = <_TrackingKindExport>[
      await _loadActivityRecords(limitPerKind),
      await _loadTrackedInputEvents(limitPerKind),
      await _loadRawActivityLogs(limitPerKind),
    ];

    for (final export in kinds) {
      if (export.records.isEmpty) {
        continue;
      }
      final detail = await _uploadKind(export, chunkSize: chunkSize);
      details.add(detail);
      uploadedBatches++;
      uploadedRecords += export.records.length;
    }

    if (uploadedBatches > 0) {
      await _database.setSetting(
        lastCompletedAtKey,
        DateTime.now().toIso8601String(),
      );
      await _database.deleteSetting(lastErrorKey);
      await _operationLogs.record(
        actor: 'system',
        action: 'tracking_upload_completed',
        entityType: 'tracking_ingest',
        summary: '追踪缓冲已上传到服务端',
        metadata: <String, Object?>{
          'uploadedBatches': uploadedBatches,
          'uploadedRecords': uploadedRecords,
          'details': details,
        },
      );
    }

    return TrackingUploadResult(
      uploadedBatches: uploadedBatches,
      uploadedRecords: uploadedRecords,
      details: details,
    );
  }

  Future<Map<String, Object?>> _uploadKind(
    _TrackingKindExport export, {
    required int chunkSize,
  }) async {
    final batchUid = 'client-${export.dataKind}-${const Uuid().v4()}';
    final batch = await _api.createBatch(
      batchUid: batchUid,
      dataKind: export.dataKind,
      startAt: export.startAt,
      endAt: export.endAt,
      metadata: <String, dynamic>{
        'source': 'native_client_spool',
        'localLastIdBefore': export.previousLastId,
        'localMaxId': export.maxId,
      },
    );
    final batchPayload = batch['batch'];
    final nestedBatch = batchPayload is Map
        ? Map<String, Object?>.from(batchPayload)
        : const <String, Object?>{};
    final batchId = batch['batchId']?.toString() ??
        batch['id']?.toString() ??
        nestedBatch['batchId']?.toString() ??
        nestedBatch['id']?.toString();
    if (batchId == null || batchId.isEmpty) {
      throw StateError('Tracking ingest batch did not return batchId.');
    }

    final totalChunks = (export.records.length / chunkSize).ceil();
    for (var chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
      final start = chunkIndex * chunkSize;
      final end = math.min(start + chunkSize, export.records.length);
      await _api.uploadChunk(
        batchId: batchId,
        chunkIndex: chunkIndex,
        records: export.records.sublist(start, end),
      );
    }

    final completed = await _api.completeBatch(batchId: batchId);
    await _database.setSetting(export.lastIdKey, export.maxId.toString());

    return <String, Object?>{
      'dataKind': export.dataKind,
      'batchId': batchId,
      'recordCount': export.records.length,
      'maxLocalId': export.maxId,
      'accepted': completed['accepted'],
      'rejected': completed['rejected'],
    };
  }

  Future<_TrackingKindExport> _loadActivityRecords(int limit) async {
    final lastId = await _readLastId(_lastActivityRecordIdKey);
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM activity_records
      WHERE id > ?
      ORDER BY id ASC
      LIMIT ?
      ''',
      variables: [Variable<int>(lastId), Variable<int>(limit)],
    ).get();
    return _TrackingKindExport(
      dataKind: 'activity_record',
      lastIdKey: _lastActivityRecordIdKey,
      previousLastId: lastId,
      rows: rows,
      records: rows.map(_activityRecordToPayload).toList(growable: false),
    );
  }

  Future<_TrackingKindExport> _loadTrackedInputEvents(int limit) async {
    final lastId = await _readLastId(_lastInputEventIdKey);
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM tracked_input_events
      WHERE id > ?
      ORDER BY id ASC
      LIMIT ?
      ''',
      variables: [Variable<int>(lastId), Variable<int>(limit)],
    ).get();
    return _TrackingKindExport(
      dataKind: 'tracked_input_event',
      lastIdKey: _lastInputEventIdKey,
      previousLastId: lastId,
      rows: rows,
      records: rows.map(_trackedInputEventToPayload).toList(growable: false),
    );
  }

  Future<_TrackingKindExport> _loadRawActivityLogs(int limit) async {
    final lastId = await _readLastId(_lastRawLogIdKey);
    final rows = await _database.customSelect(
      '''
      SELECT *
      FROM raw_activity_logs
      WHERE id > ?
      ORDER BY id ASC
      LIMIT ?
      ''',
      variables: [Variable<int>(lastId), Variable<int>(limit)],
    ).get();
    return _TrackingKindExport(
      dataKind: 'raw_activity_log',
      lastIdKey: _lastRawLogIdKey,
      previousLastId: lastId,
      rows: rows,
      records: rows.map(_rawActivityLogToPayload).toList(growable: false),
    );
  }

  Future<int> _readLastId(String key) async {
    final value = await _database.getSetting(key);
    return int.tryParse(value ?? '') ?? 0;
  }

  Map<String, dynamic> _activityRecordToPayload(QueryRow row) {
    final data = row.data;
    final id = _readInt(data['id']) ?? 0;
    final startAt = _readDate(data['start_time']);
    final endAt = _readDate(data['end_time']);
    final durationMinutes = _readInt(data['duration_minutes']) ?? 0;
    return <String, dynamic>{
      'uid': 'activity-record:$id',
      'kind': 'activity_record',
      'objectType': 'activity_record',
      'localId': id.toString(),
      if (startAt != null) 'startTime': startAt.toIso8601String(),
      if (endAt != null) 'endTime': endAt.toIso8601String(),
      'durationSeconds': durationMinutes * 60,
      'processName': data['process_name'],
      'windowTitle': data['window_title'],
      'packageName': data['package_name'],
      'category': data['category'],
      'linkedTaskId': data['linked_task_id'],
      'isAuto': _readBool(data['is_auto']),
      'source': data['source'],
      'metadata': <String, Object?>{
        'keyCount': data['key_count'],
        'mouseClicks': data['mouse_clicks'],
        'mouseMovePx': data['mouse_move_px'],
        'scrollPx': data['scroll_px'],
        'manualLabel': data['manual_label'],
        'deviceId': data['device_id'],
        'platform': data['platform'],
      },
    };
  }

  Map<String, dynamic> _trackedInputEventToPayload(QueryRow row) {
    final data = row.data;
    final id = _readInt(data['id']) ?? 0;
    final occurredAt = _readDate(data['occurred_at']);
    return <String, dynamic>{
      'uid': data['event_uid']?.toString() ?? 'tracked-input-event:$id',
      'kind': 'tracked_input_event',
      'objectType': 'tracked_input_event',
      'localId': id.toString(),
      if (occurredAt != null) 'timestamp': occurredAt.toIso8601String(),
      if (occurredAt != null) 'occurredAt': occurredAt.toIso8601String(),
      'eventKind': data['event_kind'],
      'processName': data['process_name'],
      'className': data['class_name'],
      'windowTitle': data['window_title'],
      'category': data['category'],
      'activityLabel': data['activity_label'],
      'isIgnored': _readBool(data['is_ignored']),
      'metadata': <String, Object?>{
        'sequenceId': data['sequence_id'],
        'recordId': data['record_id'],
        'keyCode': data['key_code'],
        'keyLabel': data['key_label'],
        'mouseButton': data['mouse_button'],
        'wheelDelta': data['wheel_delta'],
        'deltaX': data['delta_x'],
        'deltaY': data['delta_y'],
        'moveDistance': data['move_distance'],
        'eventCount': data['event_count'],
        'tokenText': data['token_text'],
        'payload': _decodeJsonMap(data['payload_json']),
      },
    };
  }

  Map<String, dynamic> _rawActivityLogToPayload(QueryRow row) {
    final data = row.data;
    final id = _readInt(data['id']) ?? 0;
    final occurredAt = _readDate(data['occurred_at']);
    return <String, dynamic>{
      'uid': data['entry_uid']?.toString() ?? 'raw-activity-log:$id',
      'kind': 'raw_activity_log',
      'objectType': 'raw_activity_log',
      'localId': id.toString(),
      if (occurredAt != null) 'timestamp': occurredAt.toIso8601String(),
      if (occurredAt != null) 'occurredAt': occurredAt.toIso8601String(),
      'entryType': data['entry_type'],
      'processName': data['process_name'],
      'windowTitle': data['window_title'],
      'category': data['category'],
      'label': data['label'],
      'isIgnored': _readBool(data['is_ignored']),
      'metadata': <String, Object?>{
        'recordId': data['record_id'],
        'payload': _decodeJsonMap(data['payload_json']),
      },
    };
  }

  static int? _readInt(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString());
  }

  static bool _readBool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    final text = value?.toString().toLowerCase();
    return text == 'true' || text == '1';
  }

  static DateTime? _readDate(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is int) {
      final milliseconds = value.abs() < 100000000000
          ? value * 1000
          : value;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds);
    }
    return DateTime.tryParse(value.toString());
  }

  static Map<String, Object?> _decodeJsonMap(Object? value) {
    if (value == null) {
      return const <String, Object?>{};
    }
    try {
      final decoded = jsonDecode(value.toString());
      if (decoded is Map) {
        return Map<String, Object?>.from(decoded);
      }
    } catch (_) {
      // Keep malformed source payloads from blocking the whole ingest batch.
    }
    return const <String, Object?>{};
  }
}

class _TrackingKindExport {
  _TrackingKindExport({
    required this.dataKind,
    required this.lastIdKey,
    required this.previousLastId,
    required this.rows,
    required this.records,
  });

  final String dataKind;
  final String lastIdKey;
  final int previousLastId;
  final List<QueryRow> rows;
  final List<Map<String, dynamic>> records;

  int get maxId {
    var result = previousLastId;
    for (final row in rows) {
      final value = TrackingUploadService._readInt(row.data['id']);
      if (value != null && value > result) {
        result = value;
      }
    }
    return result;
  }

  DateTime? get startAt => _dateRange.$1;

  DateTime? get endAt => _dateRange.$2;

  (DateTime?, DateTime?) get _dateRange {
    DateTime? start;
    DateTime? end;
    for (final record in records) {
      final rawStart = record['startTime'] ?? record['timestamp'];
      final rawEnd = record['endTime'] ?? record['occurredAt'] ?? rawStart;
      final startDate = rawStart == null
          ? null
          : DateTime.tryParse(rawStart.toString());
      final endDate =
          rawEnd == null ? null : DateTime.tryParse(rawEnd.toString());
      if (startDate != null && (start == null || startDate.isBefore(start))) {
        start = startDate;
      }
      if (endDate != null && (end == null || endDate.isAfter(end))) {
        end = endDate;
      }
    }
    return (start, end);
  }
}
