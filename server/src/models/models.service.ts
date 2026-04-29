import { BadRequestException, Injectable } from '@nestjs/common';
import { createDecipheriv, createHash, randomUUID } from 'node:crypto';
import { QueryResultRow } from 'pg';
import { FlowPlanRequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';

export interface ModelRunInput {
  source: string;
  targetType?: string | null;
  targetId?: string | null;
  inputSummary: Record<string, unknown>;
}

export interface CompleteModelRunInput {
  status: 'succeeded' | 'failed' | 'partial';
  outputSummary: Record<string, unknown>;
  confidence?: number;
  failureReason?: string | null;
  usedLlm?: boolean;
  llmProviderKey?: string | null;
  llmModel?: string | null;
}

export interface ScheduleFallbackInput {
  rangeStart: Date;
  rangeEnd: Date;
  tasks: Array<Record<string, unknown>>;
  busyBlocks: unknown[];
  freeBlocks: unknown[];
  unplanned: Array<Record<string, unknown>>;
  strategy: string;
  profile: Record<string, unknown>;
}

type ProviderConfig = QueryResultRow & {
  provider_key: string;
  provider_type: string;
  base_url: string;
  model: string;
  api_key_ciphertext: string | null;
  status: string;
  temperature: string | number;
  max_output_tokens: string | number;
  options: Record<string, unknown>;
};

const DEFAULT_MODELS: Array<{
  key: string;
  name: string;
  category: string;
  profile: Record<string, unknown>;
}> = [
  {
    key: 'scheduler.v1',
    name: '服务端智能排程模型',
    category: 'scheduler',
    profile: {
      priorityWeights: { urgent: 40, high: 25, normal: 8, low: 0 },
      dueSoonWeights: { within24h: 50, within72h: 30 },
      actualWorkBonus: 10,
      deadlineFirstBonus: 20,
      minChunkMinutes: 15,
      maxChunkMinutes: 120,
      llmFallback: {
        enabled: true,
        unplannedRatioThreshold: 0.3,
        confidenceThreshold: 0.65,
      },
      learnedAdjustments: {},
    },
  },
  {
    key: 'activity_merge.v1',
    name: '服务端活动合并与任务关联模型',
    category: 'activity',
    profile: {
      mergeGapMinutes: 10,
      shortInterruptionMinutes: 3,
      lowConfidenceThreshold: 0.65,
      taskMatchThreshold: 25,
      appConfidenceBonus: 0.12,
      learnedAdjustments: {},
    },
  },
  {
    key: 'report_template.v1',
    name: '服务端报告与日记模板模型',
    category: 'report',
    profile: {
      templateFirst: true,
      llmPolishOnly: true,
      evidenceRequired: true,
      learnedAdjustments: {},
    },
  },
  {
    key: 'file_recommendation.v1',
    name: '服务端文件推荐模型',
    category: 'files',
    profile: {
      recentUseWeight: 25,
      taskTitleWeight: 20,
      boundFolderWeight: 35,
      llmExplainOnly: true,
      learnedAdjustments: {},
    },
  },
  {
    key: 'deviation_detection.v1',
    name: '服务端计划偏离检测模型',
    category: 'scheduler',
    profile: {
      minorDeviationMinutes: 15,
      majorDeviationMinutes: 45,
      differentActivitySeverity: 'medium',
      learnedAdjustments: {},
    },
  },
];

@Injectable()
export class ModelsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
  ) {}

  async list(context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    await this.ensureDefaultModels(userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        d.id::text AS id,
        d.model_key AS "modelKey",
        d.display_name AS "displayName",
        d.category,
        d.status,
        d.description,
        v.id::text AS "activeVersionId",
        v.version_key AS "activeVersionKey",
        v.rule_profile_json AS "activeRuleProfile",
        v.metrics_json AS "activeMetrics",
        (
          SELECT COUNT(*)::int FROM model_runs r
          WHERE r.user_id = d.user_id AND r.model_key = d.model_key
        ) AS "runCount",
        (
          SELECT COUNT(*)::int FROM model_feedback_events f
          WHERE f.user_id = d.user_id AND f.model_key = d.model_key
        ) AS "feedbackCount"
      FROM model_definitions d
      LEFT JOIN model_versions v
        ON v.user_id = d.user_id
       AND v.model_definition_id = d.id
       AND v.status = 'active'
      WHERE d.user_id = $1
      ORDER BY d.category ASC, d.model_key ASC
      `,
      [userId],
    );
    return { items: result.rows };
  }

  async versions(modelKey: string, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    await this.ensureDefaultModels(userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        v.id::text AS id,
        v.version_key AS "versionKey",
        v.status,
        v.rule_profile_json AS "ruleProfile",
        v.metrics_json AS metrics,
        v.change_summary AS "changeSummary",
        v.created_by AS "createdBy",
        v.created_at AS "createdAt",
        v.activated_at AS "activatedAt"
      FROM model_versions v
      JOIN model_definitions d ON d.id = v.model_definition_id
      WHERE v.user_id = $1 AND d.model_key = $2
      ORDER BY v.created_at DESC
      `,
      [userId, modelKey],
    );
    return { modelKey, items: result.rows };
  }

  async runs(
    modelKey: string,
    query: Record<string, string | undefined>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = this.readLimit(query.limit, 80);
    const status = this.clean(query.status);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        model_key AS "modelKey",
        model_version_key AS "modelVersionKey",
        source,
        target_type AS "targetType",
        target_id AS "targetId",
        status,
        confidence,
        used_llm AS "usedLlm",
        llm_provider_key AS "llmProviderKey",
        llm_model AS "llmModel",
        failure_reason AS "failureReason",
        input_summary_json AS "inputSummary",
        output_summary_json AS "outputSummary",
        started_at AS "startedAt",
        completed_at AS "completedAt"
      FROM model_runs
      WHERE user_id = $1
        AND model_key = $2
        AND ($3::text IS NULL OR status = $3)
      ORDER BY started_at DESC
      LIMIT $4
      `,
      [userId, modelKey, status, limit],
    );
    return { modelKey, items: result.rows };
  }

  async feedback(
    modelKey: string,
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.ensureDefaultModels(userId);
    const definition = await this.definition(userId, modelKey);
    const feedbackType = this.clean(body.feedbackType) ?? this.clean(body.type);
    if (!feedbackType) {
      throw new BadRequestException('feedbackType is required.');
    }
    const row = await this.database.transaction(async (client) => {
      const inserted = await client.query<QueryResultRow>(
        `
        INSERT INTO model_feedback_events (
          user_id,
          device_id,
          model_definition_id,
          model_key,
          model_run_id,
          target_type,
          target_id,
          feedback_type,
          feedback_payload_json,
          outcome,
          source
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10, $11)
        RETURNING id::text AS id, created_at AS "createdAt"
        `,
        [
          userId,
          deviceId,
          definition.id,
          modelKey,
          this.clean(body.modelRunId),
          this.clean(body.targetType),
          this.clean(body.targetId),
          feedbackType,
          JSON.stringify(this.asRecord(body.feedbackPayload ?? body.payload)),
          this.clean(body.outcome) ?? feedbackType,
          this.clean(body.source) ?? 'client',
        ],
      );
      await this.insertEvalCase(client, userId, definition.id, modelKey, body);
      await this.recordAudit(client, userId, deviceId, 'model.feedback.record', {
        modelKey,
        feedbackType,
        targetType: this.clean(body.targetType),
        targetId: this.clean(body.targetId),
      });
      return inserted.rows[0];
    });
    return { ok: true, feedback: row };
  }

  async evaluate(
    modelKey: string,
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    await this.ensureDefaultModels(userId);
    const cases = await this.database.query<QueryResultRow>(
      `
      SELECT expected_outcome_json AS "expectedOutcome", status
      FROM model_eval_cases
      WHERE user_id = $1 AND model_key = $2
      ORDER BY created_at DESC
      LIMIT $3
      `,
      [userId, modelKey, this.readLimit(String(body.limit ?? ''), 100)],
    );
    const active = await this.activeVersion(userId, modelKey);
    const metrics = {
      evalCaseCount: cases.rows.length,
      acceptedFeedbackCount: cases.rows.filter((row) => row.status === 'active').length,
      versionKey: active.versionKey,
      note: 'MVP evaluates available feedback cases only; no offline training is run.',
    };
    await this.database.query(
      `
      UPDATE model_versions
      SET metrics_json = $3::jsonb, updated_at = now()
      WHERE user_id = $1 AND id = $2
      `,
      [userId, active.versionId, JSON.stringify(metrics)],
    );
    return { ok: true, modelKey, metrics };
  }

  async learn(
    modelKey: string,
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.ensureDefaultModels(userId);
    const definition = await this.definition(userId, modelKey);
    const active = await this.activeVersion(userId, modelKey);
    const feedback = await this.database.query<QueryResultRow>(
      `
      SELECT feedback_type AS "feedbackType", outcome, feedback_payload_json AS payload
      FROM model_feedback_events
      WHERE user_id = $1 AND model_key = $2
      ORDER BY created_at DESC
      LIMIT 200
      `,
      [userId, modelKey],
    );
    const currentProfile = this.asRecord(active.ruleProfile);
    const learned = this.applyFeedbackLearning(modelKey, currentProfile, feedback.rows);
    const lowRisk = this.isLowRiskLearning(currentProfile, learned.profile);
    const versionKey = `learned-${new Date().toISOString().replace(/[-:.TZ]/g, '').slice(0, 14)}`;
    const result = await this.database.transaction(async (client) => {
      const shouldAutoActivate = lowRisk && body.autoActivate !== false;
      const version = await client.query<QueryResultRow>(
        `
        INSERT INTO model_versions (
          user_id,
          model_definition_id,
          version_key,
          status,
          rule_profile_json,
          metrics_json,
          change_summary,
          created_by
        ) VALUES ($1, $2, $3, 'draft', $4::jsonb, $5::jsonb, $6, 'feedback_learning')
        RETURNING id::text AS id, version_key AS "versionKey", status, rule_profile_json AS "ruleProfile"
        `,
        [
          userId,
          definition.id,
          versionKey,
          JSON.stringify(learned.profile),
          JSON.stringify(learned.metrics),
          learned.summary,
        ],
      );
      if (shouldAutoActivate) {
        await client.query(
          `
          UPDATE model_versions
          SET status = 'archived', updated_at = now()
          WHERE user_id = $1 AND model_definition_id = $2 AND id <> $3
          `,
          [userId, definition.id, version.rows[0].id],
        );
        await client.query(
          `
          UPDATE model_versions
          SET status = 'active', activated_at = now(), updated_at = now()
          WHERE user_id = $1 AND id = $2
          `,
          [userId, version.rows[0].id],
        );
      } else {
        await client.query(
          `
          INSERT INTO model_rule_change_drafts (
            user_id,
            model_definition_id,
            model_key,
            proposed_version_id,
            title,
            summary,
            risk_level,
            proposed_profile_json,
            status,
            source
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, 'pending_review', $9)
          `,
          [
            userId,
            definition.id,
            modelKey,
            version.rows[0].id,
            `${modelKey} 规则学习建议`,
            learned.summary,
            lowRisk ? 'low' : 'medium',
            JSON.stringify(learned.profile),
            'feedback_learning',
          ],
        );
      }
      await this.recordAudit(client, userId, deviceId, 'model.learn', {
        modelKey,
        feedbackCount: feedback.rows.length,
        lowRisk,
        autoActivated: shouldAutoActivate,
        versionId: version.rows[0].id,
      });
      return version.rows[0];
    });
    return { ok: true, modelKey, version: result, learned };
  }

  async activate(
    modelKey: string,
    versionId: string,
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    if (this.clean(body.confirmationToken) !== 'CONFIRM') {
      throw new BadRequestException('confirmationToken CONFIRM is required to activate a model version.');
    }
    await this.ensureDefaultModels(userId);
    const definition = await this.definition(userId, modelKey);
    const result = await this.database.transaction(async (client) => {
      await client.query(
        `
        UPDATE model_versions
        SET status = 'archived', updated_at = now()
        WHERE user_id = $1 AND model_definition_id = $2 AND status = 'active'
        `,
        [userId, definition.id],
      );
      const activated = await client.query<QueryResultRow>(
        `
        UPDATE model_versions
        SET status = 'active', activated_at = now(), updated_at = now()
        WHERE user_id = $1 AND model_definition_id = $2 AND id = $3
        RETURNING id::text AS id, version_key AS "versionKey", status
        `,
        [userId, definition.id, versionId],
      );
      if (!activated.rows[0]) {
        throw new BadRequestException('model version not found.');
      }
      await this.recordAudit(client, userId, deviceId, 'model.version.activate', {
        modelKey,
        versionId,
        reason: this.clean(body.reason),
      });
      return activated.rows[0];
    });
    return { ok: true, modelKey, version: result };
  }

  async llmHealth(context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const provider = await this.defaultProvider(userId);
    if (!provider) {
      return { configured: false, online: false, reason: 'AI Provider is not configured.' };
    }
    return {
      configured: true,
      online: provider.status === 'enabled' && Boolean(provider.api_key_ciphertext),
      providerKey: provider.provider_key,
      providerType: provider.provider_type,
      model: provider.model,
      status: provider.status,
      lastTestedAt: provider.last_tested_at,
      lastError: provider.last_error,
    };
  }

  async activeProfile(userId: string, modelKey: string) {
    await this.ensureDefaultModels(userId);
    return this.activeVersion(userId, modelKey);
  }

  async startRun(
    userId: string,
    modelKey: string,
    input: ModelRunInput,
  ) {
    await this.ensureDefaultModels(userId);
    const definition = await this.definition(userId, modelKey);
    const version = await this.activeVersion(userId, modelKey);
    const row = await this.database.query<QueryResultRow>(
      `
      INSERT INTO model_runs (
        user_id,
        model_definition_id,
        model_version_id,
        model_key,
        model_version_key,
        source,
        target_type,
        target_id,
        input_summary_json,
        status
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, 'running')
      RETURNING id::text AS id
      `,
      [
        userId,
        definition.id,
        version.versionId,
        modelKey,
        version.versionKey,
        input.source,
        input.targetType ?? null,
        input.targetId ?? null,
        JSON.stringify(input.inputSummary),
      ],
    );
    return { id: String(row.rows[0].id), version };
  }

  async completeRun(
    userId: string,
    runId: string,
    input: CompleteModelRunInput,
  ) {
    await this.database.query(
      `
      UPDATE model_runs
      SET
        status = $3,
        output_summary_json = $4::jsonb,
        confidence = $5,
        failure_reason = $6,
        used_llm = $7,
        llm_provider_key = $8,
        llm_model = $9,
        completed_at = now(),
        updated_at = now()
      WHERE user_id = $1 AND id = $2
      `,
      [
        userId,
        runId,
        input.status,
        JSON.stringify(input.outputSummary),
        input.confidence ?? null,
        input.failureReason ?? null,
        Boolean(input.usedLlm),
        input.llmProviderKey ?? null,
        input.llmModel ?? null,
      ],
    );
  }

  async recordFeedback(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    modelKey: string,
    body: Record<string, unknown>,
  ) {
    await this.ensureDefaultModels(userId);
    const definition = await this.definition(userId, modelKey);
    const feedbackType = this.clean(body.feedbackType) ?? 'accepted';
    await client.query(
      `
      INSERT INTO model_feedback_events (
        user_id,
        device_id,
        model_definition_id,
        model_key,
        model_run_id,
        target_type,
        target_id,
        feedback_type,
        feedback_payload_json,
        outcome,
        source
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10, $11)
      `,
      [
        userId,
        deviceId,
        definition.id,
        modelKey,
        this.clean(body.modelRunId),
        this.clean(body.targetType),
        this.clean(body.targetId),
        feedbackType,
        JSON.stringify(this.asRecord(body.feedbackPayload ?? body.payload)),
        this.clean(body.outcome) ?? feedbackType,
        this.clean(body.source) ?? 'service',
      ],
    );
  }

  async scheduleFallback(userId: string, input: ScheduleFallbackInput) {
    const provider = await this.defaultProvider(userId);
    if (!provider || provider.status !== 'enabled') {
      return { used: false, reason: 'AI provider is not enabled.', draftItems: [], unplanned: input.unplanned };
    }
    const apiKey = this.readApiKey(provider);
    if (!apiKey) {
      return { used: false, reason: 'AI provider API key is missing.', draftItems: [], unplanned: input.unplanned };
    }
    const prompt = [
      {
        role: 'system',
        content:
          'You are FlowPlan scheduler fallback. Return strict JSON only. You may only produce schedule draft items, never claim to write database. Respect busy blocks, range, locked tasks and task ids. Schema: {"draftItems":[{"taskId":"","taskTitle":"","proposedStart":"","proposedEnd":"","reason":"","risk":"low|medium|high","confidence":0.0}],"unplanned":[{"taskId":"","reason":""}],"explanation":""}.',
      },
      {
        role: 'user',
        content: JSON.stringify({
          rangeStart: input.rangeStart.toISOString(),
          rangeEnd: input.rangeEnd.toISOString(),
          strategy: input.strategy,
          tasks: input.tasks,
          busyBlocks: input.busyBlocks,
          freeBlocks: input.freeBlocks,
          unplanned: input.unplanned,
          profile: input.profile,
          rule: 'LLM output is draft only. Server will validate every item before it becomes confirmable.',
        }).slice(0, 24000),
      },
    ];
    try {
      const raw = await this.callModel(provider, apiKey, prompt);
      const parsed = this.asRecord(this.parseModelJson(raw));
      return {
        used: true,
        providerKey: provider.provider_key,
        model: provider.model,
        raw,
        draftItems: Array.isArray(parsed.draftItems)
          ? parsed.draftItems
          : Array.isArray(parsed.draft_items)
            ? parsed.draft_items
            : [],
        unplanned: Array.isArray(parsed.unplanned) ? parsed.unplanned : [],
        explanation: this.clean(parsed.explanation) ?? raw,
      };
    } catch (error) {
      return {
        used: false,
        providerKey: provider.provider_key,
        model: provider.model,
        reason: error instanceof Error ? error.message : String(error),
        draftItems: [],
        unplanned: input.unplanned,
      };
    }
  }

  private async ensureDefaultModels(userId: string) {
    for (const item of DEFAULT_MODELS) {
      const definition = await this.database.query<QueryResultRow>(
        `
        INSERT INTO model_definitions (user_id, model_key, display_name, category, status, description)
        VALUES ($1, $2, $3, $4, 'enabled', $5)
        ON CONFLICT (user_id, model_key) DO UPDATE SET
          display_name = EXCLUDED.display_name,
          category = EXCLUDED.category,
          updated_at = now()
        RETURNING id::text AS id
        `,
        [userId, item.key, item.name, item.category, `${item.name} 的服务端模型定义。`],
      );
      await this.database.query(
        `
        INSERT INTO model_versions (
          user_id,
          model_definition_id,
          version_key,
          status,
          rule_profile_json,
          metrics_json,
          change_summary,
          created_by,
          activated_at
        ) VALUES ($1, $2, 'default-v1', 'active', $3::jsonb, '{}'::jsonb, 'Initial server-side MVP profile.', 'system', now())
        ON CONFLICT (user_id, model_definition_id, version_key) DO NOTHING
        `,
        [userId, definition.rows[0].id, JSON.stringify(item.profile)],
      );
    }
  }

  private async definition(userId: string, modelKey: string) {
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT id::text AS id, model_key AS "modelKey"
      FROM model_definitions
      WHERE user_id = $1 AND model_key = $2
      LIMIT 1
      `,
      [userId, modelKey],
    );
    if (!result.rows[0]) throw new BadRequestException(`unknown model: ${modelKey}`);
    return result.rows[0];
  }

  private async activeVersion(userId: string, modelKey: string) {
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        v.id::text AS "versionId",
        v.version_key AS "versionKey",
        v.rule_profile_json AS "ruleProfile"
      FROM model_versions v
      JOIN model_definitions d ON d.id = v.model_definition_id
      WHERE v.user_id = $1 AND d.model_key = $2 AND v.status = 'active'
      ORDER BY v.activated_at DESC NULLS LAST, v.created_at DESC
      LIMIT 1
      `,
      [userId, modelKey],
    );
    if (!result.rows[0]) throw new BadRequestException(`no active version for model: ${modelKey}`);
    return result.rows[0] as QueryResultRow & {
      versionId: string;
      versionKey: string;
      ruleProfile: Record<string, unknown>;
    };
  }

  private async defaultProvider(userId: string): Promise<ProviderConfig | null> {
    const result = await this.database.query<ProviderConfig>(
      `
      SELECT *
      FROM ai_provider_configs
      WHERE user_id = $1 AND is_default IS TRUE
      ORDER BY updated_at DESC
      LIMIT 1
      `,
      [userId],
    );
    return result.rows[0] ?? null;
  }

  private applyFeedbackLearning(
    modelKey: string,
    profile: Record<string, unknown>,
    feedback: QueryResultRow[],
  ) {
    const updated = JSON.parse(JSON.stringify(profile)) as Record<string, unknown>;
    const adjustments = this.asRecord(updated.learnedAdjustments);
    const rejected = feedback.filter((row) => /reject|rejected|declined/.test(String(row.feedbackType ?? row.outcome)));
    const accepted = feedback.filter((row) => /accept|accepted|confirmed|modified/.test(String(row.feedbackType ?? row.outcome)));
    if (modelKey === 'scheduler.v1') {
      const currentNightPenalty = Number(adjustments.nightPenalty ?? 0);
      adjustments.nightPenalty = Math.max(0, Math.min(25, currentNightPenalty + rejected.length * 0.25));
      adjustments.acceptedSampleCount = accepted.length;
      adjustments.rejectedSampleCount = rejected.length;
      if (accepted.length > rejected.length) {
        adjustments.confidenceBonus = Math.min(0.08, Number(adjustments.confidenceBonus ?? 0) + 0.01);
      }
    } else if (modelKey === 'activity_merge.v1') {
      const currentThreshold = Number(updated.taskMatchThreshold ?? 25);
      updated.taskMatchThreshold = Math.max(15, Math.min(45, currentThreshold + (rejected.length > accepted.length ? 2 : -1)));
      adjustments.acceptedSampleCount = accepted.length;
      adjustments.rejectedSampleCount = rejected.length;
    } else {
      adjustments.acceptedSampleCount = accepted.length;
      adjustments.rejectedSampleCount = rejected.length;
    }
    updated.learnedAdjustments = adjustments;
    return {
      profile: updated,
      summary: `Based on ${feedback.length} feedback events: ${accepted.length} accepted/modified, ${rejected.length} rejected.`,
      metrics: {
        feedbackCount: feedback.length,
        acceptedCount: accepted.length,
        rejectedCount: rejected.length,
        generatedAt: new Date().toISOString(),
      },
    };
  }

  private isLowRiskLearning(
    before: Record<string, unknown>,
    after: Record<string, unknown>,
  ) {
    return JSON.stringify(before).length > 0 && JSON.stringify(after).length < 20000;
  }

  private async insertEvalCase(
    client: TransactionClient,
    userId: string,
    definitionId: string,
    modelKey: string,
    body: Record<string, unknown>,
  ) {
    const feedbackType = this.clean(body.feedbackType) ?? this.clean(body.type);
    if (!feedbackType) return;
    await client.query(
      `
      INSERT INTO model_eval_cases (
        user_id,
        model_definition_id,
        model_key,
        case_key,
        input_snapshot_json,
        expected_outcome_json,
        source_feedback_id,
        status
      ) VALUES ($1, $2, $3, $4, $5::jsonb, $6::jsonb, NULL, 'active')
      `,
      [
        userId,
        definitionId,
        modelKey,
        `feedback:${randomUUID()}`,
        JSON.stringify(this.asRecord(body.inputSnapshot)),
        JSON.stringify({
          feedbackType,
          targetType: this.clean(body.targetType),
          targetId: this.clean(body.targetId),
          payload: this.asRecord(body.feedbackPayload ?? body.payload),
        }),
      ],
    );
  }

  private async callModel(
    provider: ProviderConfig,
    apiKey: string,
    messages: Array<{ role: string; content: string }>,
  ) {
    if (provider.provider_type !== 'openai_compatible') {
      throw new BadRequestException(`Unsupported AI provider type: ${provider.provider_type}`);
    }
    const endpoint = `${provider.base_url.replace(/\/$/, '')}/chat/completions`;
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: {
        authorization: `Bearer ${apiKey}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        model: provider.model,
        messages,
        temperature: this.readNumber(provider.temperature, 0.2),
        max_tokens: this.readInteger(provider.max_output_tokens, 1600),
        ...this.asRecord(provider.options),
      }),
    });
    const raw = (await response.text()).trim();
    if (!response.ok) {
      throw new Error(`AI API ${response.status}: ${raw.slice(0, 500)}`);
    }
    const json = raw ? JSON.parse(raw) : {};
    const choice = Array.isArray(json.choices) ? json.choices[0] : null;
    const content = choice?.message?.content;
    if (typeof content !== 'string' || content.trim().length === 0) {
      throw new Error('AI API returned empty message content.');
    }
    return content.trim();
  }

  private parseModelJson(content: string) {
    try {
      return JSON.parse(content);
    } catch {
      const match = content.match(/\{[\s\S]*\}/);
      if (!match) return {};
      try {
        return JSON.parse(match[0]);
      } catch {
        return {};
      }
    }
  }

  private readApiKey(provider: ProviderConfig) {
    return provider.api_key_ciphertext ? this.decrypt(provider.api_key_ciphertext) : null;
  }

  private decrypt(value: string) {
    const [ivRaw, tagRaw, encryptedRaw] = value.split('.');
    if (!ivRaw || !tagRaw || !encryptedRaw) {
      throw new Error('Invalid encrypted API key format.');
    }
    const decipher = createDecipheriv(
      'aes-256-gcm',
      this.secretKey(),
      Buffer.from(ivRaw, 'base64'),
    );
    decipher.setAuthTag(Buffer.from(tagRaw, 'base64'));
    return Buffer.concat([
      decipher.update(Buffer.from(encryptedRaw, 'base64')),
      decipher.final(),
    ]).toString('utf8');
  }

  private secretKey() {
    return createHash('sha256')
      .update(process.env.AI_CONFIG_SECRET ?? process.env.DATABASE_URL ?? 'flowplan-local-development-secret')
      .digest();
  }

  private async recordAudit(
    client: Pick<DatabaseService | TransactionClient, 'query'>,
    userId: string,
    deviceId: string | null,
    action: string,
    details: Record<string, unknown>,
  ) {
    await client.query(
      `
      INSERT INTO audit_logs (
        user_id, device_id, actor, action, entity_type, entity_id, summary, metadata
      ) VALUES ($1, $2, 'model', $3, $4, $5, $6, $7::jsonb)
      `,
      [
        userId,
        deviceId,
        action,
        String(details.modelKey ?? details.targetType ?? 'model'),
        details.targetId ? String(details.targetId) : null,
        action,
        JSON.stringify(details),
      ],
    );
  }

  private readLimit(value: string | undefined, fallback: number) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) return fallback;
    return Math.max(1, Math.min(300, Math.trunc(parsed)));
  }

  private readInteger(value: unknown, fallback: number) {
    const parsed = Number(value);
    if (!Number.isFinite(parsed)) return fallback;
    return Math.trunc(parsed);
  }

  private readNumber(value: unknown, fallback: number) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  private clean(value: unknown) {
    return typeof value === 'string' && value.trim().length > 0
      ? value.trim()
      : null;
  }

  private asRecord(value: unknown): Record<string, unknown> {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      return value as Record<string, unknown>;
    }
    return {};
  }
}
