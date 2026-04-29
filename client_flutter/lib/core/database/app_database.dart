import 'package:drift/drift.dart';

import 'app_database_connection.dart'
    if (dart.library.io) 'app_database_connection_io.dart'
    if (dart.library.html) 'app_database_connection_web.dart';
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
  AppDatabase() : super(openAppDatabaseConnection());

  @override
  int get schemaVersion => 18;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _insertDefaults();
          await _ensureAppSettingsTable();
          await _ensureRawActivityLogsTable();
          await _ensureTrackedInputEventsTable();
          await _ensureTaskScheduleSegmentsTable();
          await _ensureDataOperationLogsTable();
          await _ensureActivityRecordDeviceColumns();
          await _ensureServerSyncTables();
          await _ensureTrackerPerformanceSchema();
          await _ensureActualAndFusionTables();
          await _ensureReportsAndPushTables();
          await _ensureFileManagementTables();
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

          if (from < 9) {
            await _ensureTaskScheduleSegmentsTable();
            await _ensureDataOperationLogsTable();
          }

          if (from < 10) {
            await _ensureActivityRecordDeviceColumns();
          }

          if (from < 11) {
            await _ensureServerSyncTables();
          }

          if (from < 12) {
            await _ensureTrackerPerformanceSchema();
          }

          if (from < 13) {
            await _ensureActualAndFusionTables();
          }

          if (from < 14) {
            await _ensureReportsAndPushTables();
          }

          if (from < 15) {
            await _ensureFileManagementTables();
          }

          if (from < 16) {
            await _ensureFileManagementTables();
          }

          if (from < 17) {
            await _ensureFileManagementTables();
            await _ensureCloudDriveCacheColumns();
          }

          if (from < 18) {
            await _ensureTaskLocationColumn();
          }
        },
      );

  Future<void> _ensureTaskLocationColumn() async {
    final columns = await customSelect('PRAGMA table_info(task_items)').get();
    final hasLocation = columns.any((row) => row.data['name'] == 'location');
    if (hasLocation) {
      return;
    }
    await customStatement(
      'ALTER TABLE task_items ADD COLUMN location TEXT',
    );
  }

  Future<void> _ensureFileManagementTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS file_folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        folder_uid TEXT NOT NULL UNIQUE,
        provider TEXT NOT NULL DEFAULT 'local',
        display_name TEXT NOT NULL,
        local_path TEXT,
        remote_id TEXT,
        parent_path TEXT,
        source_context TEXT,
        pinned INTEGER NOT NULL DEFAULT 0,
        availability TEXT NOT NULL DEFAULT 'local',
        use_count INTEGER NOT NULL DEFAULT 0,
        last_used_at TEXT,
        metadata_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS file_folders_provider_path_idx '
      'ON file_folders(provider, local_path)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS file_folders_recent_idx '
      'ON file_folders(pinned, last_used_at, use_count)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS file_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_uid TEXT NOT NULL UNIQUE,
        provider TEXT NOT NULL DEFAULT 'local',
        display_name TEXT NOT NULL,
        folder_id INTEGER,
        local_path TEXT,
        remote_id TEXT,
        mime_type TEXT,
        size_bytes INTEGER,
        modified_at TEXT,
        availability TEXT NOT NULL DEFAULT 'local',
        preview_mode TEXT NOT NULL DEFAULT 'none',
        metadata_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS file_items_folder_idx '
      'ON file_items(folder_id, display_name)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS file_items_provider_path_idx '
      'ON file_items(provider, local_path)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS file_nodes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        node_uid TEXT NOT NULL UNIQUE,
        remote_id TEXT,
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
        hash_sha256 TEXT,
        storage_object_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS file_nodes_root_parent_idx '
      'ON file_nodes(root_folder_id, parent_node_id, item_type, display_name)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS file_nodes_root_path_idx '
      'ON file_nodes(root_folder_id, relative_path)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS file_nodes_name_idx '
      'ON file_nodes(display_name)',
    );
    await _ensureCloudDriveCacheColumns();

    await customStatement('''
      CREATE TABLE IF NOT EXISTS file_context_links (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        link_uid TEXT NOT NULL UNIQUE,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        target_type TEXT NOT NULL,
        target_id INTEGER NOT NULL,
        relation_type TEXT NOT NULL DEFAULT 'manual',
        confidence REAL NOT NULL DEFAULT 1.0,
        reason TEXT,
        status TEXT NOT NULL DEFAULT 'confirmed',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        confirmed_at TEXT
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS file_context_links_entity_idx '
      'ON file_context_links(entity_type, entity_id, status)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS file_context_links_target_idx '
      'ON file_context_links(target_type, target_id)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS file_folder_usages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        usage_uid TEXT NOT NULL UNIQUE,
        folder_id INTEGER NOT NULL,
        entity_type TEXT,
        entity_id TEXT,
        action TEXT NOT NULL,
        source TEXT NOT NULL DEFAULT 'user',
        used_at TEXT NOT NULL,
        metadata_json TEXT NOT NULL DEFAULT '{}'
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS file_folder_usages_recent_idx '
      'ON file_folder_usages(used_at, folder_id)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS file_version_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        version_uid TEXT NOT NULL UNIQUE,
        file_id INTEGER NOT NULL,
        provider TEXT NOT NULL DEFAULT 'kopia',
        version_ref TEXT NOT NULL,
        display_name TEXT NOT NULL,
        size_bytes INTEGER,
        modified_at TEXT,
        checksum TEXT,
        source_device TEXT,
        source_backend TEXT,
        note TEXT,
        metadata_json TEXT NOT NULL DEFAULT '{}',
        created_at TEXT NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS file_version_records_file_idx '
      'ON file_version_records(file_id, modified_at)',
    );
  }

  Future<void> _ensureCloudDriveCacheColumns() async {
    final columns = await customSelect('PRAGMA table_info(file_nodes)').get();
    final names = columns.map((row) => row.read<String>('name')).toSet();
    if (!names.contains('remote_id')) {
      await customStatement('ALTER TABLE file_nodes ADD COLUMN remote_id TEXT');
    }
    if (!names.contains('hash_sha256')) {
      await customStatement('ALTER TABLE file_nodes ADD COLUMN hash_sha256 TEXT');
    }
    if (!names.contains('storage_object_id')) {
      await customStatement('ALTER TABLE file_nodes ADD COLUMN storage_object_id TEXT');
    }
    await customStatement(
      'CREATE INDEX IF NOT EXISTS file_nodes_remote_idx '
      'ON file_nodes(remote_id)',
    );
  }

  Future<void> _ensureReportsAndPushTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS report_documents (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        report_uid TEXT NOT NULL UNIQUE,
        report_type TEXT NOT NULL,
        period_start TEXT NOT NULL,
        period_end TEXT NOT NULL,
        title TEXT NOT NULL,
        summary_markdown TEXT NOT NULL,
        metrics_json TEXT NOT NULL DEFAULT '{}',
        source_snapshot_json TEXT NOT NULL DEFAULT '{}',
        status TEXT NOT NULL DEFAULT 'draft',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        confirmed_at TEXT
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS report_documents_type_period_idx '
      'ON report_documents(report_type, period_start, period_end)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS report_documents_status_idx '
      'ON report_documents(status, updated_at)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS diary_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        diary_uid TEXT NOT NULL UNIQUE,
        entry_date TEXT NOT NULL,
        title TEXT NOT NULL,
        body_markdown TEXT NOT NULL,
        source_report_id INTEGER,
        linked_task_ids_json TEXT NOT NULL DEFAULT '[]',
        linked_file_ids_json TEXT NOT NULL DEFAULT '[]',
        location_json TEXT NOT NULL DEFAULT '{}',
        weather_json TEXT NOT NULL DEFAULT '{}',
        status TEXT NOT NULL DEFAULT 'draft',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        confirmed_at TEXT
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS diary_entries_date_idx '
      'ON diary_entries(entry_date, status)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS report_push_deliveries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        delivery_uid TEXT NOT NULL UNIQUE,
        report_id INTEGER,
        diary_id INTEGER,
        channel TEXT NOT NULL,
        target TEXT,
        payload_json TEXT NOT NULL DEFAULT '{}',
        status TEXT NOT NULL DEFAULT 'pending',
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        scheduled_at TEXT NOT NULL,
        sent_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS report_push_deliveries_status_idx '
      'ON report_push_deliveries(status, scheduled_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS report_push_deliveries_report_idx '
      'ON report_push_deliveries(report_id, channel)',
    );
  }

  Future<void> _ensureActualAndFusionTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS actual_activity_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        actual_uid TEXT NOT NULL UNIQUE,
        title TEXT NOT NULL,
        start_at TEXT NOT NULL,
        end_at TEXT NOT NULL,
        source_type TEXT NOT NULL,
        source_id TEXT,
        source_payload_json TEXT NOT NULL DEFAULT '{}',
        confidence REAL NOT NULL DEFAULT 1.0,
        status TEXT NOT NULL DEFAULT 'candidate',
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        confirmed_at TEXT,
        rejected_at TEXT,
        merged_into_id INTEGER
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS actual_activity_logs_status_time_idx '
      'ON actual_activity_logs(status, start_at, end_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS actual_activity_logs_source_idx '
      'ON actual_activity_logs(source_type, source_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS actual_activity_logs_time_idx '
      'ON actual_activity_logs(start_at, end_at)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS activity_segments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        segment_uid TEXT NOT NULL UNIQUE,
        start_at TEXT NOT NULL,
        end_at TEXT NOT NULL,
        primary_process_name TEXT,
        primary_window_title TEXT,
        category TEXT,
        label TEXT,
        source_record_ids_json TEXT NOT NULL DEFAULT '[]',
        evidence_json TEXT NOT NULL DEFAULT '{}',
        confidence REAL NOT NULL DEFAULT 0.5,
        status TEXT NOT NULL DEFAULT 'candidate',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_segments_time_idx '
      'ON activity_segments(start_at, end_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_segments_status_idx '
      'ON activity_segments(status, start_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_segments_category_idx '
      'ON activity_segments(category, start_at)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS activity_interpretations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        interpretation_uid TEXT NOT NULL UNIQUE,
        segment_id INTEGER NOT NULL,
        summary TEXT NOT NULL,
        inferred_project TEXT,
        inferred_document TEXT,
        inferred_task_id INTEGER,
        confidence REAL NOT NULL DEFAULT 0.5,
        evidence_json TEXT NOT NULL DEFAULT '{}',
        status TEXT NOT NULL DEFAULT 'candidate',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_interpretations_segment_idx '
      'ON activity_interpretations(segment_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_interpretations_task_idx '
      'ON activity_interpretations(inferred_task_id, status)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS task_work_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        work_uid TEXT NOT NULL UNIQUE,
        task_id INTEGER NOT NULL,
        segment_id INTEGER,
        actual_id INTEGER,
        start_at TEXT NOT NULL,
        end_at TEXT NOT NULL,
        duration_minutes INTEGER NOT NULL DEFAULT 0,
        confidence REAL NOT NULL DEFAULT 0.5,
        source_type TEXT NOT NULL,
        evidence_json TEXT NOT NULL DEFAULT '{}',
        status TEXT NOT NULL DEFAULT 'candidate',
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS task_work_logs_task_time_idx '
      'ON task_work_logs(task_id, start_at, end_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS task_work_logs_segment_idx '
      'ON task_work_logs(segment_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS task_work_logs_actual_idx '
      'ON task_work_logs(actual_id)',
    );
  }

  Future<void> _ensureTrackerPerformanceSchema() async {
    await _ensureTrackerPerformanceIndexes();
    await _ensureTrackerAggregateTables();
  }

  Future<void> _ensureTrackerPerformanceIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_records_time_idx '
      'ON activity_records(start_time, end_time)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_records_category_time_idx '
      'ON activity_records(category, start_time)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_records_process_time_idx '
      'ON activity_records(process_name, start_time)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_records_package_time_idx '
      'ON activity_records(package_name, start_time)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_records_task_time_idx '
      'ON activity_records(linked_task_id, start_time)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_records_source_time_idx '
      'ON activity_records(source, start_time)',
    );

    await customStatement(
      'CREATE INDEX IF NOT EXISTS raw_activity_logs_time_idx '
      'ON raw_activity_logs(occurred_at, id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS raw_activity_logs_type_time_idx '
      'ON raw_activity_logs(entry_type, occurred_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS raw_activity_logs_process_time_idx '
      'ON raw_activity_logs(process_name, occurred_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS raw_activity_logs_category_time_idx '
      'ON raw_activity_logs(category, occurred_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS raw_activity_logs_ignored_time_idx '
      'ON raw_activity_logs(is_ignored, occurred_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS raw_activity_logs_window_time_idx '
      'ON raw_activity_logs(window_title, occurred_at)',
    );

    await customStatement(
      'CREATE INDEX IF NOT EXISTS tracked_input_events_time_idx '
      'ON tracked_input_events(occurred_at, sequence_id, id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS tracked_input_events_category_time_idx '
      'ON tracked_input_events(category, occurred_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS tracked_input_events_ignored_time_idx '
      'ON tracked_input_events(is_ignored, occurred_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS tracked_input_events_day_kind_idx '
      'ON tracked_input_events(day_key, event_kind, occurred_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS tracked_input_events_process_kind_idx '
      'ON tracked_input_events(process_name, event_kind, occurred_at)',
    );
  }

  Future<void> _ensureTrackerAggregateTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS activity_hourly_stats (
        bucket_start TEXT NOT NULL,
        bucket_end TEXT NOT NULL,
        device_id TEXT,
        platform TEXT,
        process_name TEXT,
        package_name TEXT,
        category TEXT,
        linked_task_id INTEGER,
        record_count INTEGER NOT NULL DEFAULT 0,
        total_minutes INTEGER NOT NULL DEFAULT 0,
        key_count INTEGER NOT NULL DEFAULT 0,
        mouse_clicks INTEGER NOT NULL DEFAULT 0,
        mouse_move_px INTEGER NOT NULL DEFAULT 0,
        scroll_px INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (
          bucket_start,
          device_id,
          platform,
          process_name,
          package_name,
          category,
          linked_task_id
        )
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_hourly_stats_bucket_idx '
      'ON activity_hourly_stats(bucket_start, bucket_end)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_hourly_stats_task_idx '
      'ON activity_hourly_stats(linked_task_id, bucket_start)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS activity_daily_stats (
        day_key TEXT NOT NULL,
        device_id TEXT,
        platform TEXT,
        process_name TEXT,
        package_name TEXT,
        category TEXT,
        linked_task_id INTEGER,
        record_count INTEGER NOT NULL DEFAULT 0,
        total_minutes INTEGER NOT NULL DEFAULT 0,
        key_count INTEGER NOT NULL DEFAULT 0,
        mouse_clicks INTEGER NOT NULL DEFAULT 0,
        mouse_move_px INTEGER NOT NULL DEFAULT 0,
        scroll_px INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (
          day_key,
          device_id,
          platform,
          process_name,
          package_name,
          category,
          linked_task_id
        )
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_daily_stats_day_idx '
      'ON activity_daily_stats(day_key)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_daily_stats_task_idx '
      'ON activity_daily_stats(linked_task_id, day_key)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS input_hourly_stats (
        bucket_start TEXT NOT NULL,
        bucket_end TEXT NOT NULL,
        device_id TEXT,
        platform TEXT,
        process_name TEXT,
        category TEXT,
        event_kind TEXT,
        event_count INTEGER NOT NULL DEFAULT 0,
        active_minutes INTEGER NOT NULL DEFAULT 0,
        keyboard_event_count INTEGER NOT NULL DEFAULT 0,
        mouse_button_event_count INTEGER NOT NULL DEFAULT 0,
        wheel_event_count INTEGER NOT NULL DEFAULT 0,
        mouse_move_event_count INTEGER NOT NULL DEFAULT 0,
        mouse_move_distance INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (
          bucket_start,
          device_id,
          platform,
          process_name,
          category,
          event_kind
        )
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS input_hourly_stats_bucket_idx '
      'ON input_hourly_stats(bucket_start, bucket_end)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS input_hourly_stats_process_idx '
      'ON input_hourly_stats(process_name, bucket_start)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS input_daily_stats (
        day_key TEXT NOT NULL,
        device_id TEXT,
        platform TEXT,
        process_name TEXT,
        category TEXT,
        event_kind TEXT,
        event_count INTEGER NOT NULL DEFAULT 0,
        active_minutes INTEGER NOT NULL DEFAULT 0,
        keyboard_event_count INTEGER NOT NULL DEFAULT 0,
        mouse_button_event_count INTEGER NOT NULL DEFAULT 0,
        wheel_event_count INTEGER NOT NULL DEFAULT 0,
        mouse_move_event_count INTEGER NOT NULL DEFAULT 0,
        mouse_move_distance INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (
          day_key,
          device_id,
          platform,
          process_name,
          category,
          event_kind
        )
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS input_daily_stats_day_idx '
      'ON input_daily_stats(day_key)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS input_daily_stats_process_idx '
      'ON input_daily_stats(process_name, day_key)',
    );
  }

  Future<void> _ensureActivityRecordDeviceColumns() async {
    final columns = await customSelect(
      'PRAGMA table_info(activity_records)',
    ).get();
    final names = columns
        .map((row) => row.read<String>('name'))
        .toSet();

    if (!names.contains('device_id')) {
      await customStatement(
        'ALTER TABLE activity_records ADD COLUMN device_id TEXT',
      );
    }
    if (!names.contains('platform')) {
      await customStatement(
        'ALTER TABLE activity_records ADD COLUMN platform TEXT',
      );
    }
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_records_device_idx '
      'ON activity_records(device_id, start_time)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS activity_records_platform_idx '
      'ON activity_records(platform, start_time)',
    );
  }

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

  Future<void> _ensureTaskScheduleSegmentsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS task_schedule_segments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_id INTEGER NOT NULL,
        segment_index INTEGER NOT NULL,
        start_at TEXT NOT NULL,
        end_at TEXT NOT NULL,
        source TEXT NOT NULL,
        plan_run_id TEXT,
        note TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS task_schedule_segments_task_idx '
      'ON task_schedule_segments(task_id, start_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS task_schedule_segments_time_idx '
      'ON task_schedule_segments(start_at, end_at)',
    );
  }

  Future<void> _ensureDataOperationLogsTable() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS data_operation_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        occurred_at TEXT NOT NULL,
        actor TEXT NOT NULL,
        action TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        summary TEXT NOT NULL,
        before_json TEXT,
        after_json TEXT,
        metadata_json TEXT
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS data_operation_logs_time_idx '
      'ON data_operation_logs(occurred_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS data_operation_logs_entity_idx '
      'ON data_operation_logs(entity_type, entity_id, occurred_at)',
    );
  }

  Future<void> _ensureServerSyncTables() async {
    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_object_states (
        object_type TEXT NOT NULL,
        local_id TEXT NOT NULL,
        server_id TEXT,
        uid TEXT,
        sync_state TEXT NOT NULL,
        local_version INTEGER NOT NULL DEFAULT 1,
        server_version INTEGER,
        origin_device_id TEXT,
        last_modified_device_id TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        last_synced_at TEXT,
        last_sync_error TEXT,
        PRIMARY KEY (object_type, local_id)
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS sync_object_states_server_idx '
      'ON sync_object_states(object_type, server_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS sync_object_states_state_idx '
      'ON sync_object_states(sync_state, updated_at)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS offline_mutations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        mutation_uid TEXT NOT NULL UNIQUE,
        object_type TEXT NOT NULL,
        local_id TEXT NOT NULL,
        server_id TEXT,
        action TEXT NOT NULL,
        base_server_version INTEGER,
        payload_json TEXT NOT NULL,
        changed_fields_json TEXT,
        created_at TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        status TEXT NOT NULL
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS offline_mutations_status_idx '
      'ON offline_mutations(status, id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS offline_mutations_object_idx '
      'ON offline_mutations(object_type, local_id, id)',
    );

    await customStatement('''
      CREATE TABLE IF NOT EXISTS sync_conflicts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        conflict_uid TEXT NOT NULL UNIQUE,
        object_type TEXT NOT NULL,
        local_id TEXT,
        server_id TEXT,
        base_version INTEGER,
        local_version INTEGER NOT NULL,
        server_version INTEGER NOT NULL,
        fields_json TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        resolved_at TEXT,
        resolution_json TEXT
      )
    ''');
    await customStatement(
      'CREATE INDEX IF NOT EXISTS sync_conflicts_status_idx '
      'ON sync_conflicts(status, created_at)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS sync_conflicts_object_idx '
      'ON sync_conflicts(object_type, server_id, created_at)',
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

  Future<void> deleteSetting(String key) async {
    await customStatement(
      'DELETE FROM app_settings WHERE setting_key = ?',
      [key],
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

  Future<int> getIntSetting(
    String key, {
    required int defaultValue,
  }) async {
    final raw = await getSetting(key);
    if (raw == null) {
      return defaultValue;
    }
    return int.tryParse(raw.trim()) ?? defaultValue;
  }

  Future<void> setIntSetting(String key, int value) {
    return setSetting(key, value.toString());
  }

  Future<String> getDatabasePath() async {
    return resolveAppDatabasePathForDisplay();
  }

  Future<void> exportToFile(String targetPath) async {
    return exportAppDatabase(this, targetPath);
  }

  Future<void> _insertDefaults() async {
    final now = DateTime.now();

    await into(eventCalendars).insert(
      EventCalendarsCompanion.insert(
        name: '\u9ed8\u8ba4\u65e5\u5386',
        colorHex: const Value('#6B5EE4'),
        isDefault: const Value(true),
        createdAt: now,
      ),
    );

    await into(eventCalendars).insert(
      EventCalendarsCompanion.insert(
        name: '\u5de5\u4f5c\u65e5\u5386',
        colorHex: const Value('#0EA8A0'),
        createdAt: now,
      ),
    );

    await into(taskLists).insert(
      TaskListsCompanion.insert(
        name: '\u6536\u4ef6\u7bb1',
        colorHex: const Value('#6B5EE4'),
        emoji: const Value('\u6536'),
        isDefault: const Value(true),
        createdAt: now,
      ),
    );

    await into(taskLists).insert(
      TaskListsCompanion.insert(
        name: '\u5de5\u4f5c',
        colorHex: const Value('#F5935A'),
        emoji: const Value('\u5de5'),
        createdAt: now,
      ),
    );

    await into(taskLists).insert(
      TaskListsCompanion.insert(
        name: '\u4e2a\u4eba',
        colorHex: const Value('#0EA8A0'),
        emoji: const Value('\u6211'),
        createdAt: now,
      ),
    );
  }
}
