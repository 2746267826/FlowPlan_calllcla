import { Injectable } from '@nestjs/common';
import { QueryResultRow } from 'pg';
import { FlowPlanRequestContext } from '../common/request-context';
import { DatabaseService } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';

export interface AnalyticsQuery {
  start?: string;
  end?: string;
  bucket?: string;
  limit?: string;
  offset?: string;
  taskId?: string;
  processName?: string;
  category?: string;
  eventKind?: string;
}

type Bucket = 'hour' | 'day' | 'month';

type BucketRow = QueryResultRow & {
  bucket_start: Date | string;
  record_count?: string | number;
  event_count?: string | number;
  total_minutes?: string | number;
  keyboard_event_count?: string | number;
  mouse_button_event_count?: string | number;
  wheel_event_count?: string | number;
  mouse_move_event_count?: string | number;
  mouse_move_distance?: string | number;
};

type SummaryRow = QueryResultRow & {
  record_count: string | number;
  total_minutes: string | number;
  key_count: string | number;
  mouse_clicks: string | number;
  mouse_move_px: string | number;
  scroll_px: string | number;
};

type NamedMetricRow = QueryResultRow & {
  name: string | null;
  record_count?: string | number;
  event_count?: string | number;
  total_minutes?: string | number;
};

type DetailRow = QueryResultRow & {
  server_id: string;
  object_type: string;
  occurred_at: Date | string;
  updated_at: Date | string;
  payload: Record<string, unknown>;
  metric_count?: string | number;
  metric_minutes?: string | number;
};

@Injectable()
export class AnalyticsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
  ) {}

  async activityHeatmap(
    query: AnalyticsQuery,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const range = this.readRange(query);
    const bucket = this.readBucket(query.bucket);
    const processName = this.cleanFilter(query.processName);
    const category = this.cleanFilter(query.category);
    const taskId = this.cleanFilter(query.taskId);
    const result = await this.database.query<BucketRow>(
      `
      WITH activity AS (${this.activitySourceSql()})
      SELECT
        date_trunc($4, occurred_at) AS bucket_start,
        COUNT(*)::int AS record_count,
        COALESCE(SUM(duration_minutes), 0)::int AS total_minutes
      FROM activity
      WHERE occurred_at >= $2
        AND occurred_at < $3
        AND ($5::text IS NULL OR app_name = $5)
        AND ($6::text IS NULL OR category = $6)
        AND ($7::text IS NULL OR linked_task_id = $7)
      GROUP BY bucket_start
      ORDER BY bucket_start ASC
      `,
      [userId, range.start, range.end, bucket, processName, category, taskId],
    );

    return {
      range,
      bucket,
      source: 'server-live-sync-objects',
      buckets: result.rows.map((row) => ({
        bucketStart: this.iso(row.bucket_start),
        recordCount: this.toNumber(row.record_count),
        totalMinutes: this.toNumber(row.total_minutes),
      })),
    };
  }

  async inputHeatmap(
    query: AnalyticsQuery,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const range = this.readRange(query);
    const bucket = this.readBucket(query.bucket);
    const processName = this.cleanFilter(query.processName);
    const category = this.cleanFilter(query.category);
    const eventKind = this.cleanFilter(query.eventKind);
    const result = await this.database.query<BucketRow>(
      `
      WITH input_events AS (${this.inputSourceSql()})
      SELECT
        date_trunc($4, occurred_at) AS bucket_start,
        COALESCE(SUM(event_count), 0)::int AS event_count,
        COALESCE(SUM(CASE WHEN event_kind = 'key_down' THEN event_count ELSE 0 END), 0)::int AS keyboard_event_count,
        COALESCE(SUM(CASE WHEN event_kind = 'mouse_button' THEN event_count ELSE 0 END), 0)::int AS mouse_button_event_count,
        COALESCE(SUM(CASE WHEN event_kind = 'mouse_wheel' THEN event_count ELSE 0 END), 0)::int AS wheel_event_count,
        COALESCE(SUM(CASE WHEN event_kind = 'mouse_move' THEN event_count ELSE 0 END), 0)::int AS mouse_move_event_count,
        COALESCE(SUM(CASE WHEN event_kind = 'mouse_move' THEN move_distance ELSE 0 END), 0)::int AS mouse_move_distance
      FROM input_events
      WHERE occurred_at >= $2
        AND occurred_at < $3
        AND ($5::text IS NULL OR process_name = $5)
        AND ($6::text IS NULL OR category = $6)
        AND ($7::text IS NULL OR event_kind = $7)
      GROUP BY bucket_start
      ORDER BY bucket_start ASC
      `,
      [userId, range.start, range.end, bucket, processName, category, eventKind],
    );

    return {
      range,
      bucket,
      source: 'server-live-sync-objects',
      buckets: result.rows.map((row) => ({
        bucketStart: this.iso(row.bucket_start),
        eventCount: this.toNumber(row.event_count),
        keyboardEventCount: this.toNumber(row.keyboard_event_count),
        mouseButtonEventCount: this.toNumber(row.mouse_button_event_count),
        wheelEventCount: this.toNumber(row.wheel_event_count),
        mouseMoveEventCount: this.toNumber(row.mouse_move_event_count),
        mouseMoveDistance: this.toNumber(row.mouse_move_distance),
      })),
    };
  }

  async activityRangeSummary(
    query: AnalyticsQuery,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const range = this.readRange(query);
    const result = await this.database.query<SummaryRow>(
      `
      WITH activity AS (${this.activitySourceSql()})
      SELECT
        COUNT(*)::int AS record_count,
        COALESCE(SUM(duration_minutes), 0)::int AS total_minutes,
        COALESCE(SUM(key_count), 0)::int AS key_count,
        COALESCE(SUM(mouse_clicks), 0)::int AS mouse_clicks,
        COALESCE(SUM(mouse_move_px), 0)::int AS mouse_move_px,
        COALESCE(SUM(scroll_px), 0)::int AS scroll_px
      FROM activity
      WHERE occurred_at >= $2 AND occurred_at < $3
      `,
      [userId, range.start, range.end],
    );

    const row = result.rows[0];
    return {
      range,
      source: 'server-live-sync-objects',
      recordCount: this.toNumber(row?.record_count),
      totalMinutes: this.toNumber(row?.total_minutes),
      keyCount: this.toNumber(row?.key_count),
      mouseClicks: this.toNumber(row?.mouse_clicks),
      mouseMovePx: this.toNumber(row?.mouse_move_px),
      scrollPx: this.toNumber(row?.scroll_px),
    };
  }

  async topApps(query: AnalyticsQuery, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const range = this.readRange(query);
    const limit = this.readLimit(query.limit, 20);
    const result = await this.database.query<NamedMetricRow>(
      `
      WITH activity AS (${this.activitySourceSql()})
      SELECT
        COALESCE(NULLIF(app_name, ''), 'unknown') AS name,
        COUNT(*)::int AS record_count,
        COALESCE(SUM(duration_minutes), 0)::int AS total_minutes
      FROM activity
      WHERE occurred_at >= $2 AND occurred_at < $3
      GROUP BY name
      ORDER BY total_minutes DESC, record_count DESC, name ASC
      LIMIT $4
      `,
      [userId, range.start, range.end, limit],
    );
    return this.namedMetricResponse(range, result.rows);
  }

  async topCategories(query: AnalyticsQuery, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const range = this.readRange(query);
    const limit = this.readLimit(query.limit, 20);
    const result = await this.database.query<NamedMetricRow>(
      `
      WITH activity AS (${this.activitySourceSql()})
      SELECT
        COALESCE(NULLIF(category, ''), 'uncategorized') AS name,
        COUNT(*)::int AS record_count,
        COALESCE(SUM(duration_minutes), 0)::int AS total_minutes
      FROM activity
      WHERE occurred_at >= $2 AND occurred_at < $3
      GROUP BY name
      ORDER BY total_minutes DESC, record_count DESC, name ASC
      LIMIT $4
      `,
      [userId, range.start, range.end, limit],
    );
    return this.namedMetricResponse(range, result.rows);
  }

  async taskWorkSummary(
    query: AnalyticsQuery,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const range = this.readRange(query);
    const limit = this.readLimit(query.limit, 50);
    const taskId = query.taskId?.trim();
    const result = await this.database.query<NamedMetricRow>(
      `
      WITH activity AS (${this.activitySourceSql()})
      SELECT
        COALESCE(NULLIF(linked_task_id, ''), 'unlinked') AS name,
        COUNT(*)::int AS record_count,
        COALESCE(SUM(duration_minutes), 0)::int AS total_minutes
      FROM activity
      WHERE occurred_at >= $2
        AND occurred_at < $3
        AND ($5::text IS NULL OR linked_task_id = $5)
      GROUP BY name
      ORDER BY total_minutes DESC, record_count DESC, name ASC
      LIMIT $4
      `,
      [userId, range.start, range.end, limit, taskId || null],
    );
    return this.namedMetricResponse(range, result.rows);
  }

  async focusTrends(query: AnalyticsQuery, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const range = this.readRange(query);
    const result = await this.database.query<BucketRow>(
      `
      WITH activity AS (${this.activitySourceSql()})
      SELECT
        date_trunc('day', occurred_at) AS bucket_start,
        COALESCE(SUM(duration_minutes), 0)::int AS total_minutes,
        COALESCE(SUM(
          CASE
            WHEN lower(COALESCE(category, '')) IN ('focus', 'focused', 'work', 'study', 'productive')
            THEN duration_minutes
            ELSE 0
          END
        ), 0)::int AS record_count
      FROM activity
      WHERE occurred_at >= $2 AND occurred_at < $3
      GROUP BY bucket_start
      ORDER BY bucket_start ASC
      `,
      [userId, range.start, range.end],
    );

    return {
      range,
      bucket: 'day',
      source: 'server-live-sync-objects',
      buckets: result.rows.map((row) => {
        const totalMinutes = this.toNumber(row.total_minutes);
        const focusMinutes = this.toNumber(row.record_count);
        return {
          bucketStart: this.iso(row.bucket_start),
          totalMinutes,
          focusMinutes,
          focusRatio: totalMinutes <= 0 ? 0 : focusMinutes / totalMinutes,
        };
      }),
    };
  }

  async activityRecords(
    query: AnalyticsQuery,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const range = this.readRange(query);
    const limit = this.readLimit(query.limit, 100);
    const offset = this.readOffset(query.offset);
    const processName = this.cleanFilter(query.processName);
    const category = this.cleanFilter(query.category);
    const taskId = this.cleanFilter(query.taskId);
    const result = await this.database.query<DetailRow>(
      `
      WITH activity AS (${this.activityDetailSourceSql()})
      SELECT
        server_id,
        object_type,
        occurred_at,
        updated_at,
        payload,
        1::int AS metric_count,
        duration_minutes::int AS metric_minutes
      FROM activity
      WHERE occurred_at >= $2
        AND occurred_at < $3
        AND ($4::text IS NULL OR app_name = $4)
        AND ($5::text IS NULL OR category = $5)
        AND ($6::text IS NULL OR linked_task_id = $6)
      ORDER BY occurred_at DESC, server_id DESC
      LIMIT $7 OFFSET $8
      `,
      [userId, range.start, range.end, processName, category, taskId, limit, offset],
    );

    return this.detailResponse(range, limit, offset, result.rows);
  }

  async inputEvents(query: AnalyticsQuery, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const range = this.readRange(query);
    const limit = this.readLimit(query.limit, 100);
    const offset = this.readOffset(query.offset);
    const processName = this.cleanFilter(query.processName);
    const category = this.cleanFilter(query.category);
    const eventKind = this.cleanFilter(query.eventKind);
    const result = await this.database.query<DetailRow>(
      `
      WITH input_events AS (${this.inputDetailSourceSql()})
      SELECT
        server_id,
        object_type,
        occurred_at,
        updated_at,
        payload,
        event_count::int AS metric_count,
        0::int AS metric_minutes
      FROM input_events
      WHERE occurred_at >= $2
        AND occurred_at < $3
        AND ($4::text IS NULL OR process_name = $4)
        AND ($5::text IS NULL OR category = $5)
        AND ($6::text IS NULL OR event_kind = $6)
      ORDER BY occurred_at DESC, server_id DESC
      LIMIT $7 OFFSET $8
      `,
      [userId, range.start, range.end, processName, category, eventKind, limit, offset],
    );

    return this.detailResponse(range, limit, offset, result.rows);
  }

  private activitySourceSql() {
    return `
      SELECT
        COALESCE(
          CASE
            WHEN COALESCE(payload->>'startTime', payload->>'start_time', payload->>'startedAt') ~ '^\\d{4}-\\d{2}-\\d{2}T'
            THEN COALESCE(payload->>'startTime', payload->>'start_time', payload->>'startedAt')::timestamptz
            ELSE NULL
          END,
          updated_at
        ) AS occurred_at,
        CASE
          WHEN COALESCE(payload->>'durationMinutes', payload->>'duration_minutes') ~ '^-?\\d+(\\.\\d+)?$'
          THEN COALESCE(payload->>'durationMinutes', payload->>'duration_minutes')::numeric
          ELSE 0
        END AS duration_minutes,
        CASE
          WHEN COALESCE(payload->>'keyCount', payload->>'key_count') ~ '^-?\\d+$'
          THEN COALESCE(payload->>'keyCount', payload->>'key_count')::int
          ELSE 0
        END AS key_count,
        CASE
          WHEN COALESCE(payload->>'mouseClicks', payload->>'mouse_clicks') ~ '^-?\\d+$'
          THEN COALESCE(payload->>'mouseClicks', payload->>'mouse_clicks')::int
          ELSE 0
        END AS mouse_clicks,
        CASE
          WHEN COALESCE(payload->>'mouseMovePx', payload->>'mouse_move_px') ~ '^-?\\d+$'
          THEN COALESCE(payload->>'mouseMovePx', payload->>'mouse_move_px')::int
          ELSE 0
        END AS mouse_move_px,
        CASE
          WHEN COALESCE(payload->>'scrollPx', payload->>'scroll_px') ~ '^-?\\d+$'
          THEN COALESCE(payload->>'scrollPx', payload->>'scroll_px')::int
          ELSE 0
        END AS scroll_px,
        COALESCE(
          payload->>'processName',
          payload->>'process_name',
          payload->>'packageName',
          payload->>'package_name'
        ) AS app_name,
        payload->>'category' AS category,
        COALESCE(payload->>'linkedTaskId', payload->>'linked_task_id') AS linked_task_id
      FROM sync_objects
      WHERE user_id = $1
        AND deleted_at IS NULL
        AND object_type IN ('activity_record', 'activity_records', 'actual_record')
    `;
  }

  private activityDetailSourceSql() {
    return `
      SELECT
        id::text AS server_id,
        object_type,
        payload,
        updated_at,
        COALESCE(
          CASE
            WHEN COALESCE(payload->>'startTime', payload->>'start_time', payload->>'startedAt') ~ '^\\d{4}-\\d{2}-\\d{2}T'
            THEN COALESCE(payload->>'startTime', payload->>'start_time', payload->>'startedAt')::timestamptz
            ELSE NULL
          END,
          updated_at
        ) AS occurred_at,
        CASE
          WHEN COALESCE(payload->>'durationMinutes', payload->>'duration_minutes') ~ '^-?\\d+(\\.\\d+)?$'
          THEN COALESCE(payload->>'durationMinutes', payload->>'duration_minutes')::numeric
          ELSE 0
        END AS duration_minutes,
        COALESCE(
          payload->>'processName',
          payload->>'process_name',
          payload->>'packageName',
          payload->>'package_name'
        ) AS app_name,
        payload->>'category' AS category,
        COALESCE(payload->>'linkedTaskId', payload->>'linked_task_id') AS linked_task_id
      FROM sync_objects
      WHERE user_id = $1
        AND deleted_at IS NULL
        AND object_type IN ('activity_record', 'activity_records', 'actual_record')
    `;
  }

  private inputSourceSql() {
    return `
      SELECT
        COALESCE(
          CASE
            WHEN COALESCE(payload->>'timestamp', payload->>'occurredAt', payload->>'occurred_at') ~ '^\\d{4}-\\d{2}-\\d{2}T'
            THEN COALESCE(payload->>'timestamp', payload->>'occurredAt', payload->>'occurred_at')::timestamptz
            ELSE NULL
          END,
          updated_at
        ) AS occurred_at,
        CASE
          WHEN COALESCE(payload->>'eventCount', payload->>'event_count') ~ '^-?\\d+$'
          THEN COALESCE(payload->>'eventCount', payload->>'event_count')::int
          ELSE 1
        END AS event_count,
        COALESCE(payload->>'kind', payload->>'eventKind', payload->>'event_kind') AS event_kind,
        CASE
          WHEN COALESCE(payload->>'moveDistance', payload->>'move_distance') ~ '^-?\\d+$'
          THEN COALESCE(payload->>'moveDistance', payload->>'move_distance')::int
          ELSE 0
        END AS move_distance,
        COALESCE(payload->>'processName', payload->>'process_name') AS process_name,
        payload->>'category' AS category
      FROM sync_objects
      WHERE user_id = $1
        AND deleted_at IS NULL
        AND object_type IN ('tracked_input_event', 'tracked_input_events', 'input_event')
    `;
  }

  private inputDetailSourceSql() {
    return `
      SELECT
        id::text AS server_id,
        object_type,
        payload,
        updated_at,
        COALESCE(
          CASE
            WHEN COALESCE(payload->>'timestamp', payload->>'occurredAt', payload->>'occurred_at') ~ '^\\d{4}-\\d{2}-\\d{2}T'
            THEN COALESCE(payload->>'timestamp', payload->>'occurredAt', payload->>'occurred_at')::timestamptz
            ELSE NULL
          END,
          updated_at
        ) AS occurred_at,
        CASE
          WHEN COALESCE(payload->>'eventCount', payload->>'event_count') ~ '^-?\\d+$'
          THEN COALESCE(payload->>'eventCount', payload->>'event_count')::int
          ELSE 1
        END AS event_count,
        COALESCE(payload->>'kind', payload->>'eventKind', payload->>'event_kind') AS event_kind,
        COALESCE(payload->>'processName', payload->>'process_name') AS process_name,
        payload->>'category' AS category
      FROM sync_objects
      WHERE user_id = $1
        AND deleted_at IS NULL
        AND object_type IN ('tracked_input_event', 'tracked_input_events', 'input_event')
    `;
  }

  private readRange(query: AnalyticsQuery) {
    const dayMs = 24 * 60 * 60 * 1000;
    const now = new Date();
    const end = this.readDate(query.end) ?? now;
    const start = this.readDate(query.start) ?? new Date(end.getTime() - 30 * dayMs);
    return {
      start: start.toISOString(),
      end: end.toISOString(),
    };
  }

  private readBucket(value: string | undefined): Bucket {
    if (value === 'hour' || value === 'month') {
      return value;
    }
    return 'day';
  }

  private readDate(value: string | undefined) {
    if (!value) {
      return undefined;
    }
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? undefined : parsed;
  }

  private readLimit(value: string | undefined, fallback: number) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) {
      return fallback;
    }
    return Math.max(1, Math.min(200, Math.trunc(parsed)));
  }

  private readOffset(value: string | undefined) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) {
      return 0;
    }
    return Math.max(0, Math.trunc(parsed));
  }

  private cleanFilter(value: string | undefined) {
    const trimmed = value?.trim();
    return trimmed && trimmed.length > 0 ? trimmed : null;
  }

  private namedMetricResponse(range: { start: string; end: string }, rows: NamedMetricRow[]) {
    return {
      range,
      source: 'server-live-sync-objects',
      items: rows.map((row) => ({
        name: row.name ?? 'unknown',
        recordCount: this.toNumber(row.record_count),
        eventCount: this.toNumber(row.event_count),
        totalMinutes: this.toNumber(row.total_minutes),
      })),
    };
  }

  private detailResponse(
    range: { start: string; end: string },
    limit: number,
    offset: number,
    rows: DetailRow[],
  ) {
    return {
      range,
      limit,
      offset,
      hasMore: rows.length >= limit,
      source: 'server-live-sync-objects',
      items: rows.map((row) => ({
        serverId: row.server_id,
        objectType: row.object_type,
        occurredAt: this.iso(row.occurred_at),
        updatedAt: this.iso(row.updated_at),
        metricCount: this.toNumber(row.metric_count),
        metricMinutes: this.toNumber(row.metric_minutes),
        payload: row.payload,
      })),
    };
  }

  private toNumber(value: string | number | undefined) {
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = Number(value);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return 0;
  }

  private iso(value: Date | string) {
    if (value instanceof Date) {
      return value.toISOString();
    }
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? value : parsed.toISOString();
  }
}
