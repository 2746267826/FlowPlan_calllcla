import 'dart:convert';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/sync/sync_object_registry.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  group('DataOperationLogRepository', () {
    test('records JSON snapshots and sync evidence for created audit rows',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final mutationStore = OfflineMutationStore(db);
      final recorder = SyncWriteRecorder(
        mutationStore: mutationStore,
        stateStore: SyncObjectStateStore(db),
      );
      final repository = DataOperationLogRepository(db, recorder);

      await repository.record(
        actor: 'tester',
        action: 'update',
        entityType: 'task',
        entityId: 'task-1',
        summary: 'Updated task',
        before: const <String, Object?>{'summary': 'Before'},
        after: const <String, Object?>{'summary': 'After'},
        metadata: const <String, Object?>{
          'fields': <String>['summary'],
        },
      );

      final rows = await repository.listRecent();
      final mutations = await mutationStore.listPending(limit: 5);

      expect(rows, hasLength(1));
      expect(rows.single.actor, 'tester');
      expect(rows.single.action, 'update');
      expect(rows.single.entityType, 'task');
      expect(rows.single.entityId, 'task-1');
      expect(jsonDecode(rows.single.beforeJson!),
          containsPair('summary', 'Before'));
      expect(
          jsonDecode(rows.single.afterJson!), containsPair('summary', 'After'));
      final metadata =
          jsonDecode(rows.single.metadataJson!) as Map<String, dynamic>;
      expect(metadata['fields'], <dynamic>['summary']);

      expect(mutations, hasLength(1));
      expect(mutations.single.objectType, SyncObjectType.auditLog.key);
      expect(mutations.single.localId, rows.single.id.toString());
      expect(
        jsonDecode(mutations.single.payloadJson),
        containsPair('summary', 'Updated task'),
      );
    });

    test('preserves null optional fields and applies recent limit ordering',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = DataOperationLogRepository(db);

      await repository.record(
        actor: 'oldest',
        action: 'create',
        entityType: 'task',
        summary: 'Oldest',
      );
      await repository.record(
        actor: 'middle',
        action: 'update',
        entityType: 'event',
        entityId: 'event-1',
        summary: 'Middle',
      );
      await repository.record(
        actor: 'newest',
        action: 'delete',
        entityType: 'file',
        entityId: 'file-1',
        summary: 'Newest',
      );
      await _stampOccurredAt(db, 'Oldest', DateTime.utc(2026, 6, 10, 8));
      await _stampOccurredAt(db, 'Middle', DateTime.utc(2026, 6, 10, 9));
      await _stampOccurredAt(db, 'Newest', DateTime.utc(2026, 6, 10, 10));

      final empty = await repository.listRecent(limit: 0);
      final limited = await repository.listRecent(limit: 2);
      final all = await repository.listRecent(limit: 10);

      expect(empty, isEmpty);
      expect(limited.map((entry) => entry.summary), <String>[
        'Newest',
        'Middle',
      ]);
      expect(all.last.summary, 'Oldest');
      expect(all.last.entityId, isNull);
      expect(all.last.beforeJson, isNull);
      expect(all.last.afterJson, isNull);
      expect(all.last.metadataJson, isNull);
    });
  });
}

Future<void> _stampOccurredAt(
  AppDatabase db,
  String summary,
  DateTime occurredAt,
) {
  return db.customStatement(
    '''
    UPDATE data_operation_logs
    SET occurred_at = ?
    WHERE summary = ?
    ''',
    <Object?>[
      occurredAt.toIso8601String(),
      summary,
    ],
  );
}
