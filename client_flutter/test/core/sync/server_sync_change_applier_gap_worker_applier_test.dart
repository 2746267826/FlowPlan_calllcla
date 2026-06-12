import 'package:drift/drift.dart' hide isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/sync/server_sync_change_applier.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('deletes user settings and calendar events through synced state',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final seed = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'setting-upsert',
        objectType: 'user_setting',
        serverId: 'setting-server-delete',
        uid: 'sync.deleteMe',
        payload: <String, Object?>{
          'settingValue': 'present',
        },
      ),
      _change(
        changeId: 'event-upsert',
        objectType: 'calendar_event',
        serverId: 'event-server-delete-direct',
        uid: 'event-delete-direct',
        payload: <String, Object?>{
          'summary': 'Standalone event',
          'location': ' Focus room ',
          'startAt': '2026-06-10T09:00:00Z',
        },
      ),
    ]);

    expect(seed.applied, 2);
    expect(seed.failed, 0);
    expect(await db.getSetting('sync.deleteMe'), 'present');
    final event = _singleWhere(
      await _tableRows(db, 'calendar_events'),
      (row) => row['uid'] == 'event-delete-direct',
    );
    expect(event['location'], 'Focus room');

    final deleted = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'setting-delete',
        objectType: 'user_setting',
        serverId: 'setting-server-delete',
        uid: 'sync.deleteMe',
        action: 'delete',
        serverVersion: 2,
      ),
      _change(
        changeId: 'event-delete',
        objectType: 'calendar_event',
        serverId: 'event-server-delete-direct',
        action: 'delete',
        serverVersion: 2,
      ),
    ]);

    expect(deleted.received, 2);
    expect(deleted.applied, 2);
    expect(deleted.failed, 0);
    expect(await db.getSetting('sync.deleteMe'), isNull);
    expect(await _rowById(db, 'calendar_events', event['id'] as int), isNull);
    expect(
      await stateStore.getStateByServerId(
        objectType: 'calendar_event',
        serverId: 'event-server-delete-direct',
      ),
      isNull,
    );
  });

  test('uses default calendars and repairs broken outlook calendar refs',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final first = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'event-default-calendar',
        objectType: 'calendar_event',
        serverId: 'event-server-default-calendar',
        uid: 'plain-event-without-remote-calendar',
        payload: <String, Object?>{
          'summary': 'Uses created default calendar',
          'startAt': '2026-06-10T11:00:00Z',
        },
      ),
    ]);
    expect(first.applied, 1);
    expect(first.failed, 0);

    final firstEvent = _singleWhere(
      await _tableRows(db, 'calendar_events'),
      (row) => row['uid'] == 'plain-event-without-remote-calendar',
    );
    final defaultCalendar = await _rowById(
      db,
      'event_calendars',
      firstEvent['event_calendar_id'] as int,
    );
    expect(defaultCalendar?['is_default'], 1);
    expect(defaultCalendar?['source'], 'local');

    final second = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'event-existing-default-calendar',
        objectType: 'calendar_event',
        serverId: 'event-server-existing-default-calendar',
        uid: 'another-plain-event',
        payload: <String, Object?>{
          'summary': 'Uses existing default calendar',
          'startAt': '2026-06-10T12:00:00Z',
        },
      ),
    ]);
    expect(second.applied, 1);
    final secondEvent = _singleWhere(
      await _tableRows(db, 'calendar_events'),
      (row) => row['uid'] == 'another-plain-event',
    );
    expect(secondEvent['event_calendar_id'], defaultCalendar?['id']);

    await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            uid: 'outlook_event:remote-broken-ref:event-1',
            dtstamp: DateTime.utc(2026, 6, 10),
            summary: 'Broken outlook ref',
            dtstart: DateTime.utc(2026, 6, 10, 13),
            source: const Value('outlook'),
            eventCalendarId: const Value(99999),
            colorHex: const Value('#334455'),
          ),
        );

    final repaired = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'setting-triggers-repair',
        objectType: 'user_setting',
        serverId: 'setting-server-repair-broken-ref',
        uid: 'sync.repairBrokenRef',
        payload: <String, Object?>{
          'settingValue': 'ran',
        },
      ),
    ]);

    expect(repaired.applied, 1);
    expect(repaired.orphanCalendarEvents, 1);
    final fixedEvent = _singleWhere(
      await _tableRows(db, 'calendar_events'),
      (row) => row['uid'] == 'outlook_event:remote-broken-ref:event-1',
    );
    expect(fixedEvent['event_calendar_id'], isNot(99999));
    final fixedCalendar = await _rowById(
      db,
      'event_calendars',
      fixedEvent['event_calendar_id'] as int,
    );
    expect(fixedCalendar?['source'], 'outlook');
    expect(fixedCalendar?['sync_url'], 'remote-broken-ref');
    expect(fixedCalendar?['color_hex'], '#334455');
  });

  test('updates report delivery and file management rows on later versions',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final inserted = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'folder-insert',
        objectType: 'file_folder',
        serverId: 'folder-server-update',
        uid: 'folder-update-uid',
        serverVersion: 1,
        payload: <String, Object?>{
          'provider': 'onedrive',
          'displayName': 'Initial Folder',
          'remoteId': 'folder-remote-1',
          'useCount': 1,
        },
      ),
      _change(
        changeId: 'file-insert',
        objectType: 'file_item',
        serverId: 'file-server-update',
        uid: 'file-update-uid',
        serverVersion: 1,
        payload: <String, Object?>{
          'provider': 'onedrive',
          'displayName': 'Initial.md',
          'remoteId': 'file-remote-1',
          'sizeBytes': 12,
        },
      ),
      _change(
        changeId: 'usage-insert',
        objectType: 'file_folder_usage',
        serverId: 'usage-server-update',
        uid: 'usage-update-uid',
        serverVersion: 1,
        payload: <String, Object?>{
          'folderId': 1,
          'entityType': 'task',
          'entityId': 'task-1',
          'action': 'open',
          'usedAt': '2026-06-10T08:00:00Z',
        },
      ),
      _change(
        changeId: 'version-insert',
        objectType: 'file_version_record',
        serverId: 'version-server-update',
        uid: 'version-update-uid',
        serverVersion: 1,
        payload: <String, Object?>{
          'fileId': 1,
          'versionRef': 'v1',
          'displayName': 'Version 1',
          'sizeBytes': 12,
        },
      ),
      _change(
        changeId: 'delivery-insert',
        objectType: 'report_push_delivery',
        serverId: 'delivery-server-update',
        uid: 'delivery-update-uid',
        serverVersion: 1,
        payload: <String, Object?>{
          'channel': 'email',
          'target': 'first@example.test',
          'scheduledAt': '2026-06-10T09:00:00Z',
        },
      ),
    ]);
    expect(inserted.applied, 5);
    expect(inserted.failed, 0);

    final folder = _singleWhere(
      await _tableRows(db, 'file_folders'),
      (row) => row['folder_uid'] == 'folder-update-uid',
    );
    final file = _singleWhere(
      await _tableRows(db, 'file_items'),
      (row) => row['file_uid'] == 'file-update-uid',
    );
    final usage = _singleWhere(
      await _tableRows(db, 'file_folder_usages'),
      (row) => row['usage_uid'] == 'usage-update-uid',
    );
    final version = _singleWhere(
      await _tableRows(db, 'file_version_records'),
      (row) => row['version_uid'] == 'version-update-uid',
    );
    final delivery = _singleWhere(
      await _tableRows(db, 'report_push_deliveries'),
      (row) => row['delivery_uid'] == 'delivery-update-uid',
    );

    final updated = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'folder-update',
        objectType: 'file_folder',
        serverId: 'folder-server-update',
        uid: 'folder-update-uid',
        serverVersion: 2,
        payload: <String, Object?>{
          'provider': 'local',
          'displayName': 'Updated Folder',
          'remoteId': 'folder-remote-2',
          'pinned': true,
          'useCount': '7',
        },
      ),
      _change(
        changeId: 'file-update',
        objectType: 'file_item',
        serverId: 'file-server-update',
        uid: 'file-update-uid',
        serverVersion: 2,
        payload: <String, Object?>{
          'provider': 'local',
          'displayName': 'Updated.md',
          'folderId': folder['id'],
          'remoteId': 'file-remote-2',
          'mimeType': 'text/markdown',
          'sizeBytes': '34',
          'previewMode': 'markdown',
        },
      ),
      _change(
        changeId: 'usage-update',
        objectType: 'file_folder_usage',
        serverId: 'usage-server-update',
        uid: 'usage-update-uid',
        serverVersion: 2,
        payload: <String, Object?>{
          'folderId': folder['id'],
          'entityType': 'report',
          'entityId': 'report-1',
          'action': 'pin',
          'source': 'server',
          'usedAt': '2026-06-10T10:00:00Z',
          'metadataJson': '{"updated":true}',
        },
      ),
      _change(
        changeId: 'version-update',
        objectType: 'file_version_record',
        serverId: 'version-server-update',
        uid: 'version-update-uid',
        serverVersion: 2,
        payload: <String, Object?>{
          'fileId': file['id'],
          'provider': 'kopia',
          'versionRef': 'v2',
          'displayName': 'Version 2',
          'sizeBytes': '34',
          'checksum': 'def456',
          'note': 'Updated remotely',
        },
      ),
      _change(
        changeId: 'delivery-update',
        objectType: 'report_push_delivery',
        serverId: 'delivery-server-update',
        uid: 'delivery-update-uid',
        serverVersion: 2,
        payload: <String, Object?>{
          'channel': 'telegram',
          'target': '@updated',
          'payloadJson': '{"retry":true}',
          'status': 'sent',
          'attempts': '2',
          'lastError': 'transient',
          'scheduledAt': '2026-06-10T11:00:00Z',
          'sentAt': '2026-06-10T11:05:00Z',
        },
      ),
    ]);

    expect(updated.applied, 5);
    expect(updated.failed, 0);
    expect(
      (await _rowById(
          db, 'file_folders', folder['id'] as int))?['display_name'],
      'Updated Folder',
    );
    expect(
      (await _rowById(db, 'file_folders', folder['id'] as int))?['pinned'],
      1,
    );
    expect(
      (await _rowById(db, 'file_items', file['id'] as int))?['display_name'],
      'Updated.md',
    );
    expect(
      (await _rowById(db, 'file_folder_usages', usage['id'] as int))?['action'],
      'pin',
    );
    expect(
      (await _rowById(
        db,
        'file_version_records',
        version['id'] as int,
      ))?['version_ref'],
      'v2',
    );
    final deliveryAfter = await _rowById(
      db,
      'report_push_deliveries',
      delivery['id'] as int,
    );
    expect(deliveryAfter?['status'], 'sent');
    expect(deliveryAfter?['attempts'], 2);
    expect(deliveryAfter?['sent_at'], '2026-06-10T11:05:00.000Z');
  });

  test('uses natural keys and server ids when local sync state is absent',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    await db.customStatement(
      '''
      INSERT INTO diary_entries (
        diary_uid,
        entry_date,
        title,
        body_markdown,
        linked_task_ids_json,
        linked_file_ids_json,
        location_json,
        weather_json,
        status,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        'diary-natural-uid',
        '2026-06-09',
        'Old diary',
        'Old body',
        '[]',
        '[]',
        '{}',
        '{}',
        'draft',
        '2026-06-09T00:00:00Z',
        '2026-06-09T00:00:00Z',
      ],
    );
    await db.customStatement(
      '''
      INSERT INTO file_context_links (
        link_uid,
        entity_type,
        entity_id,
        target_type,
        target_id,
        relation_type,
        confidence,
        status,
        created_at,
        updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      <Object?>[
        'link-natural-uid',
        'task',
        'task-natural',
        'file',
        44,
        'manual',
        0.2,
        'confirmed',
        '2026-06-09T00:00:00Z',
        '2026-06-09T00:00:00Z',
      ],
    );

    final result = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'diary-natural-update',
        objectType: 'diary_entry',
        serverId: 'diary-server-natural',
        uid: 'diary-natural-uid',
        serverVersion: 3,
        payload: <String, Object?>{
          'entryDate': '2026-06-10T02:30:00Z',
          'title': 'Updated diary',
          'bodyMarkdown': 'Updated body',
          'status': 'confirmed',
        },
      ),
      _change(
        changeId: 'link-natural-update',
        objectType: 'file_context_link',
        serverId: 'link-server-natural',
        uid: 'link-natural-uid',
        serverVersion: 3,
        payload: <String, Object?>{
          'entityType': 'task',
          'entityId': 'task-natural',
          'targetType': 'file',
          'targetId': 44,
          'relationType': 'evidence',
          'confidence': '0.8',
          'reason': 'Updated by uid lookup',
          'status': 'confirmed',
        },
      ),
      _change(
        changeId: 'interpretation-server-id-fallback',
        objectType: 'activity_interpretation',
        serverId: 'interpretation-server-fallback',
        serverVersion: 3,
        payload: <String, Object?>{
          'segmentId': 7,
          'summary': 'Server id fallback interpretation',
        },
      ),
    ]);

    expect(result.applied, 3);
    expect(result.failed, 0);
    expect(await _tableRows(db, 'diary_entries'), hasLength(1));
    final diary = _singleWhere(
      await _tableRows(db, 'diary_entries'),
      (row) => row['diary_uid'] == 'diary-natural-uid',
    );
    expect(diary['title'], 'Updated diary');
    expect(diary['entry_date'], '2026-06-10');

    expect(await _tableRows(db, 'file_context_links'), hasLength(1));
    final link = _singleWhere(
      await _tableRows(db, 'file_context_links'),
      (row) => row['link_uid'] == 'link-natural-uid',
    );
    expect(link['relation_type'], 'evidence');
    expect(link['confidence'], 0.8);

    final interpretation = _singleWhere(
      await _tableRows(db, 'activity_interpretations'),
      (row) => row['interpretation_uid'] == 'interpretation-server-fallback',
    );
    expect(interpretation['summary'], 'Server id fallback interpretation');
    final state = await stateStore.getStateByServerId(
      objectType: 'activity_interpretation',
      serverId: 'interpretation-server-fallback',
    );
    expect(state?.localId, (interpretation['id'] as int).toString());
    expect(state?.uid, isNull);
  });

  test('skips malformed and unknown changes without mutating data', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final result =
        await ServerSyncChangeApplier(db, stateStore).applyPullResponse(
      <String, dynamic>{
        'changes': <Object?>[
          <String, Object?>{
            'changeId': 'unknown-type',
            'objectType': 'definitely_not_registered',
            'serverId': 'unknown-server',
            'payload': <String, Object?>{'summary': 'ignored'},
          },
          <String, Object?>{
            'changeId': 'malformed-setting',
            'objectType': 'user_setting',
            'serverId': 'setting-server-malformed',
            'payload': <String, Object?>{'settingKey': 'sync.noValue'},
          },
        ],
      },
    );

    expect(result.received, 2);
    expect(result.applied, 0);
    expect(result.skipped, 2);
    expect(result.failed, 0);
    expect(result.perType['definitely_not_registered'], 1);
    expect(result.perType['user_setting'], 1);
    expect(await db.getSetting('sync.noValue'), isNull);
    expect(await _tableRows(db, 'calendar_events'), isEmpty);
  });
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
