import 'package:drift/native.dart';
import 'package:flowplanv2/core/database/app_database.dart';

AppDatabase createTestDatabase() {
  return AppDatabase.forTesting(NativeDatabase.memory());
}
