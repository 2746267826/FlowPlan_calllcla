library;

import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/web_app/flowplanv2_web_app.dart';
import 'package:flowplanv2/web_app/web_api_client.dart';
import 'package:flowplanv2/web_app/web_local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'dashboard retries after an API failure and uses open task fallback',
      (tester) async {
    final harness = await _pumpWebApp(
      tester,
      apiBuilder: (store) => _ResidualWebApiClient(store)
        ..failDashboardOnce = true
        ..dashboardMode = _DashboardMode.openTaskFallback,
    );

    expect(harness.api.getPaths, contains('/web/dashboard'));
    expect(find.byType(FilledButton), findsWidgets);

    await _tapFilledButtonIcon(tester, Icons.refresh);

    expect(
      harness.api.getPaths.where((path) => path == '/web/dashboard'),
      hasLength(2),
    );
    await _pumpFrames(tester, 12);
    expect(find.textContaining('Backlog fallback'), findsOneWidget);
  });

  testWidgets('tasks page searches, cancels create, and edits an existing task',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellTasks);

    await tester.enterText(find.byType(TextField).first, 'blocked');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpFrames(tester, 6);
    expect(harness.api.lastGetQuery('/web/tasks')['q'], 'blocked');

    await tester.tap(find.byKey(AppKeys.webTasksCreateButton));
    await _pumpFrames(tester, 4);
    await _tapDialogCancel(tester);
    expect(harness.api.postPaths, isNot(contains('/web/tasks')));

    await tester.tap(find.byType(TextButton).first);
    await _pumpFrames(tester, 4);
    final fields = _dialogFields();
    await tester.enterText(fields.at(0), 'Web task edited');
    await tester.enterText(fields.at(1), 'done');
    await _tapDialogSave(tester);

    expect(harness.api.patchPaths, contains('/web/tasks/task-1'));
    expect(harness.api.patchBodies['/web/tasks/task-1']!.single['title'],
        'Web task edited');
    expect(
        harness.api.patchBodies['/web/tasks/task-1']!.single['status'], 'done');
  });

  testWidgets('events page retries failures and switches calendar view queries',
      (tester) async {
    final harness = await _pumpWebApp(
      tester,
      apiBuilder: (store) =>
          _ResidualWebApiClient(store)..failEventsOnce = true,
    );
    await _openShellDestination(tester, AppKeys.webShellEvents);

    expect(harness.api.getPaths.where((path) => path == '/web/events'),
        hasLength(1));

    await _tapFilledButtonIcon(tester, Icons.refresh);
    expect(harness.api.lastGetQuery('/web/events')['view'], 'timeline');
    expect(find.text('Planning sync'), findsOneWidget);

    await _tapIcon(tester, Icons.view_week_outlined);
    expect(harness.api.lastGetQuery('/web/events')['view'], 'week');

    await _tapIcon(tester, Icons.calendar_view_month_outlined);
    expect(harness.api.lastGetQuery('/web/events')['view'], 'month');

    await _tapIcon(tester, Icons.table_rows_outlined);
    expect(harness.api.lastGetQuery('/web/events')['view'], 'list');
    expect(find.text('Planning sync'), findsOneWidget);

    await _tapIcon(tester, Icons.chevron_right);
    expect(harness.api.getQueries['/web/events']!.last['view'], 'list');
  });

  testWidgets(
      'tracking tabs load analytics, filters, pagination, and segment actions',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellTracking);

    expect(harness.api.getPaths, contains('/analytics/tracker-home'));
    expect(harness.api.getPaths, contains('/analytics/task-work-summary'));
    expect(find.text('Code editor'), findsOneWidget);
    expect(find.text('Deep work'), findsOneWidget);

    await _tapIcon(tester, Icons.timeline_outlined);
    expect(harness.api.getPaths, contains('/analytics/activity-heatmap'));
    expect(harness.api.getPaths, contains('/analytics/range-analysis'));
    expect(harness.api.lastGetQuery('/analytics/range-analysis')['bucket'],
        'hour');

    await _tapIcon(tester, Icons.keyboard_outlined);
    expect(harness.api.getPaths, contains('/analytics/input-heatmap'));
    expect(find.text('Ctrl+S'), findsOneWidget);
    expect(find.text('code.exe'), findsOneWidget);

    await _tapIcon(tester, Icons.subject_outlined);
    expect(harness.api.getPaths, contains('/analytics/activity-records'));
    expect(harness.api.getPaths, contains('/analytics/input-events'));

    final filterFields = find.byType(TextField);
    await tester.enterText(filterFields.at(0), 'code');
    await tester.enterText(filterFields.at(1), 'focus');
    await tester.enterText(filterFields.at(2), 'keyboard');
    await _tapIcon(tester, Icons.filter_alt_outlined);
    expect(
        harness.api.lastGetQuery('/analytics/activity-records')['processName'],
        'code');
    expect(harness.api.lastGetQuery('/analytics/input-events')['eventKind'],
        'keyboard');

    await tester.tap(find.byType(FilledButton).last);
    await _pumpFrames(tester, 8);
    expect(harness.api.lastGetQuery('/analytics/input-events')['offset'], '50');

    await _tapIcon(tester, Icons.psychology_alt_outlined);
    expect(harness.api.getPaths, contains('/activity-understanding/segments'));
    expect(find.text('Write coverage'), findsOneWidget);

    await _tapIcon(tester, Icons.auto_fix_high);
    expect(harness.api.postPaths, contains('/activity-understanding/build'));

    await tester.tap(find.widgetWithText(TextButton, '详情').last);
    await _pumpFrames(tester, 4);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Write coverage'), findsWidgets);
    await _tapDialogCancel(tester);

    await tester.tap(find.widgetWithText(TextButton, '确认').last);
    await _pumpFrames(tester, 8);
    expect(harness.api.postPaths,
        contains('/activity-understanding/segments/segment-1/confirm'));

    await tester.tap(find.widgetWithText(TextButton, '拒绝').last);
    await _pumpFrames(tester, 8);
    expect(harness.api.postPaths,
        contains('/activity-understanding/segments/segment-1/reject'));
  });

  testWidgets('drive empty root creates a server root', (tester) async {
    final harness = await _pumpWebApp(
      tester,
      apiBuilder: (store) => _ResidualWebApiClient(store)..driveRoots.clear(),
    );
    await _openShellDestination(tester, AppKeys.webShellDrive);

    expect(harness.api.getPaths, contains('/files/drive/roots'));
    expect(find.textContaining('Root'), findsWidgets);

    await _tapIcon(tester, Icons.create_new_folder_outlined);

    expect(harness.api.postPaths, contains('/files/roots'));
    expect(harness.api.driveRoots.single['rootUid'], 'web-root');
    expect(harness.api.getPaths.where((path) => path == '/files/drive/nodes'),
        hasLength(1));
  });

  testWidgets('reports page surfaces failed action status', (tester) async {
    final harness = await _pumpWebApp(
      tester,
      apiBuilder: (store) =>
          _ResidualWebApiClient(store)..failReportGeneration = true,
    );
    await _openShellDestination(tester, AppKeys.webShellReports);

    await _tapIcon(tester, Icons.auto_awesome);

    expect(harness.api.postPaths, contains('/reports/generate'));
    expect(find.textContaining('report boom'), findsOneWidget);
  });
}

Finder _dialogFields() {
  return find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );
}

Future<void> _tapDialogSave(WidgetTester tester) async {
  final save = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(FilledButton),
  );
  expect(save, findsOneWidget);
  await tester.tap(save);
  await _pumpFrames(tester, 8);
}

Future<void> _tapDialogCancel(WidgetTester tester) async {
  final cancel = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextButton),
  );
  expect(cancel, findsOneWidget);
  await tester.tap(cancel);
  await _pumpFrames(tester, 4);
}

Future<void> _tapFilledButtonIcon(WidgetTester tester, IconData icon) async {
  final button = find.widgetWithIcon(FilledButton, icon).first;
  await tester.ensureVisible(button);
  await tester.tap(button);
  await _pumpFrames(tester, 8);
}

Future<void> _tapIcon(
  WidgetTester tester,
  IconData icon, {
  int index = 0,
}) async {
  final finder = find.byIcon(icon).at(index);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _pumpFrames(tester, 8);
}

Future<void> _openShellDestination(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await _pumpFrames(tester, 8);
}

Future<_WebAppHarness> _pumpWebApp(
  WidgetTester tester, {
  _ResidualWebApiClient Function(WebLocalStore store)? apiBuilder,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({
    'web.server.base_url': 'http://localhost:3202/api',
    'web.user_id': 'web-user',
    'web.device_id': 'web-device',
  });
  final store = await WebLocalStore.load();
  final api = apiBuilder?.call(store) ?? _ResidualWebApiClient(store);

  await tester.pumpWidget(
    FlowPlanV2WebApp(
      store: store,
      apiClientFactory: (_) => api,
    ),
  );
  await _pumpFrames(tester, 8);
  return _WebAppHarness(store: store, api: api);
}

Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i += 1) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
}

class _WebAppHarness {
  const _WebAppHarness({
    required this.store,
    required this.api,
  });

  final WebLocalStore store;
  final _ResidualWebApiClient api;
}

enum _DashboardMode { normal, openTaskFallback }

class _ResidualWebApiClient extends WebApiClient {
  _ResidualWebApiClient(super.store)
      : super(
          httpClient: MockClient(
            (_) async => http.Response('{"ok":false}', 500),
          ),
        );

  final getPaths = <String>[];
  final getQueries = <String, List<Map<String, String?>>>{};
  final postPaths = <String>[];
  final postBodies = <String, List<Map<String, dynamic>>>{};
  final patchPaths = <String>[];
  final patchBodies = <String, List<Map<String, dynamic>>>{};
  final putPaths = <String>[];

  bool failDashboardOnce = false;
  bool failEventsOnce = false;
  bool failReportGeneration = false;
  _DashboardMode dashboardMode = _DashboardMode.normal;

  late final DateTime today = DateTime.now();

  final driveRoots = <Map<String, dynamic>>[
    {
      'id': 'root-1',
      'rootUid': 'web-root',
      'name': 'Server drive',
    },
  ];

  String todayAt({required int hour}) {
    return DateTime(today.year, today.month, today.day, hour).toIso8601String();
  }

  Map<String, String?> lastGetQuery(String path) {
    final entries = getQueries[path];
    return entries == null || entries.isEmpty ? const {} : entries.last;
  }

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String?> query = const {},
  }) async {
    getPaths.add(path);
    getQueries.putIfAbsent(path, () => []).add(query);
    switch (path) {
      case '/client/bootstrap':
        return {
          'serverTime': '2026-06-10T04:00:00.000Z',
          'device': {'clientDeviceId': store.deviceId},
        };
      case '/web/dashboard':
        if (failDashboardOnce) {
          failDashboardOnce = false;
          throw StateError('dashboard boom');
        }
        return _dashboard();
      case '/web/tasks':
        return {
          'items': [
            {
              'id': 'task-1',
              'title': 'Web task',
              'status': 'todo',
              'dueAt': todayAt(hour: 17),
              'location': 'Remote',
              'payload': {'notes': 'Original notes'},
            },
          ],
        };
      case '/web/events':
        if (failEventsOnce) {
          failEventsOnce = false;
          throw StateError('events boom');
        }
        return {
          'items': [
            {
              'id': 'event-1',
              'title': 'Planning sync',
              'startAt': todayAt(hour: 10),
              'endAt': todayAt(hour: 11),
              'location': 'Room 3',
              'status': 'confirmed',
              'notes': 'Initial notes',
              'payload': {
                'isBlock': true,
                'description': 'Payload note',
              },
            },
          ],
        };
      case '/analytics/tracker-home':
        return {
          'daySummary': {
            'insights': {
              'recordCount': 8,
              'totalMinutes': 90,
              'totalKeys': 120,
              'totalClicks': 14,
            },
            'previewRecords': [_activityRecord()],
          },
          'activityHeatmap': {
            'buckets': [
              {
                'bucketStart': todayAt(hour: 0),
                'totalMinutes': 90,
              },
            ],
          },
          'topApps': {
            'items': [
              {'name': 'Code editor', 'totalMinutes': 80, 'recordCount': 4},
            ],
          },
          'topCategories': {
            'items': [
              {'name': 'Deep work', 'totalMinutes': 75, 'recordCount': 3},
            ],
          },
        };
      case '/analytics/task-work-summary':
        return {
          'items': [
            {'taskTitle': 'Coverage task', 'totalMinutes': 42},
          ],
        };
      case '/analytics/activity-heatmap':
        return {
          'buckets': [
            {
              'bucketStart': todayAt(hour: 0),
              'totalMinutes': 45,
            },
          ],
        };
      case '/analytics/range-analysis':
        return {
          'insights': {
            'recordCount': 3,
            'totalMinutes': 45,
            'focusMinutes': 30,
            'productiveRecordCount': 2,
          },
          'sessions': [
            {
              'startTime': todayAt(hour: 9),
              'endTime': todayAt(hour: 10),
              'label': 'Focus block',
              'durationMinutes': 60,
              'processNames': ['code.exe', 'terminal.exe'],
            },
          ],
          'previewRecords': [_activityRecord()],
        };
      case '/analytics/input-heatmap':
        return {
          'buckets': [
            {
              'bucketStart': todayAt(hour: 9),
              'eventCount': 12,
              'keyboardEventCount': 7,
              'mouseButtonEventCount': 3,
              'wheelEventCount': 2,
            },
          ],
          'topKeys': [
            {'label': 'Ctrl+S', 'count': 5},
          ],
          'processIntensities': [
            {
              'processName': 'code.exe',
              'intensityScore': 0.8,
              'keyEvents': 7,
              'mouseButtonEvents': 3,
              'wheelEvents': 2,
              'mouseMoveEvents': 1,
              'activeMinutes': 20,
            },
          ],
          'mouseCounts': {
            'left': 3,
            'wheel_down': 2,
          },
        };
      case '/analytics/activity-records':
        return {
          'items': [_activityRecord()],
          'hasMore': true,
        };
      case '/analytics/input-events':
        return {
          'items': [
            {
              'occurredAt': todayAt(hour: 9),
              'metricCount': 5,
              'payload': {
                'process_name': 'code.exe',
                'event_kind': 'keyboard',
                'keyLabel': 'Ctrl+S',
                'metadata': {'eventCount': 5},
              },
            },
          ],
          'hasMore': true,
        };
      case '/activity-understanding/segments':
        return {
          'items': [
            {
              'id': 'segment-1',
              'startAt': todayAt(hour: 9),
              'endAt': todayAt(hour: 10),
              'title': 'Write coverage',
              'summary': 'coverage evidence',
              'primaryApp': 'Code editor',
              'primaryWindowTitle': 'flowplanv2 tests',
              'primaryFilePath': 'test/web_app',
              'category': 'focus',
              'status': 'candidate',
              'matchedTaskId': 'task-1',
              'confidence': 0.88,
              'evidence': [
                {'kind': 'window', 'summary': 'coverage evidence'}
              ],
            },
          ],
        };
      case '/reports':
        return {
          'reports': [
            {
              'id': 'report-1',
              'title': 'Daily draft',
              'reportType': 'daily',
              'status': 'draft',
              'summary': 'Draft summary',
              'contentMarkdown': 'Draft markdown',
            },
          ],
        };
      case '/diary':
        return {'diary': <Map<String, Object?>>[]};
      case '/weather/locations':
      case '/weather/summary':
      case '/push/channels':
      case '/push/deliveries':
        return {'items': <Map<String, Object?>>[]};
      case '/client/settings':
        return {'settings': <Map<String, Object?>>[]};
      case '/files/drive/roots':
        return {'roots': driveRoots};
      case '/files/drive/nodes':
        return {'nodes': <Map<String, Object?>>[]};
      default:
        return {'items': <Map<String, Object?>>[]};
    }
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic> body = const {},
  }) async {
    postPaths.add(path);
    postBodies.putIfAbsent(path, () => []).add(body);
    if (path.endsWith('/heartbeat')) {
      return {'serverTime': '2026-06-10T04:00:01.000Z'};
    }
    switch (path) {
      case '/web/tasks':
        return {
          'task': {'id': 'created-task', ...body},
        };
      case '/files/roots':
        driveRoots.add({'id': 'root-created', ...body});
        return {'root': driveRoots.last};
      case '/reports/generate':
        if (failReportGeneration) {
          throw StateError('report boom');
        }
        return {'ok': true};
      case '/activity-understanding/build':
      case '/activity-understanding/segments/segment-1/confirm':
      case '/activity-understanding/segments/segment-1/reject':
        return {'ok': true};
      default:
        return {'ok': true};
    }
  }

  @override
  Future<Map<String, dynamic>> patchJson(
    String path, {
    Map<String, dynamic> body = const {},
  }) async {
    patchPaths.add(path);
    patchBodies.putIfAbsent(path, () => []).add(body);
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, dynamic> body = const {},
  }) async {
    putPaths.add(path);
    return {'ok': true};
  }

  Map<String, dynamic> _dashboard() {
    if (dashboardMode == _DashboardMode.openTaskFallback) {
      return {
        'today': {
          'tasks': <Map<String, Object?>>[],
          'events': <Map<String, Object?>>[],
          'actualRecords': <Map<String, Object?>>[],
        },
        'lists': {
          'openTasks': [
            {'id': 'task-open', 'title': 'Backlog fallback', 'status': 'todo'},
          ],
          'reminders': <Map<String, Object?>>[],
        },
        'sync': {
          'pendingMutations': 0,
          'openConflicts': 0,
        },
      };
    }
    return {
      'today': {
        'current': {
          'title': 'Current focus',
          'startAt': todayAt(hour: 9),
          'endAt': todayAt(hour: 10),
          'location': 'Desk',
          'status': 'active',
        },
        'tasks': [
          {'id': 'task-1', 'title': 'Dashboard task', 'status': 'todo'},
        ],
        'events': <Map<String, Object?>>[],
        'actualRecords': <Map<String, Object?>>[],
      },
      'lists': {
        'openTasks': <Map<String, Object?>>[],
        'reminders': <Map<String, Object?>>[],
      },
      'sync': {
        'pendingMutations': 1,
        'openConflicts': 0,
      },
    };
  }

  Map<String, dynamic> _activityRecord() {
    return {
      'occurredAt': todayAt(hour: 9),
      'metricMinutes': 15,
      'payload': {
        'processName': 'code.exe',
        'category': 'focus',
        'windowTitle': 'flowplanv2 coverage',
      },
    };
  }
}
