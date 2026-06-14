import { BadRequestException } from '@nestjs/common';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { ActivityUnderstandingService } from './activity-understanding.service';

const context = {
  userId: '11111111-1111-4111-8111-111111111111',
  deviceId: '22222222-2222-4222-8222-222222222222',
};

type Row = Record<string, unknown>;

function result(rows: Row[] = []) {
  return { rows };
}

function normalizeSql(sql: string) {
  return sql.replace(/\s+/g, ' ');
}

function createHarness(options: {
  rawRows?: Row[];
  taskRows?: Row[];
  listRows?: Row[];
  segmentRows?: Row[];
  actualRows?: Row[];
  insertedFlags?: boolean[];
  ruleProfile?: Row;
} = {}) {
  let upsertedSegmentCount = 0;
  const query = vi.fn(async (sql: string, params?: unknown[]) => {
    const normalized = normalizeSql(sql);

    if (
      normalized.includes('FROM sync_objects') &&
      normalized.includes('LIMIT 5000')
    ) {
      return result(options.rawRows ?? []);
    }
    if (
      normalized.includes('FROM sync_objects') &&
      normalized.includes('LIMIT 500')
    ) {
      return result(options.taskRows ?? []);
    }
    if (
      normalized.includes('FROM activity_segments s') &&
      normalized.includes('LEFT JOIN activity_interpretations')
    ) {
      return result(options.listRows ?? []);
    }
    if (normalized.includes('SELECT * FROM activity_segments')) {
      return result(options.segmentRows ?? []);
    }
    if (
      normalized.includes('INSERT INTO activity_segments') &&
      normalized.includes('ON CONFLICT')
    ) {
      upsertedSegmentCount += 1;
      return result([
        {
          id: `segment-${upsertedSegmentCount}`,
          inserted: options.insertedFlags?.[upsertedSegmentCount - 1] ?? true,
        },
      ]);
    }
    if (
      normalized.includes('INSERT INTO activity_segments') &&
      normalized.includes('RETURNING id::text AS id')
    ) {
      const uid = String(params?.[1] ?? 'segment');
      if (uid.startsWith('split-a:')) return result([{ id: 'split-a-id' }]);
      if (uid.startsWith('split-b:')) return result([{ id: 'split-b-id' }]);
      if (uid.startsWith('merged:')) return result([{ id: 'merged-id' }]);
      return result([{ id: `inserted-${upsertedSegmentCount + 1}` }]);
    }
    if (normalized.includes('INSERT INTO actual_activity_logs')) {
      return result(options.actualRows ?? [{ id: 'actual-1' }]);
    }
    return result([]);
  });
  const database = {
    query,
    transaction: vi.fn(async (callback: (client: { query: typeof query }) => unknown) =>
      callback({ query }),
    ),
  };
  const devices = {
    ensureUser: vi.fn(async (userId: string) => userId),
    ensureDevice: vi.fn(async () => context.deviceId),
  };
  const models = {
    activeProfile: vi.fn(async () => ({
      versionKey: 'rule-v1',
      ruleProfile: options.ruleProfile ?? {},
    })),
    startRun: vi.fn(async () => ({ id: 'run-1' })),
    completeRun: vi.fn(async () => undefined),
    recordFeedback: vi.fn(async () => undefined),
  };
  const service = new ActivityUnderstandingService(
    database as never,
    devices as never,
    models as never,
  );
  return { service, database, devices, models, query };
}

function callsContaining(query: ReturnType<typeof vi.fn>, fragment: string) {
  return query.mock.calls.filter(([sql]) => String(sql).includes(fragment));
}

function paramsForFirst(query: ReturnType<typeof vi.fn>, fragment: string) {
  return callsContaining(query, fragment)[0]?.[1] as unknown[] | undefined;
}

function segmentRow(overrides: Row = {}) {
  return {
    id: 'segment-1',
    segment_uid: 'seg:2026-06-08:raw-1:raw-2',
    label: 'Focused coding',
    start_at: '2026-06-08T09:00:00.000Z',
    end_at: '2026-06-08T09:01:30.000Z',
    duration_seconds: 90,
    confidence: 0.82,
    primary_process_name: 'VS Code',
    primary_window_title: 'FlowPlan tests',
    primary_file_path: 'C:/dev/flowplan/src/app.ts',
    category: 'coding',
    source_record_ids: JSON.stringify(['raw-1', 'raw-2']),
    evidence: { apps: ['VS Code'] },
    ...overrides,
  };
}

function privateApi(service: ActivityUnderstandingService) {
  return service as unknown as {
    inferTitle(appName: string, windowTitle: string, filePath?: string): string;
    inferCategory(appName: string, windowTitle: string, filePath?: string): string;
    matchTask(
      segment: Row,
      tasks: Array<{ id: string; title: string; text: string }>,
      profile: Row,
    ): Row;
    segmentSummary(segment: Row): string;
    readRange(date: unknown, rawStart: unknown, rawEnd: unknown): { start: Date; end: Date };
    toRawActivity(row: Row): Record<string, unknown> | null;
    mergeActivities(raw: Record<string, unknown>[], profile: Record<string, unknown>): unknown[];
  };
}

afterEach(() => {
  vi.restoreAllMocks();
  vi.useRealTimers();
});

describe('ActivityUnderstandingService', () => {
  it('lists segments with normalized range, status, paging, and hasMore', async () => {
    const { service, query, devices } = createHarness({
      listRows: [
        { id: 'segment-1', status: 'confirmed' },
        { id: 'segment-2', status: 'confirmed' },
      ],
    });

    await expect(
      service.segments(
        {
          date: 'ignored-when-explicit-range-is-valid',
          start: '2026-06-08T09:00:00.000Z',
          end: '2026-06-08T10:00:00.000Z',
          status: ' confirmed ',
          limit: '2',
          offset: '5',
        },
        context,
      ),
    ).resolves.toEqual({
      range: {
        start: new Date('2026-06-08T09:00:00.000Z'),
        end: new Date('2026-06-08T10:00:00.000Z'),
      },
      limit: 2,
      offset: 5,
      hasMore: true,
      items: [
        { id: 'segment-1', status: 'confirmed' },
        { id: 'segment-2', status: 'confirmed' },
      ],
    });

    expect(devices.ensureUser).toHaveBeenCalledWith(context.userId);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('FROM activity_segments s'), [
      context.userId,
      new Date('2026-06-08T09:00:00.000Z'),
      new Date('2026-06-08T10:00:00.000Z'),
      'confirmed',
      2,
      5,
    ]);
  });

  it('builds, matches, persists, and audits activity segments', async () => {
    const { service, query, database, models } = createHarness({
      insertedFlags: [true, false],
      ruleProfile: {
        mergeGapMinutes: 5,
        taskMatchThreshold: 20,
      },
      rawRows: [
        {
          id: 'raw-code-1',
          objectType: 'raw_activity_log',
          updatedAt: '2026-06-08T09:01:00.000Z',
          payload: {
            startTime: '2026-06-08T09:00:00.000Z',
            endTime: '2026-06-08T09:40:00.000Z',
            appName: 'VS Code',
            windowTitle: 'FlowPlan sync tests',
            filePath: 'C:/dev/flowplan/src/ai.service.ts',
          },
        },
        {
          id: 'raw-code-2',
          objectType: 'activity_record',
          updatedAt: '2026-06-08T09:41:00.000Z',
          payload: {
            start_at: '2026-06-08T09:41:00.000Z',
            endedAt: '2026-06-08T10:00:00.000Z',
            processName: 'VS Code',
            title: 'FlowPlan sync tests',
            projectPath: 'C:/dev/flowplan/src/ai.service.ts',
          },
        },
        {
          id: 'raw-meeting-1',
          objectType: 'tracked_input_event',
          updatedAt: '2026-06-08T11:00:00.000Z',
          payload: {
            occurredAt: '2026-06-08T11:00:00.000Z',
            durationSeconds: 1800,
            application: 'Teams',
            summary: 'Sprint planning meeting',
          },
        },
      ],
      taskRows: [
        {
          id: 'task-row-1',
          uid: 'task-42',
          payload: {
            title: 'FlowPlan sync tests',
            description: 'Keep ai.service.ts and activity merge covered.',
          },
        },
      ],
    });

    await expect(
      service.buildSegments(
        {
          start: '2026-06-08T08:00:00.000Z',
          end: '2026-06-08T12:00:00.000Z',
          rebuild: true,
        },
        context,
      ),
    ).resolves.toMatchObject({
      range: {
        start: '2026-06-08T08:00:00.000Z',
        end: '2026-06-08T12:00:00.000Z',
      },
      modelRunId: 'run-1',
      modelUsed: 'rule_learned',
      modelVersion: 'rule-v1',
      rawCount: 3,
      segmentsCreated: 1,
      segmentsUpdated: 1,
      lowConfidenceCount: 0,
    });

    expect(database.transaction).toHaveBeenCalledOnce();
    expect(models.activeProfile).toHaveBeenCalledWith(context.userId, 'activity_merge.v1');
    expect(models.startRun).toHaveBeenCalledWith(
      context.userId,
      'activity_merge.v1',
      expect.objectContaining({
        source: 'activity.buildSegments',
        inputSummary: expect.objectContaining({ rebuild: true }),
      }),
    );
    expect(callsContaining(query, 'DELETE FROM activity_segments')).toHaveLength(1);

    const segmentInserts = callsContaining(query, 'INSERT INTO activity_segments');
    expect(segmentInserts.filter(([sql]) => String(sql).includes('ON CONFLICT'))).toHaveLength(2);
    const firstSegmentParams = segmentInserts[0][1] as unknown[];
    const secondSegmentParams = segmentInserts[1][1] as unknown[];
    expect(firstSegmentParams).toEqual(
      expect.arrayContaining([
        context.userId,
        'VS Code',
        'coding',
        expect.stringContaining('FlowPlan sync tests'),
        'task-42',
      ]),
    );
    expect(firstSegmentParams[10]).toBe(JSON.stringify(['raw-code-1', 'raw-code-2']));
    expect(JSON.parse(String(firstSegmentParams[11]))).toMatchObject({
      matchedTask: {
        id: 'task-42',
        title: 'FlowPlan sync tests',
      },
    });
    expect(secondSegmentParams).toEqual(
      expect.arrayContaining([
        context.userId,
        'Teams',
        'meeting',
        expect.stringContaining('Sprint planning meeting'),
      ]),
    );
    expect(callsContaining(query, 'INSERT INTO activity_interpretations')).toHaveLength(2);
    expect(callsContaining(query, 'INSERT INTO activity_segment_evidence')).toHaveLength(2);
    expect(callsContaining(query, 'INSERT INTO audit_logs')).toHaveLength(1);
    expect(paramsForFirst(query, 'INSERT INTO audit_logs')).toEqual(
      expect.arrayContaining([context.userId, context.deviceId, 'activity.build_segments']),
    );
    expect(models.completeRun).toHaveBeenCalledWith(
      context.userId,
      'run-1',
      expect.objectContaining({
        status: 'succeeded',
        outputSummary: expect.objectContaining({ rawCount: 3, segmentCount: 2 }),
        confidence: expect.any(Number),
        usedLlm: false,
      }),
    );
  });

  it('casts raw activity range bounds before applying interval padding', async () => {
    const { service, query } = createHarness({
      rawRows: [],
      taskRows: [],
    });

    await service.buildSegments(
      {
        start: '2026-06-08T08:00:00.000Z',
        end: '2026-06-08T12:00:00.000Z',
      },
      context,
    );

    const rawQuery = callsContaining(query, 'LIMIT 5000')[0];
    const rawSql = normalizeSql(String(rawQuery?.[0]));
    expect(rawSql).toContain("updated_at >= $3::timestamptz - interval '1 day'");
    expect(rawSql).toContain("updated_at < $4::timestamptz + interval '1 day'");
    expect(rawQuery?.[1]).toEqual(
      expect.arrayContaining([
        context.userId,
        expect.any(Array),
        new Date('2026-06-08T08:00:00.000Z'),
        new Date('2026-06-08T12:00:00.000Z'),
      ]),
    );
  });

  it('chooses the dominant app and file path when merged raw activities disagree', async () => {
    const { service, query } = createHarness({
      rawRows: [
        {
          id: 'raw-main-a',
          updatedAt: '2026-06-08T09:00:00.000Z',
          payload: {
            startTime: '2026-06-08T09:00:00.000Z',
            endTime: '2026-06-08T09:10:00.000Z',
            appName: 'VS Code',
            windowTitle: 'Editor',
            filePath: 'C:/dev/flowplan/src/app.ts',
          },
        },
        {
          id: 'raw-main-b',
          updatedAt: '2026-06-08T09:11:00.000Z',
          payload: {
            startTime: '2026-06-08T09:11:00.000Z',
            endTime: '2026-06-08T09:20:00.000Z',
            appName: 'VS Code',
            windowTitle: 'Editor',
            filePath: 'C:/dev/flowplan/src/helper.ts',
          },
        },
        {
          id: 'raw-helper',
          updatedAt: '2026-06-08T09:21:00.000Z',
          payload: {
            startTime: '2026-06-08T09:21:00.000Z',
            endTime: '2026-06-08T09:30:00.000Z',
            appName: 'Code Helper',
            windowTitle: 'Indexer',
            filePath: 'C:/dev/flowplan/src/helper.ts',
          },
        },
      ],
      taskRows: [],
    });

    await expect(
      service.buildSegments(
        {
          start: '2026-06-08T08:00:00.000Z',
          end: '2026-06-08T10:00:00.000Z',
        },
        context,
      ),
    ).resolves.toMatchObject({
      rawCount: 3,
      segmentsCreated: 1,
      segmentsUpdated: 0,
    });

    const insertParams = paramsForFirst(query, 'INSERT INTO activity_segments');
    expect(insertParams).toEqual(
      expect.arrayContaining([
        context.userId,
        'VS Code',
        'coding',
        expect.stringContaining('helper.ts'),
      ]),
    );
    expect(insertParams?.[10]).toBe(JSON.stringify(['raw-main-a', 'raw-main-b', 'raw-helper']));
    expect(JSON.parse(String(insertParams?.[11]))).toMatchObject({
      apps: ['VS Code', 'Code Helper'],
      primaryFilePath: 'C:/dev/flowplan/src/helper.ts',
      filePaths: [
        'C:/dev/flowplan/src/app.ts',
        'C:/dev/flowplan/src/helper.ts',
        'C:/dev/flowplan/src/helper.ts',
      ],
    });
  });

  it('handles empty build output, task title fallbacks, and zero model confidence', async () => {
    const { service, query, models } = createHarness({
      rawRows: [],
      taskRows: [
        {
          id: 'task-row-fallback',
          payload: {},
        },
      ],
    });

    await expect(
      service.buildSegments(
        {
          start: '2026-06-08T08:00:00.000Z',
          end: '2026-06-08T09:00:00.000Z',
        },
        context,
      ),
    ).resolves.toMatchObject({
      rawCount: 0,
      segmentsCreated: 0,
      segmentsUpdated: 0,
      lowConfidenceCount: 0,
    });

    expect(callsContaining(query, 'INSERT INTO activity_segments')).toHaveLength(0);
    expect(models.completeRun).toHaveBeenCalledWith(
      context.userId,
      'run-1',
      expect.objectContaining({
        confidence: 0,
        outputSummary: expect.objectContaining({
          rawCount: 0,
          segmentCount: 0,
          lowConfidenceCount: 0,
        }),
      }),
    );
  });

  it('persists segments with empty source evidence when merge output has no source ids', async () => {
    const { service, query } = createHarness({ rawRows: [], taskRows: [] });
    const api = privateApi(service);
    vi.spyOn(api, 'mergeActivities').mockReturnValue([
      {
        uid: 'seg:manual-empty-source',
        startAt: new Date('2026-06-08T08:00:00.000Z'),
        endAt: new Date('2026-06-08T08:30:00.000Z'),
        appName: 'ManualApp',
        windowTitle: '',
        title: 'ManualApp activity',
        confidence: 0.42,
        category: 'unknown',
        sourceIds: [],
        evidence: {},
      },
    ]);

    await expect(
      service.buildSegments(
        {
          start: '2026-06-08T08:00:00.000Z',
          end: '2026-06-08T09:00:00.000Z',
        },
        context,
      ),
    ).resolves.toMatchObject({
      rawCount: 0,
      segmentsCreated: 1,
      lowConfidenceCount: 1,
    });

    const evidenceParams = paramsForFirst(query, 'INSERT INTO activity_segment_evidence');
    expect(evidenceParams?.[2]).toBeNull();
    expect(evidenceParams?.[4]).toBe(42);
  });

  it('infers common activity categories through persisted segment payloads', async () => {
    const { service, query } = createHarness({
      rawRows: [
        {
          id: 'raw-writing',
          updatedAt: '2026-06-08T08:00:00.000Z',
          payload: {
            timestamp: '2026-06-08T08:00:00.000Z',
            durationSeconds: 600,
            appName: 'Word',
            windowTitle: 'Quarterly plan',
            filePath: 'C:/docs/plan.docx',
          },
        },
        {
          id: 'raw-communication',
          updatedAt: '2026-06-08T09:00:00.000Z',
          payload: {
            timestamp: '2026-06-08T09:00:00.000Z',
            durationSeconds: 600,
            packageName: 'Outlook',
            window_title: 'Client mail',
          },
        },
        {
          id: 'raw-design',
          updatedAt: '2026-06-08T10:00:00.000Z',
          payload: {
            timestamp: '2026-06-08T10:00:00.000Z',
            durationSeconds: 600,
            appName: 'Figma',
            windowTitle: 'Prototype',
            path: 'C:/design/app.fig',
          },
        },
        {
          id: 'raw-entertainment',
          updatedAt: '2026-06-08T11:00:00.000Z',
          payload: {
            timestamp: '2026-06-08T11:00:00.000Z',
            durationSeconds: 600,
            appName: 'YouTube',
            windowTitle: 'Video review',
          },
        },
        {
          id: 'raw-browsing',
          updatedAt: '2026-06-08T12:00:00.000Z',
          payload: {
            timestamp: '2026-06-08T12:00:00.000Z',
            durationSeconds: 600,
            process_name: 'Chrome',
            title: 'Research',
          },
        },
        {
          id: 'raw-unknown',
          updatedAt: '2026-06-08T13:00:00.000Z',
          payload: {
            timestamp: '2026-06-08T13:00:00.000Z',
            durationSeconds: 600,
          },
        },
      ],
      taskRows: [],
    });

    await service.buildSegments({ date: '2026-06-08' }, context);

    const categories = callsContaining(query, 'INSERT INTO activity_segments')
      .filter(([sql]) => String(sql).includes('ON CONFLICT'))
      .map(([, params]) => (params as unknown[])[8]);
    expect(categories).toEqual([
      'writing',
      'communication',
      'design',
      'entertainment',
      'browsing',
      'unknown',
    ]);
  });

  it('confirms a segment with task work, actual log, audit, and feedback', async () => {
    const { service, query, models } = createHarness({
      segmentRows: [segmentRow()],
      actualRows: [{ id: 'actual-1' }],
    });

    await expect(
      service.confirmSegment(
        'segment-1',
        { title: 'Reviewed coding', taskId: ' task-42 ', notes: ' useful ' },
        context,
      ),
    ).resolves.toEqual({ ok: true, actualId: 'actual-1', taskId: 'task-42' });

    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO actual_activity_logs'),
      [
        context.userId,
        'actual:seg:2026-06-08:raw-1:raw-2',
        'Reviewed coding',
        '2026-06-08T09:00:00.000Z',
        '2026-06-08T09:01:30.000Z',
        90,
        'segment-1',
        JSON.stringify({ segmentId: 'segment-1', userConfirmed: true }),
        0.82,
        'useful',
      ],
    );
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO task_work_logs'),
      [
        context.userId,
        'work:seg:2026-06-08:raw-1:raw-2:task-42',
        'task-42',
        'segment-1',
        'actual-1',
        '2026-06-08T09:00:00.000Z',
        '2026-06-08T09:01:30.000Z',
        2,
        90,
        0.82,
        JSON.stringify({ segmentId: 'segment-1', title: 'Reviewed coding' }),
      ],
    );
    expect(paramsForFirst(query, 'UPDATE activity_segments')).toEqual([
      context.userId,
      'segment-1',
      'Reviewed coding',
      'task-42',
    ]);
    expect(models.recordFeedback).toHaveBeenCalledWith(
      { query },
      context.userId,
      context.deviceId,
      'activity_merge.v1',
      expect.objectContaining({
        targetId: 'segment-1',
        feedbackType: 'accepted_with_task',
        outcome: 'accepted',
      }),
    );
  });

  it('confirms a segment without task work and rejects missing segments', async () => {
    const { service, query, models } = createHarness({
      segmentRows: [segmentRow({ label: 'Existing title', confidence: null })],
      actualRows: [{ id: 'actual-2' }],
    });

    await expect(service.confirmSegment('segment-1', {}, context)).resolves.toMatchObject({
      ok: true,
      actualId: 'actual-2',
    });

    expect(callsContaining(query, 'INSERT INTO task_work_logs')).toHaveLength(0);
    expect(paramsForFirst(query, 'INSERT INTO actual_activity_logs')).toEqual(
      expect.arrayContaining(['Existing title', 0.5]),
    );
    expect(models.recordFeedback).toHaveBeenCalledWith(
      { query },
      context.userId,
      context.deviceId,
      'activity_merge.v1',
      expect.objectContaining({ feedbackType: 'accepted' }),
    );

    const missing = createHarness({ segmentRows: [] });
    await expect(missing.service.confirmSegment('missing', {}, context)).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('uses default title, duration, and confidence when confirming sparse segment rows with a task', async () => {
    const { service, query, models } = createHarness({
      segmentRows: [
        segmentRow({
          label: undefined,
          duration_seconds: undefined,
          confidence: undefined,
        }),
      ],
      actualRows: [{ id: 'actual-sparse' }],
    });

    await expect(
      service.confirmSegment('segment-1', { taskId: ' task-sparse ' }, context),
    ).resolves.toEqual({ ok: true, actualId: 'actual-sparse', taskId: 'task-sparse' });

    const actualParams = paramsForFirst(query, 'INSERT INTO actual_activity_logs');
    expect(actualParams?.[2]).toEqual(expect.any(String));
    expect(actualParams?.[5]).toBe(0);
    expect(actualParams?.[8]).toBe(0.5);

    const workParams = paramsForFirst(query, 'INSERT INTO task_work_logs');
    expect(workParams).toEqual(
      expect.arrayContaining([
        'work:seg:2026-06-08:raw-1:raw-2:task-sparse',
        'task-sparse',
        1,
        0,
        0.5,
      ]),
    );
    expect(models.recordFeedback).toHaveBeenCalledWith(
      { query },
      context.userId,
      context.deviceId,
      'activity_merge.v1',
      expect.objectContaining({
        feedbackType: 'accepted_with_task',
        feedbackPayload: expect.objectContaining({ confidence: 0.5 }),
      }),
    );
  });

  it('rejects segments and records model feedback', async () => {
    const { service, query, models } = createHarness();

    await expect(service.rejectSegment('segment-1', { reason: ' noisy ' }, context)).resolves.toEqual({
      ok: true,
    });

    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'rejected', evidence = evidence || $3::jsonb"),
      [context.userId, 'segment-1', JSON.stringify({ rejectReason: 'noisy' })],
    );
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'rejected'"),
      [context.userId, 'segment-1'],
    );
    expect(models.recordFeedback).toHaveBeenCalledWith(
      { query },
      context.userId,
      context.deviceId,
      'activity_merge.v1',
      expect.objectContaining({
        targetId: 'segment-1',
        feedbackType: 'rejected',
        outcome: 'rejected',
        feedbackPayload: { reason: 'noisy' },
      }),
    );
    expect(paramsForFirst(query, 'INSERT INTO audit_logs')).toEqual(
      expect.arrayContaining([context.userId, context.deviceId, 'activity.reject_segment']),
    );
  });

  it('stores explicit and default segment feedback payloads', async () => {
    const { service, query, models } = createHarness();

    await expect(
      service.feedback(
        'segment-1',
        {
          feedbackType: ' corrected ',
          outcome: ' improved ',
          feedbackPayload: { title: 'Better title' },
        },
        context,
      ),
    ).resolves.toEqual({ ok: true });

    expect(models.recordFeedback).toHaveBeenLastCalledWith(
      { query },
      context.userId,
      context.deviceId,
      'activity_merge.v1',
      expect.objectContaining({
        feedbackType: 'corrected',
        outcome: 'improved',
        feedbackPayload: { title: 'Better title' },
      }),
    );

    await expect(service.feedback('segment-2', { payload: { note: 'manual' } }, context)).resolves.toEqual({
      ok: true,
    });

    expect(models.recordFeedback).toHaveBeenLastCalledWith(
      { query },
      context.userId,
      context.deviceId,
      'activity_merge.v1',
      expect.objectContaining({
        targetId: 'segment-2',
        feedbackType: 'modified',
        outcome: 'modified',
        feedbackPayload: { note: 'manual' },
      }),
    );
  });

  it('validates split input and segment boundaries before writing split halves', async () => {
    const invalid = createHarness({ segmentRows: [segmentRow()] });

    await expect(
      invalid.service.splitSegment('segment-1', { splitAt: 'not-a-date' }, context),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(invalid.database.transaction).not.toHaveBeenCalled();

    const missing = createHarness({ segmentRows: [] });
    await expect(
      missing.service.splitSegment('missing', { splitAt: '2026-06-08T09:00:30.000Z' }, context),
    ).rejects.toBeInstanceOf(BadRequestException);

    const outside = createHarness({ segmentRows: [segmentRow()] });
    await expect(
      outside.service.splitSegment('segment-1', { splitAt: '2026-06-08T10:00:00.000Z' }, context),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('splits a segment into two candidate halves and writes audit metadata', async () => {
    const { service, query } = createHarness({ segmentRows: [segmentRow()] });

    await expect(
      service.splitSegment('segment-1', { splitAt: '2026-06-08T09:00:30.000Z' }, context),
    ).resolves.toEqual({ ok: true, firstHalfId: 'split-a-id', secondHalfId: 'split-b-id' });

    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'split'"),
      [context.userId, 'segment-1'],
    );
    const splitInserts = callsContaining(query, 'INSERT INTO activity_segments');
    expect(splitInserts.map(([, params]) => (params as unknown[])[1])).toEqual([
      'split-a:seg:2026-06-08:raw-1:raw-2',
      'split-b:seg:2026-06-08:raw-1:raw-2',
    ]);
    expect(splitInserts.map(([, params]) => (params as unknown[])[4])).toEqual([30, 60]);
    expect(paramsForFirst(query, 'INSERT INTO audit_logs')).toEqual(
      expect.arrayContaining([context.userId, context.deviceId, 'activity.split_segment']),
    );
  });

  it('validates merge inputs before creating a merged candidate', async () => {
    const tooFew = createHarness();
    await expect(tooFew.service.mergeSegments({ segmentIds: ['segment-1'] }, context)).rejects.toBeInstanceOf(
      BadRequestException,
    );
    expect(tooFew.database.transaction).not.toHaveBeenCalled();

    const missing = createHarness({ segmentRows: [segmentRow()] });
    await expect(
      missing.service.mergeSegments({ segmentIds: ['segment-1', 'segment-2'] }, context),
    ).rejects.toBeInstanceOf(BadRequestException);
  });

  it('merges valid segments, marks originals, and audits the manual merge', async () => {
    const { service, query } = createHarness({
      segmentRows: [
        segmentRow({ id: 'segment-1', segment_uid: 'seg-a', confidence: 0.91 }),
        segmentRow({
          id: 'segment-2',
          segment_uid: 'seg-b',
          start_at: '2026-06-08T09:02:00.000Z',
          end_at: '2026-06-08T09:05:00.000Z',
          confidence: 0.67,
          primary_process_name: 'Chrome',
        }),
      ],
    });

    await expect(
      service.mergeSegments({ segmentIds: ['segment-1', 'segment-2'] }, context),
    ).resolves.toEqual({ ok: true, mergedId: 'merged-id' });

    const mergeParams = paramsForFirst(query, 'INSERT INTO activity_segments');
    expect(mergeParams).toEqual(
      expect.arrayContaining([
        context.userId,
        'merged:seg-a:seg-b',
        300,
        'VS Code',
        'merged',
        JSON.stringify(['segment-1', 'segment-2']),
        JSON.stringify({ mergedFrom: ['segment-1', 'segment-2'], mergeRule: 'manual' }),
        0.67,
      ]),
    );
    expect(callsContaining(query, "SET status = 'merged'")).toHaveLength(2);
    expect(paramsForFirst(query, 'INSERT INTO audit_logs')).toEqual(
      expect.arrayContaining([context.userId, context.deviceId, 'activity.merge_segments']),
    );
  });

  it('uses merge fallbacks for missing app names and confidence values', async () => {
    const { service, query } = createHarness({
      segmentRows: [
        segmentRow({
          id: 'segment-1',
          segment_uid: 'seg-a',
          primary_process_name: undefined,
          confidence: null,
        }),
        segmentRow({
          id: 'segment-2',
          segment_uid: 'seg-b',
          start_at: '2026-06-08T09:02:00.000Z',
          end_at: '2026-06-08T09:05:00.000Z',
          primary_process_name: undefined,
          confidence: undefined,
        }),
      ],
    });

    await expect(
      service.mergeSegments({ segmentIds: ['segment-1', 'segment-2'] }, context),
    ).resolves.toEqual({ ok: true, mergedId: 'merged-id' });

    const mergeParams = paramsForFirst(query, 'INSERT INTO activity_segments');
    expect(mergeParams?.[5]).toBe('unknown');
    expect(mergeParams?.[10]).toBe(0.5);
  });

  it('infers titles, categories, and raw activity fallbacks for sparse tracker rows', () => {
    const { service } = createHarness();
    const api = privateApi(service);

    expect(api.inferTitle('VS Code', 'Editor', 'C:/dev/flowplan/src/app.ts')).toBe(
      'VS Code: app.ts - Editor',
    );
    expect(api.inferTitle('VS Code', '', 'C:/dev/flowplan/src/app.ts')).toBe('VS Code: app.ts');
    expect(api.inferTitle('VS Code', 'Workspace', 'C:/dev/flowplan/src/')).toBe(
      'VS Code: Workspace',
    );
    expect(api.inferTitle('Terminal', 'Build output')).toBe('Terminal: Build output');
    expect(api.inferTitle('unknown', '')).toEqual(expect.any(String));
    expect(api.inferTitle('Slack', '')).toEqual(expect.stringContaining('Slack'));
    expect(api.inferCategory('App', '', '/home/me/projects/app/README.md')).toBe('coding');
    expect(api.inferCategory('Terminal', 'Build output')).toBe('coding');
    expect(api.inferCategory('PlainApp', '', 'C:/src/app.go')).toBe('coding');
    expect(api.inferCategory('Typora', 'Draft')).toBe('writing');
    expect(api.inferCategory('Photoshop', '', 'C:/design/mockup.psd')).toBe('design');
    expect(api.inferCategory('Chrome', 'Product docs')).toBe('browsing');
    expect(api.inferCategory('PlainApp', '', 'C:/dev/project/src/main.ts')).toBe('coding');
    expect(api.inferCategory('PlainApp', '', 'C:/docs/notes.md')).toBe('writing');
    expect(api.inferCategory('PlainApp', '', 'C:/design/logo.svg')).toBe('design');
    expect(api.inferCategory('Browser', 'VS Code dev docs')).toBe('coding');
    expect(api.mergeActivities([], {})).toEqual([]);
    expect(api.toRawActivity({ id: 'raw-missing', objectType: 'activity_record', payload: {} })).toBeNull();
    expect(
      api.toRawActivity({
        id: 'raw-fallback',
        objectType: 'activity_record',
        updatedAt: '2026-06-08T09:00:00.000Z',
        payload: { appName: 'Editor', durationSeconds: 30 },
      }),
    ).toMatchObject({
      id: 'raw-fallback',
      appName: 'Editor',
      windowTitle: '',
      filePath: undefined,
    });
    expect(
      api.toRawActivity({
        id: 'raw-default-duration',
        objectType: 'activity_record',
        updatedAt: '2026-06-08T10:00:00.000Z',
        payload: { process_name: 'Editor', summary: 'Daily notes' },
      }),
    ).toMatchObject({
      id: 'raw-default-duration',
      startAt: new Date('2026-06-08T10:00:00.000Z'),
      endAt: new Date('2026-06-08T10:05:00.000Z'),
    });
  });

  it('covers merge and matching fallbacks that are hard to reach through raw ingestion', () => {
    const { service } = createHarness();
    const api = privateApi(service);

    expect(
      api.mergeActivities(
        [
          {
            id: 'raw-unknown-app',
            startAt: new Date('2026-06-08T09:00:00.000Z'),
            endAt: new Date('2026-06-08T09:05:00.000Z'),
            appName: undefined,
            windowTitle: 'Untitled',
          },
        ],
        {},
      ),
    ).toEqual([
      expect.objectContaining({
        appName: 'unknown',
        title: expect.any(String),
        category: 'unknown',
      }),
    ]);

    expect(
      api.mergeActivities(
        [
          {
            id: 'raw-a',
            startAt: new Date('2026-06-08T09:00:00.000Z'),
            endAt: new Date('2026-06-08T09:05:00.000Z'),
            appName: 'VS Code',
            windowTitle: 'One',
            filePath: 'C:/repo/src/a.ts',
          },
          {
            id: 'raw-b',
            startAt: new Date('2026-06-08T09:06:00.000Z'),
            endAt: new Date('2026-06-08T09:10:00.000Z'),
            appName: 'VS Code',
            windowTitle: 'Two',
            filePath: 'C:/repo/src/b.ts',
          },
        ],
        { mergeGapMinutes: 0, filePathChangeGap: 5 },
      ),
    ).toHaveLength(1);

    expect(
      api.mergeActivities(
        [
          {
            id: 'raw-window-1',
            startAt: new Date('2026-06-08T10:00:00.000Z'),
            endAt: new Date('2026-06-08T10:05:00.000Z'),
            appName: 'Editor',
            windowTitle: 'One',
          },
          {
            id: 'raw-window-2',
            startAt: new Date('2026-06-08T10:06:00.000Z'),
            endAt: new Date('2026-06-08T10:10:00.000Z'),
            appName: 'Editor',
            windowTitle: 'Two',
          },
          {
            id: 'raw-window-3',
            startAt: new Date('2026-06-08T10:11:00.000Z'),
            endAt: new Date('2026-06-08T10:15:00.000Z'),
            appName: 'Editor',
            windowTitle: 'Three',
          },
        ],
        {},
      ),
    ).toEqual([
      expect.objectContaining({
        evidence: expect.objectContaining({ uniqueWindowCount: 3 }),
      }),
    ]);

    const matched = api.matchTask(
      {
        title: 'Investigate service branches',
        windowTitle: 'Coverage report',
        confidence: 0.4,
        evidence: {},
      },
      [
        { id: 'task-notes', title: 'Coverage report', text: '{"notes":"branch report"}' },
        { id: 'task-other', title: 'Release plan', text: 'not json' },
        { id: 'task-empty-json', title: 'Empty metadata', text: '{}' },
      ],
      { taskMatchThreshold: 1 },
    );
    expect(matched).toMatchObject({
      matchedTaskId: 'task-notes',
      matchedTaskTitle: 'Coverage report',
      evidence: expect.objectContaining({
        matchedTask: expect.objectContaining({ id: 'task-notes' }),
      }),
    });

    expect(
      api.segmentSummary({
        title: 'Short segment',
        appName: 'Timer',
        startAt: new Date('2026-06-08T11:00:00.000Z'),
        endAt: new Date('2026-06-08T11:00:05.000Z'),
      }),
    ).toEqual(expect.stringContaining('1'));

    const pathMatched = api.matchTask(
      {
        title: 'Path based work',
        windowTitle: 'Editor',
        filePath: 'C:/Repo/src/file.ts',
        confidence: 0.4,
        evidence: {},
      },
      [
        {
          id: 'task-path',
          title: 'Path task',
          text: 'notes mention c:/repo/src/file.ts for matching',
        },
      ],
      { taskMatchThreshold: 1 },
    );
    expect(pathMatched).toMatchObject({ matchedTaskId: 'task-path' });

    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-09T12:00:00.000Z'));
    expect(api.readRange(undefined, undefined, undefined)).toEqual({
      start: new Date('2026-06-09T00:00:00.000Z'),
      end: new Date('2026-06-10T00:00:00.000Z'),
    });
  });
});
