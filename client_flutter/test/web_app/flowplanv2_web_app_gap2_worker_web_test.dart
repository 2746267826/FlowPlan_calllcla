library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flowplanv2/core/ui/app_keys.dart';
import 'package:flowplanv2/web_app/flowplanv2_web_app.dart';
import 'package:flowplanv2/web_app/web_api_client.dart';
import 'package:flowplanv2/web_app/web_local_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
      'events toolbar refreshes moves across ranges and renders dense week',
      (tester) async {
    final harness = await _pumpWebApp(tester, width: 920);
    await _openShellDestination(tester, AppKeys.webShellEvents);

    final initialLoads = harness.api.getQueries['/web/events']!.length;
    await _tapIcon(tester, Icons.refresh, index: 1);
    expect(harness.api.getQueries['/web/events']!.length, initialLoads + 1);
    expect(harness.api.lastGetQuery('/web/events')['view'], 'timeline');

    await _tapIcon(tester, Icons.view_week_outlined);
    expect(harness.api.lastGetQuery('/web/events')['view'], 'week');
    expect(find.textContaining('+2'), findsOneWidget);

    final beforeMove = harness.api.lastGetQuery('/web/events')['from'];
    await _tapIcon(tester, Icons.chevron_left);
    expect(harness.api.lastGetQuery('/web/events')['view'], 'week');
    expect(harness.api.lastGetQuery('/web/events')['from'], isNot(beforeMove));

    await _tapIcon(tester, Icons.today);
    expect(harness.api.lastGetQuery('/web/events')['view'], 'week');

    await _tapIcon(tester, Icons.table_rows_outlined);
    expect(harness.api.lastGetQuery('/web/events')['view'], 'list');
    expect(find.textContaining('Payload dtstart event'), findsOneWidget);
  });

  testWidgets(
      'drive upload creates a missing root and chunks by fallback count',
      (tester) async {
    final bytes =
        Uint8List.fromList(List<int>.generate(800000, (i) => i % 251));
    final picker = _FakeFilePicker(
      FilePickerResult([
        PlatformFile(name: 'big-upload.bin', size: bytes.length, bytes: bytes),
      ]),
    );
    final harness = await _pumpWebApp(
      tester,
      filePicker: picker,
      configureApi: (api) => api.roots.clear(),
    );
    await _openShellDestination(tester, AppKeys.webShellDrive);

    await _tapIcon(tester, Icons.upload_file);

    expect(picker.pickCount, 1);
    expect(harness.api.postPaths, contains('/files/roots'));
    expect(harness.api.postPaths, contains('/files/upload-sessions'));
    expect(harness.api.putPaths, [
      '/files/upload-sessions/upload-fallback/chunks/0',
      '/files/upload-sessions/upload-fallback/chunks/1',
    ]);
    expect(harness.api.postPaths,
        contains('/files/upload-sessions/upload-fallback/complete'));
  });

  testWidgets(
      'drive preview handles empty files and binary nodes fall back to download',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellDrive);

    await _tapIcon(tester, Icons.visibility_outlined);
    expect(
      harness.api.postBodies['/files/drive/nodes/file-empty/download-request']!
          .single['targetMode'],
      'browser_preview',
    );
    expect(find.text('Empty note.txt'), findsWidgets);
    await _closeDialog(tester);

    await _tapIcon(tester, Icons.visibility_outlined, index: 1);
    expect(
      harness.api.postBodies['/files/drive/nodes/file-binary/download-request']!
          .single['targetMode'],
      'browser_download',
    );
  });

  testWidgets(
      'tracking day buttons refresh future panels and reset detail offsets',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellTracking);

    await _tapIcon(tester, Icons.subject_outlined);
    await tester.tap(find.byType(FilledButton).at(1));
    await _pumpFrames(tester, 8);
    expect(harness.api.lastGetQuery('/analytics/activity-records')['offset'],
        '50');

    await tester.tap(find.widgetWithIcon(OutlinedButton, Icons.chevron_left));
    await _pumpFrames(tester, 8);
    expect(
        harness.api.lastGetQuery('/analytics/activity-records')['offset'], '0');

    await _tapIcon(tester, Icons.dashboard_outlined);
    harness.api.failTrackerHome = true;
    await tester.tap(find.byIcon(Icons.refresh).last);
    await _pumpFrames(tester, 8);
    expect(find.textContaining('tracker home boom'), findsOneWidget);
  });

  testWidgets('reports action and settings login reload their async data',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellReports);

    final reportLoads =
        harness.api.getPaths.where((path) => path == '/reports').length;
    await _tapIcon(tester, Icons.auto_awesome);
    expect(
      harness.api.getPaths.where((path) => path == '/reports').length,
      reportLoads + 1,
    );

    await _openShellDestination(tester, AppKeys.webShellSettings);
    final settingsLoads =
        harness.api.getPaths.where((path) => path == '/client/settings').length;
    await _tapIcon(tester, Icons.login);
    expect(
      harness.api.getPaths.where((path) => path == '/client/settings').length,
      settingsLoads + 1,
    );
  });
}

Future<void> _closeDialog(WidgetTester tester) async {
  final close = find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextButton),
  );
  expect(close, findsOneWidget);
  await tester.tap(close);
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
  double width = 1400,
  _FakeFilePicker? filePicker,
  void Function(_Gap2WebApiClient api)? configureApi,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues({
    'web.server.base_url': 'http://localhost:3202/api',
    'web.user_id': 'web-user',
    'web.device_id': 'web-device',
  });
  final store = await WebLocalStore.load();
  final api = _Gap2WebApiClient(store);
  configureApi?.call(api);

  final previousPicker = _tryReadFilePicker();
  if (filePicker != null) {
    FilePicker.platform = filePicker;
    addTearDown(() {
      if (previousPicker != null) {
        FilePicker.platform = previousPicker;
      } else {
        FilePicker.platform = _FakeFilePicker(null);
      }
    });
  }

  await tester.pumpWidget(
    FlowPlanV2WebApp(
      store: store,
      apiClientFactory: (_) => api,
    ),
  );
  await _pumpFrames(tester, 8);
  return _WebAppHarness(store: store, api: api);
}

FilePicker? _tryReadFilePicker() {
  try {
    return FilePicker.platform;
  } on Object {
    return null;
  }
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
  final _Gap2WebApiClient api;
}

class _FakeFilePicker extends FilePicker {
  _FakeFilePicker(this.result);

  final FilePickerResult? result;
  int pickCount = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    @Deprecated(
      'allowCompression is deprecated and has no effect. Use compressionQuality instead.',
    )
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    pickCount += 1;
    expect(withData, isTrue);
    return result;
  }
}

enum _DownloadMode { ok, rejected, missingSession, rangeFailed }

enum _RootsMode { normal, emptyInitially }

class _Gap2WebApiClient extends WebApiClient {
  _Gap2WebApiClient(super.store);

  final getPaths = <String>[];
  final getQueries = <String, List<Map<String, String?>>>{};
  final postPaths = <String>[];
  final postBodies = <String, List<Map<String, dynamic>>>{};
  final putPaths = <String>[];
  final putBodies = <String, List<Map<String, dynamic>>>{};

  _DownloadMode downloadMode = _DownloadMode.ok;
  _RootsMode rootsMode = _RootsMode.normal;
  bool failTrackerHome = false;

  late final DateTime today = DateTime.now();

  late final roots = <Map<String, dynamic>>[
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
        return {
          'roots': rootsMode == _RootsMode.emptyInitially ? roots : roots,
        };
      case '/files/drive/nodes':
        return {
          'nodes': roots.isEmpty
              ? <Map<String, Object?>>[]
              : [
                  {
                    'id': 'file-empty',
                    'name': 'Empty note.txt',
                    'nodeType': 'file',
                    'availability': 'ready',
                    'sizeBytes': 0,
                    'mimeType': 'text/plain',
                  },
                  {
                    'id': 'file-binary',
                    'name': 'Archive.bin',
                    'nodeType': 'file',
                    'availability': 'ready',
                    'sizeBytes': 4,
                    'mimeType': 'application/octet-stream',
                  },
                  {
                    'id': 'file-text',
                    'name': 'Download me.txt',
                    'nodeType': 'file',
                    'availability': 'ready',
                    'sizeBytes': 12,
                    'mimeType': 'text/plain',
                  },
                ],
        };
      case '/files/download-sessions/download-file-empty/range':
        if (downloadMode == _DownloadMode.rangeFailed) {
          return {'ok': false, 'reason': 'range boom'};
        }
        return {'ok': true, 'chunks': <Map<String, Object?>>[]};
      case '/files/download-sessions/download-file-binary/range':
        if (downloadMode == _DownloadMode.rangeFailed) {
          return {'ok': false, 'reason': 'range boom'};
        }
        return _downloadRange('data');
      case '/files/download-sessions/download-file-text/range':
        if (downloadMode == _DownloadMode.rangeFailed) {
          return {'ok': false, 'reason': 'range boom'};
        }
        return _downloadRange('download ok');
      case '/analytics/tracker-home':
        if (failTrackerHome) {
          throw StateError('tracker home boom');
        }
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
          'topApps': {'items': <Map<String, Object?>>[]},
          'topCategories': {'items': <Map<String, Object?>>[]},
        };
      case '/analytics/task-work-summary':
      case '/analytics/activity-heatmap':
      case '/analytics/input-heatmap':
        return {'items': <Map<String, Object?>>[], 'buckets': []};
      case '/analytics/range-analysis':
        return {
          'insights': {
            'recordCount': '3',
            'totalMinutes': '20',
            'focusMinutes': '18',
            'productiveRecordCount': '2',
          },
          'sessions': <Map<String, Object?>>[],
          'previewRecords': [_activityRecord()],
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
                  'eventKind': 'wheel',
                  'eventCount': 7,
                },
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
        return {
          'diary': [
            {
              'id': 'diary-1',
              'title': 'Daily diary',
              'entryDate': '2026-06-10',
              'status': 'draft',
              'contentMarkdown': 'Diary markdown',
            },
          ],
        };
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
              'version': getPaths
                  .where((visited) => visited == '/client/settings')
                  .length,
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
      return {'serverTime': '2026-06-10T04:00:01.000Z'};
    }
    switch (path) {
      case '/files/roots':
        roots.add({'id': 'root-created', ...body});
        return {'root': roots.last};
      case '/files/upload-sessions':
        return {
          'uploadSession': {
            'sessionId': 'upload-fallback',
            'chunkSize': body['chunkSize'],
          },
        };
      case '/files/upload-sessions/upload-fallback/complete':
        return {'ok': true};
      case '/files/drive/nodes/file-empty/download-request':
        if (body['targetMode'] == 'browser_download') {
          if (downloadMode == _DownloadMode.rejected) {
            return {'ok': false, 'reason': 'policy'};
          }
          if (downloadMode == _DownloadMode.missingSession) {
            return {'ok': true, 'downloadSession': <String, Object?>{}};
          }
        }
        return {
          'ok': true,
          'downloadSession': {
            'sessionId': 'download-file-empty',
            'totalBytes': body['targetMode'] == 'browser_download' ? 12 : 0,
            'chunkSize': 64,
          },
        };
      case '/files/drive/nodes/file-binary/download-request':
        if (downloadMode == _DownloadMode.rejected) {
          return {'ok': false, 'reason': 'policy'};
        }
        if (downloadMode == _DownloadMode.missingSession) {
          return {'ok': true, 'downloadSession': <String, Object?>{}};
        }
        return {
          'ok': true,
          'downloadSession': {
            'sessionId': 'download-file-binary',
            'totalBytes': 4,
            'chunkSize': 64,
          },
        };
      case '/files/drive/nodes/file-text/download-request':
        if (downloadMode == _DownloadMode.rejected) {
          return {'ok': false, 'reason': 'policy'};
        }
        if (downloadMode == _DownloadMode.missingSession) {
          return {'ok': true, 'downloadSession': <String, Object?>{}};
        }
        return {
          'ok': true,
          'downloadSession': {
            'sessionId': 'download-file-text',
            'totalBytes': 12,
            'chunkSize': 64,
          },
        };
      case '/reports/generate':
        return {'ok': true};
      case '/auth/login':
        return {
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          'user': {'id': 'server-user'},
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
    putBodies.putIfAbsent(path, () => []).add(body);
    return {'ok': true};
  }

  List<Map<String, dynamic>> _eventItems() {
    final denseDay = today.add(const Duration(days: 1));
    return [
      for (var i = 0; i < 8; i += 1)
        {
          'id': 'dense-$i',
          'title': 'Dense event $i',
          'startAt': DateTime(denseDay.year, denseDay.month, denseDay.day, 8, i)
              .toIso8601String(),
          'endAt': DateTime(denseDay.year, denseDay.month, denseDay.day, 9, i)
              .toIso8601String(),
          'location': 'Room $i',
          'status': 'confirmed',
        },
      {
        'id': 'payload-dt',
        'title': 'Payload dtstart event',
        'payload': {
          'dtstart': todayAt(hour: 11),
          'dtend': todayAt(hour: 12),
          'description': 'Payload dtend note',
        },
        'location': 'Payload room',
        'status': 'confirmed',
      },
    ];
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
