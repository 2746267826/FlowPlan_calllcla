// TimeBlocks 表：固定时间阻挡（睡眠/三餐等）
import 'package:drift/drift.dart';

class TimeBlocks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()(); // 早餐、午休、睡眠
  IntColumn get startHour => integer()(); // 开始小时 0-23
  IntColumn get startMinute => integer().withDefault(const Constant(0))();
  IntColumn get endHour => integer()();
  IntColumn get endMinute => integer().withDefault(const Constant(0))();
  TextColumn get weekdays =>
      text().withDefault(const Constant('[1,2,3,4,5,6,7]'))(); // JSON数组，1=周一
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  TextColumn get colorHex => text().withDefault(const Constant('#E0E0E0'))();
  TextColumn get emoji => text().withDefault(const Constant('🔒'))();
}
