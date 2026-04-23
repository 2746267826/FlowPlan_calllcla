import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/app_database.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/providers/database_provider.dart';
import '../../shared/providers/settings_provider.dart';
import '../audit/data_operation_log_repository.dart';
import '../calendar/data/event_repository.dart';
import '../task/data/task_repository.dart';
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
    required this.scheduledTaskCount,
    required this.rescheduledTaskCount,
    required this.clearedTaskCount,
    required this.unscheduledTaskCount,
    required this.splitSuggestedTaskCount,
    required this.placements,
    required this.clearedTaskIds,
    required this.logEntries,
  });

  final DateTime date;
  final String planRunId;
  final String trigger;
  final DateTime effectiveStart;
  final int scheduledTaskCount;
  final int rescheduledTaskCount;
  final int clearedTaskCount;
  final int unscheduledTaskCount;
  final int splitSuggestedTaskCount;
  final List<SchedulerTaskPlacement> placements;
  final List<int> clearedTaskIds;
  final List<SchedulerRunLogEntry> logEntries;

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
        'scheduled_task_count': scheduledTaskCount,
        'rescheduled_task_count': rescheduledTaskCount,
        'cleared_task_count': clearedTaskCount,
        'unscheduled_task_count': unscheduledTaskCount,
        'split_suggested_task_count': splitSuggestedTaskCount,
        'placements': placements.map((placement) => placement.toJson()).toList(),
        'cleared_task_ids': clearedTaskIds,
        'log_entries': logEntries.map((entry) => entry.toJson()).toList(),
      };
}

class SchedulerTaskPlacement {
  const SchedulerTaskPlacement({
    required this.taskId,
    required this.taskSummary,
    required this.wasRescheduled,
    required this.isSplit,
    required this.segments,
  });

  final int taskId;
  final String taskSummary;
  final bool wasRescheduled;
  final bool isSplit;
  final List<SchedulerTaskSegmentPlan> segments;

  DateTime get dtstart => segments.first.start;

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'task_summary': taskSummary,
        'was_rescheduled': wasRescheduled,
        'is_split': isSplit,
        'segments': segments.map((segment) => segment.toJson()).toList(),
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
  );

  static const _lastRunReportKey = 'scheduler.last_run_report.v1';
  static const _slotMinutes = 15;

  final TaskRepository _taskRepo;
  final EventRepository _eventRepo;
  final AppDatabase _db;
  final WeeklyWorkSchedule _workSchedule;
  final TaskScheduleSegmentRepository _segmentRepo;
  final DataOperationLogRepository _operationLogs;

  Future<int> autoSchedule(DateTime date) async {
    final result = await autoScheduleDetailed(date);
    return result.scheduledTaskCount;
  }

  Future<SchedulerRunResult> autoScheduleDetailed(
    DateTime date, {
    DateTime? from,
    Set<int> forceMovableTaskIds = const <int>{},
    String trigger = 'manual_reschedule',
  }) async {
    final targetDate = DateTime(date.year, date.month, date.day);
    final planRunId = 'schedule-${DateTime.now().microsecondsSinceEpoch}';
    final logs = <SchedulerRunLogEntry>[];
    final effectiveStart = _effectiveStartForDate(targetDate, from: from);
    final windows = _buildWorkWindows(targetDate, effectiveStart);

    if (windows.isEmpty) {
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
        scheduledTaskCount: 0,
        rescheduledTaskCount: 0,
        clearedTaskCount: 0,
        unscheduledTaskCount: 0,
        splitSuggestedTaskCount: 0,
        placements: const <SchedulerTaskPlacement>[],
        clearedTaskIds: const <int>[],
        logEntries: logs,
      );
      await _saveReport(result);
      return result;
    }

    final blockers = await _loadFixedBlocks(targetDate, logs);
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
    final candidates = candidatesById.values.toList()
      ..sort(_compareTasksForScheduling);

    final placements = <SchedulerTaskPlacement>[];
    final scheduledIds = <int>{};
    final clearedIds = movableTaskIds.toSet();
    var splitPlacementCount = 0;

    for (final task in candidates) {
      final duration = Duration(minutes: task.durationMinutes);
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
    }

    clearedIds.removeAll(scheduledIds);

    final result = SchedulerRunResult(
      date: targetDate,
      planRunId: planRunId,
      trigger: trigger,
      effectiveStart: effectiveStart,
      scheduledTaskCount: placements.length,
      rescheduledTaskCount:
          placements.where((item) => item.wasRescheduled).length,
      clearedTaskCount: clearedIds.length,
      unscheduledTaskCount: candidates.length - placements.length,
      splitSuggestedTaskCount: splitPlacementCount,
      placements: placements,
      clearedTaskIds: clearedIds.toList(growable: false),
      logEntries: logs,
    );
    await _saveReport(result);
    return result;
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

  List<({DateTime start, DateTime end})> _buildWorkWindows(
    DateTime date,
    DateTime effectiveStart,
  ) {
    final ranges = _workSchedule.rangesForWeekday(date.weekday);
    final windows = <({DateTime start, DateTime end})>[];
    for (final range in ranges) {
      var start = DateTime(date.year, date.month, date.day)
          .add(Duration(minutes: range.startMinute));
      final end = DateTime(date.year, date.month, date.day)
          .add(Duration(minutes: range.endMinute));
      if (!end.isAfter(effectiveStart)) {
        continue;
      }
      if (start.isBefore(effectiveStart)) {
        start = effectiveStart;
      }
      if (start.isBefore(end)) {
        windows.add((start: start, end: end));
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
        if (!block.end.isAfter(window.start) || !block.start.isBefore(window.end)) {
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
        if (!block.end.isAfter(window.start) || !block.start.isBefore(window.end)) {
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

  Future<void> _saveReport(SchedulerRunResult result) {
    return _db.setSetting(_lastRunReportKey, jsonEncode(result.toJson()));
  }

  DateTime _snapUp(DateTime value) {
    final dayStart = DateTime(value.year, value.month, value.day);
    final minutes = value.difference(dayStart).inMinutes;
    final snapped = ((minutes / _slotMinutes).ceil() * _slotMinutes);
    return dayStart.add(Duration(minutes: snapped));
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

final schedulerEngineProvider = Provider<SchedulerEngine>((ref) {
  final taskRepo = ref.watch(taskRepositoryProvider);
  final eventRepo = ref.watch(eventRepositoryProvider);
  final db = ref.watch(databaseProvider);
  final workSchedule = ref.watch(weeklyWorkScheduleProvider);
  final segmentRepo = ref.watch(taskScheduleSegmentRepositoryProvider);
  final operationLogs = ref.watch(dataOperationLogRepositoryProvider);
  return SchedulerEngine(
    taskRepo,
    eventRepo,
    db,
    workSchedule,
    segmentRepo,
    operationLogs,
  );
});
