// TaskRepository：任务 CRUD + 监听流
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';

class TaskRepository {
  final AppDatabase _db;
  TaskRepository(this._db);

  // ── 监听所有任务（按优先级+截止时间排序）────────────────────────────────────
  Stream<List<TaskItem>> watchAll() => (_db.select(_db.taskItems)
        ..orderBy([
          (t) => OrderingTerm(expression: t.priorityLocal),
          (t) => OrderingTerm(expression: t.due, mode: OrderingMode.asc),
        ]))
      .watch();

  // ── 监听指定日期范围内有 dtstart 的任务（用于时间轴渲染）────────────────────
  Stream<List<TaskItem>> watchForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return (_db.select(_db.taskItems)
          ..where((t) =>
              t.dtstart.isBiggerOrEqualValue(start) &
              t.dtstart.isSmallerThanValue(end)))
        .watch();
  }

  // ── 监听指定清单的任务 ────────────────────────────────────────────────────
  Stream<List<TaskItem>> watchByList(int taskListId) =>
      (_db.select(_db.taskItems)
            ..where((t) => t.taskListId.equals(taskListId))
            ..orderBy([
              (t) => OrderingTerm(expression: t.priorityLocal),
              (t) => OrderingTerm(expression: t.due),
            ]))
          .watch();

  // ── 获取单个任务 ──────────────────────────────────────────────────────────
  Future<TaskItem?> getById(int id) =>
      (_db.select(_db.taskItems)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  // ── 创建任务 ──────────────────────────────────────────────────────────────
  Future<int> create(TaskItemsCompanion companion) =>
      _db.into(_db.taskItems).insert(companion);

  // ── 更新任务 ──────────────────────────────────────────────────────────────
  Future<bool> update(TaskItemsCompanion companion) =>
      _db.update(_db.taskItems).replace(companion);

  // ── 轻量局部更新：仅更新开始时间（拖拽移动）──────────────────────────────
  Future<void> updateDtstart(int id, DateTime dtstart) =>
      (_db.update(_db.taskItems)..where((t) => t.id.equals(id)))
          .write(TaskItemsCompanion(dtstart: Value(dtstart)));

  // ── 轻量局部更新：仅更新时长（底缘拉伸）──────────────────────────────────
  Future<void> updateDuration(int id, int durationMinutes) =>
      (_db.update(_db.taskItems)..where((t) => t.id.equals(id)))
          .write(TaskItemsCompanion(durationMinutes: Value(durationMinutes)));

  // ── 撤回收集箱：清除 dtstart（取消排期）──────────────────────────────────
  Future<void> clearDtstart(int id) =>
      (_db.update(_db.taskItems)..where((t) => t.id.equals(id)))
          .write(const TaskItemsCompanion(dtstart: Value(null)));

  // ── 删除任务 ──────────────────────────────────────────────────────────────
  Future<int> delete(int id) =>
      (_db.delete(_db.taskItems)..where((t) => t.id.equals(id))).go();

  // ── 标记完成 ──────────────────────────────────────────────────────────────
  Future<void> markCompleted(int id) async {
    await (_db.update(_db.taskItems)..where((t) => t.id.equals(id))).write(
      TaskItemsCompanion(
        status: const Value('COMPLETED'),
        completed: Value(DateTime.now()),
        percentComplete: const Value(100),
      ),
    );
  }

  // ── 批量更新排程结果（排程引擎调用）──────────────────────────────────────
  Future<void> batchUpdateSchedule(
      List<({int id, DateTime dtstart})> schedule) async {
    await _db.transaction(() async {
      for (final item in schedule) {
        await (_db.update(_db.taskItems)..where((t) => t.id.equals(item.id)))
            .write(TaskItemsCompanion(dtstart: Value(item.dtstart)));
      }
    });
  }

  // ── 获取所有待排程任务（isAutoScheduled=true，status=NEEDS-ACTION）────────
  Future<List<TaskItem>> getPendingForSchedule() => (_db.select(_db.taskItems)
        ..where((t) =>
            t.isAutoScheduled.equals(true) &
            t.status.equals('NEEDS-ACTION') &
            t.isLocked.equals(false)))
      .get();
}
