import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum OutlookSyncMode {
  paused,
  readOnly,
  bidirectional,
}

extension OutlookSyncModeX on OutlookSyncMode {
  String get storageValue {
    switch (this) {
      case OutlookSyncMode.paused:
        return 'paused';
      case OutlookSyncMode.readOnly:
        return 'read_only';
      case OutlookSyncMode.bidirectional:
        return 'bidirectional';
    }
  }

  String get label {
    switch (this) {
      case OutlookSyncMode.paused:
        return '\u6682\u505c\u540c\u6b65';
      case OutlookSyncMode.readOnly:
        return '\u53ea\u8bfb';
      case OutlookSyncMode.bidirectional:
        return '\u53cc\u5411\u540c\u6b65';
    }
  }

  String get description {
    switch (this) {
      case OutlookSyncMode.paused:
        return '\u4fdd\u7559 Outlook \u8d26\u53f7\u8fde\u63a5\u548c\u6620\u5c04\u5173\u7cfb\uff0c\u4f46\u6682\u65f6\u505c\u6b62\u62c9\u53d6\u548c\u63a8\u9001\u540c\u6b65\u3002';
      case OutlookSyncMode.readOnly:
        return '\u53ea\u4ece Outlook \u8bfb\u53d6\u65e5\u5386\u6570\u636e\u5230 FlowPlan\uff0c\u4e0d\u4f1a\u5411 Outlook \u5199\u5165\u4efb\u4f55\u53d8\u66f4\u3002';
      case OutlookSyncMode.bidirectional:
        return '\u5141\u8bb8 FlowPlan \u4e0e Outlook \u53cc\u5411\u540c\u6b65\uff0c\u4f46\u53ea\u4f1a\u5199\u5165 FlowPlan \u6258\u7ba1\u7684 Outlook \u4e13\u5c5e\u65e5\u5386\u672c\uff0c\u666e\u901a Outlook \u65e5\u5386\u9ed8\u8ba4\u4ecd\u4fdd\u6301\u53ea\u8bfb\u3002';
    }
  }

  bool get allowsPull => this != OutlookSyncMode.paused;

  bool get allowsPush => this == OutlookSyncMode.bidirectional;

  bool get requiresWritePermission => this == OutlookSyncMode.bidirectional;

  String get syncActionLabel {
    switch (this) {
      case OutlookSyncMode.paused:
        return '\u5df2\u6682\u505c\u540c\u6b65';
      case OutlookSyncMode.readOnly:
        return '\u7acb\u5373\u4ece Outlook \u8bfb\u53d6';
      case OutlookSyncMode.bidirectional:
        return '\u7acb\u5373\u540c\u6b65';
    }
  }

  String get authSummary {
    switch (this) {
      case OutlookSyncMode.paused:
        return '\u6682\u505c\u540c\u6b65\u4e0d\u4f1a\u6e05\u9664 Outlook \u6388\u6743\uff0c\u6062\u590d\u540e\u53ef\u7ee7\u7eed\u6cbf\u7528\u5df2\u6709\u6620\u5c04\u3002';
      case OutlookSyncMode.readOnly:
        return 'FlowPlan \u5f53\u524d\u4ee5 Outlook \u53ea\u8bfb\u6a21\u5f0f\u5de5\u4f5c\uff0c\u53ea\u4f1a\u628a\u65e5\u5386\u8bfb\u53d6\u5230 FlowPlan\uff0c\u4e0d\u4f1a\u5411\u4f60\u7684 Outlook \u5199\u5165\u3001\u4fee\u6539\u6216\u5220\u9664\u4efb\u4f55\u4e8b\u4ef6\u3002';
      case OutlookSyncMode.bidirectional:
        return 'FlowPlan \u4f1a\u7533\u8bf7 Outlook \u8bfb\u5199\u6743\u9650\uff0c\u4f46\u5199\u5165\u4ecd\u53ea\u9650 FlowPlan \u6258\u7ba1\u7684 Outlook \u4e13\u5c5e\u65e5\u5386\u672c\uff0c\u4e0d\u4f1a\u76f4\u63a5\u6539\u5199\u4f60\u7684\u666e\u901a Outlook \u65e5\u7a0b\u3002';
    }
  }
}

OutlookSyncMode outlookSyncModeFromStorage(String? raw) {
  switch (raw) {
    case 'disabled':
    case 'paused':
      return OutlookSyncMode.paused;
    case 'import_only':
    case 'read_only':
      return OutlookSyncMode.readOnly;
    case 'bidirectional':
      return OutlookSyncMode.bidirectional;
    default:
      return OutlookSyncMode.readOnly;
  }
}

class OutlookConfig {
  const OutlookConfig({
    required this.clientId,
    required this.tenantId,
    this.redirectUri = 'http://localhost:8400/callback',
    this.readOnlyScopes = const [
      'Calendars.Read',
      'User.Read',
      'offline_access',
    ],
    this.bidirectionalScopes = const [
      'Calendars.ReadWrite',
      'User.Read',
      'offline_access',
    ],
  });

  final String clientId;
  final String tenantId;
  final String redirectUri;
  final List<String> readOnlyScopes;
  final List<String> bidirectionalScopes;

  List<String> scopesForMode(OutlookSyncMode mode) =>
      mode.requiresWritePermission ? bidirectionalScopes : readOnlyScopes;

  String get authorizeUrl => authorizeUrlForMode(OutlookSyncMode.readOnly);

  String authorizeUrlForMode(OutlookSyncMode mode) =>
      'https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize'
      '?client_id=$clientId'
      '&response_type=code'
      '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
      '&scope=${Uri.encodeQueryComponent(scopesForMode(mode).join(' '))}'
      '&response_mode=query';

  String get tokenUrl =>
      'https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token';
}

class AuthToken {
  const AuthToken({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
    required this.grantedMode,
  });

  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
  final OutlookSyncMode grantedMode;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  bool supportsMode(OutlookSyncMode mode) =>
      grantedMode == OutlookSyncMode.bidirectional ||
      !mode.requiresWritePermission;

  Map<String, dynamic> toJson() => {
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toIso8601String(),
        'granted_mode': grantedMode.storageValue,
      };

  factory AuthToken.fromJson(Map<String, dynamic> json) => AuthToken(
        accessToken: json['access_token'] as String,
        refreshToken: json['refresh_token'] as String?,
        expiresAt: DateTime.parse(json['expires_at'] as String),
        grantedMode: outlookSyncModeFromStorage(json['granted_mode'] as String?),
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

  static Future<bool> launchAuth(
    OutlookConfig config, {
    required OutlookSyncMode requestedMode,
  }) async {
    final uri = Uri.parse(config.authorizeUrlForMode(requestedMode));
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<AuthToken?> exchangeCode(
    OutlookConfig config,
    String code, {
    required OutlookSyncMode requestedMode,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(config.tokenUrl),
        body: {
          'client_id': config.clientId,
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': config.redirectUri,
          'scope': config.scopesForMode(requestedMode).join(' '),
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
        grantedMode: requestedMode.requiresWritePermission
            ? OutlookSyncMode.bidirectional
            : OutlookSyncMode.readOnly,
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
          'scope': config.scopesForMode(current.grantedMode).join(' '),
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
        grantedMode: current.grantedMode,
      );
      await _saveToken(token);
      return token;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getValidAccessToken(
    OutlookConfig config, {
    OutlookSyncMode requestedMode = OutlookSyncMode.readOnly,
  }) async {
    var token = await loadToken();
    if (token == null) return null;
    if (!token.supportsMode(requestedMode)) {
      return null;
    }
    if (token.isExpired) {
      token = await refreshToken(config);
    }
    if (token == null || !token.supportsMode(requestedMode)) {
      return null;
    }
    return token.accessToken;
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

  static Future<bool> isAuthorizedForMode(OutlookSyncMode mode) async {
    final token = await loadToken();
    if (token == null) {
      return false;
    }
    return token.supportsMode(mode);
  }
}
