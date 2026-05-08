-- ============================================================================
-- Migration 001: Normalize object_type values
-- Maps legacy plural/alias spellings to canonical singular forms.
-- ============================================================================

UPDATE sync_objects SET object_type = 'task_item'           WHERE object_type IN ('task', 'tasks', 'task_items');
UPDATE sync_objects SET object_type = 'task_list'           WHERE object_type IN ('task_lists');
UPDATE sync_objects SET object_type = 'calendar_event'      WHERE object_type IN ('calendar_events', 'event', 'events', 'time_block', 'time_blocks');
UPDATE sync_objects SET object_type = 'calendar_book'       WHERE object_type IN ('calendar_books');
UPDATE sync_objects SET object_type = 'activity_record'     WHERE object_type IN ('activity_records', 'actual_record');
UPDATE sync_objects SET object_type = 'raw_activity_log'    WHERE object_type IN ('raw_activity_logs');
UPDATE sync_objects SET object_type = 'tracked_input_event' WHERE object_type IN ('tracked_input_events', 'input_event');
UPDATE sync_objects SET object_type = 'task_schedule_segment' WHERE object_type IN ('task_schedule_segments');
UPDATE sync_objects SET object_type = 'actual_activity_log' WHERE object_type IN ('actual_activity_logs');

-- Normalize historical sync_changes too
UPDATE sync_changes SET object_type = 'task_item'           WHERE object_type IN ('task', 'tasks', 'task_items');
UPDATE sync_changes SET object_type = 'calendar_event'      WHERE object_type IN ('calendar_events', 'event', 'events', 'time_block', 'time_blocks');
UPDATE sync_changes SET object_type = 'activity_record'     WHERE object_type IN ('activity_records', 'actual_record');
UPDATE sync_changes SET object_type = 'tracked_input_event' WHERE object_type IN ('tracked_input_events', 'input_event');

-- Normalize sync_mutations
UPDATE sync_mutations SET object_type = 'task_item'         WHERE object_type IN ('task', 'tasks', 'task_items');
UPDATE sync_mutations SET object_type = 'calendar_event'    WHERE object_type IN ('calendar_events', 'event', 'events', 'time_block', 'time_blocks');
UPDATE sync_mutations SET object_type = 'activity_record'   WHERE object_type IN ('activity_records', 'actual_record');
UPDATE sync_mutations SET object_type = 'tracked_input_event' WHERE object_type IN ('tracked_input_events', 'input_event');

-- Normalize sync_conflicts
UPDATE sync_conflicts SET object_type = 'task_item'         WHERE object_type IN ('task', 'tasks', 'task_items');
UPDATE sync_conflicts SET object_type = 'calendar_event'    WHERE object_type IN ('calendar_events', 'event', 'events', 'time_block', 'time_blocks');
UPDATE sync_conflicts SET object_type = 'activity_record'   WHERE object_type IN ('activity_records', 'actual_record');
UPDATE sync_conflicts SET object_type = 'tracked_input_event' WHERE object_type IN ('tracked_input_events', 'input_event');
