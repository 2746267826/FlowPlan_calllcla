import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/sync/sync_object_registry.dart';
import 'package:flowplanv2/features/actual/data/actual_activity_log_repository.dart';
import 'package:flowplanv2/features/files/services/file_transfer_service.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_support/test_database.dart';

void main() {
  group('server API providers', () {
    test('build wrappers from the shared apiClientProvider override', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final requests = <_RecordedRequest>[];
      final container = _createContainer(
        db: db,
        requests: requests,
      );
      addTearDown(container.dispose);

      final analytics = await container.read(analyticsApiProvider.future);
      final ai = await container.read(aiApiProvider.future);
      final fileCloud = await container.read(fileCloudApiProvider.future);
      final fileContext = await container.read(fileContextApiProvider.future);
      final tracking = await container.read(trackingIngestApiProvider.future);
      final reports = await container.read(reportsApiProvider.future);
      final scheduler = await container.read(schedulerApiProvider.future);
      final activity =
          await container.read(activityUnderstandingApiProvider.future);
      final models = await container.read(modelsApiProvider.future);
      final client = await container.read(clientApiProvider.future);

      await analytics.trackerHome(date: DateTime.utc(2026, 6, 10));
      await ai.settings();
      await fileCloud.providers();
      await fileContext.roots(query: 'docs');
      await tracking.summary(start: DateTime.utc(2026, 6, 1));
      await reports.reports(status: 'draft');
      await scheduler.run('run-1');
      await activity.segments(status: 'confirmed');
      await models.models();
      await client.settings();

      expect(
        requests.map((request) => request.signature),
        containsAll(<String>[
          'GET /api/analytics/tracker-home',
          'GET /api/ai/settings',
          'GET /api/files/providers',
          'GET /api/files/roots',
          'GET /api/tracking/summary',
          'GET /api/reports',
          'GET /api/scheduler/runs/run-1',
          'GET /api/activity-understanding/segments',
          'GET /api/models',
          'GET /api/client/settings',
        ]),
      );
      expect(
        requests
            .singleWhere((request) => request.path == '/api/files/roots')
            .query,
        containsPair('q', 'docs'),
      );
      expect(
        requests.singleWhere((request) => request.path == '/api/reports').query,
        containsPair('status', 'draft'),
      );
    });

    test('surface shared apiClientProvider failures through wrapper providers',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
          apiClientProvider.overrideWith((ref) async {
            throw StateError('api unavailable');
          }),
        ],
      );
      addTearDown(container.dispose);

      await expectLater(
        container.read(analyticsApiProvider.future),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          'api unavailable',
        )),
      );
    });
  });

  group('repository providers', () {
    test('wire actual logs through audit and sync dependencies', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      final actualRepository =
          container.read(actualActivityLogRepositoryProvider);
      final auditRepository =
          container.read(dataOperationLogRepositoryProvider);
      final mutationStore = container.read(offlineMutationStoreProvider);

      final id = await actualRepository.insertCandidate(
        title: 'Provider-wired actual',
        startAt: DateTime.utc(2026, 6, 10, 9),
        endAt: DateTime.utc(2026, 6, 10, 10),
        sourceType: ActualActivitySourceType.manual,
        sourceId: 'provider-actual-1',
        actor: 'provider-test',
      );

      final actual = await actualRepository.getById(id);
      final auditRows = await auditRepository.listRecent();
      final mutations = await mutationStore.listPending(limit: 10);

      expect(actual?.title, 'Provider-wired actual');
      expect(auditRows.single.actor, 'provider-test');
      expect(auditRows.single.entityType, 'actual_activity_log');
      expect(
        mutations.map((mutation) => mutation.objectType),
        containsAll(<String>[
          SyncObjectType.auditLog.key,
          SyncObjectType.actualActivityLog.key,
        ]),
      );
      expect(
        mutations
            .singleWhere(
              (mutation) =>
                  mutation.objectType == SyncObjectType.actualActivityLog.key,
            )
            .action,
        OfflineMutationAction.create,
      );
    });

    test('disposes actual log repository streams with the container', () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final container = ProviderContainer(
        overrides: <Override>[
          databaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(container.dispose);

      final repository = container.read(actualActivityLogRepositoryProvider);
      final done = Completer<void>();
      final subscription = repository
          .watchInRange(
            DateTime.utc(2026, 6, 10),
            DateTime.utc(2026, 6, 11),
          )
          .listen(
            (_) {},
            onDone: done.complete,
          );
      addTearDown(subscription.cancel);

      container.dispose();

      await expectLater(done.future, completes);
    });
  });

  group('fileTransferServiceProvider', () {
    test('loads persisted jobs and uses the file cloud API provider', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        FileTransferServiceStorage.key: jsonEncode(<Map<String, Object?>>[
          FileTransferJob(
            id: 'job-1',
            direction: FileTransferDirection.upload,
            fileName: 'notes.md',
            localPath: r'C:\tmp\notes.md',
            totalBytes: 42,
            chunkSize: 42,
            expectedChunks: 1,
            transferredBytes: 0,
            status: FileTransferStatus.queued,
            createdAt: DateTime.utc(2026, 6, 10, 8),
            updatedAt: DateTime.utc(2026, 6, 10, 8),
          ).toJson(),
        ]),
      });
      final db = createTestDatabase();
      addTearDown(db.close);
      final requests = <_RecordedRequest>[];
      final container = _createContainer(
        db: db,
        requests: requests,
        responseFor: (request) {
          if (request.url.path == '/api/files/transfers') {
            return <String, Object?>{
              'transfers': <Map<String, Object?>>[
                <String, Object?>{'sessionId': 'transfer-1'},
              ],
            };
          }
          return const <String, Object?>{'ok': true};
        },
      );
      addTearDown(container.dispose);

      final service = container.read(fileTransferServiceProvider);
      await service.load();
      await service.refreshServerTransfers();

      expect(service.loaded, isTrue);
      expect(service.jobs, hasLength(1));
      expect(service.jobs.single.fileName, 'notes.md');
      expect(service.serverTransfers.single['sessionId'], 'transfer-1');
      expect(
        requests
            .singleWhere((request) => request.path == '/api/files/transfers')
            .query,
        containsPair('limit', '100'),
      );
    });

    test('disposes the provided ChangeNotifier with its container', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final db = createTestDatabase();
      addTearDown(db.close);
      final container = _createContainer(
        db: db,
        requests: <_RecordedRequest>[],
      );

      final service = container.read(fileTransferServiceProvider);
      await pumpEventQueue();
      expect(service.loaded, isTrue);

      container.dispose();

      expect(
        () => service.addListener(() {}),
        throwsA(isA<FlutterError>()),
      );
    });
  });

  group('serverSyncEngineProvider', () {
    test('builds an engine that pulls through the shared apiClientProvider',
        () async {
      final db = createTestDatabase();
      addTearDown(db.close);
      final requests = <_RecordedRequest>[];
      final container = _createContainer(
        db: db,
        requests: requests,
        responseFor: (request) {
          if (request.url.path == '/api/sync/pull') {
            return const <String, Object?>{
              'changes': <Object?>[],
              'nextCursor': null,
            };
          }
          return const <String, Object?>{'ok': true};
        },
      );
      addTearDown(container.dispose);

      final engine = await container.read(serverSyncEngineProvider.future);
      final result = await engine.pullChanges(limit: 25);

      expect(result['pulledChanges'], 0);
      final pull = requests.singleWhere(
        (request) => request.path == '/api/sync/pull',
      );
      expect(pull.query, containsPair('limit', '25'));
    });
  });
}

ProviderContainer _createContainer({
  required AppDatabase db,
  required List<_RecordedRequest> requests,
  Map<String, Object?> Function(http.Request request)? responseFor,
}) {
  final apiClient = ApiClient(
    baseUri: Uri.parse('http://flowplan.test/api'),
    tokenStore: AuthTokenStore(db),
    httpClient: MockClient((request) async {
      requests.add(_RecordedRequest(request));
      final body =
          responseFor?.call(request) ?? const <String, Object?>{'ok': true};
      return http.Response(jsonEncode(body), 200);
    }),
  );
  return ProviderContainer(
    overrides: <Override>[
      databaseProvider.overrideWithValue(db),
      apiClientProvider.overrideWith((ref) async => apiClient),
    ],
  );
}

class _RecordedRequest {
  _RecordedRequest(http.Request request)
      : method = request.method,
        path = request.url.path,
        query = Map<String, String>.from(request.url.queryParameters);

  final String method;
  final String path;
  final Map<String, String> query;

  String get signature => '$method $path';
}

class FileTransferServiceStorage {
  const FileTransferServiceStorage._();

  static const key = 'flowplanv2.file_transfer.jobs.v1';
}
