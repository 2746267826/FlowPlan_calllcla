// TaskLists 表：任务清单（如「收件箱」「工作」「学习」）
// 与 EventCalendars 完全分离；Projects 是项目管理，TaskLists 是日历视角的分组
import 'package:drift/drift.dart';

class TaskLists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // 收件箱、工作、学习
  TextColumn get colorHex => text().withDefault(const Constant('#0EA8A0'))();
  TextColumn get emoji => text().nullable()(); // 可选 emoji 图标
  BoolColumn get isVisible => boolean().withDefault(const Constant(true))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
}
