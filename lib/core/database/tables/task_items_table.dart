// TaskItems 表：遵循 iCalendar RFC 5545 VTODO 标准（v2: 新增 rrule, taskListId）
import 'package:drift/drift.dart';

class TaskItems extends Table {
  // === RFC 5545 VTODO 标准字段 ===
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uid => text()();
  DateTimeColumn get dtstamp => dateTime()();
  TextColumn get summary => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get dtstart => dateTime().nullable()();
  DateTimeColumn get due => dateTime().nullable()();
  DateTimeColumn get completed => dateTime().nullable()();
  IntColumn get priority => integer().withDefault(const Constant(0))();
  TextColumn get status => text().withDefault(const Constant('NEEDS-ACTION'))();
  IntColumn get percentComplete => integer().withDefault(const Constant(0))();
  TextColumn get categories => text().withDefault(const Constant('[]'))();
  // RFC 5545 RRULE：重复规则（任务同样支持，如每日习惯）
  TextColumn get rrule => text().nullable()();

  // === X-APP 扩展字段 ===
  IntColumn get durationMinutes => integer().withDefault(const Constant(60))();
  BoolColumn get isSplittable => boolean().withDefault(const Constant(false))();
  IntColumn get priorityLocal =>
      integer().withDefault(const Constant(2))(); // 1高/2中/3低
  BoolColumn get isAutoScheduled =>
      boolean().withDefault(const Constant(true))();
  // 任务清单 ID（关联 TaskLists 表，与 Events 的 eventCalendarId 完全分离）
  IntColumn get taskListId => integer().nullable()();
  TextColumn get tagId => text().nullable()();
  BoolColumn get isLocked => boolean().withDefault(const Constant(false))();
  IntColumn get reminderMinutesBefore =>
      integer().withDefault(const Constant(15))();
}
