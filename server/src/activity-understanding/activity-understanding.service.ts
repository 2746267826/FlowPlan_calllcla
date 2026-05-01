import { BadRequestException, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { QueryResultRow } from 'pg';
import { FlowPlanRequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import { ModelsService } from '../models/models.service';

export interface ActivityUnderstandingQuery {
  date?: string;
  start?: string;
  end?: string;
  status?: string;
  limit?: string;
  offset?: string;
}

interface RawActivity {
  id: string;
  objectType: string;
  startAt: Date;
  endAt: Date;
  appName: string;
  windowTitle: string;
  filePath?: string;
  payload: Record<string, unknown>;
}

interface BuiltSegment {
  uid: string;
  startAt: Date;
  endAt: Date;
  appName: string;
  windowTitle: string;
  filePath?: string;
  title: string;
  confidence: number;
  category: string;
  sourceIds: string[];
  evidence: Record<string, unknown>;
  matchedTaskId?: string;
  matchedTaskTitle?: string;
}

@Injectable()
export class ActivityUnderstandingService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
    private readonly modelsService: ModelsService,
  ) {}

  async buildSegments(
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const { start, end } = this.readRange(body.date, body.start, body.end);
    const rebuild = body.rebuild === true;
    const activeModel = await this.modelsService.activeProfile(userId, 'activity_merge.v1');
    const profile = this.asRecord(activeModel.ruleProfile);
    const modelRun = await this.modelsService.startRun(userId, 'activity_merge.v1', {
      source: 'activity.buildSegments',
      inputSummary: {
        start: start.toISOString(),
        end: end.toISOString(),
        rebuild,
        profile,
      },
    });
    const raw = await this.readRawActivities(userId, start, end);
    const tasks = await this.readTaskCandidates(userId);
    const built = this.mergeActivities(raw, profile).map((segment) =>
      this.matchTask(segment, tasks, profile),
    );

    let created = 0;
    let updated = 0;
    await this.database.transaction(async (client) => {
      if (rebuild) {
        await client.query(
          `
          DELETE FROM activity_segment_evidence
          WHERE user_id = $1
            AND segment_id IN (
              SELECT id FROM activity_segments
              WHERE user_id = $1 AND start_at >= $2 AND start_at < $3 AND status = 'candidate'
            )
          `,
          [userId, start, end],
        );
        await client.query(
          `
          DELETE FROM activity_interpretations
          WHERE user_id = $1
            AND segment_id IN (
              SELECT id FROM activity_segments
              WHERE user_id = $1 AND start_at >= $2 AND start_at < $3 AND status = 'candidate'
            )
          `,
          [userId, start, end],
        );
        await client.query(
          `
          DELETE FROM activity_segments
          WHERE user_id = $1 AND start_at >= $2 AND start_at < $3 AND status = 'candidate'
          `,
          [userId, start, end],
        );
      }

      for (const segment of built) {
        const row = await client.query<QueryResultRow>(
          `
          INSERT INTO activity_segments (
            user_id,
            segment_uid,
            start_at,
            end_at,
            duration_seconds,
            primary_process_name,
            primary_app,
            primary_window_title,
            primary_file_path,
            category,
            label,
            source_record_ids,
            evidence,
            confidence,
            status,
            matched_task_id
          ) VALUES (
            $1, $2, $3, $4, $5, $6, $6, $7, $8, $9, $10, $11::jsonb, $12::jsonb, $13, 'candidate', $14
          )
          ON CONFLICT (user_id, segment_uid) DO UPDATE SET
            start_at = EXCLUDED.start_at,
            end_at = EXCLUDED.end_at,
            duration_seconds = EXCLUDED.duration_seconds,
            primary_process_name = EXCLUDED.primary_process_name,
            primary_app = EXCLUDED.primary_app,
            primary_window_title = EXCLUDED.primary_window_title,
            primary_file_path = EXCLUDED.primary_file_path,
            category = EXCLUDED.category,
            label = EXCLUDED.label,
            source_record_ids = EXCLUDED.source_record_ids,
            evidence = EXCLUDED.evidence,
            confidence = EXCLUDED.confidence,
            matched_task_id = EXCLUDED.matched_task_id,
            updated_at = now()
          RETURNING id::text AS id, (xmax = 0) AS inserted
          `,
          [
            userId,
            segment.uid,
            segment.startAt,
            segment.endAt,
            this.durationSeconds(segment.startAt, segment.endAt),
            segment.appName,
            segment.windowTitle,
            segment.filePath ?? null,
            segment.category,
            segment.title,
            JSON.stringify(segment.sourceIds),
            JSON.stringify(segment.evidence),
            segment.confidence,
            segment.matchedTaskId ?? null,
          ],
        );
        const segmentId = String(row.rows[0]?.id);
        if (row.rows[0]?.inserted) {
          created += 1;
        } else {
          updated += 1;
        }
        await client.query(
          `
          INSERT INTO activity_interpretations (
            user_id,
            interpretation_uid,
            segment_id,
            title,
            summary,
            interpreted_type,
            inferred_task_id,
            matched_task_id,
            confidence,
            evidence,
            reason_json,
            model_used,
            status
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $7, $8, $9::jsonb, $10::jsonb, 'rule', 'candidate')
          ON CONFLICT (user_id, interpretation_uid) DO UPDATE SET
            title = EXCLUDED.title,
            summary = EXCLUDED.summary,
            interpreted_type = EXCLUDED.interpreted_type,
            inferred_task_id = EXCLUDED.inferred_task_id,
            matched_task_id = EXCLUDED.matched_task_id,
            confidence = EXCLUDED.confidence,
            evidence = EXCLUDED.evidence,
            reason_json = EXCLUDED.reason_json,
            updated_at = now()
          `,
          [
            userId,
            `interp:${segment.uid}`,
            segmentId,
            segment.title,
            this.segmentSummary(segment),
            segment.category,
            segment.matchedTaskId ?? null,
            segment.confidence,
            JSON.stringify(segment.evidence),
            JSON.stringify({
              matchedTaskTitle: segment.matchedTaskTitle,
              mergeMethod: 'time_app_rule',
              modelVersion: activeModel.versionKey,
              lowConfidenceAsCandidate: segment.confidence < 0.85,
            }),
          ],
        );
        await client.query(
          `
          INSERT INTO activity_segment_evidence (
            user_id, segment_id, source_type, source_id, evidence_summary, weight, payload
          ) VALUES ($1, $2, 'activity_record', $3, $4, $5, $6::jsonb)
          `,
          [
            userId,
            segmentId,
            segment.sourceIds[0] ?? null,
            this.segmentSummary(segment),
            Math.round(segment.confidence * 100),
            JSON.stringify(segment.evidence),
          ],
        );
      }
      await this.recordAudit(client, userId, deviceId, 'activity.build_segments', {
        start: start.toISOString(),
        end: end.toISOString(),
        rawCount: raw.length,
        segmentCount: built.length,
      });
    });
    await this.modelsService.completeRun(userId, modelRun.id, {
      status: 'succeeded',
      outputSummary: {
        rawCount: raw.length,
        segmentCount: built.length,
        lowConfidenceCount: built.filter((item) => item.confidence < 0.65).length,
      },
      confidence:
        built.length === 0
          ? 0
          : built.reduce((sum, item) => sum + item.confidence, 0) / built.length,
      usedLlm: false,
    });

    return {
      range: { start: start.toISOString(), end: end.toISOString() },
      modelRunId: modelRun.id,
      modelUsed: 'rule_learned',
      modelVersion: activeModel.versionKey,
      rawCount: raw.length,
      segmentsCreated: created,
      segmentsUpdated: updated,
      lowConfidenceCount: built.filter((item) => item.confidence < 0.65).length,
    };
  }

  async segments(query: ActivityUnderstandingQuery, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const { start, end } = this.readRange(query.date, query.start, query.end);
    const status = this.clean(query.status);
    const limit = this.readLimit(query.limit, 100);
    const offset = this.readOffset(query.offset);
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT
        s.id::text AS id,
        s.segment_uid AS "segmentUid",
        s.start_at AS "startAt",
        s.end_at AS "endAt",
        s.duration_seconds AS "durationSeconds",
        s.primary_app AS "primaryApp",
        s.primary_process_name AS "primaryProcessName",
        s.primary_window_title AS "primaryWindowTitle",
        s.primary_file_path AS "primaryFilePath",
        s.category,
        s.label AS title,
        s.confidence,
        s.status,
        s.matched_task_id AS "matchedTaskId",
        i.summary,
        i.reason_json AS "reason",
        COALESCE(json_agg(e.*) FILTER (WHERE e.id IS NOT NULL), '[]') AS evidence
      FROM activity_segments s
      LEFT JOIN activity_interpretations i ON i.segment_id = s.id
      LEFT JOIN activity_segment_evidence e ON e.segment_id = s.id
      WHERE s.user_id = $1
        AND s.start_at >= $2
        AND s.start_at < $3
        AND ($4::text IS NULL OR s.status = $4)
      GROUP BY s.id, i.summary, i.reason_json
      ORDER BY s.start_at ASC
      LIMIT $5 OFFSET $6
      `,
      [userId, start, end, status, limit, offset],
    );
    return { range: { start, end }, limit, offset, hasMore: result.rows.length >= limit, items: result.rows };
  }

  async confirmSegment(
    segmentId: string,
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const taskId = this.clean(body.taskId);
    const result = await this.database.transaction(async (client) => {
      const segmentResult = await client.query<QueryResultRow>(
        `
        SELECT * FROM activity_segments
        WHERE user_id = $1 AND id = $2
        LIMIT 1
        `,
        [userId, segmentId],
      );
      const segment = segmentResult.rows[0];
      if (!segment) {
        throw new BadRequestException('segment not found');
      }
      const title = this.clean(body.title) ?? String(segment.label ?? '已确认活动');
      const actualUid = `actual:${segment.segment_uid}`;
      const actual = await client.query<QueryResultRow>(
        `
        INSERT INTO actual_activity_logs (
          user_id,
          actual_uid,
          title,
          start_at,
          end_at,
          duration_seconds,
          source_type,
          source_id,
          source_payload,
          confidence,
          status,
          note,
          confirmed_at
        ) VALUES ($1, $2, $3, $4, $5, $6, 'activity_segment', $7, $8::jsonb, $9, 'confirmed', $10, now())
        ON CONFLICT (user_id, actual_uid) DO UPDATE SET
          title = EXCLUDED.title,
          source_payload = EXCLUDED.source_payload,
          confidence = EXCLUDED.confidence,
          status = 'confirmed',
          note = EXCLUDED.note,
          confirmed_at = now(),
          updated_at = now()
        RETURNING id::text AS id
        `,
        [
          userId,
          actualUid,
          title,
          segment.start_at,
          segment.end_at,
          Number(segment.duration_seconds ?? 0),
          segmentId,
          JSON.stringify({ segmentId, userConfirmed: true }),
          Number(segment.confidence ?? 0.5),
          this.clean(body.notes),
        ],
      );
      const actualId = String(actual.rows[0]?.id);
      if (taskId) {
        await client.query(
          `
          INSERT INTO task_work_logs (
            user_id,
            work_uid,
            task_id,
            segment_id,
            actual_id,
            start_at,
            end_at,
            duration_minutes,
            duration_seconds,
            confidence,
            source_type,
            evidence,
            status,
            confirmed_at
          ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'activity_segment', $11::jsonb, 'confirmed', now())
          ON CONFLICT (user_id, work_uid) DO UPDATE SET
            status = 'confirmed',
            actual_id = EXCLUDED.actual_id,
            duration_minutes = EXCLUDED.duration_minutes,
            duration_seconds = EXCLUDED.duration_seconds,
            confirmed_at = now(),
            updated_at = now()
          `,
          [
            userId,
            `work:${segment.segment_uid}:${taskId}`,
            taskId,
            segmentId,
            actualId,
            segment.start_at,
            segment.end_at,
            Math.max(1, Math.round(Number(segment.duration_seconds ?? 0) / 60)),
            Number(segment.duration_seconds ?? 0),
            Number(segment.confidence ?? 0.5),
            JSON.stringify({ segmentId, title }),
          ],
        );
      }
      await client.query(
        `
        UPDATE activity_segments
        SET status = 'confirmed', label = $3, matched_task_id = COALESCE($4, matched_task_id), updated_at = now()
        WHERE user_id = $1 AND id = $2
        `,
        [userId, segmentId, title, taskId],
      );
      await client.query(
        `
        UPDATE activity_interpretations
        SET status = 'accepted', matched_task_id = COALESCE($3, matched_task_id), updated_at = now()
        WHERE user_id = $1 AND segment_id = $2
        `,
        [userId, segmentId, taskId],
      );
        await this.recordAudit(client, userId, deviceId, 'activity.confirm_segment', {
          segmentId,
          actualId,
          taskId,
        });
        await this.modelsService.recordFeedback(client, userId, deviceId, 'activity_merge.v1', {
          targetType: 'activity_segment',
          targetId: segmentId,
          feedbackType: taskId ? 'accepted_with_task' : 'accepted',
          outcome: 'accepted',
          source: 'activity.confirmSegment',
          feedbackPayload: {
            actualId,
            taskId,
            title,
            confidence: Number(segment.confidence ?? 0.5),
          },
        });
        return { actualId, taskId };
      });
    return { ok: true, ...result };
  }

  async rejectSegment(
    segmentId: string,
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.database.transaction(async (client) => {
      await client.query(
        `
        UPDATE activity_segments
        SET status = 'rejected', evidence = evidence || $3::jsonb, updated_at = now()
        WHERE user_id = $1 AND id = $2
        `,
        [userId, segmentId, JSON.stringify({ rejectReason: this.clean(body.reason) })],
      );
      await client.query(
        `
        UPDATE activity_interpretations
        SET status = 'rejected', updated_at = now()
        WHERE user_id = $1 AND segment_id = $2
        `,
        [userId, segmentId],
      );
        await this.recordAudit(client, userId, deviceId, 'activity.reject_segment', {
          segmentId,
          reason: this.clean(body.reason),
        });
        await this.modelsService.recordFeedback(client, userId, deviceId, 'activity_merge.v1', {
          targetType: 'activity_segment',
          targetId: segmentId,
          feedbackType: 'rejected',
          outcome: 'rejected',
          source: 'activity.rejectSegment',
          feedbackPayload: {
            reason: this.clean(body.reason),
          },
        });
      });
      return { ok: true };
    }

  async feedback(
    segmentId: string,
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.database.transaction(async (client) => {
      await this.modelsService.recordFeedback(client, userId, deviceId, 'activity_merge.v1', {
        targetType: 'activity_segment',
        targetId: segmentId,
        feedbackType: this.clean(body.feedbackType) ?? 'modified',
        outcome: this.clean(body.outcome) ?? this.clean(body.feedbackType) ?? 'modified',
        source: 'activity.segment.feedback',
        feedbackPayload: this.asRecord(body.feedbackPayload ?? body.payload),
      });
      await this.recordAudit(client, userId, deviceId, 'activity.segment.feedback', {
        segmentId,
        feedbackType: this.clean(body.feedbackType) ?? 'modified',
      });
    });
    return { ok: true };
  }

  private async readRawActivities(userId: string, start: Date, end: Date) {
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT id::text AS id, object_type AS "objectType", payload, updated_at AS "updatedAt"
      FROM sync_objects
      WHERE user_id = $1
        AND deleted_at IS NULL
        AND object_type = ANY($2::text[])
        AND updated_at >= $3 - interval '1 day'
        AND updated_at < $4 + interval '1 day'
      ORDER BY updated_at ASC
      LIMIT 5000
      `,
      [
        userId,
        [
          'raw_activity_log',
          'raw_activity_logs',
          'activity_record',
          'activity_records',
          'tracked_input_event',
          'tracked_input_events',
          'input_event',
        ],
        start,
        end,
      ],
    );
    return result.rows
      .map((row) => this.toRawActivity(row))
      .filter((item): item is RawActivity => {
        return !!item && item.startAt < end && item.endAt > start;
      })
      .sort((a, b) => a.startAt.getTime() - b.startAt.getTime());
  }

  private async readTaskCandidates(userId: string) {
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT id::text AS id, uid, payload
      FROM sync_objects
      WHERE user_id = $1
        AND deleted_at IS NULL
        AND object_type = ANY($2::text[])
      ORDER BY updated_at DESC
      LIMIT 500
      `,
      [userId, ['task', 'tasks', 'task_item', 'task_items']],
    );
    return result.rows.map((row) => {
      const payload = this.asRecord(row.payload);
      return {
        id: String(row.uid ?? row.id),
        title: this.readString(payload, ['title', 'name', 'summary']) ?? String(row.uid ?? row.id),
        text: JSON.stringify(payload).toLowerCase(),
      };
    });
  }

  private mergeActivities(raw: RawActivity[], profile: Record<string, unknown>) {
    const segments: BuiltSegment[] = [];
    let current: RawActivity[] = [];
    const mergeGapMinutes = Number(profile.mergeGapMinutes ?? 10);
    const shortInterruptionMinutes = Number(profile.shortInterruptionMinutes ?? 3);
    const appConfidenceBonus = Number(profile.appConfidenceBonus ?? 0.12);
    const close = () => {
      if (current.length === 0) return;
      const first = current[0];
      const last = current[current.length - 1];
      const appCounts = new Map<string, number>();
      for (const item of current) {
        appCounts.set(item.appName, (appCounts.get(item.appName) ?? 0) + 1);
      }
      const appName = [...appCounts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? 'unknown';
      const main = current.find((item) => item.appName === appName) ?? first;
        const confidence = Math.min(0.95, 0.45 + current.length * 0.08 + (appName !== 'unknown' ? appConfidenceBonus : 0));
      segments.push({
        uid: `seg:${first.startAt.toISOString().slice(0, 10)}:${first.id}:${last.id}`,
        startAt: first.startAt,
        endAt: new Date(Math.max(...current.map((item) => item.endAt.getTime()))),
        appName,
        windowTitle: main.windowTitle,
        filePath: main.filePath,
        title: this.inferTitle(appName, main.windowTitle),
        confidence,
        category: this.inferCategory(appName, main.windowTitle),
        sourceIds: current.map((item) => item.id),
        evidence: {
          apps: [...appCounts.keys()],
          windows: current.slice(0, 8).map((item) => item.windowTitle).filter(Boolean),
          filePaths: current.map((item) => item.filePath).filter(Boolean).slice(0, 8),
          mergeRule: 'same_app_or_short_gap',
        },
      });
      current = [];
    };

    for (const item of raw) {
      const previous = current[current.length - 1];
      if (!previous) {
        current.push(item);
        continue;
      }
      const gapMinutes = (item.startAt.getTime() - previous.endAt.getTime()) / 60000;
      const sameApp = item.appName === previous.appName;
        const shortInterruption = gapMinutes <= shortInterruptionMinutes && this.isInterruptible(item.appName);
        if (gapMinutes <= mergeGapMinutes && (sameApp || shortInterruption)) {
        current.push(item);
      } else {
        close();
        current.push(item);
      }
    }
    close();
    return segments.filter((item) => this.durationSeconds(item.startAt, item.endAt) >= 60);
  }

  private matchTask(
    segment: BuiltSegment,
    tasks: Array<{ id: string; title: string; text: string }>,
    profile: Record<string, unknown>,
  ) {
    const haystack = `${segment.title} ${segment.windowTitle} ${segment.filePath ?? ''}`.toLowerCase();
    let best: { id: string; title: string; score: number } | undefined;
    for (const task of tasks) {
      const words = task.title
        .toLowerCase()
        .split(/[\s_/\\\-:，。,.]+/)
        .filter((word) => word.length >= 2);
      const titleHits = words.filter((word) => haystack.includes(word)).length;
      const pathHit = segment.filePath && task.text.includes(segment.filePath.toLowerCase());
      const score = titleHits * 25 + (pathHit ? 35 : 0);
      if (score > (best?.score ?? 0)) {
        best = { id: task.id, title: task.title, score };
      }
    }
      if (best && best.score >= Number(profile.taskMatchThreshold ?? 25)) {
      segment.matchedTaskId = best.id;
      segment.matchedTaskTitle = best.title;
      segment.confidence = Math.min(0.98, segment.confidence + best.score / 100);
      segment.title = `可能在推进：${best.title}`;
      segment.evidence = { ...segment.evidence, matchedTask: best };
    }
    return segment;
  }

  private toRawActivity(row: QueryResultRow): RawActivity | null {
    const payload = this.asRecord(row.payload);
    const startAt =
      this.readDate(this.readString(payload, ['startTime', 'start_at', 'startedAt', 'timestamp', 'occurredAt'])) ??
      this.readDate(row.updatedAt) ??
      null;
    if (!startAt) return null;
    const endAt =
      this.readDate(this.readString(payload, ['endTime', 'end_at', 'endedAt'])) ??
      new Date(startAt.getTime() + Math.max(60, Number(payload.durationSeconds ?? 300)) * 1000);
    return {
      id: String(row.id),
      objectType: String(row.objectType),
      startAt,
      endAt,
      appName:
        this.readString(payload, ['appName', 'processName', 'process_name', 'packageName', 'application']) ??
        'unknown',
      windowTitle: this.readString(payload, ['windowTitle', 'window_title', 'title', 'summary']) ?? '',
      filePath:
        this.readString(payload, ['filePath', 'file_path', 'path', 'projectPath']) ??
        undefined,
      payload,
    };
  }

  private inferTitle(appName: string, windowTitle: string) {
    if (windowTitle) return `${appName}: ${windowTitle}`.slice(0, 160);
    return appName === 'unknown' ? '未识别活动片段' : `${appName} 活动`;
  }

  private inferCategory(appName: string, windowTitle: string) {
    const text = `${appName} ${windowTitle}`.toLowerCase();
    if (/(code|studio|idea|pycharm|terminal|powershell|cmd|git)/.test(text)) return 'coding';
    if (/(word|excel|powerpoint|pdf|markdown|obsidian|notion)/.test(text)) return 'writing';
    if (/(teams|zoom|meeting|腾讯会议)/.test(text)) return 'meeting';
    if (/(wechat|qq|telegram|mail)/.test(text)) return 'communication';
    if (/(bilibili|youtube|video|music|game)/.test(text)) return 'entertainment';
    return 'unknown';
  }

  private isInterruptible(appName: string) {
    return /wechat|qq|telegram|mail|notification/i.test(appName);
  }

  private segmentSummary(segment: BuiltSegment) {
    const minutes = Math.max(1, Math.round(this.durationSeconds(segment.startAt, segment.endAt) / 60));
    return `${segment.title}，持续约 ${minutes} 分钟，主要应用 ${segment.appName}`;
  }

  private readRange(date: unknown, rawStart: unknown, rawEnd: unknown) {
    const explicitStart = this.readDate(rawStart);
    const explicitEnd = this.readDate(rawEnd);
    if (explicitStart && explicitEnd && explicitStart < explicitEnd) {
      return { start: explicitStart, end: explicitEnd };
    }
    const dateText = typeof date === 'string' && date.trim() ? date.trim() : new Date().toISOString().slice(0, 10);
    const start = new Date(`${dateText}T00:00:00.000Z`);
    const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
    return { start, end };
  }

  private durationSeconds(start: Date, end: Date) {
    return Math.max(0, Math.round((end.getTime() - start.getTime()) / 1000));
  }

  private readLimit(value: string | undefined, fallback: number) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? Math.max(1, Math.min(500, Math.trunc(parsed))) : fallback;
  }

  private readOffset(value: string | undefined) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? Math.max(0, Math.trunc(parsed)) : 0;
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

  private readString(payload: Record<string, unknown>, keys: string[]) {
    for (const key of keys) {
      const value = payload[key];
      if (typeof value === 'string' && value.trim().length > 0) {
        return value.trim();
      }
    }
    return null;
  }

  private async recordAudit(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    action: string,
    details: Record<string, unknown>,
  ) {
    await client.query(
      `
      INSERT INTO audit_logs (
        user_id, device_id, actor, action, entity_type, entity_id, summary, metadata
      ) VALUES ($1, $2, 'system', $3, $4, $5, $3, $6::jsonb)
      `,
      [
        userId,
        deviceId,
        action,
        String(details.targetType ?? 'activity_segment'),
        details.segmentId ? String(details.segmentId) : null,
        JSON.stringify(details),
      ],
    );
  }
}
