/**
 * Standardized task payload schema.
 *
 * Every service that reads or writes task objects MUST use
 * normalizeTaskPayload() to convert from legacy formats to the canonical form.
 */

import { clean, readDate, readInt } from '../utils';

export type TaskStatus = 'todo' | 'in_progress' | 'done' | 'cancelled';
export type TaskPriority = 'urgent' | 'high' | 'normal' | 'low';

export interface TaskPayload {
  title: string;
  summary?: string;
  description?: string;
  status: TaskStatus;
  priority: TaskPriority;
  dueAt?: string;
  startAt?: string;
  estimatedMinutes?: number;
  taskListId?: string;
  taskListName?: string;
  location?: string;
  notes?: string;
  rrule?: string;
  isLocked: boolean;
  isAutoScheduled: boolean;
  isSplittable: boolean;
  reminderMinutesBefore?: number;
  source?: string;
  createdAt?: string;
  updatedAt?: string;
}

const STATUS_MAP: Record<string, TaskStatus> = {
  todo: 'todo',
  'needs-action': 'todo',
  needs_action: 'todo',
  pending: 'todo',
  in_progress: 'in_progress',
  'in-progress': 'in_progress',
  doing: 'in_progress',
  done: 'done',
  completed: 'done',
  complete: 'done',
  cancelled: 'cancelled',
  canceled: 'cancelled',
  archived: 'cancelled',
};

const PRIORITY_MAP: Record<string, TaskPriority> = {
  urgent: 'urgent',
  high: 'high',
  normal: 'normal',
  medium: 'normal',
  low: 'low',
};

/**
 * Normalize a raw payload (from sync_objects, client API, import, etc.)
 * into the canonical TaskPayload format.
 *
 * Accepts legacy key names (due, due_date, dtstart, durationMinutes, etc.)
 * and normalises them to the standard camelCase keys.
 */
export function normalizeTaskPayload(
  raw: Record<string, unknown>,
): TaskPayload {
  const status = normalizeStatus(raw.status);
  const priority = normalizePriority(raw.priority ?? raw.priorityLocal);

  return {
    title: firstString(raw, ['title', 'summary', 'name']) ?? '未命名任务',
    summary: firstString(raw, ['summary', 'title']),
    description: firstString(raw, ['description', 'notes', 'note']),
    status,
    priority,
    dueAt:
      firstString(raw, ['dueAt', 'due', 'due_at', 'dueDate', 'deadline']) ??
      undefined,
    startAt:
      firstString(raw, ['startAt', 'dtstart', 'start_at', 'startTime']) ??
      undefined,
    estimatedMinutes:
      firstInt(raw, ['estimatedMinutes', 'durationMinutes']) ?? undefined,
    taskListId: firstString(raw, ['taskListId', 'task_list_id']) ?? undefined,
    taskListName:
      firstString(raw, ['taskListName', 'task_list_name', 'listName']) ??
      undefined,
    location: firstString(raw, ['location', 'place', 'where']) ?? undefined,
    notes: firstString(raw, ['notes', 'note', 'description']) ?? undefined,
    rrule: firstString(raw, ['rrule']) ?? undefined,
    isLocked: boolValue(raw.isLocked) || boolValue(raw.is_locked) || false,
    isAutoScheduled:
      raw.allowAutoSchedule === false || raw.autoSchedule === false
        ? false
        : true,
    isSplittable:
      raw.canSplit === false || raw.splittable === false ? false : true,
    reminderMinutesBefore:
      firstInt(raw, ['reminderMinutesBefore']) ?? undefined,
    source: firstString(raw, ['source', 'updatedFrom']) ?? undefined,
    createdAt: firstString(raw, ['createdAt', 'created_at']) ?? undefined,
    updatedAt: firstString(raw, ['updatedAt', 'updated_at']) ?? undefined,
  };
}

// ---- internal helpers ----

function normalizeStatus(value: unknown): TaskStatus {
  const key = clean(value)?.toLowerCase();
  return key && STATUS_MAP[key] ? STATUS_MAP[key] : 'todo';
}

function normalizePriority(value: unknown): TaskPriority {
  const key = clean(value)?.toLowerCase();
  return key && PRIORITY_MAP[key] ? PRIORITY_MAP[key] : 'normal';
}

function firstString(
  obj: Record<string, unknown>,
  keys: string[],
): string | undefined {
  for (const key of keys) {
    const val = clean(obj[key]);
    if (val) return val;
  }
  return undefined;
}

function firstInt(
  obj: Record<string, unknown>,
  keys: string[],
): number | null {
  for (const key of keys) {
    const val = readInt(obj[key], NaN);
    if (Number.isFinite(val)) return val;
  }
  return null;
}

function boolValue(value: unknown): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    const lower = value.trim().toLowerCase();
    return lower === 'true' || lower === '1';
  }
  if (typeof value === 'number') return value !== 0;
  return false;
}
