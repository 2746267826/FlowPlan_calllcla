import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class WebLocalStore {
  WebLocalStore._(this._preferences);

  static const _defaultUserId = '00000000-0000-4000-8000-000000000001';
  static const _oldReservedBaseUrl = 'http://localhost:3000/api';
  static const _defaultBaseUrl = 'http://localhost:3200/api';

  final SharedPreferences _preferences;

  static Future<WebLocalStore> load() async {
    final preferences = await SharedPreferences.getInstance();
    final store = WebLocalStore._(preferences);
    if (store.deviceId == null) {
      await store.setDeviceId(const Uuid().v4());
    }
    if (store.userId == null) {
      await store.setUserId(_defaultUserId);
    }
    if (store.baseUrl == null) {
      await store.setBaseUrl(_defaultBaseUrl);
    }
    return store;
  }

  String? get baseUrl {
    final value = _preferences.getString('web.server.base_url');
    return value == _oldReservedBaseUrl ? _defaultBaseUrl : value;
  }
  String? get accessToken => _preferences.getString('web.auth.access_token');
  String? get refreshToken => _preferences.getString('web.auth.refresh_token');
  String? get userId => _preferences.getString('web.user_id');
  String? get deviceId => _preferences.getString('web.device_id');
  String? get lastBootstrapJson =>
      _preferences.getString('web.last_bootstrap_json');
  String? get uiStateJson => _preferences.getString('web.ui_state_json');

  Future<void> setBaseUrl(String value) async {
    await _preferences.setString('web.server.base_url', _normalizeBaseUrl(value));
  }

  Future<void> setTokens({
    required String? accessToken,
    required String? refreshToken,
  }) async {
    if (accessToken == null || accessToken.isEmpty) {
      await _preferences.remove('web.auth.access_token');
    } else {
      await _preferences.setString('web.auth.access_token', accessToken);
    }
    if (refreshToken == null || refreshToken.isEmpty) {
      await _preferences.remove('web.auth.refresh_token');
    } else {
      await _preferences.setString('web.auth.refresh_token', refreshToken);
    }
  }

  Future<void> setUserId(String value) async {
    await _preferences.setString('web.user_id', value);
  }

  Future<void> setDeviceId(String value) async {
    await _preferences.setString('web.device_id', value);
  }

  Future<void> setLastBootstrap(Map<String, dynamic> value) async {
    await _preferences.setString('web.last_bootstrap_json', jsonEncode(value));
  }

  Future<void> setUiState(Map<String, dynamic> value) async {
    await _preferences.setString('web.ui_state_json', jsonEncode(value));
  }

  Map<String, dynamic>? readLastBootstrap() {
    final raw = lastBootstrapJson;
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  static String _normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
