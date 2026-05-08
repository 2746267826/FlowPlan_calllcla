/** Extract a human-readable message from any thrown value. */
export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}
