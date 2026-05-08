import { BadRequestException, Injectable } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import { QueryResultRow } from 'pg';
import { FlowPlanV2RequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import { ModelsService } from '../models/models.service';
import { clean, asRecord, asArray, readDate, readLimit, readOffset } from '../common/utils';
import { TfidfMatcher } from '../common/utils/tfidf';
import { ObjectType, TaskTypes, TrackingTypes } from '../common/constants/object-types';

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
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const { start, end } = this.readRange(body.date, body.start, body.end);
    const rebuild = body.rebuild === true;
    const activeModel = await this.modelsService.activeProfile(userId, 'activity_merge.v1');
    const profile = asRecord(activeModel.ruleProfile);
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

  async segments(query: ActivityUnderstandingQuery, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const { start, end } = this.readRange(query.date, query.start, query.end);
    const status = clean(query.status);
    const limit = readLimit(query.limit, 100);
    const offset = readOffset(query.offset);
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
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const taskId = clean(body.taskId);
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
      const title = clean(body.title) ?? String(segment.label ?? '已确认活动');
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
          clean(body.notes),
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
    context: FlowPlanV2RequestContext,
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
        [userId, segmentId, JSON.stringify({ rejectReason: clean(body.reason) })],
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
          reason: clean(body.reason),
        });
        await this.modelsService.recordFeedback(client, userId, deviceId, 'activity_merge.v1', {
          targetType: 'activity_segment',
          targetId: segmentId,
          feedbackType: 'rejected',
          outcome: 'rejected',
          source: 'activity.rejectSegment',
          feedbackPayload: {
            reason: clean(body.reason),
          },
        });
      });
      return { ok: true };
    }

  async feedback(
    segmentId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.database.transaction(async (client) => {
      await this.modelsService.recordFeedback(client, userId, deviceId, 'activity_merge.v1', {
        targetType: 'activity_segment',
        targetId: segmentId,
        feedbackType: clean(body.feedbackType) ?? 'modified',
        outcome: clean(body.outcome) ?? clean(body.feedbackType) ?? 'modified',
        source: 'activity.segment.feedback',
        feedbackPayload: asRecord(body.feedbackPayload ?? body.payload),
      });
      await this.recordAudit(client, userId, deviceId, 'activity.segment.feedback', {
        segmentId,
        feedbackType: clean(body.feedbackType) ?? 'modified',
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
        TrackingTypes,
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
      [userId, TaskTypes],
    );
    return result.rows.map((row) => {
      const payload = asRecord(row.payload);
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
    const filePathChangeGap = Number(profile.filePathChangeGap ?? 5);

    const close = () => {
      if (current.length === 0) return;
      const first = current[0];
      const last = current[current.length - 1];
      const appCounts = new Map<string, number>();
      const pathCounts = new Map<string, number>();
      for (const item of current) {
        appCounts.set(item.appName, (appCounts.get(item.appName) ?? 0) + 1);
        if (item.filePath) {
          pathCounts.set(item.filePath, (pathCounts.get(item.filePath) ?? 0) + 1);
        }
      }
      const appName = [...appCounts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] ?? 'unknown';
      const main = current.find((item) => item.appName === appName) ?? first;
      const bestPath = [...pathCounts.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];

      let confidence = 0.45 + current.length * 0.08;
      if (appName !== 'unknown') confidence += appConfidenceBonus;
      if (bestPath) confidence += 0.06;
      // Boost if window title stayed consistent
      const uniqueWindows = new Set(current.map((item) => item.windowTitle).filter(Boolean));
      if (uniqueWindows.size <= 2) confidence += 0.05;
      confidence = Math.min(0.95, confidence);

      segments.push({
        uid: `seg:${first.startAt.toISOString().slice(0, 10)}:${first.id}:${last.id}`,
        startAt: first.startAt,
        endAt: new Date(Math.max(...current.map((item) => item.endAt.getTime()))),
        appName,
        windowTitle: main.windowTitle,
        filePath: bestPath ?? main.filePath,
        title: this.inferTitle(appName, main.windowTitle, bestPath),
        confidence,
        category: this.inferCategory(appName, main.windowTitle, bestPath),
        sourceIds: current.map((item) => item.id),
        evidence: {
          apps: [...appCounts.keys()],
          windows: current.slice(0, 8).map((item) => item.windowTitle).filter(Boolean),
          filePaths: current.map((item) => item.filePath).filter(Boolean).slice(0, 8),
          primaryFilePath: bestPath,
          uniqueWindowCount: uniqueWindows.size,
          mergeRule: 'time_app_file_window_rule',
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
      const sameFile = item.filePath && previous.filePath &&
        item.filePath === previous.filePath;
      const sameDir = item.filePath && previous.filePath &&
        this.sameDirectory(item.filePath, previous.filePath);
      const shortInterruption =
        gapMinutes <= shortInterruptionMinutes && this.isInterruptible(item.appName);
      // Merge if: same app within gap, OR same file/dir within tighter gap
      const shouldMerge =
        (gapMinutes <= mergeGapMinutes && (sameApp || shortInterruption)) ||
        (gapMinutes <= filePathChangeGap && (sameFile || (sameDir && sameApp)));
      if (shouldMerge) {
        current.push(item);
      } else {
        close();
        current.push(item);
      }
    }
    close();
    return segments.filter((item) => this.durationSeconds(item.startAt, item.endAt) >= 60);
  }

  private sameDirectory(a: string, b: string): boolean {
    const dirA = a.replace(/\\/g, '/').replace(/\/[^/]*$/, '');
    const dirB = b.replace(/\\/g, '/').replace(/\/[^/]*$/, '');
    return dirA === dirB;
  }

  private matchTask(
    segment: BuiltSegment,
    tasks: Array<{ id: string; title: string; text: string }>,
    profile: Record<string, unknown>,
  ) {
    const haystack = `${segment.title} ${segment.windowTitle} ${segment.filePath ?? ''}`;
    const filePathLower = segment.filePath?.toLowerCase();
    const threshold = Number(profile.taskMatchThreshold ?? 25);

    // ---- TF-IDF matching (primary) ----
    const tfidf = new TfidfMatcher();
    for (const task of tasks) {
      let desc = '';
      try {
        const p = JSON.parse(task.text);
        desc = String(p.description ?? p.notes ?? '');
      } catch { /* not JSON */ }
      // Weight title more heavily by repeating it
      tfidf.addDocument(task.id, `${task.title} ${task.title} ${desc}`);
    }

    const tfidfBest = tfidf.bestMatch(haystack);
    const tfidfScore = tfidfBest ? Math.round(tfidfBest.score * 100) : 0;

    // ---- Keyword matching (fallback + boost) ----
    let best: { id: string; title: string; score: number } | undefined;
    for (const task of tasks) {
      const taskTitle = task.title.toLowerCase();
      const words = taskTitle
        .split(/[\s_/\\\-:，。,.]+/)
        .filter((word) => word.length >= 2);

      const titleHits = words.filter((word) => haystack.toLowerCase().includes(word)).length;
      const exactMatch = haystack.toLowerCase().includes(taskTitle) ? 40 : 0;
      const pathHit = filePathLower && task.text.includes(filePathLower) ? 35 : 0;

      let dirMatch = 0;
      if (filePathLower) {
        const parts = filePathLower.replace(/\\/g, '/').split('/');
        for (const part of parts) {
          if (part.length >= 3 && task.text.includes(part)) { dirMatch = 15; break; }
        }
      }

      // Boost keyword score with TF-IDF signal
      const tfidfBoost = tfidfBest?.id === task.id ? tfidfScore : 0;

      const score = titleHits * 25 + pathHit + exactMatch + dirMatch + tfidfBoost * 0.5;
      if (score > (best?.score ?? 0)) {
        best = { id: task.id, title: task.title, score };
      }
    }

    if (best && best.score >= threshold) {
      segment.matchedTaskId = best.id;
      segment.matchedTaskTitle = best.title;
      segment.confidence = Math.min(0.98, segment.confidence + best.score / 100);
      segment.title = `可能在推进：${best.title}`;
      segment.evidence = {
        ...segment.evidence,
        matchedTask: { id: best.id, title: best.title, score: best.score, tfidfScore },
      };
    }
    return segment;
  }

  private toRawActivity(row: QueryResultRow): RawActivity | null {
    const payload = asRecord(row.payload);
    const startAt =
      readDate(this.readString(payload, ['startTime', 'start_at', 'startedAt', 'timestamp', 'occurredAt'])) ??
      readDate(row.updatedAt) ??
      null;
    if (!startAt) return null;
    const endAt =
      readDate(this.readString(payload, ['endTime', 'end_at', 'endedAt'])) ??
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

  private inferTitle(appName: string, windowTitle: string, filePath?: string) {
    if (filePath) {
      const fileName = filePath.replace(/\\/g, '/').split('/').pop() ?? '';
      if (fileName && windowTitle) return `${appName}: ${fileName} - ${windowTitle}`.slice(0, 160);
      if (fileName) return `${appName}: ${fileName}`.slice(0, 160);
    }
    if (windowTitle) return `${appName}: ${windowTitle}`.slice(0, 160);
    return appName === 'unknown' ? '未识别活动片段' : `${appName} 活动`;
  }

  private inferCategory(appName: string, windowTitle: string, filePath?: string) {
    const text = `${appName} ${windowTitle} ${filePath ?? ''}`.toLowerCase();
    // Coding / IDE
    if (/(code|studio|idea|pycharm|terminal|powershell|cmd|git|wsl|bash)/.test(text)) return 'coding';
    if (/\.(ts|js|py|rs|go|java|cpp|c|h|vue|svelte|dart)/.test(filePath ?? '')) return 'coding';
    if (/^\/(home|Users|mnt).*\/(src|projects|dev|repo)/i.test(filePath ?? '')) return 'coding';
    // Writing / Documents
    if (/(word|excel|powerpoint|pdf|markdown|obsidian|notion|wps|typora)/.test(text)) return 'writing';
    if (/\.(md|txt|docx?|pptx?|xlsx?|pdf)/.test(filePath ?? '')) return 'writing';
    // Meeting / communication
    if (/(teams|zoom|meeting|腾讯会议|webex|slack|discord)/.test(text)) return 'meeting';
    if (/(wechat|微信|qq|telegram|mail|outlook|thunderbird)/.test(text)) return 'communication';
    // Design
    if (/(figma|sketch|photoshop|illustrator|blender|premiere|after.effects)/.test(text)) return 'design';
    if (/\.(psd|ai|fig|sketch|svg|blend)/.test(filePath ?? '')) return 'design';
    // Entertainment
    if (/(bilibili|youtube|video|music|game|steam|抖音|快手)/.test(text)) return 'entertainment';
    // Browsing
    if (/(chrome|firefox|edge|safari|browser)/.test(text) && !/(code|studio|dev)/.test(text)) return 'browsing';
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
    const explicitStart = readDate(rawStart);
    const explicitEnd = readDate(rawEnd);
    if (explicitStart && explicitEnd && explicitStart < explicitEnd) {
      return { start: explicitStart, end: explicitEnd };
    }
    const dateText = typeof date === 'string' && date.trim() ? date.trim() : new Date().toISOString().slice(0, 10);
    const start = new Date(`${dateText}T00:00:00.000Z`);
    const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
    return { start, end };
  }

  async splitSegment(
    segmentId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const splitAt = readDate(body.splitAt);
    if (!splitAt) throw new BadRequestException('splitAt must be a valid ISO-8601 date string');

    return this.database.transaction(async (client) => {
      const seg = await client.query<QueryResultRow>(
        `SELECT * FROM activity_segments WHERE user_id = $1 AND id = $2 LIMIT 1`,
        [userId, segmentId],
      );
      if (!seg.rows[0]) throw new BadRequestException('segment not found');

      const startAt = new Date(String(seg.rows[0].start_at));
      const endAt = new Date(String(seg.rows[0].end_at));
      if (splitAt <= startAt || splitAt >= endAt) {
        throw new BadRequestException('splitAt must be between segment startAt and endAt');
      }

      // Mark original as split
      await client.query(
        `UPDATE activity_segments SET status = 'split', updated_at = now() WHERE user_id = $1 AND id = $2`,
        [userId, segmentId],
      );

      // Create first half
      const first = await client.query<QueryResultRow>(
        `INSERT INTO activity_segments (
           user_id, segment_uid, start_at, end_at, duration_seconds,
           primary_process_name, primary_app, primary_window_title, primary_file_path,
           category, label, source_record_ids, evidence, confidence, status
         ) VALUES ($1,$2,$3,$4,$5,$6,$6,$7,$8,$9,$10,$11::jsonb,$12::jsonb,$13,'candidate')
         RETURNING id::text AS id`,
        [
          userId,
          `split-a:${seg.rows[0].segment_uid}`,
          startAt, splitAt,
          Math.round((splitAt.getTime() - startAt.getTime()) / 1000),
          seg.rows[0].primary_process_name,
          seg.rows[0].primary_window_title,
          seg.rows[0].primary_file_path,
          seg.rows[0].category,
          seg.rows[0].label,
          seg.rows[0].source_record_ids,
          seg.rows[0].evidence,
          seg.rows[0].confidence,
        ],
      );

      // Create second half
      const second = await client.query<QueryResultRow>(
        `INSERT INTO activity_segments (
           user_id, segment_uid, start_at, end_at, duration_seconds,
           primary_process_name, primary_app, primary_window_title, primary_file_path,
           category, label, source_record_ids, evidence, confidence, status
         ) VALUES ($1,$2,$3,$4,$5,$6,$6,$7,$8,$9,$10,$11::jsonb,$12::jsonb,$13,'candidate')
         RETURNING id::text AS id`,
        [
          userId,
          `split-b:${seg.rows[0].segment_uid}`,
          splitAt, endAt,
          Math.round((endAt.getTime() - splitAt.getTime()) / 1000),
          seg.rows[0].primary_process_name,
          seg.rows[0].primary_window_title,
          seg.rows[0].primary_file_path,
          seg.rows[0].category,
          seg.rows[0].label,
          seg.rows[0].source_record_ids,
          seg.rows[0].evidence,
          seg.rows[0].confidence,
        ],
      );

      await this.recordAudit(client, userId, deviceId, 'activity.split_segment', {
        originalSegmentId: segmentId,
        splitAt: splitAt.toISOString(),
        firstHalfId: first.rows[0]?.id,
        secondHalfId: second.rows[0]?.id,
      });

      return { ok: true, firstHalfId: first.rows[0]?.id, secondHalfId: second.rows[0]?.id };
    });
  }

  async mergeSegments(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const segmentIds = asArray(body.segmentIds).map(String);
    if (segmentIds.length < 2) throw new BadRequestException('segmentIds must have at least 2 segment IDs');

    return this.database.transaction(async (client) => {
      const segs = await client.query<QueryResultRow>(
        `SELECT * FROM activity_segments
         WHERE user_id = $1 AND id = ANY($2::uuid[])
         ORDER BY start_at ASC`,
        [userId, segmentIds],
      );
      if (segs.rows.length < 2) throw new BadRequestException('at least 2 valid segments required');

      const earliest = new Date(Math.min(...segs.rows.map((r: QueryResultRow) => new Date(String(r.start_at)).getTime())));
      const latest = new Date(Math.max(...segs.rows.map((r: QueryResultRow) => new Date(String(r.end_at)).getTime())));

      const mergedUid = `merged:${segs.rows.map((r: QueryResultRow) => (r as Record<string,unknown>).segment_uid).join(':')}`;
      const apps = [...new Set(segs.rows.map((r: QueryResultRow) => (r as Record<string,unknown>).primary_process_name))];

      const merged = await client.query<QueryResultRow>(
        `INSERT INTO activity_segments (
           user_id, segment_uid, start_at, end_at, duration_seconds,
           primary_process_name, primary_app, category, label,
           source_record_ids, evidence, confidence, status
         ) VALUES ($1,$2,$3,$4,$5,$6,$6,$7,$8,$9::jsonb,$10::jsonb,$11,'candidate')
         RETURNING id::text AS id`,
        [
          userId, mergedUid, earliest, latest,
          Math.round((latest.getTime() - earliest.getTime()) / 1000),
          (apps[0] ?? 'unknown'),
          'merged',
          `合并片段 (${segs.rows.length} 段)`,
          JSON.stringify(segmentIds),
          JSON.stringify({ mergedFrom: segmentIds, mergeRule: 'manual' }),
          Math.min(...segs.rows.map((r: QueryResultRow) => Number(r.confidence ?? 0.5))),
        ],
      );

      for (const row of segs.rows) {
        await client.query(
          `UPDATE activity_segments SET status = 'merged', updated_at = now()
           WHERE user_id = $1 AND id = $2`,
          [userId, (row as Record<string,unknown>).id],
        );
      }

      await this.recordAudit(client, userId, deviceId, 'activity.merge_segments', {
        segmentIds, mergedId: merged.rows[0]?.id,
      });

      return { ok: true, mergedId: merged.rows[0]?.id };
    });
  }

  private durationSeconds(start: Date, end: Date) {
    return Math.max(0, Math.round((end.getTime() - start.getTime()) / 1000));
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
