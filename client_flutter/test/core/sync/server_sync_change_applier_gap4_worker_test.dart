import 'package:drift/drift.dart' hide isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/sync/server_sync_change_applier.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('updates calendar books task lists and events through synced local ids',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final inserted = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'book-insert-gap4',
        objectType: 'calendar_book',
        serverId: 'book-server-gap4',
        serverVersion: 1,
        payload: <String, Object?>{
          'remoteCalendarId': 'remote-calendar-gap4',
          'name': 'Original calendar',
          'colorHex': '#111111',
          'source': 'outlook',
        },
      ),
      _change(
        changeId: 'list-insert-gap4',
        objectType: 'task_list',
        serverId: 'list-server-gap4',
        serverVersion: 1,
        payload: <String, Object?>{
          'name': 'Original list',
          'colorHex': '#222222',
        },
      ),
      _change(
        changeId: 'event-insert-gap4',
        objectType: 'calendar_event',
        serverId: 'event-server-gap4',
        uid: 'event-gap4',
        serverVersion: 1,
        payload: <String, Object?>{
          'eventCalendarRemoteId': 'remote-calendar-gap4',
          'bodyPreview': 'Original preview summary',
          'startAt': '2026-06-11T09:00:00Z',
        },
      ),
    ]);

    expect(inserted.applied, 3);
    expect(inserted.failed, 0);
    expect(await _tableRows(db, 'event_calendars'), hasLength(3));
    expect(await _tableRows(db, 'task_lists'), hasLength(4));
    expect(await _tableRows(db, 'calendar_events'), hasLength(1));

    final updated = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'book-update-gap4',
        objectType: 'calendar_book',
        serverId: 'book-server-gap4',
        serverVersion: 2,
        payload: <String, Object?>{
          'remoteCalendarId': 'remote-calendar-gap4',
          'name': 'Updated calendar',
          'colorHex': '#333333',
          'description': 'Remote description',
          'isVisible': false,
          'isDefault': true,
          'source': 'outlook',
        },
      ),
      _change(
        changeId: 'list-update-gap4',
        objectType: 'task_list',
        serverId: 'list-server-gap4',
        serverVersion: 2,
        payload: <String, Object?>{
          'name': 'Updated list',
          'colorHex': '#444444',
          'emoji': 'L',
          'isVisible': false,
          'isDefault': true,
          'isArchived': true,
        },
      ),
      _change(
        changeId: 'event-update-gap4',
        objectType: 'calendar_event',
        serverId: 'event-server-gap4',
        uid: 'event-gap4',
        serverVersion: 2,
        payload: <String, Object?>{
          'eventCalendarRemoteId': 'remote-calendar-gap4',
          'bodyPreview': 'Updated preview summary',
          'location': <String, Object?>{'displayName': 'Room 42'},
          'startAt': '2026-06-11T10:00:00Z',
          'endAt': '2026-06-11T11:00:00Z',
          'colorHex': '#555555',
          'isBlock': true,
        },
      ),
    ]);

    expect(updated.applied, 3);
    expect(updated.failed, 0);

    final calendar = _singleWhere(
      await _tableRows(db, 'event_calendars'),
      (row) => row['sync_url'] == 'remote-calendar-gap4',
    );
    expect(calendar['name'], 'Updated calendar');
    expect(calendar['color_hex'], '#333333');
    expect(calendar['description'], 'Remote description');
    expect(calendar['is_visible'], 0);
    expect(calendar['is_default'], 1);

    final list = _singleWhere(
      await _tableRows(db, 'task_lists'),
      (row) => row['name'] == 'Updated list',
    );
    expect(list['color_hex'], '#444444');
    expect(list['emoji'], 'L');
    expect(list['is_visible'], 0);
    expect(list['is_default'], 1);
    expect(list['is_archived'], 1);

    final event = _singleWhere(
      await _tableRows(db, 'calendar_events'),
      (row) => row['uid'] == 'event-gap4',
    );
    expect(event['summary'], 'Updated preview summary');
    expect(event['location'], 'Room 42');
    expect(event['event_calendar_id'], calendar['id']);
    expect(event['color_hex'], '#555555');
    expect(event['is_block'], 1);

    final eventState = await stateStore.getStateByServerId(
      objectType: 'calendar_event',
      serverId: 'event-server-gap4',
    );
    expect(eventState?.localId, (event['id'] as int).toString());
    expect(eventState?.serverVersion, 2);
  });

  test('calendar events use existing non-default calendars before creating one',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    await db.customStatement('DELETE FROM calendar_events');
    await db.customStatement('DELETE FROM event_calendars');
    final fallbackCalendarId = await db.into(db.eventCalendars).insert(
          EventCalendarsCompanion.insert(
            name: 'Only local calendar',
            colorHex: const Value('#888888'),
            isVisible: const Value(true),
            isDefault: const Value(false),
            source: const Value('local'),
            createdAt: DateTime.utc(2026, 6, 11),
          ),
        );

    final existingCalendar = await _applyChanges(
      db,
      stateStore,
      <Map<String, Object?>>[
        _change(
          changeId: 'event-existing-fallback-calendar',
          objectType: 'calendar_event',
          serverId: 'event-existing-fallback-calendar',
          uid: 'event-existing-fallback-calendar',
          payload: <String, Object?>{
            'summary': 'Uses the only calendar',
            'startAt': '2026-06-11T12:00:00Z',
          },
        ),
      ],
    );
    expect(existingCalendar.applied, 1);
    var event = _singleWhere(
      await _tableRows(db, 'calendar_events'),
      (row) => row['uid'] == 'event-existing-fallback-calendar',
    );
    expect(event['event_calendar_id'], fallbackCalendarId);

    await db.customStatement('DELETE FROM calendar_events');
    await db.customStatement('DELETE FROM event_calendars');

    final createdCalendar = await _applyChanges(
      db,
      stateStore,
      <Map<String, Object?>>[
        _change(
          changeId: 'event-created-fallback-calendar',
          objectType: 'calendar_event',
          serverId: 'event-created-fallback-calendar',
          uid: 'event-created-fallback-calendar',
          payload: <String, Object?>{
            'summary': 'Creates a default calendar',
            'startAt': '2026-06-11T13:00:00Z',
          },
        ),
      ],
    );
    expect(createdCalendar.applied, 1);
    event = _singleWhere(
      await _tableRows(db, 'calendar_events'),
      (row) => row['uid'] == 'event-created-fallback-calendar',
    );
    final createdDefault = _singleWhere(
      await _tableRows(db, 'event_calendars'),
      (row) => row['id'] == event['event_calendar_id'],
    );
    expect(createdDefault['is_default'], 1);
    expect(createdDefault['source'], 'local');
  });

  test('delivery and file version records fall back to server ids as uids',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final result = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'delivery-server-id-fallback-gap4',
        objectType: 'report_push_delivery',
        serverId: 'delivery-server-id-fallback',
        serverVersion: 1,
        payload: <String, Object?>{
          'target': '@fallback',
          'scheduledAt': '2026-06-11T14:00:00Z',
        },
      ),
      _change(
        changeId: 'version-server-id-fallback-gap4',
        objectType: 'file_version_record',
        serverId: 'version-server-id-fallback',
        serverVersion: 1,
        payload: <String, Object?>{
          'fileId': 9,
          'sizeBytes': '42',
          'modifiedAt': '2026-06-11T15:00:00Z',
        },
      ),
    ]);

    expect(result.applied, 2);
    expect(result.failed, 0);

    final delivery = _singleWhere(
      await _tableRows(db, 'report_push_deliveries'),
      (row) => row['delivery_uid'] == 'delivery-server-id-fallback',
    );
    expect(delivery['channel'], 'telegram');
    expect(delivery['status'], 'pending');
    expect(delivery['attempts'], 0);
    expect(delivery['payload_json'], '{}');

    final version = _singleWhere(
      await _tableRows(db, 'file_version_records'),
      (row) => row['version_uid'] == 'version-server-id-fallback',
    );
    expect(version['file_id'], 9);
    expect(version['provider'], 'kopia');
    expect(version['version_ref'], 'version-server-id-fallback');
    expect(version['size_bytes'], 42);
    expect(version['metadata_json'], '{}');
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
  return ServerSyncChangeApplier(db, stateStore).applyPullResponse(
    <String, dynamic>{'changes': changes},
  );
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
