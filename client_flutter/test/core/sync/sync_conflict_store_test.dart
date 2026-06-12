import 'dart:convert';

import 'package:flowplanv2/core/sync/conflict_snapshot.dart';
import 'package:flowplanv2/core/sync/sync_conflict_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('createConflict stores generated and explicit conflicts', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final store = SyncConflictStore(db);

    final generatedId = await store.createConflict(
      const ConflictSnapshot(
        conflictId: '',
        objectType: 'task_item',
        serverId: 'server-generated',
        baseVersion: null,
        localVersion: 1,
        serverVersion: 2,
        fields: <ConflictFieldSnapshot>[
          ConflictFieldSnapshot(
            field: 'summary',
            local: 'Local',
            server: 'Remote',
          ),
        ],
      ),
    );
    final explicitId = await store.createConflict(
      const ConflictSnapshot(
        conflictId: 'conflict-explicit',
        objectType: 'calendar_event',
        serverId: 'server-explicit',
        baseVersion: 3,
        localVersion: 4,
        serverVersion: 5,
        fields: <ConflictFieldSnapshot>[
          ConflictFieldSnapshot(
            field: 'location',
            base: 'A',
            local: 'B',
            server: 'C',
          ),
        ],
      ),
    );

    expect(generatedId, isNotEmpty);
    expect(explicitId, 'conflict-explicit');
    final conflicts = await store.listOpen();
    expect(conflicts, hasLength(2));
    final explicit = conflicts
        .singleWhere((item) => item.conflictUid == 'conflict-explicit');
    expect(explicit.objectType, 'calendar_event');
    expect(explicit.serverId, 'server-explicit');
    expect(explicit.baseVersion, 3);
    expect(explicit.localVersion, 4);
    expect(explicit.serverVersion, 5);
    expect(jsonDecode(explicit.fieldsJson), <Object?>[
      <String, Object?>{
        'field': 'location',
        'base': 'A',
        'local': 'B',
        'server': 'C',
      },
    ]);
    expect(explicit.resolvedAt, isNull);
    expect(explicit.resolutionJson, isNull);
  });

  test('createConflict upserts existing conflicts and resolve closes them',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final store = SyncConflictStore(db);

    await store.createConflict(
      const ConflictSnapshot(
        conflictId: 'conflict-upsert',
        objectType: 'task_item',
        serverId: 'server-upsert',
        baseVersion: 1,
        localVersion: 2,
        serverVersion: 3,
        fields: <ConflictFieldSnapshot>[
          ConflictFieldSnapshot(field: 'summary', local: 'Old'),
        ],
      ),
    );
    await store.createConflict(
      const ConflictSnapshot(
        conflictId: 'conflict-upsert',
        objectType: 'task_item',
        serverId: 'server-upsert',
        baseVersion: 1,
        localVersion: 2,
        serverVersion: 4,
        fields: <ConflictFieldSnapshot>[
          ConflictFieldSnapshot(field: 'summary', local: 'New'),
        ],
      ),
    );

    var conflicts = await store.listOpen();
    expect(conflicts, hasLength(1));
    expect(conflicts.single.serverVersion, 4);
    expect(conflicts.single.fieldsJson, contains('"New"'));

    await store.resolve(
      conflictUid: 'conflict-upsert',
      resolution: const <String, Object?>{
        'strategy': 'server',
        'field': 'summary',
      },
    );

    conflicts = await store.listOpen();
    expect(conflicts, isEmpty);
    final row = await db.customSelect(
      '''
      SELECT status, resolved_at, resolution_json
      FROM sync_conflicts
      WHERE conflict_uid = 'conflict-upsert'
      ''',
    ).getSingle();
    expect(row.read<String>('status'), 'resolved');
    expect(DateTime.tryParse(row.read<String>('resolved_at')), isNotNull);
    expect(
        row.read<String>('resolution_json'), contains('"strategy":"server"'));
  });

  test('listOpen orders by created time and tolerates malformed resolved_at',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final store = SyncConflictStore(db);

    await db.customStatement(
      '''
      INSERT INTO sync_conflicts (
        conflict_uid,
        object_type,
        server_id,
        local_version,
        server_version,
        fields_json,
        status,
        created_at,
        resolved_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        'older',
        'task_item',
        'server-older',
        1,
        2,
        '[]',
        'open',
        '2026-06-10T08:00:00.000Z',
        '',
      ],
    );
    await db.customStatement(
      '''
      INSERT INTO sync_conflicts (
        conflict_uid,
        object_type,
        server_id,
        local_version,
        server_version,
        fields_json,
        status,
        created_at,
        resolved_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        'newer',
        'task_item',
        'server-newer',
        1,
        3,
        '[]',
        'open',
        '2026-06-10T09:00:00.000Z',
        'not-a-date',
      ],
    );

    final conflicts = await store.listOpen(limit: 1);

    expect(conflicts.single.conflictUid, 'newer');
    expect(conflicts.single.createdAt, DateTime.parse('2026-06-10T09:00:00Z'));
    expect(conflicts.single.resolvedAt, isNull);
  });
}
