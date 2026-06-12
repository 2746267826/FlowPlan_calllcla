import { BadRequestException } from '@nestjs/common';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { encrypt, encryptionKey } from '../common/utils';
import { ModelsService, ScheduleFallbackInput } from './models.service';

const context = {
  userId: '00000000-0000-4000-8000-000000000001',
  deviceId: '00000000-0000-4000-8000-000000000101',
};

function createSqlMock(options: {
  provider?: Record<string, unknown> | null;
  listRows?: unknown[];
  versionRows?: unknown[];
  runRows?: unknown[];
  evalRows?: unknown[];
  definitionRows?: unknown[];
  activeVersionRows?: unknown[];
  feedbackRows?: unknown[];
  insertFeedbackRow?: Record<string, unknown>;
  learnedVersionRow?: Record<string, unknown>;
  activateRows?: unknown[];
} = {}) {
  const query = vi.fn(async (sql: string, params?: unknown[]) => {
    if (sql.includes('INSERT INTO model_definitions')) {
      return { rows: [{ id: `definition-${params?.[1]}` }] };
    }
    if (sql.includes('INSERT INTO model_versions') && sql.includes("'draft'")) {
      return {
        rows: [
          options.learnedVersionRow ?? {
            id: 'version-learned',
            versionKey: 'learned-version',
            status: 'draft',
            ruleProfile: {},
          },
        ],
      };
    }
    if (sql.includes('INSERT INTO model_versions')) {
      return { rows: [] };
    }
    if (sql.includes('FROM ai_provider_configs')) {
      return { rows: options.provider ? [options.provider] : [] };
    }
    if (sql.includes('FROM model_definitions') && sql.includes('LEFT JOIN model_versions')) {
      return { rows: options.listRows ?? [{ modelKey: 'scheduler.v1' }] };
    }
    if (sql.includes('FROM model_versions v') && sql.includes('ORDER BY v.created_at DESC')) {
      return { rows: options.versionRows ?? [{ versionKey: 'default-v1' }] };
    }
    if (sql.includes('FROM model_runs')) {
      return { rows: options.runRows ?? [{ id: 'run-1', status: 'succeeded' }] };
    }
    if (sql.includes('FROM model_eval_cases')) {
      return { rows: options.evalRows ?? [{ status: 'active' }, { status: 'archived' }] };
    }
    if (sql.includes('FROM model_feedback_events')) {
      return { rows: options.feedbackRows ?? [] };
    }
    if (sql.includes('INSERT INTO model_feedback_events')) {
      return {
        rows: sql.includes('RETURNING')
          ? [
              options.insertFeedbackRow ?? {
                id: 'feedback-1',
                createdAt: '2026-01-01T00:00:00.000Z',
              },
            ]
          : [],
      };
    }
    if (sql.includes('INSERT INTO model_eval_cases')) {
      return { rows: [] };
    }
    if (sql.includes('INSERT INTO model_rule_change_drafts')) {
      return { rows: [] };
    }
    if (sql.includes('INSERT INTO audit_logs')) {
      return { rows: [] };
    }
    if (sql.includes('UPDATE model_versions') && sql.includes('RETURNING id::text AS id')) {
      return {
        rows: options.activateRows ?? [
          { id: params?.[2], versionKey: 'draft-v2', status: 'active' },
        ],
      };
    }
    if (sql.includes('WHERE user_id = $1 AND model_key = $2') && sql.includes('FROM model_definitions')) {
      return { rows: options.definitionRows ?? [{ id: 'definition-scheduler', modelKey: params?.[1] }] };
    }
    if (sql.includes('WHERE v.user_id = $1') && sql.includes("v.status = 'active'")) {
      return {
        rows: options.activeVersionRows ?? [
          {
            versionId: 'version-1',
            versionKey: 'default-v1',
            ruleProfile: { learnedAdjustments: {} },
          },
        ],
      };
    }
    if (sql.includes('INSERT INTO model_runs')) {
      return { rows: [{ id: 'run-1' }] };
    }
    return { rows: [] };
  });
  const transaction = vi.fn(async (callback: (client: { query: typeof query }) => unknown) =>
    callback({ query }),
  );
  return { query, transaction };
}

const devices = {
  ensureUser: vi.fn(async (userId: string) => userId),
  ensureDevice: vi.fn(async () => context.deviceId),
};

function fallbackInput(): ScheduleFallbackInput {
  return {
    rangeStart: new Date('2026-01-01T09:00:00Z'),
    rangeEnd: new Date('2026-01-01T17:00:00Z'),
    tasks: [{ id: 'task-1', title: 'Plan' }],
    busyBlocks: [],
    freeBlocks: [],
    unplanned: [{ id: 'task-2', title: 'Later' }],
    strategy: 'balanced',
    profile: { minChunkMinutes: 30 },
  };
}

describe('ModelsService', () => {
  const oldEnv = { ...process.env };

  beforeEach(() => {
    process.env = { ...oldEnv, FLOWPLANV2_ENCRYPTION_KEY: 'models-unit-test-secret' };
  });

  afterEach(() => {
    process.env = oldEnv;
    vi.unstubAllGlobals();
  });

  it('ensures default models before listing model definitions', async () => {
    const database = createSqlMock({
      listRows: [{ modelKey: 'scheduler.v1', displayName: 'Scheduler' }],
    });
    const service = new ModelsService(database as never, devices as never);

    const result = await service.list(context);

    expect(result).toEqual({
      items: [{ modelKey: 'scheduler.v1', displayName: 'Scheduler' }],
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO model_definitions'),
      expect.arrayContaining([context.userId, 'scheduler.v1']),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('LEFT JOIN model_versions'),
      [context.userId],
    );
  });

  it('returns provider health when no AI provider is configured', async () => {
    const database = createSqlMock({ provider: null });
    const service = new ModelsService(database as never, devices as never);

    await expect(service.llmHealth(context)).resolves.toEqual({
      configured: false,
      online: false,
      reason: 'AI Provider is not configured.',
    });
  });

  it('returns provider health for configured but disabled providers', async () => {
    const database = createSqlMock({
      provider: {
        provider_key: 'openai-main',
        provider_type: 'openai_compatible',
        model: 'gpt-test',
        status: 'disabled',
        api_key_ciphertext: 'ciphertext',
        last_tested_at: '2026-01-01T00:00:00Z',
        last_error: 'quota',
      },
    });
    const service = new ModelsService(database as never, devices as never);

    await expect(service.llmHealth(context)).resolves.toEqual({
      configured: true,
      online: false,
      providerKey: 'openai-main',
      providerType: 'openai_compatible',
      model: 'gpt-test',
      status: 'disabled',
      lastTestedAt: '2026-01-01T00:00:00Z',
      lastError: 'quota',
    });
  });

  it('returns configured online health when the default provider is enabled with an API key', async () => {
    const database = createSqlMock({
      provider: {
        provider_key: 'openai-main',
        provider_type: 'openai_compatible',
        model: 'gpt-test',
        status: 'enabled',
        api_key_ciphertext: 'ciphertext',
        last_tested_at: null,
        last_error: null,
      },
    });
    const service = new ModelsService(database as never, devices as never);

    await expect(service.llmHealth(context)).resolves.toMatchObject({
      configured: true,
      online: true,
      providerKey: 'openai-main',
      providerType: 'openai_compatible',
      model: 'gpt-test',
      status: 'enabled',
    });
  });

  it('reports configured providers offline when the enabled default provider has no API key', async () => {
    const database = createSqlMock({
      provider: {
        provider_key: 'openai-main',
        provider_type: 'openai_compatible',
        model: 'gpt-test',
        status: 'enabled',
        api_key_ciphertext: null,
        last_tested_at: null,
        last_error: null,
      },
    });
    const service = new ModelsService(database as never, devices as never);

    await expect(service.llmHealth(context)).resolves.toMatchObject({
      configured: true,
      online: false,
      providerKey: 'openai-main',
      providerType: 'openai_compatible',
      model: 'gpt-test',
      status: 'enabled',
    });
  });

  it('lists versions and runs with normalized limits and status filters', async () => {
    const database = createSqlMock({
      versionRows: [{ versionKey: 'default-v1', status: 'active' }],
      runRows: [{ id: 'run-1', status: 'failed' }],
    });
    const service = new ModelsService(database as never, devices as never);

    await expect(service.versions('scheduler.v1', context)).resolves.toEqual({
      modelKey: 'scheduler.v1',
      items: [{ versionKey: 'default-v1', status: 'active' }],
    });
    await expect(service.runs('scheduler.v1', { limit: '999', status: 'failed' }, context)).resolves.toEqual({
      modelKey: 'scheduler.v1',
      items: [{ id: 'run-1', status: 'failed' }],
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('FROM model_runs'),
      [context.userId, 'scheduler.v1', 'failed', 300],
    );
  });

  it('lists runs with default pagination and no status filter when query values are blank', async () => {
    const database = createSqlMock({ runRows: [] });
    const service = new ModelsService(database as never, devices as never);

    await expect(service.runs('scheduler.v1', { limit: 'bad', status: '   ' }, context)).resolves.toEqual({
      modelKey: 'scheduler.v1',
      items: [],
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('FROM model_runs'),
      [context.userId, 'scheduler.v1', null, 80],
    );
  });

  it('requires a confirmation token before activating a model version', async () => {
    const database = createSqlMock();
    const service = new ModelsService(database as never, devices as never);

    await expect(
      service.activate('scheduler.v1', 'version-1', { confirmationToken: 'NOPE' }, context),
    ).rejects.toBeInstanceOf(BadRequestException);
    expect(database.query).not.toHaveBeenCalled();
  });

  it('activates a model version inside a transaction and records an audit entry', async () => {
    const database = createSqlMock();
    const service = new ModelsService(database as never, devices as never);

    await expect(
      service.activate('scheduler.v1', 'version-2', { confirmationToken: ' CONFIRM ', reason: 'stable' }, context),
    ).resolves.toEqual({
      ok: true,
      modelKey: 'scheduler.v1',
      version: { id: 'version-2', versionKey: 'draft-v2', status: 'active' },
    });

    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'archived'"),
      [context.userId, 'definition-scheduler'],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'active'"),
      [context.userId, 'definition-scheduler', 'version-2'],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([
        context.userId,
        context.deviceId,
        'model.version.activate',
        'scheduler.v1',
        null,
        'model.version.activate',
        expect.stringContaining('"reason":"stable"'),
      ]),
    );
  });

  it('rejects activation when the requested version does not exist', async () => {
    const database = createSqlMock({ activateRows: [] });
    const service = new ModelsService(database as never, devices as never);

    await expect(
      service.activate('scheduler.v1', 'missing-version', { confirmationToken: 'CONFIRM' }, context),
    ).rejects.toThrow('model version not found.');
  });

  it('evaluates feedback cases and stores metrics on the active version', async () => {
    const database = createSqlMock({
      evalRows: [{ status: 'active' }, { status: 'archived' }, { status: 'active' }],
    });
    const service = new ModelsService(database as never, devices as never);

    const result = await service.evaluate('scheduler.v1', { limit: '2' }, context);

    expect(result).toMatchObject({
      ok: true,
      modelKey: 'scheduler.v1',
      metrics: {
        evalCaseCount: 3,
        acceptedFeedbackCount: 2,
        versionKey: 'default-v1',
      },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE model_versions'),
      [context.userId, 'version-1', expect.stringContaining('"evalCaseCount":3')],
    );
  });

  it('rejects unknown models and missing active versions', async () => {
    const unknownModel = createSqlMock({ definitionRows: [] });
    await expect(
      new ModelsService(unknownModel as never, devices as never).feedback(
        'missing.v1',
        { feedbackType: 'accepted' },
        context,
      ),
    ).rejects.toThrow('unknown model: missing.v1');

    const noActiveVersion = createSqlMock({ activeVersionRows: [] });
    await expect(
      new ModelsService(noActiveVersion as never, devices as never).evaluate(
        'scheduler.v1',
        {},
        context,
      ),
    ).rejects.toThrow('no active version for model: scheduler.v1');
  });

  it('returns the active profile for a model after seeding default models', async () => {
    const database = createSqlMock({
      activeVersionRows: [
        {
          versionId: 'active-version',
          versionKey: 'default-v1',
          ruleProfile: { minChunkMinutes: 15 },
        },
      ],
    });
    const service = new ModelsService(database as never, devices as never);

    await expect(service.activeProfile(context.userId, 'scheduler.v1')).resolves.toEqual({
      versionId: 'active-version',
      versionKey: 'default-v1',
      ruleProfile: { minChunkMinutes: 15 },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("v.status = 'active'"),
      [context.userId, 'scheduler.v1'],
    );
  });

  it('rejects feedback when feedbackType and type are both blank', async () => {
    const database = createSqlMock();
    const service = new ModelsService(database as never, devices as never);

    await expect(
      service.feedback('scheduler.v1', { feedbackType: '   ', type: '' }, context),
    ).rejects.toThrow('feedbackType is required.');
    expect(database.transaction).not.toHaveBeenCalled();
  });

  it('records feedback, creates an eval case, and audits the event in one transaction', async () => {
    const database = createSqlMock({
      insertFeedbackRow: { id: 'feedback-9', createdAt: '2026-01-02T00:00:00.000Z' },
    });
    const service = new ModelsService(database as never, devices as never);

    await expect(
      service.feedback(
        'scheduler.v1',
        {
          type: 'accepted',
          modelRunId: 'run-7',
          targetType: 'task',
          targetId: 'task-1',
          payload: { score: 1 },
          outcome: 'confirmed',
          source: 'manual',
          inputSnapshot: { before: true },
        },
        context,
      ),
    ).resolves.toEqual({
      ok: true,
      feedback: { id: 'feedback-9', createdAt: '2026-01-02T00:00:00.000Z' },
    });

    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO model_feedback_events'),
      [
        context.userId,
        context.deviceId,
        'definition-scheduler',
        'scheduler.v1',
        'run-7',
        'task',
        'task-1',
        'accepted',
        JSON.stringify({ score: 1 }),
        'confirmed',
        'manual',
      ],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO model_eval_cases'),
      expect.arrayContaining([
        context.userId,
        'definition-scheduler',
        'scheduler.v1',
        expect.stringMatching(/^feedback:/),
        JSON.stringify({ before: true }),
        JSON.stringify({
          feedbackType: 'accepted',
          targetType: 'task',
          targetId: 'task-1',
          payload: { score: 1 },
        }),
      ]),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([
        context.userId,
        context.deviceId,
        'model.feedback.record',
        'scheduler.v1',
        'task-1',
        'model.feedback.record',
        expect.stringContaining('"feedbackType":"accepted"'),
      ]),
    );
  });

  it('records client feedback with payload, outcome, and source defaults', async () => {
    const database = createSqlMock({
      insertFeedbackRow: { id: 'feedback-defaults', createdAt: '2026-01-02T00:00:00.000Z' },
    });
    const service = new ModelsService(database as never, devices as never);

    await expect(
      service.feedback(
        'scheduler.v1',
        {
          feedbackType: 'modified',
          targetType: 'task',
          targetId: 'task-defaults',
          payload: { reason: 'dragged later' },
        },
        context,
      ),
    ).resolves.toMatchObject({
      ok: true,
      feedback: { id: 'feedback-defaults' },
    });

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO model_feedback_events'),
      [
        context.userId,
        context.deviceId,
        'definition-scheduler',
        'scheduler.v1',
        null,
        'task',
        'task-defaults',
        'modified',
        JSON.stringify({ reason: 'dragged later' }),
        'modified',
        'client',
      ],
    );
  });

  it('skips eval case insertion when feedback type is unavailable', async () => {
    const database = createSqlMock();
    const service = new ModelsService(database as never, devices as never);
    const client = { query: vi.fn(async () => ({ rows: [] })) };

    await (
      service as unknown as {
        insertEvalCase: (
          client: typeof client,
          userId: string,
          definitionId: string,
          modelKey: string,
          body: Record<string, unknown>,
        ) => Promise<void>;
      }
    ).insertEvalCase(client, context.userId, 'definition-scheduler', 'scheduler.v1', {
      feedbackPayload: { score: 0 },
      targetType: 'task',
    });

    expect(client.query).not.toHaveBeenCalled();
  });

  it('inserts an eval case when feedback type is available', async () => {
    const database = createSqlMock();
    const service = new ModelsService(database as never, devices as never);
    const client = { query: vi.fn(async () => ({ rows: [] })) };

    await (
      service as unknown as {
        insertEvalCase: (
          client: typeof client,
          userId: string,
          definitionId: string,
          modelKey: string,
          body: Record<string, unknown>,
        ) => Promise<void>;
      }
    ).insertEvalCase(client, context.userId, 'definition-scheduler', 'scheduler.v1', {
      feedbackType: 'rejected',
      inputSnapshot: { taskId: 'task-1', before: true },
      targetType: 'task',
      targetId: 'task-1',
      feedbackPayload: { reason: 'bad slot' },
    });

    expect(client.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO model_eval_cases'),
      [
        context.userId,
        'definition-scheduler',
        'scheduler.v1',
        expect.stringMatching(/^feedback:/),
        JSON.stringify({ taskId: 'task-1', before: true }),
        JSON.stringify({
          feedbackType: 'rejected',
          targetType: 'task',
          targetId: 'task-1',
          payload: { reason: 'bad slot' },
        }),
      ],
    );
  });

  it('starts and completes model runs with version metadata', async () => {
    const database = createSqlMock();
    const service = new ModelsService(database as never, devices as never);

    await expect(
      service.startRun(context.userId, 'scheduler.v1', {
        source: 'scheduler',
        targetType: 'task',
        targetId: 'task-1',
        inputSummary: { taskCount: 1 },
      }),
    ).resolves.toEqual({
      id: 'run-1',
      version: {
        versionId: 'version-1',
        versionKey: 'default-v1',
        ruleProfile: { learnedAdjustments: {} },
      },
    });

    await service.completeRun(context.userId, 'run-1', {
      status: 'succeeded',
      outputSummary: { scheduled: 1 },
      confidence: 0.91,
      usedLlm: true,
      llmProviderKey: 'openai-main',
      llmModel: 'gpt-test',
    });

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE model_runs'),
      [
        context.userId,
        'run-1',
        'succeeded',
        JSON.stringify({ scheduled: 1 }),
        0.91,
        null,
        true,
        'openai-main',
        'gpt-test',
      ],
    );
  });

  it('defaults optional startRun and completeRun fields to null or false', async () => {
    const database = createSqlMock();
    const service = new ModelsService(database as never, devices as never);

    await service.startRun(context.userId, 'scheduler.v1', {
      source: 'scheduler',
      inputSummary: { taskCount: 0 },
    });
    await service.completeRun(context.userId, 'run-2', {
      status: 'failed',
      outputSummary: { scheduled: 0 },
      failureReason: 'no slots',
    });

    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO model_runs'),
      [
        context.userId,
        'definition-scheduler',
        'version-1',
        'scheduler.v1',
        'default-v1',
        'scheduler',
        null,
        null,
        JSON.stringify({ taskCount: 0 }),
      ],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE model_runs'),
      [
        context.userId,
        'run-2',
        'failed',
        JSON.stringify({ scheduled: 0 }),
        null,
        'no slots',
        false,
        null,
        null,
      ],
    );
  });

  it('records service feedback with default outcome and source on an existing transaction client', async () => {
    const database = createSqlMock();
    const service = new ModelsService(database as never, devices as never);
    const client = { query: vi.fn(async () => ({ rows: [] })) };

    await service.recordFeedback(client as never, context.userId, context.deviceId, 'scheduler.v1', {
      targetType: 'task',
      targetId: 'task-1',
      feedbackPayload: { accepted: true },
    });

    expect(client.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO model_feedback_events'),
      [
        context.userId,
        context.deviceId,
        'definition-scheduler',
        'scheduler.v1',
        null,
        'task',
        'task-1',
        'accepted',
        JSON.stringify({ accepted: true }),
        'accepted',
        'service',
      ],
    );
  });

  it('records service feedback from payload when feedbackPayload is absent', async () => {
    const database = createSqlMock();
    const service = new ModelsService(database as never, devices as never);
    const client = { query: vi.fn(async () => ({ rows: [] })) };

    await service.recordFeedback(client as never, context.userId, context.deviceId, 'scheduler.v1', {
      feedbackType: 'rejected',
      payload: { reason: 'too early' },
      outcome: 'declined',
      source: 'automation',
    });

    expect(client.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO model_feedback_events'),
      [
        context.userId,
        context.deviceId,
        'definition-scheduler',
        'scheduler.v1',
        null,
        null,
        null,
        'rejected',
        JSON.stringify({ reason: 'too early' }),
        'declined',
        'automation',
      ],
    );
  });

  it('learns from scheduler feedback and auto-activates low-risk profiles by default', async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-02-03T04:05:06.000Z'));
    const database = createSqlMock({
      feedbackRows: [
        { feedbackType: 'accepted', outcome: null, payload: {} },
        { feedbackType: 'rejected', outcome: null, payload: {} },
        { feedbackType: 'modified', outcome: null, payload: {} },
      ],
      learnedVersionRow: {
        id: 'version-learned',
        versionKey: 'learned-20260203040506',
        status: 'draft',
        ruleProfile: { learnedAdjustments: { nightPenalty: 0.25 } },
      },
    });
    const service = new ModelsService(database as never, devices as never);

    const result = await service.learn('scheduler.v1', {}, context);

    expect(result.learned.profile).toMatchObject({
      learnedAdjustments: {
        acceptedSampleCount: 2,
        rejectedSampleCount: 1,
        nightPenalty: 0.25,
        confidenceBonus: 0.01,
      },
    });
    expect(result).toMatchObject({
      ok: true,
      modelKey: 'scheduler.v1',
      version: {
        id: 'version-learned',
        versionKey: 'learned-20260203040506',
      },
      learned: {
        summary: 'Based on 3 feedback events: 2 accepted/modified, 1 rejected.',
        metrics: {
          feedbackCount: 3,
          acceptedCount: 2,
          rejectedCount: 1,
        },
      },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("VALUES ($1, $2, $3, 'draft'"),
      expect.arrayContaining([
        context.userId,
        'definition-scheduler',
        'learned-20260203040506',
        expect.stringContaining('"nightPenalty":0.25'),
        expect.stringContaining('"acceptedCount":2'),
      ]),
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'archived'"),
      [context.userId, 'definition-scheduler', 'version-learned'],
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'active'"),
      [context.userId, 'version-learned'],
    );
  });

  it('keeps high-risk learned drafts in review with medium risk', async () => {
    const database = createSqlMock({
      feedbackRows: [{ feedbackType: 'rejected', outcome: null, payload: {} }],
      activeVersionRows: [
        {
          versionId: 'version-large',
          versionKey: 'default-v1',
          ruleProfile: {
            learnedAdjustments: {},
            largePolicy: 'x'.repeat(21000),
          },
        },
      ],
    });
    const service = new ModelsService(database as never, devices as never);

    const result = await service.learn('scheduler.v1', { autoActivate: false }, context);

    expect(result.learned.metrics.feedbackCount).toBe(1);
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO model_rule_change_drafts'),
      expect.arrayContaining([
        context.userId,
        'definition-scheduler',
        'scheduler.v1',
        'version-learned',
        expect.any(String),
        'Based on 1 feedback events: 0 accepted/modified, 1 rejected.',
        'medium',
      ]),
    );
  });

  it('applies learning defaults when samples do not outnumber rejects or thresholds are absent', () => {
    const service = new ModelsService(createSqlMock() as never, devices as never);
    const schedulerLearned = (
      service as unknown as {
        applyFeedbackLearning: (
          modelKey: string,
          profile: Record<string, unknown>,
          feedback: Array<Record<string, unknown>>,
        ) => { profile: Record<string, unknown> };
      }
    ).applyFeedbackLearning(
      'scheduler.v1',
      { learnedAdjustments: { confidenceBonus: 0.02 } },
      [{ feedbackType: 'rejected' }],
    );
    const activityLearned = (
      service as unknown as {
        applyFeedbackLearning: (
          modelKey: string,
          profile: Record<string, unknown>,
          feedback: Array<Record<string, unknown>>,
        ) => { profile: Record<string, unknown> };
      }
    ).applyFeedbackLearning(
      'activity_merge.v1',
      { learnedAdjustments: {} },
      [{ feedbackType: 'accepted' }],
    );

    expect(schedulerLearned.profile).toMatchObject({
      learnedAdjustments: {
        confidenceBonus: 0.02,
        acceptedSampleCount: 0,
        rejectedSampleCount: 1,
      },
    });
    expect(activityLearned.profile).toMatchObject({
      taskMatchThreshold: 24,
      learnedAdjustments: {
        acceptedSampleCount: 1,
        rejectedSampleCount: 0,
      },
    });
  });

  it('creates a review draft instead of auto-activating learned profiles when requested', async () => {
    const database = createSqlMock({
      feedbackRows: [{ feedbackType: 'rejected', outcome: null, payload: {} }],
      activeVersionRows: [
        {
          versionId: 'version-activity',
          versionKey: 'default-v1',
          ruleProfile: { taskMatchThreshold: 25, learnedAdjustments: {} },
        },
      ],
    });
    const service = new ModelsService(database as never, devices as never);

    const result = await service.learn('activity_merge.v1', { autoActivate: false }, context);

    expect(result.learned.profile).toMatchObject({
      taskMatchThreshold: 27,
      learnedAdjustments: {
        acceptedSampleCount: 0,
        rejectedSampleCount: 1,
      },
    });
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO model_rule_change_drafts'),
      expect.arrayContaining([
        context.userId,
        'definition-scheduler',
        'activity_merge.v1',
        'version-learned',
        expect.stringContaining('activity_merge.v1'),
        'Based on 1 feedback events: 0 accepted/modified, 1 rejected.',
        'low',
        expect.stringContaining('"taskMatchThreshold":27'),
        'feedback_learning',
      ]),
    );
  });

  it('lowers the activity merge threshold when accepted feedback outnumbers rejected feedback', async () => {
    const database = createSqlMock({
      feedbackRows: [
        { feedbackType: 'accepted', outcome: null, payload: {} },
        { feedbackType: null, outcome: 'confirmed', payload: {} },
        { feedbackType: 'rejected', outcome: null, payload: {} },
      ],
      activeVersionRows: [
        {
          versionId: 'version-activity',
          versionKey: 'default-v1',
          ruleProfile: { taskMatchThreshold: 25, learnedAdjustments: {} },
        },
      ],
    });
    const service = new ModelsService(database as never, devices as never);

    const result = await service.learn('activity_merge.v1', { autoActivate: false }, context);

    expect(result.learned.profile).toMatchObject({
      taskMatchThreshold: 24,
      learnedAdjustments: {
        acceptedSampleCount: 2,
        rejectedSampleCount: 1,
      },
    });
    expect(result.learned.summary).toBe(
      'Based on 3 feedback events: 2 accepted/modified, 1 rejected.',
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO model_rule_change_drafts'),
      expect.arrayContaining([
        context.userId,
        'definition-scheduler',
        'activity_merge.v1',
        'version-learned',
        expect.stringContaining('activity_merge.v1'),
        'Based on 3 feedback events: 2 accepted/modified, 1 rejected.',
        'low',
        expect.stringContaining('"taskMatchThreshold":24'),
        'feedback_learning',
      ]),
    );
  });

  it('records generic learned sample counts for non-scheduler and non-activity models', async () => {
    const database = createSqlMock({
      feedbackRows: [
        { feedbackType: 'accepted', outcome: null, payload: {} },
        { feedbackType: null, outcome: 'declined', payload: {} },
      ],
      activeVersionRows: [
        {
          versionId: 'version-report',
          versionKey: 'default-v1',
          ruleProfile: { templateFirst: true, learnedAdjustments: {} },
        },
      ],
    });
    const service = new ModelsService(database as never, devices as never);

    const result = await service.learn('report_template.v1', { autoActivate: false }, context);

    expect(result.learned.profile).toMatchObject({
      templateFirst: true,
      learnedAdjustments: {
        acceptedSampleCount: 1,
        rejectedSampleCount: 1,
      },
    });
    expect(result.learned.summary).toBe(
      'Based on 2 feedback events: 1 accepted/modified, 1 rejected.',
    );
    expect(database.query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO model_rule_change_drafts'),
      expect.arrayContaining([
        context.userId,
        'definition-scheduler',
        'report_template.v1',
        'version-learned',
        expect.stringContaining('report_template.v1'),
        'Based on 2 feedback events: 1 accepted/modified, 1 rejected.',
        'low',
        expect.stringContaining('"acceptedSampleCount":1'),
        'feedback_learning',
      ]),
    );
  });

  it('does not call an LLM when fallback provider is disabled or missing its API key', async () => {
    const disabled = new ModelsService(
      createSqlMock({ provider: null }) as never,
      devices as never,
    );
    await expect(disabled.scheduleFallback(context.userId, fallbackInput())).resolves.toEqual({
      used: false,
      reason: 'AI provider is not enabled.',
      draftItems: [],
      unplanned: [{ id: 'task-2', title: 'Later' }],
    });

    const missingKey = new ModelsService(
      createSqlMock({
        provider: {
          provider_key: 'openai-main',
          provider_type: 'openai_compatible',
          base_url: 'https://example.test',
          model: 'gpt-test',
          status: 'enabled',
          api_key_ciphertext: null,
        },
      }) as never,
      devices as never,
    );
    await expect(missingKey.scheduleFallback(context.userId, fallbackInput())).resolves.toEqual({
      used: false,
      reason: 'AI provider API key is missing.',
      draftItems: [],
      unplanned: [{ id: 'task-2', title: 'Later' }],
    });
  });

  it('calls an OpenAI-compatible provider and parses strict JSON fallback drafts', async () => {
    const database = createSqlMock({
      provider: {
        provider_key: 'openai-main',
        provider_type: 'openai_compatible',
        base_url: 'https://example.test/',
        model: 'gpt-test',
        status: 'enabled',
        api_key_ciphertext: encrypt('unit-api-key', encryptionKey()),
        temperature: '0.7',
        max_output_tokens: '512',
        options: { response_format: { type: 'json_object' } },
      },
    });
    const fetchMock = vi.fn(async () => ({
      ok: true,
      status: 200,
      text: vi.fn(async () =>
        JSON.stringify({
          choices: [
            {
              message: {
                content: JSON.stringify({
                  draftItems: [
                    {
                      taskId: 'task-1',
                      proposedStart: '2026-01-01T09:00:00.000Z',
                      proposedEnd: '2026-01-01T10:00:00.000Z',
                      confidence: 0.8,
                    },
                  ],
                  unplanned: [{ taskId: 'task-2', reason: 'outside range' }],
                  explanation: 'drafted',
                }),
              },
            },
          ],
        }),
      ),
    }));
    vi.stubGlobal('fetch', fetchMock);
    const service = new ModelsService(database as never, devices as never);

    const result = await service.scheduleFallback(context.userId, fallbackInput());

    expect(result).toMatchObject({
      used: true,
      providerKey: 'openai-main',
      model: 'gpt-test',
      draftItems: [
        {
          taskId: 'task-1',
          proposedStart: '2026-01-01T09:00:00.000Z',
          proposedEnd: '2026-01-01T10:00:00.000Z',
          confidence: 0.8,
        },
      ],
      unplanned: [{ taskId: 'task-2', reason: 'outside range' }],
      explanation: 'drafted',
    });
    expect(fetchMock).toHaveBeenCalledWith(
      'https://example.test/chat/completions',
      expect.objectContaining({
        method: 'POST',
        headers: {
          authorization: 'Bearer unit-api-key',
          'content-type': 'application/json',
        },
      }),
    );
    expect(JSON.parse(String(fetchMock.mock.calls[0][1]?.body))).toMatchObject({
      model: 'gpt-test',
      temperature: 0.7,
      max_tokens: 512,
      response_format: { type: 'json_object' },
      messages: [
        expect.objectContaining({ role: 'system' }),
        expect.objectContaining({ role: 'user' }),
      ],
    });
  });

  it('parses embedded model JSON and accepts snake_case draft items', async () => {
    const database = createSqlMock({
      provider: {
        provider_key: 'openai-main',
        provider_type: 'openai_compatible',
        base_url: 'https://example.test',
        model: 'gpt-test',
        status: 'enabled',
        api_key_ciphertext: encrypt('unit-api-key', encryptionKey()),
        temperature: 'not-a-number',
        max_output_tokens: 'not-a-number',
        options: {},
      },
    });
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: true,
        status: 200,
        text: vi.fn(async () =>
          JSON.stringify({
            choices: [
              {
                message: {
                  content: 'Here is the draft: {"draft_items":[{"taskId":"task-1"}],"unplanned":[]}',
                },
              },
            ],
          }),
        ),
      })),
    );
    const service = new ModelsService(database as never, devices as never);

    await expect(service.scheduleFallback(context.userId, fallbackInput())).resolves.toMatchObject({
      used: true,
      draftItems: [{ taskId: 'task-1' }],
      unplanned: [],
      explanation: 'Here is the draft: {"draft_items":[{"taskId":"task-1"}],"unplanned":[]}',
    });
    expect(JSON.parse(String(vi.mocked(global.fetch).mock.calls[0][1]?.body))).toMatchObject({
      temperature: 0.2,
      max_tokens: 1600,
    });
  });

  it('falls back to raw explanation when model content has no JSON object', async () => {
    const database = createSqlMock({
      provider: {
        provider_key: 'openai-main',
        provider_type: 'openai_compatible',
        base_url: 'https://example.test',
        model: 'gpt-test',
        status: 'enabled',
        api_key_ciphertext: encrypt('unit-api-key', encryptionKey()),
        temperature: 0.2,
        max_output_tokens: 1600,
        options: {},
      },
    });
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: true,
        status: 200,
        text: vi.fn(async () =>
          JSON.stringify({
            choices: [{ message: { content: 'No schedule JSON available.' } }],
          }),
        ),
      })),
    );
    const service = new ModelsService(database as never, devices as never);

    await expect(service.scheduleFallback(context.userId, fallbackInput())).resolves.toMatchObject({
      used: true,
      draftItems: [],
      unplanned: [],
      explanation: 'No schedule JSON available.',
    });
  });

  it('returns empty draft data when embedded model JSON is malformed', async () => {
    const database = createSqlMock({
      provider: {
        provider_key: 'openai-main',
        provider_type: 'openai_compatible',
        base_url: 'https://example.test',
        model: 'gpt-test',
        status: 'enabled',
        api_key_ciphertext: encrypt('unit-api-key', encryptionKey()),
        temperature: 0.2,
        max_output_tokens: 1600,
        options: {},
      },
    });
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: true,
        status: 200,
        text: vi.fn(async () =>
          JSON.stringify({
            choices: [
              {
                message: {
                  content: 'Malformed draft: {"draftItems":[{"taskId":"task-1"}',
                },
              },
            ],
          }),
        ),
      })),
    );
    const service = new ModelsService(database as never, devices as never);

    await expect(service.scheduleFallback(context.userId, fallbackInput())).resolves.toMatchObject({
      used: true,
      raw: 'Malformed draft: {"draftItems":[{"taskId":"task-1"}',
      draftItems: [],
      unplanned: [],
      explanation: 'Malformed draft: {"draftItems":[{"taskId":"task-1"}',
    });
  });

  it('returns a safe fallback result when the provider request fails or returns empty content', async () => {
    const input = fallbackInput();
    const provider = {
      provider_key: 'openai-main',
      provider_type: 'openai_compatible',
      base_url: 'https://example.test',
      model: 'gpt-test',
      status: 'enabled',
      api_key_ciphertext: encrypt('unit-api-key', encryptionKey()),
      temperature: 0.2,
      max_output_tokens: 1600,
      options: {},
    };

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: false,
        status: 429,
        text: vi.fn(async () => 'rate limited'),
      })),
    );
    await expect(
      new ModelsService(createSqlMock({ provider }) as never, devices as never).scheduleFallback(context.userId, input),
    ).resolves.toEqual({
      used: false,
      providerKey: 'openai-main',
      model: 'gpt-test',
      reason: 'AI API 429: rate limited',
      draftItems: [],
      unplanned: input.unplanned,
    });

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: true,
        status: 200,
        text: vi.fn(async () => JSON.stringify({ choices: [{ message: { content: '   ' } }] })),
      })),
    );
    await expect(
      new ModelsService(createSqlMock({ provider }) as never, devices as never).scheduleFallback(context.userId, input),
    ).resolves.toMatchObject({
      used: false,
      providerKey: 'openai-main',
      model: 'gpt-test',
      reason: 'AI API returned empty message content.',
      draftItems: [],
      unplanned: input.unplanned,
    });

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: true,
        status: 200,
        text: vi.fn(async () => '{not valid response json'),
      })),
    );
    await expect(
      new ModelsService(createSqlMock({ provider }) as never, devices as never).scheduleFallback(context.userId, input),
    ).resolves.toMatchObject({
      used: false,
      providerKey: 'openai-main',
      model: 'gpt-test',
      reason: expect.stringMatching(/JSON|Unexpected|property name|position/i),
      draftItems: [],
      unplanned: input.unplanned,
    });

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: true,
        status: 200,
        text: vi.fn(async () => '   '),
      })),
    );
    await expect(
      new ModelsService(createSqlMock({ provider }) as never, devices as never).scheduleFallback(context.userId, input),
    ).resolves.toMatchObject({
      used: false,
      providerKey: 'openai-main',
      model: 'gpt-test',
      reason: 'AI API returned empty message content.',
      draftItems: [],
      unplanned: input.unplanned,
    });
  });

  it('reports non-Error model call failures as safe scheduler fallbacks', async () => {
    const input = fallbackInput();
    const service = new ModelsService(
      createSqlMock({
        provider: {
          provider_key: 'openai-main',
          provider_type: 'openai_compatible',
          base_url: 'https://example.test',
          model: 'gpt-test',
          status: 'enabled',
          api_key_ciphertext: encrypt('unit-api-key', encryptionKey()),
        },
      }) as never,
      devices as never,
    );
    vi.spyOn(
      service as unknown as { callModel: () => Promise<string> },
      'callModel',
    ).mockRejectedValue('string failure');

    await expect(service.scheduleFallback(context.userId, input)).resolves.toEqual({
      used: false,
      providerKey: 'openai-main',
      model: 'gpt-test',
      reason: 'string failure',
      draftItems: [],
      unplanned: input.unplanned,
    });
  });

  it('records model audit entries with target or generic entity types', async () => {
    const database = createSqlMock();
    const service = new ModelsService(database as never, devices as never);
    const client = { query: vi.fn(async () => ({ rows: [] })) };
    const audit = service as unknown as {
      recordAudit: (
        client: typeof client,
        userId: string,
        deviceId: string | null,
        action: string,
        details: Record<string, unknown>,
      ) => Promise<void>;
    };

    await audit.recordAudit(client, context.userId, null, 'model.generic.target', {
      targetType: 'calendar_event',
    });
    await audit.recordAudit(client, context.userId, null, 'model.generic', {});

    expect(client.query).toHaveBeenNthCalledWith(
      1,
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        context.userId,
        null,
        'model.generic.target',
        'calendar_event',
        null,
        'model.generic.target',
        JSON.stringify({ targetType: 'calendar_event' }),
      ],
    );
    expect(client.query).toHaveBeenNthCalledWith(
      2,
      expect.stringContaining('INSERT INTO audit_logs'),
      [
        context.userId,
        null,
        'model.generic',
        'model',
        null,
        'model.generic',
        JSON.stringify({}),
      ],
    );
  });

  it('returns a safe fallback result for unsupported provider types', async () => {
    const input = fallbackInput();
    const fetchMock = vi.fn();
    vi.stubGlobal('fetch', fetchMock);
    const service = new ModelsService(
      createSqlMock({
        provider: {
          provider_key: 'other-provider',
          provider_type: 'custom',
          base_url: 'https://example.test',
          model: 'model-x',
          status: 'enabled',
          api_key_ciphertext: encrypt('unit-api-key', encryptionKey()),
          temperature: 0.2,
          max_output_tokens: 1600,
          options: {},
        },
      }) as never,
      devices as never,
    );

    await expect(service.scheduleFallback(context.userId, input)).resolves.toEqual({
      used: false,
      providerKey: 'other-provider',
      model: 'model-x',
      reason: 'Unsupported AI provider type: custom',
      draftItems: [],
      unplanned: input.unplanned,
    });
    expect(fetchMock).not.toHaveBeenCalled();
  });
});
