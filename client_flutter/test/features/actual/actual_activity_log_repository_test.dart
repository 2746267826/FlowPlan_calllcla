import 'dart:async';
import 'dart:convert';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/sync/sync_object_registry.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/actual/data/actual_activity_log_repository.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  group('ActualActivityLogRepository', () {
    test(
        'inserts candidates with defaults, clamps values, and deduplicates sources',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActualActivityLogRepository(db);
      final start = DateTime.utc(2026, 6, 10, 9);

      final firstId = await repository.insertCandidate(
        title: '   ',
        startAt: start,
        endAt: start.add(const Duration(minutes: 25)),
        sourceType: ActualActivitySourceType.trackingInference,
        sourceId: 'source-1',
        sourcePayload: const <String, Object?>{
          'window': 'editor',
          'nested': <String, Object?>{'score': 2},
        },
        confidence: 2,
        note: 'candidate note',
      );
      final duplicateId = await repository.insertCandidate(
        title: 'Duplicate should not replace existing',
        startAt: start.add(const Duration(hours: 1)),
        endAt: start.add(const Duration(hours: 2)),
        sourceType: ActualActivitySourceType.trackingInference,
        sourceId: 'source-1',
        confidence: 0.1,
      );

      final first = await repository.getById(firstId);
      final bySource = await repository.getBySource(
        sourceType: ActualActivitySourceType.trackingInference,
        sourceId: 'source-1',
      );

      expect(duplicateId, firstId);
      expect(bySource?.id, firstId);
      expect(first?.title.trim(), isNotEmpty);
      expect(first?.confidence, 1);
      expect(first?.status, ActualActivityStatus.candidate);
      expect(first?.note, 'candidate note');
      final payload =
          jsonDecode(first!.sourcePayloadJson) as Map<String, dynamic>;
      expect(payload, containsPair('window', 'editor'));
      expect(payload['nested'], containsPair('score', 2));

      await repository.reject(firstId, note: 'bad inference');
      final replacementId = await repository.insertCandidate(
        title: 'Replacement after reject',
        startAt: start.add(const Duration(hours: 3)),
        endAt: start.add(const Duration(hours: 4)),
        sourceType: ActualActivitySourceType.trackingInference,
        sourceId: 'source-1',
        confidence: -1,
      );
      final replacement = await repository.getById(replacementId);

      expect(replacementId, isNot(firstId));
      expect(replacement?.confidence, 0);
      expect(replacement?.title, 'Replacement after reject');
    });

    test('rejects invalid time ranges before writing data', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActualActivityLogRepository(db);
      final start = DateTime.utc(2026, 6, 10, 9);

      await expectLater(
        repository.insertCandidate(
          title: 'Invalid',
          startAt: start,
          endAt: start,
          sourceType: ActualActivitySourceType.manual,
        ),
        throwsA(isA<ArgumentError>()),
      );

      expect(await _countRows(db, 'actual_activity_logs'), 0);
    });

    test('queries overlapping ranges with exclusive boundary semantics',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActualActivityLogRepository(db);
      final base = DateTime.utc(2026, 6, 10, 9);

      await _insert(
        repository,
        title: 'Touches start only',
        start: base.subtract(const Duration(hours: 1)),
        end: base,
      );
      final spanning = await _insert(
        repository,
        title: 'Spanning',
        start: base.subtract(const Duration(minutes: 15)),
        end: base.add(const Duration(minutes: 30)),
      );
      final inside = await _insert(
        repository,
        title: 'Inside confirmed',
        start: base.add(const Duration(minutes: 10)),
        end: base.add(const Duration(minutes: 50)),
      );
      await repository.confirm(inside);
      await _insert(
        repository,
        title: 'Touches end only',
        start: base.add(const Duration(hours: 2)),
        end: base.add(const Duration(hours: 3)),
      );
      final rejected = await _insert(
        repository,
        title: 'Rejected overlap',
        start: base.add(const Duration(minutes: 30)),
        end: base.add(const Duration(minutes: 70)),
      );
      await repository.reject(rejected);

      final all = await repository.listInRange(
        base,
        base.add(const Duration(hours: 2)),
      );
      final confirmed = await repository.listInRange(
        base,
        base.add(const Duration(hours: 2)),
        statuses: const <String>[ActualActivityStatus.confirmed],
      );

      expect(
        all.map((actual) => actual.title),
        <String>['Spanning', 'Inside confirmed', 'Rejected overlap'],
      );
      expect(all.first.id, spanning);
      expect(confirmed.map((actual) => actual.title), <String>[
        'Inside confirmed',
      ]);
      expect(
        await repository.hasOverlappingConfirmed(
          base.subtract(const Duration(hours: 2)),
          base,
        ),
        isFalse,
      );
      expect(
        await repository.hasOverlappingConfirmed(
          base,
          base.add(const Duration(hours: 2)),
        ),
        isTrue,
      );
    });

    test('records audit evidence and sync mutations for status changes',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final evidence = _createEvidence(db);
      final repository = ActualActivityLogRepository(
        db,
        evidence.auditRepository,
        evidence.recorder,
      );
      final base = DateTime.utc(2026, 6, 10, 9);

      final confirmedId = await _insert(
        repository,
        title: 'Confirmed actual',
        start: base,
        end: base.add(const Duration(minutes: 30)),
        actor: 'system-a',
      );
      final rejectedId = await _insert(
        repository,
        title: 'Rejected actual',
        start: base.add(const Duration(hours: 1)),
        end: base.add(const Duration(hours: 2)),
        actor: 'system-b',
      );
      final mergedId = await _insert(
        repository,
        title: 'Merged actual',
        start: base.add(const Duration(hours: 3)),
        end: base.add(const Duration(hours: 4)),
        actor: 'system-c',
      );

      await repository.confirm(
        confirmedId,
        actor: 'reviewer',
        note: 'looks right',
      );
      await repository.reject(
        rejectedId,
        actor: 'reviewer',
        note: 'not work',
      );
      await repository.mergeInto(
        mergedId,
        confirmedId,
        actor: 'reviewer',
      );
      await repository.confirm(999, actor: 'nobody');
      await repository.reject(999, actor: 'nobody');
      await repository.mergeInto(999, confirmedId, actor: 'nobody');

      final confirmed = await repository.getById(confirmedId);
      final rejected = await repository.getById(rejectedId);
      final merged = await repository.getById(mergedId);
      final auditRows = await evidence.auditRepository.listRecent(limit: 20);
      final mutations = await evidence.mutationStore.listPending(limit: 50);
      final actualMutations = mutations
          .where(
            (mutation) =>
                mutation.objectType == SyncObjectType.actualActivityLog.key,
          )
          .toList(growable: false);

      expect(confirmed?.status, ActualActivityStatus.confirmed);
      expect(confirmed?.note, 'looks right');
      expect(confirmed?.confirmedAt, isNotNull);
      expect(confirmed?.rejectedAt, isNull);
      expect(rejected?.status, ActualActivityStatus.rejected);
      expect(rejected?.note, 'not work');
      expect(rejected?.rejectedAt, isNotNull);
      expect(merged?.status, ActualActivityStatus.merged);
      expect(merged?.mergedIntoId, confirmedId);

      expect(auditRows, hasLength(6));
      expect(
        auditRows.map((entry) => entry.action).toSet(),
        containsAll(<String>[
          'create_candidate',
          'confirm',
          'reject',
          'merge',
        ]),
      );
      expect(auditRows.any((entry) => entry.actor == 'nobody'), isFalse);

      expect(
        actualMutations.map((mutation) => mutation.action),
        containsAll(<OfflineMutationAction>[
          OfflineMutationAction.create,
          OfflineMutationAction.update,
        ]),
      );
      final confirmMutation = actualMutations.lastWhere(
        (mutation) => mutation.localId == confirmedId.toString(),
      );
      expect(
        jsonDecode(confirmMutation.changedFieldsJson!) as List<dynamic>,
        containsAll(<String>[
          'status',
          'note',
          'confirmedAt',
          'rejectedAt',
        ]),
      );
    });

    test('watchInRange emits updated results after repository writes',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = ActualActivityLogRepository(db);
      final base = DateTime.utc(2026, 6, 10, 9);
      final emissions = <List<ActualActivityLog>>[];
      final subscription = repository.watchInRange(
        base,
        base.add(const Duration(hours: 2)),
        statuses: const <String>[ActualActivityStatus.confirmed],
      ).listen(emissions.add);
      addTearDown(subscription.cancel);

      await _pumpUntil(() => emissions.isNotEmpty);
      expect(emissions.single, isEmpty);

      final id = await _insert(
        repository,
        title: 'Watch me',
        start: base.add(const Duration(minutes: 10)),
        end: base.add(const Duration(minutes: 30)),
      );
      await _pumpEventQueue();
      expect(emissions.last, isEmpty);

      await repository.confirm(id);

      await _pumpUntil(
        () => emissions.any(
          (items) => items.any((item) => item.title == 'Watch me'),
        ),
      );
      expect(emissions.last.single.title, 'Watch me');
      expect(emissions.last.single.status, ActualActivityStatus.confirmed);
    });
  });
}

Future<int> _insert(
  ActualActivityLogRepository repository, {
  required String title,
  required DateTime start,
  required DateTime end,
  String actor = 'test',
}) {
  return repository.insertCandidate(
    title: title,
    startAt: start,
    endAt: end,
    sourceType: ActualActivitySourceType.manual,
    sourceId: title,
    actor: actor,
  );
}

Future<int> _countRows(AppDatabase db, String tableName) async {
  final row = await db
      .customSelect(
        'SELECT COUNT(*) AS count FROM $tableName',
      )
      .getSingle();
  return row.read<int>('count');
}

_Evidence _createEvidence(AppDatabase db) {
  final mutationStore = OfflineMutationStore(db);
  final recorder = SyncWriteRecorder(
    mutationStore: mutationStore,
    stateStore: SyncObjectStateStore(db),
  );
  return _Evidence(
    auditRepository: DataOperationLogRepository(db, recorder),
    mutationStore: mutationStore,
    recorder: recorder,
  );
}

Future<void> _pumpUntil(
  FutureOr<bool> Function() condition, {
  int maxPumps = 30,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (await condition()) {
      return;
    }
    await _pumpEventQueue();
  }
  fail('Condition was not met after $maxPumps event queue pumps.');
}

Future<void> _pumpEventQueue() => pumpEventQueue(times: 4);

class _Evidence {
  const _Evidence({
    required this.auditRepository,
    required this.mutationStore,
    required this.recorder,
  });

  final DataOperationLogRepository auditRepository;
  final OfflineMutationStore mutationStore;
  final SyncWriteRecorder recorder;
}
