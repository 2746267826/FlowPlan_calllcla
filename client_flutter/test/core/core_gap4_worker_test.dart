import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flowplanv2/core/bootstrap/client_bootstrap_service.dart';
import 'package:flowplanv2/core/connection/server_connection_service.dart';
import 'package:flowplanv2/core/connection/server_connection_state.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/core/platform/desktop_shell_service.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/client_api.dart';
import 'package:flowplanv2/core/server_api/remote_settings_repository.dart';
import 'package:flowplanv2/core/server_api/server_config_store.dart';
import 'package:flowplanv2/core/server_first/mutation_coordinator.dart';
import 'package:flowplanv2/core/server_first/server_first_repository.dart';
import 'package:flowplanv2/core/server_first/task_event_server_first_store.dart';
import 'package:flowplanv2/core/storage/app_storage.dart';
import 'package:flowplanv2/core/storage/database_restore_service.dart';
import 'package:flowplanv2/core/sync/sync_object_registry.dart';
import 'package:flowplanv2/core/sync/sync_object_state_store.dart';
import 'package:flowplanv2/core/sync/sync_status.dart';
import 'package:flowplanv2/core/sync/sync_write_recorder.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/calendar/presentation/event_detail_page.dart';
import 'package:flowplanv2/features/calendar/presentation/month_view.dart';
import 'package:flowplanv2/features/calendar/presentation/week_view.dart';
import 'package:flowplanv2/features/files/presentation/file_context_page.dart';
import 'package:flowplanv2/features/files/presentation/file_transfer_center_page.dart';
import 'package:flowplanv2/features/reports/presentation/report_center_page.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flowplanv2/features/task/presentation/task_detail_page.dart';
import 'package:flowplanv2/features/tracker/presentation/tracker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;

import '../test_support/fixtures.dart';
import '../test_support/temp_app_storage.dart';
import '../test_support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    SyncWriteRecorder.onMutationRecorded = null;
  });

  test('app router constructs shell pages and detail route fallbacks', () {
    final router = createAppRouter(initialLocation: AppRoutes.week);
    addTearDown(router.dispose);

    final shell = router.configuration.routes.whereType<ShellRoute>().single;
    final shellRoutes = shell.routes.whereType<GoRoute>().toList();
    expect(router.configuration.namedLocation('week'), AppRoutes.week);
    expect(router.configuration.namedLocation('month'), AppRoutes.month);
    expect(router.configuration.namedLocation('reports'), AppRoutes.reports);
    expect(router.configuration.namedLocation('files'), AppRoutes.files);
    expect(
      router.configuration.namedLocation('fileTransfers'),
      AppRoutes.fileTransfers,
    );
    expect(appRouter.configuration.namedLocation('aiChat'), AppRoutes.aiChat);

    expect(_pageChildFor(shellRoutes, 'week'), isA<WeekView>());
    expect(_pageChildFor(shellRoutes, 'month'), isA<MonthView>());
    expect(_pageChildFor(shellRoutes, 'tracker'), isA<TrackerPage>());
    expect(_pageChildFor(shellRoutes, 'reports'), isA<ReportCenterPage>());
    expect(_pageChildFor(shellRoutes, 'files'), isA<FileContextPage>());
    expect(
      _pageChildFor(shellRoutes, 'fileTransfers'),
      isA<FileTransferCenterPage>(),
    );

    final routes = router.configuration.routes.whereType<GoRoute>().toList();
    expect(_widgetFor(routes, 'auditLogs'), isA<Widget>());
    expect(_widgetFor(routes, 'icalImportExport'), isA<Widget>());
    expect(_widgetFor(routes, 'aiChat'), isA<Widget>());

    expect(
      _widgetFor(
        routes,
        'taskDetail',
        pathParameters: const <String, String>{'id': '42'},
      ),
      isA<TaskDetailPage>().having((page) => page.taskId, 'taskId', 42),
    );
    expect(
      _widgetFor(
        routes,
        'taskDetail',
        pathParameters: const <String, String>{'id': 'not-an-int'},
      ),
      isA<TaskDetailPage>().having((page) => page.taskId, 'taskId', 0),
    );
    expect(
      _widgetFor(routes, 'taskCreate'),
      isA<TaskDetailPage>().having((page) => page.taskId, 'taskId', isNull),
    );
    expect(
      _widgetFor(
        routes,
        'eventDetail',
        pathParameters: const <String, String>{'id': '77'},
      ),
      isA<EventDetailPage>().having((page) => page.eventId, 'eventId', 77),
    );
    expect(
      _widgetFor(
        routes,
        'eventDetail',
        pathParameters: const <String, String>{'id': 'bad'},
      ),
      isA<EventDetailPage>().having((page) => page.eventId, 'eventId', 0),
    );
    expect(
      _widgetFor(routes, 'eventCreate'),
      isA<EventDetailPage>().having((page) => page.eventId, 'eventId', isNull),
    );
  });

  test('database restore handles overwrite and metadata fallback branches',
      () async {
    final tempRoot = await setUpTempAppStorage(prefix: 'core-gap4-restore-');
    final service = const DatabaseRestoreService();
    final sourceFile = File(p.join(tempRoot.path, 'backup.db'));
    await _writeSqliteLikeDatabase(sourceFile, marker: 'source');

    final firstStage = await service.stageRestore(sourceFile.path);
    final stagedFile = File(firstStage.stagedPath);
    await _writeSqliteLikeDatabase(sourceFile, marker: 'replacement');
    final secondStage = await service.stageRestore(sourceFile.path);
    expect(secondStage.stagedPath, firstStage.stagedPath);
    expect(await stagedFile.readAsBytes(), await sourceFile.readAsBytes());

    final metadataFile = await resolvePendingDatabaseRestoreMetadataFile();
    await metadataFile.writeAsString(
      jsonEncode(<String, Object?>{
        'sourcePath': 'fallback-source.db',
        'stagedPath': stagedFile.path,
        'stagedAt': 'not-a-date',
      }),
    );
    final pendingWithBadDate = await service.getPendingRestore();
    expect(pendingWithBadDate, isNotNull);
    expect(pendingWithBadDate!.sourcePath, 'fallback-source.db');
    expect(pendingWithBadDate.stagedAt, await stagedFile.lastModified());

    await metadataFile.delete();
    final pendingWithoutMetadata = await service.getPendingRestore();
    expect(pendingWithoutMetadata, isNotNull);
    expect(pendingWithoutMetadata!.sourcePath, stagedFile.path);

    await stagedFile.delete();
    await metadataFile.writeAsString('{"stale":true}');
    expect(await service.getPendingRestore(), isNull);
    expect(await metadataFile.exists(), isFalse);
  });

  test('database restore notice consumes malformed and fallback notices',
      () async {
    await setUpTempAppStorage(prefix: 'core-gap4-restore-notice-');
    final service = const DatabaseRestoreService();
    final noticeFile = await resolveDatabaseRestoreNoticeFile();
    await noticeFile.parent.create(recursive: true);

    await noticeFile.writeAsString('[1,2,3]');
    expect(await service.consumeRestoreNotice(), isNull);
    expect(await noticeFile.exists(), isFalse);

    await noticeFile.writeAsString(jsonEncode(<String, Object?>{
      'restoredAt': DateTime.utc(2026, 6, 11).toIso8601String(),
    }));
    expect(await service.consumeRestoreNotice(), isNull);
    expect(await noticeFile.exists(), isFalse);

    await noticeFile.writeAsString(jsonEncode(<String, Object?>{
      'restoredAt': 'not-a-date',
      'restoredDatabasePath': 'restored.db',
    }));
    final notice = await service.consumeRestoreNotice();
    expect(notice, isNotNull);
    expect(notice!.restoredDatabasePath, 'restored.db');
    expect(notice.restoredAt, isA<DateTime>());
    expect(await noticeFile.exists(), isFalse);
  });

  test('desktop shell service returns fallbacks on unsupported platforms',
      () async {
    const service = DesktopShellService();
    await service.showReminder(title: 'Gap4', body: 'Reminder');
    expect(await service.openPath('missing.txt'), isFalse);
    expect(await service.revealPath('missing.txt'), isFalse);

    if (!Platform.isWindows) {
      expect(await service.setLaunchAtStartupEnabled(true), isTrue);
      expect(await service.getLaunchAtStartupEnabled(), isFalse);
      return;
    }

    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('com.flowplanv2/desktop_shell'),
      (call) async {
        calls.add(call);
        if (call.method == 'setLaunchAtStartupEnabled') {
          throw PlatformException(code: 'startup');
        }
        if (call.method == 'getLaunchAtStartupEnabled') {
          return true;
        }
        throw PlatformException(code: 'unsupported');
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.flowplanv2/desktop_shell'),
        null,
      );
    });

    await service.showReminder(title: 'Gap4', body: 'Reminder');
    expect(await service.openPath('missing.txt'), isFalse);
    expect(await service.revealPath('missing.txt'), isFalse);
    expect(await service.setLaunchAtStartupEnabled(false), isTrue);
    expect(calls.map((call) => call.method), contains('showReminder'));
    expect(calls.map((call) => call.method), contains('openPath'));
    expect(calls.map((call) => call.method), contains('revealPath'));
  });

  test('server connection timers and parsing cover queued sync edges',
      () async {
    final harness = await _ConnectionHarness.create();
    addTearDown(harness.dispose);

    await _withManualTimers((timers) async {
      harness.service.start();
      await _pumpUntil(() => harness.bootstrap.syncSources.isNotEmpty);
      final fullSyncTimer = timers.periodic.single;

      fullSyncTimer.fire();
      await _pumpUntil(
        () => timers.single
            .any((timer) => timer.delay == const Duration(seconds: 2)),
      );
      timers.single.last.fire();
      await _pumpUntil(() => harness.bootstrap.syncSources.length >= 2);

      await SyncWriteRecorder.onMutationRecorded?.call();
      await _pumpUntil(
        () => timers.single
            .any((timer) => timer.delay == const Duration(seconds: 2)),
      );
      timers.single.last.fire();
      await _pumpUntil(() => harness.bootstrap.syncSources.length >= 3);
    });

    expect(harness.bootstrap.syncSources.take(3), <String>[
      'startup',
      'timer',
      'write',
    ]);

    final firstStarted = Completer<void>();
    final firstRelease = Completer<ClientRuntimeState>();
    harness.bootstrap.syncNowHandlers.add((source) {
      firstStarted.complete();
      return firstRelease.future;
    });
    harness.bootstrap.syncNowHandlers.add((source) async {
      return _runtime(lastSyncAt: DateTime.utc(2026, 6, 11, 2));
    });
    final sync = harness.service.syncNow(source: 'manual');
    await firstStarted.future;
    await harness.service.syncNow(source: 'manual-second', reason: 'queued');
    expect(harness.service.state.syncPhase, 'queued');
    expect(harness.service.state.syncReason, 'queued');
    firstRelease.complete(_runtime(lastSyncAt: DateTime.utc(2026, 6, 11, 1)));
    await sync;
    expect(
      harness.bootstrap.syncSources
          .where((source) => source.startsWith('manual')),
      <String>['manual', 'manual-second'],
    );

    harness.bootstrap.syncNowHandlers.add((source) async {
      return _runtime(serverReachable: false, lastError: 'offline runtime');
    });
    await _withManualTimers((timers) async {
      await harness.service.syncNow(source: 'manual-error');
      expect(timers.single.map((timer) => timer.delay),
          contains(const Duration(seconds: 30)));
    });
    expect(harness.service.state.level, ServerConnectionLevel.degraded);
    expect(harness.service.state.lastError, 'offline runtime');

    harness.api.heartbeatResponses.add(<String, dynamic>{
      'ok': true,
      'nextHeartbeatSeconds': 45.8,
    });
    await _withManualTimers((timers) async {
      await harness.service.heartbeat(eventSource: 'numeric');
      expect(harness.service.state.nextHeartbeatSeconds, 45);
      timers.single.last.fire();
      await _pumpUntil(
          () => harness.api.heartbeatEventSources.contains('timer'));
    });

    harness.api.heartbeatResponses.add(<String, dynamic>{
      'ok': true,
      'nextHeartbeatSeconds': 'invalid',
    });
    await _withManualTimers((timers) async {
      await harness.service.heartbeat(eventSource: 'string-fallback');
      expect(harness.service.state.nextHeartbeatSeconds, 30);
      expect(timers.single.last.delay, const Duration(seconds: 30));
    });
  });

  test('server first direct wrappers and local-only deletes queue fallbacks',
      () async {
    final harness = await _ServerFirstHarness.create((request) async {
      if (request.method == 'PATCH' ||
          request.method == 'POST' && request.url.path.endsWith('/complete')) {
        return http.Response(
            jsonEncode(<String, Object?>{
              'serverId': request.url.pathSegments.last,
              'serverVersion': 12,
            }),
            200);
      }
      fail('unexpected remote ${request.method} ${request.url}');
    });
    addTearDown(harness.dispose);

    final updateResult = await harness.store.updateTask(
      id: 'direct-task',
      patch: const <String, Object?>{'summary': 'Direct update'},
      baseServerVersion: 11,
      changedFields: const <String>['summary'],
    );
    final completeResult = await harness.store.completeTask(
      id: 'direct-task',
      body: const <String, Object?>{'completedAt': '2026-06-11T09:00:00Z'},
      baseServerVersion: 12,
    );
    final eventResult = await harness.store.updateEvent(
      id: 'direct-event',
      patch: const <String, Object?>{'summary': 'Direct event'},
      baseServerVersion: 13,
      changedFields: const <String>['summary'],
    );

    expect(updateResult.isCanonical, isTrue);
    expect(completeResult.isCanonical, isTrue);
    expect(eventResult.isCanonical, isTrue);
    expect(
        harness.requests.map((request) => '${request.method} ${request.path}'),
        <String>[
          'PATCH /api/client/tasks/direct-task',
          'POST /api/client/tasks/direct-task/complete',
          'PATCH /api/client/events/direct-event',
        ]);

    final taskId = await harness.db.into(harness.db.taskItems).insert(
          fixtureTask(
            uid: 'task-local-delete-gap4',
            summary: 'Local delete',
            taskListId: harness.taskListId,
          ),
        );
    await harness.stateStore.markPending(
      objectType: SyncObjectType.taskItem.key,
      localId: taskId.toString(),
      uid: 'task-local-delete-gap4',
      state: SyncState.pendingCreate,
    );

    final localDelete = await harness.store.deleteLocalTask(localId: taskId);
    final mutations = await harness.mutationStore.listPending();
    final payload =
        jsonDecode(mutations.single.payloadJson) as Map<String, dynamic>;
    final state = await harness.stateStore.getState(
      objectType: SyncObjectType.taskItem.key,
      localId: taskId.toString(),
    );

    expect(localDelete.isPending, isTrue);
    expect(localDelete.error, isA<StateError>());
    expect(await harness.db.select(harness.db.taskItems).get(), isEmpty);
    expect(mutations.single.action, OfflineMutationAction.delete);
    expect(mutations.single.serverId, isNull);
    expect(payload, <String, Object?>{
      'id': taskId.toString(),
      'uid': 'task-local-delete-gap4',
    });
    expect(state?.syncState, SyncState.pendingDelete);
  });
}

Widget _pageChildFor(List<GoRoute> routes, String name) {
  final route = routes.singleWhere((route) => route.name == name);
  final page = route.pageBuilder!(
    _FakeBuildContext(),
    _state(route, pathParameters: const <String, String>{}),
  ) as NoTransitionPage<dynamic>;
  return page.child;
}

Widget _widgetFor(
  List<GoRoute> routes,
  String name, {
  Map<String, String> pathParameters = const <String, String>{},
}) {
  final route = routes.singleWhere((route) => route.name == name);
  return route.builder!(
      _FakeBuildContext(), _state(route, pathParameters: pathParameters));
}

GoRouterState _state(
  GoRoute route, {
  required Map<String, String> pathParameters,
}) {
  final config = RouteConfiguration(
    ValueNotifier<RoutingConfig>(
      RoutingConfig(routes: <RouteBase>[
        GoRoute(
          path: '/placeholder',
          builder: (_, __) => const SizedBox.shrink(),
        ),
      ]),
    ),
    navigatorKey: GlobalKey<NavigatorState>(),
  );
  return GoRouterState(
    config,
    uri: Uri.parse(route.path.replaceAll(':id', pathParameters['id'] ?? '0')),
    matchedLocation: route.path,
    name: route.name,
    path: route.path,
    fullPath: route.path,
    pathParameters: pathParameters,
    pageKey: ValueKey<String>(route.name ?? route.path),
    topRoute: route,
  );
}

class _FakeBuildContext extends Fake implements BuildContext {}

Future<void> _writeSqliteLikeDatabase(
  File file, {
  required String marker,
}) async {
  await file.parent.create(recursive: true);
  await file.writeAsBytes(
    <int>[
      ...ascii.encode('SQLite format 3\x00'),
      ...utf8.encode(marker),
    ],
    flush: true,
  );
}

Future<void> _withManualTimers(
  Future<void> Function(_ManualTimers timers) body,
) {
  final timers = _ManualTimers();
  return runZoned<Future<void>>(
    () => body(timers),
    zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        if (duration == Duration.zero) {
          return parent.createTimer(zone, duration, callback);
        }
        final timer = _ManualTimer(duration, () => zone.run(callback));
        timers.single.add(timer);
        return timer;
      },
      createPeriodicTimer: (self, parent, zone, period, callback) {
        final timer = _ManualTimer.periodic(
            period,
            () => zone.run(() {
                  callback(timers.periodic.last);
                }));
        timers.periodic.add(timer);
        return timer;
      },
    ),
  );
}

class _ManualTimers {
  final single = <_ManualTimer>[];
  final periodic = <_ManualTimer>[];
}

class _ManualTimer implements Timer {
  _ManualTimer(this.delay, this._callback);

  _ManualTimer.periodic(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  var _active = true;
  var _tick = 0;

  void fire() {
    if (!_active) {
      return;
    }
    _tick++;
    _callback();
  }

  @override
  void cancel() {
    _active = false;
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _tick;
}

Future<void> _pumpUntil(
  bool Function() condition, {
  int maxPumps = 50,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (condition()) {
      return;
    }
    await pumpEventQueue();
  }
  fail('Condition was not met after $maxPumps event queue pumps.');
}

ClientRuntimeState _runtime({
  DateTime? lastSyncAt,
  String? lastError,
  bool serverReachable = true,
}) {
  return ClientRuntimeState(
    mode: 'server_first',
    syncing: false,
    serverReachable: serverReachable,
    lastSyncAt: lastSyncAt ?? DateTime.utc(2026, 6, 11),
    lastError: lastError,
  );
}

class _ConnectionHarness {
  _ConnectionHarness._({
    required this.db,
    required this.api,
    required this.bootstrap,
    required this.service,
  });

  final AppDatabase db;
  final _FakeClientApi api;
  final _FakeBootstrapService bootstrap;
  final ServerConnectionService service;
  var _disposed = false;

  static Future<_ConnectionHarness> create() async {
    final db = createTestDatabase();
    final api = _FakeClientApi(db);
    final bootstrap = _FakeBootstrapService(db, api);
    final service = ServerConnectionService(
      database: db,
      clientApi: api,
      bootstrapService: bootstrap,
      serverConfigStore: ServerConfigStore(db),
      operationLogs: DataOperationLogRepository(db),
      deviceId: 'gap4-device',
      platform: 'gap4-platform',
    );
    return _ConnectionHarness._(
      db: db,
      api: api,
      bootstrap: bootstrap,
      service: service,
    );
  }

  Future<void> dispose() async {
    if (!_disposed) {
      service.dispose();
      _disposed = true;
    }
    SyncWriteRecorder.onMutationRecorded = null;
    await db.close();
  }
}

class _FakeClientApi extends ClientApi {
  _FakeClientApi(AppDatabase db) : super(_unusedApiClient(db));

  final heartbeatResponses = <Map<String, dynamic>>[];
  final heartbeatCalls = <Map<String, Object?>>[];

  List<String> get heartbeatEventSources {
    return heartbeatCalls.map((call) {
      final body = call['body']! as Map<String, Object?>;
      final summary = body['networkSummary']! as Map<String, Object?>;
      return summary['source']! as String;
    }).toList(growable: false);
  }

  @override
  Future<Map<String, dynamic>> heartbeat({
    required String deviceId,
    required Map<String, Object?> body,
  }) async {
    heartbeatCalls.add(<String, Object?>{
      'deviceId': deviceId,
      'body': body,
    });
    if (heartbeatResponses.isNotEmpty) {
      return heartbeatResponses.removeAt(0);
    }
    return <String, dynamic>{'ok': true, 'nextHeartbeatSeconds': 30};
  }
}

class _FakeBootstrapService extends ClientBootstrapService {
  _FakeBootstrapService(AppDatabase db, ClientApi clientApi)
      : super(
          database: db,
          clientApi: clientApi,
          remoteSettingsRepository: RemoteSettingsRepository(
            database: db,
            clientApi: clientApi,
          ),
          syncEngineLoader: () {
            throw UnsupportedError('sync engine is not used by this fake');
          },
          operationLogs: DataOperationLogRepository(db),
        );

  final syncSources = <String>[];
  final syncNowHandlers = <Future<ClientRuntimeState> Function(String)>[];

  @override
  Future<ClientRuntimeState> bootstrapAndSync({String source = 'manual'}) {
    return syncNow(source: source);
  }

  @override
  Future<ClientRuntimeState> syncNow({String source = 'manual'}) {
    syncSources.add(source);
    if (syncNowHandlers.isNotEmpty) {
      return syncNowHandlers.removeAt(0)(source);
    }
    return Future<ClientRuntimeState>.value(_runtime());
  }
}

class _ServerFirstHarness {
  _ServerFirstHarness._({
    required this.db,
    required this.store,
    required this.mutationStore,
    required this.stateStore,
    required this.requests,
    required this.taskListId,
  });

  final AppDatabase db;
  final TaskEventServerFirstStore store;
  final OfflineMutationStore mutationStore;
  final SyncObjectStateStore stateStore;
  final List<_CapturedRequest> requests;
  final int taskListId;

  static Future<_ServerFirstHarness> create(
    Future<http.Response> Function(http.Request request) handler,
  ) async {
    final db = createTestDatabase();
    final taskListId = await insertFixtureTaskList(db);
    await insertFixtureCalendar(db);
    final mutationStore = OfflineMutationStore(db);
    final stateStore = SyncObjectStateStore(db);
    final mutationCoordinator = MutationCoordinator(
      mutationStore: mutationStore,
    );
    final requests = <_CapturedRequest>[];
    final repository = ServerFirstRepository(
      clientApi: ClientApi(
        ApiClient(
          baseUri: Uri.parse('http://localhost:3202/api'),
          tokenStore: AuthTokenStore(db),
          httpClient: MockClient((request) async {
            requests.add(_CapturedRequest.from(request));
            return handler(request);
          }),
        ),
      ),
      mutationCoordinator: mutationCoordinator,
    );
    return _ServerFirstHarness._(
      db: db,
      store: TaskEventServerFirstStore(
        repository: repository,
        mutationCoordinator: mutationCoordinator,
        stateStore: stateStore,
        database: db,
        taskRepository: TaskRepository(db),
        eventRepository: EventRepository(db),
      ),
      mutationStore: mutationStore,
      stateStore: stateStore,
      requests: requests,
      taskListId: taskListId,
    );
  }

  Future<void> dispose() => db.close();
}

class _CapturedRequest {
  _CapturedRequest({
    required this.method,
    required this.path,
    required this.body,
  });

  factory _CapturedRequest.from(http.Request request) {
    return _CapturedRequest(
      method: request.method,
      path: request.url.path,
      body: request.body,
    );
  }

  final String method;
  final String path;
  final String body;
}

ApiClient _unusedApiClient(AppDatabase db) {
  return ApiClient(
    baseUri: Uri.parse('http://localhost:3202/api'),
    tokenStore: AuthTokenStore(db),
    httpClient: MockClient((request) async {
      return http.Response('{}', 500);
    }),
  );
}
