import 'dart:convert';
import 'dart:io';

import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_calendar_service.dart';
import 'package:flowplanv2/features/sync/outlook_managed_container_service.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  const config = OutlookConfig(clientId: 'worker-02-client');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OutlookAuthService.debugResetTestOverrides();
  });

  tearDown(OutlookAuthService.debugResetTestOverrides);

  group('OutlookAuthService uncovered auth failures', () {
    test('exchangeCode reports client_changed before parsing callback',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_pending_auth_session': jsonEncode(<String, Object?>{
          'client_id': 'old-client',
          'code_verifier': 'verifier',
          'state': 'expected-state',
          'requested_mode': OutlookSyncMode.readOnly.storageValue,
          'created_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
        }),
      });

      await expectLater(
        OutlookAuthService.exchangeCode(
          config,
          '',
          requestedMode: OutlookSyncMode.readOnly,
        ),
        throwsA(
          isA<OutlookAuthException>()
              .having((error) => error.code, 'code', 'client_changed'),
        ),
      );
    });

    test('exchangeCode reports missing_code for callback without code',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_pending_auth_session': jsonEncode(<String, Object?>{
          'client_id': 'worker-02-client',
          'code_verifier': 'verifier',
          'state': 'expected-state',
          'requested_mode': OutlookSyncMode.readOnly.storageValue,
          'created_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
        }),
      });

      await expectLater(
        OutlookAuthService.exchangeCode(
          config,
          'https://callback.local/?state=expected-state',
          requestedMode: OutlookSyncMode.readOnly,
        ),
        throwsA(
          isA<OutlookAuthException>()
              .having((error) => error.code, 'code', 'missing_code'),
        ),
      );
    });

    test('exchangeCode stops before token post when diagnostics are down',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_pending_auth_session': jsonEncode(<String, Object?>{
          'client_id': 'worker-02-client',
          'code_verifier': 'verifier',
          'state': 'expected-state',
          'requested_mode': OutlookSyncMode.readOnly.storageValue,
          'created_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
        }),
      });
      var posted = false;
      OutlookAuthService.debugSetTestOverrides(
        networkDiagnostics: () async => const OutlookNetworkDiagnostics(
          canResolveMicrosoftHost: false,
          canReachMicrosoftServer: false,
          failureReason: 'dns blocked in worker 02',
        ),
        tokenPost: (url, {headers, body, encoding}) async {
          posted = true;
          return http.Response('{}', 200);
        },
      );

      await expectLater(
        OutlookAuthService.exchangeCode(
          config,
          '?code=auth-code&state=expected-state',
          requestedMode: OutlookSyncMode.readOnly,
        ),
        throwsA(
          isA<OutlookAuthException>()
              .having((error) => error.code, 'code', 'network_unreachable')
              .having(
                (error) => error.debugMessage,
                'debugMessage',
                'dns blocked in worker 02',
              ),
        ),
      );
      expect(posted, isFalse);
    });

    test('exchangeCode converts socket and client exceptions', () async {
      for (final thrown in <Object>[
        const SocketException('socket offline'),
        http.ClientException('client offline'),
      ]) {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'outlook_pending_auth_session': jsonEncode(<String, Object?>{
            'client_id': 'worker-02-client',
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
          tokenPost: (url, {headers, body, encoding}) async => throw thrown,
        );

        await expectLater(
          OutlookAuthService.exchangeCode(
            config,
            '?code=auth-code&state=expected-state',
            requestedMode: OutlookSyncMode.readOnly,
          ),
          throwsA(
            isA<OutlookAuthException>().having(
              (error) => error.code,
              'code',
              'network_unreachable',
            ),
          ),
        );
      }
    });

    test('refreshToken reports network and transport failures', () async {
      Future<void> seedExpiredToken() async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'outlook_auth_token': jsonEncode(<String, Object?>{
            'access_token': 'expired-access',
            'refresh_token': 'stored-refresh',
            'expires_in': 3600,
            'obtained_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
            'expires_at': DateTime.utc(2020).toIso8601String(),
            'granted_mode': OutlookSyncMode.readOnly.storageValue,
            'scope': 'Calendars.Read offline_access',
          }),
        });
      }

      await seedExpiredToken();
      OutlookAuthService.debugSetTestOverrides(
        networkDiagnostics: () async => const OutlookNetworkDiagnostics(
          canResolveMicrosoftHost: true,
          canReachMicrosoftServer: false,
          failureReason: 'login host refused',
        ),
      );
      await expectLater(
        OutlookAuthService.refreshToken(config),
        throwsA(
          isA<OutlookAuthException>()
              .having((error) => error.code, 'code', 'network_unreachable')
              .having(
                (error) => error.debugMessage,
                'debugMessage',
                'login host refused',
              ),
        ),
      );

      for (final thrown in <Object>[
        const SocketException('refresh socket offline'),
        http.ClientException('refresh client offline'),
      ]) {
        await seedExpiredToken();
        OutlookAuthService.debugSetTestOverrides(
          networkDiagnostics: () async => const OutlookNetworkDiagnostics(
            canResolveMicrosoftHost: true,
            canReachMicrosoftServer: true,
          ),
          tokenPost: (url, {headers, body, encoding}) async => throw thrown,
        );

        await expectLater(
          OutlookAuthService.refreshToken(config),
          throwsA(
            isA<OutlookAuthException>().having(
              (error) => error.code,
              'code',
              'network_unreachable',
            ),
          ),
        );
      }
    });

    test('oauth error mapping covers reauth and fallback responses', () async {
      final cases = <String, ({Map<String, Object?> body, String code})>{
        'redirect mismatch': (
          body: <String, Object?>{
            'error': 'invalid_request',
            'error_description': 'AADSTS50011: redirect mismatch',
          },
          code: 'invalid_request',
        ),
        'interaction required': (
          body: <String, Object?>{
            'error': 'interaction_required',
            'error_description': 'sign in again',
          },
          code: 'interaction_required',
        ),
        'consent required': (
          body: <String, Object?>{
            'error': 'consent_required',
            'error_description': 'consent again',
          },
          code: 'consent_required',
        ),
        'fallback oauth': (
          body: <String, Object?>{
            'error': 'temporarily_unavailable',
            'error_description': 'try later',
          },
          code: 'temporarily_unavailable',
        ),
      };

      for (final entry in cases.entries) {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'outlook_pending_auth_session': jsonEncode(<String, Object?>{
            'client_id': 'worker-02-client',
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
          tokenPost: (url, {headers, body, encoding}) async => http.Response(
            jsonEncode(entry.value.body),
            400,
            headers: const <String, String>{'content-type': 'application/json'},
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
                .having((error) => error.code, entry.key, entry.value.code)
                .having((error) => error.statusCode, 'statusCode', 400),
          ),
        );
      }

      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_pending_auth_session': jsonEncode(<String, Object?>{
          'client_id': 'worker-02-client',
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
        tokenPost: (url, {headers, body, encoding}) async => http.Response(
          '<html>bad gateway</html>',
          502,
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
              .having((error) => error.code, 'code', 'oauth_error')
              .having((error) => error.statusCode, 'statusCode', 502)
              .having(
                (error) => error.debugMessage,
                'debugMessage',
                contains('bad gateway'),
              ),
        ),
      );
    });
  });

  group('OutlookCalendarService client-side read-only shell', () {
    test('default methods remain server-managed safe', () async {
      final service = OutlookCalendarService(config);

      expect(await service.signInWithMicrosoft(), isFalse);
      expect(await service.refreshAccessToken(), isNull);
      expect(
        await service.getCalendarEvents(
          DateTime.utc(2026, 6, 8),
          DateTime.utc(2026, 6, 9),
        ),
        isEmpty,
      );
      expect(
        () => service.exchangeCodeForToken('code'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => service.createCalendarEvent(
          'Title',
          DateTime.utc(2026, 6, 8, 9),
          DateTime.utc(2026, 6, 8, 10),
          'Description',
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => service.updateCalendarEvent('event-id', <String, dynamic>{}),
        throwsA(isA<StateError>()),
      );
      expect(
        () => service.deleteCalendarEvent('event-id'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('OutlookManagedContainerService guards', () {
    test('returns existing mirror binding before permission checks', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final taskListId = await insertFixtureTaskList(db, name: 'Existing');
      final taskList = await (db.select(db.taskLists)
            ..where((row) => row.id.equals(taskListId)))
          .getSingle();
      final repository = OutlookSyncBindingsRepository(db);
      await repository.saveTaskListBinding(
        OutlookTaskListBinding(
          localTaskListId: taskListId,
          remoteCalendarId: 'remote-existing',
          remoteCalendarName: 'Existing Remote',
          linkedAt: DateTime.utc(2026, 6, 8, 9),
        ),
      );

      final binding = await OutlookManagedContainerService(
        config: config,
        bindingsRepository: repository,
      ).ensureTaskListMirrorBinding(taskList);

      expect(binding.remoteCalendarId, 'remote-existing');
    });

    test('rejects new mirror binding when mode is not bidirectional',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final taskListId = await insertFixtureTaskList(db, name: 'Read only');
      final taskList = await (db.select(db.taskLists)
            ..where((row) => row.id.equals(taskListId)))
          .getSingle();
      await OutlookAuthService.saveSyncMode(OutlookSyncMode.readOnly);

      await expectLater(
        OutlookManagedContainerService(
          config: config,
          bindingsRepository: OutlookSyncBindingsRepository(db),
        ).ensureTaskListMirrorBinding(taskList),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects new mirror binding when bidirectional grant is missing',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final taskListId = await insertFixtureTaskList(db, name: 'No grant');
      final taskList = await (db.select(db.taskLists)
            ..where((row) => row.id.equals(taskListId)))
          .getSingle();
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_sync_mode': OutlookSyncMode.bidirectional.storageValue,
        'outlook_auth_token': jsonEncode(<String, Object?>{
          'access_token': 'read-access',
          'refresh_token': 'refresh',
          'expires_in': 3600,
          'obtained_at': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
          'expires_at': DateTime.utc(2099).toIso8601String(),
          'granted_mode': OutlookSyncMode.readOnly.storageValue,
          'scope': 'Calendars.Read offline_access',
        }),
      });

      await expectLater(
        OutlookManagedContainerService(
          config: config,
          bindingsRepository: OutlookSyncBindingsRepository(db),
        ).ensureTaskListMirrorBinding(taskList),
        throwsA(isA<StateError>()),
      );
    });

    test('unbind delegates to the bindings repository', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final taskListId = await insertFixtureTaskList(db, name: 'Unbind');
      final repository = OutlookSyncBindingsRepository(db);
      await repository.saveTaskListBinding(
        OutlookTaskListBinding(
          localTaskListId: taskListId,
          remoteCalendarId: 'remote-unbind',
          remoteCalendarName: 'Remote Unbind',
          linkedAt: DateTime.utc(2026, 6, 8, 9),
        ),
      );

      await OutlookManagedContainerService(
        config: config,
        bindingsRepository: repository,
      ).unbindTaskListMirror(taskListId);

      expect(await repository.getTaskListBinding(taskListId), isNull);
    });
  });
}
