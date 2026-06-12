import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/sync/server_sync_change_applier.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  group('ServerSyncChange.fromJson', () {
    test('uses defaults for missing fields and non-map payloads', () {
      final missing = ServerSyncChange.fromJson(<String, dynamic>{});
      expect(missing.changeId, '');
      expect(missing.objectType, '');
      expect(missing.serverId, '');
      expect(missing.uid, isNull);
      expect(missing.action, 'upsert');
      expect(missing.serverVersion, 1);
      expect(missing.payload, isEmpty);

      final nonMapPayload = ServerSyncChange.fromJson(<String, dynamic>{
        'changeId': 'change-1',
        'objectType': 'calendar_book',
        'serverId': 'calendar-server-1',
        'payload': <Object?>['not', 'a', 'map'],
      });
      expect(nonMapPayload.changeId, 'change-1');
      expect(nonMapPayload.action, 'upsert');
      expect(nonMapPayload.serverVersion, 1);
      expect(nonMapPayload.payload, isEmpty);
    });
  });

  group('ServerSyncApplyResult', () {
    test('reports failures and limits summary errors to five', () {
      final result = ServerSyncApplyResult(
        received: 9,
        applied: 2,
        skipped: 1,
        failed: 6,
        perType: const <String, int>{'calendar_event': 6},
        appliedChangeIds: const <String>['applied-1', 'applied-2'],
        errors: List<String>.generate(6, (index) => 'error-$index'),
        orphanCalendarEvents: 3,
      );

      expect(result.hasFailures, isTrue);
      expect(result.toSummary(), <String, Object?>{
        'received': 9,
        'applied': 2,
        'skipped': 1,
        'failed': 6,
        'perType': <String, int>{'calendar_event': 6},
        'orphanCalendarEvents': 3,
        'errors': <String>[
          'error-0',
          'error-1',
          'error-2',
          'error-3',
          'error-4',
        ],
      });

      final clean = const ServerSyncApplyResult(
        received: 1,
        applied: 1,
        skipped: 0,
        failed: 0,
        perType: <String, int>{},
        appliedChangeIds: <String>[],
        errors: <String>[],
      );
      expect(clean.hasFailures, isFalse);
      expect(clean.toSummary().containsKey('errors'), isFalse);
    });
  });

  group('ServerSyncChangeApplier.applyPullResponse', () {
    test('returns all zero counts when changes is not a list', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final applier = ServerSyncChangeApplier(db, SyncObjectStateStore(db));

      final result = await applier.applyPullResponse(<String, dynamic>{
        'changes': <String, Object?>{'not': 'a-list'},
      });

      expect(result.received, 0);
      expect(result.applied, 0);
      expect(result.skipped, 0);
      expect(result.failed, 0);
      expect(result.perType, isEmpty);
      expect(result.appliedChangeIds, isEmpty);
      expect(result.errors, isEmpty);
      expect(result.orphanCalendarEvents, 0);
      expect(result.hasFailures, isFalse);
    });

    test('sorts calendar books before events so events use the synced book',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final stateStore = SyncObjectStateStore(db);

      final result = await _applyChanges(db, stateStore, <Map<String, Object?>>[
        _change(
          changeId: 'b-event',
          objectType: 'calendar_event',
          serverId: 'event-server-1',
          uid: 'outlook_event:remote-calendar-sort:event-1',
          serverVersion: 2,
          payload: <String, Object?>{
            'summary': 'Event from sorted pull',
            'startAt': '2026-06-10T09:00:00Z',
            'remoteCalendarId': 'remote-calendar-sort',
            'source': 'outlook',
          },
        ),
        _change(
          changeId: 'z-book',
          objectType: 'calendar_book',
          serverId: 'book-server-1',
          serverVersion: 2,
          payload: <String, Object?>{
            'name': 'Sorted Calendar',
            'remoteCalendarId': 'remote-calendar-sort',
            'source': 'outlook',
            'colorHex': '#1188cc',
          },
        ),
      ]);

      expect(result.applied, 2);
      expect(result.failed, 0);
      expect(result.appliedChangeIds, <String>['z-book', 'b-event']);

      final calendar = _singleWhere(
        await _tableRows(db, 'event_calendars'),
        (row) => row['sync_url'] == 'remote-calendar-sort',
      );
      expect(calendar['name'], 'Sorted Calendar');

      final event = _singleWhere(
        await _tableRows(db, 'calendar_events'),
        (row) => row['summary'] == 'Event from sorted pull',
      );
      expect(event['event_calendar_id'], calendar['id']);
    });

    test('deleting a calendar book removes its events and event sync states',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final stateStore = SyncObjectStateStore(db);

      final upsert = await _applyChanges(db, stateStore, <Map<String, Object?>>[
        _change(
          changeId: 'book-upsert',
          objectType: 'calendar_book',
          serverId: 'book-server-delete',
          serverVersion: 2,
          payload: <String, Object?>{
            'name': 'Calendar To Delete',
            'remoteCalendarId': 'remote-calendar-delete',
            'source': 'outlook',
          },
        ),
        _change(
          changeId: 'event-upsert',
          objectType: 'calendar_event',
          serverId: 'event-server-delete',
          uid: 'outlook_event:remote-calendar-delete:event-1',
          serverVersion: 2,
          payload: <String, Object?>{
            'summary': 'Event To Delete',
            'startAt': '2026-06-10T10:00:00Z',
            'remoteCalendarId': 'remote-calendar-delete',
            'source': 'outlook',
          },
        ),
      ]);
      expect(upsert.applied, 2);

      final calendar = _singleWhere(
        await _tableRows(db, 'event_calendars'),
        (row) => row['sync_url'] == 'remote-calendar-delete',
      );
      final event = _singleWhere(
        await _tableRows(db, 'calendar_events'),
        (row) => row['summary'] == 'Event To Delete',
      );
      expect(
        await stateStore.getStateByServerId(
          objectType: 'calendar_event',
          serverId: 'event-server-delete',
        ),
        isNotNull,
      );

      final delete = await _applyChanges(
        db,
        stateStore,
        <Map<String, Object?>>[
          _change(
            changeId: 'book-delete',
            objectType: 'calendar_book',
            serverId: 'book-server-delete',
            action: 'delete',
            serverVersion: 3,
          ),
        ],
      );

      expect(delete.applied, 1);
      expect(delete.failed, 0);
      expect(
          await _rowById(db, 'event_calendars', calendar['id'] as int), isNull);
      expect(await _rowById(db, 'calendar_events', event['id'] as int), isNull);
      expect(
        await stateStore.getStateByServerId(
          objectType: 'calendar_event',
          serverId: 'event-server-delete',
        ),
        isNull,
      );
      expect(
        await stateStore.getStateByServerId(
          objectType: 'calendar_book',
          serverId: 'book-server-delete',
        ),
        isNull,
      );
    });
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
  return applier.applyPullResponse(<String, Object?>{
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
