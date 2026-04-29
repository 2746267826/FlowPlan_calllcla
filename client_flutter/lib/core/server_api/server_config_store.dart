import '../database/app_database.dart';

class ServerConfigStore {
  ServerConfigStore(this._database);

  static const _baseUrlKey = 'server.api.base_url';
  static const _oldReservedBaseUrl = 'http://localhost:3000/api';
  static const _defaultBaseUrl = 'http://localhost:3200/api';

  final AppDatabase _database;

  Future<Uri> readBaseUri() async {
    final raw = await _database.getSetting(_baseUrlKey);
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return Uri.parse(_defaultBaseUrl);
    }
    if (trimmed == _oldReservedBaseUrl) {
      return Uri.parse(_defaultBaseUrl);
    }
    return Uri.parse(trimmed);
  }

  Future<void> saveBaseUri(Uri uri) {
    return _database.setSetting(_baseUrlKey, uri.toString());
  }
}
