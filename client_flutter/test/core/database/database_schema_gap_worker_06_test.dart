import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('app settings helpers handle missing, parsed, malformed, and deleted values',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);

    expect(await db.getSetting('worker06.missing'), isNull);
    expect(
      await db.getBoolSetting('worker06.bool', defaultValue: true),
      isTrue,
    );
    expect(await db.getIntSetting('worker06.int', defaultValue: 42), 42);

    await db.setBoolSetting('worker06.bool', true);
    expect(
      await db.getBoolSetting('worker06.bool', defaultValue: false),
      isTrue,
    );
    await db.setSetting('worker06.bool', ' OFF ');
    expect(
      await db.getBoolSetting('worker06.bool', defaultValue: true),
      isFalse,
    );
    await db.setSetting('worker06.bool', 'maybe');
    expect(
      await db.getBoolSetting('worker06.bool', defaultValue: true),
      isTrue,
    );

    await db.setIntSetting('worker06.int', 17);
    expect(await db.getIntSetting('worker06.int', defaultValue: 0), 17);
    await db.setSetting('worker06.int', 'not-an-int');
    expect(await db.getIntSetting('worker06.int', defaultValue: 99), 99);

    await db.deleteSetting('worker06.int');
    expect(await db.getSetting('worker06.int'), isNull);
  });

  test('core drift tables apply documented defaults on insert', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 6, 10, 9);

    final taskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'worker06-task',
            dtstamp: now,
            summary: 'Schema task',
          ),
        );
    final eventId = await db.into(db.calendarEvents).insert(
          CalendarEventsCompanion.insert(
            uid: 'worker06-event',
            dtstamp: now,
            summary: 'Schema event',
            dtstart: now,
          ),
        );
    final activityId = await db.into(db.activityRecords).insert(
          ActivityRecordsCompanion.insert(startTime: now),
        );
    final blockId = await db.into(db.timeBlocks).insert(
          TimeBlocksCompanion.insert(
            name: 'Focus block',
            startHour: 9,
            endHour: 10,
          ),
        );
    final listId = await db.into(db.taskLists).insert(
          TaskListsCompanion.insert(
            name: 'Worker list',
            createdAt: now,
          ),
        );
    final projectId = await db.into(db.projects).insert(
          ProjectsCompanion.insert(
            name: 'Worker project',
            colorHex: '#123456',
            createdAt: now,
          ),
        );

    final task = await (db.select(db.taskItems)
          ..where((table) => table.id.equals(taskId)))
        .getSingle();
    expect(task.location, isNull);
    expect(task.priority, 0);
    expect(task.status, 'NEEDS-ACTION');
    expect(task.percentComplete, 0);
    expect(task.categories, '[]');
    expect(task.durationMinutes, 60);
    expect(task.isSplittable, isFalse);
    expect(task.priorityLocal, 2);
    expect(task.isAutoScheduled, isTrue);
    expect(task.isLocked, isFalse);
    expect(task.reminderMinutesBefore, 15);

    final event = await (db.select(db.calendarEvents)
          ..where((table) => table.id.equals(eventId)))
        .getSingle();
    expect(event.status, 'CONFIRMED');
    expect(event.transp, 'OPAQUE');
    expect(event.source, 'local');
    expect(event.colorHex, '#6B5EE4');
    expect(event.isBlock, isFalse);

    final activity = await (db.select(db.activityRecords)
          ..where((table) => table.id.equals(activityId)))
        .getSingle();
    expect(activity.durationMinutes, 0);
    expect(activity.keyCount, 0);
    expect(activity.mouseClicks, 0);
    expect(activity.mouseMovePx, 0);
    expect(activity.scrollPx, 0);
    expect(activity.isAuto, isFalse);
    expect(activity.source, 'manual');

    final block = await (db.select(db.timeBlocks)
          ..where((table) => table.id.equals(blockId)))
        .getSingle();
    expect(block.startMinute, 0);
    expect(block.endMinute, 0);
    expect(block.weekdays, '[1,2,3,4,5,6,7]');
    expect(block.isActive, isTrue);
    expect(block.colorHex, '#E0E0E0');
    expect(block.emoji, isNotEmpty);

    final list = await (db.select(db.taskLists)
          ..where((table) => table.id.equals(listId)))
        .getSingle();
    expect(list.colorHex, '#0EA8A0');
    expect(list.emoji, isNull);
    expect(list.isVisible, isTrue);
    expect(list.isDefault, isFalse);
    expect(list.isArchived, isFalse);

    final project = await (db.select(db.projects)
          ..where((table) => table.id.equals(projectId)))
        .getSingle();
    expect(project.description, isNull);
    expect(project.deadline, isNull);
    expect(project.isArchived, isFalse);
  });

  test('database onCreate installs auxiliary schema, defaults, and indexes',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);

    expect(db.schemaVersion, 20);

    final taskLists = await db.select(db.taskLists).get();
    expect(taskLists.map((row) => row.name), containsAll(['收件箱', '工作', '个人']));
    expect(taskLists.where((row) => row.isDefault), hasLength(1));

    final calendars = await db.select(db.eventCalendars).get();
    expect(calendars.map((row) => row.name), containsAll(['默认日历', '工作日历']));
    expect(calendars.where((row) => row.isDefault), hasLength(1));

    final taskColumns = await _columnsFor(db, 'task_items');
    expect(taskColumns['location']?['type'], 'TEXT');

    final activityColumns = await _columnsFor(db, 'activity_records');
    expect(
      activityColumns.keys,
      containsAll(['device_id', 'platform', 'class_name']),
    );

    final trackedInputColumns = await _columnsFor(db, 'tracked_input_events');
    expect(
      trackedInputColumns.keys,
      containsAll(['delta_x', 'delta_y', 'event_count', 'token_text']),
    );
    expect(trackedInputColumns['event_count']?['dflt_value'], '1');

    final quarantineColumns =
        await _columnsFor(db, 'tracking_upload_quarantine');
    expect(
      quarantineColumns.keys,
      containsAll([
        'data_kind',
        'local_id',
        'reason',
        'server_payload_json',
        'created_at',
      ]),
    );

    final syncStateColumns = await _columnsFor(db, 'sync_object_states');
    expect(
      syncStateColumns.keys,
      containsAll(['object_type', 'local_id', 'sync_state', 'local_version']),
    );
    expect(syncStateColumns['local_version']?['dflt_value'], '1');

    final fileNodeColumns = await _columnsFor(db, 'file_nodes');
    expect(
      fileNodeColumns.keys,
      containsAll(['remote_id', 'hash_sha256', 'storage_object_id']),
    );

    expect(
      await _indexNamesFor(db, 'activity_records'),
      containsAll([
        'activity_records_device_idx',
        'activity_records_platform_idx',
        'activity_records_time_idx',
        'activity_records_source_time_idx',
      ]),
    );
    expect(
      await _indexNamesFor(db, 'tracked_input_events'),
      containsAll([
        'tracked_input_events_day_key_idx',
        'tracked_input_events_process_kind_idx',
      ]),
    );
    expect(
      await _indexNamesFor(db, 'tracking_upload_quarantine'),
      containsAll([
        'tracking_upload_quarantine_kind_idx',
        'tracking_upload_quarantine_created_idx',
      ]),
    );
    expect(
      await _indexNamesFor(db, 'file_nodes'),
      containsAll([
        'file_nodes_root_parent_idx',
        'file_nodes_root_path_idx',
        'file_nodes_remote_idx',
      ]),
    );
    expect(
      await _indexNamesFor(db, 'data_operation_logs'),
      containsAll([
        'data_operation_logs_time_idx',
        'data_operation_logs_entity_idx',
      ]),
    );
  });
}

Future<Map<String, Map<String, Object?>>> _columnsFor(
  AppDatabase db,
  String table,
) async {
  final rows = await db.customSelect('PRAGMA table_info($table)').get();
  return <String, Map<String, Object?>>{
    for (final row in rows)
      row.read<String>('name'): Map<String, Object?>.from(row.data),
  };
}

Future<Set<String>> _indexNamesFor(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA index_list($table)').get();
  return {
    for (final row in rows) row.read<String>('name'),
  };
}
