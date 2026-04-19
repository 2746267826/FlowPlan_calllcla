// Outlook OAuth2 认证服务 + Token 管理
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Outlook OAuth2 配置
class OutlookConfig {
  final String clientId;
  final String tenantId;
  final String redirectUri;
  final List<String> scopes;

  const OutlookConfig({
    required this.clientId,
    required this.tenantId,
    this.redirectUri = 'http://localhost:8400/callback',
    this.scopes = const [
      'Calendars.ReadWrite',
      'User.Read',
      'offline_access',
    ],
  });

  String get authorizeUrl =>
      'https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize'
      '?client_id=$clientId'
      '&response_type=code'
      '&redirect_uri=${Uri.encodeComponent(redirectUri)}'
      '&scope=${scopes.join(' ')}'
      '&response_mode=query';

  String get tokenUrl =>
      'https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token';
}

/// Token 数据
class AuthToken {
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;

  const AuthToken({
    required this.accessToken,
    this.refreshToken,
    required this.expiresAt,
  });

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

  /// 保存 OAuth 配置到 SharedPreferences
  static Future<void> saveConfig(String clientId, String tenantId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configClientIdKey, clientId);
    await prefs.setString(_configTenantIdKey, tenantId);
  }

  /// 读取已保存的配置
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

  /// 打开浏览器进行 OAuth 授权
  static Future<bool> launchAuth(OutlookConfig config) async {
    final uri = Uri.parse(config.authorizeUrl);
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// 用授权码换取 Token
  static Future<AuthToken?> exchangeCode(
      OutlookConfig config, String code) async {
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

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = AuthToken(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'],
          expiresAt:
              DateTime.now().add(Duration(seconds: data['expires_in'] ?? 3600)),
        );
        await _saveToken(token);
        return token;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 刷新 Token
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

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = AuthToken(
          accessToken: data['access_token'],
          refreshToken: data['refresh_token'] ?? current.refreshToken,
          expiresAt:
              DateTime.now().add(Duration(seconds: data['expires_in'] ?? 3600)),
        );
        await _saveToken(token);
        return token;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// 获取有效的 Access Token（自动刷新）
  static Future<String?> getValidAccessToken(OutlookConfig config) async {
    var token = await loadToken();
    if (token == null) return null;

    if (token.isExpired) {
      token = await refreshToken(config);
    }

    return token?.accessToken;
  }

  /// 加载保存的 token
  static Future<AuthToken?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_tokenKey);
    if (json == null) return null;
    try {
      return AuthToken.fromJson(jsonDecode(json));
    } catch (_) {
      return null;
    }
  }

  /// 保存 token
  static Future<void> _saveToken(AuthToken token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, jsonEncode(token.toJson()));
  }

  /// 登出：清除 token
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  /// 检查是否已认证
  static Future<bool> isAuthenticated() async {
    final token = await loadToken();
    return token != null;
  }
}
