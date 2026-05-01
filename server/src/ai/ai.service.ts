import { BadRequestException, Injectable } from '@nestjs/common';
import { createCipheriv, createDecipheriv, createHash, randomBytes, randomUUID } from 'node:crypto';
import { QueryResultRow } from 'pg';
import { FlowPlanV2RequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';

export interface AiQuery {
  status?: string;
  limit?: string;
  offset?: string;
}

type ProviderConfig = QueryResultRow & {
  provider_key: string;
  provider_type: string;
  display_name: string;
  base_url: string;
  model: string;
  api_key_ciphertext: string | null;
  status: string;
  temperature: string | number;
  max_output_tokens: string | number;
  options: Record<string, unknown>;
};

interface ModelDraft {
  title?: unknown;
  summary?: unknown;
  proposed_action?: unknown;
  target_type?: unknown;
  target_id?: unknown;
  risk_level?: unknown;
  proposed_payload?: unknown;
}

@Injectable()
export class AiService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
  ) {}

  async settings(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        provider_key AS "providerKey",
        provider_type AS "providerType",
        display_name AS "displayName",
        base_url AS "baseUrl",
        model,
        CASE
          WHEN api_key_ciphertext IS NULL THEN NULL
          ELSE CONCAT('已保存，尾号 ', COALESCE(api_key_hint, '未知'))
        END AS "apiKeyState",
        status,
        temperature,
        max_output_tokens AS "maxOutputTokens",
        is_default AS "isDefault",
        options,
        last_tested_at AS "lastTestedAt",
        last_error AS "lastError",
        updated_at AS "updatedAt"
      FROM ai_provider_configs
      WHERE user_id = $1
      ORDER BY is_default DESC, updated_at DESC
      `,
      [userId],
    );
    return { providers: result.rows, defaultProvider: result.rows[0] ?? null };
  }

  async upsertProvider(
    providerKey: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const apiKey = this.clean(body.apiKey);
    const baseUrl = this.validateProviderBaseUrl(
      this.clean(body.baseUrl) ?? 'https://api.openai.com/v1',
    );
    const encryptedKey = apiKey ? this.encrypt(apiKey) : null;
    const apiKeyHint = apiKey ? apiKey.slice(-4) : null;
    const isDefault = body.isDefault !== false;

    const provider = await this.database.transaction(async (client) => {
      if (isDefault) {
        await client.query(
          'UPDATE ai_provider_configs SET is_default = false WHERE user_id = $1',
          [userId],
        );
      }
      const result = await client.query<QueryResultRow>(
        `
        INSERT INTO ai_provider_configs (
          user_id,
          provider_key,
          provider_type,
          display_name,
          base_url,
          model,
          api_key_ciphertext,
          api_key_hint,
          status,
          temperature,
          max_output_tokens,
          is_default,
          options
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13::jsonb)
        ON CONFLICT (user_id, provider_key) DO UPDATE SET
          provider_type = EXCLUDED.provider_type,
          display_name = EXCLUDED.display_name,
          base_url = EXCLUDED.base_url,
          model = EXCLUDED.model,
          api_key_ciphertext = COALESCE(EXCLUDED.api_key_ciphertext, ai_provider_configs.api_key_ciphertext),
          api_key_hint = COALESCE(EXCLUDED.api_key_hint, ai_provider_configs.api_key_hint),
          status = EXCLUDED.status,
          temperature = EXCLUDED.temperature,
          max_output_tokens = EXCLUDED.max_output_tokens,
          is_default = EXCLUDED.is_default,
          options = EXCLUDED.options,
          last_error = NULL,
          updated_at = now()
        RETURNING
          id::text AS id,
          provider_key AS "providerKey",
          provider_type AS "providerType",
          display_name AS "displayName",
          base_url AS "baseUrl",
          model,
          status,
          is_default AS "isDefault",
          updated_at AS "updatedAt"
        `,
        [
          userId,
          providerKey,
          this.clean(body.providerType) ?? 'openai_compatible',
          this.clean(body.displayName) ?? providerKey,
          baseUrl,
          this.clean(body.model) ?? '',
          encryptedKey,
          apiKeyHint,
          this.clean(body.status) ?? 'enabled',
          this.readNumber(body.temperature, 0.2),
          this.readInteger(body.maxOutputTokens, 1600),
          isDefault,
          JSON.stringify(this.asRecord(body.options)),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'ai.provider.upsert', {
        providerKey,
        providerType: this.clean(body.providerType) ?? 'openai_compatible',
        hasApiKey: Boolean(apiKey),
      });
      return result.rows[0];
    });

    return { ok: true, provider };
  }

  async testProvider(providerKey: string, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const provider = await this.loadProvider(userId, providerKey);
    if (!provider) {
      throw new BadRequestException('AI provider is not configured.');
    }
    const apiKey = this.readApiKey(provider);
    if (!apiKey) {
      throw new BadRequestException('AI provider apiKey is missing.');
    }
    try {
      const content = await this.callModel(provider, apiKey, [
        { role: 'system', content: '只回复一句中文：FlowPlanV2 AI API 连接正常。' },
        { role: 'user', content: '测试连接' },
      ]);
      await this.database.query(
        `
        UPDATE ai_provider_configs
        SET last_tested_at = now(), last_error = NULL, updated_at = now()
        WHERE user_id = $1 AND provider_key = $2
        `,
        [userId, providerKey],
      );
      await this.recordAudit(this.database, userId, deviceId, 'ai.provider.test', {
        providerKey,
      });
      return { ok: true, message: content };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.database.query(
        `
        UPDATE ai_provider_configs
        SET last_tested_at = now(), last_error = $3, updated_at = now()
        WHERE user_id = $1 AND provider_key = $2
        `,
        [userId, providerKey, message],
      );
      throw error;
    }
  }

  async context(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    return {
      generatedAt: new Date().toISOString(),
      scope: 'sanitized_server_summary',
      context: await this.buildContext(userId),
    };
  }

  async createContextSnapshot(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const payload = await this.buildContext(userId);
    const result = await this.database.transaction(async (client) => {
      const snapshot = await client.query<QueryResultRow>(
        `
        INSERT INTO ai_context_snapshots (
          user_id,
          conversation_id,
          context_type,
          payload_json,
          sensitive_policy_json
        ) VALUES ($1, $2, $3, $4::jsonb, $5::jsonb)
        RETURNING id::text AS id, context_type AS "contextType", created_at AS "createdAt"
        `,
        [
          userId,
          this.clean(body.conversationId),
          this.clean(body.contextType) ?? 'mixed',
          JSON.stringify(payload),
          JSON.stringify(this.asRecord(body.sensitivePolicy)),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'ai.context.snapshot', {
        snapshotId: snapshot.rows[0]?.id,
        contextType: this.clean(body.contextType) ?? 'mixed',
      });
      return snapshot.rows[0];
    });
    return { ok: true, snapshot: result };
  }

  async toolPolicies(context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    await this.ensureDefaultPolicies(userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        tool_name AS "toolName",
        permission_level AS "permissionLevel",
        risk_level AS "riskLevel",
        allowed_scopes_json AS "allowedScopes",
        denied_scopes_json AS "deniedScopes",
        requires_confirmation AS "requiresConfirmation",
        requires_second_confirm AS "requiresSecondConfirm",
        updated_at AS "updatedAt"
      FROM ai_tool_policies
      WHERE user_id = $1
      ORDER BY risk_level DESC, tool_name ASC
      `,
      [userId],
    );
    return { policies: result.rows };
  }

  async upsertToolPolicy(
    toolName: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.transaction(async (client) => {
      const policy = await client.query<QueryResultRow>(
        `
        INSERT INTO ai_tool_policies (
          user_id,
          tool_name,
          permission_level,
          risk_level,
          allowed_scopes_json,
          denied_scopes_json,
          requires_confirmation,
          requires_second_confirm
        ) VALUES ($1, $2, $3, $4, $5::jsonb, $6::jsonb, $7, $8)
        ON CONFLICT (user_id, tool_name) DO UPDATE SET
          permission_level = EXCLUDED.permission_level,
          risk_level = EXCLUDED.risk_level,
          allowed_scopes_json = EXCLUDED.allowed_scopes_json,
          denied_scopes_json = EXCLUDED.denied_scopes_json,
          requires_confirmation = EXCLUDED.requires_confirmation,
          requires_second_confirm = EXCLUDED.requires_second_confirm,
          updated_at = now()
        RETURNING id::text AS id, tool_name AS "toolName", permission_level AS "permissionLevel", risk_level AS "riskLevel"
        `,
        [
          userId,
          toolName,
          this.clean(body.permissionLevel) ?? 'draft_only',
          this.clean(body.riskLevel) ?? 'low',
          JSON.stringify(Array.isArray(body.allowedScopes) ? body.allowedScopes : []),
          JSON.stringify(Array.isArray(body.deniedScopes) ? body.deniedScopes : []),
          body.requiresConfirmation !== false,
          Boolean(body.requiresSecondConfirm),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'ai.tool_policy.upsert', {
        toolName,
        permissionLevel: this.clean(body.permissionLevel) ?? 'draft_only',
      });
      return policy.rows[0];
    });
    return { ok: true, policy: result };
  }

  async conversations(query: AiQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = this.readLimit(query.limit, 50);
    const offset = this.readOffset(query.offset);
    const status = this.clean(query.status);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        source,
        title,
        provider_key AS "providerKey",
        model,
        status,
        summary,
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM ai_conversations
      WHERE user_id = $1 AND ($2::text IS NULL OR status = $2)
      ORDER BY updated_at DESC
      LIMIT $3 OFFSET $4
      `,
      [userId, status, limit, offset],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, conversations: result.rows };
  }

  async createConversation(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.transaction(async (client) => {
      const inserted = await client.query<QueryResultRow>(
        `
        INSERT INTO ai_conversations (
          user_id,
          source,
          title,
          provider_key,
          model,
          context_scope
        ) VALUES ($1, $2, $3, $4, $5, $6::jsonb)
        RETURNING id::text AS id, title, status, created_at AS "createdAt"
        `,
        [
          userId,
          this.clean(body.source) ?? 'flowplanv2',
          this.clean(body.title) ?? 'AI 对话',
          this.clean(body.providerKey),
          this.clean(body.model),
          JSON.stringify(this.asRecord(body.contextScope)),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'ai.conversation.create', {
        conversationId: inserted.rows[0]?.id,
      });
      return inserted.rows[0];
    });
    return { ok: true, conversation: result };
  }

  async messages(conversationId: string, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        conversation_id::text AS "conversationId",
        role,
        content,
        provider_key AS "providerKey",
        model,
        tool_draft_ids AS "toolDraftIds",
        metadata,
        created_at AS "createdAt"
      FROM ai_messages
      WHERE user_id = $1 AND conversation_id = $2
      ORDER BY created_at ASC
      `,
      [userId, conversationId],
    );
    return { messages: result.rows };
  }

  async sendMessage(body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const content = this.clean(body.content);
    if (!content) {
      throw new BadRequestException('content is required.');
    }

    const conversation = await this.ensureConversation(userId, body, content);
    const provider = await this.loadProvider(
      userId,
      this.clean(body.providerKey) ?? conversation.provider_key ?? undefined,
    );
    const providerKey = provider?.provider_key ?? null;
    const apiKey = provider ? this.readApiKey(provider) : null;

    await this.database.query(
      `
      INSERT INTO ai_messages (user_id, conversation_id, role, content, provider_key, model)
      VALUES ($1, $2, 'user', $3, $4, $5)
      `,
      [userId, conversation.id, content, providerKey, provider?.model ?? null],
    );

    const recentMessages = await this.recentMessages(userId, conversation.id);
    const serverContext = await this.buildContext(userId);
    let assistantContent: string;
    let drafts: ModelDraft[] = [];
    let usage: Record<string, unknown> = {};

    if (!provider || !apiKey || provider.status !== 'enabled') {
      assistantContent =
        'AI API 尚未配置或未启用。请先在管理端填写 Provider、Base URL、模型名称和 API Key，然后再发送消息。';
    } else {
      const modelResult = await this.callStructuredModel(
        provider,
        apiKey,
        recentMessages,
        serverContext,
      );
      assistantContent = modelResult.assistantContent;
      drafts = modelResult.drafts;
      usage = modelResult.usage;
    }

    const draftIds = await this.database.transaction(async (client) => {
      const ids: string[] = [];
      for (const draft of drafts) {
        const prepared = this.prepareChatDraft(draft, content);
        if (!prepared) {
          const action = this.clean(draft.proposed_action) ?? 'unknown';
          if (action !== 'answer_only') {
            await this.recordAudit(client, userId, deviceId, 'ai.draft.blocked', {
              action,
              reason:
                'Only create_task operation drafts may be produced by the MVP chat flow.',
              userMessage: content,
            });
          }
          continue;
        }
        const action = prepared.action;
        const inserted = await client.query<QueryResultRow>(
          `
          INSERT INTO ai_operation_drafts (
            user_id,
            source,
            conversation_id,
            title,
            summary,
            proposed_action,
            target_type,
            target_id,
            risk_level,
            request_payload,
            proposed_payload
          ) VALUES ($1, 'ai_chat', $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10::jsonb)
          RETURNING id::text AS id
          `,
          [
            userId,
            conversation.id,
            this.clean(draft.title) ?? 'AI 操作草案',
            this.clean(draft.summary),
            action,
            prepared.targetType,
            prepared.targetId,
            prepared.riskLevel,
            JSON.stringify({
              userMessage: content,
              providerKey,
              schema: 'OperationDraft.create_task.v1',
            }),
            JSON.stringify(prepared.payload),
          ],
        );
        const draftId = String(inserted.rows[0].id);
        ids.push(draftId);
        await this.recordAudit(client, userId, deviceId, 'ai.draft.create', {
          draftId,
          action: prepared.action,
          riskLevel: prepared.riskLevel,
          payloadPreview: {
            title: prepared.payload.title,
            dueAt: prepared.payload.dueAt,
            estimatedMinutes: prepared.payload.estimatedMinutes,
            taskBookName: prepared.payload.taskBookName,
          },
        });
      }

      if (ids.length === 0 && this.looksLikeCreateTaskRequest(content)) {
        const prepared = this.fallbackTaskDraft(content);
        const inserted = await client.query<QueryResultRow>(
          `
          INSERT INTO ai_operation_drafts (
            user_id,
            source,
            conversation_id,
            title,
            summary,
            proposed_action,
            target_type,
            target_id,
            risk_level,
            request_payload,
            proposed_payload
          ) VALUES ($1, 'ai_chat', $2, $3, $4, $5, $6, $7, $8, $9::jsonb, $10::jsonb)
          RETURNING id::text AS id
          `,
          [
            userId,
            conversation.id,
            prepared.title,
            prepared.summary,
            prepared.action,
            prepared.targetType,
            prepared.targetId,
            prepared.riskLevel,
            JSON.stringify({
              userMessage: content,
              providerKey,
              schema: 'OperationDraft.create_task.v1',
              note: 'LLM response did not include a valid create_task draft; FlowPlanV2 created a conservative draft from the user request after the model call.',
            }),
            JSON.stringify(prepared.payload),
          ],
        );
        const draftId = String(inserted.rows[0].id);
        ids.push(draftId);
        await this.recordAudit(client, userId, deviceId, 'ai.draft.create', {
          draftId,
          action: prepared.action,
          riskLevel: prepared.riskLevel,
          fallback: true,
          payloadPreview: {
            title: prepared.payload.title,
            dueAt: prepared.payload.dueAt,
            estimatedMinutes: prepared.payload.estimatedMinutes,
            taskBookName: prepared.payload.taskBookName,
          },
        });
      }

      const assistant = await client.query<QueryResultRow>(
        `
        INSERT INTO ai_messages (
          user_id,
          conversation_id,
          role,
          content,
          provider_key,
          model,
          token_usage,
          tool_draft_ids,
          metadata
        ) VALUES ($1, $2, 'assistant', $3, $4, $5, $6::jsonb, $7::jsonb, $8::jsonb)
        RETURNING id::text AS id, created_at AS "createdAt"
        `,
        [
          userId,
          conversation.id,
          assistantContent,
          providerKey,
          provider?.model ?? null,
          JSON.stringify(usage),
          JSON.stringify(ids),
          JSON.stringify({ draftCount: ids.length }),
        ],
      );
      await client.query(
        `
        UPDATE ai_conversations
        SET
          provider_key = COALESCE($3, provider_key),
          model = COALESCE($4, model),
          summary = COALESCE(summary, $5),
          updated_at = now()
        WHERE user_id = $1 AND id = $2
        `,
        [
          userId,
          conversation.id,
          providerKey,
          provider?.model ?? null,
          this.summarize(content),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'ai.message.send', {
        conversationId: conversation.id,
        providerKey,
        draftIds: ids,
        assistantMessageId: assistant.rows[0]?.id,
      });
      return ids;
    });

    return {
      ok: true,
      conversationId: conversation.id,
      assistant: { role: 'assistant', content: assistantContent },
      draftIds,
    };
  }

  async explainActivitySegment(
    segmentId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const provider = await this.loadProvider(userId, this.clean(body.providerKey) ?? undefined);
    const apiKey = provider ? this.readApiKey(provider) : null;
    if (!provider || !apiKey || provider.status !== 'enabled') {
      throw new BadRequestException('AI provider is not configured or enabled.');
    }

    const segment = await this.database.query<QueryResultRow>(
      `
      SELECT
        s.id::text AS id,
        s.segment_uid AS "segmentUid",
        s.label AS title,
        s.category,
        s.start_at AS "startAt",
        s.end_at AS "endAt",
        s.duration_seconds AS "durationSeconds",
        COALESCE(s.primary_app, s.primary_process_name) AS "primaryApp",
        s.primary_window_title AS "primaryWindow",
        s.primary_file_path AS "primaryFilePath",
        s.primary_project_path AS "primaryProjectPath",
        s.evidence AS evidence,
        s.confidence,
        s.matched_task_id AS "matchedTaskId",
        s.status
      FROM activity_segments s
      WHERE s.user_id = $1 AND s.id = $2
      LIMIT 1
      `,
      [userId, segmentId],
    );
    const row = segment.rows[0];
    if (!row) {
      throw new BadRequestException('activity segment not found.');
    }

    const tasks = await this.database.query<QueryResultRow>(
      `
      SELECT uid, payload
      FROM sync_objects
      WHERE user_id = $1
        AND deleted_at IS NULL
        AND object_type IN ('task', 'tasks', 'task_item', 'task_items')
      ORDER BY updated_at DESC
      LIMIT 20
      `,
      [userId],
    );
    const taskSummaries = tasks.rows.map((task) => this.sanitizePayload(task));
    const prompt = [
      {
        role: 'system',
        content:
          'You are FlowPlanV2 activity interpretation assistant. Read only the provided segment summary and task candidates. Return strict JSON only. Do not confirm actual records, do not write facts, do not request tools. Schema: {"suggestedTitle":"","suggestedSummary":"","likelyTaskUid":"","confidence":0.0,"reasons":[""]}.',
      },
      {
        role: 'user',
        content: JSON.stringify({
          segment: row,
          taskCandidates: taskSummaries,
          rule: 'Low-confidence activity segments may only receive explanation suggestions. Human confirmation is required before any actual record is created.',
        }),
      },
    ];
    const raw = await this.callModel(provider, apiKey, prompt);
    const suggestion = this.asRecord(this.parseModelJson(raw));
    const safeSuggestion = {
      suggestedTitle: this.clean(suggestion.suggestedTitle) ?? this.clean(suggestion.suggested_title),
      suggestedSummary:
        this.clean(suggestion.suggestedSummary) ?? this.clean(suggestion.suggested_summary) ?? raw,
      likelyTaskUid:
        this.clean(suggestion.likelyTaskUid) ?? this.clean(suggestion.likely_task_uid),
      confidence: this.readNumber(suggestion.confidence, this.readNumber(row.confidence, 0.5)),
      reasons: Array.isArray(suggestion.reasons) ? suggestion.reasons.slice(0, 8) : [],
      model: provider.model,
    };

    const draft = await this.database.transaction(async (client) => {
      const inserted = await client.query<QueryResultRow>(
        `
        INSERT INTO ai_operation_drafts (
          user_id,
          source,
          title,
          summary,
          proposed_action,
          target_type,
          target_id,
          status,
          risk_level,
          request_payload,
          proposed_payload
        ) VALUES ($1, 'activity_understanding', $2, $3, 'activity_explanation_suggestion', 'activity_segment', $4, 'pending_review', 'low', $5::jsonb, $6::jsonb)
        RETURNING id::text AS id, title, status, risk_level AS "riskLevel", proposed_payload AS "proposedPayload"
        `,
        [
          userId,
          'AI activity explanation suggestion',
          'LLM suggestion only; it does not confirm or create actual records.',
          segmentId,
          JSON.stringify({
            segment: row,
            providerKey: provider.provider_key,
            schema: 'ActivityExplanationSuggestion.v1',
          }),
          JSON.stringify(safeSuggestion),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'ai.activity_explain.suggest', {
        draftId: inserted.rows[0]?.id,
        segmentId,
        targetType: 'activity_segment',
        targetId: segmentId,
        suggestion: safeSuggestion,
      });
      return inserted.rows[0];
    });

    return { ok: true, suggestion: safeSuggestion, draft };
  }

  async toolDrafts(query: AiQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = this.readLimit(query.limit, 80);
    const offset = this.readOffset(query.offset);
    const status = this.clean(query.status);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        source,
        conversation_id AS "conversationId",
        title,
        summary,
        proposed_action AS "proposedAction",
        target_type AS "targetType",
        target_id AS "targetId",
        status,
        risk_level AS "riskLevel",
        request_payload AS "requestPayload",
        proposed_payload AS "proposedPayload",
        review_note AS "reviewNote",
        reviewed_at AS "reviewedAt",
        execution_status AS "executionStatus",
        execution_result AS "executionResult",
        executed_at AS "executedAt",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM ai_operation_drafts
      WHERE user_id = $1 AND ($2::text IS NULL OR status = $2)
      ORDER BY created_at DESC
      LIMIT $3 OFFSET $4
      `,
      [userId, status, limit, offset],
    );
    return { limit, offset, hasMore: result.rows.length >= limit, drafts: result.rows };
  }

  async reviewDraft(
    draftId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const status = this.clean(body.status) ?? 'pending_review';
    const result = await this.database.transaction(async (client) => {
      const updated = await client.query<QueryResultRow>(
        `
        UPDATE ai_operation_drafts
        SET
          status = $3,
          review_note = COALESCE($4, review_note),
          reviewed_at = now(),
          updated_at = now()
        WHERE user_id = $1 AND id = $2
        RETURNING id::text AS id, status, review_note AS "reviewNote", reviewed_at AS "reviewedAt"
        `,
        [userId, draftId, status, this.clean(body.reviewNote)],
      );
      await this.recordAudit(client, userId, deviceId, 'ai.draft.review', {
        draftId,
        status,
      });
      return updated.rows[0] ?? null;
    });
    return { ok: Boolean(result), draft: result };
  }

  async confirmDraft(
    draftId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const result = await this.database.transaction(async (client) => {
      const draftResult = await client.query<QueryResultRow>(
        `
        SELECT
          id::text AS id,
          proposed_action AS action,
          target_type,
          target_id,
          risk_level,
          proposed_payload AS payload,
          status
        FROM ai_operation_drafts
        WHERE user_id = $1 AND id = $2
        FOR UPDATE
        `,
        [userId, draftId],
      );
      const draft = draftResult.rows[0];
      if (!draft) {
        throw new BadRequestException('draft not found.');
      }
      if (draft.status === 'rejected') {
        throw new BadRequestException('rejected draft cannot be executed.');
      }
      if (draft.status !== 'pending_review') {
        throw new BadRequestException(`draft status ${draft.status} cannot be executed.`);
      }
      const policy = await this.loadToolPolicy(userId, String(draft.action));
      if (policy.permissionLevel === 'disabled') {
        throw new BadRequestException('this AI tool is disabled by policy.');
      }
      if (policy.permissionLevel === 'draft_only' || policy.permissionLevel === 'read_only') {
        throw new BadRequestException('this AI tool may only create suggestions or drafts.');
      }
      if (!['draft_then_confirm', 'confirm_required', 'second_confirm_required'].includes(policy.permissionLevel)) {
        throw new BadRequestException(`unsupported AI tool permission level: ${policy.permissionLevel}`);
      }
      if (String(draft.action) !== 'create_task') {
        throw new BadRequestException('Only create_task drafts are executable in the MVP AI flow.');
      }
      if (policy.requiresSecondConfirm && this.clean(body.confirmationPhrase) !== 'CONFIRM') {
        throw new BadRequestException('second confirmation phrase CONFIRM is required.');
      }
      const execution = await this.executeDraft(
        client,
        userId,
        deviceId,
        String(draft.action),
        this.asRecord(draft.payload),
      );
      const updated = await client.query<QueryResultRow>(
        `
        UPDATE ai_operation_drafts
        SET
          status = 'approved',
          review_note = COALESCE($3, review_note),
          reviewed_at = COALESCE(reviewed_at, now()),
          execution_status = $4,
          execution_result = $5::jsonb,
          executed_at = CASE WHEN $4 = 'executed' THEN now() ELSE executed_at END,
          updated_at = now()
        WHERE user_id = $1 AND id = $2
        RETURNING id::text AS id, status, execution_status AS "executionStatus", execution_result AS "executionResult"
        `,
        [
          userId,
          draftId,
          this.clean(body.reviewNote) ?? '用户确认执行',
          execution.status,
          JSON.stringify(execution.result),
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'ai.draft.confirm', {
        draftId,
        action: draft.action,
        policy,
        executionStatus: execution.status,
        result: execution.result,
      });
      await client.query(
        `
        INSERT INTO ai_tool_calls (
          user_id,
          conversation_id,
          draft_id,
          tool_name,
          input_json,
          output_json,
          status,
          risk_level,
          confirmed_by,
          confirmed_at
        )
        SELECT
          user_id,
          NULLIF(conversation_id, '')::uuid,
          id,
          proposed_action,
          proposed_payload,
          $3::jsonb,
          $4,
          risk_level,
          $5,
          now()
        FROM ai_operation_drafts
        WHERE user_id = $1 AND id = $2
        `,
        [
          userId,
          draftId,
          JSON.stringify(execution.result),
          execution.status,
          deviceId,
        ],
      );
      return updated.rows[0];
    });
    return { ok: true, draft: result };
  }

  private async ensureDefaultPolicies(userId: string) {
    await this.database.query(
      `
      INSERT INTO ai_tool_policies (
        user_id,
        tool_name,
        permission_level,
        risk_level,
        allowed_scopes_json,
        denied_scopes_json,
        requires_confirmation,
        requires_second_confirm
      ) VALUES
        ($1, 'create_task', 'draft_then_confirm', 'low', '["task"]'::jsonb, '[]'::jsonb, true, false),
        ($1, 'create_calendar_event', 'draft_only', 'normal', '["calendar"]'::jsonb, '[]'::jsonb, true, false),
        ($1, 'create_actual_record', 'draft_only', 'normal', '["actual"]'::jsonb, '[]'::jsonb, true, false),
        ($1, 'activity_explanation_suggestion', 'draft_only', 'low', '["activity"]'::jsonb, '["confirm_actual"]'::jsonb, true, false),
        ($1, 'reschedule_plan', 'disabled', 'high', '["scheduler"]'::jsonb, '["external_write"]'::jsonb, true, true),
        ($1, 'file_recommendation', 'draft_only', 'normal', '["files"]'::jsonb, '["delete","overwrite"]'::jsonb, true, false),
        ($1, 'server_job_request', 'disabled', 'high', '["operations"]'::jsonb, '["delete","overwrite","external_write"]'::jsonb, true, true),
        ($1, 'shell_command', 'disabled', 'critical', '[]'::jsonb, '["shell","process"]'::jsonb, true, true),
        ($1, 'direct_database_write', 'disabled', 'critical', '[]'::jsonb, '["database","sql"]'::jsonb, true, true)
      ON CONFLICT (user_id, tool_name) DO NOTHING
      `,
      [userId],
    );
    await this.database.query(
      `
      UPDATE ai_tool_policies
      SET permission_level = 'disabled',
          requires_confirmation = true,
          requires_second_confirm = true,
          updated_at = now()
      WHERE user_id = $1
        AND tool_name IN ('reschedule_plan', 'server_job_request', 'shell_command', 'direct_database_write')
        AND permission_level <> 'disabled'
      `,
      [userId],
    );
  }

  private async loadToolPolicy(userId: string, toolName: string) {
    await this.ensureDefaultPolicies(userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        permission_level AS "permissionLevel",
        risk_level AS "riskLevel",
        allowed_scopes_json AS "allowedScopes",
        denied_scopes_json AS "deniedScopes",
        requires_confirmation AS "requiresConfirmation",
        requires_second_confirm AS "requiresSecondConfirm"
      FROM ai_tool_policies
      WHERE user_id = $1 AND tool_name = $2
      LIMIT 1
      `,
      [userId, toolName],
    );
    const row = result.rows[0] ?? {};
    return {
      permissionLevel: String(row.permissionLevel ?? 'draft_only'),
      riskLevel: String(row.riskLevel ?? 'high'),
      allowedScopes: Array.isArray(row.allowedScopes) ? row.allowedScopes : [],
      deniedScopes: Array.isArray(row.deniedScopes) ? row.deniedScopes : [],
      requiresConfirmation: row.requiresConfirmation !== false,
      requiresSecondConfirm: Boolean(row.requiresSecondConfirm),
    };
  }

  private async ensureConversation(
    userId: string,
    body: Record<string, unknown>,
    firstMessage: string,
  ) {
    const conversationId = this.clean(body.conversationId);
    if (conversationId) {
      const existing = await this.database.query<QueryResultRow>(
        `
        SELECT id::text AS id, provider_key, model
        FROM ai_conversations
        WHERE user_id = $1 AND id = $2
        `,
        [userId, conversationId],
      );
      if (existing.rows[0]) {
        return existing.rows[0];
      }
    }
    const inserted = await this.database.query<QueryResultRow>(
      `
      INSERT INTO ai_conversations (user_id, source, title, provider_key, model, context_scope)
      VALUES ($1, $2, $3, $4, $5, $6::jsonb)
      RETURNING id::text AS id, provider_key, model
      `,
      [
        userId,
        this.clean(body.source) ?? 'flowplanv2',
        this.clean(body.title) ?? this.summarize(firstMessage),
        this.clean(body.providerKey),
        this.clean(body.model),
        JSON.stringify(this.asRecord(body.contextScope)),
      ],
    );
    return inserted.rows[0];
  }

  private async recentMessages(userId: string, conversationId: string) {
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT role, content
      FROM ai_messages
      WHERE user_id = $1 AND conversation_id = $2
      ORDER BY created_at DESC
      LIMIT 12
      `,
      [userId, conversationId],
    );
    return result.rows.reverse().map((row) => ({
      role: String(row.role),
      content: String(row.content),
    }));
  }

  private async buildContext(userId: string) {
    const [objectCounts, recentTasks, recentSchedules, reports, files, stats] =
      await Promise.all([
        this.database.query<QueryResultRow>(
          `
          SELECT object_type AS "objectType", COUNT(*)::int AS count
          FROM sync_objects
          WHERE user_id = $1 AND deleted_at IS NULL
          GROUP BY object_type
          ORDER BY count DESC
          LIMIT 20
          `,
          [userId],
        ),
        this.database.query<QueryResultRow>(
          `
          SELECT id::text AS id, uid, payload, updated_at AS "updatedAt"
          FROM sync_objects
          WHERE user_id = $1
            AND deleted_at IS NULL
            AND object_type IN ('task', 'tasks', 'task_item', 'task_items')
          ORDER BY updated_at DESC
          LIMIT 10
          `,
          [userId],
        ),
        this.database.query<QueryResultRow>(
          `
          SELECT id::text AS id, uid, payload, updated_at AS "updatedAt"
          FROM sync_objects
          WHERE user_id = $1
            AND deleted_at IS NULL
            AND object_type IN ('calendar_event', 'calendar_events', 'event', 'events', 'time_block')
          ORDER BY updated_at DESC
          LIMIT 10
          `,
          [userId],
        ),
        this.database.query<QueryResultRow>(
          `
          SELECT report_type AS "reportType", title, summary_markdown AS summary, status, updated_at AS "updatedAt"
          FROM report_documents
          WHERE user_id = $1
          ORDER BY updated_at DESC
          LIMIT 5
          `,
          [userId],
        ),
        this.database.query<QueryResultRow>(
          `
          SELECT provider, display_name AS "displayName", local_path AS "localPath", remote_id AS "remoteId", updated_at AS "updatedAt"
          FROM file_items
          WHERE user_id = $1
          ORDER BY updated_at DESC
          LIMIT 10
          `,
          [userId],
        ),
        this.database.query<QueryResultRow>(
          `
          SELECT day_key AS "dayKey", category, SUM(total_minutes)::int AS "totalMinutes"
          FROM activity_daily_stats
          WHERE user_id = $1 AND day_key >= current_date - interval '14 days'
          GROUP BY day_key, category
          ORDER BY day_key DESC, "totalMinutes" DESC
          LIMIT 30
          `,
          [userId],
        ),
      ]);

    return {
      objectCounts: objectCounts.rows,
      recentTasks: recentTasks.rows.map((row) => this.sanitizePayload(row)),
      recentSchedules: recentSchedules.rows.map((row) => this.sanitizePayload(row)),
      recentReports: reports.rows,
      recentFiles: files.rows,
      recentActivityStats: stats.rows,
    };
  }

  private prepareChatDraft(draft: ModelDraft, userMessage: string) {
    const action = this.clean(draft.proposed_action);
    if (action !== 'create_task') {
      return null;
    }
    const payload = this.normalizeCreateTaskPayload(
      this.asRecord(draft.proposed_payload),
      userMessage,
    );
    return {
      title: this.clean(draft.title) ?? `创建任务：${payload.title}`,
      summary:
        this.clean(draft.summary) ??
        `创建任务 "${payload.title}"，截止时间 ${payload.dueAt ?? '未设置'}。`,
      action: 'create_task',
      targetType: 'task',
      targetId: null,
      riskLevel: 'low',
      payload,
    };
  }

  private fallbackTaskDraft(userMessage: string) {
    const payload = this.normalizeCreateTaskPayload({}, userMessage);
    return {
      title: `创建任务：${payload.title}`,
      summary: `创建任务 "${payload.title}"，截止时间 ${payload.dueAt ?? '未设置'}。`,
      action: 'create_task',
      targetType: 'task',
      targetId: null,
      riskLevel: 'low',
      payload,
    };
  }

  private normalizeCreateTaskPayload(
    rawPayload: Record<string, unknown>,
    userMessage: string,
  ) {
    const title =
      this.clean(rawPayload.title) ??
      this.clean(rawPayload.name) ??
      this.extractTaskTitle(userMessage);
    const dueAt =
      this.clean(rawPayload.dueAt) ??
      this.clean(rawPayload.due_at) ??
      this.clean(rawPayload.dueDate) ??
      this.inferDueAt(userMessage);
    const estimatedMinutes = this.readInteger(
      rawPayload.estimatedMinutes ?? rawPayload.estimated_minutes ?? rawPayload.durationMinutes,
      60,
    );
    return {
      title,
      dueAt,
      estimatedMinutes,
      taskBookId: this.clean(rawPayload.taskBookId) ?? this.clean(rawPayload.task_book_id),
      taskBookName:
        this.clean(rawPayload.taskBookName) ??
        this.clean(rawPayload.task_book_name) ??
        '默认任务本',
      priority: this.clean(rawPayload.priority) ?? 'normal',
      status: this.clean(rawPayload.status) ?? 'pending',
      notes: this.clean(rawPayload.notes) ?? this.clean(rawPayload.description),
      source: 'ai_confirmed',
      createdBy: 'ai_controlled_executor',
      operationDraftSchema: 'OperationDraft.create_task.v1',
    };
  }

  private validateCreateTaskPayload(payload: Record<string, unknown>) {
    const title = this.clean(payload.title);
    if (!title) {
      throw new BadRequestException('create_task draft requires title.');
    }
    return {
      ...payload,
      title,
      dueAt: this.clean(payload.dueAt) ?? this.clean(payload.due_at),
      estimatedMinutes: this.readInteger(payload.estimatedMinutes, 60),
      taskBookName: this.clean(payload.taskBookName) ?? '默认任务本',
      priority: this.clean(payload.priority) ?? 'normal',
      status: this.clean(payload.status) ?? 'pending',
      source: 'ai_confirmed',
      createdBy: 'ai_controlled_executor',
    };
  }

  private looksLikeCreateTaskRequest(value: string) {
    return /任务|task/i.test(value) && /创建|新建|添加|加一个|帮我/i.test(value);
  }

  private extractTaskTitle(value: string) {
    if (/数据库/.test(value) && /作业/.test(value)) {
      return '数据库作业';
    }
    const cleaned = value
      .replace(/帮我|请|创建|新建|添加|加一个|一个|任务|截止|明天|今天|后天|的/g, '')
      .replace(/[，。,.]/g, ' ')
      .trim();
    return cleaned.length > 0 ? cleaned.slice(0, 60) : 'AI 创建的任务';
  }

  private inferDueAt(value: string) {
    const now = new Date();
    if (/明天/.test(value)) {
      now.setDate(now.getDate() + 1);
    } else if (/后天/.test(value)) {
      now.setDate(now.getDate() + 2);
    } else if (!/今天/.test(value)) {
      return null;
    }
    now.setHours(23, 59, 0, 0);
    return now.toISOString();
  }

  private validateProviderBaseUrl(value: string) {
    let parsed: URL;
    try {
      parsed = new URL(value);
    } catch {
      throw new BadRequestException('AI Provider Base URL must be a valid URL.');
    }
    if (!['http:', 'https:'].includes(parsed.protocol)) {
      throw new BadRequestException('AI Provider Base URL must use http or https.');
    }
    if (!parsed.hostname) {
      throw new BadRequestException('AI Provider Base URL requires a host.');
    }
    return parsed.toString().replace(/\/$/, '');
  }

  private async callStructuredModel(
    provider: ProviderConfig,
    apiKey: string,
    recentMessages: Array<{ role: string; content: string }>,
    serverContext: Record<string, unknown>,
  ) {
    const prompt = [
      {
        role: 'system',
        content:
          '你是 FlowPlanV2 的 AI 助手。你只能读取给定的服务端摘要上下文；不要声称已经直接写入数据库。当前 MVP 聊天流里，唯一允许生成的写操作草案是 create_task，其他操作必须 answer_only。请输出严格 JSON，不要 Markdown。JSON 结构为 {"assistant_message":"中文回复","operation_drafts":[{"title":"","summary":"","proposed_action":"create_task|answer_only","target_type":"task","target_id":"","risk_level":"low","proposed_payload":{"title":"","dueAt":"ISO-8601 或 YYYY-MM-DD 23:59","estimatedMinutes":60,"taskBookName":"默认任务本","priority":"normal","notes":""}}]}。当用户说“帮我创建一个明天截止的数据库作业任务”时，只生成一个 create_task 草案，不要写库。',
      },
      {
        role: 'system',
        content: `服务端只读摘要上下文：${JSON.stringify(serverContext).slice(0, 18000)}`,
      },
      ...recentMessages.map((message) => ({
        role: message.role === 'assistant' ? 'assistant' : 'user',
        content: message.content,
      })),
    ];
    const content = await this.callModel(provider, apiKey, prompt);
    const parsed = this.parseModelJson(content);
    return {
      assistantContent:
        this.clean(parsed.assistant_message) ??
        this.clean(parsed.assistantMessage) ??
        content,
      drafts: Array.isArray(parsed.operation_drafts)
        ? (parsed.operation_drafts as ModelDraft[])
        : Array.isArray(parsed.operationDrafts)
          ? (parsed.operationDrafts as ModelDraft[])
          : [],
      usage: this.asRecord(parsed.usage),
    };
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
      throw new Error('AI API response did not contain message content.');
    }
    return content;
  }

  private async loadProvider(userId: string, providerKey?: string) {
    const result = await this.database.query<ProviderConfig>(
      `
      SELECT
        provider_key,
        provider_type,
        display_name,
        base_url,
        model,
        api_key_ciphertext,
        status,
        temperature,
        max_output_tokens,
        options
      FROM ai_provider_configs
      WHERE user_id = $1
        AND ($2::text IS NULL OR provider_key = $2)
      ORDER BY
        CASE WHEN $2::text IS NOT NULL THEN 0 ELSE CASE WHEN is_default THEN 0 ELSE 1 END END,
        updated_at DESC
      LIMIT 1
      `,
      [userId, providerKey ?? null],
    );
    return result.rows[0] ?? null;
  }

  private readApiKey(provider: ProviderConfig) {
    if (!provider.api_key_ciphertext) {
      return null;
    }
    return this.decrypt(provider.api_key_ciphertext);
  }

  private async executeDraft(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    action: string,
    payload: Record<string, unknown>,
  ) {
    if (action === 'create_task') {
      const validated = this.validateCreateTaskPayload(payload);
      return this.createSyncObject(client, userId, deviceId, 'task_item', validated);
    }
    if (action === 'create_calendar_event' || action === 'create_actual_record') {
      return {
        status: 'blocked_by_policy',
        result: {
          action,
          note: 'Only create_task is executable in the MVP AI controlled executor.',
        },
      };
    }
    if (action === 'create_calendar_event') {
      return this.createSyncObject(client, userId, deviceId, 'calendar_event', payload);
    }
    if (action === 'create_actual_record') {
      const title = this.clean(payload.title) ?? 'AI 实际记录';
      const startAt = this.clean(payload.startAt) ?? this.clean(payload.start_at);
      const endAt = this.clean(payload.endAt) ?? this.clean(payload.end_at);
      if (!startAt || !endAt) {
        return {
          status: 'needs_more_information',
          result: { reason: 'create_actual_record requires startAt and endAt.' },
        };
      }
      const actual = await client.query<QueryResultRow>(
        `
        INSERT INTO actual_activity_logs (
          user_id,
          actual_uid,
          title,
          start_at,
          end_at,
          source_type,
          source_payload,
          status,
          confidence,
          confirmed_at
        ) VALUES ($1, $2, $3, $4::timestamptz, $5::timestamptz, 'ai_confirmed', $6::jsonb, 'confirmed', 0.7, now())
        RETURNING id::text AS id
        `,
        [userId, `ai-actual-${randomUUID()}`, title, startAt, endAt, JSON.stringify(payload)],
      );
      return { status: 'executed', result: { actualId: actual.rows[0]?.id } };
    }
    return {
      status: 'queued_for_manual_executor',
      result: {
        action,
        note: '该草案已确认，但当前 P11 只内置任务、日程、实际记录的安全执行器，其余动作等待后续模块执行。',
      },
    };
  }

  private async createSyncObject(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    objectType: string,
    payload: Record<string, unknown>,
  ) {
    const uid = `${objectType}-ai-${randomUUID()}`;
    const inserted = await client.query<QueryResultRow>(
      `
      INSERT INTO sync_objects (
        user_id,
        object_type,
        uid,
        payload,
        origin_device_id,
        last_modified_device_id
      ) VALUES ($1, $2, $3, $4::jsonb, $5, $5)
      RETURNING id::text AS id, server_version AS "serverVersion"
      `,
      [userId, objectType, uid, JSON.stringify({ ...payload, uid, source: 'ai_confirmed' }), deviceId],
    );
    await client.query(
      `
      INSERT INTO sync_changes (
        user_id,
        device_id,
        server_object_id,
        object_type,
        action,
        server_version,
        payload
      ) VALUES ($1, $2, $3, $4, 'upsert', $5, $6::jsonb)
      `,
      [
        userId,
        deviceId,
        inserted.rows[0].id,
        objectType,
        inserted.rows[0].serverVersion,
        JSON.stringify({ ...payload, uid, source: 'ai_confirmed' }),
      ],
    );
    await this.recordAudit(client, userId, deviceId, 'ai.executor.create_task', {
      targetType: objectType,
      targetId: inserted.rows[0].id,
      objectType,
      uid,
      payload,
    });
    return {
      status: 'executed',
      result: { objectType, objectId: inserted.rows[0].id, uid },
    };
  }

  private async recordAudit(
    client: Pick<DatabaseService | TransactionClient, 'query'>,
    userId: string,
    deviceId: string,
    action: string,
    details: Record<string, unknown>,
  ) {
    await client.query(
      `
      INSERT INTO audit_logs (
        user_id,
        device_id,
        actor,
        action,
        entity_type,
        entity_id,
        summary,
        metadata
      ) VALUES ($1, $2, 'ai', $3, $4, $5, $6, $7::jsonb)
      `,
      [
        userId,
        deviceId,
        action,
        String(details.targetType ?? 'ai'),
        details.targetId ? String(details.targetId) : null,
        action,
        JSON.stringify(details),
      ],
    );
  }

  private sanitizePayload(row: QueryResultRow) {
    const payload = this.asRecord(row.payload);
    return {
      id: row.id,
      uid: row.uid,
      title: payload.title ?? payload.name ?? payload.summary,
      status: payload.status,
      startAt: payload.startAt ?? payload.startTime ?? payload.start,
      endAt: payload.endAt ?? payload.endTime ?? payload.end,
      dueAt: payload.dueAt ?? payload.dueDate,
      priority: payload.priority,
      location: payload.location,
      updatedAt: row.updatedAt,
    };
  }

  private parseModelJson(content: string) {
    try {
      return this.asRecord(JSON.parse(content));
    } catch {
      const match = content.match(/\{[\s\S]*\}/);
      if (!match) {
        return { assistant_message: content, operation_drafts: [] };
      }
      try {
        return this.asRecord(JSON.parse(match[0]));
      } catch {
        return { assistant_message: content, operation_drafts: [] };
      }
    }
  }

  private encrypt(value: string) {
    const iv = randomBytes(12);
    const cipher = createCipheriv('aes-256-gcm', this.secretKey(), iv);
    const encrypted = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
    const tag = cipher.getAuthTag();
    return [iv, tag, encrypted].map((part) => part.toString('base64')).join('.');
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
    const secret =
      process.env.AI_CONFIG_SECRET ??
      process.env.FLOWPLANV2_DATABASE_URL ??
      process.env.DATABASE_URL ??
      'flowplanv2-local-development-secret';
    return createHash('sha256').update(secret).digest();
  }

  private summarize(value: string) {
    const cleaned = value.replace(/\s+/g, ' ').trim();
    return cleaned.length > 40 ? `${cleaned.slice(0, 40)}...` : cleaned;
  }

  private readLimit(value: string | undefined, fallback: number) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? Math.max(1, Math.min(200, Math.trunc(parsed))) : fallback;
  }

  private readOffset(value: string | undefined) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? Math.max(0, Math.trunc(parsed)) : 0;
  }

  private readNumber(value: unknown, fallback: number) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  private readInteger(value: unknown, fallback: number) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? Math.max(1, Math.trunc(parsed)) : fallback;
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
