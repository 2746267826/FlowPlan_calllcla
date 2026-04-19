// CalendarBooksRepository：任务清单 + 事件日历本管理
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';

class CalendarBooksRepository {
  final AppDatabase _db;
  CalendarBooksRepository(this._db);

  // ──────────────────────────── 事件日历本 ────────────────────────────────────

  Stream<List<EventCalendar>> watchAllEventCalendars() =>
      (_db.select(_db.eventCalendars)
            ..orderBy([(c) => OrderingTerm(expression: c.name)]))
          .watch();

  Future<List<EventCalendar>> getAllEventCalendars() =>
      _db.select(_db.eventCalendars).get();

  Future<int> createEventCalendar(EventCalendarsCompanion companion) =>
      _db.into(_db.eventCalendars).insert(companion);

  Future<bool> updateEventCalendar(EventCalendarsCompanion companion) =>
      _db.update(_db.eventCalendars).replace(companion);

  Future<int> deleteEventCalendar(int id) =>
      (_db.delete(_db.eventCalendars)..where((c) => c.id.equals(id))).go();

  Future<void> toggleEventCalendarVisible(int id, bool visible) async {
    await (_db.update(_db.eventCalendars)..where((c) => c.id.equals(id)))
        .write(EventCalendarsCompanion(isVisible: Value(visible)));
  }

  // ──────────────────────────── 任务清单 ──────────────────────────────────────

  Stream<List<TaskList>> watchAllTaskLists() => (_db.select(_db.taskLists)
        ..where((t) => t.isArchived.equals(false))
        ..orderBy([(t) => OrderingTerm(expression: t.name)]))
      .watch();

  Future<List<TaskList>> getAllTaskLists() =>
      (_db.select(_db.taskLists)..where((t) => t.isArchived.equals(false)))
          .get();

  Future<int> createTaskList(TaskListsCompanion companion) =>
      _db.into(_db.taskLists).insert(companion);

  Future<bool> updateTaskList(TaskListsCompanion companion) =>
      _db.update(_db.taskLists).replace(companion);

  Future<void> archiveTaskList(int id) async {
    await (_db.update(_db.taskLists)..where((t) => t.id.equals(id)))
        .write(const TaskListsCompanion(isArchived: Value(true)));
  }

  Future<void> toggleTaskListVisible(int id, bool visible) async {
    await (_db.update(_db.taskLists)..where((t) => t.id.equals(id)))
        .write(TaskListsCompanion(isVisible: Value(visible)));
  }
}
