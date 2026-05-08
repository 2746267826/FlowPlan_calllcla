/**
 * Standardized calendar-event payload schema.
 */

import { clean, readInt } from '../utils';

export type CalendarEventStatus = 'confirmed' | 'tentative' | 'cancelled';

export interface CalendarEventPayload {
  title: string;
  summary?: string;
  description?: string;
  startAt: string;
  endAt: string;
  status: CalendarEventStatus;
  isBlock: boolean;
  location?: string;
  notes?: string;
  rrule?: string;
  colorHex?: string;
  calendarBookId?: string;
  calendarBookName?: string;
  source?: string;
  createdAt?: string;
  updatedAt?: string;
}

const STATUS_MAP: Record<string, CalendarEventStatus> = {
  confirmed: 'confirmed',
  tentative: 'tentative',
  cancelled: 'cancelled',
  canceled: 'cancelled',
};

/**
 * Normalize a raw payload into the canonical CalendarEventPayload format.
 */
export function normalizeEventPayload(
  raw: Record<string, unknown>,
): CalendarEventPayload {
  return {
    title: firstString(raw, ['title', 'summary', 'name']) ?? '未命名日程',
    summary: firstString(raw, ['summary', 'title']),
    description: firstString(raw, ['description', 'notes', 'note']),
    startAt:
      firstString(raw, ['startAt', 'dtstart', 'start_at', 'startTime']) ?? '',
    endAt: firstString(raw, ['endAt', 'dtend', 'end_at', 'endTime']) ?? '',
    status: normalizeStatus(raw.status),
    isBlock:
      boolValue(raw.isBlock) ||
      boolValue(raw.blocking) ||
      boolValue(raw.isBlocking) ||
      raw.kind === 'blocking',
    location: firstString(raw, ['location', 'place']) ?? undefined,
    notes: firstString(raw, ['notes', 'note', 'description']) ?? undefined,
    rrule: firstString(raw, ['rrule']) ?? undefined,
    colorHex: firstString(raw, ['colorHex', 'color_hex']) ?? undefined,
    calendarBookId:
      firstString(raw, ['calendarBookId', 'eventCalendarId']) ?? undefined,
    calendarBookName:
      firstString(raw, ['calendarBookName', 'calendarName']) ?? undefined,
    source: firstString(raw, ['source', 'updatedFrom']) ?? undefined,
    createdAt: firstString(raw, ['createdAt', 'created_at']) ?? undefined,
    updatedAt: firstString(raw, ['updatedAt', 'updated_at']) ?? undefined,
  };
}

// ---- helpers ----

function normalizeStatus(value: unknown): CalendarEventStatus {
  const key = clean(value)?.toLowerCase();
  return key && STATUS_MAP[key] ? STATUS_MAP[key] : 'confirmed';
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

function boolValue(value: unknown): boolean {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'string') {
    const lower = value.trim().toLowerCase();
    return lower === 'true' || lower === '1';
  }
  if (typeof value === 'number') return value !== 0;
  return false;
}
