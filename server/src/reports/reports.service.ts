import { BadRequestException, Injectable } from '@nestjs/common';
import { createDecipheriv, createHash } from 'node:crypto';
import { QueryResultRow } from 'pg';
import { FlowPlanRequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import { ModelsService } from '../models/models.service';

export interface ReportsQuery {
  reportType?: string;
  status?: string;
  date?: string;
  limit?: string;
  locationId?: string;
}

type ReportSnapshot = Record<string, unknown> & {
  range?: { start?: string; end?: string };
  actuals?: unknown[];
  taskWork?: unknown[];
  activitySegments?: unknown[];
  tasks?: unknown[];
  schedules?: unknown[];
  files?: unknown[];
  weather?: unknown;
};

type AiProviderRow = QueryResultRow & {
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

@Injectable()
export class ReportsService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
    private readonly modelsService: ModelsService,
  ) {}

  async reports(query: ReportsQuery, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = this.readLimit(query.limit, 80);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        report_uid AS "reportUid",
        report_type AS "reportType",
        period_start AS "periodStart",
        period_end AS "periodEnd",
        title,
        summary_markdown AS "contentMarkdown",
        metrics,
        status,
        created_at AS "createdAt",
        updated_at AS "updatedAt",
        confirmed_at AS "confirmedAt"
      FROM report_documents
      WHERE user_id = $1
        AND ($2::text IS NULL OR report_type = $2)
        AND ($3::text IS NULL OR status = $3)
      ORDER BY period_start DESC
      LIMIT $4
      `,
      [userId, this.clean(query.reportType), this.clean(query.status), limit],
    );
    return { items: result.rows };
  }

  async report(reportId: string, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const report = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        report_uid AS "reportUid",
        report_type AS "reportType",
        period_start AS "periodStart",
        period_end AS "periodEnd",
        title,
        summary_markdown AS "contentMarkdown",
        metrics,
        source_snapshot AS "sourceSnapshot",
        status,
        created_at AS "createdAt",
        updated_at AS "updatedAt",
        confirmed_at AS "confirmedAt"
      FROM report_documents
      WHERE user_id = $1 AND id = $2
      LIMIT 1
      `,
      [userId, reportId],
    );
    const row = report.rows[0];
    if (!row) throw new BadRequestException('report not found');
    const entries = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        entry_type AS "entryType",
        entry_type AS "claimType",
        title,
        body,
        order_index AS "orderIndex",
        payload_json AS payload
      FROM report_entries
      WHERE user_id = $1 AND report_id = $2
      ORDER BY order_index ASC
      `,
      [userId, reportId],
    );
    const evidence = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        entry_id::text AS "entryId",
        source_type AS "sourceType",
        source_id AS "sourceId",
        evidence_type AS "evidenceType",
        summary,
        payload_json AS payload
      FROM report_evidence_links
      WHERE user_id = $1 AND report_id = $2
      ORDER BY created_at ASC
      `,
      [userId, reportId],
    );
    return { report: row, entries: entries.rows, evidence: evidence.rows };
  }

  async generateReport(body: Record<string, unknown>, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const type = this.clean(body.reportType) ?? 'daily';
    const { start, end } = this.period(type, body.date, body.periodStart, body.periodEnd);
    const activeModel = await this.modelsService.activeProfile(userId, 'report_template.v1');
    const modelRun = await this.modelsService.startRun(userId, 'report_template.v1', {
      source: 'reports.generateReport',
      targetType: 'report_document',
      inputSummary: {
        reportType: type,
        periodStart: start.toISOString(),
        periodEnd: end.toISOString(),
        templateFirst: true,
        profile: activeModel.ruleProfile,
      },
    });
    const snapshot = await this.sourceSnapshot(userId, start, end);
    const markdown = await this.renderReport(userId, type, start, snapshot);
    const reportUid = `report:${type}:${start.toISOString().slice(0, 10)}`;
    const reportId = await this.database.transaction(async (client) => {
      const result = await client.query<QueryResultRow>(
        `
        INSERT INTO report_documents (
          user_id, report_uid, report_type, period_start, period_end, title,
          summary_markdown, metrics, source_snapshot, status
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb, $9::jsonb, 'draft')
        ON CONFLICT (user_id, report_uid) DO UPDATE SET
          title = EXCLUDED.title,
          summary_markdown = EXCLUDED.summary_markdown,
          metrics = EXCLUDED.metrics,
          source_snapshot = EXCLUDED.source_snapshot,
          status = 'draft',
          confirmed_at = NULL,
          updated_at = now()
        RETURNING id::text AS id
        `,
        [
          userId,
          reportUid,
          type,
          start,
          end,
          `${start.toISOString().slice(0, 10)} ${this.reportName(type)}`,
          markdown,
          JSON.stringify(this.metrics(snapshot)),
          JSON.stringify(snapshot),
        ],
      );
      const id = String(result.rows[0]?.id);
      await client.query('DELETE FROM report_evidence_links WHERE user_id = $1 AND report_id = $2', [userId, id]);
      await client.query('DELETE FROM report_entries WHERE user_id = $1 AND report_id = $2', [userId, id]);
      await this.insertReportEntries(client, userId, id, snapshot);
      await this.recordAudit(client, userId, deviceId, 'report.generated', {
        reportId: id,
        reportType: type,
        periodStart: start.toISOString(),
        periodEnd: end.toISOString(),
        modelRunId: modelRun.id,
        modelVersion: activeModel.versionKey,
        generationMode: 'template',
      });
      return id;
    });

    await this.modelsService.completeRun(userId, modelRun.id, {
      status: 'succeeded',
      outputSummary: {
        reportId,
        reportType: type,
        metrics: this.metrics(snapshot),
        generationMode: body.useLlm === true ? 'template_then_optional_llm' : 'template',
      },
      confidence: 0.82,
      usedLlm: body.useLlm === true,
    });

    if (body.useLlm === true) {
      await this.polishReport(reportId, context, { silentFallback: true });
    }
    return {
      ...(await this.report(reportId, context)),
      modelRunId: modelRun.id,
      modelUsed: body.useLlm === true ? 'hybrid' : 'rule_learned',
      modelVersion: activeModel.versionKey,
    };
  }

  async updateReport(
    reportId: string,
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.database.transaction(async (client) => {
        await client.query(
          `
          UPDATE report_documents
          SET
            title = COALESCE($3, title),
          summary_markdown = COALESCE($4, summary_markdown),
          updated_at = now()
        WHERE user_id = $1 AND id = $2
          `,
          [userId, reportId, this.clean(body.title), this.clean(body.contentMarkdown)],
        );
        const userNote = this.clean(body.userNote);
        if (userNote) {
          const entryId = await this.insertReportEntry(client, userId, reportId, {
            type: 'user_note',
            title: '用户补充',
            body: userNote,
            orderIndex: 900,
            payload: { source: 'manual_edit' },
          });
          await this.insertEvidence(client, userId, reportId, entryId, {
            sourceType: 'user_note',
            sourceId: reportId,
            evidenceType: 'user_note',
            summary: '用户在编辑报告时添加的补充说明',
            payload: { source: 'manual_edit' },
          });
        }
          await this.recordAudit(client, userId, deviceId, 'report.updated', {
            reportId,
            userEdited: true,
            hasUserNote: Boolean(userNote),
          });
          await this.modelsService.recordFeedback(client, userId, deviceId, 'report_template.v1', {
            targetType: 'report_document',
            targetId: reportId,
            feedbackType: 'edited',
            outcome: 'modified',
            source: 'reports.updateReport',
            feedbackPayload: {
              hasUserNote: Boolean(userNote),
              titleChanged: Boolean(this.clean(body.title)),
              contentChanged: Boolean(this.clean(body.contentMarkdown)),
            },
          });
        });
    return { ok: true };
  }

  async confirmReport(reportId: string, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.database.transaction(async (client) => {
      await client.query(
        `
        UPDATE report_documents
        SET status = 'confirmed', confirmed_at = now(), updated_at = now()
        WHERE user_id = $1 AND id = $2
        `,
        [userId, reportId],
      );
        await this.recordAudit(client, userId, deviceId, 'report.confirmed', { reportId });
        await this.modelsService.recordFeedback(client, userId, deviceId, 'report_template.v1', {
          targetType: 'report_document',
          targetId: reportId,
          feedbackType: 'accepted',
          outcome: 'confirmed',
          source: 'reports.confirmReport',
          feedbackPayload: {},
        });
      });
    return { ok: true };
  }

  async polishReport(
    reportId: string,
    context: FlowPlanRequestContext,
    options: { silentFallback?: boolean } = {},
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const detail = await this.report(reportId, context);
    try {
      const polished = await this.callOptionalReportLlm(userId, {
        kind: 'report',
        title: String(detail.report.title ?? ''),
        markdown: String(detail.report.contentMarkdown ?? ''),
        entries: detail.entries,
      });
      const updatedMarkdown = [
        String(detail.report.contentMarkdown ?? '').trim(),
        '',
        '## AI 润色摘要',
        '',
        polished.trim(),
        '',
        '> AI 润色只基于本报告的事实摘要，不会把候选推断自动确认为事实。',
      ].join('\n');
      await this.database.transaction(async (client) => {
        await client.query(
          `
          UPDATE report_documents
          SET summary_markdown = $3, updated_at = now()
          WHERE user_id = $1 AND id = $2
          `,
          [userId, reportId, updatedMarkdown],
        );
        const entryId = await this.insertReportEntry(client, userId, reportId, {
          type: 'ai_summary',
          title: 'AI 润色摘要',
          body: polished.trim(),
          orderIndex: 900,
          payload: { provider: 'openai_compatible', mode: 'optional_polish' },
        });
        await this.insertEvidence(client, userId, reportId, entryId, {
          sourceType: 'report_document',
          sourceId: reportId,
          evidenceType: 'ai_summary',
          summary: 'AI 润色基于模板报告和条目摘要生成，原始事实和证据链保留。',
          payload: { originalReportId: reportId },
        });
        await this.recordAudit(client, userId, deviceId, 'report.llm_polished', { reportId });
      });
      return { ok: true, llmApplied: true, report: await this.report(reportId, context) };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.recordAudit(this.database, userId, deviceId, 'report.llm_polish.failed', {
        reportId,
        error: message,
        fallback: 'template_report_kept',
      });
      if (!options.silentFallback) {
        return {
          ok: true,
          llmApplied: false,
          fallback: 'template_report_kept',
          error: message,
          report: detail,
        };
      }
      return { ok: true, llmApplied: false, fallback: 'template_report_kept' };
    }
  }

  async diary(query: ReportsQuery, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const limit = this.readLimit(query.limit, 80);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        diary_uid AS "diaryUid",
        entry_date AS date,
        title,
        body_markdown AS "contentMarkdown",
        status,
        created_at AS "createdAt",
        updated_at AS "updatedAt",
        confirmed_at AS "confirmedAt"
      FROM diary_entries
      WHERE user_id = $1 AND ($2::text IS NULL OR status = $2)
      ORDER BY entry_date DESC
      LIMIT $3
      `,
      [userId, this.clean(query.status), limit],
    );
    return { items: result.rows };
  }

  async generateDiary(body: Record<string, unknown>, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const { start, end } = this.period('daily', body.date, body.periodStart, body.periodEnd);
    const activeModel = await this.modelsService.activeProfile(userId, 'report_template.v1');
    const modelRun = await this.modelsService.startRun(userId, 'report_template.v1', {
      source: 'reports.generateDiary',
      targetType: 'diary_entry',
      inputSummary: {
        periodStart: start.toISOString(),
        periodEnd: end.toISOString(),
        templateFirst: true,
        profile: activeModel.ruleProfile,
      },
    });
    const snapshot = await this.sourceSnapshot(userId, start, end);
    const bodyMarkdown = await this.renderDiary(userId, start, snapshot);
    const diaryUid = `diary:${start.toISOString().slice(0, 10)}`;
    const diary = await this.database.transaction(async (client) => {
      const result = await client.query<QueryResultRow>(
        `
        INSERT INTO diary_entries (
          user_id, diary_uid, entry_date, title, body_markdown, weather, status
        ) VALUES ($1, $2, $3::date, $4, $5, $6::jsonb, 'draft')
        ON CONFLICT (user_id, diary_uid) DO UPDATE SET
          title = EXCLUDED.title,
          body_markdown = EXCLUDED.body_markdown,
          weather = EXCLUDED.weather,
          status = 'draft',
          confirmed_at = NULL,
          updated_at = now()
        RETURNING id::text AS id
        `,
        [
          userId,
          diaryUid,
          start.toISOString().slice(0, 10),
          `${start.toISOString().slice(0, 10)} 日记草稿`,
          bodyMarkdown,
          JSON.stringify(snapshot.weather ?? {}),
        ],
      );
        await this.recordAudit(client, userId, deviceId, 'diary.generated', {
          diaryId: result.rows[0]?.id,
          modelRunId: modelRun.id,
          modelVersion: activeModel.versionKey,
          generationMode: 'template',
        });
        return String(result.rows[0]?.id);
      });
      await this.modelsService.completeRun(userId, modelRun.id, {
        status: 'succeeded',
        outputSummary: {
          diaryId: diary,
          generationMode: body.useLlm === true ? 'template_then_optional_llm' : 'template',
        },
        confidence: 0.82,
        usedLlm: body.useLlm === true,
      });
      if (body.useLlm === true) {
        await this.polishDiary(diary, context, { silentFallback: true });
      }
      return {
        ok: true,
        diaryId: diary,
        modelRunId: modelRun.id,
        modelUsed: body.useLlm === true ? 'hybrid' : 'rule_learned',
        modelVersion: activeModel.versionKey,
      };
    }

  async updateDiary(
    diaryId: string,
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.database.transaction(async (client) => {
      await client.query(
        `
        UPDATE diary_entries
        SET title = COALESCE($3, title), body_markdown = COALESCE($4, body_markdown), updated_at = now()
        WHERE user_id = $1 AND id = $2
        `,
        [userId, diaryId, this.clean(body.title), this.clean(body.contentMarkdown)],
      );
        await this.recordAudit(client, userId, deviceId, 'diary.updated', {
          diaryId,
          userEdited: true,
        });
        await this.modelsService.recordFeedback(client, userId, deviceId, 'report_template.v1', {
          targetType: 'diary_entry',
          targetId: diaryId,
          feedbackType: 'edited',
          outcome: 'modified',
          source: 'reports.updateDiary',
          feedbackPayload: {
            titleChanged: Boolean(this.clean(body.title)),
            contentChanged: Boolean(this.clean(body.contentMarkdown)),
          },
        });
      });
    return { ok: true };
  }

  async confirmDiary(diaryId: string, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.database.transaction(async (client) => {
      await client.query(
        `
        UPDATE diary_entries
        SET status = 'confirmed', confirmed_at = now(), updated_at = now()
        WHERE user_id = $1 AND id = $2
        `,
        [userId, diaryId],
      );
        await this.recordAudit(client, userId, deviceId, 'diary.confirmed', { diaryId });
        await this.modelsService.recordFeedback(client, userId, deviceId, 'report_template.v1', {
          targetType: 'diary_entry',
          targetId: diaryId,
          feedbackType: 'accepted',
          outcome: 'confirmed',
          source: 'reports.confirmDiary',
          feedbackPayload: {},
        });
      });
    return { ok: true };
  }

  async polishDiary(
    diaryId: string,
    context: FlowPlanRequestContext,
    options: { silentFallback?: boolean } = {},
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const row = await this.database.query<QueryResultRow>(
      `
      SELECT id::text AS id, title, body_markdown AS "contentMarkdown"
      FROM diary_entries
      WHERE user_id = $1 AND id = $2
      LIMIT 1
      `,
      [userId, diaryId],
    );
    const diary = row.rows[0];
    if (!diary) throw new BadRequestException('diary not found');
    try {
      const polished = await this.callOptionalReportLlm(userId, {
        kind: 'diary',
        title: String(diary.title ?? ''),
        markdown: String(diary.contentMarkdown ?? ''),
        entries: [],
      });
      const updatedMarkdown = [
        String(diary.contentMarkdown ?? '').trim(),
        '',
        '## AI 润色草稿',
        '',
        polished.trim(),
        '',
        '> 日记默认私密，AI 润色不会自动推送。',
      ].join('\n');
      await this.database.transaction(async (client) => {
        await client.query(
          `
          UPDATE diary_entries
          SET body_markdown = $3, updated_at = now()
          WHERE user_id = $1 AND id = $2
          `,
          [userId, diaryId, updatedMarkdown],
        );
        await this.recordAudit(client, userId, deviceId, 'diary.llm_polished', { diaryId });
      });
      return { ok: true, llmApplied: true };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.recordAudit(this.database, userId, deviceId, 'diary.llm_polish.failed', {
        diaryId,
        error: message,
        fallback: 'template_diary_kept',
      });
      if (!options.silentFallback) {
        return { ok: true, llmApplied: false, fallback: 'template_diary_kept', error: message };
      }
      return { ok: true, llmApplied: false, fallback: 'template_diary_kept' };
    }
  }

  async templates(context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    await this.ensureDefaultTemplates(userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        name,
        template_type AS "templateType",
        content_template AS "contentTemplate",
        variables_json AS variables,
        is_default AS "isDefault",
        updated_at AS "updatedAt"
      FROM report_templates
      WHERE user_id = $1
      ORDER BY template_type, is_default DESC, name
      `,
      [userId],
    );
    return { items: result.rows, defaults: this.defaultTemplateNames() };
  }

  async upsertTemplate(body: Record<string, unknown>, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const name = this.clean(body.name) ?? '默认模板';
    const templateType = this.clean(body.templateType) ?? 'daily_report';
    const content = this.clean(body.contentTemplate) ?? '# {{date}}\n\n{{actual_logs}}';
    const isDefault = body.isDefault === true;
    const result = await this.database.transaction(async (client) => {
      if (isDefault) {
        await client.query(
          'UPDATE report_templates SET is_default = false WHERE user_id = $1 AND template_type = $2',
          [userId, templateType],
        );
      }
      const row = await client.query<QueryResultRow>(
        `
        INSERT INTO report_templates (user_id, name, template_type, content_template, variables_json, is_default)
        VALUES ($1, $2, $3, $4, $5::jsonb, $6)
        ON CONFLICT (user_id, template_type, name) DO UPDATE SET
          content_template = EXCLUDED.content_template,
          variables_json = EXCLUDED.variables_json,
          is_default = EXCLUDED.is_default,
          updated_at = now()
        RETURNING id::text AS id
        `,
        [userId, name, templateType, content, JSON.stringify(this.asArray(body.variables)), isDefault],
      );
      await this.recordAudit(client, userId, deviceId, 'report.template.upserted', {
        templateId: row.rows[0]?.id,
        templateType,
      });
      return row.rows[0];
    });
    return { ok: true, template: result };
  }

  async pushChannels(context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        channel_type AS "channelType",
        name,
        status,
        config_json AS config,
        last_test_at AS "lastTestAt",
        last_error AS "lastError",
        updated_at AS "updatedAt"
      FROM push_channels
      WHERE user_id = $1
      ORDER BY channel_type, name
      `,
      [userId],
    );
    return { items: result.rows };
  }

  async upsertPushChannel(body: Record<string, unknown>, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const channelType = this.clean(body.channelType) ?? 'webhook';
    const name = this.clean(body.name) ?? channelType;
    const result = await this.database.transaction(async (client) => {
      const row = await client.query<QueryResultRow>(
        `
        INSERT INTO push_channels (user_id, channel_type, name, status, config_json)
        VALUES ($1, $2, $3, $4, $5::jsonb)
        RETURNING id::text AS id
        `,
        [userId, channelType, name, this.clean(body.status) ?? 'enabled', JSON.stringify(this.asRecord(body.config))],
      );
      await this.recordAudit(client, userId, deviceId, 'push.channel.created', {
        channelId: row.rows[0]?.id,
        channelType,
      });
      return row.rows[0];
    });
    return { ok: true, channel: result };
  }

  async pushReport(
    reportId: string,
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const channelId = this.clean(body.channelId);
    const report = await this.report(reportId, context);
    const channels = await this.database.query<QueryResultRow>(
      `
      SELECT * FROM push_channels
      WHERE user_id = $1 AND status = 'enabled' AND ($2::uuid IS NULL OR id = $2)
      ORDER BY created_at ASC
      `,
      [userId, channelId],
    );
    if (channels.rows.length === 0) {
      throw new BadRequestException('No enabled push channel is configured.');
    }
    const deliveries: string[] = [];
    await this.database.transaction(async (client) => {
      for (const channel of channels.rows) {
        const deliveryUid = `push:${reportId}:${channel.id}:${Date.now()}`;
        const payload = {
          title: report.report.title,
          summary: String(report.report.contentMarkdown ?? '').slice(0, 1200),
          reportId,
          reportUid: report.report.reportUid,
        };
        const row = await client.query<QueryResultRow>(
          `
          INSERT INTO report_push_deliveries (
            user_id, delivery_uid, report_id, channel, target, payload, status, attempts
          ) VALUES ($1, $2, $3, $4, $5, $6::jsonb, 'pending', 0)
          RETURNING id::text AS id
          `,
          [
            userId,
            deliveryUid,
            reportId,
            String(channel.channel_type),
            this.targetForChannel(this.asRecord(channel.config_json)),
            JSON.stringify(payload),
          ],
        );
        deliveries.push(String(row.rows[0]?.id));
      }
      await this.recordAudit(client, userId, deviceId, 'report.push.queued', { reportId, deliveries });
    });
    const results = [];
    for (const deliveryId of deliveries) {
      results.push(await this.trySendDelivery(deliveryId, context));
    }
    return { ok: true, deliveries, results };
  }

  async pushDeliveries(query: ReportsQuery, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        delivery_uid AS "deliveryUid",
        report_id::text AS "reportId",
        channel,
        target,
        status,
        attempts,
        last_error AS "lastError",
        payload,
        sent_at AS "sentAt",
        created_at AS "createdAt",
        updated_at AS "updatedAt"
      FROM report_push_deliveries
      WHERE user_id = $1 AND ($2::text IS NULL OR status = $2)
      ORDER BY created_at DESC
      LIMIT $3
      `,
      [userId, this.clean(query.status), this.readLimit(query.limit, 100)],
    );
    return { items: result.rows };
  }

  async retryDelivery(deliveryId: string, context: FlowPlanRequestContext) {
    return this.trySendDelivery(deliveryId, context);
  }

  async weatherLocations(context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT id::text AS id, name, latitude, longitude, timezone, is_default AS "isDefault", updated_at AS "updatedAt"
      FROM weather_locations
      WHERE user_id = $1
      ORDER BY is_default DESC, name
      `,
      [userId],
    );
    return { items: result.rows };
  }

  async upsertWeatherLocation(body: Record<string, unknown>, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const latitude = Number(body.latitude);
    const longitude = Number(body.longitude);
    if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      throw new BadRequestException('latitude and longitude are required');
    }
    const isDefault = body.isDefault !== false;
    const result = await this.database.transaction(async (client) => {
      if (isDefault) {
        await client.query('UPDATE weather_locations SET is_default = false WHERE user_id = $1', [userId]);
      }
      const row = await client.query<QueryResultRow>(
        `
        INSERT INTO weather_locations (user_id, name, latitude, longitude, timezone, is_default)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id::text AS id
        `,
        [
          userId,
          this.clean(body.name) ?? '默认地点',
          latitude,
          longitude,
          this.clean(body.timezone) ?? 'auto',
          isDefault,
        ],
      );
      await this.recordAudit(client, userId, deviceId, 'weather.location.created', {
        locationId: row.rows[0]?.id,
        isDefault,
        note: 'Manual location only; no GPS collection is implemented.',
      });
      return row.rows[0];
    });
    return { ok: true, location: result };
  }

  async refreshWeather(locationId: string, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const location = await this.database.query<QueryResultRow>(
      'SELECT * FROM weather_locations WHERE user_id = $1 AND id = $2 LIMIT 1',
      [userId, locationId],
    );
    const row = location.rows[0];
    if (!row) throw new BadRequestException('weather location not found');
    let summary = '天气暂不可用';
    let payload: Record<string, unknown> = {};
    try {
      const url = new URL('https://api.open-meteo.com/v1/forecast');
      url.searchParams.set('latitude', String(row.latitude));
      url.searchParams.set('longitude', String(row.longitude));
      url.searchParams.set('daily', 'temperature_2m_max,temperature_2m_min,precipitation_probability_max');
      url.searchParams.set('timezone', String(row.timezone ?? 'auto'));
      const response = await fetch(url);
      const raw = await response.text();
      if (!response.ok) {
        throw new Error(`Open-Meteo ${response.status}: ${raw.slice(0, 300)}`);
      }
      payload = raw ? (JSON.parse(raw) as Record<string, unknown>) : {};
      summary = this.weatherSummaryFromPayload(payload);
    } catch (error) {
      summary = `天气刷新失败：${error instanceof Error ? error.message : String(error)}`;
    }
    await this.database.transaction(async (client) => {
      await client.query(
        `
        INSERT INTO weather_cache (
          user_id, location_id, provider_type, forecast_type, forecast_time, payload_json, summary, expires_at
        ) VALUES ($1, $2, 'open_meteo', 'daily', now(), $3::jsonb, $4, now() + interval '6 hours')
        `,
        [userId, locationId, JSON.stringify(payload), summary],
      );
      await this.recordAudit(client, userId, deviceId, 'weather.refreshed', {
        locationId,
        summary,
        provider: 'open_meteo',
      });
    });
    return { ok: true, summary, payload };
  }

  async weatherSummary(query: ReportsQuery, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        c.id::text AS id,
        l.name AS "locationName",
        c.provider_type AS "providerType",
        c.forecast_type AS "forecastType",
        c.summary,
        c.expires_at AS "expiresAt",
        c.created_at AS "createdAt"
      FROM weather_cache c
      JOIN weather_locations l ON l.id = c.location_id
      WHERE c.user_id = $1 AND ($2::uuid IS NULL OR c.location_id = $2)
      ORDER BY c.created_at DESC
      LIMIT 20
      `,
      [userId, this.clean(query.locationId)],
    );
    return { items: result.rows };
  }

  private async trySendDelivery(deliveryId: string, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const delivery = await this.database.query<QueryResultRow>(
      `
      SELECT d.*, c.config_json
      FROM report_push_deliveries d
      LEFT JOIN push_channels c ON c.user_id = d.user_id AND c.channel_type = d.channel
      WHERE d.user_id = $1 AND d.id = $2
      LIMIT 1
      `,
      [userId, deliveryId],
    );
    const row = delivery.rows[0];
    if (!row) throw new BadRequestException('delivery not found');
    const config = this.asRecord(row.config_json);
    const payload = this.asRecord(row.payload);
    try {
      let response: Response;
      if (row.channel === 'webhook' && typeof config.url === 'string') {
        response = await fetch(config.url, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(payload),
        });
      } else if (row.channel === 'telegram' && typeof config.botToken === 'string' && typeof config.chatId === 'string') {
        response = await fetch(`https://api.telegram.org/bot${config.botToken}/sendMessage`, {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify({
            chat_id: config.chatId,
            text: `${payload.title ?? 'FlowPlan 报告'}\n\n${payload.summary ?? ''}`,
            disable_web_page_preview: true,
          }),
        });
      } else {
        throw new Error('push channel is not configured for automatic sending');
      }
      const text = await response.text();
      if (!response.ok) {
        throw new Error(`${row.channel} returned ${response.status}: ${text.slice(0, 500)}`);
      }
      await this.database.query(
        `
        UPDATE report_push_deliveries
        SET status = 'sent', attempts = attempts + 1, sent_at = now(), updated_at = now(), last_error = NULL
        WHERE user_id = $1 AND id = $2
        `,
        [userId, deliveryId],
      );
      return { ok: true, deliveryId, status: 'sent' };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      await this.database.query(
        `
        UPDATE report_push_deliveries
        SET status = 'failed', attempts = attempts + 1, last_error = $3, updated_at = now()
        WHERE user_id = $1 AND id = $2
        `,
        [userId, deliveryId, message],
      );
      return { ok: false, deliveryId, status: 'failed', error: message };
    }
  }

  private async sourceSnapshot(userId: string, start: Date, end: Date): Promise<ReportSnapshot> {
    const [actuals, workLogs, segments, tasks, schedules, files, weather] = await Promise.all([
      this.database.query<QueryResultRow>(
        'SELECT id::text AS id, title, start_at AS "startAt", end_at AS "endAt", status, source_type AS "sourceType" FROM actual_activity_logs WHERE user_id = $1 AND start_at >= $2 AND start_at < $3 ORDER BY start_at',
        [userId, start, end],
      ),
      this.database.query<QueryResultRow>(
        'SELECT task_id AS "taskId", SUM(duration_minutes)::int AS minutes FROM task_work_logs WHERE user_id = $1 AND start_at >= $2 AND start_at < $3 AND status = $4 GROUP BY task_id',
        [userId, start, end, 'confirmed'],
      ),
      this.database.query<QueryResultRow>(
        'SELECT id::text AS id, label AS title, start_at AS "startAt", end_at AS "endAt", confidence, status FROM activity_segments WHERE user_id = $1 AND start_at >= $2 AND start_at < $3 ORDER BY start_at',
        [userId, start, end],
      ),
      this.database.query<QueryResultRow>(
        "SELECT id::text AS id, uid, payload FROM sync_objects WHERE user_id = $1 AND deleted_at IS NULL AND object_type = ANY($2::text[]) ORDER BY updated_at DESC LIMIT 100",
        [userId, ['task', 'tasks', 'task_item', 'task_items']],
      ),
      this.database.query<QueryResultRow>(
        "SELECT id::text AS id, uid, payload FROM sync_objects WHERE user_id = $1 AND deleted_at IS NULL AND object_type = ANY($2::text[]) ORDER BY updated_at DESC LIMIT 100",
        [userId, ['calendar_event', 'calendar_events', 'event', 'events', 'task_schedule_segment']],
      ),
      this.database.query<QueryResultRow>(
        'SELECT id::text AS id, operation, source_path AS "sourcePath", target_path AS "targetPath", created_at AS "createdAt" FROM file_operation_logs WHERE user_id = $1 AND created_at >= $2 AND created_at < $3 ORDER BY created_at DESC LIMIT 50',
        [userId, start, end],
      ),
      this.database.query<QueryResultRow>(
        `
        SELECT summary, payload_json AS payload, created_at AS "createdAt", expires_at AS "expiresAt"
        FROM weather_cache
        WHERE user_id = $1
        ORDER BY created_at DESC
        LIMIT 1
        `,
        [userId],
      ),
    ]);
    return {
      range: { start: start.toISOString(), end: end.toISOString() },
      actuals: actuals.rows,
      taskWork: workLogs.rows,
      activitySegments: segments.rows,
      tasks: tasks.rows.map((row) => ({ id: row.uid ?? row.id, payload: row.payload })),
      schedules: schedules.rows.map((row) => ({ id: row.uid ?? row.id, payload: row.payload })),
      files: files.rows,
      weather: weather.rows[0] ?? null,
    };
  }

  private async renderReport(
    userId: string,
    type: string,
    start: Date,
    snapshot: ReportSnapshot,
  ) {
    const variables = this.templateVariables(type, start, snapshot);
    const templateType = `${type}_report`;
    const template =
      (await this.defaultTemplate(userId, templateType)) ?? this.builtInTemplate(templateType);
    return this.renderTemplate(template, variables);
  }

  private async renderDiary(userId: string, start: Date, snapshot: ReportSnapshot) {
    const variables = this.templateVariables('diary', start, snapshot);
    const template = (await this.defaultTemplate(userId, 'diary')) ?? this.builtInTemplate('diary');
    return this.renderTemplate(template, variables);
  }

  private async insertReportEntries(
    client: TransactionClient,
    userId: string,
    reportId: string,
    snapshot: ReportSnapshot,
  ) {
    let index = 0;
    const actuals = this.asArray(snapshot.actuals);
    const taskWork = this.asArray(snapshot.taskWork);
    const segments = this.asArray(snapshot.activitySegments);
    const files = this.asArray(snapshot.files);
    const weather = this.asRecord(snapshot.weather);

    if (actuals.length === 0) {
      const entryId = await this.insertReportEntry(client, userId, reportId, {
        type: 'fact',
        title: '已确认事实',
        body: '本周期暂无已确认实际记录。',
        orderIndex: index++,
        payload: { sourceCount: 0 },
      });
      await this.insertEvidence(client, userId, reportId, entryId, {
        sourceType: 'actual_activity_logs',
        evidenceType: 'fact',
        summary: '查询结果为空。',
      });
    } else {
      for (const item of actuals.slice(0, 8)) {
        const record = this.asRecord(item);
        const entryId = await this.insertReportEntry(client, userId, reportId, {
          type: 'fact',
          title: String(record.title ?? '实际记录'),
          body: `${record.startAt ?? ''} - ${record.endAt ?? ''}`,
          orderIndex: index++,
          payload: record,
        });
        await this.insertEvidence(client, userId, reportId, entryId, {
          sourceType: 'actual_activity_log',
          sourceId: this.clean(record.id),
          evidenceType: 'fact',
          summary: String(record.title ?? '实际记录'),
          payload: record,
        });
      }
    }

    for (const item of taskWork.slice(0, 8)) {
      const record = this.asRecord(item);
      const entryId = await this.insertReportEntry(client, userId, reportId, {
        type: 'fact',
        title: `任务投入 ${record.taskId ?? '未知任务'}`,
        body: `${record.minutes ?? 0} 分钟`,
        orderIndex: index++,
        payload: record,
      });
      await this.insertEvidence(client, userId, reportId, entryId, {
        sourceType: 'task_work_log',
        sourceId: this.clean(record.taskId),
        evidenceType: 'fact',
        summary: `${record.minutes ?? 0} 分钟已确认任务投入`,
        payload: record,
      });
    }

    for (const item of segments.filter((value) => this.asRecord(value).status !== 'confirmed').slice(0, 8)) {
      const record = this.asRecord(item);
      const entryId = await this.insertReportEntry(client, userId, reportId, {
        type: 'inferred',
        title: String(record.title ?? '待确认活动片段'),
        body: `置信度 ${Math.round(Number(record.confidence ?? 0) * 100)}%，需要人工确认后才成为事实。`,
        orderIndex: index++,
        payload: record,
      });
      await this.insertEvidence(client, userId, reportId, entryId, {
        sourceType: 'activity_segment',
        sourceId: this.clean(record.id),
        evidenceType: 'inferred',
        summary: String(record.title ?? '活动片段候选'),
        payload: record,
      });
    }

    if (files.length > 0) {
      const entryId = await this.insertReportEntry(client, userId, reportId, {
        type: 'inferred',
        title: '文件上下文',
        body: `${files.length} 条文件操作记录可作为上下文线索。`,
        orderIndex: index++,
        payload: { count: files.length },
      });
      await this.insertEvidence(client, userId, reportId, entryId, {
        sourceType: 'file_operation_logs',
        evidenceType: 'inferred',
        summary: '文件操作只作为上下文线索，不自动说明任务完成。',
        payload: { files: files.slice(0, 10) },
      });
    }

    const weatherEntryId = await this.insertReportEntry(client, userId, reportId, {
      type: 'external',
      title: '天气上下文',
      body: String(weather.summary ?? '暂无天气缓存。'),
      orderIndex: index++,
      payload: weather,
    });
    await this.insertEvidence(client, userId, reportId, weatherEntryId, {
      sourceType: 'weather_cache',
      sourceId: this.clean(weather.id),
      evidenceType: 'external',
      summary: String(weather.summary ?? '暂无天气缓存。'),
      payload: weather,
    });
  }

  private async insertReportEntry(
    client: TransactionClient,
    userId: string,
    reportId: string,
    entry: {
      type: string;
      title: string;
      body: string;
      orderIndex: number;
      payload?: Record<string, unknown>;
    },
  ) {
    const row = await client.query<QueryResultRow>(
      `
      INSERT INTO report_entries (user_id, report_id, entry_type, title, body, order_index, payload_json)
      VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)
      RETURNING id::text AS id
      `,
      [
        userId,
        reportId,
        entry.type,
        entry.title,
        entry.body,
        entry.orderIndex,
        JSON.stringify(entry.payload ?? {}),
      ],
    );
    return String(row.rows[0]?.id);
  }

  private async insertEvidence(
    client: TransactionClient,
    userId: string,
    reportId: string,
    entryId: string,
    evidence: {
      sourceType: string;
      sourceId?: string | null;
      evidenceType: string;
      summary: string;
      payload?: Record<string, unknown>;
    },
  ) {
    await client.query(
      `
      INSERT INTO report_evidence_links (
        user_id, report_id, entry_id, source_type, source_id, evidence_type, summary, payload_json
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8::jsonb)
      `,
      [
        userId,
        reportId,
        entryId,
        evidence.sourceType,
        evidence.sourceId ?? null,
        evidence.evidenceType,
        evidence.summary,
        JSON.stringify(evidence.payload ?? {}),
      ],
    );
  }

  private async defaultTemplate(userId: string, templateType: string) {
    await this.ensureDefaultTemplates(userId);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT content_template
      FROM report_templates
      WHERE user_id = $1 AND template_type = $2
      ORDER BY is_default DESC, updated_at DESC
      LIMIT 1
      `,
      [userId, templateType],
    );
    return this.clean(result.rows[0]?.content_template);
  }

  private async ensureDefaultTemplates(userId: string) {
    for (const [templateType, content] of Object.entries(this.builtInTemplates())) {
      await this.database.query(
        `
        INSERT INTO report_templates (
          user_id, name, template_type, content_template, variables_json, is_default
        ) VALUES ($1, $2, $3, $4, $5::jsonb, true)
        ON CONFLICT (user_id, template_type, name) DO NOTHING
        `,
        [
          userId,
          'FlowPlan 默认模板',
          templateType,
          content,
          JSON.stringify(Object.keys(this.templateVariableDescriptions())),
        ],
      );
    }
  }

  private templateVariables(type: string, start: Date, snapshot: ReportSnapshot) {
    const actuals = this.asArray(snapshot.actuals);
    const taskWork = this.asArray(snapshot.taskWork);
    const segments = this.asArray(snapshot.activitySegments);
    const schedules = this.asArray(snapshot.schedules);
    const tasks = this.asArray(snapshot.tasks);
    const files = this.asArray(snapshot.files);
    const weather = this.asRecord(snapshot.weather);
    return {
      date: start.toISOString().slice(0, 10),
      report_type: this.reportName(type),
      planned_events: this.bulletLines(schedules, 'payload', '暂无日程或排程片段。'),
      completed_tasks: this.bulletLines(tasks, 'payload', '暂无任务快照。'),
      actual_logs: this.bulletLines(actuals, 'title', '暂无已确认实际记录。'),
      task_work_summary:
        taskWork.length === 0
          ? '- 暂无已确认任务投入。'
          : taskWork
              .map((item) => {
                const record = this.asRecord(item);
                return `- 任务 ${record.taskId ?? '未知'}：${record.minutes ?? 0} 分钟`;
              })
              .join('\n'),
      activity_segments:
        segments.length === 0
          ? '- 暂无活动片段。'
          : segments
              .slice(0, 12)
              .map((item) => {
                const record = this.asRecord(item);
                return `- ${record.title ?? '活动片段'}（状态：${record.status ?? 'candidate'}，置信度：${Math.round(Number(record.confidence ?? 0) * 100)}%）`;
              })
              .join('\n'),
      recent_files:
        files.length === 0
          ? '- 暂无文件上下文。'
          : files
              .slice(0, 10)
              .map((item) => {
                const record = this.asRecord(item);
                return `- ${record.operation ?? 'file'} ${record.sourcePath ?? record.targetPath ?? ''}`;
              })
              .join('\n'),
      weather_summary: String(weather.summary ?? '暂无天气缓存。'),
      sync_warnings: '如存在未同步或冲突，请以同步中心状态为准。',
      tomorrow_risks: '请结合未完成任务、截止时间和明日天气手动确认。',
    };
  }

  private renderTemplate(template: string, variables: Record<string, string>) {
    return template.replace(/\{\{\s*([a-zA-Z0-9_]+)\s*\}\}/g, (_, key: string) => {
      return variables[key] ?? '';
    });
  }

  private builtInTemplate(templateType: string) {
    const templates: Record<string, string> = this.builtInTemplates();
    return templates[templateType] ?? templates.daily_report;
  }

  private builtInTemplates() {
    return {
      daily_report: [
        '# {{date}} 日报',
        '',
        '## 今日计划',
        '{{planned_events}}',
        '',
        '## 实际完成',
        '{{actual_logs}}',
        '',
        '## 任务推进',
        '{{task_work_summary}}',
        '',
        '## 待确认活动片段',
        '{{activity_segments}}',
        '',
        '## 文件上下文',
        '{{recent_files}}',
        '',
        '## 天气上下文',
        '- {{weather_summary}}',
        '',
        '## 明日风险',
        '- {{tomorrow_risks}}',
        '',
        '> 本报告由模板生成。fact / inferred / external 条目和 evidence links 保存在报告详情中；AI 润色是可选增强。',
      ].join('\n'),
      weekly_report: [
        '# {{date}} 周报',
        '',
        '## 任务推进',
        '{{task_work_summary}}',
        '',
        '## 活动摘要',
        '{{activity_segments}}',
        '',
        '## 文件上下文',
        '{{recent_files}}',
        '',
        '## 天气与外部上下文',
        '- {{weather_summary}}',
      ].join('\n'),
      monthly_report: [
        '# {{date}} 月报',
        '',
        '## 总览',
        '{{task_work_summary}}',
        '',
        '## 活动趋势线索',
        '{{activity_segments}}',
      ].join('\n'),
      diary: [
        '# {{date}} 日记草稿',
        '',
        '今天主要发生了：',
        '{{actual_logs}}',
        '',
        '可以补充的主观感受：',
        '- 今天最顺利的部分是：',
        '- 今天被打断或偏离计划的部分是：',
        '- 明天优先处理：',
        '',
        '天气：{{weather_summary}}',
        '',
        '> 这是模板日记草稿，默认私密，不会自动推送。',
      ].join('\n'),
      project_report: '# {{date}} 项目报告\n\n{{task_work_summary}}\n\n{{recent_files}}',
      course_report: '# {{date}} 课程报告\n\n{{planned_events}}\n\n{{actual_logs}}',
      push_summary: '{{date}} {{report_type}}\n\n{{actual_logs}}\n\n{{task_work_summary}}',
    };
  }

  private templateVariableDescriptions() {
    return {
      date: '报告日期',
      planned_events: '日程与排程片段',
      completed_tasks: '任务快照',
      actual_logs: '已确认实际记录',
      task_work_summary: '任务实际投入摘要',
      activity_segments: '活动片段摘要',
      recent_files: '文件上下文摘要',
      weather_summary: '天气摘要',
      sync_warnings: '同步风险提示',
      tomorrow_risks: '明日风险提示',
    };
  }

  private bulletLines(items: unknown[], key: string, empty: string) {
    if (items.length === 0) return `- ${empty}`;
    return items
      .slice(0, 12)
      .map((item) => {
        const record = this.asRecord(item);
        const value = key === 'payload' ? this.payloadTitle(record.payload) : record[key];
        return `- ${String(value ?? '未命名')}`;
      })
      .join('\n');
  }

  private payloadTitle(payload: unknown) {
    const record = this.asRecord(payload);
    return record.title ?? record.summary ?? record.name ?? record.uid ?? JSON.stringify(record).slice(0, 80);
  }

  private async callOptionalReportLlm(
    userId: string,
    payload: { kind: string; title: string; markdown: string; entries: unknown[] },
  ) {
    const provider = await this.loadDefaultAiProvider(userId);
    if (!provider || provider.status !== 'enabled') {
      throw new Error('AI provider is not configured or disabled.');
    }
    const apiKey = this.decryptAiKey(provider.api_key_ciphertext);
    if (!apiKey) throw new Error('AI provider apiKey is missing.');
    if (provider.provider_type !== 'openai_compatible') {
      throw new Error(`Unsupported AI provider type: ${provider.provider_type}`);
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
        temperature: this.readNumber(provider.temperature, 0.2),
        max_tokens: this.readInteger(provider.max_output_tokens, 1200),
        messages: [
          {
            role: 'system',
            content:
              '你是 FlowPlan 的报告润色助手。只能基于给定模板报告和条目摘要润色中文表达，不能添加新事实，不能把 inferred 写成 fact，不能删除证据边界。输出纯 Markdown 段落。',
          },
          {
            role: 'user',
            content: JSON.stringify({
              kind: payload.kind,
              title: payload.title,
              markdown: payload.markdown.slice(0, 12000),
              entries: payload.entries,
            }),
          },
        ],
        ...this.asRecord(provider.options),
      }),
    });
    const raw = await response.text();
    if (!response.ok) {
      throw new Error(`AI API ${response.status}: ${raw.slice(0, 500)}`);
    }
    const decoded = raw ? JSON.parse(raw) : {};
    const choice = Array.isArray(decoded.choices) ? decoded.choices[0] : null;
    const content = choice?.message?.content;
    if (typeof content !== 'string' || content.trim().length === 0) {
      throw new Error('AI API response did not contain message content.');
    }
    return content;
  }

  private async loadDefaultAiProvider(userId: string) {
    const result = await this.database.query<AiProviderRow>(
      `
      SELECT provider_key, provider_type, base_url, model, api_key_ciphertext, status,
             temperature, max_output_tokens, options
      FROM ai_provider_configs
      WHERE user_id = $1
      ORDER BY is_default DESC, updated_at DESC
      LIMIT 1
      `,
      [userId],
    );
    return result.rows[0] ?? null;
  }

  private decryptAiKey(ciphertext: string | null) {
    if (!ciphertext) return null;
    const [ivRaw, tagRaw, encryptedRaw] = ciphertext.split('.');
    if (!ivRaw || !tagRaw || !encryptedRaw) return null;
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
      process.env.DATABASE_URL ??
      'flowplan-local-development-secret';
    return createHash('sha256').update(secret).digest();
  }

  private weatherSummaryFromPayload(payload: Record<string, unknown>) {
    const daily = this.asRecord(payload.daily);
    const time = this.asArray(daily.time);
    const max = this.asArray(daily.temperature_2m_max);
    const min = this.asArray(daily.temperature_2m_min);
    const rain = this.asArray(daily.precipitation_probability_max);
    if (time.length === 0) {
      return 'Open-Meteo 已刷新，但返回中没有 daily 预报。';
    }
    const parts = time.slice(0, 3).map((date, index) => {
      return `${date}: ${min[index] ?? '?'}-${max[index] ?? '?'} C，降雨概率 ${rain[index] ?? '?'}%`;
    });
    return `Open-Meteo 天气预报：${parts.join('；')}`;
  }

  private period(type: string, rawDate: unknown, rawStart: unknown, rawEnd: unknown) {
    const explicitStart = this.readDate(rawStart);
    const explicitEnd = this.readDate(rawEnd);
    if (explicitStart && explicitEnd && explicitStart < explicitEnd) return { start: explicitStart, end: explicitEnd };
    const dateText = typeof rawDate === 'string' && rawDate.trim() ? rawDate.trim().slice(0, 10) : new Date().toISOString().slice(0, 10);
    const start = new Date(`${dateText}T00:00:00.000Z`);
    const days = type === 'weekly' ? 7 : type === 'monthly' ? 31 : 1;
    return { start, end: new Date(start.getTime() + days * 86400000) };
  }

  private metrics(snapshot: ReportSnapshot) {
    return {
      actualCount: this.asArray(snapshot.actuals).length,
      taskWorkCount: this.asArray(snapshot.taskWork).length,
      segmentCount: this.asArray(snapshot.activitySegments).length,
      fileContextCount: this.asArray(snapshot.files).length,
      hasWeather: Boolean(snapshot.weather),
    };
  }

  private targetForChannel(config: Record<string, unknown>) {
    return String(config.chatId ?? config.url ?? config.email ?? 'configured_target');
  }

  private reportName(type: string) {
    if (type === 'weekly') return '周报';
    if (type === 'monthly') return '月报';
    if (type === 'project') return '项目报告';
    if (type === 'course') return '课程报告';
    return '日报';
  }

  private defaultTemplateNames() {
    return ['daily_report', 'weekly_report', 'monthly_report', 'diary', 'project_report', 'course_report', 'push_summary'];
  }

  private readLimit(value: string | undefined, fallback: number) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? Math.max(1, Math.min(200, Math.trunc(parsed))) : fallback;
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
    return typeof value === 'string' && value.trim().length > 0 ? value.trim() : null;
  }

  private readDate(value: unknown) {
    if (!(typeof value === 'string' || value instanceof Date)) return null;
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }

  private asRecord(value: unknown): Record<string, unknown> {
    return value && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : {};
  }

  private asArray(value: unknown): unknown[] {
    return Array.isArray(value) ? value : [];
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
      INSERT INTO audit_logs (user_id, device_id, actor, action, entity_type, entity_id, summary, metadata)
      VALUES ($1, $2, 'system', $3, $4, $5, $3, $6::jsonb)
      `,
      [
        userId,
        deviceId,
        action,
        String(details.targetType ?? 'report'),
        details.reportId || details.diaryId || details.locationId ? String(details.reportId ?? details.diaryId ?? details.locationId) : null,
        JSON.stringify(details),
      ],
    );
  }
}
