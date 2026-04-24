import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../audit/data_operation_log_repository.dart';

class TaskRepository {
  final AppDatabase _db;
  final DataOperationLogRepository? _operationLogRepository;
  TaskRepository(this._db, [this._operationLogRepository]);

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

  Future<List<TaskItem>> getByIds(Iterable<int> ids) async {
    final taskIds = ids.toSet();
    if (taskIds.isEmpty) {
      return const <TaskItem>[];
    }

    return (_db.select(_db.taskItems)..where((t) => t.id.isIn(taskIds))).get();
  }

  Future<List<TaskItem>> getByTaskListIds(Iterable<int> taskListIds) async {
    final listIds = taskListIds.toSet();
    if (listIds.isEmpty) {
      return const <TaskItem>[];
    }

    final query = _db.select(_db.taskItems)
      ..where((t) => t.taskListId.isIn(listIds))
      ..orderBy([
        (t) => OrderingTerm(expression: t.priorityLocal),
        (t) => OrderingTerm(expression: t.due, mode: OrderingMode.asc),
        (t) => OrderingTerm(expression: t.dtstart, mode: OrderingMode.asc),
      ]);
    return query.get();
  }

  Future<int> create(
    TaskItemsCompanion companion, {
    bool audit = true,
    String actor = 'user',
    String action = 'create',
    String? summary,
    Object? metadata,
  }) async {
    await _ensureTaskListBinding(companion.taskListId, requirePresent: true);
    final id = await _db.into(_db.taskItems).insert(companion);
    if (audit) {
      final created = await getById(id);
      if (created != null) {
        await _recordTaskOperation(
          actor: actor,
          action: action,
          task: created,
          summary:
              summary ?? '\u521b\u5efa\u4efb\u52a1\u300c${created.summary}\u300d',
          after: created.toJson(),
          metadata: metadata,
        );
      }
    }
    return id;
  }

  Future<bool> update(
    TaskItemsCompanion companion, {
    bool audit = true,
    String actor = 'user',
    String action = 'update',
    String? summary,
    Object? metadata,
  }) async {
    await _ensureTaskListBinding(companion.taskListId, requirePresent: false);
    final id = companion.id.present ? companion.id.value : null;
    final before = id == null ? null : await getById(id);
    final updated = await _db.update(_db.taskItems).replace(companion);
    if (audit && updated && id != null) {
      final after = await getById(id);
      final label =
          after?.summary ?? before?.summary ?? '\u672a\u547d\u540d\u4efb\u52a1';
      await _recordTaskOperation(
        actor: actor,
        action: action,
        task: after ?? before,
        summary: summary ?? '\u66f4\u65b0\u4efb\u52a1\u300c$label\u300d',
        before: before?.toJson(),
        after: after?.toJson(),
        metadata: metadata,
      );
    }
    return updated;
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

  Future<int> delete(
    int id, {
    bool audit = true,
    String actor = 'user',
    String action = 'delete',
    String? summary,
    Object? metadata,
  }) async {
    final before = audit ? await getById(id) : null;
    final deleted =
        await (_db.delete(_db.taskItems)..where((t) => t.id.equals(id))).go();
    if (audit && deleted > 0 && before != null) {
      await _recordTaskOperation(
        actor: actor,
        action: action,
        task: before,
        summary:
            summary ?? '\u5220\u9664\u4efb\u52a1\u300c${before.summary}\u300d',
        before: before.toJson(),
        metadata: metadata,
      );
    }
    return deleted;
  }

  Future<int> deleteByTaskListId(int taskListId) =>
      (_db.delete(_db.taskItems)
            ..where((t) => t.taskListId.equals(taskListId)))
          .go();

  Future<void> markCompleted(
    int id, {
    bool audit = true,
    String actor = 'user',
    String action = 'mark_completed',
    String? summary,
    Object? metadata,
  }) async {
    final before = audit ? await getById(id) : null;
    await (_db.update(_db.taskItems)..where((t) => t.id.equals(id))).write(
      TaskItemsCompanion(
        status: const Value('COMPLETED'),
        completed: Value(DateTime.now()),
        percentComplete: const Value(100),
      ),
    );
    if (audit) {
      final after = await getById(id);
      final task = after ?? before;
      if (task != null) {
        await _recordTaskOperation(
          actor: actor,
          action: action,
          task: task,
          summary:
              summary ?? '\u5b8c\u6210\u4efb\u52a1\u300c${task.summary}\u300d',
          before: before?.toJson(),
          after: after?.toJson(),
          metadata: metadata,
        );
      }
    }
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

  Future<void> batchApplySchedule({
    required List<({int id, DateTime dtstart})> scheduled,
    required Iterable<int> clearedTaskIds,
  }) async {
    await _db.transaction(() async {
      for (final id in clearedTaskIds.toSet()) {
        await (_db.update(_db.taskItems)..where((t) => t.id.equals(id)))
            .write(const TaskItemsCompanion(dtstart: Value(null)));
      }
      for (final item in scheduled) {
        await (_db.update(_db.taskItems)..where((t) => t.id.equals(item.id)))
            .write(TaskItemsCompanion(dtstart: Value(item.dtstart)));
      }
    });
  }

  Future<List<TaskItem>> getActiveScheduledForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final query = _db.select(_db.taskItems).join([
      innerJoin(
        _db.taskLists,
        _db.taskLists.id.equalsExp(_db.taskItems.taskListId),
      ),
    ]);
    query.where(
      _db.taskLists.isArchived.equals(false) &
          _db.taskItems.status.equals('NEEDS-ACTION') &
          _db.taskItems.dtstart.isBiggerOrEqualValue(start) &
          _db.taskItems.dtstart.isSmallerThanValue(end),
    );
    query.orderBy([
      OrderingTerm(expression: _db.taskItems.dtstart, mode: OrderingMode.asc),
      OrderingTerm(expression: _db.taskItems.priorityLocal),
    ]);
    final rows = await query.get();
    return rows.map((row) => row.readTable(_db.taskItems)).toList();
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

  Future<void> _recordTaskOperation({
    required String actor,
    required String action,
    required TaskItem? task,
    required String summary,
    Object? before,
    Object? after,
    Object? metadata,
  }) async {
    final operationLogs = _operationLogRepository;
    if (operationLogs == null || task == null) {
      return;
    }
    await operationLogs.record(
      actor: actor,
      action: action,
      entityType: 'task_item',
      entityId: task.id.toString(),
      summary: summary,
      before: before,
      after: after,
      metadata: metadata,
    );
  }
}
