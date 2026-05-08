-- ============================================================================
-- FlowPlanV2 P1 Schema v2
-- Cleaned: all ALTER TABLE merged into CREATE TABLE, GIN index added,
-- schema version tracking added.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---- Schema version tracking ----

CREATE TABLE IF NOT EXISTS schema_version (
  version_key text PRIMARY KEY,
  applied_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO schema_version (version_key) VALUES ('v2.0.0')
ON CONFLICT (version_key) DO NOTHING;

-- ---- Core identity ----

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_name text NOT NULL,
  platform text NOT NULL,
  client_device_id text,
  last_seen_at timestamptz,
  -- connection
  connection_status text NOT NULL DEFAULT 'offline',
  last_heartbeat_at timestamptz,
  last_connected_at timestamptz,
  last_disconnected_at timestamptz,
  last_connection_error text,
  -- metadata
  app_version text,
  runtime_platform text,
  network_type text,
  -- sync counters
  sync_pending_count integer NOT NULL DEFAULT 0,
  sync_failed_count integer NOT NULL DEFAULT 0,
  open_conflict_count integer NOT NULL DEFAULT 0,
  -- lifecycle
  revoked_at timestamptz,
  revoked_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, client_device_id)
);

CREATE TABLE IF NOT EXISTS device_connection_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  client_time timestamptz,
  server_time timestamptz NOT NULL DEFAULT now(),
  latency_ms integer,
  app_version text,
  platform text,
  network_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  sync_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  error_message text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS device_connection_events_device_time_idx
  ON device_connection_events(device_id, server_time DESC);
CREATE INDEX IF NOT EXISTS device_connection_events_user_time_idx
  ON device_connection_events(user_id, server_time DESC);

-- ---- Sync core ----

CREATE TABLE IF NOT EXISTS sync_objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  object_type text NOT NULL,
  uid text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  deleted_at timestamptz,
  server_version integer NOT NULL DEFAULT 1,
  origin_device_id uuid REFERENCES devices(id),
  last_modified_device_id uuid REFERENCES devices(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS sync_objects_user_type_uid_idx
  ON sync_objects(user_id, object_type, uid)
  WHERE uid IS NOT NULL AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS sync_objects_user_type_updated_idx
  ON sync_objects(user_id, object_type, updated_at);

-- GIN index for JSONB payload queries (analytics, search, activity)
CREATE INDEX IF NOT EXISTS sync_objects_payload_gin_idx
  ON sync_objects USING GIN (payload jsonb_path_ops);

-- Partial indexes for common payload field extraction (text keys only — no IMMUTABLE cast)
CREATE INDEX IF NOT EXISTS sync_objects_activity_start_time_idx
  ON sync_objects(user_id, (payload->>'startTime'))
  WHERE object_type IN ('activity_record')
    AND deleted_at IS NULL
    AND payload ? 'startTime';
CREATE INDEX IF NOT EXISTS sync_objects_input_timestamp_idx
  ON sync_objects(user_id, (payload->>'timestamp'))
  WHERE object_type IN ('tracked_input_event')
    AND deleted_at IS NULL
    AND payload ? 'timestamp';

CREATE TABLE IF NOT EXISTS sync_mutations (
  mutation_uid text PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  object_type text NOT NULL,
  local_id text NOT NULL,
  server_object_id uuid REFERENCES sync_objects(id),
  action text NOT NULL,
  base_server_version integer,
  changed_fields jsonb,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  result text NOT NULL,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sync_changes (
  id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  server_object_id uuid NOT NULL REFERENCES sync_objects(id) ON DELETE CASCADE,
  object_type text NOT NULL,
  action text NOT NULL,
  server_version integer NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS sync_changes_user_id_idx
  ON sync_changes(user_id, id);

CREATE TABLE IF NOT EXISTS sync_conflicts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  mutation_uid text REFERENCES sync_mutations(mutation_uid) ON DELETE SET NULL,
  object_type text NOT NULL,
  local_id text,
  server_object_id uuid REFERENCES sync_objects(id) ON DELETE CASCADE,
  base_version integer,
  local_version integer NOT NULL DEFAULT 1,
  server_version integer NOT NULL,
  fields jsonb NOT NULL DEFAULT '[]'::jsonb,
  status text NOT NULL DEFAULT 'open',
  resolution jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz
);

CREATE INDEX IF NOT EXISTS sync_conflicts_user_status_idx
  ON sync_conflicts(user_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS sync_cursors (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  cursor_value bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(user_id, device_id)
);

-- ---- Audit ----

CREATE TABLE IF NOT EXISTS audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  actor text NOT NULL,
  action text NOT NULL,
  entity_type text NOT NULL,
  entity_id text,
  summary text NOT NULL,
  before_json jsonb,
  after_json jsonb,
  metadata jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS audit_logs_user_time_idx
  ON audit_logs(user_id, occurred_at DESC);

-- ---- Activity & Tracking ----

CREATE TABLE IF NOT EXISTS activity_hourly_stats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bucket_start timestamptz NOT NULL,
  bucket_end timestamptz NOT NULL,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  platform text,
  process_name text,
  package_name text,
  category text,
  linked_task_id text,
  record_count integer NOT NULL DEFAULT 0,
  total_minutes integer NOT NULL DEFAULT 0,
  key_count integer NOT NULL DEFAULT 0,
  mouse_clicks integer NOT NULL DEFAULT 0,
  mouse_move_px integer NOT NULL DEFAULT 0,
  scroll_px integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS activity_hourly_stats_user_bucket_idx
  ON activity_hourly_stats(user_id, bucket_start, bucket_end);
CREATE INDEX IF NOT EXISTS activity_hourly_stats_user_task_idx
  ON activity_hourly_stats(user_id, linked_task_id, bucket_start);

CREATE TABLE IF NOT EXISTS activity_daily_stats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day_key date NOT NULL,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  platform text,
  process_name text,
  package_name text,
  category text,
  linked_task_id text,
  record_count integer NOT NULL DEFAULT 0,
  total_minutes integer NOT NULL DEFAULT 0,
  key_count integer NOT NULL DEFAULT 0,
  mouse_clicks integer NOT NULL DEFAULT 0,
  mouse_move_px integer NOT NULL DEFAULT 0,
  scroll_px integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS activity_daily_stats_user_day_idx
  ON activity_daily_stats(user_id, day_key);

CREATE TABLE IF NOT EXISTS input_hourly_stats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bucket_start timestamptz NOT NULL,
  bucket_end timestamptz NOT NULL,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  platform text,
  process_name text,
  category text,
  event_kind text,
  event_count integer NOT NULL DEFAULT 0,
  active_minutes integer NOT NULL DEFAULT 0,
  keyboard_event_count integer NOT NULL DEFAULT 0,
  mouse_button_event_count integer NOT NULL DEFAULT 0,
  wheel_event_count integer NOT NULL DEFAULT 0,
  mouse_move_event_count integer NOT NULL DEFAULT 0,
  mouse_move_distance integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS input_hourly_stats_user_bucket_idx
  ON input_hourly_stats(user_id, bucket_start, bucket_end);

CREATE TABLE IF NOT EXISTS input_daily_stats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day_key date NOT NULL,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  platform text,
  process_name text,
  category text,
  event_kind text,
  event_count integer NOT NULL DEFAULT 0,
  active_minutes integer NOT NULL DEFAULT 0,
  keyboard_event_count integer NOT NULL DEFAULT 0,
  mouse_button_event_count integer NOT NULL DEFAULT 0,
  wheel_event_count integer NOT NULL DEFAULT 0,
  mouse_move_event_count integer NOT NULL DEFAULT 0,
  mouse_move_distance integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS input_daily_stats_user_day_idx
  ON input_daily_stats(user_id, day_key);

-- ---- Actuals & Activity Understanding ----

CREATE TABLE IF NOT EXISTS actual_activity_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sync_object_id uuid REFERENCES sync_objects(id) ON DELETE SET NULL,
  actual_uid text NOT NULL,
  title text NOT NULL,
  start_at timestamptz NOT NULL,
  end_at timestamptz NOT NULL,
  duration_seconds integer NOT NULL DEFAULT 0,
  source_type text NOT NULL,
  source_id text,
  source_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  confidence numeric NOT NULL DEFAULT 1.0,
  status text NOT NULL DEFAULT 'candidate',
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  rejected_at timestamptz,
  merged_into_id uuid REFERENCES actual_activity_logs(id) ON DELETE SET NULL,
  UNIQUE(user_id, actual_uid)
);

CREATE INDEX IF NOT EXISTS actual_activity_logs_user_status_time_idx
  ON actual_activity_logs(user_id, status, start_at, end_at);
CREATE INDEX IF NOT EXISTS actual_activity_logs_user_source_idx
  ON actual_activity_logs(user_id, source_type, source_id);

CREATE TABLE IF NOT EXISTS activity_segments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sync_object_id uuid REFERENCES sync_objects(id) ON DELETE SET NULL,
  segment_uid text NOT NULL,
  start_at timestamptz NOT NULL,
  end_at timestamptz NOT NULL,
  duration_seconds integer NOT NULL DEFAULT 0,
  primary_process_name text,
  primary_app text,
  primary_window_title text,
  primary_file_path text,
  primary_project_path text,
  category text,
  label text,
  source_record_ids jsonb NOT NULL DEFAULT '[]'::jsonb,
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
  device_ids jsonb NOT NULL DEFAULT '[]'::jsonb,
  merge_method text NOT NULL DEFAULT 'rule',
  matched_task_id text,
  matched_event_id text,
  confidence numeric NOT NULL DEFAULT 0.5,
  status text NOT NULL DEFAULT 'candidate',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, segment_uid)
);

CREATE INDEX IF NOT EXISTS activity_segments_user_time_idx
  ON activity_segments(user_id, start_at, end_at);
CREATE INDEX IF NOT EXISTS activity_segments_user_status_idx
  ON activity_segments(user_id, status, start_at);

CREATE TABLE IF NOT EXISTS activity_interpretations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sync_object_id uuid REFERENCES sync_objects(id) ON DELETE SET NULL,
  interpretation_uid text NOT NULL,
  segment_id uuid REFERENCES activity_segments(id) ON DELETE CASCADE,
  title text,
  summary text NOT NULL,
  interpreted_type text NOT NULL DEFAULT 'unknown',
  inferred_project text,
  inferred_document text,
  inferred_task_id text,
  matched_task_id text,
  matched_event_id text,
  matched_folder_id text,
  confidence numeric NOT NULL DEFAULT 0.5,
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
  model_used text NOT NULL DEFAULT 'rule',
  reason_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'candidate',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, interpretation_uid)
);

CREATE INDEX IF NOT EXISTS activity_interpretations_user_segment_idx
  ON activity_interpretations(user_id, segment_id);
CREATE INDEX IF NOT EXISTS activity_interpretations_user_task_idx
  ON activity_interpretations(user_id, inferred_task_id, status);

CREATE TABLE IF NOT EXISTS activity_segment_evidence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  segment_id uuid NOT NULL REFERENCES activity_segments(id) ON DELETE CASCADE,
  source_type text NOT NULL,
  source_id text,
  evidence_summary text NOT NULL,
  weight integer NOT NULL DEFAULT 50,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS activity_segment_evidence_segment_idx
  ON activity_segment_evidence(user_id, segment_id, weight DESC);

CREATE TABLE IF NOT EXISTS task_work_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sync_object_id uuid REFERENCES sync_objects(id) ON DELETE SET NULL,
  work_uid text NOT NULL,
  task_id text NOT NULL,
  segment_id uuid REFERENCES activity_segments(id) ON DELETE SET NULL,
  actual_id uuid REFERENCES actual_activity_logs(id) ON DELETE SET NULL,
  start_at timestamptz NOT NULL,
  end_at timestamptz NOT NULL,
  duration_minutes integer NOT NULL DEFAULT 0,
  duration_seconds integer NOT NULL DEFAULT 0,
  confidence numeric NOT NULL DEFAULT 0.5,
  source_type text NOT NULL,
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'candidate',
  confirmed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, work_uid)
);

CREATE INDEX IF NOT EXISTS task_work_logs_user_task_time_idx
  ON task_work_logs(user_id, task_id, start_at, end_at);
CREATE INDEX IF NOT EXISTS task_work_logs_user_segment_idx
  ON task_work_logs(user_id, segment_id);

-- ---- Reports & Diary ----

CREATE TABLE IF NOT EXISTS report_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sync_object_id uuid REFERENCES sync_objects(id) ON DELETE SET NULL,
  report_uid text NOT NULL,
  report_type text NOT NULL,
  period_start timestamptz NOT NULL,
  period_end timestamptz NOT NULL,
  title text NOT NULL,
  summary_markdown text NOT NULL,
  metrics jsonb NOT NULL DEFAULT '{}'::jsonb,
  source_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'draft',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  UNIQUE(user_id, report_uid)
);

CREATE INDEX IF NOT EXISTS report_documents_user_type_period_idx
  ON report_documents(user_id, report_type, period_start, period_end);
CREATE INDEX IF NOT EXISTS report_documents_user_status_idx
  ON report_documents(user_id, status, updated_at);

CREATE TABLE IF NOT EXISTS report_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  report_id uuid REFERENCES report_documents(id) ON DELETE CASCADE,
  entry_type text NOT NULL DEFAULT 'fact',
  title text NOT NULL,
  body text NOT NULL,
  order_index integer NOT NULL DEFAULT 0,
  payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS report_entries_report_idx
  ON report_entries(user_id, report_id, order_index);

CREATE TABLE IF NOT EXISTS report_evidence_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  report_id uuid REFERENCES report_documents(id) ON DELETE CASCADE,
  entry_id uuid REFERENCES report_entries(id) ON DELETE CASCADE,
  source_type text NOT NULL,
  source_id text,
  evidence_type text NOT NULL DEFAULT 'fact',
  summary text,
  payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS report_evidence_links_report_idx
  ON report_evidence_links(user_id, report_id, source_type);

CREATE TABLE IF NOT EXISTS report_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL,
  template_type text NOT NULL,
  content_template text NOT NULL,
  variables_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, template_type, name)
);

CREATE INDEX IF NOT EXISTS report_templates_user_type_idx
  ON report_templates(user_id, template_type, is_default);

CREATE TABLE IF NOT EXISTS diary_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sync_object_id uuid REFERENCES sync_objects(id) ON DELETE SET NULL,
  diary_uid text NOT NULL,
  entry_date date NOT NULL,
  title text NOT NULL,
  body_markdown text NOT NULL,
  source_report_id uuid REFERENCES report_documents(id) ON DELETE SET NULL,
  linked_task_ids jsonb NOT NULL DEFAULT '[]'::jsonb,
  linked_file_ids jsonb NOT NULL DEFAULT '[]'::jsonb,
  location jsonb NOT NULL DEFAULT '{}'::jsonb,
  weather jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'draft',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  UNIQUE(user_id, diary_uid)
);

CREATE INDEX IF NOT EXISTS diary_entries_user_date_idx
  ON diary_entries(user_id, entry_date, status);

-- ---- Push ----

CREATE TABLE IF NOT EXISTS push_channels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  channel_type text NOT NULL,
  name text NOT NULL,
  status text NOT NULL DEFAULT 'enabled',
  config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_test_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS push_channels_user_status_idx
  ON push_channels(user_id, channel_type, status);

CREATE TABLE IF NOT EXISTS report_push_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sync_object_id uuid REFERENCES sync_objects(id) ON DELETE SET NULL,
  delivery_uid text NOT NULL,
  report_id uuid REFERENCES report_documents(id) ON DELETE SET NULL,
  diary_id uuid REFERENCES diary_entries(id) ON DELETE SET NULL,
  channel text NOT NULL,
  target text,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'pending',
  attempts integer NOT NULL DEFAULT 0,
  last_error text,
  scheduled_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, delivery_uid)
);

CREATE INDEX IF NOT EXISTS report_push_deliveries_user_status_idx
  ON report_push_deliveries(user_id, status, scheduled_at);
CREATE INDEX IF NOT EXISTS report_push_deliveries_user_report_idx
  ON report_push_deliveries(user_id, report_id, channel);

-- ---- Weather ----

CREATE TABLE IF NOT EXISTS weather_locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL,
  latitude numeric NOT NULL,
  longitude numeric NOT NULL,
  timezone text NOT NULL DEFAULT 'auto',
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS weather_locations_user_default_idx
  ON weather_locations(user_id, is_default);

CREATE TABLE IF NOT EXISTS weather_cache (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  location_id uuid REFERENCES weather_locations(id) ON DELETE CASCADE,
  provider_type text NOT NULL DEFAULT 'open_meteo',
  forecast_type text NOT NULL DEFAULT 'daily',
  forecast_time timestamptz NOT NULL DEFAULT now(),
  payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  summary text,
  expires_at timestamptz NOT NULL DEFAULT now() + interval '6 hours',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS weather_cache_user_location_idx
  ON weather_cache(user_id, location_id, forecast_type, forecast_time DESC);

-- ---- Files ----

CREATE TABLE IF NOT EXISTS file_roots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  root_uid text NOT NULL,
  name text NOT NULL,
  provider_type text NOT NULL DEFAULT 'local',
  root_uri text NOT NULL,
  root_display_path text,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  is_managed boolean NOT NULL DEFAULT false,
  scan_status text NOT NULL DEFAULT 'idle',
  last_scan_at timestamptz,
  last_error text,
  sync_policy text NOT NULL DEFAULT 'metadata_only',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, root_uid)
);

CREATE INDEX IF NOT EXISTS file_roots_user_provider_idx
  ON file_roots(user_id, provider_type, scan_status);

CREATE TABLE IF NOT EXISTS file_nodes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  node_uid text NOT NULL,
  root_id uuid REFERENCES file_roots(id) ON DELETE CASCADE,
  parent_id uuid REFERENCES file_nodes(id) ON DELETE SET NULL,
  node_type text NOT NULL,
  name text NOT NULL,
  relative_path text NOT NULL DEFAULT '',
  display_path text,
  provider_file_id text,
  local_path text,
  mime_type text,
  extension text,
  size_bytes bigint,
  mtime timestamptz,
  ctime timestamptz,
  hash_sha256 text,
  thumbnail_status text NOT NULL DEFAULT 'none',
  preview_status text NOT NULL DEFAULT 'none',
  index_status text NOT NULL DEFAULT 'none',
  is_deleted boolean NOT NULL DEFAULT false,
  is_missing boolean NOT NULL DEFAULT false,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, node_uid)
);

CREATE INDEX IF NOT EXISTS file_nodes_user_parent_idx
  ON file_nodes(user_id, root_id, parent_id, node_type, name);
CREATE INDEX IF NOT EXISTS file_nodes_user_search_idx
  ON file_nodes(user_id, name, relative_path);

CREATE TABLE IF NOT EXISTS file_node_device_locations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  node_id uuid NOT NULL REFERENCES file_nodes(id) ON DELETE CASCADE,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  local_path text,
  availability text NOT NULL DEFAULT 'available',
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE(user_id, node_id, device_id)
);

CREATE INDEX IF NOT EXISTS file_node_device_locations_user_node_idx
  ON file_node_device_locations(user_id, node_id, availability, last_seen_at DESC);

CREATE TABLE IF NOT EXISTS file_identity_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  node_id uuid REFERENCES file_nodes(id) ON DELETE CASCADE,
  provider_key text NOT NULL,
  provider_file_id text,
  storage_object_id uuid REFERENCES file_storage_objects(id) ON DELETE SET NULL,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  local_path text,
  hash_sha256 text,
  size_bytes bigint,
  modified_at timestamptz,
  confidence text NOT NULL DEFAULT 'metadata',
  status text NOT NULL DEFAULT 'active',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, provider_key, provider_file_id),
  UNIQUE(user_id, node_id, provider_key, device_id, local_path)
);

CREATE INDEX IF NOT EXISTS file_identity_mappings_node_idx
  ON file_identity_mappings(user_id, node_id, status, updated_at DESC);
CREATE INDEX IF NOT EXISTS file_identity_mappings_hash_idx
  ON file_identity_mappings(user_id, hash_sha256)
  WHERE hash_sha256 IS NOT NULL;

CREATE TABLE IF NOT EXISTS file_providers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider_key text NOT NULL,
  provider_type text NOT NULL,
  display_name text NOT NULL,
  priority integer NOT NULL DEFAULT 100,
  status text NOT NULL DEFAULT 'enabled',
  root_remote_id text,
  local_mirror_path text,
  mobile_download_root text,
  sync_mode text NOT NULL DEFAULT 'manual',
  capabilities jsonb NOT NULL DEFAULT '{}'::jsonb,
  config jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_tree_sync_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, provider_key)
);

CREATE INDEX IF NOT EXISTS file_providers_user_priority_idx
  ON file_providers(user_id, status, priority);

CREATE TABLE IF NOT EXISTS cloud_file_tree_nodes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider_key text NOT NULL,
  remote_id text NOT NULL,
  parent_remote_id text,
  path text NOT NULL,
  display_name text NOT NULL,
  item_type text NOT NULL,
  mime_type text,
  size_bytes bigint,
  etag text,
  ctag text,
  checksum text,
  local_path text,
  availability text NOT NULL DEFAULT 'remote_only',
  modified_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  tree_revision text,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, provider_key, remote_id)
);

CREATE INDEX IF NOT EXISTS cloud_file_tree_nodes_user_provider_path_idx
  ON cloud_file_tree_nodes(user_id, provider_key, path);
CREATE INDEX IF NOT EXISTS cloud_file_tree_nodes_user_parent_idx
  ON cloud_file_tree_nodes(user_id, provider_key, parent_remote_id);

CREATE TABLE IF NOT EXISTS file_storage_objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider_key text NOT NULL DEFAULT 'server_storage',
  object_key text NOT NULL,
  display_name text NOT NULL,
  size_bytes bigint NOT NULL DEFAULT 0,
  checksum text,
  chunk_size integer NOT NULL DEFAULT 5242880,
  chunk_count integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'available',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, provider_key, object_key)
);

CREATE INDEX IF NOT EXISTS file_storage_objects_user_provider_idx
  ON file_storage_objects(user_id, provider_key, updated_at);

CREATE TABLE IF NOT EXISTS file_transfer_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider_key text NOT NULL,
  direction text NOT NULL,
  file_name text NOT NULL,
  remote_id text,
  local_path text,
  object_key text,
  storage_object_id uuid REFERENCES file_storage_objects(id) ON DELETE SET NULL,
  -- extended fields
  source_device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  target_device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  source_node_id uuid REFERENCES file_nodes(id) ON DELETE SET NULL,
  target_root_id uuid REFERENCES file_roots(id) ON DELETE SET NULL,
  transfer_type text,
  strategy text NOT NULL DEFAULT 'server_relay',
  -- transfer state
  total_bytes bigint NOT NULL DEFAULT 0,
  chunk_size integer NOT NULL DEFAULT 5242880,
  expected_chunks integer NOT NULL DEFAULT 0,
  received_chunks integer NOT NULL DEFAULT 0,
  received_bytes bigint NOT NULL DEFAULT 0,
  progress_bytes bigint NOT NULL DEFAULT 0,
  speed_bytes_per_sec bigint NOT NULL DEFAULT 0,
  checksum text,
  actual_checksum_sha256 text,
  status text NOT NULL DEFAULT 'open',
  resume_token text NOT NULL DEFAULT gen_random_uuid()::text,
  error_message text,
  error_code text,
  started_at timestamptz,
  paused_at timestamptz,
  completed_at timestamptz,
  expires_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS file_transfer_sessions_user_status_idx
  ON file_transfer_sessions(user_id, direction, status, updated_at);

CREATE TABLE IF NOT EXISTS file_transfer_chunks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_id uuid NOT NULL REFERENCES file_transfer_sessions(id) ON DELETE CASCADE,
  chunk_index integer NOT NULL,
  start_byte bigint NOT NULL,
  end_byte bigint NOT NULL,
  size_bytes integer NOT NULL,
  checksum text,
  payload bytea,
  status text NOT NULL DEFAULT 'received',
  retry_count integer NOT NULL DEFAULT 0,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, session_id, chunk_index)
);

CREATE INDEX IF NOT EXISTS file_transfer_chunks_session_idx
  ON file_transfer_chunks(user_id, session_id, chunk_index);

CREATE TABLE IF NOT EXISTS file_transfer_candidates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_id uuid NOT NULL REFERENCES file_transfer_sessions(id) ON DELETE CASCADE,
  candidate_type text NOT NULL,
  source_address text,
  source_port integer,
  target_address text,
  target_port integer,
  protocol text NOT NULL DEFAULT 'server_api',
  priority integer NOT NULL DEFAULT 100,
  status text NOT NULL DEFAULT 'pending',
  latency_ms integer,
  bandwidth_estimate bigint,
  failure_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS file_transfer_candidates_session_idx
  ON file_transfer_candidates(user_id, session_id, priority);

CREATE TABLE IF NOT EXISTS device_network_presence (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  network_type text NOT NULL DEFAULT 'unknown',
  wifi_ssid_hash text,
  local_ip text,
  local_port integer,
  public_ip_hash text,
  nat_type text NOT NULL DEFAULT 'unknown',
  capabilities jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT now() + interval '10 minutes',
  UNIQUE(user_id, device_id)
);

CREATE INDEX IF NOT EXISTS device_network_presence_user_expiry_idx
  ON device_network_presence(user_id, expires_at DESC);

CREATE TABLE IF NOT EXISTS file_transfer_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  session_id uuid NOT NULL REFERENCES file_transfer_sessions(id) ON DELETE CASCADE,
  event_type text NOT NULL,
  message text,
  payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS file_transfer_events_session_idx
  ON file_transfer_events(user_id, session_id, created_at DESC);

CREATE TABLE IF NOT EXISTS file_conflict_candidates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  file_uid text,
  path text NOT NULL,
  provider_a text NOT NULL,
  provider_b text NOT NULL,
  version_a jsonb NOT NULL DEFAULT '{}'::jsonb,
  version_b jsonb NOT NULL DEFAULT '{}'::jsonb,
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'open',
  resolution jsonb,
  resolved_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS file_conflict_candidates_user_status_idx
  ON file_conflict_candidates(user_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS file_version_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sync_object_id uuid REFERENCES sync_objects(id) ON DELETE SET NULL,
  version_uid text NOT NULL,
  file_id text NOT NULL,
  provider text NOT NULL DEFAULT 'kopia',
  version_ref text NOT NULL,
  display_name text NOT NULL,
  size_bytes bigint,
  modified_at timestamptz,
  checksum text,
  source_device text,
  source_backend text,
  note text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, version_uid)
);

CREATE INDEX IF NOT EXISTS file_version_records_user_file_idx
  ON file_version_records(user_id, file_id, modified_at);

CREATE TABLE IF NOT EXISTS file_version_download_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  version_record_id uuid REFERENCES file_version_records(id) ON DELETE SET NULL,
  file_id text NOT NULL,
  provider text NOT NULL,
  version_ref text NOT NULL,
  target_mode text NOT NULL DEFAULT 'download_copy',
  target_path text,
  status text NOT NULL DEFAULT 'pending_confirmation',
  audit_note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz
);

CREATE INDEX IF NOT EXISTS file_version_download_requests_user_status_idx
  ON file_version_download_requests(user_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS file_context_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sync_object_id uuid REFERENCES sync_objects(id) ON DELETE SET NULL,
  link_uid text NOT NULL,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  target_type text NOT NULL,
  target_id text NOT NULL,
  relation_type text NOT NULL DEFAULT 'manual',
  confidence numeric NOT NULL DEFAULT 1.0,
  reason text,
  status text NOT NULL DEFAULT 'confirmed',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  UNIQUE(user_id, link_uid)
);

CREATE INDEX IF NOT EXISTS file_context_links_user_entity_idx
  ON file_context_links(user_id, entity_type, entity_id, status);
CREATE INDEX IF NOT EXISTS file_context_links_user_target_idx
  ON file_context_links(user_id, target_type, target_id);

CREATE TABLE IF NOT EXISTS file_recent_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  node_id uuid REFERENCES file_nodes(id) ON DELETE CASCADE,
  context_type text,
  context_id text,
  opened_at timestamptz NOT NULL DEFAULT now(),
  open_method text NOT NULL DEFAULT 'preview',
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS file_recent_items_user_time_idx
  ON file_recent_items(user_id, opened_at DESC);

CREATE TABLE IF NOT EXISTS file_recommendations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  node_id uuid REFERENCES file_nodes(id) ON DELETE CASCADE,
  target_type text NOT NULL,
  target_id text NOT NULL,
  score numeric NOT NULL DEFAULT 0,
  reason_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'pending',
  created_at timestamptz NOT NULL DEFAULT now(),
  handled_at timestamptz
);

CREATE INDEX IF NOT EXISTS file_recommendations_user_target_idx
  ON file_recommendations(user_id, target_type, target_id, status, score DESC);

CREATE TABLE IF NOT EXISTS file_operation_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  operation text NOT NULL,
  node_id uuid REFERENCES file_nodes(id) ON DELETE SET NULL,
  source_path text,
  target_path text,
  status text NOT NULL DEFAULT 'success',
  error_message text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS file_operation_logs_user_node_idx
  ON file_operation_logs(user_id, node_id, created_at DESC);

-- Legacy file tables (kept for backward compat, replaced by file_roots/file_nodes)
CREATE TABLE IF NOT EXISTS file_folders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sync_object_id uuid REFERENCES sync_objects(id) ON DELETE SET NULL,
  folder_uid text NOT NULL,
  provider text NOT NULL DEFAULT 'local',
  display_name text NOT NULL,
  local_path text,
  remote_id text,
  parent_path text,
  source_context text,
  pinned boolean NOT NULL DEFAULT false,
  availability text NOT NULL DEFAULT 'local',
  use_count integer NOT NULL DEFAULT 0,
  last_used_at timestamptz,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, folder_uid)
);

CREATE INDEX IF NOT EXISTS file_folders_user_provider_path_idx
  ON file_folders(user_id, provider, local_path);
CREATE INDEX IF NOT EXISTS file_folders_user_recent_idx
  ON file_folders(user_id, pinned, last_used_at, use_count);

CREATE TABLE IF NOT EXISTS file_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sync_object_id uuid REFERENCES sync_objects(id) ON DELETE SET NULL,
  file_uid text NOT NULL,
  provider text NOT NULL DEFAULT 'local',
  display_name text NOT NULL,
  folder_id uuid REFERENCES file_folders(id) ON DELETE SET NULL,
  local_path text,
  remote_id text,
  mime_type text,
  size_bytes bigint,
  modified_at timestamptz,
  availability text NOT NULL DEFAULT 'local',
  preview_mode text NOT NULL DEFAULT 'none',
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, file_uid)
);

CREATE INDEX IF NOT EXISTS file_items_user_folder_idx
  ON file_items(user_id, folder_id, display_name);
CREATE INDEX IF NOT EXISTS file_items_user_provider_path_idx
  ON file_items(user_id, provider, local_path);

CREATE TABLE IF NOT EXISTS file_folder_usages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sync_object_id uuid REFERENCES sync_objects(id) ON DELETE SET NULL,
  usage_uid text NOT NULL,
  folder_id text NOT NULL,
  entity_type text,
  entity_id text,
  action text NOT NULL,
  source text NOT NULL DEFAULT 'user',
  used_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE(user_id, usage_uid)
);

CREATE INDEX IF NOT EXISTS file_folder_usages_user_recent_idx
  ON file_folder_usages(user_id, used_at, folder_id);

-- ---- AI & Models ----

CREATE TABLE IF NOT EXISTS ai_provider_configs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider_key text NOT NULL,
  provider_type text NOT NULL DEFAULT 'openai_compatible',
  display_name text NOT NULL,
  base_url text NOT NULL DEFAULT 'https://api.openai.com/v1',
  model text NOT NULL DEFAULT '',
  api_key_ciphertext text,
  api_key_hint text,
  status text NOT NULL DEFAULT 'disabled',
  temperature numeric NOT NULL DEFAULT 0.2,
  max_output_tokens integer NOT NULL DEFAULT 1600,
  is_default boolean NOT NULL DEFAULT false,
  options jsonb NOT NULL DEFAULT '{}'::jsonb,
  last_tested_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, provider_key)
);

CREATE UNIQUE INDEX IF NOT EXISTS ai_provider_configs_user_default_idx
  ON ai_provider_configs(user_id, is_default)
  WHERE is_default IS TRUE;
CREATE INDEX IF NOT EXISTS ai_provider_configs_user_status_idx
  ON ai_provider_configs(user_id, status, updated_at DESC);

CREATE TABLE IF NOT EXISTS ai_conversations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source text NOT NULL DEFAULT 'flowplanv2',
  title text NOT NULL DEFAULT 'AI 对话',
  provider_key text,
  model text,
  status text NOT NULL DEFAULT 'open',
  context_scope jsonb NOT NULL DEFAULT '{}'::jsonb,
  summary text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  closed_at timestamptz
);

CREATE INDEX IF NOT EXISTS ai_conversations_user_updated_idx
  ON ai_conversations(user_id, status, updated_at DESC);

CREATE TABLE IF NOT EXISTS ai_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  conversation_id uuid NOT NULL REFERENCES ai_conversations(id) ON DELETE CASCADE,
  role text NOT NULL,
  content text NOT NULL,
  provider_key text,
  model text,
  token_usage jsonb NOT NULL DEFAULT '{}'::jsonb,
  tool_draft_ids jsonb NOT NULL DEFAULT '[]'::jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ai_messages_conversation_time_idx
  ON ai_messages(user_id, conversation_id, created_at);

CREATE TABLE IF NOT EXISTS ai_context_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  conversation_id uuid REFERENCES ai_conversations(id) ON DELETE SET NULL,
  context_type text NOT NULL DEFAULT 'mixed',
  payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  sensitive_policy_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  redaction_summary text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS ai_operation_drafts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source text NOT NULL DEFAULT 'admin',
  conversation_id text,
  title text NOT NULL,
  summary text,
  proposed_action text NOT NULL,
  target_type text,
  target_id text,
  status text NOT NULL DEFAULT 'pending_review',
  risk_level text NOT NULL DEFAULT 'normal',
  request_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  proposed_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  review_note text,
  reviewed_at timestamptz,
  execution_status text NOT NULL DEFAULT 'not_executed',
  execution_result jsonb NOT NULL DEFAULT '{}'::jsonb,
  executed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ai_operation_drafts_user_status_idx
  ON ai_operation_drafts(user_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS ai_tool_calls (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  conversation_id uuid REFERENCES ai_conversations(id) ON DELETE SET NULL,
  draft_id uuid REFERENCES ai_operation_drafts(id) ON DELETE SET NULL,
  tool_name text NOT NULL,
  input_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  output_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  risk_level text NOT NULL DEFAULT 'low',
  confirmed_by uuid REFERENCES devices(id) ON DELETE SET NULL,
  confirmed_at timestamptz,
  status text NOT NULL DEFAULT 'success',
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ai_tool_calls_user_time_idx
  ON ai_tool_calls(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS ai_tool_policies (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tool_name text NOT NULL,
  permission_level text NOT NULL DEFAULT 'draft_only',
  risk_level text NOT NULL DEFAULT 'low',
  allowed_scopes_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  denied_scopes_json jsonb NOT NULL DEFAULT '[]'::jsonb,
  requires_confirmation boolean NOT NULL DEFAULT true,
  requires_second_confirm boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, tool_name)
);

CREATE INDEX IF NOT EXISTS ai_tool_policies_user_tool_idx
  ON ai_tool_policies(user_id, tool_name);

-- ---- Model Center ----

CREATE TABLE IF NOT EXISTS model_definitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  model_key text NOT NULL,
  display_name text NOT NULL,
  category text NOT NULL,
  status text NOT NULL DEFAULT 'enabled',
  description text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, model_key)
);

CREATE INDEX IF NOT EXISTS model_definitions_user_category_idx
  ON model_definitions(user_id, category, status);

CREATE TABLE IF NOT EXISTS model_versions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  model_definition_id uuid NOT NULL REFERENCES model_definitions(id) ON DELETE CASCADE,
  version_key text NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  rule_profile_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  metrics_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  change_summary text,
  created_by text NOT NULL DEFAULT 'system',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  activated_at timestamptz,
  UNIQUE(user_id, model_definition_id, version_key)
);

CREATE INDEX IF NOT EXISTS model_versions_user_status_idx
  ON model_versions(user_id, model_definition_id, status, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS model_versions_one_active_idx
  ON model_versions(user_id, model_definition_id)
  WHERE status = 'active';

CREATE TABLE IF NOT EXISTS model_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  model_definition_id uuid REFERENCES model_definitions(id) ON DELETE SET NULL,
  model_version_id uuid REFERENCES model_versions(id) ON DELETE SET NULL,
  model_key text NOT NULL,
  model_version_key text,
  source text NOT NULL DEFAULT 'server',
  target_type text,
  target_id text,
  status text NOT NULL DEFAULT 'running',
  confidence numeric,
  input_summary_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  output_summary_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  failure_reason text,
  used_llm boolean NOT NULL DEFAULT false,
  llm_provider_key text,
  llm_model text,
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS model_runs_user_model_time_idx
  ON model_runs(user_id, model_key, started_at DESC);
CREATE INDEX IF NOT EXISTS model_runs_user_status_idx
  ON model_runs(user_id, status, started_at DESC);

CREATE TABLE IF NOT EXISTS model_feedback_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  model_definition_id uuid REFERENCES model_definitions(id) ON DELETE SET NULL,
  model_key text NOT NULL,
  model_run_id uuid REFERENCES model_runs(id) ON DELETE SET NULL,
  target_type text,
  target_id text,
  feedback_type text NOT NULL,
  feedback_payload_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  outcome text,
  source text NOT NULL DEFAULT 'client',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS model_feedback_user_model_time_idx
  ON model_feedback_events(user_id, model_key, created_at DESC);
CREATE INDEX IF NOT EXISTS model_feedback_user_target_idx
  ON model_feedback_events(user_id, target_type, target_id);

-- ---- Scheduler ----

CREATE TABLE IF NOT EXISTS schedule_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  range_start timestamptz NOT NULL,
  range_end timestamptz NOT NULL,
  mode text NOT NULL DEFAULT 'initial_plan',
  strategy text NOT NULL DEFAULT 'balanced',
  status text NOT NULL DEFAULT 'draft',
  input_snapshot_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  output_summary_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  risk_summary_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  rejected_at timestamptz
);

CREATE INDEX IF NOT EXISTS schedule_runs_user_time_idx
  ON schedule_runs(user_id, range_start DESC, status);

CREATE TABLE IF NOT EXISTS schedule_draft_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  schedule_run_id uuid NOT NULL REFERENCES schedule_runs(id) ON DELETE CASCADE,
  task_id text,
  task_title text,
  proposed_start timestamptz,
  proposed_end timestamptz,
  original_start timestamptz,
  original_end timestamptz,
  action text NOT NULL DEFAULT 'create',
  confidence numeric NOT NULL DEFAULT 0.7,
  reason_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  risk_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'pending',
  user_modified_start timestamptz,
  user_modified_end timestamptz,
  user_reject_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS schedule_draft_items_run_idx
  ON schedule_draft_items(user_id, schedule_run_id, status);

CREATE TABLE IF NOT EXISTS plan_deviations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  schedule_segment_id text,
  planned_task_id text,
  planned_start timestamptz,
  planned_end timestamptz,
  actual_log_id uuid REFERENCES actual_activity_logs(id) ON DELETE SET NULL,
  actual_segment_id uuid REFERENCES activity_segments(id) ON DELETE SET NULL,
  actual_title text,
  actual_start timestamptz,
  actual_end timestamptz,
  deviation_type text NOT NULL DEFAULT 'different_activity',
  severity text NOT NULL DEFAULT 'medium',
  confidence numeric NOT NULL DEFAULT 0.6,
  status text NOT NULL DEFAULT 'detected',
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  handled_at timestamptz
);

CREATE INDEX IF NOT EXISTS plan_deviations_user_status_idx
  ON plan_deviations(user_id, status, created_at DESC);

-- ---- Administration ----

CREATE TABLE IF NOT EXISTS admin_remote_configs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  config_key text NOT NULL,
  config_value jsonb NOT NULL DEFAULT '{}'::jsonb,
  scope text NOT NULL DEFAULT 'user.preference',
  version integer NOT NULL DEFAULT 1,
  description text,
  is_sensitive boolean NOT NULL DEFAULT false,
  updated_by text NOT NULL DEFAULT 'admin',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, config_key)
);

CREATE INDEX IF NOT EXISTS admin_remote_configs_user_key_idx
  ON admin_remote_configs(user_id, config_key);
CREATE INDEX IF NOT EXISTS admin_remote_configs_user_scope_idx
  ON admin_remote_configs(user_id, scope, updated_at DESC);

CREATE TABLE IF NOT EXISTS server_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  job_key text NOT NULL,
  job_type text NOT NULL DEFAULT 'manual',
  status text NOT NULL DEFAULT 'idle',
  last_started_at timestamptz,
  last_finished_at timestamptz,
  next_run_at timestamptz,
  last_error text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_by text NOT NULL DEFAULT 'system',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, job_key)
);

CREATE INDEX IF NOT EXISTS server_jobs_user_status_idx
  ON server_jobs(user_id, status, next_run_at);

CREATE TABLE IF NOT EXISTS client_import_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  import_uid text NOT NULL,
  status text NOT NULL DEFAULT 'draft',
  summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  result jsonb NOT NULL DEFAULT '{}'::jsonb,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  cancelled_at timestamptz,
  UNIQUE(user_id, import_uid)
);

CREATE INDEX IF NOT EXISTS client_import_sessions_user_status_idx
  ON client_import_sessions(user_id, status, updated_at DESC);

-- ---- Tracking Ingestion ----

CREATE TABLE IF NOT EXISTS tracking_ingest_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id uuid REFERENCES devices(id) ON DELETE SET NULL,
  batch_uid text NOT NULL,
  data_kind text NOT NULL DEFAULT 'mixed',
  status text NOT NULL DEFAULT 'open',
  compression text NOT NULL DEFAULT 'none',
  payload_hash text,
  start_at timestamptz,
  end_at timestamptz,
  raw_event_count integer NOT NULL DEFAULT 0,
  accepted_event_count integer NOT NULL DEFAULT 0,
  rejected_event_count integer NOT NULL DEFAULT 0,
  error_message text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  UNIQUE(user_id, device_id, batch_uid)
);

CREATE INDEX IF NOT EXISTS tracking_ingest_batches_user_status_idx
  ON tracking_ingest_batches(user_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS tracking_ingest_chunks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  batch_id uuid NOT NULL REFERENCES tracking_ingest_batches(id) ON DELETE CASCADE,
  chunk_index integer NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  payload_base64 text,
  checksum text,
  size_bytes integer NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'received',
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, batch_id, chunk_index)
);

CREATE INDEX IF NOT EXISTS tracking_ingest_chunks_batch_idx
  ON tracking_ingest_chunks(user_id, batch_id, chunk_index);

-- ---- Outlook ----

CREATE TABLE IF NOT EXISTS outlook_connections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  client_id text NOT NULL,
  authority text NOT NULL DEFAULT 'https://login.microsoftonline.com/consumers',
  redirect_uri text NOT NULL DEFAULT 'https://login.microsoftonline.com/common/oauth2/nativeclient',
  scope text NOT NULL DEFAULT 'openid profile offline_access User.Read Calendars.Read',
  account_email text,
  account_display_name text,
  refresh_token_encrypted text,
  access_token_encrypted text,
  access_token_expires_at timestamptz,
  status text NOT NULL DEFAULT 'disconnected',
  sync_interval_minutes integer NOT NULL DEFAULT 15,
  last_sync_at timestamptz,
  last_error text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id)
);

CREATE TABLE IF NOT EXISTS outlook_auth_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  state text NOT NULL UNIQUE,
  code_verifier text NOT NULL,
  client_id text NOT NULL,
  redirect_uri text NOT NULL,
  scope text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  used_at timestamptz
);

CREATE INDEX IF NOT EXISTS outlook_auth_sessions_user_idx
  ON outlook_auth_sessions(user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS outlook_calendar_states (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  remote_calendar_id text NOT NULL,
  name text,
  color_hex text,
  delta_link text,
  is_visible boolean NOT NULL DEFAULT true,
  last_synced_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, remote_calendar_id)
);

CREATE INDEX IF NOT EXISTS outlook_calendar_states_user_idx
  ON outlook_calendar_states(user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS outlook_object_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  flowplanv2_object_type text NOT NULL,
  flowplanv2_object_id uuid NOT NULL,
  outlook_object_type text NOT NULL,
  outlook_object_id text NOT NULL,
  outlook_calendar_id text,
  last_synced_at timestamptz,
  sync_state text NOT NULL DEFAULT 'synced',
  last_remote_etag text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, flowplanv2_object_type, flowplanv2_object_id, outlook_object_type),
  UNIQUE(user_id, outlook_object_type, outlook_object_id)
);

CREATE INDEX IF NOT EXISTS outlook_object_mappings_user_state_idx
  ON outlook_object_mappings(user_id, sync_state, updated_at);

CREATE TABLE IF NOT EXISTS outlook_sync_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  trigger_source text NOT NULL,
  status text NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  calendar_count integer NOT NULL DEFAULT 0,
  event_upserts integer NOT NULL DEFAULT 0,
  event_deletes integer NOT NULL DEFAULT 0,
  error_message text,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS outlook_sync_runs_user_idx
  ON outlook_sync_runs(user_id, started_at DESC);

-- ---- Future / planned (table exists, implementation pending) ----

CREATE TABLE IF NOT EXISTS reality_context_sources (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source_type text NOT NULL,
  status text NOT NULL DEFAULT 'planned',
  config_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, source_type)
);
