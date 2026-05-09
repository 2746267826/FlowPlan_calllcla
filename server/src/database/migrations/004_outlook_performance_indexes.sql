-- ============================================================================
-- Migration 004: Performance indexes for Outlook aggregation queries
--
-- Addresses two slow-query patterns identified via pg_stat_statements:
--   1. sync_changes ORDER BY CASE c.object_type → Use (user_id, id) for sorting
--   2. sync_objects payload->>'source' = 'outlook' → Add partial B-tree index
-- ============================================================================

-- Composite index for pull query filtering + ordering (replaces ORDER BY CASE)
CREATE INDEX IF NOT EXISTS sync_changes_user_obj_id_idx
  ON sync_changes(user_id, object_type, id);

-- Partial B-tree expression index for Outlook source queries
-- Covers: WHERE user_id=$1 AND object_type IN ('calendar_book','calendar_event')
--         AND deleted_at IS NULL AND payload->>'source'='outlook'
CREATE INDEX IF NOT EXISTS sync_objects_outlook_source_idx
  ON sync_objects(user_id, object_type, (payload->>'source'))
  WHERE deleted_at IS NULL AND payload->>'source' = 'outlook';

-- Composite index for sync_cursors query in devices heartbeat
-- (PK on (user_id, device_id) already exists, but adding explicit index for clarity)
CREATE INDEX IF NOT EXISTS sync_cursors_user_device_idx
  ON sync_cursors(user_id, device_id);
