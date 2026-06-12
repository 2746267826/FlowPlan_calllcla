import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/sync/sync_object_registry.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_status.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/tracker/data/activity_fusion_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  ActivitySegmentDraft draft({
    required DateTime start,
    Duration duration = const Duration(minutes: 25),
    List<int> sourceRecordIds = const <int>[101, 102],
    Map<String, Object?> evidence = const <String, Object?>{
      'source': 'manual',
    },
    String? processName = 'Code.exe',
    String? windowTitle = 'activity_fusion_repository.dart - VS Code',
    String? category = 'coding',
    String? label = 'Repository tests',
    double confidence = 0.6,
    String status = 'candidate',
  }) {
    return ActivitySegmentDraft(
      startAt: start,
      endAt: start.add(duration),
      sourceRecordIds: sourceRecordIds,
      evidence: evidence,
      primaryProcessName: processName,
      primaryWindowTitle: windowTitle,
      category: category,
      label: label,
      confidence: confidence,
      status: status,
    );
  }

  Future<int> countRows(
    AppDatabase db,
    String tableName, {
    String? where,
    List<Variable> variables = const <Variable>[],
  }) async {
    final row = await db
        .customSelect(
          'SELECT COUNT(*) AS count FROM $tableName${where == null ? '' : ' WHERE $where'}',
          variables: variables,
        )
        .getSingle();
    return row.read<int>('count');
  }

  Future<void> stampCreatedAt(
    AppDatabase db,
    String tableName,
    int id,
    DateTime createdAt,
  ) {
    return db.customStatement(
      'UPDATE $tableName SET created_at = ?, updated_at = ? WHERE id = ?',
      <Object?>[
        createdAt.toIso8601String(),
        createdAt.toIso8601String(),
        id,
      ],
    );
  }

  group('ActivityFusionRepository deep database behavior', () {
    test(
        'inserts segments with defaults, clamps confidence, queries ranges, and paginates ordering',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActivityFusionRepository(db);
      final base = DateTime(2026, 6, 9, 9);

      final beforeWindow = await repository.insertSegment(
        draft(
          start: base.subtract(const Duration(hours: 2)),
          duration: const Duration(minutes: 30),
          label: 'Before',
        ),
        sync: false,
        audit: false,
      );
      final first = await repository.insertSegment(
        draft(
          start: base.add(const Duration(minutes: 40)),
          label: 'First',
          confidence: -2,
        ),
        sync: false,
        audit: false,
      );
      final second = await repository.insertSegment(
        draft(
          start: base.add(const Duration(minutes: 10)),
          label: 'Second',
          confidence: 2,
        ),
        sync: false,
        audit: false,
      );
      final third = await repository.insertSegment(
        draft(
          start: base.add(const Duration(minutes: 70)),
          label: 'Third',
          processName: null,
          windowTitle: null,
          category: null,
          sourceRecordIds: const <int>[],
          evidence: const <String, Object?>{},
        ),
        sync: false,
        audit: false,
      );
      await repository.insertSegment(
        draft(
          start: base.add(const Duration(hours: 3)),
          label: 'After',
        ),
        sync: false,
        audit: false,
      );

      expect(beforeWindow.durationMinutes, 30);
      expect(first.confidence, 0);
      expect(second.confidence, 1);
      expect(third.status, 'candidate');
      expect(third.sourceRecordIds, isEmpty);
      expect(third.evidence, isEmpty);

      final stored = await repository.getSegmentById(second.id);
      expect(stored?.label, 'Second');
      expect(stored?.sourceRecordIds, <int>[101, 102]);
      expect(stored?.evidence, containsPair('source', 'manual'));
      expect(stored?.toJson(), containsPair('segmentUid', second.segmentUid));

      final inRange = await repository.listSegmentsInRange(
        base,
        base.add(const Duration(hours: 2)),
      );
      expect(
        inRange.map((segment) => segment.label),
        <String>['Second', 'First', 'Third'],
      );

      final page = await repository.listSegmentsInRange(
        base,
        base.add(const Duration(hours: 2)),
        limit: 2,
        offset: 1,
      );
      expect(page.map((segment) => segment.id), <int>[first.id, third.id]);

      final clampedPage = await repository.listSegmentsInRange(
        base,
        base.add(const Duration(hours: 2)),
        limit: 0,
        offset: -100,
      );
      expect(clampedPage.single.id, second.id);
    });

    test(
        'replaceSegmentsForRange deletes overlapping candidates and dependents but preserves confirmed rows',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActivityFusionRepository(db);
      final base = DateTime(2026, 6, 10, 9);

      final overlappingCandidate = await repository.insertSegment(
        draft(start: base.add(const Duration(minutes: 5)), label: 'Candidate'),
        sync: false,
        audit: false,
      );
      final confirmed = await repository.insertSegment(
        draft(
          start: base.add(const Duration(minutes: 15)),
          label: 'Confirmed',
          status: 'confirmed',
        ),
        sync: false,
        audit: false,
      );
      final outside = await repository.insertSegment(
        draft(
          start: base.add(const Duration(hours: 3)),
          label: 'Outside',
        ),
        sync: false,
        audit: false,
      );
      await repository.insertInterpretation(
        segmentId: overlappingCandidate.id,
        summary: 'Candidate interpretation',
        confidence: 0.7,
      );
      await repository.insertTaskWorkLog(
        taskId: 10,
        segmentId: overlappingCandidate.id,
        startAt: overlappingCandidate.startAt,
        endAt: overlappingCandidate.endAt,
        confidence: 0.7,
        sourceType: 'activity_interpretation',
      );
      await repository.insertInterpretation(
        segmentId: confirmed.id,
        summary: 'Confirmed interpretation',
        confidence: 0.8,
      );
      await repository.insertTaskWorkLog(
        taskId: 11,
        segmentId: confirmed.id,
        startAt: confirmed.startAt,
        endAt: confirmed.endAt,
        confidence: 0.8,
        sourceType: 'activity_interpretation',
      );

      await repository.replaceSegmentsForRange(
        start: base,
        end: base.add(const Duration(hours: 1)),
        segments: <ActivitySegmentDraft>[
          draft(start: base.add(const Duration(minutes: 30)), label: 'New A'),
          draft(start: base.add(const Duration(minutes: 45)), label: 'New B'),
        ],
      );

      expect(await repository.getSegmentById(overlappingCandidate.id), isNull);
      expect(await repository.getSegmentById(confirmed.id), isNotNull);
      expect(await repository.getSegmentById(outside.id), isNotNull);
      expect(
        await countRows(
          db,
          'activity_interpretations',
          where: 'segment_id = ?',
          variables: <Variable<Object>>[
            Variable<int>(overlappingCandidate.id),
          ],
        ),
        0,
      );
      expect(
        await countRows(
          db,
          'task_work_logs',
          where: 'segment_id = ?',
          variables: <Variable<Object>>[
            Variable<int>(overlappingCandidate.id),
          ],
        ),
        0,
      );

      final range = await repository.listSegmentsInRange(
        base,
        base.add(const Duration(hours: 1)),
      );
      expect(
        range.map((segment) => segment.label),
        <String>['Confirmed', 'New A', 'New B'],
      );
    });

    test(
        'replaceSegmentsForRange rolls back deletes when a draft has an invalid JSON payload',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActivityFusionRepository(db);
      final base = DateTime(2026, 6, 11, 9);

      final existing = await repository.insertSegment(
        draft(start: base, label: 'Keep on rollback'),
        sync: false,
        audit: false,
      );
      await repository.insertInterpretation(
        segmentId: existing.id,
        summary: 'Still here',
        confidence: 0.7,
      );
      await repository.insertTaskWorkLog(
        taskId: 20,
        segmentId: existing.id,
        startAt: existing.startAt,
        endAt: existing.endAt,
        confidence: 0.7,
        sourceType: 'activity_interpretation',
      );

      await expectLater(
        repository.replaceSegmentsForRange(
          start: base,
          end: base.add(const Duration(hours: 1)),
          segments: <ActivitySegmentDraft>[
            draft(
              start: base.add(const Duration(minutes: 10)),
              evidence: <String, Object?>{'bad': Object()},
            ),
          ],
        ),
        throwsA(isA<JsonUnsupportedObjectError>()),
      );

      expect(await repository.getSegmentById(existing.id), isNotNull);
      expect(
        await countRows(
          db,
          'activity_interpretations',
          where: 'segment_id = ?',
          variables: <Variable<Object>>[Variable<int>(existing.id)],
        ),
        1,
      );
      expect(
        await countRows(
          db,
          'task_work_logs',
          where: 'segment_id = ?',
          variables: <Variable<Object>>[Variable<int>(existing.id)],
        ),
        1,
      );
    });

    test(
        'interpretations insert defaults, clamp confidence, fallback invalid evidence, update status, and page newest first',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActivityFusionRepository(db);
      final base = DateTime(2026, 6, 12, 9);
      final segment = await repository.insertSegment(
        draft(start: base),
        sync: false,
        audit: false,
      );

      final older = await repository.insertInterpretation(
        segmentId: segment.id,
        summary: 'Older',
        inferredProject: 'FlowPlan',
        inferredDocument: 'activity_fusion_repository.dart',
        inferredTaskId: 30,
        confidence: 5,
        evidence: const <String, Object?>{'rank': 1},
      );
      final newer = await repository.insertInterpretation(
        segmentId: segment.id,
        summary: 'Newer',
        confidence: -1,
      );
      await stampCreatedAt(
        db,
        'activity_interpretations',
        older.id,
        base.add(const Duration(minutes: 1)),
      );
      await stampCreatedAt(
        db,
        'activity_interpretations',
        newer.id,
        base.add(const Duration(minutes: 2)),
      );
      await db.customStatement(
        'UPDATE activity_interpretations SET evidence_json = ? WHERE id = ?',
        <Object?>['not-json', newer.id],
      );

      final all = await repository.listInterpretationsForSegment(segment.id);
      expect(all.map((item) => item.summary), <String>['Newer', 'Older']);
      expect(all.first.confidence, 0);
      expect(all.first.evidence, isEmpty);
      expect(all.last.confidence, 1);
      expect(all.last.evidence, containsPair('rank', 1));
      expect(all.last.toJson(), containsPair('summary', 'Older'));

      final page = await repository.listInterpretationsForSegment(
        segment.id,
        limit: 1,
        offset: 1,
      );
      expect(page.single.id, older.id);

      await repository.updateInterpretationsStatusForSegment(
        segment.id,
        status: 'confirmed',
      );
      final updated =
          await repository.listInterpretationsForSegment(segment.id);
      expect(updated.every((item) => item.status == 'confirmed'), isTrue);
    });

    test(
        'task work logs insert, upsert, reject, order, paginate, and aggregate minutes',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActivityFusionRepository(db);
      final base = DateTime(2026, 6, 13, 9);
      final segment = await repository.insertSegment(
        draft(start: base),
        sync: false,
        audit: false,
      );

      final negativeDuration = await repository.insertTaskWorkLog(
        taskId: 40,
        segmentId: segment.id,
        startAt: base.add(const Duration(minutes: 30)),
        endAt: base.add(const Duration(minutes: 10)),
        confidence: -0.5,
        sourceType: 'activity_interpretation',
      );
      final first = await repository.insertTaskWorkLog(
        taskId: 41,
        segmentId: segment.id,
        startAt: base.add(const Duration(minutes: 5)),
        endAt: base.add(const Duration(minutes: 25)),
        confidence: 0.6,
        sourceType: 'activity_interpretation',
        evidence: const <String, Object?>{'candidate': true},
      );
      final second = await repository.insertTaskWorkLog(
        taskId: 40,
        segmentId: segment.id,
        startAt: base.add(const Duration(minutes: 50)),
        endAt: base.add(const Duration(minutes: 80)),
        confidence: 2,
        sourceType: 'activity_interpretation',
      );

      expect(negativeDuration.durationMinutes, 0);
      expect(negativeDuration.confidence, 0);
      expect(second.confidence, 1);
      expect(first.evidence, containsPair('candidate', true));

      final bySegment = await repository.listTaskWorkLogsForSegment(segment.id);
      expect(
        bySegment.map((log) => log.id),
        <int>[first.id, negativeDuration.id, second.id],
      );
      final bySegmentPage = await repository.listTaskWorkLogsForSegment(
        segment.id,
        limit: 1,
        offset: 1,
      );
      expect(bySegmentPage.single.id, negativeDuration.id);

      final created = await repository.upsertConfirmedTaskWorkLogForSegment(
        taskId: 42,
        segmentId: segment.id,
        actualId: 700,
        startAt: base.add(const Duration(minutes: 90)),
        endAt: base.add(const Duration(minutes: 120)),
        confidence: 0.75,
        evidence: const <String, Object?>{'source': 'confirm'},
      );
      expect(created.status, 'confirmed');
      expect(created.sourceType, 'user_confirmed_activity_segment');
      expect(created.durationMinutes, 30);

      await stampCreatedAt(
        db,
        'task_work_logs',
        negativeDuration.id,
        base.add(const Duration(minutes: 1)),
      );
      await stampCreatedAt(
        db,
        'task_work_logs',
        second.id,
        base.add(const Duration(minutes: 2)),
      );
      final updated = await repository.upsertConfirmedTaskWorkLogForSegment(
        taskId: 40,
        segmentId: segment.id,
        actualId: 701,
        startAt: base.add(const Duration(minutes: 55)),
        endAt: base.add(const Duration(minutes: 100)),
        confidence: 0.85,
        evidence: const <String, Object?>{'source': 'update'},
      );
      expect(updated.id, second.id);
      expect(updated.actualId, 701);
      expect(updated.durationMinutes, 45);
      expect(updated.evidence, containsPair('source', 'update'));

      await db.customStatement(
        'UPDATE task_work_logs SET evidence_json = ? WHERE id = ?',
        <Object?>['[not-a-map]', first.id],
      );
      final invalidEvidence = await repository.listTaskWorkLogsForSegment(
        segment.id,
        limit: 1,
      );
      expect(invalidEvidence.single.evidence, isEmpty);

      await repository.rejectTaskWorkLogsForSegmentExcept(
        segmentId: segment.id,
        taskId: 42,
      );
      final afterRejectExcept =
          await repository.listTaskWorkLogsForSegment(segment.id);
      expect(
        afterRejectExcept
            .where((log) => log.taskId != 42)
            .every((log) => log.status == 'rejected'),
        isTrue,
      );
      expect(
        afterRejectExcept.singleWhere((log) => log.taskId == 42).status,
        'confirmed',
      );

      await repository.rejectTaskWorkLogsForSegment(segmentId: segment.id);
      final afterRejectAll = await repository.listTaskWorkLogsForSegment(
        segment.id,
      );
      expect(afterRejectAll.every((log) => log.status == 'rejected'), isTrue);

      final task40Logs = await repository.listTaskWorkLogsForTask(40);
      expect(task40Logs.map((log) => log.id),
          <int>[second.id, negativeDuration.id]);
      expect(
        task40Logs.fold<int>(0, (sum, log) => sum + log.durationMinutes),
        45,
      );
      final task40Page = await repository.listTaskWorkLogsForTask(
        40,
        limit: 1,
        offset: 1,
      );
      expect(task40Page.single.id, negativeDuration.id);
    });

    test('audit and sync dependencies write through real database tables',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final mutationStore = OfflineMutationStore(db);
      final stateStore = SyncObjectStateStore(db);
      final recorder = SyncWriteRecorder(
        mutationStore: mutationStore,
        stateStore: stateStore,
      );
      final repository = ActivityFusionRepository(
        db,
        DataOperationLogRepository(db),
        recorder,
      );
      final base = DateTime(2026, 6, 14, 9);

      final segment = await repository.insertSegment(
        draft(start: base, label: null, category: null),
      );
      await repository.updateSegmentStatus(
        segment.id,
        status: 'confirmed',
        actor: 'tester',
      );
      final interpretation = await repository.insertInterpretation(
        segmentId: segment.id,
        summary: 'Confirmed summary',
        confidence: 0.8,
      );
      final workLog = await repository.insertTaskWorkLog(
        taskId: 50,
        segmentId: segment.id,
        startAt: base,
        endAt: base.add(const Duration(minutes: 20)),
        confidence: 0.8,
        sourceType: 'activity_interpretation',
      );

      final logs = await DataOperationLogRepository(db).listRecent(limit: 10);
      expect(
        logs.map((log) => log.action),
        containsAll(<String>[
          'create_activity_segment',
          'update_activity_segment_status',
          'create_activity_interpretation',
          'create_task_work_log',
        ]),
      );

      final pendingMutations = await mutationStore.listPending(limit: 20);
      expect(
        pendingMutations.map((mutation) => mutation.objectType),
        containsAll(<String>[
          SyncObjectType.activitySegment.key,
          SyncObjectType.activityInterpretation.key,
          SyncObjectType.taskWorkLog.key,
        ]),
      );
      final segmentState = await stateStore.getState(
        objectType: SyncObjectType.activitySegment.key,
        localId: segment.id.toString(),
      );
      expect(segmentState?.syncState, SyncState.pendingCreate);
      expect(segmentState?.localVersion, 2);
      expect(segmentState?.uid, segment.segmentUid);

      final interpretationState = await stateStore.getState(
        objectType: SyncObjectType.activityInterpretation.key,
        localId: interpretation.id.toString(),
      );
      expect(interpretationState?.uid, interpretation.interpretationUid);
      final workLogState = await stateStore.getState(
        objectType: SyncObjectType.taskWorkLog.key,
        localId: workLog.id.toString(),
      );
      expect(workLogState?.uid, workLog.workUid);
    });
  });
}
