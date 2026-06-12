import 'dart:convert';

import 'package:flowplanv2/core/bootstrap/client_bootstrap_service.dart';
import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/storage/app_storage_config.dart';
import 'package:flowplanv2/core/sync/sync_object_registry.dart';
import 'package:flowplanv2/core/sync/sync_status.dart';
import 'package:flowplanv2/core/theme/app_theme.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/core/utils/payload_utils.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../test_support/test_database.dart';

void main() {
  test('payload helpers cover numeric boolean and date fallbacks', () {
    final payload = <String, Object?>{
      'intNum': 12.8,
      'intBad': '12.3',
      'numText': '9.25',
      'numBad': 'nope',
      'doubleInt': 7,
      'doubleBad': 'n/a',
      'boolZero': 0,
      'boolFalse': 'NO',
      'dateObject': DateTime.utc(2026, 6, 11, 8),
      'dateMillis': DateTime.utc(2026, 6, 11, 9).millisecondsSinceEpoch,
      'dateBlank': '   ',
    };

    expect(intAny(payload, const <String>['missing', 'intNum']), 12);
    expect(intAny(payload, const <String>['intBad']), isNull);
    expect(numAny(payload, const <String>['missing', 'numText']), 9.25);
    expect(numAny(payload, const <String>['numBad']), isNull);
    expect(doubleAny(payload, const <String>['doubleInt']), 7.0);
    expect(doubleAny(payload, const <String>['doubleBad']), isNull);
    expect(boolAny(payload, const <String>['boolZero']), isFalse);
    expect(boolAny(payload, const <String>['boolFalse']), isFalse);
    expect(dateAny(payload, const <String>['dateObject']),
        DateTime.utc(2026, 6, 11, 8));
    expect(
      dateAny(payload, const <String>['dateMillis']),
      DateTime.fromMillisecondsSinceEpoch(
        DateTime.utc(2026, 6, 11, 9).millisecondsSinceEpoch,
      ),
    );
    expect(dateAny(payload, const <String>['dateBlank']), isNull);
  });

  test('core value objects expose small fallback branches', () {
    expect(OfflineMutationStatus.pending.syncState, SyncState.pendingUpdate);
    expect(OfflineMutationStatus.sending.syncState, SyncState.pendingUpdate);
    expect(OfflineMutationStatus.acked.syncState, SyncState.synced);
    expect(OfflineMutationStatus.failed.syncState, SyncState.failed);
    expect(OfflineMutationStatus.conflict.syncState, SyncState.conflict);
    expect(
      OfflineMutationAction.fromWireName('unknown'),
      OfflineMutationAction.update,
    );
    expect(
      OfflineMutationStatus.fromWireName('unknown'),
      OfflineMutationStatus.failed,
    );

    final runtime = ClientRuntimeState.fromBootstrap(
      const <String, dynamic>{
        'settingsVersion': 2.8,
        'syncCursor': 42,
        'pendingActions': <String, Object?>{'upload': 3},
      },
      mode: 'server_first',
      syncing: true,
    );
    expect(runtime.settingsVersion, 2);
    expect(runtime.syncCursor, '42');
    expect(runtime.pendingActions, containsPair('upload', 3));
    expect(runtime.copyWith(lastError: 'boom').lastError, 'boom');
    expect(runtime.copyWith(lastError: 'boom').copyWith().lastError, isNull);

    expect(const ServerConnectionState(conflictCount: 1).hasConflict, isTrue);
    final registry = SyncObjectRegistry.p1();
    expect(registry.contains('task_item'), isTrue);
    expect(registry.contains('missing'), isFalse);
    expect(AppKeys.shellReports, const Key('flowplan.shell.reports'));
  });

  test('storage theme and database provider expose non-ui constants', () {
    expect(currentAppStorageFlavor, AppStorageFlavor.debug);
    expect(appStorageDirectoryName, 'FlowPlanV2_debug');
    expect(appSharedPreferencesPrefix, 'flowplanv2.debug.');
    expect(appStorageFlavorLabel, 'debug');
    expect(appStorageFlavorDisplayName, isNotEmpty);

    expect(AppTextStyles.displayLarge.fontSize, 32);
    expect(AppTextStyles.titleLarge.fontWeight, FontWeight.w600);
    expect(AppTextStyles.titleMedium.fontSize, 16);
    expect(AppTextStyles.bodyMedium.height, 1.5);
    expect(AppTextStyles.labelSmall.letterSpacing, 0.5);

    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(() => container.read(databaseProvider), throwsUnimplementedError);
  });

  test('auth token store saves refresh token and clears both tokens', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    final store = AuthTokenStore(db);

    await store.saveTokens(accessToken: ' access ', refreshToken: 'refresh');
    expect(await store.readAccessToken(), ' access ');
    expect(await store.readRefreshToken(), 'refresh');

    await store.clear();
    expect(await store.readAccessToken(), isNull);
    expect(await store.readRefreshToken(), isNull);
  });

  test('api client sends put json and converts loose map responses', () async {
    final db = createTestDatabase();
    addTearDown(db.close);
    await AuthTokenStore(db)
        .saveTokens(accessToken: ' token ', refreshToken: '');

    late http.Request captured;
    final client = ApiClient(
      baseUri: Uri.parse('https://example.test/api'),
      tokenStore: AuthTokenStore(db),
      defaultHeaders: const <String, String>{'x-device': 'gap6'},
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"ok":true,"count":1}', 200);
      }),
    );

    final response = await client.putJson(
      '/items/1',
      query: const <String, String>{'expand': 'yes'},
      body: const <String, Object?>{'name': 'Gap6'},
    );

    expect(response, containsPair('ok', true));
    expect(response, containsPair('count', 1));
    expect(captured.method, 'PUT');
    expect(
        captured.url.toString(), 'https://example.test/api/items/1?expand=yes');
    expect(captured.headers['authorization'], 'Bearer token');
    expect(captured.headers['x-device'], 'gap6');
    expect(jsonDecode(captured.body), <String, Object?>{'name': 'Gap6'});
  });
}
