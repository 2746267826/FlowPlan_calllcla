// Tags 表：颜色标签
import 'package:drift/drift.dart';

class Tags extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get colorHex => text()(); // #0EA8A0
  TextColumn get iconName => text().nullable()();
}
