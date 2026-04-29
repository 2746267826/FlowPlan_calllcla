import '../database/app_database.dart';

class SyncCursorStore {
  SyncCursorStore(this._database);

  static const _pullCursorKey = 'server.sync.pull_cursor';
  static const _lastPullAtKey = 'server.sync.last_pull_at';
  static const _lastPushAtKey = 'server.sync.last_push_at';

  final AppDatabase _database;

  Future<String?> readPullCursor() {
    return _database.getSetting(_pullCursorKey);
  }

  Future<void> savePullCursor(String cursor) {
    return _database.setSetting(_pullCursorKey, cursor);
  }

  Future<DateTime?> readLastPullAt() async {
    final raw = await _database.getSetting(_lastPullAtKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<DateTime?> readLastPushAt() async {
    final raw = await _database.getSetting(_lastPushAtKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> markPulledAt(DateTime time) {
    return _database.setSetting(_lastPullAtKey, time.toIso8601String());
  }

  Future<void> markPushedAt(DateTime time) {
    return _database.setSetting(_lastPushAtKey, time.toIso8601String());
  }
}
