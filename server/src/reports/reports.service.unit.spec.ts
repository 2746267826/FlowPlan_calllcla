import { BadRequestException } from '@nestjs/common';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { encrypt, encryptionKey } from '../common/utils';
import { ReportsService } from './reports.service';

const context = {
  userId: '11111111-1111-4111-8111-111111111111',
  deviceId: '22222222-2222-4222-8222-222222222222',
};

function result(rows: Record<string, unknown>[] = []) {
  return { rows };
}

function createHarness() {
  const query = vi.fn();
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
    activeProfile: vi.fn(async () => ({ versionKey: 'report-v1', ruleProfile: { tone: 'concise' } })),
    startRun: vi.fn(async () => ({ id: 'model-run-1' })),
    completeRun: vi.fn(async () => undefined),
    recordFeedback: vi.fn(async () => undefined),
  };
  const service = new ReportsService(database as never, devices as never, models as never);
  return { service, database, devices, models, query };
}

function privateApi(service: ReportsService) {
  return service as unknown as {
    callOptionalReportLlm(
      userId: string,
      payload: { kind: string; title: string; markdown: string; entries: unknown[] },
    ): Promise<string>;
    weatherSummaryFromPayload(payload: Record<string, unknown>): string;
    period(type: string, rawDate: unknown, rawStart: unknown, rawEnd: unknown): { start: Date; end: Date };
    reportName(type: string): string;
    targetForChannel(config: Record<string, unknown>): string;
    decryptAiKey(ciphertext: string | null): string | null;
    sourceSnapshot(userId: string, start: Date, end: Date): Promise<Record<string, unknown>>;
    renderReport(
      userId: string,
      type: string,
      start: Date,
      snapshot: Record<string, unknown>,
    ): Promise<string>;
    defaultTemplate(userId: string, templateType: string): Promise<string | undefined>;
    insertReportEntries(
      client: { query: ReturnType<typeof vi.fn> },
      userId: string,
      reportId: string,
      snapshot: Record<string, unknown>,
    ): Promise<void>;
    insertReportEntry(
      client: { query: ReturnType<typeof vi.fn> },
      userId: string,
      reportId: string,
      entry: { type: string; title: string; body: string; orderIndex: number; payload?: Record<string, unknown> },
    ): Promise<string>;
    insertEvidence(
      client: { query: ReturnType<typeof vi.fn> },
      userId: string,
      reportId: string,
      entryId: string,
      evidence: { sourceType: string; evidenceType: string; summary: string; sourceId?: string | null; payload?: Record<string, unknown> },
    ): Promise<void>;
    templateVariables(type: string, start: Date, snapshot: Record<string, unknown>): Record<string, string>;
    renderTemplate(template: string, variables: Record<string, string>): string;
    builtInTemplate(templateType: string): string;
    bulletLines(items: unknown[], key: string, empty: string): string;
    payloadTitle(payload: unknown): unknown;
  };
}

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe('ReportsService', () => {
  it('lists reports with normalized filters and limit', async () => {
    const { service, query, devices } = createHarness();
    query.mockResolvedValue(result([{ id: 'report-1', reportType: 'daily' }]));

    await expect(
      service.reports({ reportType: ' daily ', status: ' draft ', limit: '2' }, context),
    ).resolves.toEqual({
      items: [{ id: 'report-1', reportType: 'daily' }],
    });

    expect(devices.ensureUser).toHaveBeenCalledWith(context.userId);
    expect(query).toHaveBeenCalledWith(expect.stringContaining('FROM report_documents'), [
      context.userId,
      'daily',
      'draft',
      2,
    ]);
  });

  it('loads report detail entries and evidence, and rejects missing reports', async () => {
    const { service, query } = createHarness();
    const report = { id: 'report-1', title: 'Daily', contentMarkdown: 'body' };
    const entry = { id: 'entry-1', entryType: 'fact', title: 'Fact' };
    const evidence = { id: 'evidence-1', entryId: 'entry-1' };
    query
      .mockResolvedValueOnce(result([report]))
      .mockResolvedValueOnce(result([entry]))
      .mockResolvedValueOnce(result([evidence]));

    await expect(service.report('report-1', context)).resolves.toEqual({
      report,
      entries: [entry],
      evidence: [evidence],
    });

    expect(query.mock.calls.map((call) => call[1])).toEqual([
      [context.userId, 'report-1'],
      [context.userId, 'report-1'],
      [context.userId, 'report-1'],
    ]);

    query.mockReset();
    query.mockResolvedValueOnce(result([]));

    await expect(service.report('missing-report', context)).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('updates and confirms reports with audit and model feedback', async () => {
    const { service, database, query, models } = createHarness();
    query.mockResolvedValue(result([{ id: 'entry-1' }]));

    await expect(
      service.updateReport(
        'report-1',
        { title: 'Updated', contentMarkdown: 'Markdown', userNote: 'Manual note' },
        context,
      ),
    ).resolves.toEqual({ ok: true });

    expect(database.transaction).toHaveBeenCalledTimes(1);
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE report_documents'),
      [context.userId, 'report-1', 'Updated', 'Markdown'],
    );
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'report.updated']),
    );
    expect(models.recordFeedback).toHaveBeenCalledWith(
      { query },
      context.userId,
      context.deviceId,
      'report_template.v1',
      expect.objectContaining({
        targetId: 'report-1',
        feedbackType: 'edited',
        outcome: 'modified',
      }),
    );

    query.mockClear();
    await expect(service.confirmReport('report-1', context)).resolves.toEqual({ ok: true });

    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'confirmed'"),
      [context.userId, 'report-1'],
    );
    expect(models.recordFeedback).toHaveBeenLastCalledWith(
      { query },
      context.userId,
      context.deviceId,
      'report_template.v1',
      expect.objectContaining({
        targetId: 'report-1',
        feedbackType: 'accepted',
        outcome: 'confirmed',
      }),
    );
  });

  it('lists and updates diary drafts with report feedback', async () => {
    const { service, query, models } = createHarness();
    query.mockResolvedValueOnce(result([{ id: 'diary-1', status: 'draft' }]));

    await expect(service.diary({ status: ' draft ', limit: '3' }, context)).resolves.toEqual({
      items: [{ id: 'diary-1', status: 'draft' }],
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('FROM diary_entries'), [
      context.userId,
      'draft',
      3,
    ]);

    query.mockClear();
    await expect(
      service.updateDiary('diary-1', { title: 'Day', contentMarkdown: 'Text' }, context),
    ).resolves.toEqual({ ok: true });

    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE diary_entries'),
      [context.userId, 'diary-1', 'Day', 'Text'],
    );
    expect(models.recordFeedback).toHaveBeenCalledWith(
      { query },
      context.userId,
      context.deviceId,
      'report_template.v1',
      expect.objectContaining({
        targetType: 'diary_entry',
        targetId: 'diary-1',
        feedbackType: 'edited',
      }),
    );

    query.mockClear();
    await expect(service.confirmDiary('diary-1', context)).resolves.toEqual({ ok: true });
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining("SET status = 'confirmed'"),
      [context.userId, 'diary-1'],
    );
  });

  it('creates defaults before listing templates and supports default template upsert', async () => {
    const { service, query } = createHarness();
    query.mockImplementation(async (sql: string, params?: unknown[]) => {
      if (sql.includes('FROM report_templates')) {
        return result([{ id: 'template-1', templateType: 'daily_report' }]);
      }
      return result([]);
    });

    await expect(service.templates(context)).resolves.toMatchObject({
      items: [{ id: 'template-1', templateType: 'daily_report' }],
      defaults: expect.arrayContaining(['daily_report', 'weekly_report']),
    });
    expect(query.mock.calls.filter((call) => String(call[0]).includes('INSERT INTO report_templates')).length)
      .toBeGreaterThan(1);

    query.mockReset();
    query.mockResolvedValue(result([{ id: 'template-2' }]));

    await expect(
      service.upsertTemplate(
        {
          name: 'Daily',
          templateType: 'daily_report',
          contentTemplate: '# {{date}}',
          variables: ['date'],
          isDefault: true,
        },
        context,
      ),
    ).resolves.toEqual({ ok: true, template: { id: 'template-2' } });

    expect(query).toHaveBeenCalledWith(
      'UPDATE report_templates SET is_default = false WHERE user_id = $1 AND template_type = $2',
      [context.userId, 'daily_report'],
    );
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO report_templates'),
      [context.userId, 'Daily', 'daily_report', '# {{date}}', '["date"]', true],
    );
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO audit_logs'),
      expect.arrayContaining([context.userId, context.deviceId, 'report.template.upserted']),
    );
  });

  it('lists and creates push channels and queued deliveries', async () => {
    const { service, query } = createHarness();
    query.mockResolvedValueOnce(result([{ id: 'channel-1', channelType: 'webhook' }]));

    await expect(service.pushChannels(context)).resolves.toEqual({
      items: [{ id: 'channel-1', channelType: 'webhook' }],
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('FROM push_channels'), [
      context.userId,
    ]);

    query.mockReset();
    query.mockResolvedValue(result([{ id: 'channel-2' }]));
    await expect(
      service.upsertPushChannel(
        { channelType: 'webhook', name: 'Ops', status: 'enabled', config: { url: 'https://hook' } },
        context,
      ),
    ).resolves.toEqual({ ok: true, channel: { id: 'channel-2' } });

    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO push_channels'),
      [context.userId, 'webhook', 'Ops', 'enabled', '{"url":"https://hook"}'],
    );

    query.mockReset();
    query.mockResolvedValueOnce(result([{ id: 'delivery-1', status: 'failed' }]));
    await expect(service.pushDeliveries({ status: 'failed', limit: '4' }, context)).resolves.toEqual({
      items: [{ id: 'delivery-1', status: 'failed' }],
    });
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('FROM report_push_deliveries'),
      [context.userId, 'failed', 4],
    );
  });

  it('rejects report push when no enabled channel exists', async () => {
    const { service, query } = createHarness();
    vi.spyOn(service, 'report').mockResolvedValue({
      report: { id: 'report-1', title: 'Daily', contentMarkdown: 'Report' },
      entries: [],
      evidence: [],
    } as never);
    query.mockResolvedValue(result([]));

    await expect(service.pushReport('report-1', {}, context)).rejects.toBeInstanceOf(
      BadRequestException,
    );
  });

  it('validates and writes weather locations and weather summaries', async () => {
    const { service, query } = createHarness();

    await expect(
      service.upsertWeatherLocation({ name: 'Bad', latitude: 'nope', longitude: 121 }, context),
    ).rejects.toBeInstanceOf(BadRequestException);

    query.mockResolvedValue(result([{ id: 'weather-1' }]));
    await expect(
      service.upsertWeatherLocation(
        { name: 'Shanghai', latitude: 31.2, longitude: 121.5, timezone: 'Asia/Shanghai' },
        context,
      ),
    ).resolves.toEqual({ ok: true, location: { id: 'weather-1' } });

    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO weather_locations'),
      [context.userId, 'Shanghai', 31.2, 121.5, 'Asia/Shanghai', true],
    );

    query.mockReset();
    query.mockResolvedValueOnce(result([{ id: 'weather-1', name: 'Shanghai' }]));
    await expect(service.weatherLocations(context)).resolves.toEqual({
      items: [{ id: 'weather-1', name: 'Shanghai' }],
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('FROM weather_locations'), [context.userId]);

    query.mockReset();
    query.mockResolvedValueOnce(result([{ id: 'cache-1', summary: 'Cloudy' }]));
    await expect(service.weatherSummary({ locationId: 'weather-1' }, context)).resolves.toEqual({
      items: [{ id: 'cache-1', summary: 'Cloudy' }],
    });
    expect(query).toHaveBeenCalledWith(expect.stringContaining('FROM weather_cache'), [
      context.userId,
      'weather-1',
    ]);
  });

  it('computes report quality dimensions from entries and evidence', async () => {
    const { service } = createHarness();
    vi.spyOn(service, 'report').mockResolvedValue({
      report: { id: 'report-1', contentMarkdown: 'x'.repeat(500) },
      entries: [
        { id: 'entry-1', entryType: 'fact', title: 'Fact' },
        { id: 'entry-2', entryType: 'inferred', title: 'Inferred', status: 'confirmed' },
        { id: 'entry-3', entryType: 'external', title: 'Weather' },
      ],
      evidence: [
        { id: 'ev-1', entryId: 'entry-1' },
        { id: 'ev-2', entryId: 'entry-2' },
        { id: 'ev-duplicate', entryId: 'entry-2' },
        { id: 'ev-foreign', entryId: 'entry-not-in-report' },
        { id: 'ev-empty', entryId: '' },
      ],
    } as never);

    const score = await service.reportQualityScore('report-1', context);

    expect(score).toMatchObject({
      reportId: 'report-1',
      dimensions: {
        completeness: { score: 100, weight: 0.3 },
        factualAccuracy: { score: 100, weight: 0.25 },
      },
      entryStats: { factCount: 1, inferredCount: 1, externalCount: 1, total: 3 },
    });
    expect(score.dimensions.evidenceCoverage.score).toBe(67);
    expect(score.overall).toBeGreaterThan(0);
  });

  it('compares two report histories by counts, facts, length, and titles', async () => {
    const { service } = createHarness();
    vi.spyOn(service, 'report')
      .mockResolvedValueOnce({
        report: { id: 'baseline', periodStart: '2026-06-07', contentMarkdown: 'short' },
        entries: [
          { id: 'a', entryType: 'fact', title: 'Existing' },
          { id: 'b', entryType: 'inferred', title: 'Removed' },
        ],
        evidence: [],
      } as never)
      .mockResolvedValueOnce({
        report: { id: 'comparison', periodStart: '2026-06-08', contentMarkdown: 'longer text' },
        entries: [
          { id: 'c', entryType: 'fact', title: 'Existing' },
          { id: 'd', entryType: 'fact', title: 'New fact' },
        ],
        evidence: [],
      } as never);

    await expect(service.compareReports('baseline', 'comparison', context)).resolves.toMatchObject({
      baseline: { reportId: 'baseline', entryCount: 2, factCount: 1 },
      comparison: { reportId: 'comparison', entryCount: 2, factCount: 2 },
      delta: { entryCount: 0, factCount: 1, contentLength: 6 },
      newEntries: [{ type: 'fact', title: 'New fact' }],
      removedEntries: [{ type: 'inferred', title: 'Removed' }],
    });
  });

  it('generates reports from source snapshots, writes evidence entries, and completes the model run', async () => {
    const { service, query, models } = createHarness();
    query.mockImplementation(async (sql: string, params?: unknown[]) => {
      if (sql.includes('actual_activity_logs')) {
        return result([{ id: 'actual-1', title: 'Confirmed focus', startAt: '09:00', endAt: '10:00' }]);
      }
      if (sql.includes('task_work_logs')) {
        return result([{ taskId: 'task-1', minutes: 45 }]);
      }
      if (sql.includes('activity_segments')) {
        return result([{ id: 'segment-1', title: 'Needs review', confidence: 0.61, status: 'candidate' }]);
      }
      if (sql.includes('plan_deviations')) {
        return result([{ id: 'deviation-1', deviationType: 'missed', actualTitle: 'Late meeting' }]);
      }
      if (sql.includes('sync_objects') && sql.includes('task')) {
        return result([{ id: 'task-row', uid: 'task-1', payload: { title: 'Ship coverage' } }]);
      }
      if (sql.includes('sync_objects')) {
        return result([{ id: 'schedule-row', uid: 'schedule-1', payload: { title: 'Focus block' } }]);
      }
      if (sql.includes('file_operation_logs')) {
        return result([{ id: 'file-1', operation: 'open', sourcePath: 'C:/plan.md' }]);
      }
      if (sql.includes('weather_cache')) {
        return result([{ id: 'weather-1', summary: 'Clear' }]);
      }
      if (sql.includes('FROM report_templates')) {
        return result([{ content_template: '# {{date}}\n{{actual_logs}}\n{{plan_deviations}}' }]);
      }
      if (sql.includes('INSERT INTO report_documents')) {
        return result([{ id: 'report-generated' }]);
      }
      if (sql.includes('INSERT INTO report_entries')) {
        return result([{ id: `entry-${query.mock.calls.length}` }]);
      }
      if (sql.includes('FROM report_documents')) {
        return result([{ id: 'report-generated', title: 'Generated', contentMarkdown: 'body' }]);
      }
      if (sql.includes('FROM report_entries')) {
        return result([{ id: 'entry-1', entryType: 'fact' }]);
      }
      if (sql.includes('FROM report_evidence_links')) {
        return result([{ id: 'evidence-1' }]);
      }
      return result([]);
    });

    const generated = await service.generateReport({ reportType: 'weekly', date: '2026-06-08' }, context);

    expect(generated).toMatchObject({
      report: { id: 'report-generated' },
      entries: [{ id: 'entry-1', entryType: 'fact' }],
      evidence: [{ id: 'evidence-1' }],
      modelRunId: 'model-run-1',
      modelUsed: 'rule_learned',
      modelVersion: 'report-v1',
    });
    expect(models.startRun).toHaveBeenCalledWith(
      context.userId,
      'report_template.v1',
      expect.objectContaining({
        source: 'reports.generateReport',
        inputSummary: expect.objectContaining({
          reportType: 'weekly',
          periodStart: '2026-06-08T00:00:00.000Z',
          periodEnd: '2026-06-15T00:00:00.000Z',
        }),
      }),
    );
    const reportInsert = query.mock.calls.find(([sql]) => String(sql).includes('INSERT INTO report_documents'));
    expect(reportInsert?.[1]).toEqual(
      expect.arrayContaining([
        context.userId,
        'report:weekly:2026-06-08',
        'weekly',
        new Date('2026-06-08T00:00:00.000Z'),
        new Date('2026-06-15T00:00:00.000Z'),
      ]),
    );
    expect(query.mock.calls.filter(([sql]) => String(sql).includes('INSERT INTO report_entries')).length)
      .toBeGreaterThan(4);
    expect(query.mock.calls.filter(([sql]) => String(sql).includes('INSERT INTO report_evidence_links')).length)
      .toBeGreaterThan(4);
    expect(models.completeRun).toHaveBeenCalledWith(
      context.userId,
      'model-run-1',
      expect.objectContaining({
        status: 'succeeded',
        outputSummary: expect.objectContaining({
          reportId: 'report-generated',
          reportType: 'weekly',
          metrics: expect.objectContaining({
            actualCount: 1,
            taskWorkCount: 1,
            segmentCount: 1,
            deviationCount: 1,
            fileContextCount: 1,
            hasWeather: true,
          }),
        }),
        confidence: 0.82,
        usedLlm: false,
      }),
    );
  });

  it('generates hybrid reports, silently polishes them, and records empty actual evidence', async () => {
    const { service, query, models } = createHarness();
    const polish = vi.spyOn(service, 'polishReport').mockResolvedValue({ ok: true, llmApplied: false } as never);
    query.mockImplementation(async (sql: string) => {
      if (sql.includes('actual_activity_logs')) return result([]);
      if (sql.includes('task_work_logs')) return result([]);
      if (sql.includes('activity_segments')) return result([]);
      if (sql.includes('plan_deviations')) return result([]);
      if (sql.includes('sync_objects')) return result([]);
      if (sql.includes('file_operation_logs')) return result([]);
      if (sql.includes('weather_cache')) return result([]);
      if (sql.includes('FROM report_templates')) return result([]);
      if (sql.includes('INSERT INTO report_documents')) return result([{ id: 'report-hybrid' }]);
      if (sql.includes('INSERT INTO report_entries')) return result([{ id: `entry-${query.mock.calls.length}` }]);
      if (sql.includes('FROM report_documents')) {
        return result([{ id: 'report-hybrid', title: 'Hybrid', contentMarkdown: 'body' }]);
      }
      if (sql.includes('FROM report_entries')) return result([]);
      if (sql.includes('FROM report_evidence_links')) return result([]);
      return result([]);
    });

    await expect(
      service.generateReport({ date: '2026-06-08', useLlm: true }, context),
    ).resolves.toMatchObject({
      report: { id: 'report-hybrid' },
      modelUsed: 'hybrid',
    });

    expect(polish).toHaveBeenCalledWith('report-hybrid', context, { silentFallback: true });
    expect(models.completeRun).toHaveBeenCalledWith(
      context.userId,
      'model-run-1',
      expect.objectContaining({
        outputSummary: expect.objectContaining({
          generationMode: 'template_then_optional_llm',
          metrics: expect.objectContaining({ actualCount: 0, hasWeather: false }),
        }),
        usedLlm: true,
      }),
    );
    const firstEntry = query.mock.calls.find(([sql]) => String(sql).includes('INSERT INTO report_entries'));
    expect(firstEntry?.[1]).toEqual(
      expect.arrayContaining([context.userId, 'report-hybrid', 'fact', expect.any(String), expect.any(String), 0]),
    );
    const firstEvidence = query.mock.calls.find(([sql]) => String(sql).includes('INSERT INTO report_evidence_links'));
    expect(firstEvidence?.[1]).toEqual(
      expect.arrayContaining([context.userId, 'report-hybrid', expect.any(String), 'actual_activity_logs']),
    );
  });

  it('generates diary drafts and optionally invokes silent LLM polish', async () => {
    const { service, query, models } = createHarness();
    const polish = vi.spyOn(service, 'polishDiary').mockResolvedValue({ ok: true, llmApplied: false } as never);
    query.mockImplementation(async (sql: string) => {
      if (sql.includes('actual_activity_logs')) return result([{ id: 'actual-1', title: 'Done' }]);
      if (sql.includes('task_work_logs')) return result([]);
      if (sql.includes('activity_segments')) return result([]);
      if (sql.includes('plan_deviations')) return result([]);
      if (sql.includes('sync_objects')) return result([]);
      if (sql.includes('file_operation_logs')) return result([]);
      if (sql.includes('weather_cache')) return result([{ summary: 'Rain' }]);
      if (sql.includes('FROM report_templates')) return result([]);
      if (sql.includes('INSERT INTO diary_entries')) return result([{ id: 'diary-generated' }]);
      return result([]);
    });

    await expect(service.generateDiary({ date: '2026-06-08', useLlm: true }, context)).resolves.toEqual({
      ok: true,
      diaryId: 'diary-generated',
      modelRunId: 'model-run-1',
      modelUsed: 'hybrid',
      modelVersion: 'report-v1',
    });

    expect(polish).toHaveBeenCalledWith('diary-generated', context, { silentFallback: true });
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO diary_entries'),
      expect.arrayContaining([context.userId, 'diary:2026-06-08', '2026-06-08']),
    );
    expect(models.completeRun).toHaveBeenCalledWith(
      context.userId,
      'model-run-1',
      expect.objectContaining({
        outputSummary: expect.objectContaining({ diaryId: 'diary-generated' }),
        usedLlm: true,
      }),
    );

    query.mockReset();
    polish.mockClear();
    query.mockImplementation(async (sql: string) => {
      if (sql.includes('actual_activity_logs')) return result([]);
      if (sql.includes('task_work_logs')) return result([]);
      if (sql.includes('activity_segments')) return result([]);
      if (sql.includes('plan_deviations')) return result([]);
      if (sql.includes('sync_objects')) return result([]);
      if (sql.includes('file_operation_logs')) return result([]);
      if (sql.includes('weather_cache')) return result([]);
      if (sql.includes('FROM report_templates')) return result([]);
      if (sql.includes('INSERT INTO diary_entries')) return result([{ id: 'diary-template-only' }]);
      return result([]);
    });

    await expect(service.generateDiary({ date: '2026-06-09' }, context)).resolves.toEqual({
      ok: true,
      diaryId: 'diary-template-only',
      modelRunId: 'model-run-1',
      modelUsed: 'rule_learned',
      modelVersion: 'report-v1',
    });
    expect(polish).not.toHaveBeenCalled();
    expect(models.completeRun).toHaveBeenLastCalledWith(
      context.userId,
      'model-run-1',
      expect.objectContaining({
        outputSummary: expect.objectContaining({
          diaryId: 'diary-template-only',
          generationMode: 'template',
        }),
        usedLlm: false,
      }),
    );
  });

  it('polishes reports and diaries with configured OpenAI-compatible provider and records AI evidence', async () => {
    const { service, query } = createHarness();
    const fetchMock = vi.fn(async () => ({
      ok: true,
      status: 200,
      text: async () => JSON.stringify({ choices: [{ message: { content: 'Polished markdown' } }] }),
    }));
    vi.stubGlobal('fetch', fetchMock);
    vi.spyOn(service, 'report').mockResolvedValue({
      report: { id: 'report-1', title: null, contentMarkdown: null },
      entries: [{ id: 'entry-1', title: 'Fact' }],
      evidence: [],
    } as never);
    query.mockImplementation(async (sql: string) => {
      if (sql.includes('FROM ai_provider_configs')) {
        return result([
          {
            provider_key: 'openai-main',
            provider_type: 'openai_compatible',
            base_url: 'https://ai.test/',
            model: 'gpt-test',
            api_key_ciphertext: encrypt('unit-key', encryptionKey()),
            status: 'enabled',
            temperature: '0.1',
            max_output_tokens: '99',
            options: { top_p: 0.9 },
          },
        ]);
      }
      if (sql.includes('INSERT INTO report_entries')) return result([{ id: 'ai-entry' }]);
      if (sql.includes('SELECT id::text AS id, title, body_markdown')) {
        return result([{ id: 'diary-1', title: null, contentMarkdown: null }]);
      }
      return result([]);
    });

    await expect(service.polishReport('report-1', context)).resolves.toMatchObject({
      ok: true,
      llmApplied: true,
    });
    await expect(service.polishDiary('diary-1', context)).resolves.toEqual({
      ok: true,
      llmApplied: true,
    });

    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(fetchMock.mock.calls[0][0]).toBe('https://ai.test/chat/completions');
    expect(fetchMock.mock.calls[0][1]).toMatchObject({
      method: 'POST',
      headers: expect.objectContaining({ authorization: 'Bearer unit-key' }),
    });
    expect(JSON.parse(String(fetchMock.mock.calls[0][1]?.body))).toMatchObject({
      model: 'gpt-test',
      temperature: 0.1,
      max_tokens: 99,
      top_p: 0.9,
    });
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE report_documents'),
      expect.arrayContaining([context.userId, 'report-1', expect.stringContaining('Polished markdown')]),
    );
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO report_evidence_links'),
      expect.arrayContaining([context.userId, 'report-1', 'ai-entry', 'report_document']),
    );
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('UPDATE diary_entries'),
      expect.arrayContaining([context.userId, 'diary-1', expect.stringContaining('Polished markdown')]),
    );
  });

  it('keeps template output when report or diary LLM polish cannot run', async () => {
    const { service, query } = createHarness();
    vi.spyOn(service, 'report').mockResolvedValue({
      report: { id: 'report-1', title: 'Daily', contentMarkdown: 'Original' },
      entries: [],
      evidence: [],
    } as never);
    query.mockImplementation(async (sql: string) => {
      if (sql.includes('FROM ai_provider_configs')) return result([]);
      if (sql.includes('SELECT id::text AS id, title, body_markdown')) {
        return result([{ id: 'diary-1', title: 'Diary', contentMarkdown: 'Private' }]);
      }
      return result([]);
    });

    await expect(service.polishReport('report-1', context)).resolves.toMatchObject({
      ok: true,
      llmApplied: false,
      fallback: 'template_report_kept',
      error: 'AI provider is not configured or disabled.',
    });
    await expect(service.polishReport('report-1', context, { silentFallback: true })).resolves.toEqual({
      ok: true,
      llmApplied: false,
      fallback: 'template_report_kept',
    });
    await expect(service.polishDiary('diary-1', context)).resolves.toMatchObject({
      ok: true,
      llmApplied: false,
      fallback: 'template_diary_kept',
    });
    await expect(service.polishDiary('diary-1', context, { silentFallback: true })).resolves.toEqual({
      ok: true,
      llmApplied: false,
      fallback: 'template_diary_kept',
    });

    query.mockReset();
    query.mockResolvedValueOnce(result([]));
    await expect(service.polishDiary('missing-diary', context)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('surfaces optional LLM provider and response validation failures', async () => {
    const basePayload = { kind: 'report', title: 'Daily', markdown: 'Body', entries: [] };

    const missingKey = createHarness();
    missingKey.query.mockImplementation(async (sql: string) => {
      if (sql.includes('FROM ai_provider_configs')) {
        return result([
          {
            provider_type: 'openai_compatible',
            base_url: 'https://ai.test',
            model: 'gpt-test',
            api_key_ciphertext: null,
            status: 'enabled',
          },
        ]);
      }
      return result([]);
    });
    await expect(
      privateApi(missingKey.service).callOptionalReportLlm(context.userId, basePayload),
    ).rejects.toThrow('AI provider apiKey is missing.');

    const unsupported = createHarness();
    unsupported.query.mockImplementation(async (sql: string) => {
      if (sql.includes('FROM ai_provider_configs')) {
        return result([
          {
            provider_type: 'anthropic',
            base_url: 'https://ai.test',
            model: 'claude-test',
            api_key_ciphertext: encrypt('unit-key', encryptionKey()),
            status: 'enabled',
          },
        ]);
      }
      return result([]);
    });
    await expect(
      privateApi(unsupported.service).callOptionalReportLlm(context.userId, basePayload),
    ).rejects.toThrow('Unsupported AI provider type: anthropic');

    const failingHttp = createHarness();
    failingHttp.query.mockImplementation(async (sql: string) => {
      if (sql.includes('FROM ai_provider_configs')) {
        return result([
          {
            provider_type: 'openai_compatible',
            base_url: 'https://ai.test/v1/',
            model: 'gpt-test',
            api_key_ciphertext: encrypt('unit-key', encryptionKey()),
            status: 'enabled',
          },
        ]);
      }
      return result([]);
    });
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({ ok: false, status: 503, text: async () => 'upstream down' })),
    );
    await expect(
      privateApi(failingHttp.service).callOptionalReportLlm(context.userId, basePayload),
    ).rejects.toThrow('AI API 503: upstream down');

    const emptyContent = createHarness();
    emptyContent.query.mockImplementation(async (sql: string) => {
      if (sql.includes('FROM ai_provider_configs')) {
        return result([
          {
            provider_type: 'openai_compatible',
            base_url: 'https://ai.test/v1',
            model: 'gpt-test',
            api_key_ciphertext: encrypt('unit-key', encryptionKey()),
            status: 'enabled',
          },
        ]);
      }
      return result([]);
    });
    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({
        ok: true,
        status: 200,
        text: async () => JSON.stringify({ choices: [{ message: { content: '' } }] }),
      })),
    );
    await expect(
      privateApi(emptyContent.service).callOptionalReportLlm(context.userId, basePayload),
    ).rejects.toThrow('AI API response did not contain message content.');
  });

  it('covers report helper fallbacks for weather, periods, names, and delivery targets', () => {
    const { service } = createHarness();
    const api = privateApi(service);

    expect(api.weatherSummaryFromPayload({ daily: {} })).toEqual(expect.stringContaining('Open-Meteo'));
    expect(api.weatherSummaryFromPayload({ daily: { time: ['2026-06-08'] } })).toContain('?');
    expect(api.period('daily', null, '2026-06-08T01:00:00.000Z', '2026-06-08T02:00:00.000Z')).toEqual({
      start: new Date('2026-06-08T01:00:00.000Z'),
      end: new Date('2026-06-08T02:00:00.000Z'),
    });
    expect(api.period('monthly', '2026-06-08', null, null).end).toEqual(
      new Date('2026-07-09T00:00:00.000Z'),
    );
    expect(api.period('daily', '', null, null).start.toISOString()).toMatch(/T00:00:00\.000Z$/);
    expect(api.reportName('monthly')).toEqual(expect.any(String));
    expect(api.reportName('project')).toEqual(expect.any(String));
    expect(api.reportName('course')).toEqual(expect.any(String));
    expect(api.reportName('unknown')).toEqual(expect.any(String));
    expect(api.targetForChannel({ chatId: 'chat-1' })).toBe('chat-1');
    expect(api.targetForChannel({ url: 'https://hook.test' })).toBe('https://hook.test');
    expect(api.targetForChannel({ email: 'ops@example.test' })).toBe('ops@example.test');
    expect(api.targetForChannel({})).toBe('configured_target');
    expect(api.decryptAiKey('malformed-token')).toBeNull();
  });

  it('refreshes weather from Open-Meteo and stores successful or failed cache entries', async () => {
    const { service, query } = createHarness();
    const fetchMock = vi.fn()
      .mockResolvedValueOnce({
        ok: true,
        status: 200,
        text: async () => JSON.stringify({
          daily: {
            time: ['2026-06-08', '2026-06-09'],
            temperature_2m_min: [18, 19],
            temperature_2m_max: [27, 28],
            precipitation_probability_max: [20, 40],
          },
        }),
      })
      .mockResolvedValueOnce({
        ok: false,
        status: 500,
        text: async () => 'upstream down',
      });
    vi.stubGlobal('fetch', fetchMock);
    query.mockImplementation(async (sql: string) => {
      if (sql.includes('SELECT * FROM weather_locations')) {
        return result([{ id: 'weather-1', latitude: 31.2, longitude: 121.5, timezone: 'Asia/Shanghai' }]);
      }
      return result([]);
    });

    await expect(service.refreshWeather('weather-1', context)).resolves.toMatchObject({
      ok: true,
      summary: expect.stringContaining('Open-Meteo'),
      payload: expect.objectContaining({ daily: expect.any(Object) }),
    });
    await expect(service.refreshWeather('weather-1', context)).resolves.toMatchObject({
      ok: true,
      summary: expect.stringContaining('Open-Meteo 500'),
      payload: {},
    });

    expect(String(fetchMock.mock.calls[0][0])).toContain('latitude=31.2');
    expect(query.mock.calls.filter(([sql]) => String(sql).includes('INSERT INTO weather_cache'))).toHaveLength(2);
    expect(query.mock.calls.filter(([, params]) => (params as unknown[] | undefined)?.includes('weather.refreshed')))
      .toHaveLength(2);

    query.mockReset();
    query.mockResolvedValueOnce(result([]));
    await expect(service.refreshWeather('missing-weather', context)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('queues report pushes and sends webhook, telegram, and failure deliveries', async () => {
    const { service, query } = createHarness();
    const fetchMock = vi.fn()
      .mockResolvedValueOnce({ ok: true, status: 200, text: async () => 'ok' })
      .mockResolvedValueOnce({ ok: true, status: 200, text: async () => 'ok' })
      .mockResolvedValueOnce({ ok: false, status: 503, text: async () => 'down' });
    vi.stubGlobal('fetch', fetchMock);
    vi.spyOn(Date, 'now').mockReturnValue(12345);
    vi.spyOn(service, 'report').mockResolvedValue({
      report: { id: 'report-1', reportUid: 'report:daily:2026-06-08', title: 'Daily', contentMarkdown: null },
      entries: [],
      evidence: [],
    } as never);
    query.mockImplementation(async (sql: string, params?: unknown[]) => {
      if (sql.includes('FROM push_channels')) {
        return result([
          { id: 'channel-webhook', channel_type: 'webhook', config_json: { url: 'https://hook.test/report' } },
          { id: 'channel-telegram', channel_type: 'telegram', config_json: { botToken: 'bot', chatId: 'chat' } },
        ]);
      }
      if (sql.includes('INSERT INTO report_push_deliveries')) {
        const channel = String(params?.[3]);
        return result([{ id: channel === 'webhook' ? 'delivery-webhook' : 'delivery-telegram' }]);
      }
      if (sql.includes('SELECT d.*, c.config_json')) {
        if (params?.[1] === 'delivery-webhook') {
          return result([{ id: 'delivery-webhook', channel: 'webhook', config_json: { url: 'https://hook.test/report' }, payload: { title: 'Daily', summary: 'Summary text' } }]);
        }
        if (params?.[1] === 'delivery-telegram') {
          return result([{ id: 'delivery-telegram', channel: 'telegram', config_json: { botToken: 'bot', chatId: 'chat' }, payload: { title: 'Daily', summary: 'Summary text' } }]);
        }
        if (params?.[1] === 'delivery-failing') {
          return result([{ id: 'delivery-failing', channel: 'webhook', config_json: { url: 'https://hook.test/fail' }, payload: { title: 'Fail' } }]);
        }
        if (params?.[1] === 'delivery-unconfigured') {
          return result([{ id: 'delivery-unconfigured', channel: 'email', config_json: {}, payload: { title: 'No send' } }]);
        }
        if (params?.[1] === 'delivery-webhook-string-failure') {
          return result([{ id: 'delivery-webhook-string-failure', channel: 'webhook', config_json: { url: 'https://hook.test/string-fail' }, payload: { title: 'String fail' } }]);
        }
        return result([]);
      }
      return result([]);
    });

    await expect(service.pushReport('report-1', {}, context)).resolves.toEqual({
      ok: true,
      deliveries: ['delivery-webhook', 'delivery-telegram'],
      results: [
        { ok: true, deliveryId: 'delivery-webhook', status: 'sent' },
        { ok: true, deliveryId: 'delivery-telegram', status: 'sent' },
      ],
    });
    await expect(service.retryDelivery('delivery-failing', context)).resolves.toMatchObject({
      ok: false,
      deliveryId: 'delivery-failing',
      status: 'failed',
      error: expect.stringContaining('503'),
    });
    await expect(service.retryDelivery('delivery-unconfigured', context)).resolves.toMatchObject({
      ok: false,
      deliveryId: 'delivery-unconfigured',
      status: 'failed',
      error: 'push channel is not configured for automatic sending',
    });

    expect(fetchMock.mock.calls[0]).toEqual([
      'https://hook.test/report',
      expect.objectContaining({ method: 'POST' }),
    ]);
    expect(fetchMock.mock.calls[1]).toEqual([
      'https://api.telegram.org/botbot/sendMessage',
      expect.objectContaining({ method: 'POST' }),
    ]);
    expect(query.mock.calls.filter(([sql]) => String(sql).includes("SET status = 'sent'")).length)
      .toBeGreaterThanOrEqual(2);
    expect(query.mock.calls.filter(([sql]) => String(sql).includes("SET status = 'failed'")).length)
      .toBeGreaterThanOrEqual(2);

    vi.stubGlobal('fetch', vi.fn(async () => { throw 'push string failure'; }));
    await expect(service.retryDelivery('delivery-webhook-string-failure', context)).resolves.toMatchObject({
      ok: false,
      deliveryId: 'delivery-webhook-string-failure',
      status: 'failed',
      error: 'push string failure',
    });

    query.mockReset();
    query.mockResolvedValueOnce(result([]));
    await expect(service.retryDelivery('missing-delivery', context)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('covers report defaults for update, templates, channels, weather locations, and helper fallbacks', async () => {
    const { service, query, database } = createHarness();

    query.mockResolvedValue(result([{ id: 'template-default' }]));
    await expect(service.upsertTemplate({}, context)).resolves.toEqual({
      ok: true,
      template: { id: 'template-default' },
    });
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO report_templates'),
      [context.userId, expect.any(String), 'daily_report', '# {{date}}\n\n{{actual_logs}}', '[]', false],
    );
    expect(
      query.mock.calls.some(([sql]) => String(sql).includes('UPDATE report_templates SET is_default = false')),
    ).toBe(false);

    query.mockReset();
    query.mockResolvedValue(result([{ id: 'channel-default' }]));
    await expect(service.upsertPushChannel({}, context)).resolves.toEqual({
      ok: true,
      channel: { id: 'channel-default' },
    });
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO push_channels'),
      [context.userId, 'webhook', 'webhook', 'enabled', '{}'],
    );

    query.mockReset();
    query.mockResolvedValue(result([{ id: 'weather-default' }]));
    await expect(
      service.upsertWeatherLocation({ latitude: 31.2, longitude: 121.5, isDefault: false }, context),
    ).resolves.toEqual({ ok: true, location: { id: 'weather-default' } });
    expect(query).toHaveBeenCalledWith(
      expect.stringContaining('INSERT INTO weather_locations'),
      [context.userId, expect.any(String), 31.2, 121.5, 'auto', false],
    );
    expect(
      query.mock.calls.some(([sql]) => String(sql).includes('UPDATE weather_locations SET is_default = false')),
    ).toBe(false);

    query.mockReset();
    query.mockResolvedValue(result([]));
    await expect(service.updateReport('report-no-note', {}, context)).resolves.toEqual({ ok: true });
    expect(database.transaction).toHaveBeenCalled();
    expect(
      query.mock.calls.some(([sql]) => String(sql).includes('INSERT INTO report_entries')),
    ).toBe(false);
  });

  it('covers report snapshot and rendering helper fallback branches', async () => {
    const { service, query } = createHarness();
    const api = privateApi(service);

    query.mockImplementation(async (sql: string, params?: unknown[]) => {
      if (sql.includes('actual_activity_logs')) return result([]);
      if (sql.includes('task_work_logs')) return result([]);
      if (sql.includes('activity_segments')) return result([]);
      if (sql.includes('plan_deviations')) return result([]);
      const objectTypes = Array.isArray(params?.[1]) ? params[1] as string[] : [];
      if (sql.includes('sync_objects') && objectTypes.includes('task')) {
        return result([{ id: 'task-row-without-uid', payload: { summary: 'Fallback task summary' } }]);
      }
      if (sql.includes('sync_objects')) {
        return result([{ id: 'schedule-row-without-uid', payload: { name: 'Fallback schedule name' } }]);
      }
      if (sql.includes('file_operation_logs')) return result([]);
      if (sql.includes('weather_cache')) return result([]);
      if (sql.includes('FROM report_templates')) return result([]);
      return result([]);
    });

    const snapshot = await api.sourceSnapshot(
      context.userId,
      new Date('2026-06-08T00:00:00.000Z'),
      new Date('2026-06-09T00:00:00.000Z'),
    );
    expect(snapshot).toMatchObject({
      tasks: [{ id: 'task-row-without-uid', payload: { summary: 'Fallback task summary' } }],
      schedules: [{ id: 'schedule-row-without-uid', payload: { name: 'Fallback schedule name' } }],
      weather: null,
    });

    const defaultTemplate = vi.spyOn(api, 'defaultTemplate').mockResolvedValue('# Custom\n{{actual_logs}}');
    await expect(
      api.renderReport(
        context.userId,
        'daily',
        new Date('2026-06-08T00:00:00.000Z'),
        { actuals: [], deviations: [{ id: 'dev-1' }] },
      ),
    ).resolves.toContain('##');
    expect(defaultTemplate).toHaveBeenCalledWith(context.userId, 'daily_report');

    expect(api.renderTemplate('known={{known}} missing={{missing}}', { known: 'yes' })).toBe(
      'known=yes missing=',
    );
    expect(api.builtInTemplate('unknown-template')).toContain('{{actual_logs}}');
    expect(api.bulletLines([{ payload: { uid: 'payload-uid' } }, { payload: {} }, {}], 'payload', 'empty'))
      .toContain('payload-uid');
    expect(api.bulletLines([{}], 'title', 'empty')).toContain('- ');
    expect(api.payloadTitle({ summary: 'Summary title' })).toBe('Summary title');
    expect(api.payloadTitle({ name: 'Named title' })).toBe('Named title');
    expect(api.payloadTitle({ uid: 'uid-title' })).toBe('uid-title');
    expect(api.payloadTitle({})).toBe('{}');
  });

  it('covers report entry insertion and template variable field defaults', async () => {
    const { service, query } = createHarness();
    const api = privateApi(service);
    query.mockImplementation(async (sql: string) => {
      if (sql.includes('INSERT INTO report_entries')) return result([{ id: `entry-${query.mock.calls.length}` }]);
      return result([]);
    });

    await expect(
      api.insertReportEntry({ query }, context.userId, 'report-entries', {
        type: 'fact',
        title: 'No payload entry',
        body: 'Body',
        orderIndex: 1,
      }),
    ).resolves.toEqual(expect.stringContaining('entry-'));
    await api.insertEvidence({ query }, context.userId, 'report-entries', 'entry-no-payload', {
      sourceType: 'manual',
      evidenceType: 'fact',
      summary: 'No payload evidence',
    });
    await api.insertReportEntries({ query }, context.userId, 'report-entries', {
      actuals: [{}],
      taskWork: [{}],
      activitySegments: [{}],
      deviations: [{}],
      files: [{ operation: undefined, sourcePath: undefined, targetPath: undefined }],
      weather: {},
    });

    const entryParams = query.mock.calls
      .filter(([sql]) => String(sql).includes('INSERT INTO report_entries'))
      .map(([, params]) => params as unknown[]);
    expect(entryParams.some((params) => params.includes('{}'))).toBe(true);
    expect(entryParams.some((params) => String(params[4]).includes('0'))).toBe(true);

    const variables = api.templateVariables('daily', new Date('2026-06-08T00:00:00.000Z'), {
      taskWork: [{}],
      activitySegments: [{}],
      deviations: [{}],
      files: [{}],
      weather: {},
    });
    expect(variables.task_work_summary).toContain('0');
    expect(variables.activity_segments).toContain('0%');
    expect(variables.plan_deviations.length).toBeGreaterThan(0);
    expect(variables.recent_files.length).toBeGreaterThan(0);
  });

  it('covers optional report LLM empty responses and non-Error polish failures', async () => {
    const { service, query } = createHarness();
    const api = privateApi(service);
    const payload = { kind: 'report', title: '', markdown: '', entries: [] };
    query.mockImplementation(async (sql: string) => {
      if (sql.includes('FROM ai_provider_configs')) {
        return result([
          {
            provider_type: 'openai_compatible',
            base_url: 'https://ai.test/v1',
            model: 'gpt-test',
            api_key_ciphertext: encrypt('unit-key', encryptionKey()),
            status: 'enabled',
            temperature: undefined,
            max_output_tokens: undefined,
            options: {},
          },
        ]);
      }
      return result([]);
    });

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({ ok: true, status: 200, text: async () => '' })),
    );
    await expect(api.callOptionalReportLlm(context.userId, payload)).rejects.toThrow(
      'AI API response did not contain message content.',
    );

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({ ok: true, status: 200, text: async () => JSON.stringify({}) })),
    );
    await expect(api.callOptionalReportLlm(context.userId, payload)).rejects.toThrow(
      'AI API response did not contain message content.',
    );

    vi.spyOn(service, 'report').mockResolvedValue({
      report: { id: 'report-string-error', title: null, contentMarkdown: null },
      entries: [],
      evidence: [],
    } as never);
    vi.spyOn(api, 'callOptionalReportLlm').mockRejectedValue('string failure');
    await expect(service.polishReport('report-string-error', context)).resolves.toMatchObject({
      ok: true,
      llmApplied: false,
      error: 'string failure',
    });

    query.mockReset();
    query.mockImplementation(async (sql: string) => {
      if (sql.includes('SELECT id::text AS id, title, body_markdown')) {
        return result([{ id: 'diary-string-error', title: null, contentMarkdown: null }]);
      }
      return result([]);
    });
    await expect(service.polishDiary('diary-string-error', context)).resolves.toMatchObject({
      ok: true,
      llmApplied: false,
      error: 'string failure',
    });
  });

  it('covers weather refresh empty and thrown-string fallback plus telegram payload defaults', async () => {
    const { service, query } = createHarness();
    query.mockImplementation(async (sql: string, params?: unknown[]) => {
      if (sql.includes('SELECT * FROM weather_locations')) {
        return result([{ id: 'weather-1', latitude: 31.2, longitude: 121.5, timezone: null }]);
      }
      if (sql.includes('SELECT d.*, c.config_json')) {
        return result([
          {
            id: params?.[1],
            channel: 'telegram',
            config_json: { botToken: 'bot', chatId: 'chat' },
            payload: {},
          },
        ]);
      }
      return result([]);
    });

    vi.stubGlobal(
      'fetch',
      vi.fn(async () => ({ ok: true, status: 200, text: async () => '' })),
    );
    await expect(service.refreshWeather('weather-1', context)).resolves.toMatchObject({
      ok: true,
      payload: {},
    });

    vi.stubGlobal('fetch', vi.fn(async () => { throw 'weather string failure'; }));
    await expect(service.refreshWeather('weather-1', context)).resolves.toMatchObject({
      ok: true,
      summary: expect.stringContaining('weather string failure'),
    });

    const sendFetch = vi.fn(async () => ({ ok: true, status: 200, text: async () => 'ok' }));
    vi.stubGlobal('fetch', sendFetch);
    await expect(service.retryDelivery('delivery-telegram-defaults', context)).resolves.toEqual({
      ok: true,
      deliveryId: 'delivery-telegram-defaults',
      status: 'sent',
    });
    expect(JSON.parse(String(sendFetch.mock.calls[0][1]?.body))).toMatchObject({
      chat_id: 'chat',
      text: expect.stringContaining('FlowPlanV2'),
    });
  });

  it('covers quality and comparison fallbacks for empty details and summary markdown', async () => {
    const { service } = createHarness();
    vi.spyOn(service, 'report').mockResolvedValueOnce({
      report: { id: 'empty-quality' },
      entries: null,
      evidence: [{}],
    } as never);
    const score = await service.reportQualityScore('empty-quality', context);
    expect(score).toMatchObject({
      reportId: 'empty-quality',
      dimensions: {
        completeness: { score: 0, weight: 0.3 },
        evidenceCoverage: { score: 0, weight: 0.25 },
        factualAccuracy: { score: 100, weight: 0.25 },
      },
      entryStats: { factCount: 0, inferredCount: 0, externalCount: 0, total: 0 },
    });

    vi.spyOn(service, 'report')
      .mockResolvedValueOnce({
        report: { id: 'a', periodStart: '2026-06-07', summary_markdown: 'old' },
        entries: [{ entryType: 'fact' }, { title: undefined, entryType: 'inferred' }],
        evidence: [],
      } as never)
      .mockResolvedValueOnce({
        report: { id: 'b', periodStart: '2026-06-08', summary_markdown: 'newer' },
        entries: [{ title: undefined, entryType: 'fact' }, { title: 'Fresh', entryType: 'external' }],
        evidence: [],
      } as never);

    await expect(service.compareReports('a', 'b', context)).resolves.toMatchObject({
      delta: { entryCount: 0, factCount: 0, contentLength: 2 },
      newEntries: [{ type: 'external', title: 'Fresh' }],
      removedEntries: [],
    });
  });

  it('covers quality status and compare null-entry fallbacks', async () => {
    const { service } = createHarness();
    vi.spyOn(service, 'report').mockResolvedValueOnce({
      report: { id: 'quality-status-fallback', contentMarkdown: 'rich text' },
      entries: [{ id: 'candidate-without-status', entryType: 'inferred', title: 'Candidate' }],
      evidence: [{ entryId: 'candidate-without-status' }, {}],
    } as never);

    await expect(service.reportQualityScore('quality-status-fallback', context)).resolves.toMatchObject({
      dimensions: {
        completeness: { score: 30, weight: 0.3 },
        evidenceCoverage: { score: 100, weight: 0.25 },
        factualAccuracy: { score: 0, weight: 0.25 },
      },
      entryStats: { inferredCount: 1, total: 1 },
    });

    vi.spyOn(service, 'report')
      .mockResolvedValueOnce({
        report: { id: 'baseline-no-markdown', periodStart: '2026-06-07' },
        entries: null,
        evidence: [],
      } as never)
      .mockResolvedValueOnce({
        report: { id: 'comparison-no-markdown', periodStart: '2026-06-08' },
        entries: null,
        evidence: [],
      } as never);

    await expect(service.compareReports('baseline-no-markdown', 'comparison-no-markdown', context)).resolves.toMatchObject({
      baseline: { entryCount: 0, factCount: 0, contentLength: 0 },
      comparison: { entryCount: 0, factCount: 0, contentLength: 0 },
      delta: { entryCount: 0, factCount: 0, contentLength: 0 },
      newEntries: [],
      removedEntries: [],
    });
  });

  it('covers date and quality scoring residual fallback branches', async () => {
    const { service } = createHarness();
    const api = privateApi(service);

    vi.useFakeTimers();
    vi.setSystemTime(new Date('2026-06-10T12:34:56.000Z'));
    expect(api.period('daily', '   ', null, null)).toEqual({
      start: new Date('2026-06-10T00:00:00.000Z'),
      end: new Date('2026-06-11T00:00:00.000Z'),
    });
    vi.useRealTimers();

    vi.spyOn(service, 'report').mockResolvedValueOnce({
      report: { id: 'quality-empty-markdown' },
      entries: [{ entryType: 'fact' }],
      evidence: null,
    } as never);

    await expect(service.reportQualityScore('quality-empty-markdown', context)).resolves.toMatchObject({
      dimensions: {
        evidenceCoverage: { score: 0, weight: 0.25 },
        contentRichness: { score: 0, weight: 0.2 },
      },
    });
  });

  it('generates default daily reports and non-LLM diary drafts from empty snapshots', async () => {
    const reportHarness = createHarness();
    reportHarness.query.mockImplementation(async (sql: string) => {
      if (sql.includes('actual_activity_logs')) return result([]);
      if (sql.includes('task_work_logs')) return result([]);
      if (sql.includes('activity_segments')) return result([]);
      if (sql.includes('plan_deviations')) return result([]);
      if (sql.includes('sync_objects')) return result([]);
      if (sql.includes('file_operation_logs')) return result([]);
      if (sql.includes('weather_cache')) return result([]);
      if (sql.includes('FROM report_templates')) return result([]);
      if (sql.includes('INSERT INTO report_documents')) return result([{ id: 'report-default-daily' }]);
      if (sql.includes('INSERT INTO report_entries')) return result([{ id: `entry-${reportHarness.query.mock.calls.length}` }]);
      if (sql.includes('FROM report_documents')) {
        return result([{ id: 'report-default-daily', title: 'Default daily', contentMarkdown: 'body' }]);
      }
      if (sql.includes('FROM report_entries')) return result([]);
      if (sql.includes('FROM report_evidence_links')) return result([]);
      return result([]);
    });

    await expect(reportHarness.service.generateReport({ date: '2026-06-08' }, context)).resolves.toMatchObject({
      report: { id: 'report-default-daily' },
      modelUsed: 'rule_learned',
    });
    expect(reportHarness.query.mock.calls.find(([sql]) => String(sql).includes('INSERT INTO report_documents'))?.[1])
      .toEqual(expect.arrayContaining([context.userId, 'report:daily:2026-06-08', 'daily']));

    const diaryHarness = createHarness();
    const polishDiary = vi.spyOn(diaryHarness.service, 'polishDiary');
    diaryHarness.query.mockImplementation(async (sql: string) => {
      if (sql.includes('actual_activity_logs')) return result([]);
      if (sql.includes('task_work_logs')) return result([]);
      if (sql.includes('activity_segments')) return result([]);
      if (sql.includes('plan_deviations')) return result([]);
      if (sql.includes('sync_objects')) return result([]);
      if (sql.includes('file_operation_logs')) return result([]);
      if (sql.includes('weather_cache')) return result([]);
      if (sql.includes('FROM report_templates')) return result([]);
      if (sql.includes('INSERT INTO diary_entries')) return result([{ id: 'diary-default-no-llm' }]);
      return result([]);
    });

    await expect(diaryHarness.service.generateDiary({ date: '2026-06-08' }, context)).resolves.toEqual({
      ok: true,
      diaryId: 'diary-default-no-llm',
      modelRunId: 'model-run-1',
      modelUsed: 'rule_learned',
      modelVersion: 'report-v1',
    });
    expect(polishDiary).not.toHaveBeenCalled();
    expect(diaryHarness.query.mock.calls.find(([sql]) => String(sql).includes('INSERT INTO diary_entries'))?.[1])
      .toEqual(expect.arrayContaining([context.userId, 'diary:2026-06-08', '2026-06-08', expect.any(String), expect.any(String), '{}']));
    expect(diaryHarness.models.completeRun).toHaveBeenCalledWith(
      context.userId,
      'model-run-1',
      expect.objectContaining({
        outputSummary: expect.objectContaining({ generationMode: 'template' }),
        usedLlm: false,
      }),
    );
  });

  it('polishes null report and diary content with empty LLM payload fields', async () => {
    const { service, query } = createHarness();
    const fetchMock = vi.fn(async () => ({
      ok: true,
      status: 200,
      text: async () => JSON.stringify({ choices: [{ message: { content: 'Fallback polish' } }] }),
    }));
    vi.stubGlobal('fetch', fetchMock);
    vi.spyOn(service, 'report').mockResolvedValue({
      report: { id: 'report-null-content', title: null, contentMarkdown: null },
      entries: [],
      evidence: [],
    } as never);
    query.mockImplementation(async (sql: string) => {
      if (sql.includes('FROM ai_provider_configs')) {
        return result([
          {
            provider_type: 'openai_compatible',
            base_url: 'https://ai.test/v1/',
            model: 'gpt-test',
            api_key_ciphertext: encrypt('unit-key', encryptionKey()),
            status: 'enabled',
            options: {},
          },
        ]);
      }
      if (sql.includes('INSERT INTO report_entries')) return result([{ id: 'null-ai-entry' }]);
      if (sql.includes('SELECT id::text AS id, title, body_markdown')) {
        return result([{ id: 'diary-null-content', title: null, contentMarkdown: null }]);
      }
      return result([]);
    });

    await expect(service.polishReport('report-null-content', context)).resolves.toMatchObject({
      ok: true,
      llmApplied: true,
    });
    await expect(service.polishDiary('diary-null-content', context)).resolves.toEqual({
      ok: true,
      llmApplied: true,
    });

    const firstPayload = JSON.parse(String(fetchMock.mock.calls[0][1]?.body));
    const secondPayload = JSON.parse(String(fetchMock.mock.calls[1][1]?.body));
    expect(firstPayload.messages[1].content).toContain('"title":""');
    expect(firstPayload.messages[1].content).toContain('"markdown":""');
    expect(secondPayload.messages[1].content).toContain('"title":""');
    expect(secondPayload.messages[1].content).toContain('"markdown":""');
  });

  it('covers delivery and helper residual fallback branches', async () => {
    const { service, query } = createHarness();
    const api = privateApi(service);
    query.mockImplementation(async (sql: string, params?: unknown[]) => {
      if (sql.includes('SELECT d.*, c.config_json')) {
        return result([
          {
            id: params?.[1],
            channel: 'webhook',
            config_json: { url: 'https://hook.test/string-failure' },
            payload: {},
          },
        ]);
      }
      return result([]);
    });
    vi.stubGlobal('fetch', vi.fn(async () => { throw 'delivery string failure'; }));

    await expect(service.retryDelivery('delivery-string-failure', context)).resolves.toEqual({
      ok: false,
      deliveryId: 'delivery-string-failure',
      status: 'failed',
      error: 'delivery string failure',
    });

    expect(api.weatherSummaryFromPayload({ daily: { time: ['2026-06-08'] } })).toContain('?');
    expect(api.bulletLines([{}], 'title', 'empty')).toMatch(/^- .+/);
    expect(api.payloadTitle({ title: 'Direct title' })).toBe('Direct title');
  });

  it('queues push payloads with an empty summary when report markdown is absent', async () => {
    const { service, query } = createHarness();
    vi.spyOn(Date, 'now').mockReturnValue(67890);
    vi.spyOn(service, 'report').mockResolvedValue({
      report: { id: 'report-null-summary', reportUid: 'report:daily:null-summary', title: 'Null summary', contentMarkdown: null },
      entries: [],
      evidence: [],
    } as never);
    query.mockImplementation(async (sql: string, params?: unknown[]) => {
      if (sql.includes('FROM push_channels')) {
        return result([{ id: 'channel-email', channel_type: 'email', config_json: { email: 'ops@example.test' } }]);
      }
      if (sql.includes('INSERT INTO report_push_deliveries')) {
        return result([{ id: 'delivery-null-summary' }]);
      }
      if (sql.includes('SELECT d.*, c.config_json')) {
        return result([{ id: params?.[1], channel: 'email', config_json: {}, payload: {} }]);
      }
      return result([]);
    });

    await expect(service.pushReport('report-null-summary', {}, context)).resolves.toMatchObject({
      ok: true,
      deliveries: ['delivery-null-summary'],
      results: [{ ok: false, deliveryId: 'delivery-null-summary', status: 'failed' }],
    });

    const queuedPayload = JSON.parse(String(
      query.mock.calls.find(([sql]) => String(sql).includes('INSERT INTO report_push_deliveries'))?.[1]?.[5],
    ));
    expect(queuedPayload).toMatchObject({
      title: 'Null summary',
      summary: '',
      reportId: 'report-null-summary',
      reportUid: 'report:daily:null-summary',
    });
  });
});
