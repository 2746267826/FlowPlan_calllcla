import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../audit/data_operation_log_repository.dart';
import '../actual/data/actual_activity_log_repository.dart';
import '../calendar/data/event_repository.dart';
import '../task/data/task_repository.dart';
import '../tracker/data/activity_fusion_repository.dart';
import 'task_schedule_segment_repository.dart';

class SchedulerRunLogEntry {
  const SchedulerRunLogEntry({
    required this.level,
    required this.message,
    this.taskId,
    this.taskSummary,
    this.start,
    this.end,
  });

  final String level;
  final String message;
  final int? taskId;
  final String? taskSummary;
  final DateTime? start;
  final DateTime? end;

  Map<String, dynamic> toJson() => {
        'level': level,
        'message': message,
        if (taskId != null) 'task_id': taskId,
        if (taskSummary != null) 'task_summary': taskSummary,
        if (start != null) 'start': start!.toIso8601String(),
        if (end != null) 'end': end!.toIso8601String(),
      };
}

class SchedulerRunResult {
  const SchedulerRunResult({
    required this.date,
    required this.planRunId,
    required this.trigger,
    required this.effectiveStart,
    required this.effectiveEnd,
    required this.scheduledTaskCount,
    required this.rescheduledTaskCount,
    required this.clearedTaskCount,
    required this.unscheduledTaskCount,
    required this.splitSuggestedTaskCount,
    required this.evidenceCompletedTaskCount,
    required this.placements,
    required this.clearedTaskIds,
    required this.unscheduledTasks,
    required this.logEntries,
    required this.context,
  });

  final DateTime date;
  final String planRunId;
  final String trigger;
  final DateTime effectiveStart;
  final DateTime effectiveEnd;
  final int scheduledTaskCount;
  final int rescheduledTaskCount;
  final int clearedTaskCount;
  final int unscheduledTaskCount;
  final int splitSuggestedTaskCount;
  final int evidenceCompletedTaskCount;
  final List<SchedulerTaskPlacement> placements;
  final List<int> clearedTaskIds;
  final List<SchedulerUnscheduledTask> unscheduledTasks;
  final List<SchedulerRunLogEntry> logEntries;
  final SchedulerContextSnapshot context;

  bool get hasChanges => scheduledTaskCount > 0 || clearedTaskCount > 0;
  bool get requiresConfirmation => hasChanges;

  String get summary {
    if (!hasChanges && unscheduledTaskCount == 0) {
      return '没有需要重排的任务。';
    }
    return '已排入 $scheduledTaskCount 个任务，重排 $rescheduledTaskCount 个，'
        '移回未排程 $clearedTaskCount 个，仍有 $unscheduledTaskCount 个未排入。';
  }

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'plan_run_id': planRunId,
        'trigger': trigger,
        'effective_start': effectiveStart.toIso8601String(),
        'effective_end': effectiveEnd.toIso8601String(),
        'scheduled_task_count': scheduledTaskCount,
        'rescheduled_task_count': rescheduledTaskCount,
        'cleared_task_count': clearedTaskCount,
        'unscheduled_task_count': unscheduledTaskCount,
        'split_suggested_task_count': splitSuggestedTaskCount,
        'evidence_completed_task_count': evidenceCompletedTaskCount,
        'placements':
            placements.map((placement) => placement.toJson()).toList(),
        'cleared_task_ids': clearedTaskIds,
        'unscheduled_tasks':
            unscheduledTasks.map((task) => task.toJson()).toList(),
        'log_entries': logEntries.map((entry) => entry.toJson()).toList(),
        'context': context.toJson(),
      };
}

class SchedulerTaskPlacement {
  const SchedulerTaskPlacement({
    required this.taskId,
    required this.taskSummary,
    required this.wasRescheduled,
    required this.isSplit,
    required this.originalDurationMinutes,
    required this.actualWorkedMinutes,
    required this.remainingMinutes,
    required this.reason,
    required this.requiredConfirmation,
    required this.segments,
  });

  final int taskId;
  final String taskSummary;
  final bool wasRescheduled;
  final bool isSplit;
  final int originalDurationMinutes;
  final int actualWorkedMinutes;
  final int remainingMinutes;
  final String reason;
  final bool requiredConfirmation;
  final List<SchedulerTaskSegmentPlan> segments;

  DateTime get dtstart => segments.first.start;

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'task_summary': taskSummary,
        'was_rescheduled': wasRescheduled,
        'is_split': isSplit,
        'original_duration_minutes': originalDurationMinutes,
        'actual_worked_minutes': actualWorkedMinutes,
        'remaining_minutes': remainingMinutes,
        'reason': reason,
        'required_confirmation': requiredConfirmation,
        'segments': segments.map((segment) => segment.toJson()).toList(),
      };
}

class SchedulerUnscheduledTask {
  const SchedulerUnscheduledTask({
    required this.taskId,
    required this.taskSummary,
    required this.reason,
    required this.originalDurationMinutes,
    required this.actualWorkedMinutes,
    required this.remainingMinutes,
  });

  final int taskId;
  final String taskSummary;
  final String reason;
  final int originalDurationMinutes;
  final int actualWorkedMinutes;
  final int remainingMinutes;

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'task_summary': taskSummary,
        'reason': reason,
        'original_duration_minutes': originalDurationMinutes,
        'actual_worked_minutes': actualWorkedMinutes,
        'remaining_minutes': remainingMinutes,
      };
}

class SchedulerContextSnapshot {
  const SchedulerContextSnapshot({
    required this.date,
    required this.effectiveStart,
    required this.effectiveEnd,
    required this.fixedBlockCount,
    required this.confirmedActualCount,
    required this.taskEvidence,
    required this.deviationReason,
    required this.usesWeatherContext,
    required this.usesLocationContext,
    required this.usesFileContext,
  });

  final DateTime date;
  final DateTime effectiveStart;
  final DateTime effectiveEnd;
  final int fixedBlockCount;
  final int confirmedActualCount;
  final List<SchedulerTaskEvidence> taskEvidence;
  final String? deviationReason;
  final bool usesWeatherContext;
  final bool usesLocationContext;
  final bool usesFileContext;

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'effective_start': effectiveStart.toIso8601String(),
        'effective_end': effectiveEnd.toIso8601String(),
        'fixed_block_count': fixedBlockCount,
        'confirmed_actual_count': confirmedActualCount,
        'task_evidence': taskEvidence.map((item) => item.toJson()).toList(),
        'deviation_reason': deviationReason,
        'uses_weather_context': usesWeatherContext,
        'uses_location_context': usesLocationContext,
        'uses_file_context': usesFileContext,
      };
}

class SchedulerTaskEvidence {
  const SchedulerTaskEvidence({
    required this.taskId,
    required this.taskSummary,
    required this.originalDurationMinutes,
    required this.actualWorkedMinutes,
    required this.remainingMinutes,
    required this.workLogCount,
    required this.actualCandidateCount,
    required this.reason,
  });

  final int taskId;
  final String taskSummary;
  final int originalDurationMinutes;
  final int actualWorkedMinutes;
  final int remainingMinutes;
  final int workLogCount;
  final int actualCandidateCount;
  final String reason;

  bool get isSatisfiedByEvidence => remainingMinutes <= 0;

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'task_summary': taskSummary,
        'original_duration_minutes': originalDurationMinutes,
        'actual_worked_minutes': actualWorkedMinutes,
        'remaining_minutes': remainingMinutes,
        'work_log_count': workLogCount,
        'actual_candidate_count': actualCandidateCount,
        'reason': reason,
      };
}

class SchedulerTaskSegmentPlan {
  const SchedulerTaskSegmentPlan({
    required this.start,
    required this.end,
  });

  final DateTime start;
  final DateTime end;

  int get durationMinutes => end.difference(start).inMinutes;

  Map<String, dynamic> toJson() => {
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'duration_minutes': durationMinutes,
      };
}

class SchedulerEngine {
  SchedulerEngine(
    this._taskRepo,
    this._eventRepo,
    this._db,
    this._workSchedule,
    this._segmentRepo,
    this._operationLogs,
    this._actualLogs,
    this._fusionRepo,
  );

  static const _lastRunReportKey = 'scheduler.last_run_report.v1';
  static const _slotMinutes = 15;

  final TaskRepository _taskRepo;
  final EventRepository _eventRepo;
  final AppDatabase _db;
  final WeeklyWorkSchedule _workSchedule;
  final TaskScheduleSegmentRepository _segmentRepo;
  final DataOperationLogRepository _operationLogs;
  final ActualActivityLogRepository _actualLogs;
  final ActivityFusionRepository _fusionRepo;

  Future<int> autoSchedule(DateTime date) async {
    final result = await autoScheduleDetailed(date);
    return result.scheduledTaskCount;
  }

  Future<SchedulerRunResult> autoScheduleDetailed(
    DateTime date, {
    DateTime? from,
    DateTime? until,
    Set<int> forceMovableTaskIds = const <int>{},
    String trigger = 'manual_reschedule',
  }) async {
    final targetDate = DateTime(date.year, date.month, date.day);
    final planRunId = 'schedule-${DateTime.now().microsecondsSinceEpoch}';
    final logs = <SchedulerRunLogEntry>[];
    final effectiveStart = _effectiveStartForDate(targetDate, from: from);
    final effectiveEnd =
        _effectiveEndForDate(targetDate, effectiveStart, until: until);
    final windows = _buildWorkWindows(targetDate, effectiveStart, effectiveEnd);
    final context = await _buildContextSnapshot(
      targetDate,
      effectiveStart,
      effectiveEnd,
      deviationReason:
          trigger.startsWith('plan_deviation') ? '计划偏离触发局部重排' : null,
    );

    if (windows.isEmpty) {
      final schedulableTasks = await _taskRepo.getPendingForSchedule();
      final evidenceByTaskId = {
        for (final evidence in context.taskEvidence) evidence.taskId: evidence,
      };
      final unscheduledTasks = schedulableTasks.map((task) {
        final evidence =
            evidenceByTaskId[task.id] ?? _fallbackEvidenceForTask(task);
        return SchedulerUnscheduledTask(
          taskId: task.id,
          taskSummary: task.summary,
          reason: '所选排程范围内没有可用工作时段。',
          originalDurationMinutes: evidence.originalDurationMinutes,
          actualWorkedMinutes: evidence.actualWorkedMinutes,
          remainingMinutes: evidence.remainingMinutes,
        );
      }).toList(growable: false);
      logs.add(
        SchedulerRunLogEntry(
          level: 'warning',
          message: '当天没有可用工作时段，未执行排期。',
          start: effectiveStart,
        ),
      );
      final result = SchedulerRunResult(
        date: targetDate,
        planRunId: planRunId,
        trigger: trigger,
        effectiveStart: effectiveStart,
        effectiveEnd: effectiveEnd,
        scheduledTaskCount: 0,
        rescheduledTaskCount: 0,
        clearedTaskCount: 0,
        unscheduledTaskCount: unscheduledTasks.length,
        splitSuggestedTaskCount: 0,
        evidenceCompletedTaskCount: 0,
        placements: const <SchedulerTaskPlacement>[],
        clearedTaskIds: const <int>[],
        unscheduledTasks: unscheduledTasks,
        logEntries: logs,
        context: context,
      );
      await _saveReport(result);
      return result;
    }

    final blockers = await _loadFixedBlocks(targetDate, logs);
    await _loadConfirmedActualBlocks(
        targetDate, effectiveStart, blockers, logs);
    final activeScheduledTasks = await _taskRepo.getActiveScheduledForDate(
      targetDate,
    );
    final schedulableTasks = await _taskRepo.getPendingForSchedule();
    final schedulableById = {
      for (final task in schedulableTasks) task.id: task,
    };

    final movableTaskIds = <int>{};
    final candidatesById = <int, TaskItem>{};

    for (final task in schedulableTasks) {
      if (task.dtstart == null) {
        candidatesById[task.id] = task;
      }
    }

    for (final task in activeScheduledTasks) {
      final scheduled = task.dtstart;
      final isMovable = scheduled != null &&
          (!scheduled.isBefore(effectiveStart) ||
              forceMovableTaskIds.contains(task.id)) &&
          schedulableById.containsKey(task.id) &&
          !task.isLocked &&
          task.isAutoScheduled;
      if (isMovable) {
        movableTaskIds.add(task.id);
        candidatesById[task.id] = task;
        continue;
      }

      final end = scheduled?.add(Duration(minutes: task.durationMinutes));
      if (scheduled != null && end != null) {
        final existingSegments = await _segmentRepo.getByTaskId(task.id);
        if (existingSegments.isEmpty) {
          blockers.add((
            start: scheduled,
            end: end,
            label:
                task.isLocked ? '锁定任务：${task.summary}' : '已排任务：${task.summary}',
          ));
        }
      }
    }

    final existingSegmentsForDate = await _segmentRepo.getForDate(targetDate);
    for (final item in existingSegmentsForDate) {
      if (movableTaskIds.contains(item.task.id)) {
        continue;
      }
      blockers.add((
        start: item.segment.startAt,
        end: item.segment.endAt,
        label: item.task.isLocked
            ? '锁定任务片段：${item.task.summary}'
            : '已排任务片段：${item.task.summary}',
      ));
    }

    blockers.sort((left, right) => left.start.compareTo(right.start));
    final occupied = blockers.toList();
    final evidenceByTaskId = {
      for (final evidence in context.taskEvidence) evidence.taskId: evidence,
    };
    final candidates = candidatesById.values
        .map(
          (task) => _SchedulerCandidate(
            task: task,
            evidence:
                evidenceByTaskId[task.id] ?? _fallbackEvidenceForTask(task),
          ),
        )
        .toList()
      ..sort(
        (left, right) => _compareTasksForScheduling(left.task, right.task),
      );

    final placements = <SchedulerTaskPlacement>[];
    final unscheduledTasks = <SchedulerUnscheduledTask>[];
    final scheduledIds = <int>{};
    final clearedIds = movableTaskIds.toSet();
    var splitPlacementCount = 0;
    var evidenceCompletedCount = 0;

    for (final candidate in candidates) {
      final task = candidate.task;
      final evidence = candidate.evidence;
      if (evidence.isSatisfiedByEvidence) {
        evidenceCompletedCount++;
        clearedIds.add(task.id);
        logs.add(
          SchedulerRunLogEntry(
            level: 'info',
            taskId: task.id,
            taskSummary: task.summary,
            message: '已有实际投入覆盖预计时长，本轮不再为该任务安排新时间。',
          ),
        );
        continue;
      }

      final duration = Duration(minutes: evidence.remainingMinutes);
      final slot = _findFreeSlot(
        windows: windows,
        occupied: occupied,
        duration: duration,
      );

      if (slot != null) {
        final end = slot.add(duration);
        final placement = SchedulerTaskPlacement(
          taskId: task.id,
          taskSummary: task.summary,
          wasRescheduled: movableTaskIds.contains(task.id),
          isSplit: false,
          originalDurationMinutes: evidence.originalDurationMinutes,
          actualWorkedMinutes: evidence.actualWorkedMinutes,
          remainingMinutes: evidence.remainingMinutes,
          reason: evidence.reason,
          requiredConfirmation: true,
          segments: [
            SchedulerTaskSegmentPlan(start: slot, end: end),
          ],
        );
        placements.add(placement);
        scheduledIds.add(task.id);
        occupied.add((
          start: slot,
          end: end,
          label: '新排任务：${task.summary}',
        ));
        occupied.sort((left, right) => left.start.compareTo(right.start));
        logs.add(
          SchedulerRunLogEntry(
            level: movableTaskIds.contains(task.id) ? 'info' : 'success',
            taskId: task.id,
            taskSummary: task.summary,
            start: slot,
            end: end,
            message: movableTaskIds.contains(task.id)
                ? '任务已参与局部重排，并被安排到 ${_formatDateTime(slot)}。'
                : '任务已安排到 ${_formatDateTime(slot)}。',
          ),
        );
        continue;
      }

      if (task.isSplittable) {
        final segments = _findSplitSuggestion(
          windows: windows,
          occupied: occupied,
          duration: duration,
        );
        if (segments.isNotEmpty) {
          splitPlacementCount++;
          final readableSegments = segments
              .map((segment) =>
                  '${_formatTime(segment.start)}-${_formatTime(segment.end)}')
              .join('，');
          placements.add(
            SchedulerTaskPlacement(
              taskId: task.id,
              taskSummary: task.summary,
              wasRescheduled: movableTaskIds.contains(task.id),
              isSplit: true,
              originalDurationMinutes: evidence.originalDurationMinutes,
              actualWorkedMinutes: evidence.actualWorkedMinutes,
              remainingMinutes: evidence.remainingMinutes,
              reason: evidence.reason,
              requiredConfirmation: true,
              segments: segments
                  .map(
                    (segment) => SchedulerTaskSegmentPlan(
                      start: segment.start,
                      end: segment.end,
                    ),
                  )
                  .toList(),
            ),
          );
          scheduledIds.add(task.id);
          for (final segment in segments) {
            occupied.add((
              start: segment.start,
              end: segment.end,
              label: '拆分任务：${task.summary}',
            ));
          }
          occupied.sort((left, right) => left.start.compareTo(right.start));
          logs.add(
            SchedulerRunLogEntry(
              level: movableTaskIds.contains(task.id) ? 'info' : 'success',
              taskId: task.id,
              taskSummary: task.summary,
              message: '任务已按可拆分策略生成多段排程预案：$readableSegments。'
                  '确认应用后会写入任务排程片段，并在时间轴中按多段显示。',
            ),
          );
          continue;
        }
      }

      logs.add(
        SchedulerRunLogEntry(
          level: 'warning',
          taskId: task.id,
          taskSummary: task.summary,
          message: '没有找到足够空闲时段，任务保持未排程状态。',
        ),
      );
      unscheduledTasks.add(
        SchedulerUnscheduledTask(
          taskId: task.id,
          taskSummary: task.summary,
          reason: '在所选排程范围内没有找到连续或可拆分的空闲时间。',
          originalDurationMinutes: evidence.originalDurationMinutes,
          actualWorkedMinutes: evidence.actualWorkedMinutes,
          remainingMinutes: evidence.remainingMinutes,
        ),
      );
    }

    clearedIds.removeAll(scheduledIds);

    final result = SchedulerRunResult(
      date: targetDate,
      planRunId: planRunId,
      trigger: trigger,
      effectiveStart: effectiveStart,
      effectiveEnd: effectiveEnd,
      scheduledTaskCount: placements.length,
      rescheduledTaskCount:
          placements.where((item) => item.wasRescheduled).length,
      clearedTaskCount: clearedIds.length,
      unscheduledTaskCount:
          candidates.length - placements.length - evidenceCompletedCount,
      splitSuggestedTaskCount: splitPlacementCount,
      evidenceCompletedTaskCount: evidenceCompletedCount,
      placements: placements,
      clearedTaskIds: clearedIds.toList(growable: false),
      unscheduledTasks: unscheduledTasks,
      logEntries: logs,
      context: context,
    );
    await _saveReport(result);
    return result;
  }

  Future<SchedulerRunResult> autoScheduleFromDeviation({
    required DateTime date,
    required int deviatedTaskId,
    DateTime? from,
  }) {
    return autoScheduleDetailed(
      date,
      from: from ?? DateTime.now(),
      forceMovableTaskIds: {deviatedTaskId},
      trigger: 'plan_deviation',
    );
  }

  Future<void> applyRunResult(SchedulerRunResult result) async {
    if (!result.hasChanges) {
      return;
    }

    final scheduled = result.placements
        .map((placement) => (id: placement.taskId, dtstart: placement.dtstart))
        .toList();
    await _taskRepo.batchApplySchedule(
      scheduled: scheduled,
      clearedTaskIds: result.clearedTaskIds,
    );

    final affectedTaskIds = <int>{
      ...result.placements.map((placement) => placement.taskId),
      ...result.clearedTaskIds,
    };
    final segmentDrafts = <TaskScheduleSegmentDraft>[];
    for (final placement in result.placements) {
      for (var index = 0; index < placement.segments.length; index++) {
        final segment = placement.segments[index];
        segmentDrafts.add(
          TaskScheduleSegmentDraft(
            taskId: placement.taskId,
            segmentIndex: index,
            startAt: segment.start,
            endAt: segment.end,
            source: placement.isSplit ? 'auto_split' : 'auto_single',
            planRunId: result.planRunId,
            note: placement.isSplit ? '自动排期确认后的拆分片段' : '自动排期确认后的单段片段',
          ),
        );
      }
    }

    await _segmentRepo.replaceForTasks(
      taskIds: affectedTaskIds,
      segments: segmentDrafts,
      actor: '用户确认',
      summary: '应用一键重排预案：${result.summary}',
      metadata: result.toJson(),
    );

    await _operationLogs.record(
      actor: '用户确认',
      action: 'apply_scheduler_plan',
      entityType: 'scheduler_run',
      entityId: result.planRunId,
      summary: '用户确认应用排程预案：${result.summary}',
      after: result.toJson(),
      metadata: {
        'date': result.date.toIso8601String(),
        'affected_task_ids': affectedTaskIds.toList(),
        'trigger': result.trigger,
      },
    );
  }

  Future<SchedulerContextSnapshot> _buildContextSnapshot(
    DateTime targetDate,
    DateTime effectiveStart,
    DateTime effectiveEnd, {
    String? deviationReason,
  }) async {
    final dayEnd = targetDate.add(const Duration(days: 1));
    final fixedBlocks = await _eventRepo.getBlocksForDate(targetDate);
    final confirmedActuals = await _actualLogs.listInRange(
      targetDate,
      dayEnd,
      statuses: const <String>[ActualActivityStatus.confirmed],
    );
    final schedulableTasks = await _taskRepo.getPendingForSchedule();
    final activeScheduledTasks =
        await _taskRepo.getActiveScheduledForDate(targetDate);
    final taskById = <int, TaskItem>{
      for (final task in schedulableTasks) task.id: task,
      for (final task in activeScheduledTasks) task.id: task,
    };
    final allActualCandidates = await _actualLogs.listInRange(
      targetDate,
      dayEnd,
      statuses: const <String>[
        ActualActivityStatus.candidate,
        ActualActivityStatus.confirmed,
      ],
    );

    final evidence = <SchedulerTaskEvidence>[];
    for (final task in taskById.values) {
      final workLogs = await _fusionRepo.listTaskWorkLogsForTask(task.id);
      final credibleWorkLogs = workLogs
          .where(
            (log) =>
                !log.endAt.isAfter(effectiveStart) && log.status == 'confirmed',
          )
          .toList(growable: false);
      final workedMinutes = credibleWorkLogs.fold<int>(
        0,
        (sum, log) => sum + log.durationMinutes,
      );
      final actualCandidateCount = allActualCandidates
          .where((actual) => _actualMentionsTask(actual, task.id))
          .length;
      final original = task.durationMinutes <= 0 ? 30 : task.durationMinutes;
      final remainingRaw = original - workedMinutes;
      final remaining =
          remainingRaw <= 0 ? 0 : _snapDurationMinutes(remainingRaw);
      final reason = workedMinutes <= 0
          ? '尚无可信实际投入证据，按预计时长 $original 分钟排程。'
          : remaining <= 0
              ? '已有 $workedMinutes 分钟可信实际投入，达到或超过预计 $original 分钟。'
              : '已有 $workedMinutes 分钟可信实际投入，预计 $original 分钟，剩余 $remaining 分钟。';

      evidence.add(
        SchedulerTaskEvidence(
          taskId: task.id,
          taskSummary: task.summary,
          originalDurationMinutes: original,
          actualWorkedMinutes: workedMinutes,
          remainingMinutes: remaining,
          workLogCount: credibleWorkLogs.length,
          actualCandidateCount: actualCandidateCount,
          reason: reason,
        ),
      );
    }

    evidence
        .sort((left, right) => left.taskSummary.compareTo(right.taskSummary));
    return SchedulerContextSnapshot(
      date: targetDate,
      effectiveStart: effectiveStart,
      effectiveEnd: effectiveEnd,
      fixedBlockCount: fixedBlocks
          .where((event) => event.status.trim().toUpperCase() != 'CANCELLED')
          .length,
      confirmedActualCount: confirmedActuals.length,
      taskEvidence: evidence,
      deviationReason: deviationReason,
      usesWeatherContext: false,
      usesLocationContext: false,
      usesFileContext: false,
    );
  }

  SchedulerTaskEvidence _fallbackEvidenceForTask(TaskItem task) {
    final original = task.durationMinutes <= 0 ? 30 : task.durationMinutes;
    return SchedulerTaskEvidence(
      taskId: task.id,
      taskSummary: task.summary,
      originalDurationMinutes: original,
      actualWorkedMinutes: 0,
      remainingMinutes: _snapDurationMinutes(original),
      workLogCount: 0,
      actualCandidateCount: 0,
      reason: '尚无可信实际投入证据，按预计时长 $original 分钟排程。',
    );
  }

  Future<void> _loadConfirmedActualBlocks(
    DateTime date,
    DateTime effectiveStart,
    List<({DateTime start, DateTime end, String label})> blocks,
    List<SchedulerRunLogEntry> logs,
  ) async {
    final dayEnd = date.add(const Duration(days: 1));
    final actuals = await _actualLogs.listInRange(
      effectiveStart,
      dayEnd,
      statuses: const <String>[ActualActivityStatus.confirmed],
    );
    for (final actual in actuals) {
      if (!actual.endAt.isAfter(effectiveStart)) {
        continue;
      }
      blocks.add((
        start: actual.startAt.isBefore(effectiveStart)
            ? effectiveStart
            : actual.startAt,
        end: actual.endAt,
        label: '已确认实际记录：${actual.title}',
      ));
      logs.add(
        SchedulerRunLogEntry(
          level: 'info',
          message: '已避让确认的实际记录「${actual.title}」。',
          start: actual.startAt,
          end: actual.endAt,
        ),
      );
    }
  }

  bool _actualMentionsTask(ActualActivityLog actual, int taskId) {
    final payload = actual.sourcePayloadJson.trim();
    if (payload.isEmpty) {
      return false;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        return decoded['taskId'] == taskId ||
            decoded['task_id'] == taskId ||
            decoded['taskId']?.toString() == taskId.toString() ||
            decoded['task_id']?.toString() == taskId.toString();
      }
    } catch (_) {
      return payload.contains('"taskId":$taskId') ||
          payload.contains('"taskId": $taskId') ||
          payload.contains('"task_id":$taskId') ||
          payload.contains('"task_id": $taskId');
    }
    return false;
  }

  DateTime _effectiveStartForDate(DateTime date, {DateTime? from}) {
    var effectiveStart = DateTime(date.year, date.month, date.day);
    final now = DateTime.now();
    if (_isSameDay(date, now) && now.isAfter(effectiveStart)) {
      effectiveStart = now;
    }
    if (from != null && from.isAfter(effectiveStart)) {
      effectiveStart = from;
    }
    return _snapUp(effectiveStart);
  }

  DateTime _effectiveEndForDate(
    DateTime date,
    DateTime effectiveStart, {
    DateTime? until,
  }) {
    final dayEnd =
        DateTime(date.year, date.month, date.day).add(const Duration(days: 1));
    if (until == null) {
      return dayEnd;
    }
    final sameDayUntil =
        DateTime(date.year, date.month, date.day, until.hour, until.minute);
    if (!sameDayUntil.isAfter(effectiveStart)) {
      return effectiveStart;
    }
    return sameDayUntil.isAfter(dayEnd) ? dayEnd : sameDayUntil;
  }

  List<({DateTime start, DateTime end})> _buildWorkWindows(
    DateTime date,
    DateTime effectiveStart,
    DateTime effectiveEnd,
  ) {
    final ranges = _workSchedule.rangesForWeekday(date.weekday);
    final windows = <({DateTime start, DateTime end})>[];
    for (final range in ranges) {
      var start = DateTime(date.year, date.month, date.day)
          .add(Duration(minutes: range.startMinute));
      final end = DateTime(date.year, date.month, date.day)
          .add(Duration(minutes: range.endMinute));
      if (!end.isAfter(effectiveStart) || !start.isBefore(effectiveEnd)) {
        continue;
      }
      if (start.isBefore(effectiveStart)) {
        start = effectiveStart;
      }
      final clippedEnd = end.isAfter(effectiveEnd) ? effectiveEnd : end;
      if (start.isBefore(clippedEnd)) {
        windows.add((start: start, end: clippedEnd));
      }
    }
    windows.sort((left, right) => left.start.compareTo(right.start));
    return windows;
  }

  Future<List<({DateTime start, DateTime end, String label})>> _loadFixedBlocks(
    DateTime date,
    List<SchedulerRunLogEntry> logs,
  ) async {
    final events = await _eventRepo.getBlocksForDate(date);
    final blocks = <({DateTime start, DateTime end, String label})>[];
    for (final event in events) {
      if (event.status == 'CANCELLED') {
        continue;
      }
      final end = event.dtend ?? event.dtstart.add(const Duration(hours: 1));
      blocks.add((
        start: event.dtstart,
        end: end,
        label: '阻挡日程：${event.summary}',
      ));
      logs.add(
        SchedulerRunLogEntry(
          level: 'info',
          message: '已避让阻挡日程「${event.summary}」。',
          start: event.dtstart,
          end: end,
        ),
      );
    }
    return blocks;
  }

  DateTime? _findFreeSlot({
    required List<({DateTime start, DateTime end})> windows,
    required List<({DateTime start, DateTime end, String label})> occupied,
    required Duration duration,
  }) {
    for (final window in windows) {
      var cursor = window.start;
      for (final block in occupied) {
        if (!block.end.isAfter(window.start) ||
            !block.start.isBefore(window.end)) {
          continue;
        }
        final blockStart =
            block.start.isBefore(window.start) ? window.start : block.start;
        final blockEnd = block.end.isAfter(window.end) ? window.end : block.end;
        if (blockStart.isAfter(cursor) &&
            blockStart.difference(cursor) >= duration) {
          return cursor;
        }
        if (blockEnd.isAfter(cursor)) {
          cursor = _snapUp(blockEnd);
        }
      }
      if (window.end.difference(cursor) >= duration) {
        return cursor;
      }
    }
    return null;
  }

  List<({DateTime start, DateTime end})> _findSplitSuggestion({
    required List<({DateTime start, DateTime end})> windows,
    required List<({DateTime start, DateTime end, String label})> occupied,
    required Duration duration,
  }) {
    var remaining = duration;
    final segments = <({DateTime start, DateTime end})>[];
    for (final window in windows) {
      var cursor = window.start;
      for (final block in occupied) {
        if (!block.end.isAfter(window.start) ||
            !block.start.isBefore(window.end)) {
          continue;
        }
        final blockStart =
            block.start.isBefore(window.start) ? window.start : block.start;
        final blockEnd = block.end.isAfter(window.end) ? window.end : block.end;
        if (blockStart.isAfter(cursor)) {
          remaining = _takeSplitSegment(
            segments,
            cursor,
            blockStart,
            remaining,
          );
          if (remaining <= Duration.zero) {
            return segments;
          }
        }
        if (blockEnd.isAfter(cursor)) {
          cursor = _snapUp(blockEnd);
        }
      }
      if (window.end.isAfter(cursor)) {
        remaining = _takeSplitSegment(
          segments,
          cursor,
          window.end,
          remaining,
        );
        if (remaining <= Duration.zero) {
          return segments;
        }
      }
    }
    return remaining <= Duration.zero ? segments : const [];
  }

  Duration _takeSplitSegment(
    List<({DateTime start, DateTime end})> segments,
    DateTime start,
    DateTime end,
    Duration remaining,
  ) {
    final gap = end.difference(start);
    if (gap < const Duration(minutes: _slotMinutes)) {
      return remaining;
    }
    final length = gap < remaining ? gap : remaining;
    segments.add((start: start, end: start.add(length)));
    return remaining - length;
  }

  int _compareTasksForScheduling(TaskItem left, TaskItem right) {
    final priority = left.priorityLocal.compareTo(right.priorityLocal);
    if (priority != 0) {
      return priority;
    }
    final leftDue = left.due;
    final rightDue = right.due;
    if (leftDue == null && rightDue != null) {
      return 1;
    }
    if (leftDue != null && rightDue == null) {
      return -1;
    }
    if (leftDue != null && rightDue != null) {
      final due = leftDue.compareTo(rightDue);
      if (due != 0) {
        return due;
      }
    }
    final leftStart = left.dtstart;
    final rightStart = right.dtstart;
    if (leftStart == null && rightStart != null) {
      return 1;
    }
    if (leftStart != null && rightStart == null) {
      return -1;
    }
    if (leftStart != null && rightStart != null) {
      return leftStart.compareTo(rightStart);
    }
    return left.summary.compareTo(right.summary);
  }

  @visibleForTesting
  int debugCompareTasksForScheduling(TaskItem left, TaskItem right) {
    return _compareTasksForScheduling(left, right);
  }

  Future<void> _saveReport(SchedulerRunResult result) {
    return _db.setSetting(_lastRunReportKey, jsonEncode(result.toJson()));
  }

  DateTime _snapUp(DateTime value) {
    final dayStart = DateTime(value.year, value.month, value.day);
    final minutes = value.difference(dayStart).inMinutes;
    final snapped = ((minutes / _slotMinutes).ceil() * _slotMinutes);
    return dayStart.add(Duration(minutes: snapped));
  }

  int _snapDurationMinutes(int minutes) {
    if (minutes <= 0) {
      return 0;
    }
    return ((minutes / _slotMinutes).ceil() * _slotMinutes).toInt();
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$month-$day ${_formatTime(value)}';
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _SchedulerCandidate {
  const _SchedulerCandidate({
    required this.task,
    required this.evidence,
  });

  final TaskItem task;
  final SchedulerTaskEvidence evidence;
}

final schedulerEngineProvider = Provider<SchedulerEngine>((ref) {
  final taskRepo = ref.watch(taskRepositoryProvider);
  final eventRepo = ref.watch(eventRepositoryProvider);
  final db = ref.watch(databaseProvider);
  final workSchedule = ref.watch(weeklyWorkScheduleProvider);
  final segmentRepo = ref.watch(taskScheduleSegmentRepositoryProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  final actualLogs = ref.watch(actualActivityLogRepositoryProvider);
  final fusionRepo = ref.watch(activityFusionRepositoryProvider);
  return SchedulerEngine(
    taskRepo,
    eventRepo,
    db,
    workSchedule,
    segmentRepo,
    operationLogs,
    actualLogs,
    fusionRepo,
  );
});
