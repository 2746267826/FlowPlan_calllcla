import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/features/audit/data_operation_log_repository.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/calendar/data/event_repository.dart';
import 'package:flowplanv2/features/sync/ms_graph_service.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_managed_container_service.dart';
import 'package:flowplanv2/features/sync/outlook_sync_bindings_repository.dart';
import 'package:flowplanv2/features/sync/outlook_sync_policy.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_repository.dart';
import 'package:flowplanv2/features/sync/sync_engine.dart';
import 'package:flowplanv2/features/task/data/task_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../../test_support/fixtures.dart';
import '../../test_support/test_database.dart';

void main() {
  const config = OutlookConfig(clientId: 'gap5-client');
  late UrlLauncherPlatform originalLauncher;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    OutlookAuthService.debugResetTestOverrides();
    originalLauncher = UrlLauncherPlatform.instance;
  });

  tearDown(() {
    UrlLauncherPlatform.instance = originalLauncher;
    OutlookAuthService.debugResetTestOverrides();
  });

  test(
    'sync pulls calendars, prunes stale calendars, hydrates events, and reports details',
    () async {
      final start = DateTime.utc(2026, 6, 11, 9);
      SharedPreferences.setMockInitialValues(<String, Object>{
        'outlook_sync_mode': OutlookSyncMode.readOnly.storageValue,
        'outlook_sync_delta_schema_version': 3,
        'outlook_sync_delta_link.remote-keep': 'old-delta',
        'outlook_sync_delta_link.stale-remote': 'stale-delta',
      });
      final db = createTestDatabase();
      addTearDown(db.close);
      final keepCalendarId = await _insertOutlookCalendar(
        db,
        name: 'Old Work',
        remoteId: 'remote-keep',
      );
      final staleCalendarId = await _insertOutlookCalendar(
        db,
        name: 'Stale Work',
        remoteId: 'stale-remote',
      );
      await db.into(db.calendarEvents).insert(
            fixtureEvent(
              uid: 'outlook_deleted-event',
              summary: 'Deleted locally after delta',
              calendarId: keepCalendarId,
            ).copyWith(source: const Value('outlook')),
          );
      await db.into(db.calendarEvents).insert(
            fixtureEvent(
              uid: 'outlook_stale-event',
              summary: 'Stale event',
              calendarId: staleCalendarId,
            ).copyWith(source: const Value('outlook')),
          );
      final taskMirrorCalendarName = OutlookSyncPolicy.buildManagedCalendarName(
        kind: OutlookManagedCalendarKind.taskMirrorBook,
        containerName: 'Inbox',
      );
      final graph = _Gap5GraphService(
        calendars: <Map<String, dynamic>>[
          <String, dynamic>{'id': '', 'name': 'No id'},
          <String, dynamic>{
            'id': 'remote-task-mirror',
            'name': taskMirrorCalendarName,
          },
          <String, dynamic>{
            'id': 'remote-keep',
            'name': ' Work ',
            'hexColor': '00AA88',
          },
        ],
        eventBatches: <String, _Gap5EventBatch>{
          'remote-keep': _Gap5EventBatch(
            events: <Map<String, dynamic>>[
              <String, dynamic>{'id': ''},
              <String, dynamic>{
                'id': 'deleted-event',
                '@removed': <String, dynamic>{'reason': 'deleted'},
              },
              <String, dynamic>{
                'id': 'needs-hydration',
                'bodyPreview': 'compact preview',
              },
              _graphEvent(
                id: 'full-event',
                subject: 'Full event',
                start: start.add(const Duration(hours: 2)),
                location: 'Room 9',
              ),
            ],
            deltaLink: 'new-delta',
          ),
        },
        fullEvents: <String, Map<String, dynamic>>{
          'remote-keep/needs-hydration': _graphEvent(
            id: 'needs-hydration',
            subject: 'Hydrated event',
            start: start,
            location: 'Room 7',
          ),
        },
      );
      final operationLogs = DataOperationLogRepository(db);

      final result = await _engine(
        db,
        operationLogs,
        graphServiceFactory: (config, {required syncMode}) => graph,
      ).sync();

      final prefs = await SharedPreferences.getInstance();
      final report = await SyncEngine.getLastSyncReport();
      final calendars = await db.select(db.eventCalendars).get();
      final events = await db.select(db.calendarEvents).get();
      final logs = await operationLogs.listRecent(limit: 1);

      expect(result.calendarBooks, 1);
      expect(result.downloaded, 3);
      expect(result.mirroredCreated, 0);
      expect(graph.seenDeltaLinks, <String?>['old-delta']);
      expect(graph.hydratedEventIds, <String>['remote-keep/needs-hydration']);
      expect(
          prefs.getString('outlook_sync_delta_link.remote-keep'), 'new-delta');
      expect(prefs.getString('outlook_sync_delta_link.stale-remote'), isNull);
      expect(
        calendars.map((calendar) => calendar.syncUrl).toSet(),
        isNot(contains('stale-remote')),
      );
      expect(
        events.map((event) => event.uid).toSet(),
        isNot(contains('outlook_deleted-event')),
      );
      expect(
        events.map((event) => event.uid).toSet(),
        isNot(contains('outlook_stale-event')),
      );
      expect(
        events.singleWhere((event) => event.uid == 'outlook_needs-hydration')
          ..summary,
        isA<CalendarEvent>()
            .having((event) => event.summary, 'summary', 'Hydrated event')
            .having((event) => event.location, 'location', 'Room 7')
            .having(
              (event) => event.eventCalendarId,
              'eventCalendarId',
              keepCalendarId,
            ),
      );
      expect(report, isNotNull);
      expect(report!.success, isTrue);
      expect(report.calendarDetails, hasLength(1));
      expect(report.calendarDetails.single.remoteCalendarId, 'remote-keep');
      expect(report.calendarDetails.single.localCalendarId, keepCalendarId);
      expect(report.calendarDetails.single.calendarName, 'Work');
      expect(report.calendarDetails.single.colorHex, '#00AA88');
      expect(report.calendarDetails.single.downloaded, 3);
      expect(logs, hasLength(1));
      final metadata =
          jsonDecode(logs.single.metadataJson!) as Map<String, dynamic>;
      expect(metadata['calendar_books'], 1);
      expect(metadata['downloaded'], 3);
      expect(metadata['calendar_details'], hasLength(1));
    },
  );

  test(
    'managed container binding can reuse or create managed calendars through injected Graph',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        ..._bidirectionalAuthPreferences(),
      });
      final db = createTestDatabase();
      addTearDown(db.close);
      final taskListId = await insertFixtureTaskList(db, name: 'Inbox');
      final taskList = await (db.select(db.taskLists)
            ..where((row) => row.id.equals(taskListId)))
          .getSingle();
      final remoteName = OutlookSyncPolicy.buildManagedCalendarName(
        kind: OutlookManagedCalendarKind.taskMirrorBook,
        containerName: 'Inbox',
      );
      final repository = OutlookSyncBindingsRepository(db);
      final existingGraph = _Gap5ManagedGraphService(
        calendars: <Map<String, dynamic>>[
          <String, dynamic>{'id': 'remote-existing', 'name': remoteName},
        ],
      );

      final reused = await OutlookManagedContainerService(
        config: config,
        bindingsRepository: repository,
        graphServiceFactory: (config, {required syncMode}) => existingGraph,
      ).ensureTaskListMirrorBinding(taskList);

      expect(reused.remoteCalendarId, 'remote-existing');
      expect(reused.remoteCalendarName, remoteName);
      expect(existingGraph.createCalendarCalls, isEmpty);
      await repository.removeTaskListBinding(taskListId);

      final creatingGraph = _Gap5ManagedGraphService(
        calendars: const <Map<String, dynamic>>[],
        createdCalendar: <String, dynamic>{
          'id': 'remote-created',
          'name': remoteName,
        },
      );

      final created = await OutlookManagedContainerService(
        config: config,
        bindingsRepository: repository,
        graphServiceFactory: (config, {required syncMode}) => creatingGraph,
      ).ensureTaskListMirrorBinding(taskList);

      expect(created.remoteCalendarId, 'remote-created');
      expect(creatingGraph.createCalendarCalls, <String>[remoteName]);
      expect(
        creatingGraph.managedFlags,
        <bool>[true],
      );
      expect(
        (await repository.getTaskListBinding(taskListId))!.remoteCalendarId,
        'remote-created',
      );
    },
  );

  test('managed container binding rejects Graph calendars without ids',
      () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ..._bidirectionalAuthPreferences(),
    });
    final db = createTestDatabase();
    addTearDown(db.close);
    final taskListId = await insertFixtureTaskList(db, name: 'No Id');
    final taskList = await (db.select(db.taskLists)
          ..where((row) => row.id.equals(taskListId)))
        .getSingle();
    final graph = _Gap5ManagedGraphService(
      calendars: const <Map<String, dynamic>>[],
      createdCalendar: const <String, dynamic>{'name': 'Missing id'},
    );

    await expectLater(
      OutlookManagedContainerService(
        config: config,
        bindingsRepository: OutlookSyncBindingsRepository(db),
        graphServiceFactory: (config, {required syncMode}) => graph,
      ).ensureTaskListMirrorBinding(taskList),
      throwsA(isA<StateError>()),
    );
  });

  test('auth wrappers delegate launch and token exchange paths', () async {
    final launcher = _Gap5UrlLauncher(launchResult: true);
    UrlLauncherPlatform.instance = launcher;

    final launched = await OutlookAuthService.launchAuth(
      config,
      requestedMode: OutlookSyncMode.bidirectional,
    );
    final session = await OutlookAuthService.loadPendingAuthSession();

    expect(launched, isTrue);
    expect(launcher.launchedUrls, hasLength(1));
    expect(session, isNotNull);
    expect(session!.requestedMode, OutlookSyncMode.bidirectional);

    Map<String, String>? postedBody;
    OutlookAuthService.debugSetTestOverrides(
      networkDiagnostics: () async => const OutlookNetworkDiagnostics(
        canResolveMicrosoftHost: true,
        canReachMicrosoftServer: true,
      ),
      tokenPost: (url, {headers, body, encoding}) async {
        postedBody = Map<String, String>.from(body! as Map);
        return _jsonResponse(<String, Object?>{
          'access_token': 'wrapper-access',
          'refresh_token': 'wrapper-refresh',
          'expires_in': 1200,
          'scope': 'Calendars.Read',
        });
      },
    );

    final token = await OutlookAuthService.exchangeCodeForToken(
      config,
      'code=wrapper-code&state=${session.state}',
      requestedMode: OutlookSyncMode.readOnly,
    );

    expect(postedBody, containsPair('grant_type', 'authorization_code'));
    expect(postedBody, containsPair('code', 'wrapper-code'));
    expect(postedBody, containsPair('code_verifier', session.codeVerifier));
    expect(token.accessToken, 'wrapper-access');
    expect(token.grantedMode, OutlookSyncMode.readOnly);
    expect(await OutlookAuthService.loadPendingAuthSession(), isNull);
  });

  test('legacy token JSON derives expiresIn from stored timestamps', () {
    final obtainedAt = DateTime.utc(2026, 6, 11, 10);
    final expiresAt = obtainedAt.add(const Duration(seconds: 150));

    final token = AuthToken.fromJson(<String, dynamic>{
      'access_token': 'legacy-access',
      'obtained_at': obtainedAt.toIso8601String(),
      'expires_at': expiresAt.toIso8601String(),
      'granted_mode': OutlookSyncMode.readOnly.storageValue,
      'scope': 'Calendars.Read',
    });

    expect(token.expiresInSeconds, 150);
    expect(token.obtainedAt, obtainedAt);
    expect(token.expiresAt, expiresAt);
  });
}

SyncEngine _engine(
  AppDatabase db,
  DataOperationLogRepository operationLogs, {
  required MsGraphServiceFactory graphServiceFactory,
}) {
  return SyncEngine(
    EventRepository(db),
    CalendarBooksRepository(db),
    TaskRepository(db),
    OutlookSyncBindingsRepository(db),
    OutlookTaskMirrorRepository(db),
    const OutlookConfig(clientId: 'client-id'),
    operationLogs,
    graphServiceFactory,
  );
}

Future<int> _insertOutlookCalendar(
  AppDatabase db, {
  required String name,
  required String remoteId,
}) {
  return db.into(db.eventCalendars).insert(
        EventCalendarsCompanion.insert(
          name: name,
          colorHex: const Value('#0078D4'),
          source: const Value('outlook'),
          syncUrl: Value(remoteId),
          createdAt: fixtureNow(),
        ),
      );
}

Map<String, Object> _bidirectionalAuthPreferences() {
  final obtainedAt = DateTime.utc(2026, 6, 11, 9);
  return <String, Object>{
    'outlook_sync_mode': OutlookSyncMode.bidirectional.storageValue,
    'outlook_auth_token': jsonEncode(<String, Object?>{
      'access_token': 'write-access',
      'refresh_token': 'write-refresh',
      'expires_in': 3600,
      'obtained_at': obtainedAt.toIso8601String(),
      'expires_at': DateTime.utc(2099).toIso8601String(),
      'granted_mode': OutlookSyncMode.bidirectional.storageValue,
      'scope': 'Calendars.Read Calendars.ReadWrite offline_access',
    }),
  };
}

Map<String, dynamic> _graphEvent({
  required String id,
  required String subject,
  required DateTime start,
  required String location,
}) {
  return <String, dynamic>{
    'id': id,
    'subject': subject,
    'body': <String, dynamic>{
      'contentType': 'text',
      'content': '$subject body',
    },
    'bodyPreview': '$subject preview',
    'location': <String, dynamic>{'displayName': location},
    'start': <String, dynamic>{'dateTime': start.toIso8601String()},
    'end': <String, dynamic>{
      'dateTime': start.add(const Duration(hours: 1)).toIso8601String(),
    },
    'showAs': 'tentative',
  };
}

class _Gap5EventBatch {
  const _Gap5EventBatch({
    required this.events,
    this.deltaLink,
  });

  final List<Map<String, dynamic>> events;
  final String? deltaLink;
}

class _Gap5GraphService extends MsGraphService {
  _Gap5GraphService({
    required this.calendars,
    required this.eventBatches,
    required this.fullEvents,
  }) : super(
          const OutlookConfig(clientId: 'gap5-fake'),
          syncMode: OutlookSyncMode.readOnly,
        );

  final List<Map<String, dynamic>> calendars;
  final Map<String, _Gap5EventBatch> eventBatches;
  final Map<String, Map<String, dynamic>> fullEvents;
  final seenDeltaLinks = <String?>[];
  final hydratedEventIds = <String>[];

  @override
  Future<List<Map<String, dynamic>>> getCalendars() async => calendars;

  @override
  Future<({List<Map<String, dynamic>> events, String? deltaLink})> getEvents({
    required String calendarId,
    String? deltaLink,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    seenDeltaLinks.add(deltaLink);
    final batch = eventBatches[calendarId] ??
        const _Gap5EventBatch(events: <Map<String, dynamic>>[]);
    return (events: batch.events, deltaLink: batch.deltaLink);
  }

  @override
  Future<Map<String, dynamic>?> getEvent({
    required String calendarId,
    required String eventId,
  }) async {
    final key = '$calendarId/$eventId';
    hydratedEventIds.add(key);
    return fullEvents[key];
  }
}

class _Gap5ManagedGraphService extends MsGraphService {
  _Gap5ManagedGraphService({
    required this.calendars,
    this.createdCalendar,
  }) : super(
          const OutlookConfig(clientId: 'gap5-fake'),
          syncMode: OutlookSyncMode.bidirectional,
        );

  final List<Map<String, dynamic>> calendars;
  final Map<String, dynamic>? createdCalendar;
  final createCalendarCalls = <String>[];
  final managedFlags = <bool>[];

  @override
  Future<List<Map<String, dynamic>>> getCalendars() async => calendars;

  @override
  Future<Map<String, dynamic>> createCalendar({
    required String name,
    required bool isFlowPlanV2ManagedContainer,
  }) async {
    createCalendarCalls.add(name);
    managedFlags.add(isFlowPlanV2ManagedContainer);
    return createdCalendar ?? <String, dynamic>{'id': 'created-$name'};
  }
}

class _Gap5UrlLauncher extends UrlLauncherPlatform {
  _Gap5UrlLauncher({required this.launchResult});

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

http.Response _jsonResponse(Map<String, Object?> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}
