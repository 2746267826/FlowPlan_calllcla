import { randomUUID } from 'node:crypto';
import { DatabaseService } from '../../database/database.service';

export interface TestUser {
  id: string;
  displayName: string;
}

export interface TestDevice {
  id: string;
  deviceName: string;
  platform: string;
  clientDeviceId: string;
}

export async function createTestUser(
  db: DatabaseService,
  overrides: Partial<TestUser> = {},
): Promise<TestUser> {
  const id = overrides.id ?? randomUUID();
  const displayName = overrides.displayName ?? 'Test User';
  await db.query(
    `INSERT INTO users (id, display_name)
     VALUES ($1, $2)
     ON CONFLICT (id) DO UPDATE SET display_name = EXCLUDED.display_name`,
    [id, displayName],
  );
  return { id, displayName };
}

export async function createTestDevice(
  db: DatabaseService,
  userId: string,
  overrides: Partial<TestDevice> = {},
): Promise<TestDevice> {
  const id = overrides.id ?? randomUUID();
  const deviceName = overrides.deviceName ?? 'Test Device';
  const platform = overrides.platform ?? 'windows';
  const clientDeviceId = overrides.clientDeviceId ?? randomUUID();
  await db.query(
    `INSERT INTO devices (id, user_id, device_name, platform, client_device_id, connection_status)
     VALUES ($1, $2, $3, $4, $5, 'online')
     ON CONFLICT (user_id, client_device_id) DO UPDATE
       SET device_name = EXCLUDED.device_name,
           connection_status = 'online'`,
    [id, userId, deviceName, platform, clientDeviceId],
  );
  return { id, deviceName, platform, clientDeviceId };
}

/**
 * Remove all rows from every FlowPlanV2 business table.
 *
 * Tables are ordered so that child tables are deleted before their parents,
 * avoiding FK violations.  Tables referencing `devices` or `users` MUST
 * appear before those two in the list.
 */
export async function cleanDatabase(db: DatabaseService): Promise<void> {
  const tables = [
    // Model / AI (leaf tables first)
    'model_feedback_events',
    'model_runs',
    'model_versions',
    'model_definitions',
    'model_rule_profiles',
    'model_eval_cases',
    'model_rule_change_drafts',
    'ai_tool_calls',
    'ai_tool_policies',
    'ai_messages',
    'ai_operation_drafts',
    'ai_context_snapshots',
    'ai_conversations',
    'ai_provider_configs',
    // Reports / Push (leaf first)
    'report_evidence_links',
    'report_entries',
    'report_push_deliveries',
    'push_channels',
    'report_templates',
    'diary_entries',
    'report_documents',
    // Weather
    'weather_cache',
    'weather_locations',
    // Files — children before parents, device FKs before devices table
    'file_recent_items',
    'file_recommendations',
    'file_operation_logs',
    'file_node_device_locations',
    'file_identity_mappings',
    'file_transfer_events',
    'file_transfer_candidates',
    'file_transfer_chunks',
    'file_transfer_sessions',
    'file_conflict_candidates',
    'file_version_download_requests',
    'file_version_records',
    'file_storage_objects',
    'file_context_links',
    'cloud_file_tree_nodes',
    'file_providers',
    'file_nodes',
    'file_roots',
    'file_items',
    'file_folders',
    'file_folder_usages',
    // Schedule
    'plan_deviations',
    'schedule_draft_items',
    'schedule_runs',
    // Activity
    'activity_segment_evidence',
    'activity_interpretations',
    'task_work_logs',
    'activity_segments',
    'actual_activity_logs',
    'activity_hourly_stats',
    'activity_daily_stats',
    'input_hourly_stats',
    'input_daily_stats',
    // Tracking (FK to devices)
    'tracking_ingest_chunks',
    'tracking_ingest_batches',
    'sync_conflicts',
    'sync_mutations',
    'sync_changes',
    'sync_cursors',
    'sync_objects',
    // Outlook
    'outlook_sync_runs',
    'outlook_calendar_states',
    'outlook_auth_sessions',
    'outlook_object_mappings',
    'outlook_connections',
    // Client
    'client_import_sessions',
    // Admin
    'server_jobs',
    'admin_remote_configs',
    // Misc
    'reality_context_sources',
    'device_network_presence',
    'audit_logs',
    'device_connection_events',
    'devices',
    'users',
  ];

  // TRUNCATE ... CASCADE from the root handles all FK dependencies
  // automatically.  Much simpler and faster than a DELETE loop.
  await db.query('TRUNCATE TABLE users CASCADE');
}
