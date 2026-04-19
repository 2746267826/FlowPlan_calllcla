import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../storage/app_storage.dart';
import 'tables/activity_records_table.dart';
import 'tables/app_usage_rules_table.dart';
import 'tables/calendar_events_table.dart';
import 'tables/event_calendars_table.dart';
import 'tables/projects_table.dart';
import 'tables/tags_table.dart';
import 'tables/task_items_table.dart';
import 'tables/task_lists_table.dart';
import 'tables/time_blocks_table.dart';

part 'app_database.g.dart';

@DriftDatabase(tables: [
  TaskItems,
  CalendarEvents,
  TimeBlocks,
  Tags,
  Projects,
  ActivityRecords,
  AppUsageRules,
  EventCalendars,
  TaskLists,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _insertDefaults();
          await _ensureAppSettingsTable();
          await _ensureRawActivityLogsTable();
          await _ensureTrackedInputEventsTable();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(eventCalendars);
            await m.createTable(taskLists);
            await _insertDefaults();
          }

          if (from < 3) {
            await customStatement(
              'ALTER TABLE activity_records ADD COLUMN duration_minutes INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE activity_records ADD COLUMN linked_task_id INTEGER',
            );
            await customStatement(
              'ALTER TABLE activity_records ADD COLUMN is_auto INTEGER NOT NULL DEFAULT 0',
            );
          }

          if (from < 4) {
            await customStatement(
              'ALTER TABLE activity_records ADD COLUMN key_count INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE activity_records ADD COLUMN mouse_clicks INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE activity_records ADD COLUMN mouse_move_px INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE activity_records ADD COLUMN scroll_px INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE activity_records ADD COLUMN key_sequence TEXT',
            );
          }

          if (from < 5) {
            await _ensureAppSettingsTable();
          }

          if (from < 6) {
            await _ensureRawActivityLogsTable();
          }

          if (from < 7) {
            await _ensureTrackedInputEventsTable();
          }

          if (from >= 7 && from < 8) {
            await customStatement(
              'ALTER TABLE tracked_input_events ADD COLUMN delta_x INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE tracked_input_events ADD COLUMN delta_y INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE tracked_input_events ADD COLUMN event_count INTEGER NOT NULL DEFAULT 1',
            );
            await customStatement(
              'ALTER TABLE tracked_input_events ADD COLUMN token_text TEXT',
            );
          }
        },
      );

  Future<void> _ensureAppSettingsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS app_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _ensureRawActivityLogsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS raw_activity_logs (
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
    await customStatement(
      'CREATE INDEX IF NOT EXISTS raw_activity_logs_day_key_idx '
      'ON raw_activity_logs(day_key, occurred_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS raw_activity_logs_record_id_idx '
      'ON raw_activity_logs(record_id, occurred_at)',
    );
  }

  Future<void> _ensureTrackedInputEventsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS tracked_input_events (
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
        delta_x INTEGER NOT NULL DEFAULT 0,
        delta_y INTEGER NOT NULL DEFAULT 0,
        move_distance INTEGER NOT NULL DEFAULT 0,
        event_count INTEGER NOT NULL DEFAULT 1,
        token_text TEXT,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS tracked_input_events_day_key_idx '
      'ON tracked_input_events(day_key, occurred_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS tracked_input_events_process_idx '
      'ON tracked_input_events(process_name, occurred_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS tracked_input_events_record_idx '
      'ON tracked_input_events(record_id, occurred_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS tracked_input_events_kind_idx '
      'ON tracked_input_events(event_kind, occurred_at)',
    );
  }

  Future<String?> getSetting(String key) async {
    final result = await customSelect(
      'SELECT setting_value FROM app_settings WHERE setting_key = ? LIMIT 1',
      variables: [Variable<String>(key)],
    ).getSingleOrNull();
    if (result == null) {
      return null;
    }
    return result.read<String>('setting_value');
  }

  Future<void> setSetting(String key, String value) async {
    final nowIso = DateTime.now().toIso8601String();
    await customStatement(
      '''
      INSERT INTO app_settings (setting_key, setting_value, updated_at)
      VALUES (?, ?, ?)
      ON CONFLICT(setting_key) DO UPDATE SET
        setting_value = excluded.setting_value,
        updated_at = excluded.updated_at
      ''',
      [key, value, nowIso],
    );
  }

  Future<bool> getBoolSetting(
    String key, {
    required bool defaultValue,
  }) async {
    final raw = await getSetting(key);
    if (raw == null) {
      return defaultValue;
    }
    switch (raw.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
        return true;
      case '0':
      case 'false':
      case 'no':
      case 'off':
        return false;
      default:
        return defaultValue;
    }
  }

  Future<void> setBoolSetting(String key, bool value) {
    return setSetting(key, value ? 'true' : 'false');
  }

  Future<String> getDatabasePath() async {
    final file = await resolveDatabaseFile();
    return file.path;
  }

  Future<void> exportToFile(String targetPath) async {
    final targetFile = File(targetPath);
    await targetFile.parent.create(recursive: true);
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    await customStatement('PRAGMA wal_checkpoint(FULL)');
    final escapedPath = targetFile.path.replaceAll("'", "''");
    await customStatement("VACUUM INTO '$escapedPath'");
  }

  Future<void> _insertDefaults() async {
    final now = DateTime.now();

    await into(eventCalendars).insert(
      EventCalendarsCompanion.insert(
        name: 'Personal',
        colorHex: const Value('#6B5EE4'),
        isDefault: const Value(true),
        createdAt: now,
      ),
    );

    await into(eventCalendars).insert(
      EventCalendarsCompanion.insert(
        name: 'Work',
        colorHex: const Value('#0EA8A0'),
        createdAt: now,
      ),
    );

    await into(taskLists).insert(
      TaskListsCompanion.insert(
        name: 'Inbox',
        colorHex: const Value('#6B5EE4'),
        emoji: const Value('IN'),
        isDefault: const Value(true),
        createdAt: now,
      ),
    );

    await into(taskLists).insert(
      TaskListsCompanion.insert(
        name: 'Work',
        colorHex: const Value('#F5935A'),
        emoji: const Value('WK'),
        createdAt: now,
      ),
    );

    await into(taskLists).insert(
      TaskListsCompanion.insert(
        name: 'Personal',
        colorHex: const Value('#0EA8A0'),
        emoji: const Value('ME'),
        createdAt: now,
      ),
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final file = await resolveDatabaseFile();
    await file.parent.create(recursive: true);
    return NativeDatabase.createInBackground(file);
  });
}

Future<File> resolveDatabaseFile() async {
  return resolveAppStorageFile('flowplan.db');
}
