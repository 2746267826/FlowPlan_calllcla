import 'package:drift/drift.dart';

QueryExecutor openAppDatabaseConnection() {
  throw UnsupportedError('No database connection implementation available.');
}

Future<String> resolveAppDatabasePathForDisplay() async {
  return 'unsupported';
}

Future<void> exportAppDatabase(GeneratedDatabase database, String targetPath) async {
  throw UnsupportedError('Database export is not available on this platform.');
}
