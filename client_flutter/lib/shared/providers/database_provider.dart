// 全局共享 Provider：数据库实例
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../core/database/app_database.dart';

part 'database_provider.g.dart';

@Riverpod(keepAlive: true)
AppDatabase database(DatabaseRef ref) {
  // 由 main.dart 通过 overrideWithValue 注入
  throw UnimplementedError('数据库未初始化，请在 main() 中注入');
}
