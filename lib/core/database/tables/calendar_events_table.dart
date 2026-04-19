// CalendarEvents 表 v2：新增 eventCalendarId（事件日历本外键）
import 'package:drift/drift.dart';

class CalendarEvents extends Table {
  // === RFC 5545 VEVENT 标准字段 ===
  IntColumn get id => integer().autoIncrement()();
  TextColumn get uid => text()();
  DateTimeColumn get dtstamp => dateTime()();
  TextColumn get summary => text()();
  TextColumn get description => text().nullable()();
  TextColumn get location => text().nullable()();
  DateTimeColumn get dtstart => dateTime()();
  DateTimeColumn get dtend => dateTime().nullable()();
  TextColumn get rrule => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('CONFIRMED'))();
  TextColumn get transp => text().withDefault(const Constant('OPAQUE'))();

  // === X-APP 扩展字段 ===
  TextColumn get source => text().withDefault(const Constant('local'))();
  // 事件日历本 ID（关联 EventCalendars 表，与任务清单完全分离）
  IntColumn get eventCalendarId => integer().nullable()();
  TextColumn get colorHex => text().withDefault(const Constant('#6B5EE4'))();
  BoolColumn get isBlock => boolean().withDefault(const Constant(false))();
}
