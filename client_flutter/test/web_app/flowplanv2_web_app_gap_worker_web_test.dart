library;

import 'dart:typed_data';

import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/web_app/flowplanv2_web_app.dart';
import 'package:flowplanv2/web_app/web_api_client.dart';
import 'package:flowplanv2/web_app/web_local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'connection failure uses cached bootstrap and skips heartbeat without device id',
      (tester) async {
    final harness = await _pumpWebApp(
      tester,
      initialPreferences: {
        'web.server.base_url': 'http://localhost:3202/api',
        'web.user_id': 'web-user',
        'web.device_id': '',
        'web.last_bootstrap_json':
            '{"serverTime":"2026-06-10T01:02:03.000Z","device":{"clientDeviceId":"cached-device"}}',
      },
      configureApi: (api) => api.failBootstrap = true,
    );

    await _openShellDestination(tester, AppKeys.webShellSettings);

    expect(harness.api.getPaths, contains('/client/bootstrap'));
    expect(
      harness.api.postPaths.where((path) => path.contains('/heartbeat')),
      isEmpty,
    );
    expect(find.textContaining('2026-06-10T01:02:03.000Z'), findsOneWidget);
    expect(find.textContaining('服务端不可用'), findsWidgets);

    await tester.tap(find.byKey(AppKeys.webShellRefreshConnection));
    await _pumpFrames(tester, 8);

    expect(
      harness.api.getPaths.where((path) => path == '/client/bootstrap'),
      hasLength(greaterThanOrEqualTo(3)),
    );
    expect(
      harness.api.postPaths.where((path) => path.contains('/heartbeat')),
      isEmpty,
    );
  });

  testWidgets('event week and month day taps select a day and reload timeline',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellEvents);

    await _tapIcon(tester, Icons.view_week_outlined);
    final weekLoadCount = harness.api.getQueries['/web/events']!.length;
    await tester.tap(find.textContaining('Week-only sync').first);
    await _pumpFrames(tester, 8);

    expect(harness.api.getQueries['/web/events']!.last['view'], 'timeline');
    expect(harness.api.getQueries['/web/events']!.length, weekLoadCount + 1);
    expect(find.textContaining('Week-only sync'), findsOneWidget);

    await _tapIcon(tester, Icons.calendar_view_month_outlined);
    final monthLoadCount = harness.api.getQueries['/web/events']!.length;
    await tester.tap(find.textContaining('Month-only planning').first);
    await _pumpFrames(tester, 8);

    expect(harness.api.getQueries['/web/events']!.last['view'], 'timeline');
    expect(harness.api.getQueries['/web/events']!.length, monthLoadCount + 1);
    expect(find.textContaining('Month-only planning'), findsOneWidget);
  });

  testWidgets('tracking filters clear and day changes reset detail pagination',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellTracking);

    await _tapIcon(tester, Icons.subject_outlined);
    await _pumpFrames(tester, 8);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'meta-process');
    await tester.enterText(fields.at(1), 'meta-category');
    await tester.enterText(fields.at(2), 'keyboard');
    await _tapIcon(tester, Icons.filter_alt_outlined);

    expect(
      harness.api.lastGetQuery('/analytics/activity-records')['processName'],
      'meta-process',
    );
    expect(
      harness.api.lastGetQuery('/analytics/input-events')['eventKind'],
      'keyboard',
    );

    await tester.tap(find.widgetWithText(FilledButton, '下一页').first);
    await _pumpFrames(tester, 8);
    expect(
      harness.api.lastGetQuery('/analytics/activity-records')['offset'],
      '50',
    );

    await tester.tap(find.widgetWithText(TextButton, '清除'));
    await _pumpFrames(tester, 8);

    expect(
      harness.api.lastGetQuery('/analytics/activity-records')['processName'],
      '',
    );
    expect(
      harness.api.lastGetQuery('/analytics/input-events')['eventKind'],
      '',
    );

    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.chevron_right));
    await _pumpFrames(tester, 8);

    expect(
      harness.api.lastGetQuery('/analytics/activity-records')['offset'],
      '0',
    );
    expect(
      harness.api.lastGetQuery('/analytics/input-events')['offset'],
      '0',
    );
  });

  testWidgets('overview heatmap tap opens activity tab for the selected bucket',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellTracking);

    await tester.tap(find.text('15').first);
    await _pumpFrames(tester, 8);

    expect(harness.api.getPaths, contains('/analytics/range-analysis'));
    expect(
      harness.api.lastGetQuery('/analytics/range-analysis')['bucket'],
      'hour',
    );
    expect(find.textContaining('Meta session'), findsOneWidget);
  });

  testWidgets('drive download failures show status and snackbar',
      (tester) async {
    final harness = await _pumpWebApp(
      tester,
      configureApi: (api) => api.downloadMode = _DownloadMode.emptyChunks,
    );
    await _openShellDestination(tester, AppKeys.webShellDrive);

    await _tapIcon(tester, Icons.download);

    expect(
      harness.api.postPaths,
      contains('/files/drive/nodes/file-1/download-request'),
    );
    expect(find.textContaining('下载失败'), findsWidgets);
    expect(find.textContaining('未收到任何数据'), findsWidgets);
  });

  testWidgets('reports handle telegram config plus diary confirm and polish',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellReports);

    await _tapIcon(tester, Icons.send_outlined);
    final pushFields = _dialogFields();
    await tester.enterText(pushFields.at(0), 'telegram');
    await tester.enterText(pushFields.at(1), 'Team chat');
    await tester.enterText(pushFields.at(2), '');
    await tester.enterText(pushFields.at(3), 'bot-token');
    await tester.enterText(pushFields.at(4), 'chat-42');
    await _tapDialogSave(tester);

    final channelBody = harness.api.postBodies['/push/channels']!.single;
    expect(channelBody['channelType'], 'telegram');
    expect(channelBody['name'], 'Team chat');
    expect(channelBody['config'], {
      'botToken': 'bot-token',
      'chatId': 'chat-42',
    });

    await tester.tap(find.widgetWithText(TextButton, '确认').last);
    await _pumpFrames(tester, 8);
    expect(harness.api.postPaths, contains('/diary/diary-1/confirm'));

    await tester.tap(find.widgetWithText(TextButton, 'AI 润色').last);
    await _pumpFrames(tester, 8);
    expect(harness.api.postPaths, contains('/diary/diary-1/polish'));
    expect(find.textContaining('AI 润色'), findsWidgets);
  });

  testWidgets('markdown edit dialog cancel leaves report unchanged',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellReports);

    await tester.tap(find.widgetWithText(TextButton, '编辑').first);
    await _pumpFrames(tester, 4);
    await tester.enterText(_dialogFields().first, 'Canceled title');
    await _tapDialogCancel(tester);

    expect(harness.api.patchPaths, isNot(contains('/reports/report-1')));
    expect(harness.api.reports.single['title'], 'Daily draft');
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
  Map<String, Object> initialPreferences = const {
    'web.server.base_url': 'http://localhost:3202/api',
    'web.user_id': 'web-user',
    'web.device_id': 'web-device',
  },
  void Function(_GapWebApiClient api)? configureApi,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(initialPreferences);
  final store = await WebLocalStore.load();
  final api = _GapWebApiClient(store);
  configureApi?.call(api);

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
  final _GapWebApiClient api;
}

enum _DownloadMode { ok, emptyChunks }

class _GapWebApiClient extends WebApiClient {
  _GapWebApiClient(super.store);

  final getPaths = <String>[];
  final getQueries = <String, List<Map<String, String?>>>{};
  final postPaths = <String>[];
  final postBodies = <String, List<Map<String, dynamic>>>{};
  final patchPaths = <String>[];
  final patchBodies = <String, List<Map<String, dynamic>>>{};

  bool failBootstrap = false;
  _DownloadMode downloadMode = _DownloadMode.ok;

  late final DateTime today = DateTime.now();
  late final DateTime weekEventDay = today.add(const Duration(days: 2));
  late final DateTime monthEventDay = DateTime(today.year, today.month, 20);

  final reports = <Map<String, dynamic>>[
    {
      'id': 'report-1',
      'title': 'Daily draft',
      'reportType': 'daily',
      'status': 'draft',
      'contentMarkdown': 'Draft markdown',
    },
  ];

  final diary = <Map<String, dynamic>>[
    {
      'id': 'diary-1',
      'title': 'Daily diary',
      'entryDate': '2026-06-10',
      'status': 'draft',
      'contentMarkdown': 'Diary markdown',
    },
  ];

  String todayAt({required int hour}) {
    return DateTime(today.year, today.month, today.day, hour).toIso8601String();
  }

  String onDay(DateTime day, {required int hour}) {
    return DateTime(day.year, day.month, day.day, hour).toIso8601String();
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
        if (failBootstrap) {
          throw StateError('bootstrap boom');
        }
        return {
          'serverTime': '2026-06-10T04:00:00.000Z',
          'device': {'clientDeviceId': store.deviceId},
        };
      case '/web/dashboard':
        return {
          'today': {
            'tasks': <Map<String, Object?>>[],
            'events': <Map<String, Object?>>[],
            'actualRecords': <Map<String, Object?>>[],
          },
          'lists': {
            'openTasks': <Map<String, Object?>>[],
            'reminders': <Map<String, Object?>>[],
          },
          'sync': {
            'pendingMutations': 0,
            'openConflicts': 0,
          },
        };
      case '/web/tasks':
        return {'items': <Map<String, Object?>>[]};
      case '/web/events':
        return {
          'items': [
            {
              'id': 'event-today',
              'title': 'Today planning',
              'payload': {
                'start_at': todayAt(hour: 9),
                'end_at': todayAt(hour: 10),
                'description': 'Payload note',
              },
              'location': 'Desk',
              'status': 'confirmed',
            },
            {
              'id': 'event-week',
              'title': 'Week-only sync',
              'dtstart': onDay(weekEventDay, hour: 11),
              'dtend': onDay(weekEventDay, hour: 12),
              'location': 'Week room',
              'status': 'confirmed',
            },
            {
              'id': 'event-month',
              'title': 'Month-only planning',
              'payload': {
                'startTime': onDay(monthEventDay, hour: 14),
                'endTime': onDay(monthEventDay, hour: 15),
                'notes': 'Month payload note',
              },
              'location': 'Month room',
              'status': 'tentative',
            },
          ],
        };
      case '/analytics/tracker-home':
        return {
          'daySummary': {
            'insights': {
              'recordCount': '4',
              'totalMinutes': '45',
              'totalKeys': '30',
              'totalClicks': '9',
            },
            'previewRecords': [_activityRecord()],
          },
          'activityHeatmap': {
            'buckets': [
              {
                'bucketStart': todayAt(hour: 0),
                'totalMinutes': 15,
              },
            ],
          },
          'topApps': {'items': <Map<String, Object?>>[]},
          'topCategories': {'items': <Map<String, Object?>>[]},
        };
      case '/analytics/task-work-summary':
        return {'items': <Map<String, Object?>>[]};
      case '/analytics/activity-heatmap':
        return {
          'buckets': [
            {
              'bucketStart': todayAt(hour: 0),
              'totalMinutes': 20,
            },
          ],
        };
      case '/analytics/range-analysis':
        return {
          'insights': {
            'recordCount': '3',
            'totalMinutes': '20.8',
            'focusMinutes': '18',
            'productiveRecordCount': '2',
          },
          'sessions': [
            {
              'startTime': todayAt(hour: 9),
              'endTime': todayAt(hour: 10),
              'label': 'Meta session',
              'durationMinutes': 60,
              'processNames': ['meta-process', 'terminal.exe'],
            },
          ],
          'previewRecords': [_activityRecord()],
        };
      case '/analytics/input-heatmap':
        return {
          'buckets': <Map<String, Object?>>[],
          'topKeys': <Map<String, Object?>>[],
          'processIntensities': <Map<String, Object?>>[],
          'mouseCounts': {'wheel_up': '2', 'button': '1'},
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
              'metricCount': 7,
              'payload': {
                'metadata': {
                  'processName': 'meta-process',
                  'eventKind': 'keyboard',
                  'eventCount': 7,
                },
              },
            },
          ],
          'hasMore': true,
        };
      case '/activity-understanding/segments':
        return {'items': <Map<String, Object?>>[]};
      case '/files/drive/roots':
        return {
          'roots': [
            {
              'id': 'root-1',
              'rootUid': 'web-root',
              'name': 'Server drive',
            },
          ],
        };
      case '/files/drive/nodes':
        return {
          'nodes': [
            {
              'id': 'file-1',
              'name': 'Broken download.txt',
              'nodeType': 'file',
              'availability': 'ready',
              'sizeBytes': 12,
              'mimeType': 'text/plain',
            },
          ],
        };
      case '/files/download-sessions/download-file-1/range':
        if (downloadMode == _DownloadMode.emptyChunks) {
          return {'ok': true, 'chunks': <Map<String, Object?>>[]};
        }
        return _downloadRange('download data');
      case '/reports':
        return {'reports': reports};
      case '/reports/report-1':
        return {
          'report': reports.first,
          'entries': <Map<String, Object?>>[],
          'evidence': <Map<String, Object?>>[],
        };
      case '/diary':
        return {'diary': diary};
      case '/weather/locations':
      case '/weather/summary':
      case '/push/channels':
      case '/push/deliveries':
        return {'items': <Map<String, Object?>>[]};
      case '/client/settings':
        return {'settings': <Map<String, Object?>>[]};
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
      case '/files/drive/nodes/file-1/download-request':
        return {
          'ok': true,
          'downloadSession': {
            'sessionId': 'download-file-1',
            'totalBytes': 12,
            'chunkSize': 64,
          },
        };
      case '/push/channels':
      case '/diary/diary-1/confirm':
        return {'ok': true};
      case '/diary/diary-1/polish':
        return {'ok': true, 'llmApplied': true};
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

  Map<String, dynamic> _activityRecord() {
    return {
      'occurredAt': todayAt(hour: 9),
      'metricMinutes': '12.5',
      'payload': {
        'metadata': {
          'processName': 'meta-process',
          'category': 'meta-category',
          'windowTitle': 'Meta window title',
        },
      },
    };
  }

  Map<String, dynamic> _downloadRange(String text) {
    return {
      'ok': true,
      'chunks': [
        {
          'payloadBase64': encodeBytes(Uint8List.fromList(text.codeUnits)),
        },
      ],
    };
  }
}
