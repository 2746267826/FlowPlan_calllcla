/**
 * String utilities used across all services.
 * Replaces the per-service `private clean()` and `private asString()` methods.
 */

/** Trim + null-safe string extractor. Returns null for empty/whitespace-only values. */
export function clean(value: unknown): string | null {
  return typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : null;
}

/** Like clean() but returns undefined instead of null (convenience for optional args). */
export function asString(value: unknown): string | undefined {
  return (typeof value === 'string' && value.trim().length > 0
    ? value.trim()
    : undefined) as string | undefined;
}

/** Truncate to maxLen chars, appending '...' if truncated. */
export function truncate(value: string, maxLen: number): string {
  if (value.length <= maxLen) return value;
  return value.slice(0, maxLen) + '...';
}

/** Collapse whitespace and trim. For AI prompt summarization. */
export function summarize(value: string, maxLen = 40): string {
  const cleaned = value.replace(/\s+/g, ' ').trim();
  return cleaned.length > maxLen ? `${cleaned.slice(0, maxLen)}...` : cleaned;
}

/**
 * Return the last segment of a path string.
 * Handles both POSIX and Windows separators.
 */
export function basename(path: string): string {
  const normalized = path.replace(/\\/g, '/');
  return normalized.split('/').filter(Boolean).pop() ?? path;
}

/** Build a SQL ILIKE search pattern from a user query string. */
export function searchPattern(value: string | undefined): string | null {
  const cleaned = clean(value);
  return cleaned ? `%${cleaned}%` : null;
}
