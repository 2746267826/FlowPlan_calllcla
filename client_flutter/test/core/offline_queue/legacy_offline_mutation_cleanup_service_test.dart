import 'dart:convert';

import 'package:flowplanv2/core/offline_queue/legacy_offline_mutation_cleanup_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('summarizes and exports legacy offline mutations', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await db.customStatement(
      '''
      INSERT INTO offline_mutations (
        mutation_uid, object_type, local_id, action, payload_json, created_at, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        'legacy-1',
        'task_item',
        'local-1',
        'create',
        '{"summary":"Legacy"}',
        DateTime.utc(2026, 6, 12).toIso8601String(),
        'pending',
      ],
    );
    final service = LegacyOfflineMutationCleanupService(db);

    final summary = await service.summary();
    final exported = await service.exportJson();

    expect(summary.totalCount, 1);
    expect(summary.pendingCount, 1);
    expect(jsonDecode(exported), isA<List<dynamic>>());
    expect(exported, contains('legacy-1'));
  });

  test('marks pending mutations as failed without deleting evidence', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await db.customStatement(
      '''
      INSERT INTO offline_mutations (
        mutation_uid, object_type, local_id, action, payload_json, created_at, status
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        'legacy-2',
        'calendar_event',
        'local-2',
        'update',
        '{}',
        DateTime.utc(2026, 6, 12).toIso8601String(),
        'pending',
      ],
    );
    final service = LegacyOfflineMutationCleanupService(db);

    final count = await service.markPendingAsLegacyFailed();

    expect(count, 1);
    final rows = await db
        .customSelect(
          'SELECT status, last_error FROM offline_mutations',
        )
        .get();
    expect(rows.single.read<String>('status'), 'failed');
    expect(rows.single.read<String>('last_error'), contains('online-primary'));
  });
}
