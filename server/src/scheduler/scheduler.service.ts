import { BadRequestException, Injectable } from '@nestjs/common';
import { QueryResultRow } from 'pg';
import { FlowPlanV2RequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import { ModelsService } from '../models/models.service';
import { clean, asRecord, readDate } from '../common/utils';
import { ObjectType, TaskTypes, EventTypes } from '../common/constants/object-types';

interface TaskCandidate {
  id: string;
  objectId: string;
  title: string;
  estimatedMinutes: number;
  confirmedMinutes: number;
  remainingMinutes: number;
  dueAt?: Date;
  priority: string;
  location?: string | null;
  notes?: string | null;
  locked: boolean;
  allowAutoSchedule: boolean;
  earliestStart?: Date;
  latestEnd?: Date;
  canSplit: boolean;
  minChunkMinutes: number;
  maxChunkMinutes: number;
  payload: Record<string, unknown>;
  status: string;
}

interface BusyBlock {
  start: Date;
  end: Date;
  title: string;
  source: string;
}

interface FreeBlock {
  start: Date;
  end: Date;
  source?: string;
}

@Injectable()
export class SchedulerService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
    private readonly modelsService: ModelsService,
  ) {}

  async createRun(body: Record<string, unknown>, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const { start, end } = this.readRange(
      body.rangeStart ?? body.startAt,
      body.rangeEnd ?? body.endAt,
    );
    const mode = clean(body.mode) ?? 'initial_plan';
    const strategy = clean(body.strategy) ?? 'balanced';
    const activeModel = await this.modelsService.activeProfile(userId, 'scheduler.v1');
    const profile = asRecord(asRecord(activeModel).ruleProfile);
    const schedulerSettings = await this.readSchedulerSettings(userId);
    const tasks = await this.readTasks(userId);
    const busyBlocks = await this.readBusyBlocks(userId, start, end);
    const workBlocks = this.computeWorkBlocks(start, end, schedulerSettings, profile);
    const freeBlocks = this.applyWorkBlocks(
      this.computeFreeBlocks(start, end, busyBlocks),
      workBlocks,
    );
    const modelRun = await this.modelsService.startRun(userId, 'scheduler.v1', {
      source: 'scheduler.createRun',
      inputSummary: {
        rangeStart: start.toISOString(),
        rangeEnd: end.toISOString(),
        strategy,
        taskCount: tasks.length,
        busyBlockCount: busyBlocks.length,
        workBlockCount: workBlocks.length,
        schedulerSettings,
        profile,
      },
    });
    const ruleResult = this.plan(tasks, freeBlocks, strategy, profile);
    let planned = this.normalizePlannedReasons(ruleResult.planned, strategy);
    let unplanned = this.normalizeUnplannedReasons(ruleResult.unplanned, freeBlocks);
    let llmFallback: Record<string, unknown> = { used: false };
    const shouldUseLlm = this.shouldUseLlmFallback(
      body,
      tasks,
      planned,
      unplanned,
      profile,
    );
    if (shouldUseLlm) {
      const fallback = await this.modelsService.scheduleFallback(userId, {
        rangeStart: start,
        rangeEnd: end,
        strategy,
        tasks: tasks.map((task) => ({
          id: task.id,
          title: task.title,
          remainingMinutes: task.remainingMinutes,
          dueAt: task.dueAt?.toISOString(),
          priority: task.priority,
          location: task.payload.location ?? task.payload.place,
          notes: task.payload.notes ?? task.payload.description,
          locked: task.payload.locked,
          allowAutoSchedule: task.payload.allowAutoSchedule,
          earliestStart: task.earliestStart?.toISOString(),
          latestEnd: task.latestEnd?.toISOString(),
          canSplit: task.canSplit,
          minChunkMinutes: task.minChunkMinutes,
          maxChunkMinutes: task.maxChunkMinutes,
        })),
        busyBlocks,
        freeBlocks,
        unplanned,
        profile,
      });
      const validated = this.validateLlmDrafts(fallback, tasks, start, end, busyBlocks, planned);
      planned = [...planned, ...validated.planned];
      unplanned = validated.unplanned.length > 0 ? validated.unplanned : unplanned;
      llmFallback = {
        ...fallback,
        draftItems: undefined,
        raw: undefined,
        validatedCount: validated.planned.length,
        rejectedCount: validated.rejected.length,
        rejected: validated.rejected,
      };
    }
    const averageConfidence =
      planned.length === 0
        ? 0
        : planned.reduce((sum, item) => sum + Number(item.confidence), 0) / planned.length;

    const run = await this.database.transaction(async (client) => {
      const runResult = await client.query<QueryResultRow>(
        `
        INSERT INTO schedule_runs (
          user_id,
          device_id,
          range_start,
          range_end,
          mode,
          strategy,
          status,
          input_snapshot_json,
          output_summary_json,
          risk_summary_json
        ) VALUES ($1, $2, $3, $4, $5, $6, 'draft', $7::jsonb, $8::jsonb, $9::jsonb)
        RETURNING id::text AS id
        `,
        [
          userId,
          deviceId,
          start,
          end,
          mode,
          strategy,
          JSON.stringify({
            taskCount: tasks.length,
            busyBlocks,
            actualWorkApplied: tasks.map((task) => ({
              taskId: task.id,
              estimatedMinutes: task.estimatedMinutes,
              confirmedMinutes: task.confirmedMinutes,
              remainingMinutes: task.remainingMinutes,
              locked: task.locked,
              allowAutoSchedule: task.allowAutoSchedule,
            })),
            workBlocks,
          }),
          JSON.stringify({ plannedCount: planned.length, unplanned }),
          JSON.stringify({
            hasUnplanned: unplanned.length > 0,
            generatedBy: shouldUseLlm ? 'rule_greedy_with_llm_fallback' : 'rule_greedy_mvp',
            modelRunId: modelRun.id,
            modelUsed: shouldUseLlm ? 'hybrid' : 'rule_learned',
            modelVersion: modelRun.version.versionKey,
            llmFallback,
          }),
        ],
      );
      const runId = String(runResult.rows[0]?.id);
      for (const item of planned) {
        await client.query(
          `
          INSERT INTO schedule_draft_items (
            user_id,
            schedule_run_id,
            task_id,
            task_title,
            proposed_start,
            proposed_end,
            action,
            confidence,
            reason_json,
            risk_json,
            status
          ) VALUES ($1, $2, $3, $4, $5, $6, 'create', $7, $8::jsonb, $9::jsonb, 'pending')
          `,
          [
            userId,
            runId,
            item.task.id,
            item.task.title,
            item.start,
            item.end,
            item.confidence,
            JSON.stringify(item.reason),
            JSON.stringify(item.risk),
          ],
        );
      }
      await this.recordAudit(client, userId, deviceId, 'scheduler.run.created', {
        runId,
        modelRunId: modelRun.id,
        modelUsed: shouldUseLlm ? 'hybrid' : 'rule_learned',
        modelVersion: modelRun.version.versionKey,
        rangeStart: start.toISOString(),
        rangeEnd: end.toISOString(),
        plannedCount: planned.length,
        unplannedCount: unplanned.length,
      });
      return runId;
    });

    await this.modelsService.completeRun(userId, modelRun.id, {
      status: unplanned.length > 0 ? 'partial' : 'succeeded',
      outputSummary: {
        scheduleRunId: run,
        plannedCount: planned.length,
        unplannedCount: unplanned.length,
        llmFallback,
      },
      confidence: averageConfidence,
      usedLlm: Boolean(llmFallback.used),
      llmProviderKey: clean(llmFallback.providerKey),
      llmModel: clean(llmFallback.model),
    });

    return this.run(run, context);
  }

  async run(runId: string, context: FlowPlanV2RequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const run = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        range_start AS "rangeStart",
        range_end AS "rangeEnd",
        mode,
        strategy,
        status,
        input_snapshot_json AS "inputSnapshot",
        output_summary_json AS "outputSummary",
        risk_summary_json AS "riskSummary",
        created_at AS "createdAt",
        updated_at AS "updatedAt",
        confirmed_at AS "confirmedAt",
        rejected_at AS "rejectedAt"
      FROM schedule_runs
      WHERE user_id = $1 AND id = $2
      LIMIT 1
      `,
      [userId, runId],
    );
    const row = run.rows[0];
    if (!row) throw new BadRequestException('schedule run not found');
    const items = await this.database.query<QueryResultRow>(
      `
      SELECT
        id::text AS id,
        task_id AS "taskId",
        task_title AS "taskTitle",
        proposed_start AS "proposedStart",
        proposed_end AS "proposedEnd",
        action,
        confidence,
        reason_json AS reason,
        risk_json AS risk,
        status,
        user_reject_reason AS "rejectReason"
      FROM schedule_draft_items
      WHERE user_id = $1 AND schedule_run_id = $2
      ORDER BY proposed_start ASC NULLS LAST, created_at ASC
      `,
      [userId, runId],
    );
    return {
      run: row,
      items: items.rows,
      unplanned: row.outputSummary?.unplanned ?? [],
      modelRunId: row.riskSummary?.modelRunId ?? null,
      modelUsed: row.riskSummary?.modelUsed ?? 'rule',
      modelVersion: row.riskSummary?.modelVersion ?? null,
      llmFallbackUsed: Boolean(row.riskSummary?.llmFallback?.used),
    };
  }

  async acceptRun(
    runId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const acceptedIds = this.stringArray(body.acceptedItemIds);
    const rejectedIds = this.stringArray(body.rejectedItemIds);
    const modifiedItems = Array.isArray(body.modifiedItems) ? body.modifiedItems : [];
    const result = await this.database.transaction(async (client) => {
      const run = await client.query<QueryResultRow>(
        `
        SELECT * FROM schedule_runs
        WHERE user_id = $1 AND id = $2 AND status = 'draft'
        LIMIT 1
        `,
        [userId, runId],
      );
      if (!run.rows[0]) throw new BadRequestException('draft schedule run not found');
      const riskSummary = asRecord(run.rows[0].risk_summary_json);
      const modelRunId = clean(riskSummary.modelRunId);
      const items = await client.query<QueryResultRow>(
        `
        SELECT * FROM schedule_draft_items
        WHERE user_id = $1 AND schedule_run_id = $2 AND status = 'pending'
        ORDER BY proposed_start ASC
        `,
        [userId, runId],
      );
      const modifiedById = new Map(
        modifiedItems
          .filter((item): item is Record<string, unknown> => !!item && typeof item === 'object')
          .map((item) => [String(item.itemId), item]),
      );
      const selected = items.rows.filter((item) => {
        const itemId = String(item.id);
        if (rejectedIds.includes(itemId)) return false;
        return acceptedIds.length === 0 || acceptedIds.includes(itemId) || modifiedById.has(itemId);
      });
      const created: string[] = [];
      for (const item of selected) {
        const override = modifiedById.get(String(item.id));
        const start = readDate(override?.start) ?? readDate(item.proposed_start);
        const end = readDate(override?.end) ?? readDate(item.proposed_end);
        if (!start || !end || start >= end) continue;
        const payload = {
          uid: `schedule:${runId}:${item.id}`,
          taskId: String(item.task_id),
          taskTitle: String(item.task_title ?? ''),
          startAt: start.toISOString(),
          endAt: end.toISOString(),
          durationMinutes: Math.max(1, Math.round((end.getTime() - start.getTime()) / 60000)),
          status: 'confirmed',
          source: 'server_scheduler',
          scheduleRunId: runId,
          explanation: item.reason_json ?? {},
        };
        const object = await client.query<QueryResultRow>(
          `
          INSERT INTO sync_objects (
            user_id,
            object_type,
            uid,
            payload,
            origin_device_id,
            last_modified_device_id
          ) VALUES ($1, 'task_schedule_segment', $2, $3::jsonb, $4, $4)
          ON CONFLICT (user_id, object_type, uid) WHERE deleted_at IS NULL DO UPDATE SET
            payload = EXCLUDED.payload,
            server_version = sync_objects.server_version + 1,
            last_modified_device_id = EXCLUDED.last_modified_device_id,
            updated_at = now()
          RETURNING id::text AS id, server_version
          `,
          [userId, payload.uid, JSON.stringify(payload), deviceId],
        );
        const objectId = String(object.rows[0]?.id);
        created.push(objectId);
        await this.recordChange(
          client,
          userId,
          deviceId,
          objectId,
          'task_schedule_segment',
          Number(object.rows[0]?.server_version ?? 1),
          payload,
        );
        await client.query(
          `
          UPDATE schedule_draft_items
          SET
            status = CASE WHEN $4::boolean THEN 'modified' ELSE 'accepted' END,
            user_modified_start = CASE WHEN $4::boolean THEN $5 ELSE user_modified_start END,
            user_modified_end = CASE WHEN $4::boolean THEN $6 ELSE user_modified_end END,
            updated_at = now()
          WHERE user_id = $1 AND schedule_run_id = $2 AND id = $3
          `,
          [userId, runId, item.id, Boolean(override), start, end],
        );
      }
      if (rejectedIds.length > 0) {
        await client.query(
          `
          UPDATE schedule_draft_items
          SET status = 'rejected', user_reject_reason = $4, updated_at = now()
          WHERE user_id = $1 AND schedule_run_id = $2 AND id = ANY($3::uuid[])
          `,
          [userId, runId, rejectedIds, clean(body.note)],
        );
      }
      await client.query(
        `
        UPDATE schedule_runs
        SET status = $3, confirmed_at = now(), updated_at = now()
        WHERE user_id = $1 AND id = $2
        `,
        [userId, runId, selected.length === items.rows.length ? 'accepted' : 'partially_accepted'],
      );
      await this.recordAudit(client, userId, deviceId, 'scheduler.run.accepted', {
        runId,
        createdObjectIds: created,
        rejectedIds,
        note: clean(body.note),
        modelRunId,
      });
      await this.modelsService.recordFeedback(client, userId, deviceId, 'scheduler.v1', {
        modelRunId,
        targetType: 'schedule_run',
        targetId: runId,
        feedbackType: modifiedItems.length > 0 ? 'modified' : 'accepted',
        outcome: 'accepted',
        source: 'scheduler.acceptRun',
        feedbackPayload: {
          createdObjectIds: created,
          acceptedIds,
          rejectedIds,
          modifiedItems,
          note: clean(body.note),
        },
      });
      return { createdObjectIds: created };
    });
    return { ok: true, ...result };
  }

  async rejectRun(
    runId: string,
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    await this.database.transaction(async (client) => {
      await client.query(
        `
        UPDATE schedule_runs
        SET status = 'rejected', rejected_at = now(), updated_at = now()
        WHERE user_id = $1 AND id = $2 AND status = 'draft'
        `,
        [userId, runId],
      );
      await client.query(
        `
        UPDATE schedule_draft_items
        SET status = 'rejected', user_reject_reason = $3, updated_at = now()
        WHERE user_id = $1 AND schedule_run_id = $2 AND status = 'pending'
        `,
        [userId, runId, clean(body.reason)],
      );
      await this.recordAudit(client, userId, deviceId, 'scheduler.run.rejected', {
        runId,
        reason: clean(body.reason),
      });
      await this.modelsService.recordFeedback(client, userId, deviceId, 'scheduler.v1', {
        targetType: 'schedule_run',
        targetId: runId,
        feedbackType: 'rejected',
        outcome: 'rejected',
        source: 'scheduler.rejectRun',
        feedbackPayload: {
          reason: clean(body.reason),
        },
      });
    });
    return { ok: true, message: 'draft rejected; no schedule segments were written' };
  }

  async detectDeviations(
    body: Record<string, unknown>,
    context: FlowPlanV2RequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const { start, end } = this.readRange(
      body.rangeStart ?? body.startAt,
      body.rangeEnd ?? body.endAt,
    );
    const segments = await this.database.query<QueryResultRow>(
      `
      SELECT id::text AS id, payload
      FROM sync_objects
      WHERE user_id = $1
        AND deleted_at IS NULL
        AND object_type = 'task_schedule_segment'
        AND updated_at >= $2 - interval '1 day'
        AND updated_at < $3 + interval '1 day'
      `,
      [userId, start, end],
    );
    const actuals = await this.database.query<QueryResultRow>(
      `
      SELECT id::text AS id, title, start_at, end_at
      FROM actual_activity_logs
      WHERE user_id = $1 AND status = 'confirmed' AND start_at >= $2 AND start_at < $3
      `,
      [userId, start, end],
    );
    let created = 0;
    await this.database.transaction(async (client) => {
      const plannedBlocks: Array<{
        id: string;
        taskId: string | null;
        title: string;
        start: Date;
        end: Date;
        payload: Record<string, unknown>;
      }> = [];
      for (const planned of segments.rows) {
        const payload = asRecord(planned.payload);
        const plannedStart = readDate(payload.startAt);
        const plannedEnd = readDate(payload.endAt);
        if (!plannedStart || !plannedEnd) continue;
        plannedBlocks.push({
          id: String(planned.id),
          taskId: clean(payload.taskId),
          title: String(payload.taskTitle ?? ''),
          start: plannedStart,
          end: plannedEnd,
          payload,
        });
        const overlap = actuals.rows.find((actual) => {
          const actualStart = readDate(actual.start_at);
          const actualEnd = readDate(actual.end_at);
          return actualStart && actualEnd && actualStart < plannedEnd && actualEnd > plannedStart;
        });
        if (!overlap) {
          const deviation = await client.query<QueryResultRow>(
            `
            INSERT INTO plan_deviations (
              user_id, schedule_segment_id, planned_task_id, planned_start, planned_end,
              deviation_type, severity, confidence, status, evidence
            )
            SELECT $1, $2, $3, $4, $5, 'missed', 'medium', 0.65, 'detected', $6::jsonb
            WHERE NOT EXISTS (
              SELECT 1
              FROM plan_deviations
              WHERE user_id = $1
                AND schedule_segment_id = $2
                AND deviation_type = 'missed'
                AND status = 'detected'
            )
            RETURNING id::text AS id
            `,
            [
              userId,
              String(planned.id),
              clean(payload.taskId),
              plannedStart,
              plannedEnd,
              JSON.stringify({ reason: 'no confirmed actual log overlapped this schedule segment' }),
            ],
          );
          created += deviation.rows.length;
        } else if (!String(overlap.title ?? '').includes(String(payload.taskTitle ?? ''))) {
          const deviation = await client.query<QueryResultRow>(
            `
            INSERT INTO plan_deviations (
              user_id, schedule_segment_id, planned_task_id, planned_start, planned_end,
              actual_log_id, actual_title, actual_start, actual_end,
              deviation_type, severity, confidence, status, evidence
            )
            SELECT $1, $2, $3, $4, $5, $6, $7, $8, $9, 'different_activity', 'medium', 0.7, 'detected', $10::jsonb
            WHERE NOT EXISTS (
              SELECT 1
              FROM plan_deviations
              WHERE user_id = $1
                AND schedule_segment_id = $2
                AND actual_log_id = $6
                AND deviation_type = 'different_activity'
                AND status = 'detected'
            )
            RETURNING id::text AS id
            `,
            [
              userId,
              String(planned.id),
              clean(payload.taskId),
              plannedStart,
              plannedEnd,
              overlap.id,
              overlap.title,
              overlap.start_at,
              overlap.end_at,
              JSON.stringify({ planned: payload, actual: overlap }),
            ],
          );
          created += deviation.rows.length;
        }
      }
      for (const actual of actuals.rows) {
        const actualStart = readDate(actual.start_at);
        const actualEnd = readDate(actual.end_at);
        if (!actualStart || !actualEnd) continue;
        const plannedOverlap = plannedBlocks.find((planned) => {
          return actualStart < planned.end && actualEnd > planned.start;
        });
        if (plannedOverlap) continue;
        const deviation = await client.query<QueryResultRow>(
          `
          INSERT INTO plan_deviations (
            user_id, actual_log_id, actual_title, actual_start, actual_end,
            deviation_type, severity, confidence, status, evidence
          )
          SELECT $1, $2, $3, $4, $5, 'actual_unplanned', 'low', 0.72, 'detected', $6::jsonb
          WHERE NOT EXISTS (
            SELECT 1
            FROM plan_deviations
            WHERE user_id = $1
              AND actual_log_id = $2
              AND deviation_type = 'actual_unplanned'
              AND status = 'detected'
          )
          RETURNING id::text AS id
          `,
          [
            userId,
            actual.id,
            actual.title,
            actualStart,
            actualEnd,
            JSON.stringify({
              reason: 'confirmed actual log did not overlap any accepted schedule segment',
            }),
          ],
        );
        if (deviation.rows.length > 0) {
          created += deviation.rows.length;
        }
      }
      await this.recordAudit(client, userId, deviceId, 'scheduler.deviations.detected', {
        created,
        rangeStart: start.toISOString(),
        rangeEnd: end.toISOString(),
      });
    });
    return { ok: true, created };
  }

  private plan(
    tasks: TaskCandidate[],
    freeBlocks: FreeBlock[],
    strategy: string,
    profile: Record<string, unknown>,
  ) {
    const planned: Array<{
      task: TaskCandidate;
      start: Date;
      end: Date;
      confidence: number;
      reason: Record<string, unknown>;
      risk: Record<string, unknown>;
    }> = [];
    const unplanned: Array<Record<string, unknown>> = [];
    const remainingBlocks = freeBlocks.map((block) => ({ ...block }));
    const candidates = tasks.filter((task) => task.remainingMinutes > 0);
    for (const task of candidates) {
      const blockedReason = this.taskBlockedReason(task);
      if (blockedReason) {
        unplanned.push({
          taskId: task.id,
          title: task.title,
          remainingMinutes: task.remainingMinutes,
          reason: blockedReason,
          locked: task.locked,
          allowAutoSchedule: task.allowAutoSchedule,
        });
      }
    }
    const sorted = candidates
      .filter((task) => !this.taskBlockedReason(task))
      .sort((a, b) => this.taskScore(b, strategy, profile) - this.taskScore(a, strategy, profile));

    for (const task of sorted) {
      let minutesLeft = task.remainingMinutes;
      let didPlan = false;
      for (const block of remainingBlocks) {
        const taskStart = task.earliestStart && task.earliestStart > block.start ? task.earliestStart : block.start;
        const taskLimitEnd = task.latestEnd && task.latestEnd < block.end ? task.latestEnd : block.end;
        const blockMinutes = Math.floor((taskLimitEnd.getTime() - taskStart.getTime()) / 60000);
        if (blockMinutes < task.minChunkMinutes || minutesLeft <= 0) continue;
        if (!task.canSplit && blockMinutes < minutesLeft) continue;
        const minutes = Math.min(minutesLeft, blockMinutes, task.maxChunkMinutes);
        const start = new Date(taskStart);
        const end = new Date(start.getTime() + minutes * 60000);
        planned.push({
          task,
          start,
          end,
            confidence: Math.min(0.95, 0.78 + Number(asRecord(profile.learnedAdjustments).confidenceBonus ?? 0)),
            reason: {
            text: `预计剩余 ${task.remainingMinutes} 分钟，已确认投入 ${task.confirmedMinutes} 分钟；按 ${strategy} 策略优先安排。`,
            dueAt: task.dueAt?.toISOString(),
              priority: task.priority,
              confirmedMinutes: task.confirmedMinutes,
              remainingMinutes: task.remainingMinutes,
              location: task.location,
              notes: task.notes,
              canSplit: task.canSplit,
              minChunkMinutes: task.minChunkMinutes,
              maxChunkMinutes: task.maxChunkMinutes,
              earliestStart: task.earliestStart?.toISOString(),
              latestEnd: task.latestEnd?.toISOString(),
              freeBlockSource: block.source ?? 'range',
              modelUsed: 'rule_learned',
            },
          risk: {
            deadlineSoon: task.dueAt ? task.dueAt.getTime() - Date.now() < 36 * 60 * 60 * 1000 : false,
            constrainedByWindow: Boolean(task.earliestStart || task.latestEnd),
            locationAware: Boolean(task.location),
          },
        });
        block.start = end;
        minutesLeft -= minutes;
        didPlan = true;
      }
      if (!didPlan || minutesLeft > 0) {
        unplanned.push({
          taskId: task.id,
          title: task.title,
          remainingMinutes: minutesLeft,
          reason: freeBlocks.length === 0 ? '没有可用时间块' : '可用时间不足或被更高优先级任务占用',
        });
      }
    }
    return { planned, unplanned };
  }

  private async readTasks(userId: string): Promise<TaskCandidate[]> {
    const tasks = await this.database.query<QueryResultRow>(
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
    const work = await this.database.query<QueryResultRow>(
      `
      SELECT task_id, COALESCE(SUM(duration_minutes), 0)::int AS minutes
      FROM task_work_logs
      WHERE user_id = $1 AND status = 'confirmed'
      GROUP BY task_id
      `,
      [userId],
    );
    const workMap = new Map(work.rows.map((row) => [String(row.task_id), Number(row.minutes)]));
    return tasks.rows
      .map((row) => {
        const payload = asRecord(row.payload);
        const status = String(payload.status ?? '').toLowerCase();
        const taskId = String(row.uid ?? row.id);
        const estimatedMinutes = Math.max(15, Number(payload.estimatedMinutes ?? payload.estimated_minutes ?? payload.durationMinutes ?? 60));
        const confirmedMinutes = workMap.get(taskId) ?? workMap.get(String(row.id)) ?? 0;
        const minChunkMinutes = Math.max(
          5,
          Number(payload.minChunkMinutes ?? payload.min_chunk_minutes ?? 15),
        );
        const maxChunkMinutes = Math.max(
          minChunkMinutes,
          Number(payload.maxChunkMinutes ?? payload.max_chunk_minutes ?? 120),
        );
        return {
          id: taskId,
          objectId: String(row.id),
          title: this.readString(payload, ['title', 'name', 'summary']) ?? taskId,
          estimatedMinutes,
          confirmedMinutes,
          remainingMinutes: Math.max(0, estimatedMinutes - confirmedMinutes),
          dueAt:
            readDate(this.readString(payload, ['dueAt', 'due_at', 'deadline'])) ??
            undefined,
          priority: String(payload.priority ?? 'normal'),
          location: this.readString(payload, ['location', 'place', 'where']),
          notes: this.readString(payload, ['notes', 'note', 'description', 'remark']),
          locked: payload.locked === true || payload.isLocked === true,
          allowAutoSchedule:
            payload.allowAutoSchedule === false || payload.autoSchedule === false
              ? false
              : true,
          earliestStart:
            readDate(this.readString(payload, ['earliestStart', 'availableAfter', 'notBefore', 'startAfter'])) ??
            undefined,
          latestEnd:
            readDate(this.readString(payload, ['latestEnd', 'availableBefore', 'notAfter', 'endBefore'])) ??
            undefined,
          canSplit: payload.canSplit === false || payload.splittable === false ? false : true,
          minChunkMinutes,
          maxChunkMinutes,
          payload,
          status,
        };
      })
      .filter((task) => !['completed', 'done', 'cancelled', 'archived'].includes(String(task.status)));
  }

  private async readBusyBlocks(userId: string, start: Date, end: Date) {
    const events = await this.database.query<QueryResultRow>(
      `
      SELECT payload
      FROM sync_objects
      WHERE user_id = $1
        AND deleted_at IS NULL
        AND object_type = ANY($2::text[])
      ORDER BY updated_at DESC
      LIMIT 1000
      `,
      [userId, EventTypes],
    );
    const blocks: BusyBlock[] = [];
    for (const row of events.rows) {
      const payload = asRecord(row.payload);
      const eventStart = readDate(this.readString(payload, ['startAt', 'startTime', 'start_at']));
      const eventEnd = readDate(this.readString(payload, ['endAt', 'endTime', 'end_at']));
      const blocking = payload.isBlocking === true || payload.blocking === true || payload.kind === 'blocking';
      const recurring = this.isRecurringEvent(payload);
      if (blocking && recurring) {
        for (const occurrence of this.expandEventOccurrences(payload, eventStart, eventEnd, start, end)) {
          blocks.push({
            start: new Date(Math.max(occurrence.start.getTime(), start.getTime())),
            end: new Date(Math.min(occurrence.end.getTime(), end.getTime())),
            title: this.readString(payload, ['title', 'name', 'summary']) ?? 'Blocking schedule',
            source: 'calendar_event_recurring',
          });
        }
        continue;
      }
      if (eventStart && eventEnd && eventStart < end && eventEnd > start && blocking) {
        blocks.push({
          start: new Date(Math.max(eventStart.getTime(), start.getTime())),
          end: new Date(Math.min(eventEnd.getTime(), end.getTime())),
          title: this.readString(payload, ['title', 'name', 'summary']) ?? '阻挡日程',
          source: 'calendar_event',
        });
      }
    }
    return blocks.sort((a, b) => a.start.getTime() - b.start.getTime());
  }

  private async readSchedulerSettings(userId: string) {
    const result = await this.database.query<QueryResultRow>(
      `
      SELECT config_key AS key, config_value AS value
      FROM admin_remote_configs
      WHERE user_id = $1
        AND config_key = ANY($2::text[])
      ORDER BY updated_at DESC
      `,
      [
        userId,
        [
          'scheduler.policy',
          'work.time',
          'working_hours',
          'work_hours',
          'user.preference',
        ],
      ],
    );
    const merged: Record<string, unknown> = {};
    for (const row of result.rows) {
      const value = asRecord(row.value);
      Object.assign(merged, value);
      const workHours = asRecord(value.workHours ?? value.workingHours ?? value.working_hours);
      if (Object.keys(workHours).length > 0) merged.workHours = workHours;
    }
    return merged;
  }

  private computeWorkBlocks(
    start: Date,
    end: Date,
    settings: Record<string, unknown>,
    profile: Record<string, unknown>,
  ): FreeBlock[] {
    const rawWorkHours =
      settings.workHours ??
      settings.workingHours ??
      settings.working_hours ??
      profile.workHours ??
      profile.workingHours;
    const workHours = asRecord(rawWorkHours);
    if (Object.keys(workHours).length === 0 || workHours.enabled === false) return [{ start, end, source: 'range' }];

    const blocks: FreeBlock[] = [];
    const cursor = new Date(start);
    cursor.setHours(0, 0, 0, 0);
    while (cursor < end) {
      const weekday = cursor.getDay();
      const dayKey = String(weekday);
      const isoDayKey = String(weekday === 0 ? 7 : weekday);
      const windows =
        this.workWindowsForDay(workHours, dayKey) ??
        this.workWindowsForDay(workHours, isoDayKey) ??
        this.workWindowsForDay(workHours, cursor.toLocaleDateString('en-US', { weekday: 'long' }).toLowerCase()) ??
        [];
      for (const window of windows) {
        const windowStart = this.dateAtTime(cursor, clean(window.start) ?? clean(window.from) ?? '09:00');
        const windowEnd = this.dateAtTime(cursor, clean(window.end) ?? clean(window.to) ?? '18:00');
        if (windowStart && windowEnd && windowStart < end && windowEnd > start && windowStart < windowEnd) {
          blocks.push({
            start: new Date(Math.max(windowStart.getTime(), start.getTime())),
            end: new Date(Math.min(windowEnd.getTime(), end.getTime())),
            source: 'work_hours',
          });
        }
      }
      cursor.setDate(cursor.getDate() + 1);
    }
    return blocks.length > 0 ? blocks : [{ start, end, source: 'range_no_work_hours_match' }];
  }

  private applyWorkBlocks(freeBlocks: FreeBlock[], workBlocks: FreeBlock[]) {
    const result: FreeBlock[] = [];
    for (const free of freeBlocks) {
      for (const work of workBlocks) {
        const start = new Date(Math.max(free.start.getTime(), work.start.getTime()));
        const end = new Date(Math.min(free.end.getTime(), work.end.getTime()));
        if (end.getTime() - start.getTime() >= 15 * 60000) {
          result.push({ start, end, source: work.source ?? free.source });
        }
      }
    }
    return result.sort((a, b) => a.start.getTime() - b.start.getTime());
  }

  private computeFreeBlocks(start: Date, end: Date, busy: BusyBlock[]) {
    const free: FreeBlock[] = [];
    let cursor = new Date(start);
    for (const block of busy) {
      if (block.start > cursor) free.push({ start: new Date(cursor), end: new Date(block.start) });
      if (block.end > cursor) cursor = new Date(block.end);
    }
    if (cursor < end) free.push({ start: cursor, end });
    return free.filter((block) => block.end.getTime() - block.start.getTime() >= 15 * 60000);
  }

  private taskBlockedReason(task: TaskCandidate) {
    if (task.locked) return '任务已锁定，不参与自动排程。';
    if (!task.allowAutoSchedule) return '任务已关闭自动排程。';
    if (task.latestEnd && task.latestEnd <= new Date()) return '任务可排时间窗已结束。';
    return null;
  }

  private unplannedReason(task: TaskCandidate, freeBlocks: FreeBlock[]) {
    if (freeBlocks.length === 0) return '没有可用时间块，可能被阻挡日程或工作时间设置占满。';
    if (task.earliestStart || task.latestEnd) return '可用时间不足，或任务时间窗与空闲时间不匹配。';
    if (!task.canSplit) return '任务不可拆分，找不到足够长的连续时间块。';
    return '可用时间不足，或被更高优先级任务占用。';
  }

  private normalizePlannedReasons<T extends { task: TaskCandidate; reason: Record<string, unknown> }>(
    items: T[],
    strategy: string,
  ) {
    return items.map((item) => ({
      ...item,
      reason: {
        ...item.reason,
        text: `预计剩余 ${item.task.remainingMinutes} 分钟，已确认投入 ${item.task.confirmedMinutes} 分钟；按 ${strategy} 策略安排。`,
        location: item.task.location,
        notes: item.task.notes,
        dueAt: item.task.dueAt?.toISOString(),
      },
    })) as T[];
  }

  private normalizeUnplannedReasons(items: Array<Record<string, unknown>>, freeBlocks: FreeBlock[]) {
    return items.map((item) => {
      const reason = clean(item.reason);
      if (reason && /^[\x20-\x7E\u4E00-\u9FFF，。；：、（）]+$/.test(reason)) return item;
      return {
        ...item,
        reason: freeBlocks.length === 0 ? '没有可用时间块。' : '可用时间不足或约束不匹配。',
      };
    });
  }

  private isRecurringEvent(payload: Record<string, unknown>) {
    const recurrence = asRecord(payload.recurrence ?? payload.repeatRule ?? payload.rrule);
    const repeat = clean(payload.repeat ?? payload.repeatType ?? payload.frequency);
    return Object.keys(recurrence).length > 0 || Boolean(repeat);
  }

  private expandEventOccurrences(
    payload: Record<string, unknown>,
    eventStart: Date | null,
    eventEnd: Date | null,
    rangeStart: Date,
    rangeEnd: Date,
  ) {
    if (!eventStart || !eventEnd || eventStart >= eventEnd) return [];
    const recurrence = asRecord(payload.recurrence ?? payload.repeatRule ?? payload.rrule);
    const repeat = clean(recurrence.frequency ?? recurrence.freq ?? payload.repeat ?? payload.repeatType ?? payload.frequency)?.toLowerCase();
    if (!repeat) {
      return eventStart < rangeEnd && eventEnd > rangeStart ? [{ start: eventStart, end: eventEnd }] : [];
    }
    const interval = Math.max(1, Number(recurrence.interval ?? payload.repeatInterval ?? 1));
    const until = readDate(recurrence.until ?? payload.repeatUntil) ?? rangeEnd;
    const durationMs = eventEnd.getTime() - eventStart.getTime();
    const occurrences: Array<{ start: Date; end: Date }> = [];
    const cursor = new Date(eventStart);
    const maxIterations = 1000;
    let iterations = 0;

    while (cursor < rangeEnd && cursor <= until && iterations < maxIterations) {
      const occurrenceEnd = new Date(cursor.getTime() + durationMs);
      if (cursor < rangeEnd && occurrenceEnd > rangeStart && this.recurrenceDayMatches(cursor, recurrence)) {
        occurrences.push({ start: new Date(cursor), end: occurrenceEnd });
      }
      if (repeat.includes('week')) cursor.setDate(cursor.getDate() + 7 * interval);
      else if (repeat.includes('month')) cursor.setMonth(cursor.getMonth() + interval);
      else cursor.setDate(cursor.getDate() + interval);
      iterations += 1;
    }
    return occurrences;
  }

  private recurrenceDayMatches(date: Date, recurrence: Record<string, unknown>) {
    const days = recurrence.byWeekday ?? recurrence.byweekday ?? recurrence.daysOfWeek ?? recurrence.weekdays;
    if (!Array.isArray(days) || days.length === 0) return true;
    const weekday = date.getDay();
    const isoWeekday = weekday === 0 ? 7 : weekday;
    const names = ['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'];
    return days.some((item) => {
      if (typeof item === 'number') return item === weekday || item === isoWeekday;
      if (typeof item !== 'string') return false;
      const lower = item.toLowerCase();
      return lower === String(weekday) || lower === String(isoWeekday) || lower.startsWith(names[weekday]);
    });
  }

  private workWindowsForDay(workHours: Record<string, unknown>, dayKey: string) {
    const direct = workHours[dayKey];
    if (Array.isArray(direct)) return direct.map((item) => asRecord(item));
    const days = asRecord(workHours.days ?? workHours.weekly ?? workHours.schedule);
    const nested = days[dayKey];
    if (Array.isArray(nested)) return nested.map((item) => asRecord(item));
    return null;
  }

  private dateAtTime(day: Date, value: string) {
    const match = /^(\d{1,2}):(\d{2})$/.exec(value);
    if (!match) return null;
    const date = new Date(day);
    date.setHours(Number(match[1]), Number(match[2]), 0, 0);
    return date;
  }

  private taskScore(task: TaskCandidate, strategy: string, profile: Record<string, unknown>) {
    const priorityWeights = asRecord(profile.priorityWeights);
    const dueSoonWeights = asRecord(profile.dueSoonWeights);
    const learned = asRecord(profile.learnedAdjustments);
    let score = task.remainingMinutes / 10;
    score += Number(priorityWeights[task.priority] ?? 0);
    if (task.dueAt) {
      const hours = (task.dueAt.getTime() - Date.now()) / 3600000;
      if (hours <= 24) score += Number(dueSoonWeights.within24h ?? 50);
      else if (hours <= 72) score += Number(dueSoonWeights.within72h ?? 30);
    }
    if (task.confirmedMinutes > 0) score += Number(profile.actualWorkBonus ?? 10);
    if (strategy === 'deadline_first') score += task.dueAt ? Number(profile.deadlineFirstBonus ?? 20) : 0;
    score -= Number(learned.nightPenalty ?? 0) * 0.1;
    return score;
  }

  private shouldUseLlmFallback(
    body: Record<string, unknown>,
    tasks: TaskCandidate[],
    planned: Array<{ confidence: number }>,
    unplanned: Array<Record<string, unknown>>,
    profile: Record<string, unknown>,
  ) {
    const llm = asRecord(profile.llmFallback);
    if (body.useLlmFallback === false || llm.enabled === false) return false;
    if (body.useLlmFallback === true) return true;
    const candidates = tasks.filter((task) => task.remainingMinutes > 0);
    const ratio = candidates.length === 0 ? 0 : unplanned.length / candidates.length;
    const ratioThreshold = Number(llm.unplannedRatioThreshold ?? 0.3);
    const confidenceThreshold = Number(llm.confidenceThreshold ?? 0.65);
    const averageConfidence =
      planned.length === 0
        ? 0
        : planned.reduce((sum, item) => sum + Number(item.confidence ?? 0), 0) / planned.length;
    const hasUrgentUnplanned = unplanned.some((item) => {
      const task = tasks.find((candidate) => candidate.id === String(item.taskId));
      if (!task) return false;
      const dueSoon = task.dueAt ? task.dueAt.getTime() - Date.now() < 24 * 60 * 60 * 1000 : false;
      return task.priority === 'urgent' || task.priority === 'high' || dueSoon;
    });
    return ratio >= ratioThreshold || averageConfidence < confidenceThreshold || hasUrgentUnplanned;
  }

  private validateLlmDrafts(
    fallback: Record<string, unknown>,
    tasks: TaskCandidate[],
    rangeStart: Date,
    rangeEnd: Date,
    busyBlocks: BusyBlock[],
    existing: Array<{ task: TaskCandidate; start: Date; end: Date }>,
  ) {
    const planned: Array<{
      task: TaskCandidate;
      start: Date;
      end: Date;
      confidence: number;
      reason: Record<string, unknown>;
      risk: Record<string, unknown>;
    }> = [];
    const rejected: Array<Record<string, unknown>> = [];
    const draftItems = Array.isArray(fallback.draftItems) ? fallback.draftItems : [];
    const taskMap = new Map(tasks.map((task) => [task.id, task]));
    const occupied = [
      ...busyBlocks.map((block) => ({ start: block.start, end: block.end, source: block.source })),
      ...existing.map((item) => ({ start: item.start, end: item.end, source: 'rule_plan' })),
    ];
    for (const raw of draftItems) {
      const item = asRecord(raw);
      const taskId = clean(item.taskId) ?? clean(item.task_id);
      const task = taskId ? taskMap.get(taskId) : undefined;
      const start = readDate(item.proposedStart ?? item.proposed_start);
      const end = readDate(item.proposedEnd ?? item.proposed_end);
      const reason = clean(item.reason) ?? 'LLM fallback draft';
      if (!task || !start || !end || start >= end) {
        rejected.push({ taskId, reason: 'invalid_task_or_time', raw: item });
        continue;
      }
      const blockedReason = this.taskBlockedReason(task);
      if (blockedReason) {
        rejected.push({ taskId, reason: 'task_not_auto_schedulable', detail: blockedReason, raw: item });
        continue;
      }
      if (start < rangeStart || end > rangeEnd) {
        rejected.push({ taskId, reason: 'outside_range', raw: item });
        continue;
      }
      if (task.earliestStart && start < task.earliestStart) {
        rejected.push({ taskId, reason: 'before_task_time_window', raw: item });
        continue;
      }
      if (task.latestEnd && end > task.latestEnd) {
        rejected.push({ taskId, reason: 'after_task_time_window', raw: item });
        continue;
      }
      const durationMinutes = Math.round((end.getTime() - start.getTime()) / 60000);
      if (durationMinutes < task.minChunkMinutes || durationMinutes > task.maxChunkMinutes) {
        rejected.push({ taskId, reason: 'outside_task_chunk_limits', raw: item });
        continue;
      }
      if (occupied.some((block) => start < block.end && end > block.start)) {
        rejected.push({ taskId, reason: 'overlaps_busy_or_existing_block', raw: item });
        continue;
      }
      planned.push({
        task,
        start,
        end,
        confidence: Math.max(0.1, Math.min(0.85, Number(item.confidence ?? 0.62))),
        reason: {
          text: reason,
          modelUsed: 'llm_fallback',
          serverValidated: true,
          explanation: clean(fallback.explanation),
        },
        risk: {
          risk: clean(item.risk) ?? 'medium',
          llmFallback: true,
        },
      });
      occupied.push({ start, end, source: 'llm_fallback' });
    }
    const unplanned = Array.isArray(fallback.unplanned)
      ? fallback.unplanned.map((item) => asRecord(item))
      : [];
    return { planned, rejected, unplanned };
  }

  private readRange(rawStart: unknown, rawEnd: unknown) {
    const start = readDate(rawStart) ?? new Date();
    const end = readDate(rawEnd) ?? new Date(start.getTime() + 6 * 60 * 60 * 1000);
    if (start >= end) throw new BadRequestException('rangeStart must be before rangeEnd');
    return { start, end };
  }

  private async recordChange(
    client: TransactionClient,
    userId: string,
    deviceId: string,
    objectId: string,
    objectType: string,
    serverVersion: number,
    payload: Record<string, unknown>,
  ) {
    await client.query(
      `
      INSERT INTO sync_changes (
        user_id, device_id, server_object_id, object_type, action, server_version, payload
      ) VALUES ($1, $2, $3, $4, 'upsert', $5, $6::jsonb)
      `,
      [userId, deviceId, objectId, objectType, serverVersion, JSON.stringify(payload)],
    );
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
        String(details.targetType ?? 'schedule_run'),
        details.runId ? String(details.runId) : null,
        JSON.stringify(details),
      ],
    );
  }

  private stringArray(value: unknown) {
    return Array.isArray(value)
      ? value.filter((item): item is string => typeof item === 'string' && item.trim().length > 0)
      : [];
  }


  private readString(payload: Record<string, unknown>, keys: string[]) {
    for (const key of keys) {
      const value = payload[key];
      if (typeof value === 'string' && value.trim().length > 0) return value.trim();
    }
    return null;
  }
}
