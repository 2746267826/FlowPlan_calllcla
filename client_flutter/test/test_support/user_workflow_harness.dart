import 'package:flowplanv2/app.dart';
import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/router/app_router.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_first/server_first_repository.dart';
import 'package:flowplanv2/core/server_first/task_event_server_first_store.dart';
import 'package:flowplanv2/core/server_api/ai_api.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/client_api.dart';
import 'package:flowplanv2/core/server_api/reports_api.dart';
import 'package:flowplanv2/core/server_first/tracking_server_first_store.dart';
import 'package:flowplanv2/core/sync/sync_cursor_store.dart';
import 'package:flowplanv2/core/sync/sync_engine.dart';
import 'package:flowplanv2/core/sync/sync_result.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_runner.dart';
import 'package:flowplanv2/core/offline_queue/offline_mutation_store.dart';
import 'package:flowplanv2/features/calendar/presentation/calendar_shell.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flowplanv2/features/reports/presentation/report_center_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'provider_harness.dart';
import 'test_database.dart';

Future<void> pumpShellNavigationHarness(
  WidgetTester tester, {
  required Size size,
}) async {
  Widget shellRoute(String label) => Center(child: Text(label));

  final router = GoRouter(
    initialLocation: AppRoutes.timeline,
    routes: [
      ShellRoute(
        builder: (context, state, child) => CalendarShell(
          currentRoute: state.uri.path,
          child: child,
        ),
        routes: [
          GoRoute(
            path: AppRoutes.timeline,
            builder: (context, state) => shellRoute('timeline route'),
          ),
          GoRoute(
            path: AppRoutes.week,
            builder: (context, state) => shellRoute('week route'),
          ),
          GoRoute(
            path: AppRoutes.month,
            builder: (context, state) => shellRoute('month route'),
          ),
          GoRoute(
            path: AppRoutes.tracker,
            builder: (context, state) => shellRoute('tracker route'),
          ),
          GoRoute(
            path: AppRoutes.reports,
            builder: (context, state) => shellRoute('reports route'),
          ),
          GoRoute(
            path: AppRoutes.files,
            builder: (context, state) => shellRoute('files route'),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (context, state) => shellRoute('settings route'),
          ),
        ],
      ),
    ],
  );

  final db = createTestDatabase();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpTeardownFrames(tester);
    router.dispose();
    await db.close();
  });

  await pumpFlowPlanTestApp(
    tester,
    db: db,
    size: size,
    child: FlowPlanV2App(routerOverride: router),
  );
  await tester.pump();
}

Future<void> pumpAppAt(
  WidgetTester tester, {
  AppDatabase? db,
  required String initialLocation,
  Size size = const Size(390, 844),
  List<Override> overrides = const <Override>[],
}) async {
  final ownedDb = db ?? createTestDatabase();
  final router = createAppRouter(initialLocation: initialLocation);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpTeardownFrames(tester);
    router.dispose();
    if (db == null) {
      await ownedDb.close();
    }
  });

  await pumpFlowPlanTestApp(
    tester,
    db: ownedDb,
    size: size,
    overrides: overrides,
    child: FlowPlanV2App(routerOverride: router),
  );
  await tester.pump();
}

Future<void> _pumpTeardownFrames(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

TaskList fixtureTaskList() {
  return TaskList(
    id: 1,
    name: 'Inbox',
    colorHex: '#0EA8A0',
    emoji: 'I',
    isVisible: true,
    isDefault: true,
    isArchived: false,
    createdAt: DateTime.utc(2026, 6, 8),
  );
}

Future<void> tapShellDestination(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await tester.pump();
  await tester.pump();
}

Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 10,
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(
    finder,
    findsWidgets,
    reason: 'Expected finder to appear within $maxPumps bounded pumps.',
  );
}

Future<void> chooseDropdownMenuItemByValue(
  WidgetTester tester, {
  required Finder dropdown,
  required String valueFragment,
}) async {
  await tester.tap(dropdown);
  await _pumpOverlayFrames(tester);
  final menuItem = find.byWidgetPredicate(
    (widget) =>
        widget is DropdownMenuItem &&
        widget.value.toString().contains(valueFragment),
  );
  expect(menuItem, findsWidgets);
  final itemText = find
      .descendant(
        of: menuItem.last,
        matching: find.byType(Text),
      )
      .hitTestable();
  expect(itemText, findsWidgets);
  await tester.tap(itemText.last);
  await _pumpOverlayFrames(tester);
}

Future<void> _pumpOverlayFrames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Override emptyReportSnapshotOverride() {
  return reportCenterSnapshotProvider.overrideWith((ref) async {
    return <String, dynamic>{
      'reports': <Map<String, Object?>>[],
      'diary': <Map<String, Object?>>[],
      'weatherLocations': <Map<String, Object?>>[],
      'weatherSummary': <Map<String, Object?>>[],
      'channels': <Map<String, Object?>>[],
      'deliveries': <Map<String, Object?>>[],
    };
  });
}

class FakeReportsApi implements ReportsApi {
  FakeReportsApi({
    List<Map<String, dynamic>> reports = const <Map<String, dynamic>>[],
    List<Map<String, dynamic>> diary = const <Map<String, dynamic>>[],
    this.polishReportAppliesLlm = true,
  })  : reportsList = [
          for (final report in reports) Map<String, dynamic>.from(report),
        ],
        diaryList = [
          for (final entry in diary) Map<String, dynamic>.from(entry),
        ];

  final List<Map<String, dynamic>> reportsList;
  final List<Map<String, dynamic>> diaryList;
  final bool polishReportAppliesLlm;
  var generatedReports = 0;
  final openedReportIds = <String>[];
  final updatedReports = <Map<String, Object?>>[];
  final polishedReportIds = <String>[];
  final pushedReportIds = <String>[];

  @override
  Future<Map<String, dynamic>> reports({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    return <String, dynamic>{
      'items': _pagedItems(reportsList,
          status: status, limit: limit, offset: offset),
    };
  }

  @override
  Future<Map<String, dynamic>> report(String reportId) async {
    openedReportIds.add(reportId);
    final report = Map<String, dynamic>.from(_findReport(reportId));
    report.putIfAbsent('contentMarkdown', () => 'Completed deep work.');
    return <String, dynamic>{
      'report': report,
      'entries': <Map<String, Object?>>[
        <String, Object?>{
          'claimType': 'summary',
          'title': 'Focus block',
          'body': '2h focus session',
        },
      ],
      'evidence': <Map<String, Object?>>[
        <String, Object?>{
          'evidenceType': 'activity',
          'sourceType': 'tracker',
          'sourceId': 'segment-1',
          'summary': 'Timer log',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> generateReport({
    String reportType = 'daily',
    required DateTime periodStart,
    required DateTime periodEnd,
    bool autoConfirm = false,
  }) async {
    generatedReports++;
    final report = <String, dynamic>{
      'id': 'generated-report-$generatedReports',
      'title': 'Daily report',
      'reportType': reportType,
      'status': autoConfirm ? 'confirmed' : 'draft',
      'contentMarkdown': 'Generated report draft',
      'createdAt': periodStart.toIso8601String(),
      'updatedAt': periodEnd.toIso8601String(),
    };
    reportsList.insert(0, report);
    return <String, dynamic>{
      'report': Map<String, dynamic>.from(report),
    };
  }

  @override
  Future<Map<String, dynamic>> updateReport({
    required String reportId,
    String? title,
    String? contentMarkdown,
    String? userNote,
  }) async {
    updatedReports.add(<String, Object?>{
      'reportId': reportId,
      'title': title,
      'contentMarkdown': contentMarkdown,
      'userNote': userNote,
    });
    final report = _findReport(reportId);
    if (title != null) {
      report['title'] = title;
    }
    if (contentMarkdown != null) {
      report['contentMarkdown'] = contentMarkdown;
    }
    return <String, dynamic>{'report': Map<String, dynamic>.from(report)};
  }

  @override
  Future<Map<String, dynamic>> polishReport(String reportId) async {
    polishedReportIds.add(reportId);
    final report = _findReport(reportId);
    report['contentMarkdown'] =
        '${report['contentMarkdown'] ?? ''}\n\nPolished by AI.';
    return <String, dynamic>{
      'llmApplied': polishReportAppliesLlm,
      'report': Map<String, dynamic>.from(report),
    };
  }

  @override
  Future<Map<String, dynamic>> pushReport({
    required String reportId,
    String? channelId,
  }) async {
    pushedReportIds.add(reportId);
    return <String, dynamic>{
      'delivery': <String, Object?>{'id': 'delivery-1', 'status': 'sent'},
    };
  }

  @override
  Future<Map<String, dynamic>> diary({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    return <String, dynamic>{
      'items':
          _pagedItems(diaryList, status: status, limit: limit, offset: offset),
    };
  }

  @override
  Future<Map<String, dynamic>> weatherLocations() async {
    return <String, dynamic>{'items': <Map<String, Object?>>[]};
  }

  @override
  Future<Map<String, dynamic>> weatherSummary() async {
    return <String, dynamic>{'items': <Map<String, Object?>>[]};
  }

  @override
  Future<Map<String, dynamic>> pushChannels() async {
    return <String, dynamic>{'items': <Map<String, Object?>>[]};
  }

  @override
  Future<Map<String, dynamic>> pushDeliveries({
    String? status,
    int limit = 50,
  }) async {
    return <String, dynamic>{'items': <Map<String, Object?>>[]};
  }

  Map<String, dynamic> _findReport(String reportId) {
    return reportsList.firstWhere(
      (report) => '${report['id']}' == reportId,
      orElse: () {
        final report = <String, dynamic>{
          'id': reportId,
          'title': 'Daily report',
          'reportType': 'daily',
          'status': 'draft',
          'contentMarkdown': 'Generated report draft',
        };
        reportsList.add(report);
        return report;
      },
    );
  }

  List<Map<String, dynamic>> _pagedItems(
    List<Map<String, dynamic>> source, {
    required String? status,
    required int limit,
    required int offset,
  }) {
    final items = status == null
        ? source
        : source.where((item) => '${item['status']}' == status).toList();
    return [
      for (final item in items.skip(offset).take(limit))
        Map<String, dynamic>.from(item),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAiApi implements AiApi {
  FakeAiApi({
    this.conversationId = 'conversation-1',
    this.replyContent = 'AI reply',
    this.sendMessageError,
  });

  final String conversationId;
  final String replyContent;
  final Object? sendMessageError;
  final sentMessages = <Map<String, Object?>>[];
  Map<String, Object?>? createConversationRequest;

  @override
  Future<Map<String, dynamic>> createConversation({
    String title = 'AI chat',
    String source = 'flowplanv2',
    String? providerKey,
    String? model,
    Map<String, Object?> contextScope = const <String, Object?>{},
  }) async {
    createConversationRequest = <String, Object?>{
      'title': title,
      'source': source,
      'providerKey': providerKey,
      'model': model,
      'contextScope': contextScope,
    };
    return <String, dynamic>{
      'conversation': <String, dynamic>{'id': conversationId},
    };
  }

  @override
  Future<Map<String, dynamic>> sendMessage({
    String? conversationId,
    required String content,
    String source = 'flowplanv2',
    String? providerKey,
    String? model,
    String? title,
    Map<String, Object?> contextScope = const <String, Object?>{},
  }) async {
    sentMessages.add(<String, Object?>{
      'conversationId': conversationId,
      'content': content,
      'source': source,
      'providerKey': providerKey,
      'model': model,
      'title': title,
      'contextScope': contextScope,
    });
    final error = sendMessageError;
    if (error != null) {
      throw error;
    }
    return <String, dynamic>{
      'message': <String, dynamic>{
        'id': 'message-${sentMessages.length}',
        'content': replyContent,
      },
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeLocalServerWrite {
  const FakeLocalServerWrite({
    required this.localId,
    required this.payload,
    this.changedFields,
  });

  final int localId;
  final Map<String, Object?> payload;
  final List<String>? changedFields;
}

class FakeTaskEventServerFirstStore implements TaskEventServerFirstStore {
  final createdTasks = <Map<String, Object?>>[];
  final updatedTasks = <FakeLocalServerWrite>[];
  final completedTaskIds = <int>[];
  final deletedTaskIds = <int>[];
  final createdEvents = <Map<String, Object?>>[];
  final updatedEvents = <FakeLocalServerWrite>[];
  final deletedEventIds = <int>[];

  @override
  Future<Map<String, dynamic>> tasks({
    DateTime? from,
    DateTime? to,
    String? q,
    int? limit,
  }) async {
    return <String, dynamic>{'items': <Map<String, Object?>>[]};
  }

  @override
  Future<Map<String, dynamic>> events({
    DateTime? from,
    DateTime? to,
    String? q,
    int? limit,
  }) async {
    return <String, dynamic>{'items': <Map<String, Object?>>[]};
  }

  @override
  Future<ServerFirstWriteResult> createTask(
    Map<String, Object?> payload,
  ) async {
    createdTasks.add(Map<String, Object?>.from(payload));
    return _canonical('task', createdTasks.length, payload);
  }

  @override
  Future<ServerFirstWriteResult> updateLocalTask({
    required int localId,
    required Map<String, Object?> patch,
    int? baseServerVersion,
    List<String>? changedFields,
  }) async {
    updatedTasks.add(
      FakeLocalServerWrite(
        localId: localId,
        payload: Map<String, Object?>.from(patch),
        changedFields:
            changedFields == null ? null : List<String>.from(changedFields),
      ),
    );
    return _canonical('task', localId, patch);
  }

  @override
  Future<ServerFirstWriteResult> completeLocalTask({
    required int localId,
    Map<String, Object?> body = const <String, Object?>{},
    int? baseServerVersion,
  }) async {
    completedTaskIds.add(localId);
    return _canonical('task', localId, body);
  }

  @override
  Future<ServerFirstWriteResult> deleteLocalTask({
    required int localId,
    int? baseServerVersion,
  }) async {
    deletedTaskIds.add(localId);
    return _canonical('task', localId, <String, Object?>{'id': localId});
  }

  @override
  Future<ServerFirstWriteResult> createEvent(
    Map<String, Object?> payload,
  ) async {
    createdEvents.add(Map<String, Object?>.from(payload));
    return _canonical('event', createdEvents.length, payload);
  }

  @override
  Future<ServerFirstWriteResult> updateLocalEvent({
    required int localId,
    required Map<String, Object?> patch,
    int? baseServerVersion,
    List<String>? changedFields,
  }) async {
    updatedEvents.add(
      FakeLocalServerWrite(
        localId: localId,
        payload: Map<String, Object?>.from(patch),
        changedFields:
            changedFields == null ? null : List<String>.from(changedFields),
      ),
    );
    return _canonical('event', localId, patch);
  }

  @override
  Future<ServerFirstWriteResult> deleteLocalEvent({
    required int localId,
    int? baseServerVersion,
  }) async {
    deletedEventIds.add(localId);
    return _canonical('event', localId, <String, Object?>{'id': localId});
  }

  ServerFirstWriteResult _canonical(
    String type,
    Object id,
    Map<String, Object?> payload,
  ) {
    return ServerFirstWriteResult.canonical(
      <String, dynamic>{
        'serverVersion': 1,
        'item': <String, dynamic>{
          'id': '$type-$id',
          'uid': payload['uid'],
          'payload': payload,
        },
      },
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTrackingServerFirstStore implements TrackingServerFirstStore {
  final confirmedSegmentIds = <String>[];
  final confirmedSegments = <Map<String, Object?>>[];
  final rejectedSegments = <Map<String, Object?>>[];
  var buildSegmentsCalls = 0;

  @override
  Future<Map<String, dynamic>> activityDaySummary({
    required DateTime date,
  }) async {
    return <String, dynamic>{
      'insights': <String, Object?>{'totalMinutes': 0},
      'records': <Map<String, Object?>>[],
      'workSessions': <Map<String, Object?>>[],
    };
  }

  @override
  Future<Map<String, dynamic>> activityHeatmap({
    DateTime? start,
    DateTime? end,
    String bucket = 'day',
    String? processName,
    String? category,
    int? taskId,
  }) async {
    return <String, dynamic>{'buckets': <Map<String, Object?>>[]};
  }

  @override
  Future<Map<String, dynamic>> inputHeatmap({
    DateTime? start,
    DateTime? end,
    String bucket = 'hour',
    String? processName,
    String? category,
    String? eventKind,
  }) async {
    return <String, dynamic>{'buckets': <Map<String, Object?>>[]};
  }

  @override
  Future<Map<String, dynamic>> segments({
    DateTime? startAt,
    DateTime? endAt,
    String? status,
    int limit = 100,
    int offset = 0,
  }) async {
    return <String, dynamic>{
      'items': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'segment-1',
          'segmentUid': 'segment-1',
          'startAt': DateTime.utc(2026, 6, 8, 9).toIso8601String(),
          'endAt': DateTime.utc(2026, 6, 8, 9, 30).toIso8601String(),
          'title': 'Focused coding',
          'summary': 'Focused coding',
          'primaryProcessName': 'Code.exe',
          'primaryWindowTitle': 'FlowPlanV2 tests',
          'category': 'coding',
          'confidence': 0.91,
          'status': 'candidate',
          'evidence': <String, Object?>{
            'activityRecordCount': 1,
            'rawLogCount': 2,
            'inputEventCount': 3,
          },
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> confirmSegment({
    required String segmentId,
    String? title,
    String? taskId,
    String? note,
  }) async {
    confirmedSegmentIds.add(segmentId);
    confirmedSegments.add(<String, Object?>{
      'segmentId': segmentId,
      'title': title,
      'taskId': taskId,
      'note': note,
    });
    return <String, dynamic>{'taskId': taskId};
  }

  @override
  Future<Map<String, dynamic>> rejectSegment({
    required String segmentId,
    String? reason,
  }) async {
    rejectedSegments.add(<String, Object?>{
      'segmentId': segmentId,
      'reason': reason,
    });
    return <String, dynamic>{'segmentId': segmentId, 'status': 'rejected'};
  }

  @override
  Future<Map<String, dynamic>> buildSegments({
    required DateTime date,
    bool includeTrackedInputEvents = true,
    bool includeRawActivityLogs = true,
    bool includeActivityRecords = true,
  }) async {
    buildSegmentsCalls++;
    return <String, dynamic>{
      'rawCount': 1,
      'segmentsCreated': 1,
      'segmentsUpdated': 0,
      'lowConfidenceCount': 0,
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeClientApi extends ClientApi {
  FakeClientApi(AppDatabase db) : super(_mockApiClient(db));

  var bootstrapCalls = 0;
  var settingsCalls = 0;
  Object? bootstrapError;

  @override
  Future<Map<String, dynamic>> bootstrap() async {
    bootstrapCalls++;
    final error = bootstrapError;
    if (error != null) {
      throw error;
    }
    return <String, dynamic>{
      'mode': 'server_first',
      'serverReachable': true,
      'syncCursor': 'cursor-after-bootstrap',
      'settingsVersion': 7,
      'pendingActions': <String>[],
    };
  }

  @override
  Future<Map<String, dynamic>> settings() async {
    settingsCalls++;
    return <String, dynamic>{
      'version': 7,
      'updatedAt': DateTime.utc(2026, 6, 8, 10).toIso8601String(),
      'settings': <Map<String, Object?>>[],
      'policy': <String, Object?>{},
    };
  }
}

class FakeServerSyncEngine extends ServerSyncEngine {
  FakeServerSyncEngine(AppDatabase db)
      : super(
          apiClient: _mockApiClient(db),
          cursorStore: SyncCursorStore(db),
          offlineMutationRunner: OfflineMutationRunner(
            OfflineMutationStore(db),
          ),
        );

  var pushCalls = 0;
  var pullCalls = 0;

  @override
  Future<ServerSyncResult> pushPending() async {
    pushCalls++;
    return const ServerSyncResult(
      pendingCount: 2,
      acceptedCount: 1,
      conflictCount: 1,
      rejectedCount: 0,
    );
  }

  @override
  Future<Map<String, dynamic>> pullChanges({
    int limit = 200,
    void Function(int pulledChanges, int pageCount)? onProgress,
  }) async {
    pullCalls++;
    onProgress?.call(3, 1);
    return <String, dynamic>{
      'changes': <Map<String, Object?>>[
        <String, Object?>{'id': 'change-1'},
        <String, Object?>{'id': 'change-2'},
        <String, Object?>{'id': 'change-3'},
      ],
      'pulledChanges': 3,
      'appliedChanges': 2,
      'skippedChanges': 1,
      'failedChanges': 0,
      'pageCount': 1,
    };
  }
}

class FakeReminderService extends ReminderService {
  FakeReminderService(AppDatabase db)
      : super(
          database: db,
          defaultEventReminderMinutes: () => 0,
        );

  var rebuildCalls = 0;

  @override
  Future<ReminderRebuildResult> rebuildSystemSchedule() async {
    rebuildCalls++;
    return const ReminderRebuildResult(
      scheduledCount: 0,
      canScheduleExactAlarms: false,
    );
  }
}

Future<void> seedSyncDiagnostics(AppDatabase db) async {
  final now = DateTime.utc(2026, 6, 8, 10).toIso8601String();
  await db.customStatement(
    '''
    INSERT INTO offline_mutations (
      mutation_uid, object_type, local_id, action, payload_json,
      created_at, status, attempts, last_error
    ) VALUES
      ('mutation-pending', 'task_item', '101', 'create', '{}', ?, 'pending', 0, NULL),
      ('mutation-failed', 'calendar_event', '202', 'update', '{}', ?, 'failed', 2, 'network timeout')
    ''',
    [now, now],
  );
  await db.customStatement(
    '''
    INSERT INTO sync_object_states (
      object_type, local_id, server_id, sync_state, local_version,
      server_version, created_at, updated_at, last_sync_error
    ) VALUES
      ('task_item', '101', NULL, 'pending_create', 1, 0, ?, ?, NULL),
      ('calendar_event', '202', 'event-202', 'failed', 2, 1, ?, ?, 'remote rejected')
    ''',
    [now, now, now, now],
  );
}

ApiClient _mockApiClient(AppDatabase db) {
  return ApiClient(
    baseUri: Uri.parse('http://localhost:3202/api'),
    tokenStore: AuthTokenStore(db),
    httpClient: MockClient((request) async {
      return http.Response('{"ok":true}', 200);
    }),
  );
}
