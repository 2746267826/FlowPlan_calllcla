import { BadRequestException, Injectable } from '@nestjs/common';
import { QueryResultRow } from 'pg';
import { FlowPlanV2RequestContext } from '../common/request-context';
import { DatabaseService } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';

export interface AnalyticsQuery {
  start?: string;
  end?: string;
  date?: string;
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

type KeyMetricRow = QueryResultRow & {
  key_code: string | number;
  label: string | null;
  event_count: string | number;
};

type MouseMetricRow = QueryResultRow & {
  name: string | null;
  event_count: string | number;
};

type ProcessInputMetricRow = QueryResultRow & {
  process_name: string | null;
  event_count: string | number;
  keyboard_event_count: string | number;
  mouse_button_event_count: string | number;
  wheel_event_count: string | number;
  mouse_move_event_count: string | number;
  mouse_move_distance: string | number;
  active_minutes: string | number;
  intensity_score: string | number;
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

  async trackerHome(query: AnalyticsQuery, context: FlowPlanV2RequestContext) {
    const now = new Date();
    const dayRange = this.readDayRange(query.date ?? query.start);
    const monthStart = new Date(dayRange.start);
    monthStart.setDate(1);
    monthStart.setHours(0, 0, 0, 0);
    const [daySummary, heatmap, topApps, topCategories, inputHeatmap, filterOptions] =
      await Promise.all([
        this.activityDaySummary({ date: dayRange.start }, context),
        this.activityHeatmap(
          {
            start: monthStart.toISOString(),
            end: now.toISOString(),
            bucket: 'day',
          },
          context,
        ),
        this.topApps({ start: dayRange.start, end: dayRange.end, limit: '10' }, context),
        this.topCategories({ start: dayRange.start, end: dayRange.end, limit: '10' }, context),
        this.inputHeatmap({ start: dayRange.start, end: dayRange.end, bucket: 'hour' }, context),
        this.filterOptions({ start: dayRange.start, end: dayRange.end }, context),
      ]);
    return {
      range: dayRange,
      source: 'server-tracker-home-view-model',
      daySummary,
      activityHeatmap: heatmap,
      topApps,
      topCategories,
      inputHeatmap,
      filterOptions,
    };
  }

  async activityDaySummary(
    query: AnalyticsQuery,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const range = this.readDayRange(query.date ?? query.start);
    return this.composedSummary(userId, range, 20);
  }

  async rangeAnalysis(query: AnalyticsQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const range = this.readRange(query);
    const bucket = this.readBucket(query.bucket);
    const summary = await this.composedSummary(userId, range, 30);
    return {
      ...summary,
      bucket,
      source: 'server-range-analysis-view-model',
    };
  }

  async filterOptions(query: AnalyticsQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const range = this.readRange(query);
    const result = await this.database.query<QueryResultRow>(
      `
      WITH activity AS (${this.activitySourceSql()}),
      input_events AS (${this.inputSourceSql()}),
      names AS (
        SELECT app_name AS process_name, category FROM activity
        WHERE occurred_at >= $2 AND occurred_at < $3
        UNION ALL
        SELECT process_name, category FROM input_events
        WHERE occurred_at >= $2 AND occurred_at < $3
      )
      SELECT
        ARRAY(
          SELECT DISTINCT process_name
          FROM names
          WHERE process_name IS NOT NULL AND process_name <> ''
          ORDER BY process_name
          LIMIT 200
        ) AS process_options,
        ARRAY(
          SELECT DISTINCT category
          FROM names
          WHERE category IS NOT NULL AND category <> ''
          ORDER BY category
          LIMIT 200
        ) AS category_options
      `,
      [userId, range.start, range.end],
    );
    const row = result.rows[0] ?? {};
    return {
      range,
      source: 'server-filter-options',
      processOptions: Array.isArray(row.process_options) ? row.process_options : [],
      categoryOptions: Array.isArray(row.category_options) ? row.category_options : [],
    };
  }

  async activityHeatmap(
    query: AnalyticsQuery,
    context: FlowPlanV2RequestContext,
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
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const range = this.readRange(query);
    const bucket = this.readBucket(query.bucket);
    const processName = this.cleanFilter(query.processName);
    const category = this.cleanFilter(query.category);
    const eventKind = this.cleanFilter(query.eventKind);
    const commonParams = [userId, range.start, range.end, processName, category, eventKind];
    const [bucketResult, keyResult, mouseResult, processResult] = await Promise.all([
      this.database.query<BucketRow>(
      `
      WITH input_events AS (${this.inputSourceSql()})
      SELECT
        date_trunc($4, occurred_at) AS bucket_start,
        COALESCE(SUM(event_count), 0)::int AS event_count,
        COALESCE(SUM(CASE WHEN event_kind = 'key_down' THEN event_count ELSE 0 END), 0)::int AS keyboard_event_count,
        COALESCE(SUM(CASE WHEN event_kind IN ('mouse_button', 'mouse_button_down') THEN event_count ELSE 0 END), 0)::int AS mouse_button_event_count,
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
      ),
      this.database.query<KeyMetricRow>(
        `
        WITH input_events AS (${this.inputSourceSql()})
        SELECT
          key_code,
          COALESCE(NULLIF(MAX(key_label), ''), key_code::text) AS label,
          COALESCE(SUM(event_count), 0)::int AS event_count
        FROM input_events
        WHERE occurred_at >= $2
          AND occurred_at < $3
          AND ($4::text IS NULL OR process_name = $4)
          AND ($5::text IS NULL OR category = $5)
          AND ($6::text IS NULL OR event_kind = $6)
          AND event_kind = 'key_down'
          AND key_code IS NOT NULL
        GROUP BY key_code
        ORDER BY event_count DESC, key_code ASC
        LIMIT 60
        `,
        commonParams,
      ),
      this.database.query<MouseMetricRow>(
        `
        WITH input_events AS (${this.inputSourceSql()}),
        mouse_events AS (
          SELECT
            CASE
              WHEN event_kind IN ('mouse_button', 'mouse_button_down') THEN COALESCE(NULLIF(mouse_button, ''), 'button')
              WHEN event_kind = 'mouse_wheel' AND wheel_delta > 0 THEN 'wheel_up'
              WHEN event_kind = 'mouse_wheel' AND wheel_delta < 0 THEN 'wheel_down'
              WHEN event_kind = 'mouse_wheel' THEN 'wheel'
              WHEN event_kind = 'mouse_move' THEN 'move'
              ELSE NULL
            END AS name,
            event_count
          FROM input_events
          WHERE occurred_at >= $2
            AND occurred_at < $3
            AND ($4::text IS NULL OR process_name = $4)
            AND ($5::text IS NULL OR category = $5)
            AND ($6::text IS NULL OR event_kind = $6)
        )
        SELECT name, COALESCE(SUM(event_count), 0)::int AS event_count
        FROM mouse_events
        WHERE name IS NOT NULL
        GROUP BY name
        ORDER BY event_count DESC, name ASC
        `,
        commonParams,
      ),
      this.database.query<ProcessInputMetricRow>(
        `
        WITH input_events AS (${this.inputSourceSql()})
        SELECT
          COALESCE(NULLIF(process_name, ''), 'unknown') AS process_name,
          COALESCE(SUM(event_count), 0)::int AS event_count,
          COALESCE(SUM(CASE WHEN event_kind = 'key_down' THEN event_count ELSE 0 END), 0)::int AS keyboard_event_count,
          COALESCE(SUM(CASE WHEN event_kind IN ('mouse_button', 'mouse_button_down') THEN event_count ELSE 0 END), 0)::int AS mouse_button_event_count,
          COALESCE(SUM(CASE WHEN event_kind = 'mouse_wheel' THEN event_count ELSE 0 END), 0)::int AS wheel_event_count,
          COALESCE(SUM(CASE WHEN event_kind = 'mouse_move' THEN event_count ELSE 0 END), 0)::int AS mouse_move_event_count,
          COALESCE(SUM(CASE WHEN event_kind = 'mouse_move' THEN move_distance ELSE 0 END), 0)::int AS mouse_move_distance,
          COUNT(DISTINCT date_trunc('minute', occurred_at))::int AS active_minutes,
          (
            COALESCE(SUM(CASE WHEN event_kind = 'key_down' THEN event_count ELSE 0 END), 0) +
            COALESCE(SUM(CASE WHEN event_kind IN ('mouse_button', 'mouse_button_down') THEN event_count * 4 ELSE 0 END), 0) +
            COALESCE(SUM(CASE WHEN event_kind = 'mouse_wheel' THEN event_count * 2 ELSE 0 END), 0) +
            COALESCE(SUM(CASE WHEN event_kind = 'mouse_move' THEN event_count ELSE 0 END), 0) +
            COALESCE(SUM(CASE WHEN event_kind = 'mouse_move' THEN move_distance / 200 ELSE 0 END), 0)
          )::int AS intensity_score
        FROM input_events
        WHERE occurred_at >= $2
          AND occurred_at < $3
          AND ($4::text IS NULL OR process_name = $4)
          AND ($5::text IS NULL OR category = $5)
          AND ($6::text IS NULL OR event_kind = $6)
        GROUP BY process_name
        ORDER BY intensity_score DESC, event_count DESC, process_name ASC
        LIMIT 12
        `,
        commonParams,
      ),
    ]);

    const keyCounts = keyResult.rows.reduce<Record<string, number>>((acc, row) => {
      acc[String(row.key_code)] = this.toNumber(row.event_count);
      return acc;
    }, {});
    const mouseCounts = mouseResult.rows.reduce<Record<string, number>>((acc, row) => {
      const name = row.name ?? 'unknown';
      acc[name] = this.toNumber(row.event_count);
      return acc;
    }, {});
    const keyboardTotal = keyResult.rows.reduce(
      (sum, row) => sum + this.toNumber(row.event_count),
      0,
    );

    return {
      range,
      bucket,
      source: 'server-live-sync-objects',
      buckets: bucketResult.rows.map((row) => ({
        bucketStart: this.iso(row.bucket_start),
        eventCount: this.toNumber(row.event_count),
        keyboardEventCount: this.toNumber(row.keyboard_event_count),
        mouseButtonEventCount: this.toNumber(row.mouse_button_event_count),
        wheelEventCount: this.toNumber(row.wheel_event_count),
        mouseMoveEventCount: this.toNumber(row.mouse_move_event_count),
        mouseMoveDistance: this.toNumber(row.mouse_move_distance),
      })),
      keyCounts,
      topKeys: keyResult.rows.map((row) => {
        const count = this.toNumber(row.event_count);
        return {
          keyCode: this.toNumber(row.key_code),
          label: row.label ?? String(row.key_code),
          count,
          share: keyboardTotal > 0 ? count / keyboardTotal : 0,
        };
      }),
      mouseCounts,
      processIntensities: processResult.rows.map((row) => ({
        processName: row.process_name ?? 'unknown',
        totalEvents: this.toNumber(row.event_count),
        keyEvents: this.toNumber(row.keyboard_event_count),
        mouseButtonEvents: this.toNumber(row.mouse_button_event_count),
        wheelEvents: this.toNumber(row.wheel_event_count),
        mouseMoveEvents: this.toNumber(row.mouse_move_event_count),
        moveDistance: this.toNumber(row.mouse_move_distance),
        activeMinutes: this.toNumber(row.active_minutes),
        intensityScore: this.toNumber(row.intensity_score),
      })),
    };
  }

  async activityRangeSummary(
    query: AnalyticsQuery,
    context: FlowPlanV2RequestContext,
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

  async topApps(query: AnalyticsQuery, context: FlowPlanV2RequestContext) {
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

  async topCategories(query: AnalyticsQuery, context: FlowPlanV2RequestContext) {
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
    context: FlowPlanV2RequestContext,
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

  async focusTrends(query: AnalyticsQuery, context: FlowPlanV2RequestContext) {
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
    context: FlowPlanV2RequestContext,
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

  async inputEvents(query: AnalyticsQuery, context: FlowPlanV2RequestContext) {
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

  private async composedSummary(
    userId: string,
    range: { start: string; end: string },
    previewLimit: number,
  ) {
    const [summary, topProcesses, topCategories, sessions, preview] =
      await Promise.all([
        this.activityTotals(userId, range),
        this.activitySlices(userId, range, 'process'),
        this.activitySlices(userId, range, 'category'),
        this.activitySessions(userId, range, 80),
        this.activityPreview(userId, range, previewLimit),
      ]);
    return {
      range,
      source: 'server-processed-tracking-view-model',
      insights: {
        ...summary,
        topProcesses,
        topCategories,
        busiestRecords: preview.slice(0, 3),
      },
      sessions,
      previewRecords: preview,
    };
  }

  private async activityTotals(userId: string, range: { start: string; end: string }) {
    const result = await this.database.query<QueryResultRow>(
      `
      WITH activity AS (${this.activitySourceSql()})
      SELECT
        COUNT(*)::int AS record_count,
        COALESCE(SUM(duration_minutes), 0)::int AS total_minutes,
        COALESCE(SUM(CASE WHEN key_count > 0 OR mouse_clicks > 0 OR mouse_move_px > 0 OR scroll_px > 0 THEN duration_minutes ELSE 0 END), 0)::int AS focus_minutes,
        COALESCE(SUM(key_count), 0)::int AS key_count,
        COALESCE(SUM(mouse_clicks), 0)::int AS mouse_clicks,
        COALESCE(SUM(mouse_move_px), 0)::int AS mouse_move_px,
        COALESCE(SUM(scroll_px), 0)::int AS scroll_px,
        COALESCE(SUM(CASE WHEN key_count > 0 OR mouse_clicks > 0 OR mouse_move_px > 0 OR scroll_px > 0 THEN 1 ELSE 0 END), 0)::int AS productive_record_count
      FROM activity
      WHERE occurred_at >= $2 AND occurred_at < $3
      `,
      [userId, range.start, range.end],
    );
    const row = result.rows[0] ?? {};
    return {
      recordCount: this.toNumber(row.record_count),
      totalMinutes: this.toNumber(row.total_minutes),
      focusMinutes: this.toNumber(row.focus_minutes),
      totalKeys: this.toNumber(row.key_count),
      totalClicks: this.toNumber(row.mouse_clicks),
      totalMovePx: this.toNumber(row.mouse_move_px),
      totalScrollPx: this.toNumber(row.scroll_px),
      productiveRecordCount: this.toNumber(row.productive_record_count),
      sequenceRecordCount: 0,
    };
  }

  private async activitySlices(
    userId: string,
    range: { start: string; end: string },
    group: 'process' | 'category',
  ) {
    const field = group === 'process'
      ? `COALESCE(NULLIF(app_name, ''), 'unknown')`
      : `COALESCE(NULLIF(category, ''), 'uncategorized')`;
    const result = await this.database.query<QueryResultRow>(
      `
      WITH activity AS (${this.activitySourceSql()})
      SELECT
        ${field} AS label,
        COUNT(*)::int AS sessions,
        COALESCE(SUM(duration_minutes), 0)::int AS minutes,
        COALESCE(SUM(key_count), 0)::int AS keys,
        COALESCE(SUM(mouse_clicks), 0)::int AS clicks,
        COALESCE(SUM(mouse_move_px), 0)::int AS move_px,
        COALESCE(SUM(scroll_px), 0)::int AS scroll_px
      FROM activity
      WHERE occurred_at >= $2 AND occurred_at < $3
      GROUP BY label
      ORDER BY minutes DESC, sessions DESC, label ASC
      LIMIT 10
      `,
      [userId, range.start, range.end],
    );
    return result.rows.map((row) => ({
      label: String(row.label ?? ''),
      minutes: this.toNumber(row.minutes),
      keys: this.toNumber(row.keys),
      clicks: this.toNumber(row.clicks),
      movePx: this.toNumber(row.move_px),
      scrollPx: this.toNumber(row.scroll_px),
      sessions: this.toNumber(row.sessions),
    }));
  }

  private async activityPreview(
    userId: string,
    range: { start: string; end: string },
    limit: number,
  ) {
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
      WHERE occurred_at >= $2 AND occurred_at < $3
      ORDER BY occurred_at DESC, server_id DESC
      LIMIT $4
      `,
      [userId, range.start, range.end, Math.max(1, Math.min(50, limit))],
    );
    return this.detailResponse(range, limit, 0, result.rows).items;
  }

  private async activitySessions(
    userId: string,
    range: { start: string; end: string },
    limit: number,
  ) {
    const result = await this.database.query<QueryResultRow>(
      `
      WITH activity AS (${this.activitySourceSql()}),
      prepared AS (
        SELECT
          occurred_at,
          occurred_at + (duration_minutes || ' minutes')::interval AS ended_at,
          GREATEST(duration_minutes::int, 1) AS duration_minutes,
          key_count,
          mouse_clicks,
          mouse_move_px,
          scroll_px,
          COALESCE(NULLIF(app_name, ''), 'unknown') AS process_name,
          COALESCE(NULLIF(category, ''), 'uncategorized') AS category,
          COALESCE(NULLIF(linked_task_id, ''), '') AS linked_task_id,
          COALESCE(NULLIF(linked_task_id, ''), NULLIF(category, ''), NULLIF(app_name, ''), 'unknown') AS signature
        FROM activity
        WHERE occurred_at >= $2 AND occurred_at < $3
      ),
      marked AS (
        SELECT *,
          CASE
            WHEN LAG(ended_at) OVER (ORDER BY occurred_at) IS NULL THEN 1
            WHEN occurred_at - LAG(ended_at) OVER (ORDER BY occurred_at) > interval '3 minutes' THEN 1
            WHEN signature <> LAG(signature) OVER (ORDER BY occurred_at) THEN 1
            ELSE 0
          END AS new_group
        FROM prepared
      ),
      grouped AS (
        SELECT *,
          SUM(new_group) OVER (ORDER BY occurred_at ROWS UNBOUNDED PRECEDING) AS group_id
        FROM marked
      )
      SELECT
        MIN(occurred_at) AS start_time,
        MAX(ended_at) AS end_time,
        SUM(duration_minutes)::int AS duration_minutes,
        SUM(key_count)::int AS key_count,
        SUM(mouse_clicks)::int AS mouse_clicks,
        SUM(mouse_move_px)::int AS mouse_move_px,
        SUM(scroll_px)::int AS scroll_px,
        COUNT(*)::int AS raw_record_count,
        ARRAY_AGG(DISTINCT process_name) AS process_names,
        ARRAY_AGG(DISTINCT category) AS categories
      FROM grouped
      GROUP BY group_id
      ORDER BY start_time DESC
      LIMIT $4
      `,
      [userId, range.start, range.end, Math.max(1, Math.min(200, limit))],
    );
    return result.rows.map((row) => {
      const processNames = Array.isArray(row.process_names) ? row.process_names : [];
      const categories = Array.isArray(row.categories) ? row.categories : [];
      const label = String(categories[0] ?? processNames[0] ?? '未命名工作会话');
      return {
        startTime: this.iso(row.start_time),
        endTime: this.iso(row.end_time),
        label,
        processName: processNames[0] ?? null,
        category: categories[0] ?? null,
        durationMinutes: this.toNumber(row.duration_minutes),
        keyCount: this.toNumber(row.key_count),
        mouseClicks: this.toNumber(row.mouse_clicks),
        mouseMovePx: this.toNumber(row.mouse_move_px),
        scrollPx: this.toNumber(row.scroll_px),
        processNames,
        categories,
        rawRecordCount: this.toNumber(row.raw_record_count),
        interruptionCount: 0,
      };
    });
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
          WHEN COALESCE(payload->>'eventCount', payload->>'event_count', payload->'metadata'->>'eventCount', payload->'metadata'->>'event_count') ~ '^-?\\d+$'
          THEN COALESCE(payload->>'eventCount', payload->>'event_count', payload->'metadata'->>'eventCount', payload->'metadata'->>'event_count')::int
          ELSE 1
        END AS event_count,
        COALESCE(payload->>'eventKind', payload->>'event_kind', payload->>'kind') AS event_kind,
        CASE
          WHEN COALESCE(payload->>'moveDistance', payload->>'move_distance', payload->'metadata'->>'moveDistance', payload->'metadata'->>'move_distance') ~ '^-?\\d+$'
          THEN COALESCE(payload->>'moveDistance', payload->>'move_distance', payload->'metadata'->>'moveDistance', payload->'metadata'->>'move_distance')::int
          ELSE 0
        END AS move_distance,
        CASE
          WHEN COALESCE(payload->>'keyCode', payload->>'key_code', payload->'metadata'->>'keyCode', payload->'metadata'->>'key_code') ~ '^-?\\d+$'
          THEN COALESCE(payload->>'keyCode', payload->>'key_code', payload->'metadata'->>'keyCode', payload->'metadata'->>'key_code')::int
          ELSE NULL
        END AS key_code,
        COALESCE(payload->>'keyLabel', payload->>'key_label', payload->'metadata'->>'keyLabel', payload->'metadata'->>'key_label', payload->>'tokenText', payload->'metadata'->>'tokenText') AS key_label,
        COALESCE(payload->>'mouseButton', payload->>'mouse_button', payload->'metadata'->>'mouseButton', payload->'metadata'->>'mouse_button') AS mouse_button,
        CASE
          WHEN COALESCE(payload->>'wheelDelta', payload->>'wheel_delta', payload->'metadata'->>'wheelDelta', payload->'metadata'->>'wheel_delta') ~ '^-?\\d+$'
          THEN COALESCE(payload->>'wheelDelta', payload->>'wheel_delta', payload->'metadata'->>'wheelDelta', payload->'metadata'->>'wheel_delta')::int
          ELSE 0
        END AS wheel_delta,
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
          WHEN COALESCE(payload->>'eventCount', payload->>'event_count', payload->'metadata'->>'eventCount', payload->'metadata'->>'event_count') ~ '^-?\\d+$'
          THEN COALESCE(payload->>'eventCount', payload->>'event_count', payload->'metadata'->>'eventCount', payload->'metadata'->>'event_count')::int
          ELSE 1
        END AS event_count,
        COALESCE(payload->>'eventKind', payload->>'event_kind', payload->>'kind') AS event_kind,
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
    const end = this.readDate(query.end, 'end') ?? now;
    const start = this.readDate(query.start, 'start') ?? new Date(end.getTime() - 30 * dayMs);
    if (start >= end) {
      throw new BadRequestException('start must be earlier than end');
    }
    return {
      start: start.toISOString(),
      end: end.toISOString(),
    };
  }

  private readDayRange(value: string | undefined) {
    const date = this.readDate(value, 'date') ?? new Date();
    const start = new Date(date);
    start.setHours(0, 0, 0, 0);
    const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
    return {
      start: start.toISOString(),
      end: end.toISOString(),
    };
  }

  private readBucket(value: string | undefined): Bucket {
    if (!value || value === 'day') {
      return 'day';
    }
    if (value === 'hour' || value === 'month') {
      return value;
    }
    throw new BadRequestException('bucket must be one of hour, day, month');
  }

  private readDate(value: string | undefined, fieldName: string) {
    if (!value) {
      return undefined;
    }
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) {
      throw new BadRequestException(`${fieldName} must be a valid ISO-8601 date`);
    }
    return parsed;
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
