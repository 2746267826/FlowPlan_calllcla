import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'outlook_oauth_config.dart';

int? _coerceInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

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
        return '\u53ea\u4ece Outlook \u8bfb\u53d6\u65e5\u5386\u6570\u636e\u5230 FlowPlanV2\uff0c\u4e0d\u4f1a\u5411 Outlook \u5199\u5165\u4efb\u4f55\u53d8\u66f4\u3002';
      case OutlookSyncMode.bidirectional:
        return '\u5141\u8bb8 FlowPlanV2 \u4e0e Outlook \u53cc\u5411\u540c\u6b65\uff0c\u4f46\u5199\u5165\u4ecd\u53ea\u9650 FlowPlanV2 \u6258\u7ba1\u7684 Outlook \u4e13\u5c5e\u65e5\u5386\u672c\u3002';
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
      case OutlookSyncMode.bidirectional:
        return '\u624b\u52a8\u540c\u6b65 Outlook \u65e5\u5386';
    }
  }

  String get authSummary {
    switch (this) {
      case OutlookSyncMode.paused:
        return '\u5f53\u524d\u4fdd\u6301 Outlook \u8fde\u63a5\uff0c\u4f46\u4e0d\u4f1a\u81ea\u52a8\u8bfb\u5199\u4efb\u4f55 Outlook \u6570\u636e\u3002';
      case OutlookSyncMode.readOnly:
        return '\u5f53\u524d\u53ea\u4f1a\u8bfb\u53d6 Outlook \u65e5\u5386\u5230 FlowPlanV2\uff0c\u4e0d\u4f1a\u5199\u56de Outlook\u3002';
      case OutlookSyncMode.bidirectional:
        return '\u5f53\u524d\u5141\u8bb8 FlowPlanV2 \u5728\u4eba\u5de5\u786e\u8ba4\u548c\u53d7\u63a7\u5bb9\u5668\u8303\u56f4\u5185\u4e0e Outlook \u53cc\u5411\u540c\u6b65\u3002';
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
  });

  final String clientId;

  String get authority => OutlookOAuthPlatformConfig.authority;

  String get authorizeUrl => OutlookOAuthPlatformConfig.authorizeEndpoint;

  String get tokenUrl => OutlookOAuthPlatformConfig.tokenEndpoint;

  String get redirectUri => OutlookOAuthPlatformConfig.redirectUri;

  List<String> get scopes => OutlookOAuthPlatformConfig.scopes;

  String get scopeString => OutlookOAuthPlatformConfig.scopeString;
}

class AuthToken {
  const AuthToken({
    required this.accessToken,
    this.refreshToken,
    required this.expiresInSeconds,
    required this.obtainedAt,
    required this.expiresAt,
    required this.grantedMode,
    required this.scope,
  });

  final String accessToken;
  final String? refreshToken;
  final int expiresInSeconds;
  final DateTime obtainedAt;
  final DateTime expiresAt;
  final OutlookSyncMode grantedMode;
  final String scope;

  bool get isExpired =>
      DateTime.now().isAfter(expiresAt.subtract(const Duration(minutes: 1)));

  bool supportsMode(OutlookSyncMode mode) =>
      (grantedMode == OutlookSyncMode.bidirectional && _scopeAllowsWrite) ||
      !mode.requiresWritePermission;

  bool get _scopeAllowsWrite {
    final normalizedScopes = scope
        .split(RegExp(r'\s+'))
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    return normalizedScopes.contains('calendars.readwrite');
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_in': expiresInSeconds,
        'obtained_at': obtainedAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'granted_mode': grantedMode.storageValue,
        'scope': scope,
      };

  factory AuthToken.fromJson(Map<String, dynamic> json) {
    final expiresAt = DateTime.tryParse(json['expires_at'] as String? ?? '') ??
        DateTime.now().add(
          Duration(seconds: _coerceInt(json['expires_in']) ?? 3600),
        );
    final obtainedAt =
        DateTime.tryParse(json['obtained_at'] as String? ?? '') ??
            expiresAt.subtract(
              Duration(seconds: _coerceInt(json['expires_in']) ?? 3600),
            );
    return AuthToken(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiresInSeconds: _coerceInt(json['expires_in']) ??
          expiresAt.difference(obtainedAt).inSeconds,
      obtainedAt: obtainedAt,
      expiresAt: expiresAt,
      grantedMode: outlookSyncModeFromStorage(json['granted_mode'] as String?),
      scope: (json['scope'] as String?)?.trim().isNotEmpty == true
          ? (json['scope'] as String).trim()
          : OutlookOAuthPlatformConfig.scopeString,
    );
  }

  factory AuthToken.fromTokenResponse(
    Map<String, dynamic> json, {
    AuthToken? previousToken,
  }) {
    final obtainedAt = DateTime.now();
    final expiresInSeconds = _coerceInt(json['expires_in']) ?? 3600;
    final scope = (json['scope'] as String?)?.trim().isNotEmpty == true
        ? (json['scope'] as String).trim()
        : OutlookOAuthPlatformConfig.scopeString;
    return AuthToken(
      accessToken: json['access_token'] as String,
      refreshToken:
          (json['refresh_token'] as String?) ?? previousToken?.refreshToken,
      expiresInSeconds: expiresInSeconds,
      obtainedAt: obtainedAt,
      expiresAt: obtainedAt.add(Duration(seconds: expiresInSeconds)),
      grantedMode: _grantedModeFromScope(scope),
      scope: scope,
    );
  }

  static OutlookSyncMode _grantedModeFromScope(String scope) {
    final normalizedScopes = scope
        .split(RegExp(r'\s+'))
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    return normalizedScopes.contains('calendars.readwrite')
        ? OutlookSyncMode.bidirectional
        : OutlookSyncMode.readOnly;
  }
}

class OutlookPendingAuthSession {
  const OutlookPendingAuthSession({
    required this.clientId,
    required this.codeVerifier,
    required this.state,
    required this.requestedMode,
    required this.createdAt,
  });

  final String clientId;
  final String codeVerifier;
  final String state;
  final OutlookSyncMode requestedMode;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'client_id': clientId,
        'code_verifier': codeVerifier,
        'state': state,
        'requested_mode': requestedMode.storageValue,
        'created_at': createdAt.toIso8601String(),
      };

  factory OutlookPendingAuthSession.fromJson(Map<String, dynamic> json) {
    return OutlookPendingAuthSession(
      clientId: (json['client_id'] as String? ?? '').trim(),
      codeVerifier: (json['code_verifier'] as String? ?? '').trim(),
      state: (json['state'] as String? ?? '').trim(),
      requestedMode:
          outlookSyncModeFromStorage(json['requested_mode'] as String?),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class OutlookAuthException implements Exception {
  const OutlookAuthException({
    required this.code,
    required this.userMessage,
    this.debugMessage,
    this.statusCode,
  });

  final String code;
  final String userMessage;
  final String? debugMessage;
  final int? statusCode;

  @override
  String toString() => userMessage;
}

class _ParsedAuthorizationInput {
  const _ParsedAuthorizationInput({
    required this.code,
    this.state,
  });

  final String code;
  final String? state;
}

class OutlookNetworkDiagnostics {
  const OutlookNetworkDiagnostics({
    required this.canResolveMicrosoftHost,
    required this.canReachMicrosoftServer,
    this.resolvedAddresses = const <String>[],
    this.failureReason,
  });

  final bool canResolveMicrosoftHost;
  final bool canReachMicrosoftServer;
  final List<String> resolvedAddresses;
  final String? failureReason;

  bool get isReady => canResolveMicrosoftHost && canReachMicrosoftServer;
}

typedef OutlookNetworkDiagnosticsRunner = Future<OutlookNetworkDiagnostics>
    Function();
typedef OutlookTokenPost = Future<http.Response> Function(
  Uri url, {
  Map<String, String>? headers,
  Object? body,
  Encoding? encoding,
});
typedef OutlookAddressLookup = Future<List<InternetAddress>> Function(
  String host,
);
typedef OutlookHttpClientFactory = HttpClient Function();

class OutlookAuthService {
  static const _tokenKey = 'outlook_auth_token';
  static const _configClientIdKey = 'outlook_client_id';
  static const _configTenantIdKey = 'outlook_tenant_id';
  static const _syncModeKey = 'outlook_sync_mode';
  static const _pendingAuthKey = 'outlook_pending_auth_session';
  static const _pkceAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  static const _microsoftLoginHost = '';
  static OutlookNetworkDiagnosticsRunner _networkDiagnosticsRunner =
      _runMicrosoftNetworkDiagnostics;
  static OutlookTokenPost _tokenPost = http.post;
  static OutlookAddressLookup _addressLookup = InternetAddress.lookup;
  static OutlookHttpClientFactory _httpClientFactory = HttpClient.new;

  static void debugSetTestOverrides({
    OutlookNetworkDiagnosticsRunner? networkDiagnostics,
    OutlookTokenPost? tokenPost,
    OutlookAddressLookup? addressLookup,
    OutlookHttpClientFactory? httpClientFactory,
  }) {
    _networkDiagnosticsRunner =
        networkDiagnostics ?? _runMicrosoftNetworkDiagnostics;
    _tokenPost = tokenPost ?? http.post;
    _addressLookup = addressLookup ?? InternetAddress.lookup;
    _httpClientFactory = httpClientFactory ?? HttpClient.new;
  }

  static void debugResetTestOverrides() {
    _networkDiagnosticsRunner = _runMicrosoftNetworkDiagnostics;
    _tokenPost = http.post;
    _addressLookup = InternetAddress.lookup;
    _httpClientFactory = HttpClient.new;
  }

  static Future<void> saveConfig(String clientId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_configClientIdKey, clientId.trim());
    await prefs.remove(_configTenantIdKey);
  }

  static Future<OutlookConfig?> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final savedClientId = prefs.getString(_configClientIdKey)?.trim();
    final clientId = (savedClientId == null || savedClientId.isEmpty)
        ? OutlookOAuthPlatformConfig.defaultClientId.trim()
        : savedClientId;
    if (clientId.isEmpty) {
      return null;
    }
    return OutlookConfig(clientId: clientId);
  }

  static Future<OutlookSyncMode> loadSyncMode() async {
    final prefs = await SharedPreferences.getInstance();
    return outlookSyncModeFromStorage(prefs.getString(_syncModeKey));
  }

  static Future<void> saveSyncMode(OutlookSyncMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_syncModeKey, mode.storageValue);
  }

  static Future<bool> signInWithMicrosoft(
    OutlookConfig config, {
    required OutlookSyncMode requestedMode,
  }) async {
    final codeVerifier = _generateRandomString(96);
    final state = _generateRandomString(40);
    final codeChallenge = _buildCodeChallenge(codeVerifier);
    final session = OutlookPendingAuthSession(
      clientId: config.clientId,
      codeVerifier: codeVerifier,
      state: state,
      requestedMode: requestedMode,
      createdAt: DateTime.now(),
    );
    await _savePendingAuthSession(session);

    final scopeValue =
        Uri.encodeQueryComponent(config.scopeString).replaceAll('+', '%20');
    final uri = Uri.parse(
      '${config.authorizeUrl}'
      '?client_id=${Uri.encodeQueryComponent(config.clientId)}'
      '&response_type=code'
      '&redirect_uri=${Uri.encodeQueryComponent(config.redirectUri)}'
      '&response_mode=query'
      '&scope=$scopeValue'
      '&state=${Uri.encodeQueryComponent(state)}'
      '&code_challenge=${Uri.encodeQueryComponent(codeChallenge)}'
      '&code_challenge_method=S256',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> launchAuth(
    OutlookConfig config, {
    required OutlookSyncMode requestedMode,
  }) {
    return signInWithMicrosoft(
      config,
      requestedMode: requestedMode,
    );
  }

  static Future<AuthToken> exchangeCode(
    OutlookConfig config,
    String rawAuthorizationInput, {
    required OutlookSyncMode requestedMode,
  }) async {
    final session = await loadPendingAuthSession();
    if (session == null) {
      throw const OutlookAuthException(
        code: 'missing_pending_auth',
        userMessage:
            '\u672a\u627e\u5230\u5f85\u5b8c\u6210\u7684 Microsoft \u767b\u5f55\u4f1a\u8bdd\uff0c\u8bf7\u91cd\u65b0\u70b9\u51fb\u201c\u8fde\u63a5 Outlook \u65e5\u5386\u201d\u3002',
      );
    }
    if (session.clientId != config.clientId) {
      throw const OutlookAuthException(
        code: 'client_changed',
        userMessage:
            '\u5f53\u524d\u5ba2\u6237\u7aef ID \u5df2\u53d8\u5316\uff0c\u8bf7\u91cd\u65b0\u70b9\u51fb\u201c\u8fde\u63a5 Outlook \u65e5\u5386\u201d\u540e\u518d\u63d0\u4ea4\u6388\u6743\u7801\u3002',
      );
    }

    final parsed = _parseAuthorizationInput(rawAuthorizationInput);
    final state = parsed.state?.trim();
    if (state == null || state.isEmpty) {
      throw const OutlookAuthException(
        code: 'missing_state',
        userMessage:
            '\u4e3a\u4e86\u6821\u9a8c\u8fd9\u6b21\u767b\u5f55\u662f\u5426\u5c5e\u4e8e\u540c\u4e00\u4f1a\u8bdd\uff0c\u8bf7\u7c98\u8d34\u6d4f\u89c8\u5668\u5b8c\u6574\u5730\u5740\u680f\u5185\u5bb9\uff0c\u6216\u81f3\u5c11\u5305\u542b code \u548c state \u53c2\u6570\u3002',
      );
    }
    if (state != session.state) {
      throw const OutlookAuthException(
        code: 'state_mismatch',
        userMessage:
            '\u8fd9\u6b21\u7c98\u8d34\u7684\u6388\u6743\u7ed3\u679c\u4e0e\u5f53\u524d\u767b\u5f55\u4f1a\u8bdd\u4e0d\u5339\u914d\uff0c\u8bf7\u91cd\u65b0\u70b9\u51fb\u201c\u8fde\u63a5 Outlook \u65e5\u5386\u201d\u540e\u518d\u767b\u5f55\u4e00\u6b21\u3002',
      );
    }

    final diagnostics = await runMicrosoftNetworkDiagnostics();
    if (!diagnostics.isReady) {
      throw OutlookAuthException(
        code: 'network_unreachable',
        userMessage:
            '\u5f53\u524d\u8bbe\u5907\u7f51\u7edc\u6216 DNS \u65e0\u6cd5\u8bbf\u95ee Microsoft \u767b\u5f55\u670d\u52a1\u5668\uff0c\u8bf7\u68c0\u67e5\u8054\u7f51\u3001DNS\u3001\u4ee3\u7406\u6216 Android \u7f51\u7edc\u6743\u9650\u3002',
        debugMessage: diagnostics.failureReason,
      );
    }

    http.Response response;
    try {
      response = await _tokenPost(
        Uri.parse(config.tokenUrl),
        headers: const <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: <String, String>{
          'client_id': config.clientId,
          'grant_type': 'authorization_code',
          'code': parsed.code,
          'redirect_uri': config.redirectUri,
          'code_verifier': session.codeVerifier,
          'scope': config.scopeString,
        },
      );
    } on SocketException catch (error) {
      throw OutlookAuthException(
        code: 'network_unreachable',
        userMessage:
            '\u5f53\u524d\u8bbe\u5907\u7f51\u7edc\u6216 DNS \u65e0\u6cd5\u8bbf\u95ee Microsoft \u767b\u5f55\u670d\u52a1\u5668\uff0c\u8bf7\u68c0\u67e5\u8054\u7f51\u3001DNS\u3001\u4ee3\u7406\u6216 Android \u7f51\u7edc\u6743\u9650\u3002',
        debugMessage: error.message,
      );
    } on http.ClientException catch (error) {
      throw OutlookAuthException(
        code: 'network_unreachable',
        userMessage:
            '\u5f53\u524d\u8bbe\u5907\u7f51\u7edc\u6216 DNS \u65e0\u6cd5\u8bbf\u95ee Microsoft \u767b\u5f55\u670d\u52a1\u5668\uff0c\u8bf7\u68c0\u67e5\u8054\u7f51\u3001DNS\u3001\u4ee3\u7406\u6216 Android \u7f51\u7edc\u6743\u9650\u3002',
        debugMessage: error.message,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _buildAuthException(
        response,
        fallbackMessage:
            'Microsoft \u767b\u5f55\u5931\u8d25\uff0c\u8bf7\u68c0\u67e5\u6388\u6743\u7801\u662f\u5426\u5b8c\u6574\u4e14\u5c1a\u672a\u8fc7\u671f\u3002',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = AuthToken.fromTokenResponse(data);
    await _saveToken(token);
    await clearPendingAuthSession();
    return token;
  }

  static Future<AuthToken> exchangeCodeForToken(
    OutlookConfig config,
    String rawAuthorizationInput, {
    required OutlookSyncMode requestedMode,
  }) {
    return exchangeCode(
      config,
      rawAuthorizationInput,
      requestedMode: requestedMode,
    );
  }

  static Future<AuthToken?> refreshToken(OutlookConfig config) async {
    final current = await loadToken();
    final refreshToken = current?.refreshToken?.trim();
    if (current == null || refreshToken == null || refreshToken.isEmpty) {
      return null;
    }

    final diagnostics = await runMicrosoftNetworkDiagnostics();
    if (!diagnostics.isReady) {
      throw OutlookAuthException(
        code: 'network_unreachable',
        userMessage:
            '\u5f53\u524d\u8bbe\u5907\u7f51\u7edc\u6216 DNS \u65e0\u6cd5\u8bbf\u95ee Microsoft \u767b\u5f55\u670d\u52a1\u5668\uff0c\u8bf7\u68c0\u67e5\u8054\u7f51\u3001DNS\u3001\u4ee3\u7406\u6216 Android \u7f51\u7edc\u6743\u9650\u3002',
        debugMessage: diagnostics.failureReason,
      );
    }

    http.Response response;
    try {
      response = await _tokenPost(
        Uri.parse(config.tokenUrl),
        headers: const <String, String>{
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: <String, String>{
          'client_id': config.clientId,
          'grant_type': 'refresh_token',
          'refresh_token': refreshToken,
          'redirect_uri': config.redirectUri,
          'scope': config.scopeString,
        },
      );
    } on SocketException catch (error) {
      throw OutlookAuthException(
        code: 'network_unreachable',
        userMessage:
            '\u5f53\u524d\u8bbe\u5907\u7f51\u7edc\u6216 DNS \u65e0\u6cd5\u8bbf\u95ee Microsoft \u767b\u5f55\u670d\u52a1\u5668\uff0c\u8bf7\u68c0\u67e5\u8054\u7f51\u3001DNS\u3001\u4ee3\u7406\u6216 Android \u7f51\u7edc\u6743\u9650\u3002',
        debugMessage: error.message,
      );
    } on http.ClientException catch (error) {
      throw OutlookAuthException(
        code: 'network_unreachable',
        userMessage:
            '\u5f53\u524d\u8bbe\u5907\u7f51\u7edc\u6216 DNS \u65e0\u6cd5\u8bbf\u95ee Microsoft \u767b\u5f55\u670d\u52a1\u5668\uff0c\u8bf7\u68c0\u67e5\u8054\u7f51\u3001DNS\u3001\u4ee3\u7406\u6216 Android \u7f51\u7edc\u6743\u9650\u3002',
        debugMessage: error.message,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = _buildAuthException(
        response,
        fallbackMessage:
            'Microsoft \u767b\u5f55\u4fe1\u606f\u5237\u65b0\u5931\u8d25\uff0c\u8bf7\u91cd\u65b0\u8fde\u63a5 Outlook\u3002',
      );
      if (error.code == 'invalid_grant') {
        await logout();
      }
      throw error;
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = AuthToken.fromTokenResponse(
      data,
      previousToken: current,
    );
    await _saveToken(token);
    return token;
  }

  static Future<AuthToken?> refreshAccessToken(OutlookConfig config) {
    return refreshToken(config);
  }

  static Future<String?> getValidAccessToken(
    OutlookConfig config, {
    OutlookSyncMode requestedMode = OutlookSyncMode.readOnly,
  }) async {
    var token = await loadToken();
    if (token == null) {
      return null;
    }
    if (!token.supportsMode(requestedMode)) {
      return null;
    }
    if (token.isExpired) {
      try {
        token = await refreshToken(config);
      } on OutlookAuthException {
        return null;
      }
    }
    if (token == null || !token.supportsMode(requestedMode)) {
      return null;
    }
    return token.accessToken;
  }

  static Future<AuthToken?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_tokenKey);
    if (rawJson == null || rawJson.trim().isEmpty) {
      return null;
    }
    try {
      return AuthToken.fromJson(jsonDecode(rawJson) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<OutlookPendingAuthSession?> loadPendingAuthSession() async {
    final prefs = await SharedPreferences.getInstance();
    final rawJson = prefs.getString(_pendingAuthKey);
    if (rawJson == null || rawJson.trim().isEmpty) {
      return null;
    }
    try {
      return OutlookPendingAuthSession.fromJson(
        jsonDecode(rawJson) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _savePendingAuthSession(
    OutlookPendingAuthSession session,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingAuthKey, jsonEncode(session.toJson()));
  }

  static Future<void> clearPendingAuthSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingAuthKey);
  }

  static Future<void> _saveToken(AuthToken token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, jsonEncode(token.toJson()));
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_pendingAuthKey);
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

  static Future<OutlookNetworkDiagnostics> runMicrosoftNetworkDiagnostics() {
    return _networkDiagnosticsRunner();
  }

  static Future<OutlookNetworkDiagnostics>
      _runMicrosoftNetworkDiagnostics() async {
    List<InternetAddress> addresses;
    try {
      addresses = await _addressLookup(_microsoftLoginHost);
    } on SocketException catch (error) {
      return OutlookNetworkDiagnostics(
        canResolveMicrosoftHost: false,
        canReachMicrosoftServer: false,
        failureReason: error.message,
      );
    } catch (error) {
      return OutlookNetworkDiagnostics(
        canResolveMicrosoftHost: false,
        canReachMicrosoftServer: false,
        failureReason: error.toString(),
      );
    }

    if (addresses.isEmpty) {
      return const OutlookNetworkDiagnostics(
        canResolveMicrosoftHost: false,
        canReachMicrosoftServer: false,
        failureReason: 'DNS 查询成功返回为空。',
      );
    }

    final client = _httpClientFactory()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(
        Uri.parse(OutlookOAuthPlatformConfig.authority),
      );
      request.followRedirects = false;
      final response = await request.close();
      await response.drain<void>();
      final reachable = response.statusCode >= 200 && response.statusCode < 500;
      return OutlookNetworkDiagnostics(
        canResolveMicrosoftHost: true,
        canReachMicrosoftServer: reachable,
        resolvedAddresses:
            addresses.map((address) => address.address).toList(growable: false),
        failureReason:
            reachable ? null : 'Microsoft 登录服务器返回异常状态：${response.statusCode}',
      );
    } on SocketException catch (error) {
      return OutlookNetworkDiagnostics(
        canResolveMicrosoftHost: true,
        canReachMicrosoftServer: false,
        resolvedAddresses:
            addresses.map((address) => address.address).toList(growable: false),
        failureReason: error.message,
      );
    } catch (error) {
      return OutlookNetworkDiagnostics(
        canResolveMicrosoftHost: true,
        canReachMicrosoftServer: false,
        resolvedAddresses:
            addresses.map((address) => address.address).toList(growable: false),
        failureReason: error.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }

  static _ParsedAuthorizationInput _parseAuthorizationInput(String rawInput) {
    final input = rawInput.trim();
    if (input.isEmpty) {
      throw const OutlookAuthException(
        code: 'missing_code',
        userMessage:
            '\u8bf7\u5148\u7c98\u8d34\u6d4f\u89c8\u5668\u8fd4\u56de\u7684\u6388\u6743\u7ed3\u679c\u3002',
      );
    }

    Uri? uri;
    if (input.startsWith('http://') || input.startsWith('https://')) {
      uri = Uri.tryParse(input);
    } else if (input.contains('code=') || input.contains('state=')) {
      final normalized = input.startsWith('?') ? input.substring(1) : input;
      uri = Uri.tryParse(
        '${OutlookOAuthPlatformConfig.redirectUri}?$normalized',
      );
    }

    if (uri != null) {
      final fragmentUri = uri.fragment.isEmpty
          ? null
          : Uri.tryParse('https://callback.local/?${uri.fragment}');
      final code = uri.queryParameters['code']?.trim() ??
          fragmentUri?.queryParameters['code']?.trim();
      if (code == null || code.isEmpty) {
        throw const OutlookAuthException(
          code: 'missing_code',
          userMessage:
              '\u6ca1\u6709\u5728\u7c98\u8d34\u5185\u5bb9\u4e2d\u627e\u5230 code \u53c2\u6570\uff0c\u8bf7\u91cd\u65b0\u590d\u5236\u6d4f\u89c8\u5668\u5730\u5740\u680f\u5185\u5bb9\u3002',
        );
      }
      return _ParsedAuthorizationInput(
        code: code,
        state: uri.queryParameters['state']?.trim() ??
            fragmentUri?.queryParameters['state']?.trim(),
      );
    }

    return _ParsedAuthorizationInput(code: input);
  }

  static OutlookAuthException _buildAuthException(
    http.Response response, {
    required String fallbackMessage,
  }) {
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final errorCode = (json['error'] as String? ?? 'oauth_error').trim();
      final errorDescription = (json['error_description'] as String? ?? '')
          .replaceAll('\r', ' ')
          .replaceAll('\n', ' ')
          .trim();

      if (errorDescription.contains('AADSTS50020')) {
        return OutlookAuthException(
          code: errorCode,
          statusCode: response.statusCode,
          userMessage:
              'Microsoft \u8fd4\u56de AADSTS50020\u3002\u5f53\u524d\u767b\u5f55\u4ecd\u50cf\u662f\u5728\u4f7f\u7528\u5b66\u6821\u6216\u7ec4\u7ec7\u79df\u6237\u3002\u8bf7\u786e\u8ba4 FlowPlanV2 \u4f7f\u7528\u7684\u662f consumers \u6388\u6743\u5730\u5740\uff0c\u800c\u4e0d\u662f\u5b66\u6821\u79df\u6237\u3001organizations \u6216\u5177\u4f53 tenant ID\u3002',
          debugMessage: errorDescription,
        );
      }
      if (errorDescription.contains('AADSTS50011')) {
        return OutlookAuthException(
          code: errorCode,
          statusCode: response.statusCode,
          userMessage: 'Outlook OAuth 已迁移到管理端配置。',
          debugMessage: errorDescription,
        );
      }
      if (errorCode == 'invalid_grant') {
        return OutlookAuthException(
          code: errorCode,
          statusCode: response.statusCode,
          userMessage:
              '\u6388\u6743\u7801\u5df2\u8fc7\u671f\u3001\u5df2\u88ab\u4f7f\u7528\uff0c\u6216 redirect_uri / code_verifier / \u7c98\u8d34\u5185\u5bb9\u4e0d\u4e00\u81f4\u3002\u8bf7\u91cd\u65b0\u70b9\u51fb\u201c\u8fde\u63a5 Outlook \u65e5\u5386\u201d\uff0c\u91cd\u65b0\u767b\u5f55\u540e\u518d\u63d0\u4ea4\u65b0\u7684\u6d4f\u89c8\u5668\u5730\u5740\u3002',
          debugMessage: errorDescription,
        );
      }
      if (errorCode == 'interaction_required' ||
          errorCode == 'consent_required') {
        return OutlookAuthException(
          code: errorCode,
          statusCode: response.statusCode,
          userMessage:
              'Microsoft \u9700\u8981\u4f60\u91cd\u65b0\u767b\u5f55\u5e76\u540c\u610f\u65e5\u5386\u6743\u9650\uff0c\u8bf7\u91cd\u65b0\u70b9\u51fb\u201c\u8fde\u63a5 Outlook \u65e5\u5386\u201d\u3002',
          debugMessage: errorDescription,
        );
      }

      return OutlookAuthException(
        code: errorCode,
        statusCode: response.statusCode,
        userMessage: fallbackMessage,
        debugMessage:
            errorDescription.isEmpty ? response.body : errorDescription,
      );
    } catch (_) {
      return OutlookAuthException(
        code: 'oauth_error',
        statusCode: response.statusCode,
        userMessage: fallbackMessage,
        debugMessage: response.body,
      );
    }
  }

  static String _generateRandomString(int length) {
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var index = 0; index < length; index++) {
      buffer.write(_pkceAlphabet[random.nextInt(_pkceAlphabet.length)]);
    }
    return buffer.toString();
  }

  static String _buildCodeChallenge(String codeVerifier) {
    final digest = sha256.convert(utf8.encode(codeVerifier));
    return base64UrlEncode(digest.bytes).replaceAll('=', '');
  }
}
