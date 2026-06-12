import 'dart:convert';
import 'dart:io';

import 'package:flowplanv2/core/database/app_database.dart';
import 'package:flowplanv2/core/server_api/api_client.dart';
import 'package:flowplanv2/core/server_api/auth_token_store.dart';
import 'package:flowplanv2/core/server_api/client_api.dart';
import 'package:flowplanv2/features/calendar/data/calendar_books_repository.dart';
import 'package:flowplanv2/features/reminders/reminder_service.dart';
import 'package:flowplanv2/features/sync/outlook_auth_service.dart';
import 'package:flowplanv2/features/sync/outlook_settings_page.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_binding.dart';
import 'package:flowplanv2/features/sync/outlook_task_mirror_repository.dart';
import 'package:flowplanv2/shared/providers/app_providers.dart';
import 'package:flowplanv2/shared/providers/database_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../test_support/outlook_settings_test_harness.dart';
import '../test_support/test_database.dart';

void main() {
  setUp(OutlookAuthService.debugResetTestOverrides);
  tearDown(OutlookAuthService.debugResetTestOverrides);

  testWidgets(
    'server-managed diagnostics expands failed run samples and fallback data',
    (tester) async {
      final harness = await _pumpServerManagedOutlookSettings(tester);

      await _waitForTextContaining(tester, 'worker-gap3-manual');

      expect(find.textContaining('字段覆盖：事件 7'), findsOneWidget);
      expect(find.textContaining('缺地点 2'), findsOneWidget);
      expect(find.textContaining('worker-gap3-manual'), findsOneWidget);
      expect(find.text('日历 3，更新 5，删除 1'), findsOneWidget);
      expect(harness.clientApi.adminRunsCalls, 1);
      expect(harness.clientApi.adminDiagnosticsCalls, 1);

      await tester.tap(find.textContaining('worker-gap3-manual').first);
      await pumpOutlookSettingFrames(tester);

      expect(find.textContaining('gap3 Microsoft 429'), findsOneWidget);
      expect(find.textContaining('Graph 字段统计：总事件 7'), findsOneWidget);
      expect(
          find.textContaining('日历分页：Primary 2页/5项；Team 1页/2项'), findsOneWidget);
      expect(find.textContaining('Graph: id=evt-gap3'), findsOneWidget);
      expect(
          find.textContaining('occurrence master fallback 样本'), findsOneWidget);
      expect(find.textContaining('Graph: id=occ-gap3'), findsOneWidget);
    },
  );

  testWidgets(
    'server-managed diagnostics falls back to recentRuns when runs are absent',
    (tester) async {
      final harness = await _pumpServerManagedOutlookSettings(
        tester,
        runs: const <Map<String, Object?>>[],
        recentRuns: <Map<String, Object?>>[
          _runLog(
            triggerSource: 'worker-gap3-recent',
            status: 'succeeded',
            calendarCount: 1,
            eventUpserts: 2,
            eventDeletes: 0,
          ),
        ],
      );

      await _waitForTextContaining(tester, 'worker-gap3-recent');

      expect(find.textContaining('worker-gap3-recent'), findsOneWidget);
      expect(find.text('日历 1，更新 2，删除 0'), findsOneWidget);
      expect(harness.clientApi.adminRunsCalls, 1);
      expect(harness.clientApi.adminDiagnosticsCalls, 1);
    },
  );

  testWidgets(
    'last sync report renders zero-change calendar and mirror summaries',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: _zeroChangeLastSyncPreferences(),
      );

      expect(find.text('日历本级摘要'), findsOneWidget);
      expect(
        find.textContaining('本次共检查 2 个 Outlook 日历'),
        findsOneWidget,
      );
      expect(find.text('任务镜像级摘要'), findsOneWidget);
      expect(
        find.text('本次未发生任务镜像写回变更。'),
        findsOneWidget,
      );
      expect(find.textContaining('即便在双向同步下'), findsOneWidget);

      await _expandSection(tester, '使用说明');
      expect(find.text('1.'), findsOneWidget);
      expect(find.textContaining('注册 Public Client 应用'), findsOneWidget);
      expect(find.textContaining('Outlook 普通日历默认保持只读'), findsOneWidget);
    },
  );

  testWidgets(
    'last sync report sorts tied calendar and mirror details by name',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: _tiedLastSyncPreferences(),
      );

      final calendarA = find.text('Alpha Calendar');
      final calendarB = find.text('Beta Calendar');
      expect(calendarA, findsOneWidget);
      expect(calendarB, findsOneWidget);
      expect(
        tester.getTopLeft(calendarA).dy,
        lessThan(tester.getTopLeft(calendarB).dy),
      );

      final mirrorA = find.text('Alpha Mirror');
      final mirrorB = find.text('Beta Mirror');
      expect(mirrorA, findsOneWidget);
      expect(mirrorB, findsOneWidget);
      expect(
        tester.getTopLeft(mirrorA).dy,
        lessThan(tester.getTopLeft(mirrorB).dy),
      );
    },
  );

  testWidgets(
    'expired token generic refresh failures are reported on load',
    (tester) async {
      OutlookAuthService.debugSetTestOverrides(
        networkDiagnostics: () async => const OutlookNetworkDiagnostics(
          canResolveMicrosoftHost: true,
          canReachMicrosoftServer: true,
        ),
        tokenPost: (url, {headers, body, encoding}) async {
          throw StateError('gap3-refresh-crashed');
        },
      );

      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          accessToken: 'expired-access',
          refreshToken: 'refresh-token',
          expiresAt: DateTime.utc(2020),
        ),
      );

      expect(find.textContaining('Outlook token 刷新失败'), findsOneWidget);
      expect(find.textContaining('gap3-refresh-crashed'), findsOneWidget);
    },
  );

  testWidgets(
    'auth submit and manual sync stop at missing OAuth config',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: const <String, Object>{},
      );

      await tester.enterText(
        find.byType(TextField).last,
        'https://callback.local/?code=gap3&state=missing',
      );
      await _tapText(tester, '提交授权码');
      expect(find.text('请先保存 OAuth 配置。'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await pumpOutlookSettingFrames(tester);

      final authenticatedWithoutConfig = outlookAuthPreferences()
        ..remove('outlook_client_id');
      await pumpLocalOutlookSettings(
        tester,
        preferences: authenticatedWithoutConfig,
      );

      await _tapText(tester, '手动同步 Outlook 日历');
      await _waitForTextContaining(tester, 'OAuth 凭据');
      expect(find.textContaining('请先配置 OAuth 凭据'), findsOneWidget);
    },
  );

  testWidgets(
    'conflict actions can be cancelled and confirmed guards stop without config',
    (tester) async {
      final preferences = outlookAuthPreferences(
        syncMode: OutlookSyncMode.bidirectional,
        grantedMode: OutlookSyncMode.bidirectional,
        scope: 'Calendars.Read Calendars.ReadWrite offline_access',
      )..remove('outlook_client_id');
      final harness = await pumpLocalOutlookSettings(
        tester,
        preferences: preferences,
        seedData: true,
      );
      final before = await harness.countTaskMirrorBindings();

      await _expandSection(tester, '诊断与冲突');
      await _tapText(tester, '以本地为准');
      expect(find.text('以 FlowPlanV2 为准'), findsOneWidget);
      await _tapDialogButton(tester, '取消');
      expect(await harness.countTaskMirrorBindings(), before);
      expect(find.text('以 FlowPlanV2 为准'), findsNothing);

      await _tapText(tester, '重建远端镜像');
      expect(find.text('重建远端镜像'), findsWidgets);
      await _tapDialogButton(tester, '确认');
      expect(find.textContaining('请先配置 OAuth 凭据'), findsOneWidget);
      expect(await harness.countTaskMirrorBindings(), before);
    },
  );

  testWidgets(
    'batch conflict actions run through empty service results',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
        ),
        extraOverrides: <Override>[
          outlookFieldConflictSummariesProvider.overrideWith(
            (ref) async => <OutlookFieldConflictSummary>[
              _conflictSummary(
                taskId: 41,
                taskSummary: 'Gap3 local push',
                state: OutlookTaskMirrorConflictState.pendingLocalPush,
                canPushLocal: true,
              ),
              _conflictSummary(
                taskId: 42,
                taskSummary: 'Gap3 remote deleted',
                state: OutlookTaskMirrorConflictState.remoteDeleted,
                canPushLocal: true,
                canRecreateRemote: true,
                canDetachMirror: true,
              ),
            ],
          ),
        ],
      );

      await _expandSection(tester, '诊断与冲突');
      await _tapTextContaining(tester, '批量按本地覆盖远端');
      expect(find.text('批量按本地覆盖远端'), findsWidgets);
      await _tapDialogButton(tester, '确认');
      expect(find.textContaining('当前没有可批量写回的任务镜像'), findsOneWidget);

      await _tapTextContaining(tester, '批量重建已删除镜像');
      expect(find.text('批量重建远端镜像'), findsWidgets);
      await _tapDialogButton(tester, '确认');
      expect(find.textContaining('当前没有已删除的远端镜像需要重建'), findsOneWidget);
    },
  );

  testWidgets(
    'conflict action runners surface unexpected service failures',
    (tester) async {
      final throwingDb = createTestDatabase();
      addTearDown(throwingDb.close);

      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
        ),
        extraOverrides: <Override>[
          outlookFieldConflictSummariesProvider.overrideWith(
            (ref) async => <OutlookFieldConflictSummary>[
              _conflictSummary(
                taskId: 51,
                taskSummary: 'Gap3 all actions',
                state: OutlookTaskMirrorConflictState.divergent,
                canPushLocal: true,
                canPullRemote: true,
                canRecreateRemote: true,
                canDetachMirror: true,
              ),
            ],
          ),
          outlookTaskMirrorRepositoryProvider.overrideWithValue(
            _ThrowingTaskMirrorRepository(throwingDb),
          ),
        ],
      );

      await _expandSection(tester, '诊断与冲突');

      for (final label in <String>[
        '以本地为准',
        '采用 Outlook 内容',
        '重建远端镜像',
      ]) {
        await _tapText(tester, label);
        await _tapDialogButton(tester, '确认');
        expect(find.textContaining('gap3-mirror-repo-down'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'read-only conflict and cleanup actions surface write-mode guards',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.readOnly,
          grantedMode: OutlookSyncMode.readOnly,
        ),
        seedData: true,
      );

      await _expandSection(tester, '诊断与冲突');
      await _tapTextContaining(tester, '批量按本地覆盖远端');
      expect(find.text('批量按本地覆盖远端'), findsWidgets);
      await _tapDialogButton(tester, '确认');
      expect(find.textContaining('请先切换到“双向同步”模式'), findsOneWidget);

      await _expandSection(tester, '同步对象');
      await _tapText(tester, '切换为双向同步');
      expect(find.textContaining('请重新认证一次'), findsOneWidget);
    },
  );

  testWidgets(
    'missing write grant blocks conflict actions before service creation',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.readOnly,
          scope: 'Calendars.Read offline_access',
        ),
        extraOverrides: <Override>[
          outlookFieldConflictSummariesProvider.overrideWith(
            (ref) async => <OutlookFieldConflictSummary>[
              _conflictSummary(
                taskId: 61,
                taskSummary: 'Gap3 missing grant',
                state: OutlookTaskMirrorConflictState.pendingLocalPush,
                canPushLocal: true,
              ),
            ],
          ),
        ],
      );

      await _expandSection(tester, '诊断与冲突');
      await _tapText(tester, '以本地为准');
      await _tapDialogButton(tester, '确认');
      expect(find.textContaining('当前没有 Outlook 读写授权'), findsOneWidget);
    },
  );

  testWidgets(
    'last failed sync reauth action starts the auth flow',
    (tester) async {
      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.readOnly,
          scope: 'Calendars.Read offline_access',
          includeLastFailure: true,
        ),
      );

      await _tapText(tester, '重新进行读写授权');
      expect(find.textContaining('无法打开浏览器'), findsOneWidget);
    },
  );

  testWidgets(
    'mirror cleanup and Outlook reset report provider failures',
    (tester) async {
      final mirrorDb = createTestDatabase();
      final calendarDb = createTestDatabase();
      addTearDown(mirrorDb.close);
      addTearDown(calendarDb.close);

      await pumpLocalOutlookSettings(
        tester,
        preferences: outlookAuthPreferences(
          syncMode: OutlookSyncMode.bidirectional,
          grantedMode: OutlookSyncMode.bidirectional,
          scope: 'Calendars.Read Calendars.ReadWrite offline_access',
        ),
        seedData: true,
        extraOverrides: <Override>[
          outlookTaskMirrorDiagnosticsProvider.overrideWith(
            (ref) async => const OutlookTaskMirrorDiagnostics(
              totalBindings: 1,
              activeBindings: 0,
              pendingCleanup: 1,
              missingTasks: 1,
              unboundTaskLists: 0,
              movedTargets: 0,
              localChangedSinceLastMirror: 0,
            ),
          ),
          outlookTaskMirrorRepositoryProvider.overrideWithValue(
            _ThrowingTaskMirrorRepository(mirrorDb),
          ),
          calendarBooksRepositoryProvider.overrideWithValue(
            _ThrowingCalendarBooksRepository(calendarDb),
          ),
        ],
      );

      await _expandSection(tester, '同步对象');
      await _tapText(tester, '立即清理失效镜像');
      expect(find.textContaining('镜像清理失败'), findsOneWidget);
      expect(find.textContaining('gap3-mirror-repo-down'), findsOneWidget);

      await _tapText(tester, '完全重置已同步的 Outlook 日历本');
      expect(find.text('完全重置 Outlook 日历本'), findsOneWidget);
      await _tapDialogButton(tester, '确认重置');
      expect(find.textContaining('重置 Outlook 日历本失败'), findsOneWidget);
      expect(find.textContaining('gap3-calendar-repo-down'), findsOneWidget);
    },
  );

  test(
    'default diagnostics writer writes the selected report path',
    () async {
      final reportDir = await Directory.systemTemp.createTemp(
        'flowplanv2-gap3-outlook-diagnostics-',
      );
      final reportFile = File(
        '${reportDir.path}${Platform.pathSeparator}report.md',
      );
      addTearDown(() async {
        for (var i = 0; i < 5; i += 1) {
          try {
            if (await reportDir.exists()) {
              await reportDir.delete(recursive: true);
            }
            return;
          } on FileSystemException {
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
        }
      });

      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container
          .read(outlookDiagnosticsReportWriterProvider)
          .call(reportFile.path, '# FlowPlanV2 Outlook diagnostics');

      expect(reportFile.existsSync(), isTrue);
      expect(reportFile.readAsStringSync(), contains('FlowPlanV2 Outlook'));
    },
  );
}

Map<String, Object> _zeroChangeLastSyncPreferences() {
  final attemptedAt = DateTime.utc(2026, 6, 8, 13, 20);
  return <String, Object>{
    ...outlookAuthPreferences(
      syncMode: OutlookSyncMode.bidirectional,
      grantedMode: OutlookSyncMode.bidirectional,
      scope: 'Calendars.Read Calendars.ReadWrite offline_access',
    ),
    'outlook_last_sync': attemptedAt.toIso8601String(),
    'outlook_last_sync_report_time': attemptedAt.toIso8601String(),
    'outlook_last_sync_report_status': 'success',
    'outlook_last_sync_report_mode': OutlookSyncMode.bidirectional.name,
    'outlook_last_sync_report_calendar_books': 2,
    'outlook_last_sync_report_downloaded': 0,
    'outlook_last_sync_report_mirrored_created': 0,
    'outlook_last_sync_report_mirrored_updated': 0,
    'outlook_last_sync_report_mirrored_deleted': 0,
    'outlook_last_sync_report_mirrored_conflicted': 0,
    'outlook_last_sync_report_calendar_details': jsonEncode(
      <Map<String, Object?>>[
        <String, Object?>{
          'remote_calendar_id': 'remote-zero-a',
          'local_calendar_id': 11,
          'calendar_name': 'Zero Change A',
          'color_hex': '#0078D4',
          'downloaded': 0,
        },
        <String, Object?>{
          'remote_calendar_id': 'remote-zero-b',
          'local_calendar_id': 12,
          'calendar_name': 'Zero Change B',
          'color_hex': '#43A047',
          'downloaded': 0,
        },
      ],
    ),
    'outlook_last_sync_report_task_mirror_details': jsonEncode(
      <Map<String, Object?>>[
        <String, Object?>{
          'local_task_list_id': 1,
          'task_list_name': 'Zero Mirror',
          'remote_calendar_id': 'mirror-zero',
          'remote_calendar_name': 'FlowPlanV2 Zero Mirror',
          'created': 0,
          'updated': 0,
          'deleted': 0,
          'conflicted': 0,
        },
      ],
    ),
  };
}

Map<String, Object> _tiedLastSyncPreferences() {
  final attemptedAt = DateTime.utc(2026, 6, 8, 14, 5);
  return <String, Object>{
    ...outlookAuthPreferences(
      syncMode: OutlookSyncMode.bidirectional,
      grantedMode: OutlookSyncMode.bidirectional,
      scope: 'Calendars.Read Calendars.ReadWrite offline_access',
    ),
    'outlook_last_sync': attemptedAt.toIso8601String(),
    'outlook_last_sync_report_time': attemptedAt.toIso8601String(),
    'outlook_last_sync_report_status': 'success',
    'outlook_last_sync_report_mode': OutlookSyncMode.bidirectional.name,
    'outlook_last_sync_report_calendar_books': 2,
    'outlook_last_sync_report_downloaded': 4,
    'outlook_last_sync_report_mirrored_created': 2,
    'outlook_last_sync_report_mirrored_updated': 2,
    'outlook_last_sync_report_mirrored_deleted': 0,
    'outlook_last_sync_report_mirrored_conflicted': 0,
    'outlook_last_sync_report_calendar_details': jsonEncode(
      <Map<String, Object?>>[
        <String, Object?>{
          'remote_calendar_id': 'beta-calendar',
          'local_calendar_id': 22,
          'calendar_name': 'Beta Calendar',
          'color_hex': '#43A047',
          'downloaded': 2,
        },
        <String, Object?>{
          'remote_calendar_id': 'alpha-calendar',
          'local_calendar_id': 21,
          'calendar_name': 'Alpha Calendar',
          'color_hex': '#0078D4',
          'downloaded': 2,
        },
      ],
    ),
    'outlook_last_sync_report_task_mirror_details': jsonEncode(
      <Map<String, Object?>>[
        <String, Object?>{
          'local_task_list_id': 2,
          'task_list_name': 'Beta Mirror',
          'remote_calendar_id': 'beta-mirror',
          'remote_calendar_name': 'FlowPlanV2 Beta Mirror',
          'created': 1,
          'updated': 1,
          'deleted': 0,
          'conflicted': 0,
        },
        <String, Object?>{
          'local_task_list_id': 1,
          'task_list_name': 'Alpha Mirror',
          'remote_calendar_id': 'alpha-mirror',
          'remote_calendar_name': 'FlowPlanV2 Alpha Mirror',
          'created': 2,
          'updated': 0,
          'deleted': 0,
          'conflicted': 0,
        },
      ],
    ),
  };
}

Future<_ServerManagedHarness> _pumpServerManagedOutlookSettings(
  WidgetTester tester, {
  List<Map<String, Object?>>? runs,
  List<Map<String, Object?>>? recentRuns,
}) async {
  final db = createTestDatabase();
  final clientApi = _Gap3ClientApi(
    db,
    runs: runs,
    recentRuns: recentRuns,
  );
  final reminderService = _Gap3ReminderService(db);

  tester.view.physicalSize = const Size(900, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpOutlookSettingFrames(tester);
    reminderService.dispose();
    await db.close();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        databaseProvider.overrideWithValue(db),
        clientApiProvider.overrideWith((ref) async => clientApi),
        reminderServiceProvider.overrideWithValue(reminderService),
      ],
      child: const MaterialApp(
        home: OutlookSettingsPage(),
      ),
    ),
  );
  await pumpOutlookSettingFrames(tester);
  return _ServerManagedHarness(
    clientApi: clientApi,
  );
}

class _ServerManagedHarness {
  const _ServerManagedHarness({
    required this.clientApi,
  });

  final _Gap3ClientApi clientApi;
}

class _Gap3ClientApi extends ClientApi {
  _Gap3ClientApi(
    AppDatabase db, {
    List<Map<String, Object?>>? runs,
    List<Map<String, Object?>>? recentRuns,
  })  : _runs = runs ?? <Map<String, Object?>>[_runLog()],
        _recentRuns = recentRuns ?? const <Map<String, Object?>>[],
        super(_mockApiClient(db));

  final List<Map<String, Object?>> _runs;
  final List<Map<String, Object?>> _recentRuns;
  var adminRunsCalls = 0;
  var adminDiagnosticsCalls = 0;

  @override
  Future<Map<String, dynamic>> adminOutlookRuns() async {
    adminRunsCalls++;
    return <String, dynamic>{'runs': _runs};
  }

  @override
  Future<Map<String, dynamic>> adminOutlookDiagnostics() async {
    adminDiagnosticsCalls++;
    return <String, dynamic>{
      'fieldCoverage': <String, Object?>{
        'eventCount': 7,
        'missingTitle': 1,
        'missingLocation': 2,
        'missingBodyPreview': 3,
        'missingOrganizer': 4,
      },
      'recentRuns': _recentRuns,
    };
  }
}

class _ThrowingTaskMirrorRepository extends OutlookTaskMirrorRepository {
  _ThrowingTaskMirrorRepository(super.db);

  @override
  Future<Map<int, OutlookTaskMirrorBinding>> loadTaskMirrorBindings() {
    throw StateError('gap3-mirror-repo-down');
  }

  @override
  Future<OutlookTaskMirrorBinding?> getTaskMirrorBinding(int taskId) {
    throw StateError('gap3-mirror-repo-down');
  }
}

class _ThrowingCalendarBooksRepository extends CalendarBooksRepository {
  _ThrowingCalendarBooksRepository(super.db);

  @override
  Future<List<EventCalendar>> getEventCalendarsBySource(String source) {
    throw StateError('gap3-calendar-repo-down');
  }
}

class _Gap3ReminderService extends ReminderService {
  _Gap3ReminderService(AppDatabase db)
      : super(
          database: db,
          defaultEventReminderMinutes: () => 0,
        );
}

OutlookFieldConflictSummary _conflictSummary({
  required int taskId,
  required String taskSummary,
  required OutlookTaskMirrorConflictState state,
  bool canPushLocal = false,
  bool canPullRemote = false,
  bool canRecreateRemote = false,
  bool canDetachMirror = false,
}) {
  return OutlookFieldConflictSummary(
    taskId: taskId,
    taskSummary: taskSummary,
    taskListName: 'Gap3 List',
    remoteCalendarName: 'Gap3 Mirror',
    conflictState: state,
    changedFields: const <String>['标题'],
    detail: 'gap3 conflict detail',
    canPushLocal: canPushLocal,
    canPullRemote: canPullRemote,
    canRecreateRemote: canRecreateRemote,
    canDetachMirror: canDetachMirror,
  );
}

Map<String, Object?> _runLog({
  String triggerSource = 'worker-gap3-manual',
  String status = 'failed',
  int calendarCount = 3,
  int eventUpserts = 5,
  int eventDeletes = 1,
}) {
  return <String, Object?>{
    'triggerSource': triggerSource,
    'status': status,
    'startedAt': '2026-06-10T08:30:00Z',
    'calendarCount': calendarCount,
    'eventUpserts': eventUpserts,
    'eventDeletes': eventDeletes,
    'errorMessage': status == 'failed' ? 'gap3 Microsoft 429' : '',
    'metadata': <String, Object?>{
      'fieldStats': <String, Object?>{
        'totalEvents': 7,
        'removedEvents': 1,
        'privateEvents': 1,
        'missingSubject': 1,
        'missingLocation': 2,
        'missingBodyPreview': 3,
        'missingOrganizer': 4,
        'recurrenceFallbacks': 1,
        'masterLookupFailures': 1,
      },
      'replay': <String, Object?>{
        'calendarBooks': 3,
        'calendarEvents': 5,
        'changes': 6,
      },
      'calendars': <Map<String, Object?>>[
        <String, Object?>{
          'name': 'Primary',
          'pageCount': 2,
          'eventCount': 5,
        },
        <String, Object?>{
          'name': 'Team',
          'pageCount': 1,
          'eventCount': 2,
        },
      ],
      'graphEventSamples': <Map<String, Object?>>[
        _graphSample(id: 'evt-gap3', subject: 'Gap3 sample'),
      ],
      'recurrenceFallbackSamples': <Map<String, Object?>>[
        _graphSample(id: 'occ-gap3', subject: 'Occurrence sample'),
      ],
    },
  };
}

Map<String, Object?> _graphSample({
  required String id,
  required String subject,
}) {
  return <String, Object?>{
    'id': id,
    'subject': subject,
    'location': 'Room 42',
    'bodyPreview': 'preview',
    'organizer': 'owner@example.com',
    'attendees': 2,
    'start': '2026-06-10T09:00:00Z',
    'end': '2026-06-10T10:00:00Z',
    'sensitivity': 'normal',
    'showAs': 'busy',
    'type': 'singleInstance',
    'removed': false,
    'mappedPayload': <String, Object?>{
      'summary': subject,
      'source': 'outlook',
    },
  };
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final button = _buttonWithText(text);
  final target = button?.first ?? find.text(text).first;
  await _bringIntoView(tester, target);
  await pumpOutlookSettingFrames(tester, frames: 2);
  await tester.tap(target);
  await pumpOutlookSettingFrames(tester);
}

Future<void> _tapTextContaining(WidgetTester tester, String text) async {
  final finder = find.textContaining(text).first;
  final button = find.ancestor(
    of: finder,
    matching: find.byWidgetPredicate(
      (widget) =>
          widget is TextButton ||
          widget is ElevatedButton ||
          widget is FilledButton ||
          widget is OutlinedButton,
    ),
  );
  final target = button.evaluate().isNotEmpty ? button.first : finder;
  await _bringIntoView(tester, target);
  await pumpOutlookSettingFrames(tester, frames: 2);
  await tester.tap(target);
  await pumpOutlookSettingFrames(tester);
}

Finder? _buttonWithText(String text) {
  for (final finder in <Finder>[
    find.widgetWithText(TextButton, text),
    find.widgetWithText(ElevatedButton, text),
    find.widgetWithText(FilledButton, text),
    find.widgetWithText(OutlinedButton, text),
  ]) {
    if (finder.evaluate().isNotEmpty) {
      return finder;
    }
  }
  return null;
}

Future<void> _tapDialogButton(WidgetTester tester, String text) async {
  final textButton = find.widgetWithText(TextButton, text);
  final filledButton = find.widgetWithText(FilledButton, text);
  if (textButton.evaluate().isNotEmpty) {
    await tester.tap(textButton.last);
  } else {
    await tester.tap(filledButton.last);
  }
  await pumpOutlookSettingFrames(tester);
}

Future<void> _bringIntoView(WidgetTester tester, Finder finder) async {
  await Scrollable.ensureVisible(
    tester.element(finder),
    alignment: 0.35,
    duration: Duration.zero,
  );
  await tester.pump();
}

Future<void> _expandSection(WidgetTester tester, String title) async {
  final finder = find.text(title).first;
  await tester.ensureVisible(finder);
  await pumpOutlookSettingFrames(tester, frames: 2);
  await tester.tap(finder);
  await pumpOutlookSettingFrames(tester);
}

Future<void> _waitForTextContaining(
  WidgetTester tester,
  String text, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (find.textContaining(text).evaluate().isNotEmpty) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.textContaining(text), findsOneWidget);
}

ApiClient _mockApiClient(AppDatabase db) {
  return ApiClient(
    baseUri: Uri.parse('http://localhost:3202/api'),
    tokenStore: AuthTokenStore(db),
    httpClient: MockClient((request) async {
      return http.Response(jsonEncode(<String, Object?>{}), 500);
    }),
  );
}
