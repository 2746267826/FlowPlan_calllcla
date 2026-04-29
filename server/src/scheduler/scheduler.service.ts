import { BadRequestException, Injectable } from '@nestjs/common';
import { QueryResultRow } from 'pg';
import { FlowPlanRequestContext } from '../common/request-context';
import { DatabaseService, TransactionClient } from '../database/database.service';
import { DevicesService } from '../devices/devices.service';
import { ModelsService } from '../models/models.service';

interface TaskCandidate {
  id: string;
  objectId: string;
  title: string;
  estimatedMinutes: number;
  confirmedMinutes: number;
  remainingMinutes: number;
  dueAt?: Date;
  priority: string;
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
}

@Injectable()
export class SchedulerService {
  constructor(
    private readonly database: DatabaseService,
    private readonly devicesService: DevicesService,
    private readonly modelsService: ModelsService,
  ) {}

  async createRun(body: Record<string, unknown>, context: FlowPlanRequestContext) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const { start, end } = this.readRange(body.rangeStart, body.rangeEnd);
    const mode = this.clean(body.mode) ?? 'initial_plan';
    const strategy = this.clean(body.strategy) ?? 'balanced';
    const activeModel = await this.modelsService.activeProfile(userId, 'scheduler.v1');
    const profile = this.asRecord(activeModel.ruleProfile);
    const tasks = await this.readTasks(userId);
    const busyBlocks = await this.readBusyBlocks(userId, start, end);
    const freeBlocks = this.computeFreeBlocks(start, end, busyBlocks);
    const modelRun = await this.modelsService.startRun(userId, 'scheduler.v1', {
      source: 'scheduler.createRun',
      inputSummary: {
        rangeStart: start.toISOString(),
        rangeEnd: end.toISOString(),
        strategy,
        taskCount: tasks.length,
        busyBlockCount: busyBlocks.length,
        profile,
      },
    });
    const ruleResult = this.plan(tasks, freeBlocks, strategy, profile);
    let planned = ruleResult.planned;
    let unplanned = ruleResult.unplanned;
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
        : planned.reduce((sum, item) => sum + Number(item.confidence ?? 0), 0) / planned.length;

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
            })),
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
      llmProviderKey: this.clean(llmFallback.providerKey),
      llmModel: this.clean(llmFallback.model),
    });

    return this.run(run, context);
  }

  async run(runId: string, context: FlowPlanRequestContext) {
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
    context: FlowPlanRequestContext,
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
      const riskSummary = this.asRecord(run.rows[0].risk_summary_json);
      const modelRunId = this.clean(riskSummary.modelRunId);
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
        const start = this.readDate(override?.start) ?? this.readDate(item.proposed_start);
        const end = this.readDate(override?.end) ?? this.readDate(item.proposed_end);
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
          [userId, runId, rejectedIds, this.clean(body.note)],
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
        note: this.clean(body.note),
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
          note: this.clean(body.note),
        },
      });
      return { createdObjectIds: created };
    });
    return { ok: true, ...result };
  }

  async rejectRun(
    runId: string,
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
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
        [userId, runId, this.clean(body.reason)],
      );
      await this.recordAudit(client, userId, deviceId, 'scheduler.run.rejected', {
        runId,
        reason: this.clean(body.reason),
      });
      await this.modelsService.recordFeedback(client, userId, deviceId, 'scheduler.v1', {
        targetType: 'schedule_run',
        targetId: runId,
        feedbackType: 'rejected',
        outcome: 'rejected',
        source: 'scheduler.rejectRun',
        feedbackPayload: {
          reason: this.clean(body.reason),
        },
      });
    });
    return { ok: true, message: 'draft rejected; no schedule segments were written' };
  }

  async detectDeviations(
    body: Record<string, unknown>,
    context: FlowPlanRequestContext,
  ) {
    const userId = await this.devicesService.ensureUser(context.userId);
    const deviceId = await this.devicesService.ensureDevice(context);
    const { start, end } = this.readRange(body.rangeStart, body.rangeEnd);
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
      for (const planned of segments.rows) {
        const payload = this.asRecord(planned.payload);
        const plannedStart = this.readDate(payload.startAt);
        const plannedEnd = this.readDate(payload.endAt);
        if (!plannedStart || !plannedEnd) continue;
        const overlap = actuals.rows.find((actual) => {
          const actualStart = this.readDate(actual.start_at);
          const actualEnd = this.readDate(actual.end_at);
          return actualStart && actualEnd && actualStart < plannedEnd && actualEnd > plannedStart;
        });
        if (!overlap) {
          await client.query(
            `
            INSERT INTO plan_deviations (
              user_id, schedule_segment_id, planned_task_id, planned_start, planned_end,
              deviation_type, severity, confidence, status, evidence
            ) VALUES ($1, $2, $3, $4, $5, 'missed', 'medium', 0.65, 'detected', $6::jsonb)
            `,
            [
              userId,
              String(planned.id),
              this.clean(payload.taskId),
              plannedStart,
              plannedEnd,
              JSON.stringify({ reason: 'no confirmed actual log overlapped this schedule segment' }),
            ],
          );
          created += 1;
        } else if (!String(overlap.title ?? '').includes(String(payload.taskTitle ?? ''))) {
          await client.query(
            `
            INSERT INTO plan_deviations (
              user_id, schedule_segment_id, planned_task_id, planned_start, planned_end,
              actual_log_id, actual_title, actual_start, actual_end,
              deviation_type, severity, confidence, status, evidence
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'different_activity', 'medium', 0.7, 'detected', $10::jsonb)
            `,
            [
              userId,
              String(planned.id),
              this.clean(payload.taskId),
              plannedStart,
              plannedEnd,
              overlap.id,
              overlap.title,
              overlap.start_at,
              overlap.end_at,
              JSON.stringify({ planned: payload, actual: overlap }),
            ],
          );
          created += 1;
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
    const sorted = [...tasks]
      .filter((task) => task.remainingMinutes > 0)
      .sort((a, b) => this.taskScore(b, strategy, profile) - this.taskScore(a, strategy, profile));

    for (const task of sorted) {
      let minutesLeft = task.remainingMinutes;
      let didPlan = false;
      for (const block of remainingBlocks) {
        const blockMinutes = Math.floor((block.end.getTime() - block.start.getTime()) / 60000);
        if (blockMinutes < 15 || minutesLeft <= 0) continue;
        const minutes = Math.min(minutesLeft, blockMinutes, Math.max(30, Number(task.payload.maxChunkMinutes ?? 120)));
        const start = new Date(block.start);
        const end = new Date(start.getTime() + minutes * 60000);
        planned.push({
          task,
          start,
          end,
            confidence: Math.min(0.95, 0.78 + Number(this.asRecord(profile.learnedAdjustments).confidenceBonus ?? 0)),
            reason: {
            text: `预计剩余 ${task.remainingMinutes} 分钟，已确认投入 ${task.confirmedMinutes} 分钟；按 ${strategy} 策略优先安排。`,
            dueAt: task.dueAt?.toISOString(),
              priority: task.priority,
              confirmedMinutes: task.confirmedMinutes,
              remainingMinutes: task.remainingMinutes,
              modelUsed: 'rule_learned',
            },
          risk: {
            deadlineSoon: task.dueAt ? task.dueAt.getTime() - Date.now() < 36 * 60 * 60 * 1000 : false,
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
          remainingMinutes: minutesLeft > 0 ? minutesLeft : task.remainingMinutes,
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
      [userId, ['task', 'tasks', 'task_item', 'task_items']],
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
        const payload = this.asRecord(row.payload);
        const status = String(payload.status ?? '').toLowerCase();
        const taskId = String(row.uid ?? row.id);
        const estimatedMinutes = Math.max(15, Number(payload.estimatedMinutes ?? payload.estimated_minutes ?? payload.durationMinutes ?? 60));
        const confirmedMinutes = workMap.get(taskId) ?? workMap.get(String(row.id)) ?? 0;
        return {
          id: taskId,
          objectId: String(row.id),
          title: this.readString(payload, ['title', 'name', 'summary']) ?? taskId,
          estimatedMinutes,
          confirmedMinutes,
          remainingMinutes: Math.max(0, estimatedMinutes - confirmedMinutes),
          dueAt:
            this.readDate(this.readString(payload, ['dueAt', 'due_at', 'deadline'])) ??
            undefined,
          priority: String(payload.priority ?? 'normal'),
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
        AND updated_at >= $3 - interval '7 days'
        AND updated_at < $4 + interval '7 days'
      `,
      [userId, ['calendar_event', 'calendar_events', 'event', 'events', 'time_block', 'time_blocks'], start, end],
    );
    const blocks: BusyBlock[] = [];
    for (const row of events.rows) {
      const payload = this.asRecord(row.payload);
      const eventStart = this.readDate(this.readString(payload, ['startAt', 'startTime', 'start_at']));
      const eventEnd = this.readDate(this.readString(payload, ['endAt', 'endTime', 'end_at']));
      const blocking = payload.isBlocking === true || payload.blocking === true || payload.kind === 'blocking';
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

  private taskScore(task: TaskCandidate, strategy: string, profile: Record<string, unknown>) {
    const priorityWeights = this.asRecord(profile.priorityWeights);
    const dueSoonWeights = this.asRecord(profile.dueSoonWeights);
    const learned = this.asRecord(profile.learnedAdjustments);
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
    const llm = this.asRecord(profile.llmFallback);
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
      const item = this.asRecord(raw);
      const taskId = this.clean(item.taskId) ?? this.clean(item.task_id);
      const task = taskId ? taskMap.get(taskId) : undefined;
      const start = this.readDate(item.proposedStart ?? item.proposed_start);
      const end = this.readDate(item.proposedEnd ?? item.proposed_end);
      const reason = this.clean(item.reason) ?? 'LLM fallback draft';
      if (!task || !start || !end || start >= end) {
        rejected.push({ taskId, reason: 'invalid_task_or_time', raw: item });
        continue;
      }
      if (start < rangeStart || end > rangeEnd) {
        rejected.push({ taskId, reason: 'outside_range', raw: item });
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
          explanation: this.clean(fallback.explanation),
        },
        risk: {
          risk: this.clean(item.risk) ?? 'medium',
          llmFallback: true,
        },
      });
      occupied.push({ start, end, source: 'llm_fallback' });
    }
    const unplanned = Array.isArray(fallback.unplanned)
      ? fallback.unplanned.map((item) => this.asRecord(item))
      : [];
    return { planned, rejected, unplanned };
  }

  private readRange(rawStart: unknown, rawEnd: unknown) {
    const start = this.readDate(rawStart) ?? new Date();
    const end = this.readDate(rawEnd) ?? new Date(start.getTime() + 6 * 60 * 60 * 1000);
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
      if (typeof value === 'string' && value.trim().length > 0) return value.trim();
    }
    return null;
  }
}
