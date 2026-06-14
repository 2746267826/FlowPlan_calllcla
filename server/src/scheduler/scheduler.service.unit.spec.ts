import { BadRequestException } from '@nestjs/common';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { SchedulerService } from './scheduler.service';

const context = {
  userId: 'context-user',
  deviceId: 'context-device',
};
const userId = 'user-1';
const deviceId = 'device-1';

type Rows = Array<Record<string, unknown>>;

interface ServiceOptions {
  settingsRows?: Rows;
  taskRows?: Rows;
  workRows?: Rows;
  eventRows?: Rows;
  runRows?: Rows;
  runItemRows?: Rows;
  transactionRunRows?: Rows;
  transactionItemRows?: Rows;
  syncObjectRows?: Rows;
  deviationInsertRows?: Rows[];
  activeProfile?: Record<string, unknown>;
  scheduleFallback?: Record<string, unknown>;
}

function rows(rowsValue: Rows = []) {
  return { rows: rowsValue };
}

function runRow(overrides: Record<string, unknown> = {}) {
  return {
    id: 'run-1',
    rangeStart: new Date('2026-06-08T09:00:00.000Z'),
    rangeEnd: new Date('2026-06-08T12:00:00.000Z'),
    mode: 'initial_plan',
    strategy: 'balanced',
    status: 'draft',
    inputSnapshot: {},
    outputSummary: { unplanned: [] },
    riskSummary: {
      modelRunId: 'model-run-1',
      modelUsed: 'rule_learned',
      modelVersion: 'scheduler-v1',
      llmFallback: { used: false },
    },
    createdAt: new Date('2026-06-08T08:00:00.000Z'),
    updatedAt: new Date('2026-06-08T08:00:00.000Z'),
    confirmedAt: null,
    rejectedAt: null,
    ...overrides,
  };
}

function draftRow(overrides: Record<string, unknown> = {}) {
  return {
    id: 'draft-1',
    taskId: 'task-1',
    taskTitle: 'Focus task',
    proposedStart: new Date('2026-06-08T09:00:00.000Z'),
    proposedEnd: new Date('2026-06-08T10:00:00.000Z'),
    action: 'create',
    confidence: 0.78,
    reason: {},
    risk: {},
    status: 'pending',
    rejectReason: null,
    ...overrides,
  };
}

function createService(options: ServiceOptions = {}) {
  let syncObjectIndex = 0;
  let deviationIndex = 0;
  const transactionClient = {
    query: vi.fn(async (sql: string, params?: unknown[]) => {
      const text = String(sql);
      if (text.includes('INSERT INTO schedule_runs')) return rows([{ id: 'run-1' }]);
      if (text.includes('SELECT * FROM schedule_runs')) {
        return rows(options.transactionRunRows ?? [{ risk_summary_json: { modelRunId: 'model-run-1' } }]);
      }
      if (text.includes('SELECT * FROM schedule_draft_items')) {
        return rows(options.transactionItemRows ?? []);
      }
      if (text.includes('INSERT INTO sync_objects')) {
        const fallback = { id: `object-${syncObjectIndex + 1}`, server_version: syncObjectIndex + 1 };
        const row = options.syncObjectRows?.[syncObjectIndex] ?? fallback;
        syncObjectIndex += 1;
        return rows([row]);
      }
      if (text.includes('INSERT INTO plan_deviations')) {
        const insertedRows = options.deviationInsertRows?.[deviationIndex] ?? [{ id: `deviation-${deviationIndex + 1}` }];
        deviationIndex += 1;
        return rows(insertedRows);
      }
      if (
        text.includes('INSERT INTO schedule_draft_items') ||
        text.includes('INSERT INTO sync_changes') ||
        text.includes('INSERT INTO audit_logs') ||
        text.includes('UPDATE schedule_draft_items') ||
        text.includes('UPDATE schedule_runs')
      ) {
        return rows([]);
      }
      throw new Error(`Unexpected transaction query: ${text.slice(0, 120)} ${JSON.stringify(params)}`);
    }),
  };

  const database = {
    query: vi.fn(async (sql: string, params?: unknown[]) => {
      const text = String(sql);
      if (text.includes('FROM admin_remote_configs')) return rows(options.settingsRows ?? []);
      if (text.includes('FROM task_work_logs')) return rows(options.workRows ?? []);
      if (text.includes("object_type = 'task_schedule_segment'")) return rows(options.runRows ?? []);
      if (text.includes('FROM actual_activity_logs')) return rows(options.runItemRows ?? []);
      if (text.includes('LIMIT 500')) return rows(options.taskRows ?? []);
      if (text.includes('LIMIT 1000')) return rows(options.eventRows ?? []);
      if (text.includes('FROM schedule_runs')) return rows(options.runRows ?? []);
      if (text.includes('FROM schedule_draft_items')) return rows(options.runItemRows ?? []);
      throw new Error(`Unexpected database query: ${text.slice(0, 120)} ${JSON.stringify(params)}`);
    }),
    transaction: vi.fn(async (callback: (client: typeof transactionClient) => Promise<unknown>) =>
      callback(transactionClient),
    ),
  };
  const devices = {
    ensureUser: vi.fn(async () => userId),
    ensureDevice: vi.fn(async () => deviceId),
  };
  const models = {
    activeProfile: vi.fn(async () => options.activeProfile ?? { ruleProfile: {} }),
    startRun: vi.fn(async () => ({
      id: 'model-run-1',
      version: { versionKey: 'scheduler-v1' },
    })),
    completeRun: vi.fn(async () => undefined),
    scheduleFallback: vi.fn(async () => options.scheduleFallback ?? { used: false, draftItems: [] }),
    recordFeedback: vi.fn(async () => undefined),
  };
  const service = new SchedulerService(database as never, devices as never, models as never);
  return { service, database, transactionClient, devices, models };
}

function taskCandidate(overrides: Record<string, unknown> = {}) {
  return {
    id: 'task-1',
    objectId: 'object-1',
    title: 'Task',
    estimatedMinutes: 60,
    confirmedMinutes: 0,
    remainingMinutes: 60,
    dueAt: undefined,
    priority: 'normal',
    location: null,
    notes: null,
    locked: false,
    allowAutoSchedule: true,
    earliestStart: undefined,
    latestEnd: undefined,
    canSplit: true,
    minChunkMinutes: 15,
    maxChunkMinutes: 120,
    payload: {},
    status: 'open',
    ...overrides,
  };
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2026-06-08T08:00:00.000Z'));
});

describe('SchedulerService public API', () => {
  it('creates a rule-based draft run from tasks, busy blocks and confirmed work', async () => {
    const { service, database, transactionClient, devices, models } = createService({
      taskRows: [
        {
          id: 'task-object-1',
          uid: 'task-1',
          payload: {
            title: 'Focus task',
            estimatedMinutes: 90,
            priority: 'high',
            dueAt: '2026-06-09T09:00:00.000Z',
            location: 'Desk',
            notes: 'Deep work',
            minChunkMinutes: 30,
            maxChunkMinutes: 120,
          },
        },
        {
          id: 'task-object-2',
          uid: 'task-done',
          payload: { title: 'Completed task', status: 'completed' },
        },
      ],
      workRows: [{ task_id: 'task-1', minutes: 30 }],
      eventRows: [
        {
          payload: {
            title: 'Standup',
            startAt: '2026-06-08T10:00:00.000Z',
            endAt: '2026-06-08T10:30:00.000Z',
            isBlocking: true,
          },
        },
      ],
      runRows: [runRow()],
      runItemRows: [draftRow()],
    });

    const result = await service.createRun(
      {
        rangeStart: '2026-06-08T09:00:00.000Z',
        rangeEnd: '2026-06-08T12:00:00.000Z',
        strategy: 'deadline_first',
      },
      context,
    );

    expect(result).toMatchObject({
      run: { id: 'run-1' },
      items: [{ id: 'draft-1', taskId: 'task-1' }],
      unplanned: [],
      modelRunId: 'model-run-1',
      modelUsed: 'rule_learned',
      modelVersion: 'scheduler-v1',
      llmFallbackUsed: false,
    });
    expect(devices.ensureUser).toHaveBeenCalledWith(context.userId);
    expect(devices.ensureDevice).toHaveBeenCalledWith(context);
    expect(models.startRun).toHaveBeenCalledWith(
      userId,
      'scheduler.v1',
      expect.objectContaining({
        source: 'scheduler.createRun',
        inputSummary: expect.objectContaining({
          taskCount: 1,
          busyBlockCount: 1,
          strategy: 'deadline_first',
        }),
      }),
    );

    const scheduleRunInsert = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('INSERT INTO schedule_runs'),
    );
    expect((scheduleRunInsert?.[1] as unknown[])?.slice(0, 6)).toEqual([
      userId,
      deviceId,
      new Date('2026-06-08T09:00:00.000Z'),
      new Date('2026-06-08T12:00:00.000Z'),
      'initial_plan',
      'deadline_first',
    ]);
    const inputSnapshot = JSON.parse(String((scheduleRunInsert?.[1] as unknown[])[6]));
    const outputSummary = JSON.parse(String((scheduleRunInsert?.[1] as unknown[])[7]));
    const riskSummary = JSON.parse(String((scheduleRunInsert?.[1] as unknown[])[8]));
    expect(inputSnapshot).toMatchObject({
      taskCount: 1,
      actualWorkApplied: [{ taskId: 'task-1', estimatedMinutes: 90, confirmedMinutes: 30, remainingMinutes: 60 }],
    });
    expect(outputSummary).toEqual({ plannedCount: 1, unplanned: [] });
    expect(riskSummary).toMatchObject({
      hasUnplanned: false,
      generatedBy: 'rule_greedy_mvp',
      modelRunId: 'model-run-1',
      modelUsed: 'rule_learned',
      modelVersion: 'scheduler-v1',
      llmFallback: { used: false },
    });

    const draftInsert = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('INSERT INTO schedule_draft_items'),
    );
    expect((draftInsert?.[1] as unknown[])?.slice(0, 6)).toEqual([
      userId,
      'run-1',
      'task-1',
      'Focus task',
      new Date('2026-06-08T09:00:00.000Z'),
      new Date('2026-06-08T10:00:00.000Z'),
    ]);
    expect(JSON.parse(String((draftInsert?.[1] as unknown[])[7]))).toMatchObject({
      priority: 'high',
      remainingMinutes: 60,
      confirmedMinutes: 30,
      location: 'Desk',
      notes: 'Deep work',
      modelUsed: 'rule_learned',
    });

    expect(models.completeRun).toHaveBeenCalledWith(
      userId,
      'model-run-1',
      expect.objectContaining({
        status: 'succeeded',
        outputSummary: expect.objectContaining({ scheduleRunId: 'run-1', plannedCount: 1 }),
        confidence: expect.closeTo(0.78, 5),
        usedLlm: false,
      }),
    );
    expect(database.transaction).toHaveBeenCalledOnce();
  });

  it('creates an empty draft from startAt and endAt aliases using default fields', async () => {
    const { service, transactionClient, models } = createService({
      runRows: [
        runRow({
          id: 'run-empty',
          outputSummary: { unplanned: [] },
          riskSummary: {
            modelRunId: 'model-run-1',
            modelUsed: 'hybrid',
            modelVersion: 'scheduler-v1',
            llmFallback: { used: false },
          },
        }),
      ],
      runItemRows: [],
    });

    await expect(
      service.createRun(
        {
          startAt: '2026-06-08T13:00:00.000Z',
          endAt: '2026-06-08T15:00:00.000Z',
        },
        context,
      ),
    ).resolves.toMatchObject({
      run: { id: 'run-empty' },
      items: [],
      unplanned: [],
      modelUsed: 'hybrid',
    });

    expect(models.scheduleFallback).toHaveBeenCalledWith(
      userId,
      expect.objectContaining({
        rangeStart: new Date('2026-06-08T13:00:00.000Z'),
        rangeEnd: new Date('2026-06-08T15:00:00.000Z'),
        tasks: [],
        unplanned: [],
      }),
    );
    const scheduleRunInsert = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('INSERT INTO schedule_runs'),
    );
    expect((scheduleRunInsert?.[1] as unknown[])?.slice(0, 6)).toEqual([
      userId,
      deviceId,
      new Date('2026-06-08T13:00:00.000Z'),
      new Date('2026-06-08T15:00:00.000Z'),
      'initial_plan',
      'balanced',
    ]);
    expect(JSON.parse(String((scheduleRunInsert?.[1] as unknown[])[7]))).toEqual({
      plannedCount: 0,
      unplanned: [],
    });
    expect(JSON.parse(String((scheduleRunInsert?.[1] as unknown[])[8]))).toMatchObject({
      hasUnplanned: false,
      generatedBy: 'rule_greedy_with_llm_fallback',
      llmFallback: {
        used: false,
        validatedCount: 0,
        rejectedCount: 0,
      },
    });
    expect(models.completeRun).toHaveBeenCalledWith(
      userId,
      'model-run-1',
      expect.objectContaining({
        status: 'succeeded',
        confidence: 0,
        usedLlm: false,
      }),
    );
  });

  it('uses an empty scheduling profile when the active model profile is unavailable', async () => {
    const { service, transactionClient, models } = createService({
      runRows: [runRow()],
      runItemRows: [],
    });
    models.activeProfile.mockResolvedValueOnce(null as never);

    await expect(
      service.createRun(
        {
          rangeStart: '2026-06-08T09:00:00.000Z',
          rangeEnd: '2026-06-08T10:00:00.000Z',
          useLlmFallback: false,
        },
        context,
      ),
    ).resolves.toMatchObject({
      run: { id: 'run-1' },
      items: [],
      unplanned: [],
      modelUsed: 'rule_learned',
    });

    expect(models.startRun).toHaveBeenCalledWith(
      userId,
      'scheduler.v1',
      expect.objectContaining({
        inputSummary: expect.objectContaining({
          taskCount: 0,
          profile: {},
        }),
      }),
    );
    expect(models.scheduleFallback).not.toHaveBeenCalled();

    const scheduleRunInsert = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('INSERT INTO schedule_runs'),
    );
    expect(JSON.parse(String((scheduleRunInsert?.[1] as unknown[])[8]))).toMatchObject({
      generatedBy: 'rule_greedy_mvp',
      modelUsed: 'rule_learned',
      modelVersion: 'scheduler-v1',
      llmFallback: { used: false },
    });
  });

  it('records partial empty plans for locked tasks and fully blocked windows', async () => {
    const { service, transactionClient, models } = createService({
      taskRows: [
        {
          id: 'task-object-locked',
          uid: 'locked-task',
          payload: {
            title: 'Locked task',
            estimatedMinutes: 30,
            locked: true,
            priority: 'high',
            status: 'paused',
          },
        },
        {
          id: 'task-object-blocked',
          uid: 'blocked-task',
          payload: {
            title: 'Blocked task',
            estimatedMinutes: 45,
            priority: 'unknown-priority',
            status: 'waiting',
          },
        },
      ],
      eventRows: [
        {
          payload: {
            title: 'Blocked morning',
            startAt: '2026-06-08T09:00:00.000Z',
            endAt: '2026-06-08T11:00:00.000Z',
            kind: 'blocking',
          },
        },
      ],
      runRows: [
        runRow({
          outputSummary: {
            unplanned: [
              { taskId: 'locked-task' },
              { taskId: 'blocked-task' },
            ],
          },
          riskSummary: {
            modelRunId: 'model-run-1',
            modelUsed: 'rule_learned',
            modelVersion: 'scheduler-v1',
            llmFallback: { used: false },
          },
        }),
      ],
      runItemRows: [],
    });

    await expect(
      service.createRun(
        {
          rangeStart: '2026-06-08T09:00:00.000Z',
          rangeEnd: '2026-06-08T11:00:00.000Z',
          useLlmFallback: false,
        },
        context,
      ),
    ).resolves.toMatchObject({
      items: [],
      unplanned: [{ taskId: 'locked-task' }, { taskId: 'blocked-task' }],
    });

    const draftInserts = transactionClient.query.mock.calls.filter(([sql]) =>
      String(sql).includes('INSERT INTO schedule_draft_items'),
    );
    expect(draftInserts).toHaveLength(0);

    const scheduleRunInsert = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('INSERT INTO schedule_runs'),
    );
    const inputSnapshot = JSON.parse(String((scheduleRunInsert?.[1] as unknown[])[6]));
    const outputSummary = JSON.parse(String((scheduleRunInsert?.[1] as unknown[])[7]));
    const riskSummary = JSON.parse(String((scheduleRunInsert?.[1] as unknown[])[8]));
    expect(inputSnapshot).toMatchObject({
      taskCount: 2,
      busyBlocks: [
        {
          title: 'Blocked morning',
          source: 'calendar_event',
        },
      ],
      actualWorkApplied: [
        { taskId: 'locked-task', locked: true, allowAutoSchedule: true },
        { taskId: 'blocked-task', locked: false, allowAutoSchedule: true },
      ],
    });
    expect(outputSummary).toMatchObject({
      plannedCount: 0,
      unplanned: [
        { taskId: 'locked-task', remainingMinutes: 30 },
        { taskId: 'blocked-task', remainingMinutes: 45 },
      ],
    });
    expect(riskSummary).toMatchObject({
      hasUnplanned: true,
      generatedBy: 'rule_greedy_mvp',
      llmFallback: { used: false },
    });

    const auditInsert = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('INSERT INTO audit_logs'),
    );
    expect(auditInsert?.[1]).toEqual([
      userId,
      deviceId,
      'scheduler.run.created',
      'schedule_run',
      'run-1',
      expect.stringContaining('"unplannedCount":2'),
    ]);
    expect(models.completeRun).toHaveBeenCalledWith(
      userId,
      'model-run-1',
      expect.objectContaining({
        status: 'partial',
        confidence: 0,
        usedLlm: false,
      }),
    );
    expect(models.scheduleFallback).not.toHaveBeenCalled();
  });

  it('uses validated LLM fallback drafts when rule scheduling leaves work unplanned', async () => {
    const { service, transactionClient, models } = createService({
      taskRows: [
        {
          id: 'task-object-1',
          uid: 'task-long',
          payload: {
            title: 'Long task',
            estimatedMinutes: 120,
            canSplit: false,
            minChunkMinutes: 15,
            maxChunkMinutes: 120,
          },
        },
      ],
      scheduleFallback: {
        used: true,
        providerKey: 'openai',
        model: 'gpt-test',
        explanation: 'filled a short usable slot',
        raw: '{hidden}',
        draftItems: [
          {
            taskId: 'task-long',
            taskTitle: 'Long task',
            proposedStart: '2026-06-08T09:00:00.000Z',
            proposedEnd: '2026-06-08T10:00:00.000Z',
            reason: 'short fallback',
            confidence: 0.7,
          },
          {
            taskId: 'missing-task',
            proposedStart: '2026-06-08T09:00:00.000Z',
            proposedEnd: '2026-06-08T10:00:00.000Z',
          },
        ],
        unplanned: [],
      },
      runRows: [
        runRow({
          outputSummary: { unplanned: [{ taskId: 'task-long' }] },
          riskSummary: {
            modelRunId: 'model-run-1',
            modelUsed: 'hybrid',
            modelVersion: 'scheduler-v1',
            llmFallback: { used: true },
          },
        }),
      ],
    });

    await service.createRun(
      {
        rangeStart: '2026-06-08T09:00:00.000Z',
        rangeEnd: '2026-06-08T10:00:00.000Z',
        useLlmFallback: true,
      },
      context,
    );

    expect(models.scheduleFallback).toHaveBeenCalledWith(
      userId,
      expect.objectContaining({
        rangeStart: new Date('2026-06-08T09:00:00.000Z'),
        rangeEnd: new Date('2026-06-08T10:00:00.000Z'),
        tasks: [expect.objectContaining({ id: 'task-long', remainingMinutes: 120, canSplit: false })],
        unplanned: [expect.objectContaining({ taskId: 'task-long' })],
      }),
    );
    const scheduleRunInsert = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('INSERT INTO schedule_runs'),
    );
    const outputSummary = JSON.parse(String((scheduleRunInsert?.[1] as unknown[])[7]));
    const riskSummary = JSON.parse(String((scheduleRunInsert?.[1] as unknown[])[8]));
    expect(outputSummary).toMatchObject({
      plannedCount: 1,
      unplanned: [expect.objectContaining({ taskId: 'task-long' })],
    });
    expect(riskSummary).toMatchObject({
      generatedBy: 'rule_greedy_with_llm_fallback',
      modelUsed: 'hybrid',
      llmFallback: {
        used: true,
        providerKey: 'openai',
        model: 'gpt-test',
        validatedCount: 1,
        rejectedCount: 1,
        rejected: [expect.objectContaining({ taskId: 'missing-task', reason: 'invalid_task_or_time' })],
      },
    });
    expect(riskSummary.llmFallback).not.toHaveProperty('raw');
    expect(riskSummary.llmFallback).not.toHaveProperty('draftItems');

    const fallbackDraftInsert = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('INSERT INTO schedule_draft_items'),
    );
    expect(JSON.parse(String((fallbackDraftInsert?.[1] as unknown[])[7]))).toMatchObject({
      text: 'short fallback',
      modelUsed: 'llm_fallback',
      serverValidated: true,
      explanation: 'filled a short usable slot',
    });
    expect(models.completeRun).toHaveBeenCalledWith(
      userId,
      'model-run-1',
      expect.objectContaining({
        status: 'partial',
        usedLlm: true,
        llmProviderKey: 'openai',
        llmModel: 'gpt-test',
      }),
    );
  });

  it('keeps model fallback unplanned items when no fallback drafts validate', async () => {
    const { service, transactionClient, models } = createService({
      taskRows: [
        {
          id: 'task-object-1',
          uid: 'task-long',
          payload: {
            title: 'Long task',
            estimatedMinutes: 120,
            canSplit: false,
          },
        },
      ],
      scheduleFallback: {
        used: true,
        draftItems: [],
        unplanned: [{ taskId: 'task-long', reason: 'model found no acceptable slot' }],
      },
      runRows: [
        runRow({
          outputSummary: { unplanned: [{ taskId: 'task-long', reason: 'model found no acceptable slot' }] },
          riskSummary: {
            modelRunId: 'model-run-1',
            modelUsed: 'hybrid',
            modelVersion: 'scheduler-v1',
            llmFallback: { used: true },
          },
        }),
      ],
    });

    await service.createRun(
      {
        rangeStart: '2026-06-08T09:00:00.000Z',
        rangeEnd: '2026-06-08T10:00:00.000Z',
        useLlmFallback: true,
      },
      context,
    );

    expect(models.scheduleFallback).toHaveBeenCalledOnce();
    const scheduleRunInsert = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('INSERT INTO schedule_runs'),
    );
    expect(JSON.parse(String((scheduleRunInsert?.[1] as unknown[])[7]))).toEqual({
      plannedCount: 0,
      unplanned: [{ taskId: 'task-long', reason: 'model found no acceptable slot' }],
    });
    expect(JSON.parse(String((scheduleRunInsert?.[1] as unknown[])[8]))).toMatchObject({
      generatedBy: 'rule_greedy_with_llm_fallback',
      llmFallback: {
        used: true,
        validatedCount: 0,
        rejectedCount: 0,
      },
    });
    expect(models.completeRun).toHaveBeenCalledWith(
      userId,
      'model-run-1',
      expect.objectContaining({
        status: 'partial',
        confidence: 0,
        usedLlm: true,
      }),
    );
  });

  it('rejects invalid create and deviation ranges before database reads', async () => {
    const { service, database, models } = createService();

    await expect(
      service.createRun(
        {
          rangeStart: '2026-06-08T12:00:00.000Z',
          rangeEnd: '2026-06-08T09:00:00.000Z',
        },
        context,
      ),
    ).rejects.toThrow(BadRequestException);
    expect(models.activeProfile).not.toHaveBeenCalled();
    expect(database.query).not.toHaveBeenCalled();

    await expect(
      service.detectDeviations(
        {
          rangeStart: '2026-06-08T12:00:00.000Z',
          rangeEnd: '2026-06-08T09:00:00.000Z',
        },
        context,
      ),
    ).rejects.toThrow('rangeStart must be before rangeEnd');
    expect(database.query).not.toHaveBeenCalled();
  });

  it('returns a hydrated run and default model metadata, or throws for missing runs', async () => {
    const { service, database } = createService({
      runRows: [runRow({ id: 'run-empty', outputSummary: null, riskSummary: null })],
      runItemRows: [draftRow({ id: 'item-1' })],
    });

    await expect(service.run('run-empty', context)).resolves.toMatchObject({
      run: { id: 'run-empty' },
      items: [{ id: 'item-1' }],
      unplanned: [],
      modelRunId: null,
      modelUsed: 'rule',
      modelVersion: null,
      llmFallbackUsed: false,
    });
    expect(database.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('FROM schedule_runs'),
      [userId, 'run-empty'],
    );
    expect(database.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('FROM schedule_draft_items'),
      [userId, 'run-empty'],
    );

    const missing = createService({ runRows: [] });
    await expect(missing.service.run('missing-run', context)).rejects.toThrow('schedule run not found');
    expect(missing.database.query).toHaveBeenCalledOnce();
  });

  it('accepts, modifies, rejects and audits selected draft items in one transaction', async () => {
    const { service, transactionClient, models } = createService({
      transactionRunRows: [{ risk_summary_json: { modelRunId: 'model-run-1' } }],
      transactionItemRows: [
        {
          id: 'item-1',
          task_id: 'task-1',
          task_title: 'Focus task',
          proposed_start: new Date('2026-06-08T09:00:00.000Z'),
          proposed_end: new Date('2026-06-08T10:00:00.000Z'),
          reason_json: { reason: 'rule' },
        },
        {
          id: 'item-2',
          task_id: 'task-2',
          task_title: 'Rejected task',
          proposed_start: new Date('2026-06-08T10:00:00.000Z'),
          proposed_end: new Date('2026-06-08T11:00:00.000Z'),
          reason_json: {},
        },
        {
          id: 'item-3',
          task_id: 'task-3',
          task_title: 'Invalid override',
          proposed_start: new Date('2026-06-08T12:00:00.000Z'),
          proposed_end: new Date('2026-06-08T11:00:00.000Z'),
          reason_json: {},
        },
      ],
      syncObjectRows: [{ id: 'created-object-1', server_version: 7 }],
    });

    await expect(
      service.acceptRun(
        'run-1',
        {
          acceptedItemIds: ['item-1', 'item-3', '', 7],
          rejectedItemIds: ['item-2', '', null],
          modifiedItems: [
            {
              itemId: 'item-1',
              start: '2026-06-08T09:15:00.000Z',
              end: '2026-06-08T10:15:00.000Z',
            },
            null,
          ],
          note: '  no room  ',
        },
        context,
      ),
    ).resolves.toEqual({ ok: true, createdObjectIds: ['created-object-1'] });

    const syncInsert = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('INSERT INTO sync_objects'),
    );
    expect((syncInsert?.[1] as unknown[])?.slice(0, 2)).toEqual([
      userId,
      'schedule:run-1:item-1',
    ]);
    expect(JSON.parse(String((syncInsert?.[1] as unknown[])[2]))).toEqual({
      uid: 'schedule:run-1:item-1',
      taskId: 'task-1',
      taskTitle: 'Focus task',
      startAt: '2026-06-08T09:15:00.000Z',
      endAt: '2026-06-08T10:15:00.000Z',
      durationMinutes: 60,
      status: 'confirmed',
      source: 'server_scheduler',
      scheduleRunId: 'run-1',
      explanation: { reason: 'rule' },
    });

    const itemStatusUpdate = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('status = CASE WHEN $4::boolean'),
    );
    expect(itemStatusUpdate?.[1]).toMatchObject([
      userId,
      'run-1',
      'item-1',
      true,
      new Date('2026-06-08T09:15:00.000Z'),
      new Date('2026-06-08T10:15:00.000Z'),
    ]);
    const rejectedUpdate = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes("SET status = 'rejected', user_reject_reason = $4"),
    );
    expect(rejectedUpdate?.[1]).toEqual([userId, 'run-1', ['item-2'], 'no room']);
    const runStatusUpdate = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('SET status = $3, confirmed_at'),
    );
    expect(runStatusUpdate?.[1]).toEqual([userId, 'run-1', 'partially_accepted']);
    expect(models.recordFeedback).toHaveBeenCalledWith(
      transactionClient,
      userId,
      deviceId,
      'scheduler.v1',
      expect.objectContaining({
        modelRunId: 'model-run-1',
        feedbackType: 'modified',
        outcome: 'accepted',
        feedbackPayload: expect.objectContaining({
          createdObjectIds: ['created-object-1'],
          acceptedIds: ['item-1', 'item-3'],
          rejectedIds: ['item-2'],
          note: 'no room',
        }),
      }),
    );
  });

  it('marks a run fully accepted when no selection filters or modifications are provided', async () => {
    const { service, transactionClient, models } = createService({
      transactionRunRows: [{ risk_summary_json: null }],
      transactionItemRows: [
        {
          id: 'item-1',
          task_id: 'task-1',
          task_title: 'Task',
          proposed_start: new Date('2026-06-08T09:00:00.000Z'),
          proposed_end: new Date('2026-06-08T09:30:00.000Z'),
          reason_json: {},
        },
      ],
    });

    await expect(service.acceptRun('run-1', {}, context)).resolves.toMatchObject({
      ok: true,
      createdObjectIds: ['object-1'],
    });

    const runStatusUpdate = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('SET status = $3, confirmed_at'),
    );
    expect(runStatusUpdate?.[1]).toEqual([userId, 'run-1', 'accepted']);
    expect(models.recordFeedback).toHaveBeenCalledWith(
      transactionClient,
      userId,
      deviceId,
      'scheduler.v1',
      expect.objectContaining({
        modelRunId: null,
        feedbackType: 'accepted',
        feedbackPayload: {
          createdObjectIds: ['object-1'],
          acceptedIds: [],
          rejectedIds: [],
          modifiedItems: [],
          note: null,
        },
      }),
    );
  });

  it('accepts modified draft items even when they were not explicitly selected', async () => {
    const { service, transactionClient } = createService({
      transactionItemRows: [
        {
          id: 'item-1',
          task_id: 'task-1',
          proposed_start: new Date('2026-06-08T09:00:00.000Z'),
          proposed_end: new Date('2026-06-08T09:30:00.000Z'),
        },
      ],
      syncObjectRows: [{ id: 'created-object-with-default-version' }],
    });

    await expect(
      service.acceptRun(
        'run-1',
        {
          acceptedItemIds: ['different-item'],
          modifiedItems: [
            {
              itemId: 'item-1',
              start: '2026-06-08T09:00:00.000Z',
              end: '2026-06-08T09:00:30.000Z',
            },
          ],
        },
        context,
      ),
    ).resolves.toEqual({ ok: true, createdObjectIds: ['created-object-with-default-version'] });

    const syncInsert = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('INSERT INTO sync_objects'),
    );
    expect(JSON.parse(String((syncInsert?.[1] as unknown[])[2]))).toEqual({
      uid: 'schedule:run-1:item-1',
      taskId: 'task-1',
      taskTitle: '',
      startAt: '2026-06-08T09:00:00.000Z',
      endAt: '2026-06-08T09:00:30.000Z',
      durationMinutes: 1,
      status: 'confirmed',
      source: 'server_scheduler',
      scheduleRunId: 'run-1',
      explanation: {},
    });
    const changeInsert = transactionClient.query.mock.calls.find(([sql]) =>
      String(sql).includes('INSERT INTO sync_changes'),
    );
    expect(changeInsert?.[1]).toEqual([
      userId,
      deviceId,
      'created-object-with-default-version',
      'task_schedule_segment',
      1,
      expect.any(String),
    ]);
    expect(transactionClient.query).toHaveBeenCalledWith(
      expect.stringContaining('status = CASE WHEN $4::boolean'),
      [
        userId,
        'run-1',
        'item-1',
        true,
        new Date('2026-06-08T09:00:00.000Z'),
        new Date('2026-06-08T09:00:30.000Z'),
      ],
    );
  });

  it('rejects accepting a missing draft run', async () => {
    const { service, transactionClient, models } = createService({
      transactionRunRows: [],
    });

    await expect(service.acceptRun('missing-run', {}, context)).rejects.toThrow(
      'draft schedule run not found',
    );
    expect(transactionClient.query).toHaveBeenCalledOnce();
    expect(models.recordFeedback).not.toHaveBeenCalled();
  });

  it('rejects a draft run without writing schedule segments', async () => {
    const { service, transactionClient, models } = createService();

    await expect(service.rejectRun('run-1', { reason: '  conflict  ' }, context)).resolves.toEqual({
      ok: true,
      message: 'draft rejected; no schedule segments were written',
    });

    expect(transactionClient.query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'rejected'"),
      [userId, 'run-1'],
    );
    expect(transactionClient.query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'rejected', user_reject_reason = $3"),
      [userId, 'run-1', 'conflict'],
    );
    expect(transactionClient.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        userId,
        deviceId,
        'scheduler.run.rejected',
        'schedule_run',
        'run-1',
        expect.stringContaining('"reason":"conflict"'),
      ],
    );
    expect(models.recordFeedback).toHaveBeenCalledWith(
      transactionClient,
      userId,
      deviceId,
      'scheduler.v1',
      {
        targetType: 'schedule_run',
        targetId: 'run-1',
        feedbackType: 'rejected',
        outcome: 'rejected',
        source: 'scheduler.rejectRun',
        feedbackPayload: { reason: 'conflict' },
      },
    );
  });

  it('writes audit rows with default metadata when no entity details are provided', async () => {
    const { service, transactionClient } = createService();
    const internal = service as never as {
      recordAudit: (
        client: typeof transactionClient,
        userId: string,
        deviceId: string,
        action: string,
        details: Record<string, unknown>,
      ) => Promise<void>;
    };

    await internal.recordAudit(transactionClient, userId, deviceId, 'scheduler.audit.defaulted', {});

    expect(transactionClient.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        userId,
        deviceId,
        'scheduler.audit.defaulted',
        'schedule_run',
        null,
        '{}',
      ],
    );
  });

  it('detects missed, different-activity and unplanned-actual deviations', async () => {
    const { service, transactionClient } = createService({
      runRows: [
        {
          id: 'segment-missed',
          payload: {
            taskId: 'task-1',
            taskTitle: 'Focus',
            startAt: '2026-06-08T09:00:00.000Z',
            endAt: '2026-06-08T10:00:00.000Z',
          },
        },
        {
          id: 'segment-different',
          payload: {
            taskId: 'task-2',
            taskTitle: 'Plan',
            startAt: '2026-06-08T10:00:00.000Z',
            endAt: '2026-06-08T11:00:00.000Z',
          },
        },
        {
          id: 'segment-invalid',
          payload: {
            taskId: 'task-invalid',
            startAt: 'not-a-date',
            endAt: '2026-06-08T11:00:00.000Z',
          },
        },
      ],
      runItemRows: [
        {
          id: 'actual-different',
          title: 'Email',
          start_at: new Date('2026-06-08T10:15:00.000Z'),
          end_at: new Date('2026-06-08T10:45:00.000Z'),
        },
        {
          id: 'actual-unplanned',
          title: 'Walk-in call',
          start_at: new Date('2026-06-08T11:15:00.000Z'),
          end_at: new Date('2026-06-08T11:45:00.000Z'),
        },
        {
          id: 'actual-invalid',
          title: 'Broken',
          start_at: null,
          end_at: new Date('2026-06-08T11:45:00.000Z'),
        },
      ],
    });

    await expect(
      service.detectDeviations(
        {
          rangeStart: '2026-06-08T09:00:00.000Z',
          rangeEnd: '2026-06-08T12:00:00.000Z',
        },
        context,
      ),
    ).resolves.toEqual({ ok: true, created: 3 });

    const deviationCalls = transactionClient.query.mock.calls.filter(([sql]) =>
      String(sql).includes('INSERT INTO plan_deviations'),
    );
    expect(deviationCalls).toHaveLength(3);
    expect(deviationCalls.map(([sql]) => String(sql))).toEqual([
      expect.stringContaining("'missed'"),
      expect.stringContaining("'different_activity'"),
      expect.stringContaining("'actual_unplanned'"),
    ]);
    expect(transactionClient.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        userId,
        deviceId,
        'scheduler.deviations.detected',
        'schedule_run',
        null,
        expect.stringContaining('"created":3'),
      ],
    );
  });

  it('detects deviations from startAt aliases without duplicating matching actuals', async () => {
    const { service, database, transactionClient } = createService({
      runRows: [
        {
          id: 'segment-without-title',
          payload: {
            taskId: 'task-1',
            startAt: '2026-06-08T09:00:00.000Z',
            endAt: '2026-06-08T10:00:00.000Z',
          },
        },
      ],
      runItemRows: [
        {
          id: 'actual-overlap',
          title: null,
          start_at: new Date('2026-06-08T09:15:00.000Z'),
          end_at: new Date('2026-06-08T09:45:00.000Z'),
        },
        {
          id: 'actual-unplanned',
          title: 'Unplanned admin',
          start_at: new Date('2026-06-08T10:15:00.000Z'),
          end_at: new Date('2026-06-08T10:45:00.000Z'),
        },
      ],
      deviationInsertRows: [[]],
    });

    await expect(
      service.detectDeviations(
        {
          startAt: '2026-06-08T09:00:00.000Z',
          endAt: '2026-06-08T11:00:00.000Z',
        },
        context,
      ),
    ).resolves.toEqual({ ok: true, created: 0 });

    const segmentQuery = database.query.mock.calls.find(([sql]) =>
      String(sql).includes("object_type = 'task_schedule_segment'"),
    );
    const segmentSql = String(segmentQuery?.[0]).replace(/\s+/g, ' ');
    expect(segmentSql).toContain("updated_at >= $2::timestamptz - interval '1 day'");
    expect(segmentSql).toContain("updated_at < $3::timestamptz + interval '1 day'");
    expect(segmentQuery?.[1]).toEqual([
      userId,
      new Date('2026-06-08T09:00:00.000Z'),
      new Date('2026-06-08T11:00:00.000Z'),
    ]);

    const deviationCalls = transactionClient.query.mock.calls.filter(([sql]) =>
      String(sql).includes('INSERT INTO plan_deviations'),
    );
    expect(deviationCalls).toHaveLength(1);
    expect(String(deviationCalls[0][0])).toContain("'actual_unplanned'");
    expect((deviationCalls[0][1] as unknown[]).slice(0, 3)).toEqual([
      userId,
      'actual-unplanned',
      'Unplanned admin',
    ]);
    expect(transactionClient.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        userId,
        deviceId,
        'scheduler.deviations.detected',
        'schedule_run',
        null,
        expect.stringContaining('"created":0'),
      ],
    );
  });
});

describe('SchedulerService scheduling helpers', () => {
  it('normalizes scheduler settings and task rows from stored JSON payloads', async () => {
    const { service } = createService({
      settingsRows: [
        {
          key: 'working_hours',
          value: {
            theme: 'dark',
            workingHours: { enabled: true, monday: [{ start: '09:00', end: '12:00' }] },
          },
        },
        {
          key: 'scheduler.policy',
          value: {
            policy: 'balanced',
            workHours: { enabled: false },
          },
        },
      ],
      taskRows: [
        {
          id: 'db-task-1',
          payload: {
            name: 'Alias task',
            durationMinutes: 20,
            due_at: '2026-06-09T09:00:00.000Z',
            place: 'Office',
            description: 'Write notes',
            isLocked: true,
            autoSchedule: false,
            availableAfter: '2026-06-08T09:30:00.000Z',
            availableBefore: '2026-06-08T12:00:00.000Z',
            splittable: false,
            min_chunk_minutes: 30,
            max_chunk_minutes: 15,
          },
        },
        {
          id: 'db-task-2',
          uid: 'done-task',
          payload: { title: 'Done', status: 'archived' },
        },
        {
          id: 'db-task-3',
          uid: 'paused-task',
          payload: {
            summary: 'Paused but eligible',
            estimated_minutes: 10,
            priority: 'unknown-priority',
            status: 'paused',
          },
        },
        {
          id: 'untitled-task',
          payload: {
            estimatedMinutes: 45,
          },
        },
      ],
      workRows: [{ task_id: 'db-task-1', minutes: 5 }],
    });
    const internal = service as never as {
      readSchedulerSettings: (id: string) => Promise<Record<string, unknown>>;
      readTasks: (id: string) => Promise<Array<Record<string, unknown>>>;
    };

    await expect(internal.readSchedulerSettings(userId)).resolves.toEqual({
      theme: 'dark',
      workingHours: { enabled: true, monday: [{ start: '09:00', end: '12:00' }] },
      policy: 'balanced',
      workHours: { enabled: false },
    });
    await expect(internal.readTasks(userId)).resolves.toMatchObject([
      {
        id: 'db-task-1',
        objectId: 'db-task-1',
        title: 'Alias task',
        estimatedMinutes: 20,
        confirmedMinutes: 5,
        remainingMinutes: 15,
        priority: 'normal',
        location: 'Office',
        notes: 'Write notes',
        locked: true,
        allowAutoSchedule: false,
        canSplit: false,
        minChunkMinutes: 30,
        maxChunkMinutes: 30,
        status: '',
      },
      {
        id: 'paused-task',
        objectId: 'db-task-3',
        title: 'Paused but eligible',
        estimatedMinutes: 15,
        confirmedMinutes: 0,
        remainingMinutes: 15,
        priority: 'unknown-priority',
        locked: false,
        allowAutoSchedule: true,
        canSplit: true,
        minChunkMinutes: 15,
        maxChunkMinutes: 120,
        status: 'paused',
      },
      {
        id: 'untitled-task',
        objectId: 'untitled-task',
        title: 'untitled-task',
        estimatedMinutes: 45,
        confirmedMinutes: 0,
        remainingMinutes: 45,
        priority: 'normal',
      },
    ]);
  });

  it('merges snake-case scheduler work hours and leaves existing hours when later rows omit them', async () => {
    const { service } = createService({
      settingsRows: [
        {
          key: 'work_hours',
          value: {
            working_hours: { friday: [{ start: '08:00', end: '09:00' }] },
          },
        },
        {
          key: 'user.preference',
          value: {
            theme: 'plain',
          },
        },
      ],
    });
    const internal = service as never as {
      readSchedulerSettings: (id: string) => Promise<Record<string, unknown>>;
    };

    await expect(internal.readSchedulerSettings(userId)).resolves.toEqual({
      working_hours: { friday: [{ start: '08:00', end: '09:00' }] },
      workHours: { friday: [{ start: '08:00', end: '09:00' }] },
      theme: 'plain',
    });
  });

  it('expands recurring busy blocks and ignores non-blocking or invalid events', async () => {
    const { service } = createService({
      eventRows: [
        {
          payload: {
            title: 'Weekly review',
            startAt: '2026-06-01T09:00:00.000Z',
            endAt: '2026-06-01T10:00:00.000Z',
            blocking: true,
            recurrence: { frequency: 'weekly', byWeekday: ['mon'], until: '2026-06-30T00:00:00.000Z' },
          },
        },
        {
          payload: {
            startAt: '2026-06-01T10:00:00.000Z',
            endAt: '2026-06-01T11:00:00.000Z',
            blocking: true,
            recurrence: { frequency: 'weekly', byWeekday: ['mon'], until: '2026-06-30T00:00:00.000Z' },
          },
        },
        {
          payload: {
            title: 'FYI',
            startAt: '2026-06-08T09:30:00.000Z',
            endAt: '2026-06-08T10:30:00.000Z',
            blocking: false,
          },
        },
        {
          payload: {
            title: 'Invalid',
            startAt: 'not-a-date',
            endAt: '2026-06-08T10:30:00.000Z',
            kind: 'blocking',
          },
        },
      ],
    });
    const internal = service as never as {
      readBusyBlocks: (id: string, start: Date, end: Date) => Promise<Array<Record<string, unknown>>>;
      expandEventOccurrences: (
        payload: Record<string, unknown>,
        start: Date | null,
        end: Date | null,
        rangeStart: Date,
        rangeEnd: Date,
      ) => Array<{ start: Date; end: Date }>;
      recurrenceDayMatches: (date: Date, recurrence: Record<string, unknown>) => boolean;
    };

    await expect(
      internal.readBusyBlocks(
        userId,
        new Date('2026-06-08T08:00:00.000Z'),
        new Date('2026-06-08T11:00:00.000Z'),
      ),
    ).resolves.toEqual([
      {
        start: new Date('2026-06-08T09:00:00.000Z'),
        end: new Date('2026-06-08T10:00:00.000Z'),
        title: 'Weekly review',
        source: 'calendar_event_recurring',
      },
      {
        start: new Date('2026-06-08T10:00:00.000Z'),
        end: new Date('2026-06-08T11:00:00.000Z'),
        title: 'Blocking schedule',
        source: 'calendar_event_recurring',
      },
    ]);
    expect(
      internal.expandEventOccurrences(
        {},
        new Date('2026-06-08T09:00:00.000Z'),
        new Date('2026-06-08T10:00:00.000Z'),
        new Date('2026-06-08T08:00:00.000Z'),
        new Date('2026-06-08T11:00:00.000Z'),
      ),
    ).toEqual([{ start: new Date('2026-06-08T09:00:00.000Z'), end: new Date('2026-06-08T10:00:00.000Z') }]);
    expect(
      internal.expandEventOccurrences(
        { repeat: 'daily' },
        new Date('2026-06-08T10:00:00.000Z'),
        new Date('2026-06-08T09:00:00.000Z'),
        new Date('2026-06-08T08:00:00.000Z'),
        new Date('2026-06-08T11:00:00.000Z'),
      ),
    ).toEqual([]);
    expect(
      internal.expandEventOccurrences(
        { repeat: 'monthly', repeatInterval: 1 },
        new Date('2026-01-01T09:00:00.000Z'),
        new Date('2026-01-01T10:00:00.000Z'),
        new Date('2026-02-01T00:00:00.000Z'),
        new Date('2026-04-02T00:00:00.000Z'),
      ).map((item) => item.start.toISOString()),
    ).toEqual(['2026-02-01T09:00:00.000Z', '2026-03-01T09:00:00.000Z', '2026-04-01T09:00:00.000Z']);
    expect(
      internal.expandEventOccurrences(
        { repeat: 'daily', repeatInterval: 2 },
        new Date('2026-06-07T09:00:00.000Z'),
        new Date('2026-06-07T10:00:00.000Z'),
        new Date('2026-06-08T00:00:00.000Z'),
        new Date('2026-06-12T00:00:00.000Z'),
      ).map((item) => item.start.toISOString()),
    ).toEqual(['2026-06-09T09:00:00.000Z', '2026-06-11T09:00:00.000Z']);
    expect(internal.recurrenceDayMatches(new Date('2026-06-08T09:00:00.000Z'), { byWeekday: [1] })).toBe(true);
    expect(internal.recurrenceDayMatches(new Date('2026-06-08T09:00:00.000Z'), { byWeekday: ['tue'] })).toBe(false);
    expect(internal.recurrenceDayMatches(new Date('2026-06-08T09:00:00.000Z'), { weekdays: [] })).toBe(true);
    expect(internal.recurrenceDayMatches(new Date('2026-06-08T09:00:00.000Z'), { byWeekday: [false, 'mon'] })).toBe(true);
  });

  it('clips and sorts direct blocking busy blocks with fallback titles', async () => {
    const { service } = createService({
      eventRows: [
        {
          payload: {
            startAt: '2026-06-08T10:30:00.000Z',
            endAt: '2026-06-08T12:30:00.000Z',
            kind: 'blocking',
          },
        },
        {
          payload: {
            summary: 'Early focus',
            startTime: '2026-06-08T08:30:00.000Z',
            endTime: '2026-06-08T09:30:00.000Z',
            isBlocking: true,
          },
        },
      ],
    });
    const internal = service as never as {
      readBusyBlocks: (id: string, start: Date, end: Date) => Promise<Array<Record<string, unknown>>>;
    };

    await expect(
      internal.readBusyBlocks(
        userId,
        new Date('2026-06-08T09:00:00.000Z'),
        new Date('2026-06-08T12:00:00.000Z'),
      ),
    ).resolves.toMatchObject([
      {
        start: new Date('2026-06-08T09:00:00.000Z'),
        end: new Date('2026-06-08T09:30:00.000Z'),
        title: 'Early focus',
        source: 'calendar_event',
      },
      {
        start: new Date('2026-06-08T10:30:00.000Z'),
        end: new Date('2026-06-08T12:00:00.000Z'),
        title: expect.any(String),
        source: 'calendar_event',
      },
    ]);
  });

  it('computes work and free block intersections with minimum duration guards', () => {
    const { service } = createService();
    const internal = service as never as {
      computeWorkBlocks: (
        start: Date,
        end: Date,
        settings: Record<string, unknown>,
        profile: Record<string, unknown>,
      ) => Array<{ start: Date; end: Date; source?: string }>;
      computeFreeBlocks: (
        start: Date,
        end: Date,
        busy: Array<{ start: Date; end: Date; title: string; source: string }>,
      ) => Array<{ start: Date; end: Date; source?: string }>;
      applyWorkBlocks: (
        free: Array<{ start: Date; end: Date; source?: string }>,
        work: Array<{ start: Date; end: Date; source?: string }>,
      ) => Array<{ start: Date; end: Date; source?: string }>;
      dateAtTime: (day: Date, value: string) => Date | null;
      workWindowsForDay: (workHours: Record<string, unknown>, dayKey: string) => Array<Record<string, unknown>> | null;
    };
    const rangeStart = new Date('2026-06-08T00:00:00.000Z');
    const rangeEnd = new Date('2026-06-09T00:00:00.000Z');

    expect(internal.computeWorkBlocks(rangeStart, rangeEnd, { workHours: { enabled: false } }, {})).toEqual([
      { start: rangeStart, end: rangeEnd, source: 'range' },
    ]);
    const mondayWork = internal.computeWorkBlocks(
      rangeStart,
      rangeEnd,
      { workHours: { days: { monday: [{ from: '09:00', to: '10:00' }] } } },
      {},
    );
    expect(mondayWork).toHaveLength(1);
    expect(mondayWork[0].start.getHours()).toBe(9);
    expect(mondayWork[0].end.getHours()).toBe(10);
    expect(mondayWork[0].source).toBe('work_hours');
    expect(
      internal.computeWorkBlocks(rangeStart, rangeEnd, { workHours: { days: { tuesday: [{ start: '09:00', end: '10:00' }] } } }, {}),
    ).toEqual([{ start: rangeStart, end: rangeEnd, source: 'range_no_work_hours_match' }]);
    const defaultWindowWork = internal.computeWorkBlocks(
      rangeStart,
      rangeEnd,
      { workHours: { monday: [{}] } },
      {},
    );
    expect(defaultWindowWork).toHaveLength(1);
    expect(defaultWindowWork[0].start.getHours()).toBe(9);
    expect(defaultWindowWork[0].end.getHours()).toBe(18);
    expect(internal.dateAtTime(rangeStart, 'bad')).toBeNull();

    const free = internal.computeFreeBlocks(
      new Date('2026-06-08T09:00:00.000Z'),
      new Date('2026-06-08T11:00:00.000Z'),
      [
        {
          start: new Date('2026-06-08T09:10:00.000Z'),
          end: new Date('2026-06-08T09:50:00.000Z'),
          title: 'Busy',
          source: 'calendar_event',
        },
      ],
    );
    expect(free).toEqual([
      { start: new Date('2026-06-08T09:50:00.000Z'), end: new Date('2026-06-08T11:00:00.000Z') },
    ]);
    expect(
      internal.applyWorkBlocks(free, [
        { start: new Date('2026-06-08T10:00:00.000Z'), end: new Date('2026-06-08T10:10:00.000Z'), source: 'short' },
        { start: new Date('2026-06-08T10:00:00.000Z'), end: new Date('2026-06-08T10:30:00.000Z'), source: 'long' },
      ]),
    ).toEqual([
      { start: new Date('2026-06-08T10:00:00.000Z'), end: new Date('2026-06-08T10:30:00.000Z'), source: 'long' },
    ]);
    expect(
      internal.applyWorkBlocks(
        [{ start: new Date('2026-06-08T10:00:00.000Z'), end: new Date('2026-06-08T11:00:00.000Z'), source: 'free-source' }],
        [{ start: new Date('2026-06-08T10:15:00.000Z'), end: new Date('2026-06-08T10:45:00.000Z') }],
      ),
    ).toEqual([
      { start: new Date('2026-06-08T10:15:00.000Z'), end: new Date('2026-06-08T10:45:00.000Z'), source: 'free-source' },
    ]);
    expect(internal.workWindowsForDay({ schedule: { sunday: [{ start: '08:00', end: '09:00' }] } }, 'sunday')).toEqual([
      { start: '08:00', end: '09:00' },
    ]);
    expect(
      internal.computeFreeBlocks(
        new Date('2026-06-08T09:00:00.000Z'),
        new Date('2026-06-08T12:00:00.000Z'),
        [
          {
            start: new Date('2026-06-08T09:00:00.000Z'),
            end: new Date('2026-06-08T11:00:00.000Z'),
            title: 'Long busy block',
            source: 'calendar_event',
          },
          {
            start: new Date('2026-06-08T09:30:00.000Z'),
            end: new Date('2026-06-08T10:00:00.000Z'),
            title: 'Nested busy block',
            source: 'calendar_event',
          },
        ],
      ),
    ).toEqual([{ start: new Date('2026-06-08T11:00:00.000Z'), end: new Date('2026-06-08T12:00:00.000Z') }]);
    const sundayWork = internal.computeWorkBlocks(
      new Date('2026-06-07T00:00:00.000Z'),
      new Date('2026-06-08T00:00:00.000Z'),
      { workHours: { '7': [{ start: '08:00', end: '09:00' }] } },
      {},
    );
    expect(sundayWork).toHaveLength(1);
    expect(sundayWork[0].end.getTime() - sundayWork[0].start.getTime()).toBe(60 * 60000);
    expect(sundayWork[0].source).toBe('work_hours');
  });

  it('covers helper fallbacks for recurrence, windows, scoring and LLM confidence', () => {
    const { service } = createService();
    const internal = service as never as {
      computeWorkBlocks: (
        start: Date,
        end: Date,
        settings: Record<string, unknown>,
        profile: Record<string, unknown>,
      ) => Array<{ start: Date; end: Date; source?: string }>;
      expandEventOccurrences: (
        payload: Record<string, unknown>,
        start: Date | null,
        end: Date | null,
        rangeStart: Date,
        rangeEnd: Date,
      ) => Array<{ start: Date; end: Date }>;
      recurrenceDayMatches: (date: Date, recurrence: Record<string, unknown>) => boolean;
      workWindowsForDay: (workHours: Record<string, unknown>, dayKey: string) => Array<Record<string, unknown>> | null;
      isRecurringEvent: (payload: Record<string, unknown>) => boolean;
      taskScore: (task: Record<string, unknown>, strategy: string, profile: Record<string, unknown>) => number;
      shouldUseLlmFallback: (
        body: Record<string, unknown>,
        tasks: Array<Record<string, unknown>>,
        planned: Array<{ confidence: number }>,
        unplanned: Array<Record<string, unknown>>,
        profile: Record<string, unknown>,
      ) => boolean;
      validateLlmDrafts: (
        fallback: Record<string, unknown>,
        tasks: Array<Record<string, unknown>>,
        start: Date,
        end: Date,
        busy: Array<{ start: Date; end: Date; source: string }>,
        existing: Array<{ task: Record<string, unknown>; start: Date; end: Date }>,
      ) => {
        planned: Array<Record<string, unknown>>;
        rejected: Array<Record<string, unknown>>;
        unplanned: Array<Record<string, unknown>>;
      };
      plan: (
        tasks: Array<Record<string, unknown>>,
        free: Array<{ start: Date; end: Date; source?: string }>,
        strategy: string,
        profile: Record<string, unknown>,
      ) => {
        planned: Array<Record<string, unknown>>;
        unplanned: Array<Record<string, unknown>>;
      };
    };
    const monday = new Date('2026-06-08T00:00:00.000Z');

    expect(internal.isRecurringEvent({})).toBe(false);
    expect(internal.isRecurringEvent({ repeatType: 'daily' })).toBe(true);
    expect(internal.isRecurringEvent({ recurrence: { frequency: 'weekly' } })).toBe(true);
    expect(
      internal.expandEventOccurrences(
        {},
        new Date('2026-06-07T09:00:00.000Z'),
        new Date('2026-06-07T10:00:00.000Z'),
        new Date('2026-06-08T09:00:00.000Z'),
        new Date('2026-06-08T12:00:00.000Z'),
      ),
    ).toEqual([]);
    expect(internal.recurrenceDayMatches(monday, { byWeekday: ['1'] })).toBe(true);
    expect(internal.recurrenceDayMatches(monday, { byWeekday: ['monday'] })).toBe(true);
    expect(internal.recurrenceDayMatches(monday, { byWeekday: ['sun'] })).toBe(false);
    expect(internal.recurrenceDayMatches(new Date('2026-06-07T09:00:00.000Z'), { byWeekday: [7] })).toBe(true);
    expect(internal.workWindowsForDay({ monday: [{ start: '09:00', end: '10:00' }] }, 'monday')).toEqual([
      { start: '09:00', end: '10:00' },
    ]);
    expect(internal.workWindowsForDay({ weekly: { monday: [] } }, 'monday')).toEqual([]);
    expect(internal.workWindowsForDay({}, 'monday')).toBeNull();
    const profileWork = internal.computeWorkBlocks(
      new Date('2026-06-08T00:00:00.000Z'),
      new Date('2026-06-09T00:00:00.000Z'),
      {},
      { workingHours: { monday: [{ start: '09:00', end: '11:00' }] } },
    );
    expect(profileWork).toHaveLength(1);
    expect(profileWork[0].start.getHours()).toBe(9);
    expect(profileWork[0].end.getHours()).toBe(11);
    expect(profileWork[0].source).toBe('work_hours');

    expect(
      internal.taskScore(
        taskCandidate({ priority: 'unknown', dueAt: undefined, confirmedMinutes: 0 }),
        'deadline_first',
        { learnedAdjustments: { nightPenalty: 5 } },
      ),
    ).toBe(5.5);
    expect(
      internal.taskScore(
        taskCandidate({ dueAt: new Date('2026-06-12T08:00:00.000Z'), confirmedMinutes: 10 }),
        'deadline_first',
        {},
      ),
    ).toBe(36);
    expect(
      internal.taskScore(
        taskCandidate({ dueAt: new Date('2026-06-10T08:00:00.000Z') }),
        'balanced',
        {},
      ),
    ).toBe(36);
    expect(
      internal.shouldUseLlmFallback(
        {},
        [taskCandidate({ id: 'low-confidence' })],
        [{ confidence: undefined as unknown as number }],
        [],
        { llmFallback: { unplannedRatioThreshold: 1, confidenceThreshold: 0.1 } },
      ),
    ).toBe(true);
    expect(
      internal.validateLlmDrafts(
        { draftItems: [{ proposed_start: '2026-06-08T09:00:00.000Z', proposed_end: '2026-06-08T09:30:00.000Z' }] },
        [taskCandidate({ id: 'known' })],
        new Date('2026-06-08T09:00:00.000Z'),
        new Date('2026-06-08T10:00:00.000Z'),
        [],
        [],
      ).rejected,
    ).toMatchObject([{ taskId: null, reason: 'invalid_task_or_time' }]);
    expect(
      internal.plan(
        [taskCandidate({ id: 'clamped', remainingMinutes: 30, estimatedMinutes: 30 })],
        [{ start: new Date('2026-06-08T09:00:00.000Z'), end: new Date('2026-06-08T10:00:00.000Z') }],
        'balanced',
        { learnedAdjustments: { confidenceBonus: 1 } },
      ).planned[0].confidence,
    ).toBe(0.95);
  });

  it('plans schedulable chunks and reports blocked or impossible tasks', () => {
    const { service } = createService();
    const internal = service as never as {
      plan: (
        tasks: Array<Record<string, unknown>>,
        free: Array<{ start: Date; end: Date; source?: string }>,
        strategy: string,
        profile: Record<string, unknown>,
      ) => {
        planned: Array<Record<string, unknown>>;
        unplanned: Array<Record<string, unknown>>;
      };
      unplannedReason: (
        task: Record<string, unknown>,
        free: Array<{ start: Date; end: Date }>,
      ) => string;
      taskScore: (task: Record<string, unknown>, strategy: string, profile: Record<string, unknown>) => number;
      taskBlockedReason: (task: Record<string, unknown>) => string | null;
    };

    const result = internal.plan(
      [
        taskCandidate({ id: 'locked', locked: true, remainingMinutes: 30 }),
        taskCandidate({ id: 'manual', allowAutoSchedule: false, remainingMinutes: 30 }),
        taskCandidate({ id: 'expired', latestEnd: new Date('2026-06-08T07:00:00.000Z'), remainingMinutes: 30 }),
        taskCandidate({
          id: 'split',
          title: 'Split work',
          remainingMinutes: 90,
          estimatedMinutes: 120,
          confirmedMinutes: 30,
          priority: 'urgent',
          dueAt: new Date('2026-06-08T20:00:00.000Z'),
          maxChunkMinutes: 60,
        }),
      ],
      [
        { start: new Date('2026-06-08T09:00:00.000Z'), end: new Date('2026-06-08T10:00:00.000Z'), source: 'first' },
        { start: new Date('2026-06-08T10:00:00.000Z'), end: new Date('2026-06-08T11:00:00.000Z'), source: 'second' },
      ],
      'deadline_first',
      {
        priorityWeights: { urgent: 100 },
        dueSoonWeights: { within24h: 50, within72h: 30 },
        actualWorkBonus: 10,
        deadlineFirstBonus: 20,
        learnedAdjustments: { confidenceBonus: 0.1, nightPenalty: 2 },
      },
    );

    expect(result.planned).toHaveLength(2);
    expect(result.planned).toMatchObject([
      {
        task: expect.objectContaining({ id: 'split' }),
        start: new Date('2026-06-08T09:00:00.000Z'),
        end: new Date('2026-06-08T10:00:00.000Z'),
        confidence: 0.88,
      },
      {
        task: expect.objectContaining({ id: 'split' }),
        start: new Date('2026-06-08T10:00:00.000Z'),
        end: new Date('2026-06-08T10:30:00.000Z'),
        confidence: 0.88,
      },
    ]);
    expect(result.unplanned).toMatchObject([
      { taskId: 'locked', locked: true, allowAutoSchedule: true },
      { taskId: 'manual', locked: false, allowAutoSchedule: false },
      { taskId: 'expired' },
    ]);
    expect(internal.taskBlockedReason(taskCandidate())).toBeNull();
    const noFreeReason = internal.unplannedReason(taskCandidate(), []);
    const windowReason = internal.unplannedReason(taskCandidate({ earliestStart: new Date('2026-06-08T09:00:00.000Z') }), [
      { start: new Date('2026-06-08T09:00:00.000Z'), end: new Date('2026-06-08T10:00:00.000Z') },
    ]);
    const noSplitReason = internal.unplannedReason(taskCandidate({ canSplit: false }), [
      { start: new Date('2026-06-08T09:00:00.000Z'), end: new Date('2026-06-08T10:00:00.000Z') },
    ]);
    const defaultReason = internal.unplannedReason(taskCandidate(), [
      { start: new Date('2026-06-08T09:00:00.000Z'), end: new Date('2026-06-08T10:00:00.000Z') },
    ]);
    expect([noFreeReason, windowReason, noSplitReason, defaultReason]).toEqual([
      expect.any(String),
      expect.any(String),
      expect.any(String),
      expect.any(String),
    ]);
    expect(new Set([noFreeReason, windowReason, noSplitReason, defaultReason]).size).toBe(4);
    expect(
      internal.taskScore(
        taskCandidate({ dueAt: new Date('2026-06-10T08:00:00.000Z') }),
        'balanced',
        { dueSoonWeights: { within72h: 30 } },
      ),
    ).toBeGreaterThan(internal.taskScore(taskCandidate(), 'balanced', {}));
  });

  it('orders candidates by score and respects task window and split constraints', () => {
    const { service } = createService();
    const internal = service as never as {
      plan: (
        tasks: Array<Record<string, unknown>>,
        free: Array<{ start: Date; end: Date; source?: string }>,
        strategy: string,
        profile: Record<string, unknown>,
      ) => {
        planned: Array<Record<string, unknown>>;
        unplanned: Array<Record<string, unknown>>;
      };
      taskScore: (task: Record<string, unknown>, strategy: string, profile: Record<string, unknown>) => number;
    };
    const freeBlocks = [
      { start: new Date('2026-06-08T09:00:00.000Z'), end: new Date('2026-06-08T11:00:00.000Z'), source: 'window' },
    ];

    const result = internal.plan(
      [
        taskCandidate({
          id: 'low',
          title: 'Low score',
          remainingMinutes: 30,
          estimatedMinutes: 30,
          priority: 'low',
        }),
        taskCandidate({
          id: 'windowed-high',
          title: 'Windowed high score',
          remainingMinutes: 30,
          estimatedMinutes: 30,
          priority: 'urgent',
          earliestStart: new Date('2026-06-08T09:30:00.000Z'),
          latestEnd: new Date('2026-06-08T10:30:00.000Z'),
        }),
        taskCandidate({
          id: 'no-split',
          title: 'No split',
          remainingMinutes: 90,
          estimatedMinutes: 90,
          priority: 'normal',
          canSplit: false,
        }),
      ],
      freeBlocks,
      'balanced',
      { priorityWeights: { urgent: 100, low: 1 } },
    );

    expect(result.planned).toMatchObject([
      {
        task: expect.objectContaining({ id: 'windowed-high' }),
        start: new Date('2026-06-08T09:30:00.000Z'),
        end: new Date('2026-06-08T10:00:00.000Z'),
        risk: { constrainedByWindow: true },
      },
      {
        task: expect.objectContaining({ id: 'low' }),
        start: new Date('2026-06-08T10:00:00.000Z'),
        end: new Date('2026-06-08T10:30:00.000Z'),
      },
    ]);
    expect(result.unplanned).toMatchObject([
      { taskId: 'no-split', remainingMinutes: 90 },
    ]);
    expect(
      internal.taskScore(
        taskCandidate({ dueAt: new Date('2026-06-08T20:00:00.000Z'), confirmedMinutes: 15 }),
        'deadline_first',
        { actualWorkBonus: 7, deadlineFirstBonus: 13 },
      ),
    ).toBeGreaterThan(
      internal.taskScore(taskCandidate({ dueAt: new Date('2026-06-08T20:00:00.000Z') }), 'balanced', {}),
    );
    expect(
      internal.taskScore(
        taskCandidate({ dueAt: new Date('2026-06-10T08:00:00.000Z'), confirmedMinutes: 0 }),
        'deadline_first',
        { dueSoonWeights: { within72h: 31 }, deadlineFirstBonus: 11 },
      ),
    ).toBe(48);
  });

  it('normalizes reasons, LLM fallback decisions and validated fallback drafts', () => {
    const { service } = createService();
    const internal = service as never as {
      normalizePlannedReasons: (
        items: Array<Record<string, unknown>>,
        strategy: string,
      ) => Array<Record<string, unknown>>;
      normalizeUnplannedReasons: (
        items: Array<Record<string, unknown>>,
        free: Array<{ start: Date; end: Date }>,
      ) => Array<Record<string, unknown>>;
      shouldUseLlmFallback: (
        body: Record<string, unknown>,
        tasks: Array<Record<string, unknown>>,
        planned: Array<{ confidence: number }>,
        unplanned: Array<Record<string, unknown>>,
        profile: Record<string, unknown>,
      ) => boolean;
      validateLlmDrafts: (
        fallback: Record<string, unknown>,
        tasks: Array<Record<string, unknown>>,
        start: Date,
        end: Date,
        busy: Array<{ start: Date; end: Date; source: string }>,
        existing: Array<{ task: Record<string, unknown>; start: Date; end: Date }>,
      ) => {
        planned: Array<Record<string, unknown>>;
        rejected: Array<Record<string, unknown>>;
        unplanned: Array<Record<string, unknown>>;
      };
    };
    const task = taskCandidate({
      id: 'valid',
      remainingMinutes: 30,
      location: 'Desk',
      notes: 'Notes',
      dueAt: new Date('2026-06-09T09:00:00.000Z'),
    });

    expect(internal.normalizePlannedReasons([{ task, reason: { priority: 'high' } }], 'balanced')[0]).toMatchObject({
      reason: {
        priority: 'high',
        location: 'Desk',
        notes: 'Notes',
        dueAt: '2026-06-09T09:00:00.000Z',
      },
    });
    expect(
      internal.normalizeUnplannedReasons(
        [
          { taskId: 'valid', reason: 'kept reason' },
          { taskId: 'bad', reason: { nested: true } },
        ],
        [{ start: new Date('2026-06-08T09:00:00.000Z'), end: new Date('2026-06-08T10:00:00.000Z') }],
      ),
    ).toMatchObject([{ reason: 'kept reason' }, { reason: expect.any(String) }]);
    expect(internal.normalizeUnplannedReasons([{ taskId: 'none', reason: null }], [])).toMatchObject([
      { reason: expect.any(String) },
    ]);

    expect(internal.shouldUseLlmFallback({ useLlmFallback: false }, [task], [], [{ taskId: 'valid' }], {})).toBe(false);
    expect(internal.shouldUseLlmFallback({}, [task], [], [{ taskId: 'valid' }], { llmFallback: { enabled: false } })).toBe(false);
    expect(internal.shouldUseLlmFallback({ useLlmFallback: true }, [task], [], [], {})).toBe(true);
    expect(
      internal.shouldUseLlmFallback(
        {},
        [task, taskCandidate({ id: 'other' })],
        [{ confidence: 0.8 }],
        [{ taskId: 'valid' }],
        { llmFallback: { unplannedRatioThreshold: 0.5, confidenceThreshold: 0.2 } },
      ),
    ).toBe(true);
    expect(
      internal.shouldUseLlmFallback({}, [task], [{ confidence: 0.1 }], [], { llmFallback: { confidenceThreshold: 0.5 } }),
    ).toBe(true);
    expect(
      internal.shouldUseLlmFallback(
        {},
        [taskCandidate({ id: 'urgent', priority: 'urgent' })],
        [{ confidence: 0.9 }],
        [{ taskId: 'urgent' }],
        { llmFallback: { unplannedRatioThreshold: 2, confidenceThreshold: 0.5 } },
      ),
    ).toBe(true);
    expect(
      internal.shouldUseLlmFallback(
        {},
        [taskCandidate({ id: 'steady', priority: 'normal' })],
        [{ confidence: 0.9 }, { confidence: 0.8 }],
        [],
        { llmFallback: { unplannedRatioThreshold: 1, confidenceThreshold: 0.5 } },
      ),
    ).toBe(false);
    expect(
      internal.shouldUseLlmFallback(
        {},
        [taskCandidate({ id: 'missing-task-ref', priority: 'normal' })],
        [{ confidence: 0.9 }],
        [{ taskId: 'missing-in-task-list' }],
        { llmFallback: { unplannedRatioThreshold: 2, confidenceThreshold: 0.5 } },
      ),
    ).toBe(false);

    const validation = internal.validateLlmDrafts(
      {
        explanation: 'model explanation',
        draftItems: [
          {
            taskId: 'valid',
            proposedStart: '2026-06-08T10:00:00.000Z',
            proposedEnd: '2026-06-08T10:30:00.000Z',
            reason: 'valid draft',
            confidence: 2,
          },
          { taskId: 'missing', proposedStart: '2026-06-08T10:00:00.000Z', proposedEnd: '2026-06-08T10:30:00.000Z' },
          { taskId: 'locked', proposedStart: '2026-06-08T10:30:00.000Z', proposedEnd: '2026-06-08T11:00:00.000Z' },
          { taskId: 'valid', proposedStart: '2026-06-08T08:30:00.000Z', proposedEnd: '2026-06-08T09:00:00.000Z' },
          { taskId: 'windowed', proposedStart: '2026-06-08T09:00:00.000Z', proposedEnd: '2026-06-08T09:30:00.000Z' },
          { taskId: 'windowed', proposedStart: '2026-06-08T12:30:00.000Z', proposedEnd: '2026-06-08T13:00:00.000Z' },
          { taskId: 'chunked', proposedStart: '2026-06-08T10:30:00.000Z', proposedEnd: '2026-06-08T10:40:00.000Z' },
          { taskId: 'valid', proposedStart: '2026-06-08T09:40:00.000Z', proposedEnd: '2026-06-08T10:10:00.000Z' },
          { taskId: 'valid', proposedStart: '2026-06-08T11:00:00.000Z', proposedEnd: '2026-06-08T11:30:00.000Z' },
        ],
        unplanned: [{ taskId: 'still-open', reason: 'no slot' }],
      },
      [
        task,
        taskCandidate({ id: 'locked', locked: true }),
        taskCandidate({
          id: 'windowed',
          earliestStart: new Date('2026-06-08T10:00:00.000Z'),
          latestEnd: new Date('2026-06-08T12:00:00.000Z'),
        }),
        taskCandidate({ id: 'chunked', minChunkMinutes: 30, maxChunkMinutes: 60 }),
      ],
      new Date('2026-06-08T09:00:00.000Z'),
      new Date('2026-06-08T13:00:00.000Z'),
      [{ start: new Date('2026-06-08T09:30:00.000Z'), end: new Date('2026-06-08T10:00:00.000Z'), source: 'busy' }],
      [
        {
          task,
          start: new Date('2026-06-08T11:00:00.000Z'),
          end: new Date('2026-06-08T11:30:00.000Z'),
        },
      ],
    );

    expect(validation.planned).toMatchObject([
      {
        task: expect.objectContaining({ id: 'valid' }),
        confidence: 0.85,
        reason: { text: 'valid draft', modelUsed: 'llm_fallback', serverValidated: true, explanation: 'model explanation' },
        risk: { risk: 'medium', llmFallback: true },
      },
    ]);
    expect(validation.rejected.map((item) => item.reason)).toEqual([
      'invalid_task_or_time',
      'task_not_auto_schedulable',
      'outside_range',
      'before_task_time_window',
      'after_task_time_window',
      'outside_task_chunk_limits',
      'overlaps_busy_or_existing_block',
      'overlaps_busy_or_existing_block',
    ]);
    expect(validation.unplanned).toEqual([{ taskId: 'still-open', reason: 'no slot' }]);
  });

  it('defaults fallback draft fields and ignores non-array fallback collections', () => {
    const { service } = createService();
    const internal = service as never as {
      validateLlmDrafts: (
        fallback: Record<string, unknown>,
        tasks: Array<Record<string, unknown>>,
        start: Date,
        end: Date,
        busy: Array<{ start: Date; end: Date; source: string }>,
        existing: Array<{ task: Record<string, unknown>; start: Date; end: Date }>,
      ) => {
        planned: Array<Record<string, unknown>>;
        rejected: Array<Record<string, unknown>>;
        unplanned: Array<Record<string, unknown>>;
      };
      shouldUseLlmFallback: (
        body: Record<string, unknown>,
        tasks: Array<Record<string, unknown>>,
        planned: Array<{ confidence: number }>,
        unplanned: Array<Record<string, unknown>>,
        profile: Record<string, unknown>,
      ) => boolean;
      plan: (
        tasks: Array<Record<string, unknown>>,
        free: Array<{ start: Date; end: Date; source?: string }>,
        strategy: string,
        profile: Record<string, unknown>,
      ) => {
        planned: Array<Record<string, unknown>>;
        unplanned: Array<Record<string, unknown>>;
      };
      readRange: (rawStart: unknown, rawEnd: unknown) => { start: Date; end: Date };
    };
    const task = taskCandidate({ id: 'snake', minChunkMinutes: 15, maxChunkMinutes: 90 });

    expect(
      internal.validateLlmDrafts(
        { draftItems: 'not-array', unplanned: 'not-array' },
        [task],
        new Date('2026-06-08T09:00:00.000Z'),
        new Date('2026-06-08T12:00:00.000Z'),
        [],
        [],
      ),
    ).toEqual({ planned: [], rejected: [], unplanned: [] });

    const validation = internal.validateLlmDrafts(
      {
        draftItems: [
          {
            task_id: 'snake',
            proposed_start: '2026-06-08T09:15:00.000Z',
            proposed_end: '2026-06-08T09:45:00.000Z',
            risk: 'low',
          },
          {
            task_id: 'snake',
            proposed_start: '2026-06-08T10:00:00.000Z',
            proposed_end: '2026-06-08T10:30:00.000Z',
            confidence: -1,
          },
        ],
      },
      [task],
      new Date('2026-06-08T09:00:00.000Z'),
      new Date('2026-06-08T12:00:00.000Z'),
      [],
      [],
    );

    expect(validation.planned).toMatchObject([
      {
        task: expect.objectContaining({ id: 'snake' }),
        confidence: 0.62,
        reason: { text: 'LLM fallback draft', explanation: null },
        risk: { risk: 'low', llmFallback: true },
      },
      {
        task: expect.objectContaining({ id: 'snake' }),
        confidence: 0.1,
        reason: { text: 'LLM fallback draft' },
        risk: { risk: 'medium', llmFallback: true },
      },
    ]);
    expect(validation.rejected).toEqual([]);
    expect(internal.shouldUseLlmFallback({}, [], [], [{ taskId: 'ghost' }], {
      llmFallback: { unplannedRatioThreshold: 1, confidenceThreshold: 1 },
    })).toBe(true);
    expect(internal.plan([taskCandidate({ id: 'finished', remainingMinutes: 0 })], [], 'balanced', {})).toEqual({
      planned: [],
      unplanned: [],
    });
    expect(internal.readRange(undefined, undefined)).toEqual({
      start: new Date('2026-06-08T08:00:00.000Z'),
      end: new Date('2026-06-08T14:00:00.000Z'),
    });
    expect(internal.readRange('2026-06-08T09:30:00.000Z', undefined)).toEqual({
      start: new Date('2026-06-08T09:30:00.000Z'),
      end: new Date('2026-06-08T15:30:00.000Z'),
    });
  });
});
