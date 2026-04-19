// EventCalendars 表：事件日历本（如「工作」「个人」「节假日」）
import 'package:drift/drift.dart';

class EventCalendars extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // 工作、个人
  TextColumn get colorHex => text().withDefault(const Constant('#6B5EE4'))();
  TextColumn get description => text().nullable()();
  BoolColumn get isVisible => boolean().withDefault(const Constant(true))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  // 来源：local / caldav / outlook
  TextColumn get source => text().withDefault(const Constant('local'))();
  TextColumn get syncUrl => text().nullable()(); // CalDAV URL
  DateTimeColumn get createdAt => dateTime()();
}
