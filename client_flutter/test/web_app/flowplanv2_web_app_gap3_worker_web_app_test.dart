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
  testWidgets('scheduled heartbeat failures are caught by the shell',
      (tester) async {
    final harness = await _pumpWebApp(tester);

    final initialHeartbeats = harness.api.heartbeatSources.length;
    harness.api.failNextTimerHeartbeat = true;

    await tester.pump(const Duration(seconds: 31));
    await tester.pump();

    expect(
      harness.api.heartbeatSources.skip(initialHeartbeats),
      contains('timer'),
    );

    await _openShellDestination(tester, AppKeys.webShellSettings);
    expect(harness.api.getPaths, contains('/client/settings'));
  });

  testWidgets('successful bootstrap skips heartbeat when device id is blank',
      (tester) async {
    final harness = await _pumpWebApp(
      tester,
      initialPreferences: {
        'web.server.base_url': 'http://localhost:3202/api',
        'web.user_id': 'web-user',
        'web.device_id': '',
      },
    );

    expect(harness.api.getPaths, contains('/client/bootstrap'));
    expect(harness.api.heartbeatSources, isEmpty);
  });

  testWidgets('events month controls move ranges and day taps reload timeline',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellEvents);

    final initialTimelineFrom = harness.api.lastGetQuery('/web/events')['from'];
    await _tapIcon(tester, Icons.chevron_right);
    expect(harness.api.lastGetQuery('/web/events')['view'], 'timeline');
    expect(
      harness.api.lastGetQuery('/web/events')['from'],
      isNot(initialTimelineFrom),
    );

    await _tapIcon(tester, Icons.chevron_left);
    expect(
        harness.api.lastGetQuery('/web/events')['from'], initialTimelineFrom);

    await _tapIcon(tester, Icons.calendar_view_month_outlined);
    expect(harness.api.lastGetQuery('/web/events')['view'], 'month');

    final initialFrom = harness.api.lastGetQuery('/web/events')['from'];
    await _tapIcon(tester, Icons.chevron_right);
    expect(harness.api.lastGetQuery('/web/events')['view'], 'month');
    expect(harness.api.lastGetQuery('/web/events')['from'], isNot(initialFrom));

    await _tapIcon(tester, Icons.chevron_left);
    expect(harness.api.lastGetQuery('/web/events')['from'], initialFrom);

    await tester.tap(find.textContaining('Month branch event').first);
    await _pumpFrames(tester, 8);

    expect(harness.api.lastGetQuery('/web/events')['view'], 'timeline');
  });

  testWidgets('drive root selection search breadcrumbs and byte labels reload',
      (tester) async {
    final harness = await _pumpWebApp(
      tester,
      configureApi: (api) => api.driveMode = _DriveMode.breadcrumbs,
    );
    await _openShellDestination(tester, AppKeys.webShellDrive);

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await _pumpFrames(tester, 2);
    await tester.tap(find.text('Archive root').last);
    await _pumpFrames(tester, 8);

    expect(harness.api.lastGetQuery('/files/drive/nodes')['rootId'], 'root-b');
    expect(find.text('2.0 KB'), findsOneWidget);
    expect(find.text('2.00 MB'), findsOneWidget);
    expect(find.text('2.00 GB'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'spec');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpFrames(tester, 8);
    expect(harness.api.lastGetQuery('/files/drive/nodes')['q'], 'spec');

    await _tapIcon(tester, Icons.folder_open);
    expect(
      harness.api.lastGetQuery('/files/drive/nodes')['parentId'],
      'folder-b',
    );

    await tester.tap(find.widgetWithText(ActionChip, 'Archive folder'));
    await _pumpFrames(tester, 8);
    expect(
      harness.api.lastGetQuery('/files/drive/nodes')['parentId'],
      'folder-b',
    );

    await tester.tap(find.widgetWithText(ActionChip, 'Root'));
    await _pumpFrames(tester, 8);
    expect(harness.api.lastGetQuery('/files/drive/nodes')['parentId'], isNull);
  });

  testWidgets('drive load failures surface status and can be retried',
      (tester) async {
    final harness = await _pumpWebApp(
      tester,
      configureApi: (api) => api.failDriveNodesOnce = true,
    );
    await _openShellDestination(tester, AppKeys.webShellDrive);

    expect(find.textContaining('drive nodes boom'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.refresh).last);
    await _pumpFrames(tester, 8);

    expect(
      harness.api.getPaths.where((path) => path == '/files/drive/nodes'),
      hasLength(2),
    );
  });

  testWidgets('drive image preview can hand off to download', (tester) async {
    final harness = await _pumpWebApp(
      tester,
      configureApi: (api) => api.driveMode = _DriveMode.imagePreview,
    );
    await _openShellDestination(tester, AppKeys.webShellDrive);

    await _tapIcon(tester, Icons.visibility_outlined);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(
      harness.api.postBodies['/files/drive/nodes/image-1/download-request']!
          .first['targetMode'],
      'browser_preview',
    );

    final download = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(FilledButton),
    );
    await tester.tap(download);
    await _pumpFrames(tester, 8);

    expect(
      harness.api.postBodies['/files/drive/nodes/image-1/download-request']!
          .last['targetMode'],
      'browser_download',
    );
    expect(
      harness.api.getPaths,
      contains('/files/download-sessions/download-image/range'),
    );
  });

  testWidgets('drive downloads handle fallback totals and failure branches',
      (tester) async {
    final harness = await _pumpWebApp(
      tester,
      configureApi: (api) => api.driveMode = _DriveMode.downloadFailures,
    );
    await _openShellDestination(tester, AppKeys.webShellDrive);

    await _tapIcon(tester, Icons.download, index: 0);
    expect(
      harness.api.lastGetQuery(
          '/files/download-sessions/download-fallback/range')['end'],
      '3',
    );

    await _tapIcon(tester, Icons.download, index: 1);
    expect(
      harness.api.postPaths,
      contains('/files/drive/nodes/rejected/download-request'),
    );
    expect(find.textContaining('\u4e0b\u8f7d\u5931\u8d25'), findsWidgets);

    await _tapIcon(tester, Icons.download, index: 2);
    expect(
      harness.api.postPaths,
      contains('/files/drive/nodes/missing-session/download-request'),
    );
    expect(find.textContaining('\u4e0b\u8f7d\u5931\u8d25'), findsWidgets);

    await _tapIcon(tester, Icons.download, index: 3);
    expect(
      harness.api.getPaths,
      contains('/files/download-sessions/download-range/range'),
    );
  });

  testWidgets(
      'tracking refresh resets detail offsets and renders helper labels',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellTracking);

    await _tapIcon(tester, Icons.keyboard_outlined);
    expect(harness.api.getPaths, contains('/analytics/input-heatmap'));

    await _tapIcon(tester, Icons.timeline_outlined);
    expect(harness.api.getPaths, contains('/analytics/range-analysis'));
    expect(find.text('\u670d\u52a1\u7aef\u5de5\u4f5c\u4f1a\u8bdd'),
        findsOneWidget);

    await _tapIcon(tester, Icons.subject_outlined);
    expect(
        harness.api.lastGetQuery('/analytics/activity-records')['offset'], '0');

    await tester.tap(find.byType(FilledButton).at(1));
    await _pumpFrames(tester, 8);
    expect(harness.api.lastGetQuery('/analytics/activity-records')['offset'],
        '50');

    await tester.tap(find.byIcon(Icons.refresh).last);
    await _pumpFrames(tester, 8);
    expect(
        harness.api.lastGetQuery('/analytics/activity-records')['offset'], '0');
    expect(harness.api.lastGetQuery('/analytics/input-events')['offset'], '0');
  });
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
    'web.last_bootstrap_json':
        '{"serverTime":"2026-06-10T01:02:03.000Z","device":{"clientDeviceId":"cached-device"}}',
  },
  void Function(_Gap3WebApiClient api)? configureApi,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(initialPreferences);
  final store = await WebLocalStore.load();
  final api = _Gap3WebApiClient(store);
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
  final _Gap3WebApiClient api;
}

enum _DriveMode { normal, breadcrumbs, imagePreview, downloadFailures }

class _Gap3WebApiClient extends WebApiClient {
  _Gap3WebApiClient(super.store);

  final getPaths = <String>[];
  final getQueries = <String, List<Map<String, String?>>>{};
  final postPaths = <String>[];
  final postBodies = <String, List<Map<String, dynamic>>>{};
  final putPaths = <String>[];

  var driveMode = _DriveMode.normal;
  var failNextTimerHeartbeat = false;
  var failDriveNodesOnce = false;

  late final DateTime today = DateTime.now();
  final heartbeatSources = <String>[];

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
        return {'items': _eventItems()};
      case '/files/drive/roots':
        return {'roots': _driveRoots()};
      case '/files/drive/nodes':
        if (failDriveNodesOnce) {
          failDriveNodesOnce = false;
          throw StateError('drive nodes boom');
        }
        return {'nodes': _driveNodes(query)};
      case '/files/download-sessions/download-image/range':
        return _downloadRange(_pngBytes);
      case '/files/download-sessions/download-fallback/range':
        return _downloadRange(Uint8List.fromList('data'.codeUnits));
      case '/files/download-sessions/download-range/range':
        return {'ok': false, 'reason': 'range failed'};
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
              {'bucketStart': todayAt(hour: 0), 'totalMinutes': 15},
            ],
          },
          'topApps': {
            'items': [
              {'name': 'Editor', 'totalMinutes': 25, 'recordCount': 2},
            ],
          },
          'topCategories': {
            'items': [
              {'name': 'Focus', 'totalMinutes': 20, 'recordCount': 1},
            ],
          },
        };
      case '/analytics/task-work-summary':
        return {
          'items': [
            {'taskTitle': 'Coverage task', 'totalMinutes': 18},
          ],
        };
      case '/analytics/activity-heatmap':
        return {
          'buckets': [
            {'bucketStart': todayAt(hour: 0), 'totalMinutes': 20},
          ],
        };
      case '/analytics/range-analysis':
        return {
          'insights': {
            'recordCount': '3',
            'totalMinutes': '20',
            'focusMinutes': '18',
            'productiveRecordCount': '2',
          },
          'sessions': [
            {
              'startTime': todayAt(hour: 9),
              'endTime': todayAt(hour: 10),
              'label': 'String process session',
              'durationMinutes': 60,
              'processNames': 'solo-process',
            },
          ],
          'previewRecords': [_activityRecord()],
        };
      case '/analytics/input-heatmap':
        return {
          'buckets': [
            {
              'bucketStart': todayAt(hour: 9),
              'eventCount': 13,
              'keyboardEventCount': 4,
              'mouseButtonEventCount': 3,
              'wheelEventCount': 2,
            },
          ],
          'topKeys': [
            {'label': 'Ctrl+P', 'count': 4},
          ],
          'processIntensities': [
            {
              'processName': 'editor.exe',
              'intensityScore': 0.7,
              'keyEvents': 4,
              'mouseButtonEvents': 3,
              'wheelEvents': 2,
              'mouseMoveEvents': 1,
              'activeMinutes': 11,
            },
          ],
          'mouseCounts': {
            'wheel': 2,
            'move': 1,
            'button': 3,
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
              'metricCount': 11,
              'payload': {
                'process_name': 'editor.exe',
                'event_kind': 'keyboard',
                'metadata': {'event_count': 11},
              },
            },
          ],
          'hasMore': true,
        };
      case '/activity-understanding/segments':
        return {'items': <Map<String, Object?>>[]};
      case '/reports':
        return {
          'reports': [
            {
              'id': 'report-1',
              'title': 'Daily draft',
              'reportType': 'daily',
              'status': 'draft',
              'contentMarkdown': 'Draft markdown',
            },
          ],
        };
      case '/diary':
      case '/weather/locations':
      case '/weather/summary':
      case '/push/channels':
      case '/push/deliveries':
        return {'items': <Map<String, Object?>>[]};
      case '/client/settings':
        return {
          'settings': [
            {
              'key': 'remote.theme',
              'scope': 'user',
              'version': 1,
              'updatedAt': '2026-06-10T00:00:00.000Z',
            },
          ],
        };
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
      final summary = body['networkSummary'];
      final source = summary is Map ? '${summary['source']}' : '';
      heartbeatSources.add(source);
      if (failNextTimerHeartbeat && source == 'timer') {
        failNextTimerHeartbeat = false;
        throw StateError('heartbeat timer boom');
      }
      return {'serverTime': '2026-06-10T04:00:01.000Z'};
    }
    switch (path) {
      case '/files/drive/nodes/image-1/download-request':
        return {
          'ok': true,
          'downloadSession': {
            'sessionId': 'download-image',
            'totalBytes': _pngBytes.length,
            'chunkSize': 64,
          },
        };
      case '/files/drive/nodes/fallback-total/download-request':
        return {
          'ok': true,
          'downloadSession': {
            'sessionId': 'download-fallback',
            'chunkSize': 64,
          },
        };
      case '/files/drive/nodes/rejected/download-request':
        return {'ok': false, 'reason': 'policy'};
      case '/files/drive/nodes/missing-session/download-request':
        return {'ok': true, 'downloadSession': <String, Object?>{}};
      case '/files/drive/nodes/range-fails/download-request':
        return {
          'ok': true,
          'downloadSession': {
            'sessionId': 'download-range',
            'totalBytes': 5,
            'chunkSize': 64,
          },
        };
      default:
        return {'ok': true};
    }
  }

  @override
  Future<Map<String, dynamic>> putJson(
    String path, {
    Map<String, dynamic> body = const {},
  }) async {
    putPaths.add(path);
    return {'ok': true};
  }

  List<Map<String, dynamic>> _eventItems() {
    final monthDay = DateTime(today.year, today.month, 15);
    return [
      {
        'id': 'event-month',
        'title': 'Month branch event',
        'payload': {
          'startTime': DateTime(monthDay.year, monthDay.month, monthDay.day, 10)
              .toIso8601String(),
          'endTime': DateTime(monthDay.year, monthDay.month, monthDay.day, 11)
              .toIso8601String(),
          'description': 'Month branch note',
        },
        'location': 'Month room',
        'status': 'confirmed',
      },
    ];
  }

  List<Map<String, dynamic>> _driveRoots() {
    if (driveMode == _DriveMode.breadcrumbs) {
      return [
        {'id': 'root-a', 'rootUid': 'root-a', 'name': 'Primary root'},
        {'id': 'root-b', 'rootUid': 'root-b', 'name': 'Archive root'},
      ];
    }
    return [
      {'id': 'root-a', 'rootUid': 'root-a', 'name': 'Primary root'},
    ];
  }

  List<Map<String, dynamic>> _driveNodes(Map<String, String?> query) {
    switch (driveMode) {
      case _DriveMode.breadcrumbs:
        if (query['parentId'] == 'folder-b') {
          return [
            {
              'id': 'nested-doc',
              'name': 'Nested spec.txt',
              'nodeType': 'file',
              'availability': 'ready',
              'sizeBytes': 512,
              'mimeType': 'text/plain',
            },
          ];
        }
        if (query['rootId'] == 'root-b') {
          return [
            {
              'id': 'folder-b',
              'name': 'Archive folder',
              'nodeType': 'folder',
              'availability': 'ready',
              'sizeBytes': 0,
            },
            {
              'id': 'kb-file',
              'name': 'Kilobytes.bin',
              'nodeType': 'file',
              'availability': 'ready',
              'sizeBytes': 2048,
              'mimeType': 'application/octet-stream',
            },
            {
              'id': 'mb-file',
              'name': 'Megabytes.bin',
              'nodeType': 'file',
              'availability': 'ready',
              'sizeBytes': 2 * 1024 * 1024,
              'mimeType': 'application/octet-stream',
            },
            {
              'id': 'gb-file',
              'name': 'Gigabytes.bin',
              'nodeType': 'file',
              'availability': 'ready',
              'sizeBytes': 2 * 1024 * 1024 * 1024,
              'mimeType': 'application/octet-stream',
            },
          ];
        }
        return <Map<String, dynamic>>[];
      case _DriveMode.imagePreview:
        return [
          {
            'id': 'image-1',
            'name': 'Pixel.png',
            'nodeType': 'file',
            'availability': 'ready',
            'sizeBytes': _pngBytes.length,
            'mimeType': 'image/png',
          },
        ];
      case _DriveMode.downloadFailures:
        return [
          {
            'id': 'fallback-total',
            'name': 'Fallback total.txt',
            'nodeType': 'file',
            'availability': 'ready',
            'sizeBytes': 4,
            'mimeType': 'text/plain',
          },
          {
            'id': 'rejected',
            'name': 'Rejected.txt',
            'nodeType': 'file',
            'availability': 'ready',
            'sizeBytes': 5,
            'mimeType': 'text/plain',
          },
          {
            'id': 'missing-session',
            'name': 'Missing session.txt',
            'nodeType': 'file',
            'availability': 'ready',
            'sizeBytes': 5,
            'mimeType': 'text/plain',
          },
          {
            'id': 'range-fails',
            'name': 'Range fails.txt',
            'nodeType': 'file',
            'availability': 'ready',
            'sizeBytes': 5,
            'mimeType': 'text/plain',
          },
        ];
      case _DriveMode.normal:
        return <Map<String, dynamic>>[];
    }
  }

  Map<String, dynamic> _activityRecord() {
    return {
      'occurredAt': todayAt(hour: 9),
      'metricMinutes': '12.5',
      'payload': {
        'metadata': {
          'processName': 'editor.exe',
          'category': 'focus',
          'windowTitle': 'Gap worker window',
        },
      },
    };
  }

  Map<String, dynamic> _downloadRange(Uint8List bytes) {
    return {
      'ok': true,
      'chunks': [
        {'payloadBase64': encodeBytes(bytes)},
      ],
    };
  }
}

final _pngBytes = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x04,
  0x00,
  0x00,
  0x00,
  0xB5,
  0x1C,
  0x0C,
  0x02,
  0x00,
  0x00,
  0x00,
  0x0B,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0xDA,
  0x63,
  0xFC,
  0xFF,
  0x1F,
  0x00,
  0x03,
  0x03,
  0x02,
  0x00,
  0xEF,
  0xBF,
  0xA7,
  0xDB,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);
