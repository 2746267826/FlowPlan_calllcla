import 'package:drift/drift.dart' hide isNull;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/sync/server_sync_change_applier.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test(
      'applies actual, segment, interpretation, work log, and schedule objects',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final result = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'actual-change',
        objectType: 'actual_activity_log',
        serverId: 'actual-server-1',
        uid: 'actual-uid-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'title': 'Remote focus log',
          'startAt': '2026-06-10T09:00:00Z',
          'endAt': '2026-06-10T10:10:00Z',
          'sourceType': 'tracker',
          'sourceId': 'record-1',
          'confidence': '0.82',
          'status': 'confirmed',
          'confirmedAt': '2026-06-10T10:15:00Z',
        },
      ),
      _change(
        changeId: 'segment-change',
        objectType: 'activity_segment',
        serverId: 'segment-server-1',
        uid: 'segment-uid-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'startAt': '2026-06-10T09:05:00Z',
          'endAt': '2026-06-10T09:55:00Z',
          'primaryProcessName': 'Code.exe',
          'primaryWindowTitle': 'FlowPlanV2',
          'category': 'coding',
          'label': 'Deep work',
          'sourceRecordIdsJson': '[1,2]',
          'confidence': 0.91,
        },
      ),
      _change(
        changeId: 'interpretation-change',
        objectType: 'activity_interpretation',
        serverId: 'interpretation-server-1',
        uid: 'interpretation-uid-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'segmentId': 1,
          'summary': 'Worked on sync coverage',
          'inferredProject': 'FlowPlanV2',
          'inferredTaskId': '42',
          'confidence': '0.7',
          'status': 'accepted',
        },
      ),
      _change(
        changeId: 'schedule-segment-change',
        objectType: 'task_schedule_segment',
        serverId: 'schedule-segment-server-1',
        uid: 'schedule-segment-uid-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'taskId': 42,
          'segmentIndex': 1,
          'startAt': '2026-06-10T14:00:00Z',
          'endAt': '2026-06-10T14:45:00Z',
          'source': 'remote-plan',
          'planRunId': 'plan-remote',
          'note': 'Imported split',
        },
      ),
      _change(
        changeId: 'work-log-change',
        objectType: 'task_work_log',
        serverId: 'work-log-server-1',
        uid: 'work-log-uid-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'taskId': 42,
          'segmentId': 1,
          'actualId': 1,
          'startAt': '2026-06-10T09:05:00Z',
          'endAt': '2026-06-10T09:50:00Z',
          'sourceType': 'activity_interpretation',
          'evidenceJson': '{"score":0.7}',
          'status': 'candidate',
        },
      ),
    ]);

    expect(result.applied, 5);
    expect(result.failed, 0);
    expect(result.skipped, 0);
    expect(result.perType['actual_activity_log'], 1);
    expect(result.perType['task_work_log'], 1);

    final actual = _singleWhere(
      await _tableRows(db, 'actual_activity_logs'),
      (row) => row['actual_uid'] == 'actual-uid-1',
    );
    expect(actual['title'], 'Remote focus log');
    expect(actual['source_type'], 'tracker');
    expect(actual['confidence'], 0.82);
    expect(actual['status'], 'confirmed');

    final segment = _singleWhere(
      await _tableRows(db, 'activity_segments'),
      (row) => row['segment_uid'] == 'segment-uid-1',
    );
    expect(segment['primary_process_name'], 'Code.exe');
    expect(segment['category'], 'coding');

    final interpretation = _singleWhere(
      await _tableRows(db, 'activity_interpretations'),
      (row) => row['interpretation_uid'] == 'interpretation-uid-1',
    );
    expect(interpretation['summary'], 'Worked on sync coverage');
    expect(interpretation['inferred_task_id'], 42);

    final scheduleSegment = _singleWhere(
      await _tableRows(db, 'task_schedule_segments'),
      (row) => row['task_id'] == 42 && row['segment_index'] == 1,
    );
    expect(scheduleSegment['source'], 'remote-plan');
    expect(scheduleSegment['note'], 'Imported split');

    final workLog = _singleWhere(
      await _tableRows(db, 'task_work_logs'),
      (row) => row['work_uid'] == 'work-log-uid-1',
    );
    expect(workLog['duration_minutes'], 45);
    expect(workLog['source_type'], 'activity_interpretation');

    final state = await stateStore.getStateByServerId(
      objectType: 'activity_segment',
      serverId: 'segment-server-1',
    );
    expect(state?.localId, (segment['id'] as int).toString());
    expect(state?.serverVersion, 2);

    final updateResult =
        await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'actual-update-change',
        objectType: 'actual_activity_log',
        serverId: 'actual-server-1',
        uid: 'actual-uid-1',
        serverVersion: 4,
        payload: <String, Object?>{
          'title': 'Updated focus log',
          'startAt': '2026-06-10T09:10:00Z',
          'endAt': '2026-06-10T10:20:00Z',
          'sourceType': 'manual',
          'confidence': 1,
          'status': 'confirmed',
        },
      ),
      _change(
        changeId: 'segment-update-change',
        objectType: 'activity_segment',
        serverId: 'segment-server-1',
        uid: 'segment-uid-1',
        serverVersion: 4,
        payload: <String, Object?>{
          'startAt': '2026-06-10T09:10:00Z',
          'endAt': '2026-06-10T10:00:00Z',
          'category': 'review',
          'label': 'Updated deep work',
          'confidence': 0.95,
        },
      ),
      _change(
        changeId: 'interpretation-update-change',
        objectType: 'activity_interpretation',
        serverId: 'interpretation-server-1',
        uid: 'interpretation-uid-1',
        serverVersion: 4,
        payload: <String, Object?>{
          'segmentId': segment['id'],
          'summary': 'Updated interpretation',
          'inferredProject': 'FlowPlanV2',
          'confidence': 0.9,
          'status': 'accepted',
        },
      ),
      _change(
        changeId: 'schedule-update-change',
        objectType: 'task_schedule_segment',
        serverId: 'schedule-segment-server-1',
        uid: 'schedule-segment-uid-1',
        serverVersion: 4,
        payload: <String, Object?>{
          'taskId': 42,
          'segmentIndex': 2,
          'startAt': '2026-06-10T15:00:00Z',
          'endAt': '2026-06-10T15:30:00Z',
          'source': 'manual-adjusted',
          'note': 'Updated split',
        },
      ),
      _change(
        changeId: 'work-log-update-change',
        objectType: 'task_work_log',
        serverId: 'work-log-server-1',
        uid: 'work-log-uid-1',
        serverVersion: 4,
        payload: <String, Object?>{
          'taskId': 42,
          'segmentId': segment['id'],
          'actualId': actual['id'],
          'startAt': '2026-06-10T09:10:00Z',
          'endAt': '2026-06-10T10:10:00Z',
          'durationMinutes': 60,
          'sourceType': 'manual',
          'status': 'confirmed',
        },
      ),
    ]);

    expect(updateResult.applied, 5);
    expect(updateResult.failed, 0);
    expect(
      (await _rowById(
          db, 'actual_activity_logs', actual['id'] as int))?['title'],
      'Updated focus log',
    );
    expect(
      (await _rowById(db, 'activity_segments', segment['id'] as int))?['label'],
      'Updated deep work',
    );
    expect(
      (await _rowById(
        db,
        'activity_interpretations',
        interpretation['id'] as int,
      ))?['summary'],
      'Updated interpretation',
    );
    expect(
      (await _rowById(
        db,
        'task_schedule_segments',
        scheduleSegment['id'] as int,
      ))?['segment_index'],
      2,
    );
    expect(
      (await _rowById(
          db, 'task_work_logs', workLog['id'] as int))?['duration_minutes'],
      60,
    );

    final deleteResult =
        await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'actual-delete-change',
        objectType: 'actual_activity_log',
        serverId: 'actual-server-1',
        action: 'delete',
        serverVersion: 5,
      ),
      _change(
        changeId: 'segment-delete-change',
        objectType: 'activity_segment',
        serverId: 'segment-server-1',
        action: 'delete',
        serverVersion: 5,
      ),
      _change(
        changeId: 'interpretation-delete-change',
        objectType: 'activity_interpretation',
        serverId: 'interpretation-server-1',
        action: 'delete',
        serverVersion: 5,
      ),
      _change(
        changeId: 'schedule-delete-change',
        objectType: 'task_schedule_segment',
        serverId: 'schedule-segment-server-1',
        action: 'delete',
        serverVersion: 5,
      ),
      _change(
        changeId: 'work-log-delete-change',
        objectType: 'task_work_log',
        serverId: 'work-log-server-1',
        action: 'delete',
        serverVersion: 5,
      ),
    ]);

    expect(deleteResult.applied, 5);
    expect(deleteResult.failed, 0);
    expect(
      await _rowById(db, 'actual_activity_logs', actual['id'] as int),
      isNull,
    );
    expect(
      await _rowById(db, 'activity_segments', segment['id'] as int),
      isNull,
    );
    expect(
      await _rowById(
        db,
        'activity_interpretations',
        interpretation['id'] as int,
      ),
      isNull,
    );
    expect(
      await _rowById(
        db,
        'task_schedule_segments',
        scheduleSegment['id'] as int,
      ),
      isNull,
    );
    expect(
      await _rowById(db, 'task_work_logs', workLog['id'] as int),
      isNull,
    );
    expect(
      await stateStore.getStateByServerId(
        objectType: 'task_work_log',
        serverId: 'work-log-server-1',
      ),
      isNull,
    );
  });

  test('skips malformed changes and malformed payloads without side effects',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final result =
        await ServerSyncChangeApplier(db, stateStore).applyPullResponse(
      <String, dynamic>{
        'changes': <Object?>[
          'raw-string-change',
          <String, Object?>{
            'changeId': '',
            'objectType': 'task_item',
            'serverId': 'missing-change-id',
            'payload': <String, Object?>{'summary': 'Should be skipped'},
          },
          <String, Object?>{
            'changeId': 'unknown-object-change',
            'objectType': 'unknown_object',
            'serverId': 'unknown-server-1',
            'payload': <String, Object?>{'name': 'Ignored'},
          },
          <String, Object?>{
            'changeId': 'missing-value-setting',
            'objectType': 'user_setting',
            'serverId': 'setting-server-1',
            'uid': 'client.missing',
            'payload': 'not-a-map',
          },
        ],
      },
    );

    expect(result.received, 4);
    expect(result.applied, 0);
    expect(result.skipped, 4);
    expect(result.failed, 0);
    expect(result.perType['task_item'], 1);
    expect(result.perType['unknown_object'], 1);
    expect(result.perType['user_setting'], 1);
    expect(await db.getSetting('client.missing'), isNull);
    expect(await _tableRows(db, 'task_items'), isEmpty);
  });

  test('normalizes payload aliases and scalar types for task and event changes',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);
    final dueMillis = DateTime.utc(2026, 6, 12, 18).millisecondsSinceEpoch;

    final result = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'payload-task-change',
        objectType: 'task_item',
        serverId: 'payload-task-server',
        uid: 'payload-task-uid',
        serverVersion: 2,
        payload: <String, Object?>{
          'title': 'Alias task title',
          'due_date': dueMillis,
          'percent_complete': '55',
          'duration_minutes': '90',
          'is_splittable': 'yes',
          'is_auto_scheduled': '0',
          'priority_local': 1.9,
          'is_locked': 1,
          'reminder_minutes_before': '5',
        },
      ),
      _change(
        changeId: 'payload-event-change',
        objectType: 'calendar_event',
        serverId: 'payload-event-server',
        uid: 'outlook_event:remote-calendar-alias:event-1',
        serverVersion: 2,
        payload: <String, Object?>{
          'subject': 'Alias event title',
          'startTime': '2026-06-10T09:00:00Z',
          'endTime': '2026-06-10T10:00:00Z',
          'calendar_id': 'remote-calendar-alias',
          'source': 'outlook',
          'locations': <Object?>[
            <String, Object?>{'displayName': 'Room A'},
            <String, Object?>{'displayName': 'Room B'},
            <String, Object?>{'displayName': '  '},
          ],
          'is_block': 'true',
        },
      ),
    ]);

    expect(result.applied, 2);
    expect(result.failed, 0);

    final task = await (db.select(db.taskItems)
          ..where((row) => row.uid.equals('payload-task-uid')))
        .getSingle();
    expect(task.summary, 'Alias task title');
    expect(task.due, DateTime.fromMillisecondsSinceEpoch(dueMillis));
    expect(task.percentComplete, 55);
    expect(task.durationMinutes, 90);
    expect(task.isSplittable, isTrue);
    expect(task.isAutoScheduled, isFalse);
    expect(task.priorityLocal, 1);
    expect(task.isLocked, isTrue);
    expect(task.reminderMinutesBefore, 5);

    final event = await (db.select(db.calendarEvents)
          ..where((row) =>
              row.uid.equals('outlook_event:remote-calendar-alias:event-1')))
        .getSingle();
    expect(event.summary, 'Alias event title');
    expect(event.location, 'Room A, Room B');
    expect(event.isBlock, isTrue);
    expect(event.eventCalendarId, isA<int>());

    final calendar = await _rowById(
      db,
      'event_calendars',
      event.eventCalendarId!,
    );
    expect(calendar?['source'], 'outlook');
    expect(calendar?['sync_url'], 'remote-calendar-alias');

    final taskState = await stateStore.getStateByServerId(
      objectType: 'task_item',
      serverId: 'payload-task-server',
    );
    final eventState = await stateStore.getStateByServerId(
      objectType: 'calendar_event',
      serverId: 'payload-event-server',
    );
    expect(taskState?.serverVersion, 2);
    expect(eventState?.serverVersion, 2);
  });

  test('stale upserts are skipped but lower-version deletes still remove state',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    final fresh = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'fresh-segment-change',
        objectType: 'activity_segment',
        serverId: 'segment-server-stale',
        uid: 'segment-uid-stale',
        serverVersion: 8,
        payload: <String, Object?>{
          'label': 'Fresh segment',
          'category': 'coding',
          'startAt': '2026-06-10T08:00:00Z',
          'endAt': '2026-06-10T09:00:00Z',
        },
      ),
    ]);
    expect(fresh.applied, 1);
    final segment = _singleWhere(
      await _tableRows(db, 'activity_segments'),
      (row) => row['segment_uid'] == 'segment-uid-stale',
    );

    final stale = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'stale-segment-change',
        objectType: 'activity_segment',
        serverId: 'segment-server-stale',
        uid: 'segment-uid-stale',
        serverVersion: 8,
        payload: <String, Object?>{
          'label': 'Stale segment',
          'category': 'meeting',
        },
      ),
    ]);
    expect(stale.applied, 0);
    expect(stale.skipped, 1);
    expect(stale.failed, 0);
    expect(
      (await _rowById(db, 'activity_segments', segment['id'] as int))?['label'],
      'Fresh segment',
    );

    final deleteResult =
        await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'missing-delete-change',
        objectType: 'activity_segment',
        serverId: 'missing-segment-server',
        action: 'delete',
        serverVersion: 1,
      ),
      _change(
        changeId: 'lower-version-delete-change',
        objectType: 'activity_segment',
        serverId: 'segment-server-stale',
        action: 'delete',
        serverVersion: 1,
      ),
    ]);

    expect(deleteResult.applied, 2);
    expect(deleteResult.failed, 0);
    expect(
        await _rowById(db, 'activity_segments', segment['id'] as int), isNull);
    expect(
      await stateStore.getStateByServerId(
        objectType: 'activity_segment',
        serverId: 'segment-server-stale',
      ),
      isNull,
    );
  });

  test('continues applying later changes after a duplicate-uid failure',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'seed-segment-change',
        objectType: 'activity_segment',
        serverId: 'segment-server-seed',
        uid: 'duplicate-segment-uid',
        serverVersion: 2,
      ),
    ]);

    final result = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'duplicate-segment-change',
        objectType: 'activity_segment',
        serverId: 'segment-server-duplicate',
        uid: 'duplicate-segment-uid',
        serverVersion: 2,
      ),
      _change(
        changeId: 'setting-after-failure-change',
        objectType: 'user_setting',
        serverId: 'setting-after-failure',
        uid: 'sync.afterFailure',
        serverVersion: 3,
        payload: <String, Object?>{
          'settingKey': 'sync.afterFailure',
          'settingValue': 'applied',
        },
      ),
    ]);

    expect(result.received, 2);
    expect(result.applied, 1);
    expect(result.failed, 1);
    expect(result.skipped, 0);
    expect(result.appliedChangeIds, <String>['setting-after-failure-change']);
    expect(result.errors.single, contains('activity_segment'));
    expect(result.errors.single, contains('duplicate-segment-change'));
    expect(await db.getSetting('sync.afterFailure'), 'applied');
    expect(
      await stateStore.getStateByServerId(
        objectType: 'activity_segment',
        serverId: 'segment-server-duplicate',
      ),
      isNull,
    );
    expect(
      await _tableRows(db, 'activity_segments'),
      hasLength(1),
    );
  });

  test('repairs outlook orphan events during pull summary', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final stateStore = SyncObjectStateStore(db);

    await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            uid: 'outlook_event:remote-calendar-orphan:event-1',
            dtstamp: DateTime.utc(2026, 6, 10),
            summary: 'Orphan outlook event',
            dtstart: DateTime.utc(2026, 6, 10, 9),
            source: const Value('outlook'),
            eventCalendarId: const Value(null),
            colorHex: const Value('#4477aa'),
          ),
        );

    final result = await _applyChanges(db, stateStore, <Map<String, Object?>>[
      _change(
        changeId: 'setting-change-for-repair',
        objectType: 'user_setting',
        serverId: 'setting-repair',
        uid: 'sync.repair',
        payload: <String, Object?>{
          'settingValue': 'ran',
        },
      ),
    ]);

    expect(result.applied, 1);
    expect(result.orphanCalendarEvents, 1);
    final event = _singleWhere(
      await _tableRows(db, 'calendar_events'),
      (row) => row['summary'] == 'Orphan outlook event',
    );
    expect(event['event_calendar_id'], isA<int>());
    final calendar = await _rowById(
      db,
      'event_calendars',
      event['event_calendar_id'] as int,
    );
    expect(calendar?['source'], 'outlook');
    expect(calendar?['sync_url'], 'remote-calendar-orphan');
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
