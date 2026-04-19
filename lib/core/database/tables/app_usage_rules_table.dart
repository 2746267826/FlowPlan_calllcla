// AppUsageRules 表：Windows 应用→活动类别学习规则库
import 'package:drift/drift.dart';

class AppUsageRules extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get processName => text()(); // cursor.exe
  TextColumn get windowTitlePattern => text().nullable()(); // 可选：关键词匹配
  TextColumn get category => text()(); // 编程
  TextColumn get customLabel => text().nullable()(); // Flutter 开发
  IntColumn get hitCount => integer().withDefault(const Constant(0))(); // 命中次数
}
