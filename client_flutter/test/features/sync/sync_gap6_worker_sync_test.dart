import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_task_list_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_binding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/test_database.dart';

void main() {
  const config = OutlookConfig(clientId: 'gap6-client');

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OutlookAuthService.debugResetTestOverrides();
  });

  tearDown(OutlookAuthService.debugResetTestOverrides);

  group('Outlook auth gap6 network diagnostics and token branches', () {
    test('exchangeCode stores token and clears pending session', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_pending_auth_session': jsonEncode(<String, Object?>{
          'client_id': 'gap6-client',
          'code_verifier': 'verifier-gap6',
          'state': 'state-gap6',
          'requested_mode': OutlookSyncMode.bidirectional.storageValue,
          'created_at': DateTime.utc(2026, 6, 11, 9).toIso8601String(),
        }),
      });
      Map<String, String>? postedBody;
      OutlookAuthService.debugSetTestOverrides(
        networkDiagnostics: () async => const OutlookNetworkDiagnostics(
          canResolveMicrosoftHost: true,
          canReachMicrosoftServer: true,
          resolvedAddresses: <String>['127.0.0.1'],
        ),
        tokenPost: (url, {headers, body, encoding}) async {
          postedBody = Map<String, String>.from(body! as Map);
          return _jsonResponse(<String, Object?>{
            'access_token': 'gap6-access',
            'refresh_token': 'gap6-refresh',
            'expires_in': 900,
            'scope': 'Calendars.Read Calendars.ReadWrite offline_access',
          });
        },
      );

      final token = await OutlookAuthService.exchangeCode(
        config,
        '?code=gap6-code&state=state-gap6',
        requestedMode: OutlookSyncMode.bidirectional,
      );

      expect(postedBody, containsPair('grant_type', 'authorization_code'));
      expect(postedBody, containsPair('code', 'gap6-code'));
      expect(postedBody, containsPair('code_verifier', 'verifier-gap6'));
      expect(token.accessToken, 'gap6-access');
      expect(token.grantedMode, OutlookSyncMode.bidirectional);
      expect(await OutlookAuthService.loadPendingAuthSession(), isNull);
      expect((await OutlookAuthService.loadToken())!.refreshToken,
          'gap6-refresh');
    });

    test('refreshToken clears invalid refresh grants', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_auth_token': jsonEncode(<String, Object?>{
          'access_token': 'old-access',
          'refresh_token': 'bad-refresh',
          'expires_in': 3600,
          'obtained_at': DateTime.utc(2026, 6, 11, 9).toIso8601String(),
          'expires_at': DateTime.utc(2020).toIso8601String(),
          'granted_mode': OutlookSyncMode.readOnly.storageValue,
          'scope': 'Calendars.Read',
        }),
        'outlook_pending_auth_session': jsonEncode(<String, Object?>{
          'client_id': 'gap6-client',
          'code_verifier': 'verifier',
          'state': 'state',
          'requested_mode': OutlookSyncMode.readOnly.storageValue,
          'created_at': DateTime.utc(2026, 6, 11, 9).toIso8601String(),
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
        throwsA(isA<OutlookAuthException>()
            .having((error) => error.code, 'code', 'invalid_grant')),
      );
      expect(await OutlookAuthService.loadToken(), isNull);
      expect(await OutlookAuthService.loadPendingAuthSession(), isNull);
    });

    test('network diagnostics reports DNS SocketException failures', () async {
      OutlookAuthService.debugSetTestOverrides(
        addressLookup: (_) async => throw const SocketException('dns offline'),
      );

      final diagnostics =
          await OutlookAuthService.runMicrosoftNetworkDiagnostics();

      expect(diagnostics.canResolveMicrosoftHost, isFalse);
      expect(diagnostics.canReachMicrosoftServer, isFalse);
      expect(diagnostics.failureReason, 'dns offline');
    });

    test('network diagnostics reports unexpected DNS failures', () async {
      OutlookAuthService.debugSetTestOverrides(
        addressLookup: (_) async => throw StateError('dns exploded'),
      );

      final diagnostics =
          await OutlookAuthService.runMicrosoftNetworkDiagnostics();

      expect(diagnostics.canResolveMicrosoftHost, isFalse);
      expect(diagnostics.canReachMicrosoftServer, isFalse);
      expect(diagnostics.failureReason, contains('dns exploded'));
    });

    test('network diagnostics reports empty DNS results', () async {
      OutlookAuthService.debugSetTestOverrides(
        addressLookup: (_) async => const <InternetAddress>[],
      );

      final diagnostics =
          await OutlookAuthService.runMicrosoftNetworkDiagnostics();

      expect(diagnostics.canResolveMicrosoftHost, isFalse);
      expect(diagnostics.canReachMicrosoftServer, isFalse);
      expect(diagnostics.failureReason, isNotEmpty);
    });

    test('network diagnostics maps HTTP status into reachability', () async {
      final client = _FakeHttpClient(
        response: _FakeHttpClientResponse(statusCode: 503),
      );
      OutlookAuthService.debugSetTestOverrides(
        addressLookup: (_) async => <InternetAddress>[
          InternetAddress('127.0.0.1'),
          InternetAddress('::1'),
        ],
        httpClientFactory: () => client,
      );

      final diagnostics =
          await OutlookAuthService.runMicrosoftNetworkDiagnostics();

      expect(client.request!.followRedirects, isFalse);
      expect(client.closedForcefully, isTrue);
      expect(diagnostics.canResolveMicrosoftHost, isTrue);
      expect(diagnostics.canReachMicrosoftServer, isFalse);
      expect(diagnostics.resolvedAddresses, <String>['127.0.0.1', '::1']);
      expect(diagnostics.failureReason, contains('503'));
    });

    test('network diagnostics reports HTTP SocketException failures', () async {
      OutlookAuthService.debugSetTestOverrides(
        addressLookup: (_) async => <InternetAddress>[
          InternetAddress('127.0.0.1'),
        ],
        httpClientFactory: () => _FakeHttpClient(
          closeError: const SocketException('login offline'),
        ),
      );

      final diagnostics =
          await OutlookAuthService.runMicrosoftNetworkDiagnostics();

      expect(diagnostics.canResolveMicrosoftHost, isTrue);
      expect(diagnostics.canReachMicrosoftServer, isFalse);
      expect(diagnostics.resolvedAddresses, <String>['127.0.0.1']);
      expect(diagnostics.failureReason, 'login offline');
    });
  });

  group('Outlook binding models and repository boundaries', () {
    test('task list binding copyWith overrides and preserves fields', () {
      final linkedAt = DateTime.utc(2026, 6, 11, 9);
      final replacementLinkedAt = linkedAt.add(const Duration(minutes: 5));
      final binding = OutlookTaskListBinding(
        localTaskListId: 7,
        remoteCalendarId: 'remote-old',
        remoteCalendarName: 'Old name',
        linkedAt: linkedAt,
      );

      final unchanged = binding.copyWith();
      final changed = binding.copyWith(
        localTaskListId: 8,
        remoteCalendarId: 'remote-new',
        remoteCalendarName: 'New name',
        linkedAt: replacementLinkedAt,
      );

      expect(unchanged.localTaskListId, 7);
      expect(unchanged.remoteCalendarId, 'remote-old');
      expect(unchanged.remoteCalendarName, 'Old name');
      expect(unchanged.linkedAt, linkedAt);
      expect(changed.localTaskListId, 8);
      expect(changed.remoteCalendarId, 'remote-new');
      expect(changed.remoteCalendarName, 'New name');
      expect(changed.linkedAt, replacementLinkedAt);
      expect(
        OutlookTaskListBinding.fromJson(changed.toJson()).toJson(),
        changed.toJson(),
      );
    });

    test('mirror binding copyWith overrides remote and conflict fields', () {
      final syncedAt = DateTime.utc(2026, 6, 11, 9);
      final changedSyncedAt = syncedAt.add(const Duration(minutes: 10));
      final binding = _mirrorBinding(
        syncedAt: syncedAt,
        conflictState: OutlookTaskMirrorConflictState.remoteChanged,
      );

      final unchanged = binding.copyWith();
      final changed = binding.copyWith(
        remoteCalendarId: 'remote-new',
        remoteCalendarName: 'New calendar',
        remoteEventId: 'event-new',
        syncedAt: changedSyncedAt,
        localSnapshotHash: 'local-hash-new',
        remoteSnapshotHash: 'remote-hash-new',
        conflictState: OutlookTaskMirrorConflictState.writeFailed,
      );

      expect(unchanged.remoteCalendarId, 'remote-old');
      expect(unchanged.remoteCalendarName, 'Old calendar');
      expect(unchanged.remoteEventId, 'event-old');
      expect(unchanged.syncedAt, syncedAt);
      expect(unchanged.localSnapshotHash, 'local-hash');
      expect(unchanged.remoteSnapshotHash, 'remote-hash');
      expect(
        unchanged.conflictState,
        OutlookTaskMirrorConflictState.remoteChanged,
      );
      expect(changed.remoteCalendarId, 'remote-new');
      expect(changed.remoteCalendarName, 'New calendar');
      expect(changed.remoteEventId, 'event-new');
      expect(changed.syncedAt, changedSyncedAt);
      expect(changed.localSnapshotHash, 'local-hash-new');
      expect(changed.remoteSnapshotHash, 'remote-hash-new');
      expect(changed.conflictState, OutlookTaskMirrorConflictState.writeFailed);
      expect(
        OutlookTaskMirrorBinding.fromJson(changed.toJson()).toJson(),
        changed.toJson(),
      );
    });

    test('repository bulk removal skips empty inputs and persists removals',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final repository = OutlookSyncBindingsRepository(db);
      final first = _taskListBinding(1, remoteCalendarId: 'remote-1');
      final second = _taskListBinding(2, remoteCalendarId: 'remote-2');
      await repository.saveTaskListBinding(first);
      await repository.saveTaskListBinding(second);
      final beforeEmptyRemove = await db.getSetting(
        OutlookSyncBindingsRepository.taskListBindingsSettingKey,
      );

      await repository.removeTaskListBindings(const <int>[]);

      expect(
        await db.getSetting(
          OutlookSyncBindingsRepository.taskListBindingsSettingKey,
        ),
        beforeEmptyRemove,
      );

      await repository.removeTaskListBindings(<int>[1, 99, 1]);

      final remaining = await repository.loadTaskListBindings();
      expect(remaining.keys, <int>[2]);
      expect(remaining[2]!.remoteCalendarId, 'remote-2');
    });
  });
}

OutlookTaskListBinding _taskListBinding(
  int id, {
  required String remoteCalendarId,
}) {
  return OutlookTaskListBinding(
    localTaskListId: id,
    remoteCalendarId: remoteCalendarId,
    remoteCalendarName: 'Calendar $id',
    linkedAt: DateTime.utc(2026, 6, 11, 9),
  );
}

OutlookTaskMirrorBinding _mirrorBinding({
  required DateTime syncedAt,
  required OutlookTaskMirrorConflictState conflictState,
}) {
  return OutlookTaskMirrorBinding(
    localTaskId: 11,
    localTaskListId: 2,
    remoteCalendarId: 'remote-old',
    remoteCalendarName: 'Old calendar',
    remoteEventId: 'event-old',
    syncedAt: syncedAt,
    localSnapshotHash: 'local-hash',
    localSnapshotJson: '{"local":true}',
    remoteSnapshotHash: 'remote-hash',
    remoteSnapshotJson: '{"remote":true}',
    remoteLastModifiedAt: DateTime.utc(2026, 6, 11, 8),
    conflictState: conflictState,
    conflictMessage: 'Needs review',
    conflictDetectedAt: DateTime.utc(2026, 6, 11, 8, 30),
  );
}

http.Response _jsonResponse(
  Map<String, Object?> body, {
  int statusCode = 200,
}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({
    this.response,
    this.closeError,
  });

  final _FakeHttpClientResponse? response;
  final Object? closeError;
  _FakeHttpClientRequest? request;
  bool closedForcefully = false;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    request = _FakeHttpClientRequest(
      response: response,
      closeError: closeError,
    );
    return request!;
  }

  @override
  void close({bool force = false}) {
    closedForcefully = force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest({
    required this.response,
    required this.closeError,
  });

  final _FakeHttpClientResponse? response;
  final Object? closeError;

  @override
  bool followRedirects = true;

  @override
  Future<HttpClientResponse> close() async {
    final error = closeError;
    if (error != null) {
      throw error;
    }
    return response ?? _FakeHttpClientResponse(statusCode: 204);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse({required this.statusCode});

  @override
  final int statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.empty().listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
