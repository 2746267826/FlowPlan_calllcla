import { BadRequestException } from '@nestjs/common';
import { describe, expect, it, vi } from 'vitest';
import { AnalyticsService } from './analytics.service';

const context = {
  userId: '11111111-1111-4111-8111-111111111111',
  deviceId: '22222222-2222-4222-8222-222222222222',
};

type Row = Record<string, unknown>;
type QueryResult = { rows: Row[] };

function result(rows: Row[] = []): QueryResult {
  return { rows };
}

function createHarness(rowQueues: Row[][] = []) {
  const queues = [...rowQueues];
  const query = vi.fn(async () => result(queues.shift() ?? []));
  const database = { query };
  const devices = {
    ensureUser: vi.fn(async (userId: string) => userId),
  };
  const service = new AnalyticsService(database as never, devices as never);
  return { service, database, devices, query };
}

function createHarnessWithQuery(
  queryImpl: (sql: string, params?: unknown[]) => Promise<QueryResult>,
) {
  const query = vi.fn(queryImpl);
  const database = { query };
  const devices = {
    ensureUser: vi.fn(async (userId: string) => userId),
  };
  const service = new AnalyticsService(database as never, devices as never);
  return { service, database, devices, query };
}

function dayRangeFor(value?: string) {
  const date = value ? new Date(value) : new Date();
  const start = new Date(date);
  start.setHours(0, 0, 0, 0);
  return {
    start: start.toISOString(),
    end: new Date(start.getTime() + 24 * 60 * 60 * 1000).toISOString(),
  };
}

function callsContaining(query: ReturnType<typeof vi.fn>, fragment: string) {
  return query.mock.calls.filter(([sql]) => String(sql).includes(fragment));
}

describe('AnalyticsService tracker view models', () => {
  it('composes trackerHome from daily, monthly, ranked, input, and filter views', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-08T12:00:00.000Z'));
    const { service } = createHarness();
    const dayRange = dayRangeFor();
    const monthStart = new Date(dayRange.start);
    monthStart.setDate(1);
    monthStart.setHours(0, 0, 0, 0);

    const daySummary = { source: 'day-summary' };
    const activityHeatmap = { source: 'activity-heatmap' };
    const topApps = { items: ['apps'] };
    const topCategories = { items: ['categories'] };
    const inputHeatmap = { source: 'input-heatmap' };
    const filterOptions = { processOptions: ['Code'] };
    vi.spyOn(service, 'activityDaySummary').mockResolvedValue(daySummary as never);
    vi.spyOn(service, 'activityHeatmap').mockResolvedValue(activityHeatmap as never);
    vi.spyOn(service, 'topApps').mockResolvedValue(topApps as never);
    vi.spyOn(service, 'topCategories').mockResolvedValue(topCategories as never);
    vi.spyOn(service, 'inputHeatmap').mockResolvedValue(inputHeatmap as never);
    vi.spyOn(service, 'filterOptions').mockResolvedValue(filterOptions as never);

    await expect(service.trackerHome({}, context)).resolves.toEqual({
      range: dayRange,
      source: 'server-tracker-home-view-model',
      daySummary,
      activityHeatmap,
      topApps,
      topCategories,
      inputHeatmap,
      filterOptions,
    });
    expect(service.activityDaySummary).toHaveBeenCalledWith({ date: dayRange.start }, context);
    expect(service.activityHeatmap).toHaveBeenCalledWith(
      {
        start: monthStart.toISOString(),
        end: '2026-06-08T12:00:00.000Z',
        bucket: 'day',
      },
      context,
    );
    expect(service.topApps).toHaveBeenCalledWith(
      { start: dayRange.start, end: dayRange.end, limit: '10' },
      context,
    );
    expect(service.topCategories).toHaveBeenCalledWith(
      { start: dayRange.start, end: dayRange.end, limit: '10' },
      context,
    );
    expect(service.inputHeatmap).toHaveBeenCalledWith(
      { start: dayRange.start, end: dayRange.end, bucket: 'hour' },
      context,
    );
    expect(service.filterOptions).toHaveBeenCalledWith(
      { start: dayRange.start, end: dayRange.end },
      context,
    );
  });

  it('builds a composed day summary with totals, slices, sessions, and preview records', async () => {
    const dayRange = dayRangeFor('2026-06-08T15:30:00.000Z');
    const previewRow = {
      server_id: 'activity-1',
      object_type: 'activity_record',
      occurred_at: '2026-06-08T09:00:00.000Z',
      updated_at: new Date('2026-06-08T09:30:00.000Z'),
      metric_count: '1',
      metric_minutes: '45',
      payload: { processName: 'Code' },
    };
    const { service, devices, query } = createHarness([
      [
        {
          record_count: '4',
          total_minutes: '90',
          focus_minutes: '75',
          key_count: '100',
          mouse_clicks: '8',
          mouse_move_px: '900',
          scroll_px: '1200',
          productive_record_count: '3',
        },
      ],
      [{ label: 'Code', minutes: '60', keys: '70', clicks: '4', move_px: '300', scroll_px: '500', sessions: '2' }],
      [{ label: 'coding', minutes: '60', keys: '70', clicks: '4', move_px: '300', scroll_px: '500', sessions: '2' }],
      [
        {
          start_time: '2026-06-08T09:00:00.000Z',
          end_time: '2026-06-08T10:00:00.000Z',
          duration_minutes: '60',
          key_count: '70',
          mouse_clicks: '4',
          mouse_move_px: '300',
          scroll_px: '500',
          raw_record_count: '2',
          process_names: ['Code', 'Terminal'],
          categories: ['coding'],
        },
      ],
      [previewRow, { ...previewRow, server_id: 'activity-2' }, { ...previewRow, server_id: 'activity-3' }, { ...previewRow, server_id: 'activity-4' }],
    ]);

    const response = await service.activityDaySummary(
      { date: '2026-06-08T15:30:00.000Z' },
      context,
    );

    expect(devices.ensureUser).toHaveBeenCalledWith(context.userId);
    expect(response).toMatchObject({
      range: dayRange,
      source: 'server-processed-tracking-view-model',
      insights: {
        recordCount: 4,
        totalMinutes: 90,
        focusMinutes: 75,
        totalKeys: 100,
        totalClicks: 8,
        totalMovePx: 900,
        totalScrollPx: 1200,
        productiveRecordCount: 3,
        sequenceRecordCount: 0,
        topProcesses: [
          { label: 'Code', minutes: 60, keys: 70, clicks: 4, movePx: 300, scrollPx: 500, sessions: 2 },
        ],
        topCategories: [
          { label: 'coding', minutes: 60, keys: 70, clicks: 4, movePx: 300, scrollPx: 500, sessions: 2 },
        ],
      },
      sessions: [
        {
          startTime: '2026-06-08T09:00:00.000Z',
          endTime: '2026-06-08T10:00:00.000Z',
          label: 'coding',
          processName: 'Code',
          category: 'coding',
          durationMinutes: 60,
          keyCount: 70,
          mouseClicks: 4,
          mouseMovePx: 300,
          scrollPx: 500,
          processNames: ['Code', 'Terminal'],
          categories: ['coding'],
          rawRecordCount: 2,
          interruptionCount: 0,
        },
      ],
    });
    expect(response.previewRecords).toHaveLength(4);
    expect(response.insights.busiestRecords).toHaveLength(3);
    expect(response.previewRecords[0]).toEqual({
      serverId: 'activity-1',
      objectType: 'activity_record',
      occurredAt: '2026-06-08T09:00:00.000Z',
      updatedAt: '2026-06-08T09:30:00.000Z',
      metricCount: 1,
      metricMinutes: 45,
      payload: { processName: 'Code' },
    });
    expect(query).toHaveBeenCalledTimes(5);
    expect(query).toHaveBeenNthCalledWith(4, expect.stringContaining('ARRAY_AGG(DISTINCT process_name)'), [
      context.userId,
      dayRange.start,
      dayRange.end,
      80,
    ]);
    expect(query).toHaveBeenNthCalledWith(5, expect.stringContaining('LIMIT $4'), [
      context.userId,
      dayRange.start,
      dayRange.end,
      20,
    ]);
  });

  it('uses start as the day summary date and applies empty slice/session fallbacks', async () => {
    const dayRange = dayRangeFor('2026-06-09T05:00:00.000Z');
    const { service, query } = createHarness([
      [{}],
      [{ label: null }],
      [{ label: null }],
      [
        {
          start_time: null,
          end_time: null,
          process_names: 'not-array',
          categories: 'not-array',
        },
      ],
      [],
    ]);

    const response = await service.activityDaySummary(
      { start: '2026-06-09T05:00:00.000Z' },
      context,
    );

    expect(response.range).toEqual(dayRange);
    expect(response.insights.topProcesses).toEqual([
      { label: '', minutes: 0, keys: 0, clicks: 0, movePx: 0, scrollPx: 0, sessions: 0 },
    ]);
    expect(response.insights.topCategories).toEqual([
      { label: '', minutes: 0, keys: 0, clicks: 0, movePx: 0, scrollPx: 0, sessions: 0 },
    ]);
    expect(response.sessions).toEqual([
      {
        startTime: null,
        endTime: null,
        label: expect.any(String),
        processName: null,
        category: null,
        durationMinutes: 0,
        keyCount: 0,
        mouseClicks: 0,
        mouseMovePx: 0,
        scrollPx: 0,
        processNames: [],
        categories: [],
        rawRecordCount: 0,
        interruptionCount: 0,
      },
    ]);
    expect(query.mock.calls.map((call) => call[1])).toEqual([
      [context.userId, dayRange.start, dayRange.end],
      [context.userId, dayRange.start, dayRange.end],
      [context.userId, dayRange.start, dayRange.end],
      [context.userId, dayRange.start, dayRange.end, 80],
      [context.userId, dayRange.start, dayRange.end, 20],
    ]);
  });

  it('returns a range-analysis view with default zero summary values and selected bucket', async () => {
    const start = '2026-06-01T00:00:00.000Z';
    const end = '2026-06-08T00:00:00.000Z';
    const { service } = createHarness([[], [], [], [], []]);

    await expect(service.rangeAnalysis({ start, end, bucket: 'month' }, context)).resolves.toMatchObject({
      range: { start, end },
      bucket: 'month',
      source: 'server-range-analysis-view-model',
      insights: {
        recordCount: 0,
        totalMinutes: 0,
        focusMinutes: 0,
        totalKeys: 0,
        totalClicks: 0,
        totalMovePx: 0,
        totalScrollPx: 0,
        productiveRecordCount: 0,
        sequenceRecordCount: 0,
        topProcesses: [],
        topCategories: [],
        busiestRecords: [],
      },
      sessions: [],
      previewRecords: [],
    });
  });
});

describe('AnalyticsService query endpoints', () => {
  it('returns filter options from combined activity and input names', async () => {
    const start = '2026-06-01T00:00:00.000Z';
    const end = '2026-06-08T00:00:00.000Z';
    const { service, query } = createHarness([
      [{ process_options: ['Code', 'Terminal'], category_options: ['coding', 'ops'] }],
    ]);

    await expect(service.filterOptions({ start, end }, context)).resolves.toEqual({
      range: { start, end },
      source: 'server-filter-options',
      processOptions: ['Code', 'Terminal'],
      categoryOptions: ['coding', 'ops'],
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('process_options'), [
      context.userId,
      start,
      end,
    ]);
  });

  it('falls filter options back to empty arrays for missing or non-array rows', async () => {
    const start = '2026-06-01T00:00:00.000Z';
    const end = '2026-06-08T00:00:00.000Z';
    const { service } = createHarness([[]]);

    await expect(service.filterOptions({ start, end }, context)).resolves.toMatchObject({
      processOptions: [],
      categoryOptions: [],
    });
  });

  it('maps activity heatmap buckets and trims optional filters', async () => {
    const start = '2026-06-01T00:00:00.000Z';
    const end = '2026-06-08T00:00:00.000Z';
    const { service, query } = createHarness([
      [{ bucket_start: new Date('2026-06-01T01:00:00.000Z'), record_count: '3', total_minutes: '40' }],
    ]);

    await expect(
      service.activityHeatmap(
        { start, end, bucket: 'hour', processName: ' Code ', category: ' coding ', taskId: ' ' },
        context,
      ),
    ).resolves.toEqual({
      range: { start, end },
      bucket: 'hour',
      source: 'server-live-sync-objects',
      buckets: [
        {
          bucketStart: '2026-06-01T01:00:00.000Z',
          recordCount: 3,
          totalMinutes: 40,
        },
      ],
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('date_trunc($4, occurred_at)'), [
      context.userId,
      start,
      end,
      'hour',
      'Code',
      'coding',
      null,
    ]);
  });

  it('maps input heatmap buckets, keys, mouse counts, and process intensities', async () => {
    const start = '2026-06-01T00:00:00.000Z';
    const end = '2026-06-08T00:00:00.000Z';
    const { service, query } = createHarness([
      [
        {
          bucket_start: '2026-06-01T00:00:00.000Z',
          event_count: '20',
          keyboard_event_count: '10',
          mouse_button_event_count: '3',
          wheel_event_count: '2',
          mouse_move_event_count: '5',
          mouse_move_distance: '600',
        },
      ],
      [
        { key_code: '65', label: 'A', event_count: '6' },
        { key_code: 13, label: null, event_count: '4' },
      ],
      [
        { name: 'left', event_count: '3' },
        { name: null, event_count: '1' },
      ],
      [
        {
          process_name: null,
          event_count: '20',
          keyboard_event_count: '10',
          mouse_button_event_count: '3',
          wheel_event_count: '2',
          mouse_move_event_count: '5',
          mouse_move_distance: '600',
          active_minutes: '9',
          intensity_score: '42',
        },
      ],
    ]);

    await expect(
      service.inputHeatmap(
        { start, end, bucket: 'month', processName: ' Code ', category: ' ', eventKind: 'key_down' },
        context,
      ),
    ).resolves.toEqual({
      range: { start, end },
      bucket: 'month',
      source: 'server-live-sync-objects',
      buckets: [
        {
          bucketStart: '2026-06-01T00:00:00.000Z',
          eventCount: 20,
          keyboardEventCount: 10,
          mouseButtonEventCount: 3,
          wheelEventCount: 2,
          mouseMoveEventCount: 5,
          mouseMoveDistance: 600,
        },
      ],
      keyCounts: { '13': 4, '65': 6 },
      topKeys: [
        { keyCode: 65, label: 'A', count: 6, share: 0.6 },
        { keyCode: 13, label: '13', count: 4, share: 0.4 },
      ],
      mouseCounts: { left: 3, unknown: 1 },
      processIntensities: [
        {
          processName: 'unknown',
          totalEvents: 20,
          keyEvents: 10,
          mouseButtonEvents: 3,
          wheelEvents: 2,
          mouseMoveEvents: 5,
          moveDistance: 600,
          activeMinutes: 9,
          intensityScore: 42,
        },
      ],
    });
    expect(query).toHaveBeenNthCalledWith(1, expect.stringContaining('keyboard_event_count'), [
      context.userId,
      start,
      end,
      'month',
      'Code',
      null,
      'key_down',
    ]);
    expect(query).toHaveBeenNthCalledWith(2, expect.stringContaining('key_code'), [
      context.userId,
      start,
      end,
      'Code',
      null,
      'key_down',
    ]);
  });

  it('keeps top key share at zero when the keyboard total is zero', async () => {
    const start = '2026-06-01T00:00:00.000Z';
    const end = '2026-06-08T00:00:00.000Z';
    const { service } = createHarness([
      [],
      [{ key_code: '9', label: 'Tab', event_count: '0' }],
      [],
      [],
    ]);

    const response = await service.inputHeatmap({ start, end }, context);

    expect(response.bucket).toBe('day');
    expect(response.topKeys).toEqual([{ keyCode: 9, label: 'Tab', count: 0, share: 0 }]);
  });

  it('summarizes an activity range and returns zero totals when no aggregate row is present', async () => {
    const start = '2026-06-01T00:00:00.000Z';
    const end = '2026-06-08T00:00:00.000Z';
    const { service } = createHarness([[]]);

    await expect(service.activityRangeSummary({ start, end }, context)).resolves.toEqual({
      range: { start, end },
      source: 'server-live-sync-objects',
      recordCount: 0,
      totalMinutes: 0,
      keyCount: 0,
      mouseClicks: 0,
      mouseMovePx: 0,
      scrollPx: 0,
    });
  });

  it('normalizes limits and names for top apps, categories, and task summaries', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-08T12:00:00.000Z'));
    const { service, query } = createHarness([
      [{ name: 'Code', record_count: '2', total_minutes: '70' }],
      [{ name: null, record_count: '3', event_count: '7', total_minutes: '50' }],
      [{ name: 'task-1', record_count: '1', total_minutes: '25' }],
      [{ name: 'unlinked', record_count: '1', total_minutes: '5' }],
    ]);
    const defaultEnd = '2026-06-08T12:00:00.000Z';
    const defaultStart = '2026-05-09T12:00:00.000Z';

    await expect(service.topApps({ limit: '999' }, context)).resolves.toEqual({
      range: { start: defaultStart, end: defaultEnd },
      source: 'server-live-sync-objects',
      items: [{ name: 'Code', recordCount: 2, eventCount: 0, totalMinutes: 70 }],
    });
    await expect(
      service.topCategories({ start: defaultStart, end: defaultEnd, limit: '0' }, context),
    ).resolves.toMatchObject({
      items: [{ name: 'unknown', recordCount: 3, eventCount: 7, totalMinutes: 50 }],
    });
    await expect(
      service.taskWorkSummary({ start: defaultStart, end: defaultEnd, limit: 'not-a-number', taskId: ' task-1 ' }, context),
    ).resolves.toMatchObject({
      items: [{ name: 'task-1', recordCount: 1, eventCount: 0, totalMinutes: 25 }],
    });
    await expect(
      service.taskWorkSummary({ start: defaultStart, end: defaultEnd, limit: '2', taskId: ' ' }, context),
    ).resolves.toMatchObject({
      items: [{ name: 'unlinked', recordCount: 1, eventCount: 0, totalMinutes: 5 }],
    });
    expect(query.mock.calls[0][1]).toEqual([context.userId, defaultStart, defaultEnd, 200]);
    expect(query.mock.calls[1][1]).toEqual([context.userId, defaultStart, defaultEnd, 1]);
    expect(query.mock.calls[2][1]).toEqual([context.userId, defaultStart, defaultEnd, 50, 'task-1']);
    expect(query.mock.calls[3][1]).toEqual([context.userId, defaultStart, defaultEnd, 2, null]);
  });

  it('computes focus trend ratios including zero-duration buckets', async () => {
    const start = '2026-06-01T00:00:00.000Z';
    const end = '2026-06-08T00:00:00.000Z';
    const { service } = createHarness([
      [
        { bucket_start: '2026-06-01T00:00:00.000Z', total_minutes: '120', record_count: '60' },
        { bucket_start: '2026-06-02T00:00:00.000Z', total_minutes: '0', record_count: '5' },
      ],
    ]);

    await expect(service.focusTrends({ start, end }, context)).resolves.toEqual({
      range: { start, end },
      bucket: 'day',
      source: 'server-live-sync-objects',
      buckets: [
        {
          bucketStart: '2026-06-01T00:00:00.000Z',
          totalMinutes: 120,
          focusMinutes: 60,
          focusRatio: 0.5,
        },
        {
          bucketStart: '2026-06-02T00:00:00.000Z',
          totalMinutes: 0,
          focusMinutes: 5,
          focusRatio: 0,
        },
      ],
    });
  });
});

describe('AnalyticsService detail and export endpoints', () => {
  it('returns paged activity records with normalized filters and hasMore', async () => {
    const start = '2026-06-01T00:00:00.000Z';
    const end = '2026-06-08T00:00:00.000Z';
    const row = {
      server_id: 'activity-1',
      object_type: 'activity_record',
      occurred_at: '2026-06-01T09:00:00.000Z',
      updated_at: '2026-06-01T09:25:00.000Z',
      metric_count: '1',
      metric_minutes: '25',
      payload: { processName: 'Code' },
    };
    const { service, query } = createHarness([[row, { ...row, server_id: 'activity-2' }]]);

    await expect(
      service.activityRecords(
        { start, end, limit: '2', offset: '5', processName: ' Code ', category: ' coding ', taskId: ' task-1 ' },
        context,
      ),
    ).resolves.toEqual({
      range: { start, end },
      limit: 2,
      offset: 5,
      hasMore: true,
      source: 'server-live-sync-objects',
      items: [
        {
          serverId: 'activity-1',
          objectType: 'activity_record',
          occurredAt: '2026-06-01T09:00:00.000Z',
          updatedAt: '2026-06-01T09:25:00.000Z',
          metricCount: 1,
          metricMinutes: 25,
          payload: { processName: 'Code' },
        },
        {
          serverId: 'activity-2',
          objectType: 'activity_record',
          occurredAt: '2026-06-01T09:00:00.000Z',
          updatedAt: '2026-06-01T09:25:00.000Z',
          metricCount: 1,
          metricMinutes: 25,
          payload: { processName: 'Code' },
        },
      ],
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('LIMIT $7 OFFSET $8'), [
      context.userId,
      start,
      end,
      'Code',
      'coding',
      'task-1',
      2,
      5,
    ]);
  });

  it('returns paged input events with default pagination and blank filters removed', async () => {
    const start = '2026-06-01T00:00:00.000Z';
    const end = '2026-06-08T00:00:00.000Z';
    const { service, query } = createHarness([
      [
        {
          server_id: 'input-1',
          object_type: 'tracked_input_event',
          occurred_at: new Date('2026-06-01T09:00:00.000Z'),
          updated_at: '2026-06-01T09:00:01.000Z',
          metric_count: '4',
          metric_minutes: '0',
          payload: { eventKind: 'key_down' },
        },
      ],
    ]);

    await expect(
      service.inputEvents(
        { start, end, limit: 'bad', offset: '-5', processName: ' ', category: ' ', eventKind: ' ' },
        context,
      ),
    ).resolves.toEqual({
      range: { start, end },
      limit: 100,
      offset: 0,
      hasMore: false,
      source: 'server-live-sync-objects',
      items: [
        {
          serverId: 'input-1',
          objectType: 'tracked_input_event',
          occurredAt: '2026-06-01T09:00:00.000Z',
          updatedAt: '2026-06-01T09:00:01.000Z',
          metricCount: 4,
          metricMinutes: 0,
          payload: { eventKind: 'key_down' },
        },
      ],
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('WITH input_events AS'), [
      context.userId,
      start,
      end,
      null,
      null,
      null,
      100,
      0,
    ]);
  });

  it('exports activity records as CSV with cleaned payload fields', async () => {
    const start = '2026-06-01T00:00:00.000Z';
    const end = '2026-06-08T00:00:00.000Z';
    const { service } = createHarness([
      [
        {
          server_id: 'activity-1',
          object_type: 'activity_record',
          occurred_at: '2026-06-01T09:00:00.000Z',
          updated_at: '2026-06-01T09:25:00.000Z',
          payload: { process_name: ' Code ', category: ' coding ', duration_minutes: '25' },
        },
      ],
    ]);

    await expect(service.exportCSV({ start, end }, context)).resolves.toEqual({
      format: 'csv',
      range: { start, end },
      headers: ['serverId', 'objectType', 'occurredAt', 'updatedAt', 'processName', 'category', 'durationMinutes'],
      rowCount: 1,
      data:
        'serverId,objectType,occurredAt,updatedAt,processName,category,durationMinutes\n' +
        'activity-1,activity_record,2026-06-01T09:00:00.000Z,2026-06-01T09:25:00.000Z,Code,coding,25',
    });
  });

  it('exports CSV rows with empty fallback fields when payload and timestamps are absent', async () => {
    const start = '2026-06-01T00:00:00.000Z';
    const end = '2026-06-08T00:00:00.000Z';
    const { service } = createHarness([
      [
        {
          server_id: 'activity-empty',
          object_type: 'activity_record',
          occurred_at: null,
          updated_at: null,
          payload: null,
        },
      ],
    ]);

    await expect(service.exportCSV({ start, end }, context)).resolves.toEqual({
      format: 'csv',
      range: { start, end },
      headers: ['serverId', 'objectType', 'occurredAt', 'updatedAt', 'processName', 'category', 'durationMinutes'],
      rowCount: 1,
      data:
        'serverId,objectType,occurredAt,updatedAt,processName,category,durationMinutes\n' +
        'activity-empty,activity_record,,,,,0',
    });
  });

  it('exports activity records as JSON and drops nullish payload fields', async () => {
    const start = '2026-06-01T00:00:00.000Z';
    const end = '2026-06-08T00:00:00.000Z';
    const { service } = createHarness([
      [
        {
          server_id: 'activity-1',
          object_type: 'activity_record',
          occurred_at: '2026-06-01T09:00:00.000Z',
          updated_at: '2026-06-01T09:25:00.000Z',
          payload: {
            processName: 'Code',
            category: null,
            durationMinutes: 0,
            hidden: undefined,
            active: false,
          },
        },
      ],
    ]);

    await expect(service.exportJSON({ start, end }, context)).resolves.toEqual({
      format: 'json',
      range: { start, end },
      rowCount: 1,
      items: [
        {
          serverId: 'activity-1',
          objectType: 'activity_record',
          occurredAt: '2026-06-01T09:00:00.000Z',
          updatedAt: '2026-06-01T09:25:00.000Z',
          processName: 'Code',
          durationMinutes: 0,
          active: false,
        },
      ],
    });
  });
});

describe('AnalyticsService validation and materialized-view helpers', () => {
  it('rejects invalid dates, inverted ranges, and unsupported buckets', async () => {
    const { service, query } = createHarness();

    await expect(service.activityDaySummary({ date: 'not-a-date' }, context)).rejects.toThrow(
      'date must be a valid ISO-8601 date',
    );
    await expect(
      service.activityHeatmap(
        { start: '2026-06-08T00:00:00.000Z', end: '2026-06-01T00:00:00.000Z' },
        context,
      ),
    ).rejects.toThrow('start must be earlier than end');
    await expect(
      service.activityHeatmap(
        { start: '2026-06-01T00:00:00.000Z', end: '2026-06-08T00:00:00.000Z', bucket: 'week' },
        context,
      ),
    ).rejects.toThrow(BadRequestException);
    expect(query).not.toHaveBeenCalled();
  });

  it('returns materialized activity summary buckets when the view has rows', async () => {
    const range = { start: '2026-06-01T00:00:00.000Z', end: '2026-06-08T00:00:00.000Z' };
    const { service, query } = createHarness([
      [{ bucket_start: '2026-06-01T00:00:00.000Z', record_count: '2', total_minutes: '45' }],
    ]);

    await expect(
      (service as unknown as {
        queryActivitySummary: (
          userId: string,
          range: typeof range,
          options: Record<string, unknown>,
        ) => Promise<unknown>;
      }).queryActivitySummary(context.userId, range, {
        bucket: 'month',
        processName: 'Code',
        category: 'coding',
        taskId: 'task-1',
      }),
    ).resolves.toEqual({
      source: 'materialized_view',
      buckets: [
        { bucketStart: '2026-06-01T00:00:00.000Z', recordCount: 2, totalMinutes: 45 },
      ],
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('FROM mv_activity_daily_summary'), [
      context.userId,
      range.start,
      range.end,
      'month',
      'Code',
      'coding',
      'task-1',
    ]);
  });

  it('falls activity summary back to live rows when the view is empty or unavailable', async () => {
    const range = { start: '2026-06-01T00:00:00.000Z', end: '2026-06-08T00:00:00.000Z' };
    const emptyView = createHarness([
      [],
      [{ bucket_start: '2026-06-02T00:00:00.000Z', record_count: '3', total_minutes: '30' }],
    ]);

    await expect(
      (emptyView.service as unknown as {
        queryActivitySummary: (userId: string, range: typeof range) => Promise<unknown>;
      }).queryActivitySummary(context.userId, range),
    ).resolves.toEqual({
      source: 'live_sync_objects',
      buckets: [{ bucketStart: '2026-06-02T00:00:00.000Z', recordCount: 3, totalMinutes: 30 }],
    });

    const failingView = createHarnessWithQuery(async (sql) => {
      if (String(sql).includes('FROM mv_activity_daily_summary')) {
        throw new Error('missing view');
      }
      return result([{ bucket_start: '2026-06-03T00:00:00.000Z', record_count: '4', total_minutes: '35' }]);
    });

    await expect(
      (failingView.service as unknown as {
        queryActivitySummary: (userId: string, range: typeof range) => Promise<unknown>;
      }).queryActivitySummary(context.userId, range),
    ).resolves.toMatchObject({
      source: 'live_sync_objects',
      buckets: [{ bucketStart: '2026-06-03T00:00:00.000Z', recordCount: 4, totalMinutes: 35 }],
    });
  });

  it('returns materialized input summary buckets when available', async () => {
    const range = { start: '2026-06-01T00:00:00.000Z', end: '2026-06-08T00:00:00.000Z' };
    const { service, query } = createHarness([
      [{ bucket_start: '2026-06-01T02:00:00.000Z', event_count: '12', total_minutes: '5' }],
    ]);

    await expect(
      (service as unknown as {
        queryInputSummary: (
          userId: string,
          range: typeof range,
          options: Record<string, unknown>,
        ) => Promise<unknown>;
      }).queryInputSummary(context.userId, range, {
        processName: 'Code',
        category: 'coding',
        eventKind: 'key_down',
      }),
    ).resolves.toEqual({
      source: 'materialized_view',
      buckets: [{ bucketStart: '2026-06-01T02:00:00.000Z', eventCount: 12, totalMinutes: 5 }],
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('FROM mv_input_hourly_summary'), [
      context.userId,
      range.start,
      range.end,
      'Code',
      'coding',
      'key_down',
    ]);
  });

  it('falls input summary back to live event buckets when the view query fails', async () => {
    const range = { start: '2026-06-01T00:00:00.000Z', end: '2026-06-08T00:00:00.000Z' };
    const { service, query } = createHarnessWithQuery(async (sql) => {
      if (String(sql).includes('FROM mv_input_hourly_summary')) {
        throw new Error('missing view');
      }
      return result([{ bucket_start: '2026-06-01T03:00:00.000Z', event_count: '9' }]);
    });

    await expect(
      (service as unknown as {
        queryInputSummary: (
          userId: string,
          range: typeof range,
          options: Record<string, unknown>,
        ) => Promise<unknown>;
      }).queryInputSummary(context.userId, range, { bucket: 'hour' }),
    ).resolves.toEqual({
      source: 'live_sync_objects',
      buckets: [{ bucketStart: '2026-06-01T03:00:00.000Z', eventCount: 9 }],
    });
    expect(callsContaining(query, 'FROM mv_input_hourly_summary')).toHaveLength(1);
    expect(callsContaining(query, 'WITH input_events AS')).toHaveLength(1);
    expect(query.mock.calls[1][1]).toEqual([
      context.userId,
      range.start,
      range.end,
      'hour',
      null,
      null,
      null,
    ]);
  });

  it('uses hour as the input summary fallback bucket when the view is empty', async () => {
    const range = { start: '2026-06-01T00:00:00.000Z', end: '2026-06-08T00:00:00.000Z' };
    const { service, query } = createHarness([
      [],
      [{ bucket_start: '2026-06-01T04:00:00.000Z', event_count: '5' }],
    ]);

    await expect(
      (service as unknown as {
        queryInputSummary: (userId: string, range: typeof range) => Promise<unknown>;
      }).queryInputSummary(context.userId, range),
    ).resolves.toEqual({
      source: 'live_sync_objects',
      buckets: [{ bucketStart: '2026-06-01T04:00:00.000Z', eventCount: 5 }],
    });
    expect(query.mock.calls[1][1]).toEqual([
      context.userId,
      range.start,
      range.end,
      'hour',
      null,
      null,
      null,
    ]);
  });
});
