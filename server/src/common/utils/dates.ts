/**
 * Date utilities used across all services.
 * Replaces the per-service `private readDate()`, `private iso()`, and inline date logic.
 */

/**
 * Parse a value to Date, returning null for invalid/unset inputs.
 * Accepts string (ISO-8601 preferred) or Date.
 */
export function readDate(value: unknown): Date | null {
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }
  if (typeof value !== 'string' || value.trim().length === 0) {
    return null;
  }
  const parsed = new Date(value.trim());
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

/**
 * Parse a value to Date with a strict ISO-8601 format requirement.
 * Only accepts strings matching: YYYY-MM-DDTHH:MM:SS(.sss)?(Z|[+-]HH:MM)
 */
export function readIsoDate(value: unknown): Date | null {
  if (typeof value !== 'string') return null;
  const text = value.trim();
  if (
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/.test(
      text,
    )
  ) {
    return null;
  }
  const parsed = new Date(text);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

/**
 * Convert a Date or date-string to an ISO-8601 string.
 * Returns the original string unchanged if it's already a string and can't be parsed.
 */
export function iso(value: Date | string | null | undefined): string | null {
  if (value == null) return null;
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value.toISOString();
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? value : parsed.toISOString();
}

/**
 * Return {start, end} as ISO strings from two date-like values.
 * Defaults to today (00:00–23:59:59.999) if date is not provided.
 */
export function dayRange(
  date?: string | null,
  start?: string | null,
  end?: string | null,
): { start: string; end: string } {
  const explicitStart = readDate(start);
  const explicitEnd = readDate(end);
  if (explicitStart && explicitEnd && explicitStart < explicitEnd) {
    return { start: explicitStart.toISOString(), end: explicitEnd.toISOString() };
  }
  const dateText =
    typeof date === 'string' && date.trim()
      ? date.trim().slice(0, 10)
      : new Date().toISOString().slice(0, 10);
  const s = new Date(`${dateText}T00:00:00.000Z`);
  const e = new Date(s.getTime() + 24 * 60 * 60 * 1000);
  return { start: s.toISOString(), end: e.toISOString() };
}

/**
 * Parse start/end ISO strings and validate start < end.
 * Defaults to last 30 days if no range is given.
 */
export function dateRange(
  start?: string | null,
  end?: string | null,
): { start: string; end: string } {
  const dayMs = 24 * 60 * 60 * 1000;
  const now = new Date();
  const e = readDate(end) ?? now;
  const s = readDate(start) ?? new Date(e.getTime() - 30 * dayMs);
  if (s >= e) {
    throw new Error('start must be earlier than end');
  }
  return { start: s.toISOString(), end: e.toISOString() };
}
