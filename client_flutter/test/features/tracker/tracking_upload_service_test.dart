import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/server_api/tracking_ingest_api.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/tracker/services/tracking_upload_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  String dayKey(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  Future<int> insertActivityRecord(
    AppDatabase db, {
    required DateTime start,
    int durationMinutes = 5,
    String processName = 'Code.exe',
    String windowTitle = 'main.dart',
    String category = 'coding',
  }) async {
    await db.customStatement(
      '''
      INSERT INTO activity_records (
        start_time,
        end_time,
        duration_minutes,
        key_count,
        mouse_clicks,
        mouse_move_px,
        scroll_px,
        process_name,
        window_title,
        category,
        is_auto,
        source
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        start.toIso8601String(),
        start.add(Duration(minutes: durationMinutes)).toIso8601String(),
        durationMinutes,
        12,
        3,
        320,
        240,
        processName,
        windowTitle,
        category,
        1,
        'test',
      ],
    );
    final row =
        await db.customSelect('SELECT last_insert_rowid() AS id').getSingle();
    return row.read<int>('id');
  }

  Future<int> insertTrackedInputEvent(
    AppDatabase db, {
    required DateTime at,
    required int sequenceId,
    String eventUid = 'input-event',
  }) async {
    await db.customStatement(
      '''
      INSERT INTO tracked_input_events (
        event_uid,
        sequence_id,
        occurred_at,
        day_key,
        event_kind,
        record_id,
        process_name,
        class_name,
        window_title,
        category,
        activity_label,
        is_ignored,
        key_code,
        key_label,
        mouse_button,
        wheel_delta,
        delta_x,
        delta_y,
        move_distance,
        event_count,
        token_text,
        payload_json,
        created_at
      ) VALUES (?, ?, ?, ?, ?, NULL, ?, ?, ?, ?, ?, 0, ?, ?, NULL, 0, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        '$eventUid-$sequenceId',
        sequenceId,
        at.toIso8601String(),
        dayKey(at),
        'key_down',
        'Code.exe',
        'Editor',
        'main.dart',
        'coding',
        'Implementation',
        65,
        'A',
        4,
        2,
        0,
        7,
        'a',
        jsonEncode(<String, Object?>{'source': 'test'}),
        DateTime.now().toIso8601String(),
      ],
    );
    final row =
        await db.customSelect('SELECT last_insert_rowid() AS id').getSingle();
    return row.read<int>('id');
  }

  Future<int> insertRawActivityLog(
    AppDatabase db, {
    required DateTime at,
    required String entryUid,
  }) async {
    await db.customStatement(
      '''
      INSERT INTO raw_activity_logs (
        entry_uid,
        occurred_at,
        day_key,
        entry_type,
        record_id,
        process_name,
        window_title,
        category,
        label,
        is_ignored,
        payload_json,
        created_at
      ) VALUES (?, ?, ?, ?, NULL, ?, ?, ?, ?, 0, ?, ?)
      ''',
      <Object?>[
        entryUid,
        at.toIso8601String(),
        dayKey(at),
        'snapshot',
        'Code.exe',
        'main.dart',
        'coding',
        'Implementation',
        jsonEncode(<String, Object?>{'entryUid': entryUid}),
        DateTime.now().toIso8601String(),
      ],
    );
    final row =
        await db.customSelect('SELECT last_insert_rowid() AS id').getSingle();
    return row.read<int>('id');
  }

  TrackingUploadService serviceFor(
    AppDatabase db,
    FakeTrackingIngestApi api,
  ) {
    return TrackingUploadService(
      database: db,
      api: api,
      operationLogs: DataOperationLogRepository(db),
    );
  }

  test('uploads each tracking kind in chunks and advances cursors', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final api = FakeTrackingIngestApi();
    final service = serviceFor(db, api);
    final base = DateTime(2026, 6, 15, 9);

    final activityIds = <int>[
      await insertActivityRecord(db, start: base),
      await insertActivityRecord(db,
          start: base.add(const Duration(minutes: 10))),
      await insertActivityRecord(db,
          start: base.add(const Duration(minutes: 20))),
    ];
    final inputIds = <int>[
      await insertTrackedInputEvent(db, at: base, sequenceId: 1),
      await insertTrackedInputEvent(
        db,
        at: base.add(const Duration(seconds: 1)),
        sequenceId: 2,
      ),
    ];
    final rawId = await insertRawActivityLog(db, at: base, entryUid: 'raw-1');

    final result = await service.uploadPending(limitPerKind: 10, chunkSize: 2);

    expect(result.uploadedBatches, 3);
    expect(result.uploadedRecords, 6);
    expect(
      api.createdBatches.map((batch) => batch.dataKind),
      <String>['activity_record', 'tracked_input_event', 'raw_activity_log'],
    );
    expect(
      api.chunkCalls
          .where((call) => call.batchId == 'batch-activity_record-1')
          .map((call) => call.records.length),
      <int>[2, 1],
    );
    expect(
      api.chunkCalls
          .where((call) => call.batchId == 'batch-tracked_input_event-2')
          .map((call) => call.records.length),
      <int>[2],
    );
    expect(
      api.chunkCalls
          .where((call) => call.batchId == 'batch-raw_activity_log-3')
          .map((call) => call.records.length),
      <int>[1],
    );
    expect(api.completedBatchIds, <String>[
      'batch-activity_record-1',
      'batch-tracked_input_event-2',
      'batch-raw_activity_log-3',
    ]);

    final diagnostics = await service.buildUploadDiagnostics();
    expect(diagnostics['lastActivityRecordId'], activityIds.last);
    expect(diagnostics['lastInputEventId'], inputIds.last);
    expect(diagnostics['lastRawLogId'], rawId);
    expect(diagnostics['pendingActivityRecords'], 0);
    expect(diagnostics['pendingInputEvents'], 0);
    expect(diagnostics['pendingRawLogs'], 0);
    expect(diagnostics['lastCompletedAt'], isNotNull);
    expect(diagnostics['lastError'], isNull);
  });

  test('preserves cursor and records last error when upload fails', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final api = FakeTrackingIngestApi(
      completeResponses: <String, Map<String, dynamic>>{
        'activity_record': <String, dynamic>{
          'ok': false,
          'reason': 'server rejected batch',
        },
      },
    );
    final service = serviceFor(db, api);
    final base = DateTime(2026, 6, 15, 10);

    await insertActivityRecord(db, start: base);

    await expectLater(
      service.uploadPending(limitPerKind: 10, chunkSize: 2),
      throwsA(isA<StateError>()),
    );

    final diagnostics = await service.buildUploadDiagnostics();
    expect(diagnostics['lastActivityRecordId'], 0);
    expect(diagnostics['pendingActivityRecords'], 1);
    expect(
      diagnostics['lastError'].toString(),
      contains('server rejected batch'),
    );

    final logRows = await db.customSelect(
      '''
      SELECT action, metadata_json
      FROM data_operation_logs
      ORDER BY id ASC
      ''',
    ).get();
    expect(logRows.single.read<String>('action'), 'tracking_upload_failed');
    expect(
      logRows.single.read<String>('metadata_json'),
      contains('activity_record'),
    );
  });

  test('does not create upload batches when there is no pending data',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final api = FakeTrackingIngestApi();
    final service = serviceFor(db, api);

    final result = await service.uploadPending(limitPerKind: 10, chunkSize: 2);

    expect(result.uploadedBatches, 0);
    expect(result.uploadedRecords, 0);
    expect(api.createCallCount, 0);
    expect(api.chunkCalls, isEmpty);
    expect(api.completedBatchIds, isEmpty);
    final diagnostics = await service.buildUploadDiagnostics();
    expect(diagnostics['lastCompletedAt'], isNull);
    expect(diagnostics['lastError'], isNull);
    final logs = await db.customSelect('SELECT * FROM data_operation_logs').get();
    expect(logs, isEmpty);
  });

  test('preserves cursor and records failure when a chunk upload fails',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final api = FakeTrackingIngestApi(
      failingChunkKinds: const <String>{'tracked_input_event'},
    );
    final service = serviceFor(db, api);
    final base = DateTime(2026, 6, 15, 12);

    final activityId = await insertActivityRecord(db, start: base);
    await insertTrackedInputEvent(
      db,
      at: base.add(const Duration(minutes: 1)),
      sequenceId: 1,
    );

    await expectLater(
      service.uploadPending(limitPerKind: 10, chunkSize: 2),
      throwsA(isA<StateError>()),
    );

    final diagnostics = await service.buildUploadDiagnostics();
    expect(diagnostics['lastActivityRecordId'], activityId);
    expect(diagnostics['lastInputEventId'], 0);
    expect(diagnostics['pendingActivityRecords'], 0);
    expect(diagnostics['pendingInputEvents'], 1);
    expect(
      diagnostics['lastError'].toString(),
      contains('chunk upload failed'),
    );
    expect(api.completedBatchIds, <String>['batch-activity_record-1']);

    final logRows = await db.customSelect(
      '''
      SELECT action, metadata_json
      FROM data_operation_logs
      ORDER BY id ASC
      ''',
    ).get();
    expect(logRows.map((row) => row.read<String>('action')), <String>[
      'tracking_upload_failed',
    ]);
    expect(
      logRows.single.read<String>('metadata_json'),
      contains('tracked_input_event'),
    );
  });

  test('returns the active upload future for concurrent callers', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final createGate = Completer<void>();
    final api = FakeTrackingIngestApi(createBatchGate: createGate.future);
    final service = serviceFor(db, api);
    final base = DateTime(2026, 6, 15, 11);

    await insertActivityRecord(db, start: base);
    await insertActivityRecord(db,
        start: base.add(const Duration(minutes: 10)));

    final first = service.uploadPending(limitPerKind: 10, chunkSize: 1);
    final second = service.uploadPending(limitPerKind: 10, chunkSize: 1);

    await pumpEventQueue();
    expect(api.createCallCount, 1);

    createGate.complete();
    final results = await Future.wait(<Future<TrackingUploadResult>>[
      first,
      second,
    ]);

    expect(identical(results[0], results[1]), isTrue);
    expect(results.first.uploadedBatches, 1);
    expect(results.first.uploadedRecords, 2);
    expect(api.createdBatches, hasLength(1));
    expect(api.chunkCalls.map((call) => call.records.length), <int>[1, 1]);
  });
}

class FakeTrackingIngestApi implements TrackingIngestApi {
  FakeTrackingIngestApi({
    this.completeResponses = const <String, Map<String, dynamic>>{},
    this.createBatchGate,
    this.failingChunkKinds = const <String>{},
  });

  final Map<String, Map<String, dynamic>> completeResponses;
  final Future<void>? createBatchGate;
  final Set<String> failingChunkKinds;
  final List<FakeCreatedBatch> createdBatches = <FakeCreatedBatch>[];
  final List<FakeChunkCall> chunkCalls = <FakeChunkCall>[];
  final List<String> completedBatchIds = <String>[];
  int createCallCount = 0;

  final Map<String, String> _batchKindsById = <String, String>{};

  @override
  Future<Map<String, dynamic>> createBatch({
    required String batchUid,
    required String dataKind,
    DateTime? startAt,
    DateTime? endAt,
    String compression = 'none',
    List<Map<String, dynamic>> records = const [],
    Map<String, dynamic> metadata = const {},
  }) async {
    createCallCount++;
    final gate = createBatchGate;
    if (gate != null) {
      await gate;
    }
    final batchId = 'batch-$dataKind-${createdBatches.length + 1}';
    _batchKindsById[batchId] = dataKind;
    createdBatches.add(
      FakeCreatedBatch(
        batchUid: batchUid,
        dataKind: dataKind,
        startAt: startAt,
        endAt: endAt,
        metadata: metadata,
      ),
    );
    return <String, dynamic>{'batchId': batchId};
  }

  @override
  Future<Map<String, dynamic>> uploadChunk({
    required String batchId,
    required int chunkIndex,
    List<Map<String, dynamic>> records = const [],
    Uint8List? compressedJsonBytes,
    String? checksum,
  }) async {
    final dataKind = _batchKindsById[batchId];
    if (dataKind != null && failingChunkKinds.contains(dataKind)) {
      throw StateError('chunk upload failed for $dataKind');
    }
    chunkCalls.add(
      FakeChunkCall(
        batchId: batchId,
        chunkIndex: chunkIndex,
        records: records,
      ),
    );
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> completeBatch({
    required String batchId,
    List<Map<String, dynamic>> records = const [],
  }) async {
    completedBatchIds.add(batchId);
    final dataKind = _batchKindsById[batchId];
    final response = completeResponses[dataKind];
    if (response != null) {
      return response;
    }
    final accepted = chunkCalls
        .where((call) => call.batchId == batchId)
        .fold<int>(0, (sum, call) => sum + call.records.length);
    return <String, dynamic>{
      'ok': true,
      'accepted': accepted,
      'rejected': 0,
    };
  }

  @override
  Future<Map<String, dynamic>> summary({DateTime? start, DateTime? end}) async {
    return <String, dynamic>{};
  }
}

class FakeCreatedBatch {
  const FakeCreatedBatch({
    required this.batchUid,
    required this.dataKind,
    required this.startAt,
    required this.endAt,
    required this.metadata,
  });

  final String batchUid;
  final String dataKind;
  final DateTime? startAt;
  final DateTime? endAt;
  final Map<String, dynamic> metadata;
}

class FakeChunkCall {
  const FakeChunkCall({
    required this.batchId,
    required this.chunkIndex,
    required this.records,
  });

  final String batchId;
  final int chunkIndex;
  final List<Map<String, dynamic>> records;
}
