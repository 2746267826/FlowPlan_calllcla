/**
 * Number utilities used across all services.
 * Replaces the per-service `private readNumber()`, `readLimit()`, `readOffset()`,
 * `toNumber()`, `readInteger()`, `readNullableNumber()`.
 */

/** Parse a numeric value, returning a fallback if NaN or non-finite. */
export function readNumber(value: unknown, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

/** Parse a non-negative integer, clamped to [min, max]. */
export function readInt(
  value: unknown,
  fallback: number,
  min = 0,
  max = Number.MAX_SAFE_INTEGER,
): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, Math.trunc(parsed)));
}

/**
 * Parse an optional integer, returning null when absent/non-finite.
 * Used for nullable numeric columns (size_bytes, etc.).
 */
export function readNullableNumber(value: unknown): number | null {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.max(0, Math.trunc(parsed)) : null;
}

/** Parse a limit parameter for pagination. Defaults to [1, 500]. */
export function readLimit(
  value: string | undefined,
  fallback: number,
  min = 1,
  max = 500,
): number {
  return readInt(value, fallback, min, max);
}

/** Parse an offset parameter for pagination. Minimum 0. */
export function readOffset(value: string | undefined): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.max(0, Math.trunc(parsed)) : 0;
}

/** Coerce any value to a finite number, defaulting to 0. */
export function toNumber(value: unknown): number {
  if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
  if (typeof value === 'string') {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}
