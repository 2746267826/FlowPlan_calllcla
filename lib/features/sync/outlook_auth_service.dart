import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum OutlookSyncMode {
  disabled,
  importOnly,
}

extension OutlookSyncModeX on OutlookSyncMode {
  String get storageValue {
    switch (this) {
      case OutlookSyncMode.disabled:
        return 'disabled';
      case OutlookSyncMode.importOnly:
        return 'import_only';
    }
  }

  String get label {
    switch (this) {
      case OutlookSyncMode.disabled:
        return '\u5173\u95ed\u540c\u6b65';
      case OutlookSyncMode.importOnly:
        return '\u4ec5\u4ece Outlook \u8bfb\u53d6';
    }
  }

  String get description {
    switch (this) {
      case OutlookSyncMode.disabled:
        return '\u4e0d\u62c9\u53d6 Outlook \u6570\u636e\uff0c\u4e5f\u4e0d\u4f1a\u6267\u884c\u4efb\u4f55\u540c\u6b65\u3002';
      case OutlookSyncMode.importOnly:
        return '\u53ea\u628a Outlook \u65e5\u5386\u8bfb\u53d6\u5230 FlowPlan\uff0c\u7edd\u4e0d\u4f1a\u56de\u5199\u6216\u4fee\u6539 Outlook\u3002';
    }
  }
}

OutlookSyncMode outlookSyncModeFromStorage(String? raw) {
  switch (raw) {
    case 'disabled':
      return OutlookSyncMode.disabled;
    case 'import_only':
    default:
      return OutlookSyncMode.importOnly;
  }
}

class OutlookConfig {
  const OutlookConfig({
    required this.clientId,
    required this.tenantId,
    this.redirectUri = 'http://localhost:8400/callback',
    this.scopes = const [
      'Calendars.Read',
      'User.Read',
      'offline_access',
    ],
  });

  final String clientId;
  final String tenantId;
  final String redirectUri;
  final List<String> scopes;

  String get authorizeUrl =>
      'https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize'
      '?client_id=$clientId'
      '&response_type=code'
      '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
      '&scope=${Uri.encodeQueryComponent(scopes.join(' '))}'
      '&response_mode=query';

  String get tokenUrl =>
      'https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token';
}

class AuthToken {
  const AuthToken({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
      };

  factory AuthToken.fromJson(Map<String, dynamic> json) => AuthToken(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String?,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

class OutlookAuthService {
  static const _tokenKey = 'outlook_auth_token';
  static const _configClientIdKey = 'outlook_client_id';
  static const _configTenantIdKey = 'outlook_tenant_id';
  static const _syncModeKey = 'outlook_sync_mode';

  static Future<void> saveConfig(String clientId, String tenantId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configClientIdKey, clientId);
    await prefs.setString(_configTenantIdKey, tenantId);
  }

  static Future<OutlookConfig?> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final clientId = prefs.getString(_configClientIdKey);
    final tenantId = prefs.getString(_configTenantIdKey);
    if (clientId == null ||
        clientId.isEmpty ||
        tenantId == null ||
        tenantId.isEmpty) {
      return null;
    }
    return OutlookConfig(clientId: clientId, tenantId: tenantId);
  }

  static Future<OutlookSyncMode> loadSyncMode() async {
    final prefs = await SharedPreferences.getInstance();
    return outlookSyncModeFromStorage(prefs.getString(_syncModeKey));
  }

  static Future<void> saveSyncMode(OutlookSyncMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_syncModeKey, mode.storageValue);
  }

  static Future<bool> launchAuth(OutlookConfig config) async {
    final uri = Uri.parse(config.authorizeUrl);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<AuthToken?> exchangeCode(OutlookConfig config, String code) async {
    try {
      final response = await http.post(
        Uri.parse(config.tokenUrl),
        body: {
          'client_id': config.clientId,
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': config.redirectUri,
          'scope': config.scopes.join(' '),
        },
      );

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = AuthToken(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String?,
        expiresAt: DateTime.now().add(
          Duration(seconds: data['expires_in'] as int? ?? 3600),
        ),
      );
      await _saveToken(token);
      return token;
    } catch (_) {
      return null;
    }
  }

  static Future<AuthToken?> refreshToken(OutlookConfig config) async {
    final current = await loadToken();
    if (current?.refreshToken == null) return null;

    try {
      final response = await http.post(
        Uri.parse(config.tokenUrl),
        body: {
          'client_id': config.clientId,
          'grant_type': 'refresh_token',
          'refresh_token': current!.refreshToken!,
          'scope': config.scopes.join(' '),
        },
      );

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final token = AuthToken(
        accessToken: data['access_token'] as String,
        refreshToken: data['refresh_token'] as String? ?? current.refreshToken,
        expiresAt: DateTime.now().add(
          Duration(seconds: data['expires_in'] as int? ?? 3600),
        ),
      );
      await _saveToken(token);
      return token;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getValidAccessToken(OutlookConfig config) async {
    var token = await loadToken();
    if (token == null) return null;
    if (token.isExpired) {
      token = await refreshToken(config);
    }
    return token?.accessToken;
  }

  static Future<AuthToken?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_tokenKey);
    if (json == null) return null;
    try {
      return AuthToken.fromJson(jsonDecode(json) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveToken(AuthToken token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, jsonEncode(token.toJson()));
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  static Future<bool> isAuthenticated() async {
    final token = await loadToken();
    return token != null;
  }
}
