/**
 * Object utilities used across all services.
 * Replaces the per-service `private asRecord()` and inline array checks.
 */

/** Cast a value to Record<string, unknown>. Returns {} for non-objects / arrays / null. */
export function asRecord(value: unknown): Record<string, unknown> {
  if (value && typeof value === 'object' && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

/** Cast a value to unknown[]. Returns [] for non-arrays. */
export function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

/** Deep-clone a JSON-serializable value. */
export function deepClone<T>(value: T): T {
  return JSON.parse(JSON.stringify(value)) as T;
}

/**
 * Pick only the named keys from an object.
 * Returns a new object — does not mutate the input.
 */
export function pick(
  obj: Record<string, unknown>,
  keys: string[],
): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const key of keys) {
    if (key in obj) {
      result[key] = obj[key];
    }
  }
  return result;
}
