import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/database/tables/activity_records_table.dart'
    as source_tables;
import 'package:flowplanv2/core/database/tables/task_items_table.dart'
    as source_tables;
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/test_database.dart';

void main() {
  test('source table getters expose every task and activity column', () {
    final tasks = source_tables.TaskItems();
    final taskColumns = <Object? Function()>[
      () => tasks.id,
      () => tasks.uid,
      () => tasks.dtstamp,
      () => tasks.summary,
      () => tasks.description,
      () => tasks.location,
      () => tasks.dtstart,
      () => tasks.due,
      () => tasks.completed,
      () => tasks.priority,
      () => tasks.status,
      () => tasks.percentComplete,
      () => tasks.categories,
      () => tasks.rrule,
      () => tasks.durationMinutes,
      () => tasks.isSplittable,
      () => tasks.priorityLocal,
      () => tasks.isAutoScheduled,
      () => tasks.taskListId,
      () => tasks.tagId,
      () => tasks.isLocked,
      () => tasks.reminderMinutesBefore,
    ];

    final activities = source_tables.ActivityRecords();
    final activityColumns = <Object? Function()>[
      () => activities.id,
      () => activities.startTime,
      () => activities.endTime,
      () => activities.durationMinutes,
      () => activities.keyCount,
      () => activities.mouseClicks,
      () => activities.mouseMovePx,
      () => activities.scrollPx,
      () => activities.keySequence,
      () => activities.manualLabel,
      () => activities.processName,
      () => activities.windowTitle,
      () => activities.packageName,
      () => activities.category,
      () => activities.appUsageRuleId,
      () => activities.linkedTaskId,
      () => activities.isAuto,
      () => activities.source,
    ];

    for (final getter in [...taskColumns, ...activityColumns]) {
      expect(getter, throwsUnsupportedError);
    }
  });

  test('task and activity companions serialize explicit nullable values',
      () async {
    final now = DateTime(2026, 6, 10, 9);
    final task = TaskItem(
      id: 7,
      uid: 'task-gap3',
      dtstamp: now,
      summary: 'Companion task',
      description: 'notes',
      location: 'Desk',
      dtstart: now,
      due: now.add(const Duration(hours: 1)),
      completed: null,
      priority: 5,
      status: 'IN-PROCESS',
      percentComplete: 40,
      categories: '["focus"]',
      rrule: 'FREQ=DAILY',
      durationMinutes: 90,
      isSplittable: true,
      priorityLocal: 1,
      isAutoScheduled: false,
      taskListId: 3,
      tagId: 'tag-gap3',
      isLocked: true,
      reminderMinutesBefore: 45,
    );
    final taskRoundTrip = TaskItem.fromJson(task.toJson());
    expect(taskRoundTrip, task);
    expect(task.toColumns(true).keys, containsAll(<String>[
      'location',
      'dtstart',
      'due',
      'rrule',
      'task_list_id',
      'tag_id',
    ]));
    expect(task.toColumns(false).keys, contains('completed'));

    final taskCompanion = TaskItemsCompanion.insert(
      uid: 'task-insert-gap3',
      dtstamp: now,
      summary: 'Inserted task',
      description: const Value('body'),
      location: const Value('Cafe'),
      dtstart: Value(now),
      due: Value(now.add(const Duration(hours: 2))),
      completed: const Value(null),
      priority: const Value(3),
      status: const Value('NEEDS-ACTION'),
      percentComplete: const Value(10),
      categories: const Value('["a"]'),
      rrule: const Value('FREQ=WEEKLY'),
      durationMinutes: const Value(120),
      isSplittable: const Value(true),
      priorityLocal: const Value(1),
      isAutoScheduled: const Value(false),
      taskListId: const Value(4),
      tagId: const Value('tag-1'),
      isLocked: const Value(true),
      reminderMinutesBefore: const Value(5),
    ).copyWith(summary: const Value('Updated task'));
    expect(taskCompanion.toColumns(true).keys, containsAll(<String>[
      'uid',
      'summary',
      'location',
      'completed',
      'is_locked',
      'reminder_minutes_before',
    ]));

    final activity = ActivityRecord(
      id: 9,
      startTime: now,
      endTime: now.add(const Duration(minutes: 25)),
      durationMinutes: 25,
      keyCount: 100,
      mouseClicks: 8,
      mouseMovePx: 900,
      scrollPx: 1200,
      keySequence: 'abc',
      manualLabel: 'Manual focus',
      processName: 'Code.exe',
      windowTitle: 'tests',
      packageName: 'com.flowplanv2',
      category: 'coding',
      appUsageRuleId: 'rule-1',
      linkedTaskId: 7,
      isAuto: true,
      source: 'android_usage',
    );
    final activityRoundTrip = ActivityRecord.fromJson(activity.toJson());
    expect(activityRoundTrip, activity);
    expect(activity.toColumns(true).keys, containsAll(<String>[
      'end_time',
      'key_sequence',
      'manual_label',
      'process_name',
      'package_name',
      'linked_task_id',
    ]));

    final activityCompanion = ActivityRecordsCompanion.insert(
      startTime: now,
      endTime: Value(now.add(const Duration(minutes: 10))),
      durationMinutes: const Value(10),
      keyCount: const Value(12),
      mouseClicks: const Value(3),
      mouseMovePx: const Value(45),
      scrollPx: const Value(60),
      keySequence: const Value('xyz'),
      manualLabel: const Value('Review'),
      processName: const Value('Browser'),
      windowTitle: const Value('Docs'),
      packageName: const Value('com.browser'),
      category: const Value('research'),
      appUsageRuleId: const Value('rule-2'),
      linkedTaskId: const Value(8),
      isAuto: const Value(true),
      source: const Value('usage_stats'),
    ).copyWith(source: const Value('manual_edit'));
    expect(activityCompanion.toColumns(true).keys, containsAll(<String>[
      'start_time',
      'end_time',
      'duration_minutes',
      'mouse_move_px',
      'app_usage_rule_id',
      'source',
    ]));
  });

  test('task and activity inserts apply defaults and explicit edge values',
      () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final now = DateTime.utc(2026, 6, 10, 10);

    final defaultTaskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'default-task-gap3',
            dtstamp: now,
            summary: 'Default task',
          ),
        );
    final explicitTaskId = await db.into(db.taskItems).insert(
          TaskItemsCompanion.insert(
            uid: 'explicit-task-gap3',
            dtstamp: now,
            summary: 'Explicit task',
            location: const Value('Meeting room'),
            completed: Value(now.add(const Duration(minutes: 30))),
            durationMinutes: const Value(0),
            isSplittable: const Value(true),
            isAutoScheduled: const Value(false),
            taskListId: const Value(null),
            reminderMinutesBefore: const Value(0),
          ),
        );
    final defaultActivityId = await db.into(db.activityRecords).insert(
          ActivityRecordsCompanion.insert(startTime: now),
        );
    final explicitActivityId = await db.into(db.activityRecords).insert(
          ActivityRecordsCompanion.insert(
            startTime: now,
            endTime: Value(now.add(const Duration(minutes: 1))),
            durationMinutes: const Value(1),
            keyCount: const Value(2),
            mouseClicks: const Value(3),
            mouseMovePx: const Value(4),
            scrollPx: const Value(5),
            keySequence: const Value('ab'),
            manualLabel: const Value(null),
            processName: const Value('worker.exe'),
            windowTitle: const Value('settings'),
            packageName: const Value('com.worker'),
            category: const Value('coverage'),
            appUsageRuleId: const Value('rule'),
            linkedTaskId: Value(explicitTaskId),
            isAuto: const Value(true),
            source: const Value('android_usage'),
          ),
        );

    final defaultTask = await (db.select(db.taskItems)
          ..where((table) => table.id.equals(defaultTaskId)))
        .getSingle();
    expect(defaultTask.location, isNull);
    expect(defaultTask.status, 'NEEDS-ACTION');
    expect(defaultTask.durationMinutes, 60);
    expect(defaultTask.isAutoScheduled, isTrue);
    expect(defaultTask.reminderMinutesBefore, 15);

    final explicitTask = await (db.select(db.taskItems)
          ..where((table) => table.id.equals(explicitTaskId)))
        .getSingle();
    expect(explicitTask.location, 'Meeting room');
    expect(explicitTask.durationMinutes, 0);
    expect(explicitTask.isSplittable, isTrue);
    expect(explicitTask.isAutoScheduled, isFalse);
    expect(explicitTask.reminderMinutesBefore, 0);

    final defaultActivity = await (db.select(db.activityRecords)
          ..where((table) => table.id.equals(defaultActivityId)))
        .getSingle();
    expect(defaultActivity.durationMinutes, 0);
    expect(defaultActivity.keyCount, 0);
    expect(defaultActivity.isAuto, isFalse);
    expect(defaultActivity.source, 'manual');

    final explicitActivity = await (db.select(db.activityRecords)
          ..where((table) => table.id.equals(explicitActivityId)))
        .getSingle();
    expect(explicitActivity.durationMinutes, 1);
    expect(explicitActivity.keyCount, 2);
    expect(explicitActivity.mouseClicks, 3);
    expect(explicitActivity.mouseMovePx, 4);
    expect(explicitActivity.scrollPx, 5);
    expect(explicitActivity.manualLabel, isNull);
    expect(explicitActivity.linkedTaskId, explicitTaskId);
    expect(explicitActivity.isAuto, isTrue);
    expect(explicitActivity.source, 'android_usage');
  });

  test('legacy database migrations add settings, tracking, and file columns',
      () async {
    await _withDatabase(
      _legacyDatabase(
        userVersion: 1,
        createSchema: (database) {
          _createLegacyTaskItems(database);
          _createLegacyActivityRecordsV1(database);
        },
      ),
      (db) async {
        final taskColumns = await _columnsFor(db, 'task_items');
        expect(taskColumns.keys, contains('location'));

        final activityColumns = await _columnsFor(db, 'activity_records');
        expect(activityColumns.keys, containsAll(<String>[
          'duration_minutes',
          'linked_task_id',
          'is_auto',
          'key_count',
          'mouse_clicks',
          'mouse_move_px',
          'scroll_px',
          'key_sequence',
          'device_id',
          'platform',
          'class_name',
        ]));
        expect(await _tableExists(db, 'app_settings'), isTrue);
        expect(await _tableExists(db, 'raw_activity_logs'), isTrue);
        expect(await _tableExists(db, 'tracked_input_events'), isTrue);
        expect(await _tableExists(db, 'sync_object_states'), isTrue);

        final defaultLists = await db
            .customSelect('SELECT name FROM task_lists ORDER BY id')
            .get();
        expect(
          defaultLists.map((row) => row.read<String>('name')),
          containsAll(<String>['收件箱', '工作', '个人']),
        );
      },
    );

    await _withDatabase(
      _legacyDatabase(
        userVersion: 7,
        createSchema: (database) {
          _createLegacyTaskItems(database);
          _createLegacyActivityRecordsV7(database);
          _createLegacyRawActivityLogs(database);
          _createLegacyTrackedInputEventsV7(database);
        },
      ),
      (db) async {
        final inputColumns = await _columnsFor(db, 'tracked_input_events');
        expect(inputColumns.keys, containsAll(<String>[
          'delta_x',
          'delta_y',
          'event_count',
          'token_text',
        ]));
        expect(inputColumns['event_count']?['dflt_value'], '1');
        expect(await _tableExists(db, 'task_schedule_segments'), isTrue);
        expect(await _tableExists(db, 'data_operation_logs'), isTrue);
      },
    );

    await _withDatabase(
      _legacyDatabase(
        userVersion: 16,
        createSchema: (database) {
          _createLegacyTaskItems(database);
          _createLegacyFileNodesWithoutCloudCache(database);
        },
      ),
      (db) async {
        final fileNodeColumns = await _columnsFor(db, 'file_nodes');
        expect(fileNodeColumns.keys, containsAll(<String>[
          'remote_id',
          'hash_sha256',
          'storage_object_id',
        ]));
        expect(await _indexNamesFor(db, 'file_nodes'),
            contains('file_nodes_remote_idx'));
      },
    );
  });
}

AppDatabase _legacyDatabase({
  required int userVersion,
  required void Function(dynamic database) createSchema,
}) {
  return AppDatabase.forTesting(
    NativeDatabase.memory(
      setup: (database) {
        createSchema(database);
        database.execute('PRAGMA user_version = $userVersion');
      },
    ),
  );
}

Future<void> _withDatabase(
  AppDatabase db,
  Future<void> Function(AppDatabase db) body,
) async {
  try {
    await body(db);
  } finally {
    await db.close();
  }
}

void _createLegacyTaskItems(dynamic database) {
  database.execute('''
    CREATE TABLE task_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uid TEXT NOT NULL,
      dtstamp INTEGER NOT NULL,
      summary TEXT NOT NULL,
      description TEXT,
      dtstart INTEGER,
      due INTEGER,
      completed INTEGER,
      priority INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'NEEDS-ACTION',
      percent_complete INTEGER NOT NULL DEFAULT 0,
      categories TEXT NOT NULL DEFAULT '[]',
      rrule TEXT,
      duration_minutes INTEGER NOT NULL DEFAULT 60,
      is_splittable INTEGER NOT NULL DEFAULT 0,
      priority_local INTEGER NOT NULL DEFAULT 2,
      is_auto_scheduled INTEGER NOT NULL DEFAULT 1,
      task_list_id INTEGER,
      tag_id TEXT,
      is_locked INTEGER NOT NULL DEFAULT 0,
      reminder_minutes_before INTEGER NOT NULL DEFAULT 15
    )
  ''');
}

void _createLegacyActivityRecordsV1(dynamic database) {
  database.execute('''
    CREATE TABLE activity_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      start_time INTEGER NOT NULL,
      end_time INTEGER,
      manual_label TEXT,
      process_name TEXT,
      window_title TEXT,
      package_name TEXT,
      category TEXT,
      app_usage_rule_id TEXT,
      source TEXT NOT NULL DEFAULT 'manual'
    )
  ''');
}

void _createLegacyActivityRecordsV7(dynamic database) {
  database.execute('''
    CREATE TABLE activity_records (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      start_time INTEGER NOT NULL,
      end_time INTEGER,
      duration_minutes INTEGER NOT NULL DEFAULT 0,
      key_count INTEGER NOT NULL DEFAULT 0,
      mouse_clicks INTEGER NOT NULL DEFAULT 0,
      mouse_move_px INTEGER NOT NULL DEFAULT 0,
      scroll_px INTEGER NOT NULL DEFAULT 0,
      key_sequence TEXT,
      manual_label TEXT,
      process_name TEXT,
      window_title TEXT,
      package_name TEXT,
      category TEXT,
      app_usage_rule_id TEXT,
      linked_task_id INTEGER,
      is_auto INTEGER NOT NULL DEFAULT 0,
      source TEXT NOT NULL DEFAULT 'manual'
    )
  ''');
}

void _createLegacyRawActivityLogs(dynamic database) {
  database.execute('''
    CREATE TABLE raw_activity_logs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entry_uid TEXT NOT NULL UNIQUE,
      occurred_at TEXT NOT NULL,
      day_key TEXT NOT NULL,
      entry_type TEXT NOT NULL,
      record_id INTEGER,
      process_name TEXT,
      window_title TEXT,
      category TEXT,
      label TEXT,
      is_ignored INTEGER NOT NULL DEFAULT 0,
      payload_json TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
}

void _createLegacyTrackedInputEventsV7(dynamic database) {
  database.execute('''
    CREATE TABLE tracked_input_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event_uid TEXT NOT NULL UNIQUE,
      sequence_id INTEGER NOT NULL,
      occurred_at TEXT NOT NULL,
      day_key TEXT NOT NULL,
      event_kind TEXT NOT NULL,
      record_id INTEGER,
      process_name TEXT,
      class_name TEXT,
      window_title TEXT,
      category TEXT,
      activity_label TEXT,
      is_ignored INTEGER NOT NULL DEFAULT 0,
      key_code INTEGER,
      key_label TEXT,
      mouse_button TEXT,
      wheel_delta INTEGER NOT NULL DEFAULT 0,
      move_distance INTEGER NOT NULL DEFAULT 0,
      payload_json TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''');
}

void _createLegacyFileNodesWithoutCloudCache(dynamic database) {
  database.execute('''
    CREATE TABLE file_nodes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      node_uid TEXT NOT NULL UNIQUE,
      root_folder_id INTEGER NOT NULL,
      parent_node_id INTEGER,
      item_type TEXT NOT NULL,
      display_name TEXT NOT NULL,
      local_path TEXT NOT NULL,
      relative_path TEXT NOT NULL,
      mime_type TEXT,
      size_bytes INTEGER,
      modified_at TEXT,
      availability TEXT NOT NULL DEFAULT 'local',
      scan_batch_id TEXT NOT NULL,
      depth INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
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

Future<bool> _tableExists(AppDatabase db, String table) async {
  final rows = await db.customSelect(
    'SELECT name FROM sqlite_master WHERE type = ? AND name = ? LIMIT 1',
    variables: [
      const Variable<String>('table'),
      Variable<String>(table),
    ],
  ).get();
  return rows.isNotEmpty;
}

Future<Set<String>> _indexNamesFor(AppDatabase db, String table) async {
  final rows = await db.customSelect('PRAGMA index_list($table)').get();
  return <String>{
    for (final row in rows) row.read<String>('name'),
  };
}
