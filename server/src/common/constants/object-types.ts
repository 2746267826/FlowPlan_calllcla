/**
 * Canonical object_type values for sync_objects.
 *
 * Every service that queries or writes sync_objects MUST use these
 * constants instead of ad-hoc strings.  A migration in
 * src/database/migrations/001_normalize_object_types.sql maps legacy
 * spellings to the canonical ones.
 */

export const ObjectType = {
  TASK: 'task_item',
  TASK_LIST: 'task_list',
  CALENDAR_EVENT: 'calendar_event',
  CALENDAR_BOOK: 'calendar_book',
  TASK_SCHEDULE_SEGMENT: 'task_schedule_segment',
  ACTUAL_ACTIVITY_LOG: 'actual_activity_log',
  ACTIVITY_RECORD: 'activity_record',
  RAW_ACTIVITY_LOG: 'raw_activity_log',
  TRACKED_INPUT_EVENT: 'tracked_input_event',
  FILE_FOLDER: 'file_folder',
  FILE_ITEM: 'file_item',
  FILE_NODE: 'file_node',
  FILE_CONTEXT_LINK: 'file_context_link',
  REPORT_DOCUMENT: 'report_document',
  DIARY_ENTRY: 'diary_entry',
  AI_CONVERSATION: 'ai_conversation',
} as const;

export type ObjectTypeValue = (typeof ObjectType)[keyof typeof ObjectType];

/** Legacy aliases that map to canonical types. */
export const LegacyTypeMap: Record<string, string> = {
  task: ObjectType.TASK,
  tasks: ObjectType.TASK,
  task_items: ObjectType.TASK,
  calendar_event: ObjectType.CALENDAR_EVENT,
  calendar_events: ObjectType.CALENDAR_EVENT,
  event: ObjectType.CALENDAR_EVENT,
  events: ObjectType.CALENDAR_EVENT,
  time_block: ObjectType.CALENDAR_EVENT,
  time_blocks: ObjectType.CALENDAR_EVENT,
  activity_records: ObjectType.ACTIVITY_RECORD,
  actual_record: ObjectType.ACTIVITY_RECORD,
  raw_activity_logs: ObjectType.RAW_ACTIVITY_LOG,
  tracked_input_events: ObjectType.TRACKED_INPUT_EVENT,
  input_event: ObjectType.TRACKED_INPUT_EVENT,
  task_lists: ObjectType.TASK_LIST,
  calendar_books: ObjectType.CALENDAR_BOOK,
  task_schedule_segments: ObjectType.TASK_SCHEDULE_SEGMENT,
  actual_activity_logs: ObjectType.ACTUAL_ACTIVITY_LOG,
};

/** Arrays of object types used in WHERE object_type = ANY(...) clauses. */
export const TaskTypes = [ObjectType.TASK];
export const EventTypes = [ObjectType.CALENDAR_EVENT];
export const TrackingTypes = [
  ObjectType.RAW_ACTIVITY_LOG,
  ObjectType.ACTIVITY_RECORD,
  ObjectType.TRACKED_INPUT_EVENT,
] as const;
export const ActivityTypes = [
  ObjectType.ACTIVITY_RECORD,
  ObjectType.RAW_ACTIVITY_LOG,
] as const;
export const InputTypes = [
  ObjectType.TRACKED_INPUT_EVENT,
] as const;
export const ScheduleTypes = [
  ObjectType.TASK,
  ObjectType.CALENDAR_EVENT,
  ObjectType.TASK_SCHEDULE_SEGMENT,
] as const;
