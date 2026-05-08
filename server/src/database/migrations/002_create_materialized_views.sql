-- ============================================================================
-- Migration 002: Materialized views for analytics queries
-- Replaces real-time JSONB extraction with pre-aggregated summaries.
-- ============================================================================

-- Daily activity summary
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_activity_daily_summary AS
SELECT
  user_id,
  (payload->>'startTime')::date AS day_key,
  COALESCE(NULLIF(payload->>'processName', ''), NULLIF(payload->>'process_name', ''), 'unknown') AS process_name,
  COALESCE(NULLIF(payload->>'category', ''), 'uncategorized') AS category,
  payload->>'linkedTaskId' AS linked_task_id,
  COUNT(*)::int AS record_count,
  COALESCE(SUM(
    CASE
      WHEN payload->>'durationMinutes' ~ '^-?\\d+(\\.\\d+)?$'
      THEN (payload->>'durationMinutes')::numeric
      WHEN payload->>'durationSeconds' ~ '^-?\\d+(\\.\\d+)?$'
      THEN (payload->>'durationSeconds')::numeric / 60
      ELSE 0
    END
  ), 0)::int AS total_minutes,
  COALESCE(SUM(
    CASE WHEN payload->>'keyCount' ~ '^-?\\d+$'
      THEN (payload->>'keyCount')::int ELSE 0 END
  ), 0)::int AS key_count,
  COALESCE(SUM(
    CASE WHEN payload->>'mouseClicks' ~ '^-?\\d+$'
      THEN (payload->>'mouseClicks')::int ELSE 0 END
  ), 0)::int AS mouse_clicks,
  COALESCE(SUM(
    CASE WHEN payload->>'mouseMovePx' ~ '^-?\\d+$'
      THEN (payload->>'mouseMovePx')::int ELSE 0 END
  ), 0)::int AS mouse_move_px,
  COALESCE(SUM(
    CASE WHEN payload->>'scrollPx' ~ '^-?\\d+$'
      THEN (payload->>'scrollPx')::int ELSE 0 END
  ), 0)::int AS scroll_px
FROM sync_objects
WHERE object_type = 'activity_record'
  AND deleted_at IS NULL
  AND payload ? 'startTime'
GROUP BY user_id, day_key, process_name, category, linked_task_id;

CREATE UNIQUE INDEX IF NOT EXISTS mv_activity_daily_summary_user_idx
  ON mv_activity_daily_summary(user_id, day_key, process_name, category, linked_task_id);

-- Hourly input summary
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_input_hourly_summary AS
SELECT
  user_id,
  date_trunc('hour', COALESCE(
    CASE WHEN payload->>'timestamp' ~ '^\\d{4}-\\d{2}-\\d{2}T'
      THEN (payload->>'timestamp')::timestamptz
      ELSE NULL
    END,
    updated_at
  )) AS bucket_start,
  COALESCE(NULLIF(payload->>'processName', ''), NULLIF(payload->>'process_name', ''), 'unknown') AS process_name,
  payload->>'category' AS category,
  payload->>'eventKind' AS event_kind,
  COALESCE(SUM(
    CASE WHEN payload->>'eventCount' ~ '^-?\\d+$'
      THEN (payload->>'eventCount')::int ELSE 1 END
  ), 0)::int AS event_count,
  COUNT(DISTINCT date_trunc('minute', COALESCE(
    CASE WHEN payload->>'timestamp' ~ '^\\d{4}-\\d{2}-\\d{2}T'
      THEN (payload->>'timestamp')::timestamptz
      ELSE updated_at
    END
  )))::int AS active_minutes
FROM sync_objects
WHERE object_type = 'tracked_input_event'
  AND deleted_at IS NULL
GROUP BY user_id, bucket_start, process_name, category, event_kind;

CREATE UNIQUE INDEX IF NOT EXISTS mv_input_hourly_summary_user_idx
  ON mv_input_hourly_summary(user_id, bucket_start, process_name, category, event_kind);

-- Refresh function
CREATE OR REPLACE FUNCTION refresh_analytics_views()
RETURNS void AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_activity_daily_summary;
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_input_hourly_summary;
END;
$$ LANGUAGE plpgsql;
