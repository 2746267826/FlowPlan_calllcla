import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/sync/server_sync_change_applier.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('applies fallback ids and defaults for remaining worker gap branches',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final result = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'event-default-start',
        objectType: 'calendar_event',
        serverId: 'event-server-default-start',
        uid: 'event-default-start-uid',
        serverVersion: 1,
        payload: <String, Object?>{
          'summary': 'Server event without start',
        },
      ),
      _change(
        changeId: 'actual-server-id-fallback',
        objectType: 'actual_activity_log',
        serverId: 'actual-server-id-fallback',
        serverVersion: 1,
        payload: <String, Object?>{
          'title': 'Actual uses server id',
        },
      ),
      _change(
        changeId: 'segment-server-id-fallback',
        objectType: 'activity_segment',
        serverId: 'segment-server-id-fallback',
        serverVersion: 1,
        payload: <String, Object?>{
          'label': 'Segment uses server id',
        },
      ),
      _change(
        changeId: 'report-server-id-fallback',
        objectType: 'report_document',
        serverId: 'report-server-id-fallback',
        serverVersion: 1,
        payload: <String, Object?>{
          'title': 'Report uses server id',
          'summaryMarkdown': 'Initial summary',
          'metricsJson': '{"initial":true}',
        },
      ),
    ]);

    expect(result.received, 4);
    expect(result.applied, 4);
    expect(result.failed, 0);

    final event = await (db.select(db.calendarEvents)
          ..where((row) => row.uid.equals('event-default-start-uid')))
        .getSingle();
    expect(event.summary, 'Server event without start');

    final actual = _singleWhere(
      await _tableRows(db, 'actual_activity_logs'),
      (row) => row['actual_uid'] == 'actual-server-id-fallback',
    );
    expect(actual['title'], 'Actual uses server id');
    expect(actual['source_type'], 'server');

    final segment = _singleWhere(
      await _tableRows(db, 'activity_segments'),
      (row) => row['segment_uid'] == 'segment-server-id-fallback',
    );
    expect(segment['label'], 'Segment uses server id');
    expect(segment['source_record_ids_json'], '[]');
    expect(segment['evidence_json'], '{}');

    final report = _singleWhere(
      await _tableRows(db, 'report_documents'),
      (row) => row['report_uid'] == 'report-server-id-fallback',
    );
    expect(report['title'], 'Report uses server id');
    expect(report['summary_markdown'], 'Initial summary');
    expect(report['metrics_json'], '{"initial":true}');

    final reportState = await stateStore.getStateByServerId(
      objectType: 'report_document',
      serverId: 'report-server-id-fallback',
    );
    expect(reportState?.localId, (report['id'] as int).toString());
  });

  test('updates report document snapshot fields through synced local id',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final inserted = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'report-insert-before-update',
        objectType: 'report_document',
        serverId: 'report-server-update-gap',
        serverVersion: 1,
        payload: <String, Object?>{
          'reportUid': 'report-update-gap-uid',
          'reportType': 'daily',
          'periodStart': '2026-06-10T00:00:00Z',
          'periodEnd': '2026-06-10T23:59:59Z',
          'title': 'Initial report title',
          'summaryMarkdown': 'Initial summary',
          'metricsJson': '{"count":1}',
          'sourceSnapshotJson': '{"phase":"initial"}',
          'createdAt': '2026-06-10T01:00:00Z',
        },
      ),
    ]);

    expect(inserted.applied, 1);
    expect(inserted.failed, 0);
    final report = _singleWhere(
      await _tableRows(db, 'report_documents'),
      (row) => row['report_uid'] == 'report-update-gap-uid',
    );

    final updated = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'report-update-gap',
        objectType: 'report_document',
        serverId: 'report-server-update-gap',
        serverVersion: 2,
        payload: <String, Object?>{
          'reportUid': 'report-update-gap-uid',
          'reportType': 'weekly',
          'periodStart': '2026-06-08T00:00:00Z',
          'periodEnd': '2026-06-14T23:59:59Z',
          'title': 'Updated report title',
          'summaryMarkdown': 'Updated summary',
          'metricsJson': '{"count":2}',
          'sourceSnapshotJson': '{"phase":"updated"}',
          'status': 'confirmed',
          'createdAt': '2026-06-10T02:00:00Z',
          'confirmedAt': '2026-06-11T03:00:00Z',
        },
      ),
    ]);

    expect(updated.applied, 1);
    expect(updated.failed, 0);

    final reportAfterUpdate = await _rowById(
      db,
      'report_documents',
      report['id'] as int,
    );
    expect(reportAfterUpdate?['report_type'], 'weekly');
    expect(reportAfterUpdate?['title'], 'Updated report title');
    expect(reportAfterUpdate?['summary_markdown'], 'Updated summary');
    expect(reportAfterUpdate?['metrics_json'], '{"count":2}');
    expect(reportAfterUpdate?['source_snapshot_json'], '{"phase":"updated"}');
    expect(reportAfterUpdate?['status'], 'confirmed');
    expect(reportAfterUpdate?['created_at'], '2026-06-10T02:00:00Z');
    expect(reportAfterUpdate?['confirmed_at'], '2026-06-11T03:00:00.000Z');
  });

  test('uses server ids for diary and file object uid fallbacks', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final result = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'diary-server-id-fallback-gap',
        objectType: 'diary_entry',
        serverId: 'diary-server-id-fallback-gap',
        serverVersion: 1,
        payload: <String, Object?>{
          'entryDate': '2026-06-12T09:30:00Z',
          'title': 'Diary uses server id',
          'bodyMarkdown': 'Fallback body',
          'status': 'confirmed',
          'createdAt': '2026-06-12T09:00:00Z',
        },
      ),
      _change(
        changeId: 'folder-server-id-fallback-gap',
        objectType: 'file_folder',
        serverId: 'folder-server-id-fallback-gap',
        serverVersion: 1,
        payload: <String, Object?>{
          'provider': 'dropbox',
          'displayName': 'Fallback Folder',
        },
      ),
    ]);

    expect(result.received, 2);
    expect(result.applied, 2);
    expect(result.failed, 0);

    final diary = _singleWhere(
      await _tableRows(db, 'diary_entries'),
      (row) => row['diary_uid'] == 'diary-server-id-fallback-gap',
    );
    expect(diary['entry_date'], '2026-06-12');
    expect(diary['title'], 'Diary uses server id');
    expect(diary['body_markdown'], 'Fallback body');
    expect(diary['status'], 'confirmed');

    final diaryState = await stateStore.getStateByServerId(
      objectType: 'diary_entry',
      serverId: 'diary-server-id-fallback-gap',
    );
    expect(diaryState?.localId, (diary['id'] as int).toString());

    final folder = _singleWhere(
      await _tableRows(db, 'file_folders'),
      (row) => row['folder_uid'] == 'folder-server-id-fallback-gap',
    );
    expect(folder['folder_uid'], 'folder-server-id-fallback-gap');
    expect(folder['display_name'], 'Fallback Folder');
    expect(folder['provider'], 'dropbox');
    expect(folder['remote_id'], isNull);

    final folderState = await stateStore.getStateByServerId(
      objectType: 'file_folder',
      serverId: 'folder-server-id-fallback-gap',
    );
    expect(folderState?.localId, (folder['id'] as int).toString());

    final usageResult =
        await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'usage-server-id-fallback-gap',
        objectType: 'file_folder_usage',
        serverId: 'usage-server-id-fallback-gap',
        serverVersion: 1,
        payload: <String, Object?>{
          'folderId': folder['id'],
          'entityType': 'diary',
          'entityId': 'diary-server-id-fallback-gap',
          'action': 'open',
          'source': 'server',
          'usedAt': '2026-06-12T10:15:00Z',
          'metadataJson': '{"fallback":true}',
        },
      ),
    ]);

    expect(usageResult.received, 1);
    expect(usageResult.applied, 1);
    expect(usageResult.failed, 0);

    final usage = _singleWhere(
      await _tableRows(db, 'file_folder_usages'),
      (row) => row['usage_uid'] == 'usage-server-id-fallback-gap',
    );
    expect(usage['folder_id'], folder['id']);
    expect(usage['entity_type'], 'diary');
    expect(usage['entity_id'], 'diary-server-id-fallback-gap');
    expect(usage['source'], 'server');
    expect(usage['used_at'], '2026-06-12T10:15:00.000Z');

    final usageState = await stateStore.getStateByServerId(
      objectType: 'file_folder_usage',
      serverId: 'usage-server-id-fallback-gap',
    );
    expect(usageState?.localId, (usage['id'] as int).toString());
  });

  test(
    'resolves file folder usage folder id from synced folder server id',
    () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final stateStore = SyncObjectStateStore(db);

      final folderResult =
          await _applyChanges(db, stateStore, <Map<String, Object?>>[
        _change(
          changeId: 'folder-server-id-for-usage-gap',
          objectType: 'file_folder',
          serverId: 'folder-server-id-for-usage-gap',
          serverVersion: 1,
          payload: <String, Object?>{
            'provider': 'dropbox',
            'displayName': 'Usage Target Folder',
          },
        ),
      ]);

      expect(folderResult.applied, 1);
      expect(folderResult.failed, 0);

      final folder = _singleWhere(
        await _tableRows(db, 'file_folders'),
        (row) => row['folder_uid'] == 'folder-server-id-for-usage-gap',
      );

      final usageResult =
          await _applyChanges(db, stateStore, <Map<String, Object?>>[
        _change(
          changeId: 'usage-folder-server-id-resolution-gap',
          objectType: 'file_folder_usage',
          serverId: 'usage-folder-server-id-resolution-gap',
          serverVersion: 1,
          payload: <String, Object?>{
            'folderId': 'folder-server-id-for-usage-gap',
            'entityType': 'diary',
            'entityId': 'diary-server-id-fallback-gap',
            'action': 'open',
            'source': 'server',
            'usedAt': '2026-06-12T10:15:00Z',
            'metadataJson': '{"fallback":true}',
          },
        ),
      ]);

      expect(usageResult.applied, 1);
      expect(usageResult.failed, 0);

      final usage = _singleWhere(
        await _tableRows(db, 'file_folder_usages'),
        (row) => row['usage_uid'] == 'usage-folder-server-id-resolution-gap',
      );
      expect(usage['folder_id'], folder['id']);
    },
  );

  test(
    'resolves file folder usage folder id from legacy folder uid without sync state',
    () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final stateStore = SyncObjectStateStore(db);
      final folderId = await _insertLegacyFolder(
        db,
        folderUid: 'legacy-folder-uid-gap',
        remoteId: 'legacy-folder-remote-gap',
      );

      final uidResult = await _applyChanges(db, stateStore, <Map<String, Object?>>[
        _change(
          changeId: 'usage-legacy-folder-uid-gap',
          objectType: 'file_folder_usage',
          serverId: 'usage-legacy-folder-uid-gap',
          serverVersion: 1,
          payload: <String, Object?>{
            'folderId': 'legacy-folder-uid-gap',
            'entityType': 'diary',
            'entityId': 'diary-legacy-folder-uid-gap',
            'action': 'open',
            'source': 'server',
            'usedAt': '2026-06-12T11:15:00Z',
          },
        ),
      ]);

      expect(uidResult.applied, 1);
      expect(uidResult.failed, 0);

      final uidUsage = _singleWhere(
        await _tableRows(db, 'file_folder_usages'),
        (row) => row['usage_uid'] == 'usage-legacy-folder-uid-gap',
      );
      expect(uidUsage['folder_id'], folderId);

      final remoteResult =
          await _applyChanges(db, stateStore, <Map<String, Object?>>[
        _change(
          changeId: 'usage-legacy-folder-remote-gap',
          objectType: 'file_folder_usage',
          serverId: 'usage-legacy-folder-remote-gap',
          serverVersion: 1,
          payload: <String, Object?>{
            'folderId': 'legacy-folder-remote-gap',
            'entityType': 'diary',
            'entityId': 'diary-legacy-folder-remote-gap',
            'action': 'open',
            'source': 'server',
            'usedAt': '2026-06-12T11:30:00Z',
          },
        ),
      ]);

      expect(remoteResult.applied, 1);
      expect(remoteResult.failed, 0);

      final remoteUsage = _singleWhere(
        await _tableRows(db, 'file_folder_usages'),
        (row) => row['usage_uid'] == 'usage-legacy-folder-remote-gap',
      );
      expect(remoteUsage['folder_id'], folderId);
    },
  );
}

Map<String, Object?> _change({
  required String changeId,
  required String objectType,
  required String serverId,
  String action = 'upsert',
  int serverVersion = 1,
  String? uid,
  Map<String, Object?> payload = const <String, Object?>{},
}) {
  return <String, Object?>{
    'changeId': changeId,
    'objectType': objectType,
    'serverId': serverId,
    if (uid != null) 'uid': uid,
    'action': action,
    'serverVersion': serverVersion,
    'payload': payload,
  };
}

Future<ServerSyncApplyResult> _applyChanges(
  AppDatabase db,
  SyncObjectStateStore stateStore,
  List<Map<String, Object?>> changes,
) {
  final applier = ServerSyncChangeApplier(db, stateStore);
  return applier.applyPullResponse(<String, dynamic>{
    'changes': changes,
  });
}

Future<List<Map<String, dynamic>>> _tableRows(
  AppDatabase db,
  String tableName,
) async {
  final rows =
      await db.customSelect('SELECT * FROM $tableName ORDER BY id').get();
  return rows
      .map((row) => Map<String, dynamic>.from(row.data))
      .toList(growable: false);
}

Future<int> _insertLegacyFolder(
  AppDatabase db, {
  required String folderUid,
  required String remoteId,
}) async {
  await db.customStatement(
    '''
    INSERT INTO file_folders (
      folder_uid,
      provider,
      display_name,
      remote_id,
      created_at,
      updated_at
    ) VALUES (?, ?, ?, ?, ?, ?)
    ''',
    [
      folderUid,
      'onedrive',
      'Legacy Folder',
      remoteId,
      '2026-06-12T11:00:00.000Z',
      '2026-06-12T11:00:00.000Z',
    ],
  );
  final row = _singleWhere(
    await _tableRows(db, 'file_folders'),
    (row) => row['folder_uid'] == folderUid,
  );
  return row['id'] as int;
}

Map<String, dynamic> _singleWhere(
  List<Map<String, dynamic>> rows,
  bool Function(Map<String, dynamic> row) matches,
) {
  final found = rows.where(matches).toList(growable: false);
  expect(found, hasLength(1));
  return found.single;
}

Future<Map<String, dynamic>?> _rowById(
  AppDatabase db,
  String tableName,
  int id,
) async {
  final matches = (await _tableRows(db, tableName))
      .where((row) => row['id'] == id)
      .toList(growable: false);
  if (matches.isEmpty) {
    return null;
  }
  return matches.single;
}
