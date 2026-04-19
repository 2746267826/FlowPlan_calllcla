// SchedulerEngine：贪心自动排程算法
// 按优先级排序未排程任务，避开已有日程，见缝插针填入空闲时段
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/app_providers.dart';
import '../task/data/task_repository.dart';
import '../calendar/data/event_repository.dart';

class SchedulerEngine {
  final TaskRepository _taskRepo;
  final EventRepository _eventRepo;

  SchedulerEngine(this._taskRepo, this._eventRepo);

  /// 对指定日期执行一键重排
  /// 1. 获取当天已有的日程事件（作为不可移动的阻挡块）
  /// 2. 获取所有待排程任务（未排、未完成、未锁定）
  /// 3. 按优先级排序后贪心填充空闲时段
  /// 4. 批量更新所有被排入的任务 dtstart
  Future<int> autoSchedule(DateTime date) async {
    // 工作时间范围（可配置）
    const int workStartHour = 8;
    const int workEndHour = 22;
    const int slotMinutes = 15; // 最小排程粒度

    final dayStart = DateTime(date.year, date.month, date.day, workStartHour);
    final dayEnd = DateTime(date.year, date.month, date.day, workEndHour);

    // 如果是今天且当前时间已超过 workStartHour，则从当前时间开始（向上取整到15分）
    final now = DateTime.now();
    DateTime effectiveStart = dayStart;
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      if (now.isAfter(dayStart)) {
        // 使用 Duration 计算避免 minute>=60 的構造溢出
        final totalMins = now.hour * 60 + now.minute;
        final snappedMins = ((totalMins / slotMinutes).ceil() * slotMinutes);
        effectiveStart = DateTime(now.year, now.month, now.day)
            .add(Duration(minutes: snappedMins));
        if (effectiveStart.isAfter(dayEnd)) return 0;
      }
    }

    // 1. 获取当天所有日程事件（均作为不可移动的阻挡块）
    final events = await _eventRepo.getEventsForDate(date);

    // 构建已占用区间列表
    final List<({DateTime start, DateTime end})> occupied = [];
    for (final e in events) {
      final eEnd = e.dtend ?? e.dtstart.add(const Duration(hours: 1));
      occupied.add((start: e.dtstart, end: eEnd));
    }
    // 也排除当天已排程的任务
    final allTasks = await _taskRepo.getPendingForSchedule();
    // 但只要未排程的（dtstart == null）
    // 已排程的任务也要作为阻挡块
    final scheduledTasks = allTasks
        .where((t) =>
            t.dtstart != null &&
            t.dtstart!.isAfter(dayStart.subtract(const Duration(hours: 1))) &&
            t.dtstart!.isBefore(dayEnd))
        .toList();
    for (final t in scheduledTasks) {
      occupied.add((
        start: t.dtstart!,
        end: t.dtstart!.add(Duration(minutes: t.durationMinutes)),
      ));
    }

    // 按开始时间排序
    occupied.sort((a, b) => a.start.compareTo(b.start));

    // 2. 获取待排程任务（dtstart == null, status = NEEDS-ACTION）
    final pendingTasks = allTasks.where((t) => t.dtstart == null).toList();

    // 按优先级排序（1高 > 2中 > 3低），同优先级按截止时间排
    pendingTasks.sort((a, b) {
      final pCmp = a.priorityLocal.compareTo(b.priorityLocal);
      if (pCmp != 0) return pCmp;
      if (a.due == null && b.due == null) return 0;
      if (a.due == null) return 1;
      if (b.due == null) return -1;
      return a.due!.compareTo(b.due!);
    });

    // 3. 贪心填充
    final List<({int id, DateTime dtstart})> schedule = [];

    for (final task in pendingTasks) {
      final duration = Duration(minutes: task.durationMinutes);
      final slot = _findFreeSlot(
        effectiveStart,
        dayEnd,
        duration,
        occupied,
      );

      if (slot != null) {
        schedule.add((id: task.id, dtstart: slot));
        // 将新占据的时间段也加入 occupied 以防后续任务重叠
        occupied.add((start: slot, end: slot.add(duration)));
        occupied.sort((a, b) => a.start.compareTo(b.start));
      }
    }

    // 4. 批量写入
    if (schedule.isNotEmpty) {
      await _taskRepo.batchUpdateSchedule(schedule);
    }

    return schedule.length;
  }

  /// 在 [rangeStart, rangeEnd] 范围内找到第一个能容纳 duration 的空闲时段
  DateTime? _findFreeSlot(
    DateTime rangeStart,
    DateTime rangeEnd,
    Duration duration,
    List<({DateTime start, DateTime end})> occupied,
  ) {
    DateTime cursor = rangeStart;

    for (final block in occupied) {
      // 空隙 = [cursor, block.start)
      if (block.start.isAfter(cursor)) {
        final gap = block.start.difference(cursor);
        if (gap >= duration) {
          return cursor; // 找到足够大的空闲
        }
      }
      // 将光标推过当前阻挡块
      if (block.end.isAfter(cursor)) {
        cursor = block.end;
      }
    }

    // 检查最后一个阻挡块之后到 rangeEnd 的空隙
    if (cursor.isBefore(rangeEnd)) {
      final remaining = rangeEnd.difference(cursor);
      if (remaining >= duration) {
        return cursor;
      }
    }

    return null; // 今天放不下了
  }
}

// ── Provider ────────────────────────────────────────────────────────────────
final schedulerEngineProvider = Provider<SchedulerEngine>((ref) {
  final taskRepo = ref.watch(taskRepositoryProvider);
  final eventRepo = ref.watch(eventRepositoryProvider);
  return SchedulerEngine(taskRepo, eventRepo);
});
