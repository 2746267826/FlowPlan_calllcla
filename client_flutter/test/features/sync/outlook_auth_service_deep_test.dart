import 'dart:convert';

import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

void main() {
  const config = OutlookConfig(clientId: 'client-id');
  final future = DateTime.utc(2099);
  late UrlLauncherPlatform originalLauncher;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    originalLauncher = UrlLauncherPlatform.instance;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = originalLauncher;
    OutlookAuthService.debugResetTestOverrides();
  });

  group('configuration and OAuth launch', () {
    test('saveConfig trims client id and removes legacy tenant id', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_tenant_id': 'legacy-tenant',
      });

      await OutlookAuthService.saveConfig('  trimmed-client  ');

      final loaded = await OutlookAuthService.loadConfig();
      final prefs = await SharedPreferences.getInstance();
      expect(loaded, isNotNull);
      expect(loaded!.clientId, 'trimmed-client');
      expect(prefs.getString('outlook_tenant_id'), isNull);
    });

    test('loadConfig returns null when no client id is configured', () async {
      expect(await OutlookAuthService.loadConfig(), isNull);
    });

    test('saveSyncMode persists all supported storage values', () async {
      for (final mode in OutlookSyncMode.values) {
        await OutlookAuthService.saveSyncMode(mode);
        expect(await OutlookAuthService.loadSyncMode(), mode);
      }

      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_sync_mode': 'import_only',
      });
      expect(await OutlookAuthService.loadSyncMode(), OutlookSyncMode.readOnly);

      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_sync_mode': 'disabled',
      });
      expect(await OutlookAuthService.loadSyncMode(), OutlookSyncMode.paused);
    });

    test('signInWithMicrosoft launches a PKCE authorization URL', () async {
      final launcher = _FakeUrlLauncher(launchResult: true);
      UrlLauncherPlatform.instance = launcher;

      final launched = await OutlookAuthService.signInWithMicrosoft(
        config,
        requestedMode: OutlookSyncMode.bidirectional,
      );

      expect(launched, isTrue);
      expect(launcher.launchedUrls, hasLength(1));
      final uri = Uri.parse(launcher.launchedUrls.single);
      expect(uri.queryParameters['client_id'], 'client-id');
      expect(uri.queryParameters['response_type'], 'code');
      expect(uri.queryParameters['response_mode'], 'query');
      expect(uri.queryParameters['scope'], 'Calendars.Read');
      expect(uri.queryParameters['code_challenge_method'], 'S256');
      expect(uri.queryParameters['code_verifier'], isNull);
      expect(uri.queryParameters['code_challenge'], isNotEmpty);
      expect(
        uri.queryParameters['code_challenge'],
        matches(RegExp(r'^[A-Za-z0-9_-]+$')),
      );

      final session = await OutlookAuthService.loadPendingAuthSession();
      expect(session, isNotNull);
      expect(session!.clientId, 'client-id');
      expect(session.requestedMode, OutlookSyncMode.bidirectional);
      expect(session.codeVerifier, hasLength(96));
      expect(session.state, hasLength(40));
      expect(uri.queryParameters['state'], session.state);
    });

    test('signInWithMicrosoft reports launcher failure but keeps session',
        () async {
      final launcher = _FakeUrlLauncher(launchResult: false);
      UrlLauncherPlatform.instance = launcher;

      final launched = await OutlookAuthService.signInWithMicrosoft(
        config,
        requestedMode: OutlookSyncMode.readOnly,
      );

      expect(launched, isFalse);
      expect(launcher.launchedUrls, hasLength(1));
      expect(await OutlookAuthService.loadPendingAuthSession(), isNotNull);
    });
  });

  group('exchangeCode session validation', () {
    test('throws missing_pending_auth before parsing or posting tokens',
        () async {
      await expectLater(
        OutlookAuthService.exchangeCode(
          config,
          'https://callback.local/?code=auth-code&state=session-state',
          requestedMode: OutlookSyncMode.readOnly,
        ),
        throwsA(
          isA<OutlookAuthException>()
              .having((error) => error.code, 'code', 'missing_pending_auth')
              .having((error) => error.statusCode, 'statusCode', isNull),
        ),
      );
    });

    test('throws state_mismatch and keeps the pending session intact',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_pending_auth_session': jsonEncode(<String, Object?>{
          'client_id': 'client-id',
          'code_verifier': 'verifier',
          'state': 'expected-state',
          'requested_mode': OutlookSyncMode.readOnly.storageValue,
          'created_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
        }),
      });

      await expectLater(
        OutlookAuthService.exchangeCode(
          config,
          'https://callback.local/?code=auth-code&state=wrong-state',
          requestedMode: OutlookSyncMode.readOnly,
        ),
        throwsA(
          isA<OutlookAuthException>()
              .having((error) => error.code, 'code', 'state_mismatch'),
        ),
      );

      final session = await OutlookAuthService.loadPendingAuthSession();
      expect(session, isNotNull);
      expect(session!.state, 'expected-state');
    });

    test('throws missing_state when only a raw code is submitted', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_pending_auth_session': jsonEncode(<String, Object?>{
          'client_id': 'client-id',
          'code_verifier': 'verifier',
          'state': 'expected-state',
          'requested_mode': OutlookSyncMode.readOnly.storageValue,
          'created_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
        }),
      });

      await expectLater(
        OutlookAuthService.exchangeCode(
          config,
          'auth-code-only',
          requestedMode: OutlookSyncMode.readOnly,
        ),
        throwsA(
          isA<OutlookAuthException>()
              .having((error) => error.code, 'code', 'missing_state'),
        ),
      );
    });

    test('posts fragment callback, stores token, and clears pending session',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_pending_auth_session': jsonEncode(<String, Object?>{
          'client_id': 'client-id',
          'code_verifier': 'verifier-123',
          'state': 'expected-state',
          'requested_mode': OutlookSyncMode.bidirectional.storageValue,
          'created_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
        }),
      });
      Uri? postedUrl;
      Map<String, String>? postedBody;
      OutlookAuthService.debugSetTestOverrides(
        networkDiagnostics: () async => const OutlookNetworkDiagnostics(
          canResolveMicrosoftHost: true,
          canReachMicrosoftServer: true,
          resolvedAddresses: <String>['127.0.0.1'],
        ),
        tokenPost: (url, {headers, body, encoding}) async {
          postedUrl = url;
          postedBody = Map<String, String>.from(body! as Map);
          return _jsonResponse(
            <String, Object?>{
              'access_token': 'fresh-access',
              'refresh_token': 'fresh-refresh',
              'expires_in': 1800,
              'scope': 'Calendars.Read Calendars.ReadWrite offline_access',
            },
          );
        },
      );

      final token = await OutlookAuthService.exchangeCode(
        config,
        'https://login.local/callback#code=fragment-code&state=expected-state',
        requestedMode: OutlookSyncMode.bidirectional,
      );

      expect(postedUrl, Uri.parse(config.tokenUrl));
      expect(postedBody, containsPair('grant_type', 'authorization_code'));
      expect(postedBody, containsPair('code', 'fragment-code'));
      expect(postedBody, containsPair('code_verifier', 'verifier-123'));
      expect(token.accessToken, 'fresh-access');
      expect(token.refreshToken, 'fresh-refresh');
      expect(token.grantedMode, OutlookSyncMode.bidirectional);
      expect(token.supportsMode(OutlookSyncMode.bidirectional), isTrue);
      expect(await OutlookAuthService.loadPendingAuthSession(), isNull);
      expect(
          (await OutlookAuthService.loadToken())!.accessToken, 'fresh-access');
    });

    test('maps Microsoft OAuth errors into user-facing auth exceptions',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_pending_auth_session': jsonEncode(<String, Object?>{
          'client_id': 'client-id',
          'code_verifier': 'verifier',
          'state': 'expected-state',
          'requested_mode': OutlookSyncMode.readOnly.storageValue,
          'created_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
        }),
      });
      OutlookAuthService.debugSetTestOverrides(
        networkDiagnostics: () async => const OutlookNetworkDiagnostics(
          canResolveMicrosoftHost: true,
          canReachMicrosoftServer: true,
        ),
        tokenPost: (url, {headers, body, encoding}) async => _jsonResponse(
          <String, Object?>{
            'error': 'invalid_request',
            'error_description':
                'AADSTS50020: User account from identity provider does not exist.',
          },
          statusCode: 400,
        ),
      );

      await expectLater(
        OutlookAuthService.exchangeCode(
          config,
          '?code=auth-code&state=expected-state',
          requestedMode: OutlookSyncMode.readOnly,
        ),
        throwsA(
          isA<OutlookAuthException>()
              .having((error) => error.code, 'code', 'invalid_request')
              .having((error) => error.statusCode, 'statusCode', 400)
              .having(
                (error) => error.userMessage,
                'userMessage',
                contains('AADSTS50020'),
              ),
        ),
      );
    });
  });

  group('AuthToken parsing and scope guards', () {
    test('fromTokenResponse preserves refresh token and parses write scope',
        () {
      final previous = AuthToken(
        accessToken: 'old-access',
        refreshToken: 'old-refresh',
        expiresInSeconds: 1200,
        obtainedAt: DateTime.utc(2026, 6, 8, 9),
        expiresAt: DateTime.utc(2026, 6, 8, 10),
        grantedMode: OutlookSyncMode.readOnly,
        scope: 'Calendars.Read',
      );

      final token = AuthToken.fromTokenResponse(
        <String, dynamic>{
          'access_token': 'new-access',
          'expires_in': '1800',
          'scope': 'offline_access calendars.readwrite Calendars.Read',
        },
        previousToken: previous,
      );

      expect(token.accessToken, 'new-access');
      expect(token.refreshToken, 'old-refresh');
      expect(token.expiresInSeconds, 1800);
      expect(token.grantedMode, OutlookSyncMode.bidirectional);
      expect(token.supportsMode(OutlookSyncMode.bidirectional), isTrue);
    });

    test('bidirectional storage value still requires a readwrite scope', () {
      final token = AuthToken(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresInSeconds: 3600,
        obtainedAt: DateTime.utc(2026, 6, 8, 9),
        expiresAt: future,
        grantedMode: OutlookSyncMode.bidirectional,
        scope: 'Calendars.Read offline_access',
      );

      expect(token.supportsMode(OutlookSyncMode.readOnly), isTrue);
      expect(token.supportsMode(OutlookSyncMode.bidirectional), isFalse);
    });
  });

  group('token loading and mode guards', () {
    test('loadToken returns null for malformed persisted JSON', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_auth_token': '{not-json',
      });

      expect(await OutlookAuthService.loadToken(), isNull);
      expect(await OutlookAuthService.isAuthenticated(), isFalse);
    });

    test('getValidAccessToken rejects read-only grants for write mode',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_auth_token': jsonEncode(<String, Object?>{
          'access_token': 'read-token',
          'refresh_token': 'refresh-token',
          'expires_in': 3600,
          'obtained_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
          'expires_at': future.toIso8601String(),
          'granted_mode': OutlookSyncMode.readOnly.storageValue,
          'scope': 'Calendars.Read',
        }),
      });

      expect(
        await OutlookAuthService.getValidAccessToken(
          config,
          requestedMode: OutlookSyncMode.bidirectional,
        ),
        isNull,
      );
      expect(
        await OutlookAuthService.getValidAccessToken(
          config,
          requestedMode: OutlookSyncMode.readOnly,
        ),
        'read-token',
      );
    });

    test('getValidAccessToken converts refresh failures into null', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_auth_token': jsonEncode(<String, Object?>{
          'access_token': 'expired-token',
          'refresh_token': 'refresh-token',
          'expires_in': 3600,
          'obtained_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
          'expires_at': DateTime.utc(2020).toIso8601String(),
          'granted_mode': OutlookSyncMode.readOnly.storageValue,
          'scope': 'Calendars.Read',
        }),
      });

      expect(
        await OutlookAuthService.getValidAccessToken(
          config,
          requestedMode: OutlookSyncMode.readOnly,
        ),
        isNull,
      );
    });

    test('refreshToken returns null when no refresh token is stored', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_auth_token': jsonEncode(<String, Object?>{
          'access_token': 'expired-token',
          'expires_in': 3600,
          'obtained_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
          'expires_at': DateTime.utc(2020).toIso8601String(),
          'granted_mode': OutlookSyncMode.readOnly.storageValue,
          'scope': 'Calendars.Read',
        }),
      });

      expect(await OutlookAuthService.refreshToken(config), isNull);
    });

    test('refreshToken preserves old refresh token when response omits one',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_auth_token': jsonEncode(<String, Object?>{
          'access_token': 'expired-token',
          'refresh_token': 'stored-refresh',
          'expires_in': 3600,
          'obtained_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
          'expires_at': DateTime.utc(2020).toIso8601String(),
          'granted_mode': OutlookSyncMode.readOnly.storageValue,
          'scope': 'Calendars.Read',
        }),
      });
      Map<String, String>? postedBody;
      OutlookAuthService.debugSetTestOverrides(
        networkDiagnostics: () async => const OutlookNetworkDiagnostics(
          canResolveMicrosoftHost: true,
          canReachMicrosoftServer: true,
        ),
        tokenPost: (url, {headers, body, encoding}) async {
          postedBody = Map<String, String>.from(body! as Map);
          return _jsonResponse(
            <String, Object?>{
              'access_token': 'refreshed-access',
              'expires_in': '7200',
              'scope': 'Calendars.Read',
            },
          );
        },
      );

      final refreshed = await OutlookAuthService.refreshAccessToken(config);

      expect(postedBody, containsPair('grant_type', 'refresh_token'));
      expect(postedBody, containsPair('refresh_token', 'stored-refresh'));
      expect(refreshed!.accessToken, 'refreshed-access');
      expect(refreshed.refreshToken, 'stored-refresh');
      expect(refreshed.expiresInSeconds, 7200);
      expect((await OutlookAuthService.loadToken())!.accessToken,
          'refreshed-access');
    });

    test('refreshToken logs out when Microsoft rejects the refresh grant',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_auth_token': jsonEncode(<String, Object?>{
          'access_token': 'expired-token',
          'refresh_token': 'stored-refresh',
          'expires_in': 3600,
          'obtained_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
          'expires_at': DateTime.utc(2020).toIso8601String(),
          'granted_mode': OutlookSyncMode.readOnly.storageValue,
          'scope': 'Calendars.Read',
        }),
        'outlook_pending_auth_session': jsonEncode(<String, Object?>{
          'client_id': 'client-id',
          'code_verifier': 'verifier',
          'state': 'state',
          'requested_mode': OutlookSyncMode.readOnly.storageValue,
          'created_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
        }),
      });
      OutlookAuthService.debugSetTestOverrides(
        networkDiagnostics: () async => const OutlookNetworkDiagnostics(
          canResolveMicrosoftHost: true,
          canReachMicrosoftServer: true,
        ),
        tokenPost: (url, {headers, body, encoding}) async => _jsonResponse(
          <String, Object?>{
            'error': 'invalid_grant',
            'error_description': 'Refresh token expired.',
          },
          statusCode: 401,
        ),
      );

      await expectLater(
        OutlookAuthService.refreshToken(config),
        throwsA(
          isA<OutlookAuthException>()
              .having((error) => error.code, 'code', 'invalid_grant')
              .having((error) => error.statusCode, 'statusCode', 401),
        ),
      );
      expect(await OutlookAuthService.loadToken(), isNull);
      expect(await OutlookAuthService.loadPendingAuthSession(), isNull);
    });

    test('logout clears both token and pending auth session', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_auth_token': jsonEncode(<String, Object?>{
          'access_token': 'access-token',
          'refresh_token': 'refresh-token',
          'expires_in': 3600,
          'obtained_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
          'expires_at': future.toIso8601String(),
          'granted_mode': OutlookSyncMode.bidirectional.storageValue,
          'scope': 'Calendars.ReadWrite',
        }),
        'outlook_pending_auth_session': jsonEncode(<String, Object?>{
          'client_id': 'client-id',
          'code_verifier': 'verifier',
          'state': 'state',
          'requested_mode': OutlookSyncMode.readOnly.storageValue,
          'created_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
        }),
      });

      await OutlookAuthService.logout();

      expect(await OutlookAuthService.loadToken(), isNull);
      expect(await OutlookAuthService.loadPendingAuthSession(), isNull);
    });
  });
}

class _FakeUrlLauncher extends UrlLauncherPlatform {
  _FakeUrlLauncher({required this.launchResult});

  final bool launchResult;
  final launchedUrls = <String>[];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrls.add(url);
    return launchResult;
  }
}

http.Response _jsonResponse(
  Map<String, Object?> body, {
  int statusCode = 200,
}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const <String, String>{
      'content-type': 'application/json',
    },
  );
}
