import '../database/app_database.dart';

class AuthTokenStore {
  AuthTokenStore(this._database);

  static const _accessTokenKey = 'server.auth.access_token';
  static const _refreshTokenKey = 'server.auth.refresh_token';

  final AppDatabase _database;

  Future<String?> readAccessToken() {
    return _database.getSetting(_accessTokenKey);
  }

  Future<String?> readRefreshToken() {
    return _database.getSetting(_refreshTokenKey);
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _database.setSetting(_accessTokenKey, accessToken);
    await _database.setSetting(_refreshTokenKey, refreshToken);
  }

  Future<void> clear() async {
    await _database.deleteSetting(_accessTokenKey);
    await _database.deleteSetting(_refreshTokenKey);
  }
}
