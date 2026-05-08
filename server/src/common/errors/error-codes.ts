/**
 * Central error-code registry for FlowPlanV2.
 *
 * Every business-logic error thrown outside of NestJS built-in guards/pipes
 * should include one of these codes so the global exception filter can return
 * a structured, machine-readable response.
 *
 * Format: MODULE_STATUS
 * Status digits:
 *   001–099  Input / validation
 *   100–199  Auth / permission
 *   200–299  Not found
 *   300–399  Conflict / state
 *   400–499  Business rule
 *   500–599  External dependency
 */

export const ErrorCode = {
  // ---- Auth ----
  AUTH_INVALID_TOKEN: 'AUTH_001',
  AUTH_TOKEN_EXPIRED: 'AUTH_002',
  AUTH_REFRESH_INVALID: 'AUTH_003',
  AUTH_NO_PERMISSION: 'AUTH_100',

  // ---- Sync ----
  SYNC_INVALID_MUTATION: 'SYNC_001',
  SYNC_VERSION_CONFLICT: 'SYNC_301',
  SYNC_OUTLOOK_READONLY: 'SYNC_401',

  // ---- Files ----
  FILE_NOT_FOUND: 'FILE_201',
  FILE_PATH_TRAVERSAL: 'FILE_102',
  FILE_UPLOAD_MISSING_CHUNKS: 'FILE_401',
  FILE_CHECKSUM_MISMATCH: 'FILE_402',
  FILE_SESSION_NOT_FOUND: 'FILE_201',

  // ---- Tracking ----
  TRACKING_BATCH_NOT_FOUND: 'TRACK_201',
  TRACKING_INVALID_CHUNK: 'TRACK_001',

  // ---- Report ----
  REPORT_NOT_FOUND: 'REPORT_201',
  REPORT_PUSH_FAILED: 'REPORT_501',

  // ---- AI ----
  AI_PROVIDER_NOT_CONFIGURED: 'AI_201',
  AI_API_ERROR: 'AI_501',
  AI_DRAFT_NOT_EXECUTABLE: 'AI_401',

  // ---- Scheduler ----
  SCHEDULER_RUN_NOT_FOUND: 'SCHED_201',
  SCHEDULER_CONFIRMATION_REQUIRED: 'SCHED_401',

  // ---- Activity ----
  ACTIVITY_SEGMENT_NOT_FOUND: 'ACT_201',

  // ---- General ----
  VALIDATION_ERROR: 'GEN_001',
  INTERNAL_ERROR: 'GEN_500',
} as const;

export type ErrorCodeType = (typeof ErrorCode)[keyof typeof ErrorCode];
