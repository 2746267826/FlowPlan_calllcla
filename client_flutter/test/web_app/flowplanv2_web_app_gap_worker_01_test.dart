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
  test('local store initializes defaults and clears optional values', () async {
    SharedPreferences.setMockInitialValues({});

    final store = await WebLocalStore.load();

    expect(store.deviceId, isNotEmpty);
    expect(store.userId, '00000000-0000-4000-8000-000000000001');
    expect(store.baseUrl, 'http://localhost:3202/api');
    expect(store.readLastBootstrap(), isNull);

    await store.setBaseUrl(' http://localhost:3000/api/ ');
    expect(store.baseUrl, 'http://localhost:3202/api');

    await store.setTokens(accessToken: 'access-token', refreshToken: 'refresh');
    expect(store.accessToken, 'access-token');
    expect(store.refreshToken, 'refresh');

    await store.setTokens(accessToken: '', refreshToken: null);
    expect(store.accessToken, isNull);
    expect(store.refreshToken, isNull);

    await store.setDeviceId('device-fixed');
    expect(store.deviceId, 'device-fixed');
  });

  test('local store reads valid bootstrap and ignores blank cached payload',
      () async {
    SharedPreferences.setMockInitialValues({
      'web.last_bootstrap_json': '',
      'web.ui_state_json': '{"tab":"reports"}',
    });

    final store = await WebLocalStore.load();

    expect(store.readLastBootstrap(), isNull);
    expect(store.uiStateJson, '{"tab":"reports"}');

    await store.setLastBootstrap({
      'serverTime': '2026-06-10T00:00:00.000Z',
      'device': {'clientDeviceId': 'device-from-cache'},
    });
    await store.setUiState({'tab': 'tracking'});

    expect(store.readLastBootstrap()?['serverTime'],
        '2026-06-10T00:00:00.000Z');
    expect(store.uiStateJson, '{"tab":"tracking"}');
  });

  testWidgets('tasks page searches edits existing item and cancels create',
      (tester) async {
    final harness = await _pumpWebApp(tester);

    await _openShellDestination(tester, AppKeys.webShellTasks);

    final search = find.byType(TextField).first;
    await tester.enterText(search, 'web');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpFrames(tester, 6);

    expect(harness.api.lastGetQuery('/web/tasks')['q'], 'web');

    await tester.tap(find.byType(TextButton).first);
    await _pumpFrames(tester, 4);
    final editFields = _dialogFields();
    await tester.enterText(editFields.at(0), 'Edited web task');
    await tester.enterText(editFields.at(1), 'done');
    await _tapDialogSave(tester);

    expect(harness.api.patchPaths, contains('/web/tasks/task-1'));
    expect(harness.api.tasks.single['title'], 'Edited web task');
    expect(harness.api.tasks.single['status'], 'done');

    await tester.tap(find.byKey(AppKeys.webTasksCreateButton));
    await _pumpFrames(tester, 4);
    await tester.enterText(_dialogFields().first, 'Canceled task');
    await _tapDialogCancel(tester);

    expect(harness.api.postPaths.where((path) => path == '/web/tasks'), isEmpty);
  });

  testWidgets('drive surfaces root empty search crumbs and download errors',
      (tester) async {
    final harness = await _pumpWebApp(
      tester,
      picker: _FakeFilePicker(
        FilePickerResult([
          PlatformFile(
            name: 'root-created.txt',
            size: 10,
            bytes: Uint8List.fromList('root upload'.codeUnits),
          ),
        ]),
      ),
      configureApi: (api) => api.driveRoots.clear(),
    );

    await _openShellDestination(tester, AppKeys.webShellDrive);

    expect(find.textContaining('Root'), findsWidgets);
    await _tapIcon(tester, Icons.upload_file);
    expect(harness.api.postPaths, contains('/files/roots'));
    expect(harness.api.postPaths, contains('/files/upload-sessions'));

    await tester.enterText(find.byType(TextField).first, 'report');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _pumpFrames(tester, 6);
    expect(harness.api.lastGetQuery('/files/drive/nodes')['q'], 'report');

    await _tapIcon(tester, Icons.folder_open);
    expect(harness.api.lastGetQuery('/files/drive/nodes')['parentId'],
        'folder-1');

    await tester.tap(find.widgetWithText(ActionChip, 'Root'));
    await _pumpFrames(tester, 6);
    expect(harness.api.lastGetQuery('/files/drive/nodes')['parentId'], isNull);

    harness.api.downloadMode = _DownloadMode.rejected;
    await _tapIcon(tester, Icons.download);
    expect(find.textContaining('policy'), findsWidgets);

    harness.api.downloadMode = _DownloadMode.missingSession;
    await _tapIcon(tester, Icons.download);
    expect(find.textContaining('ID'), findsWidgets);

    harness.api.downloadMode = _DownloadMode.rangeFailed;
    await _tapIcon(tester, Icons.download);
    expect(find.textContaining('range boom'), findsWidgets);
  });

  testWidgets('tracking details supports previous pages and segment actions',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellTracking);

    await _tapIcon(tester, Icons.subject_outlined);
    await tester.tap(find.byType(FilledButton).at(1));
    await _pumpFrames(tester, 8);
    await _pumpFrames(tester, 6);
    expect(harness.api.lastGetQuery('/analytics/activity-records')['offset'],
        '50');

    await tester.tap(find.byType(OutlinedButton).at(2));
    await _pumpFrames(tester, 8);
    await _pumpFrames(tester, 6);
    expect(
        harness.api.lastGetQuery('/analytics/activity-records')['offset'], '0');

    await tester.tap(find.byType(FilledButton).at(2));
    await _pumpFrames(tester, 8);
    await _pumpFrames(tester, 6);
    expect(harness.api.lastGetQuery('/analytics/input-events')['offset'], '50');

    await tester.tap(find.byType(OutlinedButton).at(3));
    await _pumpFrames(tester, 8);
    await _pumpFrames(tester, 6);
    expect(harness.api.lastGetQuery('/analytics/input-events')['offset'], '0');

    await _tapIcon(tester, Icons.psychology_alt_outlined);
    await tester.tap(find.byType(FilledButton).first);
    await _pumpFrames(tester, 8);
    expect(harness.api.postPaths, contains('/activity-understanding/build'));

    await _tapFirstButtonOpeningDialog(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    await _tapDialogCancel(tester);

    await _tapUntilPostPath(
      tester,
      harness.api,
      '/activity-understanding/segments/segment-1/confirm',
    );
    expect(harness.api.postPaths,
        contains('/activity-understanding/segments/segment-1/confirm'));
    expect(
      harness.api.postBodies['/activity-understanding/segments/segment-1/confirm']!
          .last['taskId'],
      'task-9',
    );

    await _tapUntilPostPath(
      tester,
      harness.api,
      '/activity-understanding/segments/segment-1/reject',
    );
    expect(harness.api.postPaths,
        contains('/activity-understanding/segments/segment-1/reject'));
  });

  testWidgets('reports and settings show action failure and login without user',
      (tester) async {
    final harness = await _pumpWebApp(tester);
    await _openShellDestination(tester, AppKeys.webShellReports);

    harness.api.failReportGenerate = true;
    await _tapIcon(tester, Icons.auto_awesome);
    expect(find.textContaining('generate boom'), findsOneWidget);

    await _tapIcon(tester, Icons.cloud_outlined);
    await _tapDialogCancel(tester);
    expect(harness.api.postPaths, isNot(contains('/weather/locations')));

    await _openShellDestination(tester, AppKeys.webShellSettings);
    harness.api.loginReturnsUser = false;
    await _tapIcon(tester, Icons.login);

    expect(harness.store.accessToken, 'access-token');
    expect(harness.store.refreshToken, 'refresh-token');
    expect(harness.store.userId, 'web-user');
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

Future<void> _tapFirstButtonOpeningDialog(WidgetTester tester) async {
  final count = find.byType(TextButton).evaluate().length;
  for (var index = 0; index < count; index += 1) {
    final finder = find.byType(TextButton).at(index);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await _pumpFrames(tester, 4);
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      return;
    }
  }
  fail('No visible TextButton opened an AlertDialog.');
}

Future<void> _tapUntilPostPath(
  WidgetTester tester,
  _Worker01WebApiClient api,
  String path,
) async {
  final count = find.byType(TextButton).evaluate().length;
  for (var index = 0; index < count; index += 1) {
    final before = api.postPaths.length;
    final finder = find.byType(TextButton).at(index);
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await _pumpFrames(tester, 8);
    if (api.postPaths.contains(path)) {
      return;
    }
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await _tapDialogCancel(tester);
    }
    if (api.postPaths.length > before) {
      continue;
    }
  }
  fail('No visible TextButton posted $path.');
}

Future<void> _openShellDestination(WidgetTester tester, Key key) async {
  await tester.tap(find.byKey(key));
  await _pumpFrames(tester, 8);
}

Future<_WebAppHarness> _pumpWebApp(
  WidgetTester tester, {
  _FakeFilePicker? picker,
  void Function(_Worker01WebApiClient api)? configureApi,
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
  final api = _Worker01WebApiClient(store);
  configureApi?.call(api);

  final previousPicker = _tryReadFilePicker();
  if (picker != null) {
    FilePicker.platform = picker;
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
  const _WebAppHarness({required this.store, required this.api});

  final WebLocalStore store;
  final _Worker01WebApiClient api;
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

class _Worker01WebApiClient extends WebApiClient {
  _Worker01WebApiClient(super.store);

  final getPaths = <String>[];
  final getQueries = <String, List<Map<String, String?>>>{};
  final postPaths = <String>[];
  final postBodies = <String, List<Map<String, dynamic>>>{};
  final patchPaths = <String>[];
  final patchBodies = <String, List<Map<String, dynamic>>>{};
  final putPaths = <String>[];
  final putBodies = <String, List<Map<String, dynamic>>>{};

  _DownloadMode downloadMode = _DownloadMode.ok;
  bool failReportGenerate = false;
  bool loginReturnsUser = true;

  late final DateTime today = DateTime.now();

  final tasks = <Map<String, dynamic>>[
    {
      'id': 'task-1',
      'title': 'Web task',
      'status': 'todo',
      'dueAt': '2026-06-10T17:00:00.000',
      'location': 'Desk',
      'payload': {'notes': 'Task notes'},
    },
  ];

  final driveRoots = <Map<String, dynamic>>[
    {'id': 'root-1', 'rootUid': 'web-root', 'name': 'Server drive'},
  ];

  final rootNodes = <Map<String, dynamic>>[
    {
      'id': 'folder-1',
      'name': 'Archive',
      'nodeType': 'folder',
      'availability': 'ready',
      'sizeBytes': 0,
    },
    {
      'id': 'file-1',
      'name': 'Project notes.md',
      'nodeType': 'file',
      'availability': 'ready',
      'sizeBytes': 16,
      'mimeType': 'text/markdown',
    },
  ];

  final folderNodes = <Map<String, dynamic>>[
    {
      'id': 'file-2',
      'name': 'Nested spec.txt',
      'nodeType': 'file',
      'availability': 'ready',
      'sizeBytes': 11,
      'mimeType': 'text/plain',
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
          'sync': {'pendingMutations': 0, 'openConflicts': 0},
        };
      case '/web/tasks':
        final q = (query['q'] ?? '').toString().toLowerCase();
        return {
          'items': [
            for (final task in tasks)
              if (q.isEmpty || '${task['title']}'.toLowerCase().contains(q))
                task,
          ],
        };
      case '/web/events':
        return {'items': <Map<String, Object?>>[]};
      case '/files/drive/roots':
        return {'roots': driveRoots};
      case '/files/drive/nodes':
        return {
          'nodes': query['parentId'] == 'folder-1' ? folderNodes : rootNodes,
        };
      case '/files/download-sessions/download-file-1/range':
        if (downloadMode == _DownloadMode.rangeFailed) {
          return {'ok': false, 'reason': 'range boom'};
        }
        return _downloadRange('hello from drive');
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
        return {'items': [_activityRecord()], 'hasMore': true};
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
        return {
          'items': [
            {
              'id': 'segment-1',
              'title': 'IDE implementation',
              'startAt': todayAt(hour: 9),
              'endAt': todayAt(hour: 10),
              'primaryApp': 'IDE',
              'primaryWindowTitle': 'worker test',
              'primaryFilePath': 'client_flutter/test/web_app',
              'category': 'coding',
              'status': 'draft',
              'matchedTaskId': 'task-9',
              'confidence': 0.88,
              'evidence': ['activity'],
              'reason': 'focused window',
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
      case '/web/tasks':
        tasks.add({'id': 'created-${tasks.length}', ...body});
        return {'task': tasks.last};
      case '/files/roots':
        driveRoots.add({'id': 'root-created', ...body});
        return {'root': driveRoots.last};
      case '/files/upload-sessions':
        return {
          'uploadSession': {
            'sessionId': 'upload-1',
            'expectedChunks': 1,
            'chunkSize': body['chunkSize'],
          },
        };
      case '/files/upload-sessions/upload-1/complete':
        return {'ok': true};
      case '/files/drive/nodes/file-1/download-request':
        if (downloadMode == _DownloadMode.rejected) {
          return {'ok': false, 'reason': 'policy'};
        }
        if (downloadMode == _DownloadMode.missingSession) {
          return {'ok': true, 'downloadSession': <String, Object?>{}};
        }
        return {
          'ok': true,
          'downloadSession': {
            'sessionId': 'download-file-1',
            'totalBytes': 16,
            'chunkSize': 64,
          },
        };
      case '/activity-understanding/build':
      case '/activity-understanding/segments/segment-1/reject':
        return {'ok': true};
      case '/activity-understanding/segments/segment-1/confirm':
        return {'ok': true};
      case '/reports/generate':
        if (failReportGenerate) {
          throw StateError('generate boom');
        }
        return {'ok': true};
      case '/auth/login':
        return {
          'accessToken': 'access-token',
          'refreshToken': 'refresh-token',
          if (loginReturnsUser) 'user': {'id': 'server-user'},
        };
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
    if (path == '/web/tasks/task-1') {
      tasks.first.addAll(body);
      return {'task': tasks.first};
    }
    return {'ok': true};
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
