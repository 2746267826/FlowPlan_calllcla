// ignore_for_file: deprecated_member_use

import 'package:drift/drift.dart';
import 'package:drift/web.dart';

QueryExecutor openAppDatabaseConnection() {
  return WebDatabase('flowplan_web');
}

Future<String> resolveAppDatabasePathForDisplay() async {
  return '浏览器 IndexedDB：flowplan_web';
}

Future<void> exportAppDatabase(GeneratedDatabase database, String targetPath) async {
  throw UnsupportedError('Web 端暂不支持直接导出 SQLite 文件。');
}
