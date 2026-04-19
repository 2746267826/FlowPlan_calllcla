// EventRepository：日程 CRUD + 监听流
import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';

class EventRepository {
  final AppDatabase _db;
  EventRepository(this._db);

  // ── 监听指定日期范围内的事件（用于时间轴/周视图渲染）───────────────────────
  Stream<List<CalendarEvent>> watchForDateRange(DateTime start, DateTime end) {
    return (_db.select(_db.calendarEvents)
          ..where((e) =>
              e.dtstart.isBiggerOrEqualValue(start) &
              e.dtstart.isSmallerThanValue(end))
          ..orderBy([(e) => OrderingTerm(expression: e.dtstart)]))
        .watch();
  }

  // ── 监听指定日历本的事件 ───────────────────────────────────────────────────
  Stream<List<CalendarEvent>> watchByCalendar(int calendarId) =>
      (_db.select(_db.calendarEvents)
            ..where((e) => e.eventCalendarId.equals(calendarId))
            ..orderBy([(e) => OrderingTerm(expression: e.dtstart)]))
          .watch();

  // ── 监听所有可见日历本的事件（用于日视图）────────────────────────────────
  Stream<List<CalendarEvent>> watchVisibleForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));

    // 联合 EventCalendars.isVisible 过滤，仅返回可见日历本下的事件
    final query = _db.select(_db.calendarEvents).join([
      leftOuterJoin(
        _db.eventCalendars,
        _db.eventCalendars.id.equalsExp(_db.calendarEvents.eventCalendarId),
      ),
    ]);
    query.where(
      _db.calendarEvents.dtstart.isBiggerOrEqualValue(start) &
          _db.calendarEvents.dtstart.isSmallerThanValue(end) &
          (_db.calendarEvents.eventCalendarId.isNull() |
              _db.eventCalendars.isVisible.equals(true)),
    );
    query.orderBy([OrderingTerm.asc(_db.calendarEvents.dtstart)]);

    return query.watch().map(
        (rows) => rows.map((r) => r.readTable(_db.calendarEvents)).toList());
  }

  // ── 获取单个事件 ──────────────────────────────────────────────────────────
  Future<CalendarEvent?> getById(int id) =>
      (_db.select(_db.calendarEvents)..where((e) => e.id.equals(id)))
          .getSingleOrNull();

  // ── 创建事件 ──────────────────────────────────────────────────────────────
  Future<int> create(CalendarEventsCompanion companion) =>
      _db.into(_db.calendarEvents).insert(companion);

  // ── 更新事件 ──────────────────────────────────────────────────────────────
  Future<bool> update(CalendarEventsCompanion companion) =>
      _db.update(_db.calendarEvents).replace(companion);

  // ── 轻量局部更新：仅更新开始/结束时间（拖拽移动 + 拉伸调长）──────────────
  Future<void> updateTimes(int id, DateTime dtstart, DateTime dtend) =>
      (_db.update(_db.calendarEvents)..where((e) => e.id.equals(id)))
          .write(CalendarEventsCompanion(
        dtstart: Value(dtstart),
        dtend: Value(dtend),
      ));

  // ── 删除事件 ──────────────────────────────────────────────────────────────
  Future<int> delete(int id) =>
      (_db.delete(_db.calendarEvents)..where((e) => e.id.equals(id))).go();

  // ── 获取指定日期的阻挡块（供排程引擎使用）────────────────────────────────
  Future<List<CalendarEvent>> getBlocksForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return (_db.select(_db.calendarEvents)
          ..where((e) =>
              e.isBlock.equals(true) &
              e.dtstart.isBiggerOrEqualValue(start) &
              e.dtstart.isSmallerThanValue(end)))
        .get();
  }

  // ── 获取指定日期的所有事件（供排程引擎用作阻挡块）──────────────────────────
  Future<List<CalendarEvent>> getEventsForDate(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return (_db.select(_db.calendarEvents)
          ..where((e) =>
              e.dtstart.isBiggerOrEqualValue(start) &
              e.dtstart.isSmallerThanValue(end)))
        .get();
  }
}
