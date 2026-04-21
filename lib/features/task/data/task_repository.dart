import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

class TaskRepository {
  final AppDatabase _db;
  TaskRepository(this._db);

  Stream<List<TaskItem>> _watchTasks({
    Expression<bool> Function($TaskItemsTable task, $TaskListsTable list)?
        filter,
    bool requireVisible = false,
  }) {
    final query = _db.select(_db.taskItems).join([
      innerJoin(
        _db.taskLists,
        _db.taskLists.id.equalsExp(_db.taskItems.taskListId),
      ),
    ]);

    var predicate = _db.taskLists.isArchived.equals(false);
    if (requireVisible) {
      predicate = predicate & _db.taskLists.isVisible.equals(true);
    }
    if (filter != null) {
      predicate = predicate & filter(_db.taskItems, _db.taskLists);
    }

    query.where(predicate);
    query.orderBy([
      OrderingTerm(expression: _db.taskItems.priorityLocal),
      OrderingTerm(
        expression: _db.taskItems.due,
        mode: OrderingMode.asc,
      ),
      OrderingTerm(expression: _db.taskItems.dtstart, mode: OrderingMode.asc),
    ]);

    return query.watch().map(
          (rows) => rows.map((row) => row.readTable(_db.taskItems)).toList(),
        );
  }

  Future<void> _ensureTaskListBinding(
    Value<int?> taskListId, {
    required bool requirePresent,
  }) async {
    if (!taskListId.present) {
      if (requirePresent) {
        throw StateError(
          '\u4efb\u52a1\u5fc5\u987b\u5f52\u5c5e\u4e8e\u4e00\u4e2a\u4efb\u52a1\u672c\u3002',
        );
      }
      return;
    }

    final id = taskListId.value;
    if (id == null) {
      throw StateError(
        '\u4efb\u52a1\u5fc5\u987b\u5f52\u5c5e\u4e8e\u4e00\u4e2a\u4efb\u52a1\u672c\u3002',
      );
    }

    final taskList = await (_db.select(_db.taskLists)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (taskList == null || taskList.isArchived) {
      throw StateError(
        '\u6240\u9009\u4efb\u52a1\u672c\u4e0d\u5b58\u5728\uff0c\u6216\u5df2\u5f52\u6863\u4e0d\u53ef\u7ee7\u7eed\u4f7f\u7528\u3002',
      );
    }
  }

  Stream<List<TaskItem>> watchAll() => _watchTasks(
        requireVisible: true,
      );

  Stream<List<TaskItem>> watchForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return _watchTasks(
      requireVisible: true,
      filter: (task, _) =>
          task.dtstart.isBiggerOrEqualValue(start) &
          task.dtstart.isSmallerThanValue(end),
    );
  }

  Stream<List<TaskItem>> watchByList(int taskListId) => _watchTasks(
        filter: (task, list) =>
            task.taskListId.equals(taskListId) & list.id.equals(taskListId),
      );

  Future<TaskItem?> getById(int id) =>
      (_db.select(_db.taskItems)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> create(TaskItemsCompanion companion) async {
    await _ensureTaskListBinding(companion.taskListId, requirePresent: true);
    return _db.into(_db.taskItems).insert(companion);
  }

  Future<bool> update(TaskItemsCompanion companion) async {
    await _ensureTaskListBinding(companion.taskListId, requirePresent: false);
    return _db.update(_db.taskItems).replace(companion);
  }

  Future<void> updateDtstart(int id, DateTime dtstart) =>
      (_db.update(_db.taskItems)..where((t) => t.id.equals(id)))
          .write(TaskItemsCompanion(dtstart: Value(dtstart)));

  Future<void> updateDuration(int id, int durationMinutes) =>
      (_db.update(_db.taskItems)..where((t) => t.id.equals(id)))
          .write(TaskItemsCompanion(durationMinutes: Value(durationMinutes)));

  Future<void> clearDtstart(int id) =>
      (_db.update(_db.taskItems)..where((t) => t.id.equals(id)))
          .write(const TaskItemsCompanion(dtstart: Value(null)));

  Future<int> delete(int id) =>
      (_db.delete(_db.taskItems)..where((t) => t.id.equals(id))).go();

  Future<void> markCompleted(int id) async {
    await (_db.update(_db.taskItems)..where((t) => t.id.equals(id))).write(
      TaskItemsCompanion(
        status: const Value('COMPLETED'),
        completed: Value(DateTime.now()),
        percentComplete: const Value(100),
      ),
    );
  }

  Future<void> batchUpdateSchedule(
    List<({int id, DateTime dtstart})> schedule,
  ) async {
    await _db.transaction(() async {
      for (final item in schedule) {
        await (_db.update(_db.taskItems)..where((t) => t.id.equals(item.id)))
            .write(TaskItemsCompanion(dtstart: Value(item.dtstart)));
      }
    });
  }

  Future<List<TaskItem>> getPendingForSchedule() async {
    final query = _db.select(_db.taskItems).join([
      innerJoin(
        _db.taskLists,
        _db.taskLists.id.equalsExp(_db.taskItems.taskListId),
      ),
    ]);
    query.where(
      _db.taskLists.isArchived.equals(false) &
          _db.taskItems.isAutoScheduled.equals(true) &
          _db.taskItems.status.equals('NEEDS-ACTION') &
          _db.taskItems.isLocked.equals(false),
    );
    query.orderBy([
      OrderingTerm(expression: _db.taskItems.priorityLocal),
      OrderingTerm(expression: _db.taskItems.due, mode: OrderingMode.asc),
    ]);
    final rows = await query.get();
    return rows.map((row) => row.readTable(_db.taskItems)).toList();
  }
}
